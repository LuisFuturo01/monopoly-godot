class_name GameAudio
extends Node
## Traduce los eventos del juego a efectos de sonido, sincronizados con las animaciones.

var controller: GameController


func bind(c: GameController) -> void:
	controller = c
	controller.player_events.event_played.connect(_on_event)


func _on_event(ev: Dictionary) -> void:
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
