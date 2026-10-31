class_name BoardView3D
extends Node3D
## Vista 3D: tablero con casillas de color, carteles con fotos de los lugares que miran a la cámara,
## ciudad detallada y animada, fichas con saltos, obras animadas, haz de luz con el resultado de los
## dados, monedas al cobrar y cartas que salen del mazo.

signal space_clicked(index: int)

const S := BoardLayout.SIZE
const TOP := 0.06
const DIE := 0.4
const PAPER := Color("#fbf8f1")
const INK := Color("#13233f")
const RIM := Color("#13233f")
const TRIM := Color("#f2a541")
const TABLE := Color("#1d5c4f")
const LAWN := Color("#8cc56a")
const LAWN_2 := Color("#6fae55")
const ROAD := Color("#4a5260")
const SIDEWALK := Color("#d8d4cc")
const CORNER_COLORS := {"go": Color("#bfeedd"), "jail": Color("#ffe2b8"), "free": Color("#cfe3ff"), "gotojail": Color("#ffc9c4")}
const FACADES := [Color("#f4e3c1"), Color("#e9c9a8"), Color("#cfd8e3"), Color("#f2d0c4"), Color("#d9e6d3"), Color("#f6efe4"), Color("#e3d5f0")]
const ROOFS := [Color("#b5523b"), Color("#8f3f2f"), Color("#5c6b7a"), Color("#3f6f5a")]

var controller: GameController
var active := true
var cinematic := true

var camera: Camera3D
var _cam_yaw := 0.0
var _cam_pitch := deg_to_rad(48.0)
var _cam_dist := 15.0
var _cam_target := Vector3.ZERO
var _cur_yaw := 0.0
var _cur_pitch := deg_to_rad(48.0)
var _cur_dist := 15.0
var _cur_target := Vector3.ZERO
var _follow := -1

var _tokens: Dictionary = {}        # pid -> Node3D
var _anim: Dictionary = {}          # pid -> {pos, from, queue, t}
var _units: Dictionary = {}         # casilla -> {"kind": "houses"|"hotel", "nodes": Array}
var _owner_marks: Dictionary = {}
var _mortgage_marks: Dictionary = {}
var _signs: Array = []              # {node, outward: Vector3, space, frame, price}
var _sign_of: Dictionary = {}       # casilla -> entrada de _signs
var _flags: Array = []              # banderines de dueño que ondean
var _glow: MeshInstance3D
var _dice: Array = []
var _dice_tween: Tween
var _beam: Node3D
var _beam_label: Label3D
var _beam_sub: Label3D
var _mats: Dictionary = {}
var _font: SystemFont
var _rng := RandomNumberGenerator.new()
var _animate_buildings := false

var _cabins: Array = []
var _cars: Array = []
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
	_build_beam()
	_glow = _box(Vector3(1, 0.02, 1), Vector3.ZERO, _glow_material())
	_glow.visible = false
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.far = 200.0
	add_child(camera)
	_update_camera(1.0)


func bind(c: GameController) -> void:
	controller = c
	# Mientras se reproducen eventos, el tablero no se adelanta: cada casilla cambia con su evento.
	controller.state_changed.connect(func(): if not controller.player_events.is_busy(): _refresh())
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
	m.radial_segments = 14
	m.rings = 7
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _prism(size: Vector3, pos: Vector3, mat: Material, yaw: float = 0.0, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := PrismMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi


func _label(text: String, pos: Vector3, angle: float, font_size: int, width_units: float, color: Color = INK, parent: Node = self) -> Label3D:
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
	parent.add_child(l)
	return l


func _glow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.35, 0.6)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.3)
	m.emission_energy_multiplier = 1.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _window_material(tint: Color, glass: bool = false) -> StandardMaterial3D:
	var key := "win_%s_%s" % [tint.to_html(), glass]
	if _mats.has(key):
		return _mats[key]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var pane := Color("#9cc4e4") if not glass else Color("#5d8fbf")
	for y in range(6, 26):
		for x in range(5, 27):
			if (x < 15 or x > 16) and (y < 15 or y > 16):
				img.set_pixel(x, y, pane.lerp(Color.WHITE, 0.25 * float(y - 6) / 20.0))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(3.6, 3.6, 3.6)
	m.roughness = 0.12 if glass else 0.55
	m.metallic = 0.45 if glass else 0.0
	_mats[key] = m
	return m


func _noise_material(a: Color, b: Color, scale: float, rough: float = 0.9) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.noise = noise
	var grad := Gradient.new()
	grad.set_color(0, b)
	grad.set_color(1, a)
	tex.color_ramp = grad
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = rough
	return m


# ---------------------------------------------------------------------------
# Entorno y tablero
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#4f8fd6")
	sky_mat.sky_horizon_color = Color("#d9e9f7")
	sky_mat.ground_horizon_color = Color("#d9e9f7")
	sky_mat.ground_bottom_color = Color("#2b4a5c")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(32), 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 35.0
	add_child(sun)


func _tile_color(board: Board, i: int) -> Color:
	var sp := board.space(i)
	match sp["type"]:
		"street":
			return board.space_color(i).lerp(Color.WHITE, 0.8)
		"transit":
			return Color("#e2e9f2")
		"utility":
			return Color("#fff1c9")
		"card":
			return UiKit.DESTINO.lerp(Color.WHITE, 0.35) if sp["deck"] == "destino" else UiKit.CABILDO.lerp(Color.WHITE, 0.45)
		"tax":
			return Color("#ffdcdc")
	return CORNER_COLORS.get(sp["type"], PAPER)


func _build_board() -> void:
	var board := Board.load_from_file(GameController.BOARD_PATH)
	# Mesa de paño verde, marco azul marino con filete dorado
	_cyl(16.0, 16.0, 0.3, Vector3(0, -0.5, 0), _noise_material(TABLE.lightened(0.08), TABLE.darkened(0.12), 0.6), self, 64)
	_box(Vector3(S + 0.8, 0.32, S + 0.8), Vector3(0, -0.2, 0), _mat(RIM, 0.3, 0.1))
	_box(Vector3(S + 0.36, 0.05, S + 0.36), Vector3(0, -0.02, 0), _mat(TRIM, 0.3, 0.6))
	_box(Vector3(S + 0.24, 0.06, S + 0.24), Vector3(0, -0.01, 0), _mat(Color("#d7dde5"), 0.6))
	for i in board.size():
		var sp := board.space(i)
		var r := BoardLayout.rect(i)
		var ang := BoardLayout.text_angle(i)
		var inward := BoardLayout.inward(i)
		var corner := BoardLayout.is_corner(i)
		_box(Vector3(r.size.x - 0.05, 0.05, r.size.y - 0.05), _w(r.get_center(), 0.03), _mat(_tile_color(board, i), 0.65))
		var along := (BoardLayout.CORNER if corner else BoardLayout.CELL) - 0.12
		var ty := TOP + 0.002
		if sp["type"] == "street":
			var br := BoardLayout.band_rect(i)
			_box(Vector3(br.size.x - 0.05, 0.08, br.size.y - 0.05), _w(br.get_center(), 0.07), _mat(board.space_color(i), 0.25, 0.1))
		var photo := UiKit.place_photo(i, sp["name"])
		if corner:
			var names := {"go": "SALIDA\n+Bs %d" % board.salary, "jail": "RETÉN", "free": "MIRADOR", "gotojail": "¡AL\nRETÉN!"}
			if photo:
				# Esquina con foto de fondo (cárcel, policía, mirador...) y un velo claro para leer el texto.
				_tile_photo(photo, _w(r.get_center(), TOP + 0.001), ang, Vector2(along, along), Color(1, 1, 1, 0.82))
			var cl := _label(names.get(sp["type"], sp["name"]), _w(r.get_center(), ty + 0.002), ang + PI / 4.0, 64, along * 1.2, INK)
			if photo:
				cl.outline_size = 16
				cl.outline_modulate = Color.WHITE
			_corner_prop(sp["type"], _w(r.get_center(), TOP), ang)
			continue
		var name_pos := r.get_center() + inward * (BoardLayout.CORNER / 2.0 - BoardLayout.BAND - 0.25)
		if photo:
			# Mini foto del lugar bajo la franja de color; el nombre va debajo de la foto.
			var top_edge := BoardLayout.CORNER / 2.0 - (BoardLayout.BAND if sp["type"] == "street" else 0.06) - 0.05
			var depth := 0.4
			_tile_photo(photo, _w(r.get_center() + inward * (top_edge - depth / 2.0), ty), ang, Vector2(along - 0.06, depth), Color.WHITE)
			name_pos = r.get_center() + inward * (top_edge - depth - 0.13)
		_label(String(sp["name"]).to_upper(), _w(name_pos, ty), ang, 30, along)
		var sub := ""
		var sub_color := INK
		if board.is_property(i):
			sub = "Bs %d" % board.price(i)
			sub_color = Color("#1f7a68")
		elif sp["type"] == "tax":
			sub = "PAGA Bs %d" % int(sp["amount"])
			sub_color = Color("#c0392b")
		if sub != "":
			_label(sub, _w(r.get_center() - inward * 0.55, ty), ang, 38, along, sub_color)
		if sp["type"] == "card":
			var destino: bool = sp["deck"] == "destino"
			_label("?" if destino else "!", _w(r.get_center() - inward * 0.15, ty), ang, 110, along, Color.WHITE)
		_build_sign(board, i)


## Foto plana sobre la casilla, con marco blanco y recorte centrado (no se deforma).
func _tile_photo(tex: Texture2D, pos: Vector3, angle: float, size: Vector2, tint: Color) -> void:
	var frame := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = size + Vector2(0.04, 0.04)
	frame.mesh = fq
	frame.material_override = _mat(Color.WHITE, 0.8)
	frame.position = pos
	frame.rotation = Vector3(-PI / 2.0, -angle, 0.0)
	add_child(frame)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var aspect := float(tex.get_width()) / maxf(1.0, tex.get_height())
	var want := size.x / size.y
	if aspect > want:
		m.uv1_scale = Vector3(want / aspect, 1, 1)
		m.uv1_offset = Vector3((1.0 - want / aspect) / 2.0, 0, 0)
	else:
		m.uv1_scale = Vector3(1, aspect / want, 1)
		m.uv1_offset = Vector3(0, (1.0 - aspect / want) / 2.0, 0)
	mi.material_override = m
	mi.position = Vector3(0, 0, 0.001)
	frame.add_child(mi)
	if tint.a < 1.0:
		var veil := MeshInstance3D.new()
		var vq := QuadMesh.new()
		vq.size = size
		veil.mesh = vq
		var vm := StandardMaterial3D.new()
		vm.albedo_color = Color(1, 1, 1, 1.0 - tint.a)
		vm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		veil.material_override = vm
		veil.position = Vector3(0, 0, 0.002)
		frame.add_child(veil)


## Detalle 3D en cada esquina.
func _corner_prop(kind: String, pos: Vector3, ang: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = -ang
	add_child(n)
	match kind:
		"go":
			var arrow := _prism(Vector3(0.5, 0.06, 0.4), Vector3(0.45, 0.04, 0.45), _mat(Color("#e8735a"), 0.3), PI / 4.0, n)
			arrow.rotation = Vector3(PI / 2.0, PI * 0.75, 0)
		"jail":
			for k in 5:
				_cyl(0.015, 0.015, 0.45, Vector3(-0.5 + k * 0.08, 0.23, -0.5), _mat(Color("#5c6b7a"), 0.3, 0.8), n)
			_box(Vector3(0.42, 0.03, 0.03), Vector3(-0.34, 0.45, -0.5), _mat(Color("#5c6b7a"), 0.3, 0.8), n)
		"free":
			_cyl(0.02, 0.02, 0.5, Vector3(0.45, 0.25, 0.45), _mat(Color("#dfe6e9"), 0.4), n)
			_box(Vector3(0.24, 0.24, 0.02), Vector3(0.45, 0.55, 0.45), _mat(Color("#3d6fd6"), 0.3), n)
		"gotojail":
			_cyl(0.13, 0.15, 0.18, Vector3(0.45, 0.09, 0.45), _mat(Color("#13233f"), 0.3), n)
			_sphere(0.1, Vector3(0.45, 0.25, 0.45), _mat(Color("#d64550"), 0.2), n)


func _place_texture(board: Board, i: int) -> Texture2D:
	var photo := UiKit.place_photo(i, board.space(i)["name"])
	if photo:
		return photo
	# Sin foto: degradado con el color del grupo.
	var g := Gradient.new()
	var base := board.space_color(i) if board.space(i).has("group") else Color("#3d6fd6")
	if board.space(i)["type"] == "card":
		base = Color("#e8735a") if board.space(i)["deck"] == "destino" else Color("#3d6fd6")
	elif board.space(i)["type"] == "tax":
		base = Color("#d64550")
	g.set_color(0, base.lightened(0.25))
	g.set_color(1, base.darkened(0.25))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	return tex


## Cartel publicitario: foto del lugar + franja con nombre y precio. Gira hacia la cámara.
func _build_sign(board: Board, i: int) -> void:
	var sp := board.space(i)
	var r := BoardLayout.rect(i)
	var outward := -BoardLayout.inward(i)
	var base := _w(r.get_center() + outward * (BoardLayout.CORNER / 2.0 + 0.3), 0.0)
	var root := Node3D.new()
	root.position = base
	add_child(root)
	_cyl(0.025, 0.03, 0.55, Vector3(0, 0.27, 0), _mat(Color("#7f8c99"), 0.3, 0.7), root)
	var panel := Node3D.new()
	panel.name = "Panel"
	panel.position = Vector3(0, 0.82, 0)
	root.add_child(panel)
	var group_col := board.space_color(i) if sp.has("group") and board.groups.has(sp["group"]) else (Color("#3d6fd6") if sp["type"] != "tax" else Color("#d64550"))
	if sp["type"] == "card":
		group_col = Color("#e8735a") if sp["deck"] == "destino" else Color("#3d6fd6")
	var frame := _box(Vector3(0.98, 0.7, 0.04), Vector3.ZERO, _mat(INK, 0.3), panel)
	var photo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.44)
	photo.mesh = quad
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = _place_texture(board, i)
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	photo.material_override = pm
	photo.position = Vector3(0, 0.1, 0.022)
	panel.add_child(photo)
	_box(Vector3(0.9, 0.17, 0.01), Vector3(0, -0.24, 0.022), _mat(group_col, 0.3), panel)
	var title := Label3D.new()
	title.text = String(sp["name"]).to_upper()
	title.font = _font
	title.font_size = 34
	title.pixel_size = 0.0032
	title.outline_size = 8
	title.outline_modulate = Color(0, 0, 0, 0.35)
	title.modulate = Color.WHITE if group_col.get_luminance() < 0.6 else INK
	title.position = Vector3(0, -0.24, 0.03)
	title.width = 0.88 / title.pixel_size
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	if board.is_property(i):
		var price := Label3D.new()
		price.text = "Bs %d" % board.price(i)
		price.font = _font
		price.font_size = 30
		price.pixel_size = 0.0032
		price.outline_size = 10
		price.outline_modulate = INK
		price.modulate = TRIM
		price.position = Vector3(0.3, 0.27, 0.03)
		panel.add_child(price)
		var entry := {"node": root, "outward": Vector3(outward.x, 0, outward.y), "space": i, "frame": frame, "price": price, "panel": panel}
		_signs.append(entry)
		_sign_of[i] = entry
		return
	_signs.append({"node": root, "outward": Vector3(outward.x, 0, outward.y)})


func _build_city() -> void:
	var inner := S - BoardLayout.CORNER * 2.0 - 0.1
	_box(Vector3(inner, 0.04, inner), Vector3(0, 0.02, 0), _noise_material(LAWN, LAWN_2, 0.9))
	var ring := 3.0
	var road := _noise_material(ROAD.lightened(0.05), ROAD.darkened(0.1), 2.0, 0.85)
	var walk := _mat(SIDEWALK, 0.8)
	# Aceras (bordes claros) bajo las avenidas
	for k in 4:
		var horizontal := k % 2 == 0
		var off := ring if k < 2 else -ring
		var size := Vector3(ring * 2 + 0.8, 0.03, 0.78) if horizontal else Vector3(0.78, 0.03, ring * 2 + 0.8)
		_box(size, Vector3(0, 0.05, off) if horizontal else Vector3(off, 0.05, 0), walk)
	_box(Vector3(0.72, 0.03, ring * 2), Vector3(0, 0.05, 0), walk)
	_box(Vector3(ring * 2, 0.03, 0.72), Vector3(0, 0.05, 0), walk)
	for k in 4:
		var horizontal := k % 2 == 0
		var off := ring if k < 2 else -ring
		var size := Vector3(ring * 2 + 0.5, 0.02, 0.5) if horizontal else Vector3(0.5, 0.02, ring * 2 + 0.5)
		_box(size, Vector3(0, 0.065, off) if horizontal else Vector3(off, 0.065, 0), road)
	_box(Vector3(0.45, 0.02, ring * 2), Vector3(0, 0.065, 0), road)
	_box(Vector3(ring * 2, 0.02, 0.45), Vector3(0, 0.065, 0), road)
	var dash := _mat(Color("#f4f1e8"), 0.5)
	var yellow := _mat(Color("#f2c14e"), 0.5)
	for k in range(-5, 6):
		_box(Vector3(0.18, 0.005, 0.03), Vector3(k * 0.55, 0.077, ring), dash)
		_box(Vector3(0.18, 0.005, 0.03), Vector3(k * 0.55, 0.077, -ring), dash)
		_box(Vector3(0.03, 0.005, 0.18), Vector3(ring, 0.077, k * 0.55), dash)
		_box(Vector3(0.03, 0.005, 0.18), Vector3(-ring, 0.077, k * 0.55), dash)
	_box(Vector3(0.02, 0.005, ring * 2 - 0.6), Vector3(0, 0.077, 0), yellow)
	_box(Vector3(ring * 2 - 0.6, 0.005, 0.02), Vector3(0, 0.077, 0), yellow)
	# Pasos de cebra en los cruces del anillo
	for c in [Vector2(0, ring), Vector2(0, -ring), Vector2(ring, 0), Vector2(-ring, 0)]:
		for s in range(-3, 4):
			var vertical := absf(c.x) < 0.1
			var p := Vector3(c.x + (s * 0.07 if vertical else (0.32 if c.x < 0 else -0.32)), 0.078, c.y + ((0.32 if c.y < 0 else -0.32) if vertical else s * 0.07))
			_box(Vector3(0.04, 0.004, 0.16) if vertical else Vector3(0.16, 0.004, 0.04), p, dash)
	# Faroles a lo largo del anillo
	for k in range(-2, 3):
		for side in [-1, 1]:
			_streetlight(Vector3(k * 1.3, 0.06, side * (ring - 0.34)))
			_streetlight(Vector3(side * (ring - 0.34), 0.06, k * 1.3))
	_district_downtown(Vector2(-1.5, -1.5))
	_district_houses(Vector2(1.5, -1.5))
	_district_park(Vector2(-1.5, 1.5))
	_district_mixed(Vector2(1.5, 1.5))
	_plaza()
	_mountains()
	_build_cable_car()
	_build_cars(ring)
	# Mazos de cartas
	for k in 2:
		var pos := Vector3(-3.65, 0, 3.65) if k == 0 else Vector3(3.65, 0, -3.65)
		var col := Color("#e8735a") if k == 0 else Color("#3d6fd6")
		for layer in 4:
			var card := _box(Vector3(1.2, 0.04, 0.8), pos + Vector3(0, 0.08 + layer * 0.045, 0), _mat(col.lightened(0.05 * layer), 0.35))
			card.rotation.y = PI / 4.0 + layer * 0.03
		_label("DESTINO ?" if k == 0 else "CABILDO !", pos + Vector3(0, 0.265, 0), -PI / 4.0, 44, 1.1, Color.WHITE)
	_box(Vector3(2.3, 0.12, 0.5), Vector3(2.35, 0.1, 3.75), _mat(INK, 0.3))
	_box(Vector3(2.36, 0.02, 0.56), Vector3(2.35, 0.04, 3.75), _mat(TRIM, 0.3, 0.6))
	var logo := _label("LUCHOPOLIS", Vector3(2.35, 0.165, 3.75), 0.0, 76, 2.2, TRIM)
	logo.outline_size = 0


func _streetlight(pos: Vector3) -> void:
	_cyl(0.008, 0.012, 0.36, pos + Vector3(0, 0.18, 0), _mat(Color("#3b4250"), 0.4, 0.6))
	var bulb := _sphere(0.025, pos + Vector3(0, 0.37, 0), _mat(Color.WHITE))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#fff3c4")
	m.emission_enabled = true
	m.emission = Color("#ffe9a8")
	m.emission_energy_multiplier = 2.0
	bulb.material_override = m


func _tree(pos: Vector3, size: float = 1.0) -> void:
	if _rng.randf() < 0.35:
		# Pino
		_cyl(0.025 * size, 0.03 * size, 0.12 * size, pos + Vector3(0, 0.06 * size, 0), _mat(Color("#6b4423"), 0.9))
		var g := _mat(Color("#2f6e47").lerp(Color("#3f8a57"), _rng.randf()), 0.85)
		_cyl(0.0, 0.15 * size, 0.24 * size, pos + Vector3(0, 0.22 * size, 0), g, self, 10)
		_cyl(0.0, 0.11 * size, 0.2 * size, pos + Vector3(0, 0.34 * size, 0), g, self, 10)
		return
	_cyl(0.022 * size, 0.035 * size, 0.2 * size, pos + Vector3(0, 0.1 * size, 0), _mat(Color("#7a4e2d"), 0.9))
	var greens := [Color("#4f9a4a"), Color("#5fae55"), Color("#3e8a46"), Color("#6cb35e")]
	var leaf := _mat(greens[_rng.randi() % greens.size()], 0.85)
	for k in 3:
		var off := Vector3(_rng.randf_range(-0.06, 0.06), _rng.randf_range(0, 0.07), _rng.randf_range(-0.06, 0.06)) * size
		_sphere(_rng.randf_range(0.09, 0.13) * size, pos + Vector3(0, 0.27 * size, 0) + off, leaf)


## Casa con techo a dos aguas, chimenea, puerta y ventanas.
func _house(pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	var wall: Color = FACADES[_rng.randi() % FACADES.size()]
	var roof: Color = ROOFS[_rng.randi() % ROOFS.size()]
	_box(size, Vector3(0, size.y / 2.0, 0), _mat(wall, 0.75), n)
	_prism(Vector3(size.x * 1.12, size.y * 0.65, size.z * 1.12), Vector3(0, size.y + size.y * 0.325, 0), _mat(roof, 0.6), PI / 2.0, n)
	_box(Vector3(0.05, size.y * 0.45, 0.05), Vector3(size.x * 0.28, size.y * 1.3, size.z * 0.2), _mat(Color("#8a5a44"), 0.8), n)
	_box(Vector3(size.x * 0.2, size.y * 0.5, 0.01), Vector3(0, size.y * 0.25, size.z / 2.0 + 0.004), _mat(Color("#6b3f2a"), 0.7), n)
	for sx in [-1, 1]:
		_box(Vector3(size.x * 0.18, size.y * 0.22, 0.01), Vector3(sx * size.x * 0.3, size.y * 0.58, size.z / 2.0 + 0.004), _mat(Color("#bfe0f5"), 0.15, 0.3), n)


## Edificio de oficinas: podio, torre con ventanas (o vidrio), retranqueo y detalles en la azotea.
func _tower(pos: Vector3, w: float, h: float, tint: Color, glass: bool = false, round: bool = false) -> void:
	_box(Vector3(w + 0.12, 0.14, w + 0.12), pos + Vector3(0, 0.07, 0), _mat(Color("#b9b3a8"), 0.7))
	var body_mat := _window_material(tint, glass)
	if round:
		_cyl(w / 2.0, w / 2.0, h, pos + Vector3(0, 0.14 + h / 2.0, 0), body_mat, self, 24)
		_cyl(w / 2.0 + 0.02, w / 2.0 + 0.02, 0.04, pos + Vector3(0, 0.16 + h, 0), _mat(tint.darkened(0.3), 0.4), self, 24)
	else:
		var lower := h * 0.65
		_box(Vector3(w, lower, w), pos + Vector3(0, 0.14 + lower / 2.0, 0), body_mat)
		_box(Vector3(w * 0.72, h - lower, w * 0.72), pos + Vector3(0, 0.14 + lower + (h - lower) / 2.0, 0), body_mat)
		_box(Vector3(w + 0.03, 0.03, w + 0.03), pos + Vector3(0, 0.14 + lower, 0), _mat(tint.darkened(0.25), 0.4))
		_box(Vector3(w * 0.75, 0.03, w * 0.75), pos + Vector3(0, 0.15 + h, 0), _mat(tint.darkened(0.3), 0.4))
	var top := pos + Vector3(0, 0.16 + h, 0)
	match _rng.randi() % 3:
		0:
			_cyl(0.004, 0.008, 0.3, top + Vector3(0, 0.15, 0), _mat(Color("#cfd6dd"), 0.3, 0.8))
			_sphere(0.012, top + Vector3(0, 0.31, 0), _mat(Color("#ff4d4d")))
		1:
			_cyl(0.05, 0.05, 0.08, top + Vector3(w * 0.15, 0.04, 0), _mat(Color("#9aa4ad"), 0.5, 0.4), self, 12)
		2:
			_box(Vector3(0.1, 0.05, 0.08), top + Vector3(-w * 0.15, 0.025, w * 0.1), _mat(Color("#b8c0c8"), 0.5))


func _district_downtown(c: Vector2) -> void:
	_box(Vector3(2.2, 0.025, 2.2), Vector3(c.x, 0.055, c.y), _mat(Color("#cfcac0"), 0.8))
	_tower(Vector3(c.x - 0.6, 0.06, c.y - 0.6), 0.5, 1.7, Color("#d6e4f0"), true)
	_tower(Vector3(c.x + 0.55, 0.06, c.y - 0.6), 0.42, 1.2, Color("#f1dfc4"))
	_tower(Vector3(c.x - 0.6, 0.06, c.y + 0.55), 0.46, 1.1, Color("#e6d6ec"), false, true)
	_tower(Vector3(c.x + 0.6, 0.06, c.y + 0.6), 0.4, 0.9, Color("#cfe6dc"))
	_tower(Vector3(c.x, 0.06, c.y), 0.55, 2.5, Color("#bcd3ea"), true)


func _district_houses(c: Vector2) -> void:
	for x in 3:
		for z in 3:
			var p := c + Vector2((x - 1) * 0.74, (z - 1) * 0.74)
			_box(Vector3(0.6, 0.02, 0.6), Vector3(p.x, 0.05, p.y), _mat(Color("#9ccf7f"), 0.9))
			_house(Vector3(p.x, 0.06, p.y), Vector3(0.36, 0.26, 0.3), (_rng.randi() % 4) * PI / 2.0)
			if _rng.randf() < 0.6:
				_tree(Vector3(p.x + 0.22, 0.06, p.y + 0.2), 0.7)


func _district_park(c: Vector2) -> void:
	_cyl(1.25, 1.25, 0.02, Vector3(c.x, 0.05, c.y), _mat(Color("#9ad17a"), 0.9), self, 40)
	_cyl(1.05, 1.05, 0.022, Vector3(c.x, 0.052, c.y), _mat(Color("#e6dcc4"), 0.85), self, 40)
	_cyl(0.95, 0.95, 0.024, Vector3(c.x, 0.054, c.y), _mat(Color("#8cc56a"), 0.9), self, 40)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.25, 0.58, 0.88, 0.88)
	water.roughness = 0.03
	water.metallic = 0.35
	water.emission_enabled = true
	water.emission = Color(0.15, 0.4, 0.7)
	water.emission_energy_multiplier = 0.25
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var stone := _mat(Color("#d6cfc2"), 0.6)
	# Estanque: borde de piedra y lámina de agua con el doble de grosor que antes.
	_cyl(0.62, 0.66, 0.12, Vector3(c.x, 0.11, c.y), stone, self, 40)
	_cyl(0.56, 0.56, 0.06, Vector3(c.x, 0.15, c.y), water, self, 40)
	# Columna central y taza superior con su propia agua.
	_cyl(0.06, 0.09, 0.3, Vector3(c.x, 0.27, c.y), stone, self, 16)
	_cyl(0.24, 0.14, 0.08, Vector3(c.x, 0.44, c.y), stone, self, 24)
	_cyl(0.21, 0.21, 0.04, Vector3(c.x, 0.47, c.y), water, self, 24)
	_cyl(0.03, 0.04, 0.14, Vector3(c.x, 0.55, c.y), stone, self, 12)
	var drop := SphereMesh.new()
	drop.radius = 0.016
	drop.height = 0.032
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.85, 0.95, 1.0, 0.85)
	dm.emission_enabled = true
	dm.emission = Color(0.7, 0.85, 1.0)
	dm.emission_energy_multiplier = 0.4
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Chorro central que sube y cae en la taza.
	var spray := CPUParticles3D.new()
	spray.amount = 70
	spray.lifetime = 0.9
	spray.direction = Vector3.UP
	spray.spread = 12.0
	spray.initial_velocity_min = 0.9
	spray.initial_velocity_max = 1.1
	spray.gravity = Vector3(0, -2.2, 0)
	spray.mesh = drop
	spray.material_override = dm
	spray.position = Vector3(c.x, 0.62, c.y)
	add_child(spray)
	# Cortina que rebosa de la taza al estanque.
	var curtain := CPUParticles3D.new()
	curtain.amount = 90
	curtain.lifetime = 0.45
	curtain.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	curtain.emission_ring_axis = Vector3.UP
	curtain.emission_ring_radius = 0.22
	curtain.emission_ring_inner_radius = 0.2
	curtain.emission_ring_height = 0.0
	curtain.direction = Vector3.DOWN
	curtain.spread = 5.0
	curtain.initial_velocity_min = 0.05
	curtain.initial_velocity_max = 0.1
	curtain.gravity = Vector3(0, -1.6, 0)
	curtain.mesh = drop
	curtain.material_override = dm
	curtain.position = Vector3(c.x, 0.46, c.y)
	add_child(curtain)
	for k in 10:
		var a := k * TAU / 10.0
		_tree(Vector3(c.x + cos(a) * 1.08, 0.06, c.y + sin(a) * 1.08), _rng.randf_range(0.8, 1.15))
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var bench := _box(Vector3(0.16, 0.03, 0.05), Vector3(c.x + cos(a) * 0.78, 0.09, c.y + sin(a) * 0.78), _mat(Color("#8a5a44"), 0.8))
		bench.rotation.y = -a + PI / 2.0


func _district_mixed(c: Vector2) -> void:
	_box(Vector3(2.2, 0.025, 2.2), Vector3(c.x, 0.055, c.y), _mat(Color("#d6d0c4"), 0.8))
	_tower(Vector3(c.x - 0.58, 0.06, c.y - 0.6), 0.48, 1.3, Color("#f3d9c9"))
	_tower(Vector3(c.x + 0.6, 0.06, c.y - 0.55), 0.42, 0.95, Color("#d9e8f3"), false, true)
	_house(Vector3(c.x - 0.55, 0.06, c.y + 0.58), Vector3(0.48, 0.3, 0.38))
	_house(Vector3(c.x + 0.55, 0.06, c.y + 0.58), Vector3(0.4, 0.28, 0.36), PI)
	_tree(Vector3(c.x, 0.06, c.y), 1.2)


func _plaza() -> void:
	_cyl(0.34, 0.34, 0.03, Vector3(0, 0.085, 0), _mat(Color("#efe3c6"), 0.6), self, 32)
	_box(Vector3(0.12, 0.08, 0.12), Vector3(0, 0.13, 0), _mat(Color("#d9cdb2"), 0.5))
	_cyl(0.025, 0.06, 0.7, Vector3(0, 0.52, 0), _mat(Color("#f4efe4"), 0.35))
	_cyl(0.0, 0.03, 0.08, Vector3(0, 0.91, 0), _mat(TRIM, 0.3, 0.7))
	for k in 8:
		var a := k * TAU / 8.0
		_sphere(0.035, Vector3(cos(a) * 0.26, 0.11, sin(a) * 0.26), _mat([Color("#e8735a"), Color("#f2c14e"), Color("#d64550")][k % 3], 0.7))


func _mountains() -> void:
	var rock := _mat(Color("#7d8aa3"), 0.85)
	var rock2 := _mat(Color("#69768f"), 0.85)
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("#ffffff")
	snow.roughness = 0.35
	snow.emission_enabled = true
	snow.emission = Color("#dfeaff")
	snow.emission_energy_multiplier = 0.35
	var peaks := [[Vector3(-3.35, 0, -3.65), 0.7, 1.0], [Vector3(-2.6, 0, -3.85), 0.5, 0.75], [Vector3(-3.95, 0, -3.1), 0.42, 0.6]]
	for pk in peaks:
		var base: Vector3 = pk[0]
		var r: float = pk[1]
		var h: float = pk[2]
		var stretch := Vector3(1.15, 1, 0.85)
		var m := _cyl(0.0, r, h, base + Vector3(0, h / 2.0 + 0.04, 0), rock if r > 0.55 else rock2, self, 9)
		m.scale = stretch
		# Casquete de nieve el doble de grueso (cubre el 55 % superior) y apenas más ancho
		# que la roca para que no parpadee contra ella.
		var cap_h := h * 0.55
		var cap_r := r * 0.55 * 1.06
		var cap := _cyl(0.0, cap_r, cap_h, base + Vector3(0, h - cap_h / 2.0 + 0.045, 0), snow, self, 9)
		cap.scale = stretch
		# Lenguas de nieve que bajan por las laderas.
		for k in 5:
			var a := k * TAU / 5.0 + 0.3
			var tongue_h := h * _rng.randf_range(0.22, 0.32)
			var tip := base + Vector3(cos(a) * r * 0.42 * stretch.x, h * 0.42, sin(a) * r * 0.42 * stretch.z)
			var tongue := _cyl(0.0, r * 0.16, tongue_h, tip, snow, self, 6)
			tongue.rotation = Vector3(0, -a, 0)
			tongue.rotate_object_local(Vector3.FORWARD, 0.0)
			tongue.look_at_from_position(tip, base + Vector3(0, h + 0.04, 0), Vector3.UP)
			tongue.rotate_object_local(Vector3.RIGHT, -PI / 2.0)


func _build_cable_car() -> void:
	var a := Vector3(-3.4, 0, -2.4)
	var b := Vector3(3.4, 0, -2.0)
	for p in [a, b]:
		_box(Vector3(0.4, 0.22, 0.3), p + Vector3(0, 0.15, 0), _mat(Color("#e9e4da"), 0.6))
		_box(Vector3(0.44, 0.04, 0.34), p + Vector3(0, 0.28, 0), _mat(Color("#1f9e89"), 0.4))
		_cyl(0.04, 0.07, 1.5, p + Vector3(0, 1.0, 0), _mat(Color("#cfd6dd"), 0.4, 0.5))
		_box(Vector3(0.32, 0.06, 0.1), p + Vector3(0, 1.75, 0), _mat(Color("#5c6b7a"), 0.4, 0.5))
	var cable := _cyl(0.006, 0.006, a.distance_to(b), (a + b) / 2.0 + Vector3(0, 1.7, 0), _mat(INK))
	cable.look_at_from_position(cable.position, b + Vector3(0, 1.7, 0), Vector3.UP)
	cable.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var colors := [Color("#d64550"), Color("#f2c14e"), Color("#1f9e89")]
	for k in 3:
		var cab := Node3D.new()
		add_child(cab)
		_box(Vector3(0.2, 0.16, 0.15), Vector3(0, -0.14, 0), _mat(colors[k], 0.35), cab)
		_box(Vector3(0.21, 0.06, 0.16), Vector3(0, -0.11, 0), _mat(Color("#dff3fb"), 0.05, 0.3), cab)
		_cyl(0.006, 0.006, 0.12, Vector3(0, -0.02, 0), _mat(INK), cab)
		_cabins.append({"node": cab, "a": a + Vector3(0, 1.7, 0), "b": b + Vector3(0, 1.7, 0), "phase": k / 3.0})


func _build_cars(ring: float) -> void:
	var colors := [Color("#d64550"), Color("#3d6fd6"), Color("#f2c14e"), Color("#ecf0f1"), Color("#1f9e89"), Color("#2d3436")]
	var tire := _mat(Color("#1e1e1e"), 0.8)
	for k in 6:
		var car := Node3D.new()
		add_child(car)
		_box(Vector3(0.26, 0.07, 0.13), Vector3(0, 0.07, 0), _mat(colors[k], 0.25, 0.4), car)
		_box(Vector3(0.14, 0.06, 0.115), Vector3(-0.02, 0.13, 0), _mat(Color("#cfe8f5"), 0.05, 0.4), car)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				var wheel := _cyl(0.028, 0.028, 0.02, Vector3(sx * 0.08, 0.03, sz * 0.065), tire, car, 10)
				wheel.rotation.x = PI / 2.0
		_cars.append({"node": car, "phase": k / 6.0, "ring": ring, "lane": 0.12 if k % 2 == 0 else -0.12, "speed": 0.035 + 0.01 * (k % 3)})


func _build_dice() -> void:
	for k in 3:
		var die := Node3D.new()
		var speed := k == 2
		_box(Vector3(DIE, DIE, DIE), Vector3.ZERO, _mat(Color("#d64550") if speed else Color("#fbfbf8"), 0.18), die)
		if speed:
			var faces := [["1", Vector3.UP], ["2", Vector3.RIGHT], ["3", Vector3.BACK], ["»", Vector3.FORWARD], ["»", Vector3.LEFT], ["Bs", Vector3.DOWN]]
			for f in faces:
				var l := Label3D.new()
				l.text = f[0]
				l.font = _font
				l.font_size = 64
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
		var pip_mat := _mat(Color("#d64550") if f[0] == 1 else INK, 0.4)
		for p in layouts[f[0]]:
			var mi := MeshInstance3D.new()
			mi.mesh = pip_mesh
			mi.material_override = pip_mat
			mi.position = n * (DIE / 2.0 - 0.014) + u * p.x + v * p.y
			die.add_child(mi)


## Haz de luz desde el centro de la ciudad hacia el cielo, con el resultado de los dados flotando.
func _build_beam() -> void:
	_beam = Node3D.new()
	_beam.visible = false
	add_child(_beam)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.45, 0.28)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.4)
	m.emission_energy_multiplier = 2.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cyl(0.75, 0.18, 3.4, Vector3(0, 1.8, 0), m, _beam, 32)
	var core := m.duplicate()
	core.albedo_color = Color(1.0, 0.95, 0.8, 0.35)
	_cyl(0.22, 0.06, 3.4, Vector3(0, 1.8, 0), core, _beam, 16)
	_beam_label = Label3D.new()
	_beam_label.font = _font
	_beam_label.font_size = 160
	_beam_label.pixel_size = 0.01
	_beam_label.outline_size = 36
	_beam_label.outline_modulate = INK
	_beam_label.modulate = TRIM
	_beam_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_beam_label.no_depth_test = true
	_beam_label.position = Vector3(0, 2.35, 0)
	_beam.add_child(_beam_label)
	_beam_sub = Label3D.new()
	_beam_sub.font = _font
	_beam_sub.font_size = 90
	_beam_sub.pixel_size = 0.01
	_beam_sub.outline_size = 24
	_beam_sub.outline_modulate = INK
	_beam_sub.modulate = Color.WHITE
	_beam_sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_beam_sub.no_depth_test = true
	_beam_sub.position = Vector3(0, 1.7, 0)
	_beam.add_child(_beam_sub)


func _show_beam(values: Array, double: bool) -> void:
	var total := int(values[0]) + int(values[1])
	var extra := int(values[2])
	if extra in [1, 2, 3]:
		total += extra
	_beam_label.text = str(total)
	var notes := []
	if double:
		notes.append("¡DOBLES!")
	if extra == GameEngine.SPEED_BOLT:
		notes.append("» TURBO")
	elif extra == GameEngine.SPEED_STAR:
		notes.append("+Bs 50")
	_beam_sub.text = "  ".join(notes)
	_beam.visible = true
	_beam.scale = Vector3(0.2, 0.01, 0.2)
	var tw := create_tween()
	tw.tween_interval(EventPlayer.DICE_TIME * 0.8)
	tw.tween_property(_beam, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(_beam, "scale", Vector3(0.05, 1.0, 0.05), 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _beam.visible = false)


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


## Dueño a simple vista: marco del color del jugador alrededor de la casilla, banderín en la
## esquina exterior y el cartel con el borde de su color y su nombre. Las libres muestran «EN VENTA».
func _update_owner(i: int, own: int, mortgaged: bool) -> void:
	var r := BoardLayout.rect(i)
	var outward := -BoardLayout.inward(i)
	if not _owner_marks.has(i):
		var mark := Node3D.new()
		mark.position = _w(r.get_center(), TOP + 0.012)
		add_child(mark)
		var th := 0.07
		var sx := r.size.x - 0.06
		var sz := r.size.y - 0.06
		for spec in [[Vector3(sx, 0.03, th), Vector3(0, 0, (sz - th) / 2.0)], [Vector3(sx, 0.03, th), Vector3(0, 0, -(sz - th) / 2.0)],
				[Vector3(th, 0.03, sz), Vector3((sx - th) / 2.0, 0, 0)], [Vector3(th, 0.03, sz), Vector3(-(sx - th) / 2.0, 0, 0)]]:
			_box(spec[0], spec[1], _mat(Color.WHITE), mark).set_meta("edge", true)
		var along := Vector2(1, 0) if BoardLayout.side(i) % 2 == 0 else Vector2(0, 1)
		var corner := outward * (BoardLayout.CORNER / 2.0 - 0.16) + along * (minf(r.size.x, r.size.y) / 2.0 - 0.14)
		var flag := Node3D.new()
		flag.name = "Flag"
		flag.position = Vector3(corner.x, 0, corner.y)
		mark.add_child(flag)
		_cyl(0.012, 0.012, 0.42, Vector3(0, 0.21, 0), _mat(Color("#dfe6e9"), 0.3, 0.7), flag)
		_sphere(0.022, Vector3(0, 0.43, 0), _mat(TRIM, 0.3, 0.6), flag)
		var cloth := _box(Vector3(0.2, 0.12, 0.012), Vector3(0.1, 0.34, 0), _mat(Color.WHITE), flag)
		cloth.name = "Cloth"
		_flags.append(flag)
		mark.visible = false
		_owner_marks[i] = mark
		_mortgage_marks[i] = _box(Vector3(r.size.x - 0.08, 0.01, r.size.y - 0.08), _w(r.get_center(), TOP + 0.03), _veil())
	var mark: Node3D = _owner_marks[i]
	var was_visible := mark.visible
	var was_mortgaged: bool = _mortgage_marks[i].visible
	mark.visible = own >= 0
	var flag: Node3D = mark.get_node("Flag")
	if own >= 0:
		var pcol := Color.html(controller.engine.player(own)["color"])
		var m := _mat(pcol, 0.35)
		for c in mark.get_children():
			if c.has_meta("edge"):
				c.material_override = m
		flag.get_node("Cloth").material_override = _mat(pcol.lerp(Color.GRAY, 0.6) if mortgaged else pcol, 0.4)
		if not was_visible and _animate_buildings:
			mark.scale = Vector3(0.2, 1, 0.2)
			create_tween().tween_property(mark, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			flag.scale = Vector3(1, 0.01, 1)
			create_tween().tween_property(flag, "scale", Vector3.ONE, 0.6).set_delay(0.15).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		elif mortgaged != was_mortgaged and _animate_buildings:
			# Hipoteca: el banderín baja a media asta; al levantarla vuelve a subir.
			create_tween().tween_property(flag, "scale", Vector3(1, 0.55 if mortgaged else 1.0, 1), 0.4).set_trans(Tween.TRANS_BACK)
		elif not _animate_buildings:
			flag.scale = Vector3(1, 0.55 if mortgaged else 1.0, 1)
	_mortgage_marks[i].visible = mortgaged
	_update_sign_owner(i, own, mortgaged)


func _update_sign_owner(i: int, own: int, mortgaged: bool) -> void:
	if not _sign_of.has(i):
		return
	var s: Dictionary = _sign_of[i]
	var price: Label3D = s["price"]
	var frame: MeshInstance3D = s["frame"]
	if own < 0:
		price.text = "EN VENTA  Bs %d" % controller.board.price(i)
		price.font_size = 22
		price.modulate = TRIM
		price.outline_modulate = INK
		price.position.x = 0.0
		frame.material_override = _mat(INK, 0.3)
		return
	var p := controller.engine.player(own)
	var pcol := Color.html(p["color"])
	price.text = ("HIPOTECADA · " if mortgaged else "DE ") + String(p["name"]).to_upper()
	price.font_size = 22 if mortgaged else 28
	price.modulate = Color.WHITE
	price.outline_modulate = pcol.darkened(0.35)
	price.position.x = 0.0
	frame.material_override = _mat(pcol.lerp(Color.GRAY, 0.5) if mortgaged else pcol, 0.3)


## Festejo de compra: confeti del color del dueño sobre la casilla y el cartel salta.
func _claim(i: int, pid: int) -> void:
	if pid < 0:
		return
	var r := BoardLayout.rect(i)
	var pcol := Color.html(controller.engine.player(pid)["color"])
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.005, 0.03)
	_burst(_w(r.get_center(), TOP + 0.1), mesh, pcol, 30, 50.0, 2.2, true)
	_burst(_w(r.get_center(), TOP + 0.1), mesh, TRIM, 16, 40.0, 1.8, true)
	_sync_space(i)
	if _sign_of.has(i):
		var panel: Node3D = _sign_of[i]["panel"]
		var tw := create_tween()
		tw.tween_property(panel, "position:y", 1.05, 0.18).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "position:y", 0.82, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Aplica el estado actual del motor a una sola casilla (en el momento de su evento).
func _sync_space(i: int) -> void:
	var e := controller.engine
	if controller.board.is_property(i):
		_update_owner(i, e.owner_of(i), e.is_mortgaged(i))
		_update_buildings(i, e.houses_on(i))


func _veil() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.38, 0.45, 0.6)
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
			unit = _hotel_unit(_w(c, TOP + 0.05), yaw)
		else:
			var p := c + along * (k - 1.5) * 0.23
			unit = _house_unit(_w(p, TOP + 0.05), yaw)
		nodes.append(unit)
		if _animate_buildings:
			_construct(unit, k * 0.1)
		k += 1


func _lit_mat() -> StandardMaterial3D:
	if not _mats.has("lit"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#ffe9a8")
		m.emission_enabled = true
		m.emission = Color("#ffd36b")
		m.emission_energy_multiplier = 0.6
		_mats["lit"] = m
	return _mats["lit"]


func _unit_root(base: Vector3, yaw: float) -> Array:
	var node := Node3D.new()
	node.position = base
	node.rotation.y = yaw
	add_child(node)
	var body := Node3D.new()
	body.name = "Body"
	node.add_child(body)
	return [node, body]


## Casa: zócalo, muros verdes, techo de teja, chimenea, puerta y ventanas encendidas.
func _house_unit(base: Vector3, yaw: float) -> Node3D:
	var nb := _unit_root(base, yaw)
	var node: Node3D = nb[0]
	var body: Node3D = nb[1]
	var w := 0.17
	var h := 0.12
	_box(Vector3(w + 0.03, 0.02, w + 0.03), Vector3(0, 0.01, 0), _mat(Color("#e9e2d0"), 0.8), body)
	_box(Vector3(w, h, w), Vector3(0, 0.02 + h / 2.0, 0), _mat(Color("#3fae6a"), 0.5), body)
	_prism(Vector3(w * 1.2, h * 0.85, w * 1.14), Vector3(0, 0.02 + h + h * 0.42, 0), _mat(Color("#b5523b"), 0.45), PI / 2.0, body)
	_box(Vector3(0.028, 0.08, 0.028), Vector3(w * 0.26, 0.02 + h + 0.07, -w * 0.18), _mat(Color("#8f3f2f"), 0.6), body)
	for face in [1.0, -1.0]:
		_box(Vector3(0.036, 0.06, 0.006), Vector3(0, 0.05, face * (w / 2.0 + 0.003)), _mat(Color("#6b3e26"), 0.6), body)
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.03, 0.03, 0.006), Vector3(sx * 0.052, 0.09, face * (w / 2.0 + 0.003)), _lit_mat(), body)
	node.set_meta("size", Vector3(w, h * 1.9, w))
	return node


## Hotel: tres pisos con filas de ventanas, losa, marquesina dorada y letrero «H».
func _hotel_unit(base: Vector3, yaw: float) -> Node3D:
	var nb := _unit_root(base, yaw)
	var node: Node3D = nb[0]
	var body: Node3D = nb[1]
	var w := 0.54
	var h := 0.36
	var d := 0.26
	_box(Vector3(w + 0.04, 0.02, d + 0.04), Vector3(0, 0.01, 0), _mat(Color("#e9e2d0"), 0.8), body)
	_box(Vector3(w, h, d), Vector3(0, 0.02 + h / 2.0, 0), _mat(Color("#d64550"), 0.4), body)
	for floor_i in 3:
		var y := 0.075 + floor_i * 0.1
		for col in 5:
			var x := -w / 2.0 + 0.07 + col * (w - 0.14) / 4.0
			for face in [1.0, -1.0]:
				if floor_i == 0 and col == 2:
					continue
				_box(Vector3(0.05, 0.045, 0.006), Vector3(x, y, face * (d / 2.0 + 0.003)), _lit_mat(), body)
	_box(Vector3(w + 0.04, 0.03, d + 0.04), Vector3(0, 0.02 + h + 0.015, 0), _mat(Color("#8f2d36"), 0.5), body)
	for face in [1.0, -1.0]:
		_box(Vector3(0.06, 0.06, 0.006), Vector3(0, 0.05, face * (d / 2.0 + 0.003)), _mat(Color("#6b3e26"), 0.6), body)
		_box(Vector3(0.16, 0.012, 0.06), Vector3(0, 0.095, face * (d / 2.0 + 0.03)), _mat(TRIM, 0.3, 0.5), body)
	var sign := _box(Vector3(0.14, 0.1, 0.02), Vector3(0, 0.02 + h + 0.09, 0), _mat(TRIM, 0.3, 0.6), body)
	for face in [1.0, -1.0]:
		var hl := Label3D.new()
		hl.text = "H"
		hl.font = _font
		hl.font_size = 64
		hl.pixel_size = 0.0016
		hl.modulate = INK
		hl.outline_size = 0
		hl.position = Vector3(0, 0, face * 0.011)
		hl.rotation.y = 0.0 if face > 0 else PI
		sign.add_child(hl)
	node.set_meta("size", Vector3(w, h * 1.3, d))
	return node


func _building(base: Vector3, size: Vector3, color: Color, yaw: float) -> Node3D:
	var node := Node3D.new()
	node.position = base
	node.rotation.y = yaw
	add_child(node)
	var body := Node3D.new()
	body.name = "Body"
	node.add_child(body)
	_box(size, Vector3(0, size.y / 2.0, 0), _mat(color, 0.3), body)
	_prism(Vector3(size.x * 1.08, size.y * 0.75, size.z * 1.08), Vector3(0, size.y + size.y * 0.375, 0), _mat(color.darkened(0.3), 0.35), PI / 2.0, body)
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
	var pole := _mat(Color("#f2c14e"), 0.5)
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
	tw.tween_callback(func(): if is_instance_valid(node): _dust(node.global_position, size.x))
	tw.tween_property(body, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(scaffold, "scale", Vector3(1, 0.001, 1), 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(scaffold.queue_free)
	tw.tween_callback(func(): if is_instance_valid(node): _sparkle(node.global_position + Vector3(0, size.y, 0)))
	tw.tween_property(body, "scale", Vector3(1.12, 0.9, 1.12), 0.08)
	tw.tween_property(body, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Destellos dorados al terminar una obra.
func _sparkle(pos: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.018
	mesh.height = 0.036
	_burst(pos, mesh, Color("#ffd36b"), 16, 80.0, 1.4, true)


func _demolish(node: Node3D) -> void:
	if not _animate_buildings:
		node.queue_free()
		return
	_dust(node.global_position, 0.2)
	var coin := CylinderMesh.new()
	coin.top_radius = 0.035
	coin.bottom_radius = 0.035
	coin.height = 0.01
	_burst(node.global_position + Vector3(0, 0.15, 0), coin, Color("#f2b84b"), 8, 30.0, 1.5, true)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3(1.1, 0.001, 1.1), 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(node.queue_free)


func _burst(pos: Vector3, mesh: Mesh, color: Color, amount: int, spread: float, velocity: float, metallic: bool = false) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.0
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = velocity * 0.6
	p.initial_velocity_max = velocity
	p.gravity = Vector3(0, -3.0 if metallic else -0.6, 0)
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if metallic:
		m.metallic = 0.9
		m.roughness = 0.25
	else:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.8).timeout.connect(p.queue_free)


func _dust(pos: Vector3, spread: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.035 + spread * 0.05
	mesh.height = mesh.radius * 2.0
	_burst(pos + Vector3(0, 0.05, 0), mesh, Color(0.93, 0.88, 0.78, 0.8), 18, 70.0, 0.8)


## Lluvia de monedas doradas sobre la ficha que cobra.
func _coins(pid: int) -> void:
	if not _tokens.has(pid):
		return
	var coin := CylinderMesh.new()
	coin.top_radius = 0.04
	coin.bottom_radius = 0.04
	coin.height = 0.012
	coin.radial_segments = 12
	_burst(_tokens[pid].position + Vector3(0, 0.4, 0), coin, Color("#f2b84b"), 14, 35.0, 1.8, true)


## La carta sale volando del mazo, gira y se desvanece (el texto lo muestra el HUD).
func _card_flight(deck: String) -> void:
	var from := Vector3(-3.65, 0.3, 3.65) if deck == "destino" else Vector3(3.65, 0.3, -3.65)
	var col := Color("#e8735a") if deck == "destino" else Color("#3d6fd6")
	var card := _box(Vector3(0.8, 0.02, 0.55), from, _mat(col, 0.3))
	var face := _box(Vector3(0.72, 0.005, 0.47), Vector3(0, -0.012, 0), _mat(Color("#fbf8f1"), 0.5), card)
	face.visible = true
	var target := camera.global_position.lerp(Vector3(0, 1.2, 0), 0.75)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "position", target, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "rotation", Vector3(PI, PI / 4.0, 0.2), 0.6)
	tw.chain().tween_interval(0.5)
	tw.chain().tween_property(card, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
	tw.chain().tween_callback(card.queue_free)


# ---------------------------------------------------------------------------
# Eventos y animación
# ---------------------------------------------------------------------------

func _on_event(ev: Dictionary) -> void:
	match ev["type"]:
		"dice_rolled":
			_throw_dice(ev["dice"])
			_show_beam(ev["dice"], ev["double"])
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
		"bought":
			_claim(int(ev["space"]), int(ev["player"]))
		"auction_ended":
			if int(ev["winner"]) >= 0:
				_claim(int(ev["space"]), int(ev["winner"]))
		"built", "sold_building", "mortgaged", "unmortgaged":
			_sync_space(int(ev["space"]))
		"money":
			var reason := String(ev["reason"])
			if int(ev["delta"]) > 0 and (reason in ["Sueldo", "Bono por caer en la Salida", "Bote del Mirador", "Carta", "Bono turbo"] or reason.begins_with("Alquiler")):
				_coins(int(ev["player"]))
		"card_drawn":
			_card_flight(ev["deck"])
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
	if not has_meta("fixed_cam"):
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


static func _face_up_rotation(v: int) -> Vector3:
	match v:
		2: return Vector3(0, 0, PI / 2.0)
		3: return Vector3(-PI / 2.0, 0, 0)
		4: return Vector3(PI / 2.0, 0, 0)
		5: return Vector3(0, 0, -PI / 2.0)
		6: return Vector3(PI, 0, 0)
	return Vector3.ZERO


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
	_orient_signs(delta)
	if controller == null or controller.engine == null:
		_update_camera(delta)
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


## Los carteles giran hacia la cámara; los del lado cercano se pliegan para no tapar la jugada.
func _orient_signs(delta: float) -> void:
	if camera == null:
		return
	var cam_flat := Vector3(camera.global_position.x, 0, camera.global_position.z)
	var view := cam_flat.normalized() if cam_flat.length() > 0.01 else Vector3.BACK
	for s in _signs:
		var node: Node3D = s["node"]
		var to_cam := cam_flat - Vector3(node.position.x, 0, node.position.z)
		var yaw := atan2(to_cam.x, to_cam.z)
		node.rotation.y = lerp_angle(node.rotation.y, yaw, minf(1.0, delta * 6.0))
		var near: bool = (s["outward"] as Vector3).dot(view) > 0.5
		var target := 0.0 if near else 1.0
		var sc := lerpf(node.scale.y, target, minf(1.0, delta * 8.0))
		node.scale = Vector3(maxf(sc, 0.001), maxf(sc, 0.001), maxf(sc, 0.001))
		node.visible = sc > 0.02


func _animate_city() -> void:
	for k in _flags.size():
		var f: Node3D = _flags[k]
		if f.is_visible_in_tree():
			f.rotation.y = sin(_time * 3.0 + k) * 0.35
	for c in _cabins:
		var t := fposmod(_time * 0.05 + c["phase"], 1.0)
		var ping := t * 2.0 if t < 0.5 else 2.0 - t * 2.0
		var p: Vector3 = c["a"].lerp(c["b"], ping)
		c["node"].position = p + Vector3(0, -0.12 * sin(ping * PI), 0)
	for car in _cars:
		var ring: float = car["ring"]
		var t := fposmod(_time * car["speed"] + car["phase"], 1.0) * 4.0
		var side := mini(int(t), 3)
		var f := t - side
		var corners := [Vector2(-ring, ring), Vector2(ring, ring), Vector2(ring, -ring), Vector2(-ring, -ring), Vector2(-ring, ring)]
		var lane: float = car["lane"]
		var p: Vector2 = corners[side].lerp(corners[side + 1], f)
		var dir: Vector2 = (corners[side + 1] - corners[side]).normalized()
		p += Vector2(-dir.y, dir.x) * lane
		car["node"].position = Vector3(p.x, 0.07, p.y)
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
