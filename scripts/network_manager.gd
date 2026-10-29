extends Node
class_name NetworkManager

signal connection_status_changed(message: String)
signal player_list_changed(players: Array)
signal game_message_received(message: Dictionary)

const DEFAULT_PORT: int = 39178
const MAX_CLIENTS: int = 3

var is_host: bool = false
var local_player_name: String = "Игрок"
var players: Dictionary = {}
var _peer: ENetMultiplayerPeer

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_room(player_name: String, port: int = DEFAULT_PORT) -> Error:
	_close_peer()
	local_player_name = _clean_name(player_name)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		connection_status_changed.emit("Не удалось создать комнату: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = true
	players.clear()
	players[1] = {"id": 1, "name": local_player_name}
	player_list_changed.emit(get_players())
	connection_status_changed.emit("Комната создана. Ожидаем игроков.")
	return OK

func join_room(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	_close_peer()
	local_player_name = _clean_name(player_name)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		connection_status_changed.emit("Не удалось подключиться: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = false
	connection_status_changed.emit("Подключаемся к %s..." % address)
	return OK

func leave_room() -> void:
	_close_peer()
	players.clear()
	is_host = false
	player_list_changed.emit([])
	connection_status_changed.emit("Вы вышли из комнаты.")

func get_players() -> Array:
	var result: Array = []
	for id in players:
		result.append(players[id].duplicate(true))
	return result

func send_player_action(action: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if is_host:
		_host_process_action(1, action)
	else:
		_submit_action.rpc_id(1, action)

@rpc("any_peer", "call_remote", "reliable")
func _submit_action(action: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_host_process_action(sender_id, action)

func _host_process_action(sender_id: int, action: Dictionary) -> void:
	# GameManager will validate every action before it changes game state.
	if not is_host and not multiplayer.is_server():
		return
	if action.is_empty():
		return
	_broadcast_game_message.rpc({"from": sender_id, "action": action})

@rpc("authority", "call_local", "reliable")
func _broadcast_game_message(message: Dictionary) -> void:
	game_message_received.emit(message)

func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	players[peer_id] = {"id": peer_id, "name": "Игрок %d" % peer_id}
	player_list_changed.emit(get_players())
	connection_status_changed.emit("Подключился игрок %d." % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	player_list_changed.emit(get_players())
	connection_status_changed.emit("Игрок %d отключился." % peer_id)

func _on_connected_to_server() -> void:
	connection_status_changed.emit("Подключено к комнате.")
	_register_player.rpc_id(1, local_player_name)

@rpc("any_peer", "call_remote", "reliable")
func _register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	players[sender_id] = {"id": sender_id, "name": _clean_name(player_name)}
	player_list_changed.emit(get_players())

func _on_connection_failed() -> void:
	connection_status_changed.emit("Не удалось подключиться к комнате.")
	_close_peer()

func _on_server_disconnected() -> void:
	connection_status_changed.emit("Соединение с хостом потеряно.")
	_close_peer()

func _close_peer() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false

func _clean_name(value: String) -> String:
	var cleaned := value.strip_edges()
	if cleaned.is_empty():
		return "Игрок"
	return cleaned.left(20)
