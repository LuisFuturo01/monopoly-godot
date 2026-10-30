class_name TokenArt
extends RefCounted
## Fichas originales dibujadas por código: glifos 2D y mallas 3D con primitivas.
## llama, charango, cabina (teleférico), bombín, ekeko, zampoña, cóndor, trompo.


static func draw_2d(ci: CanvasItem, token: String, c: Vector2, r: float, color: Color) -> void:
	ci.draw_circle(c + Vector2(r * 0.08, r * 0.12), r, Color(0, 0, 0, 0.35))
	ci.draw_circle(c, r, color)
	ci.draw_arc(c, r, 0, TAU, 24, color.darkened(0.45), r * 0.14, true)
	var g := Color(1, 1, 1, 0.95)
	var s := r * 0.62
	match token:
		"llama":
			ci.draw_rect(Rect2(c + Vector2(-0.7, 0.0) * s, Vector2(1.0, 0.45) * s), g)
			ci.draw_rect(Rect2(c + Vector2(0.1, -0.8) * s, Vector2(0.28, 0.85) * s), g)
			ci.draw_rect(Rect2(c + Vector2(0.1, -0.8) * s, Vector2(0.55, 0.25) * s), g)
			for x in [-0.6, -0.15]:
				ci.draw_rect(Rect2(c + Vector2(x, 0.45) * s, Vector2(0.14, 0.45) * s), g)
		"charango":
			ci.draw_circle(c + Vector2(0, 0.35) * s, 0.5 * s, g)
			ci.draw_rect(Rect2(c + Vector2(-0.1, -0.95) * s, Vector2(0.2, 1.0) * s), g)
			ci.draw_circle(c + Vector2(0, 0.35) * s, 0.14 * s, color)
		"cabina":
			ci.draw_line(c + Vector2(-1, -0.8) * s, c + Vector2(1, -0.95) * s, g, s * 0.1)
			ci.draw_line(c + Vector2(0, -0.87) * s, c + Vector2(0, -0.45) * s, g, s * 0.1)
			ci.draw_rect(Rect2(c + Vector2(-0.55, -0.45) * s, Vector2(1.1, 1.05) * s), g)
			ci.draw_rect(Rect2(c + Vector2(-0.4, -0.3) * s, Vector2(0.8, 0.35) * s), color)
		"bombin":
			ci.draw_rect(Rect2(c + Vector2(-0.95, 0.25) * s, Vector2(1.9, 0.22) * s), g)
			ci.draw_circle(c + Vector2(0, 0.15) * s, 0.55 * s, g)
			ci.draw_rect(Rect2(c + Vector2(-0.55, 0.12) * s, Vector2(1.1, 0.13) * s), color)
		"ekeko":
			ci.draw_circle(c + Vector2(0, 0.35) * s, 0.55 * s, g)
			ci.draw_circle(c + Vector2(0, -0.45) * s, 0.35 * s, g)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.3, -0.7) * s, c + Vector2(0.3, -0.7) * s, c + Vector2(0, -1.05) * s]), g)
		"zampona":
			for k in 5:
				var h := 1.5 - k * 0.2
				ci.draw_rect(Rect2(c + Vector2(-0.8 + k * 0.33, -0.75) * s, Vector2(0.24, h) * s), g)
		"condor":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-1, -0.3) * s, c + Vector2(-0.4, 0.05) * s, c + Vector2(0, 0.35) * s, c + Vector2(0.4, 0.05) * s, c + Vector2(1, -0.3) * s]), g, s * 0.3)
			ci.draw_circle(c + Vector2(0, 0.0) * s, 0.22 * s, g)
		"trompo":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.7, -0.35) * s, c + Vector2(0.7, -0.35) * s, c + Vector2(0, 0.95) * s]), g)
			ci.draw_rect(Rect2(c + Vector2(-0.12, -0.8) * s, Vector2(0.24, 0.48) * s), g)
		_:
			ci.draw_circle(c, 0.5 * s, g)


static func build_3d(token: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Token_" + token
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.65
	mat.roughness = 0.3
	var dark := mat.duplicate()
	dark.albedo_color = color.darkened(0.4)
	# Peana común para que todas las fichas se lean igual sobre el tablero.
	_add(root, _cyl(0.17, 0.19, 0.05), Vector3(0, 0.025, 0), dark)
	match token:
		"llama":
			_add(root, _box(Vector3(0.32, 0.14, 0.14)), Vector3(0, 0.2, 0), mat)
			_add(root, _box(Vector3(0.08, 0.24, 0.08)), Vector3(0.12, 0.36, 0), mat)
			_add(root, _box(Vector3(0.14, 0.07, 0.07)), Vector3(0.16, 0.48, 0), mat)
			for e in [-0.025, 0.025]:
				_add(root, _box(Vector3(0.025, 0.06, 0.02)), Vector3(0.11, 0.54, e), mat)
			for x in [-0.12, 0.1]:
				for z in [-0.05, 0.05]:
					_add(root, _cyl(0.022, 0.022, 0.13), Vector3(x, 0.11, z), mat)
		"charango":
			var body := _add(root, _sphere(0.13), Vector3(0, 0.17, 0), mat)
			body.scale = Vector3(1.0, 0.55, 1.0)
			body.rotation.x = PI / 2
			_add(root, _box(Vector3(0.05, 0.3, 0.025)), Vector3(0, 0.38, 0), dark)
			_add(root, _box(Vector3(0.08, 0.07, 0.03)), Vector3(0, 0.55, 0), mat)
		"cabina":
			_add(root, _box(Vector3(0.26, 0.24, 0.22)), Vector3(0, 0.19, 0), mat)
			_add(root, _box(Vector3(0.27, 0.08, 0.23)), Vector3(0, 0.22, 0), _glass())
			_add(root, _cyl(0.015, 0.015, 0.2), Vector3(0, 0.41, 0), dark)
			var cable := _add(root, _cyl(0.012, 0.012, 0.42), Vector3(0, 0.51, 0), dark)
			cable.rotation.z = PI / 2
		"bombin":
			_add(root, _cyl(0.17, 0.17, 0.03), Vector3(0, 0.07, 0), mat)
			var dome := _add(root, _sphere(0.12), Vector3(0, 0.16, 0), mat)
			dome.scale = Vector3(1, 1.15, 1)
			_add(root, _cyl(0.123, 0.123, 0.03), Vector3(0, 0.11, 0), dark)
		"ekeko":
			_add(root, _sphere(0.13), Vector3(0, 0.17, 0), mat)
			_add(root, _sphere(0.085), Vector3(0, 0.36, 0), mat)
			_add(root, _cone(0.07, 0.12), Vector3(0, 0.47, 0), dark)
		"zampona":
			for k in 5:
				var h := 0.42 - k * 0.06
				_add(root, _cyl(0.028, 0.028, h), Vector3(-0.12 + k * 0.06, 0.05 + h / 2.0, 0), mat)
			_add(root, _box(Vector3(0.32, 0.03, 0.07)), Vector3(0, 0.3, 0), dark)
		"condor":
			_add(root, _cyl(0.025, 0.03, 0.2), Vector3(0, 0.15, 0), dark)
			var body2 := _add(root, _sphere(0.07), Vector3(0, 0.3, 0), mat)
			body2.scale = Vector3(1, 0.8, 1.4)
			for sgn in [-1.0, 1.0]:
				var wing := _add(root, _box(Vector3(0.24, 0.02, 0.11)), Vector3(sgn * 0.15, 0.34, 0), mat)
				wing.rotation.z = sgn * 0.35
		"trompo":
			var cone := _add(root, _cone(0.15, 0.26), Vector3(0, 0.2, 0), mat)
			cone.rotation.x = PI
			_add(root, _cyl(0.03, 0.03, 0.1), Vector3(0, 0.38, 0), dark)
		_:
			_add(root, _sphere(0.15), Vector3(0, 0.2, 0), mat)
	return root


static func _add(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 16
	return m


static func _cone(r: float, h: float) -> CylinderMesh:
	return _cyl(0.0, r, h)


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.85, 1.0, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.2
	m.roughness = 0.05
	return m
