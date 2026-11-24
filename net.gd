extends Node

signal message(m: Dictionary)
signal voice(id: int, data: PackedByteArray)
signal closed

var ws := WebSocketPeer.new()
var open := false
var trying := false
var pending_join: Dictionary = {}

func connect_to(url: String, join: Dictionary) -> bool:
	ws = WebSocketPeer.new()
	pending_join = join
	open = false
	var err := ws.connect_to_url(url)
	trying = (err == OK)
	return trying

func send(d: Dictionary) -> void:
	if open:
		ws.send_text(JSON.stringify(d))

func send_bytes(b: PackedByteArray) -> void:
	if open:
		ws.send(b)

func close() -> void:
	ws.close()
	open = false
	trying = false

func _process(_delta: float) -> void:
	if not trying and not open:
		return
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not open:
				open = true
				send(pending_join)
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				if ws.was_string_packet():
					var m = JSON.parse_string(pkt.get_string_from_utf8())
					if m is Dictionary:
						message.emit(m)
				elif pkt.size() > 2:
					voice.emit(pkt.decode_u16(0), pkt.slice(2))
		WebSocketPeer.STATE_CLOSED:
			open = false
			trying = false
			closed.emit()