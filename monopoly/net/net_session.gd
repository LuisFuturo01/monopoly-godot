extends Node
## Autoload "Net": sesión multijugador local cliente-servidor autoritativa.
##
## - El anfitrión ejecuta el GameEngine; es el único que tira dados y aplica reglas.
## - Los clientes envían comandos (_rpc_command) y reciben el estado completo + eventos (_rpc_sync).
## - Cada asiento se identifica por el UUID del perfil local: al reconectar, el jugador recupera su asiento.
## - Si un jugador se desconecta en partida, su asiento queda "desconectado" y la IA juega por él.

signal lobby_changed(seats: Array, rules: Dictionary)
signal game_started(snapshot: Dictionary)
signal synced(snapshot: Dictionary, events: Array)
signal command_received(cmd: Dictionary, sender_seats: Array)
signal seat_connection_changed(seat: int, connected: bool)
signal session_ended(reason: String)

enum Role { NONE, HOST, CLIENT }

const MAX_SEATS := 6

var role: int = Role.NONE
var adapter: NetworkAdapter
var discovery: LanDiscovery
var seats: Array = []          # {uuid, name, nick, token, color, ai, peer}
var rules: Dictionary = {}
var in_game := false
var room_name := ""
var last_address := ""
## Lo asigna el GameController anfitrión para reenviar el estado a quien reconecta.
var snapshot_provider: Callable

var _my_seat: Dictionary = {}


func _ready() -> void:
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func is_online() -> bool:
	return role != Role.NONE


# ---------------------------------------------------------------------------
# Anfitrión
# ---------------------------------------------------------------------------

func host_game(p_adapter: NetworkAdapter, my_seat: Dictionary, p_rules: Dictionary, p_room: String) -> Error:
	leave()
	var err := p_adapter.host()
	if err != OK:
		return err
	adapter = p_adapter
	multiplayer.multiplayer_peer = adapter.peer
	role = Role.HOST
	room_name = p_room
	rules = p_rules
	var seat := my_seat.duplicate()
	seat["peer"] = 1
	seats = [seat]
	if adapter.kind() == "wifi":
		discovery.start_broadcast(_beacon())
	lobby_changed.emit(seats, rules)
	return OK


func add_ai_seat(level: int, seat: Dictionary) -> void:
	if not is_host() or in_game or seats.size() >= MAX_SEATS:
		return
	var s := seat.duplicate()
	s["ai"] = level
	s["peer"] = 0
	seats.append(s)
	_broadcast_lobby()


func remove_seat(idx: int) -> void:
	if not is_host() or in_game or idx <= 0 or idx >= seats.size():
		return
	var peer_id := int(seats[idx].get("peer", 0))
	seats.remove_at(idx)
	if peer_id > 1:
		_rpc_rejected.rpc_id(peer_id, "El anfitrión te quitó de la sala")
	_broadcast_lobby()


func set_rules(p_rules: Dictionary) -> void:
	if is_host() and not in_game:
		rules = p_rules
		_broadcast_lobby()


func start_game(snapshot: Dictionary) -> void:
	if not is_host():
		return
	in_game = true
	discovery.update_beacon({"in_game": true})
	_rpc_start.rpc(snapshot)


func broadcast_sync(snapshot: Dictionary, events: Array) -> void:
	if is_host() and in_game:
		_rpc_sync.rpc(snapshot, events)


## Índices de asiento controlados por un peer remoto.
func seats_of_peer(peer_id: int) -> Array:
	var out := []
	for i in seats.size():
		if int(seats[i].get("peer", 0)) == peer_id and int(seats[i].get("ai", -1)) < 0:
			out.append(i)
	return out


func _beacon() -> Dictionary:
	return {"name": room_name, "port": NetworkAdapter.DEFAULT_PORT, "players": seats.size(), "max": MAX_SEATS, "in_game": in_game}


func _broadcast_lobby() -> void:
	discovery.update_beacon(_beacon())
	_rpc_lobby.rpc(seats, rules)
	lobby_changed.emit(seats, rules)


# ---------------------------------------------------------------------------
# Cliente
# ---------------------------------------------------------------------------

func join_game(p_adapter: NetworkAdapter, address: String, my_seat: Dictionary) -> Error:
	leave()
	var err := p_adapter.join(address)
	if err != OK:
		return err
	adapter = p_adapter
	multiplayer.multiplayer_peer = adapter.peer
	role = Role.CLIENT
	last_address = address
	_my_seat = my_seat.duplicate()
	return OK


func send_command(cmd: Dictionary) -> void:
	if is_client():
		_rpc_command.rpc_id(1, cmd)


func leave() -> void:
	discovery.stop()
	if adapter:
		adapter.close()
	adapter = null
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	in_game = false
	seats = []


# ---------------------------------------------------------------------------
# Eventos de conexión
# ---------------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass   # El cliente se presenta con _rpc_hello.


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	for i in range(seats.size() - 1, -1, -1):
		if int(seats[i].get("peer", 0)) != id:
			continue
		if in_game:
			seats[i]["peer"] = 0
			seat_connection_changed.emit(i, false)
		else:
			seats.remove_at(i)
	if not in_game:
		_broadcast_lobby()


func _on_connected_to_server() -> void:
	_rpc_hello.rpc_id(1, _my_seat)


func _on_connection_failed() -> void:
	leave()
	session_ended.emit("No se pudo conectar con el anfitrión")


func _on_server_disconnected() -> void:
	leave()
	session_ended.emit("Se perdió la conexión con el anfitrión")


# ---------------------------------------------------------------------------
# RPC
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(seat: Dictionary) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var uuid: String = seat.get("uuid", "")
	for i in seats.size():
		if seats[i].get("uuid", "") == uuid and uuid != "":
			# Reconexión: recupera su asiento sin reiniciar la partida.
			seats[i]["peer"] = sender
			if in_game:
				seat_connection_changed.emit(i, true)
				if snapshot_provider.is_valid():
					_rpc_start.rpc_id(sender, snapshot_provider.call())
			else:
				_broadcast_lobby()
			return
	if in_game:
		_rpc_rejected.rpc_id(sender, "La partida ya comenzó")
		return
	if seats.size() >= MAX_SEATS:
		_rpc_rejected.rpc_id(sender, "La sala está llena")
		return
	var s := seat.duplicate()
	s["ai"] = -1
	s["peer"] = sender
	seats.append(s)
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(p_seats: Array, p_rules: Dictionary) -> void:
	seats = p_seats
	rules = p_rules
	lobby_changed.emit(seats, rules)


@rpc("authority", "call_remote", "reliable")
func _rpc_start(snapshot: Dictionary) -> void:
	in_game = true
	game_started.emit(snapshot)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(cmd: Dictionary) -> void:
	if not is_host():
		return
	command_received.emit(cmd, seats_of_peer(multiplayer.get_remote_sender_id()))


@rpc("authority", "call_remote", "reliable")
func _rpc_sync(snapshot: Dictionary, events: Array) -> void:
	synced.emit(snapshot, events)


@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	leave()
	session_ended.emit(reason)
