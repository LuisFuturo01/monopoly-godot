extends SceneTree
## Pruebas del núcleo de reglas. Ejecutar:
##   Godot_console.exe --headless --path . --script res://tests/run_tests.gd

const BOARD_PATH := "res://data/board_lapaz.json"

var board: Board
var failures := 0
var checks := 0


func _init() -> void:
	board = Board.load_from_file(BOARD_PATH)
	for t in [
		"test_three_doubles_go_to_jail",
		"test_jail_third_failed_roll_pays_and_moves",
		"test_jail_doubles_no_extra_roll",
		"test_buy_rent_and_monopoly_double",
		"test_decline_starts_auction",
		"test_auction_nobody_bids",
		"test_even_building_and_hotel",
		"test_quick_mode_hotel_after_three",
		"test_mortgage_rules",
		"test_debt_then_bankruptcy_to_creditor",
		"test_bankruptcy_to_bank_frees_properties",
		"test_house_rules",
		"test_trade",
		"test_cards_jail_free_leaves_deck",
		"test_snapshot_roundtrip",
		"test_ai_simulation",
	]:
		call(t)
	print("\n%d comprobaciones, %d fallos" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		push_error("FALLO: " + msg)
		print("  FALLO: ", msg)


func mk(n: int = 2, rules: RulesConfig = null) -> GameEngine:
	var e := GameEngine.new(board, rules)
	var seats := []
	for i in n:
		seats.append({"name": "P%d" % i})
	e.new_game(seats, 12345)
	return e


func run(e: GameEngine, cmd: Dictionary) -> Dictionary:
	var r := e.apply(cmd)
	if not r["ok"]:
		print("    (comando rechazado: %s -> %s)" % [cmd, r["error"]])
	return r


func roll(e: GameEngine, pid: int, d1: int, d2: int) -> Dictionary:
	e.forced_dice.append([d1, d2])
	return run(e, {"type": "roll", "player": pid})


func has_event(r: Dictionary, type: String) -> bool:
	for ev in r["events"]:
		if ev["type"] == type:
			return true
	return false


# ---------------------------------------------------------------------------

func test_three_doubles_go_to_jail() -> void:
	print("test_three_doubles_go_to_jail")
	var e := mk()
	roll(e, 0, 2, 2)          # -> 4 (Teleférico Rojo), dobles
	_settle(e, 0)
	check(e.phase() == GameEngine.PRE_ROLL, "tras dobles se vuelve a tirar")
	roll(e, 0, 1, 1)          # -> 6 (Chasquipampa)
	_settle(e, 0)
	var cash_before: int = e.player(0)["cash"]
	var r := roll(e, 0, 3, 3)
	check(has_event(r, "three_doubles"), "tercer doble detectado")
	check(e.player(0)["in_jail"], "va al Retén")
	check(int(e.player(0)["pos"]) == board.jail_index, "posición = Retén")
	check(int(e.player(0)["cash"]) == cash_before, "no cobra sueldo al ir al Retén")
	check(e.phase() == GameEngine.POST_ROLL, "turno termina")


func test_jail_third_failed_roll_pays_and_moves() -> void:
	print("test_jail_third_failed_roll_pays_and_moves")
	var e := mk()
	e._send_to_jail(0)
	for k in 2:
		roll(e, 0, 1, 2)
		check(e.player(0)["in_jail"], "sigue en el Retén intento %d" % (k + 1))
		run(e, {"type": "end_turn", "player": 0})
		roll(e, 1, 6, 5)
		_settle(e, 1)
		run(e, {"type": "end_turn", "player": 1})
	var cash: int = e.player(0)["cash"]
	roll(e, 0, 1, 2)
	check(not e.player(0)["in_jail"], "sale al tercer intento")
	check(int(e.player(0)["pos"]) == board.jail_index + 3, "se mueve con la tirada")
	check(int(e.player(0)["cash"]) <= cash - board.jail_fine, "pagó la multa")


func test_jail_doubles_no_extra_roll() -> void:
	print("test_jail_doubles_no_extra_roll")
	var e := mk()
	e._send_to_jail(0)
	roll(e, 0, 4, 4)
	check(not e.player(0)["in_jail"], "dobles liberan")
	_settle(e, 0)
	check(e.phase() == GameEngine.POST_ROLL, "sin tirada extra al salir con dobles")


func test_buy_rent_and_monopoly_double() -> void:
	print("test_buy_rent_and_monopoly_double")
	var e := mk()
	roll(e, 0, 1, 2)                       # -> 3 Achachicala
	check(e.phase() == GameEngine.AWAIT_BUY, "ofrece compra")
	run(e, {"type": "buy", "player": 0})
	check(e.owner_of(3) == 0, "propietario asignado")
	check(int(e.player(0)["cash"]) == 1500 - 70, "precio cobrado")
	run(e, {"type": "end_turn", "player": 0})
	roll(e, 1, 1, 2)
	var base := int(board.space(3)["rents"][0])
	check(int(e.player(1)["cash"]) == 1500 - base, "alquiler base pagado")
	check(int(e.player(0)["cash"]) == 1500 - 70 + base, "alquiler recibido")
	e.s["owner"][1] = 0
	check(e.rent_for(3) == base * 2, "alquiler doble con monopolio sin edificar")


func test_decline_starts_auction() -> void:
	print("test_decline_starts_auction")
	var e := mk(3)
	roll(e, 0, 1, 2)
	run(e, {"type": "decline", "player": 0})
	check(e.phase() == GameEngine.AUCTION, "subasta iniciada")
	check(e.pending_actor() == 1, "puja empieza por el siguiente jugador")
	run(e, {"type": "bid", "player": 1, "amount": 10})
	check(not run(e, {"type": "bid", "player": 2, "amount": 15})["ok"], "puja mínima respetada")
	run(e, {"type": "bid", "player": 2, "amount": 30})
	run(e, {"type": "pass_bid", "player": 0})
	check(e.pending_actor() == 1, "turno vuelve al jugador 1")
	run(e, {"type": "pass_bid", "player": 1})
	check(e.owner_of(3) == 2, "gana el mejor postor")
	check(int(e.player(2)["cash"]) == 1470, "paga su puja")
	check(e.phase() == GameEngine.POST_ROLL, "turno continúa")


func test_auction_nobody_bids() -> void:
	print("test_auction_nobody_bids")
	var e := mk(2)
	roll(e, 0, 1, 2)
	run(e, {"type": "decline", "player": 0})
	run(e, {"type": "pass_bid", "player": 1})
	run(e, {"type": "pass_bid", "player": 0})
	check(e.owner_of(3) == -1, "queda en el banco")
	check(e.phase() == GameEngine.POST_ROLL, "turno continúa")


func test_even_building_and_hotel() -> void:
	print("test_even_building_and_hotel")
	var e := mk()
	for i in [6, 7, 9]:
		e.s["owner"][i] = 0
	e.player(0)["cash"] = 5000
	check(run(e, {"type": "build", "player": 0, "space": 6})["ok"], "primera casa")
	check(not run(e, {"type": "build", "player": 0, "space": 6})["ok"], "no 2 casas sin parejo")
	run(e, {"type": "build", "player": 0, "space": 7})
	run(e, {"type": "build", "player": 0, "space": 9})
	for lvl in range(2, 5):
		for i in [6, 7, 9]:
			check(run(e, {"type": "build", "player": 0, "space": i})["ok"], "casa nivel %d en %d" % [lvl, i])
	check(int(e.s["houses_left"]) == 32 - 12, "suministro de casas")
	run(e, {"type": "build", "player": 0, "space": 6})
	check(e.houses_on(6) == GameEngine.HOTEL, "4 casas -> hotel")
	check(int(e.s["houses_left"]) == 32 - 8, "hotel devuelve casas")
	check(int(e.s["hotels_left"]) == 11, "hotel consumido")
	check(not run(e, {"type": "sell_building", "player": 0, "space": 7})["ok"], "venta pareja")
	check(run(e, {"type": "sell_building", "player": 0, "space": 6})["ok"], "vender hotel")
	check(e.houses_on(6) == 4, "hotel -> 4 casas")
	check(not run(e, {"type": "mortgage", "player": 0, "space": 9})["ok"], "no hipoteca con edificios")


func test_quick_mode_hotel_after_three() -> void:
	print("test_quick_mode_hotel_after_three")
	var e := mk(2, RulesConfig.quick())
	for i in [1, 3]:
		e.s["owner"][i] = 0
	e.player(0)["cash"] = 5000
	for lvl in 3:
		for i in [1, 3]:
			run(e, {"type": "build", "player": 0, "space": i})
	run(e, {"type": "build", "player": 0, "space": 1})
	check(e.houses_on(1) == GameEngine.HOTEL, "3 casas -> hotel en modo rápido")


func test_mortgage_rules() -> void:
	print("test_mortgage_rules")
	var e := mk()
	e.s["owner"][4] = 0
	run(e, {"type": "mortgage", "player": 0, "space": 4})
	check(e.is_mortgaged(4), "hipotecada")
	check(int(e.player(0)["cash"]) == 1600, "recibe 50%")
	e.s["owner"][15] = 1
	e.s["current"] = 1
	roll(e, 1, 2, 2)                          # 1 -> pos 4 Teleférico Rojo (hipotecado)
	check(int(e.player(1)["cash"]) == 1500, "sin alquiler en hipotecada")
	e.s["current"] = 0
	e.s["phase"] = GameEngine.PRE_ROLL
	run(e, {"type": "unmortgage", "player": 0, "space": 4})
	check(int(e.player(0)["cash"]) == 1600 - board.unmortgage_cost(4), "levantar cuesta 55%")


func test_debt_then_bankruptcy_to_creditor() -> void:
	print("test_debt_then_bankruptcy_to_creditor")
	var e := mk(3)
	e.s["owner"][39] = 1
	e.s["owner"][38] = 1
	e.s["houses"][39] = GameEngine.HOTEL
	e.s["houses"][38] = GameEngine.HOTEL
	e.s["hotels_left"] = 10
	e.s["owner"][1] = 0
	e.player(0)["pos"] = 33
	e.player(0)["jail_cards"] = ["destino"]
	roll(e, 0, 3, 3)                           # -> 39 alquiler enorme
	check(e.phase() == GameEngine.DEBT, "entra en deuda")
	check(e.pending_actor() == 0, "deudor decide")
	check(not run(e, {"type": "pay_debt", "player": 0})["ok"], "no puede pagar sin fondos")
	run(e, {"type": "bankrupt", "player": 0})
	check(e.player(0)["bankrupt"], "en bancarrota")
	check(e.owner_of(1) == 1, "propiedades pasan al acreedor")
	check(e.player(1)["jail_cards"].size() == 1, "salvoconducto pasa al acreedor")
	check(int(e.player(1)["cash"]) == 1500 + 1500, "efectivo pasa al acreedor")
	check(e.current() == 1 and e.phase() == GameEngine.PRE_ROLL, "turno pasa al siguiente")
	check(not e.is_over(), "quedan 2 jugadores")


func test_bankruptcy_to_bank_frees_properties() -> void:
	print("test_bankruptcy_to_bank_frees_properties")
	var e := mk(2)
	e.s["owner"][1] = 0
	e.s["mortgaged"][1] = true
	e.player(0)["cash"] = 10
	e.player(0)["pos"] = 1
	roll(e, 0, 1, 3)                           # -> 5 Tasa Municipal (100)
	check(e.phase() == GameEngine.DEBT, "deuda con el banco")
	run(e, {"type": "bankrupt", "player": 0})
	check(e.owner_of(1) == -1 and not e.is_mortgaged(1), "propiedad vuelve al banco libre")
	check(e.is_over() and int(e.s["winner"]) == 1, "gana el último en pie")


func test_house_rules() -> void:
	print("test_house_rules")
	var r := RulesConfig.new()
	r.free_parking_pot = true
	r.double_salary_on_go = true
	r.no_rent_in_jail = true
	var e := mk(2, r)
	roll(e, 0, 2, 3)                           # -> 5 Tasa Municipal 100 al bote
	check(int(e.s["pot"]) == 100, "impuesto al bote")
	run(e, {"type": "end_turn", "player": 0})
	e.player(1)["pos"] = 15
	roll(e, 1, 2, 3)                           # 15 -> 20 Mirador
	check(int(e.player(1)["cash"]) == 1600 and int(e.s["pot"]) == 0, "cobra el bote")
	run(e, {"type": "end_turn", "player": 1})
	e.player(0)["pos"] = 36
	roll(e, 0, 1, 3)                           # 36 -> 0 Salida exacta
	check(int(e.player(0)["cash"]) == 1400 + 400, "doble sueldo en Salida exacta")
	run(e, {"type": "end_turn", "player": 0})
	e.s["owner"][3] = 0
	e._send_to_jail(0)
	e.player(1)["pos"] = 0
	roll(e, 1, 1, 2)
	check(int(e.player(1)["cash"]) == 1600, "sin alquiler con dueño en el Retén")


func test_trade() -> void:
	print("test_trade")
	var e := mk(2)
	e.s["owner"][1] = 0
	e.s["owner"][3] = 1
	e.player(0)["jail_cards"] = ["cabildo"]
	var r := run(e, {"type": "trade_propose", "player": 0, "to": 1,
		"give": {"cash": 100, "props": [1], "cards": 1}, "get": {"cash": 0, "props": [3], "cards": 0}})
	check(r["ok"], "propuesta válida")
	check(e.pending_actor() == 1, "el destinatario decide")
	check(not run(e, {"type": "roll", "player": 0})["ok"], "no se tira con intercambio pendiente")
	run(e, {"type": "trade_accept", "player": 1})
	check(e.owner_of(1) == 1 and e.owner_of(3) == 0, "propiedades intercambiadas")
	check(int(e.player(1)["cash"]) == 1600 and int(e.player(0)["cash"]) == 1400, "dinero intercambiado")
	check(e.player(1)["jail_cards"].size() == 1, "salvoconducto intercambiado")
	e.s["houses"][3] = 0
	e.s["owner"][1] = 0
	e.player(0)["cash"] = 5000
	run(e, {"type": "build", "player": 0, "space": 1})
	check(not run(e, {"type": "trade_propose", "player": 0, "to": 1,
		"give": {"props": [3]}, "get": {"cash": 10}})["ok"], "no se intercambia un grupo con edificios")


func test_cards_jail_free_leaves_deck() -> void:
	print("test_cards_jail_free_leaves_deck")
	var e := mk(2)
	var deck: Array = e.s["decks"]["destino"]
	var jf := -1
	for k in board.decks["destino"].size():
		if board.decks["destino"][k]["action"] == "jail_free":
			jf = k
	deck.erase(jf)
	deck.push_front(jf)
	roll(e, 0, 3, 5)                           # -> 8 Destino
	check(e.player(0)["jail_cards"] == ["destino"], "se queda la carta")
	check(not e.s["decks"]["destino"].has(jf), "fuera del mazo")
	e._send_to_jail(0)
	e.s["phase"] = GameEngine.PRE_ROLL
	run(e, {"type": "use_jail_card", "player": 0})
	check(e.s["decks"]["destino"].has(jf), "vuelve al mazo al usarla")


func test_snapshot_roundtrip() -> void:
	print("test_snapshot_roundtrip")
	var e := mk(3)
	roll(e, 0, 1, 2)
	var snap := e.snapshot()
	var bytes := var_to_bytes(snap)
	var e2 := GameEngine.new(board)
	e2.load_snapshot(bytes_to_var(bytes))
	check(e2.phase() == e.phase() and e2.pending_actor() == e.pending_actor(), "estado restaurado")
	var a := e.apply({"type": "decline", "player": 0})
	var b := e2.apply({"type": "decline", "player": 0})
	check(a["events"].size() == b["events"].size(), "misma evolución tras restaurar")


func test_ai_simulation() -> void:
	print("test_ai_simulation")
	var configs := []
	var c1 := RulesConfig.classic()
	c1.max_rounds = 200
	configs.append(c1)
	var c2 := RulesConfig.quick()
	configs.append(c2)
	var c3 := RulesConfig.classic()
	c3.free_parking_pot = true
	c3.double_salary_on_go = true
	c3.no_rent_in_jail = true
	c3.speed_die = true
	c3.max_rounds = 200
	configs.append(c3)
	var ai := AiBrain.new(99)
	var finished := 0
	var games := 60
	var total_cmds := 0
	var winners_by_level := [0, 0, 0]
	for g in games:
		var rules: RulesConfig = configs[g % configs.size()]
		var e := GameEngine.new(board, rules)
		var n := 2 + g % 5
		var seats := []
		for k in n:
			seats.append({"name": "IA%d" % k, "ai": (k + g) % 3})
		e.new_game(seats, 1000 + g)
		var cmds := 0
		while not e.is_over() and cmds < 30000:
			var pid := e.pending_actor()
			var level: int = e.player(pid)["ai"]
			var cmd := ai.decide(e, pid, level)
			if cmd.is_empty():
				check(false, "IA sin decisión en fase %s" % e.phase())
				break
			var r := e.apply(cmd)
			if not r["ok"]:
				check(false, "IA envió comando inválido %s: %s (fase %s)" % [cmd, r["error"], e.phase()])
				break
			cmds += 1
			if not _invariants(e):
				break
		total_cmds += cmds
		if e.is_over():
			finished += 1
			var w := int(e.s["winner"])
			if w >= 0:
				winners_by_level[int(e.player(w)["ai"])] += 1
	print("  %d/%d partidas terminadas, %d comandos; victorias por nivel F/M/D: %s" % [finished, games, total_cmds, winners_by_level])
	check(finished == games, "todas las partidas terminan")


func _invariants(e: GameEngine) -> bool:
	var ok := true
	for p in e.players():
		if int(p["cash"]) < 0:
			check(false, "efectivo negativo: %s" % p["name"])
			ok = false
	var houses := 0
	var hotels := 0
	for i in board.size():
		var h := e.houses_on(i)
		if h == GameEngine.HOTEL:
			hotels += 1
		else:
			houses += h
		if h > 0 and e.is_mortgaged(i):
			check(false, "edificio sobre hipoteca en %d" % i)
			ok = false
	if houses + int(e.s["houses_left"]) != board.houses_total:
		check(false, "suministro de casas inconsistente")
		ok = false
	if hotels + int(e.s["hotels_left"]) != board.hotels_total:
		check(false, "suministro de hoteles inconsistente")
		ok = false
	return ok


## Resuelve compras/cartas pendientes de forma neutra para pruebas.
func _settle(e: GameEngine, pid: int) -> void:
	var guard := 0
	while guard < 20:
		guard += 1
		match e.phase():
			GameEngine.AWAIT_BUY:
				run(e, {"type": "buy", "player": pid})
			GameEngine.DEBT:
				run(e, {"type": "pay_debt", "player": e.pending_actor()})
			_:
				return
