class_name FichaVisual
extends Node3D

signal movimiento_completado

var id_jugador: int
var color_jugador: Color
var tipo_figura: int = 0
var mesh_principal: MeshInstance3D

# Variables de animación fluida
var esta_animando: bool = false
var _trayecto: Array[Vector3] = []
var _paso_actual: int = 0
var _pos_inicio_paso: Vector3
var _pos_destino_paso: Vector3
var _tiempo_paso: float = 0.0
var _duracion_paso: float = 0.11 # Duración rápida y fluida por casilla
var _callback_final: Callable

func setup(p_id: int, p_color: Color, p_tipo_figura: int = 0) -> void:
	id_jugador = p_id
	color_jugador = p_color
	tipo_figura = p_tipo_figura
	_crear_geometria_ficha()

func _crear_geometria_ficha() -> void:
	for child in get_children():
		child.queue_free()
		
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color_jugador
	mat.metallic = 0.7
	mat.roughness = 0.2
	
	match tipo_figura:
		0: # Sombrero de Copa
			var container = Node3D.new()
			add_child(container)
			
			var copa = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.16
			cyl.bottom_radius = 0.16
			cyl.height = 0.35
			copa.mesh = cyl
			copa.material_override = mat
			copa.position.y = 0.22
			container.add_child(copa)
			
			var ala = MeshInstance3D.new()
			var cyl_ala = CylinderMesh.new()
			cyl_ala.top_radius = 0.28
			cyl_ala.bottom_radius = 0.28
			cyl_ala.height = 0.04
			ala.mesh = cyl_ala
			ala.material_override = mat
			ala.position.y = 0.04
			container.add_child(ala)
			
		1: # Coche Deportivo
			var container = Node3D.new()
			add_child(container)
			
			var chasis = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.32, 0.14, 0.5)
			chasis.mesh = box
			chasis.material_override = mat
			chasis.position.y = 0.12
			container.add_child(chasis)
			
			var cabina = MeshInstance3D.new()
			var box_cab = BoxMesh.new()
			box_cab.size = Vector3(0.24, 0.12, 0.24)
			cabina.mesh = box_cab
			
			var mat_cabina = StandardMaterial3D.new()
			mat_cabina.albedo_color = color_jugador.darkened(0.4)
			mat_cabina.metallic = 0.9
			mat_cabina.roughness = 0.1
			cabina.material_override = mat_cabina
			cabina.position = Vector3(0, 0.24, -0.02)
			container.add_child(cabina)
			
		2: # Barco / Velero
			var container = Node3D.new()
			add_child(container)
			
			var casco = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.26, 0.16, 0.48)
			casco.mesh = box
			casco.material_override = mat
			casco.position.y = 0.10
			container.add_child(casco)
			
			var vela = MeshInstance3D.new()
			var prism = PrismMesh.new()
			prism.size = Vector3(0.05, 0.4, 0.28)
			vela.mesh = prism
			
			var mat_vela = StandardMaterial3D.new()
			mat_vela.albedo_color = Color(0.95, 0.95, 0.95)
			vela.material_override = mat_vela
			vela.position = Vector3(0, 0.35, 0)
			container.add_child(vela)
			
		_: # Peón Clásico
			var peon = MeshInstance3D.new()
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.1
			cyl.bottom_radius = 0.22
			cyl.height = 0.48
			peon.mesh = cyl
			peon.material_override = mat
			peon.position.y = 0.24
			add_child(peon)

func mover_paso_a_paso(trayecto_puntos: Array, al_terminar: Callable = Callable()) -> void:
	if trayecto_puntos.is_empty():
		if al_terminar.is_valid():
			al_terminar.call()
		return
		
	_trayecto = trayecto_puntos
	_paso_actual = 0
	_pos_inicio_paso = position
	_pos_destino_paso = _trayecto[0]
	_tiempo_paso = 0.0
	_callback_final = al_terminar
	esta_animando = true
	set_process(true)

func _process(delta: float) -> void:
	if not esta_animando:
		set_process(false)
		return
		
	_tiempo_paso += delta
	var progress = clamp(_tiempo_paso / _duracion_paso, 0.0, 1.0)
	
	# Interpolación lineal horizontal (X, Z)
	var pos_interp = _pos_inicio_paso.lerp(_pos_destino_paso, progress)
	
	# Salto parabólico suave en Y (curva seno)
	var altura_salto = sin(progress * PI) * 0.28
	pos_interp.y = lerp(_pos_inicio_paso.y, _pos_destino_paso.y, progress) + altura_salto
	
	position = pos_interp
	
	if progress >= 1.0:
		# Pasar al siguiente paso del trayecto
		_paso_actual += 1
		if _paso_actual < _trayecto.size():
			_pos_inicio_paso = position
			_pos_destino_paso = _trayecto[_paso_actual]
			_tiempo_paso = 0.0
		else:
			# Animación completada
			esta_animando = false
			position = _trayecto[_trayecto.size() - 1]
			movimiento_completado.emit()
			set_process(false)
			if _callback_final.is_valid():
				_callback_final.call()
