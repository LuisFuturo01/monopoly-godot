class_name BoardView2D
extends Control
## Vista cenital 2D: dibujo procedural del tablero, fichas, edificios y dados.
## Solo lee el estado del motor y reacciona a eventos; nunca lo modifica.

signal space_clicked(index: int)

const PAPER := Color("#fbf8f1")
const FELT := Color("#2f8f6e")
const FELT_2 := Color("#247a5c")
const INK := Color("#13233f")
const RIM := Color("#13233f")
const TRIM := Color("#f2a541")
const CORNER_COLORS := {"go": Color("#bfeedd"), "jail": Color("#ffe2b8"), "free": Color("#cfe3ff"), "gotojail": Color("#ffc9c4")}

var controller: GameController
var active := true
## Margen reservado por el HUD (px).
var margin_top := 108.0
var margin_bottom := 150.0
var highlight := -1

var _scale := 40.0
var _origin := Vector2.ZERO
var _tokens: Dictionary = {}        # pid -> {pos, from, queue, t}
var _dice := [1, 1, 0]
var _dice_t := -1.0
var _rng := RandomNumberGenerator.new()
var _font: Font
var _pop: Dictionary = {}           # casilla -> progreso 0..1 de la obra
var _font_black: Font
var _sb := StyleBoxFlat.new()
var _time := 0.0
var _badge: Texture2D = preload("res://branding/splash_round.png")


func _ready() -> void:
	_font = UiKit.font()
	_font_black = UiKit.font_black()
	_sb.anti_aliasing = true
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
	_time += delta
	var animating := true   # pulso de la casilla actual y banderines
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
	_draw_background()
	if controller == null or controller.engine == null:
		return
	var avail := Vector2(size.x - 24.0, size.y - margin_top - margin_bottom)
	_scale = minf(avail.x, avail.y) / BoardLayout.SIZE
	var board_px := BoardLayout.SIZE * _scale
	_origin = Vector2((size.x - board_px) / 2.0, margin_top + (avail.y - board_px) / 2.0)
	var outer := Rect2(_origin - Vector2(12, 12), Vector2(board_px + 24, board_px + 24))
	_rbox(Rect2(outer.position + Vector2(0, 10), outer.size), Color(0, 0, 0, 0.3), 22)
	_rbox(outer, RIM, 22, TRIM, 3)
	_rbox(Rect2(_origin - Vector2(3, 3), Vector2(board_px + 6, board_px + 6)), Color("#d7dde5"), 6)
	var inner := BoardLayout.CORNER * _scale
	var felt := Rect2(_origin + Vector2(inner, inner), Vector2(board_px - inner * 2, board_px - inner * 2))
	_rbox(felt, FELT, 4)
	# Trama suave del paño
	for k in range(1, 12):
		var y := felt.position.y + felt.size.y * k / 12.0
		draw_line(Vector2(felt.position.x, y), Vector2(felt.end.x, y), FELT_2, 1.0)
	for i in controller.board.size():
		_draw_space(i)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_center(board_px)
	_draw_tokens()
	_draw_dice(board_px)


## Fondo degradado azul noche a verde azulado (como el menú).
func _draw_background() -> void:
	var top := Color("#0b1d3a")
	var bottom := Color("#1b6b73")
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([top, top.lerp(bottom, 0.4), bottom, top.lerp(bottom, 0.6)]))


## Rectángulo redondeado con borde opcional (sirve con la transformación actual).
func _rbox(r: Rect2, color: Color, radius: float, border: Color = Color(0, 0, 0, 0), bw: float = 0.0) -> void:
	_sb.bg_color = color
	_sb.set_corner_radius_all(int(radius))
	_sb.border_color = border
	_sb.set_border_width_all(int(bw) if border.a > 0 else 0)
	draw_style_box(_sb, r)


func _px(p: Vector2) -> Vector2:
	return _origin + p * _scale


func _tile_color(i: int) -> Color:
	var b := controller.board
	var sp := b.space(i)
	match sp["type"]:
		"street":
			return b.space_color(i).lerp(Color.WHITE, 0.82)
		"transit":
			return Color("#e2e9f2")
		"utility":
			return Color("#fff1c9")
		"card":
			return UiKit.DESTINO.lerp(Color.WHITE, 0.35) if sp["deck"] == "destino" else UiKit.CABILDO.lerp(Color.WHITE, 0.45)
		"tax":
			return Color("#ffdcdc")
	return CORNER_COLORS.get(sp["type"], PAPER)


func _draw_space(i: int) -> void:
	var e := controller.engine
	var b := controller.board
	var sp := b.space(i)
	var r := BoardLayout.rect(i)
	var corner := BoardLayout.is_corner(i)
	var lw := (BoardLayout.CORNER if corner else BoardLayout.CELL) * _scale
	var lh := BoardLayout.CORNER * _scale
	draw_set_transform(_px(r.get_center()), BoardLayout.text_angle(i), Vector2.ONE)
	var box := Rect2(-lw / 2 + 1, -lh / 2 + 1, lw - 2, lh - 2)
	_rbox(box, _tile_color(i), 4)
	var fs := maxi(8, int(_scale * 0.17))
	var y := -lh / 2 + 4.0
	if sp["type"] == "street":
		var band := Rect2(-lw / 2 + 2, -lh / 2 + 2, lw - 4, BoardLayout.BAND * _scale)
		_rbox(band, b.space_color(i), 3)
		_draw_buildings(i, band)
		y = band.end.y + 2.0
	var title: String = sp["name"]
	var photo := UiKit.place_photo(i, title)
	if corner:
		if photo:
			_photo_rect(photo, box.grow(-3))
			_rbox(box.grow(-3), Color(1, 1, 1, 0.15), 3)
		_draw_corner(i, sp, lw, lh)
	elif photo:
		var ph := Rect2(-lw / 2 + 4, y + 2, lw - 8, lh * 0.36)
		_photo_rect(photo, ph)
		draw_multiline_string(_font_black, Vector2(-lw / 2 + 2, ph.end.y + fs + 1), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, lw - 4, fs, 2, INK)
	else:
		draw_multiline_string(_font_black, Vector2(-lw / 2 + 2, y + fs), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, lw - 4, fs, 3, INK)
	if not corner:
		var icon := "" if photo else _icon_for(sp)
		if icon != "":
			var icol := Color.WHITE if sp["type"] == "card" else INK.lerp(PAPER, 0.25)
			draw_string(_font_black, Vector2(-lw / 2, lh * 0.14 + fs), icon, HORIZONTAL_ALIGNMENT_CENTER, lw, int(fs * 2.1), icol)
		var price_text := ""
		if b.is_property(i):
			price_text = "Bs %d" % b.price(i)
		elif sp["type"] == "tax":
			price_text = "Paga Bs %d" % int(sp["amount"])
		if price_text != "":
			draw_string(_font, Vector2(-lw / 2, lh / 2 - 6), price_text, HORIZONTAL_ALIGNMENT_CENTER, lw, fs, Color("#1f7a68") if b.is_property(i) else Color("#c0392b"))
	# Dueño: marco grueso de su color y banderín; hipoteca: velo gris.
	var own := e.owner_of(i)
	if own >= 0:
		var col := Color.html(e.player(own)["color"])
		if e.is_mortgaged(i):
			_rbox(box, Color(0.25, 0.28, 0.35, 0.55), 4)
			draw_string(_font_black, Vector2(-lw / 2, 0), "HIPOTECA", HORIZONTAL_ALIGNMENT_CENTER, lw, fs, Color.WHITE)
		_rbox(box.grow(-1), Color(0, 0, 0, 0), 4, col, maxf(3.0, _scale * 0.07))
		var fx := lw / 2 - _scale * 0.22
		var fy := lh / 2 - _scale * 0.08
		var wave := sin(_time * 4.0 + i) * _scale * 0.03
		draw_line(Vector2(fx, fy), Vector2(fx, fy - _scale * 0.42), INK, 1.5)
		var low := 0.18 if e.is_mortgaged(i) else 0.0
		draw_colored_polygon(PackedVector2Array([Vector2(fx, fy - _scale * (0.42 - low)), Vector2(fx - _scale * 0.26, fy - _scale * (0.34 - low) + wave), Vector2(fx, fy - _scale * (0.26 - low))]), col)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_set_transform(_px(r.get_center()), BoardLayout.text_angle(i), Vector2.ONE)
	var hot := i == highlight or i == int(e.s["pending_buy"]) or (e.phase() == GameEngine.AUCTION and int(e.s["auction"].get("space", -1)) == i)
	if hot:
		var pulse := 0.6 + 0.4 * sin(_time * 6.0)
		_rbox(box.grow(-1.5), Color(0, 0, 0, 0), 5, Color(1.0, 0.82, 0.1, pulse), 4)


## Dibuja la foto llenando el rectángulo con recorte centrado (sin deformarla) y un borde blanco.
func _photo_rect(tex: Texture2D, r: Rect2) -> void:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var want := r.size.x / maxf(1.0, r.size.y)
	var src := Rect2(0, 0, tw, th)
	if tw / th > want:
		src.size.x = th * want
		src.position.x = (tw - src.size.x) / 2.0
	else:
		src.size.y = tw / want
		src.position.y = (th - src.size.y) / 2.0
	draw_texture_rect_region(tex, r, src)
	draw_rect(r, Color.WHITE, false, 1.5)


func _draw_corner(i: int, sp: Dictionary, lw: float, lh: float) -> void:
	var fs := maxi(9, int(_scale * 0.22))
	var labels := {"go": "SALIDA\ncobra Bs %d" % controller.board.salary, "jail": "RETÉN\nde visita", "free": "MIRADOR", "gotojail": "¡AL\nRETÉN!"}
	var icon := {"go": "»", "jail": "| | |", "free": "*", "gotojail": "!"}
	var t: String = labels.get(sp["type"], sp["name"])
	var ccol: Color = UiKit.CORNERS.get(sp["type"], INK)
	# Franja de color con el nombre en blanco, sobre la foto.
	var lines := t.count("\n") + 1
	var band := Rect2(-lw / 2 + 4, -fs * (lines * 0.65 + 0.35), lw - 8, fs * (lines * 1.3 + 0.7))
	_rbox(Rect2(band.position + Vector2(2, 3), band.size), Color(0, 0, 0, 0.25), 6)
	_rbox(band, ccol, 6, Color.WHITE, 2)
	draw_multiline_string(_font_black, Vector2(band.position.x, band.position.y + fs * 1.15), t, HORIZONTAL_ALIGNMENT_CENTER, band.size.x, fs, lines, Color.WHITE)
	if sp["type"] == "free" and controller.engine.rules.free_parking_pot:
		var pot := Rect2(-lw / 2 + 8, lh / 2 - fs * 2.0, lw - 16, fs * 1.6)
		_rbox(pot, Color(1, 1, 1, 0.9), 5)
		draw_string(_font_black, Vector2(pot.position.x, pot.end.y - fs * 0.4), "Bote Bs %d" % int(controller.engine.s["pot"]), HORIZONTAL_ALIGNMENT_CENTER, pot.size.x, fs, INK)


func _icon_for(sp: Dictionary) -> String:
	match sp["type"]:
		"transit":
			return "[ T ]"
		"utility":
			# La primera empresa de servicio es la de luz.
			return "( E )" if sp["name"] == controller.board.space(12)["name"] else "( A )"
		"card":
			return "?" if sp["deck"] == "destino" else "!"
		"tax":
			return "Bs"
	return ""


## Casas con techo a dos aguas y hotel con letrero «H»; crecen al construirse.
func _draw_buildings(i: int, band: Rect2) -> void:
	var h := controller.engine.houses_on(i)
	if h == 0:
		return
	var unit := band.size.y * 0.78
	if _pop.has(i):
		unit *= maxf(0.05, ease(_pop[i], -2.2))
	var base_y := band.get_center().y + unit * 0.42
	if h == GameEngine.HOTEL:
		var w := unit * 2.4
		var hr := Rect2(band.get_center().x - w / 2, base_y - unit * 0.85, w, unit * 0.85)
		_rbox(hr, Color("#d64550"), 2, INK, 1)
		draw_string(_font_black, Vector2(hr.position.x, hr.end.y - unit * 0.15), "H", HORIZONTAL_ALIGNMENT_CENTER, w, int(unit * 0.7), Color.WHITE)
		return
	var gap := (band.size.x - h * unit) / (h + 1)
	for k in h:
		var x := band.position.x + gap + k * (unit + gap)
		var body := PackedVector2Array([Vector2(x, base_y), Vector2(x + unit, base_y), Vector2(x + unit, base_y - unit * 0.5),
			Vector2(x + unit / 2, base_y - unit * 0.95), Vector2(x, base_y - unit * 0.5)])
		draw_colored_polygon(body, Color("#3fae6a"))
		draw_colored_polygon(PackedVector2Array([Vector2(x - 1, base_y - unit * 0.5), Vector2(x + unit / 2, base_y - unit * 0.98), Vector2(x + unit + 1, base_y - unit * 0.5)]), Color("#b5523b"))
		draw_polyline(body + PackedVector2Array([body[0]]), INK, 1.0)


## Centro: la insignia de Luchopolis y los mazos en diagonal, cada uno en su esquina del paño
## (antes el mazo de Cabildo tapaba el nombre).
func _draw_center(board_px: float) -> void:
	var c := _origin + Vector2(board_px, board_px) / 2.0
	var side := _scale * 4.4
	draw_circle(c + Vector2(0, -_scale * 0.5) + Vector2(4, 8), side * 0.47, Color(0, 0, 0, 0.25))
	draw_texture_rect(_badge, Rect2(c + Vector2(-side / 2, -side / 2 - _scale * 0.5), Vector2(side, side)), false)
	var deck_size := Vector2(2.1, 1.35) * _scale
	for k in 2:
		var dc := c + (Vector2(-3.2, -3.2) if k == 0 else Vector2(3.2, 3.2)) * _scale
		var col := UiKit.DESTINO if k == 0 else UiKit.CABILDO
		draw_set_transform(dc, -PI / 4.0, Vector2.ONE)
		var r := Rect2(-deck_size / 2.0, deck_size)
		for layer in [3, 2, 1]:
			_rbox(Rect2(r.position + Vector2(layer * 2.5, layer * 2.5), deck_size), col.darkened(0.2 + layer * 0.08), 8)
		_rbox(r, col, 8, Color.WHITE, 2)
		draw_string(_font_black, r.position + Vector2(0, deck_size.y * 0.52), "?" if k == 0 else "!", HORIZONTAL_ALIGNMENT_CENTER, deck_size.x, int(_scale * 0.55), Color.WHITE)
		draw_string(_font_black, r.position + Vector2(0, deck_size.y * 0.86), "DESTINO" if k == 0 else "CABILDO", HORIZONTAL_ALIGNMENT_CENTER, deck_size.x, maxi(8, int(_scale * 0.28)), Color.WHITE)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if controller.engine.rules.free_parking_pot and int(controller.engine.s["pot"]) > 0:
		var pot := "Bote: Bs %d" % int(controller.engine.s["pot"])
		draw_string(_font_black, c + Vector2(-board_px / 2, _scale * 2.15), pot, HORIZONTAL_ALIGNMENT_CENTER, board_px, maxi(9, int(_scale * 0.3)), TRIM)


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
		draw_set_transform(pos + Vector2(0, rr * 0.9 + hop * 0.5), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, rr * (1.0 - hop / (_scale * 0.5)), Color(0, 0, 0, 0.3))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if pid == e.current():
			draw_arc(pos, rr * 1.35, 0, TAU, 32, Color(1.0, 0.82, 0.1, 0.6 + 0.4 * sin(_time * 5.0)), 3.0)
		TokenArt.draw_2d(self, p["token"], pos, rr, Color.html(p["color"]))
		if p["in_jail"]:
			for k in 3:
				draw_line(pos + Vector2(-rr + k * rr, -rr), pos + Vector2(-rr + k * rr, rr), Color(0.2, 0.2, 0.2), 2.0)


func _draw_dice(board_px: float) -> void:
	var c := _origin + Vector2(board_px, board_px) / 2.0 + Vector2(0, 2.95) * _scale
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
		_rbox(Rect2(rect.position + Vector2(3, 5), rect.size), Color(0, 0, 0, 0.35), sz * 0.2)
		_rbox(rect, Color("#d64550") if k == 2 else Color.WHITE, sz * 0.2, INK.lerp(Color.WHITE, 0.6), 1.5)
		if k == 2:
			var face := int(d[2])
			var txt := str(face) if face <= 3 else ("»" if face == GameEngine.SPEED_BOLT else "Bs")
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
