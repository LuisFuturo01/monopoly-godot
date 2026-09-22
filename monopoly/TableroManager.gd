class_name TableroManager
extends Node3D

var casillas: Array[CasillaData] = []
var contenedor_visual: Node3D

func construir_tablero() -> Array[CasillaData]:
	contenedor_visual = Node3D.new()
	contenedor_visual.name = "ContenedorTableroVisual"
	add_child(contenedor_visual)
	
	_crear_entorno_e_iluminacion()
	_crear_centro()
	
	var total = 40
	var ancho_tablero = 16.0
	var paso = ancho_tablero / 10.0
	
	for i in range(total):
		var datos = _obtener_datos_oficiales(i)
		casillas.append(datos)
		
		var casilla_node = Node3D.new()
		casilla_node.name = "Casilla_" + str(i)
		
		var mesh_base = MeshInstance3D.new()
		var box_base = BoxMesh.new()
		
		var es_esquina = (i == 0 or i == 10 or i == 20 or i == 30)
		if es_esquina:
			box_base.size = Vector3(1.6, 0.45, 1.6)
		else:
			box_base.size = Vector3(1.05, 0.45, 1.45)
			
		mesh_base.mesh = box_base
		
		var mat_base = StandardMaterial3D.new()
		if i == 0:
			mat_base.albedo_color = Color(0.1, 0.8, 0.3) # SALIDA
		elif i == 10:
			mat_base.albedo_color = Color(0.9, 0.5, 0.1) # CÁRCEL
		elif i == 20:
			mat_base.albedo_color = Color(0.2, 0.6, 0.9) # PARKING
		elif i == 30:
			mat_base.albedo_color = Color(0.9, 0.1, 0.1) # IR A CÁRCEL
		elif datos.tipo in ["suerte", "arca"]:
			mat_base.albedo_color = Color(0.95, 0.95, 0.95)
		else:
			mat_base.albedo_color = Color(1.0, 1.0, 1.0)
			
		mesh_base.material_override = mat_base
		mesh_base.position = Vector3(0, 0.225, 0)
		casilla_node.add_child(mesh_base)
		
		if datos.tipo == "calle":
			var mesh_banda = MeshInstance3D.new()
			var box_banda = BoxMesh.new()
			box_banda.size = Vector3(1.05, 0.08, 0.5)
			mesh_banda.mesh = box_banda
			
			var mat_banda = StandardMaterial3D.new()
			mat_banda.albedo_color = datos.color_grupo
			mat_banda.material_override = mat_banda
			mat_banda.position = Vector3(0, 0.46, 0.48)
			casilla_node.add_child(mesh_banda)
			
		var pos_x = 0.0
		var pos_z = 0.0
		var mitad = ancho_tablero / 2.0
		
		if i >= 0 and i <= 10:
			pos_x = mitad - (i * paso)
			pos_z = mitad
			casilla_node.rotation.y = 0
		elif i > 10 and i <= 20:
			pos_x = -mitad
			pos_z = mitad - ((i - 10) * paso)
			casilla_node.rotation.y = PI / 2
		elif i > 20 and i <= 30:
			pos_x = -mitad + ((i - 20) * paso)
			pos_z = -mitad
			casilla_node.rotation.y = PI
		else:
			pos_x = mitad
			pos_z = -mitad + ((i - 30) * paso)
			casilla_node.rotation.y = -PI / 2
			
		casilla_node.position = Vector3(pos_x, 0, pos_z)
		
		var label = Label3D.new()
		label.text = datos.nombre
		label.font_size = 12
		label.pixel_size = 0.0025
		label.modulate = Color.BLACK
		label.outline_modulate = Color.WHITE
		label.outline_size = 4
		label.rotation = Vector3(-PI / 2, 0, 0)
		
		if i >= 0 and i <= 10:
			label.position = Vector3(0, 0.48, 0.5)
		elif i > 10 and i <= 20:
			label.rotation.z = -PI / 2
			label.position = Vector3(0.5, 0.48, 0)
		elif i > 20 and i <= 30:
			label.rotation.z = PI
			label.position = Vector3(0, 0.48, -0.5)
		else:
			label.rotation.z = PI / 2
			label.position = Vector3(-0.5, 0.48, 0)
			
		casilla_node.add_child(label)
		contenedor_visual.add_child(casilla_node)
		
		# Asignar posición 3D real al objeto de datos para uso de los jugadores
		datos.posicion_3d = casilla_node.position
		datos.nodo_visual = mesh_base
		
	return casillas

func _crear_entorno_e_iluminacion() -> void:
	var luz = DirectionalLight3D.new()
	luz.shadow_enabled = true
	luz.rotation = Vector3(-deg_to_rad(60), deg_to_rad(45), 0)
	add_child(luz)
	
	var env = WorldEnvironment.new()
	var entorno = Environment.new()
	entorno.background_mode = Environment.BG_COLOR
	entorno.background_color = Color(0.08, 0.1, 0.14)
	entorno.ambient_light_color = Color(0.9, 0.9, 0.9)
	entorno.ambient_light_energy = 1.2
	env.environment = entorno
	add_child(env)

func _crear_centro() -> void:
	var base = MeshInstance3D.new()
	var plano = PlaneMesh.new()
	plano.size = Vector2(13.8, 13.8)
	base.mesh = plano
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.91, 0.85)
	base.material_override = mat
	base.position = Vector3(0, 0.02, 0)
	contenedor_visual.add_child(base)
	
	var titulo = Label3D.new()
	titulo.text = "MONOPOLY"
	titulo.font_size = 75
	titulo.pixel_size = 0.003
	titulo.modulate = Color(0.85, 0.1, 0.1)
	titulo.rotation = Vector3(-PI / 2, 0, 0)
	titulo.position = Vector3(0, 0.04, -0.5)
	contenedor_visual.add_child(titulo)
	
	_crear_rectangulo_central(Vector3(-3.2, 0.03, -2.0), Vector2(2.5, 1.5), Color(0.15, 0.45, 0.75), "ARCA\nCOMUNAL")
	_crear_rectangulo_central(Vector3(3.2, 0.03, 2.0), Vector2(2.5, 1.5), Color(0.85, 0.5, 0.1), "CASUALIDAD")

func _crear_rectangulo_central(pos: Vector3, tam: Vector2, color: Color, texto: String) -> void:
	var zona = MeshInstance3D.new()
	var caja = BoxMesh.new()
	caja.size = Vector3(tam.x, 0.03, tam.y)
	zona.mesh = caja
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	zona.material_override = mat
	zona.position = pos
	contenedor_visual.add_child(zona)
	
	var lbl = Label3D.new()
	lbl.text = texto
	lbl.font_size = 18
	lbl.pixel_size = 0.003
	lbl.modulate = Color.WHITE
	lbl.rotation = Vector3(-PI / 2, 0, 0)
	lbl.position = Vector3(0, 0.04, 0)
	zona.add_child(lbl)

func _obtener_datos_oficiales(i: int) -> CasillaData:
	var color_neutro = Color(0.6, 0.6, 0.6)
	if i == 0: return CasillaData.new(i, "SALIDA", "salida", 0, 0, color_neutro)
	if i == 10: return CasillaData.new(i, "CÁRCEL", "carcel", 0, 0, color_neutro)
	if i == 20: return CasillaData.new(i, "PARKING", "parking", 0, 0, color_neutro)
	if i == 30: return CasillaData.new(i, "IR CÁRCEL", "ir_carcel", 0, 0, color_neutro)
	if i in [2, 17, 33]: return CasillaData.new(i, "ARCA COMUNAL", "arca", 0, 0, color_neutro)
	if i in [7, 22, 36]: return CasillaData.new(i, "CASUALIDAD", "suerte", 0, 0, color_neutro)
	if i in [5, 15, 25, 35]: return CasillaData.new(i, "ESTACIÓN", "estacion", 200, 25, color_neutro)
	if i in [12, 28]: return CasillaData.new(i, "SERVICIO", "servicio", 150, 30, color_neutro)
	
	var grupo_color = color_neutro
	if i in [1, 3]: grupo_color = Color(0.45, 0.22, 0.08)
	elif i in [6, 8, 9]: grupo_color = Color(0.2, 0.7, 0.95)
	elif i in [11, 13, 14]: grupo_color = Color(0.85, 0.25, 0.6)
	elif i in [16, 18, 19]: grupo_color = Color(0.95, 0.4, 0.05)
	elif i in [21, 23, 24]: grupo_color = Color(0.9, 0.1, 0.1)
	elif i in [26, 27, 29]: grupo_color = Color(0.95, 0.85, 0.0)
	elif i in [31, 32, 34]: grupo_color = Color(0.1, 0.7, 0.2)
	elif i in [37, 39]: grupo_color = Color(0.1, 0.25, 0.75)
	
	var nombre_calle = "Calle " + str(i)
	if i == 1: nombre_calle = "Mediterráneo"
	elif i == 3: nombre_calle = "Báltico"
	elif i == 6: nombre_calle = "Oriental"
	elif i == 8: nombre_calle = "Vermont"
	elif i == 9: nombre_calle = "Connecticut"
	
	return CasillaData.new(i, nombre_calle, "calle", 100 + (i * 5), int((100 + (i * 5)) * 0.2), grupo_color)
