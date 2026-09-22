class_name CasillaData
extends RefCounted

var id: int
var nombre: String
var tipo: String
var precio: int
var alquiler: int
var propietario: int = -1
var color_grupo: Color
var nodo_visual: MeshInstance3D
var posicion_3d: Vector3 # <--- Añade esta línea aquí

func _init(p_id: int, p_nombre: String, p_tipo: String, p_precio: int, p_alquiler: int, p_color: Color):
	id = p_id
	nombre = p_nombre
	tipo = p_tipo
	precio = p_precio
	alquiler = p_alquiler
	color_grupo = p_color
