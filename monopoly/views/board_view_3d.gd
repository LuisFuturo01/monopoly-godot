class_name BoardView3D
extends Node3D
## Vista 3D: tablero con luz dinámica y sombras, ciudad en miniatura al centro,
## fichas y edificios procedurales, dados animados y cámara cinemática.

signal space_clicked(index: int)

const CITY_SCENE := "res://ciudad/city.glb"
const S := BoardLayout.SIZE
const TOP := 0.04
const PAPER := Color(0.95, 0.94, 0.87)
const INK := Color(0.12, 0.12, 0.14)
const DIE := 0.38

var controller: GameController
var active := true
var cinematic := true

var camera: Camera3D
var _cam_yaw := 0.0
var _cam_pitch := deg_to_rad(52.0)
var _cam_dist := 15.5
var _cam_target := Vector3.ZERO
var _cur_yaw := 0.0
var _cur_pitch := deg_to_rad(52.0)
var _cur_dist := 15.5
var _cur_target := Vector3.ZERO
var _follow := -1

var _tokens: Dictionary = {}        # pid -> Node3D
var _anim: Dictionary = {}          # pid -> {pos: Vector2, from, queue, t}
var _buildings: Dictionary = {}     # space -> Node3D
var _owner_marks: Dictionary = {}   # space -> MeshInstance3D
var _mortgage_marks: Dictionary = {}
var _dice: Array = []
var _dice_tween: Tween
var _mats: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _press_pos := Vector2.ZERO
var _dragging := false
var _left_down := false
var _touches: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_build_environment()
	_build_board()
	_build_center()
	_build_dice()
	camera = Camera3D.new()
	camera.fov = 50.0
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
		tok.scale = Vector3.ONE * 1.25
		add_child(tok)
		_tokens[int(p["id"])] = tok
		_anim[int(p["id"])] = {"pos": Vector2.ZERO, "from": Vector2.ZERO, "queue": [], "t": 0.0}
	_refresh()
	_snap_tokens()


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


func _mat(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
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


func _label(text: String, pos: Vector3, angle: float, font_size: int, width_units: float, color: Color = INK) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.004
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


# ---------------------------------------------------------------------------
# Construcción de la escena
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.45, 0.68)
	sky_mat.sky_horizon_color = Color(0.75, 0.7, 0.62)
	sky_mat.ground_bottom_color = Color(0.1, 0.08, 0.07)
	sky_mat.ground_horizon_color = Color(0.45, 0.38, 0.32)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 7, 0)
	lamp.omni_range = 14.0
	lamp.light_energy = 0.6
	lamp.light_color = Color(1.0, 0.85, 0.65)
	add_child(lamp)


func _build_board() -> void:
	var board := Board.load_from_file(GameController.BOARD_PATH)
	_box(Vector3(60, 0.2, 60), Vector3(0, -0.42, 0), _mat(Color(0.22, 0.13, 0.08), 0.6))
	_box(Vector3(S + 0.5, 0.3, S + 0.5), Vector3(0, -0.15, 0), _mat(Color(0.35, 0.08, 0.07), 0.5))
	_box(Vector3(S, 0.04, S), Vector3(0, 0.0, 0), _mat(Color(0.80, 0.88, 0.81), 0.9))
	for i in board.size():
		var sp := board.space(i)
		var r := BoardLayout.rect(i)
		var ang := BoardLayout.text_angle(i)
		var inward := BoardLayout.inward(i)
		_box(Vector3(r.size.x - 0.03, 0.03, r.size.y - 0.03), _w(r.get_center(), 0.025), _mat(PAPER, 0.85))
		var corner := BoardLayout.is_corner(i)
		var along := (BoardLayout.CORNER if corner else BoardLayout.CELL) - 0.08
		var text_y := TOP + 0.003
		if sp["type"] == "street":
			var br := BoardLayout.band_rect(i)
			_box(Vector3(br.size.x - 0.03, 0.035, br.size.y - 0.03), _w(br.get_center(), 0.03), _mat(board.space_color(i), 0.6))
		if corner:
			var names := {"go": "SALIDA\ncobra $%d" % board.salary, "jail": "RETÉN", "free": "MIRADOR", "gotojail": "¡AL RETÉN!"}
			_label(names.get(sp["type"], sp["name"]), _w(r.get_center(), text_y), ang, 48, along, Color(0.7, 0.12, 0.1))
			continue
		var name_pos := r.get_center() + inward * (BoardLayout.CORNER / 2.0 - BoardLayout.BAND - 0.28)
		_label(String(sp["name"]).to_upper(), _w(name_pos, text_y), ang, 26, along)
		var sub := ""
		if board.is_property(i):
			sub = "$%d" % board.price(i)
		elif sp["type"] == "tax":
			sub = "Paga $%d" % int(sp["amount"])
		elif sp["type"] == "card":
			sub = "DESTINO ?" if sp["deck"] == "destino" else "CABILDO !"
		if sub != "":
			_label(sub, _w(r.get_center() - inward * 0.55, text_y), ang, 26, along)
		if sp["type"] == "transit":
			_label("[ T ]", _w(r.get_center() - inward * 0.1, text_y), ang, 40, along, Color(0.25, 0.25, 0.3))


func _build_center() -> void:
	var city: Node3D = null
	if ResourceLoader.exists(CITY_SCENE):
		var packed = load(CITY_SCENE)
		if packed is PackedScene:
			city = packed.instantiate()
	if city:
		add_child(city)
		var aabb := _scene_aabb(city, Transform3D.IDENTITY)
		var footprint := maxf(aabb.size.x, aabb.size.z)
		if footprint > 0.001:
			var k := 5.2 / footprint
			city.scale = Vector3.ONE * k
			var center := aabb.get_center()
			city.position = Vector3(-center.x * k, TOP - aabb.position.y * k, -center.z * k)
		city.name = "Ciudad"
	else:
		_procedural_city()
	# Mazos de cartas
	for k in 2:
		var pos := Vector3(-3.0, 0, 2.9) if k == 0 else Vector3(3.0, 0, -2.9)
		var col := Color(0.95, 0.62, 0.15) if k == 0 else Color(0.35, 0.6, 0.85)
		var deck := _box(Vector3(1.5, 0.18, 1.0), pos + Vector3(0, TOP + 0.09, 0), _mat(col, 0.5))
		deck.rotation.y = PI / 4.0
		_label("DESTINO" if k == 0 else "CABILDO", pos + Vector3(0, TOP + 0.185, 0), -PI / 4.0, 40, 1.4)


func _scene_aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is VisualInstance3D:
		result = t * (node as VisualInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		var a := _scene_aabb(child, t)
		if a.size == Vector3.ZERO:
			continue
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result


func _procedural_city() -> void:
	var colors := [Color(0.85, 0.82, 0.75), Color(0.7, 0.75, 0.82), Color(0.9, 0.7, 0.55), Color(0.6, 0.65, 0.6)]
	for x in range(-2, 3):
		for z in range(-2, 3):
			if _rng.randf() < 0.2:
				continue
			var h := _rng.randf_range(0.3, 2.2) * (1.4 if abs(x) + abs(z) <= 1 else 0.8)
			_box(Vector3(0.75, h, 0.75), Vector3(x * 1.0, TOP + h / 2.0, z * 1.0), _mat(colors[_rng.randi() % colors.size()], 0.7))
	var mountain := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.4
	cone.height = 2.0
	mountain.mesh = cone
	mountain.material_override = _mat(Color(0.95, 0.97, 1.0), 0.6)
	mountain.position = Vector3(-1.5, TOP + 1.0, -3.2)
	add_child(mountain)


func _build_dice() -> void:
	for k in 3:
		var die := Node3D.new()
		var speed := k == 2
		_box(Vector3(DIE, DIE, DIE), Vector3.ZERO, _mat(Color(0.85, 0.15, 0.15) if speed else Color(0.97, 0.97, 0.95), 0.35), die)
		if speed:
			var faces := [["1", Vector3.UP], ["2", Vector3.RIGHT], ["3", Vector3.BACK], ["»", Vector3.FORWARD], ["»", Vector3.LEFT], ["$", Vector3.DOWN]]
			for f in faces:
				var l := Label3D.new()
				l.text = f[0]
				l.font_size = 64
				l.pixel_size = 0.004
				l.modulate = Color.WHITE
				l.position = f[1] * (DIE / 2.0 + 0.002)
				l.look_at_from_position(l.position, l.position * 2.0, Vector3.UP if absf(f[1].y) < 0.9 else Vector3.FORWARD)
				l.rotate_object_local(Vector3.UP, PI)
				die.add_child(l)
		else:
			_add_pips(die)
		die.position = Vector3((k - 1) * 0.6, TOP + DIE / 2.0, 3.6)
		die.visible = k < 2
		add_child(die)
		_dice.append(die)


func _add_pips(die: Node3D) -> void:
	# +Y=1, +X=2, +Z=3, -Z=4, -X=5, -Y=6
	var faces := [[1, Vector3.UP], [2, Vector3.RIGHT], [3, Vector3.BACK], [4, Vector3.FORWARD], [5, Vector3.LEFT], [6, Vector3.DOWN]]
	var o := 0.095
	var layouts := {
		1: [Vector2.ZERO], 2: [Vector2(-o, -o), Vector2(o, o)], 3: [Vector2(-o, -o), Vector2.ZERO, Vector2(o, o)],
		4: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, o), Vector2(o, o)],
		5: [Vector2(-o, -o), Vector2(o, -o), Vector2.ZERO, Vector2(-o, o), Vector2(o, o)],
		6: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, 0), Vector2(o, 0), Vector2(-o, o), Vector2(o, o)],
	}
	var pip_mesh := SphereMesh.new()
	pip_mesh.radius = 0.032
	pip_mesh.height = 0.064
	var pip_mat := _mat(INK, 0.4)
	for f in faces:
		var n: Vector3 = f[1]
		var u := Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.BACK
		var v := n.cross(u)
		for p in layouts[f[0]]:
			var mi := MeshInstance3D.new()
			mi.mesh = pip_mesh
			mi.material_override = pip_mat
			mi.position = n * (DIE / 2.0 - 0.012) + u * p.x + v * p.y
			die.add_child(mi)


## Orientación que deja la cara `v` hacia arriba.
static func _face_up_rotation(v: int) -> Vector3:
	match v:
		2: return Vector3(0, 0, PI / 2.0)
		3: return Vector3(-PI / 2.0, 0, 0)
		4: return Vector3(PI / 2.0, 0, 0)
		5: return Vector3(0, 0, -PI / 2.0)
		6: return Vector3(PI, 0, 0)
	return Vector3.ZERO


# ---------------------------------------------------------------------------
# Estado
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
		var size := Vector3(r.size.x - 0.06, 0.02, 0.1) if horizontal else Vector3(0.1, 0.02, r.size.y - 0.06)
		var pos := r.get_center() + outward * (BoardLayout.CORNER / 2.0 - 0.08)
		_owner_marks[i] = _box(size, _w(pos, TOP + 0.01), _mat(Color.WHITE))
		_mortgage_marks[i] = _box(Vector3(r.size.x - 0.05, 0.01, r.size.y - 0.05), _w(r.get_center(), TOP + 0.02), _translucent())
	var mark: MeshInstance3D = _owner_marks[i]
	mark.visible = own >= 0
	if own >= 0:
		mark.material_override = _mat(Color.html(controller.engine.player(own)["color"]), 0.4, 0.3)
	_mortgage_marks[i].visible = mortgaged


func _translucent() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.1, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _update_buildings(i: int, h: int) -> void:
	var key := "h%d" % h
	var holder: Node3D = _buildings.get(i)
	if holder and holder.get_meta("key", "") == key:
		return
	if holder:
		holder.queue_free()
	holder = Node3D.new()
	holder.set_meta("key", key)
	add_child(holder)
	_buildings[i] = holder
	if h == 0:
		return
	var br := BoardLayout.band_rect(i)
	var c := br.get_center()
	var along := Vector2(1, 0) if BoardLayout.side(i) % 2 == 0 else Vector2(0, 1)
	var yaw := 0.0 if BoardLayout.side(i) % 2 == 0 else PI / 2.0
	if h == GameEngine.HOTEL:
		_house(holder, _w(c, TOP + 0.03), Vector3(0.5, 0.2, 0.24), Color(0.85, 0.12, 0.12), yaw)
		return
	var spacing := 0.22
	for k in h:
		var p := c + along * (k - (h - 1) / 2.0) * spacing
		_house(holder, _w(p, TOP + 0.03), Vector3(0.16, 0.13, 0.16), Color(0.15, 0.62, 0.25), yaw)


func _house(parent: Node3D, base: Vector3, size: Vector3, color: Color, yaw: float) -> void:
	var node := Node3D.new()
	node.position = base
	node.rotation.y = yaw
	parent.add_child(node)
	_box(size, Vector3(0, size.y / 2.0, 0), _mat(color, 0.5), node)
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x * 1.05, size.y * 0.7, size.z * 1.05)
	roof.mesh = prism
	roof.material_override = _mat(color.darkened(0.3), 0.5)
	roof.position = Vector3(0, size.y + size.y * 0.35, 0)
	roof.rotation.y = PI / 2.0
	node.add_child(roof)
	# Aparición con rebote
	node.scale = Vector3.ONE * 0.01
	create_tween().tween_property(node, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
			_anim[int(ev["player"])]["queue"].append(BoardLayout.rect(controller.board.jail_index).get_center())
		"turn_started":
			if cinematic:
				_focus_player(int(ev["player"]))


func _on_drained() -> void:
	_follow = -1
	_cam_target = Vector3.ZERO
	_cam_dist = 15.5


func _focus_player(pid: int) -> void:
	if not _tokens.has(pid):
		return
	var pos: int = controller.engine.player(pid)["pos"]
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
		var end := Vector3((k - (count - 1) / 2.0) * 0.62 + _rng.randf_range(-0.1, 0.1), TOP + DIE / 2.0, 3.5 + _rng.randf_range(-0.15, 0.15))
		var start := end + Vector3(_rng.randf_range(-1.5, 1.5), 2.2, 2.4)
		var final_rot := _face_up_rotation(v) + Vector3(0, _rng.randf_range(-0.4, 0.4), 0)
		var spin := Vector3(_rng.randf_range(8, 16), _rng.randf_range(-6, 6), _rng.randf_range(8, 16)) * (1 if _rng.randf() < 0.5 else -1)
		var dur := EventPlayer.DICE_TIME * 0.85
		_dice_tween.tween_method(func(t: float):
			var xz := start.lerp(end, 1.0 - pow(1.0 - t, 2.0))
			var fall := maxf(0.0, 1.0 - t * 3.0) * (start.y - end.y)
			var bounce := absf(sin(t * PI * 3.0)) * (1.0 - t) * 0.6 if t > 0.33 else 0.0
			die.position = Vector3(xz.x, end.y + fall + bounce, xz.z)
			var u := (1.0 - t) * (1.0 - t)
			# Rotación final con orden YXZ: la cara elegida queda arriba.
			die.rotation = Vector3(final_rot.x + spin.x * u, final_rot.y + spin.y * u, final_rot.z + spin.z * u)
		, 0.0, 1.0, dur)


func _snap_tokens() -> void:
	if controller == null or controller.engine == null:
		return
	for pid in _anim:
		_anim[pid]["queue"].clear()
		_anim[pid]["pos"] = _rest_point(pid)
		_anim[pid]["from"] = _anim[pid]["pos"]
		_place_token(pid, 0.0)


func _rest_point(pid: int) -> Vector2:
	var e := controller.engine
	var space: int = e.player(pid)["pos"]
	var here := []
	for p in e.players():
		if not p["bankrupt"] and int(p["pos"]) == space:
			here.append(int(p["id"]))
	return BoardLayout.token_point(space, maxi(0, here.find(pid)), here.size())


func _place_token(pid: int, hop: float) -> void:
	var tok: Node3D = _tokens[pid]
	var a: Dictionary = _anim[pid]
	tok.position = _w(a["pos"], TOP + hop)


func _process(delta: float) -> void:
	if controller == null or controller.engine == null:
		return
	for pid in _anim:
		var a: Dictionary = _anim[pid]
		var hop := 0.0
		if not a["queue"].is_empty():
			a["t"] += delta / EventPlayer.STEP_TIME
			var target: Vector2 = a["queue"][0]
			var t := minf(a["t"], 1.0)
			a["pos"] = a["from"].lerp(target, t)
			hop = sin(t * PI) * 0.35
			var dir: Vector2 = target - a["from"]
			if dir.length() > 0.01:
				_tokens[pid].rotation.y = lerp_angle(_tokens[pid].rotation.y, atan2(-dir.x, -dir.y), minf(1.0, delta * 12.0))
			if a["t"] >= 1.0:
				a["from"] = target
				a["t"] = 0.0
				a["queue"].pop_front()
		else:
			var rest := _rest_point(pid)
			a["pos"] = a["pos"].lerp(rest, minf(1.0, delta * 8.0))
			a["from"] = a["pos"]
		_place_token(pid, hop)
	# Cámara cinemática: sigue a la ficha que se mueve y gira hacia su lado del tablero.
	if _follow >= 0 and _tokens.has(_follow):
		var tp: Vector3 = _tokens[_follow].position
		_cam_target = tp * 0.85
		_cam_dist = 9.5
		var space := BoardLayout.space_at(_anim[_follow]["pos"])
		if space >= 0:
			_cam_yaw = [0.0, -PI / 2.0, PI, PI / 2.0][BoardLayout.side(space)]
	_update_camera(delta)


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
