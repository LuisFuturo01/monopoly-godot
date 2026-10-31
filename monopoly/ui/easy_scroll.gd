class_name EasyScroll
extends Control
## Lista desplazable cómoda en el celular:
## - se arrastra con el dedo (o el mouse) en cualquier punto, con inercia;
## - botones grandes ▲ ▼ que avanzan una página, visibles solo si hay más contenido;
## - barra gruesa con el color de acento.
## Un arrastre nunca se convierte en clic, así no se pulsa nada (ni se cierra nada) por accidente.

const DRAG_START := 14.0

var scroll: ScrollContainer
var _up: Button
var _down: Button
var _press_y := -1.0
var _press_scroll := 0.0
var _dragging := false
var _velocity := 0.0
var _last_y := 0.0
var _last_t := 0
var _tween: Tween
var _muted: BaseButton           # botón bajo el dedo, anulado mientras se arrastra
var _muted_was_disabled := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	add_child(scroll)
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 12
	bar.add_theme_stylebox_override("scroll", UiKit.box(Color(0.5, 0.58, 0.7, 0.18), 6, 0, 0))
	bar.add_theme_stylebox_override("grabber", UiKit.box(UiKit.ACCENT, 6, 0, 0))
	bar.add_theme_stylebox_override("grabber_highlight", UiKit.box(UiKit.ACCENT.lightened(0.1), 6, 0, 0))
	bar.add_theme_stylebox_override("grabber_pressed", UiKit.box(UiKit.ACCENT.darkened(0.1), 6, 0, 0))
	_up = _pager("▲", -1)
	_down = _pager("▼", 1)


## Envuelve `content` en una lista desplazable de alto `height` (0 = la llena su contenedor).
static func wrap(content: Control, height: float = 0.0) -> EasyScroll:
	var es := EasyScroll.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	es.scroll.add_child(content)
	if height > 0.0:
		es.custom_minimum_size = Vector2(0, height)
	es.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return es


func _pager(text: String, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(52, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_stylebox_override("normal", UiKit.box(UiKit.NAVY, 26, 0, 0, Color.WHITE, 3, true))
	b.add_theme_stylebox_override("hover", UiKit.box(UiKit.NAVY.lightened(0.15), 26, 0, 0, UiKit.ACCENT, 3, true))
	b.add_theme_stylebox_override("pressed", UiKit.box(UiKit.ACCENT, 26, 0, 0, Color.WHITE, 3))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 0.0 if dir < 0 else 1.0
	b.anchor_bottom = b.anchor_top
	b.offset_left = -70
	b.offset_right = -18
	b.offset_top = 6 if dir < 0 else -58
	b.offset_bottom = b.offset_top + 52
	b.modulate.a = 0.0
	b.visible = false
	b.pressed.connect(func():
		Sfx.play("click")
		page(dir))
	add_child(b)
	return b


## Avanza (1) o retrocede (-1) casi una pantalla con una animación suave.
func page(dir: int) -> void:
	_velocity = 0.0
	var target := clampf(scroll.scroll_vertical + dir * size.y * 0.8, 0.0, _max_scroll())
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(scroll, "scroll_vertical", int(target), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _max_scroll() -> float:
	var bar := scroll.get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var inside := get_global_rect().has_point(event.global_position)
			var on_pager := (_up.visible and _up.get_global_rect().has_point(event.global_position)) or (_down.visible and _down.get_global_rect().has_point(event.global_position))
			if inside and not on_pager and _max_scroll() > 0.0:
				_press_y = event.global_position.y
				_press_scroll = scroll.scroll_vertical
				_last_y = _press_y
				_last_t = Time.get_ticks_msec()
				_velocity = 0.0
				_dragging = false
				if _tween:
					_tween.kill()
		else:
			if _muted:
				call_deferred("_restore_child")
			_press_y = -1.0
			_dragging = false
	elif event is InputEventMouseMotion and _press_y >= 0.0:
		var dy: float = event.global_position.y - _press_y
		if not _dragging and absf(dy) > DRAG_START:
			_dragging = true
			_cancel_child_press()
		if _dragging:
			scroll.scroll_vertical = int(clampf(_press_scroll - dy, 0.0, _max_scroll()))
			var now := Time.get_ticks_msec()
			var dt := maxf(1.0, now - _last_t) / 1000.0
			_velocity = lerpf(_velocity, -(event.global_position.y - _last_y) / dt, 0.5)
			_last_y = event.global_position.y
			_last_t = now
			get_viewport().set_input_as_handled()


## Anula el botón que quedó presionado bajo el dedo: al soltar no dispara su acción.
func _cancel_child_press() -> void:
	var c := get_viewport().gui_get_hovered_control()
	while c and not c is BaseButton and c != self:
		c = c.get_parent_control()
	if c is BaseButton and is_ancestor_of(c):
		_muted = c
		_muted_was_disabled = _muted.disabled
		_muted.disabled = true


func _restore_child() -> void:
	if is_instance_valid(_muted):
		_muted.disabled = _muted_was_disabled
	_muted = null


func _process(delta: float) -> void:
	if not _dragging and absf(_velocity) > 20.0:
		scroll.scroll_vertical = int(clampf(scroll.scroll_vertical + _velocity * delta, 0.0, _max_scroll()))
		_velocity *= pow(0.04, delta)
	var max_s := _max_scroll()
	_fade(_up, max_s > 0.0 and scroll.scroll_vertical > 4)
	_fade(_down, max_s > 0.0 and scroll.scroll_vertical < max_s - 4)


func _fade(b: Button, on: bool) -> void:
	if on:
		b.visible = true
		b.modulate.a = minf(1.0, b.modulate.a + 0.15)
	elif b.visible:
		b.modulate.a -= 0.15
		if b.modulate.a <= 0.0:
			b.visible = false
