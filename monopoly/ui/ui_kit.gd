class_name UiKit
extends RefCounted
## Tema y constructores de controles compartidos por menú y HUD.

const BG := Color(0.07, 0.09, 0.11, 0.94)
const PANEL := Color(0.12, 0.15, 0.18, 0.96)
const ACCENT := Color(0.96, 0.74, 0.22)
const TEXT := Color(0.94, 0.94, 0.92)
const MUTED := Color(0.65, 0.68, 0.7)
const DANGER := Color(0.86, 0.3, 0.26)
const GOOD := Color(0.3, 0.75, 0.42)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 14))
	t.set_stylebox("panel", "Panel", box(PANEL, 14))
	t.set_stylebox("normal", "Button", box(Color(0.2, 0.24, 0.28), 10, 14, 9))
	t.set_stylebox("hover", "Button", box(Color(0.27, 0.32, 0.37), 10, 14, 9))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.25), 10, 14, 9))
	t.set_stylebox("disabled", "Button", box(Color(0.16, 0.18, 0.2, 0.7), 10, 14, 9))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 10, 14, 9, ACCENT))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.55))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", box(Color(0.08, 0.1, 0.12), 8, 10, 7))
	t.set_stylebox("focus", "LineEdit", box(Color(0.08, 0.1, 0.12), 8, 10, 7, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	_theme = t
	return t


static func box(color: Color, radius: int = 10, mx: int = 14, my: int = 12, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	if border.a > 0:
		sb.set_border_width_all(2)
		sb.border_color = border
	return sb


static func label(text: String, font_size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	if accent:
		b.add_theme_stylebox_override("normal", box(ACCENT, 10, 14, 9))
		b.add_theme_stylebox_override("hover", box(ACCENT.lightened(0.15), 10, 14, 9))
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.04))
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.04))
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(child: Control, color: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, 14, 18, 16))
	p.add_child(child)
	return p


## Centra un panel sobre un fondo oscurecido que bloquea clics.
static func modal(content: Control, parent: Control) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	center.add_child(content)
	parent.add_child(dim)
	return dim


static func swatch(color: Color, size: Vector2 = Vector2(18, 18)) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = size
	return c


static func token_icon(token: String, color: Color, size: float = 36.0) -> Control:
	var c := TokenIcon.new()
	c.token = token
	c.color = color
	c.custom_minimum_size = Vector2(size, size)
	return c


class TokenIcon extends Control:
	var token := "llama"
	var color := Color.WHITE

	func _draw() -> void:
		TokenArt.draw_2d(self, token, size / 2.0, minf(size.x, size.y) * 0.42, color)
