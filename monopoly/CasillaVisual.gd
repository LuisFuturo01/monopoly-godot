class_name CasillaVisual
extends Node3D

const CASILLA_W: float = 1.28
const CASILLA_D: float = 1.68
const ESQUINA_SIZE: float = 1.68
const CASILLA_H: float = 0.20
const BORDE_GROSOR: float = 0.02
const BANDA_H: float = 0.42

var data: CasillaData
var contenedor_casas: Node3D
var mesh_borde: MeshInstance3D
var mesh_base: MeshInstance3D
var mesh_banda: MeshInstance3D
var indicador_dueno: MeshInstance3D
var label_nombre: Label3D
var label_precio: Label3D
var mesh_lote_base: MeshInstance3D
var mesh_neon_frame: MeshInstance3D
var mat_neon: StandardMaterial3D

func setup(p_data: CasillaData, es_esquina: bool = false) -> void:
	data = p_data

	contenedor_casas = Node3D.new()
	contenedor_casas.name = "Casas"
	add_child(contenedor_casas)

	var w = ESQUINA_SIZE if es_esquina else CASILLA_W
	var d = ESQUINA_SIZE if es_esquina else CASILLA_D

	# ── Borde fino negro que separa casillas ──
	mesh_borde = MeshInstance3D.new()
	var box_borde = BoxMesh.new()
	box_borde.size = Vector3(w + BORDE_GROSOR * 2, CASILLA_H, d + BORDE_GROSOR * 2)
	mesh_borde.mesh = box_borde
	var mat_borde = StandardMaterial3D.new()
	mat_borde.albedo_color = Color(0.12, 0.12, 0.12)
	mat_borde.roughness = 0.6
	mesh_borde.material_override = mat_borde
	mesh_borde.position = Vector3(0, CASILLA_H * 0.5, 0)
	add_child(mesh_borde)

	# ── Base Interior ──
	mesh_base = MeshInstance3D.new()
	var box_base = BoxMesh.new()
	box_base.size = Vector3(w, CASILLA_H + 0.02, d)
	mesh_base.mesh = box_base
	var mat_base = StandardMaterial3D.new()
	mat_base.roughness = 0.35
	mat_base.albedo_color = _color_base(es_esquina)
	mesh_base.material_override = mat_base
	mesh_base.position = Vector3(0, CASILLA_H * 0.5 + 0.01, 0)
	add_child(mesh_base)

	# ── Banda de color del grupo (calles) con acabado satinado PBR ──
	if data.tipo == "calle":
		mesh_banda = MeshInstance3D.new()
		var box_banda = BoxMesh.new()
		box_banda.size = Vector3(w, 0.05, BANDA_H)
		mesh_banda.mesh = box_banda
		var mat_banda = StandardMaterial3D.new()
		mat_banda.albedo_color = data.color_grupo
		mat_banda.roughness = 0.22
		mat_banda.metallic = 0.08
		mat_banda.clearcoat_enabled = true
		mat_banda.clearcoat = 0.4
		mat_banda.clearcoat_roughness = 0.12
		mat_banda.emission_enabled = true
		mat_banda.emission = data.color_grupo.lightened(0.1)
		mat_banda.emission_energy_multiplier = 0.25
		mesh_banda.material_override = mat_banda
		mesh_banda.position = Vector3(0, CASILLA_H + 0.03, d * 0.5 - BANDA_H * 0.5)
		add_child(mesh_banda)

	# ── Lote Urbano 3D con Línea Neón LED (28 casillas de propiedad) ──
	if not es_esquina and data.tipo in ["calle", "estacion", "servicio"]:
		_crear_lote_urbano()

	# ── Indicador propietario (Placa discreta en la base del lote) ──
	indicador_dueno = MeshInstance3D.new()
	var box_d = BoxMesh.new()
	box_d.size = Vector3(w * 0.85, 0.05, 0.12)
	indicador_dueno.mesh = box_d
	indicador_dueno.position = Vector3(0, CASILLA_H + 0.035, -d * 0.5 - 0.08)
	indicador_dueno.visible = false
	add_child(indicador_dueno)

	# ── Textos ──
	_crear_nombre(w, d, es_esquina)
	_crear_precio(w, d, es_esquina)

func _crear_lote_urbano() -> void:
	var w_out = CASILLA_W * 0.94 # 1.20m de ancho en el borde de la casilla
	var w_in = 0.82              # 0.82m de ancho hacia el centro de la ciudad
	var length = 1.68            # Profundidad de la cuña hacia el centro
	var height = 0.035           # Elevación sobre el paño
	var z_start = -CASILLA_D * 0.5 # Borde interior de la casilla

	# 1. Base del Lote (Asfalto/Concreto urbano)
	mesh_lote_base = MeshInstance3D.new()
	mesh_lote_base.mesh = _crear_mesh_trapecio(w_out, w_in, length, z_start, height)
	var mat_lote = StandardMaterial3D.new()
	mat_lote.albedo_color = Color(0.12, 0.14, 0.18) # Concreto urbano oscuro
	mat_lote.roughness = 0.65
	mat_lote.metallic = 0.1
	mesh_lote_base.material_override = mat_lote
	add_child(mesh_lote_base)

	# 2. Marco Neón LED Perimetral
	mesh_neon_frame = MeshInstance3D.new()
	mesh_neon_frame.mesh = _crear_mesh_marco_neon(w_out, w_in, length, z_start, height + 0.005)
	mat_neon = StandardMaterial3D.new()
	mat_neon.albedo_color = Color(0.28, 0.32, 0.38)
	mat_neon.emission_enabled = true
	mat_neon.emission = Color(0.28, 0.32, 0.38) # Estado inactivo (neutro tenue)
	mat_neon.emission_energy_multiplier = 0.5
	mat_neon.roughness = 0.2
	mesh_neon_frame.material_override = mat_neon
	add_child(mesh_neon_frame)

func _crear_mesh_trapecio(w_out: float, w_in: float, length: float, z_start: float, height: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var y0 = CASILLA_H
	var y1 = CASILLA_H + height
	var z0 = z_start
	var z1 = z_start - length
	var x0l = -w_out * 0.5
	var x0r = w_out * 0.5
	var x1l = -w_in * 0.5
	var x1r = w_in * 0.5

	# Cara Superior
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(x0l, y1, z0))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(x0r, y1, z0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(x1r, y1, z1))

	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(x0l, y1, z0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(x1r, y1, z1))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(x1l, y1, z1))

	# Cara Frontal (z1)
	st.set_normal(Vector3.FORWARD)
	_add_quad(st, Vector3(x1l, y1, z1), Vector3(x1r, y1, z1), Vector3(x1r, y0, z1), Vector3(x1l, y0, z1))

	return st.commit()

func _crear_mesh_marco_neon(w_out: float, w_in: float, length: float, z_start: float, height: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var y = CASILLA_H + height
	var z0 = z_start
	var z1 = z_start - length
	var x0l = -w_out * 0.5
	var x0r = w_out * 0.5
	var x1l = -w_in * 0.5
	var x1r = w_in * 0.5
	var t = 0.038 # Grosor de la cinta Neón LED

	# Construir los 4 segmentos perimetrales
	_add_quad(st, Vector3(x0l, y, z0), Vector3(x0r, y, z0), Vector3(x0r - t, y, z0 - t), Vector3(x0l + t, y, z0 - t))
	_add_quad(st, Vector3(x1l + t, y, z1 + t), Vector3(x1r - t, y, z1 + t), Vector3(x1r, y, z1), Vector3(x1l, y, z1))
	_add_quad(st, Vector3(x0l, y, z0), Vector3(x0l + t, y, z0 - t), Vector3(x1l + t, y, z1 + t), Vector3(x1l, y, z1))
	_add_quad(st, Vector3(x0r - t, y, z0 - t), Vector3(x0r, y, z0), Vector3(x1r, y, z1), Vector3(x1r - t, y, z1 + t))

	return st.commit()

func _add_quad(st: SurfaceTool, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(p1); st.add_vertex(p2); st.add_vertex(p3)
	st.add_vertex(p1); st.add_vertex(p3); st.add_vertex(p4)

func _color_base(es_esquina: bool) -> Color:
	match data.tipo:
		"salida":    return Color(0.85, 0.96, 0.86)
		"carcel":    return Color(0.96, 0.88, 0.72)
		"parking":   return Color(0.82, 0.92, 0.98)
		"ir_carcel": return Color(0.98, 0.82, 0.82)
		"suerte":    return Color(0.98, 0.94, 0.85)
		"arca":      return Color(0.85, 0.92, 0.98)
		"impuesto":  return Color(0.94, 0.93, 0.90)
		"estacion":  return Color(0.93, 0.93, 0.91)
		"servicio":  return Color(0.93, 0.93, 0.91)
		_:           return Color(0.96, 0.96, 0.93)

func _crear_nombre(w: float, d: float, es_esquina: bool) -> void:
	label_nombre = Label3D.new()
	label_nombre.text = data.nombre
	label_nombre.font_size = 36 if es_esquina else 28
	label_nombre.pixel_size = 0.008 if es_esquina else 0.006
	label_nombre.width = w / label_nombre.pixel_size * 0.9
	label_nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_nombre.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_nombre.no_depth_test = false
	label_nombre.render_priority = 2
	label_nombre.shaded = false
	label_nombre.double_sided = true
	label_nombre.modulate = Color(0.05, 0.05, 0.05)
	label_nombre.outline_modulate = Color(1.0, 1.0, 0.98)
	label_nombre.outline_size = 8
	label_nombre.rotation = Vector3(-PI / 2, 0, 0)

	var y_surface = CASILLA_H + 0.025
	match data.tipo:
		"calle":
			label_nombre.position = Vector3(0, y_surface, -0.1)
		"salida", "carcel", "parking", "ir_carcel":
			label_nombre.position = Vector3(0, y_surface, 0.15)
		_:
			label_nombre.position = Vector3(0, y_surface, -0.1)
	add_child(label_nombre)

func _crear_precio(w: float, d: float, es_esquina: bool) -> void:
	var y_surface = CASILLA_H + 0.025
	if data is PropiedadCasillaData:
		var prop = data as PropiedadCasillaData
		label_precio = Label3D.new()
		label_precio.text = "$" + str(prop.precio)
		label_precio.font_size = 24
		label_precio.pixel_size = 0.006
		label_precio.no_depth_test = false
		label_precio.render_priority = 2
		label_precio.shaded = false
		label_precio.double_sided = true
		label_precio.modulate = Color(0.0, 0.38, 0.05)
		label_precio.outline_modulate = Color(1.0, 1.0, 0.98)
		label_precio.outline_size = 6
		label_precio.rotation = Vector3(-PI / 2, 0, 0)
		label_precio.position = Vector3(0, y_surface, -d * 0.5 + 0.32)
		add_child(label_precio)

	if data.tipo in ["salida", "parking", "carcel", "ir_carcel", "suerte", "arca", "impuesto"]:
		var lbl_extra = Label3D.new()
		lbl_extra.font_size = 24 if not es_esquina else 28
		lbl_extra.pixel_size = 0.007 if es_esquina else 0.006
		lbl_extra.no_depth_test = false
		lbl_extra.render_priority = 2
		lbl_extra.shaded = false
		lbl_extra.double_sided = true
		lbl_extra.outline_size = 6
		lbl_extra.rotation = Vector3(-PI / 2, 0, 0)

		match data.tipo:
			"salida":
				lbl_extra.text = "Cobras $200"
				lbl_extra.modulate = Color(0.0, 0.5, 0.15)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, y_surface, -0.35)
			"parking":
				lbl_extra.text = "Descanso"
				lbl_extra.modulate = Color(0.1, 0.35, 0.7)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, y_surface, -0.35)
			"carcel":
				lbl_extra.text = "De visita"
				lbl_extra.modulate = Color(0.5, 0.3, 0.1)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, y_surface, -0.35)
			"ir_carcel":
				lbl_extra.text = "Ve directo"
				lbl_extra.modulate = Color(0.7, 0.1, 0.1)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, y_surface, -0.35)
			"suerte":
				lbl_extra.text = "?"
				lbl_extra.font_size = 42
				lbl_extra.pixel_size = 0.008
				lbl_extra.modulate = Color(0.85, 0.45, 0.05)
				lbl_extra.outline_modulate = Color(1,0.95,0.85)
				lbl_extra.outline_size = 8
				lbl_extra.position = Vector3(0, y_surface, 0.28)
			"arca":
				lbl_extra.text = "?"
				lbl_extra.font_size = 42
				lbl_extra.pixel_size = 0.008
				lbl_extra.modulate = Color(0.1, 0.35, 0.7)
				lbl_extra.outline_modulate = Color(0.85,0.92,1)
				lbl_extra.outline_size = 8
				lbl_extra.position = Vector3(0, y_surface, 0.28)
			"impuesto":
				var monto = 200 if data.id == 4 else 100
				lbl_extra.text = "Paga $%d" % monto
				lbl_extra.modulate = Color(0.7, 0.15, 0.15)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, y_surface, 0.28)
		add_child(lbl_extra)

func actualizar_propietario(color_propietario: Color) -> void:
	if indicador_dueno:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color_propietario
		mat.emission_enabled = true
		mat.emission = color_propietario
		mat.emission_energy_multiplier = 0.8
		indicador_dueno.material_override = mat
		indicador_dueno.visible = true

	# Encendido instantáneo de las líneas Neón LED con el color del propietario
	if mat_neon:
		var tw = create_tween().set_parallel(true)
		tw.tween_property(mat_neon, "emission", color_propietario, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat_neon, "albedo_color", color_propietario, 0.4)
		mat_neon.emission_energy_multiplier = 4.5

func actualizar_casas(num_casas: int) -> void:
	for child in contenedor_casas.get_children():
		child.queue_free()
	if num_casas <= 0:
		return

	# Superficie del Lote Urbano (y = CASILLA_H + 0.035 = 0.235m, z = -1.65m)
	var z_lote = -1.65
	var y_lote = CASILLA_H + 0.035

	if num_casas == 5:
		var hotel_inst = _crear_hotel_3d_clasico()
		hotel_inst.position = Vector3(0, y_lote, z_lote)
		contenedor_casas.add_child(hotel_inst)
	else:
		var spacing = CASILLA_W * 0.75 / (num_casas + 1)
		for i in range(num_casas):
			var x_off = -CASILLA_W * 0.375 + spacing * (i + 1)
			var casa_inst = _crear_casa_3d_clasica()
			casa_inst.position = Vector3(x_off, y_lote, z_lote)
			contenedor_casas.add_child(casa_inst)

func _crear_casa_3d_clasica() -> Node3D:
	var casa_root = Node3D.new()
	casa_root.name = "Casa3D"

	# Materiales PBR Verde Esmeralda de Lujo
	var mat_pared = StandardMaterial3D.new()
	mat_pared.albedo_color = Color(0.12, 0.75, 0.25) # Verde esmeralda vivo
	mat_pared.roughness = 0.3
	mat_pared.metallic = 0.05
	mat_pared.emission_enabled = true
	mat_pared.emission = Color(0.04, 0.35, 0.08)
	mat_pared.emission_energy_multiplier = 0.25

	var mat_techo = StandardMaterial3D.new()
	mat_techo.albedo_color = Color(0.06, 0.52, 0.16) # Verde tejado más oscuro
	mat_techo.roughness = 0.22
	mat_techo.clearcoat_enabled = true
	mat_techo.clearcoat = 0.5

	var mat_chimenea = StandardMaterial3D.new()
	mat_chimenea.albedo_color = Color(0.65, 0.25, 0.15) # Ladrillo terracota
	mat_chimenea.roughness = 0.6

	var mat_ventana = StandardMaterial3D.new()
	mat_ventana.albedo_color = Color(1.0, 0.95, 0.7)
	mat_ventana.emission_enabled = true
	mat_ventana.emission = Color(1.0, 0.90, 0.55)
	mat_ventana.emission_energy_multiplier = 0.8

	# 1. Cuerpo principal (Paredes)
	var paredes = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(0.20, 0.14, 0.16)
	paredes.mesh = box_p
	paredes.material_override = mat_pared
	paredes.position = Vector3(0, 0.07, 0)
	casa_root.add_child(paredes)

	# 2. Techo a dos aguas (Prisma triangular)
	var techo = MeshInstance3D.new()
	var prism = PrismMesh.new()
	prism.size = Vector3(0.22, 0.09, 0.18)
	techo.mesh = prism
	techo.material_override = mat_techo
	techo.position = Vector3(0, 0.14 + 0.045, 0)
	techo.rotation = Vector3(0, PI / 2.0, 0) # Orientar el tejado a dos aguas
	casa_root.add_child(techo)

	# 3. Chimenea 3D
	var chimenea = MeshInstance3D.new()
	var box_ch = BoxMesh.new()
	box_ch.size = Vector3(0.035, 0.07, 0.035)
	chimenea.mesh = box_ch
	chimenea.material_override = mat_chimenea
	chimenea.position = Vector3(0.06, 0.16, 0.02)
	casa_root.add_child(chimenea)

	# 4. Puerta frontal
	var puerta = MeshInstance3D.new()
	var box_dr = BoxMesh.new()
	box_dr.size = Vector3(0.04, 0.07, 0.01)
	puerta.mesh = box_dr
	var mat_dr = StandardMaterial3D.new()
	mat_dr.albedo_color = Color(0.35, 0.20, 0.10)
	puerta.material_override = mat_dr
	puerta.position = Vector3(0, 0.035, 0.081)
	casa_root.add_child(puerta)

	# 5. Ventanas iluminadas
	for side in [-0.05, 0.05]:
		var win = MeshInstance3D.new()
		var box_w = BoxMesh.new()
		box_w.size = Vector3(0.035, 0.035, 0.01)
		win.mesh = box_w
		win.material_override = mat_ventana
		win.position = Vector3(side, 0.085, 0.081)
		casa_root.add_child(win)

	return casa_root

func _crear_hotel_3d_clasico() -> Node3D:
	var hotel_root = Node3D.new()
	hotel_root.name = "Hotel3D"

	# Materiales PBR Rojo Rubí y Dorado de Lujo
	var mat_cuerpo = StandardMaterial3D.new()
	mat_cuerpo.albedo_color = Color(0.88, 0.12, 0.14) # Rojo rubí brillante
	mat_cuerpo.roughness = 0.22
	mat_cuerpo.clearcoat_enabled = true
	mat_cuerpo.clearcoat = 0.6
	mat_cuerpo.emission_enabled = true
	mat_cuerpo.emission = Color(0.55, 0.06, 0.08)
	mat_cuerpo.emission_energy_multiplier = 0.35

	var mat_techo = StandardMaterial3D.new()
	mat_techo.albedo_color = Color(0.60, 0.08, 0.10) # Rojo granate
	mat_techo.roughness = 0.3

	var mat_oro = StandardMaterial3D.new()
	mat_oro.albedo_color = Color(0.92, 0.78, 0.22)
	mat_oro.metallic = 0.8
	mat_oro.roughness = 0.25

	var mat_ventana = StandardMaterial3D.new()
	mat_ventana.albedo_color = Color(1.0, 0.95, 0.7)
	mat_ventana.emission_enabled = true
	mat_ventana.emission = Color(1.0, 0.88, 0.45)
	mat_ventana.emission_energy_multiplier = 0.9

	# 1. Edificio Principal
	var cuerpo = MeshInstance3D.new()
	var box_c = BoxMesh.new()
	box_c.size = Vector3(0.44, 0.26, 0.32)
	cuerpo.mesh = box_c
	cuerpo.material_override = mat_cuerpo
	cuerpo.position = Vector3(0, 0.13, 0)
	hotel_root.add_child(cuerpo)

	# 2. Penthouse / Nivel Superior
	var penthouse = MeshInstance3D.new()
	var box_ph = BoxMesh.new()
	box_ph.size = Vector3(0.32, 0.09, 0.22)
	penthouse.mesh = box_ph
	penthouse.material_override = mat_techo
	penthouse.position = Vector3(0, 0.26 + 0.045, 0)
	hotel_root.add_child(penthouse)

	# 3. Cornisa Dorada Superior
	var cornisa = MeshInstance3D.new()
	var box_cr = BoxMesh.new()
	box_cr.size = Vector3(0.46, 0.02, 0.34)
	cornisa.mesh = box_cr
	cornisa.material_override = mat_oro
	cornisa.position = Vector3(0, 0.26, 0)
	hotel_root.add_child(cornisa)

	# 4. Letrero "HOTEL" en el penthouse
	var label_h = Label3D.new()
	label_h.text = "H O T E L"
	label_h.font_size = 28
	label_h.pixel_size = 0.004
	label_h.modulate = Color(1.0, 0.90, 0.3)
	label_h.outline_modulate = Color.BLACK
	label_h.outline_size = 6
	label_h.position = Vector3(0, 0.31, 0.111)
	hotel_root.add_child(label_h)

	# 5. Filas de Ventanas PBR en la fachada frontal
	for row in range(2):
		var y_pos = 0.07 + row * 0.09
		for col in range(4):
			var x_pos = -0.15 + col * 0.10
			var win = MeshInstance3D.new()
			var box_w = BoxMesh.new()
			box_w.size = Vector3(0.05, 0.05, 0.01)
			win.mesh = box_w
			win.material_override = mat_ventana
			win.position = Vector3(x_pos, y_pos, 0.161)
			hotel_root.add_child(win)

	return hotel_root
