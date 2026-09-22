class_name GameManager
extends Node3D

var tablero_manager: TableroManager
var casillas: Array[CasillaData] = []
var jugadores = []
var turno_actual = 0

# Referencias a elementos de la UI
var label_estado: Label
var boton_tirar: Button

func _ready() -> void:
	# 1. Configurar Cámara 3D
	var camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 14, 14)
	camera.rotation_degrees = Vector3(-45, 0, 0)
	add_child(camera)
	
	# 2. Construir Tablero
	tablero_manager = TableroManager.new()
	add_child(tablero_manager)
	casillas = tablero_manager.construir_tablero()
	
	# 3. Inicializar Jugadores y UI
	inicializar_jugadores(2)
	construir_interfaz_usuario()
	actualizar_texto_ui()

func inicializar_jugadores(cantidad: int) -> void:
	for i in range(cantidad):
		var ficha = MeshInstance3D.new()
		var cilindro = CylinderMesh.new()
		cilindro.top_radius = 0.22
		cilindro.bottom_radius = 0.22
		cilindro.height = 0.7
		ficha.mesh = cilindro
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2, 0.2) if i == 0 else Color(0.2, 0.4, 1.0)
		ficha.material_override = mat
		add_child(ficha)
		
		var jugador = {
			"id": i,
			"nombre": "Jugador " + str(i + 1),
			"dinero": 1500,
			"posicion": 0,
			"nodo_ficha": ficha
		}
		jugadores.append(jugador)
		actualizar_posicion_visual(jugador)

func actualizar_posicion_visual(jugador) -> void:
	var casilla_destino = casillas[jugador["posicion"]]
	var pos = casilla_destino.posicion_3d
	
	# Offset sutil y controlado dentro del perímetro de la casilla
	var offset_x = 0.0
	var offset_z = 0.0
	
	if jugador["id"] == 0:
		offset_x = -0.2
	else:
		offset_x = 0.2
		
	jugador["nodo_ficha"].position = Vector3(pos.x + offset_x, 0.5, pos.z + offset_z)

func construir_interfaz_usuario() -> void:
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	# Contenedor principal estilo panel superior
	var panel = PanelContainer.new()
	panel.anchor_right = 0.35
	panel.anchor_bottom = 0.2
	panel.offset_left = 20
	panel.offset_top = 20
	canvas.add_child(panel)
	
	label_estado = Label.new()
	label_estado.text = "Iniciando juego..."
	panel.add_child(label_estado)
	
	# Botón flotante para tirar dados
	boton_tirar = Button.new()
	boton_tirar.text = "🎲 TIRAR DADOS (ESPACIO)"
	boton_tirar.anchor_left = 0.05
	boton_tirar.anchor_top = 0.82
	boton_tirar.anchor_right = 0.3
	boton_tirar.anchor_bottom = 0.92
	boton_tirar.pressed.connect(_on_boton_tirar_pressed)
	canvas.add_child(boton_tirar)

func actualizar_texto_ui() -> void:
	if not label_estado: return
	var texto = "=== ESTADO DE LA PARTIDA ===\n"
	for j in jugadores:
		var indicador = " -> [TURNO]" if j["id"] == turno_actual else ""
		texto += "%s: $%d (Pos: %d)%s\n" % [j["nombre"], j["dinero"], j["posicion"], indicador]
	label_estado.text = texto

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		ejecutar_turno()

func _on_boton_tirar_pressed() -> void:
	ejecutar_turno()

func ejecutar_turno() -> void:
	var j = jugadores[turno_actual]
	
	var dado1 = randi_range(1, 6)
	var dado2 = randi_range(1, 6)
	var dados = dado1 + dado2
	
	print("\n----------------------------------------")
	print(j["nombre"] + " tiró los dados: " + str(dado1) + " y " + str(dado2) + " (Total: " + str(dados) + ")")
	
	var pos_vieja = j["posicion"]
	j["posicion"] = (j["posicion"] + dados) % 40
	
	if j["posicion"] < pos_vieja:
		j["dinero"] += 200
		print("¡" + j["nombre"] + " pasó por la SALIDA! Cobra $200.")
		
	actualizar_posicion_visual(j)
	
	var casilla = casillas[j["posicion"]]
	print(j["nombre"] + " cayó en: " + casilla.nombre)
	
	# --- LÓGICA DE CASILLAS ---
	if casilla.tipo in ["calle", "estacion", "servicio"]:
		if casilla.propietario == -1:
			if j["dinero"] >= casilla.precio:
				j["dinero"] -= casilla.precio
				casilla.propietario = j["id"]
				
				var mat_compra = StandardMaterial3D.new()
				mat_compra.albedo_color = Color(1.0, 0.4, 0.4) if j["id"] == 0 else Color(0.4, 0.6, 1.0)
				casilla.nodo_visual.material_override = mat_compra
				print("-> ¡" + j["nombre"] + " compró " + casilla.nombre + " por $" + str(casilla.precio) + "!")
		elif casilla.propietario != j["id"]:
			var dueno = jugadores[casilla.propietario]
			j["dinero"] -= casilla.alquiler
			dueno["dinero"] += casilla.alquiler
			print("-> Pagó $" + str(casilla.alquiler) + " de alquiler a " + dueno["nombre"])
			
	elif casilla.tipo == "suerte":
		ejecutar_carta_suerte(j)
	elif casilla.tipo == "arca":
		ejecutar_carta_arca(j)
	elif casilla.tipo == "ir_carcel":
		j["posicion"] = 10
		actualizar_posicion_visual(j)
		print("-> ¡" + j["nombre"] + " va directo a la CÁRCEL!")
		
	# Cambiar turno y actualizar interfaz visual en pantalla
	turno_actual = (turno_actual + 1) % jugadores.size()
	actualizar_texto_ui()
func ejecutar_carta_suerte(jugador) -> void:
	var eventos = [
		{"texto": "¡Premio mayor de la lotería! Recibe $100.", "monto": 100},
		{"texto": "Multa por exceso de velocidad. Paga $50.", "monto": -50},
		{"texto": "Error bancario a tu favor. Recibe $150.", "monto": 150}
	]
	var evento = eventos.pick_random()
	jugador["dinero"] += evento["monto"]
	print(" cartas [SUERTE] -> " + evento["texto"])

func ejecutar_carta_arca(jugador) -> void:
	var eventos = [
		{"texto": "Venta de acciones exitosa. Recibe $200.", "monto": 200},
		{"texto": "Pagas honorarios médicos. Paga $100.", "monto": -100},
		{"texto": "Devolución de impuestos. Recibe $50.", "monto": 50}
	]
	var evento = eventos.pick_random()
	jugador["dinero"] += evento["monto"]
	print(" cartas [ARCA COMUNAL] -> " + evento["texto"])
