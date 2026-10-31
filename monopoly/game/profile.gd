extends Node
## Autoload "Profile": identidad local del jugador (sin autenticación) y ajustes.
## El UUID se genera una vez por dispositivo y sirve para reconectar a partidas en red.

signal settings_changed

const PATH := "user://profile.cfg"
const MAX_NAME_WORDS := 2
const MAX_NAME_CHARS := 20
const MAX_NICK_CHARS := 12
const COLORS := ["#e04848", "#3d7be0", "#3fb36b", "#f0b429", "#9b59d0", "#ef7d3c", "#1fb5b5", "#e05aa8"]
const TOKEN_NAMES := {
	"llama": "Llama", "charango": "Charango", "cabina": "Cabina", "bombin": "Bombín",
	"ekeko": "Ekeko", "zampona": "Zampoña", "condor": "Cóndor", "trompo": "Trompo",
}

var uuid := ""
var display_name := "Jugador"
var nick := ""
var token := "llama"
var color := COLORS[0]
var view_mode := "3d"          # "3d" | "2d"
var music_volume := 0.5
var sfx_volume := 0.8
var voice_volume := 0.9        # locutor (0 = sin voz)
var voice_name := "ef_dora"    # carpeta en audio/voice/: ef_dora (Dora) o em_alex (Alex)
var last_host := ""
var anim_speed := 1.0          # 0.75 relajado, 1 normal, 1.6 rápido
var cinematic := true
var show_log := false
var rules: Dictionary = {}


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		uuid = cfg.get_value("profile", "uuid", "")
		display_name = cfg.get_value("profile", "name", display_name)
		nick = cfg.get_value("profile", "nick", nick)
		token = cfg.get_value("profile", "token", token)
		color = cfg.get_value("profile", "color", color)
		view_mode = cfg.get_value("settings", "view_mode", view_mode)
		music_volume = cfg.get_value("settings", "music_volume", music_volume)
		sfx_volume = cfg.get_value("settings", "sfx_volume", sfx_volume)
		voice_volume = cfg.get_value("settings", "voice_volume", voice_volume)
		voice_name = cfg.get_value("settings", "voice_name", voice_name)
		last_host = cfg.get_value("settings", "last_host", last_host)
		anim_speed = cfg.get_value("settings", "anim_speed", anim_speed)
		cinematic = cfg.get_value("settings", "cinematic", cinematic)
		show_log = cfg.get_value("settings", "show_log", show_log)
		rules = cfg.get_value("settings", "rules", rules)
		display_name = clean_name(display_name)
		nick = clean_nick(nick)
	if uuid == "":
		uuid = _new_uuid()
		save_profile()


func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "uuid", uuid)
	cfg.set_value("profile", "name", display_name)
	cfg.set_value("profile", "nick", nick)
	cfg.set_value("profile", "token", token)
	cfg.set_value("profile", "color", color)
	cfg.set_value("settings", "view_mode", view_mode)
	cfg.set_value("settings", "music_volume", music_volume)
	cfg.set_value("settings", "sfx_volume", sfx_volume)
	cfg.set_value("settings", "voice_volume", voice_volume)
	cfg.set_value("settings", "voice_name", voice_name)
	cfg.set_value("settings", "last_host", last_host)
	cfg.set_value("settings", "anim_speed", anim_speed)
	cfg.set_value("settings", "cinematic", cinematic)
	cfg.set_value("settings", "show_log", show_log)
	cfg.set_value("settings", "rules", rules)
	cfg.save(PATH)


## Guarda y avisa a quien aplique los ajustes (vista, cámara, velocidad).
func apply_settings() -> void:
	save_profile()
	settings_changed.emit()


func as_seat() -> Dictionary:
	return {"uuid": uuid, "name": display_name, "nick": nick, "token": token, "color": color, "ai": -1}


## Nombre de hasta dos palabras (cabe en las tarjetas y el locutor lo dice rápido).
static func clean_name(s: String) -> String:
	var words := s.strip_edges().split(" ", false)
	var out := " ".join(words.slice(0, MAX_NAME_WORDS)).left(MAX_NAME_CHARS).strip_edges()
	return out if out != "" else "Jugador"


## Apodo de una sola palabra.
static func clean_nick(s: String) -> String:
	var words := s.strip_edges().split(" ", false)
	return words[0].left(MAX_NICK_CHARS) if not words.is_empty() else ""


static func label_for(p: Dictionary) -> String:
	var nk: String = p.get("nick", "")
	return p["name"] if nk == "" else "%s «%s»" % [p["name"], nk]


func _new_uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hex := ""
	for i in 16:
		hex += "%02x" % rng.randi_range(0, 255)
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
