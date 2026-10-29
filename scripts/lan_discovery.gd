extends Node
class_name LanDiscovery

signal room_found(room: Dictionary)
signal rooms_updated(rooms: Array[Dictionary])

const DISCOVERY_PORT: int = 39177
const DISCOVERY_MAGIC: String = "DURAK_LAN_V1"
const ANNOUNCE_INTERVAL: float = 1.5
const ROOM_TIMEOUT: float = 6.0

var _udp := PacketPeerUDP.new()
var _broadcast_udp := PacketPeerUDP.new()
var _rooms: Dictionary = {}
var _elapsed: float = 0.0
var _room_code: String = ""
var _room_name: String = ""
var _host_port: int = 39178
var _advertising: bool = false

func _ready() -> void:
	set_process(true)

func start_search() -> Error:
	_udp.close()
	var err := _udp.bind(DISCOVERY_PORT, "*")
	if err != OK:
		push_warning("LAN discovery bind failed: %s" % error_string(err))
		return err
	_udp.set_broadcast_enabled(true)
	_broadcast_udp.set_broadcast_enabled(true)
	return OK

func stop_search() -> void:
	_udp.close()
	_broadcast_udp.close()
	_rooms.clear()
	rooms_updated.emit([])

func advertise_room(room_name: String, room_code: String, game_port: int = 39178) -> void:
	_room_name = room_name
	_room_code = room_code
	_host_port = game_port
	_advertising = true
	_elapsed = ANNOUNCE_INTERVAL
	if not _broadcast_udp.is_socket_connected():
		_broadcast_udp.set_broadcast_enabled(true)

func stop_advertising() -> void:
	_advertising = false

func get_rooms() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _rooms.values():
		result.append(value.duplicate(true))
	return result

func _process(delta: float) -> void:
	_elapsed += delta
	if _advertising and _elapsed >= ANNOUNCE_INTERVAL:
		_elapsed = 0.0
		_send_announcement()
	_receive_announcements()
	_expire_rooms()

func _send_announcement() -> void:
	var packet := {
		"magic": DISCOVERY_MAGIC,
		"name": _room_name,
		"code": _room_code,
		"port": _host_port,
		"players": 1,
		"timestamp": Time.get_ticks_msec()
	}
	var bytes := JSON.stringify(packet).to_utf8_buffer()
	var err := _broadcast_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	if err == OK:
		_broadcast_udp.put_packet(bytes)

func _receive_announcements() -> void:
	while _udp.get_available_packet_count() > 0:
		var bytes := _udp.get_packet()
		var sender_ip := _udp.get_packet_ip()
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		if str(parsed.get("magic", "")) != DISCOVERY_MAGIC:
			continue
		var code := str(parsed.get("code", ""))
		if code.is_empty() or sender_ip.is_empty():
			continue
		var room := {
			"name": str(parsed.get("name", "Комната")),
			"code": code,
			"ip": sender_ip,
			"port": int(parsed.get("port", 39178)),
			"players": int(parsed.get("players", 1)),
			"last_seen": Time.get_ticks_msec()
		}
		_rooms[code] = room
		room_found.emit(room.duplicate(true))
	rooms_updated.emit(get_rooms())

func _expire_rooms() -> void:
	var now := Time.get_ticks_msec()
	var changed := false
	for code in _rooms.keys():
		if now - int(_rooms[code].get("last_seen", 0)) > int(ROOM_TIMEOUT * 1000.0):
			_rooms.erase(code)
			changed = true
	if changed:
		rooms_updated.emit(get_rooms())
