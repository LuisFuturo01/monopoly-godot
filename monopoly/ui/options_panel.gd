class_name OptionsPanel
extends RefCounted
## Panel de opciones compartido por el menú principal y la partida.
## Cada cambio se guarda al instante (sin botón "Aplicar") y se notifica con Profile.settings_changed.


static func build(on_close: Callable) -> Control:
	var v := UiKit.vbox(14)
	v.custom_minimum_size = Vector2(460, 0)
	var title := UiKit.label("Opciones", 30, UiKit.HEADING)
	v.add_child(title)

	v.add_child(_section("Sonido"))
	v.add_child(_slider("Música", "music_volume", func(): Sfx.apply_volumes()))
	v.add_child(_slider("Efectos", "sfx_volume", func():
		Sfx.apply_volumes()
		Sfx.play("coin")))
	v.add_child(_slider("Locutor", "voice_volume", func():
		Sfx.apply_volumes()
		Sfx.say("dice_7")))
	var voices := ["ef_dora", "em_alex"]
	v.add_child(_segmented(["Voz de Dora", "Voz de Alex"], maxi(0, voices.find(Profile.voice_name)), func(i):
		Profile.voice_name = voices[i]
		Sfx.say("bought_29")))

	v.add_child(_section("Tablero"))
	v.add_child(_segmented(["Vista 3D", "Vista 2D"], 0 if Profile.view_mode == "3d" else 1, func(i):
		Profile.view_mode = "3d" if i == 0 else "2d"))
	v.add_child(_segmented(["Relajado", "Normal", "Rápido"], [0.75, 1.0, 1.6].find(Profile.anim_speed) if Profile.anim_speed in [0.75, 1.0, 1.6] else 1, func(i):
		Profile.anim_speed = [0.75, 1.0, 1.6][i]))
	v.add_child(_toggle("La cámara sigue a la ficha (3D)", "cinematic"))
	v.add_child(_toggle("Mostrar registro de jugadas", "show_log"))

	v.add_child(UiKit.button("Listo", on_close, true))
	return UiKit.panel(v)


static func _section(text: String) -> Label:
	return UiKit.label(text.to_upper(), 14, UiKit.MUTED)


static func _slider(text: String, prop: String, after: Callable) -> Control:
	var row := UiKit.hbox(12)
	var l := UiKit.label(text, 18)
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = Profile.get(prop)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.drag_ended.connect(func(_changed): after.call())
	s.value_changed.connect(func(val):
		Profile.set(prop, val)
		Profile.apply_settings())
	row.add_child(s)
	return row


static func _toggle(text: String, prop: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = Profile.get(prop)
	c.toggled.connect(func(on):
		Profile.set(prop, on)
		Profile.apply_settings())
	return c


## Selector de opciones excluyentes como píldoras.
static func _segmented(options: Array, selected: int, on_pick: Callable) -> Control:
	var row := UiKit.hbox(8)
	var buttons := []
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("pressed", UiKit.box(UiKit.ACCENT, 24, 16, 8))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		b.add_theme_stylebox_override("hover_pressed", UiKit.box(UiKit.ACCENT.lightened(0.1), 24, 16, 8))
		b.button_pressed = i == selected
		buttons.append(b)
		row.add_child(b)
	for i in buttons.size():
		buttons[i].pressed.connect(func():
			for j in buttons.size():
				buttons[j].button_pressed = j == i
			Sfx.play("click")
			on_pick.call(i)
			Profile.apply_settings())
	return row
