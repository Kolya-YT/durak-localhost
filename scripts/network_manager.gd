extends Node

class_name NetworkManager

signal status_changed(message: String)
signal peers_changed(player_ids: Array[int])
signal connected_to_host

const GAME_PORT: int = 39178
const MAX_CLIENTS: int = 3

var is_host: bool = false
var local_player_name: String = "Игрок"
var peer_names: Dictionary = {}
var _peer: ENetMultiplayerPeer

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_room(player_name: String, port: int = GAME_PORT) -> Error:
	_close_peer()
	local_player_name = _clean_name(player_name)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		status_changed.emit("Не удалось создать комнату: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = true
	peer_names.clear()
	peer_names[1] = local_player_name
	peers_changed.emit(get_player_ids())
	status_changed.emit("Комната создана. Ожидаем игроков.")
	return OK

func join_room(address: String, port: int, player_name: String) -> Error:
	_close_peer()
	local_player_name = _clean_name(player_name)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		status_changed.emit("Не удалось подключиться: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = _peer
	is_host = false
	status_changed.emit("Подключаемся к %s..." % address)
	return OK

func disconnect_network() -> void:
	_close_peer()
	peer_names.clear()
	peers_changed.emit([])
	status_changed.emit("Вы вышли из комнаты.")

func get_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in peer_names.keys():
		ids.append(int(id))
	ids.sort()
	return ids

func send_player_action(action: Dictionary) -> void:
	# Retained for compatibility with the game layer; authoritative game RPCs
	# are sent directly through GameManager.
	if action.is_empty():
		return

func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	peer_names[peer_id] = "Игрок %d" % peer_id
	_broadcast_peer_names.rpc(peer_names)
	peers_changed.emit(get_player_ids())
	status_changed.emit("Подключился игрок %d." % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	peer_names.erase(peer_id)
	if is_host:
		_broadcast_peer_names.rpc(peer_names)
	peers_changed.emit(get_player_ids())
	status_changed.emit("Игрок %d отключился." % peer_id)

func _on_connected_to_server() -> void:
	status_changed.emit("Подключено к комнате.")
	_register_player.rpc_id(1, local_player_name)
	connected_to_host.emit()

@rpc("any_peer", "call_remote", "reliable")
func _register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	peer_names[sender_id] = _clean_name(player_name)
	_broadcast_peer_names.rpc(peer_names)
	peers_changed.emit(get_player_ids())

@rpc("authority", "call_remote", "reliable")
func _broadcast_peer_names(names: Dictionary) -> void:
	peer_names = names.duplicate(true)
	peers_changed.emit(get_player_ids())

func _on_connection_failed() -> void:
	status_changed.emit("Не удалось подключиться к комнате.")
	_close_peer()

func _on_server_disconnected() -> void:
	status_changed.emit("Соединение с хостом потеряно.")
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
