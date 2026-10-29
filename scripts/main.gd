extends Control

const DISCOVERY_SCRIPT = preload("res://scripts/lan_discovery.gd")
const NETWORK_SCRIPT = preload("res://scripts/network_manager.gd")
const GAME_SCRIPT = preload("res://scripts/game_manager.gd")

var discovery: LanDiscovery
var network: NetworkManager
var game: GameManager
var root_box: VBoxContainer
var room_list: VBoxContainer
var hand_box: HBoxContainer
var table_box: HBoxContainer
var status_label: Label
var players_label: Label
var selected_card := -1
var local_hand: Array = []
var current_state: Dictionary = {}
var name_input: LineEdit
var _refresh_timer := 0.0

func _ready() -> void:
	_build_ui()
	discovery = DISCOVERY_SCRIPT.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	discovery.rooms_updated.connect(_on_rooms_changed)
	discovery.start_search()
	network = NETWORK_SCRIPT.new()
	network.name = "NetworkManager"
	add_child(network)
	network.status_changed.connect(_set_status)
	network.peers_changed.connect(_on_peers_changed)
	network.connected_to_host.connect(_on_connected)
	game = GAME_SCRIPT.new()
	game.name = "GameManager"
	add_child(game)
	game.private_hand_changed.connect(_on_hand_changed)
	game.state_changed.connect(_on_state_changed)
	game.notice_changed.connect(_set_status)
	_show_lobby()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0d4b3a")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	root_box = VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 12)
	root_box.add_theme_constant_override("margin_left", 18)
	root_box.add_theme_constant_override("margin_right", 18)
	root_box.add_theme_constant_override("margin_top", 22)
	root_box.add_theme_constant_override("margin_bottom", 22)
	add_child(root_box)

func _clear_ui() -> void:
	for child in root_box.get_children():
		child.queue_free()

func _show_lobby() -> void:
	_clear_ui()
	var title := Label.new()
	title.text = "ДУРАК LAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Играйте рядом — без интернета"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_box.add_child(subtitle)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Ваше имя"
	name_input.text = "Игрок"
	root_box.add_child(name_input)
	var host_btn := Button.new()
	host_btn.text = "Создать комнату"
	host_btn.custom_minimum_size.y = 58
	host_btn.pressed.connect(_on_host_pressed)
	root_box.add_child(host_btn)
	var rooms_title := Label.new()
	rooms_title.text = "Комнаты поблизости"
	rooms_title.add_theme_font_size_override("font_size", 22)
	root_box.add_child(rooms_title)
	room_list = VBoxContainer.new()
	root_box.add_child(room_list)
	var refresh_btn := Button.new()
	refresh_btn.text = "Обновить список"
	refresh_btn.pressed.connect(func(): _on_rooms_changed(discovery.get_rooms()))
	root_box.add_child(refresh_btn)
	status_label = Label.new()
	status_label.text = "Подключите телефоны к одной сети Wi-Fi или точке доступа."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(status_label)
	_on_rooms_changed(discovery.get_rooms())

func _show_room() -> void:
	_clear_ui()
	var title := Label.new()
	title.text = "КОМНАТА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	root_box.add_child(title)
	players_label = Label.new()
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_box.add_child(players_label)
	var start_btn := Button.new()
	start_btn.text = "Начать игру (2–4 игрока)"
	start_btn.custom_minimum_size.y = 58
	start_btn.pressed.connect(func():
		if network.is_host:
			game.start_game(network.get_player_ids())
	)
	root_box.add_child(start_btn)
	var leave_btn := Button.new()
	leave_btn.text = "Выйти в меню"
	leave_btn.pressed.connect(func():
		discovery.stop_advertising()
		network.disconnect_network()
		_show_lobby()
	)
	root_box.add_child(leave_btn)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(status_label)
	_on_peers_changed(network.get_player_ids())

func _show_table() -> void:
	_clear_ui()
	var title := Label.new()
	title.text = "ДУРАК LAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	root_box.add_child(title)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(status_label)
	var counts_label := Label.new()
	counts_label.name = "Counts"
	root_box.add_child(counts_label)
	var deck_label := Label.new()
	deck_label.name = "Deck"
	root_box.add_child(deck_label)
	var table_title := Label.new()
	table_title.text = "СТОЛ"
	table_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_box.add_child(table_title)
	table_box = HBoxContainer.new()
	table_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root_box.add_child(table_box)
	var hand_title := Label.new()
	hand_title.text = "ВАШИ КАРТЫ — выберите карту"
	root_box.add_child(hand_title)
	hand_box = HBoxContainer.new()
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(hand_box)
	var actions := HBoxContainer.new()
	var play_btn := Button.new()
	play_btn.text = "Сыграть"
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.pressed.connect(_play_selected)
	actions.add_child(play_btn)
	var take_btn := Button.new()
	take_btn.text = "Беру"
	take_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_btn.pressed.connect(func(): game.request_take())
	actions.add_child(take_btn)
	var beat_btn := Button.new()
	beat_btn.text = "Бито"
	beat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	beat_btn.pressed.connect(func(): game.request_beat())
	actions.add_child(beat_btn)
	var transfer_btn := Button.new()
	transfer_btn.text = "Перевести"
	transfer_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transfer_btn.pressed.connect(func():
		if selected_card >= 0:
			game.request_transfer(selected_card)
		else:
			_set_status("Выберите карту для перевода.")
	)
	actions.add_child(transfer_btn)
	root_box.add_child(actions)
	_render_state(current_state)
	_render_hand()

func _on_host_pressed() -> void:
	var err := network.create_room(name_input.text)
	if err == OK:
		discovery.advertise_room("Дурак LAN", "room-%d" % OS.get_process_id(), NETWORK_SCRIPT.GAME_PORT)
		_show_room()

func _on_rooms_changed(rooms: Array[Dictionary]) -> void:
	if room_list == null or not is_instance_valid(room_list):
		return
	for child in room_list.get_children():
		child.queue_free()
	if rooms.is_empty():
		var empty := Label.new()
		empty.text = "Пока комнат не найдено. Создайте свою."
		room_list.add_child(empty)
		return
	for room in rooms:
		var button := Button.new()
		button.text = "%s · %d/%d\n%s:%d" % [str(room.get("name", "Комната")), int(room.get("players", 1)), int(room.get("capacity", 4)), str(room.get("ip", "")), int(room.get("port", NETWORK_SCRIPT.GAME_PORT))]
		button.custom_minimum_size.y = 64
		var ip := str(room.ip)
		var port := int(room.port)
		button.pressed.connect(func():
			var err := network.join_room(ip, port, name_input.text)
			if err == OK:
				_show_room()
		)
		room_list.add_child(button)

func _on_connected() -> void:
	_show_room()

func _on_peers_changed(ids: Array[int]) -> void:
	if players_label and is_instance_valid(players_label):
		var names: PackedStringArray = []
		for id in ids:
			names.append(str(network.peer_names.get(id, "Игрок %d" % id)))
		players_label.text = "Игроков: %d/4\n%s" % [ids.size(), ", ".join(names)]
	if network.is_host and discovery:
		discovery.advertise_room("Дурак LAN", "room-%d" % get_instance_id(), NETWORK_SCRIPT.GAME_PORT)

func _on_hand_changed(cards: Array) -> void:
	local_hand = cards.duplicate(true)
	selected_card = -1
	_render_hand()

func _on_state_changed(state: Dictionary) -> void:
	current_state = state.duplicate(true)
	if bool(state.get("game_started", false)):
		if hand_box == null or not is_instance_valid(hand_box):
			_show_table()
		_render_state(current_state)

func _render_state(state: Dictionary) -> void:
	if state.is_empty() or status_label == null or not is_instance_valid(status_label):
		return
	status_label.text = str(state.get("status", "Ожидание игроков"))
	if table_box and is_instance_valid(table_box):
		for child in table_box.get_children():
			child.queue_free()
		for pair_value in (state.get("table_pairs", []) as Array):
			var pair: Dictionary = pair_value
			var stack := VBoxContainer.new()
			var attack := Label.new()
			attack.text = _card_text(pair.attack)
			attack.add_theme_font_size_override("font_size", 22)
			stack.add_child(attack)
			var defense := Label.new()
			defense.text = _card_text(pair.defense) if not (pair.defense as Dictionary).is_empty() else "?"
			defense.add_theme_font_size_override("font_size", 22)
			stack.add_child(defense)
			table_box.add_child(stack)
	var counts := root_box.find_child("Counts", true, false)
	if counts:
		counts.text = "Карты у игроков: %s" % str(state.get("hand_counts", {}))
	var deck_label := root_box.find_child("Deck", true, false)
	if deck_label:
		var suits := ["♣", "♦", "♥", "♠"]
		deck_label.text = "В колоде: %d · Козырь: %s" % [int(state.get("deck_count", 0)), suits[clampi(int(state.get("trump_suit", 0)), 0, 3)]]

func _render_hand() -> void:
	if hand_box == null or not is_instance_valid(hand_box):
		return
	for child in hand_box.get_children():
		child.queue_free()
	for i in range(local_hand.size()):
		var card: Dictionary = local_hand[i]
		var button := Button.new()
		button.text = _card_text(card)
		button.custom_minimum_size = Vector2(48, 90)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 17)
		if int(card.suit) == 1 or int(card.suit) == 2:
			button.add_theme_color_override("font_color", Color("#ff8b8b"))
		if i == selected_card:
			button.modulate = Color("#ffe08a")
		var index := i
		button.pressed.connect(func():
			selected_card = index
			_render_hand()
		)
		hand_box.add_child(button)

func _play_selected() -> void:
	if selected_card < 0 or selected_card >= local_hand.size():
		_set_status("Сначала выберите карту.")
		return
	var target := -1
	for i in range((current_state.get("table_pairs", []) as Array).size()):
		var pair: Dictionary = current_state.table_pairs[i]
		if (pair.defense as Dictionary).is_empty():
			target = i
			break
	game.request_play(selected_card, target)

func _card_text(card: Dictionary) -> String:
	if card.is_empty():
		return "—"
	var ranks := ["", "", "", "", "", "", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
	var suits := ["♣", "♦", "♥", "♠"]
	return "%s%s" % [ranks[clampi(int(card.get("rank", 6)), 6, 14)], suits[clampi(int(card.get("suit", 0)), 0, 3)]]

func _set_status(message: String) -> void:
	if status_label and is_instance_valid(status_label):
		status_label.text = message

func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 2.0:
		_refresh_timer = 0.0
		if room_list and is_instance_valid(room_list):
			_on_rooms_changed(discovery.get_rooms())
