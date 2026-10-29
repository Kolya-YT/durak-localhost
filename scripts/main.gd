extends Control

var network: NetworkManager
var discovery: LanDiscovery
var status_label: Label
var room_list: VBoxContainer
var name_input: LineEdit

func _ready() -> void:
	network = NetworkManager.new()
	network.name = "NetworkManager"
	add_child(network)
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	network.connection_status_changed.connect(_set_status)
	discovery.room_found.connect(_on_room_found)
	_build_ui()
	var err := discovery.start_search()
	if err != OK:
		_set_status("Не удалось запустить поиск комнат. Проверьте разрешения Android.")

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#123c32")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 18)
	layout.offset_left = 28
	layout.offset_top = 60
	layout.offset_right = -28
	layout.offset_bottom = -40
	add_child(layout)

	var title := Label.new()
	title.text = "ДУРАК LAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Играйте рядом — интернет не нужен"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(subtitle)

	name_input = LineEdit.new()
	name_input.placeholder_text = "Ваше имя"
	name_input.text = "Игрок"
	name_input.custom_minimum_size.y = 56
	layout.add_child(name_input)

	var create_button := Button.new()
	create_button.text = "Создать комнату"
	create_button.custom_minimum_size.y = 64
	create_button.pressed.connect(_create_room)
	layout.add_child(create_button)

	var refresh_button := Button.new()
	refresh_button.text = "Обновить поиск комнат"
	refresh_button.custom_minimum_size.y = 54
	refresh_button.pressed.connect(_refresh_rooms)
	layout.add_child(refresh_button)

	var rooms_title := Label.new()
	rooms_title.text = "Найденные комнаты"
	rooms_title.add_theme_font_size_override("font_size", 22)
	layout.add_child(rooms_title)

	room_list = VBoxContainer.new()
	layout.add_child(room_list)

	status_label = Label.new()
	status_label.text = "Поиск комнат в локальной сети..."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)

func _create_room() -> void:
	var room_code := "%04d" % randi_range(1000, 9999)
	var err := network.create_room(name_input.text)
	if err != OK:
		return
	discovery.advertise_room("%s — комната" % name_input.text.strip_edges(), room_code)
	_set_status("Комната создана. Подключите телефоны к одной точке доступа.")

func _refresh_rooms() -> void:
	for child in room_list.get_children():
		child.queue_free()
	_set_status("Ищем комнаты в локальной сети...")

func _on_room_found(room: Dictionary) -> void:
	var code := str(room.get("code", ""))
	for child in room_list.get_children():
		if child is Button and str(child.get_meta("room_code", "")) == code:
			return
	var button := Button.new()
	button.text = "%s  (%s)" % [str(room.get("name", "Комната")), str(room.get("ip", ""))]
	button.custom_minimum_size.y = 58
	button.set_meta("room_code", code)
	button.pressed.connect(_join_room.bind(room))
	room_list.add_child(button)

func _join_room(room: Dictionary) -> void:
	discovery.stop_search()
	discovery.stop_advertising()
	var err := network.join_room(str(room.get("ip", "")), name_input.text, int(room.get("port", 39178)))
	if err == OK:
		_set_status("Подключение к комнате %s..." % str(room.get("ip", "")))

func _set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
