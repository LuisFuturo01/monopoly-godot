class_name UiKit
extends RefCounted
## Tema compartido por menú y HUD: azul marino y verde azulado con acentos dorados,
## tarjetas blancas con sombra suave, botones píldora grandes (>= 54 px) que reaccionan
## al pasar el cursor y al presionar, y entradas animadas.

const NAVY := Color("#13233f")
const PANEL := Color("#ffffff")
const SOFT := Color("#eef2f7")
const TEXT := Color("#13233f")
const HEADING := Color("#13233f")
const MUTED := Color("#6b7a90")
const ACCENT := Color("#f2a541")     # dorado: acción principal
const ACCENT_2 := Color("#1f9e89")   # verde azulado
const GOLD := Color("#f2a541")
const CORAL := Color("#e8735a")
const DANGER := Color("#d64550")
const GOOD := Color("#1f9e89")
const LINE := Color("#d9e2ec")
## Puntos que se suman a todos los tamaños de letra (lectura cómoda en el celular).
const FONT_BOOST := 2
const DESTINO := Color("#f08a3c")    # cartas y casillas de Destino
const CABILDO := Color("#3d7be0")    # cartas y casillas de Cabildo
const PLACES_DIR := "res://data/places/"
## Color de cada esquina (franja del tablero y tarjeta al tocarla).
const CORNERS := {"go": Color("#1f9e89"), "jail": Color("#e8735a"), "free": Color("#3d7be0"), "gotojail": Color("#d64550")}

static var _theme: Theme
static var _photos: Dictionary = {}
static var _font: SystemFont
static var _font_black: SystemFont


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Nunito", "Poppins", "Segoe UI", "Roboto", "Arial"])
		_font.font_weight = 700
	return _font


static func font_black() -> SystemFont:
	if _font_black == null:
		_font_black = SystemFont.new()
		_font_black.font_names = PackedStringArray(["Nunito", "Poppins", "Segoe UI Black", "Segoe UI", "Roboto", "Arial"])
		_font_black.font_weight = 900
	return _font_black


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 19 + FONT_BOOST
	t.set_stylebox("panel", "PanelContainer", card())
	t.set_stylebox("panel", "Panel", card())
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(PANEL, 26, 18, 10, LINE, 2, true))
		t.set_stylebox("hover", type, box(Color("#f6f9fc"), 26, 18, 10, ACCENT, 2, true))
		t.set_stylebox("pressed", type, box(Color("#fff3df"), 26, 18, 10, ACCENT, 2))
		t.set_stylebox("disabled", type, box(SOFT, 26, 18, 10))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(c, type, NAVY)
		t.set_color("font_disabled_color", type, Color("#a9b4c2"))
	for type in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, box(SOFT, 16, 14, 10))
		t.set_stylebox("hover", type, box(Color("#e3ebf3"), 16, 14, 10))
		t.set_stylebox("pressed", type, box(SOFT, 16, 14, 10))
		t.set_stylebox("hover_pressed", type, box(Color("#e3ebf3"), 16, 14, 10))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(c, type, TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", box(PANEL, 14, 14, 10, LINE, 2))
	t.set_stylebox("focus", "LineEdit", box(PANEL, 14, 14, 10, ACCENT, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color("#a9b4c2"))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font())
	t.set_stylebox("slider", "HSlider", box(SOFT, 6, 0, 4))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, 6, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 6, 0, 4))
	t.set_stylebox("panel", "PopupMenu", card())
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", NAVY)
	t.set_stylebox("hover", "PopupMenu", box(Color("#fff3df"), 10, 8, 6))
	t.set_stylebox("panel", "TooltipPanel", box(NAVY, 10, 10, 6))
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
		sb.shadow_color = Color(0.04, 0.09, 0.2, 0.22)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 5)
	return sb


## Tarjeta blanca con sombra suave.
static func card(color: Color = PANEL, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	return box(color, 24, 22, 20, border, 3, true)


## Etiqueta de una línea. `wrap` = true para párrafos dentro de un contenedor con ancho.
static func label(text: String, font_size: int = 18, color: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size + FONT_BOOST)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return l


## Botón píldora. `accent` = acción principal (relleno de color).
static func button(text: String, cb: Callable, accent: bool = false, color: Color = ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 54)
	if accent:
		var fg := NAVY if color.get_luminance() > 0.55 else Color.WHITE
		b.add_theme_stylebox_override("normal", box(color, 26, 22, 10, Color(0, 0, 0, 0), 0, true))
		b.add_theme_stylebox_override("hover", box(color.lightened(0.12), 26, 22, 10, Color(0, 0, 0, 0), 0, true))
		b.add_theme_stylebox_override("pressed", box(color.darkened(0.12), 26, 22, 10))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, fg)
	make_lively(b)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


## Botón compacto para listas (alto 44 px, texto 16): nunca recorta su texto.
static func small_button(text: String, cb: Callable, color: Color = Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 16 + FONT_BOOST)
	var fill := color if color.a > 0 else PANEL
	var fg := NAVY if fill.get_luminance() > 0.55 else Color.WHITE
	b.add_theme_stylebox_override("normal", box(fill, 18, 14, 6, LINE if color.a == 0 else Color(0, 0, 0, 0), 2))
	b.add_theme_stylebox_override("hover", box(fill.lightened(0.08), 18, 14, 6, ACCENT, 2))
	b.add_theme_stylebox_override("pressed", box(fill.darkened(0.08), 18, 14, 6, ACCENT, 2))
	b.add_theme_stylebox_override("disabled", box(SOFT, 18, 14, 6))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, fg)
	make_lively(b)
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


## Hace que un control reaccione: crece al pasar el cursor y rebota al presionar.
static func make_lively(c: Control) -> void:
	c.mouse_entered.connect(func(): _scale_to(c, 1.04, 0.12))
	c.mouse_exited.connect(func(): _scale_to(c, 1.0, 0.15))
	if c is BaseButton:
		(c as BaseButton).button_down.connect(func(): _scale_to(c, 0.93, 0.06))
		(c as BaseButton).button_up.connect(func():
			if c.is_inside_tree():
				c.pivot_offset = c.size / 2.0
				c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))


static func _scale_to(c: Control, s: float, t: float) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	c.create_tween().tween_property(c, "scale", Vector2(s, s), t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Entrada escalonada: los hijos aparecen subiendo y haciéndose visibles uno tras otro.
static func animate_in(container: Control, step: float = 0.045) -> void:
	var k := 0
	for child in container.get_children():
		if not child is Control:
			continue
		var c: Control = child
		c.modulate.a = 0.0
		var tw := c.create_tween()
		tw.tween_interval(k * step)
		tw.tween_property(c, "modulate:a", 1.0, 0.25)
		k += 1


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
	dim.color = Color(0.03, 0.08, 0.17, 0.55)
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


## Etiqueta tipo "chip" con fondo de color (propiedades en negociaciones, etc.).
static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, 14, 12, 5))
	var l := label(text, 15, NAVY if color.get_luminance() > 0.55 else Color.WHITE)
	p.add_child(l)
	return p


## Nombre de archivo de la foto de una casilla: «23_av_camacho» (ver data/places/LEEME.md).
static func place_file(i: int, name: String) -> String:
	var s := name.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		s = s.replace(pair[0], pair[1])
	var out := ""
	for c in s:
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return "%02d_%s" % [i, out.trim_prefix("_").trim_suffix("_")]


## Limita un campo de texto a `max_words` palabras mientras se escribe
## (nombre: 2 palabras; apodo: 1, sin espacios).
static func limit_words(edit: LineEdit, max_words: int, max_chars: int) -> void:
	edit.max_length = max_chars
	edit.text_changed.connect(func(t: String):
		var clean := t
		if max_words == 1:
			clean = t.replace(" ", "")
		else:
			var words := t.split(" ", false)
			if words.size() > max_words or (words.size() == max_words and t.ends_with(" ")):
				clean = " ".join(words.slice(0, max_words))
			clean = clean.replace("  ", " ").lstrip(" ")
		if clean != t:
			edit.text = clean
			edit.caret_column = clean.length())


## Foto del lugar (data/places/NN_nombre.jpg o .png) o null si no hay.
static func place_photo(i: int, name: String) -> Texture2D:
	var key := place_file(i, name)
	if not _photos.has(key):
		_photos[key] = null
		for ext in [".jpg", ".png"]:
			var path: String = PLACES_DIR + key + ext
			if ResourceLoader.exists(path):
				_photos[key] = load(path)
				break
	return _photos[key]


## Degradado diagonal entre dos colores (fondos de tarjetas sin foto).
static func gradient_tex(a: Color, b: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	tex.width = 64
	tex.height = 64
	return tex


static func token_icon(token: String, color: Color, size: float = 36.0) -> Control:
	var c := TokenIcon.new()
	c.token = token
	c.color = color
	c.custom_minimum_size = Vector2(size, size)
	return c


## Fondo degradado (azul marino a verde azulado) para el menú.
static func gradient_bg() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color("#0b1d3a"))
	g.set_color(1, Color("#1b6b73"))
	g.add_point(0.55, Color("#12425a"))
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
