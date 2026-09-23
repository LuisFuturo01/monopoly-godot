class_name CasillaVisual
extends Node3D

var data: CasillaData
var mesh_base: MeshInstance3D
var mesh_banda: MeshInstance3D
var mesh_borde: MeshInstance3D
var indicador_dueno: MeshInstance3D
var contenedor_casas: Node3D
var label_nombre: Label3D
var label_precio: Label3D

const CASILLA_W: float = 1.28
const CASILLA_D: float = 1.68
const CASILLA_H: float = 0.35
const ESQUINA_SIZE: float = 1.68
const BANDA_H: float = 0.44
const BORDE_GROSOR: float = 0.035

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

	# ── Banda de color del grupo (calles) ──
	if data.tipo == "calle":
		mesh_banda = MeshInstance3D.new()
		var box_banda = BoxMesh.new()
		box_banda.size = Vector3(w, 0.05, BANDA_H)
		mesh_banda.mesh = box_banda
		var mat_banda = StandardMaterial3D.new()
		mat_banda.albedo_color = data.color_grupo
		mat_banda.roughness = 0.15
		mat_banda.emission_enabled = true
		mat_banda.emission = data.color_grupo.lightened(0.15)
		mat_banda.emission_energy_multiplier = 0.35
		mesh_banda.material_override = mat_banda
		mesh_banda.position = Vector3(0, CASILLA_H + 0.03, d * 0.5 - BANDA_H * 0.5)
		add_child(mesh_banda)

	# ── Indicador propietario ──
	indicador_dueno = MeshInstance3D.new()
	var box_d = BoxMesh.new()
	box_d.size = Vector3(w, 0.06, 0.14)
	indicador_dueno.mesh = box_d
	indicador_dueno.position = Vector3(0, CASILLA_H + 0.035, -d * 0.5 - 0.02)
	indicador_dueno.visible = false
	add_child(indicador_dueno)

	# ── Textos ──
	_crear_nombre(w, d, es_esquina)
	_crear_precio(w, d, es_esquina)

func _color_base(es_esquina: bool) -> Color:
	match data.tipo:
		"salida":    return Color(0.82, 0.96, 0.84)
		"carcel":    return Color(0.96, 0.85, 0.65)
		"parking":   return Color(0.78, 0.9, 0.98)
		"ir_carcel": return Color(0.98, 0.76, 0.76)
		"suerte":    return Color(0.98, 0.93, 0.8)
		"arca":      return Color(0.82, 0.9, 0.98)
		"impuesto":  return Color(0.93, 0.93, 0.9)
		"estacion":  return Color(0.92, 0.92, 0.9)
		"servicio":  return Color(0.92, 0.92, 0.9)
		_:           return Color(0.95, 0.96, 0.92)

func _crear_nombre(w: float, d: float, es_esquina: bool) -> void:
	label_nombre = Label3D.new()
	label_nombre.text = data.nombre
	label_nombre.font_size = 36 if es_esquina else 28
	label_nombre.pixel_size = 0.008 if es_esquina else 0.006
	label_nombre.width = w / label_nombre.pixel_size * 0.9
	label_nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_nombre.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_nombre.no_depth_test = true
	label_nombre.render_priority = 10
	label_nombre.shaded = false
	label_nombre.double_sided = true
	label_nombre.modulate = Color(0.05, 0.05, 0.05)
	label_nombre.outline_modulate = Color(1.0, 1.0, 0.98)
	label_nombre.outline_size = 8
	label_nombre.rotation = Vector3(-PI / 2, 0, 0)

	match data.tipo:
		"calle":
			label_nombre.position = Vector3(0, CASILLA_H + 0.045, -0.1)
		"salida", "carcel", "parking", "ir_carcel":
			label_nombre.position = Vector3(0, CASILLA_H + 0.045, 0.15)
		_:
			label_nombre.position = Vector3(0, CASILLA_H + 0.045, -0.1)
	add_child(label_nombre)

func _crear_precio(w: float, d: float, es_esquina: bool) -> void:
	if data is PropiedadCasillaData:
		var prop = data as PropiedadCasillaData
		label_precio = Label3D.new()
		label_precio.text = "$" + str(prop.precio)
		label_precio.font_size = 24
		label_precio.pixel_size = 0.006
		label_precio.no_depth_test = true
		label_precio.render_priority = 10
		label_precio.shaded = false
		label_precio.double_sided = true
		label_precio.modulate = Color(0.0, 0.35, 0.0)
		label_precio.outline_modulate = Color(1.0, 1.0, 0.98)
		label_precio.outline_size = 6
		label_precio.rotation = Vector3(-PI / 2, 0, 0)
		label_precio.position = Vector3(0, CASILLA_H + 0.045, -d * 0.5 + 0.32)
		add_child(label_precio)

	# Texto especial para esquinas y tipos sin precio
	if data.tipo in ["salida", "parking", "carcel", "ir_carcel", "suerte", "arca", "impuesto"]:
		var lbl_extra = Label3D.new()
		lbl_extra.font_size = 24 if not es_esquina else 28
		lbl_extra.pixel_size = 0.007 if es_esquina else 0.006
		lbl_extra.no_depth_test = true
		lbl_extra.render_priority = 10
		lbl_extra.shaded = false
		lbl_extra.double_sided = true
		lbl_extra.outline_size = 6
		lbl_extra.rotation = Vector3(-PI / 2, 0, 0)

		match data.tipo:
			"salida":
				lbl_extra.text = "Cobras $200"
				lbl_extra.modulate = Color(0.0, 0.5, 0.15)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, CASILLA_H + 0.045, -0.35)
			"parking":
				lbl_extra.text = "Descanso"
				lbl_extra.modulate = Color(0.1, 0.35, 0.7)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, CASILLA_H + 0.045, -0.35)
			"carcel":
				lbl_extra.text = "De visita"
				lbl_extra.modulate = Color(0.5, 0.3, 0.1)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, CASILLA_H + 0.045, -0.35)
			"ir_carcel":
				lbl_extra.text = "Ve directo"
				lbl_extra.modulate = Color(0.7, 0.1, 0.1)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, CASILLA_H + 0.045, -0.35)
			"suerte":
				lbl_extra.text = "?"
				lbl_extra.font_size = 42
				lbl_extra.pixel_size = 0.008
				lbl_extra.modulate = Color(0.85, 0.45, 0.05)
				lbl_extra.outline_modulate = Color(1,0.95,0.85)
				lbl_extra.outline_size = 8
				lbl_extra.position = Vector3(0, CASILLA_H + 0.045, 0.28)
			"arca":
				lbl_extra.text = "?"
				lbl_extra.font_size = 42
				lbl_extra.pixel_size = 0.008
				lbl_extra.modulate = Color(0.1, 0.35, 0.7)
				lbl_extra.outline_modulate = Color(0.85,0.92,1)
				lbl_extra.outline_size = 8
				lbl_extra.position = Vector3(0, CASILLA_H + 0.045, 0.28)
			"impuesto":
				var monto = 200 if data.id == 4 else 100
				lbl_extra.text = "Paga $%d" % monto
				lbl_extra.modulate = Color(0.7, 0.15, 0.15)
				lbl_extra.outline_modulate = Color(1,1,1)
				lbl_extra.position = Vector3(0, CASILLA_H + 0.045, 0.28)
		add_child(lbl_extra)

func actualizar_propietario(color_propietario: Color) -> void:
	if not indicador_dueno:
		return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color_propietario
	mat.emission_enabled = true
	mat.emission = color_propietario
	mat.emission_energy_multiplier = 0.8
	indicador_dueno.material_override = mat
	indicador_dueno.visible = true

func actualizar_casas(num_casas: int) -> void:
	for child in contenedor_casas.get_children():
		child.queue_free()
	if num_casas <= 0:
		return

	if num_casas == 5:
		var hotel = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.46, 0.26, 0.32)
		hotel.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.88, 0.12, 0.12)
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.05, 0.05)
		mat.emission_energy_multiplier = 0.4
		hotel.material_override = mat
		hotel.position = Vector3(0, CASILLA_H + 0.14, CASILLA_D * 0.5 - BANDA_H * 0.5)
		contenedor_casas.add_child(hotel)
	else:
		var spacing = CASILLA_W / (num_casas + 1)
		for i in range(num_casas):
			var casa = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.18, 0.18, 0.18)
			casa.mesh = box
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.15, 0.72, 0.25)
			mat.roughness = 0.3
			casa.material_override = mat
			var x_off = -CASILLA_W * 0.5 + spacing * (i + 1)
			casa.position = Vector3(x_off, CASILLA_H + 0.1, CASILLA_D * 0.5 - BANDA_H * 0.5)
			contenedor_casas.add_child(casa)
