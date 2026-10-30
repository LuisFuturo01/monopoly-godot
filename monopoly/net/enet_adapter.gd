class_name EnetAdapter
extends NetworkAdapter
## Transporte Wi-Fi / LAN con ENet (UDP fiable).


func kind() -> String:
	return "wifi"


func host(port: int = DEFAULT_PORT, max_clients: int = MAX_CLIENTS) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, max_clients)
	if err == OK:
		peer = p
	return err


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address, port)
	if err == OK:
		peer = p
	return err
