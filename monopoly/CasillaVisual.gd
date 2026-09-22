class_name CasillaVisual
extends Node3D

var data: CasillaData
var mesh_base: MeshInstance3D
var mesh_banda: MeshInstance3D
var indicador_dueno: MeshInstance3D
var contenedor_casas: Node3D
var contenedor_icono: Node3D
var label_nombre: Label3D
var label_precio: Label3D

func setup(p_data: CasillaData, es_esquina: bool = false) -> void:
	data = p_data
	
	contenedor_casas = Node3D.new()
	contenedor_casas.name = "ContenedorCasas"
	add_child(contenedor_casas)
	
	contenedor_icono = Node3D.new()
	contenedor_icono.name = "ContenedorIcono"
	add_child(contenedor_icono)
	
	# Malla Base de la Casilla
	mesh_base = MeshInstance3D.new()
	var box_base = BoxMesh.new()
	
	if es_esquina:
		box_base.size = Vector3(1.7, 0.16, 1.7)
	else:
		box_base.size = Vector3(1.3, 0.16, 1.7)
		
	mesh_base.mesh = box_base
	
	var mat_base = StandardMaterial3D.new()
	mat_base.roughness = 0.2
	mat_base.specular = 0.5
	
	if data.id == 0: # SALIDA
		mat_base.albedo_color = Color(0.08, 0.65, 0.28)
	elif data.id == 10: # CÁRCEL
		mat_base.albedo_color = Color(0.85, 0.48, 0.12)
	elif data.id == 20: # PARKING
		mat_base.albedo_color = Color(0.12, 0.5, 0.85)
	elif data.id == 30: # IR CÁRCEL
		mat_base.albedo_color = Color(0.88, 0.15, 0.15)
	elif data.tipo in ["suerte", "arca"]:
		mat_base.albedo_color = Color(0.96, 0.94, 0.88)
	elif data.tipo == "impuesto":
		mat_base.albedo_color = Color(0.92, 0.9, 0.92)
	else:
		mat_base.albedo_color = Color(0.98, 0.97, 0.94)
		
	mesh_base.material_override = mat_base
	mesh_base.position = Vector3(0, 0.08, 0)
	add_child(mesh_base)
	
	# Banda de Color para Calles
	if data.tipo == "calle":
		mesh_banda = MeshInstance3D.new()
		var box_banda = BoxMesh.new()
		box_banda.size = Vector3(1.3, 0.02, 0.48)
		mesh_banda.mesh = box_banda
		
		var mat_banda = StandardMaterial3D.new()
		mat_banda.albedo_color = data.color_grupo
		mat_banda.roughness = 0.2
		mesh_banda.material_override = mat_banda
		mesh_banda.position = Vector3(0, 0.17, 0.55)
		add_child(mesh_banda)
		
	# Indicador de Propietario (Placa resplandeciente)
	indicador_dueno = MeshInstance3D.new()
	var box_dueno = BoxMesh.new()
	box_dueno.size = Vector3(1.31, 0.04, 0.16) if not es_esquina else Vector3(1.71, 0.04, 0.16)
	indicador_dueno.mesh = box_dueno
	indicador_dueno.position = Vector3(0, 0.17, -0.76)
	indicador_dueno.visible = false
	add_child(indicador_dueno)
	
	# Iconos y Detalle Visual 3D
	_crear_icono_casilla()
	
	# Label3D de Nombre de Alta Nitidez
	label_nombre = Label3D.new()
	label_nombre.text = data.nombre
	label_nombre.font_size = 18
	label_nombre.pixel_size = 0.003
	label_nombre.no_depth_test = true
	label_nombre.render_priority = 10
	label_nombre.shaded = false
	label_nombre.double_sided = true
	label_nombre.modulate = Color(0.0, 0.0, 0.0)
	label_nombre.outline_modulate = Color(1.0, 1.0, 1.0)
	label_nombre.outline_size = 4
	label_nombre.rotation = Vector3(-PI / 2, 0, 0)
	label_nombre.position = Vector3(0, 0.22, 0.15 if data.tipo == "calle" else -0.1)
	add_child(label_nombre)
	
	# Label3D de Precio de Alta Nitidez
	if data is PropiedadCasillaData:
		var prop = data as PropiedadCasillaData
		label_precio = Label3D.new()
		label_precio.text = "$" + str(prop.precio)
		label_precio.font_size = 16
		label_precio.pixel_size = 0.003
		label_precio.no_depth_test = true
		label_precio.render_priority = 10
		label_precio.shaded = false
		label_precio.double_sided = true
		label_precio.modulate = Color(0.1, 0.45, 0.1)
		label_precio.outline_modulate = Color(1.0, 1.0, 1.0)
		label_precio.outline_size = 4
		label_precio.rotation = Vector3(-PI / 2, 0, 0)
		label_precio.position = Vector3(0, 0.22, -0.55)
		add_child(label_precio)

func _crear_icono_casilla() -> void:
	match data.tipo:
		"estacion":
			var loco = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.35, 0.16, 0.5)
			loco.mesh = box
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.15, 0.15, 0.2)
			mat.metallic = 0.8
			loco.material_override = mat
			loco.position = Vector3(0, 0.24, 0.15)
			contenedor_icono.add_child(loco)
			
			var lbl_st = Label3D.new()
			lbl_st.text = "🚂 TREN"
			lbl_st.font_size = 18
			lbl_st.pixel_size = 0.003
			lbl_st.no_depth_test = true
			lbl_st.render_priority = 10
			lbl_st.shaded = false
			lbl_st.modulate = Color.BLACK
			lbl_st.outline_modulate = Color.WHITE
			lbl_st.outline_size = 4
			lbl_st.rotation = Vector3(-PI / 2, 0, 0)
			lbl_st.position = Vector3(0, 0.22, 0.38)
			contenedor_icono.add_child(lbl_st)
			
		"servicio":
			var foco = MeshInstance3D.new()
			var sphere = SphereMesh.new()
			sphere.radius = 0.16
			sphere.height = 0.32
			foco.mesh = sphere
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.95, 0.85, 0.1) if data.id == 12 else Color(0.15, 0.6, 0.95)
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 0.8
			foco.material_override = mat
			foco.position = Vector3(0, 0.26, 0.15)
			contenedor_icono.add_child(foco)
			
		"suerte", "arca":
			var lbl_q = Label3D.new()
			lbl_q.text = "❓" if data.tipo == "suerte" else "📦"
			lbl_q.font_size = 36
			lbl_q.pixel_size = 0.0035
			lbl_q.no_depth_test = true
			lbl_q.render_priority = 10
			lbl_q.shaded = false
			lbl_q.rotation = Vector3(-PI / 2, 0, 0)
			lbl_q.position = Vector3(0, 0.22, 0.25)
			contenedor_icono.add_child(lbl_q)
			
		"impuesto":
			var moneda = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.18
			cyl.bottom_radius = 0.18
			cyl.height = 0.12
			moneda.mesh = cyl
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.95, 0.8, 0.15)
			mat.metallic = 0.9
			mat.roughness = 0.1
			moneda.material_override = mat
			moneda.position = Vector3(0, 0.22, 0.18)
			contenedor_icono.add_child(moneda)
			
			var lbl_tax = Label3D.new()
			lbl_tax.text = "PAGA $" + str(200 if data.id == 4 else 100)
			lbl_tax.font_size = 14
			lbl_tax.pixel_size = 0.003
			lbl_tax.no_depth_test = true
			lbl_tax.render_priority = 10
			lbl_tax.shaded = false
			lbl_tax.modulate = Color(0.85, 0.1, 0.1)
			lbl_tax.outline_modulate = Color.WHITE
			lbl_tax.outline_size = 3
			lbl_tax.rotation = Vector3(-PI / 2, 0, 0)
			lbl_tax.position = Vector3(0, 0.22, -0.45)
			contenedor_icono.add_child(lbl_tax)
			
		"salida":
			var flecha = Label3D.new()
			flecha.text = "🟢 SALIDA\nCobras $200"
			flecha.font_size = 22
			flecha.pixel_size = 0.0035
			flecha.no_depth_test = true
			flecha.render_priority = 10
			flecha.shaded = false
			flecha.modulate = Color(0.1, 0.9, 0.2)
			flecha.outline_modulate = Color.BLACK
			flecha.outline_size = 5
			flecha.rotation = Vector3(-PI / 2, 0, 0)
			flecha.position = Vector3(0, 0.22, 0.0)
			contenedor_icono.add_child(flecha)
			
		"parking":
			var sign_p = Label3D.new()
			sign_p.text = "🅿️ PARKING\nGRATUITO"
			sign_p.font_size = 18
			sign_p.pixel_size = 0.003
			sign_p.no_depth_test = true
			sign_p.render_priority = 10
			sign_p.shaded = false
			sign_p.modulate = Color(0.15, 0.5, 0.9)
			sign_p.outline_modulate = Color.WHITE
			sign_p.outline_size = 4
			sign_p.rotation = Vector3(-PI / 2, 0, 0)
			sign_p.position = Vector3(0, 0.22, 0.0)
			contenedor_icono.add_child(sign_p)

func actualizar_propietario(color_propietario: Color) -> void:
	if not indicador_dueno: return
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color_propietario
	mat.emission_enabled = true
	mat.emission = color_propietario
	mat.emission_energy_multiplier = 0.6
	indicador_dueno.material_override = mat
	indicador_dueno.visible = true

func actualizar_casas(num_casas: int) -> void:
	for child in contenedor_casas.get_children():
		child.queue_free()
		
	if num_casas <= 0: return
	
	if num_casas == 5:
		var hotel = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.42, 0.22, 0.28)
		hotel.mesh = box
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.12, 0.12)
		mat.roughness = 0.3
		hotel.material_override = mat
		hotel.position = Vector3(0, 0.27, 0.55)
		contenedor_casas.add_child(hotel)
	else:
		for i in range(num_casas):
			var casa = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.18, 0.18, 0.18)
			casa.mesh = box
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.1, 0.75, 0.2)
			mat.roughness = 0.3
			casa.material_override = mat
			casa.position = Vector3(-0.42 + (i * 0.26), 0.26, 0.55)
			contenedor_casas.add_child(casa)
