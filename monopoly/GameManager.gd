class_name GameManager
extends Node3D

var tablero_manager: TableroManager
var casillas_data: Array[CasillaData] = []
var jugadores: Array[JugadorData] = []
var turno_actual: int = 0
var esta_procesando_turno: bool = false

# Cámara y sistema orbital 3D
var camara: Camera3D
var cam_distance: float = 14.5
var cam_yaw: float = 0.0
var cam_pitch: float = -deg_to_rad(52.0)
var cam_target: Vector3 = Vector3.ZERO

var curr_distance: float = 14.5
var curr_yaw: float = 0.0
var curr_pitch: float = -deg_to_rad(52.0)
var curr_target: Vector3 = Vector3.ZERO

var is_orbiting: bool = false
var modo_cine: bool = false
var btn_modo_cine: Button
var btn_reset_cam: Button

# UI
var canvas: CanvasLayer

# HUD Superior — Tarjetas de jugador
var hud_top: HBoxContainer

# Notificación central
var notif_label: Label

# Dados overlay
var dados_panel: PanelContainer
var dado1_label: Label
var dado2_label: Label
var dados_msg: Label

# Panel de compra
var compra_panel: PanelContainer
var compra_info: Label
var btn_comprar: Button
var btn_pasar: Button

# Modal detalle casilla
var detalle_modal: PanelContainer
var detalle_vb_contenido: VBoxContainer

# Botón principal
var btn_tirar: Button

# Player 3D tags en la mesa
var player_tags3d: Array[Label3D] = []

func _ready() -> void:
	randomize()
	_setup_camara()

	tablero_manager = TableroManager.new()
	tablero_manager.name = "TableroManager"
	add_child(tablero_manager)
	casillas_data = tablero_manager.construir_tablero()

	_inicializar_jugadores(2)
	_crear_tags_3d_mesa()
	_construir_ui()
	_actualizar_hud()
	_notificar("🎲 ¡Bienvenido a Monopoly 3D!")

func _setup_camara() -> void:
	camara = Camera3D.new()
	camara.name = "Camara"
	camara.near = 0.1
	camara.far = 100.0
	add_child(camara)
	_actualizar_posicion_camara(1.0)

func _process(delta: float) -> void:
	_actualizar_posicion_camara(delta)

func _actualizar_posicion_camara(delta: float) -> void:
	if not camara:
		return

	if modo_cine and not is_orbiting:
		cam_yaw += delta * 0.22

	if Input.is_key_pressed(KEY_Q):
		cam_yaw -= delta * 1.6
	if Input.is_key_pressed(KEY_E):
		cam_yaw += delta * 1.6

	curr_target = curr_target.lerp(cam_target, delta * 3.5)
	curr_distance = lerp(curr_distance, cam_distance, delta * 6.0)
	curr_yaw = lerp_angle(curr_yaw, cam_yaw, delta * 8.0)
	curr_pitch = lerp(curr_pitch, cam_pitch, delta * 8.0)

	var offset_x = curr_distance * cos(curr_pitch) * sin(curr_yaw)
	var offset_y = curr_distance * -sin(curr_pitch)
	var offset_z = curr_distance * cos(curr_pitch) * cos(curr_yaw)

	camara.position = curr_target + Vector3(offset_x, offset_y, offset_z)
	camara.look_at(curr_target, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not esta_procesando_turno:
		ejecutar_turno()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_distance = clamp(cam_distance - 1.2, 5.5, 24.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_distance = clamp(cam_distance + 1.2, 5.5, 24.0)
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_intentar_seleccionar_casilla_3d(event.position)

	elif event is InputEventMouseMotion and is_orbiting:
		var sens = 0.005
		cam_yaw -= event.relative.x * sens
		cam_pitch = clamp(cam_pitch - event.relative.y * sens, -deg_to_rad(85.0), -deg_to_rad(12.0))

func _intentar_seleccionar_casilla_3d(click_pos: Vector2) -> void:
	if not camara or casillas_data.is_empty():
		return

	var from = camara.project_ray_origin(click_pos)
	var dir = camara.project_ray_normal(click_pos)

	if abs(dir.y) < 0.001:
		return

	var t = (0.2 - from.y) / dir.y
	if t <= 0.0:
		return

	var hit_pos = from + dir * t

	var mejor_cas: CasillaData = null
	var min_dist: float = 1.6

	for cas in casillas_data:
		if cas.nodo_visual:
			var pos = cas.nodo_visual.global_position
			var d = Vector2(hit_pos.x - pos.x, hit_pos.z - pos.z).length()
			if d < min_dist:
				min_dist = d
				mejor_cas = cas

	if mejor_cas:
		_mostrar_modal_detalle_casilla(mejor_cas)

func _inicializar_jugadores(cantidad: int) -> void:
	var colores = [Color(0.92, 0.22, 0.22), Color(0.22, 0.5, 0.92)]
	var nombres = ["Jugador 1", "Jugador 2"]

	for i in range(cantidad):
		var jd = JugadorData.new(i, nombres[i], 1500, colores[i])
		var ficha = FichaVisual.new()
		ficha.name = "Ficha_%d" % i
		ficha.setup(i, colores[i], i)
		add_child(ficha)
		jd.nodo_ficha = ficha
		jugadores.append(jd)
		ficha.position = tablero_manager.obtener_posicion_casilla_con_offset(0, i, cantidad)

# ─────────────────────────────────────────────────────────────────────
#   TURNO
# ─────────────────────────────────────────────────────────────────────

func ejecutar_turno() -> void:
	if esta_procesando_turno:
		return
	esta_procesando_turno = true
	btn_tirar.disabled = true

	var jug = jugadores[turno_actual]
	var d1 = randi_range(1, 6)
	var d2 = randi_range(1, 6)
	var total = d1 + d2

	_animar_dados(d1, d2, total, func():
		_mover_ficha(jug, total)
	)

const Dado3DScript = preload("res://Dado3DVisual.gd")
const ManoScript = preload("res://ManoVisual.gd")

# Dados y Mano 3D
var dado1_3d: Node3D
var dado2_3d: Node3D
var mano_3d: Node3D

func _animar_dados(d1: int, d2: int, total: int, callback: Callable) -> void:
	dados_panel.visible = false

	if not dado1_3d:
		dado1_3d = Dado3DScript.new()
		dado1_3d.name = "Dado3D_1"
		add_child(dado1_3d)
	if not dado2_3d:
		dado2_3d = Dado3DScript.new()
		dado2_3d.name = "Dado3D_2"
		add_child(dado2_3d)

	if not mano_3d:
		mano_3d = ManoScript.new()
		mano_3d.name = "Mano3D"
		add_child(mano_3d)

	mano_3d.visible = true
	mano_3d.agarrar_dados(1.0)

	# Posición inicial de la mano
	var pos_mano = Vector3(-5.0, 1.2, 7.0)
	mano_3d.position = pos_mano
	mano_3d.rotation = Vector3(deg_to_rad(10), 0, 0)

	# ── CLAVE: Dados ajustados mínimamente en altura (Y=1.4) y avance (-Z=-2.6) ──
	dado1_3d.reparent(mano_3d, false)
	dado2_3d.reparent(mano_3d, false)
	dado1_3d.position = Vector3(-pos_mano.x - 0.9, 3.5, -4)
	dado2_3d.position = Vector3(-pos_mano.x - 0.6, 3.5, -4)
	dado1_3d.scale = Vector3(0.7, 0.7, 0.7)
	dado2_3d.scale = Vector3(0.7, 0.7, 0.7)
	dado1_3d.rotation = Vector3.ZERO
	dado2_3d.rotation = Vector3.ZERO
	dado1_3d.visible = true
	dado2_3d.visible = true

	var jug = jugadores[turno_actual]
	_notificar("🎲 " + jug.nombre + " agita los dados...")

	# FASE 1: Shake — Solo movemos la mano, los dados siguen como hijos
	var tw = create_tween()
	for i in range(10):
		var off = Vector3(randf_range(-0.16, 0.16), randf_range(-0.1, 0.1), randf_range(-0.16, 0.16))
		var r1 = Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI))
		var r2 = Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI))

		tw.tween_property(mano_3d, "position", pos_mano + off, 0.045)
		tw.parallel().tween_property(dado1_3d, "rotation", r1, 0.045)
		tw.parallel().tween_property(dado2_3d, "rotation", r2, 0.045)

	# FASE 2: Lanzamiento — La mano realiza su movimiento normal y los dados se lanzan con 0.5s de retraso
	tw.tween_callback(func():
		_notificar("🎲 " + jug.nombre + " lanza los dados...")

		# La mano se desplaza hacia adelante realizando el movimiento de lanzamiento (tiempo normal)
		var tw_mano = create_tween().set_parallel(true)
		tw_mano.tween_property(mano_3d, "position", Vector3(-5.0, 1.4, 5.3), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_mano.tween_method(mano_3d.agarrar_dados, 1.0, 0.0, 0.35)

		# Tras el impulso, la mano desciende suavemente saliendo de la pantalla
		tw_mano.chain().tween_property(mano_3d, "position", Vector3(-5.0, -2.5, 8.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw_mano.chain().tween_callback(func():
			mano_3d.visible = false
		)

		# Durante los 0.5s de espera, los dados avanzan 0.6 a la izquierda (-X) y 0.6 hacia adelante (-Z) en la mano
		var tw_windup = create_tween().set_parallel(true)
		var target_pos1 = Vector3(-pos_mano.x - 1.5, 3.5, -4.6)
		var target_pos2 = Vector3(-pos_mano.x - 1.2, 3.5, -4.6)
		tw_windup.tween_property(dado1_3d, "position", target_pos1, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_windup.tween_property(dado2_3d, "position", target_pos2, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		# Retraso de 0.5s para la liberación y lanzamiento de los dados al tablero
		var tw_delay = create_tween()
		tw_delay.tween_interval(0.5)
		tw_delay.tween_callback(func():
			# Reparentar dados al nodo raíz preservando posición global
			dado1_3d.reparent(self, true)
			dado2_3d.reparent(self, true)

			# Destinos aleatorios naturales en el centro del tablero
			var pos_dest1 = Vector3(-1.3 + randf_range(-0.4, 0.4), 0.36, -0.3 + randf_range(-0.4, 0.4))
			var pos_dest2 = Vector3(1.3 + randf_range(-0.4, 0.4), 0.36, -1.1 + randf_range(-0.4, 0.4))

			# Obtener la rotación matemática exacta para que las caras d1 y d2 queden mirando hacia arriba (+Y)
			var rot_final1 = dado1_3d.obtener_rotacion_para_valor(d1)
			var rot_final2 = dado2_3d.obtener_rotacion_para_valor(d2)

			var tw_throw = create_tween().set_parallel(true)

			# Escala de dados: de 0.7 en mano a 1.0 (tamaño normal) en el tablero
			tw_throw.tween_property(dado1_3d, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw_throw.tween_property(dado2_3d, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

			# Desplazamiento X, Z con desaceleración desde la mano hacia el tablero
			tw_throw.tween_property(dado1_3d, "position:x", pos_dest1.x, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw_throw.tween_property(dado1_3d, "position:z", pos_dest1.z, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw_throw.tween_property(dado2_3d, "position:x", pos_dest2.x, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw_throw.tween_property(dado2_3d, "position:z", pos_dest2.z, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

			# Parábola de salto Y desde la palma rebotando hasta el tablero
			var tw_y1 = create_tween().set_parallel(false)
			tw_y1.tween_property(dado1_3d, "position:y", 1.85, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw_y1.tween_property(dado1_3d, "position:y", 0.36, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw_y1.tween_property(dado1_3d, "position:y", 0.68, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw_y1.tween_property(dado1_3d, "position:y", 0.36, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

			var tw_y2 = create_tween().set_parallel(false)
			tw_y2.tween_property(dado2_3d, "position:y", 2.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw_y2.tween_property(dado2_3d, "position:y", 0.36, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw_y2.tween_property(dado2_3d, "position:y", 0.62, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw_y2.tween_property(dado2_3d, "position:y", 0.36, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

			# Giro 3D girando sobre sus 3 ejes y asentándose suavemente en el resultado exacto
			var spin1 = rot_final1 + Vector3(PI * 4, PI * 6, PI * 2)
			var spin2 = rot_final2 + Vector3(-PI * 4, PI * 4, -PI * 4)

			tw_throw.tween_property(dado1_3d, "rotation", spin1, 0.4)
			tw_throw.tween_property(dado2_3d, "rotation", spin2, 0.4)
			tw_throw.chain().tween_property(dado1_3d, "rotation", rot_final1, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw_throw.tween_property(dado2_3d, "rotation", rot_final2, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

			# FASE 3: Una vez asentados en el tablero -> Mostrar HUD nítido
			tw_throw.chain().tween_callback(func():
				var caras = ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"]
				dado1_label.text = caras[d1 - 1]
				dado2_label.text = caras[d2 - 1]
				dados_msg.text = jug.nombre + " — ¡Avanza %d casillas!" % total
				dados_panel.visible = true

				var tw_wait = create_tween()
				tw_wait.tween_interval(1.1)
				tw_wait.tween_callback(func():
					dados_panel.visible = false
					dado1_3d.visible = false
					dado2_3d.visible = false
					if callback.is_valid():
						callback.call()
				)
			)
		)
	)

func _mover_ficha(jug: JugadorData, total: int) -> void:
	var pos_ant = jug.posicion
	var nueva = (pos_ant + total) % 40
	var puntos: Array[Vector3] = []

	for paso in range(1, total + 1):
		var idx = (pos_ant + paso) % 40
		puntos.append(tablero_manager.obtener_posicion_casilla_con_offset(idx, jug.id, jugadores.size()))

	jug.posicion = nueva

	var destino = puntos[puntos.size() - 1]
	cam_target = Vector3(destino.x * 0.35, 0, destino.z * 0.35)

	jug.nodo_ficha.mover_paso_a_paso(puntos, func():
		_al_llegar(jug, pos_ant, nueva, total)
	)

func _al_llegar(jug: JugadorData, pos_ant: int, nueva: int, dados: int) -> void:
	if nueva < pos_ant:
		jug.modificar_dinero(200)
		_notificar("💰 " + jug.nombre + " pasó por SALIDA — +$200")

	var cas = casillas_data[nueva]
	_notificar(jug.nombre + " cayó en: " + cas.nombre.replace("\n", " "))

	if cas is PropiedadCasillaData:
		var prop = cas as PropiedadCasillaData
		if not prop.esta_comprada():
			_mostrar_compra(jug, prop)
			return
		elif prop.propietario_id != jug.id:
			var dueno = jugadores[prop.propietario_id]
			var alq = prop.calcular_alquiler(dados)
			jug.modificar_dinero(-alq)
			dueno.modificar_dinero(alq)
			_notificar("💸 " + jug.nombre + " paga $" + str(alq) + " a " + dueno.nombre)
		elif prop.propietario_id == jug.id and prop.tipo == "calle":
			if jug.puede_pagar(prop.costo_casa) and prop.casas < 5:
				jug.modificar_dinero(-prop.costo_casa)
				prop.agregar_casa()
				cas.nodo_visual.actualizar_casas(prop.casas)
				_notificar("🏠 " + jug.nombre + " construyó en " + prop.nombre.replace("\n", " "))
	elif cas.tipo == "suerte":
		_evento_suerte(jug)
	elif cas.tipo == "arca":
		_evento_arca(jug)
	elif cas.tipo == "impuesto":
		var m = 200 if cas.id == 4 else 100
		jug.modificar_dinero(-m)
		_notificar("🏛 " + jug.nombre + " paga $" + str(m) + " de impuestos")
	elif cas.tipo == "ir_carcel":
		jug.posicion = 10
		jug.en_carcel = true
		jug.nodo_ficha.position = tablero_manager.obtener_posicion_casilla_con_offset(10, jug.id, jugadores.size())
		_notificar("🚨 " + jug.nombre + " fue a la Cárcel!")

	_fin_turno()

func _mostrar_compra(jug: JugadorData, prop: PropiedadCasillaData) -> void:
	compra_info.text = prop.nombre.replace("\n", " ") + "\nPrecio: $" + str(prop.precio) + "   Saldo: $" + str(jug.dinero)
	btn_comprar.disabled = not jug.puede_pagar(prop.precio)
	compra_panel.visible = true

func _on_comprar() -> void:
	compra_panel.visible = false
	var jug = jugadores[turno_actual]
	var cas = casillas_data[jug.posicion]
	if cas is PropiedadCasillaData:
		var prop = cas as PropiedadCasillaData
		if jug.puede_pagar(prop.precio):
			jug.modificar_dinero(-prop.precio)
			prop.propietario_id = jug.id
			jug.agregar_propiedad(prop)
			cas.nodo_visual.actualizar_propietario(jug.color_ficha)
			_notificar("📜 " + jug.nombre + " compró " + prop.nombre.replace("\n", " "))
	_fin_turno()

func _on_pasar() -> void:
	compra_panel.visible = false
	_fin_turno()

func _fin_turno() -> void:
	turno_actual = (turno_actual + 1) % jugadores.size()
	esta_procesando_turno = false
	btn_tirar.disabled = false
	_actualizar_hud()

func _evento_suerte(jug: JugadorData) -> void:
	var evs = [
		{"t": "Lotería — Ganas $150", "m": 150},
		{"t": "Multa de tránsito — Pagas $50", "m": -50},
		{"t": "Reembolso bancario — Ganas $100", "m": 100}
	]
	var e = evs.pick_random()
	jug.modificar_dinero(e["m"])
	_notificar("❓ " + e["t"])

func _evento_arca(jug: JugadorData) -> void:
	var evs = [
		{"t": "Venta de acciones — Ganas $200", "m": 200},
		{"t": "Gastos médicos — Pagas $100", "m": -100},
		{"t": "Regalo — Ganas $50", "m": 50}
	]
	var e = evs.pick_random()
	jug.modificar_dinero(e["m"])
	_notificar("♦ " + e["t"])

# ─────────────────────────────────────────────────────────────────────
#   UI
# ─────────────────────────────────────────────────────────────────────

var pos_esquinas_mesa = [
	Vector3(8.8, 0.4, 8.8),
	Vector3(-8.8, 0.4, 8.8),
	Vector3(-8.8, 0.4, -8.8),
	Vector3(8.8, 0.4, -8.8)
]

func _crear_tags_3d_mesa() -> void:
	for i in range(jugadores.size()):
		var jug = jugadores[i]
		var lbl = Label3D.new()
		lbl.name = "TagMesa_%d" % i
		lbl.position = pos_esquinas_mesa[i % pos_esquinas_mesa.size()]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.pixel_size = 0.007
		lbl.font_size = 32
		lbl.outline_size = 10
		lbl.outline_modulate = Color.BLACK
		lbl.modulate = jug.color_ficha
		add_child(lbl)
		player_tags3d.append(lbl)

func _construir_ui() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)

	# ── Notificación ──
	notif_label = Label.new()
	notif_label.anchor_left = 0.15
	notif_label.anchor_top = 0.0
	notif_label.anchor_right = 0.85
	notif_label.anchor_bottom = 0.0
	notif_label.offset_top = 16
	notif_label.offset_bottom = 44
	notif_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notif_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notif_label.add_theme_font_size_override("font_size", 18)
	notif_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	notif_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	notif_label.add_theme_constant_override("outline_size", 8)
	canvas.add_child(notif_label)

	# ── Dados centro ──
	dados_panel = PanelContainer.new()
	dados_panel.anchor_left = 0.39
	dados_panel.anchor_top = 0.37
	dados_panel.anchor_right = 0.61
	dados_panel.anchor_bottom = 0.55
	dados_panel.visible = false

	var style_dados = StyleBoxFlat.new()
	style_dados.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	style_dados.border_color = Color(0.82, 0.65, 0.18)
	style_dados.set_border_width_all(3)
	style_dados.set_corner_radius_all(16)
	style_dados.set_content_margin_all(16)
	dados_panel.add_theme_stylebox_override("panel", style_dados)
	canvas.add_child(dados_panel)

	var vb_d = VBoxContainer.new()
	vb_d.alignment = BoxContainer.ALIGNMENT_CENTER
	dados_panel.add_child(vb_d)

	var titulo_dados = Label.new()
	titulo_dados.text = "🎲 DADOS"
	titulo_dados.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo_dados.add_theme_font_size_override("font_size", 16)
	titulo_dados.add_theme_color_override("font_color", Color(0.82, 0.65, 0.18))
	vb_d.add_child(titulo_dados)

	var hb_d = HBoxContainer.new()
	hb_d.alignment = BoxContainer.ALIGNMENT_CENTER
	hb_d.add_theme_constant_override("separation", 32)
	vb_d.add_child(hb_d)

	dado1_label = Label.new()
	dado1_label.text = "⚀"
	dado1_label.add_theme_font_size_override("font_size", 48)
	dado1_label.add_theme_color_override("font_color", Color.WHITE)
	hb_d.add_child(dado1_label)

	dado2_label = Label.new()
	dado2_label.text = "⚀"
	dado2_label.add_theme_font_size_override("font_size", 48)
	dado2_label.add_theme_color_override("font_color", Color.WHITE)
	hb_d.add_child(dado2_label)

	dados_msg = Label.new()
	dados_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dados_msg.add_theme_font_size_override("font_size", 17)
	dados_msg.add_theme_color_override("font_color", Color(0.9, 0.88, 0.75))
	vb_d.add_child(dados_msg)

	# ── Botón tirar ──
	btn_tirar = Button.new()
	btn_tirar.text = "🎲  TIRAR DADOS"
	btn_tirar.anchor_left = 0.38
	btn_tirar.anchor_top = 0.87
	btn_tirar.anchor_right = 0.62
	btn_tirar.anchor_bottom = 0.95
	btn_tirar.add_theme_font_size_override("font_size", 19)

	var style_btn = StyleBoxFlat.new()
	style_btn.bg_color = Color(0.82, 0.15, 0.15)
	style_btn.set_corner_radius_all(10)
	style_btn.set_content_margin_all(8)
	btn_tirar.add_theme_stylebox_override("normal", style_btn)
	var style_btn_h = StyleBoxFlat.new()
	style_btn_h.bg_color = Color(0.95, 0.2, 0.2)
	style_btn_h.set_corner_radius_all(10)
	style_btn_h.set_content_margin_all(8)
	btn_tirar.add_theme_stylebox_override("hover", style_btn_h)
	var style_btn_p = StyleBoxFlat.new()
	style_btn_p.bg_color = Color(0.65, 0.1, 0.1)
	style_btn_p.set_corner_radius_all(10)
	style_btn_p.set_content_margin_all(8)
	btn_tirar.add_theme_stylebox_override("pressed", style_btn_p)
	var style_btn_d = StyleBoxFlat.new()
	style_btn_d.bg_color = Color(0.25, 0.25, 0.3)
	style_btn_d.set_corner_radius_all(10)
	style_btn_d.set_content_margin_all(8)
	btn_tirar.add_theme_stylebox_override("disabled", style_btn_d)
	btn_tirar.add_theme_color_override("font_color", Color.WHITE)
	btn_tirar.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.5))
	btn_tirar.pressed.connect(ejecutar_turno)
	canvas.add_child(btn_tirar)

	# ── Panel compra ──
	compra_panel = PanelContainer.new()
	compra_panel.anchor_left = 0.28
	compra_panel.anchor_top = 0.35
	compra_panel.anchor_right = 0.72
	compra_panel.anchor_bottom = 0.62
	compra_panel.visible = false

	var style_compra = StyleBoxFlat.new()
	style_compra.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	style_compra.border_color = Color(0.2, 0.7, 0.3)
	style_compra.set_border_width_all(3)
	style_compra.set_corner_radius_all(14)
	style_compra.set_content_margin_all(20)
	compra_panel.add_theme_stylebox_override("panel", style_compra)
	canvas.add_child(compra_panel)

	var vb_c = VBoxContainer.new()
	vb_c.alignment = BoxContainer.ALIGNMENT_CENTER
	vb_c.add_theme_constant_override("separation", 12)
	compra_panel.add_child(vb_c)

	var titulo_compra = Label.new()
	titulo_compra.text = "¿Comprar propiedad?"
	titulo_compra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo_compra.add_theme_font_size_override("font_size", 18)
	titulo_compra.add_theme_color_override("font_color", Color(0.2, 0.75, 0.35))
	vb_c.add_child(titulo_compra)

	compra_info = Label.new()
	compra_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	compra_info.add_theme_font_size_override("font_size", 16)
	compra_info.add_theme_color_override("font_color", Color.WHITE)
	vb_c.add_child(compra_info)

	var hb_c = HBoxContainer.new()
	hb_c.alignment = BoxContainer.ALIGNMENT_CENTER
	hb_c.add_theme_constant_override("separation", 16)
	vb_c.add_child(hb_c)

	btn_comprar = Button.new()
	btn_comprar.text = "COMPRAR"
	btn_comprar.add_theme_font_size_override("font_size", 15)
	var st_buy = StyleBoxFlat.new()
	st_buy.bg_color = Color(0.15, 0.6, 0.25)
	st_buy.set_corner_radius_all(8)
	st_buy.set_content_margin_all(8)
	btn_comprar.add_theme_stylebox_override("normal", st_buy)
	btn_comprar.add_theme_color_override("font_color", Color.WHITE)
	btn_comprar.pressed.connect(_on_comprar)
	hb_c.add_child(btn_comprar)

	btn_pasar = Button.new()
	btn_pasar.text = "PASAR"
	btn_pasar.add_theme_font_size_override("font_size", 15)
	var st_pass = StyleBoxFlat.new()
	st_pass.bg_color = Color(0.5, 0.15, 0.15)
	st_pass.set_corner_radius_all(8)
	st_pass.set_content_margin_all(8)
	btn_pasar.add_theme_stylebox_override("normal", st_pass)
	btn_pasar.add_theme_color_override("font_color", Color.WHITE)
	btn_pasar.pressed.connect(_on_pasar)
	hb_c.add_child(btn_pasar)

	# ── Modal Detalle Casilla (Tarjeta de Propiedad Auténtica) ──
	detalle_modal = PanelContainer.new()
	detalle_modal.anchor_left = 0.5
	detalle_modal.anchor_top = 0.5
	detalle_modal.anchor_right = 0.5
	detalle_modal.anchor_bottom = 0.5
	detalle_modal.offset_left = -160
	detalle_modal.offset_top = -230
	detalle_modal.offset_right = 160
	detalle_modal.offset_bottom = 230
	detalle_modal.visible = false

	# Fondo tipo papel/cartulina de Monopoly blanco cálido con borde negro exterior
	var style_mod = StyleBoxFlat.new()
	style_mod.bg_color = Color(0.97, 0.96, 0.93)
	style_mod.border_color = Color(0.1, 0.1, 0.1)
	style_mod.set_border_width_all(3)
	style_mod.set_corner_radius_all(12)
	style_mod.set_content_margin_all(10)
	detalle_modal.add_theme_stylebox_override("panel", style_mod)
	canvas.add_child(detalle_modal)

	detalle_vb_contenido = VBoxContainer.new()
	detalle_vb_contenido.add_theme_constant_override("separation", 6)
	detalle_modal.add_child(detalle_vb_contenido)

func _mostrar_modal_detalle_casilla(cas: CasillaData) -> void:
	if not detalle_modal:
		return

	# Limpiar contenido anterior
	for child in detalle_vb_contenido.get_children():
		child.queue_free()

	# ── Cabecera de Color del Grupo (Banda superior auténtica) ──
	var header = PanelContainer.new()
	var style_h = StyleBoxFlat.new()
	var bg_col = cas.color_grupo if cas.color_grupo != Color.WHITE else Color(0.15, 0.2, 0.3)
	style_h.bg_color = bg_col
	style_h.border_color = Color(0.1, 0.1, 0.1)
	style_h.set_border_width_all(2)
	style_h.set_corner_radius_all(6)
	style_h.set_content_margin_all(8)
	header.add_theme_stylebox_override("panel", style_h)
	detalle_vb_contenido.add_child(header)

	var vb_h = VBoxContainer.new()
	vb_h.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(vb_h)

	var is_dark_header = bg_col.get_luminance() < 0.55
	var text_col_h = Color.WHITE if is_dark_header else Color(0.08, 0.08, 0.1)

	var tag_title = Label.new()
	tag_title.text = "TÍTULO DE PROPIEDAD" if cas.es_propiedad() else "TABLERO DE MONOPOLY"
	tag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_title.add_theme_font_size_override("font_size", 10)
	tag_title.add_theme_color_override("font_color", text_col_h)
	vb_h.add_child(tag_title)

	var title_lbl = Label.new()
	title_lbl.text = cas.nombre.replace("\n", " ").to_upper()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", text_col_h)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb_h.add_child(title_lbl)

	# ── Cuerpo de la Tarjeta con diseño oficial ──
	if cas is PropiedadCasillaData:
		var prop = cas as PropiedadCasillaData

		var lbl_alq = Label.new()
		lbl_alq.text = "ALQUILER  $%d" % prop.alquiler_base
		lbl_alq.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_alq.add_theme_font_size_override("font_size", 14)
		lbl_alq.add_theme_color_override("font_color", Color(0.12, 0.12, 0.14))
		detalle_vb_contenido.add_child(lbl_alq)

		# Tabla de casas estilo clásico Monopoly
		if prop.tipo == "calle" and prop.alquileres_casas.size() >= 5:
			_agregar_fila_tarjeta("Con 1 Casa", "$ %d" % prop.alquileres_casas[0])
			_agregar_fila_tarjeta("Con 2 Casas", "$ %d" % prop.alquileres_casas[1])
			_agregar_fila_tarjeta("Con 3 Casas", "$ %d" % prop.alquileres_casas[2])
			_agregar_fila_tarjeta("Con 4 Casas", "$ %d" % prop.alquileres_casas[3])
			_agregar_fila_tarjeta("Con HOTEL", "$ %d" % prop.alquileres_casas[4])

			var sep1 = HSeparator.new()
			detalle_vb_contenido.add_child(sep1)

			var lbl_costo_casa = Label.new()
			lbl_costo_casa.text = "Casas cuestan $%d c/u" % prop.costo_casa
			lbl_costo_casa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl_costo_casa.add_theme_font_size_override("font_size", 11)
			lbl_costo_casa.add_theme_color_override("font_color", Color(0.25, 0.25, 0.3))
			detalle_vb_contenido.add_child(lbl_costo_casa)

			var lbl_costo_hotel = Label.new()
			lbl_costo_hotel.text = "Hoteles, $%d más 4 casas" % prop.costo_casa
			lbl_costo_hotel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl_costo_hotel.add_theme_font_size_override("font_size", 11)
			lbl_costo_hotel.add_theme_color_override("font_color", Color(0.25, 0.25, 0.3))
			detalle_vb_contenido.add_child(lbl_costo_hotel)

		var sep2 = HSeparator.new()
		detalle_vb_contenido.add_child(sep2)

		# Estado de propiedad y dueño
		var estado_txt = "🟢 Disponible por $%d" % prop.precio
		var col_estado = Color(0.1, 0.5, 0.2)

		if prop.esta_comprada():
			var owner = jugadores[prop.propietario_id]
			estado_txt = "👤 Dueño: " + owner.nombre
			col_estado = owner.color_ficha

		var lbl_estado = Label.new()
		lbl_estado.text = estado_txt
		lbl_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_estado.add_theme_font_size_override("font_size", 12)
		lbl_estado.add_theme_color_override("font_color", col_estado)
		detalle_vb_contenido.add_child(lbl_estado)

	else:
		# Casillas Especiales
		var icons = {
			"salida": "🏁", "suerte": "❓", "arca": "♦",
			"impuesto": "🏛", "carcel": "🚨", "parking": "🚗", "ir_carcel": "🚔"
		}
		var icon_lbl = Label.new()
		icon_lbl.text = icons.get(cas.tipo, "🎲")
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 42)
		detalle_vb_contenido.add_child(icon_lbl)

		var desc_lbl = Label.new()
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.18, 0.2, 0.25))

		var descs = {
			"salida": "🏁 ¡Punto de partida!\nRecibe $200 cada vez que pases o caigas en esta casilla.",
			"suerte": "❓ Casilla de Suerte\nToma una tarjeta de la suerte con sorpresas, premios o multas.",
			"arca": "♦ Arca Comunal\nToma una tarjeta del tesoro comunal.",
			"impuesto": "🏛 Impuestos del Estado\nDebes pagar el monto correspondiente al Banco.",
			"carcel": "🚨 Cárcel / De Visita\nSi estás de visita no hay penalización. Si caíste detenido deberás pagar para salir.",
			"parking": "🚗 Parada Libre\nDescanso libre sin costos ni efectos.",
			"ir_carcel": "🚔 ¡Ir a la Cárcel!\nTu ficha es enviada directamente a la Cárcel sin cobrar los $200 de Salida."
		}
		desc_lbl.text = descs.get(cas.tipo, "Casilla especial del tablero de Monopoly.")
		detalle_vb_contenido.add_child(desc_lbl)

	# ── Botón Cerrar Estilizado ──
	var btn_cerrar = Button.new()
	btn_cerrar.text = "✖  CERRAR"
	btn_cerrar.add_theme_font_size_override("font_size", 13)
	var st_c = StyleBoxFlat.new()
	st_c.bg_color = Color(0.18, 0.2, 0.26)
	st_c.set_corner_radius_all(8)
	st_c.set_content_margin_all(8)
	btn_cerrar.add_theme_stylebox_override("normal", st_c)
	btn_cerrar.add_theme_color_override("font_color", Color.WHITE)
	btn_cerrar.pressed.connect(func():
		_ocultar_modal_detalle()
	)
	detalle_vb_contenido.add_child(btn_cerrar)

	# ── Animación desplegable suave ──
	detalle_modal.pivot_offset = Vector2(160, 230)
	detalle_modal.scale = Vector2(0.6, 0.6)
	detalle_modal.modulate.a = 0.0
	detalle_modal.visible = true

	var tw = create_tween().set_parallel(true)
	tw.tween_property(detalle_modal, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(detalle_modal, "modulate:a", 1.0, 0.18)

	# Mover cámara suavemente hacia la casilla seleccionada
	if cas.nodo_visual:
		var target_pos = cas.nodo_visual.global_position
		cam_target = Vector3(target_pos.x * 0.35, 0.0, target_pos.z * 0.35)

func _agregar_fila_tarjeta(concepto: String, valor: String) -> void:
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN

	var l1 = Label.new()
	l1.text = concepto
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l1.add_theme_font_size_override("font_size", 11)
	l1.add_theme_color_override("font_color", Color(0.2, 0.2, 0.24))
	hb.add_child(l1)

	var l2 = Label.new()
	l2.text = valor
	l2.add_theme_font_size_override("font_size", 11)
	l2.add_theme_color_override("font_color", Color(0.1, 0.1, 0.12))
	hb.add_child(l2)

	detalle_vb_contenido.add_child(hb)

func _ocultar_modal_detalle() -> void:
	if not detalle_modal or not detalle_modal.visible:
		return
	var tw = create_tween().set_parallel(true)
	tw.tween_property(detalle_modal, "scale", Vector2(0.6, 0.6), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(detalle_modal, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func():
		detalle_modal.visible = false
	)

func _crear_tarjeta_jugador(jug: JugadorData) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 40)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(jug.color_ficha.r, jug.color_ficha.g, jug.color_ficha.b, 0.2)
	style.border_color = jug.color_ficha
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	lbl.name = "Info"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(lbl)

	return panel

func _actualizar_hud() -> void:
	for i in range(jugadores.size()):
		var jug = jugadores[i]
		var es_turno = (i == turno_actual)
		if i < player_tags3d.size():
			var tag = player_tags3d[i]
			var marker = "🎯 " if es_turno else ""
			tag.text = "%s%s\n💰 $%d" % [marker, jug.nombre, jug.dinero]
			if es_turno:
				tag.font_size = 40
				tag.modulate = Color(1.0, 0.88, 0.3)
				tag.outline_size = 12
			else:
				tag.font_size = 30
				tag.modulate = jug.color_ficha
				tag.outline_size = 8

func _notificar(msg: String) -> void:
	if notif_label:
		notif_label.text = msg
