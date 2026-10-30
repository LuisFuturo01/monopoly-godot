class_name UiKit
extends RefCounted
## Tema claro y juvenil compartido por menú y HUD: tarjetas blancas con sombra suave,
## botones tipo píldora grandes (>= 52 px de alto para dedos) y acentos de color vivos.

const PANEL := Color("#ffffff")
const SOFT := Color("#f1f2f6")
const TEXT := Color("#2d3436")
const MUTED := Color("#7f8c8d")
const ACCENT := Color("#6c5ce7")     # violeta: acción principal
const ACCENT_2 := Color("#00cec9")   # menta
const GOLD := Color("#fdcb6e")
const CORAL := Color("#ff7675")
const DANGER := Color("#e84357")
const GOOD := Color("#00b894")

static var _theme: Theme
static var _font: SystemFont


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Nunito", "Poppins", "Segoe UI", "Roboto", "Arial"])
		_font.font_weight = 700
	return _font


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 19
	t.set_stylebox("panel", "PanelContainer", card())
	t.set_stylebox("panel", "Panel", card())
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(PANEL, 26, 18, 10, ACCENT.lightened(0.55), 2, true))
		t.set_stylebox("hover", type, box(Color("#f3f0ff"), 26, 18, 10, ACCENT, 2, true))
		t.set_stylebox("pressed", type, box(Color("#e4ddff"), 26, 18, 10, ACCENT, 2))
		t.set_stylebox("disabled", type, box(SOFT, 26, 18, 10))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, ACCENT.darkened(0.2))
		t.set_color("font_hover_color", type, ACCENT.darkened(0.3))
		t.set_color("font_pressed_color", type, ACCENT.darkened(0.3))
		t.set_color("font_disabled_color", type, Color("#b2bec3"))
	for type in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, box(SOFT, 14, 12, 8))
		t.set_stylebox("hover", type, box(Color("#e9e6ff"), 14, 12, 8))
		t.set_stylebox("pressed", type, box(SOFT, 14, 12, 8))
		t.set_stylebox("hover_pressed", type, box(Color("#e9e6ff"), 14, 12, 8))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(c, type, TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", box(SOFT, 14, 14, 10))
	t.set_stylebox("focus", "LineEdit", box(PANEL, 14, 14, 10, ACCENT, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color("#b2bec3"))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font())
	t.set_stylebox("slider", "HSlider", box(SOFT, 6, 0, 4))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT_2, 6, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT_2, 6, 0, 4))
	t.set_stylebox("panel", "PopupMenu", card())
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", ACCENT)
	t.set_stylebox("hover", "PopupMenu", box(Color("#f3f0ff"), 10, 8, 6))
	t.set_stylebox("panel", "TooltipPanel", box(TEXT, 10, 10, 6))
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	_theme = t
	return t


static func box(color: Color, radius: int = 16, mx: int = 14, my: int = 12, border: Color = Color(0, 0, 0, 0), border_w: int = 2, shadow: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	sb.anti_aliasing = true
	if border.a > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	if shadow:
		sb.shadow_color = Color(0.17, 0.12, 0.35, 0.18)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 4)
	return sb


## Tarjeta blanca con sombra suave.
static func card(color: Color = PANEL, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	return box(color, 24, 20, 18, border, 3, true)


static func label(text: String, font_size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Botón píldora. `accent` = acción principal (relleno de color).
static func button(text: String, cb: Callable, accent: bool = false, color: Color = ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 54)
	if accent:
		b.add_theme_stylebox_override("normal", box(color, 26, 22, 10, Color(0, 0, 0, 0), 0, true))
		b.add_theme_stylebox_override("hover", box(color.lightened(0.12), 26, 22, 10, Color(0, 0, 0, 0), 0, true))
		b.add_theme_stylebox_override("pressed", box(color.darkened(0.12), 26, 22, 10))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, Color.WHITE)
	b.pressed.connect(func():
		Sfx.play("click")
		_bounce(b)
		cb.call())
	return b


static func _bounce(c: Control) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(0.94, 0.94), 0.06)
	tw.tween_property(c, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)


static func vbox(sep: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(child: Control, color: Color = PANEL, border: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card(color, border))
	p.add_child(child)
	return p


## Centra un panel sobre un fondo velado que bloquea clics; entra con un pequeño rebote.
static func modal(content: Control, parent: Control) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.18, 0.12, 0.35, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	center.add_child(content)
	parent.add_child(dim)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.15)
	content.scale = Vector2(0.9, 0.9)
	content.resized.connect(func(): content.pivot_offset = content.size / 2.0)
	content.create_tween().tween_property(content, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return dim


static func swatch(color: Color, size: Vector2 = Vector2(18, 18)) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = size
	p.add_theme_stylebox_override("panel", box(color, int(minf(size.x, size.y) / 2.0), 0, 0))
	return p


static func token_icon(token: String, color: Color, size: float = 36.0) -> Control:
	var c := TokenIcon.new()
	c.token = token
	c.color = color
	c.custom_minimum_size = Vector2(size, size)
	return c


## Fondo degradado vivo para el menú y pantallas completas.
static func gradient_bg() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color("#6c5ce7"))
	g.set_color(1, Color("#fd79a8"))
	g.add_point(0.55, Color("#a29bfe"))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	tex.width = 64
	tex.height = 64
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


class TokenIcon extends Control:
	var token := "llama"
	var color := Color.WHITE

	func _draw() -> void:
		TokenArt.draw_2d(self, token, size / 2.0, minf(size.x, size.y) * 0.42, color)
