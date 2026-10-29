extends Control

const DISCOVERY_SCRIPT = preload("res://scripts/lan_discovery.gd")
const NETWORK_SCRIPT = preload("res://scripts/network_manager.gd")
const GAME_SCRIPT = preload("res://scripts/game_manager.gd")

const BLUE := Color("#426b8e")
const BLUE_DARK := Color("#294c6c")
const BLUE_LIGHT := Color("#7294b3")
const CREAM := Color("#fffaf0")
const RED := Color("#e64c62")
const MUTED := Color("#d4e1ed")

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
var player_count := 3
var deck_size := 36
var wager := 100
var private_game := false
var selected_modes := {"Соседи": true, "С шулерами": true, "Классика": true, "Переводной": true}
var _refresh_timer := 0.0
var _screen := "lobby"

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
	bg.color = BLUE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color("#254a6a")
	glow.anchor_left = 0.0
	glow.anchor_right = 1.0
	glow.anchor_top = 0.0
	glow.anchor_bottom = 1.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	root_box = VBoxContainer.new()
	root_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 10)
	root_box.add_theme_constant_override("margin_left", 18)
	root_box.add_theme_constant_override("margin_right", 18)
	root_box.add_theme_constant_override("margin_top", 12)
	root_box.add_theme_constant_override("margin_bottom", 12)
	add_child(root_box)

func _clear_ui() -> void:
	for child in root_box.get_children():
		child.queue_free()

func _style_label(label: Label, size: int = 20, color: Color = CREAM, centered: bool = false, italic: bool = false) -> Label:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if italic:
		label.add_theme_font_override("font", _decorative_font())
	return label

func _decorative_font() -> Font:
	# Use the built-in font safely; the italic style is applied by the label theme.
	return ThemeDB.fallback_font

func _style_button(button: Button, selected: bool = false, tall: int = 48) -> Button:
	button.custom_minimum_size.y = tall
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", RED if selected else CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#f8f7f3") if selected else Color("#6285a4")
	normal.border_color = Color("#f8f7f3")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(14)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#87a4bd") if not selected else Color.WHITE
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#355b7b")
	button.add_theme_stylebox_override("pressed", pressed)
	return button

func _section_title(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return _style_label(label, 23, CREAM, true, true)

func _show_lobby() -> void:
	_screen = "lobby"
	_clear_ui()
	var header := HBoxContainer.new()
	var logo := Label.new()
	logo.text = "♠"
	_style_label(logo, 32, CREAM, true)
	header.add_child(logo)
	var title_box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Создать игру"
	_style_label(title, 29, CREAM, true, true)
	title_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "ДУРАК • ЛОКАЛЬНАЯ ИГРА"
	_style_label(subtitle, 11, MUTED, true)
	title_box.add_child(subtitle)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	var gem := Label.new()
	gem.text = "◆"
	_style_label(gem, 34, RED, true)
	header.add_child(gem)
	root_box.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	var wager_header := HBoxContainer.new()
	var wager_title := Label.new()
	wager_title.text = "Ваша ставка"
	_style_label(wager_title, 22, CREAM, false, true)
	wager_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wager_header.add_child(wager_title)
	var wager_value := Label.new()
	wager_value.name = "WagerValue"
	wager_value.text = _format_money(wager)
	_style_label(wager_value, 27, CREAM, false)
	wager_header.add_child(wager_value)
	content.add_child(wager_header)
	var wager_slider := HSlider.new()
	wager_slider.min_value = 100
	wager_slider.max_value = 10000000
	wager_slider.step = 100
	wager_slider.value = wager
	wager_slider.custom_minimum_size.y = 24
	wager_slider.value_changed.connect(func(value: float):
		wager = int(value)
		wager_value.text = _format_money(wager)
	)
	content.add_child(wager_slider)
	var wager_marks := HBoxContainer.new()
	for mark in ["100", "1K", "10K", "100K", "1M", "10M"]:
		var m := Label.new()
		m.text = mark
		_style_label(m, 12, MUTED, true)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wager_marks.add_child(m)
	content.add_child(wager_marks)

	content.add_child(_section_title("Игроки"))
	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 4)
	for count in range(2, 7):
		var b := Button.new()
		b.text = str(count) + (" ✓" if count == player_count else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, count == player_count, 48)
		b.pressed.connect(func():
			player_count = count
			_show_lobby()
		)
		player_row.add_child(b)
	content.add_child(player_row)

	var settings_row := HBoxContainer.new()
	settings_row.add_theme_constant_override("separation", 14)
	var deck_column := VBoxContainer.new()
	deck_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_column.add_child(_section_title("Колода"))
	var deck_row := HBoxContainer.new()
	for size in [24, 36, 52]:
		var b := Button.new()
		b.text = str(size) + (" ✓" if size == deck_size else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, size == deck_size, 46)
		b.pressed.connect(func():
			deck_size = size
			_show_lobby()
		)
		deck_row.add_child(b)
	deck_column.add_child(deck_row)
	settings_row.add_child(deck_column)
	var speed_column := VBoxContainer.new()
	speed_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_column.add_child(_section_title("Скорость"))
	var speed_row := HBoxContainer.new()
	var normal_speed := Button.new()
	normal_speed.text = "▶ ✓"
	_style_button(normal_speed, true, 46)
	normal_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(normal_speed)
	var fast_speed := Button.new()
	fast_speed.text = "≫"
	_style_button(fast_speed, false, 46)
	fast_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fast_speed.pressed.connect(func(): _set_status("Быстрый режим скоро появится."))
	speed_row.add_child(fast_speed)
	speed_column.add_child(speed_row)
	settings_row.add_child(speed_column)
	content.add_child(settings_row)

	content.add_child(_section_title("Режимы игры"))
	var modes_grid := GridContainer.new()
	modes_grid.columns = 4
	modes_grid.add_theme_constant_override("h_separation", 7)
	modes_grid.add_theme_constant_override("v_separation", 7)
	var mode_data := [
		["⇥", "Подкидной", false],
		["⇄", "Соседи", true],
		["♟", "С шулерами", true],
		["▣", "Классика", true],
		["↪", "Переводной", true],
		["✣", "Все", false],
		["♧", "Честная", false],
		["⚄", "Ничья", false]
	]
	for entry in mode_data:
		var mode_name: String = entry[1]
		var b := Button.new()
		b.text = str(entry[0]) + (" ✓" if bool(selected_modes.get(mode_name, false)) else "") + "\n" + mode_name
		b.custom_minimum_size = Vector2(0, 72)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, bool(selected_modes.get(mode_name, false)), 72)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			selected_modes[mode_name] = not bool(selected_modes.get(mode_name, false))
			_show_lobby()
		)
		modes_grid.add_child(b)
	content.add_child(modes_grid)

	var privacy_row := HBoxContainer.new()
	var privacy := CheckBox.new()
	privacy.text = "Приватная игра"
	privacy.button_pressed = private_game
	privacy.add_theme_color_override("font_color", CREAM)
	privacy.toggled.connect(func(value: bool): private_game = value)
	privacy_row.add_child(privacy)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	privacy_row.add_child(spacer)
	var create_btn := Button.new()
	create_btn.text = "Создать  ▶"
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(create_btn, true, 54)
	create_btn.pressed.connect(_on_host_pressed)
	privacy_row.add_child(create_btn)
	content.add_child(privacy_row)

	content.add_child(_section_title("Открытые комнаты"))
	name_input = LineEdit.new()
	name_input.placeholder_text = "Ваше имя"
	name_input.text = "Игрок"
	name_input.custom_minimum_size.y = 42
	content.add_child(name_input)
	room_list = VBoxContainer.new()
	room_list.add_theme_constant_override("separation", 6)
	content.add_child(room_list)
	var refresh_btn := Button.new()
	refresh_btn.text = "↻  Обновить список комнат"
	_style_button(refresh_btn, false, 42)
	refresh_btn.pressed.connect(func(): _on_rooms_changed(discovery.get_rooms()))
	content.add_child(refresh_btn)
	status_label = Label.new()
	status_label.text = "Подключите телефоны к одной сети Wi-Fi или точке доступа."
	_style_label(status_label, 13, MUTED, true)
	content.add_child(status_label)
	_on_rooms_changed(discovery.get_rooms())

func _show_room() -> void:
	_screen = "room"
	_clear_ui()
	var title := _section_title("ИГРОВАЯ КОМНАТА")
	root_box.add_child(title)
	players_label = Label.new()
	_style_label(players_label, 20, CREAM, true)
	root_box.add_child(players_label)
	var start_btn := Button.new()
	start_btn.text = "Начать игру  ▶"
	_style_button(start_btn, true, 56)
	start_btn.pressed.connect(func():
		if network.is_host:
			game.start_game(network.get_player_ids())
	)
	root_box.add_child(start_btn)
	var leave_btn := Button.new()
	leave_btn.text = "← Выйти в меню"
	_style_button(leave_btn, false, 48)
	leave_btn.pressed.connect(func():
		discovery.stop_advertising()
		network.disconnect_network()
		_show_lobby()
	)
	root_box.add_child(leave_btn)
	status_label = Label.new()
	_style_label(status_label, 14, MUTED, true)
	root_box.add_child(status_label)
	_on_peers_changed(network.get_player_ids())

func _show_table() -> void:
	_screen = "table"
	_clear_ui()
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "♠  ДУРАК LAN"
	_style_label(title, 23, CREAM, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var money := Label.new()
	money.text = _format_money(wager) + " 💵"
	_style_label(money, 18, CREAM, true)
	header.add_child(money)
	root_box.add_child(header)
	var opponents := HBoxContainer.new()
	opponents.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in network.get_player_ids():
		if id == multiplayer.get_unique_id():
			continue
		var opponent := VBoxContainer.new()
		var back := Label.new()
		back.text = "┌─────┐\n│  ⌛  │\n└─────┘"
		_style_label(back, 19, CREAM, true)
		opponent.add_child(back)
		var count := Label.new()
		count.text = "6"
		_style_label(count, 17, CREAM, true)
		opponent.add_child(count)
		opponents.add_child(opponent)
	root_box.add_child(opponents)
	status_label = Label.new()
	_style_label(status_label, 15, CREAM, true)
	status_label.custom_minimum_size.y = 46
	root_box.add_child(status_label)
	var deck_label := Label.new()
	deck_label.name = "Deck"
	_style_label(deck_label, 16, CREAM, true)
	root_box.add_child(deck_label)
	var table_panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#315776")
	panel_style.bg_color.a = 0.65
	panel_style.set_corner_radius_all(18)
	table_panel.add_theme_stylebox_override("panel", panel_style)
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(table_panel)
	table_box = HBoxContainer.new()
	table_box.alignment = BoxContainer.ALIGNMENT_CENTER
	table_box.add_theme_constant_override("separation", 6)
	table_panel.add_child(table_box)
	var hand_title := Label.new()
	hand_title.text = "ВАШИ КАРТЫ"
	root_box.add_child(_style_label(hand_title, 18, CREAM, true, true))
	var hand_scroll := ScrollContainer.new()
	hand_scroll.custom_minimum_size.y = 118
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_box.add_child(hand_scroll)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", -14)
	hand_scroll.add_child(hand_box)
	var actions := HBoxContainer.new()
	for pair in [["Сыграть", Callable(self, "_play_selected")], ["Беру", Callable(self, "_take_action")], ["Бито", Callable(self, "_beat_action")], ["Перевести", Callable(self, "_transfer_action")]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_button(b, pair[0] == "Сыграть", 46)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(pair[1])
		actions.add_child(b)
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
		_style_label(empty, 13, MUTED, true)
		room_list.add_child(empty)
		return
	for room in rooms:
		var button := Button.new()
		button.text = "%s · %d/%d\n%s:%d" % [str(room.get("name", "Комната")), int(room.get("players", 1)), int(room.get("capacity", 4)), str(room.get("ip", "")), int(room.get("port", NETWORK_SCRIPT.GAME_PORT))]
		_style_button(button, false, 58)
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
		players_label.text = "Игроков: %d/%d\n%s" % [ids.size(), player_count, ", ".join(names)]
	if network.is_host and discovery:
		discovery.advertise_room("Дурак LAN", "room-%d" % get_instance_id(), NETWORK_SCRIPT.GAME_PORT)

func _on_hand_changed(cards: Array) -> void:
	local_hand = cards.duplicate(true)
	selected_card = -1
	_render_hand()

func _on_state_changed(state: Dictionary) -> void:
	current_state = state.duplicate(true)
	if bool(state.get("game_started", false)):
		if _screen != "table":
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
			var stack := HBoxContainer.new()
			stack.add_theme_constant_override("separation", -18)
			var attack := _card_widget(pair.attack, false)
			stack.add_child(attack)
			var defense_card: Dictionary = pair.defense
			stack.add_child(_card_widget(defense_card, defense_card.is_empty()))
			table_box.add_child(stack)
	var deck_label := root_box.find_child("Deck", true, false)
	if deck_label:
		var suits := ["♣", "♦", "♥", "♠"]
		deck_label.text = "В колоде: %d     Козырь: %s" % [int(state.get("deck_count", 0)), suits[clampi(int(state.get("trump_suit", 0)), 0, 3)]]

func _render_hand() -> void:
	if hand_box == null or not is_instance_valid(hand_box):
		return
	for child in hand_box.get_children():
		child.queue_free()
	for i in range(local_hand.size()):
		var card: Dictionary = local_hand[i]
		var widget := _card_widget(card, false)
		widget.custom_minimum_size = Vector2(76, 110)
		widget.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var index := i
		widget.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				selected_card = index
				_render_hand()
		)
		if i == selected_card:
			widget.position.y -= 12
		hand_box.add_child(widget)

func _card_widget(card: Dictionary, empty: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(66, 96)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fdfcf7") if not empty else Color("#8da6bb")
	style.border_color = Color("#d6d6d0")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "?" if empty else _card_text(card)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 23)
	var suit := int(card.get("suit", 0)) if not empty else 0
	label.add_theme_color_override("font_color", Color("#df4059") if suit == 1 or suit == 2 else Color("#263746"))
	panel.add_child(label)
	return panel

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

func _take_action() -> void:
	game.request_take()

func _beat_action() -> void:
	game.request_beat()

func _transfer_action() -> void:
	if selected_card >= 0:
		game.request_transfer(selected_card)
	else:
		_set_status("Выберите карту для перевода.")

func _card_text(card: Dictionary) -> String:
	if card.is_empty():
		return "—"
	var ranks := ["", "", "", "", "", "", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
	var suits := ["♣", "♦", "♥", "♠"]
	return "%s\n%s" % [ranks[clampi(int(card.get("rank", 6)), 6, 14)], suits[clampi(int(card.get("suit", 0)), 0, 3)]]

func _format_money(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1fK" % (float(value) / 1000.0)
	return str(value)

func _set_status(message: String) -> void:
	if status_label and is_instance_valid(status_label):
		status_label.text = message

func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 2.0:
		_refresh_timer = 0.0
		if room_list and is_instance_valid(room_list):
			_on_rooms_changed(discovery.get_rooms())
