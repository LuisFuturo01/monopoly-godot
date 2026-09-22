class_name TableroManager
extends Node3D

var casillas_data: Array[CasillaData] = []
var casillas_visuales: Array[CasillaVisual] = []
var contenedor_visual: Node3D

func construir_tablero() -> Array[CasillaData]:
	contenedor_visual = Node3D.new()
	contenedor_visual.name = "ContenedorTableroVisual"
	add_child(contenedor_visual)
	
	_crear_entorno_e_iluminacion()
	_crear_mesa_y_base_tablero()
	_crear_centro_tablero()
	
	var total = 40
	var ancho_tablero = 13.5
	var paso = ancho_tablero / 10.0
	var mitad = ancho_tablero / 2.0
	
	for i in range(total):
		var datos = _crear_datos_casilla_oficial(i)
		casillas_data.append(datos)
		
		var es_esquina = (i == 0 or i == 10 or i == 20 or i == 30)
		var casilla_vis = CasillaVisual.new()
		casilla_vis.name = "CasillaVisual_" + str(i)
		casilla_vis.setup(datos, es_esquina)
		
		var pos_x = 0.0
		var pos_z = 0.0
		
		if i >= 0 and i <= 10:
			pos_x = mitad - (i * paso)
			pos_z = mitad
			casilla_vis.rotation.y = 0
		elif i > 10 and i <= 20:
			pos_x = -mitad
			pos_z = mitad - ((i - 10) * paso)
			casilla_vis.rotation.y = PI / 2
		elif i > 20 and i <= 30:
			pos_x = -mitad + ((i - 20) * paso)
			pos_z = -mitad
			casilla_vis.rotation.y = PI
		else:
			pos_x = mitad
			pos_z = -mitad + ((i - 30) * paso)
			casilla_vis.rotation.y = -PI / 2
			
		casilla_vis.position = Vector3(pos_x, 0, pos_z)
		contenedor_visual.add_child(casilla_vis)
		
		datos.posicion_3d = casilla_vis.position
		datos.nodo_visual = casilla_vis
		casillas_visuales.append(casilla_vis)
		
	_agregar_detalles_carcel(casillas_visuales[10])
	
	return casillas_data

func obtener_posicion_casilla_con_offset(index: int, id_jugador: int, total_jugadores: int = 2) -> Vector3:
	var base_pos = casillas_data[index].posicion_3d
	var offset_dist = 0.28
	
	var offsets = [
		Vector3(-offset_dist, 0, -offset_dist),
		Vector3(offset_dist, 0, offset_dist),
		Vector3(offset_dist, 0, -offset_dist),
		Vector3(-offset_dist, 0, offset_dist)
	]
	
	var selected_offset = offsets[id_jugador % offsets.size()]
	return Vector3(base_pos.x + selected_offset.x, base_pos.y, base_pos.z + selected_offset.z)

func _crear_entorno_e_iluminacion() -> void:
	var luz_principal = DirectionalLight3D.new()
	luz_principal.shadow_enabled = true
	luz_principal.light_color = Color(1.0, 0.96, 0.9)
	luz_principal.light_energy = 1.3
	luz_principal.shadow_blur = 1.5
	luz_principal.rotation = Vector3(-deg_to_rad(55), deg_to_rad(35), 0)
	add_child(luz_principal)
	
	var luz_relleno = DirectionalLight3D.new()
	luz_relleno.shadow_enabled = false
	luz_relleno.light_color = Color(0.65, 0.78, 0.95)
	luz_relleno.light_energy = 0.45
	luz_relleno.rotation = Vector3(-deg_to_rad(40), -deg_to_rad(135), 0)
	add_child(luz_relleno)
	
	var env = WorldEnvironment.new()
	var entorno = Environment.new()
	entorno.background_mode = Environment.BG_COLOR
	entorno.background_color = Color(0.06, 0.08, 0.12)
	entorno.ambient_light_color = Color(0.85, 0.88, 0.95)
	entorno.ambient_light_energy = 1.1
	env.environment = entorno
	add_child(env)

func _crear_mesa_y_base_tablero() -> void:
	var mesa = MeshInstance3D.new()
	var box_mesa = BoxMesh.new()
	box_mesa.size = Vector3(26.0, 0.8, 26.0)
	mesa.mesh = box_mesa
	
	var mat_mesa = StandardMaterial3D.new()
	mat_mesa.albedo_color = Color(0.08, 0.11, 0.16)
	mat_mesa.roughness = 0.6
	mesa.material_override = mat_mesa
	mesa.position = Vector3(0, -0.42, 0)
	contenedor_visual.add_child(mesa)
	
	var base_tablero = MeshInstance3D.new()
	var box_base = BoxMesh.new()
	box_base.size = Vector3(14.8, 0.32, 14.8)
	base_tablero.mesh = box_base
	
	var mat_base_tab = StandardMaterial3D.new()
	mat_base_tab.albedo_color = Color(0.08, 0.14, 0.11)
	mat_base_tab.roughness = 0.3
	mat_base_tab.specular = 0.5
	base_tablero.material_override = mat_base_tab
	base_tablero.position = Vector3(0, -0.16, 0)
	contenedor_visual.add_child(base_tablero)
	
	var marco_dorado = MeshInstance3D.new()
	var box_dorado = BoxMesh.new()
	box_dorado.size = Vector3(15.0, 0.05, 15.0)
	marco_dorado.mesh = box_dorado
	
	var mat_dorado = StandardMaterial3D.new()
	mat_dorado.albedo_color = Color(0.85, 0.7, 0.2)
	mat_dorado.metallic = 0.8
	mat_dorado.roughness = 0.2
	marco_dorado.material_override = mat_dorado
	marco_dorado.position = Vector3(0, -0.17, 0)
	contenedor_visual.add_child(marco_dorado)

func _crear_centro_tablero() -> void:
	# Tapete Fieltro Verde Esmeralda Oficial
	var base = MeshInstance3D.new()
	var plano = PlaneMesh.new()
	plano.size = Vector2(11.6, 11.6)
	base.mesh = plano
	
	var mat_tapete = StandardMaterial3D.new()
	mat_tapete.albedo_color = Color(0.1, 0.36, 0.2)
	mat_tapete.roughness = 0.7
	base.material_override = mat_tapete
	base.position = Vector3(0, 0.01, 0)
	contenedor_visual.add_child(base)
	
	# Placa/Caja Roja 3D del Título MONOPOLY
	var placa_titulo = MeshInstance3D.new()
	var box_placa = BoxMesh.new()
	box_placa.size = Vector3(5.5, 0.04, 1.4)
	placa_titulo.mesh = box_placa
	
	var mat_placa = StandardMaterial3D.new()
	mat_placa.albedo_color = Color(0.85, 0.12, 0.12) # Rojo Monopoly
	mat_placa.roughness = 0.2
	placa_titulo.material_override = mat_placa
	placa_titulo.position = Vector3(0, 0.03, -0.4)
	placa_titulo.rotation = Vector3(0, -deg_to_rad(30), 0)
	contenedor_visual.add_child(placa_titulo)
	
	# Título 3D MONOPOLY Hiper-Destacado
	var titulo = Label3D.new()
	titulo.text = "MONOPOLY"
	titulo.font_size = 72
	titulo.pixel_size = 0.0035
	titulo.no_depth_test = true
	titulo.render_priority = 10
	titulo.shaded = false
	titulo.modulate = Color(1.0, 1.0, 1.0)
	titulo.outline_modulate = Color(0.1, 0.1, 0.1)
	titulo.outline_size = 8
	titulo.rotation = Vector3(-PI / 2, 0, 0)
	titulo.position = Vector3(0, 0.06, 0.0)
	placa_titulo.add_child(titulo)
	
	# Zonas de Tarjetas 3D
	_crear_mazo_cartas_3d(Vector3(-2.8, 0.02, -1.8), Vector2(2.2, 1.4), Color(0.15, 0.45, 0.75), "ARCA\nCOMUNAL")
	_crear_mazo_cartas_3d(Vector3(2.8, 0.02, 1.8), Vector2(2.2, 1.4), Color(0.85, 0.5, 0.1), "CASUALIDAD")

func _crear_mazo_cartas_3d(pos: Vector3, tam: Vector2, color: Color, texto: String) -> void:
	var zona = MeshInstance3D.new()
	var caja = BoxMesh.new()
	caja.size = Vector3(tam.x, 0.02, tam.y)
	zona.mesh = caja
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	zona.material_override = mat
	zona.position = pos
	contenedor_visual.add_child(zona)
	
	var mazo = MeshInstance3D.new()
	var box_mazo = BoxMesh.new()
	box_mazo.size = Vector3(tam.x * 0.85, 0.1, tam.y * 0.85)
	mazo.mesh = box_mazo
	
	var mat_mazo = StandardMaterial3D.new()
	mat_mazo.albedo_color = Color(0.98, 0.98, 0.95)
	mazo.material_override = mat_mazo
	mazo.position = Vector3(0, 0.06, 0)
	zona.add_child(mazo)
	
	var lbl = Label3D.new()
	lbl.text = texto
	lbl.font_size = 18
	lbl.pixel_size = 0.003
	lbl.no_depth_test = true
	lbl.render_priority = 10
	lbl.shaded = false
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = Color.BLACK
	lbl.outline_size = 5
	lbl.rotation = Vector3(-PI / 2, 0, 0)
	lbl.position = Vector3(0, 0.12, 0)
	zona.add_child(lbl)

func _agregar_detalles_carcel(casilla_vis: CasillaVisual) -> void:
	var container = Node3D.new()
	container.name = "BarrotesCarcel"
	casilla_vis.add_child(container)
	
	var mat_barrote = StandardMaterial3D.new()
	mat_barrote.albedo_color = Color(0.2, 0.2, 0.2)
	mat_barrote.metallic = 0.9
	mat_barrote.roughness = 0.2
	
	for offset_x in [-0.2, 0.0, 0.2]:
		var barrote = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		cyl.height = 0.42
		barrote.mesh = cyl
		barrote.material_override = mat_barrote
		barrote.position = Vector3(offset_x, 0.32, 0.2)
		container.add_child(barrote)

func _crear_datos_casilla_oficial(i: int) -> CasillaData:
	var color_neutro = Color(0.6, 0.6, 0.6)
	
	if i == 0: return CasillaData.new(i, "SALIDA", "salida", Color(0.1, 0.8, 0.3))
	if i == 10: return CasillaData.new(i, "CÁRCEL", "carcel", Color(0.9, 0.5, 0.1))
	if i == 20: return CasillaData.new(i, "PARKING", "parking", Color(0.2, 0.6, 0.9))
	if i == 30: return CasillaData.new(i, "IR CÁRCEL", "ir_carcel", Color(0.9, 0.1, 0.1))
	
	if i in [2, 17, 33]: return CasillaData.new(i, "ARCA COMUNAL", "arca", color_neutro)
	if i in [7, 22, 36]: return CasillaData.new(i, "CASUALIDAD", "suerte", color_neutro)
	if i == 4: return CasillaData.new(i, "IMP. RENTA", "impuesto", color_neutro)
	if i == 38: return CasillaData.new(i, "IMP. LUJO", "impuesto", color_neutro)
	
	if i == 5: return PropiedadCasillaData.new(i, "Ferrocarril Reading", "estacion", 200, 25, color_neutro)
	if i == 15: return PropiedadCasillaData.new(i, "Ferrocarril Pensilvania", "estacion", 200, 25, color_neutro)
	if i == 25: return PropiedadCasillaData.new(i, "Ferrocarril B. & O.", "estacion", 200, 25, color_neutro)
	if i == 35: return PropiedadCasillaData.new(i, "Ferrocarril Vía Rápida", "estacion", 200, 25, color_neutro)
	
	if i == 12: return PropiedadCasillaData.new(i, "Cía. Electricidad", "servicio", 150, 10, color_neutro)
	if i == 28: return PropiedadCasillaData.new(i, "Cía. de Agua", "servicio", 150, 10, color_neutro)
	
	var color_marron = Color(0.45, 0.22, 0.08)
	var color_celeste = Color(0.2, 0.7, 0.95)
	var color_rosado = Color(0.85, 0.25, 0.6)
	var color_naranja = Color(0.95, 0.4, 0.05)
	var color_rojo = Color(0.9, 0.1, 0.1)
	var color_amarillo = Color(0.95, 0.85, 0.0)
	var color_verde = Color(0.1, 0.7, 0.2)
	var color_azul_oscuro = Color(0.1, 0.25, 0.75)
	
	match i:
		1: return PropiedadCasillaData.new(1, "Av. Mediterráneo", "calle", 60, 2, color_marron, 50, [10, 30, 90, 160, 250])
		3: return PropiedadCasillaData.new(3, "Av. Báltico", "calle", 60, 4, color_marron, 50, [20, 60, 180, 320, 450])
		6: return PropiedadCasillaData.new(6, "Av. Oriental", "calle", 100, 6, color_celeste, 50, [30, 90, 270, 400, 550])
		8: return PropiedadCasillaData.new(8, "Av. Vermont", "calle", 100, 6, color_celeste, 50, [30, 90, 270, 400, 550])
		9: return PropiedadCasillaData.new(9, "Av. Connecticut", "calle", 120, 8, color_celeste, 50, [40, 100, 300, 450, 600])
		11: return PropiedadCasillaData.new(11, "Plaza San Carlos", "calle", 140, 10, color_rosado, 100, [50, 150, 450, 625, 750])
		13: return PropiedadCasillaData.new(13, "Av. Estados", "calle", 140, 10, color_rosado, 100, [50, 150, 450, 625, 750])
		14: return PropiedadCasillaData.new(14, "Av. Virginia", "calle", 160, 12, color_rosado, 100, [60, 180, 500, 700, 900])
		16: return PropiedadCasillaData.new(16, "Plaza Santiago", "calle", 180, 14, color_naranja, 100, [70, 200, 550, 750, 950])
		18: return PropiedadCasillaData.new(18, "Av. Nueva York", "calle", 180, 14, color_naranja, 100, [70, 200, 550, 750, 950])
		19: return PropiedadCasillaData.new(19, "Av. Tennessee", "calle", 200, 16, color_naranja, 100, [80, 220, 600, 800, 1000])
		21: return PropiedadCasillaData.new(21, "Av. Kentucky", "calle", 220, 18, color_rojo, 150, [90, 250, 700, 875, 1050])
		23: return PropiedadCasillaData.new(23, "Av. Indiana", "calle", 220, 18, color_rojo, 150, [90, 250, 700, 875, 1050])
		24: return PropiedadCasillaData.new(24, "Av. Illinois", "calle", 240, 20, color_rojo, 150, [100, 300, 750, 925, 1100])
		26: return PropiedadCasillaData.new(26, "Av. Atlántico", "calle", 260, 22, color_amarillo, 150, [110, 330, 800, 975, 1150])
		27: return PropiedadCasillaData.new(27, "Av. Ventnor", "calle", 260, 22, color_amarillo, 150, [110, 330, 800, 975, 1150])
		29: return PropiedadCasillaData.new(29, "Jardines Marvin", "calle", 280, 24, color_amarillo, 150, [120, 360, 850, 1025, 1200])
		31: return PropiedadCasillaData.new(31, "Av. Pacífico", "calle", 300, 26, color_verde, 200, [130, 390, 900, 1100, 1275])
		32: return PropiedadCasillaData.new(32, "Av. Carolina N.", "calle", 300, 26, color_verde, 200, [130, 390, 900, 1100, 1275])
		34: return PropiedadCasillaData.new(34, "Av. Pensilvania", "calle", 320, 28, color_verde, 200, [150, 450, 1000, 1200, 1400])
		37: return PropiedadCasillaData.new(37, "Plaza Park", "calle", 350, 35, color_azul_oscuro, 200, [175, 500, 1100, 1300, 1500])
		39: return PropiedadCasillaData.new(39, "Paseo del Prado", "calle", 400, 50, color_azul_oscuro, 200, [200, 600, 1400, 1700, 2000])
		_: return CasillaData.new(i, "Casilla " + str(i), "calle", color_neutro)
