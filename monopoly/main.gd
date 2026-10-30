extends Node
## Raíz de la aplicación: alterna entre el menú y una partida.
##
## Argumentos de usuario (tras `--`) para pruebas visuales:
##   --demo            partida de 4 IA
##   --view=2d|3d      vista inicial
##   --shot=<ruta>     guarda una captura tras --time segundos y sale
##   --time=<seg>

var _menu_layer: CanvasLayer
var _game: Node
var _controller: GameController
var _view2d: BoardView2D
var _view3d: BoardView3D
var _hud: Hud
var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("view"):
		Profile.view_mode = _args["view"]
	if _args.has("demo"):
		_start_demo()
	elif _args.has("hud-test"):
		_hud_test(_args["hud-test"])
	elif _args.has("net-host"):
		_net_test_host()
	elif _args.has("net-join"):
		_net_test_join(_args["net-join"])
	else:
		_show_menu()
	if _args.has("shot"):
		await get_tree().create_timer(float(_args.get("time", "6"))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args["shot"])
		get_tree().quit()


func _show_menu(message: String = "") -> void:
	_end_game()
	_menu_layer = CanvasLayer.new()
	add_child(_menu_layer)
	var menu := MainMenu.new()
	_menu_layer.add_child(menu)
	menu.start_local.connect(func(seats, rules): _start_game("local", seats, rules))
	menu.start_host.connect(func(seats, rules): _start_game("host", seats, rules))
	menu.start_client.connect(func(snap): _start_game("client", [], null, snap))
	if message != "":
		menu.show_home(message)
	match _args.get("page", ""):
		"profile":
			menu.show_profile()
		"setup":
			menu.show_setup("ai")
		"wifi":
			menu.show_network("wifi")
		"modes":
			menu.show_modes()
		"rules":
			menu.show_setup("ai")
			menu._tab = 1
			menu._render_setup()


func _start_demo() -> void:
	var seats := []
	var names := ["Remedios", "Fortunato", "Wilmer", "Pochi"]
	for k in 4:
		seats.append({"uuid": "demo-%d" % k, "name": names[k], "token": ["llama", "cabina", "ekeko", "condor"][k], "color": Profile.COLORS[k], "ai": k % 3})
	var rules := RulesConfig.classic()
	rules.speed_die = true
	_start_game("local", seats, rules)
	if _args.has("cam"):
		# --cam=yaw_grados,pitch_grados,distancia,x,z  (solo para revisar la escena 3D)
		var c: PackedStringArray = _args["cam"].split(",")
		Profile.cinematic = false
		_view3d.cinematic = false
		_view3d._cam_yaw = deg_to_rad(float(c[0]))
		_view3d._cam_pitch = deg_to_rad(float(c[1]))
		_view3d._cam_dist = float(c[2])
		_view3d._cam_target = Vector3(float(c[3]), 0.3, float(c[4]))
	if _args.has("think"):
		_controller.ai_think_time = float(_args["think"])
	if _args.has("log"):
		_controller.events_emitted.connect(func(evs):
			for ev in evs:
				if ev["type"] in ["jailed", "three_doubles", "bankrupt", "game_over", "jail_released", "debt"]:
					print("LOG ronda=%d %s" % [int(_controller.engine.s["round"]), ev]))


func _start_game(kind: String, seats: Array, rules: RulesConfig, snapshot: Dictionary = {}) -> void:
	if _menu_layer:
		_menu_layer.queue_free()
		_menu_layer = null
	_game = Node.new()
	_game.name = "Game"
	add_child(_game)
	_controller = GameController.new()
	_controller.name = "Controller"
	_game.add_child(_controller)
	match kind:
		"local":
			_controller.start_local(seats, rules)
		"host":
			_controller.start_host(seats, rules)
		"client":
			_controller.start_client(snapshot)
	_view3d = BoardView3D.new()
	_view3d.add_to_group("board_view_3d")
	_game.add_child(_view3d)
	var layer2d := CanvasLayer.new()
	layer2d.layer = 0
	_game.add_child(layer2d)
	_view2d = BoardView2D.new()
	layer2d.add_child(_view2d)
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	_game.add_child(hud_layer)
	_hud = Hud.new()
	hud_layer.add_child(_hud)
	_view3d.bind(_controller)
	_view2d.bind(_controller)
	_hud.setup(_controller, _view2d, _view3d)
	_hud.view_toggle_requested.connect(_toggle_view)
	_hud.exit_requested.connect(func():
		Net.leave()
		_show_menu())
	var audio := GameAudio.new()
	_game.add_child(audio)
	audio.bind(_controller)
	Net.session_ended.connect(_on_session_ended)
	Profile.settings_changed.connect(_apply_settings)
	_apply_settings()


func _on_session_ended(reason: String) -> void:
	if _game:
		_show_menu(reason)


func _toggle_view() -> void:
	Profile.view_mode = "2d" if Profile.view_mode == "3d" else "3d"
	Profile.apply_settings()


func _apply_settings() -> void:
	if _controller == null:
		return
	_controller.player_events.speed = float(_args.get("speed", Profile.anim_speed))
	_view3d.cinematic = Profile.cinematic
	_apply_view()


func _apply_view() -> void:
	var is3d := Profile.view_mode == "3d"
	_view3d.set_active(is3d)
	_view2d.set_active(not is3d)
	_hud.set_view_label(Profile.view_mode)


## Abre paneles del HUD para un jugador humano: manager | trade | auction | space.
func _hud_test(panel: String) -> void:
	var seats := [Profile.as_seat(),
		{"uuid": "a", "name": "Wilmer", "token": "ekeko", "color": Profile.COLORS[1], "ai": 1},
		{"uuid": "b", "name": "Pochi", "token": "condor", "color": Profile.COLORS[2], "ai": 2}]
	_start_game("local", seats, RulesConfig.classic())
	var e := _controller.engine
	for i in [6, 7, 9, 12]:
		e.s["owner"][i] = 0
	for i in [1, 3, 25]:
		e.s["owner"][i] = 1
	e.s["houses"][6] = 2
	e.s["houses"][7] = 1
	e.s["houses"][9] = 1
	e.s["houses_left"] = 28
	e.s["mortgaged"][12] = true
	match panel:
		"manager":
			_hud._show_manager()
		"trade":
			_hud._show_trade_composer()
		"space":
			_hud._show_space(6)
		"buy":
			e.player(0)["pos"] = 11
			_controller.player_events.sync_from(e)
			e.s["phase"] = GameEngine.AWAIT_BUY
			e.s["pending_buy"] = 11
		"build":
			e.player(0)["cash"] = 3000
			e.s["houses"][6] = 0
			e.s["houses"][7] = 0
			e.s["houses"][9] = 0
			e.s["houses_left"] = 32
			_controller.state_changed.emit()
			await get_tree().create_timer(1.0).timeout
			for i in [6, 7, 9, 6, 7, 9]:
				_controller.submit({"type": "build", "player": 0, "space": i})
				await get_tree().create_timer(0.15).timeout
		"victory":
			e.player(1)["bankrupt"] = true
			e.player(1)["cash"] = 0
			e.player(2)["cash"] = 2350
			e._game_over("bankruptcy")
		"auction":
			e.s["current"] = 1
			e.s["phase"] = GameEngine.AUCTION
			e.s["auction"] = {"space": 39, "bidders": [0, 2], "turn": 0, "high": 120, "high_bidder": 2}
	_controller.state_changed.emit()


# ---------------------------------------------------------------------------
# Prueba de red automatizada (--net-host / --net-join=IP): el cliente juega su
# asiento con la IA enviando comandos por RPC; ambos imprimen un hash del estado.
# ---------------------------------------------------------------------------

var _autoplay_ai: AiBrain
var _autoplay_wait := 0.0


func _net_test_host() -> void:
	Profile.uuid = "test-host"
	Profile.display_name = "Anfitrion"
	var rules := RulesConfig.classic()
	if Net.host_game(EnetAdapter.new(), Profile.as_seat(), rules.to_dict(), "Prueba") != OK:
		print("NETTEST host_failed")
		get_tree().quit(1)
		return
	var waited := 0.0
	while Net.seats.size() < 2 and waited < 20.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	print("NETTEST lobby seats=%d" % Net.seats.size())
	Net.seat_connection_changed.connect(func(seat, on): print("NETTEST seat %d connected=%s" % [seat, on]))
	Net.add_ai_seat(AiBrain.Level.HARD, {"uuid": "ai-x", "name": "IA", "nick": "", "token": "condor", "color": "#1fb5b5"})
	var seats := []
	for s in Net.seats:
		var c: Dictionary = s.duplicate()
		c.erase("peer")
		seats.append(c)
	seats[0]["ai"] = AiBrain.Level.MEDIUM   # el anfitrión también juega solo
	_start_game("host", seats, rules)
	_controller.player_events.speed = 6.0
	await get_tree().create_timer(float(_args.get("time", "20"))).timeout
	print("NETTEST host turns=%d hash=%d" % [int(_controller.engine.s["turns"]), _state_hash()])
	Net.leave()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _net_test_join(address: String) -> void:
	Profile.uuid = "test-client"
	Profile.display_name = "Cliente"
	Profile.token = "charango"
	_autoplay_ai = AiBrain.new(5)
	Net.game_started.connect(func(snap):
		if _controller == null:
			_start_game("client", [], null, snap)
			_controller.player_events.speed = 6.0, CONNECT_ONE_SHOT)
	Net.session_ended.connect(func(reason):
		if _controller:
			print("NETTEST client turns=%d hash=%d reason=%s" % [int(_controller.engine.s["turns"]), _state_hash(), reason])
		get_tree().quit())
	if _args.has("drop"):
		get_tree().create_timer(float(_args["drop"])).timeout.connect(func():
			print("NETTEST client dropped turns=%d" % int(_controller.engine.s["turns"]))
			get_tree().quit())
	if Net.join_game(EnetAdapter.new(), address, Profile.as_seat()) != OK:
		print("NETTEST join_failed")
		get_tree().quit(1)


func _process(delta: float) -> void:
	if _autoplay_ai == null or _controller == null or _controller.authority:
		return
	_autoplay_wait += delta
	var pid := _controller.local_actor()
	if pid < 0 or _controller.is_busy() or _autoplay_wait < 0.3:
		return
	_autoplay_wait = 0.0
	var cmd := _autoplay_ai.decide(_controller.engine, pid, AiBrain.Level.MEDIUM)
	if not cmd.is_empty():
		_controller.submit(cmd)


func _state_hash() -> int:
	var e := _controller.engine
	return hash([e.s["players"].map(func(p): return [p["cash"], p["pos"], p["bankrupt"]]), e.s["owner"], e.s["houses"], e.s["turns"]])


func _end_game() -> void:
	if Net.session_ended.is_connected(_on_session_ended):
		Net.session_ended.disconnect(_on_session_ended)
	if Profile.settings_changed.is_connected(_apply_settings):
		Profile.settings_changed.disconnect(_apply_settings)
	if _controller:
		_controller.shutdown()
	if _game:
		_game.queue_free()
	_game = null
	_controller = null
