class_name TableroManager
extends Node3D

var casillas_data: Array[CasillaData] = []
var casillas_visuales: Array = []
var contenedor_visual: Node3D

const ESQUINA_SIZE: float = 1.68
const CASILLA_W: float = 1.28
const MITAD_TABLERO: float = (9.0 * CASILLA_W + ESQUINA_SIZE) / 2.0 # 6.60
const TABLERO_ANCHO: float = MITAD_TABLERO * 2.0 # 13.20

var mazo_arca_top: MeshInstance3D
var mazo_suerte_top: MeshInstance3D

func construir_tablero() -> Array[CasillaData]:
	contenedor_visual = Node3D.new()
	contenedor_visual.name = "Tablero"
	add_child(contenedor_visual)

	_crear_entorno()
	_crear_superficie_mesa()
	_crear_base_tablero()
	_crear_centro()

	for i in range(40):
		var datos = _crear_datos_casilla(i)
		casillas_data.append(datos)

		var es_esquina = (i % 10 == 0)
		var casilla_vis = CasillaVisual.new()
		casilla_vis.name = "Casilla_%d" % i
		casilla_vis.setup(datos, es_esquina)

		var pos = _calcular_posicion(i)
		casilla_vis.position = pos.pos
		casilla_vis.rotation.y = pos.rot_y
		contenedor_visual.add_child(casilla_vis)

		datos.posicion_3d = casilla_vis.position
		datos.nodo_visual = casilla_vis
		casillas_visuales.append(casilla_vis)

	return casillas_data

func _calcular_posicion(i: int) -> Dictionary:
	var lado = i / 10 # 0: inferior, 1: izquierdo, 2: superior, 3: derecho
	var idx_en_lado = i % 10

	var offset_coord := 0.0
	if idx_en_lado == 0:
		offset_coord = MITAD_TABLERO
	else:
		offset_coord = (MITAD_TABLERO - ESQUINA_SIZE * 0.5 - CASILLA_W * 0.5) - (idx_en_lado - 1) * CASILLA_W

	var pos_x := 0.0
	var pos_z := 0.0
	var rot_y := 0.0

	match lado:
		0: # Lado inferior (Salida a Cárcel)
			pos_x = offset_coord
			pos_z = MITAD_TABLERO
			rot_y = 0.0
		1: # Lado izquierdo (Cárcel a Parking)
			pos_x = -MITAD_TABLERO
			pos_z = offset_coord
			rot_y = PI / 2.0
		2: # Lado superior (Parking a Ir a la Cárcel)
			pos_x = -offset_coord
			pos_z = -MITAD_TABLERO
			rot_y = PI
		3: # Lado derecho (Ir a la Cárcel a Salida)
			pos_x = MITAD_TABLERO
			pos_z = -offset_coord
			rot_y = -PI / 2.0

	return {"pos": Vector3(pos_x, 0, pos_z), "rot_y": rot_y}

func obtener_posicion_casilla_con_offset(index: int, id_jugador: int, total_jugadores: int = 2) -> Vector3:
	var base_pos = casillas_data[index].posicion_3d
	var d = 0.26
	var h = 0.385 # Elevación justa para asentar la ficha sobre las letras sin flotar
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
	# Luz solar cálida principal tipo estudio/atardecer elegante
	var sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 1.6
	sun.shadow_blur = 2.0
	sun.rotation = Vector3(-deg_to_rad(60), deg_to_rad(28), 0)
	add_child(sun)

	# Luz de relleno fría suave
	var fill = DirectionalLight3D.new()
	fill.shadow_enabled = false
	fill.light_color = Color(0.65, 0.75, 0.95)
	fill.light_energy = 0.55
	fill.rotation = Vector3(-deg_to_rad(38), -deg_to_rad(135), 0)
	add_child(fill)

	# Entorno con SSAO (Oclusión Ambiental) y Tonemap Filmic/ACES
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.06)
	env.ambient_light_color = Color(0.85, 0.87, 0.93)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05

	# SSAO para sombras de contacto reales entre fichas, casillas y cartas
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.5
	env.ssao_detail = 0.5

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
	# Marco exterior de madera oscura pulida
	var marco_madera = MeshInstance3D.new()
	var box_m = BoxMesh.new()
	box_m.size = Vector3(16.5, 0.35, 16.5)
	marco_madera.mesh = box_m
	var mat_m = StandardMaterial3D.new()
	mat_m.albedo_color = Color(0.12, 0.06, 0.03) # Caoba oscura pulida
	var wood_tex = _cargar_textura([
		"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/textures/wood_texture.png",
		"C:/Users/usuario/.gemini/antigravity-ide/brain/d6fad507-c1cf-49bb-b6eb-1631344b7bf7/wood_texture_1790054206611.png"
	])
	if wood_tex:
		mat_m.albedo_texture = wood_tex
		mat_m.uv1_scale = Vector3(4, 4, 1)
	mat_m.roughness = 0.22
	mat_m.metallic = 0.1
	marco_madera.material_override = mat_m
	marco_madera.position = Vector3(0, -0.18, 0)
	contenedor_visual.add_child(marco_madera)

	# Esquineros de bronce/oro tallado en las 4 esquinas del marco exterior
	_crear_esquineros_oro(16.5, 0.36)

	# Filete dorado interior
	var filete = MeshInstance3D.new()
	var box_f = BoxMesh.new()
	box_f.size = Vector3(15.2, 0.28, 15.2)
	filete.mesh = box_f
	var mat_f = StandardMaterial3D.new()
	mat_f.albedo_color = Color(0.88, 0.72, 0.22)
	mat_f.metallic = 0.88
	mat_f.roughness = 0.12
	filete.material_override = mat_f
	filete.position = Vector3(0, -0.13, 0)
	contenedor_visual.add_child(filete)

	# Tablero verde oscuro base sólido
	var base = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(14.88, 0.22, 14.88)
	base.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.22, 0.12)
	mat.roughness = 0.45
	base.material_override = mat
	base.position = Vector3(0, -0.11, 0)
	contenedor_visual.add_child(base)

func _crear_esquineros_oro(tam_marco: float, alto_m: float) -> void:
	var offset_c = tam_marco * 0.5 - 0.4
	var mat_oro = StandardMaterial3D.new()
	mat_oro.albedo_color = Color(0.9, 0.75, 0.25)
	mat_oro.metallic = 0.9
	mat_oro.roughness = 0.15

	var esquinas = [
		Vector3(-offset_c, -0.16, -offset_c),
		Vector3(offset_c, -0.16, -offset_c),
		Vector3(-offset_c, -0.16, offset_c),
		Vector3(offset_c, -0.16, offset_c)
	]
	for p in esquinas:
		var corner_mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.8, 0.37, 0.8)
		corner_mesh.mesh = box
		corner_mesh.material_override = mat_oro
		corner_mesh.position = p
		contenedor_visual.add_child(corner_mesh)

func _cargar_modelo_ciudad() -> Node3D:
	var rutas = [
		"res://ciudad/city.glb",
		"res://city.glb",
		"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/ciudad/city.glb",
		"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/city.glb"
	]
	for r in rutas:
		if ResourceLoader.exists(r):
			var res = load(r)
			if res is PackedScene:
				return res.instantiate()
	return null

func _crear_centro() -> void:
	# Tapete central de paño de casino verde clásico
	var tapete = MeshInstance3D.new()
	var plano = BoxMesh.new()
	plano.size = Vector3(11.52, 0.08, 11.52)
	tapete.mesh = plano
	var mat_t = StandardMaterial3D.new()
	mat_t.albedo_color = Color(0.08, 0.28, 0.16) # Paño de casino verde profundo
	mat_t.roughness = 0.75
	tapete.material_override = mat_t
	tapete.position = Vector3(0, 0.04, 0)
	contenedor_visual.add_child(tapete)

	# ══ CIUDAD 3D CENTRAL REALISTA (city.glb) ══
	var ciudad_node = _cargar_modelo_ciudad()
	if ciudad_node:
		ciudad_node.name = "Ciudad3DCentro"
		ciudad_node.position = Vector3(0, 0.08, 0.4) # Centrada en el centro exacto del tablero
		ciudad_node.scale = Vector3(0.00048, 0.00048, 0.00048) # Escala ajustada con margen de padding para casas y hoteles
		contenedor_visual.add_child(ciudad_node)

	# ── Filetes de riel dorado alrededor del tapete interno ──
	var tam_i = TABLERO_ANCHO - 1.5
	_crear_linea_decorativa(Vector3(0, 0.082, -tam_i * 0.5 + 0.04), Vector3(tam_i, 0.015, 0.08), Color(0.85, 0.7, 0.22))
	_crear_linea_decorativa(Vector3(0, 0.082, tam_i * 0.5 - 0.04), Vector3(tam_i, 0.015, 0.08), Color(0.85, 0.7, 0.22))
	_crear_linea_decorativa(Vector3(-tam_i * 0.5 + 0.04, 0.082, 0), Vector3(0.08, 0.015, tam_i), Color(0.85, 0.7, 0.22))
	_crear_linea_decorativa(Vector3(tam_i * 0.5 - 0.04, 0.082, 0), Vector3(0.08, 0.015, tam_i), Color(0.85, 0.7, 0.22))

	# ── Líneas decorativas doradas en cruz en el centro ──
	_crear_linea_decorativa(Vector3(0, 0.085, 0), Vector3(8.0, 0.02, 0.06), Color(0.85, 0.7, 0.25, 0.4))
	_crear_linea_decorativa(Vector3(0, 0.085, 0), Vector3(0.06, 0.02, 8.0), Color(0.85, 0.7, 0.25, 0.4))

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
	# Marco/Bandeja 3D del mazo con filete dorado
	var caja = MeshInstance3D.new()
	var box_c = BoxMesh.new()
	box_c.size = Vector3(2.5, 0.1, 1.7)
	caja.mesh = box_c
	var mat_c = StandardMaterial3D.new()
	mat_c.albedo_color = Color(0.85, 0.7, 0.2) # Marco dorado de la caja
	mat_c.metallic = 0.85
	mat_c.roughness = 0.18
	caja.material_override = mat_c
	caja.position = pos
	caja.rotation.y = rot
	contenedor_visual.add_child(caja)

	# Montón de cartas 3D con grosor de papel real
	var pila = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(2.35, 0.32, 1.55)
	pila.mesh = box_p
	var mat_p = StandardMaterial3D.new()
	mat_p.albedo_color = Color(0.96, 0.95, 0.92) # Papel marfil de las cartas apiladas
	mat_p.roughness = 0.6
	pila.material_override = mat_p
	pila.position = Vector3(0, 0.16, 0)
	caja.add_child(pila)

	# Carta superior 3D con borde dorado
	var top = MeshInstance3D.new()
	var box_t = BoxMesh.new()
	box_t.size = Vector3(2.30, 0.03, 1.50)
	top.mesh = box_t
	var mat_t = StandardMaterial3D.new()
	mat_t.albedo_color = color
	var card_tex: Texture2D = null
	if clave_tex == "arca":
		card_tex = _cargar_textura([
			"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/textures/chest_card.png",
			"C:/Users/usuario/.gemini/antigravity-ide/brain/d6fad507-c1cf-49bb-b6eb-1631344b7bf7/chest_card_1790054172237.png"
		])
		mazo_arca_top = top
	elif clave_tex == "suerte":
		card_tex = _cargar_textura([
			"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/textures/chance_card.png",
			"C:/Users/usuario/.gemini/antigravity-ide/brain/d6fad507-c1cf-49bb-b6eb-1631344b7bf7/chance_card_1790054160909.png"
		])
		mazo_suerte_top = top
	if card_tex:
		mat_t.albedo_texture = card_tex
	mat_t.roughness = 0.25
	mat_t.emission_enabled = true
	mat_t.emission = color.darkened(0.2)
	mat_t.emission_energy_multiplier = 0.15
	top.material_override = mat_t
	top.position = Vector3(0, 0.175, 0)
	pila.add_child(top)

	# Texto del mazo
	var lbl = Label3D.new()
	lbl.name = "LabelTituloMazo"
	lbl.text = texto
	lbl.font_size = 32
	lbl.pixel_size = 0.005
	lbl.no_depth_test = true
	lbl.render_priority = 10
	lbl.shaded = false
	lbl.double_sided = true
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = Color.BLACK
	lbl.outline_size = 6
	lbl.rotation = Vector3(-PI / 2, 0, 0)
	lbl.position = Vector3(0, 0.02, 0)
	top.add_child(lbl)

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
