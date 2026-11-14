extends RefCounted
## The VELA reconstruction workshop: the player's selection, its material and
## fabrication cost, and the one atomic fabrication commit. Pure rules: no
## nodes, no UI. The screen edits a selection; previewing and simulating are
## free; only commit() spends materials, and only once.
##
## Unlike the day-one construction console (credits, new parts), the future
## workshop runs on salvage (scrap metal, circuitry, polymer) and a limited
## fabrication capacity. Propellant is drawn from the Dawn Project depot.

const SFReturnSim := preload("res://core/star_fall/sf_return_sim.gd")

const GROUPS := ["propulsion", "protection", "storage", "route"]
const OPTIONAL_PAYLOAD := ["environmental_samples", "additional_records"]

var data: Dictionary = {}
var original_propulsion_id: String = "propulsion_light"
var selection: Dictionary = {}


## `original_id` is the propulsion the player launched with on day one.
func setup(reconstruction_data: Dictionary, original_id: String, saved_selection: Dictionary = {}) -> void:
	data = reconstruction_data
	var originals: Dictionary = data.get("original_propulsion", {}) as Dictionary
	original_propulsion_id = original_id if originals.has(original_id) else "propulsion_light"
	selection = default_selection()
	if not saved_selection.is_empty():
		load_selection(saved_selection)


func default_selection() -> Dictionary:
	return {
		"propulsion": "repair_original",
		"protection": "protection_none",
		"storage": "storage_compact",
		"route": "extended_arc",
		"fuel_kg": 0.0,
		"optional": {"environmental_samples": false, "additional_records": false},
	}


## Restores a saved selection, ignoring unknown ids rather than trusting them.
func load_selection(saved: Dictionary) -> void:
	for group in GROUPS:
		var id := String(saved.get(group, ""))
		if not option(String(group), id).is_empty():
			selection[group] = id
	set_fuel(float(saved.get("fuel_kg", 0.0)))
	var opt: Variant = saved.get("optional", {})
	if opt is Dictionary:
		for id in OPTIONAL_PAYLOAD:
			selection["optional"][id] = bool((opt as Dictionary).get(id, false))


func to_dict() -> Dictionary:
	return selection.duplicate(true)


# ---------------------------------------------------------------- options

func options(group: String) -> Array:
	return data.get(group + "s" if group == "route" else group, []) as Array


func option(group: String, id: String) -> Dictionary:
	for o in options(group):
		if String((o as Dictionary)["id"]) == id:
			return o
	return {}


func selected(group: String) -> Dictionary:
	return option(group, String(selection.get(group, "")))


## Cycles a group's choice by `direction` steps.
func cycle(group: String, direction: int) -> void:
	var list := options(group)
	if list.is_empty():
		return
	var at := 0
	for i in list.size():
		if String((list[i] as Dictionary)["id"]) == String(selection.get(group, "")):
			at = i
	selection[group] = String((list[posmod(at + direction, list.size())] as Dictionary)["id"])


func set_choice(group: String, id: String) -> bool:
	if option(group, id).is_empty():
		return false
	selection[group] = id
	return true


func toggle_optional(id: String) -> void:
	if OPTIONAL_PAYLOAD.has(id):
		selection["optional"][id] = not bool(selection["optional"].get(id, false))


func set_optional(id: String, value: bool) -> void:
	if OPTIONAL_PAYLOAD.has(id):
		selection["optional"][id] = value


func set_fuel(value: float) -> void:
	var frame: Dictionary = data.get("frame", {}) as Dictionary
	var step := float(frame.get("fuel_step_kg", 20.0))
	selection["fuel_kg"] = clampf(round(value / step) * step, 0.0, float(frame.get("tank_capacity_kg", 0.0)))


func adjust_fuel(steps: int) -> void:
	var step := float((data.get("frame", {}) as Dictionary).get("fuel_step_kg", 20.0))
	set_fuel(float(selection["fuel_kg"]) + float(steps) * step)


## A stable fingerprint of the design. A report is only current while its
## signature matches, so any change invalidates a passing report.
func signature() -> String:
	return JSON.stringify([selection["propulsion"], selection["protection"], selection["storage"],
		selection["route"], float(selection["fuel_kg"]), bool(selection["optional"]["environmental_samples"]),
		bool(selection["optional"]["additional_records"]), original_propulsion_id])


# ---------------------------------------------------------------- resolution

## The resolved propulsion stats: the repaired original engine takes its
## numbers from the day-one choice, so every Phase 1 build carries forward.
func propulsion_stats() -> Dictionary:
	var choice := selected("propulsion")
	var out := choice.duplicate(true)
	if String(choice.get("id", "")) == "repair_original":
		var originals: Dictionary = data.get("original_propulsion", {}) as Dictionary
		var orig: Dictionary = originals.get(original_propulsion_id, {}) as Dictionary
		for key in orig.keys():
			if key != "name":
				out[key] = orig[key]
		out["name"] = String(orig.get("name", out.get("name", "")))
	return out


func payload_entries() -> Array:
	var out: Array = []
	for p in data.get("payload", []) as Array:
		var entry: Dictionary = p
		if bool(entry.get("mandatory", false)) or bool(selection["optional"].get(String(entry["id"]), false)):
			out.append(entry)
	return out


## Everything the simulation needs, resolved from data and the selection.
func build_spec(recovered_ids: Array) -> Dictionary:
	return {
		"signature": signature(),
		"route": selected("route"),
		"propulsion": propulsion_stats(),
		"protection": selected("protection"),
		"storage": selected("storage"),
		"payload": payload_entries(),
		"recovered_ids": recovered_ids.duplicate(),
		"fuel_kg": float(selection["fuel_kg"]),
	}


func simulate(recovered_ids: Array, seed_value: int) -> Dictionary:
	return SFReturnSim.simulate(build_spec(recovered_ids), data, seed_value)


# ---------------------------------------------------------------- cost

func _priced_parts() -> Array:
	var out: Array = [selected("propulsion"), selected("protection"), selected("storage")]
	out.append_array(payload_entries())
	return out


## Total material cost {material_id: amount}.
func material_cost() -> Dictionary:
	var total: Dictionary = {}
	for p in _priced_parts():
		var cost: Dictionary = (p as Dictionary).get("cost", {}) as Dictionary
		for m in cost.keys():
			total[String(m)] = int(total.get(String(m), 0)) + int(cost[m])
	return total


func fabrication_units() -> int:
	var units := 0
	for p in _priced_parts():
		units += int((p as Dictionary).get("fabrication", 0))
	return units


func fabrication_capacity() -> int:
	return int(data.get("fabrication_capacity", 12))


## Material shortfall against the campaign inventory: {material: missing}.
func shortfall(campaign) -> Dictionary:
	var out: Dictionary = {}
	var cost := material_cost()
	for m in cost.keys():
		var have: int = campaign.material_count(String(m))
		if have < int(cost[m]):
			out[String(m)] = int(cost[m]) - have
	return out


## Fabricates and assembles the design. Atomic: every condition is checked
## before anything is removed, and a committed design can never be charged
## twice. Returns {"ok": bool, "message": String}.
func commit(campaign, report: Dictionary) -> Dictionary:
	if campaign.has_flag(campaign.FLAG_READY_FOR_FINAL_ASSEMBLY):
		return {"ok": false, "message": "The VELA is already assembled."}
	if report.is_empty() or String(report.get("signature", "")) != signature():
		return {"ok": false, "message": "Run the simulation on this exact design first."}
	if not bool(report.get("valid", false)):
		return {"ok": false, "message": "The simulation report shows failures. Revise the design."}
	for id in SFReturnSim.REQUIRED_COMPONENTS:
		if not campaign.has_component(String(id)):
			return {"ok": false, "message": "Missing recovered component: %s." % String(id).replace("_", " ")}
	if fabrication_units() > fabrication_capacity():
		return {"ok": false, "message": "The design needs %d fabrication units; the workshop has %d." % [fabrication_units(), fabrication_capacity()]}
	var short := shortfall(campaign)
	if not short.is_empty():
		return {"ok": false, "message": "Not enough salvage: %s." % _describe(short, campaign)}
	var cost := material_cost()
	for m in cost.keys():
		campaign.remove_material(String(m), int(cost[m]))
	campaign.commit_reconstruction(to_dict(), report)
	return {"ok": true, "message": "VELA fabricated and assembled."}


## Fair replenishment of common materials: tops each material up to the floor
## in reconstruction.json, never above it. The floor covers the cheapest valid
## build, so no run can be stranded by having spent salvage earlier.
## Returns {material: added}.
func replenish(campaign) -> Dictionary:
	var added: Dictionary = {}
	var floor_map: Dictionary = data.get("replenish_floor", {}) as Dictionary
	for m in floor_map.keys():
		var need := int(floor_map[m]) - int(campaign.material_count(String(m)))
		if need > 0:
			var got: int = campaign.add_material(String(m), need)
			if got > 0:
				added[String(m)] = got
	return added


func _describe(amounts: Dictionary, campaign) -> String:
	var parts: Array = []
	for m in amounts.keys():
		parts.append("%d %s" % [int(amounts[m]), campaign.content.material_name(String(m))])
	return ", ".join(parts)
