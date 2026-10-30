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
	_log.add_theme_font_size_override("normal_font_size", 15)
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
	_status = UiKit.label("", 19)
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
	_card_panel.custom_minimum_size = Vector2(420, 0)
	_card_panel.visible = false
	_card_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_panel.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: _card_panel.visible = false)
	add_child(_card_panel)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_toast = UiKit.label("", 17, Color.WHITE)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 86
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		var sb := UiKit.box(Color("#fff7d6") if cur else Color.WHITE, 20, 12, 8, pcol if cur else Color(0, 0, 0, 0), 3, true)
		sb.border_width_bottom = 6
		sb.border_color = pcol
		card.add_theme_stylebox_override("panel", sb)
		card.modulate.a = 0.45 if p["bankrupt"] else 1.0
		_player_cards[pid] = card
		var row := UiKit.hbox(8)
		card.add_child(row)
		row.add_child(UiKit.token_icon(p["token"], Color.html(p["color"]), 40))
		var col := UiKit.vbox(0)
		row.add_child(col)
		var name_l := UiKit.label(Profile.label_for(p), 15)
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
			tags.append("salvoconducto x%d" % p["jail_cards"].size())
		var cash_l := UiKit.label("$%d" % int(shown.get(pid, p["cash"])), 20, UiKit.GOOD.darkened(0.1))
		cash_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(cash_l)
		if not tags.is_empty():
			var tl := UiKit.label(" · ".join(tags), 12, UiKit.MUTED)
			tl.autowrap_mode = TextServer.AUTOWRAP_OFF
			col.add_child(tl)
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
			text = "%s puede comprar %s por $%d" % [who, _space_name(i), controller.board.price(i)]
		GameEngine.AUCTION:
			text = "Subasta de %s — puja %s" % [_space_name(int(en.s["auction"]["space"])), who]
		GameEngine.DEBT:
			var d: Dictionary = en.s["debts"][0]
			text = "%s debe $%d a %s. Hipoteca o vende para pagar." % [who, int(d["amount"]), _plain(int(d["creditor"]))]
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
				_actions.add_child(UiKit.button("Tirar dados", func(): _submit({"type": "roll", "player": local}), true))
			"pay_jail":
				_actions.add_child(UiKit.button("Pagar multa $%d" % controller.board.jail_fine, func(): _submit({"type": "pay_jail", "player": local})))
			"use_jail_card":
				_actions.add_child(UiKit.button("Usar salvoconducto", func(): _submit({"type": "use_jail_card", "player": local})))
			"buy":
				var i: int = en.s["pending_buy"]
				_actions.add_child(UiKit.button("Comprar $%d" % controller.board.price(i), func(): _submit({"type": "buy", "player": local}), true))
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
		_status.text += "  Te faltan $%d." % (int(en.s["debts"][0]["amount"]) - int(pc["cash"]))


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
	var title := UiKit.label("SUBASTA · %s" % _space_name(i), 20, UiKit.ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(title)
	v.add_child(head)
	v.add_child(UiKit.label("Precio de lista $%d" % controller.board.price(i), 15, UiKit.MUTED))
	var hb := int(a["high_bidder"])
	v.add_child(UiKit.label("Puja más alta: %s" % ("$%d de %s" % [int(a["high"]), _plain(hb)] if hb >= 0 else "ninguna"), 18))
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
	v.add_child(row)
	var base := en.min_bid()
	for extra in [0, 40, 90, 190]:
		var amount: int = base + extra
		if amount > cash:
			break
		row.add_child(UiKit.button("$%d" % amount, func(): Sfx.play("bid"); _submit({"type": "bid", "player": local, "amount": amount}), extra == 0))
	row.add_child(UiKit.button("Retirarme", func(): _submit({"type": "pass_bid", "player": local})))


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
	v.add_child(UiKit.label("Propuesta de %s para %s" % [_plain(from), _plain(to)], 19, UiKit.ACCENT))
	v.add_child(UiKit.label("%s entrega: %s" % [_plain(from), _offer_text(t["give"])], 16))
	v.add_child(UiKit.label("%s entrega: %s" % [_plain(to), _offer_text(t["get"])], 16))
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


func _offer_text(o: Dictionary) -> String:
	var parts := []
	if int(o["cash"]) > 0:
		parts.append("$%d" % int(o["cash"]))
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
	v.add_child(UiKit.label("Negociar", 24, UiKit.ACCENT))
	var target := OptionButton.new()
	for pid in others:
		target.add_item(_plain(pid), pid)
	v.add_child(target)
	var cols := UiKit.hbox(16)
	v.add_child(cols)
	var state := {"give": {}, "get": {}}
	var build_side := func(owner_pid: int, key: String, title: String) -> VBoxContainer:
		var col := UiKit.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UiKit.label(title, 18))
		var checks := []
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 220)
		var list := UiKit.vbox(4)
		sc.add_child(list)
		col.add_child(sc)
		for i in en.properties_of(owner_pid):
			var cb := CheckBox.new()
			cb.text = _space_name(i) + (" (hip.)" if en.is_mortgaged(i) else "")
			cb.disabled = en.houses_on(i) > 0
			cb.set_meta("space", i)
			list.add_child(cb)
			checks.append(cb)
		var cash := SpinBox.new()
		cash.max_value = int(en.player(owner_pid)["cash"])
		cash.step = 10
		cash.prefix = "$"
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
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", UiKit.box(b.space_color(i) if sp["type"] == "street" else UiKit.ACCENT, 16, 12, 14))
	var hl := UiKit.label(String(sp["name"]).to_upper(), 22, Color.WHITE)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(hl)
	v.add_child(head)
	match sp["type"]:
		"street":
			var r: Array = sp["rents"]
			_row(v, "Alquiler", "$%d" % r[0])
			_row(v, "Con el grupo completo", "$%d" % (int(r[0]) * 2))
			for k in range(1, 5):
				_row(v, "Con %d casa%s" % [k, "" if k == 1 else "s"], "$%d" % r[k])
			_row(v, "Con hotel", "$%d" % r[5])
			_row(v, "Cada casa cuesta", "$%d" % b.house_cost(i))
		"transit":
			for k in 4:
				_row(v, "Con %d teleférico%s" % [k + 1, "" if k == 0 else "s"], "$%d" % sp["rents"][k])
		"utility":
			_row(v, "Con 1 servicio", "%d × dados" % sp["multipliers"][0])
			_row(v, "Con ambos", "%d × dados" % sp["multipliers"][1])
		"tax":
			v.add_child(UiKit.label("Paga $%d al caer aquí." % int(sp["amount"]), 16))
		"card":
			v.add_child(UiKit.label("Roba una carta de %s." % ("Destino" if sp["deck"] == "destino" else "Cabildo"), 16))
		"go":
			v.add_child(UiKit.label("Cobra $%d cada vez que pases." % b.salary, 16))
		"jail":
			v.add_child(UiKit.label("Si solo estás de visita, no pasa nada.", 16))
		"free":
			v.add_child(UiKit.label("Descanso. Con la regla del bote, cobras lo acumulado.", 16))
		"gotojail":
			v.add_child(UiKit.label("Vas directo al Retén sin cobrar sueldo.", 16))
	if b.is_property(i):
		_row(v, "Precio", "$%d" % b.price(i))
		_row(v, "Hipoteca", "$%d" % b.mortgage_value(i))
		var own := en.owner_of(i)
		v.add_child(UiKit.label("Dueño: %s%s" % [_plain(own) if own >= 0 else "nadie", " (hipotecada)" if en.is_mortgaged(i) else ""], 16, UiKit.ACCENT))
		var me := controller.local_actor()
		if own >= 0 and own == me:
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			v.add_child(row)
			_manage_buttons(row, me, i)
	if _modal_kind == "buy_pending":
		var me2 := controller.local_actor()
		var row2 := UiKit.hbox(10)
		var buy := UiKit.button("Comprar $%d" % b.price(i), func():
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
			v.add_child(UiKit.label("No te alcanza: hipoteca algo desde «Mis propiedades» o súbastala.", 14, UiKit.DANGER))
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
	var legal := en.legal_actions(me)
	var specs := [
		["build", "+ Casa ($%d)" % controller.board.house_cost(i), en.can_build(me, i)],
		["sell_building", "− Casa", en.can_sell_building(me, i)],
		["mortgage", "Hipotecar", en.can_mortgage(me, i)],
		["unmortgage", "Levantar ($%d)" % controller.board.unmortgage_cost(i), en.can_unmortgage(me, i)],
	]
	for s in specs:
		if not controller.board.is_street(i) and s[0] in ["build", "sell_building"]:
			continue
		if s[0] == "mortgage" and en.is_mortgaged(i):
			continue
		if s[0] == "unmortgage" and not en.is_mortgaged(i):
			continue
		var b := UiKit.button(s[1], func(): _submit({"type": s[0], "player": me, "space": i}))
		b.custom_minimum_size = Vector2(0, 38)
		b.disabled = s[2] != "" or not (s[0] in legal)
		b.tooltip_text = s[2]
		row.add_child(b)


func _show_manager() -> void:
	var en := e()
	var me := controller.local_actor()
	if me < 0:
		_close_modal()
		return
	var v := UiKit.vbox(6)
	v.custom_minimum_size = Vector2(minf(640, get_viewport_rect().size.x - 40), 0)
	v.add_child(UiKit.label("Mis propiedades — efectivo $%d" % int(en.player(me)["cash"]), 22, UiKit.ACCENT))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, minf(440, get_viewport_rect().size.y - 220))
	var list := UiKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	v.add_child(sc)
	for i in en.properties_of(me):
		var row := UiKit.hbox(8)
		row.add_child(UiKit.swatch(controller.board.space_color(i), Vector2(10, 34)))
		var h := en.houses_on(i)
		var info := _space_name(i)
		if h == GameEngine.HOTEL:
			info += " · hotel"
		elif h > 0:
			info += " · %d casa%s" % [h, "" if h == 1 else "s"]
		if en.is_mortgaged(i):
			info += " · hipotecada"
		var l := UiKit.label(info, 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		_manage_buttons(row, me, i)
		list.add_child(row)
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
		if ev is InputEventMouseButton and ev.pressed and not kind in ["trade", "buy"]:
			_close_modal())


func _close_modal() -> void:
	if _modal and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_modal_kind = ""


func _confirm(msg: String, on_yes: Callable) -> void:
	var v := UiKit.vbox(12)
	v.custom_minimum_size = Vector2(380, 0)
	v.add_child(UiKit.label(msg, 19))
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
	var title := UiKit.label("¡%s gana!" % _plain(w) if w >= 0 else "Fin de la partida", 30, UiKit.ACCENT)
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
		row.add_child(UiKit.label("quiebra" if r["p"]["bankrupt"] else "$%d" % r["worth"], 18, UiKit.MUTED if r["p"]["bankrupt"] else UiKit.ACCENT))
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
	var line := _describe(ev)
	if line != "":
		_log.append_text(line + "\n")
	if ev["type"] == "card_drawn":
		_show_card(ev)


## Aviso flotante "+$200" / "−$50" bajo la tarjeta del jugador.
func _money_float(pid: int, delta: int) -> void:
	var card: Control = _player_cards.get(pid)
	if card == null:
		return
	var l := UiKit.label(("+$%d" if delta > 0 else "−$%d") % absi(delta), 22, UiKit.GOOD if delta > 0 else UiKit.DANGER)
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
	var col := Color(0.95, 0.62, 0.15) if destino else Color(0.35, 0.6, 0.85)
	_card_panel.add_theme_stylebox_override("panel", UiKit.box(Color.WHITE, 24, 24, 20, col, 5, true))
	var v := UiKit.vbox(8)
	_card_panel.add_child(v)
	var t := UiKit.label("DESTINO" if destino else "CABILDO", 22, col.darkened(0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var body := UiKit.label(ev["text"], 19, Color(0.12, 0.12, 0.14))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)
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
				s += " · turbo " + (str(d[2]) if int(d[2]) <= 3 else ("»" if int(d[2]) == GameEngine.SPEED_BOLT else "$"))
			return s + (" [color=#e17055]¡dobles![/color]" if ev["double"] else "")
		"landed":
			return "%s cae en %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"bought":
			return "%s compra %s por $%d" % [_pname(int(ev["player"])), _space_name(int(ev["space"])), int(ev["price"])]
		"rent_due":
			return "%s paga $%d de alquiler a %s" % [_pname(int(ev["player"])), int(ev["amount"]), _pname(int(ev["owner"]))]
		"tax_due":
			return "%s paga $%d (%s)" % [_pname(int(ev["player"])), int(ev["amount"]), _space_name(int(ev["space"]))]
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
			return "%s puja $%d" % [_pname(int(ev["player"])), int(ev["amount"])]
		"bid_pass":
			return "%s se retira de la puja" % _pname(int(ev["player"]))
		"auction_ended":
			if int(ev["winner"]) < 0:
				return "Nadie compró %s" % _space_name(int(ev["space"]))
			return "%s gana %s por $%d" % [_pname(int(ev["winner"])), _space_name(int(ev["space"])), int(ev["amount"])]
		"built":
			return "%s construye en %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"sold_building":
			return "%s vende un edificio en %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"mortgaged":
			return "%s hipoteca %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"unmortgaged":
			return "%s levanta la hipoteca de %s" % [_pname(int(ev["player"])), _space_name(int(ev["space"]))]
		"debt":
			return "[color=#e05a4a]%s debe $%d[/color]" % [_pname(int(ev["debtor"])), int(ev["amount"])]
		"bankrupt":
			return "[color=#e05a4a]%s quiebra[/color]" % _pname(int(ev["player"]))
		"trade_proposed":
			return "%s propone un intercambio a %s" % [_pname(int(ev["from"])), _pname(int(ev["to"]))]
		"trade_resolved":
			return "Intercambio %s" % {"accepted": "aceptado", "rejected": "rechazado", "cancelled": "cancelado", "invalid": "inválido"}.get(ev["result"], "")
		"speed_bolt":
			return "Dado turbo: %s salta a %s" % [_pname(int(ev["player"])), _space_name(int(ev["target"]))]
		"pot_collected":
			return "%s se lleva el bote de $%d" % [_pname(int(ev["player"])), int(ev["amount"])]
		"money":
			if ev["reason"] == "Sueldo":
				return "%s cobra $%d de sueldo" % [_pname(int(ev["player"])), int(ev["delta"])]
		"connection":
			return "%s %s" % [_pname(int(ev["player"])), "volvió a conectarse" if ev["connected"] else "se desconectó: la IA toma el control"]
		"game_over":
			return "[color=#e17055]Fin: gana %s[/color]" % _pname(int(ev["winner"])) if int(ev["winner"]) >= 0 else "Fin de la partida"
	return ""
