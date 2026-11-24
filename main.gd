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
		mic_btn.pressed.connect(_toggle_mic.bind(mic_btn))
		mic_btn.position = Vector2(size.x - 210, 84)
		hud.add_child(mic_btn)
		ui.append(Rect2(mic_btn.position, Vector2(190, 64)))
	if mode == "sandbox":
		var b1 := _button("+ Block", _spawn_local.bind("block"), 180)
		b1.position = Vector2(size.x / 2.0 - 190, size.y - 84)
		hud.add_child(b1)
		ui.append(Rect2(b1.position, Vector2(180, 64)))
		var b2 := _button("+ Ball", _spawn_local.bind("ball"), 180)
		b2.position = Vector2(size.x / 2.0 + 10, size.y - 84)
		hud.add_child(b2)
		ui.append(Rect2(b2.position, Vector2(180, 64)))
	player.ui_rects = ui

func _toggle_mic(btn: Button) -> void:
	voice.enabled = not voice.enabled
	btn.text = "Mic: ON" if voice.enabled else "Mic: OFF"

func _exit_game() -> void:
	Net.close()
	get_tree().reload_current_scene()

# ---------- Sandbox props ----------
func _spawn_prop(kind: String, pos: Vector3) -> void:
	var b := RigidBody3D.new()
	b.position = pos
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(randf(), 0.7, 0.95)
	if kind == "ball":
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		mi.mesh = sm
		var ss := SphereShape3D.new()
		ss.radius = 0.4
		cs.shape = ss
		b.mass = 1.0
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9, 0.9, 0.9)
		mi.mesh = bm
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.9, 0.9, 0.9)
		cs.shape = bs
		b.mass = 3.0
	mi.material_override = mat
	b.add_child(mi)
	b.add_child(cs)
	world.add_child(b)

func _spawn_local(kind: String) -> void:
	var fwd: Vector3 = -player.global_transform.basis.z
	var pos: Vector3 = player.global_position + fwd * 2.5 + Vector3(0, 1.5, 0)
	_spawn_prop(kind, pos)
	if online:
		Net.send({"t": "spawn", "k": kind, "p": [pos.x, pos.y, pos.z]})

# ---------- Multiplayer ----------
func _add_remote(id: int, nm: String) -> void:
	if remotes.has(id) or id == my_id:
		return
	var a = ApeScript.new()
	add_child(a)
	a.build(Color.from_hsv(float((id * 37) % 100) / 100.0, 0.55, 0.65), nm)
	a.setup_voice()
	a.set_it(id == it_id)
	remotes[id] = a

func _remove_remote(id: int) -> void:
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)

func _refresh_status() -> void:
	status.text = "Online - players: " + str(remotes.size() + 1)

func _update_role() -> void:
	if role == null:
		return
	if mode == "sandbox" or not online:
		role.text = ""
	elif caught:
		role.text = "CAUGHT - spectating"
	elif it_id == 0:
		role.text = "Waiting for players..."
	elif it_id == my_id:
		role.text = "YOU ARE THE HUNTER" if mode == "horror" else "YOU ARE IT!"
	else:
		role.text = "SURVIVE" if mode == "horror" else "RUN!"
	player.speed_mult = 1.15 if (mode == "horror" and it_id == my_id) else 1.0
	for id in remotes:
		remotes[id].set_it(id == it_id)

func _on_net(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"welcome":
			my_id = int(m["id"])
			it_id = int(m.get("it", 0))
			for pl in m["players"]:
				_add_remote(int(pl["id"]), str(pl["name"]))
			_refresh_status()
			_update_role()
		"joined":
			_add_remote(int(m["id"]), str(m["name"]))
			_refresh_status()
		"left":
			_remove_remote(int(m["id"]))
			_refresh_status()
		"s":
			var sid := int(m["id"])
			if remotes.has(sid):
				var pa: Array = m["p"]
				remotes[sid].move_to(Vector3(pa[0], pa[1], pa[2]), float(m["r"]))
		"it":
			it_id = int(m["id"])
			_update_role()
		"caught":
			var cid := int(m["id"])
			if cid == my_id:
				caught = true
				_update_role()
			elif remotes.has(cid):
				remotes[cid].ghost = true
		"round_end":
			st
	