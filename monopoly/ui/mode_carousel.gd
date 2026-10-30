class_name ModeCarousel
extends Control
## Carrusel de tarjetas: la central grande, las vecinas más pequeñas y translúcidas.
## Se navega con flechas, arrastrando (mouse o dedo), con el teclado o tocando una tarjeta lateral.

signal chosen(index: int)

const CARD_SIZE := Vector2(330, 400)
const SPACING := 300.0

var items: Array = []        # {title, subtitle, color, icon, bullets}
var index := 0

var _cards: Array = []
var _pos := 0.0               # posición animada (float) hacia `index`
var _drag_from := -1.0
var _drag_x := 0.0
var _dots: HBoxContainer


func setup(p_items: Array) -> void:
	items = p_items
	custom_minimum_size = Vector2(0, CARD_SIZE.y + 90)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = false
	for i in items.size():
		var card := _make_card(items[i], i)
		add_child(card)
		_cards.append(card)
	_dots = UiKit.hbox(8)
	add_child(_dots)
	for arrow in [-1, 1]:
		var b := UiKit.button("‹" if arrow < 0 else "›", func(): go(index + arrow))
		b.custom_minimum_size = Vector2(56, 56)
		b.add_theme_font_size_override("font_size", 30)
		b.set_meta("arrow", arrow)
		add_child(b)
	_render_dots()


func go(i: int) -> void:
	var n := items.size()
	index = posmod(i, n)
	Sfx.play("card")
	_render_dots()


func _render_dots() -> void:
	for c in _dots.get_children():
		c.queue_free()
	for i in items.size():
		var on := i == index
		_dots.add_child(UiKit.swatch(UiKit.ACCENT if on else Color(1, 1, 1, 0.45), Vector2(26 if on else 10, 10)))


func _make_card(item: Dictionary, i: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.add_theme_stylebox_override("panel", UiKit.card())
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := UiKit.vbox(10)
	card.add_child(v)
	var art := ModeIcon.new()
	art.kind = item["icon"]
	art.color = item["color"]
	art.custom_minimum_size = Vector2(0, 170)
	v.add_child(art)
	var title := UiKit.label(item["title"], 26, UiKit.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiKit.font_black())
	v.add_child(title)
	var sub := UiKit.label(item["subtitle"], 15, UiKit.MUTED, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	for bullet in item.get("bullets", []):
		var row := UiKit.hbox(8)
		row.add_child(UiKit.swatch(item["color"], Vector2(8, 8)))
		var bl := UiKit.label(bullet, 14, UiKit.TEXT)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(bl)
		v.add_child(row)
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and absf(_drag_x) < 10.0:
			if i == index:
				chosen.emit(i)
			else:
				go(i))
	return card


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_from = event.position.x
			_drag_x = 0.0
		else:
			if absf(_drag_x) > 60.0:
				go(index + (1 if _drag_x < 0 else -1))
			_drag_from = -1.0
			_drag_x = 0.0
	elif event is InputEventMouseMotion and _drag_from >= 0.0:
		_drag_x = event.position.x - _drag_from
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_LEFT:
			go(index - 1)
		elif event.keycode == KEY_RIGHT:
			go(index + 1)
		elif event.keycode in [KEY_ENTER, KEY_SPACE]:
			chosen.emit(index)


func _process(delta: float) -> void:
	if _cards.is_empty():
		return
	var n := items.size()
	# Camino más corto alrededor del carrusel.
	var target := float(index)
	if absf(target - _pos) > n / 2.0:
		_pos += n if target > _pos else -n
	_pos = lerpf(_pos, target, minf(1.0, delta * 9.0))
	var center := Vector2(size.x / 2.0, CARD_SIZE.y / 2.0 + 10)
	var order := []
	for i in n:
		var d := float(i) - _pos
		if d > n / 2.0:
			d -= n
		elif d < -n / 2.0:
			d += n
		d += _drag_x / SPACING
		var card: Control = _cards[i]
		var s := clampf(1.0 - absf(d) * 0.18, 0.6, 1.0)
		card.pivot_offset = CARD_SIZE / 2.0
		card.scale = Vector2(s, s)
		card.position = center + Vector2(d * SPACING, 0) - CARD_SIZE / 2.0
		card.modulate.a = clampf(1.15 - absf(d) * 0.45, 0.0, 1.0)
		card.visible = absf(d) < 2.2
		card.rotation = d * 0.04
		order.append([absf(d), card])
	order.sort_custom(func(a, b): return a[0] > b[0])
	for k in order.size():
		move_child(order[k][1], k)
	for c in get_children():
		if c.has_meta("arrow"):
			var side: int = c.get_meta("arrow")
			c.position = Vector2(size.x / 2.0 + side * (CARD_SIZE.x / 2.0 + 40) - 28, center.y - 28)
			move_child(c, get_child_count() - 1)
	_dots.position = Vector2(size.x / 2.0 - _dots.size.x / 2.0, CARD_SIZE.y + 40)


class ModeIcon extends Control:
	## Ilustración simple dibujada por código para cada modo.
	var kind := "ai"
	var color := Color.WHITE
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := UiKit.box(color, 18, 0, 0)
		draw_style_box(sb, r)
		draw_circle(Vector2(size.x * 0.85, size.y * 0.15), size.y * 0.35, Color(1, 1, 1, 0.08))
		draw_circle(Vector2(size.x * 0.1, size.y * 0.95), size.y * 0.3, Color(1, 1, 1, 0.08))
		var c := size / 2.0 + Vector2(0, sin(_t * 2.0) * 4.0)
		var w := Color.WHITE
		match kind:
			"ai":
				draw_style_box(UiKit.box(w, 18, 0, 0), Rect2(c - Vector2(52, 38), Vector2(104, 76)))
				draw_line(c + Vector2(0, -38), c + Vector2(0, -58), w, 5)
				draw_circle(c + Vector2(0, -62), 8, UiKit.ACCENT)
				var blink := 1.0 if fmod(_t, 3.0) > 0.12 else 0.15
				for sx in [-1, 1]:
					draw_rect(Rect2(c + Vector2(sx * 22 - 9, -14 * blink), Vector2(18, 28 * blink)), color)
				draw_rect(Rect2(c + Vector2(-22, 18), Vector2(44, 6)), color)
			"local":
				for sx in [-1, 1]:
					var p := c + Vector2(sx * 34, 0)
					draw_circle(p + Vector2(0, -26), 18, w)
					draw_arc(p + Vector2(0, 40), 34, PI, TAU, 24, w, 14)
				var a := fmod(_t, 2.0) / 2.0
				draw_circle(c + Vector2(lerpf(-34, 34, a), -60), 7, UiKit.ACCENT)
			"wifi":
				var base := c + Vector2(0, 34)
				for k in 3:
					var on := int(_t * 2.0) % 4 > k
					draw_arc(base, 26 + k * 24, -PI * 0.78, -PI * 0.22, 24, w if on else Color(1, 1, 1, 0.35), 9)
				draw_circle(base, 9, w)
			"bt":
				var pts := PackedVector2Array([c + Vector2(-26, -26), c + Vector2(26, 22), c + Vector2(0, 46), c + Vector2(0, -46), c + Vector2(26, -22), c + Vector2(-26, 26)])
				draw_polyline(pts, w, 9, true)
				var pulse := fmod(_t, 1.5) / 1.5
				draw_arc(c, 60 + pulse * 20, 0, TAU, 40, Color(1, 1, 1, 0.5 * (1.0 - pulse)), 4)
