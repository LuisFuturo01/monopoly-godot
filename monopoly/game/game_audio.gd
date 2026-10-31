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


## Locutor: dice el resultado de los dados y lo importante de cada jugada.
func _announce(ev: Dictionary) -> void:
	match ev["type"]:
		"dice_rolled":
			var d: Array = ev["dice"]
			Sfx.say("dice_%d" % (int(d[0]) + int(d[1])), EventPlayer.DICE_TIME * 0.9)
			if ev["double"]:
				Sfx.say("doubles", EventPlayer.DICE_TIME * 0.95)
		"bought":
			Sfx.say("bought_%d" % int(ev["space"]))
		"mortgaged":
			Sfx.say("mortgaged_%d" % int(ev["space"]))
		"unmortgaged":
			Sfx.say("unmortgaged_%d" % int(ev["space"]))
		"sold_building":
			Sfx.say("sold_%d" % int(ev["space"]))
		"built":
			Sfx.say(("hotel_%d" if int(ev.get("houses", 0)) == GameEngine.HOTEL else "house_%d") % int(ev["space"]))
		"auction_started":
			Sfx.say("auction_%d" % int(ev["space"]))
		"auction_ended":
			Sfx.say("auction_sold" if int(ev["winner"]) >= 0 else "no_buyer")
		"rent_due":
			Sfx.say("rent_%d" % int(ev["space"]) if ev.has("space") else "tax")
		"tax_due":
			Sfx.say("tax")
		"money":
			if ev["reason"] == "Sueldo":
				Sfx.say("salary")
		"card_drawn":
			Sfx.say("destino" if ev["deck"] == "destino" else "cabildo")
		"three_doubles":
			Sfx.say("three_doubles")
		"jailed":
			Sfx.say("jail")
		"jail_released":
			Sfx.say("jail_free")
		"trade_proposed":
			if controller.is_local_human(int(ev["to"])):
				Sfx.say("trade_offer")
		"trade_resolved":
			if ev["result"] == "accepted":
				Sfx.say("trade_ok")
			elif ev["result"] == "rejected":
				Sfx.say("trade_no")
		"bankrupt":
			Sfx.say("bankrupt")
		"pot_collected":
			Sfx.say("pot")
		"debt":
			if controller.is_local_human(int(ev["debtor"])):
				Sfx.say("debt")
		"turn_started":
			var limit := controller.engine.rules.max_rounds
			if limit > 0 and int(ev.get("round", 0)) == limit and int(ev["player"]) == controller.engine.active_players()[0]:
				Sfx.say("last_round")
			elif controller.is_local_human(int(ev["player"])):
				Sfx.say("your_turn")
		"game_over":
			Sfx.say("win")
