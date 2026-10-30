class_name MainMenu
extends Control
## Menú principal: perfil local, configuración de partida, reglas y salas en red.

signal start_local(seats: Array, rules: RulesConfig)
signal start_host(seats: Array, rules: RulesConfig)
signal start_client(snapshot: Dictionary)

const AI_NAMES := ["Doña Remedios", "Don Fortunato", "La Chola Rica", "El Ingeniero", "Tía Pochi", "Compadre Wilmer"]
const LEVELS := ["IA fácil", "IA media", "IA difícil"]

var board: Board
var _page: Control
var _seats: Array = []
var _rules := RulesConfig.classic()
var _mode := ""
var _hosts_list: VBoxContainer
var _lobby_list: VBoxContainer


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


func _set_page(content: Control) -> void:
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
	margin.add_child(content if content is PanelContainer else UiKit.panel(content))
	content.custom_minimum_size.x = minf(content.custom_minimum_size.x, get_viewport_rect().size.x - 32)
	add_child(scroll)
	_page = scroll


func _title(text: String, sub: String = "") -> VBoxContainer:
	var v := UiKit.vbox(2)
	var t := UiKit.label(text, 44, UiKit.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if sub != "":
		var s := UiKit.label(sub, 16, UiKit.MUTED)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	return v


# ---------------------------------------------------------------------------
# Inicio
# ---------------------------------------------------------------------------

func show_home(message: String = "") -> void:
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(440, 0)
	v.add_child(_title("MAGNATES", "Juego de propiedades · %s" % board.name))
	if message != "":
		v.add_child(UiKit.label(message, 16, UiKit.DANGER))
	var chip := UiKit.hbox(12)
	chip.add_child(UiKit.token_icon(Profile.token, Color.html(Profile.color), 56))
	var who := UiKit.vbox(0)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(UiKit.label(Profile.label_for(Profile.as_seat()), 20))
	who.add_child(UiKit.label("Ficha: %s" % Profile.TOKEN_NAMES.get(Profile.token, Profile.token), 14, UiKit.MUTED))
	chip.add_child(who)
	chip.add_child(UiKit.button("Editar perfil", show_profile))
	v.add_child(UiKit.panel(chip, UiKit.SOFT))
	v.add_child(UiKit.button("¡Jugar contra la IA!", func(): show_setup("ai"), true))
	v.add_child(UiKit.button("Pasar y jugar (mismo dispositivo)", func(): show_setup("local"), true, UiKit.ACCENT_2.darkened(0.1)))
	var net_row := UiKit.hbox(10)
	for spec in [["Wi-Fi local", "wifi"], ["Bluetooth", "bluetooth"]]:
		var b := UiKit.button(spec[0], func(): show_network(spec[1]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		net_row.add_child(b)
	v.add_child(net_row)
	var misc_row := UiKit.hbox(10)
	var opts := UiKit.button("Opciones", func(): _set_page(OptionsPanel.build(func(): show_home())))
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	misc_row.add_child(opts)
	var quit := UiKit.button("Salir", func(): get_tree().quit())
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	misc_row.add_child(quit)
	v.add_child(misc_row)
	_set_page(v)


# ---------------------------------------------------------------------------
# Perfil (sin autenticación)
# ---------------------------------------------------------------------------

func show_profile() -> void:
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(520, 0)
	v.add_child(_title("Tu perfil", "Se guarda solo en este dispositivo"))
	v.add_child(UiKit.label("Nombre", 15, UiKit.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = Profile.display_name
	name_edit.max_length = 18
	v.add_child(name_edit)
	v.add_child(UiKit.label("Apodo (nick)", 15, UiKit.MUTED))
	var nick_edit := LineEdit.new()
	nick_edit.text = Profile.nick
	nick_edit.max_length = 14
	nick_edit.placeholder_text = "opcional"
	v.add_child(nick_edit)
	var sel := {"token": Profile.token, "color": Profile.color}
	v.add_child(UiKit.label("Ficha", 15, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	v.add_child(UiKit.label("Color", 15, UiKit.MUTED))
	var colors := UiKit.hbox(8)
	v.add_child(colors)
	var render := func(self_ref: Callable) -> void:
		for c in grid.get_children():
			c.queue_free()
		for c in colors.get_children():
			c.queue_free()
		for t in board.tokens:
			var b := Button.new()
			b.custom_minimum_size = Vector2(110, 96)
			b.focus_mode = Control.FOCUS_NONE
			b.toggle_mode = true
			b.button_pressed = t == sel["token"]
			if b.button_pressed:
				b.add_theme_stylebox_override("normal", UiKit.box(Color("#efeaff"), 18, 8, 8, UiKit.ACCENT, 3))
			var col := UiKit.vbox(2)
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var icon := UiKit.token_icon(t, Color.html(sel["color"]), 56)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(icon)
			var l := UiKit.label(Profile.TOKEN_NAMES.get(t, t), 14)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(l)
			b.add_child(col)
			b.pressed.connect(func():
				sel["token"] = t
				self_ref.call(self_ref))
			grid.add_child(b)
		for c in Profile.COLORS:
			var cb := Button.new()
			cb.custom_minimum_size = Vector2(42, 42)
			cb.focus_mode = Control.FOCUS_NONE
			cb.add_theme_stylebox_override("normal", UiKit.box(Color.html(c), 21, 0, 0, UiKit.TEXT if c == sel["color"] else Color(0, 0, 0, 0), 4))
			cb.add_theme_stylebox_override("hover", UiKit.box(Color.html(c).lightened(0.2), 21, 0, 0))
			cb.pressed.connect(func():
				sel["color"] = c
				self_ref.call(self_ref))
			colors.add_child(cb)
	render.call(render)
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UiKit.button("Volver", func(): show_home()))
	row.add_child(UiKit.button("Guardar", func():
		Profile.display_name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Jugador"
		Profile.nick = nick_edit.text.strip_edges()
		Profile.token = sel["token"]
		Profile.color = sel["color"]
		Profile.save_profile()
		show_home(), true))
	v.add_child(row)
	_set_page(v)


# ---------------------------------------------------------------------------
# Configuración de partida local / contra IA
# ---------------------------------------------------------------------------

func show_setup(mode: String) -> void:
	_mode = mode
	_seats = [Profile.as_seat()]
	if mode == "ai":
		_add_ai(AiBrain.Level.MEDIUM)
		_add_ai(AiBrain.Level.HARD)
	else:
		_add_local()
	_render_setup()


func _free_token() -> String:
	var used := []
	for s in _seats:
		used.append(s["token"])
	for t in board.tokens:
		if not t in used:
			return t
	return board.tokens[0]


func _free_color() -> String:
	var used := []
	for s in _seats:
		used.append(s["color"])
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
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(640, 0)
	v.add_child(_title("Contra la IA" if _mode == "ai" else "Pasar y jugar", "De 2 a 6 jugadores"))
	var list := UiKit.vbox(6)
	v.add_child(list)
	for idx in _seats.size():
		list.add_child(_seat_row(idx))
	var add_row := UiKit.hbox(8)
	if _seats.size() < 6:
		add_row.add_child(UiKit.button("+ IA", func():
			_add_ai(AiBrain.Level.MEDIUM)
			_render_setup()))
		add_row.add_child(UiKit.button("+ Jugador local", func():
			_add_local()
			_render_setup()))
	v.add_child(add_row)
	v.add_child(_rules_panel(_rules, func(): Profile.rules = _rules.to_dict(); Profile.save_profile()))
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UiKit.button("Volver", func(): show_home()))
	var start := UiKit.button("Comenzar partida", func(): start_local.emit(_seats.duplicate(true), _rules), true)
	start.disabled = _seats.size() < 2
	row.add_child(start)
	v.add_child(row)
	_set_page(v)


func _seat_row(idx: int) -> Control:
	var s: Dictionary = _seats[idx]
	var row := UiKit.hbox(8)
	var icon_btn := Button.new()
	icon_btn.custom_minimum_size = Vector2(48, 48)
	icon_btn.focus_mode = Control.FOCUS_NONE
	icon_btn.tooltip_text = "Cambiar ficha"
	var icon := UiKit.token_icon(s["token"], Color.html(s["color"]), 44)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_btn.add_child(icon)
	row.add_child(icon_btn)
	if idx == 0:
		var l := UiKit.label(Profile.label_for(s) + " (tú)", 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		return row
	icon_btn.pressed.connect(func():
		var i := (board.tokens.find(s["token"]) + 1) % board.tokens.size()
		s["token"] = board.tokens[i]
		s["color"] = Profile.COLORS[(Profile.COLORS.find(s["color"]) + 1) % Profile.COLORS.size()]
		_render_setup())
	var name_edit := LineEdit.new()
	name_edit.text = s["name"]
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): s["name"] = t)
	row.add_child(name_edit)
	if int(s["ai"]) >= 0:
		var lvl := OptionButton.new()
		for l in LEVELS:
			lvl.add_item(l)
		lvl.selected = int(s["ai"])
		lvl.item_selected.connect(func(i): s["ai"] = i)
		row.add_child(lvl)
	else:
		var nick := LineEdit.new()
		nick.placeholder_text = "apodo"
		nick.text = s["nick"]
		nick.custom_minimum_size = Vector2(120, 0)
		nick.text_changed.connect(func(t): s["nick"] = t)
		row.add_child(nick)
	row.add_child(UiKit.button("Quitar", func():
		_seats.remove_at(idx)
		_render_setup()))
	return row


func _rules_panel(r: RulesConfig, on_change: Callable, editable: bool = true) -> Control:
	var v := UiKit.vbox(6)
	v.add_child(UiKit.label("Reglas", 20, UiKit.ACCENT))
	var mode := OptionButton.new()
	mode.add_item("Modo clásico")
	mode.add_item("Modo rápido")
	mode.selected = r.mode
	mode.disabled = not editable
	v.add_child(mode)
	var checks := {}
	var specs := [
		["speed_die", "Dado turbo (tercer dado: 1-3, » salta a la siguiente propiedad libre, $ bono)"],
		["free_parking_pot", "Bote en el Mirador (impuestos y multas se acumulan)"],
		["double_salary_on_go", "Doble sueldo al caer justo en la Salida ($400)"],
		["no_rent_in_jail", "No se cobra alquiler desde el Retén"],
		["end_on_first_bankruptcy", "Terminar en la primera quiebra (gana el mayor patrimonio)"],
	]
	for spec in specs:
		var cb := CheckBox.new()
		cb.text = spec[1]
		cb.button_pressed = r.get(spec[0])
		cb.disabled = not editable
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.toggled.connect(func(on):
			r.set(spec[0], on)
			on_change.call())
		v.add_child(cb)
		checks[spec[0]] = cb
	var hotel := CheckBox.new()
	hotel.text = "Hotel con solo 3 casas"
	hotel.button_pressed = r.houses_per_hotel == 3
	hotel.disabled = not editable
	hotel.toggled.connect(func(on):
		r.houses_per_hotel = 3 if on else 4
		on_change.call())
	v.add_child(hotel)
	var rounds_row := UiKit.hbox(8)
	rounds_row.add_child(UiKit.label("Límite de rondas (0 = sin límite)", 16))
	var rounds := SpinBox.new()
	rounds.max_value = 300
	rounds.step = 5
	rounds.value = r.max_rounds
	rounds.editable = editable
	rounds.value_changed.connect(func(val):
		r.max_rounds = int(val)
		on_change.call())
	rounds_row.add_child(rounds)
	v.add_child(rounds_row)
	mode.item_selected.connect(func(i):
		var preset := RulesConfig.quick() if i == 1 else RulesConfig.classic()
		r.mode = preset.mode
		r.end_on_first_bankruptcy = preset.end_on_first_bankruptcy
		r.houses_per_hotel = preset.houses_per_hotel
		r.speed_die = preset.speed_die
		checks["end_on_first_bankruptcy"].button_pressed = r.end_on_first_bankruptcy
		checks["speed_die"].button_pressed = r.speed_die
		hotel.button_pressed = r.houses_per_hotel == 3
		on_change.call())
	return UiKit.panel(v, UiKit.SOFT)


# ---------------------------------------------------------------------------
# Red local
# ---------------------------------------------------------------------------

func _adapter(kind: String) -> NetworkAdapter:
	return EnetAdapter.new() if kind == "wifi" else BluetoothAdapter.new()


func show_network(kind: String) -> void:
	_mode = kind
	var adapter := _adapter(kind)
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(560, 0)
	v.add_child(_title("Red local Wi-Fi" if kind == "wifi" else "Bluetooth", "Sin servidores externos: un dispositivo hace de anfitrión"))
	if not adapter.is_available():
		v.add_child(UiKit.label("Bluetooth requiere la app de Android con el plugin MagnatesBluetooth. En este dispositivo usa la red Wi-Fi.", 16, UiKit.DANGER))
		v.add_child(UiKit.button("Volver", func(): show_home()))
		_set_page(v)
		return
	var host_box := UiKit.vbox(8)
	host_box.add_child(UiKit.label("Crear sala", 20, UiKit.ACCENT))
	var room := LineEdit.new()
	room.text = "Sala de %s" % Profile.display_name
	host_box.add_child(room)
	host_box.add_child(UiKit.button("Crear sala como anfitrión", func():
		var err := Net.host_game(_adapter(kind), Profile.as_seat(), _rules.to_dict(), room.text)
		if err != OK:
			show_home("No se pudo crear la sala (error %d)" % err)
		else:
			show_lobby(), true))
	v.add_child(UiKit.panel(host_box, UiKit.SOFT))
	var join_box := UiKit.vbox(8)
	join_box.add_child(UiKit.label("Unirse", 20, UiKit.ACCENT))
	_hosts_list = UiKit.vbox(6)
	join_box.add_child(_hosts_list)
	if kind == "wifi":
		var err := Net.discovery.start_listening()
		if err != OK:
			join_box.add_child(UiKit.label("No se pudo escuchar salas en la red (error %d)." % err, 14, UiKit.DANGER))
		var manual := UiKit.hbox(8)
		var ip := LineEdit.new()
		ip.placeholder_text = "IP del anfitrión, ej. 192.168.1.20"
		ip.text = Profile.last_host
		ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		manual.add_child(ip)
		manual.add_child(UiKit.button("Conectar", func(): _join(kind, ip.text.strip_edges())))
		join_box.add_child(manual)
	v.add_child(UiKit.panel(join_box, UiKit.SOFT))
	v.add_child(UiKit.button("Volver", func():
		Net.leave()
		show_home()))
	var hosts_list := _hosts_list
	_set_page(v)
	_hosts_list = hosts_list
	_render_hosts()


func _render_hosts() -> void:
	if _hosts_list == null:
		return
	for c in _hosts_list.get_children():
		c.queue_free()
	var entries := []
	if _mode == "wifi":
		for h in Net.discovery.hosts():
			entries.append({"label": "%s  ·  %d/%d%s" % [h.get("name", "Sala"), int(h.get("players", 0)), int(h.get("max", 6)), "  (en juego)" if h.get("in_game", false) else ""], "address": h["ip"]})
		if entries.is_empty():
			_hosts_list.add_child(UiKit.label("Buscando salas en la red…", 15, UiKit.MUTED))
	else:
		for d in (BluetoothAdapter.new() as BluetoothAdapter).paired_devices():
			entries.append({"label": d["name"], "address": d["address"]})
		if entries.is_empty():
			_hosts_list.add_child(UiKit.label("Empareja primero los dispositivos desde los ajustes de Bluetooth.", 15, UiKit.MUTED))
	for entry in entries:
		_hosts_list.add_child(UiKit.button(entry["label"], func(): _join(_mode, entry["address"])))


func _join(kind: String, address: String) -> void:
	if address == "":
		return
	Profile.last_host = address
	Profile.save_profile()
	var err := Net.join_game(_adapter(kind), address, Profile.as_seat())
	if err != OK:
		show_home("No se pudo conectar (error %d)" % err)
		return
	show_lobby()


func show_lobby() -> void:
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(600, 0)
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
	var sub := "Eres el anfitrión · %s" % ("Wi-Fi: %s" % ", ".join(_local_ips()) if _mode == "wifi" else "Bluetooth") if host else "Esperando a que el anfitrión comience…"
	v.add_child(_title(Net.room_name if host else "Sala", sub))
	for idx in Net.seats.size():
		var s: Dictionary = Net.seats[idx]
		var row := UiKit.hbox(8)
		row.add_child(UiKit.token_icon(s["token"], Color.html(s["color"]), 40))
		var tag: String = LEVELS[int(s["ai"])] if int(s["ai"]) >= 0 else ("anfitrión" if int(s.get("peer", 0)) == 1 else "jugador")
		var l := UiKit.label("%s  ·  %s" % [Profile.label_for(s), tag], 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if host and idx > 0:
			row.add_child(UiKit.button("Quitar", func(): Net.remove_seat(idx)))
		v.add_child(row)
	var rules := RulesConfig.from_dict(Net.rules) if not Net.rules.is_empty() else _rules
	v.add_child(_rules_panel(rules, func(): Net.set_rules(rules.to_dict()), host))
	var row2 := UiKit.hbox(10)
	row2.alignment = BoxContainer.ALIGNMENT_END
	row2.add_child(UiKit.button("Salir de la sala", func():
		Net.leave()
		show_home()))
	if host:
		if Net.seats.size() < Net.MAX_SEATS:
			row2.add_child(UiKit.button("+ IA", func():
				Net.add_ai_seat(AiBrain.Level.MEDIUM, {"uuid": "ai-%d" % randi(), "name": AI_NAMES[Net.seats.size() % AI_NAMES.size()], "nick": "", "token": _free_token_for(Net.seats), "color": _free_color_for(Net.seats)})))
		var start := UiKit.button("Comenzar", func():
			var seats := []
			for s in Net.seats:
				var c: Dictionary = s.duplicate()
				c.erase("peer")
				seats.append(c)
			start_host.emit(_dedupe_tokens(seats), rules), true)
		start.disabled = Net.seats.size() < 2
		row2.add_child(start)
	v.add_child(row2)


func _local_ips() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(ip)
	return out


func _free_token_for(seats: Array) -> String:
	var used := seats.map(func(s): return s["token"])
	for t in board.tokens:
		if not t in used:
			return t
	return board.tokens[0]


func _free_color_for(seats: Array) -> String:
	var used := seats.map(func(s): return s["color"])
	for c in Profile.COLORS:
		if not c in used:
			return c
	return Profile.COLORS[0]


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
	## Fondo animado: burbujas y dados translúcidos que flotan.
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for k in 26:
			var base := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			var r := rng.randf_range(14, 70)
			var speed := rng.randf_range(8, 22)
			var p := Vector2(base.x + sin(_t * 0.3 + k) * 20.0, fposmod(base.y - _t * speed, size.y + 160) - 80)
			var col := Color(1, 1, 1, 0.08 + 0.06 * (k % 3))
			if k % 4 == 0:
				draw_set_transform(p, _t * 0.2 + k, Vector2.ONE)
				draw_rect(Rect2(-r / 2, -r / 2, r, r), col)
				draw_set_transform_matrix(Transform2D.IDENTITY)
			else:
				draw_circle(p, r / 2, col)
