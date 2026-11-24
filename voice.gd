extends Node
# Mic capture -> 16 kHz mono 16-bit chunks (60 ms). Only sends when you are talking.

signal chunk(bytes: PackedByteArray)

const RATE := 16000
const CHUNK := 960

var enabled := true
var capture: AudioEffectCapture
var mic_player: AudioStreamPlayer
var pending := PackedFloat32Array()
var acc := 0.0
var cnt := 0
var phase := 0.0
var hang := 0

func start() -> void:
	var idx := AudioServer.get_bus_index("Mic")
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Mic")
		AudioServer.set_bus_volume_db(idx, -80.0)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	capture = AudioServer.get_bus_effect(idx, 0) as AudioEffectCapture
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Mic"
	add_child(mic_player)
	mic_player.play()

func _process(_delta: float) -> void:
	if capture == null:
		return
	var avail := capture.get_frames_available()
	if avail <= 0:
		return
	var frames := capture.get_buffer(avail)
	var ratio := AudioServer.get_mix_rate() / float(RATE)
	for f in frames:
		acc += (f.x + f.y) * 0.5
		cnt += 1
		phase += 1.0
		if phase >= ratio:
			phase -= ratio
			pending.append(acc / float(cnt))
			acc = 0.0
			cnt = 0
	while pending.size() >= CHUNK:
		var part := pending.slice(0, CHUNK)
		pending = pending.slice(CHUNK)
		var sum := 0.0
		for s in part:
			sum += s * s
		var rms := sqrt(sum / CHUNK)
		if rms > 0.012:
			hang = 8
		if not enabled or hang <= 0:
			continue
		hang -= 1
		var bytes := PackedByteArray()
		bytes.resize(CHUNK * 2)
		for i in CHUNK:
			bytes.encode_s16(i * 2, int(clampf(part[i] * 2.0, -1.0, 1.0) * 32767.0))
		chunk.emit(bytes)