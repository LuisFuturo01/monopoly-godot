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

# Modal interactivo de carta 3D
var carta_overlay_bg: Button
var carta_header_panel: PanelContainer
var carta_header_label: Label
var btn_cerrar_carta: Button
var mostrando_carta_modal: bool = false
var _carta_mesh_activa: MeshInstance3D
var _carta_orig_pos: Vector3
var _carta_orig_rot: Vector3
var _carta_orig_scale: Vector3

# Botones principales
var btn_tirar: Button
var btn_construir: Button

# Modal de construcción de casas/hoteles
var construir_modal: PanelContainer
var construir_vb_contenido: VBoxContainer


# Player 3D tags en la mesa
var player_tags3d: Array[Label3D] = []

# Base de datos de cartas JSON
var cartas_db: Dictionary = {}

func _ready() -> void:
	randomize()
	_cargar_cartas_json()
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

func _cargar_cartas_json() -> void:
	var rutas = [
		"res://cartas_monopoly.json",
		"d:/xampp/htdocs/PersonalProjects/monopoly/monopoly/cartas_monopoly.json"
	]
	for r in rutas:
		if FileAccess.file_exists(r):
			var file = FileAccess.open(r, FileAccess.READ)
			if file:
				var json_text = file.get_as_text()
				var json = JSON.new()
				if json.parse(json_text) == OK and json.data is Dictionary:
					cartas_db = json.data
					return

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

			# FASE 3: Los dados 3D crecen y se deslicen hacia la pantalla (frente a la cámara)
			tw_throw.chain().tween_callback(func():
				var cam_tf = camara.global_transform
				var cam_pos = cam_tf.origin
				var forward = -cam_tf.basis.z
				var right = cam_tf.basis.x
				var up = cam_tf.basis.y

				# Posicionar los dados 3D flotando a 2.4m frente a la cámara
				var center_screen = cam_pos + forward * 2.4 + up * 0.1
				var pos_dado1_cam = center_screen - right * 0.52
				var pos_dado2_cam = center_screen + right * 0.52

				# Inclinación ligera hacia el espectador para destacar la cara superior con el número
				var rot_cam1 = rot_final1 + Vector3(deg_to_rad(22), 0, 0)
				var rot_cam2 = rot_final2 + Vector3(deg_to_rad(22), 0, 0)

				var tw_slide = create_tween().set_parallel(true)
				tw_slide.tween_property(dado1_3d, "global_position", pos_dado1_cam, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw_slide.tween_property(dado2_3d, "global_position", pos_dado2_cam, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

				# Crecimiento de los dados 3D hacia la pantalla
				tw_slide.tween_property(dado1_3d, "scale", Vector3(1.75, 1.75, 1.75), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw_slide.tween_property(dado2_3d, "scale", Vector3(1.75, 1.75, 1.75), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

				# Orientación ajustada para lectura perfecta
				tw_slide.tween_property(dado1_3d, "rotation", rot_cam1, 0.45)
				tw_slide.tween_property(dado2_3d, "rotation", rot_cam2, 0.45)

				# Desplegar el modal como marco informativo debajo de los dados 3D reales
				dados_msg.text = "%s — Sacó %d + %d  ➜  ¡Avanza %d casillas!" % [jug.nombre, d1, d2, total]
				dados_panel.visible = true
				dados_panel.pivot_offset = dados_panel.size * 0.5
				dados_panel.scale = Vector2(0.8, 0.8)
				dados_panel.modulate.a = 0.0

				var tw_panel = create_tween().set_parallel(true)
				tw_panel.tween_property(dados_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw_panel.tween_property(dados_panel, "modulate:a", 1.0, 0.25)

				var tw_wait = create_tween()
				tw_wait.tween_interval(1.2)
				tw_wait.tween_callback(func():
					# Encoger dados 3D y desvanecer modal antes de avanzar la ficha
					var tw_out = create_tween().set_parallel(true)
					tw_out.tween_property(dado1_3d, "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					tw_out.tween_property(dado2_3d, "scale", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					tw_out.tween_property(dados_panel, "modulate:a", 0.0, 0.25)

					tw_out.chain().tween_callback(func():
						dados_panel.visible = false
						dado1_3d.visible = false
						dado2_3d.visible = false
						if callback.is_valid():
							callback.call()
					)
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
				_crear_efecto_particulas_compra(cas.nodo_visual.global_position)
				_notificar("🏠 " + jug.nombre + " construyó en " + prop.nombre.replace("\n", " "))
	elif cas.tipo == "suerte":
		_animar_carta_3d(tablero_manager.mazo_suerte_top, jug, "suerte")
		return
	elif cas.tipo == "arca":
		_animar_carta_3d(tablero_manager.mazo_arca_top, jug, "arca")
		return
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
			_crear_efecto_particulas_compra(cas.nodo_visual.global_position)
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

var _es_carta_temp: bool = false

func _crear_carta_3d_dinamica(tipo: String) -> MeshInstance3D:
	var card_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(2.30, 0.03, 1.50)
	card_mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.38, 0.72) if tipo == "arca" else Color(0.88, 0.5, 0.08)
	mat.roughness = 0.95
	card_mesh.material_override = mat
	add_child(card_mesh)
	card_mesh.global_position = Vector3(-3.8 if tipo == "arca" else 3.8, 0.15, 3.0)
	card_mesh.global_rotation = Vector3.ZERO
	return card_mesh

func _animar_carta_3d(top_mesh: MeshInstance3D, jug: JugadorData, tipo: String) -> void:
	# Obtener datos de la carta desde JSON
	var lista_cartas = cartas_db.get(tipo, [])
	var carta_data: Dictionary = {}
	if not lista_cartas.is_empty():
		carta_data = lista_cartas.pick_random()
	else:
		carta_data = {"texto": "¡Evento especial!\nGanas $100.", "monto": 100, "tipo_accion": "dinero"}

	if not top_mesh:
		top_mesh = _crear_carta_3d_dinamica(tipo)
		_es_carta_temp = true
	else:
		_es_carta_temp = false

	# Ocultar el título impreso del mazo en la tarjeta para que no tape el contenido
	var lbl_deck = top_mesh.get_node_or_null("LabelTituloMazo")
	if lbl_deck:
		lbl_deck.visible = false

	# Label3D impreso directamente sobre la cara de la carta 3D
	var lbl_txt: Label3D = top_mesh.get_node_or_null("LabelTextoCarta")
	if not lbl_txt:
		lbl_txt = Label3D.new()
		lbl_txt.name = "LabelTextoCarta"
		lbl_txt.position = Vector3(0, 0.022, 0)
		lbl_txt.rotation = Vector3(-PI / 2, 0, 0)
		lbl_txt.font_size = 28
		lbl_txt.pixel_size = 0.0045
		lbl_txt.width = 2.2 / 0.0045 * 0.85
		lbl_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl_txt.modulate = Color(0.08, 0.08, 0.08) # Tinta oscura de tarjeta
		lbl_txt.outline_modulate = Color(1.0, 1.0, 0.95)
		lbl_txt.outline_size = 6
		lbl_txt.no_depth_test = false
		lbl_txt.render_priority = 4
		top_mesh.add_child(lbl_txt)

	lbl_txt.text = carta_data["texto"]
	lbl_txt.visible = true

	# Eliminar brillos y reflejos deslumbrantes para una lectura cómoda mate en pantalla
	if top_mesh.material_override and top_mesh.material_override is StandardMaterial3D:
		var mat_read = top_mesh.material_override.duplicate() as StandardMaterial3D
		mat_read.emission_enabled = false
		mat_read.roughness = 0.95
		mat_read.metallic = 0.0
		top_mesh.material_override = mat_read

	_carta_mesh_activa = top_mesh
	_carta_orig_pos = top_mesh.global_position
	_carta_orig_rot = top_mesh.global_rotation
	_carta_orig_scale = top_mesh.scale

	# FASE 1: Ojeado / Extracción lateral del mazo 3D
	var tw_pull = create_tween().set_parallel(true)
	tw_pull.tween_property(top_mesh, "global_position:y", _carta_orig_pos.y + 0.35, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_pull.tween_property(top_mesh, "global_position:x", _carta_orig_pos.x + (0.35 if tipo == "suerte" else -0.35), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw_pull.chain().tween_callback(func():
		# FASE 2: Deslizamiento hacia la pantalla alineándose sin inclinación (plano 3D a 2D)
		var cam_tf = camara.global_transform
		var cam_pos = cam_tf.origin
		var forward = -cam_tf.basis.z

		# Posición plana frente a la cámara (a 2.0m de distancia)
		var pos_card_cam = cam_pos + forward * 2.0

		# Orientación alineada plana al plano de la cámara (sin inclinación para lectura perfecta)
		var rot_card_flat = cam_tf.basis.get_euler() + Vector3(PI / 2, 0, 0)

		var tw_slide = create_tween().set_parallel(true)
		tw_slide.tween_property(top_mesh, "global_position", pos_card_cam, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw_slide.tween_property(top_mesh, "scale", Vector3(2.1, 2.1, 2.1), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw_slide.tween_property(top_mesh, "global_rotation", rot_card_flat, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

		tw_slide.chain().tween_callback(func():
			# FASE 3: Aplicar el efecto de la carta y desplegar Header superior + Botón de Cierre "✖"
			_ejecutar_evento_carta(jug, tipo, carta_data)

			var titulo_hdr = "❓ CASUALIDAD" if tipo == "suerte" else "♦ ARCA COMUNAL"
			var col_hdr = Color(1.0, 0.65, 0.15) if tipo == "suerte" else Color(0.25, 0.65, 1.0)
			carta_header_label.text = titulo_hdr
			carta_header_label.add_theme_color_override("font_color", col_hdr)

			carta_overlay_bg.visible = true
			carta_header_panel.visible = true
			btn_cerrar_carta.visible = true
			mostrando_carta_modal = true
		)
	)

func _on_cerrar_carta_clicked() -> void:
	if not mostrando_carta_modal or not _carta_mesh_activa:
		return
	mostrando_carta_modal = false

	carta_overlay_bg.visible = false
	carta_header_panel.visible = false
	btn_cerrar_carta.visible = false

	var lbl_txt: Label3D = _carta_mesh_activa.get_node_or_null("LabelTextoCarta")
	if lbl_txt:
		lbl_txt.visible = false

	# Restaurar material de brillo original para el mazo en el tablero
	if _carta_mesh_activa.material_override and _carta_mesh_activa.material_override is StandardMaterial3D:
		_carta_mesh_activa.material_override.roughness = 0.25
		_carta_mesh_activa.material_override.emission_enabled = true

	# FASE 4: Regresar la carta al mazo 3D
	var tw_return = create_tween().set_parallel(true)
	tw_return.tween_property(_carta_mesh_activa, "global_position", _carta_orig_pos, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw_return.tween_property(_carta_mesh_activa, "scale", _carta_orig_scale, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw_return.tween_property(_carta_mesh_activa, "global_rotation", _carta_orig_rot, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	tw_return.chain().tween_callback(func():
		var lbl_deck = _carta_mesh_activa.get_node_or_null("LabelTituloMazo")
		if lbl_deck:
			lbl_deck.visible = true
		if _es_carta_temp and is_instance_valid(_carta_mesh_activa):
			_carta_mesh_activa.queue_free()
		_fin_turno()
	)

func _ejecutar_evento_carta(jug: JugadorData, tipo: String, carta_data: Dictionary) -> void:
	if not carta_data or carta_data.is_empty():
		return
	var monto = carta_data.get("monto", 0)
	var accion = carta_data.get("tipo_accion", "dinero")

	if monto != 0:
		jug.modificar_dinero(monto)

	if accion == "salida":
		jug.posicion = 0
		jug.nodo_ficha.position = tablero_manager.obtener_posicion_casilla_con_offset(0, jug.id, jugadores.size())
		jug.modificar_dinero(200)
	elif accion == "carcel":
		jug.posicion = 10
		jug.en_carcel = true
		jug.nodo_ficha.position = tablero_manager.obtener_posicion_casilla_con_offset(10, jug.id, jugadores.size())

	var nom_tipo = "Casualidad" if tipo == "suerte" else "Arca Comunal"
	_notificar("🃏 " + jug.nombre + " robó carta de " + nom_tipo)

func _crear_efecto_particulas_compra(pos: Vector3) -> void:
	var particle = GPUParticles3D.new()
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.4
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -2.5, 0)
	mat.color = Color(1.0, 0.85, 0.2)
	mat.scale_min = 0.08
	mat.scale_max = 0.18

	particle.process_material = mat
	particle.amount = 24
	particle.lifetime = 0.8
	particle.one_shot = true
	particle.position = pos + Vector3(0, 0.4, 0)

	var p_mesh = QuadMesh.new()
	p_mesh.size = Vector2(0.12, 0.12)
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color(1.0, 0.88, 0.3)
	p_mat.emission_enabled = true
	p_mat.emission = Color(1.0, 0.88, 0.3)
	p_mat.emission_energy_multiplier = 2.0
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p_mesh.material = p_mat

	particle.draw_pass_1 = p_mesh
	add_child(particle)
	particle.restart()

	var tw = create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(func(): particle.queue_free())



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

	# ── Modal Interactivo de Carta 3D (Overlay + Header + Botón de Cierre "✖") ──
	carta_overlay_bg = Button.new()
	carta_overlay_bg.anchor_left = 0.0
	carta_overlay_bg.anchor_top = 0.0
	carta_overlay_bg.anchor_right = 1.0
	carta_overlay_bg.anchor_bottom = 1.0
	carta_overlay_bg.flat = true
	var style_overlay = StyleBoxFlat.new()
	style_overlay.bg_color = Color(0, 0, 0, 0.45)
	carta_overlay_bg.add_theme_stylebox_override("normal", style_overlay)
	carta_overlay_bg.add_theme_stylebox_override("hover", style_overlay)
	carta_overlay_bg.add_theme_stylebox_override("pressed", style_overlay)
	carta_overlay_bg.visible = false
	carta_overlay_bg.pressed.connect(_on_cerrar_carta_clicked)
	canvas.add_child(carta_overlay_bg)

	carta_header_panel = PanelContainer.new()
	carta_header_panel.anchor_left = 0.32
	carta_header_panel.anchor_top = 0.10
	carta_header_panel.anchor_right = 0.68
	carta_header_panel.anchor_bottom = 0.17
	carta_header_panel.visible = false
	var style_hdr = StyleBoxFlat.new()
	style_hdr.bg_color = Color(0.06, 0.09, 0.16, 0.94)
	style_hdr.border_color = Color(0.85, 0.72, 0.25, 0.85)
	style_hdr.set_border_width_all(2)
	style_hdr.set_corner_radius_all(14)
	style_hdr.set_content_margin_all(8)
	style_hdr.shadow_color = Color(0, 0, 0, 0.6)
	style_hdr.shadow_size = 10
	carta_header_panel.add_theme_stylebox_override("panel", style_hdr)
	canvas.add_child(carta_header_panel)

	carta_header_label = Label.new()
	carta_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	carta_header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	carta_header_label.add_theme_font_size_override("font_size", 20)
	carta_header_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	carta_header_label.add_theme_color_override("font_outline_color", Color.BLACK)
	carta_header_label.add_theme_constant_override("outline_size", 4)
	carta_header_panel.add_child(carta_header_label)

	btn_cerrar_carta = Button.new()
	btn_cerrar_carta.text = "✖"
	btn_cerrar_carta.anchor_left = 0.71
	btn_cerrar_carta.anchor_top = 0.14
	btn_cerrar_carta.anchor_right = 0.75
	btn_cerrar_carta.anchor_bottom = 0.20
	btn_cerrar_carta.add_theme_font_size_override("font_size", 20)
	btn_cerrar_carta.visible = false

	var style_close = StyleBoxFlat.new()
	style_close.bg_color = Color(0.85, 0.18, 0.18, 0.95)
	style_close.border_color = Color(1.0, 0.88, 0.3)
	style_close.set_border_width_all(2)
	style_close.set_corner_radius_all(20)
	style_close.shadow_color = Color(0, 0, 0, 0.6)
	style_close.shadow_size = 8
	btn_cerrar_carta.add_theme_stylebox_override("normal", style_close)

	var style_close_h = StyleBoxFlat.new()
	style_close_h.bg_color = Color(0.98, 0.25, 0.25, 1.0)
	style_close_h.border_color = Color(1.0, 0.95, 0.5)
	style_close_h.set_border_width_all(2)
	style_close_h.set_corner_radius_all(20)
	btn_cerrar_carta.add_theme_stylebox_override("hover", style_close_h)

	btn_cerrar_carta.pressed.connect(_on_cerrar_carta_clicked)
	canvas.add_child(btn_cerrar_carta)

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

	# ── Dados centro (Glassmorphism Modal de marco 3D) ──
	dados_panel = PanelContainer.new()
	dados_panel.anchor_left = 0.25
	dados_panel.anchor_top = 0.65
	dados_panel.anchor_right = 0.75
	dados_panel.anchor_bottom = 0.78
	dados_panel.visible = false

	var style_dados = StyleBoxFlat.new()
	style_dados.bg_color = Color(0.06, 0.09, 0.16, 0.88)
	style_dados.border_color = Color(0.85, 0.72, 0.25, 0.85)
	style_dados.set_border_width_all(2)
	style_dados.set_corner_radius_all(18)
	style_dados.set_content_margin_all(14)
	style_dados.shadow_color = Color(0, 0, 0, 0.6)
	style_dados.shadow_size = 18
	style_dados.shadow_offset = Vector2(0, 6)
	dados_panel.add_theme_stylebox_override("panel", style_dados)
	canvas.add_child(dados_panel)

	var vb_d = VBoxContainer.new()
	vb_d.alignment = BoxContainer.ALIGNMENT_CENTER
	dados_panel.add_child(vb_d)

	var titulo_dados = Label.new()
	titulo_dados.text = "🎲 RESULTADO DEL LANZAMIENTO"
	titulo_dados.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo_dados.add_theme_font_size_override("font_size", 14)
	titulo_dados.add_theme_color_override("font_color", Color(0.95, 0.82, 0.3))
	vb_d.add_child(titulo_dados)

	dados_msg = Label.new()
	dados_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dados_msg.add_theme_font_size_override("font_size", 18)
	dados_msg.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	dados_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	dados_msg.add_theme_constant_override("outline_size", 4)
	vb_d.add_child(dados_msg)

	# ── Botón Tirar Dados ──
	btn_tirar = Button.new()
	btn_tirar.text = "🎲  TIRAR DADOS"
	btn_tirar.anchor_left = 0.22
	btn_tirar.anchor_top = 0.86
	btn_tirar.anchor_right = 0.48
	btn_tirar.anchor_bottom = 0.95
	btn_tirar.add_theme_font_size_override("font_size", 18)

	var style_btn = StyleBoxFlat.new()
	style_btn.bg_color = Color(0.85, 0.15, 0.18)
	style_btn.border_color = Color(1.0, 0.84, 0.3)
	style_btn.set_border_width_all(2)
	style_btn.set_corner_radius_all(14)
	style_btn.set_content_margin_all(8)
	style_btn.shadow_color = Color(0.5, 0.05, 0.05, 0.6)
	style_btn.shadow_size = 10
	style_btn.shadow_offset = Vector2(0, 4)
	btn_tirar.add_theme_stylebox_override("normal", style_btn)

	var style_btn_h = StyleBoxFlat.new()
	style_btn_h.bg_color = Color(0.98, 0.22, 0.25)
	style_btn_h.border_color = Color(1.0, 0.92, 0.5)
	style_btn_h.set_border_width_all(2)
	style_btn_h.set_corner_radius_all(14)
	style_btn_h.set_content_margin_all(8)
	style_btn_h.shadow_color = Color(0.7, 0.1, 0.1, 0.7)
	style_btn_h.shadow_size = 14
	style_btn_h.shadow_offset = Vector2(0, 5)
	btn_tirar.add_theme_stylebox_override("hover", style_btn_h)

	var style_btn_p = StyleBoxFlat.new()
	style_btn_p.bg_color = Color(0.6, 0.08, 0.1)
	style_btn_p.border_color = Color(0.8, 0.65, 0.2)
	style_btn_p.set_border_width_all(2)
	style_btn_p.set_corner_radius_all(14)
	style_btn_p.set_content_margin_all(8)
	style_btn_p.shadow_size = 2
	style_btn_p.shadow_offset = Vector2(0, 1)
	btn_tirar.add_theme_stylebox_override("pressed", style_btn_p)

	var style_btn_d = StyleBoxFlat.new()
	style_btn_d.bg_color = Color(0.2, 0.22, 0.28, 0.8)
	style_btn_d.border_color = Color(0.35, 0.38, 0.45, 0.5)
	style_btn_d.set_border_width_all(1)
	style_btn_d.set_corner_radius_all(14)
	style_btn_d.set_content_margin_all(8)
	btn_tirar.add_theme_stylebox_override("disabled", style_btn_d)
	btn_tirar.add_theme_color_override("font_color", Color.WHITE)
	btn_tirar.add_theme_color_override("font_disabled_color", Color(0.5, 0.52, 0.58))
	btn_tirar.pressed.connect(ejecutar_turno)
	canvas.add_child(btn_tirar)

	# ── Botón Construir Casas / Hoteles ──
	btn_construir = Button.new()
	btn_construir.text = "🏠  CONSTRUIR"
	btn_construir.anchor_left = 0.52
	btn_construir.anchor_top = 0.86
	btn_construir.anchor_right = 0.78
	btn_construir.anchor_bottom = 0.95
	btn_construir.add_theme_font_size_override("font_size", 18)

	var style_cbtn = StyleBoxFlat.new()
	style_cbtn.bg_color = Color(0.15, 0.58, 0.28)
	style_cbtn.border_color = Color(0.4, 0.9, 0.55)
	style_cbtn.set_border_width_all(2)
	style_cbtn.set_corner_radius_all(14)
	style_cbtn.set_content_margin_all(8)
	style_cbtn.shadow_color = Color(0.05, 0.3, 0.1, 0.6)
	style_cbtn.shadow_size = 10
	style_cbtn.shadow_offset = Vector2(0, 4)
	btn_construir.add_theme_stylebox_override("normal", style_cbtn)

	var style_cbtn_h = StyleBoxFlat.new()
	style_cbtn_h.bg_color = Color(0.2, 0.72, 0.35)
	style_cbtn_h.border_color = Color(0.6, 1.0, 0.7)
	style_cbtn_h.set_border_width_all(2)
	style_cbtn_h.set_corner_radius_all(14)
	style_cbtn_h.set_content_margin_all(8)
	btn_construir.add_theme_stylebox_override("hover", style_cbtn_h)

	btn_construir.add_theme_color_override("font_color", Color.WHITE)
	btn_construir.pressed.connect(_abrir_modal_construccion)
	canvas.add_child(btn_construir)

	# ── Modal de Construcción de Casas/Hoteles ──
	construir_modal = PanelContainer.new()
	construir_modal.anchor_left = 0.5
	construir_modal.anchor_top = 0.5
	construir_modal.anchor_right = 0.5
	construir_modal.anchor_bottom = 0.5
	construir_modal.offset_left = -230
	construir_modal.offset_top = -220
	construir_modal.offset_right = 230
	construir_modal.offset_bottom = 220
	construir_modal.visible = false

	var style_cmod = StyleBoxFlat.new()
	style_cmod.bg_color = Color(0.06, 0.09, 0.16, 0.96)
	style_cmod.border_color = Color(0.25, 0.85, 0.45, 0.85)
	style_cmod.set_border_width_all(2)
	style_cmod.set_corner_radius_all(16)
	style_cmod.set_content_margin_all(16)
	style_cmod.shadow_color = Color(0, 0, 0, 0.6)
	style_cmod.shadow_size = 18
	construir_modal.add_theme_stylebox_override("panel", style_cmod)
	canvas.add_child(construir_modal)

	construir_vb_contenido = VBoxContainer.new()
	construir_vb_contenido.add_theme_constant_override("separation", 10)
	construir_modal.add_child(construir_vb_contenido)


	# ── Panel compra (Glassmorphism) ──
	compra_panel = PanelContainer.new()
	compra_panel.anchor_left = 0.28
	compra_panel.anchor_top = 0.35
	compra_panel.anchor_right = 0.72
	compra_panel.anchor_bottom = 0.62
	compra_panel.visible = false

	var style_compra = StyleBoxFlat.new()
	style_compra.bg_color = Color(0.06, 0.09, 0.16, 0.92)
	style_compra.border_color = Color(0.2, 0.75, 0.35, 0.8)
	style_compra.set_border_width_all(2)
	style_compra.set_corner_radius_all(16)
	style_compra.set_content_margin_all(20)
	style_compra.shadow_color = Color(0, 0, 0, 0.5)
	style_compra.shadow_size = 14
	style_compra.shadow_offset = Vector2(0, 6)
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

# ─────────────────────────────────────────────────────────────────────
#   MODAL DE CONSTRUCCIÓN DE CASAS / HOTELES
# ─────────────────────────────────────────────────────────────────────

func _abrir_modal_construccion() -> void:
	if not construir_modal:
		return

	# Limpiar elementos anteriores
	for child in construir_vb_contenido.get_children():
		child.queue_free()

	var jug = jugadores[turno_actual]

	# Cabecera del modal
	var header = VBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER

	var title = Label.new()
	title.text = "🏠 CONSTRUIR EN PROPIEDADES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.25, 0.85, 0.45))
	header.add_child(title)

	var sub = Label.new()
	sub.text = "%s — Saldo disponible: $%d" % [jug.nombre, jug.dinero]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	header.add_child(sub)

	construir_vb_contenido.add_child(header)

	# Scroll Container para la lista de propiedades
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	construir_vb_contenido.add_child(scroll)

	var list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 8)
	scroll.add_child(list_container)

	# Obtener propiedades tipo "calle" del jugador actual (regla temporal: cualquier propiedad propia)
	var props_construibles: Array = []
	for prop in jug.propiedades:
		if prop is PropiedadCasillaData and prop.tipo == "calle":
			props_construibles.append(prop)

	if props_construibles.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No tienes calles compradas aún.\n¡Compra propiedades de calle para poder construir!"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		list_container.add_child(empty_lbl)
	else:
		for prop in props_construibles:
			var prop_item = PanelContainer.new()
			var st_item = StyleBoxFlat.new()
			st_item.bg_color = Color(0.12, 0.16, 0.24, 0.9)
			st_item.border_color = prop.color_grupo
			st_item.set_border_width_all(2)
			st_item.set_corner_radius_all(8)
			st_item.set_content_margin_all(8)
			prop_item.add_theme_stylebox_override("panel", st_item)

			var hb_row = HBoxContainer.new()
			hb_row.alignment = BoxContainer.ALIGNMENT_CENTER
			hb_row.add_theme_constant_override("separation", 10)
			prop_item.add_child(hb_row)

			var info_vb = VBoxContainer.new()
			info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var lbl_name = Label.new()
			lbl_name.text = prop.nombre.replace("\n", " ")
			lbl_name.add_theme_font_size_override("font_size", 14)
			lbl_name.add_theme_color_override("font_color", Color.WHITE)
			info_vb.add_child(lbl_name)

			var nivel_str = ""
			if prop.casas == 0:
				nivel_str = "Sin edificaciones"
			elif prop.casas < 5:
				nivel_str = "%d casa(s)" % prop.casas
			else:
				nivel_str = "🏨 1 Hotel (Máximo)"

			var lbl_nivel = Label.new()
			lbl_nivel.text = "Estado: " + nivel_str + " | Costo: $" + str(prop.costo_casa)
			lbl_nivel.add_theme_font_size_override("font_size", 12)
			lbl_nivel.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
			info_vb.add_child(lbl_nivel)

			hb_row.add_child(info_vb)

			# Botón Construir
			var btn_add = Button.new()
			if prop.casas < 4:
				btn_add.text = "+ Casa ($%d)" % prop.costo_casa
			elif prop.casas == 4:
				btn_add.text = "+ Hotel ($%d)" % prop.costo_casa
			else:
				btn_add.text = "Máximo"

			btn_add.add_theme_font_size_override("font_size", 13)
			btn_add.disabled = (prop.casas >= 5) or (not jug.puede_pagar(prop.costo_casa))

			var st_badd = StyleBoxFlat.new()
			st_badd.bg_color = Color(0.18, 0.65, 0.3)
			st_badd.set_corner_radius_all(6)
			st_badd.set_content_margin_all(6)
			btn_add.add_theme_stylebox_override("normal", st_badd)
			btn_add.add_theme_color_override("font_color", Color.WHITE)

			var p_ref = prop
			btn_add.pressed.connect(func():
				_construir_en_propiedad(jug, p_ref)
			)
			hb_row.add_child(btn_add)

			list_container.add_child(prop_item)

	# Botón de Cerrar Modal
	var btn_cerrar_mod = Button.new()
	btn_cerrar_mod.text = "CERRAR"
	btn_cerrar_mod.add_theme_font_size_override("font_size", 14)
	var st_cls = StyleBoxFlat.new()
	st_cls.bg_color = Color(0.45, 0.15, 0.15)
	st_cls.set_corner_radius_all(8)
	st_cls.set_content_margin_all(6)
	btn_cerrar_mod.add_theme_stylebox_override("normal", st_cls)
	btn_cerrar_mod.add_theme_color_override("font_color", Color.WHITE)
	btn_cerrar_mod.pressed.connect(_cerrar_modal_construccion)
	construir_vb_contenido.add_child(btn_cerrar_mod)

	construir_modal.visible = true

func _cerrar_modal_construccion() -> void:
	if construir_modal:
		construir_modal.visible = false

func _construir_en_propiedad(jug: JugadorData, prop: PropiedadCasillaData) -> void:
	if jug.puede_pagar(prop.costo_casa) and prop.casas < 5:
		jug.modificar_dinero(-prop.costo_casa)
		prop.agregar_casa()
		var cas = casillas_data[prop.id]
		if cas and cas.nodo_visual:
			cas.nodo_visual.actualizar_casas(prop.casas)
			_crear_efecto_particulas_compra(cas.nodo_visual.global_position)

		var tipo_txt = "hotel" if prop.casas == 5 else "casa"
		_notificar("🏠 " + jug.nombre + " construyó un " + tipo_txt + " en " + prop.nombre.replace("\n", " "))
		_actualizar_hud()
		_abrir_modal_construccion()
