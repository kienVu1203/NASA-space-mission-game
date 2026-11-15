extends RefCounted
## Phase 4 finale rules. Pure: no nodes, no UI, no mutation.
##
## Three questions live here, and nowhere else:
##   1. Are the finale prerequisites satisfied right now?
##   2. What does the mission report say, from the recorded run?
##   3. What is the score, and by what published formula?
##
## The report never invents a number. Masses, route, reserves and material use
## are recomputed from the committed reconstruction design with the same
## SFReconstruction + SFReturnSim code the workshop certified, so the report and
## the simulation a player passed cannot disagree.

const SFReconstruction := preload("res://core/star_fall/sf_reconstruction.gd")

const BOSS_FLAGS := ["scrap_king_defeated", "toxic_tide_defeated", "sky_remnant_defeated"]
const COMPONENTS := ["navigation_chip", "power_core", "shield_emitter"]
const MANDATORY_PAYLOAD := ["bill_memory_core", "evidence_archive"]


## A workshop object restored to the committed design. Callers may simulate with
## it; nothing is spent.
static func workshop_for(campaign, reconstruction_data: Dictionary):
	var ws = SFReconstruction.new()
	var committed: Dictionary = campaign.reconstruction.get("committed", {}) as Dictionary
	ws.setup(reconstruction_data, campaign.original_propulsion_id(), committed)
	return ws


## The certified report stored at fabrication time, or an empty dictionary.
static func stored_report(campaign) -> Dictionary:
	return (campaign.reconstruction.get("report", {}) as Dictionary)


## Recomputed simulation of the committed design, or empty when there is none.
static func simulation_for(campaign, reconstruction_data: Dictionary) -> Dictionary:
	if not campaign.reconstruction.has("committed"):
		return {}
	var ws = workshop_for(campaign, reconstruction_data)
	var stored := stored_report(campaign)
	var seed_value := int(stored.get("seed", 30303))
	return ws.simulate(campaign.recovered_component_ids(), seed_value)


## Every finale prerequisite, as an ordered list of {"id", "ok"}. The screen maps
## ids to its own labels, so the same checks can be shown anywhere.
## `others_clear` is the caller's judgement that no cutscene, dialogue or
## transition is running; the controller owns that knowledge.
static func prerequisites(campaign, reconstruction_data: Dictionary, others_clear: bool = true) -> Dictionary:
	var checks: Array = []

	var bosses_ok := true
	for flag in BOSS_FLAGS:
		bosses_ok = bosses_ok and campaign.has_flag(String(flag))
	checks.append({"id": "bosses", "ok": bosses_ok})

	var components_ok := true
	for id in COMPONENTS:
		# Fitted to the frame, not merely carried: the merged workshop requires
		# every recovered component to be installed before it fabricates, so the
		# gate must agree with it or a fabrication could be described as ready
		# while a part is still in the backpack.
		components_ok = components_ok and campaign.has_component(String(id)) \
			and campaign.is_component_installed(String(id))
	checks.append({"id": "components", "ok": components_ok})

	var committed: Dictionary = campaign.reconstruction.get("committed", {}) as Dictionary
	var fabricated_ok := not committed.is_empty()
	checks.append({"id": "fabricated", "ok": fabricated_ok})

	# The mandatory payload is what makes the flight a return with evidence:
	# Bill's memory core and the minimum evidence archive must be in the design
	# that was actually fabricated.
	var payload_ok := false
	if fabricated_ok:
		var ws = workshop_for(campaign, reconstruction_data)
		var loaded: Array = []
		for p in ws.payload_entries():
			loaded.append(String((p as Dictionary).get("id", "")))
		payload_ok = true
		for id in MANDATORY_PAYLOAD:
			payload_ok = payload_ok and loaded.has(String(id))
	checks.append({"id": "payload", "ok": payload_ok})

	# The passing report must describe this exact design, and it must still pass
	# when recomputed from the committed record.
	var simulation_ok := false
	if fabricated_ok:
		var fresh := simulation_for(campaign, reconstruction_data)
		var stored := stored_report(campaign)
		simulation_ok = bool(fresh.get("valid", false)) \
			and String(stored.get("signature", "")) != "" \
			and String(fresh.get("signature", "")) == String(stored.get("signature", ""))
	checks.append({"id": "simulation", "ok": simulation_ok})
	checks.append({"id": "clear", "ok": bool(others_clear)})

	var all_ok := true
	for c in checks:
		all_ok = all_ok and bool((c as Dictionary).get("ok", false))
	return {"ok": all_ok, "checks": checks}


## The recorded run, as the mission report screen shows it. Every value here is
## measured from campaign state or recomputed from the committed design.
static func build_report(campaign, reconstruction_data: Dictionary, finale_data: Dictionary) -> Dictionary:
	var ws = workshop_for(campaign, reconstruction_data)
	var sim := simulation_for(campaign, reconstruction_data)
	var totals: Dictionary = sim.get("totals", {}) as Dictionary
	var route: Dictionary = ws.selected("route")
	var committed: Dictionary = campaign.reconstruction.get("committed", {}) as Dictionary
	var optional: Dictionary = committed.get("optional", {}) as Dictionary
	var cost := ws.material_cost()
	var units := ws.fabrication_units()
	for m in cost.keys():
		units += int(cost[m])

	var dry := float(totals.get("dry_mass_kg", 0.0))
	var efficiency := dry / float(maxi(1, units))

	var reserves := {
		"propellant_kg": float(totals.get("propellant_remaining_kg", 0.0)),
		"propellant_loaded_kg": float(totals.get("propellant_kg", 0.0)),
		"battery_wh": float(totals.get("battery_remaining_wh", 0.0)),
		"battery_capacity_wh": float(totals.get("battery_usable_wh", 0.0)),
	}

	var decisions: Array = []
	var text: Dictionary = (finale_data.get("report", {}) as Dictionary).get("decisions", {}) as Dictionary
	_append_decision(decisions, text, String(committed.get("propulsion", "")))
	_append_decision(decisions, text, String(committed.get("protection", "")))
	_append_decision(decisions, text, String(committed.get("storage", "")))
	_append_decision(decisions, text, String(committed.get("route", "")))
	if bool(optional.get("environmental_samples", false)):
		_append_decision(decisions, text, "samples")
	if bool(optional.get("additional_records", false)):
		_append_decision(decisions, text, "records")
	var reserve_text := String(text.get("reserve", ""))
	if reserve_text != "":
		decisions.append(reserve_text % [
			"%.0f kg" % reserves["propellant_kg"],
			"%.0f Wh" % reserves["battery_wh"],
		])

	var original_slots: Dictionary = (campaign.confirmed_design.get("slots", {}) as Dictionary)
	var original_label := _design_label(campaign, original_slots, float(campaign.confirmed_design.get("fuel_kg", 0.0)))

	var report := {
		"objective_complete": campaign.has_flag("return_objective_complete"),
		"memories": campaign.viewed_memories.duplicate(),
		"memory_count": campaign.viewed_memories.size(),
		"samples_returned": bool(optional.get("environmental_samples", false)),
		"records_returned": bool(optional.get("additional_records", false)),
		"components": campaign.recovered_component_ids().duplicate(),
		"original_design": original_label,
		"reconstructed_design": _reconstructed_label(ws),
		"launch_mass_kg": float(totals.get("wet_mass_kg", 0.0)),
		"dry_mass_kg": dry,
		"route_id": String(route.get("id", "")),
		"route_name": String(route.get("name", "")),
		"reserves": reserves,
		"material_units": units,
		"fabrication_units": ws.fabrication_units(),
		"material_cost": cost,
		"efficiency_kg_per_unit": efficiency,
		"debris_impacts": int(totals.get("debris_impacts", 0)),
		"decisions": decisions,
		"cinematic_skipped": campaign.cinematic_skipped(),
	}
	report["score"] = score_for(campaign, report, finale_data)
	return report


## The published score. Weights live in data/star_fall/finale.json under
## report.score; this function only applies them. Nothing here reads inventory
## size, play time, skipped cinematics or settings, so farming and accessibility
## choices cannot move the number.
static func score_for(_campaign, report: Dictionary, finale_data: Dictionary) -> Dictionary:
	var weights: Dictionary = ((finale_data.get("report", {}) as Dictionary).get("score", {}) as Dictionary)
	var w_objective := int(weights.get("return_objective", 100))
	var w_component := int(weights.get("component", 25))
	var w_memory := int(weights.get("memory", 15))
	var w_payload := int(weights.get("optional_payload", 20))
	var w_efficiency := int(weights.get("efficiency_max", 30))

	var objective := w_objective if bool(report.get("objective_complete", false)) else 0
	var components := w_component * (report.get("components", []) as Array).size()
	var memories := w_memory * int(report.get("memory_count", 0))
	var payload := 0
	if bool(report.get("samples_returned", false)):
		payload += w_payload
	if bool(report.get("records_returned", false)):
		payload += w_payload

	var reserves: Dictionary = report.get("reserves", {}) as Dictionary
	var loaded := float(reserves.get("propellant_loaded_kg", 0.0))
	var left := float(reserves.get("propellant_kg", 0.0))
	var ratio := 0.0 if loaded <= 0.0 else clampf(left / loaded, 0.0, 1.0)
	# Full efficiency points at half the propellant still in the tank. That is
	# generous on purpose: the score rewards margin rather than a knife edge, and
	# every passing design can reach it by loading slightly more propellant.
	var efficiency := int(round(float(w_efficiency) * clampf(ratio / 0.5, 0.0, 1.0)))

	return {
		"objective": objective,
		"components": components,
		"memories": memories,
		"payload": payload,
		"efficiency": efficiency,
		"total": objective + components + memories + payload + efficiency,
		"formula": "%d objective + %d/component + %d/memory + %d/optional payload + up to %d efficiency (propellant reserve)" % [
			w_objective, w_component, w_memory, w_payload, w_efficiency],
	}


## The snapshot frozen at final assembly. It carries only values the player
## actually recorded, so a report read after the fact describes the same run.
static func snapshot(campaign, reconstruction_data: Dictionary) -> Dictionary:
	var ws = workshop_for(campaign, reconstruction_data)
	var sim := simulation_for(campaign, reconstruction_data)
	var totals: Dictionary = sim.get("totals", {}) as Dictionary
	return {
		"design": campaign.reconstruction.get("committed", {}).duplicate(true),
		"report_signature": String(stored_report(campaign).get("signature", "")),
		"route_id": String(ws.selected("route").get("id", "")),
		"launch_mass_kg": float(totals.get("wet_mass_kg", 0.0)),
		"components": campaign.recovered_component_ids().duplicate(),
		"memories": campaign.viewed_memories.duplicate(),
		"frozen": true,
	}


# ---------------------------------------------------------------- helpers

static func _append_decision(out: Array, text: Dictionary, key: String) -> void:
	if key == "" or not text.has(key):
		return
	var line := String(text[key])
	if line != "" and not out.has(line):
		out.append(line)


static func _design_label(campaign, slots: Dictionary, fuel_kg: float) -> String:
	var names: Array = []
	for slot in ["propulsion", "power", "sensor", "computer", "communications"]:
		var id := String(slots.get(slot, ""))
		if id == "":
			continue
		var comp: Dictionary = campaign.content.component(id)
		names.append(String(comp.get("name", id)))
	if names.is_empty():
		return "No confirmed day-one design on record"
	var mass := float(campaign.mission_manifest.get("mass_kg", 0.0))
	return "%s / %.0f kg propellant, %.0f kg launch mass" % [" + ".join(names), fuel_kg, mass]


static func _reconstructed_label(ws) -> String:
	var parts: Array = []
	for group in ["propulsion", "protection", "storage", "route"]:
		var o: Dictionary = ws.selected(group)
		if not o.is_empty():
			parts.append(String(o.get("name", o.get("id", ""))))
	return " / ".join(parts)
