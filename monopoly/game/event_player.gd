class_name EventPlayer
extends Node
## Reproduce los eventos del motor en secuencia con su duración de animación.
## Vistas 2D/3D y audio se suscriben a `event_played`, así comparten la misma línea de tiempo.

signal event_played(ev: Dictionary)
signal drained

const DICE_TIME := 1.0
const STEP_TIME := 0.2

var _queue: Array = []
var _running := false
var speed := 1.0
## Estado tal como lo ve el jugador: avanza con cada evento reproducido, no con el motor.
## Así la ficha no aparece en la meta antes de recorrer el camino.
var shown_pos: Dictionary = {}
var shown_cash: Dictionary = {}


func sync_from(engine: GameEngine) -> void:
	for p in engine.players():
		shown_pos[int(p["id"])] = int(p["pos"])
		shown_cash[int(p["id"])] = int(p["cash"])


func push(events: Array) -> void:
	_queue.append_array(events)
	if not _running:
		_run()


func is_busy() -> bool:
	return _running


func _run() -> void:
	_running = true
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		_track(ev)
		event_played.emit(ev)
		var d := duration(ev) / speed
		if d > 0.0 and is_inside_tree():
			await get_tree().create_timer(d).timeout
	_running = false
	drained.emit()


func _track(ev: Dictionary) -> void:
	match ev["type"]:
		"moved":
			shown_pos[int(ev["player"])] = int(ev["to"])
		"jailed":
			shown_pos[int(ev["player"])] = int(ev["space"])
		"money":
			var pid := int(ev["player"])
			shown_cash[pid] = int(shown_cash.get(pid, 0)) + int(ev["delta"])


static func duration(ev: Dictionary) -> float:
	match ev["type"]:
		"dice_rolled":
			return DICE_TIME
		"moved":
			return ev["path"].size() * STEP_TIME + 0.15
		"card_drawn":
			return 1.4
		"jailed":
			return 0.7
		"rent_due", "tax_due":
			return 0.45
		"bought", "built", "auction_ended":
			return 0.3
		"bankrupt", "game_over":
			return 1.0
	return 0.0
