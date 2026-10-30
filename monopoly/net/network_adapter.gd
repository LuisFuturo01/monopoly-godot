class_name NetworkAdapter
extends RefCounted
## Capa de abstracción de transporte. Cada adaptador produce un MultiplayerPeer,
## así las RPC de NetSession funcionan igual sobre Wi-Fi (ENet) o Bluetooth.

const DEFAULT_PORT := 47010
const MAX_CLIENTS := 5

var peer: MultiplayerPeer


func kind() -> String:
	return "base"


func is_available() -> bool:
	return true


## Crea el peer servidor. `address` lo ignora ENet; Bluetooth lo usa como nombre de servicio.
func host(_port: int = DEFAULT_PORT, _max_clients: int = MAX_CLIENTS) -> Error:
	return ERR_UNAVAILABLE


func join(_address: String, _port: int = DEFAULT_PORT) -> Error:
	return ERR_UNAVAILABLE


func close() -> void:
	if peer:
		peer.close()
	peer = null
