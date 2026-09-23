class_name ManoVisual
extends Node3D

var palma: MeshInstance3D
var antebrazo: MeshInstance3D
var manga: MeshInstance3D
var camisa_cuello: MeshInstance3D
var reloj: MeshInstance3D

# Articulaciones de los 5 dedos
var nodo_pulgar: Node3D
var nodo_indice: Node3D
var nodo_medio: Node3D
var nodo_anular: Node3D
var nodo_menique: Node3D

var nodos_dedos: Array[Node3D] = []

var mat_piel: StandardMaterial3D
var mat_traje: StandardMaterial3D
var mat_camisa: StandardMaterial3D
var mat_reloj: StandardMaterial3D

var es_modelo_externo: bool = false
var pivote_modelo: Node3D = null

func _ready() -> void:
	if not _intentar_cargar_modelo_3d_externo():
		_crear_mano_humana_3d()

func _intentar_cargar_modelo_3d_externo() -> bool:
	var posibles_rutas = [
		"res://Hands + armature.glb",
		"res://Hands+armature.glb",
		"res://models/Hands + armature.glb",
		"res://models/brazo.glb", "res://models/brazo.gltf", "res://models/brazo.tscn",
		"res://models/mano.glb", "res://models/mano.gltf", "res://models/mano.tscn",
		"res://brazo.glb", "res://brazo.gltf", "res://brazo.tscn",
		"res://mano.glb", "res://mano.gltf", "res://mano.tscn"
	]
	for path in posibles_rutas:
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			var res = load(path)
			if res is PackedScene:
				var inst = res.instantiate()
				inst.name = "ModeloBlender"

				pivote_modelo = Node3D.new()
				pivote_modelo.name = "PivoteMano"
				add_child(pivote_modelo)
				pivote_modelo.add_child(inst)

				# Calcular el centro exacto AABB de la malla para compensar offsets de origen en Blender
				var aabb = _obtener_aabb_combinado(inst)
				var center = aabb.get_center()

				# Desplazar el modelo para que la palma/centro quede en (0,0,0) del pivote
				inst.position = -center

				# Ajustar escala y rotación del pivote para orientar la mano mirando hacia el tablero (-Z)
				pivote_modelo.scale = Vector3(3.2, 3.2, 3.2)
				pivote_modelo.rotation_degrees = Vector3(-15, -135, 0)

				es_modelo_externo = true
				_aplicar_material_piel_a_modelo(inst)
				_configurar_animacion_o_esqueleto(inst)
				print("[ManoVisual] Modelo 3D cargado correctamente desde: ", path, " AABB Center: ", center)
				return true
	return false

func _aplicar_material_piel_a_modelo(nodo: Node) -> void:
	mat_piel = StandardMaterial3D.new()
	mat_piel.albedo_color = Color(0.85, 0.66, 0.52) # Tono piel humana natural y cálido
	mat_piel.roughness = 0.5

	var meshes: Array[MeshInstance3D] = []
	_buscar_mesh_instances(nodo, meshes)
	for m in meshes:
		m.material_override = mat_piel

func _obtener_aabb_combinado(nodo: Node3D) -> AABB:
	var combined_aabb := AABB()
	var first := true
	var meshes: Array[MeshInstance3D] = []
	_buscar_mesh_instances(nodo, meshes)

	for m in meshes:
		if m.mesh:
			var m_aabb = m.mesh.get_aabb()
			var trans_relativa = _obtener_transform_relativo(m, nodo)
			for i in range(8):
				var corner = trans_relativa * m_aabb.get_endpoint(i)
				if first:
					combined_aabb = AABB(corner, Vector3.ZERO)
					first = false
				else:
					combined_aabb = combined_aabb.expand(corner)

	return combined_aabb

func _obtener_transform_relativo(nodo: Node3D, ancestro: Node3D) -> Transform3D:
	var t = Transform3D.IDENTITY
	var curr = nodo
	while curr and curr != ancestro:
		t = curr.transform * t
		curr = curr.get_parent() as Node3D
	return t

func _buscar_mesh_instances(nodo: Node, resultado: Array[MeshInstance3D]) -> void:
	if nodo is MeshInstance3D:
		resultado.append(nodo as MeshInstance3D)
	for c in nodo.get_children():
		_buscar_mesh_instances(c, resultado)

func _configurar_animacion_o_esqueleto(inst: Node) -> void:
	var anim_player: AnimationPlayer = null
	for child in inst.get_children():
		if child is AnimationPlayer:
			anim_player = child as AnimationPlayer
			break
		for grand in child.get_children():
			if grand is AnimationPlayer:
				anim_player = grand as AnimationPlayer
				break

	if anim_player:
		var list = anim_player.get_animation_list()
		if not list.is_empty():
			anim_player.play(list[0])

func _crear_mano_humana_3d() -> void:
	# Materiales refinados
	mat_piel = StandardMaterial3D.new()
	mat_piel.albedo_color = Color(0.88, 0.70, 0.56) # Tono piel realista y cálido
	mat_piel.roughness = 0.45

	mat_traje = StandardMaterial3D.new()
	mat_traje.albedo_color = Color(0.12, 0.15, 0.24) # Manga de traje elegante azul marino
	mat_traje.roughness = 0.6

	mat_camisa = StandardMaterial3D.new()
	mat_camisa.albedo_color = Color(0.96, 0.96, 0.98) # Puño blanco de camisa
	mat_camisa.roughness = 0.3

	mat_reloj = StandardMaterial3D.new()
	mat_reloj.albedo_color = Color(0.92, 0.74, 0.20) # Reloj dorado metálico
	mat_reloj.metallic = 0.9
	mat_reloj.roughness = 0.15

	# ── 1. PALMA AHUECADA DE LA MANO ──
	palma = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(1.6, 0.4, 1.5)
	palma.mesh = box_p
	palma.material_override = mat_piel
	palma.position = Vector3(0, 0, 0)
	add_child(palma)

	# ── 2. RELOJ DORADO Y MUÑECA ──
	reloj = MeshInstance3D.new()
	var box_r = BoxMesh.new()
	box_r.size = Vector3(1.5, 0.42, 0.22)
	reloj.mesh = box_r
	reloj.material_override = mat_reloj
	reloj.position = Vector3(0, 0.05, 0.9)
	add_child(reloj)

	# ── 3. PUÑO DE CAMISA BLANCO ──
	camisa_cuello = MeshInstance3D.new()
	var box_c = BoxMesh.new()
	box_c.size = Vector3(1.52, 0.45, 0.25)
	camisa_cuello.mesh = box_c
	camisa_cuello.material_override = mat_camisa
	camisa_cuello.position = Vector3(0, 0.05, 1.12)
	add_child(camisa_cuello)

	# ── 4. ANTEBRAZO CON MANGA DE TRAJE ELEGANTE ──
	antebrazo = MeshInstance3D.new()
	var box_a = BoxMesh.new()
	box_a.size = Vector3(1.55, 0.5, 3.0)
	antebrazo.mesh = box_a
	antebrazo.material_override = mat_traje
	antebrazo.position = Vector3(0, 0.2, 2.6)
	antebrazo.rotation = Vector3(deg_to_rad(10), 0, 0)
	add_child(antebrazo)

	# ── 5. CREACIÓN DE LOS 5 DEDOS ARTICULADOS ──
	nodo_indice  = _crear_dedo_articulado(Vector3(-0.58, 0.0, -0.75), 1.0)
	nodo_medio   = _crear_dedo_articulado(Vector3(-0.19, 0.0, -0.80), 1.1)
	nodo_anular  = _crear_dedo_articulado(Vector3(0.19, 0.0, -0.75), 1.0)
	nodo_menique = _crear_dedo_articulado(Vector3(0.58, 0.0, -0.68), 0.85)
	nodo_pulgar  = _crear_pulgar_articulado(Vector3(-0.85, 0.08, -0.2))

	nodos_dedos = [nodo_indice, nodo_medio, nodo_anular, nodo_menique, nodo_pulgar]

func _crear_dedo_articulado(pos: Vector3, largo_total: float) -> Node3D:
	var base_joint = Node3D.new()
	base_joint.position = pos
	add_child(base_joint)

	# Segmento 1: Falange proximal
	var seg1 = MeshInstance3D.new()
	var box1 = BoxMesh.new()
	var l1 = largo_total * 0.55
	box1.size = Vector3(0.28, 0.26, l1)
	seg1.mesh = box1
	seg1.material_override = mat_piel
	seg1.position = Vector3(0, 0, -l1 * 0.5)
	base_joint.add_child(seg1)

	# Nudillo medio
	var mid_joint = Node3D.new()
	mid_joint.name = "MidJoint"
	mid_joint.position = Vector3(0, 0, -l1)
	base_joint.add_child(mid_joint)

	# Segmento 2: Falange distal (punta del dedo)
	var seg2 = MeshInstance3D.new()
	var box2 = BoxMesh.new()
	var l2 = largo_total * 0.45
	box2.size = Vector3(0.24, 0.22, l2)
	seg2.mesh = box2
	seg2.material_override = mat_piel
	seg2.position = Vector3(0, 0, -l2 * 0.5)
	mid_joint.add_child(seg2)

	return base_joint

func _crear_pulgar_articulado(pos: Vector3) -> Node3D:
	var base_joint = Node3D.new()
	base_joint.position = pos
	base_joint.rotation = Vector3(0, deg_to_rad(30), deg_to_rad(-25))
	add_child(base_joint)

	var seg = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.3, 0.28, 0.85)
	seg.mesh = box
	seg.material_override = mat_piel
	seg.position = Vector3(0, 0, -0.42)
	base_joint.add_child(seg)

	return base_joint

func agarrar_dados(nivel_cierre: float) -> void:
	if es_modelo_externo and pivote_modelo:
		pivote_modelo.rotation_degrees.x = lerp(-10.0, -35.0, nivel_cierre)
		return

	if nodos_dedos.size() < 5:
		return

	# nivel_cierre: 1.0 = Mano ahuecada sujetando/envolviendo los dados desde abajo
	#               0.0 = Mano abierta con dedos extendidos lanzando
	var flex_base = lerp(deg_to_rad(5), -deg_to_rad(65), nivel_cierre)
	var flex_mid = lerp(deg_to_rad(5), -deg_to_rad(75), nivel_cierre)

	for i in range(4): # Dedos: Índice, Medio, Anular, Meñique
		var d = nodos_dedos[i]
		d.rotation.x = flex_base
		var mid = d.get_node_or_null("MidJoint") as Node3D
		if mid:
			mid.rotation.x = flex_mid

	# Pulgar abrazando hacia arriba/dentro
	if nodo_pulgar:
		nodo_pulgar.rotation.x = lerp(deg_to_rad(10), -deg_to_rad(50), nivel_cierre)
		nodo_pulgar.rotation.y = lerp(deg_to_rad(30), deg_to_rad(65), nivel_cierre)
