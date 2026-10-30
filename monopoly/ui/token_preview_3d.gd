class_name TokenPreview3D
extends SubViewportContainer
## Vista previa 3D de una ficha girando sobre un pedestal (para elegir ficha y color).

var _viewport: SubViewport
var _holder: Node3D
var _token: Node3D
var _spin := 0.0


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c9d6e8")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(35), 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	_viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.2, 1.2, -1.2)
	rim.light_color = Color("#f2a541")
	rim.light_energy = 1.5
	rim.omni_range = 4.0
	_viewport.add_child(rim)
	var cam := Camera3D.new()
	var eye := Vector3(0, 0.95, 2.2)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.42, 0) - eye), eye)
	cam.fov = 40
	_viewport.add_child(cam)
	var pedestal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.56
	cyl.height = 0.08
	cyl.radial_segments = 48
	pedestal.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#13233f")
	pm.metallic = 0.4
	pm.roughness = 0.25
	pedestal.material_override = pm
	pedestal.position = Vector3(0, -0.04, 0)
	_viewport.add_child(pedestal)
	_holder = Node3D.new()
	_viewport.add_child(_holder)


func set_token(token: String, color: Color) -> void:
	if _token:
		_token.queue_free()
	_token = TokenArt.build_3d(token, color)
	_token.scale = Vector3.ONE * 0.01
	_holder.add_child(_token)
	create_tween().tween_property(_token, "scale", Vector3.ONE * 2.2, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_spin += delta
	_holder.rotation.y = _spin * 0.9
	_holder.position.y = 0.03 + sin(_spin * 2.0) * 0.02
