class_name AiBrain
extends RefCounted
## Toma decisiones para un jugador controlado por la computadora.
## Fácil: decisiones aleatorias. Medio: compra conservadora con reserva de efectivo.
## Difícil: persigue y bloquea monopolios, calcula retorno por alquiler y negocia.

enum Level { EASY, MEDIUM, HARD }

var rng := RandomNumberGenerator.new()


func _init(p_seed: int = 0) -> void:
	if p_seed != 0:
		rng.seed = p_seed
	else:
		rng.randomize()


## Devuelve el siguiente comando para `pid`, o {} si no le toca decidir.
func decide(e: GameEngine, pid: int, level: int) -> Dictionary:
	if e.is_over() or e.pending_actor() != pid:
		return {}
	var t: Dictionary = e.s["trade"]
	if not t.is_empty():
		if int(t["to"]) == pid:
			return _cmd(pid, "trade_accept" if _accept_trade(e, pid, level, t) else "trade_reject")
		return _cmd(pid, "trade_cancel")
	match e.phase():
		GameEngine.AUCTION:
			return _auction(e, pid, level)
		GameEngine.DEBT:
			return _raise_money(e, pid, int(e.s["debts"][0]["amount"]), true)
		GameEngine.AWAIT_BUY:
			return _buy_decision(e, pid, level)
		GameEngine.PRE_ROLL:
			return _pre_roll(e, pid, level)
		GameEngine.POST_ROLL:
			var c := _manage(e, pid, level)
			return c if not c.is_empty() else _cmd(pid, "end_turn")
	return {}


func _cmd(pid: int, type: String, extra: Dictionary = {}) -> Dictionary:
	var c := {"type": type, "player": pid}
	c.merge(extra)
	return c


# --- Turno ------------------------------------------------------------------

func _pre_roll(e: GameEngine, pid: int, level: int) -> Dictionary:
	var p := e.player(pid)
	if p["in_jail"]:
		var want_out := false
		match level:
			Level.EASY:
				want_out = rng.randf() < 0.5
			Level.MEDIUM:
				want_out = int(p["cash"]) > 400
			Level.HARD:
				# Al inicio conviene salir a comprar; con el tablero vendido, el Retén protege.
				want_out = _unowned_count(e) > 6
		if want_out:
			if not p["jail_cards"].is_empty():
				return _cmd(pid, "use_jail_card")
			if int(p["cash"]) >= e.board.jail_fine + _reserve(e, pid, level):
				return _cmd(pid, "pay_jail")
		return _cmd(pid, "roll")
	var c := _manage(e, pid, level)
	if not c.is_empty():
		return c
	if level >= Level.MEDIUM and int(e.s["trade_proposals"]) == 0:
		var offer := _find_trade(e, pid, level)
		if not offer.is_empty():
			return offer
	return _cmd(pid, "roll")


## Levantar hipotecas y construir con el excedente de efectivo.
func _manage(e: GameEngine, pid: int, level: int) -> Dictionary:
	if level == Level.EASY and rng.randf() < 0.5:
		return {}
	var spare: int = int(e.player(pid)["cash"]) - _reserve(e, pid, level)
	if spare <= 0:
		return {}
	# Primero, levantar hipotecas de grupos completos (habilita construir).
	for i in e.properties_of(pid):
		if e.is_mortgaged(i) and e.board.unmortgage_cost(i) <= spare:
			if e.owns_group(pid, e.board.group_of(i)) or level == Level.MEDIUM:
				return _cmd(pid, "unmortgage", {"space": i})
	var best := -1
	var best_score := -INF
	for i in e.properties_of(pid):
		if e.can_build(pid, i) != "" or e.board.house_cost(i) > spare:
			continue
		var h := e.houses_on(i)
		var rents: Array = e.board.space(i)["rents"]
		var gain := float(rents[mini(h + 1, 5)]) - float(rents[h])
		var score := gain / e.board.house_cost(i)
		if level == Level.HARD and h < 3:
			score *= 1.5   # La tercera casa es la de mejor retorno.
		if score > best_score:
			best_score = score
			best = i
	if best >= 0:
		return _cmd(pid, "build", {"space": best})
	return {}


func _reserve(e: GameEngine, pid: int, level: int) -> int:
	match level:
		Level.EASY:
			return 50
		Level.MEDIUM:
			return 200
	# Difícil: más reserva cuando los rivales tienen edificios caros.
	var danger := 0
	for i in e.board.size():
		var o := e.owner_of(i)
		if o >= 0 and o != pid and e.houses_on(i) > 0:
			danger = maxi(danger, e.rent_for(i))
	return clampi(100 + danger / 2, 100, 600)


# --- Compra y subasta -----------------------------------------------------------

## Valor estratégico de una propiedad para `pid`.
func value_for(e: GameEngine, pid: int, i: int, level: int) -> float:
	var v := float(e.board.price(i))
	if level == Level.EASY:
		return v
	var group := e.board.group_of(i)
	var members := e.board.group_members(group)
	var mine := 0
	var rival_counts := {}
	for j in members:
		if j == i:
			continue
		var o := e.owner_of(j)
		if o == pid:
			mine += 1
		elif o >= 0:
			rival_counts[o] = rival_counts.get(o, 0) + 1
	if mine == members.size() - 1:
		v *= 2.0 if level == Level.HARD else 1.4     # Completa mi monopolio.
	elif level == Level.HARD:
		for o in rival_counts:
			if rival_counts[o] == members.size() - 1:
				v *= 1.6                              # Bloquea el monopolio de un rival.
		if e.board.space(i)["type"] == "street":
			# Retorno de inversión: alquiler con 3 casas frente a precio + obras.
			var rents: Array = e.board.space(i)["rents"]
			var roi := float(rents[3]) / (e.board.price(i) + 3 * e.board.house_cost(i))
			v *= 0.85 + roi
		elif mine > 0:
			v *= 1.2
	return v


func _buy_decision(e: GameEngine, pid: int, level: int) -> Dictionary:
	var i: int = e.s["pending_buy"]
	var cash: int = e.player(pid)["cash"]
	var price := e.board.price(i)
	if cash < price:
		return _cmd(pid, "decline")
	var buy := false
	match level:
		Level.EASY:
			buy = rng.randf() < 0.6
		Level.MEDIUM:
			buy = cash - price >= _reserve(e, pid, level)
		Level.HARD:
			var v := value_for(e, pid, i, level)
			buy = cash - price >= 60 and (v >= price * 1.3 or cash - price >= _reserve(e, pid, level))
	return _cmd(pid, "buy" if buy else "decline")


func _auction(e: GameEngine, pid: int, level: int) -> Dictionary:
	var a: Dictionary = e.s["auction"]
	var i: int = a["space"]
	var cash: int = e.player(pid)["cash"]
	var limit := 0.0
	match level:
		Level.EASY:
			limit = e.board.price(i) * rng.randf_range(0.4, 1.1)
		Level.MEDIUM:
			limit = minf(e.board.price(i) * 0.9, cash - _reserve(e, pid, level))
		Level.HARD:
			limit = minf(value_for(e, pid, i, level), cash - 40)
	var bid := e.min_bid()
	if bid <= limit and bid <= cash:
		# Puja con saltos para no eternizar la subasta.
		var step := maxi(e.rules.auction_min_increment, int(e.board.price(i) * 0.1))
		var amount := mini(int(limit), bid + (step if level == Level.HARD else 0))
		return _cmd(pid, "bid", {"amount": maxi(bid, amount)})
	return _cmd(pid, "pass_bid")


# --- Deudas -------------------------------------------------------------------------

## Vende edificios e hipoteca hasta cubrir `amount`; si no alcanza, bancarrota.
func _raise_money(e: GameEngine, pid: int, amount: int, in_debt: bool) -> Dictionary:
	if int(e.player(pid)["cash"]) >= amount:
		return _cmd(pid, "pay_debt") if in_debt else {}
	if e.liquidation_value(pid) < amount:
		return _cmd(pid, "bankrupt")
	# Vender edificios del grupo menos rentable primero.
	var sell := -1
	var sell_rent := INF
	for i in e.properties_of(pid):
		if e.can_sell_building(pid, i) == "":
			var r := float(e.rent_for(i))
			if r < sell_rent:
				sell_rent = r
				sell = i
	# Hipotecar antes que vender si hay propiedades sueltas (no rompen monopolios).
	var mort := -1
	var mort_cost := INF
	for i in e.properties_of(pid):
		if e.can_mortgage(pid, i) == "":
			var c := float(e.board.price(i))
			if e.owns_group(pid, e.board.group_of(i)):
				c += 1000.0
			if c < mort_cost:
				mort_cost = c
				mort = i
	if mort >= 0 and mort_cost < 1000.0:
		return _cmd(pid, "mortgage", {"space": mort})
	if sell >= 0:
		return _cmd(pid, "sell_building", {"space": sell})
	if mort >= 0:
		return _cmd(pid, "mortgage", {"space": mort})
	return _cmd(pid, "bankrupt")


# --- Intercambios -----------------------------------------------------------------

## Busca una propiedad que complete un grupo propio y ofrece dinero por ella.
func _find_trade(e: GameEngine, pid: int, level: int) -> Dictionary:
	var cash: int = e.player(pid)["cash"]
	for group in e.board.groups.keys():
		var members := e.board.group_members(group)
		var missing := -1
		var mine := 0
		for j in members:
			if e.owner_of(j) == pid:
				mine += 1
			else:
				missing = j
		if mine != members.size() - 1 or missing < 0:
			continue
		var holder := e.owner_of(missing)
		if holder < 0 or e.houses_on(missing) > 0:
			continue
		var swap := _swap_candidate(e, pid, holder, group)
		if swap >= 0:
			# Terreno por terreno: a ambos les completa un grupo; se compensa la diferencia en dinero.
			var diff := maxi(0, e.board.price(missing) - e.board.price(swap))
			if cash - diff >= _reserve(e, pid, level):
				return _cmd(pid, "trade_propose", {
					"to": holder,
					"give": {"cash": diff, "props": [swap], "cards": 0},
					"get": {"cash": 0, "props": [missing], "cards": 0},
				})
		var premium := 1.8 if level == Level.HARD else 1.3
		var offer := int(e.board.price(missing) * premium)
		if cash - offer < _reserve(e, pid, level):
			continue
		return _cmd(pid, "trade_propose", {
			"to": holder,
			"give": {"cash": offer, "props": [], "cards": 0},
			"get": {"cash": 0, "props": [missing], "cards": 0},
		})
	return {}


## Propiedad mía que le completaría a `other` un grupo distinto de `wanted`
## (si fuera el mismo grupo, ambos se la devolverían turno tras turno).
func _swap_candidate(e: GameEngine, pid: int, other: int, wanted: String) -> int:
	for group in e.board.groups.keys():
		if group == wanted:
			continue
		var members := e.board.group_members(group)
		var theirs := 0
		var mine := -1
		for j in members:
			if e.owner_of(j) == other:
				theirs += 1
			elif e.owner_of(j) == pid and e.houses_on(j) == 0:
				mine = j
		if mine >= 0 and theirs == members.size() - 1:
			return mine
	return -1


func _accept_trade(e: GameEngine, pid: int, level: int, t: Dictionary) -> bool:
	var other := int(t["from"])
	var incoming: Dictionary = t["give"]
	var outgoing: Dictionary = t["get"]
	if int(outgoing["cash"]) > int(e.player(pid)["cash"]):
		return false
	var score := float(incoming["cash"]) - float(outgoing["cash"])
	score += 50.0 * (int(incoming["cards"]) - int(outgoing["cards"]))
	for i in incoming["props"]:
		score += value_for(e, pid, int(i), level)
	for i in outgoing["props"]:
		var v := value_for(e, pid, int(i), level)
		if level >= Level.MEDIUM:
			# Penaliza ceder lo que completa el monopolio del rival.
			var group := e.board.group_of(int(i))
			var theirs := 0
			for j in e.board.group_members(group):
				if e.owner_of(j) == other:
					theirs += 1
			if theirs == e.board.group_members(group).size() - 1:
				v *= 1.6 if level == Level.HARD else 1.25
		score -= v
	match level:
		Level.EASY:
			return score > -50.0 and rng.randf() < 0.5
		Level.MEDIUM:
			return score > 0.0
	return score > 40.0


func _unowned_count(e: GameEngine) -> int:
	var n := 0
	for i in e.board.property_indices():
		if e.owner_of(i) == -1:
			n += 1
	return n
