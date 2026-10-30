class_name CasillaData
extends RefCounted

var id: int
var nombre: String
var tipo: String # "salida", "calle", "estacion", "servicio", "suerte", "arca", "carcel", "parking", "ir_carcel", "impuesto"
var color_grupo: Color
var posicion_3d: Vector3 = Vector3.ZERO
var nodo_visual: Node3D

func _init(p_id: int, p_nombre: String, p_tipo: String, p_color: Color = Color.WHITE) -> void:
	id = p_id
	nombre = p_nombre
	tipo = p_tipo
	color_grupo = p_color

func es_propiedad() -> bool:
	return tipo in ["calle", "estacion", "servicio"]
