class_name PropiedadCasillaData
extends CasillaData

var precio: int
var alquiler_base: int
var alquileres_casas: Array = [] # Alquiler con 1, 2, 3, 4 casas y hotel
var costo_casa: int
var casas: int = 0 # 0..4 casas, 5 = hotel
var propietario_id: int = -1
var hipotecada: bool = false

func _init(p_id: int, p_nombre: String, p_tipo: String, p_precio: int, p_alquiler_base: int, p_color: Color = Color.WHITE, p_costo_casa: int = 50, p_alquileres: Array = []) -> void:
	super._init(p_id, p_nombre, p_tipo, p_color)
	precio = p_precio
	alquiler_base = p_alquiler_base
	costo_casa = p_costo_casa
	alquileres_casas = p_alquileres

func esta_comprada() -> bool:
	return propietario_id != -1

func calcular_alquiler(resultado_dados: int = 7, total_propiedades_grupo: int = 1) -> int:
	if hipotecada:
		return 0
		
	if tipo == "calle":
		if casas > 0 and casas <= alquileres_casas.size():
			return alquileres_casas[casas - 1]
		return alquiler_base
	elif tipo == "estacion":
		# Las estaciones multiplican por 2^propiedades
		return alquiler_base * int(pow(2, max(0, total_propiedades_grupo - 1)))
	elif tipo == "servicio":
		var multiplicador = 4 if total_propiedades_grupo <= 1 else 10
		return resultado_dados * multiplicador
		
	return alquiler_base

func agregar_casa() -> bool:
	if casas < 5:
		casas += 1
		return true
	return false
