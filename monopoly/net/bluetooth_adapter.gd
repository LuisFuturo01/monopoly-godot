class_name BluetoothAdapter
extends NetworkAdapter
## Transporte Bluetooth (RFCOMM). Requiere el plugin nativo de Android
## (native/android_bluetooth). En escritorio e iOS informa que no está disponible:
## iOS no expone RFCOMM a apps sin certificación MFi.

const SINGLETON := "MagnatesBluetooth"


func kind() -> String:
	return "bluetooth"


func is_available() -> bool:
	return Engine.has_singleton(SINGLETON)


func bridge() -> Object:
	return Engine.get_singleton(SINGLETON) if is_available() else null


## Dispositivos emparejados: Array de {name, address}.
func paired_devices() -> Array:
	return bridge().call("getPairedDevices") if is_available() else []


func host(_port: int = DEFAULT_PORT, _max_clients: int = MAX_CLIENTS) -> Error:
	if not is_available():
		return ERR_UNAVAILABLE
	var p := BluetoothMultiplayerPeer.new(bridge())
	var err := p.create_server("Luchopolis")
	if err == OK:
		peer = p
	return err


## `address`: dirección MAC del anfitrión emparejado.
func join(address: String, _port: int = DEFAULT_PORT) -> Error:
	if not is_available():
		return ERR_UNAVAILABLE
	var p := BluetoothMultiplayerPeer.new(bridge())
	var err := p.create_client(address)
	if err == OK:
		peer = p
	return err
