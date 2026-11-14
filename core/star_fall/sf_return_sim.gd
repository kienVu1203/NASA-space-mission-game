extends RefCounted
## Return-mission simulation for the reconstructed VELA. Pure and deterministic:
## no nodes, no UI, no campaign mutation. Running it never spends anything.
##
## SIMPLIFIED EDUCATIONAL MODEL. All values come from
## data/star_fall/reconstruction.json and are invented for the game; none of
## them are NASA data.
##
## Model
##   mass        dry = frame + recovered parts + fitted parts + payload (kg);
##               wet = dry + propellant (kg). Wet mass must fit the frame limit
##               and the engine's thrust capacity.
##   delta-v     ideal rocket equation, dv = Isp * g0 * ln(wet / dry), against
##               the route requirement plus a reserve fraction. Each stage burns
##               its share of the route delta-v in order.
##   power       each stage has a demand in W. The power core supplies its
##               output continuously; demand above it is drawn from the core's
##               buffer, limited to a maximum discharge rate (peak check).
##   energy      energy_used_Wh = power_W * duration_s / 3600. Only the part
##               above the core's output drains the buffer, which must keep a
##               reserve fraction. Electrical energy and propellant are separate.
##   protection  emitter rating + upgrade rating >= route debris rating.
##   data        payload MB <= storage MB.
##   sync        the payload is copied from the surviving local Dawn relay at
##               relay_rate MB/s before launch and must fit the route's launch
##               window. Nothing contacts the present day.
##   seed        only varies the reported debris impact count; validity is
##               decided by the deterministic margins above.

const REQUIRED_COMPONENTS := ["navigation_chip", "power_core", "shield_emitter"]


## `spec` comes from SFReconstruction.build_spec(). Returns the report:
## {"valid", "signature", "seed", "route_id", "checks", "failures",
##  "suggestions", "stages", "totals"}.
static func simulate(spec: Dictionary, data: Dictionary, seed_value: int) -> Dictionary:
	var k: Dictionary = data.get("constants", {}) as Dictionary
	var frame: Dictionary = data.get("frame", {}) as Dictionary
	var route: Dictionary = spec.get("route", {}) as Dictionary
	var propulsion: Dictionary = spec.get("propulsion", {}) as Dictionary
	var protection: Dictionary = spec.get("protection", {}) as Dictionary
	var storage: Dictionary = spec.get("storage", {}) as Dictionary
	var payload: Array = spec.get("payload", []) as Array
	var recovered_ids: Array = spec.get("recovered_ids", []) as Array
	var fuel := float(spec.get("fuel_kg", 0.0))
	var g0 := float(k.get("g0_m_s2", 9.81))
	var checks: Array = []

	# Recovered components actually present.
	var parts: Dictionary = {}
	for c in data.get("recovered_components", []) as Array:
		var comp: Dictionary = c
		if recovered_ids.has(String(comp["id"])):
			parts[String(comp["id"])] = comp
	var nav: Dictionary = parts.get("navigation_chip", {}) as Dictionary
	var core: Dictionary = parts.get("power_core", {}) as Dictionary
	var emitter: Dictionary = parts.get("shield_emitter", {}) as Dictionary

	# 1. Required components.
	var missing: Array = []
	for id in REQUIRED_COMPONENTS:
		if not parts.has(String(id)):
			missing.append(String(id).replace("_", " "))
	_add(checks, "components", missing.is_empty(),
		"All three recovered components are installed." if missing.is_empty()
		else "Missing recovered component: %s." % ", ".join(missing),
		"Final assembly needs the navigation chip, power core and shield emitter.")

	# 2. Mandatory payload.
	var payload_ids: Array = []
	for p in payload:
		payload_ids.append(String((p as Dictionary)["id"]))
	var missing_payload: Array = []
	for p in data.get("payload", []) as Array:
		var entry: Dictionary = p
		if bool(entry.get("mandatory", false)) and not payload_ids.has(String(entry["id"])):
			missing_payload.append(String(entry["name"]))
	_add(checks, "payload", missing_payload.is_empty(),
		"Mandatory payload loaded: Bill's memory core and the evidence archive." if missing_payload.is_empty()
		else "Mandatory payload missing: %s." % ", ".join(missing_payload),
		"Bill's memory core and the minimum evidence archive must fly.")

	# Mass.
	var dry := float(frame.get("dry_mass_kg", 0.0))
	for id in parts.keys():
		dry += float((parts[id] as Dictionary).get("mass_kg", 0.0))
	dry += float(propulsion.get("mass_kg", 0.0)) + float(protection.get("mass_kg", 0.0)) + float(storage.get("mass_kg", 0.0))
	var payload_mass := 0.0
	var payload_data := 0.0
	var payload_power := 0.0
	for p in payload:
		var entry: Dictionary = p
		payload_mass += float(entry.get("mass_kg", 0.0))
		payload_data += float(entry.get("data_mb", 0.0))
		payload_power += float(entry.get("power_w", 0.0))
	dry += payload_mass
	var wet := dry + fuel
	var frame_limit := float(frame.get("mass_limit_kg", 0.0))
	var thrust_limit := float(propulsion.get("thrust_capacity_kg", 0.0))
	var mass_limit := minf(frame_limit, thrust_limit) if thrust_limit > 0.0 else frame_limit

	# 3. Launch mass.
	if wet > frame_limit:
		_add(checks, "mass", false, "Launch mass %.0f kg exceeds the frame limit of %.0f kg." % [wet, frame_limit],
			"Carry less propellant or drop optional payload.")
	elif wet > thrust_limit:
		_add(checks, "mass", false, "Launch mass %.0f kg exceeds the engine's %.0f kg thrust capacity." % [wet, thrust_limit],
			"Lighten the ship, or fit an engine with more thrust (rebuilt cluster or a repaired heavy cluster).")
	else:
		_add(checks, "mass", true, "Launch mass %.0f kg is within the %.0f kg limit." % [wet, mass_limit])

	# 4. Tank.
	var tank := float(frame.get("tank_capacity_kg", 0.0))
	_add(checks, "tank", fuel <= tank,
		"Propellant %.0f kg fits the %.0f kg tank." % [fuel, tank] if fuel <= tank
		else "Propellant %.0f kg exceeds the %.0f kg tank." % [fuel, tank], "Reduce the propellant load.")

	# 5. Delta-v with reserve, and per-stage propellant.
	var isp := float(propulsion.get("isp_s", 0.0))
	var ve := isp * g0
	var dv_route := float(route.get("delta_v_m_s", 0.0))
	var reserve := float(k.get("delta_v_reserve_fraction", 0.1))
	var dv_required := dv_route * (1.0 + reserve)
	var dv_available: float = ve * log(wet / dry) if dry > 0.0 and fuel > 0.0 and ve > 0.0 else 0.0
	var fuel_needed: float = dry * (exp(dv_required / ve) - 1.0) if ve > 0.0 else INF
	var step := float(frame.get("fuel_step_kg", 20.0))
	var fuel_needed_step: float = ceil(fuel_needed / step) * step if fuel_needed < INF else INF
	if dv_available >= dv_required:
		_add(checks, "delta_v", true, "Delta-v %.0f m/s covers %.0f m/s plus a %d%% reserve." % [dv_available, dv_route, int(round(reserve * 100.0))])
	else:
		var hint: String = "Load at least %.0f kg of propellant." % fuel_needed_step
		if dry + fuel_needed_step > mass_limit:
			hint = "Even a full load cannot reach it at this mass: lighten the ship, fit a stronger engine, or take the Extended Arc."
		_add(checks, "delta_v", false,
			"Delta-v %.0f m/s is short of the %.0f m/s needed (route %.0f m/s + reserve)." % [dv_available, dv_required, dv_route], hint)

	# Electrical stages.
	var output := float(core.get("output_w", 0.0))
	var buffer := float(core.get("storage_wh", 0.0))
	var discharge := float(k.get("max_battery_discharge_w", 0.0))
	var base_w := float(nav.get("power_w", 0.0)) + float(k.get("crew_life_support_w", 0.0)) + payload_power \
		+ float(storage.get("power_w", 0.0)) + float(emitter.get("idle_w", 0.0))
	var data_capacity := float(nav.get("data_capacity_mb", 0.0)) + float(storage.get("data_mb", 0.0))
	var relay_rate := maxf(0.001, float(k.get("relay_rate_mb_per_s", 0.5)))
	var sync_s := payload_data / relay_rate
	var share: Dictionary = data.get("stage_delta_v_share", {}) as Dictionary
	var stage_defs := [
		{"id": "prelaunch_sync", "name": "Relay sync", "seconds": sync_s,
			"power_w": base_w + float(k.get("relay_radio_w", 0.0)), "dv_share": 0.0},
		{"id": "ascent", "name": "Ascent", "seconds": float(k.get("ascent_seconds", 300.0)),
			"power_w": base_w + float(propulsion.get("power_w", 0.0)), "dv_share": float(share.get("ascent", 0.6))},
		{"id": "transit", "name": "Debris transit", "seconds": float(route.get("transit_seconds", 0.0)),
			"power_w": base_w - float(emitter.get("idle_w", 0.0)) + float(emitter.get("active_w", 0.0)) + float(protection.get("active_w", 0.0)),
			"dv_share": float(share.get("transit", 0.25))},
		{"id": "rift", "name": "Rift transition", "seconds": float(k.get("rift_seconds", 300.0)),
			"power_w": base_w + float(k.get("rift_navigation_surge_w", 0.0)), "dv_share": float(share.get("rift", 0.15))},
	]
	var stages: Array = []
	var mass_now := wet
	var prop_used := 0.0
	var peak := 0.0
	var deficit_total := 0.0
	var energy_total := 0.0
	for s in stage_defs:
		var st: Dictionary = s
		var seconds := float(st["seconds"])
		var power := float(st["power_w"])
		var used_wh := power * seconds / 3600.0
		var deficit_wh := maxf(0.0, power - output) * seconds / 3600.0
		var dv_stage := dv_route * float(st["dv_share"])
		var prop := 0.0
		if dv_stage > 0.0 and ve > 0.0:
			prop = mass_now - mass_now / exp(dv_stage / ve)
		mass_now -= prop
		prop_used += prop
		peak = maxf(peak, power)
		deficit_total += deficit_wh
		energy_total += used_wh
		stages.append({
			"id": String(st["id"]), "name": String(st["name"]), "duration_s": seconds,
			"power_w": power, "energy_used_wh": used_wh, "battery_draw_wh": deficit_wh,
			"delta_v_m_s": dv_stage, "propellant_kg": prop,
		})

	# 6. Peak electrical demand.
	var power_limit := output + discharge
	_add(checks, "peak_power", peak <= power_limit,
		"Peak demand %.0f W is within %.0f W (core %.0f W + buffer %.0f W)." % [peak, power_limit, output, discharge] if peak <= power_limit
		else "Peak demand %.0f W exceeds %.0f W (core %.0f W + buffer %.0f W)." % [peak, power_limit, output, discharge],
		"Drop the amplifier, the sample cooler or the larger data array to cut peak load.")

	# 7. Total energy with reserve.
	var usable := buffer * (1.0 - float(k.get("battery_reserve_fraction", 0.2)))
	_add(checks, "energy", deficit_total <= usable,
		"Buffer draw %.0f Wh leaves the %d%% reserve (usable %.0f Wh)." % [deficit_total, int(round(float(k.get("battery_reserve_fraction", 0.2)) * 100.0)), usable] if deficit_total <= usable
		else "Buffer draw %.0f Wh exceeds the usable %.0f Wh." % [deficit_total, usable],
		"Shorter routes drain less. Cut continuous loads such as the amplifier or sample cooling.")

	# 8. Protection.
	var rating := float(emitter.get("protection_rating", 0.0)) + float(protection.get("rating", 0.0))
	var needed_rating := float(route.get("debris_rating", 0.0))
	_add(checks, "protection", rating >= needed_rating,
		"Protection rating %.0f meets the route's debris rating %.0f." % [rating, needed_rating] if rating >= needed_rating
		else "Protection rating %.0f is below the route's debris rating %.0f." % [rating, needed_rating],
		"Fit armor plating or a shield amplifier, or take the Extended Arc.")

	# 9. Data capacity.
	_add(checks, "data", payload_data <= data_capacity,
		"Payload data %.0f MB fits %.0f MB of storage." % [payload_data, data_capacity] if payload_data <= data_capacity
		else "Payload data %.0f MB exceeds %.0f MB of storage." % [payload_data, data_capacity],
		"Fit a larger data module or leave the additional records behind.")

	# 10. Local relay synchronization.
	var window := float(route.get("launch_window_seconds", 0.0))
	_add(checks, "sync", sync_s <= window,
		"Relay sync takes %.0f s, inside the %.0f s launch window." % [sync_s, window] if sync_s <= window
		else "Relay sync takes %.0f s, longer than the %.0f s launch window." % [sync_s, window],
		"Carry less data, or take the Extended Arc and its longer window.")

	# Seeded, informational only: debris impacts the shield absorbs in transit.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var variance := float(route.get("debris_variance", 0.0))
	var impacts := int(round(float(route.get("transit_seconds", 0.0)) / 600.0 * needed_rating
		* float(k.get("debris_impacts_per_600_s_per_rating", 1.0)) * (1.0 + variance * rng.randf_range(-1.0, 1.0))))

	var failures: Array = []
	var suggestions: Array = []
	for c in checks:
		var check: Dictionary = c
		if not bool(check["ok"]):
			failures.append(String(check["message"]))
			if String(check["hint"]) != "" and not suggestions.has(String(check["hint"])):
				suggestions.append(String(check["hint"]))

	return {
		"valid": failures.is_empty(),
		"signature": String(spec.get("signature", "")),
		"seed": seed_value,
		"route_id": String(route.get("id", "")),
		"checks": checks,
		"failures": failures,
		"suggestions": suggestions,
		"stages": stages,
		"totals": {
			"dry_mass_kg": dry, "wet_mass_kg": wet, "mass_limit_kg": mass_limit,
			"propellant_kg": fuel, "propellant_used_kg": prop_used, "propellant_remaining_kg": fuel - prop_used,
			"propellant_needed_kg": fuel_needed_step,
			"delta_v_available_m_s": dv_available, "delta_v_required_m_s": dv_required,
			"peak_power_w": peak, "power_limit_w": power_limit,
			"energy_used_wh": energy_total, "battery_draw_wh": deficit_total,
			"battery_usable_wh": usable, "battery_remaining_wh": buffer - deficit_total,
			"protection_rating": rating, "protection_required": needed_rating,
			"payload_data_mb": payload_data, "data_capacity_mb": data_capacity,
			"sync_seconds": sync_s, "launch_window_seconds": window,
			"debris_impacts": impacts,
		},
	}


static func _add(checks: Array, id: String, ok: bool, message: String, hint: String = "") -> void:
	checks.append({"id": id, "ok": ok, "message": message, "hint": "" if ok else hint})
