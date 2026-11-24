extends CharacterBody3D
# Touch "gorilla" movement: hold L or R hand pad and drag to push yourself.
# Touch anywhere else (upper area) and drag to look around.

const GRAVITY := 14.0
const MAX_SPEED := 14.0
const PULL := 0.02

var hand_rects: Array[Rect2] = []
var ui_rects: Array[Rect2] = []
var hand_touch := [-1, -1]
var look_touch := -1
var pitch := 0.0
var speed_mult := 1.0
var spawn := Vector3.ZERO
var cam: Camera3D
var hands: Array[MeshInstance3D] = []
var flashlight: SpotLight3D

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	shape.shape = cap
	shape.position.y = 0.85
	add_child(shape)
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.55, 0)
	cam.current = true
	add_child(cam)
	for i in 2:
		var h := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.13
		s.height = 0.26
		h.mesh = s
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.32, 0.25)
		h.material_override = mat
		h.position = Vector3(-0.5 if i == 0 else 0.5, -0.55, -0.8)
		cam.add_child(h)
		hands.append(h)
	flashlight = SpotLight3D.new()
	flashlight.spot_range = 22.0
	flashlight.spot_angle = 32.0
	flashlight.light_energy = 3.0
	flashlight.visible = false
	cam.add_child(flashlight)

func set_horror(on: bool) -> void:
	flashlight.visible = on

func teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO

func _blocked(pos: Vector2) -> bool:
	for r in ui_rects:
		if r.has_point(pos):
			return true
	return false

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _blocked(event.position):
				return
			for i in 2:
				if hand_rects.size() > i and hand_rects[i].has_point(event.position) and hand_touch[i] == -1:
					hand_touch[i] = event.index
					return
			if look_touch == -1:
				look_touch = event.index
		else:
			for i in 2:
				if hand_touch[i] == event.index:
					hand_touch[i] = -1
			if look_touch == event.index:
				look_touch = -1
	elif event is InputEventScreenDrag:
		for i in 2:
			if hand_touch[i] == event.index:
				_pull(event.relative)
				return
		if event.index == look_touch:
			rotate_y(-event.relative.x * 0.004)
			pitch = clampf(pitch - event.relative.y * 0.004, -1.3, 1.3)
			cam.rotation.x = pitch

func _pull(rel: Vector2) -> void:
	var b := global_transform.basis
	var push := (-b.x * rel.x - b.z * rel.y) * PULL
	velocity.x += push.x
	velocity.z += push.z
	if is_on_floor():
		velocity.y += clampf(rel.length() * 0.004, 0.0, 0.35)

func _physics_process(delta: float) -> void:
	var held: bool = hand_touch[0] != -1 or hand_touch[1] != -1
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var damp := 0.15
	if is_on_floor():
		damp = 1.2 if held else 3.5
	var k := exp(-damp * delta)
	velocity.x *= k
	velocity.z *= k
	var hv := Vector2(velocity.x, velocity.z)
	var cap_speed := MAX_SPEED * speed_mult
	if hv.length() > cap_speed:
		hv = hv.normalized() * cap_speed
		velocity.x = hv.x
		velocity.z = hv.y
	move_and_slide()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o := c.get_collider()
		if o is RigidBody3D:
			o.apply_central_impulse(-c.get_normal() * maxf(velocity.length(), 2.0) * 0.5)
	if global_position.y < -20.0:
		teleport(spawn)
	for i in 2:
		var rest := Vector3(-0.5 if i == 0 else 0.5, -0.55, -0.8)
		var down := Vector3(rest.x, -0.95, -0.55)
		hands[i].position = hands[i].position.lerp(down if hand_touch[i] != -1 else rest, 0.3)