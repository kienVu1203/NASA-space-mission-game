extends RefCounted
## A spacecraft design and its preflight validation. Pure logic: no nodes, no
## UI, no signals. The construction screen owns one of these, mutates it, and
## renders the summary this class computes.
##
## Units used here and in data/star_fall/ship_parts.json:
##   mass         kg      (structural mass and propellant mass are separate)
##   fuel         kg      (rocket propellant, NOT electrical energy)
##   power        W       (instantaneous electrical demand and supply)
##   energy       Wh      (stored electrical energy)
##   cost         credits (fictional construction credits)
##   data         MB      (recorded science data, not propellant)

const SLOTS := ["computer", "propulsion", "power", "communications", "sensor"]
const FUEL_STEP_KG := 20.0


var slots: Dictionary = {}   # slot id -> component id ("" when empty)
var fuel_kg: float = 0.0


func _init() -> void:
	clear()


func clear() -> void:
	slots = {}
	for s in SLOTS:
		slots[String(s)] = ""
	fuel_kg = 0.0


func set_slot(slot: String, component_id: String) -> void:
	if not SLOTS.has(slot):
		return
	slots[slot] = component_id


func clear_slot(slot: String) -> void:
	if SLOTS.has(slot):
		slots[slot] = ""


func slot_component(slot: String) -> String:
	return String(slots.get(slot, ""))


func set_fuel(value: float, content) -> void:
	var cap := float(content.hull.get("fuel_capacity_kg", 0.0))
	fuel_kg = clampf(round(value / FUEL_STEP_KG) * FUEL_STEP_KG, 0.0, cap)


func adjust_fuel(steps: int, content) -> void:
	set_fuel(fuel_kg + float(steps) * FUEL_STEP_KG, content)


func is_empty() -> bool:
	for s in SLOTS:
		if slot_component(String(s)) != "":
			return false
	return fuel_kg <= 0.0


# ---------------------------------------------------------------- totals

## Every derived number the UI needs, in one pure pass.
func summary(content) -> Dictionary:
	var hull: Dictionary = content.hull
	var dry_mass := float(hull.get("mass_kg", 0.0))
	var cost := float(hull.get("cost", 0.0))
	var demand: float = 0.0
	var output: float = 0.0
	var energy: float = 0.0
	var sensor_quality: int = 0
	var data_capture: float = 0.0
	var lift_capacity: float = 0.0
	var filled: int = 0
	var sensor_id: String = ""

	for s in SLOTS:
		var id := slot_component(String(s))
		if id == "":
			continue
		var comp: Dictionary = content.component(id)
		if comp.is_empty():
			continue
		filled += 1
		dry_mass += float(comp.get("mass_kg", 0.0))
		cost += float(comp.get("cost", 0.0))
		demand += float(comp.get("power_demand_w", 0.0))
		output += float(comp.get("power_output_w", 0.0))
		energy += float(comp.get("energy_storage_wh", 0.0))
		if String(comp.get("slot", "")) == "sensor":
			sensor_id = id
			sensor_quality = maxi(sensor_quality, int(comp.get("sensor_quality", 0)))
			data_capture += float(comp.get("data_gain_mb", 0.0))
		if String(comp.get("slot", "")) == "propulsion":
			lift_capacity = float(comp.get("thrust_capacity_kg", 0.0))

	var wet_mass := dry_mass + fuel_kg
	var hull_limit := float(hull.get("launch_mass_limit_kg", 0.0))
	var limit_kg := hull_limit
	if lift_capacity > 0.0:
		limit_kg = minf(hull_limit, lift_capacity) if hull_limit > 0.0 else lift_capacity

	var req: Dictionary = content.requirements
	var observation_hours := float(req.get("observation_hours", 2.0))
	var min_energy := float(req.get("minimum_stored_energy_wh", 0.0))
	var energy_required := maxf(min_energy, observation_hours * demand)

	return {
		"dry_mass_kg": dry_mass,
		"fuel_kg": fuel_kg,
		"wet_mass_kg": wet_mass,
		"cost": cost,
		"power_demand_w": demand,
		"power_output_w": output,
		"energy_stored_wh": energy,
		"energy_required_wh": energy_required,
		"sensor_quality": sensor_quality,
		"sensor_id": sensor_id,
		"data_capture_mb": data_capture,
		"data_capacity_mb": float(hull.get("data_capacity_mb", 0.0)),
		"lift_capacity_kg": lift_capacity,
		"hull_mass_limit_kg": hull_limit,
		"mass_limit_kg": limit_kg,
		"slots_filled": filled,
		"slots_total": SLOTS.size(),
		"fuel_capacity_kg": float(hull.get("fuel_capacity_kg", 0.0)),
	}


# ---------------------------------------------------------------- validation

## Returns one entry per check:
##   {"id": String, "ok": bool, "blocking": bool, "message": String, "hint": String}
## A design is launchable only when every blocking check is ok. Changing the
## design invalidates the result because it is recomputed from this object.
func validate(content) -> Array:
	var checks: Array = []
	var s: Dictionary = summary(content)
	var req: Dictionary = content.requirements
	var required_slots: Array = content.required_slots()

	# 1. Required slots.
	var names: Array = []
	for slot in required_slots:
		if slot_component(String(slot)) == "":
			names.append(_slot_label(String(slot)).to_lower())
	if names.is_empty():
		checks.append(_check("slots", true, true, "All required slots are filled."))
	else:
		checks.append(_check(
			"slots", false, true,
			"Required slots are empty: %s." % ", ".join(names),
			"Install one component in each empty slot."))

	# 2. Sensor quality.
	var min_quality := int(req.get("minimum_sensor_quality", 0))
	var q := int(s["sensor_quality"])
	if slot_component("sensor") == "":
		checks.append(_check("sensor", false, true,
			"No scientific sensor is installed.",
			"Install a sensor rated quality %d or better." % min_quality))
	elif q >= min_quality:
		checks.append(_check("sensor", true, true,
			"Sensor resolution meets the mission requirement (quality %d of %d)." % [q, min_quality]))
	else:
		checks.append(_check("sensor", false, true,
			"Sensor resolution is too low for the signal (quality %d of %d required)." % [q, min_quality],
			"Replace it with the Spectrometer Array or the Deep Fields Instrument."))

	# 3. Lift and launch mass.
	var wet := float(s["wet_mass_kg"])
	var hull_limit := float(s["hull_mass_limit_kg"])
	var lift := float(s["lift_capacity_kg"])
	if slot_component("propulsion") == "":
		checks.append(_check("mass", false, true,
			"No propulsion is installed.",
			"Install a propulsion module that can lift the assembled ship."))
	elif hull_limit > 0.0 and wet > hull_limit:
		checks.append(_check("mass", false, true,
			"Launch mass %.0f kg exceeds the hull limit of %.0f kg." % [wet, hull_limit],
			"Remove a heavy component or reduce the fuel load."))
	elif lift > 0.0 and wet > lift:
		checks.append(_check("mass", false, true,
			"Launch mass %.0f kg exceeds the propulsion limit of %.0f kg." % [wet, lift],
			"Remove a heavy component, reduce fuel, or install the Heavy Cluster."))
	else:
		checks.append(_check("mass", true, true,
			"Launch mass %.0f kg is within the %.0f kg limit." % [wet, s["mass_limit_kg"]]))

	# 4. Budget.
	var cost := float(s["cost"])
	if cost > content.program.get("start_credits", 80.0):
		checks.append(_check("budget", false, true,
			"Design costs %.0f credits, over the %.0f credit budget." % [cost, content.program.get("start_credits", 80.0)],
			"Choose cheaper components. The solar array and light thruster are the cheapest path."))
	else:
		checks.append(_check("budget", true, true,
			"Design costs %.0f of %.0f credits." % [cost, content.program.get("start_credits", 80.0)]))

	# 5. Peak power.
	var demand := float(s["power_demand_w"])
	var output := float(s["power_output_w"])
	if slot_component("power") == "":
		checks.append(_check("power", false, true,
			"No power plant is installed.",
			"Install a solar array or a power cell."))
	elif demand > output:
		checks.append(_check("power", false, true,
			"Power demand %.0f W exceeds available output %.0f W." % [demand, output],
			"Replace the sensor or install a higher-output power module."))
	else:
		checks.append(_check("power", true, true,
			"Power demand %.0f W is supported by %.0f W of output." % [demand, output]))

	# 6. Stored energy for the observation window.
	var stored := float(s["energy_stored_wh"])
	var required := float(s["energy_required_wh"])
	var obs := float(req.get("observation_hours", 2.0))
	if stored < required:
		checks.append(_check("energy", false, true,
			"Stored energy %.0f Wh is short of the %.0f Wh observation window needs." % [stored, required],
			"Install the Radioisotope Power Cell, or fit a sensor that draws less power (the window is %.1f h at peak demand)." % obs))
	else:
		checks.append(_check("energy", true, true,
			"Stored energy %.0f Wh covers the %.0f Wh observation window." % [stored, required]))

	# 7. Fuel.
	var min_fuel := float(req.get("minimum_fuel_kg", 0.0))
	if fuel_kg < min_fuel:
		checks.append(_check("fuel", false, true,
			"Fuel load %.0f kg is below the %.0f kg mission minimum." % [fuel_kg, min_fuel],
			"Increase the fuel load on the construction console."))
	elif fuel_kg > float(s["fuel_capacity_kg"]):
		checks.append(_check("fuel", false, true,
			"Fuel load %.0f kg exceeds the tank capacity of %.0f kg." % [fuel_kg, s["fuel_capacity_kg"]],
			"Reduce the fuel load."))
	else:
		checks.append(_check("fuel", true, true,
			"Fuel load %.0f kg meets the %.0f kg mission minimum." % [fuel_kg, min_fuel]))

	# 8. Data capacity (informational, never blocks).
	var capture := float(s["data_capture_mb"])
	var capacity := float(s["data_capacity_mb"])
	if capture > capacity:
		checks.append(_check("data", false, false,
			"Sensor capture %.0f MB exceeds the %.0f MB data capacity." % [capture, capacity],
			"The recorded data would be truncated. Install a lower-yield sensor."))
	else:
		checks.append(_check("data", true, false,
			"Data capacity %.0f MB holds an estimated %.0f MB of captured science." % [capacity, capture]))

	return checks


func is_valid(content) -> bool:
	for c in validate(content):
		var check: Dictionary = c
		if bool(check.get("blocking", true)) and not bool(check.get("ok", false)):
			return false
	return true


func first_blocking_failure(content) -> Dictionary:
	for c in validate(content):
		var check: Dictionary = c
		if bool(check.get("blocking", true)) and not bool(check.get("ok", false)):
			return check
	return {}


func _check(id: String, ok: bool, blocking: bool, message: String, hint: String = "") -> Dictionary:
	return {"id": id, "ok": ok, "blocking": blocking, "message": message, "hint": hint}


func _slot_label(slot: String) -> String:
	match slot:
		"computer":
			return "Flight Computer"
		"propulsion":
			return "Propulsion"
		"power":
			return "Power Plant"
		"communications":
			return "Communications"
		"sensor":
			return "Sensor"
	return slot.capitalize()


# ---------------------------------------------------------------- persistence

func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "fuel_kg": fuel_kg}


## Restores this design from a save dictionary. Unknown slot ids and
## component ids are ignored rather than trusted.
func load_dict(data: Dictionary) -> void:
	clear()
	var raw: Variant = data.get("slots", {})
	if raw is Dictionary:
		for k in (raw as Dictionary).keys():
			var slot := String(k)
			if SLOTS.has(slot):
				set_slot(slot, String((raw as Dictionary)[k]))
	fuel_kg = maxf(0.0, float(data.get("fuel_kg", 0.0)))
