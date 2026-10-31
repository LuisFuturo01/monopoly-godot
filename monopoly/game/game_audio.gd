class_name GameAudio
extends Node
## Traduce los eventos del juego a efectos de sonido y a frases del locutor,
## sincronizados con las animaciones.

var controller: GameController


func bind(c: GameController) -> void:
	controller = c
	controller.player_events.event_played.connect(_on_event)


func _on_event(ev: Dictionary) -> void:
	_announce(ev)
	match ev["type"]:
		"dice_rolled":
			Sfx.play("dice_roll", 0.05)
			Sfx.play_later("dice_stop", EventPlayer.DICE_TIME * 0.85, 0.08)
			if ev["double"]:
				Sfx.play_later("doubles", EventPlayer.DICE_TIME * 0.95)
		"moved":
			for k in ev["path"].size():
				Sfx.play_later("step", (k + 0.85) * EventPlayer.STEP_TIME, 0.12)
		"rent_due", "tax_due":
			Sfx.play("alert")
			Sfx.play_later("cash", 0.35)
		"money":
			if ev["reason"] == "Sueldo" or ev["reason"].begins_with("Bote") or (ev["reason"] == "Carta" and int(ev["delta"]) > 0):
				Sfx.play("coin", 0.1)
		"jailed":
			Sfx.play("jail")
		"bought":
			Sfx.play("buy")
			Sfx.play_later("cash", 0.15)
		"built":
			Sfx.play("build", 0.05)
		"sold_building":
			Sfx.play("sell", 0.05)
		"mortgaged":
			Sfx.play("mortgage")
		"unmortgaged":
			Sfx.play("cash")
		"auction_ended":
			Sfx.play("hammer")
		"bid_pass":
			Sfx.play("pass")
		"trade_proposed":
			Sfx.play("whoosh")
		"jail_released":
			Sfx.play("doubles")
		"pot_collected":
			Sfx.play("trade_ok")
		"card_drawn":
			Sfx.play("card")
		"auction_started":
			Sfx.play("bid")
		"bid":
			Sfx.play("bid", 0.1)
		"turn_started":
			Sfx.play("turn")
		"trade_resolved":
			if ev["result"] == "accepted":
				Sfx.play("trade_ok")
			elif ev["result"] in ["rejected", "invalid"]:
				Sfx.play("trade_no")
		"bankrupt":
			Sfx.play("lose")
		"game_over":
			Sfx.play("win")
		"debt":
			Sfx.play("alert")


## Movimiento que sigue a una carta o al dado turbo (no es de los dados): pid -> true
var _jump: Dictionary = {}
## Ya se anunció «tres dobles»: no repetir que va al Retén
var _three: Dictionary = {}


## Clave del sujeto de la frase: el nombre del jugador si está grabado (nombres comunes y
## los de la IA, ver tools/gen_voice.py); si no, su ficha («La llama»).
func _subject(pid: int) -> String:
	var p := controller.engine.player(pid)
	var full := _norm(String(p["name"]))
	if Sfx.has_voice("n_" + full):
		return "n_" + full
	var first := _norm(String(p["name"]).split(" ")[0])
	if Sfx.has_voice("n_" + first):
		return "n_" + first
	return "n_ficha_" + String(p["token"])


static func _norm(s: String) -> String:
	s = s.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		s = s.replace(pair[0], pair[1])
	var out := ""
	for c in s:
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")


func _tell(pid: int, action: String, priority: int = 1) -> void:
	Sfx.say_parts([_subject(pid), action], 0.0, priority)


## Locutor: cuenta quién hace qué en cada jugada.
func _announce(ev: Dictionary) -> void:
	var pid := int(ev.get("player", -1))
	match ev["type"]:
		"dice_rolled":
			if ev["double"]:
				Sfx.say("g_doubles", EventPlayer.DICE_TIME * 0.55, 2)
		"card_drawn":
			_jump[pid] = true
			_tell(pid, "a_destino" if ev["deck"] == "destino" else "a_cabildo")
		"speed_bolt":
			_jump[pid] = true
		"moved":
			var path: Array = ev["path"]
			if path.is_empty():
				return
			var back := int(path[0]) == posmod(int(ev["from"]) - 1, controller.board.size())
			if back:
				_tell(pid, "a_back_%d" % clampi(path.size(), 1, 5), 2)
			elif _jump.get(pid, false):
				_tell(pid, "a_goto_%d" % int(ev["to"]), 2)
			else:
				_tell(pid, "a_adv_%d" % clampi(path.size(), 1, 20), 2)
			_jump.erase(pid)
		"bought":
			_tell(pid, "a_buy_%d" % int(ev["space"]), 2)
		"rent_due":
			_tell(pid, "a_rent")
		"tax_due":
			_tell(pid, "a_tax")
		"mortgaged":
			_tell(pid, "a_mort_%d" % int(ev["space"]))
		"unmortgaged":
			_tell(pid, "a_unmort_%d" % int(ev["space"]))
		"sold_building":
			_tell(pid, "a_sell_%d" % int(ev["space"]))
		"built":
			_tell(pid, ("a_hotel_%d" if int(ev.get("houses", 0)) == GameEngine.HOTEL else "a_house_%d") % int(ev["space"]))
		"auction_started":
			Sfx.say("g_auction_%d" % int(ev["space"]), 0.0, 3)
		"auction_ended":
			if int(ev["winner"]) >= 0:
				_tell(int(ev["winner"]), "a_win_auction", 3)
			else:
				Sfx.say("g_no_buyer")
		"three_doubles":
			_three[pid] = true
			Sfx.say("g_three_doubles", 0.0, 3)
		"jailed":
			if not _three.get(pid, false):
				_tell(pid, "a_jail", 3)
			_three.erase(pid)
			_jump.erase(pid)
		"jail_released":
			_tell(pid, "a_jail_free")
		"trade_proposed":
			if controller.is_local_human(int(ev["to"])):
				Sfx.say("g_trade_offer")
		"trade_resolved":
			if ev["result"] == "accepted":
				Sfx.say("g_trade_ok")
			elif ev["result"] == "rejected":
				Sfx.say("g_trade_no")
		"bankrupt":
			_tell(pid, "a_bankrupt", 3)
		"pot_collected":
			_tell(pid, "a_pot")
		"debt":
			if controller.is_local_human(int(ev["debtor"])):
				_tell(int(ev["debtor"]), "a_debt")
		"turn_started":
			_jump.erase(pid)
			var limit := controller.engine.rules.max_rounds
			if limit > 0 and int(ev.get("round", 0)) == limit and pid == controller.engine.active_players()[0]:
				Sfx.say("g_last_round")
			elif controller.is_local_human(pid) and controller.local_humans().size() < controller.engine.active_players().size():
				Sfx.say("g_your_turn")
		"game_over":
			if int(ev["winner"]) >= 0:
				_tell(int(ev["winner"]), "a_wins", 3)
