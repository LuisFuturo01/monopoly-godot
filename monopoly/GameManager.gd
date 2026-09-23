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

# Botón principal
var btn_tirar: Button

# Player card labels
var player_cards: Array = []

func _ready() -> void:
	randomize()
	_setup_camara()

	tablero_manager = TableroManager.new()
	tablero_manager.name = "TableroManager"
	add_child(tablero_manager)
	casillas_data = tablero_manager.construir_tablero()

	_inicializar_jugadores(2)
	_construir_ui()
	_actualizar_hud()
	_notificar("Bienvenido a Monopoly 3D — Rotar cámara: Clic derecho | Zoom: Rueda | Q/E: Girar")

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

	elif event is InputEventMouseMotion and is_orbiting:
		var sens = 0.005
		cam_yaw -= event.relative.x * sens
		cam_pitch = clamp(cam_pitch - event.relative.y * sens, -deg_to_rad(85.0), -deg_to_rad(12.0))

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

func _construir_ui() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)

	# ── Tarjetas de jugador (superior) ──
	hud_top = HBoxContainer.new()
	hud_top.anchor_left = 0.0
	hud_top.anchor_top = 0.0
	hud_top.anchor_right = 1.0
	hud_top.anchor_bottom = 0.0
	hud_top.offset_top = 12
	hud_top.offset_bottom = 58
	hud_top.offset_left = 12
	hud_top.offset_right = -12
	hud_top.alignment = BoxContainer.ALIGNMENT_CENTER
	hud_top.add_theme_constant_override("separation", 20)
	canvas.add_child(hud_top)

	for jug in jugadores:
		var card = _crear_tarjeta_jugador(jug)
		hud_top.add_child(card)
		player_cards.append(card)

	# ── Notificación ──
	notif_label = Label.new()
	notif_label.anchor_left = 0.15
	notif_label.anchor_top = 0.0
	notif_label.anchor_right = 0.85
	notif_label.anchor_bottom = 0.0
	notif_label.offset_top = 62
	notif_label.offset_bottom = 88
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

	# ── Panel Controles de Cámara (inferior-izq) ──
	var cam_panel = PanelContainer.new()
	cam_panel.anchor_left = 0.02
	cam_panel.anchor_top = 0.86
	cam_panel.anchor_right = 0.24
	cam_panel.anchor_bottom = 0.98
	
	var style_cam = StyleBoxFlat.new()
	style_cam.bg_color = Color(0.04, 0.06, 0.1, 0.85)
	style_cam.border_color = Color(0.3, 0.45, 0.65)
	style_cam.set_border_width_all(2)
	style_cam.set_corner_radius_all(10)
	style_cam.set_content_margin_all(8)
	cam_panel.add_theme_stylebox_override("panel", style_cam)
	canvas.add_child(cam_panel)

	var vb_cam = VBoxContainer.new()
	vb_cam.add_theme_constant_override("separation", 4)
	cam_panel.add_child(vb_cam)

	var lbl_cam = Label.new()
	lbl_cam.text = "🎥 CÁMARA 3D"
	lbl_cam.add_theme_font_size_override("font_size", 13)
	lbl_cam.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	vb_cam.add_child(lbl_cam)

	var hb_cam_btns = HBoxContainer.new()
	hb_cam_btns.add_theme_constant_override("separation", 8)
	vb_cam.add_child(hb_cam_btns)

	btn_modo_cine = Button.new()
	btn_modo_cine.text = "🎬 Órbita Cine"
	btn_modo_cine.add_theme_font_size_override("font_size", 12)
	btn_modo_cine.pressed.connect(func():
		modo_cine = not modo_cine
		btn_modo_cine.text = "🎬 Órbita: ON" if modo_cine else "🎬 Órbita Cine"
	)
	hb_cam_btns.add_child(btn_modo_cine)

	btn_reset_cam = Button.new()
	btn_reset_cam.text = "🏠 Vista Frontal"
	btn_reset_cam.add_theme_font_size_override("font_size", 12)
	btn_reset_cam.pressed.connect(func():
		cam_yaw = 0.0
		cam_pitch = -deg_to_rad(52.0)
		cam_distance = 14.5
		cam_target = Vector3.ZERO
		modo_cine = false
		if btn_modo_cine:
			btn_modo_cine.text = "🎬 Órbita Cine"
	)
	hb_cam_btns.add_child(btn_reset_cam)

	var hint_cam = Label.new()
	hint_cam.text = "🖱 Clic Der · Q/E · Rueda: Zoom"
	hint_cam.add_theme_font_size_override("font_size", 11)
	hint_cam.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	vb_cam.add_child(hint_cam)

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
		var casilla_nom = casillas_data[jug.posicion].nombre.replace("\n", " ")
		var info_lbl = player_cards[i].get_node("Info") as Label
		var marker = "  🎯" if es_turno else ""
		info_lbl.text = "%s   $%d   %s%s" % [jug.nombre, jug.dinero, casilla_nom, marker]

		var style = player_cards[i].get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if es_turno:
			style.bg_color = Color(jug.color_ficha.r, jug.color_ficha.g, jug.color_ficha.b, 0.45)
			style.border_color = Color(1.0, 0.85, 0.25)
			style.set_border_width_all(4)
		else:
			style.bg_color = Color(jug.color_ficha.r, jug.color_ficha.g, jug.color_ficha.b, 0.15)
			style.border_color = jug.color_ficha
			style.set_border_width_all(1)
		player_cards[i].add_theme_stylebox_override("panel", style)

func _notificar(msg: String) -> void:
	if notif_label:
		notif_label.text = msg
