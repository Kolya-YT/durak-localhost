extends Node
class_name GameManager

signal state_changed(state: Dictionary)
signal private_hand_changed(cards: Array[Dictionary])
signal notice_changed(message: String)

const SUITS := ["♣", "♦", "♥", "♠"]
const HAND_SIZE := 6

var hands: Dictionary = {}
var player_order: Array[int] = []
var deck: Array[Dictionary] = []
var table_pairs: Array[Dictionary] = []
var discard_pile: Array[Dictionary] = []
var trump_suit := 0
var attacker := 1
var defender := 1
var current_attacker := 1
var game_started := false
var round_finished := false
var status_text := "Создайте комнату или подключитесь к ней."

func start_game(ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return
	if ids.size() < 2 or ids.size() > 4:
		notice_changed.emit("Для игры нужно от 2 до 4 игроков.")
		return
	player_order = ids.duplicate()
	player_order.sort()
	deck.clear()
	discard_pile.clear()
	table_pairs.clear()
	for suit in range(4):
		for rank in range(6, 15):
			deck.append({"rank": rank, "suit": suit})
	deck.shuffle()
	trump_suit = int(deck.back().suit)
	hands.clear()
	for id in player_order:
		hands[id] = []
	for _i in range(HAND_SIZE):
		for id in player_order:
			if not deck.is_empty():
				hands[id].append(deck.pop_back())
	attacker = _find_first_trump_holder()
	defender = _next_player(attacker)
	current_attacker = attacker
	game_started = true
	round_finished = false
	status_text = "Игра началась. Козырь: %s" % SUITS[trump_suit]
	_publish_state()

func request_play(card_index: int, target_pair: int = -1) -> void:
	if multiplayer.is_server():
		_handle_play(multiplayer.get_unique_id(), card_index, target_pair)
	else:
		_request_play.rpc_id(1, card_index, target_pair)

@rpc("any_peer", "call_remote", "reliable")
func _request_play(card_index: int, target_pair: int) -> void:
	if multiplayer.is_server():
		_handle_play(multiplayer.get_remote_sender_id(), card_index, target_pair)

func _handle_play(sender: int, card_index: int, target_pair: int) -> void:
	if not game_started or round_finished:
		return
	var can_defend := sender == defender and _has_uncovered_pair()
	if sender != current_attacker and not can_defend:
		return
	var hand: Array = hands.get(sender, [])
	if card_index < 0 or card_index >= hand.size():
		return
	var card: Dictionary = hand[card_index]
	if table_pairs.is_empty():
		if sender != attacker:
			return
		hand.remove_at(card_index)
		table_pairs.append({"attack": card, "defense": {}})
		status_text = "Атака. Защитник должен побить карту или взять."
	elif sender == defender and target_pair >= 0 and target_pair < table_pairs.size():
		var pair: Dictionary = table_pairs[target_pair]
		if not (pair.defense as Dictionary).is_empty() or not _beats(card, pair.attack):
			status_text = "Эта карта не может побить выбранную."
			notice_changed.emit(status_text)
			return
		hand.remove_at(card_index)
		pair.defense = card
		table_pairs[target_pair] = pair
		current_attacker = attacker
		status_text = "Карта побита. Можно подкинуть или нажать «Бито»."
	else:
		if sender == defender or table_pairs.size() >= _max_attacks() or not _rank_on_table(int(card.rank)):
			return
		hand.remove_at(card_index)
		table_pairs.append({"attack": card, "defense": {}})
		status_text = "Подкинута карта."
	_publish_state()

func request_transfer(card_index: int) -> void:
	if multiplayer.is_server():
		_handle_transfer(multiplayer.get_unique_id(), card_index)
	else:
		_request_transfer.rpc_id(1, card_index)

@rpc("any_peer", "call_remote", "reliable")
func _request_transfer(card_index: int) -> void:
	if multiplayer.is_server():
		_handle_transfer(multiplayer.get_remote_sender_id(), card_index)

func _handle_transfer(sender: int, card_index: int) -> void:
	if not game_started or round_finished or sender != defender or player_order.size() < 3:
		return
	if table_pairs.size() != 1 or not (table_pairs[0].defense as Dictionary).is_empty():
		return
	var hand: Array = hands.get(sender, [])
	if card_index < 0 or card_index >= hand.size():
		return
	var card: Dictionary = hand[card_index]
	if int(card.rank) != int(table_pairs[0].attack.rank):
		status_text = "Для перевода нужна карта того же достоинства."
		notice_changed.emit(status_text)
		return
	var next_defender := _next_player(defender)
	if next_defender == attacker or int((hands.get(next_defender, []) as Array).size()) < table_pairs.size() + 1:
		status_text = "Следующему игроку не хватает карт для перевода."
		notice_changed.emit(status_text)
		return
	hand.remove_at(card_index)
	table_pairs.append({"attack": card, "defense": {}})
	defender = next_defender
	current_attacker = attacker
	status_text = "Перевод выполнен. Защищается следующий игрок."
	_publish_state()

func request_take() -> void:
	if multiplayer.is_server():
		_handle_take(multiplayer.get_unique_id())
	else:
		_request_take.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_take() -> void:
	if multiplayer.is_server():
		_handle_take(multiplayer.get_remote_sender_id())

func _handle_take(sender: int) -> void:
	if not game_started or round_finished or sender != defender:
		return
	var hand: Array = hands[defender]
	for pair in table_pairs:
		hand.append(pair.attack)
		if not (pair.defense as Dictionary).is_empty():
			hand.append(pair.defense)
	table_pairs.clear()
	_draw_cards()
	attacker = _next_active_player(attacker)
	defender = _next_active_player(attacker)
	current_attacker = attacker
	status_text = "Защитник забрал карты. Ход следующего игрока."
	_check_winner()
	_publish_state()

func request_beat() -> void:
	if multiplayer.is_server():
		_handle_beat(multiplayer.get_unique_id())
	else:
		_request_beat.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request_beat() -> void:
	if multiplayer.is_server():
		_handle_beat(multiplayer.get_remote_sender_id())

func _handle_beat(sender: int) -> void:
	if not game_started or round_finished or sender != attacker or table_pairs.is_empty():
		return
	for pair in table_pairs:
		if (pair.defense as Dictionary).is_empty():
			status_text = "Не все карты побиты."
			notice_changed.emit(status_text)
			return
	for pair in table_pairs:
		discard_pile.append(pair.attack)
		discard_pile.append(pair.defense)
	table_pairs.clear()
	_draw_cards()
	attacker = _next_active_player(attacker)
	defender = _next_active_player(attacker)
	current_attacker = attacker
	status_text = "Отбой. Следующий ход."
	_check_winner()
	_publish_state()

func _draw_cards() -> void:
	var order: Array[int] = [attacker]
	var next := attacker
	for _i in range(player_order.size() - 1):
		next = _next_player(next)
		order.append(next)
	for id in order:
		var hand: Array = hands.get(id, [])
		while hand.size() < HAND_SIZE and not deck.is_empty():
			hand.append(deck.pop_back())

func _beats(card: Dictionary, target: Dictionary) -> bool:
	if int(card.suit) == int(target.suit):
		return int(card.rank) > int(target.rank)
	return int(card.suit) == trump_suit and int(target.suit) != trump_suit

func _has_uncovered_pair() -> bool:
	for pair in table_pairs:
		if (pair.defense as Dictionary).is_empty():
			return true
	return false

func _rank_on_table(rank: int) -> bool:
	for pair in table_pairs:
		if int(pair.attack.rank) == rank:
			return true
		if not (pair.defense as Dictionary).is_empty() and int(pair.defense.rank) == rank:
			return true
	return false

func _max_attacks() -> int:
	return mini(6, int(hands.get(defender, []).size()))

func _next_player(id: int) -> int:
	if player_order.is_empty():
		return id
	return player_order[(player_order.find(id) + 1) % player_order.size()]

func _next_active_player(id: int) -> int:
	var candidate := _next_player(id)
	for _i in range(player_order.size()):
		if not (hands.get(candidate, []) as Array).is_empty() or not deck.is_empty():
			return candidate
		candidate = _next_player(candidate)
	return candidate

func _find_first_trump_holder() -> int:
	var best_id := player_order[0]
	var best_rank := 99
	for id in player_order:
		for card in hands[id]:
			if int(card.suit) == trump_suit and int(card.rank) < best_rank:
				best_rank = int(card.rank)
				best_id = id
	return best_id

func _check_winner() -> void:
	if not deck.is_empty():
		return
	var active: Array[int] = []
	for id in player_order:
		if not (hands.get(id, []) as Array).is_empty():
			active.append(id)
	if active.size() <= 1:
		round_finished = true
		status_text = "Победитель: игрок %d" % (active[0] if not active.is_empty() else 0)

func _publish_state() -> void:
	var public_state := {
		"player_order": player_order,
		"table_pairs": table_pairs,
		"trump_suit": trump_suit,
		"deck_count": deck.size(),
		"attacker": attacker,
		"defender": defender,
		"current_attacker": current_attacker,
		"status": status_text,
		"game_started": game_started,
		"round_finished": round_finished,
		"hand_counts": _hand_counts()
	}
	state_changed.emit(public_state.duplicate(true))
	_apply_public_state.rpc(public_state)
	for id in player_order:
		if id == 1:
			private_hand_changed.emit((hands.get(id, []) as Array).duplicate(true))
		else:
			_send_private_hand.rpc_id(id, hands.get(id, []))

@rpc("authority", "call_remote", "reliable")
func _apply_public_state(state: Dictionary) -> void:
	state_changed.emit(state)
	notice_changed.emit(str(state.get("status", "")))

@rpc("authority", "call_remote", "reliable")
func _send_private_hand(cards: Array) -> void:
	private_hand_changed.emit(cards.duplicate(true))

func _hand_counts() -> Dictionary:
	var counts: Dictionary = {}
	for id in player_order:
		counts[str(id)] = (hands.get(id, []) as Array).size()
	return counts
