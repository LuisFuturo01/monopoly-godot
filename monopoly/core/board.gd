class_name Board
extends RefCounted
## Definición estática del tablero (datos, sin estado de partida).
## Se carga desde JSON para que el diseño del tablero sea editable sin tocar código.

const PROPERTY_TYPES := ["street", "transit", "utility"]

var name: String = ""
var salary: int = 200
var start_cash: int = 1500
var jail_fine: int = 50
var houses_total: int = 32
var hotels_total: int = 12
var spaces: Array = []        # Array[Dictionary]
var groups: Dictionary = {}   # group -> {color, house}
var decks: Dictionary = {}    # deck -> Array[Dictionary]
var tokens: Array = []
var jail_index: int = 10

var _group_members: Dictionary = {}


static func load_from_file(path: String) -> Board:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "No se pudo abrir el tablero: %s" % path)
	var data = JSON.parse_string(f.get_as_text())
	var b := Board.new()
	b._load(data)
	return b


func _load(data: Dictionary) -> void:
	name = data.get("name", "")
	salary = int(data.get("salary", 200))
	start_cash = int(data.get("start_cash", 1500))
	jail_fine = int(data.get("jail_fine", 50))
	houses_total = int(data.get("houses_total", 32))
	hotels_total = int(data.get("hotels_total", 12))
	spaces = data["spaces"]
	groups = data.get("groups", {})
	decks = data.get("decks", {})
	tokens = data.get("tokens", [])
	for i in spaces.size():
		var sp: Dictionary = spaces[i]
		sp["index"] = i
		if sp["type"] == "jail":
			jail_index = i
		if sp.has("group"):
			if not _group_members.has(sp["group"]):
				_group_members[sp["group"]] = []
			_group_members[sp["group"]].append(i)


func size() -> int:
	return spaces.size()


func space(i: int) -> Dictionary:
	return spaces[i]


func is_property(i: int) -> bool:
	return spaces[i]["type"] in PROPERTY_TYPES


func is_street(i: int) -> bool:
	return spaces[i]["type"] == "street"


func group_of(i: int) -> String:
	return spaces[i].get("group", "")


func group_members(group: String) -> Array:
	return _group_members.get(group, [])


func price(i: int) -> int:
	return int(spaces[i].get("price", 0))


func mortgage_value(i: int) -> int:
	return price(i) / 2


func unmortgage_cost(i: int) -> int:
	return int(ceil(mortgage_value(i) * 1.1))


func house_cost(i: int) -> int:
	return int(spaces[i].get("house_cost", 0))


func group_color(group: String) -> Color:
	if groups.has(group):
		return Color.html(groups[group]["color"])
	return Color(0.85, 0.85, 0.85)


func space_color(i: int) -> Color:
	return group_color(group_of(i))


func property_indices() -> Array:
	var out := []
	for i in spaces.size():
		if is_property(i):
			out.append(i)
	return out
