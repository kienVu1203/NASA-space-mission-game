extends SceneTree
## STAR FALL logic tests: construction transactions, validation, inventory,
## salvage and save/load. No rendering and no input device required.
##
##   Godot --headless --path . --script res://tests/star_fall/test_logic.gd

const SFContent := preload("res://core/star_fall/sf_content.gd")
const SFDesign := preload("res://core/star_fall/sf_design.gd")
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const SFSave := preload("res://core/star_fall/sf_save.gd")
const SFDialogue := preload("res://core/star_fall/sf_dialogue.gd")
const SFMenu := preload("res://core/star_fall/sf_menu.gd")
const SFSites := preload("res://core/star_fall/sf_sites.gd")

var fails: int = 0
var checks_run: int = 0
var content
var test_save_path := "user://star_fall_test_save.json"


func check(label: String, ok: bool, detail: String = "") -> void:
	checks_run += 1
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1


func section(title: String) -> void:
	print("")
	print("-- " + title + " " + "-".repeat(maxi(0, 58 - title.length())))


func _init() -> void:
	content = SFContent.new()
	check("content loads", content.load_all())
	check("hull is present", not content.hull.is_empty())
	check("required slots listed", content.required_slots().size() == 5)
	check("propulsion has two options", content.components_for_slot("propulsion").size() == 2)
	check("power has two options", content.components_for_slot("power").size() == 2)
	check("sensor has at least two options", content.components_for_slot("sensor").size() >= 2)

	_test_validation()
	_test_viable_configurations()
	_test_atomic_confirmation()
	_test_inventory()
	_test_salvage_quest()
	_test_save_load()
	_test_corrupt_save()
	_test_dialogue_and_menu()
	_test_sites()

	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- helpers

func _blank_design() -> RefCounted:
	return SFDesign.new()


## The affordable viable build: light thruster, solar array, spectrometer.
func _viable_design_a() -> RefCounted:
	var d = _blank_design()
	d.set_slot("computer", "flight_computer_standard")
	d.set_slot("propulsion", "propulsion_light")
	d.set_slot("power", "power_solar_array")
	d.set_slot("communications", "comms_standard")
	d.set_slot("sensor", "sensor_spectrometer")
	d.fuel_kg = 200.0
	return d


## The heavy science build: heavy cluster, RTG cell, deep fields instrument.
func _viable_design_b() -> RefCounted:
	var d = _blank_design()
	d.set_slot("computer", "flight_computer_standard")
	d.set_slot("propulsion", "propulsion_heavy")
	d.set_slot("power", "power_rtg_cell")
	d.set_slot("communications", "comms_standard")
	d.set_slot("sensor", "sensor_deep_field")
	d.fuel_kg = 300.0
	return d


func _check_ids(checks: Array) -> Dictionary:
	var out: Dictionary = {}
	for c in checks:
		var check_entry: Dictionary = c
		out[String(check_entry.get("id", ""))] = check_entry
	return out


# ---------------------------------------------------------------- validation

func _test_validation() -> void:
	section("Preflight validation")

	var empty = _blank_design()
	check("empty design is invalid", not empty.is_valid(content))
	var empty_checks: Dictionary = _check_ids(empty.validate(content))
	check("empty design reports missing slots", not bool(empty_checks["slots"]["ok"]))
	check("empty design reports missing sensor", not bool(empty_checks["sensor"]["ok"]))
	check("empty design reports missing propulsion", not bool(empty_checks["mass"]["ok"]))
	check("empty design reports no fuel", not bool(empty_checks["fuel"]["ok"]))
	var first: Dictionary = empty.first_blocking_failure(content)
	check("first failure is actionable", String(first.get("hint", "")) != "", String(first.get("message", "")))

	# Low-gain sensor must be rejected on science quality, not mass.
	var low = _viable_design_a()
	low.set_slot("sensor", "sensor_low_gain")
	var low_checks: Dictionary = _check_ids(low.validate(content))
	check("low-gain sensor is rejected", not bool(low_checks["sensor"]["ok"]))
	check("low-gain rejection mentions quality", String(low_checks["sensor"]["message"]).findn("quality") >= 0)

	# Deep Fields on the solar array must fail on power, with the sensor-or-plant hint.
	var underpowered = _viable_design_a()
	underpowered.set_slot("propulsion", "propulsion_heavy")
	underpowered.set_slot("sensor", "sensor_deep_field")
	var power_checks: Dictionary = _check_ids(underpowered.validate(content))
	check("deep field on solar is rejected", not bool(power_checks["power"]["ok"]))
	check("power failure names a fix",
		String(power_checks["power"]["hint"]).findn("higher-output") >= 0,
		String(power_checks["power"]["hint"]))

	# Over-fueling the light thruster must fail on mass, not silently launch.
	var heavy_fuel = _viable_design_a()
	heavy_fuel.fuel_kg = 600.0
	var mass_checks: Dictionary = _check_ids(heavy_fuel.validate(content))
	check("over-fueled light build is rejected", not bool(mass_checks["mass"]["ok"]))
	check("mass failure names the propulsion limit",
		String(mass_checks["mass"]["message"]).findn("propulsion limit") >= 0,
		String(mass_checks["mass"]["message"]))

	# Insufficient fuel must fail independently of mass.
	var dry = _viable_design_a()
	dry.fuel_kg = 0.0
	var fuel_checks: Dictionary = _check_ids(dry.validate(content))
	check("no-fuel build is rejected", not bool(fuel_checks["fuel"]["ok"]))
	check("no-fuel build still passes mass", bool(fuel_checks["mass"]["ok"]))

	# Data capacity is informational and must never block a launch.
	var data_checks: Dictionary = _check_ids(_viable_design_a().validate(content))
	check("data check never blocks", not bool(data_checks["data"]["blocking"]))

	# Every check carries a player-facing message.
	var all_messages := true
	for c in _viable_design_a().validate(content):
		var entry: Dictionary = c
		if String(entry.get("message", "")) == "":
			all_messages = false
	check("all checks carry a message", all_messages)


func _test_viable_configurations() -> void:
	section("At least two viable configurations")

	var a = _viable_design_a()
	var b = _viable_design_b()
	check("configuration A passes preflight", a.is_valid(content))
	check("configuration B passes preflight", b.is_valid(content))

	var sa: Dictionary = a.summary(content)
	var sb: Dictionary = b.summary(content)
	check("A is cheaper than B", float(sa["cost"]) < float(sb["cost"]), "%d vs %d" % [int(sa["cost"]), int(sb["cost"])])
	check("A is lighter than B", float(sa["wet_mass_kg"]) < float(sb["wet_mass_kg"]))
	check("B carries better sensor quality", int(sb["sensor_quality"]) > int(sa["sensor_quality"]))
	check("both within budget", float(sa["cost"]) <= 100.0 and float(sb["cost"]) <= 100.0)
	check("fuel and mass are separate units",
		float(sa["fuel_kg"]) > 0.0 and float(sa["wet_mass_kg"]) == float(sa["dry_mass_kg"]) + float(sa["fuel_kg"]))
	check("power demand and energy are separate units",
		float(sa["power_demand_w"]) > 0.0 and float(sa["energy_stored_wh"]) > 0.0)


# ---------------------------------------------------------------- transactions

func _test_atomic_confirmation() -> void:
	section("Construction transactions")

	var campaign = SFCampaign.new()
	check("new campaign starts at the menu", campaign.stage == SFCampaign.STAGE_MENU)
	check("new campaign has the start budget", is_equal_approx(campaign.credits, 100.0))
	check("new campaign has no confirmed design", not campaign.has_confirmed_design())

	# Previewing a design must not spend credits or commit anything.
	campaign.design = _viable_design_a()
	var before_credits: float = campaign.credits
	var preview_summary: Dictionary = campaign.design.summary(content)
	var preview_checks: Array = campaign.design.validate(content)
	check("preview computes real numbers", float(preview_summary.get("wet_mass_kg", 0.0)) > 0.0)
	check("preview runs the checks", preview_checks.size() >= 6)
	check("preview does not spend credits", is_equal_approx(campaign.credits, before_credits))
	check("preview does not confirm a design", not campaign.has_confirmed_design())

	# An invalid design is refused and commits nothing.
	campaign.design = _blank_design()
	var rejected: Dictionary = campaign.confirm_design()
	check("invalid design is refused", not bool(rejected["ok"]))
	check("refusal reports errors", not (rejected.get("errors", []) as Array).is_empty())
	check("refused design is not stored", not campaign.has_confirmed_design())
	check("refusal sets no design flag", not campaign.has_flag(SFCampaign.FLAG_DESIGN_CONFIRMED))

	# A valid design commits exactly once and is stored intact.
	campaign.design = _viable_design_a()
	var accepted: Dictionary = campaign.confirm_design()
	check("valid design is accepted", bool(accepted["ok"]))
	check("accepted design is stored", campaign.has_confirmed_design())
	check("confirmation sets the design flag", campaign.has_flag(SFCampaign.FLAG_DESIGN_CONFIRMED))
	var manifest: Dictionary = campaign.mission_manifest
	check("manifest records the hull", String(manifest.get("hull", "")) == "standard_hull")
	check("manifest records wet mass", float(manifest.get("mass_kg", 0.0)) > 0.0)
	check("manifest records sensor quality", int(manifest.get("sensor_quality", 0)) == 2)
	check("manifest records fuel", is_equal_approx(float(manifest.get("fuel_kg", 0.0)), 200.0))

	# Re-confirming with a now-invalid design must not corrupt the stored manifest.
	campaign.design.set_slot("sensor", "")
	var refused: Dictionary = campaign.confirm_design()
	check("later invalid edit is refused", not bool(refused["ok"]))
	check("stored manifest survives a refused edit",
		String(campaign.mission_manifest.get("hull", "")) == "standard_hull")

	# Design-dependent crash consequences exist for every valid configuration.
	campaign.design = _viable_design_a()
	campaign.confirm_design()
	var data_a: float = campaign.surviving_data_mb()
	var bonus_a: int = campaign.crash_salvage_bonus()
	campaign.design = _viable_design_b()
	campaign.confirm_design()
	var data_b: float = campaign.surviving_data_mb()
	var bonus_b: int = campaign.crash_salvage_bonus()
	check("both configurations recover some data", data_a > 0.0 and data_b > 0.0)
	check("better science recovers more data", data_b > data_a, "%.0f vs %.0f" % [data_a, data_b])
	check("both configurations leave salvage", bonus_a > 0 and bonus_b > 0)


# ---------------------------------------------------------------- inventory

func _test_inventory() -> void:
	section("Inventory limits")

	var campaign = SFCampaign.new()
	check("inventory starts empty", campaign.inventory_used() == 0)
	check("inventory limit is positive", campaign.inventory_limit() > 0)

	var added: int = campaign.add_material("scrap_metal", 3)
	check("adds material", added == 3 and campaign.material_count("scrap_metal") == 3)
	check("negative quantities are refused", campaign.add_material("scrap_metal", -5) == 0)
	check("negative input does not reduce the stack", campaign.material_count("scrap_metal") == 3)

	# Fill to the limit, then check the excess is refused rather than clamped silently.
	var free: int = campaign.inventory_free()
	var over: int = campaign.add_material("polymer", free + 10)
	check("adding past the limit accepts only the free space", over == free, "%d of %d" % [over, free])
	check("inventory never exceeds its limit", campaign.inventory_used() == campaign.inventory_limit())
	check("refusing overflow leaves the stack unchanged", campaign.add_material("circuitry", 1) == 0)

	check("cannot remove more than held", not campaign.remove_material("scrap_metal", 99))
	check("failed removal leaves the stack", campaign.material_count("scrap_metal") == 3)
	check("removing the exact amount empties the stack", campaign.remove_material("scrap_metal", 3))
	check("emptied material is cleared", campaign.material_count("scrap_metal") == 0)
	check("unknown material reads as zero", campaign.material_count("unobtainium") == 0)


# ---------------------------------------------------------------- salvage

func _test_salvage_quest() -> void:
	section("Salvage and the Bill quest")

	var campaign = SFCampaign.new()
	var first: Dictionary = campaign.claim_salvage("salvage_plate")
	check("salvage grants its material", bool(first["ok"]) and campaign.material_count("scrap_metal") == 3)
	check("salvage marks the object collected", campaign.is_collected("salvage_plate"))
	var duplicate: Dictionary = campaign.claim_salvage("salvage_plate")
	check("duplicate pickup is refused", not bool(duplicate["ok"]))
	check("duplicate pickup adds nothing", campaign.material_count("scrap_metal") == 3)
	check("unknown salvage does nothing", not bool(campaign.claim_salvage("not_a_thing")["ok"]))

	# The junction cannot be repaired before the material exists.
	check("repair needs materials first", not campaign.can_repair_junction())
	var early: Dictionary = campaign.repair_junction()
	check("early repair is refused", not bool(early["ok"]))
	check("early repair spends nothing", campaign.material_count("scrap_metal") == 3)

	# Collecting the rest completes the repair exactly once.
	campaign.claim_salvage("salvage_circuit")
	check("repair becomes possible", campaign.can_repair_junction())
	var repair: Dictionary = campaign.repair_junction()
	check("repair succeeds", bool(repair["ok"]))
	check("repair sets the flag", campaign.has_flag(SFCampaign.FLAG_POWER_REPAIRED))
	check("repair spends scrap", campaign.material_count("scrap_metal") == 1)
	check("repair spends circuitry", campaign.material_count("circuitry") == 1)
	check("repair cannot run twice", not campaign.can_repair_junction())
	check("second repair is refused", not bool(campaign.repair_junction()["ok"]))

	# Stage flow and memory recording.
	campaign.advance_to(SFCampaign.STAGE_CRASH_SITE)
	check("advance enters the crash site", campaign.stage == SFCampaign.STAGE_CRASH_SITE)
	check("advance updates the chapter", campaign.chapter_id == SFCampaign.CHAPTER_CRASH)
	check("unknown stage is refused", not campaign.advance_to("not_a_stage"))

	check("memory starts unviewed", not campaign.has_viewed_memory(SFCampaign.MEMORY_GREEN_CITY))
	check("viewing a memory records it", campaign.view_memory(SFCampaign.MEMORY_GREEN_CITY))
	check("memory is now viewed", campaign.has_viewed_memory(SFCampaign.MEMORY_GREEN_CITY))
	check("viewing twice is a no-op", not campaign.view_memory(SFCampaign.MEMORY_GREEN_CITY))

	# Every stable id from the brief must exist in data.
	for chapter_id in ["present_day_earth", "crash_site", "forgotten_city", "silent_coast", "dawn_tower", "return_home"]:
		check("chapter id exists: " + chapter_id, not content.chapter(chapter_id).is_empty())
	check("green city memory exists", not content.memory(SFCampaign.MEMORY_GREEN_CITY).is_empty())


# ---------------------------------------------------------------- save / load

func _test_save_load() -> void:
	section("Save and load")

	SFSave.delete_save(test_save_path)
	check("no save until one is written", not SFSave.has_valid_save(test_save_path))

	var campaign = SFCampaign.new()
	campaign.advance_to(SFCampaign.STAGE_CRASH_SITE)
	campaign.design = _viable_design_a()
	campaign.confirm_design()
	campaign.add_material("scrap_metal", 4)
	campaign.add_material("polymer", 2)
	campaign.mark_collected("salvage_plate")
	campaign.set_flag(SFCampaign.FLAG_POWER_REPAIRED)
	campaign.set_flag(SFCampaign.FLAG_BILL_ACTIVE)
	campaign.view_memory(SFCampaign.MEMORY_GREEN_CITY)
	campaign.set_checkpoint(SFCampaign.STAGE_CRASH_SITE, SFCampaign.CHAPTER_CRASH)

	var write: Dictionary = SFSave.write_save(campaign, test_save_path)
	check("save writes", bool(write["ok"]), String(write.get("error", "")))
	check("save is valid", SFSave.has_valid_save(test_save_path))

	var loaded = SFCampaign.new()
	var result: Dictionary = SFSave.load_into(loaded, test_save_path)
	check("save loads", bool(result["ok"]))
	check("stage survives", loaded.stage == SFCampaign.STAGE_CRASH_SITE)
	check("chapter survives", loaded.chapter_id == SFCampaign.CHAPTER_CRASH)
	check("inventory survives", loaded.material_count("scrap_metal") == 4 and loaded.material_count("polymer") == 2)
	check("collected objects survive", loaded.is_collected("salvage_plate"))
	check("quest flags survive", loaded.has_flag(SFCampaign.FLAG_POWER_REPAIRED) and loaded.has_flag(SFCampaign.FLAG_BILL_ACTIVE))
	check("viewed memories survive", loaded.has_viewed_memory(SFCampaign.MEMORY_GREEN_CITY))
	check("checkpoint stage survives", loaded.checkpoint_stage == SFCampaign.STAGE_CRASH_SITE)
	check("design survives", loaded.design.slot_component("sensor") == "sensor_spectrometer")
	check("confirmed design survives", loaded.has_confirmed_design())
	check("manifest survives", int(loaded.mission_manifest.get("sensor_quality", 0)) == 2)

	# Loading a save must not duplicate inventory or collected ids.
	var second_load: Dictionary = SFSave.load_into(loaded, test_save_path)
	check("reloading replaces rather than merges", bool(second_load["ok"]))
	check("reload does not duplicate inventory", loaded.material_count("scrap_metal") == 4)
	var collected_count := 0
	for item in loaded.collected_items:
		if String(item) == "salvage_plate":
			collected_count += 1
	check("reload does not duplicate collected ids", collected_count == 1)

	SFSave.delete_save(test_save_path)


func _test_corrupt_save() -> void:
	section("Corrupted saves")

	# A truncated document must be reported, never silently accepted.
	var f := FileAccess.open(test_save_path, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"stage\": ")
	f.close()
	var read_corrupt: Dictionary = SFSave.read_save(test_save_path)
	check("corrupt save is detected", String(read_corrupt["status"]) == SFSave.LOAD_CORRUPT)

	# Loading a corrupt save must leave the live campaign untouched.
	var campaign = SFCampaign.new()
	campaign.advance_to(SFCampaign.STAGE_CONSTRUCTION)
	campaign.add_material("scrap_metal", 2)
	var before_stage: String = campaign.stage
	var load_corrupt: Dictionary = SFSave.load_into(campaign, test_save_path)
	check("corrupt load fails", not bool(load_corrupt["ok"]))
	check("corrupt load preserves the campaign", campaign.stage == before_stage)
	check("corrupt load preserves inventory", campaign.material_count("scrap_metal") == 2)
	check("corrupt save is not deleted", FileAccess.file_exists(test_save_path))

	# An empty file counts as corrupt.
	var empty_file := FileAccess.open(test_save_path, FileAccess.WRITE)
	empty_file.store_string("")
	empty_file.close()
	check("empty save is corrupt", String(SFSave.read_save(test_save_path)["status"]) == SFSave.LOAD_CORRUPT)

	# A document from a newer schema is reported separately, not parsed blindly.
	var newer := FileAccess.open(test_save_path, FileAccess.WRITE)
	newer.store_string("{\"version\": 999, \"stage\": \"crash_site\"}")
	newer.close()
	check("newer save version is flagged", String(SFSave.read_save(test_save_path)["status"]) == SFSave.LOAD_VERSION)

	# Salvage payloads are sanitised: unknown components are dropped, not trusted.
	var dubious := {
		"version": 1,
		"stage": "construction",
		"chapter_id": "present_day_earth",
		"credits": -50.0,
		"design": {"slots": {"sensor": "not_a_real_part", "computer": "comms_standard"}, "fuel_kg": -400.0},
		"inventory": {"scrap_metal": -3, "polymer": 2},
	}
	var sanitised = SFCampaign.new()
	var warnings: Array = sanitised.apply_save_dict(dubious)
	check("sanitiser reports warnings", not warnings.is_empty())
	check("negative credits are clamped", sanitised.credits >= 0.0)
	check("negative fuel is clamped", sanitised.design.fuel_kg >= 0.0)
	check("negative inventory is dropped", sanitised.material_count("scrap_metal") == 0)
	check("valid inventory is kept", sanitised.material_count("polymer") == 2)
	check("unknown component is cleared", sanitised.design.slot_component("sensor") == "")
	check("mismatched component is cleared", sanitised.design.slot_component("computer") == "")

	SFSave.delete_save(test_save_path)


# ---------------------------------------------------------------- small models

func _test_dialogue_and_menu() -> void:
	section("Dialogue and menu models")

	var dialogue = SFDialogue.new(["First", "Second"])
	check("dialogue starts on the first line", dialogue.current_text() == "First")
	dialogue.chars = 999.0
	check("line completes", dialogue.is_line_complete())
	check("advance moves to the next line", not dialogue.advance())
	check("second line is current", dialogue.current_text() == "Second")
	dialogue.chars = 999.0
	check("advancing past the last line finishes", dialogue.advance())

	var fast = SFDialogue.new(["abcdefghij"])
	fast.tick(10.0)
	check("typewriter respects the tick", fast.is_line_complete() or fast.visible_text().length() > 0)

	var menu = SFMenu.new()
	menu.set_items([
		{"id": "a", "label": "A", "enabled": true},
		{"id": "b", "label": "B", "enabled": false},
		{"id": "c", "label": "C", "enabled": true},
	])
	menu.move_enabled(1)
	check("menu skips disabled items", menu.current_id() == "c", menu.current_id())
	menu.move_enabled(1)
	check("menu wraps past the end", menu.current_id() == "a")
	menu.move_enabled(-1)
	check("menu skips disabled items backwards", menu.current_id() == "c")
	check("menu reports disabled state", not menu.items[1]["enabled"])


func _test_sites() -> void:
	section("Authored world data")
	var sites = SFSites.new()
	check("sites load", sites.load_all())
	var spaceport: Dictionary = sites.site("spaceport")
	var crash: Dictionary = sites.site("crash_site")
	check("spaceport exists", not spaceport.is_empty())
	check("crash site exists", not crash.is_empty())

	var ids: Array = []
	for p in spaceport.get("props", []) as Array:
		var prop: Dictionary = p
		if prop.has("interact"):
			ids.append(String(prop["interact"]))
	check("spaceport has a briefing terminal", ids.has("briefing"))
	check("spaceport has a construction console", ids.has("construction"))
	check("spaceport has the VELA frame", ids.has("vela"))
	check("spaceport has a launch point", ids.has("launch"))
	check("Bill is not present on Earth", not ids.has("bill_body"))

	var crash_ids: Array = []
	for p in crash.get("props", []) as Array:
		var prop: Dictionary = p
		if prop.has("interact"):
			crash_ids.append(String(prop["interact"]))
	check("crash site has the wreck", crash_ids.has("crash_vela"))
	check("crash site has the junction", crash_ids.has("power_connection"))
	check("crash site has Bill", crash_ids.has("bill_body"))
	check("crash site has salvage", crash_ids.has("salvage_plate") and crash_ids.has("salvage_circuit") and crash_ids.has("salvage_polymer"))

	# Every interactable must have a matching definition in content.
	var missing_definitions: Array = []
	for object_id in crash_ids:
		var key := String(object_id)
		if key.begins_with("salvage") or key == "scrap_extra":
			if not content.salvage.has(key):
				missing_definitions.append(key)
		elif content.site_item_name(key) == key:
			missing_definitions.append(key)
	check("every crash-site interactable has content", missing_definitions.is_empty(), str(missing_definitions))
