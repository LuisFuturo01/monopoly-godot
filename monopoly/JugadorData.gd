class_name JugadorData
extends RefCounted

var id: int
var nombre: String
var dinero: int
var posicion: int = 0
var color_ficha: Color
var propiedades: Array = []
var nodo_ficha: Node3D
var en_carcel: bool = false
var turnos_carcel: int = 0

func _init(p_id: int, p_nombre: String, p_dinero: int = 1500, p_color: Color = Color.RED) -> void:
	id = p_id
	nombre = p_nombre
	dinero = p_dinero
	color_ficha = p_color

func puede_pagar(monto: int) -> bool:
	return dinero >= monto

func modificar_dinero(monto: int) -> void:
	dinero += monto

func agregar_propiedad(propiedad) -> void:
	if not propiedades.has(propiedad):
		propiedades.append(propiedad)
