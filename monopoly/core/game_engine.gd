class_name GameEngine
extends RefCounted
## Motor de reglas: máquina de estados finitos independiente de la vista.
##
## Todo el estado vive en `s` (un Dictionary serializable) para poder enviarlo por red.
## La única forma de mutarlo es `apply(cmd)`, que valida el comando y devuelve
## {ok, error, events}. Las vistas y el audio reaccionan a los eventos; nunca tocan `s`.

const PRE_ROLL := "pre_roll"
const AWAIT_BUY := "await_buy"
const AUCTION := "auction"
const DEBT := "debt"
const POST_ROLL := "post_roll"
const GAME_OVER := "game_over"
const RESOLVING := "resolving"

const BANK := -1
const POT := -2
const HOTEL := 5

## Caras del dado turbo: 1-3 suman, BOLT salta a la siguiente propiedad libre, STAR da un bono.
const SPEED_BOLT := 4
const SPEED_STAR := 5
const SPEED_FACES := [1, 2, 3, SPEED_BOLT, SPEED_BOLT, SPEED_STAR]
const SPEED_STAR_BONUS := 50
const MAX_TRADE_PROPOSALS_PER_TURN := 3

var board: Board
var rules: RulesConfig
var s: Dictionary = {}
var rng := RandomNumberGenerator.new()
## Solo para pruebas: tiradas predefinidas [[d1, d2], ...] (o [d1, d2, turbo]).
var forced_dice: Array = []

var _events: Array = []


func _init(p_board: Board, p_rules: RulesConfig = null) -> void:
	board = p_board
	rules = p_rules if p_rules else RulesConfig.classic()


# ---------------------------------------------------------------------------
# Creación / serialización
# ---------------------------------------------------------------------------

## seats: Array de Dictionary {uuid, name, nick, token, color, ai} (ai: -1 humano, 0..2 nivel IA)
func new_game(seats: Array, p_seed: int = 0) -> void:
	if p_seed == 0:
		p_seed = int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
	rng.seed = p_seed
	var n := board.size()
	var players := []
	for i in seats.size():
		var seat: Dictionary = seats[i]
		players.append({
			"id": i,
			"uuid": seat.get("uuid", "seat-%d" % i),
			"name": seat.get("name", "Jugador %d" % (i + 1)),
			"nick": seat.get("nick", ""),
			"token": seat.get("token", board.tokens[i % board.tokens.size()]),
			"color": seat.get("color", "#ffffff"),
			"ai": int(seat.get("ai", -1)),
			"connected": true,
			"cash": board.start_cash,
			"pos": 0,
			"in_jail": false,
			"jail_turns": 0,
			"jail_cards": [],
			"bankrupt": false,
		})
	var decks := {}
	for deck_name in board.decks.keys():
		var order := range(board.decks[deck_name].size())
		_shuffle(order)
		decks[deck_name] = order
	var owner := []
	var houses := []
	var mortgaged := []
	owner.resize(n)
	owner.fill(-1)
	houses.resize(n)
	houses.fill(0)
	mortgaged.resize(n)
	mortgaged.fill(false)
	s = {
		"phase": PRE_ROLL,
		"current": 0,
		"doubles": 0,
		"dice": [0, 0, 0],
		"rolled": false,
		"extra_roll": false,
		"bolt_pending": false,
		"players": players,
		"owner": owner,
		"houses": houses,
		"mortgaged": mortgaged,
		"decks": decks,
		"pot": 0,
		"houses_left": board.houses_total,
		"hotels_left": board.hotels_total,
		"pending_buy": -1,
		"auction": {},
		"debts": [],
		"continuation": "",
		"pending_move": 0,
		"trade": {},
		"trade_proposals": 0,
		"auction_queue": [],
		"resume_phase": "",
		"round": 1,
		"turns": 0,
		"winner": -1,
		"last_card": {},
		"rules": rules.to_dict(),
		"rng_state": rng.state,
	}
	_events = []
	_ev("turn_started", {"player": 0, "round": 1})


func snapshot() -> Dictionary:
	s["rng_state"] = rng.state
	return s.duplicate(true)


func load_snapshot(snap: Dictionary) -> void:
	s = snap.duplicate(true)
	rules = RulesConfig.from_dict(s.get("rules", {}))
	if s.has("rng_state"):
		rng.state = int(s["rng_state"])


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

## cmd: {type: String, player: int, ...}
func apply(cmd: Dictionary) -> Dictionary:
	_events = []
	var err := _run(cmd)
	s["rng_state"] = rng.state
	return {"ok": err == "", "error": err, "events": _events}


func phase() -> String:
	return s.get("phase", "")


func current() -> int:
	return int(s["current"])


func player(pid: int) -> Dictionary:
	return s["players"][pid]


func players() -> Array:
	return s["players"]


func owner_of(i: int) -> int:
	return int(s["owner"][i])


func houses_on(i: int) -> int:
	return int(s["houses"][i])


func is_mortgaged(i: int) -> bool:
	return bool(s["mortgaged"][i])


func is_over() -> bool:
	return phase() == GAME_OVER


## Jugador del que se espera la siguiente decisión.
func pending_actor() -> int:
	match phase():
		GAME_OVER:
			return -1
		AUCTION:
			var a: Dictionary = s["auction"]
			return int(a["bidders"][a["turn"]])
		DEBT:
			return int(s["debts"][0]["debtor"])
	if not s["trade"].is_empty():
		return int(s["trade"]["to"])
	return current()


func active_players() -> Array:
	var out := []
	for p in s["players"]:
		if not p["bankrupt"]:
			out.append(int(p["id"]))
	return out


func properties_of(pid: int) -> Array:
	var out := []
	for i in board.size():
		if owner_of(i) == pid:
			out.append(i)
	return out


func owns_group(pid: int, group: String) -> bool:
	if group == "":
		return false
	for i in board.group_members(group):
		if owner_of(i) != pid:
			return false
	return true


func net_worth(pid: int) -> int:
	var p := player(pid)
	var total: int = p["cash"]
	for i in properties_of(pid):
		total += board.price(i) - (board.mortgage_value(i) if is_mortgaged(i) else 0)
		total += _building_units(i) * board.house_cost(i)
	return total


## Dinero máximo que el jugador puede reunir vendiendo edificios e hipotecando.
func liquidation_value(pid: int) -> int:
	var total: int = player(pid)["cash"]
	for i in properties_of(pid):
		total += _building_units(i) * board.house_cost(i) / 2
		if not is_mortgaged(i):
			total += board.mortgage_value(i)
	return total


func rent_for(i: int, dice_total: int = -1) -> int:
	var own := owner_of(i)
	if own < 0 or is_mortgaged(i):
		return 0
	if rules.no_rent_in_jail and player(own)["in_jail"]:
		return 0
	var sp := board.space(i)
	match sp["type"]:
		"street":
			var h := houses_on(i)
			if h > 0:
				return int(sp["rents"][h])
			var base := int(sp["rents"][0])
			return base * 2 if owns_group(own, sp["group"]) else base
		"transit":
			var n := _count_owned_in_group(own, sp["group"])
			return int(sp["rents"][clampi(n - 1, 0, 3)])
		"utility":
			var n2 := _count_owned_in_group(own, sp["group"])
			if dice_total < 0:
				dice_total = int(s["dice"][0]) + int(s["dice"][1])
			return int(sp["multipliers"][clampi(n2 - 1, 0, 1)]) * dice_total
	return 0


func can_build(pid: int, i: int) -> String:
	if not board.is_street(i):
		return "Solo se construye en calles"
	if owner_of(i) != pid:
		return "No es tu propiedad"
	var group := board.group_of(i)
	if not owns_group(pid, group):
		return "Necesitas todo el grupo de color"
	for j in board.group_members(group):
		if is_mortgaged(j):
			return "Hay propiedades hipotecadas en el grupo"
	var lvl := _level(i)
	var max_lvl := rules.houses_per_hotel + 1
	if lvl >= max_lvl:
		return "Ya tiene hotel"
	for j in board.group_members(group):
		if _level(j) < lvl:
			return "Debes construir de forma pareja"
	if player(pid)["cash"] < board.house_cost(i):
		return "Dinero insuficiente"
	if lvl == rules.houses_per_hotel:
		if int(s["hotels_left"]) <= 0:
			return "El banco no tiene hoteles"
	elif int(s["houses_left"]) <= 0:
		return "El banco no tiene casas"
	return ""


func can_sell_building(pid: int, i: int) -> String:
	if owner_of(i) != pid or not board.is_street(i):
		return "No es tu propiedad"
	var lvl := _level(i)
	if lvl == 0:
		return "No hay edificios"
	for j in board.group_members(board.group_of(i)):
		if _level(j) > lvl:
			return "Debes vender de forma pareja"
	return ""


func can_mortgage(pid: int, i: int) -> String:
	if owner_of(i) != pid:
		return "No es tu propiedad"
	if is_mortgaged(i):
		return "Ya está hipotecada"
	if board.group_of(i) != "":
		for j in board.group_members(board.group_of(i)):
			if houses_on(j) > 0:
				return "Vende primero los edificios del grupo"
	return ""


func can_unmortgage(pid: int, i: int) -> String:
	if owner_of(i) != pid:
		return "No es tu propiedad"
	if not is_mortgaged(i):
		return "No está hipotecada"
	if player(pid)["cash"] < unmortgage_cost(i):
		return "Dinero insuficiente"
	return ""


## Acciones disponibles para un jugador (para UI e IA).
func legal_actions(pid: int) -> Array:
	var out := []
	if is_over() or pid < 0 or player(pid)["bankrupt"]:
		return out
	var ph := phase()
	var trade: Dictionary = s["trade"]
	if not trade.is_empty():
		if int(trade["to"]) == pid:
			out.append_array(["trade_accept", "trade_reject"])
		if int(trade["from"]) == pid:
			out.append("trade_cancel")
		return out
	match ph:
		PRE_ROLL:
			if pid == current():
				out.append("roll")
				var p := player(pid)
				if p["in_jail"]:
					if p["cash"] >= board.jail_fine:
						out.append("pay_jail")
					if not p["jail_cards"].is_empty():
						out.append("use_jail_card")
				out.append_array(["build", "sell_building", "mortgage", "unmortgage", "trade_propose"])
		POST_ROLL:
			if pid == current():
				out.append_array(["end_turn", "build", "sell_building", "mortgage", "unmortgage", "trade_propose"])
		AWAIT_BUY:
			if pid == current():
				if player(pid)["cash"] >= board.price(int(s["pending_buy"])):
					out.append("buy")
				out.append_array(["decline", "sell_building", "mortgage"])
		AUCTION:
			if pid == pending_actor():
				out.append_array(["bid", "pass_bid", "sell_building", "mortgage"])
		DEBT:
			if pid == pending_actor():
				if player(pid)["cash"] >= int(s["debts"][0]["amount"]):
					out.append("pay_debt")
				out.append_array(["sell_building", "mortgage", "bankrupt"])
	return out


# ---------------------------------------------------------------------------
# Despacho de comandos
# ---------------------------------------------------------------------------

func _run(cmd: Dictionary) -> String:
	if s.is_empty():
		return "Partida no iniciada"
	if is_over():
		return "La partida terminó"
	var t: String = cmd.get("type", "")
	var pid := int(cmd.get("player", -1))
	if pid < 0 or pid >= s["players"].size():
		return "Jugador inválido"
	if player(pid)["bankrupt"]:
		return "Jugador en bancarrota"
	if not s["trade"].is_empty() and not t.begins_with("trade_"):
		return "Hay un intercambio pendiente"
	var i := int(cmd.get("space", -1))
	match t:
		"roll":
			return _cmd_roll(pid)
		"pay_jail":
			return _cmd_pay_jail(pid)
		"use_jail_card":
			return _cmd_use_jail_card(pid)
		"buy":
			return _cmd_buy(pid)
		"decline":
			return _cmd_decline(pid)
		"bid":
			return _cmd_bid(pid, int(cmd.get("amount", 0)))
		"pass_bid":
			return _cmd_pass_bid(pid)
		"build":
			return _cmd_build(pid, i)
		"sell_building":
			return _cmd_sell_building(pid, i)
		"mortgage":
			return _cmd_mortgage(pid, i)
		"unmortgage":
			return _cmd_unmortgage(pid, i)
		"end_turn":
			return _cmd_end_turn(pid)
		"pay_debt":
			return _cmd_pay_debt(pid)
		"bankrupt":
			return _cmd_bankrupt(pid)
		"trade_propose":
			return _cmd_trade_propose(pid, cmd)
		"trade_accept":
			return _cmd_trade_accept(pid)
		"trade_reject":
			return _cmd_trade_close(pid, "to", "rejected")
		"trade_cancel":
			return _cmd_trade_close(pid, "from", "cancelled")
	return "Comando desconocido: %s" % t


func _require_turn(pid: int, phases: Array) -> String:
	if pid != current():
		return "No es tu turno"
	if not phase() in phases:
		return "Acción no permitida ahora"
	return ""


# --- Dados y movimiento -----------------------------------------------------

func _cmd_roll(pid: int) -> String:
	var err := _require_turn(pid, [PRE_ROLL])
	if err != "":
		return err
	var p := player(pid)
	var d := _roll_dice(not p["in_jail"] and rules.speed_die)
	s["dice"] = d
	s["rolled"] = true
	var is_double: bool = d[0] == d[1]
	_ev("dice_rolled", {"player": pid, "dice": d, "double": is_double})
	s["phase"] = RESOLVING

	if p["in_jail"]:
		if is_double:
			p["in_jail"] = false
			p["jail_turns"] = 0
			s["extra_roll"] = false
			_ev("jail_released", {"player": pid, "reason": "doubles"})
			_move(pid, d[0] + d[1])
			return ""
		p["jail_turns"] += 1
		if p["jail_turns"] >= 3:
			# Tercer intento fallido: paga la multa y mueve con esta tirada.
			p["in_jail"] = false
			p["jail_turns"] = 0
			_ev("jail_released", {"player": pid, "reason": "forced_fine"})
			s["continuation"] = "jail_move"
			s["pending_move"] = d[0] + d[1]
			_charge(pid, _fine_sink(), board.jail_fine, "Multa del Retén")
			_resolve_done()
			return ""
		s["extra_roll"] = false
		_resolve_done()
		return ""

	if is_double:
		s["doubles"] += 1
		if s["doubles"] >= 3:
			_ev("three_doubles", {"player": pid})
			_send_to_jail(pid)
			_resolve_done()
			return ""
	s["extra_roll"] = is_double
	var steps: int = d[0] + d[1]
	if d[2] in [1, 2, 3]:
		steps += d[2]
	elif d[2] == SPEED_BOLT:
		s["bolt_pending"] = true
	elif d[2] == SPEED_STAR:
		_transfer(BANK, pid, SPEED_STAR_BONUS, "Bono turbo")
	_move(pid, steps)
	return ""


func _roll_dice(with_speed: bool) -> Array:
	if not forced_dice.is_empty():
		var f: Array = forced_dice.pop_front()
		return [int(f[0]), int(f[1]), int(f[2]) if f.size() > 2 else 0]
	var d1 := rng.randi_range(1, 6)
	var d2 := rng.randi_range(1, 6)
	var d3 := 0
	if with_speed:
		d3 = SPEED_FACES[rng.randi_range(0, 5)]
	return [d1, d2, d3]


func _move(pid: int, steps: int) -> void:
	var p := player(pid)
	var n := board.size()
	var from: int = p["pos"]
	var path := []
	var passed_go := false
	var dir := 1 if steps >= 0 else -1
	for k in absi(steps):
		var nxt := posmod(int(p["pos"]) + dir, n)
		p["pos"] = nxt
		path.append(nxt)
		if dir > 0 and nxt == 0:
			passed_go = true
	_ev("moved", {"player": pid, "from": from, "to": p["pos"], "path": path})
	if passed_go:
		_transfer(BANK, pid, board.salary, "Sueldo")
	_land(pid)


func _move_forward_to(pid: int, target: int) -> void:
	var from: int = player(pid)["pos"]
	var steps := posmod(target - from, board.size())
	if steps == 0:
		steps = board.size()
	_move(pid, steps)


func _land(pid: int) -> void:
	var p := player(pid)
	var i: int = p["pos"]
	var sp := board.space(i)
	_ev("landed", {"player": pid, "space": i})
	match sp["type"]:
		"street", "transit", "utility":
			var own := owner_of(i)
			if own == -1:
				s["pending_buy"] = i
				s["phase"] = AWAIT_BUY
				_ev("offer_buy", {"player": pid, "space": i, "price": board.price(i)})
				return
			if own != pid:
				var rent := rent_for(i)
				if rent > 0:
					_ev("rent_due", {"player": pid, "owner": own, "space": i, "amount": rent})
					_charge(pid, own, rent, "Alquiler de %s" % sp["name"])
		"tax":
			_ev("tax_due", {"player": pid, "space": i, "amount": int(sp["amount"])})
			_charge(pid, _fine_sink(), int(sp["amount"]), sp["name"])
		"card":
			if _draw_card(pid, sp["deck"]):
				return
		"gotojail":
			_send_to_jail(pid)
		"free":
			if rules.free_parking_pot and int(s["pot"]) > 0:
				var amount: int = s["pot"]
				s["pot"] = 0
				_transfer(BANK, pid, amount, "Bote del Mirador")
				_ev("pot_collected", {"player": pid, "amount": amount})
		"go":
			if rules.double_salary_on_go:
				_transfer(BANK, pid, board.salary, "Bono por caer en la Salida")
	_resolve_done()


func _send_to_jail(pid: int) -> void:
	var p := player(pid)
	p["pos"] = board.jail_index
	p["in_jail"] = true
	p["jail_turns"] = 0
	if pid == current():
		s["doubles"] = 0
		s["extra_roll"] = false
		s["bolt_pending"] = false
	_ev("jailed", {"player": pid, "space": board.jail_index})


## Se llama cuando termina de resolverse una caída (o un paso bloqueante).
func _resolve_done() -> void:
	if is_over():
		return
	if _process_debts():
		return
	var cont: String = s["continuation"]
	s["continuation"] = ""
	if cont == "resume":
		# Vuelve a la fase previa (p. ej. tras pagar el interés de un intercambio antes de tirar).
		s["phase"] = s["resume_phase"]
		return
	# Reglas oficiales: el banco subasta las propiedades de quien quebró ante él.
	var queue: Array = s.get("auction_queue", [])
	if not queue.is_empty():
		s["continuation"] = cont
		_start_auction(int(queue.pop_front()), -1)
		return
	var cur := current()
	var p := player(cur)
	if cont == "jail_move" and not p["bankrupt"]:
		var steps: int = s["pending_move"]
		s["pending_move"] = 0
		s["phase"] = RESOLVING
		_move(cur, steps)
		return
	if p["bankrupt"]:
		_next_turn()
		return
	if s["bolt_pending"]:
		s["bolt_pending"] = false
		if not p["in_jail"]:
			var target := _next_unowned_from(int(p["pos"]))
			if target >= 0:
				_ev("speed_bolt", {"player": cur, "target": target})
				s["phase"] = RESOLVING
				_move_forward_to(cur, target)
				return
	if s["extra_roll"] and not p["in_jail"]:
		s["phase"] = PRE_ROLL
		_ev("extra_roll", {"player": cur})
	else:
		s["phase"] = POST_ROLL
	_ev("phase", {"phase": s["phase"]})


func _next_unowned_from(from: int) -> int:
	var n := board.size()
	for k in range(1, n):
		var i := (from + k) % n
		if board.is_property(i) and owner_of(i) == -1:
			return i
	return -1


# --- Cárcel -----------------------------------------------------------------

func _cmd_pay_jail(pid: int) -> String:
	var err := _require_turn(pid, [PRE_ROLL])
	if err != "":
		return err
	var p := player(pid)
	if not p["in_jail"]:
		return "No estás en el Retén"
	if p["cash"] < board.jail_fine:
		return "Dinero insuficiente"
	_transfer(pid, _fine_sink(), board.jail_fine, "Multa del Retén")
	p["in_jail"] = false
	p["jail_turns"] = 0
	_ev("jail_released", {"player": pid, "reason": "paid"})
	return ""


func _cmd_use_jail_card(pid: int) -> String:
	var err := _require_turn(pid, [PRE_ROLL])
	if err != "":
		return err
	var p := player(pid)
	if not p["in_jail"] or p["jail_cards"].is_empty():
		return "No puedes usar un salvoconducto"
	var deck_name: String = p["jail_cards"].pop_back()
	_return_jail_card(deck_name)
	p["in_jail"] = false
	p["jail_turns"] = 0
	_ev("jail_released", {"player": pid, "reason": "card"})
	return ""


func _return_jail_card(deck_name: String) -> void:
	var cards: Array = board.decks[deck_name]
	for idx in cards.size():
		if cards[idx]["action"] == "jail_free" and not s["decks"][deck_name].has(idx):
			s["decks"][deck_name].append(idx)
			return


# --- Cartas -------------------------------------------------------------------

## Devuelve true si la carta movió al jugador (la resolución continúa en _land).
func _draw_card(pid: int, deck_name: String) -> bool:
	var order: Array = s["decks"][deck_name]
	if order.is_empty():
		return false
	var idx: int = order.pop_front()
	var card: Dictionary = board.decks[deck_name][idx]
	if card["action"] != "jail_free":
		order.append(idx)
	s["last_card"] = {"deck": deck_name, "index": idx, "text": card["text"]}
	_ev("card_drawn", {"player": pid, "deck": deck_name, "index": idx, "text": card["text"]})
	match card["action"]:
		"money":
			var amount := int(card["amount"])
			if amount >= 0:
				_transfer(BANK, pid, amount, "Carta")
			else:
				_charge(pid, _fine_sink(), -amount, "Carta")
		"move_to":
			s["phase"] = RESOLVING
			_move_forward_to(pid, int(card["target"]))
			return true
		"nearest":
			var target := _nearest_of_type(int(player(pid)["pos"]), card["kind"])
			if target >= 0:
				_move_forward_to(pid, target)
				return true
		"move_rel":
			_move(pid, int(card["steps"]))
			return true
		"jail":
			_send_to_jail(pid)
		"jail_free":
			player(pid)["jail_cards"].append(deck_name)
		"repairs":
			var total := 0
			for i in properties_of(pid):
				var h := houses_on(i)
				total += int(card["hotel"]) if h == HOTEL else h * int(card["house"])
			if total > 0:
				_charge(pid, _fine_sink(), total, "Reparaciones")
		"pay_each":
			for other in active_players():
				if other != pid:
					_charge(pid, other, int(card["amount"]), "Carta")
		"collect_each":
			for other in active_players():
				if other != pid:
					_charge(other, pid, int(card["amount"]), "Carta")
	return false


func _nearest_of_type(from: int, kind: String) -> int:
	var n := board.size()
	for k in range(1, n + 1):
		var i := (from + k) % n
		if board.space(i)["type"] == kind:
			return i
	return -1


# --- Compra y subasta ---------------------------------------------------------

func _cmd_buy(pid: int) -> String:
	var err := _require_turn(pid, [AWAIT_BUY])
	if err != "":
		return err
	var i: int = s["pending_buy"]
	if player(pid)["cash"] < board.price(i):
		return "Dinero insuficiente"
	_transfer(pid, BANK, board.price(i), "Compra de %s" % board.space(i)["name"])
	s["owner"][i] = pid
	s["pending_buy"] = -1
	_ev("bought", {"player": pid, "space": i, "price": board.price(i)})
	s["phase"] = RESOLVING
	_resolve_done()
	return ""


func _cmd_decline(pid: int) -> String:
	var err := _require_turn(pid, [AWAIT_BUY])
	if err != "":
		return err
	var i: int = s["pending_buy"]
	s["pending_buy"] = -1
	_ev("declined", {"player": pid, "space": i})
	_start_auction(i, pid)
	return ""


## decliner = -1: subasta del banco abierta a todos, empezando tras el jugador actual.
func _start_auction(i: int, decliner: int) -> void:
	var bidders := []
	var n: int = s["players"].size()
	var start := decliner if decliner >= 0 else current()
	for k in range(1, n + 1):
		var pid := (start + k) % n
		if player(pid)["bankrupt"]:
			continue
		if pid == decliner and not rules.auction_includes_decliner:
			continue
		bidders.append(pid)
	if bidders.is_empty():
		s["phase"] = RESOLVING
		_resolve_done()
		return
	s["auction"] = {"space": i, "bidders": bidders, "turn": 0, "high": 0, "high_bidder": -1}
	s["phase"] = AUCTION
	_ev("auction_started", {"space": i, "bidders": bidders.duplicate()})


func min_bid() -> int:
	var a: Dictionary = s["auction"]
	# Reglamento: la primera puja puede ser de cualquier monto; las siguientes suben de a Bs 10.
	return int(a["high"]) + rules.auction_min_increment if int(a["high_bidder"]) >= 0 else 1


func _cmd_bid(pid: int, amount: int) -> String:
	if phase() != AUCTION or pid != pending_actor():
		return "No es tu turno de pujar"
	if amount < min_bid():
		return "La puja mínima es Bs %d" % min_bid()
	if amount > int(player(pid)["cash"]):
		return "Dinero insuficiente"
	var a: Dictionary = s["auction"]
	a["high"] = amount
	a["high_bidder"] = pid
	_ev("bid", {"player": pid, "amount": amount})
	_advance_auction(false)
	return ""


func _cmd_pass_bid(pid: int) -> String:
	if phase() != AUCTION or pid != pending_actor():
		return "No es tu turno de pujar"
	var a: Dictionary = s["auction"]
	a["bidders"].remove_at(a["turn"])
	_ev("bid_pass", {"player": pid})
	_advance_auction(true)
	return ""


func _advance_auction(removed: bool) -> void:
	var a: Dictionary = s["auction"]
	var bidders: Array = a["bidders"]
	var hb: int = a["high_bidder"]
	if bidders.is_empty() or (bidders.size() == 1 and int(bidders[0]) == hb):
		_end_auction()
		return
	if not removed:
		a["turn"] = (int(a["turn"]) + 1) % bidders.size()
	else:
		a["turn"] = int(a["turn"]) % bidders.size()
	# El mejor postor no puja contra sí mismo.
	if int(bidders[a["turn"]]) == hb:
		a["turn"] = (int(a["turn"]) + 1) % bidders.size()


func _end_auction() -> void:
	var a: Dictionary = s["auction"]
	var i: int = a["space"]
	var winner: int = a["high_bidder"]
	if winner >= 0:
		_transfer(winner, BANK, int(a["high"]), "Subasta de %s" % board.space(i)["name"])
		s["owner"][i] = winner
	_ev("auction_ended", {"space": i, "winner": winner, "amount": int(a["high"])})
	s["auction"] = {}
	s["phase"] = RESOLVING
	_resolve_done()


# --- Construcción e hipotecas ----------------------------------------------------

func _can_manage(pid: int) -> String:
	var ph := phase()
	if ph == DEBT or ph == AUCTION:
		# En deuda o en una subasta, quien tiene el turno puede reunir dinero.
		return "" if pid == pending_actor() else "No puedes gestionar ahora"
	if pid != current():
		return "No es tu turno"
	if ph in [PRE_ROLL, POST_ROLL, AWAIT_BUY]:
		return ""
	return "No puedes gestionar ahora"


func _cmd_build(pid: int, i: int) -> String:
	var err := _can_manage(pid)
	if err == "" and phase() in [DEBT, AWAIT_BUY, AUCTION]:
		err = "Ahora solo puedes conseguir dinero"
	if err == "":
		err = can_build(pid, i) if i >= 0 else "Casilla inválida"
	if err != "":
		return err
	var cost := board.house_cost(i)
	_transfer(pid, BANK, cost, "Construcción")
	if _level(i) == rules.houses_per_hotel:
		s["houses_left"] += rules.houses_per_hotel
		s["hotels_left"] -= 1
		s["houses"][i] = HOTEL
	else:
		s["houses_left"] -= 1
		s["houses"][i] += 1
	_ev("built", {"player": pid, "space": i, "houses": houses_on(i)})
	return ""


func _cmd_sell_building(pid: int, i: int) -> String:
	var err := _can_manage(pid)
	if err == "":
		err = can_sell_building(pid, i) if i >= 0 else "Casilla inválida"
	if err != "":
		return err
	var refund := board.house_cost(i) / 2
	if houses_on(i) == HOTEL:
		var need := rules.houses_per_hotel
		if int(s["houses_left"]) >= need:
			s["houses_left"] -= need
			s["hotels_left"] += 1
			s["houses"][i] = need
		else:
			# Sin casas en el banco el hotel se desarma por completo.
			s["hotels_left"] += 1
			s["houses"][i] = 0
			refund *= need + 1
	else:
		s["houses_left"] += 1
		s["houses"][i] -= 1
	_transfer(BANK, pid, refund, "Venta de edificio")
	_ev("sold_building", {"player": pid, "space": i, "houses": houses_on(i)})
	return ""


func _cmd_mortgage(pid: int, i: int) -> String:
	var err := _can_manage(pid)
	if err == "":
		err = can_mortgage(pid, i) if i >= 0 else "Casilla inválida"
	if err != "":
		return err
	s["mortgaged"][i] = true
	_transfer(BANK, pid, board.mortgage_value(i), "Hipoteca")
	_ev("mortgaged", {"player": pid, "space": i})
	return ""


func _cmd_unmortgage(pid: int, i: int) -> String:
	var err := _can_manage(pid)
	if err == "" and phase() in [DEBT, AWAIT_BUY, AUCTION]:
		err = "Ahora solo puedes conseguir dinero"
	if err == "":
		err = can_unmortgage(pid, i) if i >= 0 else "Casilla inválida"
	if err != "":
		return err
	_transfer(pid, BANK, unmortgage_cost(i), "Levantar hipoteca")
	s["interest_paid"] = s.get("interest_paid", []).filter(func(x): return int(x) != i)
	s["mortgaged"][i] = false
	_ev("unmortgaged", {"player": pid, "space": i})
	return ""


# --- Deudas y bancarrota -------------------------------------------------------

func _fine_sink() -> int:
	return POT if rules.free_parking_pot else BANK


func _charge(debtor: int, creditor: int, amount: int, reason: String) -> void:
	if amount <= 0:
		return
	s["debts"].append({"debtor": debtor, "creditor": creditor, "amount": amount, "reason": reason})


## Liquida las deudas pendientes. Devuelve true si alguna bloquea (fase DEBT).
func _process_debts() -> bool:
	var debts: Array = s["debts"]
	while not debts.is_empty():
		var d: Dictionary = debts[0]
		var p := player(int(d["debtor"]))
		if p["bankrupt"] or (int(d["creditor"]) >= 0 and player(int(d["creditor"]))["bankrupt"]):
			debts.pop_front()
			continue
		if int(p["cash"]) >= int(d["amount"]):
			_transfer(int(d["debtor"]), int(d["creditor"]), int(d["amount"]), d["reason"])
			debts.pop_front()
			continue
		s["phase"] = DEBT
		_ev("debt", d.duplicate())
		return true
	return false


func _cmd_pay_debt(pid: int) -> String:
	if phase() != DEBT or pid != pending_actor():
		return "No tienes deudas pendientes"
	if int(player(pid)["cash"]) < int(s["debts"][0]["amount"]):
		return "Dinero insuficiente: hipoteca o vende edificios"
	s["phase"] = RESOLVING
	_resolve_done()
	return ""


func _cmd_bankrupt(pid: int) -> String:
	var creditor := BANK
	if phase() == DEBT and pid == pending_actor():
		creditor = int(s["debts"][0]["creditor"])
	elif pid != current() or not phase() in [PRE_ROLL, POST_ROLL]:
		return "No puedes declararte en bancarrota ahora"
	_bankrupt(pid, creditor)
	if is_over():
		return ""
	s["phase"] = RESOLVING
	_resolve_done()
	return ""


func _bankrupt(pid: int, creditor: int) -> void:
	var p := player(pid)
	if creditor == POT:
		creditor = BANK
	# Los edificios vuelven al banco a mitad de precio.
	for i in properties_of(pid):
		var units := _building_units(i)
		if units > 0:
			p["cash"] += units * board.house_cost(i) / 2
			if houses_on(i) == HOTEL:
				s["hotels_left"] += 1
			else:
				s["houses_left"] += houses_on(i)
			s["houses"][i] = 0
	if creditor >= 0:
		var c := player(creditor)
		c["cash"] += p["cash"]
		_ev("money", {"player": creditor, "delta": p["cash"], "reason": "Bancarrota de %s" % p["name"]})
		for i in properties_of(pid):
			s["owner"][i] = creditor
			_charge_mortgage_interest(creditor, i)
		c["jail_cards"].append_array(p["jail_cards"])
	else:
		for i in properties_of(pid):
			s["owner"][i] = -1
			s["mortgaged"][i] = false
			s["auction_queue"].append(i)
		for deck_name in p["jail_cards"]:
			_return_jail_card(deck_name)
	p["jail_cards"] = []
	p["cash"] = 0
	p["bankrupt"] = true
	p["in_jail"] = false
	var keep := []
	for d in s["debts"]:
		if int(d["debtor"]) != pid and int(d["creditor"]) != pid:
			keep.append(d)
	s["debts"] = keep
	if not s["trade"].is_empty() and (int(s["trade"]["from"]) == pid or int(s["trade"]["to"]) == pid):
		s["trade"] = {}
	_ev("bankrupt", {"player": pid, "creditor": creditor})
	if active_players().size() <= 1 or rules.end_on_first_bankruptcy:
		_game_over("bankruptcy")


func _game_over(reason: String) -> void:
	var best := -1
	var best_worth := -1
	for pid in active_players():
		var w := net_worth(pid)
		if w > best_worth:
			best_worth = w
			best = pid
	s["winner"] = best
	s["auction_queue"] = []
	s["phase"] = GAME_OVER
	var ranking := []
	for p in s["players"]:
		ranking.append({"player": p["id"], "worth": 0 if p["bankrupt"] else net_worth(int(p["id"])), "bankrupt": p["bankrupt"]})
	ranking.sort_custom(func(a, b): return a["worth"] > b["worth"])
	_ev("game_over", {"winner": best, "reason": reason, "ranking": ranking})


# --- Turnos ---------------------------------------------------------------------

func _cmd_end_turn(pid: int) -> String:
	var err := _require_turn(pid, [POST_ROLL])
	if err != "":
		return err
	_next_turn()
	return ""


func _next_turn() -> void:
	var n: int = s["players"].size()
	var cur := current()
	var wrapped := false
	for k in range(1, n + 1):
		var nxt := (cur + k) % n
		if nxt <= cur:
			wrapped = true
		if not player(nxt)["bankrupt"]:
			s["current"] = nxt
			break
	if wrapped:
		s["round"] += 1
		if rules.max_rounds > 0 and int(s["round"]) > rules.max_rounds:
			_game_over("rounds")
			return
	s["pending_buy"] = -1
	s["turns"] += 1
	s["doubles"] = 0
	s["rolled"] = false
	s["extra_roll"] = false
	s["bolt_pending"] = false
	s["trade_proposals"] = 0
	s["interest_paid"] = []
	s["phase"] = PRE_ROLL
	_ev("turn_started", {"player": current(), "round": s["round"]})


# --- Intercambios ---------------------------------------------------------------

## cmd: {to, give: {cash, props, cards}, get: {cash, props, cards}}
func _cmd_trade_propose(pid: int, cmd: Dictionary) -> String:
	var err := _require_turn(pid, [PRE_ROLL, POST_ROLL])
	if err != "":
		return err
	if not s["trade"].is_empty():
		return "Ya hay un intercambio pendiente"
	if int(s["trade_proposals"]) >= MAX_TRADE_PROPOSALS_PER_TURN:
		return "Demasiadas propuestas este turno"
	var to := int(cmd.get("to", -1))
	if to < 0 or to >= s["players"].size() or to == pid or player(to)["bankrupt"]:
		return "Destinatario inválido"
	var give := _norm_offer(cmd.get("give", {}))
	var get_ := _norm_offer(cmd.get("get", {}))
	if give["cash"] == 0 and give["props"].is_empty() and give["cards"] == 0 \
			and get_["cash"] == 0 and get_["props"].is_empty() and get_["cards"] == 0:
		return "El intercambio está vacío"
	err = _validate_offer(pid, give)
	if err == "":
		err = _validate_offer(to, get_)
	if err != "":
		return err
	s["trade_proposals"] += 1
	s["trade"] = {"from": pid, "to": to, "give": give, "get": get_}
	_ev("trade_proposed", s["trade"].duplicate(true))
	return ""


func _norm_offer(o: Dictionary) -> Dictionary:
	var props := []
	for x in o.get("props", []):
		props.append(int(x))
	return {"cash": maxi(0, int(o.get("cash", 0))), "props": props, "cards": maxi(0, int(o.get("cards", 0)))}


func _validate_offer(pid: int, o: Dictionary) -> String:
	var p := player(pid)
	if o["cash"] > int(p["cash"]):
		return "%s no tiene ese dinero" % p["name"]
	if o["cards"] > p["jail_cards"].size():
		return "%s no tiene esos salvoconductos" % p["name"]
	for i in o["props"]:
		if i < 0 or i >= board.size() or owner_of(i) != pid:
			return "Propiedad inválida en el intercambio"
		for j in board.group_members(board.group_of(i)):
			if houses_on(j) > 0:
				return "No se pueden intercambiar grupos con edificios"
	return ""


func _cmd_trade_accept(pid: int) -> String:
	var t: Dictionary = s["trade"]
	if t.is_empty() or int(t["to"]) != pid:
		return "No hay intercambio para ti"
	var a := int(t["from"])
	var b := int(t["to"])
	var err := _validate_offer(a, t["give"])
	if err == "":
		err = _validate_offer(b, t["get"])
	if err != "":
		s["trade"] = {}
		_ev("trade_resolved", {"from": a, "to": b, "result": "invalid"})
		return err
	_swap(a, b, t["give"])
	_swap(b, a, t["get"])
	s["trade"] = {}
	_ev("trade_resolved", {"from": a, "to": b, "result": "accepted"})
	if not s["debts"].is_empty():
		s["resume_phase"] = phase()
		s["continuation"] = "resume"
		s["phase"] = RESOLVING
		_resolve_done()
	return ""


## Regla oficial: quien recibe una propiedad hipotecada paga al banco el 10 % de la hipoteca.
func _charge_mortgage_interest(receiver: int, i: int) -> void:
	if is_mortgaged(i):
		_charge(receiver, BANK, int(ceil(board.mortgage_value(i) * 0.1)), "Interés de hipoteca")
		if not s.has("interest_paid"):
			s["interest_paid"] = []
		s["interest_paid"].append(i)


## Costo de levantar la hipoteca. Si se recibió hipotecada en este turno ya pagó el 10 %,
## así que levantarla ahora cuesta solo el valor de hipoteca (total: valor + 10 %, como el
## reglamento). Si se espera a otro turno, vuelve a costar valor + 10 %.
func unmortgage_cost(i: int) -> int:
	if i in s.get("interest_paid", []):
		return board.mortgage_value(i)
	return board.unmortgage_cost(i)


func _swap(src: int, dst: int, o: Dictionary) -> void:
	if o["cash"] > 0:
		_transfer(src, dst, o["cash"], "Intercambio")
	for i in o["props"]:
		s["owner"][i] = dst
		_charge_mortgage_interest(dst, int(i))
	for k in o["cards"]:
		player(dst)["jail_cards"].append(player(src)["jail_cards"].pop_back())


func _cmd_trade_close(pid: int, side: String, result: String) -> String:
	var t: Dictionary = s["trade"]
	if t.is_empty() or int(t[side]) != pid:
		return "No hay intercambio que cerrar"
	s["trade"] = {}
	_ev("trade_resolved", {"from": int(t["from"]), "to": int(t["to"]), "result": result})
	return ""


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

func _transfer(from: int, to: int, amount: int, reason: String) -> void:
	if amount == 0:
		return
	if from >= 0:
		player(from)["cash"] -= amount
		_ev("money", {"player": from, "delta": -amount, "reason": reason, "other": to})
	if to >= 0:
		player(to)["cash"] += amount
		_ev("money", {"player": to, "delta": amount, "reason": reason, "other": from})
	elif to == POT:
		s["pot"] += amount
		_ev("pot", {"amount": s["pot"]})


func _level(i: int) -> int:
	var h := houses_on(i)
	return rules.houses_per_hotel + 1 if h == HOTEL else h


## Unidades de construcción pagadas (un hotel cuesta houses_per_hotel + 1).
func _building_units(i: int) -> int:
	return _level(i)


func _count_owned_in_group(pid: int, group: String) -> int:
	var n := 0
	for j in board.group_members(group):
		if owner_of(j) == pid:
			n += 1
	return n


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _ev(type: String, data: Dictionary) -> void:
	data["type"] = type
	_events.append(data)
