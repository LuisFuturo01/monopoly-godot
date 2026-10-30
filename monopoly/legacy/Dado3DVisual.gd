class_name Dado3DVisual
extends Node3D

var mesh_dado: MeshInstance3D
var mat_dado: StandardMaterial3D
var mat_punto: StandardMaterial3D

func _ready() -> void:
	_crear_geometria()

func _crear_geometria() -> void:
	# Cuerpo del dado (cubo blanco pulido con esquinas suaves)
	mesh_dado = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.55, 0.55, 0.55)
	mesh_dado.mesh = box

	mat_dado = StandardMaterial3D.new()
	mat_dado.albedo_color = Color(0.98, 0.96, 0.92)
	mat_dado.roughness = 0.2
	mat_dado.metallic = 0.05
	mesh_dado.material_override = mat_dado
	add_child(mesh_dado)

	mat_punto = StandardMaterial3D.new()
	mat_punto.albedo_color = Color(0.1, 0.1, 0.1)
	mat_punto.roughness = 0.3

	var d = 0.276
	var p = 0.13

	# Cara 1 (+Y)
	_agregar_puntos_cara(Vector3(0, d, 0), Vector3(0, 0, 0), [Vector2(0, 0)])
	# Cara 6 (-Y)
	_agregar_puntos_cara(Vector3(0, -d, 0), Vector3(PI, 0, 0), [
		Vector2(-p, -p), Vector2(p, -p),
		Vector2(-p, 0), Vector2(p, 0),
		Vector2(-p, p), Vector2(p, p)
	])
	# Cara 2 (+Z)
	_agregar_puntos_cara(Vector3(0, 0, d), Vector3(PI / 2.0, 0, 0), [Vector2(-p, -p), Vector2(p, p)])
	# Cara 5 (-Z)
	_agregar_puntos_cara(Vector3(0, 0, -d), Vector3(-PI / 2.0, 0, 0), [
		Vector2(-p, -p), Vector2(p, p),
		Vector2(0, 0),
		Vector2(p, -p), Vector2(-p, p)
	])
	# Cara 3 (+X)
	_agregar_puntos_cara(Vector3(d, 0, 0), Vector3(0, 0, -PI / 2.0), [Vector2(-p, -p), Vector2(0, 0), Vector2(p, p)])
	# Cara 4 (-X)
	_agregar_puntos_cara(Vector3(-d, 0, 0), Vector3(0, 0, PI / 2.0), [
		Vector2(-p, -p), Vector2(p, -p),
		Vector2(-p, p), Vector2(p, p)
	])

func _agregar_puntos_cara(centro: Vector3, rot_cara: Vector3, coords_2d: Array) -> void:
	var nodo_cara = Node3D.new()
	nodo_cara.position = centro
	nodo_cara.rotation = rot_cara
	add_child(nodo_cara)

	for p2d in coords_2d:
		var p = MeshInstance3D.new()
		var s = SphereMesh.new()
		s.radius = 0.045
		s.height = 0.04
		p.mesh = s
		p.material_override = mat_punto
		p.position = Vector3(p2d.x, 0.01, p2d.y)
		nodo_cara.add_child(p)

func obtener_rotacion_para_valor(valor: int) -> Vector3:
	var base_rot = Vector3.ZERO
	match valor:
		1: base_rot = Vector3(0, 0, 0)
		2: base_rot = Vector3(-PI / 2.0, 0, 0)
		3: base_rot = Vector3(0, 0, PI / 2.0)
		4: base_rot = Vector3(0, 0, -PI / 2.0)
		5: base_rot = Vector3(PI / 2.0, 0, 0)
		6: base_rot = Vector3(PI, 0, 0)
	var rot_y_rand = [0.0, PI / 2.0, PI, 1.5 * PI].pick_random()
	return Vector3(base_rot.x, base_rot.y + rot_y_rand, base_rot.z)
