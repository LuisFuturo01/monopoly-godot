class_name GameController
extends Node
## Puente entre el motor de reglas y el resto del juego.
## Decide quién ejecuta cada comando (jugador local, IA o red) y publica eventos.

signal state_changed
signal events_emitted(events: Array)
signal command_failed(message: String)

const BOARD_PATH := "res://data/board_lapaz.json"
const AI_THINK_TIME := 0.6
## Si la IA envía un comando inválido, intenta estas salidas seguras en orden.
const AI_FALLBACKS := ["pay_debt", "bankrupt", "pass_bid", "decline", "trade_reject", "trade_cancel", "roll", "end_turn"]

var board: Board
var engine: GameEngine
var authority := true
var networked := false
var my_uuid := ""
var ai := AiBrain.new()
var player_events: EventPlayer

var _ai_wait := 0.0


func _ready() -> void:
	board = Board.load_from_file(BOARD_PATH)
	player_events = EventPlayer.new()
	player_events.name = "EventPlayer"
	add_child(player_events)


# ---------------------------------------------------------------------------
# Inicio de partida
# ---------------------------------------------------------------------------

func start_local(seats: Array, rules: RulesConfig) -> void:
	engine = GameEngine.new(board, rules)
	engine.new_game(seats)
	authority = true
	networked = false
	_publish([{"type": "turn_started", "player": 0, "round": 1}])


func start_host(seats: Array, rules: RulesConfig) -> void:
	engine = GameEngine.new(board, rules)
	engine.new_game(seats)
	authority = true
	networked = true
	my_uuid = Profile.uuid
	Net.snapshot_provider = engine.snapshot
	Net.command_received.connect(_on_remote_command)
	Net.seat_connection_changed.connect(_on_seat_connection)
	Net.start_game(engine.snapshot())
	_publish([{"type": "turn_started", "player": 0, "round": 1}])


func start_client(snapshot: Dictionary) -> void:
	engine = GameEngine.new(board)
	engine.load_snapshot(snapshot)
	authority = false
	networked = true
	my_uuid = Profile.uuid
	Net.synced.connect(_on_synced)
	Net.game_started.connect(_on_resync)
	state_changed.emit()


func shutdown() -> void:
	for sig in [Net.command_received, Net.seat_connection_changed, Net.synced, Net.game_started]:
		for c in sig.get_connections():
			if c["callable"].get_object() == self:
				sig.disconnect(c["callable"])


# ---------------------------------------------------------------------------
# Consultas para la UI
# ---------------------------------------------------------------------------

func is_local_human(pid: int) -> bool:
	if engine == null or pid < 0:
		return false
	var p := engine.player(pid)
	if int(p["ai"]) >= 0:
		return false
	if networked:
		return p["uuid"] == my_uuid
	return true


func controlled_by_ai(pid: int) -> bool:
	var p := engine.player(pid)
	return int(p["ai"]) >= 0 or (networked and not p["connected"])


## Jugador local que debe decidir ahora, o -1.
func local_actor() -> int:
	if engine == null or engine.is_over():
		return -1
	var pid := engine.pending_actor()
	return pid if is_local_human(pid) else -1


func local_humans() -> Array:
	var out := []
	for p in engine.players():
		if is_local_human(int(p["id"])):
			out.append(int(p["id"]))
	return out


func is_busy() -> bool:
	return player_events.is_busy()


# ---------------------------------------------------------------------------
# Comandos
# ---------------------------------------------------------------------------

func submit(cmd: Dictionary) -> void:
	if authority:
		_apply(cmd)
	else:
		Net.send_command(cmd)


func _apply(cmd: Dictionary) -> bool:
	var r := engine.apply(cmd)
	if not r["ok"]:
		command_failed.emit(r["error"])
		return false
	_publish(r["events"])
	return true


func _publish(events: Array) -> void:
	player_events.push(events)
	events_emitted.emit(events)
	state_changed.emit()
	if networked and authority:
		Net.broadcast_sync(engine.snapshot(), events)


func _process(delta: float) -> void:
	if engine == null or not authority or engine.is_over() or is_busy():
		return
	var pid := engine.pending_actor()
	if pid < 0 or not controlled_by_ai(pid):
		_ai_wait = 0.0
		return
	_ai_wait += delta
	if _ai_wait < AI_THINK_TIME:
		return
	_ai_wait = 0.0
	# Un humano desconectado lo juega temporalmente la IA de nivel medio.
	var level := maxi(int(engine.player(pid)["ai"]), AiBrain.Level.MEDIUM)
	var cmd := ai.decide(engine, pid, level)
	if cmd.is_empty() or not _apply_silent(cmd):
		for t in AI_FALLBACKS:
			if _apply_silent({"type": t, "player": pid}):
				return


## Aplica un comando de la IA sin avisar fallos a la UI.
func _apply_silent(cmd: Dictionary) -> bool:
	var r := engine.apply(cmd)
	if r["ok"]:
		_publish(r["events"])
	return r["ok"]


# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------

func _on_remote_command(cmd: Dictionary, sender_seats: Array) -> void:
	if int(cmd.get("player", -1)) in sender_seats:
		_apply(cmd)


func _on_seat_connection(seat: int, connected: bool) -> void:
	engine.player(seat)["connected"] = connected
	_publish([{"type": "connection", "player": seat, "connected": connected}])


func _on_synced(snapshot: Dictionary, events: Array) -> void:
	engine.load_snapshot(snapshot)
	player_events.push(events)
	events_emitted.emit(events)
	state_changed.emit()


func _on_resync(snapshot: Dictionary) -> void:
	engine.load_snapshot(snapshot)
	state_changed.emit()
