class_name GameManager
extends Node3D

var tablero_manager: TableroManager
var casillas_data: Array[CasillaData] = []
var jugadores: Array[JugadorData] = []
var turno_actual: int = 0
var esta_procesando_turno: bool = false

# Cámara 3D
var camara_3d: Camera3D
var target_camara_pos: Vector3

# Elementos de la UI Minimalista
var canvas_ui: CanvasLayer
var contenedor_jugadores_hud: HBoxContainer
var array_labels_jugadores: Array[Label] = []
var boton_tirar: Button
var banner_notificacion: Label
var timer_banner: SceneTreeTimer

# Modal de Animación de Dados en Centro de Pantalla
var overlay_dados: PanelContainer
var label_dado1: Label
var label_dado2: Label
var label_dados_total: Label

# Modal de Compra de Propiedad
var panel_compra: PanelContainer
var label_compra_info: Label
var boton_comprar: Button
var boton_pasar: Button

func _ready() -> void:
	randomize()
	
	# 1. Cámara 3D
	_configurar_camara_3d()
	
	# 2. Tablero 3D Proporcional
	tablero_manager = TableroManager.new()
	tablero_manager.name = "TableroManager"
	add_child(tablero_manager)
	casillas_data = tablero_manager.construir_tablero()
	
	# 3. Jugadores y Fichas 3D
	_inicializar_jugadores(2)
	
	# 4. HUD Limpio y Minimalista
	_construir_hud_limpio()
	_actualizar_ui()
	_mostrar_notificacion("¡Bienvenido a Monopoly 3D! Presiona TIRAR DADOS para iniciar.")

func _configurar_camara_3d() -> void:
	camara_3d = Camera3D.new()
	camara_3d.name = "CamaraJuego3D"
	camara_3d.position = Vector3(0, 13.0, 10.0)
	camara_3d.rotation_degrees = Vector3(-50, 0, 0)
	target_camara_pos = camara_3d.position
	add_child(camara_3d)

func _process(delta: float) -> void:
	if camara_3d:
		camara_3d.position = camara_3d.position.lerp(target_camara_pos, delta * 3.5)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not esta_procesando_turno:
		ejecutar_turno()
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			target_camara_pos.y = max(6.0, target_camara_pos.y - 1.0)
			target_camara_pos.z = max(4.0, target_camara_pos.z - 0.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			target_camara_pos.y = min(18.0, target_camara_pos.y + 1.0)
			target_camara_pos.z = min(15.0, target_camara_pos.z + 0.8)

func _inicializar_jugadores(cantidad: int) -> void:
	var colores = [Color(0.95, 0.25, 0.25), Color(0.25, 0.55, 0.95)]
	var nombres = ["Jugador 1 (Rojo)", "Jugador 2 (Azul)"]
	
	for i in range(cantidad):
		var j_data = JugadorData.new(i, nombres[i], 1500, colores[i])
		
		var ficha = FichaVisual.new()
		ficha.name = "FichaJugador_" + str(i)
		ficha.setup(i, colores[i], i)
		add_child(ficha)
		
		j_data.nodo_ficha = ficha
		jugadores.append(j_data)
		
		var pos_inicio = tablero_manager.obtener_posicion_casilla_con_offset(0, i, cantidad)
		ficha.position = pos_inicio

func ejecutar_turno() -> void:
	if esta_procesando_turno: return
	esta_procesando_turno = true
	boton_tirar.disabled = true
	
	var jugador_actual = jugadores[turno_actual]
	
	# Lanzar Dados con Animación en Centro de Pantalla
	var dado1 = randi_range(1, 6)
	var dado2 = randi_range(1, 6)
	var total_dados = dado1 + dado2
	
	_animar_lanzamiento_dados_centro(dado1, dado2, total_dados, func():
		_continuar_turno(jugador_actual, total_dados)
	)

func _animar_lanzamiento_dados_centro(d1: int, d2: int, total: int, al_terminar: Callable) -> void:
	overlay_dados.visible = true
	label_dados_total.text = "TIRANDO DADOS..."
	
	var tween = create_tween().set_parallel(false)
	var caras_dados = ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"]
	
	# Animación de giro de caras de dados por 0.5 segundos
	for k in range(8):
		tween.tween_callback(func():
			label_dado1.text = caras_dados.pick_random()
			label_dado2.text = caras_dados.pick_random()
		)
		tween.tween_interval(0.06)
		
	# Fijar caras finales
	tween.tween_callback(func():
		label_dado1.text = caras_dados[d1 - 1]
		label_dado2.text = caras_dados[d2 - 1]
		label_dados_total.text = "¡Avanzas %d casillas!" % total
	)
	tween.tween_interval(0.6)
	
	tween.tween_callback(func():
		overlay_dados.visible = false
		if al_terminar.is_valid():
			al_terminar.call()
	)

func _continuar_turno(jugador_actual: JugadorData, total_dados: int) -> void:
	var pos_anterior = jugador_actual.posicion
	var nueva_pos = (pos_anterior + total_dados) % 40
	var trayecto_puntos: Array[Vector3] = []
	
	var paso_pos = pos_anterior
	for paso in range(1, total_dados + 1):
		paso_pos = (pos_anterior + paso) % 40
		var pos_3d = tablero_manager.obtener_posicion_casilla_con_offset(paso_pos, jugador_actual.id, jugadores.size())
		trayecto_puntos.append(pos_3d)
		
	jugador_actual.posicion = nueva_pos
	
	# Cámara enfocada en la zona
	var pos_final_3d = trayecto_puntos[trayecto_puntos.size() - 1]
	target_camara_pos = Vector3(pos_final_3d.x * 0.35, target_camara_pos.y, pos_final_3d.z * 0.35 + 8.5)
	
	jugador_actual.nodo_ficha.mover_paso_a_paso(trayecto_puntos, func():
		_procesar_llegada_casilla(jugador_actual, pos_anterior, nueva_pos, total_dados)
	)

func _procesar_llegada_casilla(jugador: JugadorData, pos_anterior: int, nueva_pos: int, resultado_dados: int) -> void:
	if nueva_pos < pos_anterior:
		jugador.modificar_dinero(200)
		_mostrar_notificacion("💰 ¡" + jugador.nombre + " pasó por la SALIDA y cobró $200!")
		
	var casilla = casillas_data[nueva_pos]
	_mostrar_notificacion("📍 " + jugador.nombre + " cayó en " + casilla.nombre)
	
	if casilla is PropiedadCasillaData:
		var prop = casilla as PropiedadCasillaData
		if not prop.esta_comprada():
			_mostrar_dialogo_compra(jugador, prop)
			return
		elif prop.propietario_id != jugador.id:
			var propietario = jugadores[prop.propietario_id]
			var alquiler = prop.calcular_alquiler(resultado_dados)
			jugador.modificar_dinero(-alquiler)
			propietario.modificar_dinero(alquiler)
			_mostrar_notificacion("💸 " + jugador.nombre + " pagó $" + str(alquiler) + " de alquiler a " + propietario.nombre)
		elif prop.propietario_id == jugador.id and prop.tipo == "calle":
			if jugador.puede_pagar(prop.costo_casa) and prop.casas < 5:
				jugador.modificar_dinero(-prop.costo_casa)
				prop.agregar_casa()
				casilla.nodo_visual.actualizar_casas(prop.casas)
				_mostrar_notificacion("🏠 ¡" + jugador.nombre + " construyó una casa en " + prop.nombre + "!")
				
	elif casilla.tipo == "suerte":
		_ejecutar_evento_suerte(jugador)
	elif casilla.tipo == "arca":
		_ejecutar_evento_arca(jugador)
	elif casilla.tipo == "impuesto":
		var monto = 200 if casilla.id == 4 else 100
		jugador.modificar_dinero(-monto)
		_mostrar_notificacion("🏛️ " + jugador.nombre + " pagó $" + str(monto) + " de impuestos.")
	elif casilla.tipo == "ir_carcel":
		jugador.posicion = 10
		jugador.en_carcel = true
		var pos_carcel = tablero_manager.obtener_posicion_casilla_con_offset(10, jugador.id, jugadores.size())
		jugador.nodo_ficha.position = pos_carcel
		_mostrar_notificacion("🚨 ¡" + jugador.nombre + " fue enviado a la CÁRCEL!")
		
	_finalizar_turno()

func _mostrar_dialogo_compra(jugador: JugadorData, prop: PropiedadCasillaData) -> void:
	label_compra_info.text = "¿Deseas comprar " + prop.nombre + "?\nPrecio: $" + str(prop.precio) + "  |  Tu Saldo: $" + str(jugador.dinero)
	boton_comprar.disabled = not jugador.puede_pagar(prop.precio)
	panel_compra.visible = true

func _on_boton_comprar_pressed() -> void:
	panel_compra.visible = false
	var jugador = jugadores[turno_actual]
	var casilla = casillas_data[jugador.posicion]
	
	if casilla is PropiedadCasillaData:
		var prop = casilla as PropiedadCasillaData
		if jugador.puede_pagar(prop.precio):
			jugador.modificar_dinero(-prop.precio)
			prop.propietario_id = jugador.id
			jugador.agregar_propiedad(prop)
			
			casilla.nodo_visual.actualizar_propietario(jugador.color_ficha)
			_mostrar_notificacion("📜 ¡" + jugador.nombre + " compró " + prop.nombre + " por $" + str(prop.precio) + "!")
			
	_finalizar_turno()

func _on_boton_pasar_pressed() -> void:
	panel_compra.visible = false
	_finalizar_turno()

func _finalizar_turno() -> void:
	turno_actual = (turno_actual + 1) % jugadores.size()
	esta_procesando_turno = false
	boton_tirar.disabled = false
	_actualizar_ui()

func _ejecutar_evento_suerte(jugador: JugadorData) -> void:
	var eventos = [
		{"texto": "¡Premio de lotería! Ganas $150.", "monto": 150},
		{"texto": "Multa de tránsito. Pagas $50.", "monto": -50},
		{"texto": "Reembolso bancario a favor. Ganas $100.", "monto": 100}
	]
	var e = eventos.pick_random()
	jugador.modificar_dinero(e["monto"])
	_mostrar_notificacion("❓ [SUERTE] " + e["texto"])

func _ejecutar_evento_arca(jugador: JugadorData) -> void:
	var eventos = [
		{"texto": "Venta de acciones en bolsa. Ganas $200.", "monto": 200},
		{"texto": "Gastos médicos imprevistos. Pagas $100.", "monto": -100},
		{"texto": "Regalo de cumpleaños. Ganas $50.", "monto": 50}
	]
	var e = eventos.pick_random()
	jugador.modificar_dinero(e["monto"])
	_mostrar_notificacion("💼 [ARCA COMUNAL] " + e["texto"])

func _construir_hud_limpio() -> void:
	canvas_ui = CanvasLayer.new()
	add_child(canvas_ui)
	
	# 1. Barra Superior Flotante para Jugadores (Minimalista, sin cajas gigantes)
	contenedor_jugadores_hud = HBoxContainer.new()
	contenedor_jugadores_hud.anchor_left = 0.05
	contenedor_jugadores_hud.anchor_top = 0.03
	contenedor_jugadores_hud.anchor_right = 0.95
	contenedor_jugadores_hud.alignment = BoxContainer.ALIGNMENT_CENTER
	contenedor_jugadores_hud.add_theme_constant_override("separation", 40)
	canvas_ui.add_child(contenedor_jugadores_hud)
	
	for j in jugadores:
		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		contenedor_jugadores_hud.add_child(lbl)
		array_labels_jugadores.append(lbl)
		
	# 2. Banner Flotante Superior para Notificaciones Rápidas
	banner_notificacion = Label.new()
	banner_notificacion.anchor_left = 0.2
	banner_notificacion.anchor_top = 0.09
	banner_notificacion.anchor_right = 0.8
	banner_notificacion.anchor_bottom = 0.14
	banner_notificacion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_notificacion.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_notificacion.add_theme_font_size_override("font_size", 16)
	banner_notificacion.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	banner_notificacion.add_theme_color_override("font_outline_color", Color.BLACK)
	banner_notificacion.add_theme_constant_override("outline_size", 5)
	canvas_ui.add_child(banner_notificacion)
	
	# 3. Overlay Animado de Dados en el Centro de Pantalla
	overlay_dados = PanelContainer.new()
	overlay_dados.anchor_left = 0.38
	overlay_dados.anchor_top = 0.35
	overlay_dados.anchor_right = 0.62
	overlay_dados.anchor_bottom = 0.62
	overlay_dados.visible = false
	canvas_ui.add_child(overlay_dados)
	
	var vbox_dados = VBoxContainer.new()
	vbox_dados.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_dados.add_child(vbox_dados)
	
	var hbox_caras = HBoxContainer.new()
	hbox_caras.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_caras.add_theme_constant_override("separation", 30)
	vbox_dados.add_child(hbox_caras)
	
	label_dado1 = Label.new()
	label_dado1.text = "⚀"
	label_dado1.add_theme_font_size_override("font_size", 72)
	hbox_caras.add_child(label_dado1)
	
	label_dado2 = Label.new()
	label_dado2.text = "⚀"
	label_dado2.add_theme_font_size_override("font_size", 72)
	hbox_caras.add_child(label_dado2)
	
	label_dados_total = Label.new()
	label_dados_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_dados_total.add_theme_font_size_override("font_size", 20)
	vbox_dados.add_child(label_dados_total)
	
	# 4. Botón Elegante Inferior para Tirar Dados
	boton_tirar = Button.new()
	boton_tirar.text = "🎲 TIRAR DADOS"
	boton_tirar.anchor_left = 0.38
	boton_tirar.anchor_top = 0.86
	boton_tirar.anchor_right = 0.62
	boton_tirar.anchor_bottom = 0.94
	boton_tirar.add_theme_font_size_override("font_size", 20)
	boton_tirar.pressed.connect(ejecutar_turno)
	canvas_ui.add_child(boton_tirar)
	
	# 5. Diálogo Modal de Compra
	panel_compra = PanelContainer.new()
	panel_compra.anchor_left = 0.3
	panel_compra.anchor_top = 0.38
	panel_compra.anchor_right = 0.7
	panel_compra.anchor_bottom = 0.62
	panel_compra.visible = false
	canvas_ui.add_child(panel_compra)
	
	var vbox_compra = VBoxContainer.new()
	vbox_compra.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_compra.add_child(vbox_compra)
	
	label_compra_info = Label.new()
	label_compra_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_compra_info.add_theme_font_size_override("font_size", 18)
	vbox_compra.add_child(label_compra_info)
	
	var hbox_compra = HBoxContainer.new()
	hbox_compra.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_compra.add_theme_constant_override("separation", 20)
	vbox_compra.add_child(hbox_compra)
	
	boton_comprar = Button.new()
	boton_comprar.text = "🛒 COMPRAR"
	boton_comprar.add_theme_font_size_override("font_size", 16)
	boton_comprar.pressed.connect(_on_boton_comprar_pressed)
	hbox_compra.add_child(boton_comprar)
	
	boton_pasar = Button.new()
	boton_pasar.text = "❌ PASAR"
	boton_pasar.add_theme_font_size_override("font_size", 16)
	boton_pasar.pressed.connect(_on_boton_pasar_pressed)
	hbox_compra.add_child(boton_pasar)

func _actualizar_ui() -> void:
	for i in range(jugadores.size()):
		var j = jugadores[i]
		var es_turno = (i == 0 and turno_actual == 0) or (i == 1 and turno_actual == 1)
		var marker = " ◄ TURNO" if es_turno else ""
		var casilla_nom = casillas_data[j.posicion].nombre
		array_labels_jugadores[i].text = "%s: $%d | %s%s" % [j.nombre, j.dinero, casilla_nom, marker]
		if es_turno:
			array_labels_jugadores[i].add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			array_labels_jugadores[i].add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

func _mostrar_notificacion(msg: String) -> void:
	if banner_notificacion:
		banner_notificacion.text = msg
