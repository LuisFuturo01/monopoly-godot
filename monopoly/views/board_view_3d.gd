class_name BoardView3D
extends Node3D
## Vista 3D: tablero de juguete con colores vivos, ciudad procedural animada al centro,
## fichas con saltos por casilla, construcción animada de casas y hoteles, y cámara que sigue la jugada.

signal space_clicked(index: int)

const S := BoardLayout.SIZE
const TOP := 0.06
const DIE := 0.4
const PAPER := Color("#fffaf0")
const INK := Color("#2d3436")
const RIM := Color("#6c5ce7")
const TABLE := Color("#1fa89c")
const LAWN := Color("#b8e994")
const ROAD := Color("#57606f")
const CORNER_COLORS := {"go": Color("#55efc4"), "jail": Color("#fdcb6e"), "free": Color("#74b9ff"), "gotojail": Color("#ff7675")}
const PASTELS := [Color("#ff9ff3"), Color("#feca57"), Color("#48dbfb"), Color("#1dd1a1"), Color("#ff6b6b"), Color("#a29bfe"), Color("#fab1a0"), Color("#81ecec")]

var controller: GameController
var active := true
var cinematic := true

var camera: Camera3D
var _cam_yaw := 0.0
var _cam_pitch := deg_to_rad(50.0)
var _cam_dist := 15.0
var _cam_target := Vector3.ZERO
var _cur_yaw := 0.0
var _cur_pitch := deg_to_rad(50.0)
var _cur_dist := 15.0
var _cur_target := Vector3.ZERO
var _follow := -1

var _tokens: Dictionary = {}        # pid -> Node3D
var _anim: Dictionary = {}          # pid -> {pos, from, queue, t}
var _units: Dictionary = {}         # space -> {"kind": "houses"|"hotel", "nodes": Array}
var _owner_marks: Dictionary = {}
var _mortgage_marks: Dictionary = {}
var _glow: MeshInstance3D
var _dice: Array = []
var _dice_tween: Tween
var _mats: Dictionary = {}
var _font: SystemFont
var _rng := RandomNumberGenerator.new()
var _animate_buildings := false

var _cabins: Array = []             # teleférico
var _cars: Array = []               # autos en la avenida
var _time := 0.0

var _press_pos := Vector2.ZERO
var _dragging := false
var _left_down := false
var _touches: Dictionary = {}


func _ready() -> void:
	_rng.seed = 2024
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Nunito", "Poppins", "Segoe UI", "Roboto", "Arial"])
	_font.font_weight = 800
	_build_environment()
	_build_board()
	_build_city()
	_build_dice()
	_glow = _box(Vector3(1, 0.02, 1), Vector3.ZERO, _glow_material())
	_glow.visible = false
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.far = 200.0
	add_child(camera)
	_update_camera(1.0)


func bind(c: GameController) -> void:
	controller = c
	controller.state_changed.connect(_refresh)
	controller.player_events.event_played.connect(_on_event)
	controller.player_events.drained.connect(_on_drained)
	for p in controller.engine.players():
		var tok := TokenArt.build_3d(p["token"], Color.html(p["color"]))
		tok.scale = Vector3.ONE * 1.5
		add_child(tok)
		_tokens[int(p["id"])] = tok
		_anim[int(p["id"])] = {"pos": Vector2.ZERO, "from": Vector2.ZERO, "queue": [], "t": 0.0}
	_refresh()
	_snap_tokens()
	_animate_buildings = true


func set_active(on: bool) -> void:
	active = on
	visible = on
	camera.current = on
	set_process(on)
	set_process_unhandled_input(on)
	if on:
		_snap_tokens()
		_refresh()


func _w(p: Vector2, y: float = TOP) -> Vector3:
	return Vector3(p.x - S / 2.0, y, p.y - S / 2.0)


# ---------------------------------------------------------------------------
# Utilidades de construcción
# ---------------------------------------------------------------------------

func _mat(color: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [color.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, pos: Vector3, mat: Material, parent: Node = self, segments: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segments
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _sphere(r: float, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label(text: String, pos: Vector3, angle: float, font_size: int, width_units: float, color: Color = INK) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = font_size
	l.pixel_size = 0.0035
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = width_units / l.pixel_size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	l.rotation = Vector3(-PI / 2.0, -angle, 0.0)
	add_child(l)
	return l


func _glow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.92, 0.3, 0.6)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.2)
	m.emission_energy_multiplier = 1.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _window_material(tint: Color) -> StandardMaterial3D:
	var key := "win_" + tint.to_html()
	if _mats.has(key):
		return _mats[key]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for y in range(5, 27):
		for x in range(6, 26):
			if (x < 14 or x > 17) and (y < 15 or y > 17):
				img.set_pixel(x, y, Color("#bfe3ff"))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(3.2, 3.2, 3.2)
	m.roughness = 0.45
	_mats[key] = m
	return m


# ---------------------------------------------------------------------------
# Escena: entorno, tablero y ciudad
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#6fb6ff")
	sky_mat.sky_horizon_color = Color("#e3f2ff")
	sky_mat.ground_horizon_color = Color("#e3f2ff")
	sky_mat.ground_bottom_color = Color("#9ad7cf")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.ssao_enabled = true
	env.ssao_intensity = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(28), 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 35.0
	add_child(sun)


func _build_board() -> void:
	var board := Board.load_from_file(GameController.BOARD_PATH)
	# Mesa redonda turquesa y tablero con borde violeta
	_cyl(16.0, 16.0, 0.3, Vector3(0, -0.5, 0), _mat(TABLE, 0.85), self, 64)
	_cyl(9.6, 9.6, 0.02, Vector3(0, -0.34, 0), _mat(TABLE.lightened(0.15), 0.85), self, 64)
	_box(Vector3(S + 0.7, 0.3, S + 0.7), Vector3(0, -0.2, 0), _mat(RIM, 0.35))
	_box(Vector3(S + 0.2, 0.06, S + 0.2), Vector3(0, -0.02, 0), _mat(Color("#dfe6e9"), 0.6))
	for i in board.size():
		var sp := board.space(i)
		var r := BoardLayout.rect(i)
		var ang := BoardLayout.text_angle(i)
		var inward := BoardLayout.inward(i)
		var corner := BoardLayout.is_corner(i)
		var tile_color: Color = CORNER_COLORS.get(sp["type"], PAPER)
		_box(Vector3(r.size.x - 0.05, 0.05, r.size.y - 0.05), _w(r.get_center(), 0.03), _mat(tile_color, 0.7))
		var along := (BoardLayout.CORNER if corner else BoardLayout.CELL) - 0.12
		var ty := TOP + 0.002
		if sp["type"] == "street":
			var br := BoardLayout.band_rect(i)
			_box(Vector3(br.size.x - 0.05, 0.08, br.size.y - 0.05), _w(br.get_center(), 0.07), _mat(board.space_color(i), 0.3))
		if corner:
			var names := {"go": "SALIDA\n+$%d" % board.salary, "jail": "RETÉN", "free": "MIRADOR", "gotojail": "¡AL\nRETÉN!"}
			_label(names.get(sp["type"], sp["name"]), _w(r.get_center(), ty), ang + PI / 4.0, 64, along * 1.2, Color.WHITE if sp["type"] == "gotojail" else INK)
			continue
		var name_pos := r.get_center() + inward * (BoardLayout.CORNER / 2.0 - BoardLayout.BAND - 0.25)
		_label(String(sp["name"]).to_upper(), _w(name_pos, ty), ang, 34, along)
		var sub := ""
		var sub_color := INK
		if board.is_property(i):
			sub = "$%d" % board.price(i)
			sub_color = Color("#00b894")
		elif sp["type"] == "tax":
			sub = "PAGA $%d" % int(sp["amount"])
			sub_color = Color("#d63031")
		if sub != "":
			_label(sub, _w(r.get_center() - inward * 0.55, ty), ang, 40, along, sub_color)
		match sp["type"]:
			"card":
				var destino: bool = sp["deck"] == "destino"
				_label("?" if destino else "!", _w(r.get_center() - inward * 0.2, ty), ang, 110, along, Color("#e17055") if destino else Color("#0984e3"))
			"transit":
				_cabin_icon(_w(r.get_center() - inward * 0.12, TOP), ang)
			"utility":
				var luz := String(sp["name"]).contains("Luz")
				_label("LUZ" if luz else "AGUA", _w(r.get_center() - inward * 0.15, ty), ang, 44, along, Color("#e1a100") if luz else Color("#0984e3"))


func _cabin_icon(pos: Vector3, ang: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = -ang
	add_child(n)
	_box(Vector3(0.28, 0.2, 0.2), Vector3(0, 0.12, 0), _mat(Color("#e17055"), 0.4), n)
	_box(Vector3(0.29, 0.07, 0.21), Vector3(0, 0.15, 0), _mat(Color("#dff9fb"), 0.1), n)
	_cyl(0.012, 0.012, 0.5, Vector3(0, 0.3, 0), _mat(ROAD), n).rotation.z = PI / 2.0


func _build_city() -> void:
	var inner := S - BoardLayout.CORNER * 2.0 - 0.1
	_box(Vector3(inner, 0.04, inner), Vector3(0, 0.02, 0), _mat(LAWN, 0.9))
	# Avenidas: anillo y cruce central
	var road := _mat(ROAD, 0.8)
	var ring := 3.0
	for k in 4:
		var horizontal := k % 2 == 0
		var off := ring if k < 2 else -ring
		var size := Vector3(ring * 2 + 0.5, 0.02, 0.5) if horizontal else Vector3(0.5, 0.02, ring * 2 + 0.5)
		_box(size, Vector3(0, 0.05, off) if horizontal else Vector3(off, 0.05, 0), road)
	_box(Vector3(0.45, 0.02, ring * 2), Vector3(0, 0.05, 0), road)
	_box(Vector3(ring * 2, 0.02, 0.45), Vector3(0, 0.05, 0), road)
	var dash := _mat(Color.WHITE, 0.5)
	for k in range(-5, 6):
		_box(Vector3(0.18, 0.005, 0.04), Vector3(k * 0.55, 0.062, ring), dash)
		_box(Vector3(0.18, 0.005, 0.04), Vector3(k * 0.55, 0.062, -ring), dash)
		_box(Vector3(0.04, 0.005, 0.18), Vector3(ring, 0.062, k * 0.55), dash)
		_box(Vector3(0.04, 0.005, 0.18), Vector3(-ring, 0.062, k * 0.55), dash)
	# Cuatro barrios con estilos distintos
	_district_towers(Vector2(-1.5, -1.5))
	_district_houses(Vector2(1.5, -1.5))
	_district_park(Vector2(-1.5, 1.5))
	_district_mixed(Vector2(1.5, 1.5))
	# Plaza central con obelisco
	_cyl(0.32, 0.32, 0.05, Vector3(0, 0.08, 0), _mat(Color("#ffeaa7"), 0.6), self, 24)
	_cyl(0.03, 0.08, 0.6, Vector3(0, 0.4, 0), _mat(Color.WHITE, 0.3))
	# Nevados al fondo
	_cyl(0.0, 0.85, 1.5, Vector3(-3.15, 0.8, -3.4), _mat(Color("#a29bfe"), 0.8), self, 9)
	_cyl(0.0, 0.36, 0.64, Vector3(-3.15, 1.24, -3.4), _mat(Color.WHITE, 0.6), self, 9)
	_cyl(0.0, 0.6, 1.0, Vector3(-2.2, 0.55, -3.65), _mat(Color("#8c7ae6"), 0.8), self, 9)
	_build_cable_car()
	_build_cars(ring)
	# Mazos de cartas y placa del título
	for k in 2:
		var pos := Vector3(-3.6, 0, 3.6) if k == 0 else Vector3(3.6, 0, -3.6)
		var col := Color("#e17055") if k == 0 else Color("#0984e3")
		var deck := _box(Vector3(1.3, 0.2, 0.85), pos + Vector3(0, 0.15, 0), _mat(col, 0.35))
		deck.rotation.y = PI / 4.0
		_label("DESTINO ?" if k == 0 else "CABILDO !", pos + Vector3(0, 0.256, 0), -PI / 4.0, 46, 1.2, Color.WHITE)
	_box(Vector3(2.3, 0.12, 0.5), Vector3(2.35, 0.1, 3.75), _mat(Color("#fd79a8"), 0.35))
	_label("MAGNATES", Vector3(2.35, 0.165, 3.75), 0.0, 84, 2.2, Color.WHITE)


func _tree(pos: Vector3, size: float = 1.0) -> void:
	_cyl(0.03 * size, 0.04 * size, 0.18 * size, pos + Vector3(0, 0.09 * size, 0), _mat(Color("#a0522d"), 0.9))
	var greens := [Color("#20bf6b"), Color("#26de81"), Color("#0fb9b1")]
	_sphere(0.14 * size, pos + Vector3(0, 0.27 * size, 0), _mat(greens[_rng.randi() % 3], 0.8))


func _house(pos: Vector3, color: Color, size: Vector3) -> void:
	_box(size, pos + Vector3(0, size.y / 2.0, 0), _mat(color, 0.6))
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x * 1.1, size.y * 0.6, size.z * 1.1)
	roof.mesh = prism
	roof.material_override = _mat(color.darkened(0.35), 0.6)
	roof.position = pos + Vector3(0, size.y + size.y * 0.3, 0)
	add_child(roof)


func _tower(pos: Vector3, w: float, h: float, color: Color) -> void:
	_box(Vector3(w, h, w), pos + Vector3(0, h / 2.0 + 0.04, 0), _window_material(color))
	_box(Vector3(w + 0.04, 0.06, w + 0.04), pos + Vector3(0, h + 0.07, 0), _mat(color.darkened(0.3), 0.5))


func _district_towers(c: Vector2) -> void:
	var spots := [Vector2(-0.6, -0.6), Vector2(0.55, -0.65), Vector2(-0.6, 0.55), Vector2(0.6, 0.6), Vector2(0, 0)]
	for k in spots.size():
		var p: Vector2 = c + spots[k]
		var h := 2.4 if k == 4 else _rng.randf_range(0.9, 1.8)
		_tower(Vector3(p.x, 0.04, p.y), 0.55 if k == 4 else 0.45, h, PASTELS[k % PASTELS.size()])


func _district_houses(c: Vector2) -> void:
	for x in 3:
		for z in 3:
			var p := c + Vector2((x - 1) * 0.75, (z - 1) * 0.75)
			_house(Vector3(p.x, 0.04, p.y), PASTELS[(x * 3 + z) % PASTELS.size()], Vector3(0.38, 0.28, 0.34))
	_tree(Vector3(c.x + 1.1, 0.04, c.y), 1.0)


func _district_park(c: Vector2) -> void:
	_cyl(0.6, 0.6, 0.02, Vector3(c.x, 0.06, c.y), _mat(Color("#74b9ff"), 0.15), self, 32)
	for k in 9:
		var a := k * TAU / 9.0
		_tree(Vector3(c.x + cos(a) * 1.0, 0.04, c.y + sin(a) * 1.0), _rng.randf_range(0.9, 1.3))
	_box(Vector3(0.3, 0.06, 0.12), Vector3(c.x, 0.08, c.y + 0.75), _mat(Color("#e17055"), 0.7))


func _district_mixed(c: Vector2) -> void:
	_tower(Vector3(c.x - 0.6, 0.04, c.y - 0.6), 0.5, 1.3, PASTELS[5])
	_tower(Vector3(c.x + 0.6, 0.04, c.y - 0.55), 0.4, 0.9, PASTELS[2])
	_house(Vector3(c.x - 0.55, 0.04, c.y + 0.55), PASTELS[1], Vector3(0.5, 0.3, 0.4))
	_house(Vector3(c.x + 0.55, 0.04, c.y + 0.55), PASTELS[0], Vector3(0.4, 0.3, 0.4))
	_tree(Vector3(c.x, 0.04, c.y), 1.2)


func _build_cable_car() -> void:
	var a := Vector3(-3.4, 0, -2.6)
	var b := Vector3(3.4, 0, -2.0)
	for p in [a, b]:
		_cyl(0.05, 0.08, 1.7, p + Vector3(0, 0.85, 0), _mat(Color("#dfe6e9"), 0.4))
		_box(Vector3(0.3, 0.08, 0.12), p + Vector3(0, 1.7, 0), _mat(Color("#636e72"), 0.4))
	var cable := _cyl(0.008, 0.008, a.distance_to(b), (a + b) / 2.0 + Vector3(0, 1.64, 0), _mat(INK))
	cable.look_at_from_position(cable.position, b + Vector3(0, 1.64, 0), Vector3.UP)
	cable.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var colors := [Color("#d63031"), Color("#fdcb6e"), Color("#00b894")]
	for k in 3:
		var cab := Node3D.new()
		add_child(cab)
		_box(Vector3(0.22, 0.18, 0.16), Vector3(0, -0.14, 0), _mat(colors[k], 0.4), cab)
		_box(Vector3(0.23, 0.06, 0.17), Vector3(0, -0.11, 0), _mat(Color("#dff9fb"), 0.1), cab)
		_cyl(0.008, 0.008, 0.12, Vector3(0, -0.02, 0), _mat(INK), cab)
		_cabins.append({"node": cab, "a": a + Vector3(0, 1.64, 0), "b": b + Vector3(0, 1.64, 0), "phase": k / 3.0})


func _build_cars(ring: float) -> void:
	var colors := [Color("#e84393"), Color("#0984e3"), Color("#fdcb6e"), Color("#00cec9")]
	for k in 4:
		var car := Node3D.new()
		add_child(car)
		_box(Vector3(0.26, 0.08, 0.14), Vector3(0, 0.1, 0), _mat(colors[k], 0.3, 0.2), car)
		_box(Vector3(0.14, 0.07, 0.12), Vector3(-0.02, 0.17, 0), _mat(Color("#dff9fb"), 0.1), car)
		_cars.append({"node": car, "phase": k / 4.0, "ring": ring, "lane": 0.12 if k % 2 == 0 else -0.12})


func _build_dice() -> void:
	for k in 3:
		var die := Node3D.new()
		var speed := k == 2
		_box(Vector3(DIE, DIE, DIE), Vector3.ZERO, _mat(Color("#d63031") if speed else Color.WHITE, 0.25), die)
		if speed:
			var faces := [["1", Vector3.UP], ["2", Vector3.RIGHT], ["3", Vector3.BACK], ["»", Vector3.FORWARD], ["»", Vector3.LEFT], ["$", Vector3.DOWN]]
			for f in faces:
				var l := Label3D.new()
				l.text = f[0]
				l.font = _font
				l.font_size = 72
				l.pixel_size = 0.004
				l.position = f[1] * (DIE / 2.0 + 0.002)
				l.look_at_from_position(l.position, l.position * 2.0, Vector3.UP if absf(f[1].y) < 0.9 else Vector3.FORWARD)
				l.rotate_object_local(Vector3.UP, PI)
				die.add_child(l)
		else:
			_add_pips(die)
		die.position = Vector3((k - 1) * 0.6, TOP + DIE / 2.0, 3.75)
		die.visible = k < 2
		add_child(die)
		_dice.append(die)


func _add_pips(die: Node3D) -> void:
	# +Y=1, +X=2, +Z=3, -Z=4, -X=5, -Y=6
	var faces := [[1, Vector3.UP], [2, Vector3.RIGHT], [3, Vector3.BACK], [4, Vector3.FORWARD], [5, Vector3.LEFT], [6, Vector3.DOWN]]
	var o := 0.1
	var layouts := {
		1: [Vector2.ZERO], 2: [Vector2(-o, -o), Vector2(o, o)], 3: [Vector2(-o, -o), Vector2.ZERO, Vector2(o, o)],
		4: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, o), Vector2(o, o)],
		5: [Vector2(-o, -o), Vector2(o, -o), Vector2.ZERO, Vector2(-o, o), Vector2(o, o)],
		6: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, 0), Vector2(o, 0), Vector2(-o, o), Vector2(o, o)],
	}
	var pip_mesh := SphereMesh.new()
	pip_mesh.radius = 0.034
	pip_mesh.height = 0.068
	for f in faces:
		var n: Vector3 = f[1]
		var u := Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.BACK
		var v := n.cross(u)
		var pip_mat := _mat(Color("#d63031") if f[0] == 1 else INK, 0.4)
		for p in layouts[f[0]]:
			var mi := MeshInstance3D.new()
			mi.mesh = pip_mesh
			mi.material_override = pip_mat
			mi.position = n * (DIE / 2.0 - 0.014) + u * p.x + v * p.y
			die.add_child(mi)


static func _face_up_rotation(v: int) -> Vector3:
	match v:
		2: return Vector3(0, 0, PI / 2.0)
		3: return Vector3(-PI / 2.0, 0, 0)
		4: return Vector3(PI / 2.0, 0, 0)
		5: return Vector3(0, 0, -PI / 2.0)
		6: return Vector3(PI, 0, 0)
	return Vector3.ZERO


# ---------------------------------------------------------------------------
# Estado: dueños, hipotecas y edificios
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if controller == null or controller.engine == null:
		return
	var e := controller.engine
	var b := controller.board
	for i in b.size():
		if not b.is_property(i):
			continue
		_update_owner(i, e.owner_of(i), e.is_mortgaged(i))
		_update_buildings(i, e.houses_on(i))
	for p in e.players():
		var tok: Node3D = _tokens.get(int(p["id"]))
		if tok:
			tok.visible = not p["bankrupt"]


func _update_owner(i: int, own: int, mortgaged: bool) -> void:
	var r := BoardLayout.rect(i)
	var outward := -BoardLayout.inward(i)
	if not _owner_marks.has(i):
		var horizontal := BoardLayout.side(i) % 2 == 0
		var size := Vector3(r.size.x - 0.1, 0.03, 0.14) if horizontal else Vector3(0.14, 0.03, r.size.y - 0.1)
		var pos := r.get_center() + outward * (BoardLayout.CORNER / 2.0 - 0.1)
		_owner_marks[i] = _box(size, _w(pos, TOP + 0.01), _mat(Color.WHITE))
		_mortgage_marks[i] = _box(Vector3(r.size.x - 0.08, 0.01, r.size.y - 0.08), _w(r.get_center(), TOP + 0.03), _veil())
	var mark: MeshInstance3D = _owner_marks[i]
	var was_visible := mark.visible
	mark.visible = own >= 0
	if own >= 0:
		mark.material_override = _mat(Color.html(controller.engine.player(own)["color"]), 0.3)
		if not was_visible and _animate_buildings:
			mark.scale = Vector3(0.1, 1, 0.1)
			create_tween().tween_property(mark, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_mortgage_marks[i].visible = mortgaged


func _veil() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.4, 0.45, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Sincroniza los edificios de una casilla; los cambios se animan como una obra.
func _update_buildings(i: int, h: int) -> void:
	var want_kind := "hotel" if h == GameEngine.HOTEL else "houses"
	var want := 1 if h == GameEngine.HOTEL else h
	var cur: Dictionary = _units.get(i, {"kind": "houses", "nodes": []})
	_units[i] = cur
	var nodes: Array = cur["nodes"]
	if cur["kind"] != want_kind:
		for n in nodes:
			_demolish(n)
		nodes.clear()
		cur["kind"] = want_kind
	while nodes.size() > want:
		_demolish(nodes.pop_back())
	var br := BoardLayout.band_rect(i)
	var c := br.get_center()
	var along := Vector2(1, 0) if BoardLayout.side(i) % 2 == 0 else Vector2(0, 1)
	var yaw := 0.0 if BoardLayout.side(i) % 2 == 0 else PI / 2.0
	var k := nodes.size()
	while nodes.size() < want:
		var unit: Node3D
		if want_kind == "hotel":
			unit = _building(_w(c, TOP + 0.05), Vector3(0.56, 0.26, 0.26), Color("#e74c3c"), yaw)
		else:
			var p := c + along * (k - 1.5) * 0.23
			unit = _building(_w(p, TOP + 0.05), Vector3(0.17, 0.15, 0.17), Color("#27ae60"), yaw)
		nodes.append(unit)
		if _animate_buildings:
			_construct(unit, k * 0.1)
		k += 1


func _building(base: Vector3, size: Vector3, color: Color, yaw: float) -> Node3D:
	var node := Node3D.new()
	node.position = base
	node.rotation.y = yaw
	add_child(node)
	var body := Node3D.new()
	body.name = "Body"
	node.add_child(body)
	_box(size, Vector3(0, size.y / 2.0, 0), _mat(color, 0.35), body)
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x * 1.08, size.y * 0.75, size.z * 1.08)
	roof.mesh = prism
	roof.material_override = _mat(color.darkened(0.25), 0.4)
	roof.position = Vector3(0, size.y + size.y * 0.375, 0)
	roof.rotation.y = PI / 2.0
	body.add_child(roof)
	_box(Vector3(size.x * 0.25, size.y * 0.45, 0.01), Vector3(0, size.y * 0.22, size.z / 2.0 + 0.004), _mat(Color("#fff3c4"), 0.5), body)
	node.set_meta("size", size)
	return node


## Obra: aparece el andamio, el edificio crece desde el suelo con polvo y se retira el andamio.
func _construct(node: Node3D, delay: float) -> void:
	var size: Vector3 = node.get_meta("size")
	var body: Node3D = node.get_node("Body")
	body.scale = Vector3(1, 0.001, 1)
	var scaffold := Node3D.new()
	node.add_child(scaffold)
	var pole := _mat(Color("#f9ca24"), 0.5)
	var h := size.y * 1.9
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.012, h, 0.012), Vector3(sx * (size.x / 2 + 0.02), h / 2, sz * (size.z / 2 + 0.02)), pole, scaffold)
	for y in [h * 0.35, h * 0.7, h]:
		_box(Vector3(size.x + 0.05, 0.012, 0.012), Vector3(0, y, size.z / 2 + 0.02), pole, scaffold)
		_box(Vector3(size.x + 0.05, 0.012, 0.012), Vector3(0, y, -size.z / 2 - 0.02), pole, scaffold)
	scaffold.scale = Vector3(1, 0.001, 1)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(scaffold, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _dust(node.global_position, size.x))
	tw.tween_property(body, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(scaffold, "scale", Vector3(1, 0.001, 1), 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(scaffold.queue_free)


func _demolish(node: Node3D) -> void:
	if not _animate_buildings:
		node.queue_free()
		return
	_dust(node.global_position, 0.2)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.1, 0.001, 1.1), 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(node.queue_free)


func _dust(pos: Vector3, spread: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 18
	p.lifetime = 0.8
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -0.6, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread * 0.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.88, 0.78, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.position = pos + Vector3(0, 0.05, 0)
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


# ---------------------------------------------------------------------------
# Eventos y animación
# ---------------------------------------------------------------------------

func _on_event(ev: Dictionary) -> void:
	match ev["type"]:
		"dice_rolled":
			_throw_dice(ev["dice"])
		"moved":
			var pid := int(ev["player"])
			for i in ev["path"]:
				_anim[pid]["queue"].append(BoardLayout.rect(int(i)).get_center())
			if cinematic:
				_follow = pid
		"jailed":
			_anim[int(ev["player"])]["queue"].append(BoardLayout.rect(int(ev["space"])).get_center())
		"landed":
			_highlight(int(ev["space"]))
		"turn_started":
			if cinematic:
				_focus_player(int(ev["player"]))


func _highlight(i: int) -> void:
	var r := BoardLayout.rect(i)
	_glow.mesh.size = Vector3(r.size.x - 0.04, 0.02, r.size.y - 0.04)
	_glow.position = _w(r.get_center(), TOP + 0.05)
	_glow.visible = true
	_glow.transparency = 0.0
	var tw := create_tween()
	tw.tween_property(_glow, "transparency", 0.7, 0.4)
	tw.tween_property(_glow, "transparency", 0.0, 0.4)
	tw.tween_property(_glow, "transparency", 1.0, 0.6)
	tw.tween_callback(func(): _glow.visible = false)


func _on_drained() -> void:
	_follow = -1
	_cam_target = Vector3.ZERO
	_cam_dist = 15.0
	_refresh()


func _focus_player(pid: int) -> void:
	if not _tokens.has(pid):
		return
	var pos: int = controller.player_events.shown_pos.get(pid, 0)
	_cam_yaw = [0.0, -PI / 2.0, PI, PI / 2.0][BoardLayout.side(pos)]


func _throw_dice(values: Array) -> void:
	if _dice_tween and _dice_tween.is_running():
		_dice_tween.kill()
	var count := 3 if int(values[2]) > 0 else 2
	_dice_tween = create_tween().set_parallel(true)
	for k in 3:
		var die: Node3D = _dice[k]
		die.visible = k < count
		if k >= count:
			continue
		var v := int(values[k])
		if k == 2:
			v = {1: 1, 2: 2, 3: 3, GameEngine.SPEED_BOLT: 4, GameEngine.SPEED_STAR: 6}.get(v, 1)
		var end := Vector3((k - (count - 1) / 2.0) * 0.65 + _rng.randf_range(-0.1, 0.1), TOP + DIE / 2.0, 3.75 + _rng.randf_range(-0.08, 0.08))
		var start := end + Vector3(_rng.randf_range(-1.5, 1.5), 2.4, 1.6)
		var final_rot := _face_up_rotation(v) + Vector3(0, _rng.randf_range(-0.4, 0.4), 0)
		var spin := Vector3(_rng.randf_range(8, 16), _rng.randf_range(-6, 6), _rng.randf_range(8, 16)) * (1 if _rng.randf() < 0.5 else -1)
		_dice_tween.tween_method(func(t: float):
			var xz := start.lerp(end, 1.0 - pow(1.0 - t, 2.0))
			var fall := maxf(0.0, 1.0 - t * 3.0) * (start.y - end.y)
			var bounce := absf(sin(t * PI * 3.0)) * (1.0 - t) * 0.6 if t > 0.33 else 0.0
			die.position = Vector3(xz.x, end.y + fall + bounce, xz.z)
			var u := (1.0 - t) * (1.0 - t)
			die.rotation = Vector3(final_rot.x + spin.x * u, final_rot.y + spin.y * u, final_rot.z + spin.z * u)
		, 0.0, 1.0, EventPlayer.DICE_TIME * 0.85)


func _snap_tokens() -> void:
	if controller == null or controller.engine == null:
		return
	for pid in _anim:
		_anim[pid]["queue"].clear()
		_anim[pid]["pos"] = _rest_point(pid)
		_anim[pid]["from"] = _anim[pid]["pos"]
		_place_token(pid, 0.0, 1.0)


func _rest_point(pid: int) -> Vector2:
	var e := controller.engine
	var shown: Dictionary = controller.player_events.shown_pos
	var space: int = shown.get(pid, e.player(pid)["pos"])
	var here := []
	for p in e.players():
		if not p["bankrupt"] and int(shown.get(int(p["id"]), p["pos"])) == space:
			here.append(int(p["id"]))
	return BoardLayout.token_point(space, maxi(0, here.find(pid)), here.size())


func _place_token(pid: int, hop: float, squash: float) -> void:
	var tok: Node3D = _tokens[pid]
	tok.position = _w(_anim[pid]["pos"], TOP + 0.02 + hop)
	tok.scale = Vector3(1.5 / sqrt(squash), 1.5 * squash, 1.5 / sqrt(squash))


func _process(delta: float) -> void:
	_time += delta
	_animate_city()
	if controller == null or controller.engine == null:
		return
	for pid in _anim:
		var a: Dictionary = _anim[pid]
		var hop := 0.0
		var squash := 1.0
		if not a["queue"].is_empty():
			a["t"] += delta / EventPlayer.STEP_TIME
			var target: Vector2 = a["queue"][0]
			var t := minf(a["t"], 1.0)
			a["pos"] = a["from"].lerp(target, t)
			hop = sin(t * PI) * 0.45
			squash = 1.0 + 0.18 * sin(t * PI) - (0.22 if t > 0.92 else 0.0)
			var dir: Vector2 = target - a["from"]
			if dir.length() > 0.01:
				_tokens[pid].rotation.y = lerp_angle(_tokens[pid].rotation.y, atan2(-dir.x, -dir.y), minf(1.0, delta * 14.0))
			if a["t"] >= 1.0:
				a["from"] = target
				a["t"] = 0.0
				a["queue"].pop_front()
		else:
			var rest := _rest_point(pid)
			a["pos"] = a["pos"].lerp(rest, minf(1.0, delta * 8.0))
			a["from"] = a["pos"]
		_place_token(pid, hop, squash)
	if _follow >= 0 and _tokens.has(_follow):
		var tp: Vector3 = _tokens[_follow].position
		_cam_target = tp * 0.8
		_cam_dist = 9.0
		var space := BoardLayout.space_at(_anim[_follow]["pos"])
		if space >= 0:
			_cam_yaw = [0.0, -PI / 2.0, PI, PI / 2.0][BoardLayout.side(space)]
	_update_camera(delta)


func _animate_city() -> void:
	for c in _cabins:
		var t := fposmod(_time * 0.05 + c["phase"], 1.0)
		var ping := t * 2.0 if t < 0.5 else 2.0 - t * 2.0
		var p: Vector3 = c["a"].lerp(c["b"], ping)
		c["node"].position = p + Vector3(0, -0.12 * sin(ping * PI), 0)
	for car in _cars:
		var ring: float = car["ring"]
		var t := fposmod(_time * 0.04 + car["phase"], 1.0) * 4.0
		var side := mini(int(t), 3)
		var f := t - side
		var corners := [Vector2(-ring, ring), Vector2(ring, ring), Vector2(ring, -ring), Vector2(-ring, -ring), Vector2(-ring, ring)]
		var lane: float = car["lane"]
		var p: Vector2 = corners[side].lerp(corners[side + 1], f)
		var dir: Vector2 = (corners[side + 1] - corners[side]).normalized()
		p += Vector2(-dir.y, dir.x) * lane
		car["node"].position = Vector3(p.x, 0.04, p.y)
		car["node"].rotation.y = atan2(-dir.y, dir.x)


func _update_camera(delta: float) -> void:
	var k := minf(1.0, delta * 3.0)
	_cur_target = _cur_target.lerp(_cam_target, k)
	_cur_dist = lerpf(_cur_dist, _cam_dist, k)
	_cur_yaw = lerp_angle(_cur_yaw, _cam_yaw, minf(1.0, delta * 2.0))
	_cur_pitch = lerpf(_cur_pitch, _cam_pitch, k)
	var offset := Vector3(sin(_cur_yaw) * cos(_cur_pitch), sin(_cur_pitch), cos(_cur_yaw) * cos(_cur_pitch)) * _cur_dist
	camera.position = _cur_target + offset
	camera.look_at(_cur_target, Vector3.UP)


# ---------------------------------------------------------------------------
# Entrada: clic en casillas, órbita con arrastre, zoom con rueda o pellizco.
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist = clampf(_cam_dist - 0.8, 5.0, 24.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist = clampf(_cam_dist + 0.8, 5.0, 24.0)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_left_down = true
					_dragging = event.button_index == MOUSE_BUTTON_RIGHT
					_press_pos = event.position
				else:
					if not _dragging and event.button_index == MOUSE_BUTTON_LEFT:
						_pick(event.position)
					_left_down = false
					_dragging = false
	elif event is InputEventMouseMotion and _left_down:
		if not _dragging and event.position.distance_to(_press_pos) > 8.0:
			_dragging = true
		if _dragging:
			_orbit(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag and _touches.size() == 2:
		var other := -1
		for idx in _touches:
			if idx != event.index:
				other = idx
		if other >= 0:
			var before: float = _touches[event.index].distance_to(_touches[other])
			var after: float = event.position.distance_to(_touches[other])
			_cam_dist = clampf(_cam_dist * before / maxf(after, 1.0), 5.0, 24.0)
		_touches[event.index] = event.position
	elif event is InputEventMagnifyGesture:
		_cam_dist = clampf(_cam_dist / event.factor, 5.0, 24.0)


func _orbit(rel: Vector2) -> void:
	_follow = -1
	_cam_yaw -= rel.x * 0.006
	_cam_pitch = clampf(_cam_pitch + rel.y * 0.004, deg_to_rad(18), deg_to_rad(85))


func _pick(screen: Vector2) -> void:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return
	var t := (TOP - from.y) / dir.y
	if t <= 0.0:
		return
	var hit := from + dir * t
	var i := BoardLayout.space_at(Vector2(hit.x + S / 2.0, hit.z + S / 2.0))
	if i >= 0:
		space_clicked.emit(i)
