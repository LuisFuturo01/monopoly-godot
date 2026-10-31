extends Node
## Autoload "Sfx": audio 100% procedural (sin archivos).
## - Efectos: se sintetizan al arrancar en AudioStreamWAV.
## - Música: un bucle lo-fi jazz (ii-V-I-vi) se renderiza en un hilo y se transmite
##   con AudioStreamGenerator.
## - Locutor: frases generadas con una voz neuronal (Kokoro, Apache-2.0) en
##   audio/voice/<voz>/. Se dicen en cola, sin pisarse, y bajan un poco la música mientras suenan.

const RATE := 22050
const POOL_SIZE := 14
## Ganancia extra del bus de música: el bucle lo-fi es suave y al máximo se perdía.
const MUSIC_BOOST_DB := 6.0

var _sounds: Dictionary = {}
var _pool: Array = []
var _music_player: AudioStreamPlayer
var _music_playback: AudioStreamGeneratorPlayback
var _music: PackedVector2Array
var _music_pos := 0
var _thread: Thread
var _rng := RandomNumberGenerator.new()
var _mrng := RandomNumberGenerator.new()   # solo para el hilo de música
var _voice: AudioStreamPlayer
var _voice_queue: Array = []        # cada elemento: Array de claves que se dicen seguidas
var _voice_parts: Array = []        # partes que faltan de la frase en curso
var _voice_priority := 0             # prioridad de la frase que está sonando
var _voice_cache: Dictionary = {}
var _last_said := ""
var _last_said_at := 0


func _ready() -> void:
	_rng.seed = 7
	_setup_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_build_sounds()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.5
	_music_player.stream = gen
	add_child(_music_player)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	_voice.finished.connect(_next_voice)
	add_child(_voice)
	apply_volumes()
	if DisplayServer.get_name() != "headless":
		_thread = Thread.new()
		_thread.start(_render_music)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(Profile.music_volume, 0.0001)) + MUSIC_BOOST_DB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(Profile.sfx_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voice"), linear_to_db(maxf(Profile.voice_volume, 0.0001)) + 3.0)
	# Mientras habla el locutor la música baja para que se le entienda.
	var duck := -9.0 if _voice and _voice.playing else 0.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(Profile.music_volume, 0.0001)) + MUSIC_BOOST_DB + duck)


func play(sound: String, pitch_jitter: float = 0.0, volume_db: float = 0.0) -> void:
	if not _sounds.has(sound):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _sounds[sound]
			p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
			p.volume_db = volume_db
			p.play()
			return


## Dice una frase del locutor (audio/voice/<voz>/<clave>.ogg).
func say(key: String, delay: float = 0.0, priority: int = 1) -> void:
	say_parts([key], delay, priority)


## Dice varias partes seguidas como una sola frase, p. ej. ["n_camilo", "a_adv_7"]
## → «Camilo, ¡avanza siete!». Para no quedar atrasado respecto del juego:
## - una frase más importante (`priority`) corta la que suena si es menos importante;
## - solo espera una frase; la nueva reemplaza a la que esperaba.
func say_parts(parts: Array, delay: float = 0.0, priority: int = 1) -> void:
	if Profile.voice_volume <= 0.01 or not is_inside_tree() or parts.is_empty():
		return
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): say_parts(parts, 0.0, priority))
		return
	var key := "+".join(parts)
	var now := Time.get_ticks_msec()
	if key == _last_said and now - _last_said_at < 1500:
		return
	_last_said = key
	_last_said_at = now
	if _voice.playing and priority > _voice_priority:
		_voice.stop()
		_voice_parts.clear()
		_voice_queue.clear()
	# Solo espera una frase: la nueva la reemplaza salvo que la que esperaba sea más importante.
	if _voice_queue.is_empty() or priority >= int(_voice_queue[0][0]):
		_voice_queue = [[priority, parts.duplicate()]]
	if not _voice.playing:
		_next_voice()


func has_voice(key: String) -> bool:
	return _voice_stream(key) != null


func _next_voice() -> void:
	if _voice_parts.is_empty():
		if _voice_queue.is_empty():
			apply_volumes()
			return
		var item: Array = _voice_queue.pop_front()
		_voice_priority = item[0]
		_voice_parts = item[1].duplicate()
	var stream := _voice_stream(_voice_parts.pop_front())
	if stream == null:
		_next_voice()
		return
	_voice.stream = stream
	_voice.play()
	apply_volumes()


func _voice_stream(key: String) -> AudioStream:
	var path := "res://audio/voice/%s/%s.ogg" % [Profile.voice_name, key]
	if not _voice_cache.has(path):
		_voice_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _voice_cache[path]


func play_later(sound: String, delay: float, pitch_jitter: float = 0.0) -> void:
	if not is_inside_tree():
		return
	get_tree().create_timer(delay).timeout.connect(func(): play(sound, pitch_jitter))


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX", "Voice"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


# ---------------------------------------------------------------------------
# Música
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _music.is_empty():
		return
	if not _music_player.playing:
		_music_player.play()
		_music_playback = _music_player.get_stream_playback()
	if _music_playback == null:
		return
	var frames := _music_playback.get_frames_available()
	while frames > 0:
		var chunk := mini(frames, _music.size() - _music_pos)
		_music_playback.push_buffer(_music.slice(_music_pos, _music_pos + chunk))
		_music_pos = (_music_pos + chunk) % _music.size()
		frames -= chunk


func _render_music() -> void:
	var bpm := 72.0
	var beat := 60.0 / bpm
	var bars := 4
	var n := int(bars * 4 * beat * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# ii-V-I-vi en Do con extensiones jazz (MIDI).
	var chords := [[50, 53, 57, 60, 64], [43, 53, 59, 64, 69], [48, 52, 55, 59, 62], [45, 55, 60, 64, 67]]
	var bass := [[38, 45, 41, 40], [31, 38, 35, 37], [36, 43, 40, 42], [33, 40, 36, 38]]
	for bar in bars:
		var t0 := bar * 4 * beat
		var chord: Array = chords[bar]
		# Piano eléctrico: comping en 1 y en el "y" del 2 (swing).
		for hit in [0.0, 1.66]:
			for k in range(1, chord.size()):
				_add_ep(buf, t0 + hit * beat + k * 0.012, _midi(chord[k]), 1.8 if hit == 0.0 else 1.2, 0.07)
		# Bajo caminante.
		for b in 4:
			_add_bass(buf, t0 + b * beat, _midi(bass[bar][b]), beat * 0.95, 0.22)
		# Batería suave.
		for b in 4:
			if b % 2 == 0:
				_add_kick(buf, t0 + b * beat, 0.35)
			else:
				_add_noise_hit(buf, t0 + b * beat, 0.11, 0.08, 0.4)
			_add_noise_hit(buf, t0 + b * beat, 0.03, 0.025, 0.95)
			_add_noise_hit(buf, t0 + (b + 0.66) * beat, 0.03, 0.018, 0.95)
	# Crepitar de vinilo y filtro pasa-bajos para el carácter lo-fi.
	var lp := 0.0
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var x := buf[i]
		if _mrng.randf() < 0.0004:
			x += _mrng.randf_range(-0.12, 0.12)
		x += _mrng.randf_range(-0.004, 0.004)
		lp += (x - lp) * 0.32
		# Más presencia: ganancia con saturación suave (tanh) en lugar de recortar.
		var y := tanh(lp * 2.4) * 0.92
		out[i] = Vector2(y, y)
	call_deferred("_set_music", out)


func _set_music(data: PackedVector2Array) -> void:
	_music = data
	_music_pos = 0


func _midi(note: int) -> float:
	return 440.0 * pow(2.0, (note - 69) / 12.0)


func _add_ep(buf: PackedFloat32Array, t: float, f: float, dur: float, amp: float) -> void:
	var start := int(t * RATE)
	var count := mini(int(dur * RATE), buf.size() - start)
	for i in count:
		var tt := float(i) / RATE
		var env := minf(1.0, tt * 80.0) * exp(-tt * 2.2)
		var trem := 1.0 + 0.15 * sin(TAU * 4.5 * tt)
		var v := sin(TAU * f * tt) + 0.25 * sin(TAU * 2.0 * f * tt) * exp(-tt * 6.0) + 0.08 * sin(TAU * 3.0 * f * tt)
		buf[start + i] += v * env * trem * amp


func _add_bass(buf: PackedFloat32Array, t: float, f: float, dur: float, amp: float) -> void:
	var start := int(t * RATE)
	var count := mini(int(dur * RATE), buf.size() - start)
	for i in count:
		var tt := float(i) / RATE
		var env := minf(1.0, tt * 60.0) * exp(-tt * 1.6)
		buf[start + i] += (sin(TAU * f * tt) + 0.2 * sin(TAU * 2.0 * f * tt)) * env * amp


func _add_kick(buf: PackedFloat32Array, t: float, amp: float) -> void:
	var start := int(t * RATE)
	var count := mini(int(0.3 * RATE), buf.size() - start)
	var phase := 0.0
	for i in count:
		var tt := float(i) / RATE
		var f := 50.0 + 70.0 * exp(-tt * 30.0)
		phase += TAU * f / RATE
		buf[start + i] += sin(phase) * exp(-tt * 9.0) * amp


func _add_noise_hit(buf: PackedFloat32Array, t: float, dur: float, amp: float, brightness: float) -> void:
	var start := int(t * RATE)
	var count := mini(int(dur * RATE), buf.size() - start)
	var prev := 0.0
	for i in count:
		var tt := float(i) / RATE
		var w := _mrng.randf_range(-1.0, 1.0)
		var hp := w - prev * brightness
		prev = w
		buf[start + i] += hp * exp(-tt * 5.0 / dur) * amp


# ---------------------------------------------------------------------------
# Efectos
# ---------------------------------------------------------------------------

func _build_sounds() -> void:
	_sounds["dice_roll"] = _wav(_dice_roll())
	_sounds["dice_stop"] = _wav(_thud(0.25, 95.0, 0.9))
	_sounds["step"] = _wav(_tock())
	_sounds["cash"] = _wav(_cash())
	_sounds["coin"] = _wav(_coin())
	_sounds["alert"] = _wav(_alert())
	_sounds["jail"] = _wav(_jail())
	_sounds["buy"] = _wav(_arpeggio([72, 76, 79, 84], 0.09, 0.35))
	_sounds["build"] = _wav(_build_sound())
	_sounds["card"] = _wav(_swish())
	_sounds["click"] = _wav(_tone(1200.0, 0.04, 0.25, 60.0))
	_sounds["bid"] = _wav(_tone(880.0, 0.08, 0.3, 30.0))
	_sounds["turn"] = _wav(_arpeggio([79, 84], 0.06, 0.2))
	_sounds["win"] = _wav(_arpeggio([60, 64, 67, 72, 76, 79, 84], 0.11, 0.35))
	_sounds["lose"] = _wav(_arpeggio([67, 63, 60, 55], 0.18, 0.3))
	_sounds["bill"] = _wav(_paper(0.14, 0.35))
	_sounds["stamp"] = _wav(_stamp())
	_sounds["flip"] = _wav(_flip())
	_sounds["trade_ok"] = _wav(_mix(_arpeggio([67, 71, 74, 79, 83], 0.07, 0.4), _cash(), 0.3))
	_sounds["trade_no"] = _wav(_buzzer())
	_sounds["hammer"] = _wav(_gavel())
	_sounds["pass"] = _wav(_arpeggio([64, 59], 0.08, 0.22))
	_sounds["mortgage"] = _wav(_mix(_paper(0.25, 0.3), _tone(220.0, 0.6, 0.3, 6.0), 0.0))
	_sounds["sell"] = _wav(_mix(_coin(), _coin(), 0.1))
	_sounds["doubles"] = _wav(_arpeggio([84, 88, 91, 96], 0.05, 0.25))
	_sounds["whoosh"] = _wav(_swish())


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _buffer(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


func _tone(f: float, dur: float, amp: float, decay: float) -> PackedFloat32Array:
	var b := _buffer(dur)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * f * t) * exp(-t * decay) * amp
	return b


func _dice_roll() -> PackedFloat32Array:
	var b := _buffer(0.9)
	var t := 0.0
	var amp := 0.6
	while t < 0.8:
		var start := int(t * RATE)
		var f := _rng.randf_range(1800.0, 3200.0)
		for i in mini(int(0.025 * RATE), b.size() - start):
			var tt := float(i) / RATE
			b[start + i] += (_rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * f * tt) * 0.4) * exp(-tt * 180.0) * amp
		t += _rng.randf_range(0.04, 0.11)
		amp *= 0.9
	return b


func _thud(dur: float, f0: float, amp: float) -> PackedFloat32Array:
	var b := _buffer(dur)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += TAU * (f0 * (0.6 + 0.4 * exp(-t * 25.0))) / RATE
		b[i] = (sin(phase) * exp(-t * 18.0) + _rng.randf_range(-1.0, 1.0) * exp(-t * 120.0) * 0.4) * amp
	return b


func _tock() -> PackedFloat32Array:
	var b := _buffer(0.09)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 720.0 * t) * 0.6 + sin(TAU * 1460.0 * t) * 0.25) * exp(-t * 70.0) * 0.5
	return b


func _coin() -> PackedFloat32Array:
	var b := _buffer(0.35)
	for i in b.size():
		var t := float(i) / RATE
		var v := sin(TAU * 2093.0 * t) + 0.6 * sin(TAU * 2637.0 * t) + 0.4 * sin(TAU * 3520.0 * t * 1.003)
		b[i] = v * exp(-t * 12.0) * 0.18
	return b


func _cash() -> PackedFloat32Array:
	var b := _buffer(0.9)
	# "Ka-ching": golpe mecánico + campana + monedas.
	for i in int(0.04 * RATE):
		b[i] += _rng.randf_range(-1.0, 1.0) * exp(-float(i) / RATE * 90.0) * 0.4
	for k in 3:
		var start := int((0.08 + k * 0.07) * RATE)
		var f := 2000.0 + k * 410.0
		for i in mini(int(0.5 * RATE), b.size() - start):
			var t := float(i) / RATE
			b[start + i] += (sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.51 * t)) * exp(-t * 9.0) * 0.12
	var start2 := int(0.06 * RATE)
	for i in b.size() - start2:
		var t := float(i) / RATE
		b[start2 + i] += (sin(TAU * 1568.0 * t) + 0.7 * sin(TAU * 2093.0 * t)) * exp(-t * 4.0) * 0.16
	return b


func _alert() -> PackedFloat32Array:
	var b := _buffer(1.0)
	var notes := [_midi(46), _midi(49), _midi(52), _midi(58)]   # acorde disminuido, dramático
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for f in notes:
			for h in range(1, 5):
				v += sin(TAU * f * h * t) / h
		b[i] = v * minf(1.0, t * 60.0) * exp(-t * 3.0) * 0.07
	return b


func _jail() -> PackedFloat32Array:
	var b := _buffer(1.2)
	var partials := [[220.0, 1.0], [563.0, 0.7], [891.0, 0.5], [1250.0, 0.35], [1710.0, 0.2]]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * p[0] * t) * p[1]
		b[i] = v * exp(-t * 3.5) * 0.12
	# Portazo: golpe grave con ruido.
	var slam := _thud(0.4, 70.0, 0.8)
	for i in slam.size():
		b[i] += slam[i]
	return b


func _swish() -> PackedFloat32Array:
	var b := _buffer(0.35)
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var w := _rng.randf_range(-1.0, 1.0)
		var hp := w - prev * 0.9
		prev = w
		b[i] = hp * sin(PI * t / 0.35) * 0.25
	return b


## Suma `b` a `a` empezando `offset` segundos después.
func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset: float) -> PackedFloat32Array:
	var start := int(offset * RATE)
	var out := a.duplicate()
	if out.size() < start + b.size():
		out.resize(start + b.size())
	for i in b.size():
		out[start + i] += b[i]
	return out


## Billete o papel: ráfaga de ruido filtrado que se desliza.
func _paper(dur: float, amp: float) -> PackedFloat32Array:
	var b := _buffer(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var w := _rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * (0.5 - 0.35 * t / dur)
		b[i] = (w - lp) * sin(PI * t / dur) * amp
	return b


## Sello sobre el título: golpe grave seco con chasquido de papel.
func _stamp() -> PackedFloat32Array:
	return _mix(_thud(0.3, 80.0, 0.9), _paper(0.06, 0.4), 0.0)


## Tarjeta que gira: barrido corto ascendente.
func _flip() -> PackedFloat32Array:
	var b := _buffer(0.16)
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var w := _rng.randf_range(-1.0, 1.0)
		var hp := w - prev * (0.6 + t * 2.0)
		prev = w
		b[i] = hp * sin(PI * t / 0.16) * 0.22
	return b


## Trato rechazado: dos notas graves descendentes con timbre áspero.
func _buzzer() -> PackedFloat32Array:
	var b := _buffer(0.6)
	for k in 2:
		var f := _midi(55 - k * 4)
		var start := int(k * 0.22 * RATE)
		for i in mini(int(0.25 * RATE), b.size() - start):
			var t := float(i) / RATE
			var v := sin(TAU * f * t) + 0.5 * sin(TAU * f * 3.0 * t) + 0.3 * sin(TAU * f * 5.0 * t)
			b[start + i] += v * minf(1.0, t * 100.0) * exp(-t * 6.0) * 0.16
	return b


## Martillo de subasta: dos golpes de madera.
func _gavel() -> PackedFloat32Array:
	var knock := _buffer(0.15)
	for i in knock.size():
		var t := float(i) / RATE
		knock[i] = (sin(TAU * 380.0 * t) * 0.7 + sin(TAU * 910.0 * t) * 0.3 + _rng.randf_range(-1.0, 1.0) * exp(-t * 200.0)) * exp(-t * 38.0) * 0.6
	return _mix(_mix(knock, knock, 0.18), _arpeggio([72, 79], 0.06, 0.2), 0.32)


## Obra: tres martillazos y una campanita al terminar.
func _build_sound() -> PackedFloat32Array:
	var tap := _buffer(0.08)
	for i in tap.size():
		var t := float(i) / RATE
		tap[i] = (sin(TAU * 1300.0 * t) * 0.5 + _rng.randf_range(-1.0, 1.0) * 0.5) * exp(-t * 70.0) * 0.4
	var out := _mix(_mix(tap, tap, 0.12), tap, 0.24)
	return _mix(out, _arpeggio([72, 76, 79], 0.06, 0.3), 0.38)


func _arpeggio(notes: Array, step: float, amp: float) -> PackedFloat32Array:
	var b := _buffer(step * notes.size() + 0.5)
	for k in notes.size():
		var f := _midi(notes[k])
		var start := int(k * step * RATE)
		for i in b.size() - start:
			var t := float(i) / RATE
			b[start + i] += (sin(TAU * f * t) + 0.3 * sin(TAU * 2.0 * f * t)) * minf(1.0, t * 200.0) * exp(-t * 5.0) * amp / 2.0
	return b
