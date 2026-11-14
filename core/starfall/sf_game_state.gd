extends RefCounted
const SFData := preload("res://core/starfall/sf_data.gd")
## Persistent run state for Operation: Starfall. Pure data and rules: the
## screens read it, never the other way around.

const SECTOR_IDS := ["s1", "s2", "s3"]

var balance: Dictionary = {}
var debris_types: Dictionary = {}
var sectors: Array = []
var upgrade_defs: Array = []
var logs: Dictionary = {}
var pa: Dictionary = {}
var endings: Dictionary = {}

var budget: float = 0.0
var upgrade_levels: Dictionary = {}
var sector_state: Dictionary = {}
var unlocked: int = 1
var specimen_secured: bool = false
var found_logs: Array = []
var ending: String = ""
var sorties: int = 0
var total_banked: float = 0.0
var total_mass: float = 0.0


func _init() -> void:
	balance = SFData.read_json("balance.json") as Dictionary
	debris_types = SFData.read_json("debris.json") as Dictionary
	sectors = SFData.read_json("sectors.json") as Array
	upgrade_defs = SFData.read_json("upgrades.json") as Array
	logs = SFData.read_json("logs.json") as Dictionary
	pa = SFData.read_json("pa.json") as Dictionary
	endings = SFData.read_json("endings.json") as Dictionary
	reset()


func reset() -> void:
	var base: Dictionary = balance.get("base", {}) as Dictionary
	budget = float(base.get("start_budget", 110.0))
	upgrade_levels = {"cargo": 0, "thruster": 0, "magnet": 0, "cell": 0}
	sector_state = {}
	for s in sectors:
		var sec: Dictionary = s as Dictionary
		sector_state[String(sec.get("id", ""))] = {"banked": 0.0, "cleared": false, "runs": 0}
	unlocked = 1
	specimen_secured = false
	found_logs = []
	ending = ""
	sorties = 0
	total_banked = 0.0
	total_mass = 0.0


# ---------------------------------------------------------------- ship stats

func ship_stats() -> Dictionary:
	var base: Dictionary = balance.get("base", {}) as Dictionary
	var storage: float = float(base.get("storage", 40.0))
	var fuel_burn: float = float(base.get("fuel_burn", 1.85))
	var beam_radius: float = float(base.get("beam_radius", 58.0))
	var power: float = float(base.get("power", 100.0))
	for d in upgrade_defs:
		var def: Dictionary = d as Dictionary
		var id := String(def.get("id", ""))
		var lvl: int = int(upgrade_levels.get(id, 0))
		var values: Array = def.get("values", []) as Array
		if lvl <= 0 or values.is_empty():
			continue
		var v: float = float(values[mini(lvl, values.size()) - 1])
		match String(def.get("stat", "")):
			"storage":
				storage = v
			"fuel_burn_mult":
				fuel_burn *= v
			"beam_radius":
				beam_radius = v
			"power":
				power = v
	var out := {
		"fuel": float(base.get("fuel", 100.0)),
		"power": power,
		"storage": storage,
		"beam_radius": beam_radius,
		"dry_mass": float(base.get("dry_mass", 18.0)),
		"accel": float(base.get("accel", 265.0)),
		"max_speed": float(base.get("max_speed", 300.0)),
		"drag": float(base.get("drag", 0.15)),
		"fuel_burn": fuel_burn,
		"beam_drain": float(base.get("beam_drain", 4.2)),
		"passive_power": float(base.get("passive_power", 0.22)),
		"pickup_radius": float(base.get("pickup_radius", 14.0)),
		"beam_pull": float(base.get("beam_pull", 560.0)),
		"mass_factor": float(balance.get("mass_factor", 46.0)),
		"impact_power_loss": float(balance.get("impact_power_loss", 4.0)),
		"impact_speed": float(balance.get("impact_speed", 95.0)),
	}
	return out


func upgrade_cost(index: int) -> int:
	if index < 0 or index >= upgrade_defs.size():
		return -1
	var def: Dictionary = upgrade_defs[index] as Dictionary
	var id := String(def.get("id", ""))
	var lvl: int = int(upgrade_levels.get(id, 0))
	var costs: Array = def.get("costs", []) as Array
	if lvl >= costs.size():
		return -1
	return int(costs[lvl])


func can_upgrade(index: int) -> bool:
	var cost := upgrade_cost(index)
	return cost > 0 and budget >= float(cost)


func buy_upgrade(index: int) -> bool:
	if not can_upgrade(index):
		return false
	var def: Dictionary = upgrade_defs[index] as Dictionary
	var id := String(def.get("id", ""))
	budget -= float(upgrade_cost(index))
	upgrade_levels[id] = int(upgrade_levels.get(id, 0)) + 1
	return true


func upgrade_level(index: int) -> int:
	if index < 0 or index >= upgrade_defs.size():
		return 0
	var def: Dictionary = upgrade_defs[index] as Dictionary
	return int(upgrade_levels.get(String(def.get("id", "")), 0))


# ---------------------------------------------------------------- sectors

func sector(index: int) -> Dictionary:
	if index < 0 or index >= sectors.size():
		return {}
	return sectors[index] as Dictionary


func is_unlocked(index: int) -> bool:
	return index < unlocked


func is_cleared(index: int) -> bool:
	var s := sector(index)
	if s.is_empty():
		return false
	var st: Dictionary = sector_state.get(String(s.get("id", "")), {}) as Dictionary
	return bool(st.get("cleared", false))


func sector_banked(index: int) -> float:
	var s := sector(index)
	if s.is_empty():
		return 0.0
	var st: Dictionary = sector_state.get(String(s.get("id", "")), {}) as Dictionary
	return float(st.get("banked", 0.0))


func sector_quota(index: int) -> float:
	var s := sector(index)
	return float(s.get("quota", 100.0))


func quota_progress(index: int) -> float:
	var q := sector_quota(index)
	if q <= 0.0:
		return 1.0
	return clampf(sector_banked(index) / q, 0.0, 1.0)


## Bank a completed sortie. Returns the report dictionary for the screen.
func bank_sortie(index: int, value: float, mass: float, collected: int, specimen: bool) -> Dictionary:
	var s := sector(index)
	var id := String(s.get("id", ""))
	var st: Dictionary = sector_state.get(id, {"banked": 0.0, "cleared": false, "runs": 0}) as Dictionary
	var was_cleared := bool(st.get("cleared", false))
	var quota := float(s.get("quota", 0.0))
	var bonus := 0.0
	st["banked"] = float(st.get("banked", 0.0)) + value
	st["runs"] = int(st.get("runs", 0)) + 1
	var now_cleared: bool = float(st["banked"]) >= quota
	if now_cleared and not was_cleared:
		bonus = float(s.get("bonus", 0.0))
		st["cleared"] = true
		if unlocked < index + 2:
			unlocked = mini(sectors.size(), index + 2)
	sector_state[id] = st
	budget += value + bonus
	total_banked += value + bonus
	total_mass += mass
	sorties += 1
	if specimen:
		specimen_secured = true
	return {
		"value": value,
		"bonus": bonus,
		"cleared_now": now_cleared,
		"cleared_before": was_cleared,
		"banked": float(st["banked"]),
		"quota": quota,
		"collected": collected,
		"mass": mass,
		"budget": budget,
	}


func add_log(log_id: String) -> bool:
	if log_id == "" or found_logs.has(log_id) or not logs.has(log_id):
		return false
	found_logs.append(log_id)
	return true


func log_count() -> int:
	return found_logs.size()


func all_sectors_cleared() -> bool:
	for i in sectors.size():
		if not is_cleared(i):
			return false
	return true


func finale_available() -> bool:
	return all_sectors_cleared()


func endings_available() -> Array:
	var out: Array = []
	out.append("plastic_snow")
	out.append("endless_loop")
	if specimen_secured:
		out.append("last_specimen")
	return out
