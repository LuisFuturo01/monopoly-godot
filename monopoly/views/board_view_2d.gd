class_name BoardView2D
extends Control
## Vista cenital 2D: dibujo procedural del tablero, fichas, edificios y dados.
## Solo lee el estado del motor y reacciona a eventos; nunca lo modifica.

signal space_clicked(index: int)

const TABLE := Color("#2ec4b6")
const PAPER := Color("#fffaf0")
const CENTER_FILL := Color("#b8e994")
const INK := Color("#2d3436")
const RIM := Color("#6c5ce7")

var controller: GameController
var active := true
## Margen reservado por el HUD (px).
var margin_top := 84.0
var margin_bottom := 120.0
var highlight := -1

var _scale := 40.0
var _origin := Vector2.ZERO
var _tokens: Dictionary = {}        # pid -> {pos, from, queue, t}
var _dice := [1, 1, 0]
var _dice_t := -1.0
var _rng := RandomNumberGenerator.new()
var _font: Font
var _pop: Dictionary = {}           # casilla -> progreso 0..1 de la obra


func _ready() -> void:
	_font = UiKit.font()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func bind(c: GameController) -> void:
	controller = c
	controller.state_changed.connect(queue_redraw)
	controller.player_events.event_played.connect(_on_event)
	_snap_tokens()


func set_active(on: bool) -> void:
	active = on
	visible = on
	set_process(on)
	if on:
		_snap_tokens()
		queue_redraw()


# ---------------------------------------------------------------------------
# Eventos y animación
# ---------------------------------------------------------------------------

func _on_event(ev: Dictionary) -> void:
	match ev["type"]:
		"dice_rolled":
			_dice = ev["dice"]
			_dice_t = 0.0
		"moved":
			var tok := _token(int(ev["player"]))
			for i in ev["path"]:
				tok["queue"].append(BoardLayout.rect(int(i)).get_center())
		"jailed":
			var tok2 := _token(int(ev["player"]))
			tok2["queue"].append(BoardLayout.rect(int(ev["space"])).get_center())
		"built":
			_pop[int(ev["space"])] = 0.0
	queue_redraw()


func _token(pid: int) -> Dictionary:
	if not _tokens.has(pid):
		_tokens[pid] = {"pos": Vector2.ZERO, "from": Vector2.ZERO, "queue": [], "t": 0.0}
	return _tokens[pid]


func _snap_tokens() -> void:
	if controller == null or controller.engine == null:
		return
	for p in controller.engine.players():
		var tok := _token(int(p["id"]))
		tok["queue"].clear()
		tok["pos"] = _rest_point(int(p["id"]))
		tok["from"] = tok["pos"]


func _rest_point(pid: int) -> Vector2:
	var e := controller.engine
	var shown: Dictionary = controller.player_events.shown_pos
	var space: int = shown.get(pid, e.player(pid)["pos"])
	var here := []
	for p in e.players():
		if not p["bankrupt"] and int(shown.get(int(p["id"]), p["pos"])) == space:
			here.append(int(p["id"]))
	return BoardLayout.token_point(space, maxi(0, here.find(pid)), here.size())


func _process(delta: float) -> void:
	if controller == null or controller.engine == null:
		return
	var animating := false
	for i in _pop.keys():
		_pop[i] += delta * 2.0
		if _pop[i] >= 1.0:
			_pop.erase(i)
		animating = true
	if _dice_t >= 0.0:
		_dice_t += delta
		if _dice_t > EventPlayer.DICE_TIME:
			_dice_t = -1.0
		animating = true
	for pid in _tokens:
		var tok: Dictionary = _tokens[pid]
		if not tok["queue"].is_empty():
			tok["t"] += delta / EventPlayer.STEP_TIME
			var target: Vector2 = tok["queue"][0]
			tok["pos"] = tok["from"].lerp(target, minf(tok["t"], 1.0))
			if tok["t"] >= 1.0:
				tok["from"] = target
				tok["t"] = 0.0
				tok["queue"].pop_front()
			animating = true
		elif pid < controller.engine.players().size():
			var rest := _rest_point(pid)
			if tok["pos"].distance_to(rest) > 0.01:
				tok["pos"] = tok["pos"].lerp(rest, minf(1.0, delta * 10.0))
				tok["from"] = tok["pos"]
				animating = true
	if animating:
		queue_redraw()


# ---------------------------------------------------------------------------
# Entrada
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := BoardLayout.space_at((event.position - _origin) / _scale)
		if i >= 0:
			space_clicked.emit(i)
			accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		var j := BoardLayout.space_at((event.position - _origin) / _scale)
		if j >= 0:
			space_clicked.emit(j)


# ---------------------------------------------------------------------------
# Dibujo
# ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), TABLE)
	if controller == null or controller.engine == null:
		return
	var avail := Vector2(size.x - 24.0, size.y - margin_top - margin_bottom)
	_scale = minf(avail.x, avail.y) / BoardLayout.SIZE
	var board_px := BoardLayout.SIZE * _scale
	_origin = Vector2((size.x - board_px) / 2.0, margin_top + (avail.y - board_px) / 2.0)
	draw_rect(Rect2(_origin + Vector2(6, 10), Vector2(board_px, board_px)), Color(0, 0, 0, 0.18))
	draw_rect(Rect2(_origin - Vector2(8, 8), Vector2(board_px + 16, board_px + 16)), RIM)
	draw_rect(Rect2(_origin, Vector2(board_px, board_px)), PAPER)
	var inner := BoardLayout.CORNER * _scale
	draw_rect(Rect2(_origin + Vector2(inner, inner), Vector2(board_px - inner * 2, board_px - inner * 2)), CENTER_FILL)
	for i in controller.board.size():
		_draw_space(i)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_center(board_px)
	_draw_tokens()
	_draw_dice(board_px)


func _px(p: Vector2) -> Vector2:
	return _origin + p * _scale


func _draw_space(i: int) -> void:
	var e := controller.engine
	var b := controller.board
	var sp := b.space(i)
	var r := BoardLayout.rect(i)
	var corner := BoardLayout.is_corner(i)
	var lw := (BoardLayout.CORNER if corner else BoardLayout.CELL) * _scale
	var lh := BoardLayout.CORNER * _scale
	draw_set_transform(_px(r.get_center()), BoardLayout.text_angle(i), Vector2.ONE)
	var box := Rect2(-lw / 2, -lh / 2, lw, lh)
	draw_rect(box, PAPER)
	var fs := maxi(7, int(_scale * 0.15))
	var y := -lh / 2 + 4.0
	if sp["type"] == "street":
		var band := Rect2(-lw / 2, -lh / 2, lw, BoardLayout.BAND * _scale)
		draw_rect(band, b.space_color(i))
		_draw_buildings(i, band)
		y = band.end.y + 2.0
	var title: String = sp["name"]
	if corner:
		_draw_corner(i, sp, lw, lh)
	else:
		draw_multiline_string(_font, Vector2(-lw / 2 + 2, y + fs), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, lw - 4, fs, 3, INK)
		var icon := _icon_for(sp)
		if icon != "":
			draw_string(_font, Vector2(-lw / 2, lh * 0.12 + fs), icon, HORIZONTAL_ALIGNMENT_CENTER, lw, int(fs * 1.9), INK.lerp(PAPER, 0.25))
		var price_text := ""
		if b.is_property(i):
			price_text = "$%d" % b.price(i)
		elif sp["type"] == "tax":
			price_text = "Paga $%d" % int(sp["amount"])
		if price_text != "":
			draw_string(_font, Vector2(-lw / 2, lh / 2 - 6), price_text, HORIZONTAL_ALIGNMENT_CENTER, lw, fs, INK)
	# Dueño e hipoteca
	var own := e.owner_of(i)
	if own >= 0:
		var col := Color.html(e.player(own)["color"])
		draw_rect(Rect2(-lw / 2, lh / 2 - 0.1 * _scale, lw, 0.1 * _scale), col)
		if e.is_mortgaged(i):
			draw_rect(box, Color(0.2, 0.2, 0.2, 0.55))
			draw_string(_font, Vector2(-lw / 2, 0), "HIPOTECA", HORIZONTAL_ALIGNMENT_CENTER, lw, fs, Color.WHITE)
	draw_rect(box, INK, false, 1.0)
	if i == highlight or i == int(e.s["pending_buy"]) or (e.phase() == GameEngine.AUCTION and int(e.s["auction"].get("space", -1)) == i):
		draw_rect(box.grow(-1.5), Color(1.0, 0.82, 0.1), false, 3.0)


func _draw_corner(i: int, sp: Dictionary, lw: float, lh: float) -> void:
	var tiles := {"go": Color("#55efc4"), "jail": Color("#fdcb6e"), "free": Color("#74b9ff"), "gotojail": Color("#ff7675")}
	draw_rect(Rect2(-lw / 2, -lh / 2, lw, lh), tiles.get(sp["type"], PAPER))
	var fs := maxi(8, int(_scale * 0.2))
	var labels := {"go": "SALIDA\ncobra $%d" % controller.board.salary, "jail": "RETÉN\nde visita", "free": "MIRADOR", "gotojail": "¡AL\nRETÉN!"}
	var icon := {"go": "<<<", "jail": "| | |", "free": "*", "gotojail": "!"}
	var t: String = labels.get(sp["type"], sp["name"])
	draw_multiline_string(_font, Vector2(-lw / 2 + 2, -lh / 2 + fs * 1.6), t, HORIZONTAL_ALIGNMENT_CENTER, lw - 4, fs, 3, INK)
	draw_string(_font, Vector2(-lw / 2, lh * 0.32), icon.get(sp["type"], ""), HORIZONTAL_ALIGNMENT_CENTER, lw, fs * 2, Color(0.75, 0.15, 0.12))
	if sp["type"] == "free" and controller.engine.rules.free_parking_pot:
		draw_string(_font, Vector2(-lw / 2, lh / 2 - 6), "Bote $%d" % int(controller.engine.s["pot"]), HORIZONTAL_ALIGNMENT_CENTER, lw, fs, INK)


func _icon_for(sp: Dictionary) -> String:
	match sp["type"]:
		"transit":
			return "[ T ]"
		"utility":
			return "( E )" if sp["name"].contains("Luz") else "( A )"
		"card":
			return "?" if sp["deck"] == "destino" else "!"
		"tax":
			return "$"
	return ""


func _draw_buildings(i: int, band: Rect2) -> void:
	var h := controller.engine.houses_on(i)
	if h == 0:
		return
	var unit := band.size.y * 0.7
	if _pop.has(i):
		unit *= maxf(0.05, ease(_pop[i], -2.2))
	if h == GameEngine.HOTEL:
		var hr := Rect2(band.get_center() - Vector2(unit * 1.2, unit / 2), Vector2(unit * 2.4, unit))
		draw_rect(hr, Color(0.85, 0.12, 0.12))
		draw_rect(hr, INK, false, 1.0)
		return
	var gap := (band.size.x - h * unit) / (h + 1)
	for k in h:
		var hr2 := Rect2(Vector2(band.position.x + gap + k * (unit + gap), band.get_center().y - unit / 2), Vector2(unit, unit))
		draw_rect(hr2, Color(0.15, 0.62, 0.25))
		draw_rect(hr2, INK, false, 1.0)


func _draw_center(board_px: float) -> void:
	var c := _origin + Vector2(board_px, board_px) / 2.0
	var fs := maxi(8, int(_scale * 0.75))
	draw_set_transform(c, -PI / 4.0, Vector2.ONE)
	draw_string(_font, Vector2(-board_px / 2, -fs * 0.2), "MAGNATES", HORIZONTAL_ALIGNMENT_CENTER, board_px, fs, Color("#fd79a8"))
	draw_string(_font, Vector2(-board_px / 2, fs * 0.6), controller.board.name, HORIZONTAL_ALIGNMENT_CENTER, board_px, maxi(6, int(fs * 0.35)), INK)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Mazos
	var deck_size := Vector2(2.0, 1.3) * _scale
	for k in 2:
		var pos := c + Vector2(-2.6 if k == 0 else 0.6, -3.4) * _scale
		var col := Color(0.95, 0.62, 0.15) if k == 0 else Color(0.35, 0.6, 0.85)
		draw_rect(Rect2(pos + Vector2(4, 4), deck_size), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(pos, deck_size), col)
		draw_rect(Rect2(pos, deck_size), INK, false, 1.5)
		draw_string(_font, pos + Vector2(0, deck_size.y * 0.6), "DESTINO" if k == 0 else "CABILDO", HORIZONTAL_ALIGNMENT_CENTER, deck_size.x, maxi(6, int(_scale * 0.28)), INK)


func _draw_tokens() -> void:
	var e := controller.engine
	var r := 0.17 * _scale
	for p in e.players():
		if p["bankrupt"]:
			continue
		var pid := int(p["id"])
		var tok := _token(pid)
		var hop := 0.0
		if not tok["queue"].is_empty():
			hop = sin(clampf(tok["t"], 0.0, 1.0) * PI) * 0.25 * _scale
		var pos := _px(tok["pos"]) - Vector2(0, hop)
		var rr := r * (1.25 if pid == e.current() else 1.0)
		TokenArt.draw_2d(self, p["token"], pos, rr, Color.html(p["color"]))
		if p["in_jail"]:
			for k in 3:
				draw_line(pos + Vector2(-rr + k * rr, -rr), pos + Vector2(-rr + k * rr, rr), Color(0.2, 0.2, 0.2), 2.0)


func _draw_dice(board_px: float) -> void:
	var c := _origin + Vector2(board_px, board_px) / 2.0 + Vector2(0, 2.4) * _scale
	var d := _dice
	if _dice_t >= 0.0 and _dice_t < EventPlayer.DICE_TIME * 0.8:
		d = [_rng.randi_range(1, 6), _rng.randi_range(1, 6), d[2]]
	var sz := 0.9 * _scale
	var count := 3 if int(d[2]) > 0 else 2
	for k in count:
		var pos := c + Vector2((k - (count - 1) / 2.0) * sz * 1.3 - sz / 2, -sz / 2)
		var jitter := Vector2.ZERO
		if _dice_t >= 0.0:
			jitter = Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)) * (1.0 - _dice_t)
		var rect := Rect2(pos + jitter, Vector2(sz, sz))
		draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.35))
		draw_rect(rect, Color(0.85, 0.15, 0.15) if k == 2 else Color.WHITE)
		draw_rect(rect, INK, false, 1.5)
		if k == 2:
			var face := int(d[2])
			var txt := str(face) if face <= 3 else ("»" if face == GameEngine.SPEED_BOLT else "$")
			draw_string(_font, rect.position + Vector2(0, sz * 0.72), txt, HORIZONTAL_ALIGNMENT_CENTER, sz, int(sz * 0.7), Color.WHITE)
		else:
			_draw_pips(rect, int(d[k]))


func _draw_pips(rect: Rect2, v: int) -> void:
	var c := rect.get_center()
	var o := rect.size.x * 0.27
	var pts := {
		1: [Vector2.ZERO],
		2: [Vector2(-o, -o), Vector2(o, o)],
		3: [Vector2(-o, -o), Vector2.ZERO, Vector2(o, o)],
		4: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, o), Vector2(o, o)],
		5: [Vector2(-o, -o), Vector2(o, -o), Vector2.ZERO, Vector2(-o, o), Vector2(o, o)],
		6: [Vector2(-o, -o), Vector2(o, -o), Vector2(-o, 0), Vector2(o, 0), Vector2(-o, o), Vector2(o, o)],
	}
	for p in pts.get(v, []):
		draw_circle(c + p, rect.size.x * 0.09, INK)
