extends RefCounted
## Persistent campaign state for STAR FALL. Pure data and rules: screens read
## and request changes here; this class never touches UI nodes.
##
## Campaign state is deliberately separate from the legacy mission-planner
## demo state in autoload/game_state.gd.
const SFContent := preload("res://core/star_fall/sf_content.gd")
const SFDesign := preload("res://core/star_fall/sf_design.gd")

const SAVE_VERSION := 1

# Campaign stages. The stage is the only thing that decides which screen runs.
const STAGE_MENU := "menu"
const STAGE_BRIEFING := "briefing"
const STAGE_CONSTRUCTION := "construction"
const STAGE_LAUNCH := "launch"
const STAGE_FLIGHT := "flight"
const STAGE_CRASH_INTRO := "crash_intro"
const STAGE_CRASH_SITE := "crash_site"
const STAGE_MEMORY := "memory"
const STAGE_CHECKPOINT := "checkpoint"
const STAGE_COMPLETE := "complete"

## Legal forward transitions. Save loading clamps back into this graph.
const STAGE_ORDER := [
	STAGE_MENU,
	STAGE_BRIEFING,
	STAGE_CONSTRUCTION,
	STAGE_LAUNCH,
	STAGE_FLIGHT,
	STAGE_CRASH_INTRO,
	STAGE_CRASH_SITE,
	STAGE_MEMORY,
	STAGE_CHECKPOINT,
	STAGE_COMPLETE,
]

const CHAPTER_PRESENT := "present_day_earth"
const CHAPTER_CRASH := "crash_site"

const MEMORY_GREEN_CITY := "memory_green_city"

# Quest flags.
const FLAG_BRIEFING_READ := "briefing_read"
const FLAG_DESIGN_CONFIRMED := "design_confirmed"
const FLAG_PREFLIGHT_PASSED := "preflight_passed"
const FLAG_LAUNCHED := "launched"
const FLAG_RIFT_SEEN := "rift_seen"
const FLAG_CRASHED := "crashed"
const FLAG_VELA_INSPECTED := "vela_inspected"
const FLAG_POWER_REPAIRED := "power_repaired"
const FLAG_BILL_ACTIVE := "bill_active"
const FLAG_MEMORY_VIEWED := "memory_viewed"
const FLAG_COORDINATES_RECEIVED := "coordinates_received"

var content

var stage: String = STAGE_MENU
var chapter_id: String = CHAPTER_PRESENT
var checkpoint_stage: String = STAGE_BRIEFING
var checkpoint_chapter: String = CHAPTER_PRESENT

var credits: float = 0.0
var design: RefCounted = null
var confirmed_design: Dictionary = {}   # the design that actually launched
var inventory: Dictionary = {}          # material id -> count
var collected_items: Array = []         # world object ids already picked up
var flags: Dictionary = {}              # flag id -> true
var viewed_memories: Array = []
var mission_manifest: Dictionary = {}

var play_seconds: float = 0.0


func _init() -> void:
	content = SFContent.new()
	if not content.load_all():
		push_error("SFCampaign: campaign content failed to load")
	design = SFDesign.new()
	reset_campaign()


func reset_campaign() -> void:
	stage = STAGE_MENU
	chapter_id = CHAPTER_PRESENT
	checkpoint_stage = STAGE_BRIEFING
	checkpoint_chapter = CHAPTER_PRESENT
	credits = float(content.program.get("start_credits", 100.0))
	design = SFDesign.new()
	confirmed_design = {}
	inventory = {}
	collected_items = []
	flags = {}
	viewed_memories = []
	mission_manifest = {}
	play_seconds = 0.0


# ---------------------------------------------------------------- stage flow

func can_transition_to(next_stage: String) -> bool:
	return STAGE_ORDER.has(next_stage)


## Advances the campaign stage. Returns false when the id is unknown.
func advance_to(next_stage: String) -> bool:
	if not can_transition_to(next_stage):
		push_error("Unknown campaign stage: %s" % next_stage)
		return false
	if next_stage == stage:
		return true
	stage = next_stage
	_update_chapter_for_stage()
	return true


func _update_chapter_for_stage() -> void:
	match stage:
		STAGE_FLIGHT, STAGE_CRASH_INTRO, STAGE_CRASH_SITE, STAGE_MEMORY, STAGE_CHECKPOINT, STAGE_COMPLETE:
			chapter_id = CHAPTER_CRASH
		_:
			chapter_id = CHAPTER_PRESENT


## Records a safe resume point. Called at every scripted beat boundary.
func set_checkpoint(at_stage: String, at_chapter: String = "") -> void:
	checkpoint_stage = at_stage
	checkpoint_chapter = at_chapter if at_chapter != "" else chapter_id


func stage_index() -> int:
	return STAGE_ORDER.find(stage)


# ---------------------------------------------------------------- flags

func set_flag(flag: String, value: bool = true) -> void:
	if flag == "":
		return
	if value:
		flags[flag] = true
	else:
		flags.erase(flag)


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


# ---------------------------------------------------------------- budget

func spend(amount: float) -> bool:
	if amount < 0.0 or credits < amount:
		return false
	credits -= amount
	return true


func refund(amount: float) -> void:
	if amount <= 0.0:
		return
	credits = minf(credits + amount, float(content.program.get("start_credits", 100.0)))


# ---------------------------------------------------------------- inventory

func inventory_limit() -> int:
	return int(content.program.get("inventory_limit", 24))


func inventory_used() -> int:
	var total: int = 0
	for k in inventory.keys():
		total += int(inventory[k])
	return total


func inventory_free() -> int:
	return inventory_limit() - inventory_used()


func has_material(material: String, amount: int = 1) -> bool:
	return int(inventory.get(material, 0)) >= amount


## Adds material, refusing anything that would exceed the carry limit.
## Quantities can never go negative. Returns the amount actually added.
func add_material(material: String, amount: int) -> int:
	if material == "" or amount <= 0:
		return 0
	var free := inventory_free()
	if free <= 0:
		return 0
	var accepted: int = mini(amount, free)
	inventory[material] = int(inventory.get(material, 0)) + accepted
	return accepted


func remove_material(material: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var held := int(inventory.get(material, 0))
	if held < amount:
		return false
	var left := held - amount
	if left <= 0:
		inventory.erase(material)
	else:
		inventory[material] = left
	return true


func material_count(material: String) -> int:
	return int(inventory.get(material, 0))


## Rejects a duplicate salvage pickup. Returns true when it is newly collected.
func mark_collected(object_id: String) -> bool:
	if object_id == "" or collected_items.has(object_id):
		return false
	collected_items.append(object_id)
	return true


func is_collected(object_id: String) -> bool:
	return collected_items.has(object_id)


# ---------------------------------------------------------------- salvage

## Claims a salvage object. Duplicate pickups are refused, so this is safe to
## call on every interaction. Returns {"ok": bool, "material": String,
## "added": int, "message": String}.
func claim_salvage(object_id: String) -> Dictionary:
	if is_collected(object_id):
		return {"ok": false, "material": "", "added": 0, "message": "Already collected."}
	var entry: Dictionary = content.salvage.get(object_id, {}) as Dictionary
	if entry.is_empty():
		return {"ok": false, "material": "", "added": 0, "message": "Nothing here."}
	var material := String(entry.get("material", ""))
	var amount := int(entry.get("amount", 0))
	if inventory_free() < amount:
		return {"ok": false, "material": material, "added": 0, "message": "Carry limit reached."}
	var added := add_material(material, amount)
	if added <= 0:
		return {"ok": false, "material": material, "added": 0, "message": "Carry limit reached."}
	mark_collected(object_id)
	return {
		"ok": true,
		"material": material,
		"added": added,
		"message": "+%d %s" % [added, content.material_name(material)],
	}


## Repairs the crash-site power junction, spending the repair cost.
func can_repair_junction() -> bool:
	if has_flag(FLAG_POWER_REPAIRED):
		return false
	var cost := _repair_cost()
	for k in cost.keys():
		if not has_material(String(k), int(cost[k])):
			return false
	return true


func repair_cost_text() -> String:
	return _repair_cost_text(_repair_cost())


func repair_junction() -> Dictionary:
	if has_flag(FLAG_POWER_REPAIRED):
		return {"ok": false, "message": "The junction is already live."}
	var cost := _repair_cost()
	for k in cost.keys():
		if not has_material(String(k), int(cost[k])):
			return {"ok": false, "message": "Not enough materials. Need %s." % _repair_cost_text(cost)}
	for k in cost.keys():
		remove_material(String(k), int(cost[k]))
	set_flag(FLAG_POWER_REPAIRED)
	return {"ok": true, "message": "Power connection bridged."}


func _repair_cost() -> Dictionary:
	return content.repair_cost.duplicate(true)


func _repair_cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost.keys():
		parts.append("%d %s" % [int(cost[k]), content.material_name(String(k))])
	return ", ".join(parts)


# ---------------------------------------------------------------- memories

func view_memory(memory_id: String) -> bool:
	if memory_id == "" or viewed_memories.has(memory_id):
		return false
	viewed_memories.append(memory_id)
	# Keep the quest flag and the memory list in agreement, so either can be
	# used as the "has this been seen" test without drifting.
	set_flag(FLAG_MEMORY_VIEWED)
	return true


func has_viewed_memory(memory_id: String) -> bool:
	return viewed_memories.has(memory_id)


# ---------------------------------------------------------------- design

## The design is previewable at any time. Confirmation is the atomic commit:
## validate first, then store the manifest. Nothing is spent by previewing.
func confirm_design() -> Dictionary:
	if design == null:
		return {"ok": false, "errors": ["No design."]}
	var checks: Array = design.validate(content)
	for c in checks:
		var check: Dictionary = c
		if bool(check.get("blocking", true)) and not bool(check.get("ok", false)):
			return {"ok": false, "checks": checks, "errors": [String(check.get("message", ""))]}
	confirmed_design = design.to_dict()
	var s: Dictionary = design.summary(content)
	mission_manifest = {
		"ship": String(content.program.get("ship_name", "VELA")),
		"hull": String(content.hull.get("id", "standard_hull")),
		"slots": design.to_dict().get("slots", {}),
		"fuel_kg": design.fuel_kg,
		"mass_kg": s["wet_mass_kg"],
		"cost": s["cost"],
		"sensor_quality": s["sensor_quality"],
		"sensor_id": s["sensor_id"],
		"data_capture_mb": s["data_capture_mb"],
		"power_output_w": s["power_output_w"],
		"power_demand_w": s["power_demand_w"],
		"energy_stored_wh": s["energy_stored_wh"],
	}
	set_flag(FLAG_DESIGN_CONFIRMED)
	set_flag(FLAG_PREFLIGHT_PASSED)
	return {"ok": true, "checks": checks, "manifest": mission_manifest}


func has_confirmed_design() -> bool:
	return not confirmed_design.is_empty()


## Surviving science after the crash. A better sensor survives with more data,
## which Phase 2 can spend. Every valid configuration yields at least some.
func surviving_data_mb() -> float:
	var slots: Dictionary = confirmed_design.get("slots", {}) as Dictionary
	var sensor_id := String(slots.get("sensor", ""))
	if sensor_id == "":
		return 0.0
	var comp: Dictionary = content.component(sensor_id)
	var capture := float(comp.get("data_gain_mb", 0.0))
	var quality := int(comp.get("sensor_quality", 0))
	# The antenna survives partially; higher quality survives better.
	var keep := 0.45 + 0.15 * float(clampi(quality, 0, 3))
	return round(capture * clampf(keep, 0.0, 1.0))


## A small, always-positive salvage difference based on the launch manifest.
func crash_salvage_bonus() -> int:
	if confirmed_design.is_empty():
		return 0
	var s := design_summary_for_manifest()
	return 1 + int(float(s.get("sensor_quality", 0)))


func design_summary_for_manifest() -> Dictionary:
	if confirmed_design.is_empty():
		return {}
	var d = SFDesign.new()
	d.load_dict(confirmed_design)
	return d.summary(content)


# ---------------------------------------------------------------- save / load

func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"stage": stage,
		"chapter_id": chapter_id,
		"checkpoint_stage": checkpoint_stage,
		"checkpoint_chapter": checkpoint_chapter,
		"credits": credits,
		"design": design.to_dict() if design != null else {},
		"confirmed_design": confirmed_design.duplicate(true),
		"inventory": inventory.duplicate(true),
		"collected_items": collected_items.duplicate(),
		"flags": flags.duplicate(true),
		"viewed_memories": viewed_memories.duplicate(),
		"mission_manifest": mission_manifest.duplicate(true),
		"play_seconds": play_seconds,
	}


## Applies a save dictionary. Missing or unknown fields fall back to safe
## defaults rather than crashing. Negative values are clamped to zero.
## Returns a list of non-fatal warnings.
func apply_save_dict(data: Dictionary) -> Array:
	var warnings: Array = []
	reset_campaign()

	var saved_stage := String(data.get("stage", STAGE_MENU))
	if STAGE_ORDER.has(saved_stage):
		stage = saved_stage
	else:
		warnings.append("Unknown stage '%s'; starting from the briefing." % saved_stage)
		stage = STAGE_BRIEFING

	var saved_chapter := String(data.get("chapter_id", CHAPTER_PRESENT))
	if content.chapter(saved_chapter).is_empty():
		warnings.append("Unknown chapter '%s'; defaulting." % saved_chapter)
		saved_chapter = CHAPTER_PRESENT
	chapter_id = saved_chapter

	var cp_stage := String(data.get("checkpoint_stage", STAGE_BRIEFING))
	checkpoint_stage = cp_stage if STAGE_ORDER.has(cp_stage) else STAGE_BRIEFING
	var cp_chapter := String(data.get("checkpoint_chapter", CHAPTER_PRESENT))
	checkpoint_chapter = cp_chapter if not content.chapter(cp_chapter).is_empty() else CHAPTER_PRESENT

	credits = clampf(float(data.get("credits", content.program.get("start_credits", 100.0))), 0.0, 100000.0)

	var design_raw: Variant = data.get("design", {})
	design = SFDesign.new()
	if design_raw is Dictionary:
		design.load_dict(design_raw as Dictionary)
		_sanitise_design(design, warnings)

	var confirmed_raw: Variant = data.get("confirmed_design", {})
	if confirmed_raw is Dictionary:
		confirmed_design = (confirmed_raw as Dictionary).duplicate(true)

	var inv_raw: Variant = data.get("inventory", {})
	if inv_raw is Dictionary:
		for k in (inv_raw as Dictionary).keys():
			var amount := int((inv_raw as Dictionary)[k])
			if amount > 0:
				inventory[String(k)] = amount

	var items_raw: Variant = data.get("collected_items", [])
	if items_raw is Array:
		for item in (items_raw as Array):
			var id := String(item)
			if id != "" and not collected_items.has(id):
				collected_items.append(id)

	var flags_raw: Variant = data.get("flags", {})
	if flags_raw is Dictionary:
		for k in (flags_raw as Dictionary).keys():
			if bool((flags_raw as Dictionary)[k]):
				flags[String(k)] = true

	var mem_raw: Variant = data.get("viewed_memories", [])
	if mem_raw is Array:
		for m in (mem_raw as Array):
			var id := String(m)
			if id != "" and not viewed_memories.has(id):
				viewed_memories.append(id)

	var manifest_raw: Variant = data.get("mission_manifest", {})
	if manifest_raw is Dictionary:
		mission_manifest = (manifest_raw as Dictionary).duplicate(true)

	play_seconds = maxf(0.0, float(data.get("play_seconds", 0.0)))
	return warnings


func _sanitise_design(d, warnings: Array) -> void:
	for slot in SFDesign.SLOTS:
		var id := String(d.slot_component(String(slot)))
		if id == "":
			continue
		if not content.has_component(id):
			warnings.append("Unknown component '%s' in slot '%s'; clearing it." % [id, slot])
			d.clear_slot(String(slot))
		elif String(content.component(id).get("slot", "")) != String(slot):
			warnings.append("Component '%s' does not fit slot '%s'; clearing it." % [id, slot])
			d.clear_slot(String(slot))
	d.fuel_kg = clampf(d.fuel_kg, 0.0, float(content.hull.get("fuel_capacity_kg", 0.0)))
