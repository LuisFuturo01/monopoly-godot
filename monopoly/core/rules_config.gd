class_name RulesConfig
extends RefCounted
## Opciones de reglas: modo clásico, modo rápido, dado turbo y reglas de la casa.

enum Mode { CLASSIC, QUICK }

var mode: int = Mode.CLASSIC
## Dado turbo: tercer dado con caras 1,2,3,⚡,⚡,★ (ver GameEngine._apply_speed_die).
var speed_die: bool = false
## Reglas de la casa
var free_parking_pot: bool = false
var double_salary_on_go: bool = false
var no_rent_in_jail: bool = false
## Modo rápido
var end_on_first_bankruptcy: bool = false
var houses_per_hotel: int = 4
var max_rounds: int = 0            # 0 = sin límite
## Subasta
var auction_includes_decliner: bool = true
var auction_min_increment: int = 10


static func classic() -> RulesConfig:
	return RulesConfig.new()


static func quick() -> RulesConfig:
	var r := RulesConfig.new()
	r.mode = Mode.QUICK
	r.end_on_first_bankruptcy = true
	r.houses_per_hotel = 3
	r.speed_die = true
	return r


func to_dict() -> Dictionary:
	return {
		"mode": mode,
		"speed_die": speed_die,
		"free_parking_pot": free_parking_pot,
		"double_salary_on_go": double_salary_on_go,
		"no_rent_in_jail": no_rent_in_jail,
		"end_on_first_bankruptcy": end_on_first_bankruptcy,
		"houses_per_hotel": houses_per_hotel,
		"max_rounds": max_rounds,
		"auction_includes_decliner": auction_includes_decliner,
		"auction_min_increment": auction_min_increment,
	}


static func from_dict(d: Dictionary) -> RulesConfig:
	var r := RulesConfig.new()
	for k in d.keys():
		if k in r:
			r.set(k, int(d[k]) if typeof(r.get(k)) == TYPE_INT else d[k])
	return r
