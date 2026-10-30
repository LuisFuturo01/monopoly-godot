class_name LanDiscovery
extends Node
## Descubrimiento de salas en la red local mediante broadcast UDP.
## El anfitrión emite una baliza por segundo; los clientes escuchan y listan salas.

signal hosts_changed(hosts: Array)

const DISCOVERY_PORT := 47011
const MAGIC := "MAGNATES1"
const BEACON_INTERVAL := 1.0
const HOST_TIMEOUT := 4.0

var _udp: PacketPeerUDP
var _broadcasting := false
var _beacon: Dictionary = {}
var _timer := 0.0
var _hosts: Dictionary = {}   # "ip:port" -> {info..., seen}


func start_broadcast(info: Dictionary) -> void:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_beacon = info
	_broadcasting = true
	_timer = BEACON_INTERVAL


func update_beacon(info: Dictionary) -> void:
	_beacon.merge(info, true)


func start_listening() -> Error:
	stop()
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(DISCOVERY_PORT)
	if err != OK:
		_udp = null
	return err


func stop() -> void:
	if _udp:
		_udp.close()
	_udp = null
	_broadcasting = false
	_hosts.clear()


func _process(delta: float) -> void:
	if _udp == null:
		return
	if _broadcasting:
		_timer += delta
		if _timer >= BEACON_INTERVAL:
			_timer = 0.0
			var msg := {"magic": MAGIC}
			msg.merge(_beacon)
			_udp.put_packet(JSON.stringify(msg).to_utf8_buffer())
		return
	var changed := false
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var data = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY or data.get("magic", "") != MAGIC:
			continue
		data["ip"] = ip
		data["seen"] = Time.get_ticks_msec()
		var key := "%s:%s" % [ip, data.get("port", 0)]
		changed = changed or not _hosts.has(key)
		_hosts[key] = data
	var now := Time.get_ticks_msec()
	for key in _hosts.keys():
		if now - int(_hosts[key]["seen"]) > HOST_TIMEOUT * 1000:
			_hosts.erase(key)
			changed = true
	if changed:
		hosts_changed.emit(_hosts.values())


func hosts() -> Array:
	return _hosts.values()
