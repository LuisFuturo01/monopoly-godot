class_name TableroManager
extends Node3D

var casillas_data: Array[CasillaData] = []
var casillas_visuales: Array[CasillaVisual] = []
var contenedor_visual: Node3D

const TABLERO_ANCHO: float = 13.5
const CASILLAS_POR_LADO: int = 10

func construir_tablero() -> Array[CasillaData]:
	contenedor_visual = Node3D.new()
	contenedor_visual.name = "Tablero"
	add_child(contenedor_visual)

	_crear_entorno()
	_crear_superficie_mesa()
	_crear_base_tablero()
	_crear_centro()

	var paso = TABLERO_ANCHO / float(CASILLAS_POR_LADO)
	var mitad = TABLERO_ANCHO / 2.0

	for i in range(40):
		var datos = _crear_datos_casilla(i)
		casillas_data.append(datos)

		var es_esquina = (i % 10 == 0)
		var casilla_vis = CasillaVisual.new()
		casilla_vis.name = "Casilla_%d" % i
		casilla_vis.setup(datos, es_esquina)

		var pos = _calcular_posicion(i, paso, mitad)
		casilla_vis.position = pos.pos
		casilla_vis.rotation.y = pos.rot_y
		contenedor_visual.add_child(casilla_vis)

		datos.posicion_3d = casilla_vis.position
		datos.nodo_visual = casilla_vis
		casillas_visuales.append(casilla_vis)

	return casillas_data

func _calcular_posicion(i: int, paso: float, mitad: float) -> Dictionary:
	var pos_x := 0.0
	var pos_z := 0.0
	var rot_y := 0.0

	if i >= 0 and i <= 10:
		pos_x = mitad - (i * paso)
		pos_z = mitad
		rot_y = 0
	elif i > 10 and i <= 20:
		pos_x = -mitad
		pos_z = mitad - ((i - 10) * paso)
		rot_y = PI / 2
	elif i > 20 and i <= 30:
		pos_x = -mitad + ((i - 20) * paso)
		pos_z = -mitad
		rot_y = PI
	else:
		pos_x = mitad
		pos_z = -mitad + ((i - 30) * paso)
		rot_y = -PI / 2.0

	return {"pos": Vector3(pos_x, 0, pos_z), "rot_y": rot_y}

func obtener_posicion_casilla_con_offset(index: int, id_jugador: int, total_jugadores: int = 2) -> Vector3:
	var base_pos = casillas_data[index].posicion_3d
	var d = 0.26
	var h = 0.36
	var offsets = [
		Vector3(-d, h, -d), Vector3(d, h, d),
		Vector3(d, h, -d), Vector3(-d, h, d)
	]
	var o = offsets[id_jugador % offsets.size()]
	return base_pos + o

# ═══════════════════════════════════════════════════════════════════
#   ENTORNO E ILUMINACIÓN
# ═══════════════════════════════════════════════════════════════════

func _crear_entorno() -> void:
	# Luz solar cálida principal
	var sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.5
	sun.shadow_blur = 2.5
	sun.rotation = Vector3(-deg_to_rad(60), deg_to_rad(28), 0)
	add_child(sun)

	# Luz de relleno fría suave
	var fill = DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.light_color = Color(0.65, 0.75, 0.95)
	fill.light_energy = 0.55
	fill.rotation = Vector3(-deg_to_rad(38), -deg_to_rad(135), 0)
	add_child(fill)

	# Entorno con fondo oscuro elegante
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.06)
	env.ambient_light_color = Color(0.85, 0.87, 0.93)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05
	env_node.environment = env
	add_child(env_node)

# ═══════════════════════════════════════════════════════════════════
#   MESA Y BASE DEL TABLERO
# ═══════════════════════════════════════════════════════════════════

func _cargar_textura(rutas: Array) -> Texture2D:
	for r in rutas:
		if FileAccess.file_exists(r):
			var img = Image.load_from_file(r)
			if img and not img.is_empty():
				return ImageTexture.create_from_image(img)
	return null

func _crear_superficie_mesa() -> void:
	var mesa = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(28.0, 1.2, 28.0)
	mesa.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.08, 0.05)
	var wood_tex = _cargar_textura([
		"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/textures/wood_texture.png",
		"C:/Users/usuario/.gemini/antigravity-ide/brain/d6fad507-c1cf-49bb-b6eb-1631344b7bf7/wood_texture_1790054206611.png"
	])
	if wood_tex:
		mat.albedo_texture = wood_tex
		mat.uv1_scale = Vector3(3, 3, 1)
	mat.roughness = 0.5
	mesa.material_override = mat
	mesa.position = Vector3(0, -0.65, 0)
	contenedor_visual.add_child(mesa)

func _crear_base_tablero() -> void:
	# Marco exterior dorado grueso
	var filete = MeshInstance3D.new()
	var box_f = BoxMesh.new()
	box_f.size = Vector3(TABLERO_ANCHO + 2.2, 0.28, TABLERO_ANCHO + 2.2)
	filete.mesh = box_f
	var mat_f = StandardMaterial3D.new()
	mat_f.albedo_color = Color(0.82, 0.65, 0.18)
	mat_f.metallic = 0.88
	mat_f.roughness = 0.12
	filete.material_override = mat_f
	filete.position = Vector3(0, -0.14, 0)
	contenedor_visual.add_child(filete)

	# Tablero verde oscuro base sólido
	var base = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(TABLERO_ANCHO + 1.8, 0.22, TABLERO_ANCHO + 1.8)
	base.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.22, 0.12)
	mat.roughness = 0.45
	base.material_override = mat
	base.position = Vector3(0, -0.11, 0)
	contenedor_visual.add_child(base)

func _crear_centro() -> void:
	# Tapete central verde clásico Monopoly elevado
	var tapete = MeshInstance3D.new()
	var plano = BoxMesh.new()
	plano.size = Vector3(TABLERO_ANCHO - 1.5, 0.08, TABLERO_ANCHO - 1.5)
	tapete.mesh = plano
	var mat_t = StandardMaterial3D.new()
	mat_t.albedo_color = Color(0.14, 0.46, 0.24) # Verde clásico vibrante Monopoly
	mat_t.roughness = 0.65
	tapete.material_override = mat_t
	tapete.position = Vector3(0, 0.04, 0)
	contenedor_visual.add_child(tapete)

	# ── Líneas decorativas doradas en el centro ──
	_crear_linea_decorativa(Vector3(0, 0.085, 0), Vector3(8.0, 0.02, 0.06), Color(0.85, 0.7, 0.25, 0.4))
	_crear_linea_decorativa(Vector3(0, 0.085, 0), Vector3(0.06, 0.02, 8.0), Color(0.85, 0.7, 0.25, 0.4))

	# ══ PLACA MONOPOLY GRANDE ELEVADA ══
	var placa = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(6.5, 0.16, 1.8)
	placa.mesh = box_p
	var mat_p = StandardMaterial3D.new()
	mat_p.albedo_color = Color(0.85, 0.1, 0.1)
	var logo_tex = _cargar_textura([
		"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/textures/monopoly_logo.png",
		"C:/Users/usuario/.gemini/antigravity-ide/brain/d6fad507-c1cf-49bb-b6eb-1631344b7bf7/monopoly_logo_1790054123543.png"
	])
	if logo_tex:
		mat_p.albedo_texture = logo_tex
	mat_p.roughness = 0.15
	mat_p.emission_enabled = true
	mat_p.emission = Color(0.2, 0.02, 0.02)
	mat_p.emission_energy_multiplier = 0.2
	placa.material_override = mat_p
	placa.position = Vector3(0, 0.14, 0.3)
	placa.rotation.y = -deg_to_rad(20)
	contenedor_visual.add_child(placa)

	# Borde dorado de la placa
	var borde_placa = MeshInstance3D.new()
	var box_bp = BoxMesh.new()
	box_bp.size = Vector3(6.75, 0.14, 2.05)
	borde_placa.mesh = box_bp
	var mat_bp = StandardMaterial3D.new()
	mat_bp.albedo_color = Color(0.85, 0.68, 0.2)
	mat_bp.metallic = 0.85
	mat_bp.roughness = 0.15
	borde_placa.material_override = mat_bp
	borde_placa.position = Vector3(0, 0.13, 0.3)
	borde_placa.rotation.y = -deg_to_rad(20)
	contenedor_visual.add_child(borde_placa)

	# Texto MONOPOLY enorme elevado
	var titulo = Label3D.new()
	titulo.text = "MONOPOLY"
	titulo.font_size = 72
	titulo.pixel_size = 0.009
	titulo.no_depth_test = true
	titulo.render_priority = 12
	titulo.shaded = false
	titulo.double_sided = true
	titulo.modulate = Color(1.0, 1.0, 1.0)
	titulo.outline_modulate = Color(0.4, 0.02, 0.02)
	titulo.outline_size = 10
	titulo.rotation = Vector3(-PI / 2, 0, 0)
	titulo.position = Vector3(0, 0.18, 0)
	placa.add_child(titulo)

	# Subtítulo
	var sub = Label3D.new()
	sub.text = "EDICIÓN CLÁSICA"
	sub.font_size = 28
	sub.pixel_size = 0.005
	sub.no_depth_test = true
	sub.render_priority = 12
	sub.shaded = false
	sub.double_sided = true
	sub.modulate = Color(0.95, 0.85, 0.5)
	sub.outline_modulate = Color(0.3, 0.02, 0.02)
	sub.outline_size = 6
	sub.rotation = Vector3(-PI / 2, 0, 0)
	sub.position = Vector3(0, 0.18, 0.55)
	placa.add_child(sub)

	# ── Mazo Arca Comunal (esquina sup-izq) ──
	_crear_mazo(Vector3(-4.0, 0.06, -3.0), Color(0.12, 0.38, 0.72), "ARCA\nCOMUNAL", -deg_to_rad(40), "arca")
	# ── Mazo Casualidad (esquina inf-der) ──
	_crear_mazo(Vector3(4.0, 0.06, 3.0), Color(0.88, 0.5, 0.08), "CASUALIDAD", deg_to_rad(40), "suerte")

func _crear_linea_decorativa(pos: Vector3, size: Vector3, color: Color) -> void:
	var linea = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	linea.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.3
	linea.material_override = mat
	linea.position = pos
	contenedor_visual.add_child(linea)

func _crear_mazo(pos: Vector3, color: Color, texto: String, rot: float, clave_tex: String = "") -> void:
	# Base del mazo
	var base_m = MeshInstance3D.new()
	var box_b = BoxMesh.new()
	box_b.size = Vector3(2.3, 0.06, 1.5)
	base_m.mesh = box_b
	var mat_b = StandardMaterial3D.new()
	mat_b.albedo_color = color.darkened(0.25)
	mat_b.roughness = 0.5
	base_m.material_override = mat_b
	base_m.position = pos
	base_m.rotation.y = rot
	contenedor_visual.add_child(base_m)

	# Pila de cartas
	var pila = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(1.85, 0.22, 1.15)
	pila.mesh = box_p
	var mat_p = StandardMaterial3D.new()
	mat_p.albedo_color = Color(0.97, 0.97, 0.94)
	pila.material_override = mat_p
	pila.position = Vector3(0, 0.14, 0)
	base_m.add_child(pila)

	# Carta superior con color o textura
	var top = MeshInstance3D.new()
	var box_t = BoxMesh.new()
	box_t.size = Vector3(1.82, 0.03, 1.12)
	top.mesh = box_t
	var mat_t = StandardMaterial3D.new()
	mat_t.albedo_color = color
	var card_tex: Texture2D = null
	if clave_tex == "arca":
		card_tex = _cargar_textura([
			"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/textures/chest_card.png",
			"C:/Users/usuario/.gemini/antigravity-ide/brain/d6fad507-c1cf-49bb-b6eb-1631344b7bf7/chest_card_1790054172237.png"
		])
	elif clave_tex == "suerte":
		card_tex = _cargar_textura([
			"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/textures/chance_card.png",
			"C:/Users/usuario/.gemini/antigravity-ide/brain/d6fad507-c1cf-49bb-b6eb-1631344b7bf7/chance_card_1790054160909.png"
		])
	if card_tex:
		mat_t.albedo_texture = card_tex
	mat_t.roughness = 0.25
	mat_t.emission_enabled = true
	mat_t.emission = color.darkened(0.2)
	mat_t.emission_energy_multiplier = 0.15
	top.material_override = mat_t
	top.position = Vector3(0, 0.125, 0)
	pila.add_child(top)

	# Texto del mazo
	var lbl = Label3D.new()
	lbl.text = texto
	lbl.font_size = 28
	lbl.pixel_size = 0.005
	lbl.no_depth_test = true
	lbl.render_priority = 10
	lbl.shaded = false
	lbl.double_sided = true
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = Color.BLACK
	lbl.outline_size = 6
	lbl.rotation = Vector3(-PI / 2, 0, 0)
	lbl.position = Vector3(0, 0.15, 0)
	pila.add_child(lbl)

# ═══════════════════════════════════════════════════════════════════
#   DATOS DE CASILLAS
# ═══════════════════════════════════════════════════════════════════

func _crear_datos_casilla(i: int) -> CasillaData:
	var cn = Color(0.6, 0.6, 0.6)

	# Esquinas
	if i == 0:  return CasillaData.new(i, "SALIDA", "salida", cn)
	if i == 10: return CasillaData.new(i, "CÁRCEL", "carcel", cn)
	if i == 20: return CasillaData.new(i, "PARKING", "parking", cn)
	if i == 30: return CasillaData.new(i, "IR A\nCÁRCEL", "ir_carcel", cn)

	# Especiales
	if i in [2, 17, 33]: return CasillaData.new(i, "ARCA\nCOMUNAL", "arca", cn)
	if i in [7, 22, 36]: return CasillaData.new(i, "SUERTE", "suerte", cn)
	if i == 4:  return CasillaData.new(i, "IMPUESTO", "impuesto", cn)
	if i == 38: return CasillaData.new(i, "IMP. LUJO", "impuesto", cn)

	# Estaciones
	if i == 5:  return PropiedadCasillaData.new(i, "F.C.\nReading", "estacion", 200, 25, cn)
	if i == 15: return PropiedadCasillaData.new(i, "F.C.\nPennsyl.", "estacion", 200, 25, cn)
	if i == 25: return PropiedadCasillaData.new(i, "F.C.\nB.&O.", "estacion", 200, 25, cn)
	if i == 35: return PropiedadCasillaData.new(i, "F.C.\nVía Ráp.", "estacion", 200, 25, cn)

	# Servicios
	if i == 12: return PropiedadCasillaData.new(i, "Electric.", "servicio", 150, 10, cn)
	if i == 28: return PropiedadCasillaData.new(i, "Cía. Agua", "servicio", 150, 10, cn)

	# Calles
	var c_brown  = Color(0.55, 0.27, 0.08)
	var c_sky    = Color(0.3, 0.75, 0.95)
	var c_pink   = Color(0.85, 0.3, 0.6)
	var c_orange = Color(0.95, 0.5, 0.1)
	var c_red    = Color(0.9, 0.15, 0.15)
	var c_yellow = Color(0.95, 0.88, 0.1)
	var c_green  = Color(0.15, 0.7, 0.25)
	var c_blue   = Color(0.12, 0.25, 0.72)

	match i:
		1:  return PropiedadCasillaData.new(1,  "Mediterr.", "calle", 60,  2,  c_brown,  50, [10,30,90,160,250])
		3:  return PropiedadCasillaData.new(3,  "Báltico",   "calle", 60,  4,  c_brown,  50, [20,60,180,320,450])
		6:  return PropiedadCasillaData.new(6,  "Oriental",  "calle", 100, 6,  c_sky,    50, [30,90,270,400,550])
		8:  return PropiedadCasillaData.new(8,  "Vermont",   "calle", 100, 6,  c_sky,    50, [30,90,270,400,550])
		9:  return PropiedadCasillaData.new(9,  "Connect.",  "calle", 120, 8,  c_sky,    50, [40,100,300,450,600])
		11: return PropiedadCasillaData.new(11, "San Carlos","calle", 140, 10, c_pink,  100, [50,150,450,625,750])
		13: return PropiedadCasillaData.new(13, "Estados",   "calle", 140, 10, c_pink,  100, [50,150,450,625,750])
		14: return PropiedadCasillaData.new(14, "Virginia",  "calle", 160, 12, c_pink,  100, [60,180,500,700,900])
		16: return PropiedadCasillaData.new(16, "Santiago",  "calle", 180, 14, c_orange,100, [70,200,550,750,950])
		18: return PropiedadCasillaData.new(18, "New York",  "calle", 180, 14, c_orange,100, [70,200,550,750,950])
		19: return PropiedadCasillaData.new(19, "Tennessee", "calle", 200, 16, c_orange,100, [80,220,600,800,1000])
		21: return PropiedadCasillaData.new(21, "Kentucky",  "calle", 220, 18, c_red,   150, [90,250,700,875,1050])
		23: return PropiedadCasillaData.new(23, "Indiana",   "calle", 220, 18, c_red,   150, [90,250,700,875,1050])
		24: return PropiedadCasillaData.new(24, "Illinois",  "calle", 240, 20, c_red,   150, [100,300,750,925,1100])
		26: return PropiedadCasillaData.new(26, "Atlántico", "calle", 260, 22, c_yellow,150, [110,330,800,975,1150])
		27: return PropiedadCasillaData.new(27, "Ventnor",   "calle", 260, 22, c_yellow,150, [110,330,800,975,1150])
		29: return PropiedadCasillaData.new(29, "Marvin",    "calle", 280, 24, c_yellow,150, [120,360,850,1025,1200])
		31: return PropiedadCasillaData.new(31, "Pacífico",  "calle", 300, 26, c_green, 200, [130,390,900,1100,1275])
		32: return PropiedadCasillaData.new(32, "Carolina",  "calle", 300, 26, c_green, 200, [130,390,900,1100,1275])
		34: return PropiedadCasillaData.new(34, "Pennsylv.", "calle", 320, 28, c_green, 200, [150,450,1000,1200,1400])
		37: return PropiedadCasillaData.new(37, "Park Place","calle", 350, 35, c_blue,  200, [175,500,1100,1300,1500])
		39: return PropiedadCasillaData.new(39, "Boardwalk", "calle", 400, 50, c_blue,  200, [200,600,1400,1700,2000])
		_:  return CasillaData.new(i, "Casilla %d" % i, "calle", cn)
