extends Node3D

const DEFAULT_SERVER := "wss://apetag.onrender.com"

const ApeScript := preload("res://ape.gd")
const PlayerScript := preload("res://player.gd")
const VoiceScript := preload("res://voice.gd")

var mode := "tag"
var online := false
var my_id := 0
var it_id := 0
var caught := false
var player
var voice
var world: Node3D
var remotes := {}
var menu: CanvasLayer
var hud: CanvasLayer
var status: Label
var role: Label
var name_edit: LineEdit
var url_edit: LineEdit
var room_edit: LineEdit
var mode_opt: OptionButton
var send_t := 0.0
var tag_cd := 0.0

func _ready() -> void:
	if OS.get_name() == "Android":
		OS.request_permissions()
	_build_menu()

# ---------- UI helpers ----------
func _label(text: String, size := 28) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l

func _button(text: String, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 64)
	b.add_theme_font_size_override("font_size", 28)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

func _edit(text: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(0, 56)
	e.add_theme_font_size_override("font_size", 26)
	return e

func _build_menu() -> void:
	menu = CanvasLayer.new()
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.1, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	box.add_child(_label("APE TAG", 44))
	name_edit = _edit("Ape" + str(randi() % 1000))
	box.add_child(name_edit)
	url_edit = _edit(DEFAULT_SERVER)
	box.add_child(url_edit)
	room_edit = _edit("public")
	box.add_child(room_edit)
	mode_opt = OptionButton.new()
	mode_opt.custom_minimum_size = Vector2(0, 56)
	mode_opt.add_theme_font_size_override("font_size", 26)
	mode_opt.add_item("Tag")
	mode_opt.add_item("Horror")
	mode_opt.add_item("Sandbox")
	box.add_child(mode_opt)
	box.add_child(_button("Play online", _start.bind(true)))
	box.add_child(_button("Practice offline", _start.bind(false)))

func _start(is_online: bool) -> void:
	online = is_online
	mode = ["tag", "horror", "sandbox"][mode_opt.selected]
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = "Ape"
	var url := url_edit.text.strip_edges()
	var room_name := room_edit.text.strip_edges()
	if room_name == "":
		room_name = "public"
	menu.queue_free()
	_build_world()
	_build_player()
	_build_hud()
	voice = VoiceScript.new()
	add_child(voice)
	if online:
		voice.start()
		voice.chunk.connect(func(b: PackedByteArray): Net.send_bytes(b))
		Net.message.connect(_on_net)
		Net.voice.connect(_on_voice_in)
		Net.closed.connect(_on_closed)
		var join := {"t": "join", "name": nm.substr(0, 16), "mode": mode, "room": room_name}
		if Net.connect_to(url, join):
			status.text = "Connecting..."
		else:
			status.text = "Bad server address"
	else:
		status.text = "Practice mode (offline)"

# ---------- World ----------
func _box(pos: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	var b := StaticBody3D.new()
	b.position = pos
	b.rotation_degrees = rot
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mi.material_override = mat
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(mi)
	b.add_child(cs)
	world.add_child(b)

func _build_world() -> void:
	world = Node3D.new()
	add_child(world)
	var horror := mode == "horror"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03) if horror else Color(0.45, 0.72, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.28, 0.4) if horror else Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.12 if horror else 0.7
	if horror:
		env.fog_enabled = true
		env.fog_light_color = Color(0.02, 0.02, 0.04)
		env.fog_density = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	if not horror:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55, 30, 0)
		world.add_child(sun)
	var floor_col := Color(0.18, 0.2, 0.22) if horror else Color(0.3, 0.7, 0.35)
	var prop_col := Color(0.25, 0.22, 0.2) if horror else Color(0.9, 0.6, 0.2)
	_box(Vector3(0, -0.5, 0), Vector3(70, 1, 70), floor_col)
	for s in [-1.0, 1.0]:
		_box(Vector3(35.5 * s, 4, 0), Vector3(1, 10, 72), prop_col.darkened(0.3))
		_box(Vector3(0, 4, 35.5 * s), Vector3(72, 10, 1), prop_col.darkened(0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 22:
		var h := rng.randf_range(1.0, 6.0)
		var sz := Vector3(rng.randf_range(3, 7), h, rng.randf_range(3, 7))
		var p := Vector3(rng.randf_range(-28, 28), h / 2.0, rng.randf_range(-28, 28))
		_box(p, sz, prop_col.lerp(Color(0.5, 0.5, 0.9), rng.randf() * 0.4))
	for i in 5:
		var rp := Vector3(rng.randf_range(-24, 24), 1.2, rng.randf_range(-24, 24))
		_box(rp, Vector3(5, 0.5, 8), prop_col.lightened(0.2), Vector3(rng.randf_range(15, 25), rng.randf_range(0, 180), 0))

func _build_player() -> void:
	player = PlayerScript.new()
	player.position = Vector3(randf_range(-8, 8), 1.5, randf_range(-8, 8))
	player.spawn = player.position
	add_child(player)
	player.set_horror(mode == "horror")

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var size := get_viewport().get_visible_rect().size
	status = _label("", 24)
	status.position = Vector2(20, 12)
	hud.add_child(status)
	role = _label("", 34)
	role.position = Vector2(20, 48)
	hud.add_child(role)
	var rects: Array[Rect2] = []
	for i in 2:
		var pos := Vector2(30, size.y - 260) if i == 0 else Vector2(size.x - 260, size.y - 260)
		rects.append(Rect2(pos, Vector2(230, 230)))
		var pad := ColorRect.new()
		pad.color = Color(1, 1, 1, 0.18)
		pad.position = pos
		pad.size = Vector2(230, 230)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(pad)
		var l := _label("L" if i == 0 else "R", 64)
		l.position = pos + Vector2(90, 70)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(l)
	player.hand_rects = rects
	var ui: Array[Rect2] = []
	var exit_btn := _button("Exit", _exit_game, 130)
	exit_btn.position = Vector2(size.x - 150, 10)
	hud.add_child(exit_btn)
	ui.append(Rect2(exit_btn.position, Vector2(130, 64)))
	if online:
		var mic_btn := _button("Mic: ON", Callable(), 190)
		mic_btn.pressed.connect(func():
			voice.