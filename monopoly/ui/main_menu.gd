class_name MainMenu
extends Control
## Menú principal: inicio, carrusel de modos, perfil con fichas 3D, jugadores y reglas, y salas en red.

signal start_local(seats: Array, rules: RulesConfig)
signal start_host(seats: Array, rules: RulesConfig)
signal start_client(snapshot: Dictionary)

const AI_NAMES := ["Doña Remedios", "Don Fortunato", "La Chola Rica", "El Ingeniero", "Tía Pochi", "Compadre Wilmer"]
const LEVELS := ["Fácil", "Media", "Difícil"]
const MODES := [
	{"id": "ai", "title": "Contra la IA", "subtitle": "Rivales con tres niveles de astucia.", "color": Color("#1f9e89"), "icon": "ai", "bullets": ["De 2 a 6 jugadores", "Ideal para practicar"]},
	{"id": "local", "title": "Pasar y jugar", "subtitle": "Varios jugadores en un mismo dispositivo.", "color": Color("#e8735a"), "icon": "local", "bullets": ["Cada quien con su ficha", "Sin conexión"]},
	{"id": "wifi", "title": "Wi-Fi local", "subtitle": "Cada jugador en su teléfono, en la misma red.", "color": Color("#3d6fd6"), "icon": "wifi", "bullets": ["Busca la sala y únete", "Sin servidores externos"]},
	{"id": "bluetooth", "title": "Bluetooth", "subtitle": "Juega cerca, sin internet ni Wi-Fi.", "color": Color("#7b5cd6"), "icon": "bt", "bullets": ["Teléfonos emparejados", "Solo Android"]},
]

var board: Board
var _page: Control
var _seats: Array = []
var _rules := RulesConfig.classic()
var _mode := ""
var _tab := 0
var _hosts_list: VBoxContainer
var _lobby_list: VBoxContainer
var _search_until := 0


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board = Board.load_from_file(GameController.BOARD_PATH)
	if not Profile.rules.is_empty():
		_rules = RulesConfig.from_dict(Profile.rules)
	add_child(UiKit.gradient_bg())
	var deco := MenuBackdrop.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deco)
	Net.lobby_changed.connect(func(_s, _r): if _lobby_list: _render_lobby())
	Net.game_started.connect(func(snap): start_client.emit(snap))
	Net.session_ended.connect(func(reason): show_home(reason))
	Net.discovery.hosts_changed.connect(func(_h): _render_hosts())
	show_home()


func _set_page(content: Control, card := true) -> void:
	if _page:
		_page.queue_free()
	_lobby_list = null
	_hosts_list = null
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = get_viewport_rect().size
	scroll.add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	center.add_child(margin)
	var wrapped: Control = content if (content is PanelContainer or not card) else UiKit.panel(content)
	margin.add_child(wrapped)
	content.custom_minimum_size.x = minf(content.custom_minimum_size.x, get_viewport_rect().size.x - 40)
	add_child(scroll)
	_page = scroll
	UiKit.animate_in(content)
	wrapped.modulate.a = 0.0
	wrapped.position.y += 20
	var tw := wrapped.create_tween().set_parallel(true)
	tw.tween_property(wrapped, "modulate:a", 1.0, 0.25)


func _title(text: String, sub: String = "", light := false) -> VBoxContainer:
	var v := UiKit.vbox(2)
	var t := UiKit.label(text, 40, Color.WHITE if light else UiKit.HEADING)
	t.add_theme_font_override("font", UiKit.font_black())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if sub != "":
		var s := UiKit.label(sub, 16, Color(1, 1, 1, 0.75) if light else UiKit.MUTED, true)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	return v


func _footer(back: Callable, next_text: String = "", next: Callable = Callable(), next_enabled := true) -> HBoxContainer:
	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UiKit.button("Volver", back))
	if next_text != "":
		var b := UiKit.button(next_text, next, true)
		b.disabled = not next_enabled
		b.custom_minimum_size.x = 220
		row.add_child(b)
	return row


# ---------------------------------------------------------------------------
# Inicio
# ---------------------------------------------------------------------------

func show_home(message: String = "") -> void:
	Net.discovery.stop()
	var v := UiKit.vbox(14)
	v.custom_minimum_size = Vector2(460, 0)
	var logo := UiKit.label("MAGNATES", 64, UiKit.HEADING)
	logo.add_theme_font_override("font", UiKit.font_black())
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	var tag := UiKit.label("Compra, construye y negocia en La Paz – El Alto", 16, UiKit.MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	if message != "":
		var m := UiKit.label(message, 16, UiKit.DANGER, true)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(m)
	var chip := UiKit.hbox(14)
	var preview := TokenPreview3D.new()
	preview.custom_minimum_size = Vector2(84, 84)
	chip.add_child(preview)
	preview.set_token(Profile.token, Color.html(Profile.color))
	var who := UiKit.vbox(0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_child(UiKit.label(Profile.label_for(Profile.as_seat()), 22))
	who.add_child(UiKit.label("Ficha: %s" % Profile.TOKEN_NAMES.get(Profile.token, Profile.token), 14, UiKit.MUTED))
	chip.add_child(who)
	var edit := UiKit.button("Editar", show_profile)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(edit)
	v.add_child(UiKit.panel(chip, UiKit.SOFT))
	var play := UiKit.button("JUGAR", show_modes, true)
	play.custom_minimum_size.y = 68
	play.add_theme_font_size_override("font_size", 26)
	play.add_theme_font_override("font", UiKit.font_black())
	v.add_child(play)
	_pulse(play)
	var row := UiKit.hbox(10)
	for spec in [["Opciones", func(): _set_page(OptionsPanel.build(func(): show_home()))], ["Salir", func(): get_tree().quit()]]:
		var b := UiKit.button(spec[0], spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	_set_page(v)


## Latido suave para invitar a la acción principal.
func _pulse(c: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2(1.03, 1.03), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)


func show_modes() -> void:
	var v := UiKit.vbox(16)
	v.custom_minimum_size = Vector2(900, 0)
	v.add_child(_title("¿Cómo quieres jugar?", "Desliza o usa las flechas", true))
	var carousel := ModeCarousel.new()
	carousel.setup(MODES)
	v.add_child(carousel)
	var choose := func(i: int):
		var id: String = MODES[i]["id"]
		if id in ["ai", "local"]:
			show_setup(id)
		else:
			show_network(id)
	carousel.chosen.connect(choose)
	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.button("Volver", func(): show_home()))
	var go := UiKit.button("Elegir este modo", func(): choose.call(carousel.index), true)
	go.custom_minimum_size.x = 260
	row.add_child(go)
	v.add_child(row)
	_set_page(v, false)
	carousel.grab_focus()


# ---------------------------------------------------------------------------
# Perfil con carrusel de fichas 3D
# ---------------------------------------------------------------------------

func show_profile() -> void:
	var sel := {"token": Profile.token, "color": Profile.color}
	var root := UiKit.hbox(28)
	root.custom_minimum_size = Vector2(780, 0)
	# Izquierda: ficha 3D con flechas
	var left := UiKit.vbox(10)
	left.custom_minimum_size = Vector2(320, 0)
	root.add_child(left)
	var preview := TokenPreview3D.new()
	preview.custom_minimum_size = Vector2(320, 280)
	left.add_child(preview)
	var name_row := UiKit.hbox(8)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var token_name := UiKit.label("", 26, UiKit.HEADING)
	token_name.add_theme_font_override("font", UiKit.font_black())
	token_name.custom_minimum_size.x = 170
	token_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var colors := HFlowContainer.new()
	colors.alignment = FlowContainer.ALIGNMENT_CENTER
	colors.add_theme_constant_override("h_separation", 8)
	colors.add_theme_constant_override("v_separation", 8)
	var refresh := func(self_ref: Callable):
		preview.set_token(sel["token"], Color.html(sel["color"]))
		token_name.text = Profile.TOKEN_NAMES.get(sel["token"], sel["token"])
		for c in colors.get_children():
			c.queue_free()
		for c in Profile.COLORS:
			var cb := Button.new()
			cb.custom_minimum_size = Vector2(40, 40)
			cb.focus_mode = Control.FOCUS_NONE
			var on: bool = c == sel["color"]
			cb.add_theme_stylebox_override("normal", UiKit.box(Color.html(c), 20, 0, 0, UiKit.NAVY if on else Color(1, 1, 1, 1), 4 if on else 3, true))
			cb.add_theme_stylebox_override("hover", UiKit.box(Color.html(c).lightened(0.15), 20, 0, 0, UiKit.NAVY, 3))
			UiKit.make_lively(cb)
			cb.pressed.connect(func():
				sel["color"] = c
				Sfx.play("click")
				self_ref.call(self_ref))
			colors.add_child(cb)
	var step := func(d: int):
		var i: int = (board.tokens.find(sel["token"]) + d) % board.tokens.size()
		sel["token"] = board.tokens[posmod(i, board.tokens.size())]
		Sfx.play("card")
		refresh.call(refresh)
	var prev := UiKit.button("‹", func(): step.call(-1))
	var next := UiKit.button("›", func(): step.call(1))
	for b in [prev, next]:
		b.custom_minimum_size = Vector2(56, 56)
		b.add_theme_font_size_override("font_size", 30)
	name_row.add_child(prev)
	name_row.add_child(token_name)
	name_row.add_child(next)
	left.add_child(name_row)
	left.add_child(colors)
	# Derecha: nombre y apodo
	var right := UiKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	right.add_child(_title("Tu perfil", "Se guarda solo en este dispositivo"))
	right.add_child(UiKit.label("Nombre", 15, UiKit.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = Profile.display_name
	name_edit.max_length = 18
	right.add_child(name_edit)
	right.add_child(UiKit.label("Apodo", 15, UiKit.MUTED))
	var nick_edit := LineEdit.new()
	nick_edit.text = Profile.nick
	nick_edit.max_length = 14
	nick_edit.placeholder_text = "opcional, aparece entre « »"
	right.add_child(nick_edit)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(_footer(func(): show_home(), "Guardar", func():
		Profile.display_name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Jugador"
		Profile.nick = nick_edit.text.strip_edges()
		Profile.token = sel["token"]
		Profile.color = sel["color"]
		Profile.save_profile()
		show_home()))
	_set_page(root)
	refresh.call(refresh)


# ---------------------------------------------------------------------------
# Jugadores y reglas (local / contra IA)
# ---------------------------------------------------------------------------

func show_setup(mode: String) -> void:
	_mode = mode
	_tab = 0
	_seats = [Profile.as_seat()]
	if mode == "ai":
		_add_ai(AiBrain.Level.MEDIUM)
		_add_ai(AiBrain.Level.HARD)
	else:
		_add_local()
	_render_setup()


func _free_token(seats: Array = _seats) -> String:
	var used := seats.map(func(s): return s["token"])
	for t in board.tokens:
		if not t in used:
			return t
	return board.tokens[0]


func _free_color(seats: Array = _seats) -> String:
	var used := seats.map(func(s): return s["color"])
	for c in Profile.COLORS:
		if not c in used:
			return c
	return Profile.COLORS[0]


func _add_ai(level: int) -> void:
	if _seats.size() >= 6:
		return
	_seats.append({"uuid": "ai-%d" % randi(), "name": AI_NAMES[_seats.size() % AI_NAMES.size()], "nick": "", "token": _free_token(), "color": _free_color(), "ai": level})


func _add_local() -> void:
	if _seats.size() >= 6:
		return
	_seats.append({"uuid": "local-%d" % randi(), "name": "Jugador %d" % (_seats.size() + 1), "nick": "", "token": _free_token(), "color": _free_color(), "ai": -1})


func _render_setup() -> void:
	var v := UiKit.vbox(14)
	v.custom_minimum_size = Vector2(720, 0)
	v.add_child(_title("Contra la IA" if _mode == "ai" else "Pasar y jugar", "%d de 6 jugadores" % _seats.size()))
	v.add_child(_tabs(["Jugadores", "Reglas"], _tab, func(i):
		_tab = i
		_render_setup()))
	if _tab == 0:
		var list := UiKit.vbox(10)
		v.add_child(list)
		for idx in _seats.size():
			list.add_child(_seat_card(idx))
		if _seats.size() < 6:
			var adds := UiKit.hbox(12)
			adds.add_child(_add_tile("Añadir IA", "Un rival de la computadora", UiKit.ACCENT_2, func():
				_add_ai(AiBrain.Level.MEDIUM)
				Sfx.play("build")
				_render_setup()))
			adds.add_child(_add_tile("Añadir jugador", "Otra persona en este dispositivo", UiKit.CORAL, func():
				_add_local()
				Sfx.play("build")
				_render_setup()))
			v.add_child(adds)
	else:
		v.add_child(_rules_editor(_rules, func():
			Profile.rules = _rules.to_dict()
			Profile.save_profile(), true))
	v.add_child(_footer(func(): show_modes(), "Comenzar partida", func(): start_local.emit(_seats.duplicate(true), _rules), _seats.size() >= 2))
	_set_page(v)


func _tabs(names: Array, selected: int, on_pick: Callable) -> Control:
	var row := UiKit.hbox(6)
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UiKit.box(UiKit.SOFT, 28, 6, 6))
	bg.add_child(row)
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on := i == selected
		b.add_theme_stylebox_override("normal", UiKit.box(UiKit.NAVY if on else Color(0, 0, 0, 0), 22, 16, 8, Color(0, 0, 0, 0), 0, on))
		b.add_theme_stylebox_override("hover", UiKit.box(UiKit.NAVY if on else Color(1, 1, 1, 0.7), 22, 16, 8))
		b.add_theme_stylebox_override("pressed", UiKit.box(UiKit.NAVY, 22, 16, 8))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, Color.WHITE if on else UiKit.MUTED)
		b.pressed.connect(func():
			Sfx.play("click")
			on_pick.call(i))
		row.add_child(b)
	return bg


func _seat_card(idx: int) -> Control:
	var s: Dictionary = _seats[idx]
	var pcol := Color.html(s["color"])
	var row := UiKit.hbox(12)
	var card := PanelContainer.new()
	var sb := UiKit.box(Color.WHITE, 20, 14, 10, UiKit.LINE, 2, true)
	sb.border_width_left = 8
	sb.border_color = pcol
	card.add_theme_stylebox_override("panel", sb)
	card.add_child(row)
	var icon_btn := Button.new()
	icon_btn.custom_minimum_size = Vector2(56, 56)
	icon_btn.focus_mode = Control.FOCUS_NONE
	icon_btn.flat = true
	icon_btn.tooltip_text = "Cambiar ficha y color"
	var icon := UiKit.token_icon(s["token"], pcol, 52)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_btn.add_child(icon)
	UiKit.make_lively(icon_btn)
	row.add_child(icon_btn)
	if idx == 0:
		var col := UiKit.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.label(Profile.label_for(s), 20))
		col.add_child(UiKit.label("Tú · %s" % Profile.TOKEN_NAMES.get(s["token"], s["token"]), 14, UiKit.MUTED))
		row.add_child(col)
		icon_btn.pressed.connect(show_profile)
		return card
	icon_btn.pressed.connect(func():
		var others := _seats.filter(func(o): return o != s)
		var i := (board.tokens.find(s["token"]) + 1) % board.tokens.size()
		while board.tokens[i] in others.map(func(o): return o["token"]):
			i = (i + 1) % board.tokens.size()
		s["token"] = board.tokens[i]
		s["color"] = _free_color(others)
		Sfx.play("card")
		_render_setup())
	var name_edit := LineEdit.new()
	name_edit.text = s["name"]
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): s["name"] = t)
	row.add_child(name_edit)
	if int(s["ai"]) >= 0:
		row.add_child(_mini_segment(LEVELS, int(s["ai"]), func(i): s["ai"] = i))
	else:
		var nick := LineEdit.new()
		nick.placeholder_text = "apodo"
		nick.text = s["nick"]
		nick.custom_minimum_size = Vector2(130, 0)
		nick.text_changed.connect(func(t): s["nick"] = t)
		row.add_child(nick)
	var remove := UiKit.button("✕", func():
		_seats.remove_at(idx)
		_render_setup())
	remove.custom_minimum_size = Vector2(54, 54)
	remove.tooltip_text = "Quitar"
	row.add_child(remove)
	return card


func _mini_segment(options: Array, selected: int, on_pick: Callable) -> Control:
	var row := UiKit.hbox(4)
	var buttons := []
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(76, 46)
		b.add_theme_stylebox_override("normal", UiKit.box(UiKit.SOFT, 14, 8, 6))
		b.add_theme_stylebox_override("pressed", UiKit.box(UiKit.NAVY, 14, 8, 6))
		b.add_theme_stylebox_override("hover_pressed", UiKit.box(UiKit.NAVY, 14, 8, 6))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.add_theme_font_size_override("font_size", 15)
		b.button_pressed = i == selected
		buttons.append(b)
		row.add_child(b)
	for i in buttons.size():
		buttons[i].pressed.connect(func():
			for j in buttons.size():
				buttons[j].button_pressed = j == i
			Sfx.play("click")
			on_pick.call(i))
	return row


## Tarjeta grande para añadir jugadores, con un "+" que late.
func _add_tile(title: String, sub: String, color: Color, cb: Callable) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 86)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", UiKit.box(color.lerp(Color.WHITE, 0.88), 20, 16, 10, color.lerp(Color.WHITE, 0.4), 2))
	b.add_theme_stylebox_override("hover", UiKit.box(color.lerp(Color.WHITE, 0.78), 20, 16, 10, color, 2, true))
	b.add_theme_stylebox_override("pressed", UiKit.box(color.lerp(Color.WHITE, 0.65), 20, 16, 10, color, 2))
	var row := UiKit.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var plus := PanelContainer.new()
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plus.custom_minimum_size = Vector2(52, 52)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.add_theme_stylebox_override("panel", UiKit.box(color, 26, 0, 0, Color(0, 0, 0, 0), 0, true))
	var pl := UiKit.label("+", 32, Color.WHITE)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.add_child(pl)
	row.add_child(plus)
	var col := UiKit.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(UiKit.label(title, 19, UiKit.HEADING))
	col.add_child(UiKit.label(sub, 13, UiKit.MUTED))
	row.add_child(col)
	b.add_child(row)
	UiKit.make_lively(b)
	b.pressed.connect(cb)
	_spin_plus(plus)
	return b


func _spin_plus(c: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2(1.1, 1.1), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)


## Editor de reglas: dos tarjetas de modo y tarjetas de interruptor con descripción.
func _rules_editor(r: RulesConfig, on_change: Callable, editable: bool) -> Control:
	var v := UiKit.vbox(10)
	var presets := UiKit.hbox(12)
	v.add_child(presets)
	var preset_specs := [
		[RulesConfig.Mode.CLASSIC, "Clásico", "Reglas completas. Gana el último que no quiebre.", UiKit.ACCENT_2],
		[RulesConfig.Mode.QUICK, "Rápido", "Termina en la primera quiebra, hotel con 3 casas y dado turbo.", UiKit.CORAL],
	]
	for spec in preset_specs:
		var on: bool = r.mode == spec[0]
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = on
		b.disabled = not editable
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 104)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col: Color = spec[3]
		b.add_theme_stylebox_override("normal", UiKit.box(UiKit.SOFT, 20, 16, 12))
		b.add_theme_stylebox_override("hover", UiKit.box(col.lerp(Color.WHITE, 0.85), 20, 16, 12, col, 2))
		b.add_theme_stylebox_override("pressed", UiKit.box(col.lerp(Color.WHITE, 0.82), 20, 16, 12, col, 3, true))
		b.add_theme_stylebox_override("hover_pressed", UiKit.box(col.lerp(Color.WHITE, 0.78), 20, 16, 12, col, 3, true))
		b.add_theme_stylebox_override("disabled", UiKit.box(col.lerp(Color.WHITE, 0.82) if on else UiKit.SOFT, 20, 16, 12, col if on else Color(0, 0, 0, 0), 3))
		var inner := UiKit.vbox(2)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 18
		inner.offset_right = -18
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		var t := UiKit.label(("✓ " if on else "") + spec[1], 22, col.darkened(0.25) if on else UiKit.HEADING)
		t.add_theme_font_override("font", UiKit.font_black())
		inner.add_child(t)
		inner.add_child(UiKit.label(spec[2], 14, UiKit.MUTED, true))
		b.add_child(inner)
		UiKit.make_lively(b)
		b.pressed.connect(func():
			var preset := RulesConfig.quick() if spec[0] == RulesConfig.Mode.QUICK else RulesConfig.classic()
			for k in ["mode", "end_on_first_bankruptcy", "houses_per_hotel", "speed_die"]:
				r.set(k, preset.get(k))
			Sfx.play("click")
			on_change.call()
			_rerender_rules())
		presets.add_child(b)
	var toggles := [
		["speed_die", "Dado turbo", "Un tercer dado: 1-3 suma pasos, » salta a la siguiente propiedad libre, Bs da un bono de Bs 50."],
		["free_parking_pot", "Bote en el Mirador", "Impuestos y multas se acumulan; quien cae en el Mirador se lo lleva."],
		["double_salary_on_go", "Doble sueldo en la Salida", "Caer justo en la Salida paga Bs 400 en vez de Bs 200."],
		["no_rent_in_jail", "Sin alquiler desde el Retén", "Mientras estás en el Retén no cobras alquileres."],
		["end_on_first_bankruptcy", "Final rápido", "La partida termina en la primera quiebra; gana el mayor patrimonio."],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for spec in toggles:
		grid.add_child(_toggle_card(spec[1], spec[2], r.get(spec[0]), editable, func(on):
			r.set(spec[0], on)
			on_change.call()))
	grid.add_child(_toggle_card("Hotel con 3 casas", "Se necesitan solo 3 casas por calle para construir un hotel.", r.houses_per_hotel == 3, editable, func(on):
		r.houses_per_hotel = 3 if on else 4
		on_change.call()))
	var rounds_box := UiKit.vbox(6)
	rounds_box.add_child(UiKit.label("Duración de la partida", 17, UiKit.HEADING))
	var opts := [0, 30, 60, 100]
	var labels := ["Sin límite", "30 rondas", "60 rondas", "100 rondas"]
	var current := opts.find(r.max_rounds)
	if not editable:
		rounds_box.add_child(UiKit.label(labels[maxi(current, 0)], 16, UiKit.MUTED))
	else:
		rounds_box.add_child(_mini_segment(labels, maxi(current, 0), func(i):
			r.max_rounds = opts[i]
			on_change.call()))
	v.add_child(UiKit.panel(rounds_box, UiKit.SOFT))
	return v


func _rerender_rules() -> void:
	if _lobby_list:
		_render_lobby()
	else:
		_render_setup()


func _toggle_card(title: String, desc: String, on: bool, editable: bool, cb: Callable) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color("#fff7ea") if on else UiKit.SOFT, 18, 16, 12, UiKit.ACCENT if on else Color(0, 0, 0, 0), 2))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(330, 0)
	var row := UiKit.hbox(10)
	p.add_child(row)
	var col := UiKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiKit.label(title, 17, UiKit.HEADING))
	var d := UiKit.label(desc, 13, UiKit.MUTED, true)
	d.custom_minimum_size.x = 230
	col.add_child(d)
	row.add_child(col)
	var sw := CheckButton.new()
	sw.button_pressed = on
	sw.disabled = not editable
	sw.focus_mode = Control.FOCUS_NONE
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	sw.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	sw.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	sw.add_theme_stylebox_override("hover_pressed", StyleBoxEmpty.new())
	sw.toggled.connect(func(v):
		Sfx.play("click")
		p.add_theme_stylebox_override("panel", UiKit.box(Color("#fff7ea") if v else UiKit.SOFT, 18, 16, 12, UiKit.ACCENT if v else Color(0, 0, 0, 0), 2))
		cb.call(v))
	row.add_child(sw)
	return p


# ---------------------------------------------------------------------------
# Red local: crear sala o buscar salas (sin IP)
# ---------------------------------------------------------------------------

func _adapter(kind: String) -> NetworkAdapter:
	return EnetAdapter.new() if kind == "wifi" else BluetoothAdapter.new()


func show_network(kind: String) -> void:
	_mode = kind
	var adapter := _adapter(kind)
	var v := UiKit.vbox(14)
	v.custom_minimum_size = Vector2(760, 0)
	v.add_child(_title("Wi-Fi local" if kind == "wifi" else "Bluetooth", "Un teléfono crea la sala y los demás se unen"))
	if not adapter.is_available():
		v.add_child(UiKit.label("Bluetooth está disponible en la app de Android. En este equipo usa Wi-Fi local.", 16, UiKit.DANGER, true))
		v.add_child(_footer(func(): show_modes()))
		_set_page(v)
		return
	var cols := UiKit.hbox(14)
	v.add_child(cols)
	var host_box := UiKit.vbox(10)
	host_box.add_child(UiKit.label("Crear sala", 22, UiKit.HEADING))
	host_box.add_child(UiKit.label("Tú eres el anfitrión: los demás te encontrarán.", 14, UiKit.MUTED, true))
	var room := LineEdit.new()
	room.text = "Sala de %s" % Profile.display_name
	room.max_length = 24
	host_box.add_child(room)
	host_box.add_child(UiKit.button("Crear sala", func():
		var err := Net.host_game(_adapter(kind), Profile.as_seat(), _rules.to_dict(), room.text)
		if err != OK:
			show_home("No se pudo crear la sala. Revisa que estés conectado a una red.")
		else:
			show_lobby(), true))
	var host_card := UiKit.panel(host_box, UiKit.SOFT)
	host_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(host_card)
	var join_box := UiKit.vbox(10)
	join_box.add_child(UiKit.label("Unirse a una sala", 22, UiKit.HEADING))
	join_box.add_child(UiKit.label("Conéctate a la misma red Wi-Fi que el anfitrión." if kind == "wifi" else "Empareja los teléfonos en los ajustes de Bluetooth.", 14, UiKit.MUTED, true))
	join_box.add_child(UiKit.button("Buscar salas" if kind == "wifi" else "Buscar dispositivos", func(): _start_search(kind), true, UiKit.ACCENT_2))
	var hosts := UiKit.vbox(8)
	join_box.add_child(hosts)
	var join_card := UiKit.panel(join_box, UiKit.SOFT)
	join_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(join_card)
	v.add_child(_footer(func():
		Net.leave()
		show_modes()))
	_set_page(v)
	_hosts_list = hosts


func _start_search(kind: String) -> void:
	_search_until = Time.get_ticks_msec() + 7000
	if kind == "wifi":
		if Net.discovery.start_listening() != OK:
			if _hosts_list:
				for c in _hosts_list.get_children():
					c.queue_free()
				_hosts_list.add_child(UiKit.label("No se pudo buscar en esta red. Revisa tu conexión Wi-Fi.", 14, UiKit.DANGER, true))
			return
	_render_hosts()
	_search_tick()


func _search_tick() -> void:
	while _hosts_list and Time.get_ticks_msec() < _search_until:
		await get_tree().create_timer(0.4).timeout
		_render_hosts()
	_render_hosts()


func _render_hosts() -> void:
	if _hosts_list == null or not is_instance_valid(_hosts_list) or _search_until == 0:
		return
	for c in _hosts_list.get_children():
		c.queue_free()
	var searching := Time.get_ticks_msec() < _search_until
	var entries := []
	if _mode == "wifi":
		for h in Net.discovery.hosts():
			entries.append({"name": h.get("name", "Sala"), "info": "%d de %d jugadores%s" % [int(h.get("players", 0)), int(h.get("max", 6)), " · en juego" if h.get("in_game", false) else ""], "address": h["ip"], "full": h.get("in_game", false)})
	else:
		for d in (BluetoothAdapter.new() as BluetoothAdapter).paired_devices():
			entries.append({"name": d["name"], "info": "Dispositivo emparejado", "address": d["address"], "full": false})
	for entry in entries:
		var row := UiKit.hbox(10)
		var card := UiKit.panel(row, Color.WHITE)
		var col := UiKit.vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.label(entry["name"], 18, UiKit.HEADING))
		col.add_child(UiKit.label(entry["info"], 13, UiKit.MUTED))
		row.add_child(col)
		var join := UiKit.button("Unirme", func(): _join(_mode, entry["address"]), true)
		join.disabled = entry["full"]
		row.add_child(join)
		_hosts_list.add_child(card)
	if searching:
		var dots := ".".repeat(1 + int(Time.get_ticks_msec() / 400) % 3)
		_hosts_list.add_child(UiKit.label("Buscando" + dots, 15, UiKit.MUTED))
	elif entries.is_empty():
		_hosts_list.add_child(UiKit.label("No encontramos salas. Pide al anfitrión que cree una y vuelve a buscar.", 14, UiKit.MUTED, true))


func _join(kind: String, address: String) -> void:
	if address == "":
		return
	Profile.last_host = address
	Profile.save_profile()
	var err := Net.join_game(_adapter(kind), address, Profile.as_seat())
	if err != OK:
		show_home("No se pudo conectar con la sala.")
		return
	show_lobby()


func show_lobby() -> void:
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(720, 0)
	_set_page(v)
	_lobby_list = v   # la página entera se re-renderiza al cambiar la sala
	_render_lobby()


func _render_lobby() -> void:
	var v := _lobby_list
	if v == null:
		return
	for c in v.get_children():
		c.queue_free()
	var host := Net.is_host()
	v.add_child(_title(Net.room_name if host else "Sala", "Comparte el nombre de la sala con tus amigos" if host else "Esperando a que el anfitrión comience…"))
	for idx in Net.seats.size():
		var s: Dictionary = Net.seats[idx]
		var row := UiKit.hbox(10)
		var sb := UiKit.box(Color.WHITE, 18, 14, 8, UiKit.LINE, 2, true)
		sb.border_width_left = 8
		sb.border_color = Color.html(s["color"])
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", sb)
		card.add_child(row)
		row.add_child(UiKit.token_icon(s["token"], Color.html(s["color"]), 44))
		var tag: String = ("IA " + LEVELS[int(s["ai"])].to_lower()) if int(s["ai"]) >= 0 else ("anfitrión" if int(s.get("peer", 0)) == 1 else "jugador")
		var l := UiKit.label(Profile.label_for(s), 18)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UiKit.chip(tag, UiKit.SOFT))
		if host and idx > 0:
			var rm := UiKit.button("✕", func(): Net.remove_seat(idx))
			rm.custom_minimum_size = Vector2(50, 50)
			row.add_child(rm)
		v.add_child(card)
	if host and Net.seats.size() < Net.MAX_SEATS:
		v.add_child(_add_tile("Añadir IA", "Completa la mesa con un rival", UiKit.ACCENT_2, func():
			Net.add_ai_seat(AiBrain.Level.MEDIUM, {"uuid": "ai-%d" % randi(), "name": AI_NAMES[Net.seats.size() % AI_NAMES.size()], "nick": "", "token": _free_token(Net.seats), "color": _free_color(Net.seats)})))
	var rules := RulesConfig.from_dict(Net.rules) if not Net.rules.is_empty() else _rules
	v.add_child(_rules_editor(rules, func(): Net.set_rules(rules.to_dict()), host))
	v.add_child(_footer(func():
		Net.leave()
		show_home(), "Comenzar" if host else "", func():
		var seats := []
		for s in Net.seats:
			var c: Dictionary = s.duplicate()
			c.erase("peer")
			seats.append(c)
		start_host.emit(_dedupe_tokens(seats), rules), Net.seats.size() >= 2))


## Si dos jugadores en red eligieron la misma ficha y color, se ajusta el color del segundo.
func _dedupe_tokens(seats: Array) -> Array:
	var seen := []
	for s in seats:
		var key: String = s["token"] + s["color"]
		if key in seen:
			for c in Profile.COLORS:
				if not (s["token"] + c) in seen:
					s["color"] = c
					key = s["token"] + c
					break
		seen.append(key)
	return seats


class MenuBackdrop extends Control:
	## Fondo animado: casillas de colores y monedas doradas que flotan lentamente.
	var _t := 0.0
	const COLORS := ["#e8735a", "#f2a541", "#1f9e89", "#3d6fd6", "#7b5cd6", "#d64550"]

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for k in 22:
			var base := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			var r := rng.randf_range(18, 60)
			var speed := rng.randf_range(6, 16)
			var p := Vector2(base.x + sin(_t * 0.3 + k) * 18.0, fposmod(base.y - _t * speed, size.y + 160) - 80)
			if k % 3 == 0:
				draw_circle(p, r * 0.4, Color(0.95, 0.65, 0.25, 0.22))
				draw_arc(p, r * 0.4, 0, TAU, 24, Color(1, 0.85, 0.5, 0.3), 2.0)
			else:
				draw_set_transform(p, _t * 0.15 + k, Vector2.ONE)
				var col := Color.html(COLORS[k % COLORS.size()])
				col.a = 0.16
				draw_rect(Rect2(-r / 2, -r * 0.7, r, r * 1.4), col)
				draw_rect(Rect2(-r / 2, -r * 0.7, r, r * 0.35), Color(col.r, col.g, col.b, 0.3))
				draw_set_transform_matrix(Transform2D.IDENTITY)
