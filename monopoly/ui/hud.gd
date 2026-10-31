class_name Hud
extends Control
## HUD de partida. Lee el estado del motor y envía comandos a través del GameController.

signal exit_requested
signal view_toggle_requested

var controller: GameController

var _players_bar: HBoxContainer
var _status: Label
var _actions: HFlowContainer
var _bottom: PanelContainer
var _log: RichTextLabel
var _log_panel: PanelContainer
var _overlay: Control
var _modal: Control
var _modal_kind := ""
var _modal_arg := -1
var _auction_panel: PanelContainer
var _trade_panel: PanelContainer
var _card_panel: PanelContainer
var _card_timer: SceneTreeTimer
var _handoff: Control
var _toast: Label
var _view_btn: Button
var _player_cards: Dictionary = {}   # pid -> PanelContainer
var _floats: Dictionary = {}         # pid -> avisos de dinero visibles (para apilarlos)
var _last_local_actor := -1
var _game_over_shown := false
var _deed_back: Dictionary = {}      # casilla -> la tarjeta muestra el dorso
var _banners := 0                    # avisos grandes visibles (para apilarlos)


func setup(c: GameController, view2d: BoardView2D, view3d: BoardView3D) -> void:
	controller = c
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	controller.state_changed.connect(_refresh)
	controller.player_events.event_played.connect(_on_event)
	controller.player_events.drained.connect(_refresh)
	controller.command_failed.connect(toast)
	view2d.space_clicked.connect(_show_space)
	view3d.space_clicked.connect(_show_space)
	if Net.is_host():
		Net.rejoin_requested.connect(_on_rejoin_request)
	_refresh()


func e() -> GameEngine:
	return controller.engine


func _pname(pid: int) -> String:
	if pid == GameEngine.BANK or pid == GameEngine.POT:
		return "el Banco"
	var p := e().player(pid)
	return "[color=%s]%s[/color]" % [p["color"], Profile.label_for(p)]


func _plain(pid: int) -> String:
	return "el Banco" if pid < 0 else Profile.label_for(e().player(pid))


func _space_name(i: int) -> String:
	return controller.board.space(i)["name"]


func _submit(cmd: Dictionary) -> void:
	controller.submit(cmd)


# ---------------------------------------------------------------------------
# Construcción
# ---------------------------------------------------------------------------

func _build() -> void:
	# Barra superior
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right", "top"]:
		top.add_theme_constant_override("margin_" + side, 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var top_row := UiKit.hbox(8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # se desliza con el dedo
	scroll.custom_minimum_size = Vector2(0, 66)
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	top_row.add_child(scroll)
	_players_bar = UiKit.hbox(8)
	scroll.add_child(_players_bar)
	_view_btn = UiKit.button("2D", func(): view_toggle_requested.emit())
	top_row.add_child(_view_btn)
	top_row.add_child(UiKit.button("Registro", func():
		Profile.show_log = not Profile.show_log
		Profile.apply_settings()))
	top_row.add_child(UiKit.button("Opciones", _show_settings))
	top_row.add_child(UiKit.button("Salir", _confirm_exit))

	# Registro
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.88), 20, 14, 12, Color(0, 0, 0, 0), 0, true))
	_log_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_log_panel.offset_left = -320
	_log_panel.offset_right = -10
	_log_panel.offset_top = 92
	_log_panel.offset_bottom = -150
	_log_panel.visible = Profile.show_log
	Profile.settings_changed.connect(func(): _log_panel.visible = Profile.show_log)
	add_child(_log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 17)
	_log.mouse_filter = Control.MOUSE_FILTER_PASS
	_log_panel.add_child(_log)

	# Barra inferior de acciones
	_bottom = PanelContainer.new()
	_bottom.add_theme_stylebox_override("panel", UiKit.card())
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom.offset_bottom = -10
	_bottom.custom_minimum_size = Vector2(minf(760, get_viewport_rect().size.x - 20), 0)
	add_child(_bottom)
	var bv := UiKit.vbox(8)
	_bottom.add_child(bv)
	_status = UiKit.label("", 19, UiKit.TEXT, true)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_status)
	_actions = HFlowContainer.new()
	_actions.alignment = FlowContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.add_theme_constant_override("v_separation", 8)
	bv.add_child(_actions)

	# Subasta (no modal)
	_auction_panel = PanelContainer.new()
	_auction_panel.add_theme_stylebox_override("panel", UiKit.card(UiKit.PANEL, UiKit.GOLD))
	_auction_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_auction_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_auction_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_auction_panel.visible = false
	add_child(_auction_panel)

	# Intercambio entrante / pendiente
	_trade_panel = PanelContainer.new()
	_trade_panel.add_theme_stylebox_override("panel", UiKit.card(UiKit.PANEL, UiKit.ACCENT_2))
	_trade_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_trade_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_trade_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_trade_panel.visible = false
	add_child(_trade_panel)

	# Carta
	_card_panel = PanelContainer.new()
	_card_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_card_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card_panel.offset_top = 110
	_card_panel.custom_minimum_size = Vector2(minf(440, get_viewport_rect().size.x - 30), 0)
	_card_panel.visible = false
	_card_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_panel.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: _card_panel.visible = false)
	add_child(_card_panel)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_toast = UiKit.label("", 17, Color.WHITE, true)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 86
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.custom_minimum_size.x = minf(520, get_viewport_rect().size.x - 40)
	_toast.add_theme_stylebox_override("normal", UiKit.box(UiKit.DANGER, 20, 18, 10, Color(0, 0, 0, 0), 0, true))
	_toast.visible = false
	add_child(_toast)


func set_view_label(mode: String) -> void:
	_view_btn.text = "Ver 2D" if mode == "3d" else "Ver 3D"


func toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _toast.visible = false)


# ---------------------------------------------------------------------------
# Refresco
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if controller.engine == null:
		return
	_refresh_players()
	_refresh_actions()
	_refresh_auction()
	_refresh_trade()
	if _modal and is_instance_valid(_modal):
		match _modal_kind:
			"manager":
				_show_manager()
			"space":
				_show_space(_modal_arg)
			"player":
				_show_player(_modal_arg)
	var local := controller.local_actor()
	if e().phase() == GameEngine.AWAIT_BUY and local >= 0 and not controller.is_busy() and _modal_kind != "buy" and e().s["trade"].is_empty():
		_modal_kind = "buy_pending"
		_show_space(int(e().s["pending_buy"]))
	elif _modal_kind == "buy" and (e().phase() != GameEngine.AWAIT_BUY or local < 0):
		_close_modal()
	if e().is_over() and not _game_over_shown and not controller.is_busy():
		_show_game_over()


func _refresh_players() -> void:
	for child in _players_bar.get_children():
		child.queue_free()
	_player_cards.clear()
	var shown: Dictionary = controller.player_events.shown_cash
	for p in e().players():
		var pid := int(p["id"])
		var cur := pid == e().current() and not e().is_over()
		var card := PanelContainer.new()
		var pcol := Color.html(p["color"])
		var sb := UiKit.box(Color("#fff7d6") if cur else Color.WHITE, 18, 10, 6, pcol if cur else Color(0, 0, 0, 0), 3, true)
		sb.border_width_bottom = 6
		sb.border_color = pcol
		card.add_theme_stylebox_override("panel", sb)
		card.modulate.a = 0.45 if p["bankrupt"] else 1.0
		_player_cards[pid] = card
		var row := UiKit.hbox(8)
		card.add_child(row)
		row.add_child(UiKit.token_icon(p["token"], Color.html(p["color"]), 34))
		var col := UiKit.vbox(0)
		row.add_child(col)
		var name_l := UiKit.label(Profile.label_for(p), 14)
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(name_l)
		var tags := []
		if p["bankrupt"]:
			tags.append("QUIEBRA")
		if p["in_jail"]:
			tags.append("Retén")
		if int(p["ai"]) >= 0:
			tags.append("IA " + ["fácil", "media", "difícil"][int(p["ai"])])
		if not p["connected"]:
			tags.append("desconectado (IA)")
		if not p["jail_cards"].is_empty():
			tags.append("pase x%d" % p["jail_cards"].size())
		var owned := e().properties_of(pid).size()
		if owned > 0 and not p["bankrupt"]:
			tags.append("%d prop." % owned)
		var cash_l := UiKit.label("Bs %d" % int(shown.get(pid, p["cash"])), 18, UiKit.GOOD.darkened(0.1))
		cash_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(cash_l)
		if not tags.is_empty():
			var tl := UiKit.label(" · ".join(tags), 11, UiKit.MUTED)
			tl.autowrap_mode = TextServer.AUTOWRAP_OFF
			col.add_child(tl)
		# Tocar un perfil muestra sus terrenos.
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.tooltip_text = "Ver sus terrenos"
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
				Sfx.play("click")
				_show_player(pid))
		_players_bar.add_child(card)


func _refresh_actions() -> void:
	for child in _actions.get_children():
		child.queue_free()
	var en := e()
	if en.is_over():
		_status.text = "Partida terminada"
		return
	var actor := en.pending_actor()
	var local := controller.local_actor()
	_check_handoff(local)
	var who := _plain(actor)
	var p := en.player(actor)
	var text := ""
	match en.phase():
		GameEngine.PRE_ROLL:
			text = "Turno de %s" % who
			if p["in_jail"]:
				text += " — en el Retén (intento %d de 3)" % (int(p["jail_turns"]) + 1)
			elif int(en.s["doubles"]) > 0:
				text += " — ¡dobles, tira otra vez!"
		GameEngine.AWAIT_BUY:
			var i: int = en.s["pending_buy"]
			text = "%s puede comprar %s por Bs %d" % [who, _space_name(i), controller.board.price(i)]
		GameEngine.AUCTION:
			text = "Subasta de %s — puja %s" % [_space_name(int(en.s["auction"]["space"])), who]
		GameEngine.DEBT:
			var d: Dictionary = en.s["debts"][0]
			text = "%s debe Bs %d a %s. Hipoteca o vende para pagar." % [who, int(d["amount"]), _plain(int(d["creditor"]))]
		GameEngine.POST_ROLL:
			text = "%s: gestiona tus propiedades o termina el turno" % who
	if not en.s["trade"].is_empty():
		text = "Intercambio pendiente: responde %s" % _plain(int(en.s["trade"]["to"]))
	if local < 0:
		if controller.controlled_by_ai(actor):
			text += "  (pensando…)"
		elif controller.networked:
			text += "  (en otro dispositivo)"
	_status.text = text
	if local < 0 or controller.is_busy():
		return
	var legal := en.legal_actions(local)
	var pc := en.player(local)
	for a in legal:
		match a:
			"roll":
				var label := "Intentar dobles" if pc["in_jail"] else "Tirar dados"
				_actions.add_child(UiKit.button(label, func(): _submit({"type": "roll", "player": local}), true))
			"pay_jail":
				_actions.add_child(UiKit.button("Pagar Bs %d y tirar" % controller.board.jail_fine, func():
					_submit({"type": "pay_jail", "player": local})
					_submit({"type": "roll", "player": local}), true, UiKit.ACCENT_2))
			"use_jail_card":
				_actions.add_child(UiKit.button("Usar salvoconducto y tirar", func():
					_submit({"type": "use_jail_card", "player": local})
					_submit({"type": "roll", "player": local})))
			"buy":
				var i: int = en.s["pending_buy"]
				_actions.add_child(UiKit.button("Comprar Bs %d" % controller.board.price(i), func(): _submit({"type": "buy", "player": local}), true))
			"decline":
				_actions.add_child(UiKit.button("No comprar (subasta)", func(): _submit({"type": "decline", "player": local})))
			"end_turn":
				_actions.add_child(UiKit.button("Terminar turno", func(): _submit({"type": "end_turn", "player": local}), true))
			"pay_debt":
				_actions.add_child(UiKit.button("Pagar deuda", func(): _submit({"type": "pay_debt", "player": local}), true))
			"bankrupt":
				_actions.add_child(UiKit.button("Declarar quiebra", func(): _confirm("¿Declarar la quiebra? Perderás todo.", func(): _submit({"type": "bankrupt", "player": local}))))
			"trade_propose":
				_actions.add_child(UiKit.button("Negociar", _show_trade_composer))
	if en.phase() in [GameEngine.PRE_ROLL, GameEngine.POST_ROLL, GameEngine.DEBT, GameEngine.AWAIT_BUY] and not en.properties_of(local).is_empty() and "mortgage" in legal:
		_actions.add_child(UiKit.button("Mis propiedades (%d)" % en.properties_of(local).size(), _show_manager))
	if en.phase() == GameEngine.DEBT and int(pc["cash"]) < int(en.s["debts"][0]["amount"]):
		_status.text += "  Te faltan Bs %d." % (int(en.s["debts"][0]["amount"]) - int(pc["cash"]))


func _check_handoff(local: int) -> void:
	if local < 0 or controller.networked or controller.local_humans().size() < 2:
		return
	if local == _last_local_actor:
		return
	_last_local_actor = local
	if _handoff and is_instance_valid(_handoff):
		_handoff.queue_free()
	var p := e().player(local)
	var v := UiKit.vbox(14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := UiKit.token_icon(p["token"], Color.html(p["color"]), 96)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var l := UiKit.label("Pasa el dispositivo a\n%s" % Profile.label_for(p), 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	v.add_child(UiKit.button("Soy %s, continuar" % p["name"], func(): _handoff.queue_free(), true))
	_handoff = UiKit.modal(UiKit.panel(v), _overlay)


# ---------------------------------------------------------------------------
# Subasta e intercambio
# ---------------------------------------------------------------------------

func _refresh_auction() -> void:
	var en := e()
	_auction_panel.visible = en.phase() == GameEngine.AUCTION
	if not _auction_panel.visible:
		return
	for child in _auction_panel.get_children():
		child.queue_free()
	var a: Dictionary = en.s["auction"]
	var i: int = a["space"]
	var v := UiKit.vbox(8)
	v.custom_minimum_size = Vector2(380, 0)
	_auction_panel.add_child(v)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.swatch(controller.board.space_color(i), Vector2(10, 28)))
	var title := UiKit.label("SUBASTA · %s" % _space_name(i), 20, UiKit.HEADING)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(title)
	v.add_child(head)
	v.add_child(UiKit.label("Precio de lista Bs %d" % controller.board.price(i), 15, UiKit.MUTED))
	var hb := int(a["high_bidder"])
	v.add_child(UiKit.label("Puja más alta: %s" % ("Bs %d de %s" % [int(a["high"]), _plain(hb)] if hb >= 0 else "ninguna"), 18))
	var names := []
	for pid in a["bidders"]:
		names.append(_plain(int(pid)))
	v.add_child(UiKit.label("En la puja: " + ", ".join(names), 14, UiKit.MUTED))
	var local := controller.local_actor()
	if local < 0 or controller.is_busy():
		v.add_child(UiKit.label("Esperando a %s…" % _plain(en.pending_actor()), 15, UiKit.MUTED))
		return
	var cash: int = en.player(local)["cash"]
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	v.add_child(row)
	var base := en.min_bid()
	# Montos redondos sugeridos: la mínima y saltos de 10 %, 25 % y 50 % del precio.
	var price := controller.board.price(i)
	var amounts := [base]
	for f in [0.1, 0.25, 0.5]:
		var amt := int(ceil((base + price * f) / 10.0) * 10)
		if amt > amounts.back():
			amounts.append(amt)
	for amount in amounts:
		if amount > cash:
			break
		row.add_child(UiKit.button("Bs %d" % amount, func(): Sfx.play("bid"); _submit({"type": "bid", "player": local, "amount": amount}), amount == base))
	row.add_child(UiKit.button("Retirarme", func(): _submit({"type": "pass_bid", "player": local})))
	v.add_child(UiKit.label("Tu efectivo: Bs %d" % cash, 15, UiKit.MUTED))
	if base > cash:
		var short := UiKit.label("No te alcanza para pujar: hipoteca o vende casas.", 15, UiKit.DANGER, true)
		short.custom_minimum_size.x = 360
		v.add_child(short)
	if not en.properties_of(local).is_empty():
		v.add_child(UiKit.button("Mis propiedades · conseguir dinero", _show_manager, base > cash, UiKit.ACCENT_2))


func _refresh_trade() -> void:
	var en := e()
	var t: Dictionary = en.s["trade"]
	_trade_panel.visible = not t.is_empty()
	if t.is_empty():
		return
	for child in _trade_panel.get_children():
		child.queue_free()
	var v := UiKit.vbox(8)
	v.custom_minimum_size = Vector2(420, 0)
	_trade_panel.add_child(v)
	var from := int(t["from"])
	var to := int(t["to"])
	v.add_child(UiKit.label("Propuesta de %s para %s" % [_plain(from), _plain(to)], 19, UiKit.HEADING))
	v.add_child(UiKit.label("%s entrega:" % _plain(from), 15, UiKit.MUTED))
	v.add_child(_offer_chips(t["give"]))
	v.add_child(UiKit.label("%s entrega:" % _plain(to), 15, UiKit.MUTED))
	v.add_child(_offer_chips(t["get"]))
	var row := UiKit.hbox(8)
	v.add_child(row)
	if controller.is_local_human(to):
		row.add_child(UiKit.button("Aceptar", func(): _submit({"type": "trade_accept", "player": to}), true))
		row.add_child(UiKit.button("Rechazar", func(): _submit({"type": "trade_reject", "player": to})))
	elif controller.is_local_human(from):
		row.add_child(UiKit.label("Esperando respuesta…", 15, UiKit.MUTED))
		row.add_child(UiKit.button("Cancelar", func(): _submit({"type": "trade_cancel", "player": from})))
	else:
		row.add_child(UiKit.label("Esperando respuesta…", 15, UiKit.MUTED))


## Chips de colores: cada propiedad con el color de su grupo, el dinero en dorado.
func _offer_chips(o: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	if int(o["cash"]) > 0:
		flow.add_child(UiKit.chip("Bs %d" % int(o["cash"]), UiKit.GOLD))
	for i in o["props"]:
		flow.add_child(UiKit.chip(_space_name(int(i)), controller.board.space_color(int(i))))
	if int(o["cards"]) > 0:
		flow.add_child(UiKit.chip("%d salvoconducto(s)" % int(o["cards"]), UiKit.ACCENT_2))
	if flow.get_child_count() == 0:
		flow.add_child(UiKit.chip("nada", UiKit.SOFT))
	return flow


func _offer_text(o: Dictionary) -> String:
	var parts := []
	if int(o["cash"]) > 0:
		parts.append("Bs %d" % int(o["cash"]))
	for i in o["props"]:
		parts.append(_space_name(int(i)))
	if int(o["cards"]) > 0:
		parts.append("%d salvoconducto(s)" % int(o["cards"]))
	return "nada" if parts.is_empty() else ", ".join(parts)


func _show_trade_composer() -> void:
	var en := e()
	var me := controller.local_actor()
	if me < 0:
		return
	var others := []
	for pid in en.active_players():
		if pid != me:
			others.append(pid)
	if others.is_empty():
		return
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(minf(720, get_viewport_rect().size.x - 40), 0)
	v.add_child(UiKit.label("Negociar", 24, UiKit.HEADING))
	var target := OptionButton.new()
	for pid in others:
		target.add_item(_plain(pid), pid)
	v.add_child(target)
	var cols := UiKit.hbox(16)
	v.add_child(cols)
	var state := {"give": {}, "get": {}}
	var balance := UiKit.label("", 15, UiKit.MUTED)
	## Valor de lista de lo que das frente a lo que recibes, para negociar con criterio.
	var update_balance := func():
		var sums := {}
		for key in ["give", "get"]:
			var d: Dictionary = state[key]
			if d.is_empty():
				sums[key] = 0
				continue
			var total := int(d["cash"].value)
			for cb in d["checks"]:
				if cb.button_pressed:
					var sp: int = cb.get_meta("space")
					total += controller.board.mortgage_value(sp) if en.is_mortgaged(sp) else controller.board.price(sp)
			sums[key] = total
		balance.text = "Das ≈ Bs %d   ·   Recibes ≈ Bs %d" % [sums["give"], sums["get"]]
	var build_side := func(owner_pid: int, key: String, title: String) -> VBoxContainer:
		var col := UiKit.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.label(title, 18))
		var checks := []
		var list := UiKit.vbox(4)
		col.add_child(EasyScroll.wrap(list, 220))
		for i in en.properties_of(owner_pid):
			var cb := CheckBox.new()
			cb.text = _space_name(i) + (" (hipotecada)" if en.is_mortgaged(i) else "")
			cb.disabled = en.houses_on(i) > 0
			cb.tooltip_text = "Tiene edificios: véndelos primero" if cb.disabled else ""
			cb.set_meta("space", i)
			var tint := controller.board.space_color(i)
			cb.add_theme_stylebox_override("normal", UiKit.box(tint.lerp(Color.WHITE, 0.82), 14, 12, 8, tint, 0))
			cb.add_theme_stylebox_override("hover", UiKit.box(tint.lerp(Color.WHITE, 0.7), 14, 12, 8))
			cb.add_theme_stylebox_override("pressed", UiKit.box(tint.lerp(Color.WHITE, 0.55), 14, 12, 8, tint, 3))
			cb.add_theme_stylebox_override("hover_pressed", UiKit.box(tint.lerp(Color.WHITE, 0.5), 14, 12, 8, tint, 3))
			var sb: StyleBoxFlat = cb.get_theme_stylebox("normal")
			sb.border_width_left = 8
			sb.border_color = tint
			cb.toggled.connect(func(_on): update_balance.call())
			list.add_child(cb)
			checks.append(cb)
		var cash := SpinBox.new()
		cash.max_value = int(en.player(owner_pid)["cash"])
		cash.step = 10
		cash.prefix = "Bs "
		cash.value_changed.connect(func(_v): update_balance.call())
		col.add_child(cash)
		var cards := SpinBox.new()
		cards.max_value = en.player(owner_pid)["jail_cards"].size()
		cards.suffix = " salvoconductos"
		cards.visible = cards.max_value > 0
		col.add_child(cards)
		state[key] = {"checks": checks, "cash": cash, "cards": cards}
		return col
	cols.add_child(build_side.call(me, "give", "Tú das"))
	var their_col := UiKit.vbox(0)
	their_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(their_col)
	var rebuild_their := func():
		for child in their_col.get_children():
			child.queue_free()
		their_col.add_child(build_side.call(target.get_selected_id(), "get", "Pides"))
	rebuild_their.call()
	target.item_selected.connect(func(_idx): rebuild_their.call())
	var collect := func(key: String) -> Dictionary:
		var d: Dictionary = state[key]
		var props := []
		for cb in d["checks"]:
			if cb.button_pressed:
				props.append(cb.get_meta("space"))
		return {"cash": int(d["cash"].value), "props": props, "cards": int(d["cards"].value)}
	v.add_child(balance)
	update_balance.call()
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UiKit.button("Cancelar", _close_modal))
	row.add_child(UiKit.button("Proponer", func():
		_submit({"type": "trade_propose", "player": me, "to": target.get_selected_id(), "give": collect.call("give"), "get": collect.call("get")})
		_close_modal(), true))
	_open_modal(UiKit.panel(v), "trade", -1)


# ---------------------------------------------------------------------------
# Propiedades
# ---------------------------------------------------------------------------

func _show_space(i: int) -> void:
	var en := e()
	var b := controller.board
	var sp := b.space(i)
	var v := UiKit.vbox(6)
	v.custom_minimum_size = Vector2(340, 0)
	if b.is_property(i):
		_show_property(i)
		return
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiKit.box(b.space_color(i) if sp["type"] == "street" else UiKit.ACCENT, 16, 12, 14))
	var hl := UiKit.label(String(sp["name"]).to_upper(), 22, Color.WHITE)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(hl)
	v.add_child(head)
	match sp["type"]:
		"street":
			var r: Array = sp["rents"]
			_row(v, "Alquiler", "Bs %d" % r[0])
			_row(v, "Con el grupo completo", "Bs %d" % (int(r[0]) * 2))
			for k in range(1, 5):
				_row(v, "Con %d casa%s" % [k, "" if k == 1 else "s"], "Bs %d" % r[k])
			_row(v, "Con hotel", "Bs %d" % r[5])
			_row(v, "Cada casa cuesta", "Bs %d" % b.house_cost(i))
		"transit":
			for k in 4:
				_row(v, "Con %d teleférico%s" % [k + 1, "" if k == 0 else "s"], "Bs %d" % sp["rents"][k])
		"utility":
			_row(v, "Con 1 servicio", "%d × dados" % sp["multipliers"][0])
			_row(v, "Con ambos", "%d × dados" % sp["multipliers"][1])
		"tax":
			v.add_child(UiKit.label("Paga Bs %d al caer aquí." % int(sp["amount"]), 16, UiKit.TEXT, true))
		"card":
			v.add_child(UiKit.label("Roba una carta de %s." % ("Destino" if sp["deck"] == "destino" else "Cabildo"), 16, UiKit.TEXT, true))
		"go":
			v.add_child(UiKit.label("Cobra Bs %d cada vez que pases." % b.salary, 16, UiKit.TEXT, true))
		"jail":
			v.add_child(UiKit.label("Si solo estás de visita, no pasa nada.", 16, UiKit.TEXT, true))
		"free":
			v.add_child(UiKit.label("Descanso. Con la regla del bote, cobras lo acumulado.", 16, UiKit.TEXT, true))
		"gotojail":
			v.add_child(UiKit.label("Vas directo al Retén sin cobrar sueldo.", 16, UiKit.TEXT, true))
	v.add_child(UiKit.button("Cerrar", _close_modal))
	_open_modal(UiKit.panel(v), "space", i)


## Ficha de una propiedad: título de doble cara + acciones (comprar o gestionar).
func _show_property(i: int) -> void:
	var en := e()
	var b := controller.board
	var v := UiKit.vbox(10)
	v.add_child(_deed(i))
	var own := en.owner_of(i)
	var me := controller.local_actor()
	if own >= 0 and own == me:
		var row := HFlowContainer.new()
		row.alignment = FlowContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		v.add_child(row)
		_manage_buttons(row, me, i)
	if _modal_kind == "buy_pending":
		var me2 := controller.local_actor()
		var row2 := UiKit.hbox(10)
		var buy := UiKit.button("Comprar Bs %d" % b.price(i), func():
			_close_modal()
			_submit({"type": "buy", "player": me2}), true, UiKit.GOOD)
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy.disabled = int(en.player(me2)["cash"]) < b.price(i)
		var auc := UiKit.button("Subastar", func():
			_close_modal()
			_submit({"type": "decline", "player": me2}))
		auc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(buy)
		row2.add_child(auc)
		v.add_child(row2)
		if buy.disabled:
			var warn := UiKit.label("No te alcanza: hipoteca algo desde «Mis propiedades» o súbastala.", 14, UiKit.DANGER, true)
			warn.custom_minimum_size.x = 340
			v.add_child(warn)
			if not en.properties_of(me2).is_empty():
				v.add_child(UiKit.button("Mis propiedades", _show_manager))
		_open_modal(UiKit.panel(v), "buy", i)
		return
	v.add_child(UiKit.button("Cerrar", _close_modal))
	_open_modal(UiKit.panel(v), "space", i)


func _row(parent: Control, a: String, b: String) -> void:
	var h := UiKit.hbox(8)
	var la := UiKit.label(a, 15, UiKit.MUTED)
	la.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(la)
	var lb := UiKit.label(b, 16)
	lb.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(lb)
	parent.add_child(h)


func _manage_buttons(row: Control, me: int, i: int) -> void:
	var en := e()
	var b := controller.board
	var legal := en.legal_actions(me)
	var refund := b.house_cost(i) / 2
	var specs := [
		["build", "+ Casa · Bs %d" % b.house_cost(i), en.can_build(me, i), UiKit.GOOD],
		["sell_building", "− Casa · +Bs %d" % refund, en.can_sell_building(me, i), Color(0, 0, 0, 0)],
		["mortgage", "Hipotecar · +Bs %d" % b.mortgage_value(i), en.can_mortgage(me, i), Color(0, 0, 0, 0)],
		["unmortgage", "Levantar · Bs %d" % en.unmortgage_cost(i), en.can_unmortgage(me, i), UiKit.ACCENT],
	]
	for s in specs:
		if not b.is_street(i) and s[0] in ["build", "sell_building"]:
			continue
		if s[0] == "mortgage" and en.is_mortgaged(i):
			continue
		if s[0] == "unmortgage" and not en.is_mortgaged(i):
			continue
		if s[0] == "sell_building" and en.houses_on(i) == 0:
			continue
		var btn := UiKit.small_button(s[1], func(): _submit({"type": s[0], "player": me, "space": i}), s[3])
		btn.disabled = s[2] != "" or not (s[0] in legal)
		btn.tooltip_text = s[2]
		row.add_child(btn)


func _show_manager() -> void:
	var en := e()
	var me := controller.local_actor()
	if me < 0:
		_close_modal()
		return
	var vw := get_viewport_rect().size
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(minf(680, vw.x - 48), 0)
	var head := UiKit.hbox(10)
	var title := UiKit.label("Mis propiedades", 24, UiKit.HEADING)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiKit.chip("Efectivo Bs %d" % int(en.player(me)["cash"]), UiKit.GOLD))
	v.add_child(head)
	var list := UiKit.vbox(8)
	v.add_child(EasyScroll.wrap(list, minf(460, vw.y - 230)))
	for i in en.properties_of(me):
		var card := PanelContainer.new()
		var tint := controller.board.space_color(i)
		var sb := UiKit.box(Color.WHITE, 16, 14, 10, UiKit.LINE, 2)
		sb.border_width_left = 8
		sb.border_color = tint
		card.add_theme_stylebox_override("panel", sb)
		var col := UiKit.vbox(6)
		card.add_child(col)
		var top := UiKit.hbox(8)
		var name_l := UiKit.label(_space_name(i), 18, UiKit.HEADING)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		top.add_child(name_l)
		var h := en.houses_on(i)
		if h == GameEngine.HOTEL:
			top.add_child(UiKit.chip("Hotel", UiKit.DANGER))
		elif h > 0:
			top.add_child(UiKit.chip("%d casa%s" % [h, "" if h == 1 else "s"], UiKit.GOOD))
		if en.is_mortgaged(i):
			top.add_child(UiKit.chip("Hipotecada", UiKit.SOFT))
		col.add_child(top)
		var buttons := HFlowContainer.new()
		buttons.alignment = FlowContainer.ALIGNMENT_END
		buttons.add_theme_constant_override("h_separation", 6)
		buttons.add_theme_constant_override("v_separation", 6)
		_manage_buttons(buttons, me, i)
		col.add_child(buttons)
		list.add_child(card)
	v.add_child(UiKit.button("Cerrar", _close_modal))
	_open_modal(UiKit.panel(v), "manager", -1)


# ---------------------------------------------------------------------------
# Modales
# ---------------------------------------------------------------------------

func _open_modal(content: Control, kind: String, arg: int) -> void:
	_close_modal()
	_modal = UiKit.modal(content, _overlay)
	_modal_kind = kind
	_modal_arg = arg
	_modal.gui_input.connect(func(ev):
		# Solo las vistas cortas se cierran tocando afuera; las listas largas piden «Cerrar».
		if ev is InputEventMouseButton and ev.pressed and kind in ["space", "player", "confirm"]:
			_close_modal())


func _close_modal() -> void:
	if _modal and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_modal_kind = ""


func _confirm(msg: String, on_yes: Callable) -> void:
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(380, 0)
	v.add_child(UiKit.label(msg, 19, UiKit.TEXT, true))
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UiKit.button("Cancelar", _close_modal))
	row.add_child(UiKit.button("Confirmar", func():
		_close_modal()
		on_yes.call(), true))
	v.add_child(row)
	_open_modal(UiKit.panel(v), "confirm", -1)


func _confirm_exit() -> void:
	_confirm("¿Salir al menú principal?" + ("\nLos demás jugadores perderán la conexión." if Net.is_host() else ""), func(): exit_requested.emit())


func _show_settings() -> void:
	_open_modal(OptionsPanel.build(_close_modal), "settings", -1)


func _show_game_over() -> void:
	_game_over_shown = true
	_close_modal()
	var en := e()
	var v := UiKit.vbox(10)
	v.custom_minimum_size = Vector2(420, 0)
	var w := int(en.s["winner"])
	var title := UiKit.label("¡%s gana!" % _plain(w) if w >= 0 else "Fin de la partida", 30, UiKit.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var ranking := []
	for p in en.players():
		ranking.append({"p": p, "worth": 0 if p["bankrupt"] else en.net_worth(int(p["id"]))})
	ranking.sort_custom(func(a, b): return a["worth"] > b["worth"])
	var pos := 1
	for r in ranking:
		var row := UiKit.hbox(10)
		row.add_child(UiKit.label("%d." % pos, 18))
		row.add_child(UiKit.token_icon(r["p"]["token"], Color.html(r["p"]["color"]), 32))
		var l := UiKit.label(Profile.label_for(r["p"]), 18)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UiKit.label("quiebra" if r["p"]["bankrupt"] else "Bs %d" % r["worth"], 18, UiKit.MUTED if r["p"]["bankrupt"] else UiKit.GOOD))
		v.add_child(row)
		pos += 1
	v.add_child(UiKit.label("Patrimonio = efectivo + propiedades + edificios", 13, UiKit.MUTED))
	v.add_child(UiKit.button("Volver al menú", func(): exit_requested.emit(), true))
	UiKit.modal(UiKit.panel(v), _overlay)


# ---------------------------------------------------------------------------
# Eventos -> registro y cartas
# ---------------------------------------------------------------------------

func _on_event(ev: Dictionary) -> void:
	if ev["type"] == "money":
		_refresh_players()
		_money_float(int(ev["player"]), int(ev["delta"]))
		_money_flow(ev)
	var line := _describe(ev)
	if line != "":
		_log.append_text(line + "\n")
	_animate_event(ev)
	if ev["type"] == "card_drawn":
		_show_card(ev)


## Aviso flotante "+Bs 200" / "−Bs 50" bajo la tarjeta del jugador.
func _money_float(pid: int, delta: int) -> void:
	var card: Control = _player_cards.get(pid)
	if card == null:
		return
	var l := UiKit.label(("+Bs %d" if delta > 0 else "−Bs %d") % absi(delta), 22, UiKit.GOOD if delta > 0 else UiKit.DANGER)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(l)
	await get_tree().process_frame
	if not is_instance_valid(card):
		l.queue_free()
		return
	var stack: int = _floats.get(pid, 0)
	_floats[pid] = stack + 1
	l.tree_exited.connect(func(): _floats[pid] = maxi(0, int(_floats.get(pid, 1)) - 1))
	l.global_position = card.global_position + Vector2(card.size.x / 2.0 - l.size.x / 2.0, card.size.y + 4 + stack * 26)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 26, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


func _show_card(ev: Dictionary) -> void:
	for child in _card_panel.get_children():
		child.queue_free()
	var destino: bool = ev["deck"] == "destino"
	var col := UiKit.DESTINO if destino else UiKit.CABILDO
	var width := _card_panel.custom_minimum_size.x
	_card_panel.add_theme_stylebox_override("panel", UiKit.box(Color.WHITE, 24, 0, 0, col, 5, true))
	_card_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var v := UiKit.vbox(0)
	_card_panel.add_child(v)
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiKit.box(col, 0, 18, 10))
	var bh := UiKit.hbox(10)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := UiKit.label("?" if destino else "!", 30, Color.WHITE)
	icon.add_theme_font_override("font", UiKit.font_black())
	bh.add_child(icon)
	var t := UiKit.label("DESTINO" if destino else "CABILDO", 24, Color.WHITE)
	t.add_theme_font_override("font", UiKit.font_black())
	bh.add_child(t)
	band.add_child(bh)
	v.add_child(band)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 20)
	v.add_child(pad)
	# Ancho fijo: un texto con ajuste de línea sin ancho se parte letra por letra.
	var body := UiKit.label(ev["text"], 20, UiKit.TEXT, true)
	body.custom_minimum_size.x = width - 40
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad.add_child(body)
	Sfx.play("flip")
	_card_panel.visible = true
	_card_panel.scale = Vector2(0.8, 0.8)
	_card_panel.pivot_offset = _card_panel.size / 2.0
	create_tween().tween_property(_card_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	var timer := get_tree().create_timer(3.0)
	_card_timer = timer
	timer.timeout.connect(func(): if _card_timer == timer: _card_panel.visible = false)


func _describe(ev: Dictionary) -> String:
	var b := controller.board
	match ev["type"]:
		"turn_started":
			return "[color=#888]— Turno de %s (ronda %d)[/color]" % [_pname(int(ev["player"])), int(ev["round"])]
		"dice_rolled":
			var d: Array = ev["dice"]
			var s := "%s tira %d + %d" % [_pname(int(ev["player"])), d[0], d[1]]
			if int(d[2]) > 0:
				s += " · turbo " + (str(d[2]) if int(d[2]) <= 3 else ("»" if int(d[2]) == GameEngine.SPEED_BOLT else "Bs"))
			return s + (" [color=#e17055]¡dobles![/color]" if ev["double"] else "")
		"landed":
			return "%s cae en %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"bought":
			return "%s compra %s por Bs %d" % [_pname(int(ev["player"])), _space_name(int(ev["space"])), int(ev["price"])]
		"rent_due":
			return "%s paga Bs %d de alquiler a %s" % [_pname(int(ev["player"])), int(ev["amount"]), _pname(int(ev["owner"]))]
		"tax_due":
			return "%s paga Bs %d (%s)" % [_pname(int(ev["player"])), int(ev["amount"]), _space_name(int(ev["space"]))]
		"card_drawn":
			return "%s · %s: %s" % [_pname(int(ev["player"])), "Destino" if ev["deck"] == "destino" else "Cabildo", ev["text"]]
		"jailed":
			return "%s va al [color=#e05a4a]Retén[/color]" % _pname(int(ev["player"]))
		"three_doubles":
			return "¡Tres dobles seguidos!"
		"jail_released":
			return "%s sale del Retén" % _pname(int(ev["player"]))
		"declined":
			return "%s no compra %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"auction_started":
			return "[color=#e17055]Subasta de %s[/color]" % _space_name(int(ev["space"]))
		"bid":
			return "%s puja Bs %d" % [_pname(int(ev["player"])), int(ev["amount"])]
		"bid_pass":
			return "%s se retira de la puja" % _pname(int(ev["player"]))
		"auction_ended":
			if int(ev["winner"]) < 0:
				return "Nadie compró %s" % _space_name(int(ev["space"]))
			return "%s gana %s por Bs %d" % [_pname(int(ev["winner"])), _space_name(int(ev["space"])), int(ev["amount"])]
		"built":
			return "%s construye en %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"sold_building":
			return "%s vende un edificio en %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"mortgaged":
			return "%s hipoteca %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"unmortgaged":
			return "%s levanta la hipoteca de %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"debt":
			return "[color=#e05a4a]%s debe Bs %d[/color]" % [_pname(int(ev["debtor"])), int(ev["amount"])]
		"bankrupt":
			return "[color=#e05a4a]%s quiebra[/color]" % _pname(int(ev["player"]))
		"trade_proposed":
			return "%s propone un intercambio a %s" % [_pname(int(ev["from"])), _pname(int(ev["to"]))]
		"trade_resolved":
			return "Intercambio %s" % {"accepted": "aceptado", "rejected": "rechazado", "cancelled": "cancelado", "invalid": "inválido"}.get(ev["result"], "")
		"speed_bolt":
			return "Dado turbo: %s salta a %s" % [_pname(int(ev["player"])), _space_name(int(ev["target"]))]
		"pot_collected":
			return "%s se lleva el bote de Bs %d" % [_pname(int(ev["player"])), int(ev["amount"])]
		"money":
			if ev["reason"] == "Sueldo":
				return "%s cobra Bs %d de sueldo" % [_pname(int(ev["player"])), int(ev["delta"])]
		"connection":
			return "%s %s" % [_pname(int(ev["player"])), "volvió a conectarse" if ev["connected"] else "se desconectó: la IA toma el control"]
		"game_over":
			return "[color=#e17055]Fin: gana %s[/color]" % _pname(int(ev["winner"])) if int(ev["winner"]) >= 0 else "Fin de la partida"
	return ""


# ---------------------------------------------------------------------------
# Título de propiedad de doble cara
# ---------------------------------------------------------------------------

## Color identificador de una casilla (grupo, teleférico, servicio, cartas...).
func _deed_color(i: int) -> Color:
	var b := controller.board
	var sp := b.space(i)
	match sp["type"]:
		"street":
			return b.space_color(i)
		"transit":
			return Color("#2d3e63")
		"utility":
			return Color("#c9971c")
		"card":
			return UiKit.DESTINO if sp["deck"] == "destino" else UiKit.CABILDO
		"tax":
			return UiKit.DANGER
	return UiKit.ACCENT_2


## Frente: foto del lugar y alquileres. Dorso: hipoteca, costos y estado.
## Se gira tocándola; recuerda la cara visible aunque el HUD se refresque.
func _deed(i: int) -> Control:
	var en := e()
	var b := controller.board
	var sp := b.space(i)
	var col := _deed_color(i)
	var width := minf(360.0, get_viewport_rect().size.x - 80.0)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.box(Color.WHITE, 22, 0, 0, col, 4, true))
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "Toca para girar"
	var faces := MarginContainer.new()
	card.add_child(faces)

	# --- Frente ---
	var front := UiKit.vbox(0)
	front.custom_minimum_size.x = width
	var photo := TextureRect.new()
	var tex := UiKit.place_photo(i)
	photo.texture = tex if tex else UiKit.gradient_tex(col.lightened(0.3), col.darkened(0.3))
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.custom_minimum_size = Vector2(width, 136)
	front.add_child(photo)
	front.add_child(_deed_band(String(sp["name"]).to_upper(), col, 24))
	var rows := UiKit.vbox(4)
	var pad := _pad(rows, 18, 12)
	front.add_child(pad)
	match sp["type"]:
		"street":
			var r: Array = sp["rents"]
			_row(rows, "Alquiler", "Bs %d" % r[0])
			_row(rows, "Con el grupo completo", "Bs %d" % (int(r[0]) * 2))
			for k in range(1, 5):
				_row(rows, "Con %d casa%s" % [k, "" if k == 1 else "s"], "Bs %d" % r[k])
			_row(rows, "Con hotel", "Bs %d" % r[5])
		"transit":
			for k in 4:
				_row(rows, "Con %d teleférico%s" % [k + 1, "" if k == 0 else "s"], "Bs %d" % sp["rents"][k])
		"utility":
			_row(rows, "Con 1 servicio", "%d × dados" % sp["multipliers"][0])
			_row(rows, "Con ambos", "%d × dados" % sp["multipliers"][1])
	var hint := UiKit.label("Toca la tarjeta para ver el dorso  ↻", 13, UiKit.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(hint)
	faces.add_child(front)

	# --- Dorso ---
	var back := UiKit.vbox(0)
	back.custom_minimum_size.x = width
	back.add_child(_deed_band("DORSO · " + String(sp["name"]).to_upper(), col.darkened(0.25), 18))
	var brows := UiKit.vbox(4)
	back.add_child(_pad(brows, 18, 12))
	_row(brows, "Precio de compra", "Bs %d" % b.price(i))
	_row(brows, "Valor de hipoteca", "+Bs %d" % b.mortgage_value(i))
	_row(brows, "Levantar hipoteca", "Bs %d" % en.unmortgage_cost(i))
	if sp["type"] == "street":
		_row(brows, "Cada casa cuesta", "Bs %d" % b.house_cost(i))
		_row(brows, "Hotel", "Bs %d + 4 casas" % b.house_cost(i))
		_row(brows, "Vender una casa", "+Bs %d" % (b.house_cost(i) / 2))
	brows.add_child(HSeparator.new())
	var own := en.owner_of(i)
	var state := UiKit.hbox(8)
	state.add_child(UiKit.label("Dueño", 15, UiKit.MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.add_child(spacer)
	if own >= 0:
		state.add_child(UiKit.chip(_plain(own), Color.html(en.player(own)["color"])))
	else:
		state.add_child(UiKit.chip("Libre", UiKit.GOOD))
	brows.add_child(state)
	var h := en.houses_on(i)
	var status := "Sin edificios"
	if en.is_mortgaged(i):
		status = "Hipotecada: no cobra alquiler"
	elif h == GameEngine.HOTEL:
		status = "Con hotel"
	elif h > 0:
		status = "%d casa%s" % [h, "" if h == 1 else "s"]
	_row(brows, "Estado", status)
	if own >= 0 and not en.is_mortgaged(i):
		_row(brows, "Cobra ahora", ("Bs %d" % en.rent_for(i)) if sp["type"] != "utility" else "%d × dados" % sp["multipliers"][clampi(_owned_in_group(own, i) - 1, 0, 1)])
	var note := UiKit.label("Hipotecar te da dinero al instante; para levantarla pagas el valor + 10 %.", 13, UiKit.MUTED, true)
	note.custom_minimum_size.x = width - 36
	brows.add_child(note)
	var hint2 := UiKit.label("Toca para ver el frente  ↻", 13, UiKit.MUTED)
	hint2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brows.add_child(hint2)
	faces.add_child(back)

	var show_back: bool = _deed_back.get(i, false)
	_set_face(front, back, show_back)
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
			_flip(card, front, back, i))
	return card


func _owned_in_group(pid: int, i: int) -> int:
	var n := 0
	for j in controller.board.group_members(controller.board.group_of(i)):
		if e().owner_of(j) == pid:
			n += 1
	return n


func _deed_band(text: String, col: Color, font_size: int) -> PanelContainer:
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiKit.box(col, 0, 14, 10))
	var l := UiKit.label(text, font_size, Color.WHITE if col.get_luminance() < 0.62 else UiKit.NAVY)
	l.add_theme_font_override("font", UiKit.font_black())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	band.add_child(l)
	return band


func _pad(child: Control, h: int, v: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", h)
	m.add_theme_constant_override("margin_right", h)
	m.add_theme_constant_override("margin_top", v)
	m.add_theme_constant_override("margin_bottom", v)
	m.add_child(child)
	return m


## Las dos caras ocupan el mismo lugar: la oculta queda transparente (así la tarjeta no cambia de tamaño).
func _set_face(front: Control, back: Control, show_back: bool) -> void:
	front.modulate.a = 0.0 if show_back else 1.0
	back.modulate.a = 1.0 if show_back else 0.0


func _flip(card: Control, front: Control, back: Control, i: int) -> void:
	var show_back := not bool(_deed_back.get(i, false))
	_deed_back[i] = show_back
	Sfx.play("flip")
	card.pivot_offset = card.size / 2.0
	var tw := card.create_tween()
	tw.tween_property(card, "scale:x", 0.0, 0.14).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _set_face(front, back, show_back))
	tw.tween_property(card, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Perfil de un jugador: sus terrenos
# ---------------------------------------------------------------------------

func _show_player(pid: int) -> void:
	var en := e()
	var p := en.player(pid)
	var vw := get_viewport_rect().size
	var pcol := Color.html(p["color"])
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(minf(560, vw.x - 48), 0)
	var head := UiKit.hbox(14)
	head.add_child(UiKit.token_icon(p["token"], pcol, 64))
	var col := UiKit.vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UiKit.label(Profile.label_for(p), 24, UiKit.HEADING))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	chips.add_child(UiKit.chip("Efectivo Bs %d" % int(controller.player_events.shown_cash.get(pid, p["cash"])), UiKit.GOLD))
	if not p["bankrupt"]:
		chips.add_child(UiKit.chip("Patrimonio Bs %d" % en.net_worth(pid), UiKit.ACCENT_2))
	if p["in_jail"]:
		chips.add_child(UiKit.chip("En el Retén", UiKit.CORAL))
	if p["bankrupt"]:
		chips.add_child(UiKit.chip("En quiebra", UiKit.DANGER))
	col.add_child(chips)
	head.add_child(col)
	v.add_child(head)
	var props := en.properties_of(pid)
	if props.is_empty():
		var none := UiKit.label("Todavía no tiene terrenos.", 17, UiKit.MUTED)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(none)
	else:
		var list := UiKit.vbox(8)
		for i in props:
			list.add_child(_prop_row(i))
		v.add_child(EasyScroll.wrap(list, minf(props.size() * 66.0, minf(400.0, vw.y - 300.0))))
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	if pid == controller.local_actor() and not props.is_empty() and "mortgage" in en.legal_actions(pid):
		row.add_child(UiKit.button("Gestionar", _show_manager, true))
	row.add_child(UiKit.button("Cerrar", _close_modal))
	v.add_child(row)
	_open_modal(UiKit.panel(v, UiKit.PANEL, pcol), "player", pid)


## Fila tocable de un terreno: color del grupo, nombre, edificios y lo que cobra ahora.
func _prop_row(i: int) -> Button:
	var en := e()
	var tint := _deed_color(i)
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 58)
	for st in ["normal", "hover", "pressed"]:
		var sb := UiKit.box(Color.WHITE if st == "normal" else UiKit.SOFT, 14, 0, 0, UiKit.LINE, 2)
		sb.border_width_left = 12
		sb.border_color = tint
		btn.add_theme_stylebox_override(st, sb)
	var row := UiKit.hbox(8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -12
	var name_l := UiKit.label(_space_name(i), 18, UiKit.HEADING)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	row.add_child(name_l)
	var h := en.houses_on(i)
	if h == GameEngine.HOTEL:
		row.add_child(UiKit.chip("Hotel", UiKit.DANGER))
	elif h > 0:
		row.add_child(UiKit.chip("%d casa%s" % [h, "" if h == 1 else "s"], UiKit.GOOD))
	if en.is_mortgaged(i):
		row.add_child(UiKit.chip("Hipotecada", UiKit.SOFT))
	elif controller.board.space(i)["type"] != "utility":
		row.add_child(UiKit.label("cobra Bs %d" % en.rent_for(i), 15, UiKit.MUTED))
	for c in row.get_children():
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ignore_mouse(row)
	btn.add_child(row)
	btn.pressed.connect(func():
		Sfx.play("click")
		_show_space(i))
	return btn


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_ignore_mouse(c)


# ---------------------------------------------------------------------------
# Reconexión: el anfitrión acepta o rechaza
# ---------------------------------------------------------------------------

func _on_rejoin_request(peer_id: int, seat: int) -> void:
	var p := e().player(seat)
	var v := UiKit.vbox(14)
	v.custom_minimum_size = Vector2(minf(440, get_viewport_rect().size.x - 40), 0)
	var head := UiKit.hbox(12)
	head.add_child(UiKit.token_icon(p["token"], Color.html(p["color"]), 56))
	var l := UiKit.label("%s quiere volver a la partida" % Profile.label_for(p), 21, UiKit.HEADING, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 260
	head.add_child(l)
	v.add_child(head)
	var info := UiKit.label("Si aceptas, recupera su asiento y la IA deja de jugar por él.", 15, UiKit.MUTED, true)
	info.custom_minimum_size.x = 340
	v.add_child(info)
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var dlg: Control
	row.add_child(UiKit.button("Rechazar", func():
		Net.approve_rejoin(peer_id, false)
		dlg.queue_free()))
	row.add_child(UiKit.button("Aceptar", func():
		Net.approve_rejoin(peer_id, true)
		dlg.queue_free(), true, UiKit.GOOD))
	dlg = UiKit.modal(UiKit.panel(v, UiKit.PANEL, UiKit.ACCENT_2), _overlay)
	Sfx.play("alert")


# ---------------------------------------------------------------------------
# Animaciones de juego: billetes, avisos y títulos que vuelan
# ---------------------------------------------------------------------------

## Billetes que viajan entre los perfiles (o desde/hacia el Banco) con el monto.
func _money_flow(ev: Dictionary) -> void:
	var pid := int(ev["player"])
	var delta := int(ev["delta"])
	var other := int(ev.get("other", GameEngine.BANK))
	var src := pid
	var dst := other
	if delta > 0:
		if other >= 0:
			return   # la transferencia ya se anima desde quien paga
		src = other
		dst = pid
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var a := _anchor(src)
	var b := _anchor(dst)
	if src < 0 or dst < 0:
		_bank_badge(src if src < 0 else dst, a if src < 0 else b)
	var amount := absi(delta)
	var n := clampi(1 + amount / 150, 1, 4)
	Sfx.play("bill", 0.1)
	for k in n:
		var bill := _bill("Bs %d" % amount if k == n - 1 else "Bs")
		add_child(bill)
		bill.modulate.a = 0.0
		var ctrl := (a + b) / 2.0 + Vector2(randf_range(-50.0, 50.0), -110.0 - k * 14.0)
		var tw := bill.create_tween()
		tw.tween_interval(k * 0.09)
		tw.tween_property(bill, "modulate:a", 1.0, 0.08)
		tw.parallel().tween_method(func(t: float):
			bill.global_position = _bezier(a, ctrl, b, t) - bill.size / 2.0
			bill.rotation = sin(t * TAU) * 0.3, 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(bill, "scale", Vector2(0.3, 0.3), 0.12)
		tw.parallel().tween_property(bill, "modulate:a", 0.0, 0.12)
		tw.tween_callback(bill.queue_free)
	get_tree().create_timer(0.85 + n * 0.09).timeout.connect(func(): _bump(dst))


func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


## Centro de la tarjeta del jugador, o el «Banco» en la parte superior central.
func _anchor(pid: int) -> Vector2:
	var card: Control = _player_cards.get(pid)
	if pid >= 0 and card and is_instance_valid(card) and card.is_inside_tree():
		return card.get_global_rect().get_center()
	var vw := get_viewport_rect().size
	return Vector2(vw.x * 0.5, minf(170.0, vw.y * 0.24))


func _bill(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color("#2fa36b"), 8, 12, 4, Color("#c9f2d8"), 3, true))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 16, Color.WHITE)
	l.add_theme_font_override("font", UiKit.font_black())
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color("#14583a"))
	p.add_child(l)
	return p


## Etiqueta «Banco» / «Bote» que aparece donde salen o llegan los billetes.
func _bank_badge(who: int, pos: Vector2) -> void:
	var chip := UiKit.chip("Bote" if who == GameEngine.POT else "Banco", UiKit.NAVY)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chip)
	chip.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(chip):
		return
	chip.global_position = pos - chip.size / 2.0
	var tw := chip.create_tween()
	tw.tween_property(chip, "modulate:a", 1.0, 0.12)
	tw.tween_interval(0.8)
	tw.tween_property(chip, "modulate:a", 0.0, 0.3)
	tw.tween_callback(chip.queue_free)


func _bump(pid: int) -> void:
	var card: Control = _player_cards.get(pid)
	if card == null or not is_instance_valid(card):
		return
	card.pivot_offset = card.size / 2.0
	var tw := card.create_tween()
	tw.tween_property(card, "scale", Vector2(1.08, 1.08), 0.08)
	tw.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Aviso grande que aparece en el centro, rebota y se desvanece.
func _banner(title: String, sub: String, color: Color) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(color, 26, 30, 14, Color.WHITE, 4, true))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UiKit.vbox(2)
	var fg := Color.WHITE if color.get_luminance() < 0.62 else UiKit.NAVY
	var t := UiKit.label(title, 30, fg)
	t.add_theme_font_override("font", UiKit.font_black())
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if sub != "":
		var s := UiKit.label(sub, 17, fg)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	p.add_child(v)
	add_child(p)
	var slot := _banners
	_banners += 1
	p.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(p):
		return
	var vw := get_viewport_rect().size
	p.position = Vector2((vw.x - p.size.x) / 2.0, vw.y * 0.3 - p.size.y / 2.0 + slot * (p.size.y + 10))
	p.pivot_offset = p.size / 2.0
	p.scale = Vector2(0.4, 0.4)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(p, "position:y", p.position.y - 30, 0.35)
	tw.tween_callback(func():
		_banners = maxi(0, _banners - 1)
		p.queue_free())


## Mini título de propiedad: aparece al centro, recibe un sello y vuela al perfil del dueño.
func _deed_fly(i: int, pid: int, stamp: String, stamp_color: Color) -> void:
	var col := _deed_color(i)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.box(Color.WHITE, 16, 0, 0, col, 4, true))
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UiKit.vbox(0)
	v.custom_minimum_size.x = 220
	v.add_child(_deed_band(_space_name(i).to_upper(), col, 18))
	var price := UiKit.label("Bs %d" % controller.board.price(i), 20, UiKit.HEADING)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_pad(price, 10, 8))
	var st := UiKit.label(stamp, 24, stamp_color)
	st.add_theme_font_override("font", UiKit.font_black())
	st.add_theme_constant_override("outline_size", 6)
	st.add_theme_color_override("font_outline_color", Color.WHITE)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.modulate.a = 0.0
	v.add_child(_pad(st, 10, 6))
	card.add_child(v)
	add_child(card)
	card.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	var vw := get_viewport_rect().size
	card.position = Vector2(vw.x / 2.0 - card.size.x / 2.0, vw.y * 0.55 - card.size.y / 2.0)
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(0.3, 0.3)
	card.rotation = -0.2
	st.pivot_offset = Vector2(110, 16)
	st.scale = Vector2(2.2, 2.2)
	st.rotation = -0.12
	var target := _anchor(pid) - card.size / 2.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "rotation", 0.0, 0.35)
	tw.tween_callback(func(): Sfx.play("stamp"))
	tw.tween_property(st, "modulate:a", 1.0, 0.05)
	tw.parallel().tween_property(st, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.6)
	tw.tween_property(card, "position", target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(card, "scale", Vector2(0.15, 0.15), 0.45)
	tw.parallel().tween_property(card, "modulate:a", 0.2, 0.45)
	tw.tween_callback(func():
		_bump(pid)
		card.queue_free())


## Animaciones según la acción: compras, hipotecas, subastas, tratos, Retén y quiebras.
func _animate_event(ev: Dictionary) -> void:
	match ev["type"]:
		"bought":
			_deed_fly(int(ev["space"]), int(ev["player"]), "¡COMPRADO!", UiKit.GOOD)
		"mortgaged":
			_deed_fly(int(ev["space"]), int(ev["player"]), "HIPOTECADA", UiKit.MUTED)
		"unmortgaged":
			_deed_fly(int(ev["space"]), int(ev["player"]), "LIBERADA", UiKit.ACCENT_2)
		"auction_started":
			_banner("¡Subasta!", _space_name(int(ev["space"])), UiKit.GOLD)
		"auction_ended":
			if int(ev["winner"]) >= 0:
				_deed_fly(int(ev["space"]), int(ev["winner"]), "¡VENDIDO!", UiKit.CORAL)
			else:
				_banner("Sin comprador", _space_name(int(ev["space"])), UiKit.MUTED)
		"trade_proposed":
			_banner("Nueva propuesta", "%s le ofrece un trato a %s" % [_plain(int(ev["from"])), _plain(int(ev["to"]))], UiKit.ACCENT_2)
		"trade_resolved":
			match ev["result"]:
				"accepted":
					_banner("¡Trato aceptado!", "%s y %s cerraron el negocio" % [_plain(int(ev["from"])), _plain(int(ev["to"]))], UiKit.GOOD)
				"rejected":
					_banner("Trato rechazado", "%s no aceptó la propuesta" % _plain(int(ev["to"])), UiKit.DANGER)
				"cancelled":
					_banner("Propuesta retirada", "%s retiró su oferta" % _plain(int(ev["from"])), UiKit.MUTED)
				"invalid":
					_banner("Trato inválido", "Las condiciones ya no se cumplen", UiKit.MUTED)
		"jailed":
			_banner("¡Al Retén!", _plain(int(ev["player"])), UiKit.CORAL)
		"jail_released":
			_banner("¡Libre!", "%s sale del Retén" % _plain(int(ev["player"])), UiKit.ACCENT_2)
		"three_doubles":
			_banner("¡Tres dobles!", "Directo al Retén", UiKit.DANGER)
		"built":
			if int(ev.get("houses", 0)) == GameEngine.HOTEL:
				_banner("¡Hotel!", _space_name(int(ev["space"])), UiKit.DANGER)
		"bankrupt":
			_banner("¡Quiebra!", _plain(int(ev["player"])), UiKit.DANGER)
		"pot_collected":
			_banner("¡Bote!", "%s se lleva Bs %d" % [_plain(int(ev["player"])), int(ev["amount"])], UiKit.GOLD)
		"connection":
			_banner("Conectado" if ev["connected"] else "Desconectado", _plain(int(ev["player"])), UiKit.ACCENT_2 if ev["connected"] else UiKit.MUTED)
