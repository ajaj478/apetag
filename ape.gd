extends Node3D
# The "Mangorilla": gorilla-like, but with a flame crest, big round ears,
# glowing eyes, a curled glowing tail and stubby legs.

const VOICE_RATE := 16000

var arms: Array[Node3D] = []
var eye_mats: Array[StandardMaterial3D] = []
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var snapped_once := false
var speed := 0.0
var prev := Vector3.ZERO
var t := 0.0
var ghost := false
var speaker: AudioStreamPlayer3D
var playback: AudioStreamGeneratorPlayback

func _part(mesh: Mesh, pos: Vector3, col: Color, glow := false, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	if glow:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.5
	m.material_override = mat
	m.position = pos
	var p: Node3D = parent if parent != null else self
	p.add_child(m)
	return m

func build(col: Color, nm: String) -> void:
	var torso := CapsuleMesh.new()
	torso.radius = 0.32
	torso.height = 1.1
	_part(torso, Vector3(0, 0.95, 0), col).scale = Vector3(1.25, 1.0, 0.9)
	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.48
	_part(head, Vector3(0, 1.62, -0.05), col.lightened(0.1))
	var crest := BoxMesh.new()
	crest.size = Vector3(0.08, 0.22, 0.32)
	_part(crest, Vector3(0, 1.9, -0.03), Color(1.0, 0.45, 0.1), true)
	for s in [-1.0, 1.0]:
		var ear := SphereMesh.new()
		ear.radius = 0.16
		ear.height = 0.32
		_part(ear, Vector3(0.27 * s, 1.66, 0), col.lightened(0.25)).scale = Vector3(0.35, 1.0, 1.0)
		var eye := SphereMesh.new()
		eye.radius = 0.05
		eye.height = 0.1
		var em := _part(eye, Vector3(0.1 * s, 1.66, -0.26), Color(1.0, 0.9, 0.2), true)
		eye_mats.append(em.material_override as StandardMaterial3D)
		var leg := CapsuleMesh.new()
		leg.radius = 0.12
		leg.height = 0.5
		_part(leg, Vector3(0.2 * s, 0.28, 0), col.darkened(0.2))
		var pivot := Node3D.new()
		pivot.position = Vector3(0.46 * s, 1.3, 0)
		add_child(pivot)
		arms.append(pivot)
		var arm := CapsuleMesh.new()
		arm.radius = 0.1
		arm.height = 1.1
		_part(arm, Vector3(0, -0.5, 0), col.darkened(0.1), false, pivot)
		var hand := SphereMesh.new()
		hand.radius = 0.17
		hand.height = 0.34
		_part(hand, Vector3(0, -1.1, 0), col.lightened(0.3), false, pivot)
	var tail := CylinderMesh.new()
	tail.top_radius = 0.03
	tail.bottom_radius = 0.06
	tail.height = 0.7
	var tl := _part(tail, Vector3(0, 0.65, 0.35), col.darkened(0.3))
	tl.rotation_degrees = Vector3(50, 0, 0)
	var tip := SphereMesh.new()
	tip.radius = 0.08
	tip.height = 0.16
	_part(tip, Vector3(0, 0.88, 0.62), Color(0.2, 1.0, 0.9), true)
	var label := Label3D.new()
	label.text = nm
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.35, 0)
	add_child(label)

func set_it(on: bool) -> void:
	var c := Color(1.0, 0.1, 0.1) if on else Color(1.0, 0.9, 0.2)
	for m in eye_mats:
		m.albedo_color = c
		m.emission = c

func setup_voice() -> void:
	speaker = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VOICE_RATE
	gen.buffer_length = 0.4
	speaker.stream = gen
	speaker.unit_size = 5.0
	speaker.max_distance = 45.0
	add_child(speaker)
	speaker.play()
	playback = speaker.get_stream_playback() as AudioStreamGeneratorPlayback

func push_voice(data: PackedByteArray) -> void:
	if playback == null:
		return
	var n := data.size() / 2
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var s := data.decode_s16(i * 2) / 32768.0
		frames[i] = Vector2(s, s)
	if playback.can_push_buffer(n):
		playback.push_buffer(frames)

func move_to(p: Vector3, yaw: float) -> void:
	target_pos = p
	target_yaw = yaw
	if not snapped_once:
		snapped_once = true
		global_position = p
		prev = p

func _process(delta: float) -> void:
	t += delta
	var k := 1.0 - exp(-12.0 * delta)
	global_position = global_position.lerp(target_pos, k)
	rotation.y = lerp_angle(rotation.y, target_yaw, k)
	var v := (global_position - prev).length() / maxf(delta, 0.001)
	prev = global_position
	speed = lerpf(speed, v, 0.2)
	var sw := sin(t * 9.0) * clampf(speed / 5.0, 0.0, 1.0)
	arms[0].rotation.x = sw
	arms[1].rotation.x = -sw