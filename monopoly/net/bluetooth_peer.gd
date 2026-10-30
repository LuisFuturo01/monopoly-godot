class_name BluetoothMultiplayerPeer
extends MultiplayerPeerExtension
## MultiplayerPeer sobre sockets Bluetooth RFCOMM expuestos por un plugin nativo.
##
## Contrato del plugin (singleton "MagnatesBluetooth", ver native/android_bluetooth):
##   métodos: startServer(name, uuid), connectTo(address, uuid), send(conn_id, bytes),
##            disconnect(conn_id), close(), getPairedDevices() -> Array[Dictionary{name,address}]
##   señales: connected(conn_id), disconnected(conn_id), data_received(conn_id, bytes), error(msg)
##
## RFCOMM es un flujo de bytes en estrella (servidor <-> clientes), así que aquí se enmarcan
## paquetes [u32 longitud][u8 tipo][u8 canal][u8 modo][payload] y el servidor asigna IDs.

const SERVICE_UUID := "6f1d3b52-8a4e-4c1b-9b8e-3a5d2f7c9e10"
const KIND_DATA := 0
const KIND_ASSIGN_ID := 1
const HEADER := 7

var bridge: Object
var _server := false
var _unique_id := 0
var _status := CONNECTION_DISCONNECTED
var _target := 0
var _channel := 0
var _mode := TRANSFER_MODE_RELIABLE
var _refuse := false
var _incoming: Array = []            # [{peer, data, channel, mode}]
var _current: Dictionary = {}
var _buffers: Dictionary = {}        # conn_id -> PackedByteArray
var _conn_to_peer: Dictionary = {}   # conn_id -> peer_id
var _peer_to_conn: Dictionary = {}
var _next_peer_id := 2


func _init(p_bridge: Object) -> void:
	bridge = p_bridge
	bridge.connect("connected", _on_connected)
	bridge.connect("disconnected", _on_disconnected)
	bridge.connect("data_received", _on_data)


func create_server(service_name: String) -> Error:
	_server = true
	_unique_id = 1
	_status = CONNECTION_CONNECTED
	bridge.call("startServer", service_name, SERVICE_UUID)
	return OK


func create_client(address: String) -> Error:
	_server = false
	_status = CONNECTION_CONNECTING
	bridge.call("connectTo", address, SERVICE_UUID)
	return OK


# --- Eventos del plugin ------------------------------------------------------

func _on_connected(conn_id: int) -> void:
	_buffers[conn_id] = PackedByteArray()
	if _server:
		if _refuse:
			bridge.call("disconnect", conn_id)
			return
		var pid := _next_peer_id
		_next_peer_id += 1
		_conn_to_peer[conn_id] = pid
		_peer_to_conn[pid] = conn_id
		var payload := PackedByteArray()
		payload.resize(4)
		payload.encode_u32(0, pid)
		_send_frame(conn_id, KIND_ASSIGN_ID, 0, TRANSFER_MODE_RELIABLE, payload)
		peer_connected.emit(pid)
	else:
		# El cliente solo habla con el servidor (peer 1); espera su ID asignado.
		_conn_to_peer[conn_id] = 1
		_peer_to_conn[1] = conn_id


func _on_disconnected(conn_id: int) -> void:
	var pid: int = _conn_to_peer.get(conn_id, 0)
	_conn_to_peer.erase(conn_id)
	_peer_to_conn.erase(pid)
	_buffers.erase(conn_id)
	if pid != 0:
		peer_disconnected.emit(pid)
	if not _server:
		_status = CONNECTION_DISCONNECTED


func _on_data(conn_id: int, bytes: PackedByteArray) -> void:
	var buf: PackedByteArray = _buffers.get(conn_id, PackedByteArray())
	buf.append_array(bytes)
	while buf.size() >= HEADER:
		var length := buf.decode_u32(0)
		if buf.size() < HEADER + length:
			break
		var kind := buf[4]
		var channel := buf[5]
		var mode := buf[6]
		var payload := buf.slice(HEADER, HEADER + length)
		buf = buf.slice(HEADER + length)
		if kind == KIND_ASSIGN_ID and not _server:
			_unique_id = payload.decode_u32(0)
			_status = CONNECTION_CONNECTED
			peer_connected.emit(1)
		elif kind == KIND_DATA:
			_incoming.append({"peer": _conn_to_peer.get(conn_id, 0), "data": payload, "channel": channel, "mode": mode})
	_buffers[conn_id] = buf


func _send_frame(conn_id: int, kind: int, channel: int, mode: int, payload: PackedByteArray) -> void:
	var frame := PackedByteArray()
	frame.resize(HEADER)
	frame.encode_u32(0, payload.size())
	frame[4] = kind
	frame[5] = channel
	frame[6] = mode
	frame.append_array(payload)
	bridge.call("send", conn_id, frame)


# --- MultiplayerPeerExtension ---------------------------------------------------

func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return 1 << 20


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	_current = _incoming.pop_front()
	return _current["data"]


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if _server:
		for pid in _peer_to_conn.keys():
			if _target == 0 or _target == pid or (_target < 0 and -_target != pid):
				_send_frame(_peer_to_conn[pid], KIND_DATA, _channel, _mode, buffer)
	elif _peer_to_conn.has(1):
		_send_frame(_peer_to_conn[1], KIND_DATA, _channel, _mode, buffer)
	return OK


func _get_packet_peer() -> int:
	return int(_current.get("peer", 0))


func _get_packet_channel() -> int:
	return int(_current.get("channel", 0))


func _get_packet_mode() -> TransferMode:
	return int(_current.get("mode", TRANSFER_MODE_RELIABLE)) as TransferMode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _is_server() -> bool:
	return _server


func _is_server_relay_supported() -> bool:
	return false


func _poll() -> void:
	pass   # El plugin entrega datos por señales.


func _close() -> void:
	bridge.call("close")
	_status = CONNECTION_DISCONNECTED
	_conn_to_peer.clear()
	_peer_to_conn.clear()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _peer_to_conn.has(peer):
		bridge.call("disconnect", _peer_to_conn[peer])


func _get_unique_id() -> int:
	return _unique_id


func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _get_connection_status() -> ConnectionStatus:
	return _status
