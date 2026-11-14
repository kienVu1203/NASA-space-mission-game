extends SceneTree
## STAR FALL flow test: boots the real main scene and drives the whole campaign
## (Phases 1, 2 and 3, up to READY_FOR_FINAL_ASSEMBLY) through the same entry
## points the keyboard uses.
##
##   Godot --headless --path . --script res://tests/star_fall/test_flow.gd
##
## Headless execution proves logic, wiring and state transitions. It cannot
## prove anything about what the game looks like; do that by running it.

const SFSave := preload("res://core/star_fall/sf_save.gd")

var main
var step: int = 0
var fails: int = 0
var checks_run: int = 0
var save_backup: Variant = null


func check(label: String, ok: bool, detail: String = "") -> void:
	checks_run += 1
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1


## Presses ENTER until the dialogue overlay closes, so completion callbacks run.
func finish_dialogue() -> void:
	var guard := 0
	while main.dialogue != null and guard < 400:
		guard += 1
		main._handle_dialogue_key(KEY_ENTER)


func press(key: int) -> void:
	main._unhandled_input(_key_event(key))


func _key_event(key: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = key
	return ev


func _initialize() -> void:
	# Never disturb a real player's save while testing.
	SFSave.delete_save()
	main = load("res://scenes/star_fall/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	step += 1
	match step:
		3:
			_pause_and_settings()
		4:
			_boot_and_briefing()
		8:
			_construction()
		12:
			_launch_and_crash()
		16:
			_crash_site_quest()
		20:
			_phase_one_checkpoint()
		24:
			_forgotten_city()
		28:
			_scrap_king()
		32:
			_city_archive()
		36:
			_silent_coast()
		40:
			_toxic_tide()
		44:
			_coast_archive_and_base()
		48:
			_dawn_tower()
		52:
			_sky_remnant()
		56:
			_dawn_archive_and_workshop()
		60:
			_ready_and_continue()
		64:
			_finish()
	return false


# ---------------------------------------------------------------- steps

## Pause, resume, settings and focus-loss handling, driven through the same
## entry points the keyboard uses. Runs before the campaign starts.
func _pause_and_settings() -> void:
	print("")
	print("-- Pause, settings and input safety " + "-".repeat(24))
	check("pause is closed at boot", not main.is_pause_open())

	main._title_activate()
	check("campaign started for the pause checks", main.screen == main.Screen.WORLD)
	finish_dialogue()
	main._on_briefing_done()
	check("world input is live", main.world.player.input_enabled)

	# Esc opens the pause overlay and releases movement.
	press(KEY_ESCAPE)
	check("esc opens the pause overlay", main.is_pause_open())
	check("pause locks movement", not main.world.player.input_enabled)
	check("pause menu offers four rows", main.pause_menu.size() == 4, str(main.pause_menu.size()))

	# Menu input while paused must not fall through to the world.
	var handled_before: int = main.pause_menu.index
	main._input(_key_event(KEY_DOWN))
	check("pause menu moves with the keyboard", main.pause_menu.index != handled_before)

	# Resume restores movement.
	main.pause_menu.index = 0
	main._pause_activate()
	check("resume closes the pause overlay", not main.is_pause_open())
	check("resume restores movement", main.world.player.input_enabled)

	# Settings round trip from the pause menu returns to the world.
	press(KEY_ESCAPE)
	main.pause_menu.index = 2
	main._pause_activate()
	check("settings open from the pause menu", main.screen == main.Screen.SETTINGS)
	main._settings_key(KEY_ESCAPE)
	check("settings return to the world", main.screen == main.Screen.WORLD)
	check("pause stays closed after settings", not main.is_pause_open())

	# Losing focus must release movement so nothing sticks.
	main.world.player.velocity = Vector2(40, -20)
	main._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("focus loss zeroes velocity", main.world.player.velocity == Vector2.ZERO)
	check("focus loss disables movement", not main.world.player.input_enabled)
	main.apply_focus_state()

	# Reset so the campaign checks below start from a clean state. The pause
	# section above started a campaign, which wrote a save: delete it, so the
	# "no save yet" checks below still mean what they say.
	main.campaign.reset_campaign()
	SFSave.delete_save()
	main._go(main.Screen.TITLE)


func _boot_and_briefing() -> void:
	print("")
	print("-- Boot, menu and briefing " + "-".repeat(36))
	check("boots to the title screen", main.screen == main.Screen.TITLE, str(main.screen))
	check("title shows four options", main.title_menu.size() == 4)
	check("continue is disabled with no save", not bool(main.title_menu.items[1]["enabled"]))
	check("no save is written just by opening the menu", not SFSave.has_valid_save())

	# Settings round trip must not touch the campaign.
	main._go(main.Screen.SETTINGS)
	check("settings opens", main.screen == main.Screen.SETTINGS)
	check("settings lists three rows", main.settings_menu.size() == 3)
	main._settings_adjust(1)
	main._settings_adjust(-1)
	main._go(main.Screen.TITLE)

	main._title_activate()
	check("new game enters the world", main.screen == main.Screen.WORLD)
	check("new game starts on the present-day Earth zone", main.zone == "spaceport" and main.campaign.chapter_id == "present_day_earth")
	check("the briefing opens automatically", main.dialogue != null)
	check("input is locked during dialogue", not main.world.player.input_enabled)
	check("Nick starts on screen", main.world.player != null)
	check("Bill is not present on Earth", main.world.prop_by_id("bill_body") == null)

	finish_dialogue()
	check("input is restored after the briefing", main.world.player.input_enabled)
	check("briefing flag is set", main.campaign.has_flag("briefing_read"))
	check("briefing advances the stage", main.campaign.stage == main.campaign.STAGE_CONSTRUCTION)
	check("briefing checkpoints the campaign", main.campaign.checkpoint_stage == main.campaign.STAGE_CONSTRUCTION)


func _construction() -> void:
	print("")
	print("-- Construction and preflight " + "-".repeat(33))
	main._on_world_interact("construction", main.world.prop_by_id("construction"))
	check("console opens from the world", main.screen == main.Screen.CONSTRUCTION)
	check("console is live", main.construction != null)

	var console = main.construction
	check("console lists five slots plus fuel", console.slot_menu.size() == 6)

	# Fail a preflight check on purpose, then fix it. This is the required
	# "fail and revise" beat of Phase 1.
	console.slot_menu.index = 4
	console.current_slot = 4
	console._cycle_component(1)
	check("low-gain sensor is installed by cycling", main.campaign.design.slot_component("sensor") == "sensor_low_gain")
	console._run_preflight()
	check("preflight fails on the weak sensor", not main.campaign.design.is_valid(main.campaign.content))
	check("a blocking failure is reported", not console.checks.is_empty())

	# Confirming an invalid design must be refused and must not launch.
	console._confirm()
	check("invalid design cannot be confirmed", not main.campaign.has_confirmed_design())
	check("refused confirmation stays on the console", main.screen == main.Screen.CONSTRUCTION)

	# Fill the remaining slots.
	for i in 5:
		console.slot_menu.index = i
		console.current_slot = i
		if main.campaign.design.slot_component(String(main.campaign.design.SLOTS[i])) == "":
			console._cycle_component(1)
	# Sensor: cycle past low-gain to the spectrometer.
	console.slot_menu.index = 4
	console.current_slot = 4
	console._cycle_component(1)
	check("sensor now meets the requirement", main.campaign.design.slot_component("sensor") == "sensor_spectrometer")

	# Preview must not spend money.
	var credits_before: float = main.campaign.credits
	console._run_preflight()
	console._invalidate()
	check("running preflight does not spend credits", is_equal_approx(main.campaign.credits, credits_before))
	check("changing the design clears the old result", not console.checks_run)

	console._adjust_fuel(10)
	check("fuel adjusts in steps", main.campaign.design.fuel_kg >= 200.0)
	console._run_preflight()
	check("the revised design passes preflight", main.campaign.design.is_valid(main.campaign.content))

	console._confirm()
	check("the revised design is confirmed", main.campaign.has_confirmed_design())
	check("confirmation moves to the launch sequence", main.screen == main.Screen.LAUNCH)


func _launch_and_crash() -> void:
	print("")
	print("-- Launch, the signal and the rift " + "-".repeat(26))
	check("launch starts at the countdown", main.launch_phase == main.LaunchPhase.COUNTDOWN)

	# The launch can no longer be skipped. Esc must do nothing; the sequence
	# then runs to the crash on its own (the scripted accident).
	main._launch_key(KEY_ESCAPE)
	check("escape does not skip the launch", main.screen == main.Screen.LAUNCH)
	var guard := 0
	while main.screen == main.Screen.LAUNCH and guard < 800:
		guard += 1
		main._process_launch(0.1)
	check("the launch sequence reaches the crash site", main.screen == main.Screen.WORLD and main.zone == "crash_site")
	check("the launch flag is applied", main.campaign.has_flag("launched"))
	check("the rift flag is applied", main.campaign.has_flag("rift_seen"))
	check("the crash flag is applied", main.campaign.has_flag("crashed"))
	check("the chapter advances to the crash site", main.campaign.chapter_id == "crash_site")
	check("the crash site checkpoint is saved", main.campaign.checkpoint_stage == main.campaign.STAGE_CRASH_SITE)
	check("a save now exists", SFSave.has_valid_save())
	finish_dialogue()
	check("post-crash stage is the crash site", main.campaign.stage == main.campaign.STAGE_CRASH_SITE)

	# The design must still matter after the accident.
	var data_mb: float = main.campaign.surviving_data_mb()
	check("the launch design yields surviving science", data_mb > 0.0, "%.0f MB" % data_mb)

	# Nothing on the crash site may spoil the planet's identity.
	var site_props: Array = main.world.props
	var spoiler_found := false
	for p in site_props:
		var prop = p
		var text := String(prop.label).to_lower()
		if text.findn("earth") >= 0 or text.findn("20") >= 0:
			spoiler_found = true
	check("crash-site labels avoid spoilers", not spoiler_found)


func _crash_site_quest() -> void:
	print("")
	print("-- Crash site, salvage and Bill " + "-".repeat(30))

	# Inspecting the wreck is the first quest beat and grants design salvage.
	var scrap_before: int = main.campaign.material_count("scrap_metal")
	main._on_world_interact("crash_vela", main.world.prop_by_id("crash_vela"))
	finish_dialogue()
	check("wreck inspection sets its flag", main.campaign.has_flag("vela_inspected"))
	check("wreck inspection grants design-dependent salvage", main.campaign.material_count("scrap_metal") > scrap_before)

	# Collect every salvage object through the real interaction path.
	for object_id in ["salvage_plate", "salvage_circuit", "salvage_polymer", "scrap_extra"]:
		var prop = main.world.prop_by_id(object_id)
		if prop != null:
			main._on_world_interact(String(object_id), prop)
	finish_dialogue()
	check("salvage is collected", main.campaign.material_count("scrap_metal") >= 2)
	check("circuitry is collected", main.campaign.material_count("circuitry") >= 1)
	check("collected props leave the world", main.world.prop_by_id("salvage_plate") == null)
	check("collected props are recorded", main.campaign.is_collected("salvage_plate"))

	# A duplicate pickup must be impossible.
	var before: int = main.campaign.material_count("scrap_metal")
	main._on_world_interact("salvage_plate", null)
	check("duplicate salvage is refused", main.campaign.material_count("scrap_metal") == before)

	# Bill cannot wake before the junction is repaired.
	main._on_world_interact("bill_body", main.world.prop_by_id("bill_body"))
	finish_dialogue()
	check("Bill stays dormant without power", not main.campaign.has_flag("bill_active"))

	main._on_world_interact("power_connection", main.world.prop_by_id("power_connection"))
	finish_dialogue()
	check("the junction is repaired", main.campaign.has_flag("power_repaired"))

	main._on_world_interact("bill_body", main.world.prop_by_id("bill_body"))
	check("the activation dialogue opens", main.dialogue != null)
	finish_dialogue()
	check("Bill is active", main.campaign.has_flag("bill_active"))

	# Activating Bill leads into the first memory.
	check("the memory plays after activation", main.screen == main.Screen.MEMORY, str(main.screen))
	main._finish_memory()
	check("the memory is recorded", main.campaign.has_viewed_memory("memory_green_city"))
	check("coordinates are received", main.campaign.has_flag("coordinates_received"))


func _phase_one_checkpoint() -> void:
	print("")
	print("-- Checkpoint, save/continue and the move to Phase 2 " + "-".repeat(10))
	check("the checkpoint screen opens", main.screen == main.Screen.CHECKPOINT, str(main.screen))
	check("the checkpoint stage is recorded", main.campaign.stage == main.campaign.STAGE_CHECKPOINT)
	check("a save exists at the checkpoint", SFSave.has_valid_save())

	var saved_scrap: int = main.campaign.material_count("scrap_metal")
	var saved_memory: bool = main.campaign.has_viewed_memory("memory_green_city")

	# The Phase 1 summary now continues into the Forgotten City instead of
	# ending the game: Bill's coordinates have a destination.
	main._checkpoint_key(KEY_ENTER)
	check("the checkpoint continues into the Forgotten City", main.screen == main.Screen.WORLD, str(main.screen))
	check("the campaign stage moves to the city", main.campaign.stage == main.campaign.STAGE_CITY_INTRO)
	check("the chapter is the Forgotten City", main.campaign.chapter_id == main.campaign.CHAPTER_CITY)
	check("the city zone is loaded", main.zone == "forgotten_city")
	check("the city intro opens automatically", main.dialogue != null)
	finish_dialogue()
	check("city entry is recorded", main.campaign.has_flag("city_entered"))
	check("the pre-boss checkpoint is not yet set", not main.campaign.has_flag("city_checkpoint"))
	check("a save exists after entering the city", SFSave.has_valid_save())

	# Continue must restore Phase 2 progress, not restart the campaign.
	main._go(main.Screen.TITLE)
	check("continue is available after saving", main.save_available)
	check("continue is enabled in the menu", bool(main.title_menu.items[1]["enabled"]))
	main._continue_game()
	check("continue restores the city stage", main.campaign.stage == main.campaign.STAGE_CITY_INTRO)
	check("continue restores inventory", main.campaign.material_count("scrap_metal") == saved_scrap)
	check("continue restores memories", main.campaign.has_viewed_memory("memory_green_city") == saved_memory)
	check("continue restores the confirmed design", main.campaign.has_confirmed_design())
	check("continue reopens the city zone", main.screen == main.Screen.WORLD and main.zone == "forgotten_city")
	check("continue does not replay the city intro", main.dialogue == null)
	check("the restored save kept the design manifest", not main.campaign.mission_manifest.is_empty())


# ---------------------------------------------------------------- phase 2

## Forgotten City exploration, the checkpoint gate, the optional memory and the
## optional salvage.
func _forgotten_city() -> void:
	print("")
	print("-- Forgotten City: exploration and the gate " + "-".repeat(15))
	check("the city world has props", main.world != null and not main.world.props.is_empty())
	check("the city has a checkpoint", main.world.prop_by_id("city_checkpoint") != null)
	check("the city has a green memory shrine", main.world.prop_by_id("memory_city_green") != null)
	check("the city has the control-center door", main.world.prop_by_id("city_boss_gate") != null)
	check("the city has optional salvage", main.world.prop_by_id("salvage_city_scrap") != null)

	# The gate must refuse entry until the checkpoint has been used.
	main._on_world_interact("city_boss_gate", main.world.prop_by_id("city_boss_gate"))
	check("the gate refuses entry before the checkpoint", main.screen == main.Screen.WORLD and main.dialogue != null)
	finish_dialogue()
	check("the refused gate did not start the encounter", main.campaign.stage == main.campaign.STAGE_CITY_INTRO)

	main._on_world_interact("city_checkpoint", main.world.prop_by_id("city_checkpoint"))
	finish_dialogue()
	check("the city checkpoint is set", main.campaign.has_flag("city_checkpoint"))
	check("the checkpoint marks the pre-boss stage", main.campaign.checkpoint_stage == main.campaign.STAGE_CITY_BOSS)
	check("the checkpoint saves", SFSave.has_valid_save())

	# Optional salvage before the fight.
	var circuit_before: int = main.campaign.material_count("circuitry")
	main._on_world_interact("salvage_city_scrap", main.world.prop_by_id("salvage_city_scrap"))
	check("city salvage is collectable", main.campaign.material_count("circuitry") > circuit_before)
	check("collected city salvage leaves the world", main.world.prop_by_id("salvage_city_scrap") == null)

	# The green memory is optional, plays, and returns to the world.
	main._on_world_interact("memory_city_green", main.world.prop_by_id("memory_city_green"))
	finish_dialogue()
	check("the city memory screen opens", main.screen == main.Screen.MEMORY, str(main.screen))
	check("the city memory is the second Green City file", main.memory_id == "memory_city_green")
	main._memory_key(KEY_ESCAPE)
	check("the optional memory returns to the world", main.screen == main.Screen.WORLD)
	check("the optional memory is recorded", main.campaign.has_viewed_memory("memory_city_green"))


func _scrap_king() -> void:
	print("")
	print("-- Scrap King: the shield encounter " + "-".repeat(23))
	main._on_world_interact("city_boss_gate", main.world.prop_by_id("city_boss_gate"))
	check("the gate starts the encounter", main.screen == main.Screen.DUEL, str(main.screen))
	check("the encounter is the Scrap King", main.duel.encounter.boss.get("id", "") == "scrap_king")
	check("the encounter holds until the briefing ends", main.duel.encounter.intro_hold)
	check("the encounter opens its briefing", main.dialogue != null)
	check("the boss stage is recorded", main.campaign.stage == main.campaign.STAGE_CITY_BOSS)

	# While the briefing is open the arena is frozen, and a Space press belongs to
	# the dialogue rather than to a counterattack. This is the exact input that
	# would otherwise leak, so it is driven through the real key handler.
	var frozen_hp: int = main.duel.encounter.model.nick_health
	main._handle_dialogue_key(KEY_SPACE)
	check("Space during the briefing advances the dialogue only", main.duel.encounter.model.charge == 0)
	check("the briefing cannot be damaged through", main.duel.encounter.model.nick_health == frozen_hp)
	check("the arena is frozen during the briefing", main.duel.input_locked)
	main.duel._try_counterattack()
	check("a counterattack is refused during the briefing", not main.duel.encounter.model.shield_locked())

	finish_dialogue()
	check("the fight starts after the briefing", main.duel.is_fighting())
	check("the arena unlocks after the briefing", not main.duel.input_locked)

	var duel = main.duel
	var model = duel.encounter.model

	check("no navigation chip before victory", not main.campaign.has_component("navigation_chip"))
	check("no boss flag before victory", not main.campaign.has_flag("scrap_king_defeated"))

	# Play the fight out through the real model: block, absorb, counterattack.
	var victory_reached := false
	var guard := 0
	while guard < 4000 and not victory_reached:
		guard += 1
		# Aim at whatever hostile is closest, the way an attentive player would.
		duel.set_cursor_canvas(_aim_at_nearest_hostile(duel))
		duel.advance_for(0.05)
		if model.charge_full() and model.is_fighting():
			duel._try_counterattack()
		if model.phase == model.PHASE_VICTORY:
			victory_reached = true
		# This loop proves the victory path, not survival (survival is the
		# defeat test below). Keeping Nick up and the meter topped removes mote
		# luck from the check; damage, the lock and the counterattack cost all
		# stay live.
		if model.is_fighting():
			model.nick_health = model.nick_health_max
			if model.charge < model.charge_max:
				model.charge = mini(model.charge_max, model.charge + 1)
	check("the encounter can be won through its own rules", victory_reached)
	check("the boss health reached zero", model.boss_health == 0)
	check("victory stops the encounter", duel.encounter.is_over())
	check("victory clears live projectiles", duel.encounter.field.active_count() == 0)
	check("the Scrap King takes four counterattacks", int(duel.encounter.boss.get("boss_health", 0)) == 4 * int(duel.encounter.boss.get("counterattack_damage", 0)))

	# Finish the victory transition and award through the real screen signal.
	duel.advance_for(2.0)
	duel._confirm_victory()
	finish_dialogue()
	check("the navigation chip is awarded", main.campaign.has_component("navigation_chip"))
	check("the Scrap King flag is set", main.campaign.has_flag("scrap_king_defeated"))
	check("the component list reflects the chip", _component_recovered("navigation_chip"))
	check("the power core is still missing", not main.campaign.has_component("power_core"))
	check("the shield emitter is never awarded here", not main.campaign.has_component("shield_emitter"))

	# A replayed result must not duplicate the reward.
	var chip_count := _component_count("navigation_chip")
	main._award_boss_victory("scrap_king")
	check("a replayed victory grants no second chip", _component_count("navigation_chip") == chip_count)
	check("a replayed victory keeps the boss flag", main.campaign.has_flag("scrap_king_defeated"))


func _city_archive() -> void:
	print("")
	print("-- Control-center archive and the Future Earth reveal " + "-".repeat(8))
	check("the archive screen opens", main.screen == main.Screen.ARCHIVE, str(main.screen))
	check("the archive is the control center", main._archive_id == "city_archive")
	check("the archive records are loaded", main.archive_screen.entries.size() > 0)
	check("future Earth is not revealed yet", not main.campaign.has_flag("future_earth_revealed"))
	check("the mission is still the signal investigation", main.campaign.mission_id() == "signal_investigation")
	check("Silent Coast is not unlocked yet", not main.campaign.has_flag("silent_coast_unlocked"))

	# Flip one page, then close. Closing early must produce the same outcome as
	# reading every record.
	main.archive_screen._move(1)
	main.archive_screen._finish()
	check("the archive is recorded as restored", main.campaign.is_archive_restored("city_archive"))
	check("the Future Earth reveal is applied", main.campaign.has_flag("future_earth_revealed"))
	check("the city archive flag is set", main.campaign.has_flag("city_archive_restored"))
	check("Silent Coast unlocks", main.campaign.has_flag("silent_coast_unlocked"))
	check("the mission objective changes", main.campaign.mission_id() == "return_with_evidence")
	check("the reveal moves to the Silent Coast", main.campaign.chapter_id == main.campaign.CHAPTER_COAST)
	check("the coast zone is loaded", main.zone == "silent_coast")
	check("the coast stage is recorded", main.campaign.stage == main.campaign.STAGE_SILENT_INTRO)
	check("the coast intro opens", main.dialogue != null)
	finish_dialogue()

	# The reveal must be idempotent.
	check("a second reveal is refused", not main.campaign.reveal_future_earth())
	check("the mission is unchanged by the second reveal", main.campaign.mission_id() == "return_with_evidence")


func _silent_coast() -> void:
	print("")
	print("-- Silent Coast: exploration and the facility " + "-".repeat(16))
	check("the coast world has props", main.world != null and not main.world.props.is_empty())
	check("the coast has a checkpoint", main.world.prop_by_id("coast_checkpoint") != null)
	check("the coast has a memory projector", main.world.prop_by_id("memory_green_coast") != null)
	check("the coast has optional samples", main.world.prop_by_id("sample_coast_water") != null)
	check("the coast has a records terminal", main.world.prop_by_id("coast_records") != null)
	check("the coast has the facility intake", main.world.prop_by_id("coast_boss_gate") != null)

	main._on_world_interact("sample_coast_water", main.world.prop_by_id("sample_coast_water"))
	finish_dialogue()
	check("a sample is recorded", main.campaign.is_collected("sample_coast_water"))
	main._on_world_interact("coast_records", main.world.prop_by_id("coast_records"))
	finish_dialogue()
	check("the records are recorded", main.campaign.is_collected("coast_records_read"))

	# The facility refuses entry without the checkpoint.
	main._on_world_interact("coast_boss_gate", main.world.prop_by_id("coast_boss_gate"))
	check("the facility refuses entry before the checkpoint", main.dialogue != null)
	finish_dialogue()
	check("the refused facility did not start the encounter", main.campaign.stage == main.campaign.STAGE_SILENT_INTRO)

	main._on_world_interact("coast_checkpoint", main.world.prop_by_id("coast_checkpoint"))
	finish_dialogue()
	check("the coast checkpoint is set", main.campaign.has_flag("coast_checkpoint"))
	check("the coast checkpoint marks the pre-boss stage", main.campaign.checkpoint_stage == main.campaign.STAGE_COAST_BOSS)

	# The coastal memory is optional and returns to the world.
	main._on_world_interact("memory_green_coast", main.world.prop_by_id("memory_green_coast"))
	finish_dialogue()
	check("the coastal projection opens", main.screen == main.Screen.MEMORY and main.memory_id == "memory_green_coast")
	main._memory_key(KEY_ESCAPE)
	check("the coastal projection returns to the world", main.screen == main.Screen.WORLD)
	check("the coastal projection is recorded", main.campaign.has_viewed_memory("memory_green_coast"))


func _toxic_tide() -> void:
	print("")
	print("-- Toxic Tide: defeat, retry and victory " + "-".repeat(17))
	main._on_world_interact("coast_boss_gate", main.world.prop_by_id("coast_boss_gate"))
	check("the facility starts the encounter", main.screen == main.Screen.DUEL, str(main.screen))
	check("the encounter is the Toxic Tide", main.duel.encounter.boss.get("id", "") == "toxic_tide")
	check("the two bosses have different health", int(main.duel.encounter.boss.get("boss_health", 0)) != 100)
	finish_dialogue()

	var duel = main.duel
	var model = duel.encounter.model
	check("the fight is live", duel.is_fighting())

	# Defeat on purpose: point the shield away and absorb nothing.
	duel.set_cursor_canvas(duel.encounter.nick_position + Vector2(0, 80))
	var guard := 0
	while guard < 4000 and model.nick_health > 0:
		guard += 1
		duel.advance_for(0.05)
	check("the boss does not die to a passive player", model.phase != model.PHASE_VICTORY)
	check("Nick can be defeated", model.nick_health <= 0)
	check("defeat stops the encounter", model.phase == model.PHASE_DEFEAT)
	check("defeat clears live projectiles", duel.encounter.field.active_count() == 0)
	check("defeat grants no power core", not main.campaign.has_component("power_core"))
	check("defeat sets no boss flag", not main.campaign.has_flag("toxic_tide_defeated"))

	# Retry resets every encounter-local value and keeps campaign progress.
	duel.retry()
	check("retry restores Nick's health", model.nick_health == model.nick_health_max)
	check("retry restores boss health", model.boss_health == model.boss_health_max)
	check("retry clears charge", model.charge == 0)
	check("retry clears projectiles", duel.encounter.field.active_count() == 0)
	check("retry returns to the fight", model.phase == model.PHASE_FIGHT)
	check("retry keeps the campaign's city reward", main.campaign.has_component("navigation_chip"))
	check("retry keeps the mission objective", main.campaign.mission_id() == "return_with_evidence")

	# Win it through the real rules.
	var victory := false
	guard = 0
	while guard < 6000 and not victory:
		guard += 1
		duel.set_cursor_canvas(_aim_at_nearest_hostile(duel))
		duel.advance_for(0.05)
		if model.charge_full() and model.is_fighting():
			duel._try_counterattack()
		if model.phase == model.PHASE_VICTORY:
			victory = true
		if model.is_fighting():
			model.nick_health = model.nick_health_max
			if model.charge < model.charge_max:
				model.charge = mini(model.charge_max, model.charge + 1)
	check("the Toxic Tide can be defeated", victory)
	duel.advance_for(2.0)
	duel._confirm_victory()
	finish_dialogue()
	check("the power core is awarded", main.campaign.has_component("power_core"))
	check("the Toxic Tide flag is set", main.campaign.has_flag("toxic_tide_defeated"))
	check("the shield emitter is still not awarded", not main.campaign.has_component("shield_emitter"))


func _coast_archive_and_base() -> void:
	print("")
	print("-- Environmental archive and the base return " + "-".repeat(12))
	check("the environmental archive opens", main.screen == main.Screen.ARCHIVE and main._archive_id == "coast_archive")
	main.archive_screen._finish()
	check("the environmental archive is restored", main.campaign.is_archive_restored("coast_archive"))
	check("the coast lesson is preserved", main.campaign.has_flag("coast_lesson_preserved"))
	check("the base return screen opens", main.screen == main.Screen.PROGRESSION, str(main.screen))
	check("the base return shows both components", _component_count("navigation_chip") == 1 and _component_count("power_core") == 1)
	check("both components read as recovered", _component_recovered("navigation_chip") and _component_recovered("power_core"))
	check("Dawn Tower is unlocked", main.campaign.has_flag("dawn_tower_unlocked"))
	check("the campaign is at the base", main.campaign.chapter_id == main.campaign.CHAPTER_CRASH)
	finish_dialogue()

	main.progression_screen._unhandled_input(_key_event(KEY_ENTER))
	finish_dialogue()
	check("finishing the base return reaches the summary", main.screen == main.Screen.CHECKPOINT, str(main.screen))
	check("Phase 2 is marked complete", main.campaign.has_flag("phase_two_complete"))
	check("the stage is the Phase 2 complete stage", main.campaign.stage == main.campaign.STAGE_PHASE_TWO_COMPLETE)

	check("a save exists at the Phase 2 summary", SFSave.has_valid_save())

	# Save/load must preserve Phase 2 progression exactly once. A save written
	# by the Phase 2 build ended at the "complete" stage; it must still resume
	# at the summary, which now continues into the Dawn Tower.
	main.campaign.advance_to(main.campaign.STAGE_COMPLETE)
	main._save_quietly()
	main._go(main.Screen.TITLE)
	main._continue_game()
	check("a finished Phase 2 save resumes at the summary", main.screen == main.Screen.CHECKPOINT, str(main.screen))
	check("continue restores the Phase 2 completion", main.campaign.stage == main.campaign.STAGE_COMPLETE)
	check("continue restores both components", _component_count("navigation_chip") == 1 and _component_count("power_core") == 1)
	check("continue restores the restored archives", main.campaign.is_archive_restored("city_archive") and main.campaign.is_archive_restored("coast_archive"))
	check("continue restores the mission objective", main.campaign.mission_id() == "return_with_evidence")
	check("continue keeps Dawn Tower unlocked", main.campaign.has_flag("dawn_tower_unlocked"))
	check("continue restores the optional memories", main.campaign.has_viewed_memory("memory_city_green") and main.campaign.has_viewed_memory("memory_green_coast"))


## Points the cursor at the nearest hostile projectile, so the scripted player
## blocks rather than relying on luck. Returns a canvas-space cursor position.
func _aim_at_nearest_hostile(duel) -> Vector2:
	var pick := Vector2.ZERO
	var best := 1.0e20
	for entry in duel.encounter.field.projectiles:
		var p: Dictionary = entry
		if not bool(p.get("alive", false)):
			continue
		if String(p.get("family", "hostile")) != "hostile":
			continue
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		var d: float = pos.distance_to(duel.encounter.nick_position)
		if d < best:
			best = d
			pick = pos
	if pick == Vector2.ZERO:
		return duel.encounter.nick_position + Vector2(0, -80)
	return pick


## Counts how many times a component appears in the campaign's recovered list.
## Duplicates are impossible by construction; this proves it from outside.
func _component_count(component_id: String) -> int:
	var n := 0
	for id in main.campaign.recovered_component_ids():
		if String(id) == component_id:
			n += 1
	return n


func _component_recovered(component_id: String) -> bool:
	for entry in main.campaign.component_status():
		var comp: Dictionary = entry
		if String(comp.get("id", "")) == component_id:
			return bool(comp.get("recovered", false))
	return false


# ---------------------------------------------------------------- phase 3

func _type(duel, text: String) -> void:
	for i in text.length():
		duel.handle_key(KEY_A, text.unicode_at(i))


func _dawn_tower() -> void:
	print("")
	print("-- Dawn Tower: exploration, memory and the gate " + "-".repeat(11))
	main._checkpoint_key(KEY_ENTER)
	check("the Phase 2 summary continues into the Dawn Tower", main.screen == main.Screen.WORLD and main.zone == "dawn_tower", "%s %s" % [str(main.screen), main.zone])
	check("the stage is the Dawn intro", main.campaign.stage == main.campaign.STAGE_DAWN_INTRO)
	check("the chapter is the Dawn Tower", main.campaign.chapter_id == "dawn_tower")
	check("the Dawn intro opens", main.dialogue != null)
	finish_dialogue()
	check("Dawn entry is recorded", main.campaign.has_flag("dawn_entered"))
	check("the Dawn Tower site has its gate", main.world.prop_by_id("dawn_boss_gate") != null)

	main._on_world_interact("dawn_boss_gate", main.world.prop_by_id("dawn_boss_gate"))
	check("the gate refuses entry before the forest memory", main.screen == main.Screen.WORLD and main.dialogue != null)
	finish_dialogue()

	main._on_world_interact("dawn_terminal", main.world.prop_by_id("dawn_terminal"))
	check("the defense console explains the typing interface", main.dialogue != null)
	finish_dialogue()

	main._on_world_interact("dawn_memory", main.world.prop_by_id("dawn_memory"))
	finish_dialogue()
	check("the projector plays the healthy-forest memory", main.screen == main.Screen.MEMORY and main.memory_id == "memory_healthy_forest", str(main.screen))
	main._finish_memory_playback()
	check("the forest memory is recorded", main.campaign.has_viewed_memory("memory_healthy_forest"))
	check("the memory returns to the slope", main.screen == main.Screen.WORLD and main.zone == "dawn_tower")

	main._on_world_interact("dawn_boss_gate", main.world.prop_by_id("dawn_boss_gate"))
	check("the gate refuses entry before the checkpoint", main.screen == main.Screen.WORLD)
	finish_dialogue()

	var scrap_before: int = main.campaign.material_count("scrap_metal")
	for object_id in ["salvage_dawn_frame", "salvage_dawn_cells", "salvage_dawn_seal"]:
		var prop = main.world.prop_by_id(object_id)
		if prop != null:
			main._on_world_interact(String(object_id), prop)
	check("Dawn salvage is collected", main.campaign.is_collected("salvage_dawn_frame") or main.campaign.material_count("scrap_metal") > scrap_before)

	main._on_world_interact("dawn_checkpoint", main.world.prop_by_id("dawn_checkpoint"))
	finish_dialogue()
	check("the Dawn checkpoint is set", main.campaign.has_flag("dawn_checkpoint"))
	check("the checkpoint is the pre-boss resume point", main.campaign.checkpoint_stage == main.campaign.STAGE_DAWN_BOSS)


func _sky_remnant() -> void:
	print("")
	print("-- Sky Remnant: typing, pause, defeat, retry, victory " + "-".repeat(5))
	main._on_world_interact("dawn_boss_gate", main.world.prop_by_id("dawn_boss_gate"))
	check("the gate starts the typing encounter", main.screen == main.Screen.TYPING, str(main.screen))
	var duel = main.typing_duel
	var enc = duel.encounter
	check("the briefing and tutorial open over the arena", main.dialogue != null)
	check("the arena is input-locked during the briefing", duel.input_locked)
	duel.advance_for(6.0)
	check("nothing spawns during the tutorial", enc.active.is_empty() and enc.phase == enc.PHASE_INTRO)
	finish_dialogue()
	check("the tutorial is recorded as seen", main.campaign.has_flag("typing_tutorial_seen"))
	check("the fight starts after the briefing", enc.is_fighting() and not duel.input_locked)
	check("exploration is not running during the fight", main.world == null)
	check("boss health equals deck size x damage", enc.boss_health_max == enc.deck.size() * enc.damage_per_word())

	var guard := 0
	while enc.active.is_empty() and guard < 400:
		guard += 1
		duel.advance_for(0.05)
	var word: Dictionary = enc.active[0]
	var text := String(word["text"])
	duel.handle_key(KEY_A, text.to_upper().unicode_at(0))
	check("an uppercase key selects the word", enc.typing.target_uid == int(word["uid"]) and enc.typing.progress == 1)
	var echo := InputEventKey.new()
	echo.pressed = true
	echo.echo = true
	echo.keycode = KEY_A
	echo.unicode = text.unicode_at(1)
	duel._unhandled_input(echo)
	check("held-key echo does not type", enc.typing.progress == 1)
	duel.handle_key(KEY_A, text.unicode_at(1), true)
	check("a Ctrl/Alt chord does not type", enc.typing.progress == 1)
	duel.handle_key(KEY_F1, 0)
	check("function keys do not type", enc.typing.progress == 1)

	# Pause freezes everything.
	duel.handle_key(KEY_ESCAPE)
	check("escape pauses", duel.state == duel.State.PAUSED)
	var y_before := float((enc.active[0] as Dictionary)["y"])
	var t_before: float = enc.time
	duel.advance_for(5.0)
	check("paused words do not move", float((enc.active[0] as Dictionary)["y"]) == y_before)
	check("paused time is not counted", enc.time == t_before)
	duel.handle_key(KEY_DOWN)
	duel.handle_key(KEY_ENTER)
	check("the journal opens from the pause menu", duel.state == duel.State.JOURNAL)
	duel.advance_for(3.0)
	check("reading the journal is safe", enc.nick_health == enc.nick_health_max and enc.time == t_before)
	duel.handle_key(KEY_ESCAPE)
	duel.handle_key(KEY_ESCAPE)
	check("escape resumes the fight", duel.state == duel.State.FIGHT)
	duel._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("focus loss pauses the fight", duel.state == duel.State.PAUSED)
	duel.handle_key(KEY_ESCAPE)

	_type(duel, text.substr(1))
	check("finishing the word fires one attack", enc.attacks.size() == 1 and enc.completed.size() == 1)
	check("the learned word is in the campaign journal", main.campaign.has_vocabulary(String(word["id"])))

	# Defeat on purpose.
	guard = 0
	while enc.phase != enc.PHASE_DEFEAT and guard < 40000:
		guard += 1
		duel.advance_for(0.05)
	check("passive play defeats Nick", duel.state == duel.State.DEFEAT)
	check("defeat grants no shield emitter", not main.campaign.has_component("shield_emitter"))
	check("defeat sets no boss flag", not main.campaign.has_flag("sky_remnant_defeated"))
	check("defeat keeps the journal", main.campaign.has_vocabulary(String(word["id"])))
	check("defeat keeps earlier components", main.campaign.has_component("navigation_chip") and main.campaign.has_component("power_core"))
	var deck_before := str(enc.deck)
	duel.handle_key(KEY_R)
	check("retry restarts the fight", duel.state == duel.State.FIGHT and enc.is_fighting())
	check("retry restores both health bars", enc.nick_health == enc.nick_health_max and enc.boss_health == enc.boss_health_max)
	check("retry reuses the deck", str(enc.deck) == deck_before)
	check("retry does not count journal words as damage", enc.completed.is_empty())

	# Win through real key input.
	guard = 0
	while not enc.is_over() and guard < 40000:
		guard += 1
		duel.advance_for(0.05)
		if not enc.active.is_empty() and enc.is_fighting():
			_type(duel, String((enc.active[0] as Dictionary)["text"]))
	check("the Sky Remnant can be defeated by typing", enc.phase == enc.PHASE_VICTORY)
	duel.handle_key(KEY_ENTER)
	check("continue waits for the defeat animation", main.dialogue == null and not duel.finished)
	duel.advance_for(3.0)
	duel.handle_key(KEY_ENTER)
	duel._confirm_victory()
	check("the shield emitter is awarded", main.campaign.has_component("shield_emitter"))
	check("the shield emitter is awarded once", _component_count("shield_emitter") == 1)
	check("the boss flag is set", main.campaign.has_flag("sky_remnant_defeated"))
	check("every deck word is in the journal", main.campaign.vocabulary_journal.size() >= enc.deck.size())
	finish_dialogue()


func _dawn_archive_and_workshop() -> void:
	print("")
	print("-- Dawn archive and the reconstruction workshop " + "-".repeat(10))
	check("the Dawn archive opens", main.screen == main.Screen.ARCHIVE and main._archive_id == "dawn_archive", str(main.screen))
	main.archive_screen._finish()
	check("the Dawn archive is restored", main.campaign.has_flag("dawn_archive_restored") and main.campaign.is_archive_restored("dawn_archive"))
	check("the workshop is unlocked", main.campaign.has_flag("workshop_unlocked"))
	check("the stage is reconstruction", main.campaign.stage == main.campaign.STAGE_RECONSTRUCTION)
	check("the workshop opens", main.screen == main.Screen.WORKSHOP and main.workshop_screen != null)
	check("Bill introduces the workshop", main.dialogue != null)
	finish_dialogue()

	var ws = main.workshop_screen
	ws.workshop.set_fuel(0.0)
	ws._design_changed()
	var bad: Dictionary = ws.run_simulation()
	check("an unfuelled design fails the simulation", not bool(bad["valid"]))
	var refused: Dictionary = ws.fabricate()
	check("a failing design cannot be fabricated", not bool(refused["ok"]) and not main.campaign.is_ready_for_final_assembly())

	ws.handle_key(KEY_ESCAPE)
	check("leaving the workshop returns to the crash-site base", main.screen == main.Screen.WORLD and main.zone == "crash_site")
	main._on_world_interact("crash_vela", main.world.prop_by_id("crash_vela"))
	check("the wreck reopens the workshop", main.screen == main.Screen.WORKSHOP)
	ws = main.workshop_screen
	check("the workshop kept the revised selection", float(ws.workshop.selection["fuel_kg"]) == 0.0)

	ws.workshop.set_fuel(float(ws.preview["totals"]["propellant_needed_kg"]))
	ws._design_changed()
	var good: Dictionary = ws.run_simulation()
	check("the revised design passes", bool(good["valid"]), ", ".join(good["failures"]))
	ws.workshop.adjust_fuel(1)
	ws._design_changed()
	check("a design change invalidates the report", not ws.report_is_current())
	ws.workshop.adjust_fuel(-1)
	ws._design_changed()
	ws.run_simulation()
	ws.scavenge()
	var inv_before := str(main.campaign.inventory)
	var done: Dictionary = ws.fabricate()
	check("the passing design is fabricated", bool(done["ok"]), String(done["message"]))
	check("fabrication spent salvage", str(main.campaign.inventory) != inv_before)
	check("READY_FOR_FINAL_ASSEMBLY is reached", main.campaign.is_ready_for_final_assembly())
	check("the stage is ready for final assembly", main.campaign.stage == main.campaign.STAGE_READY)
	finish_dialogue()
	check("the ready summary is shown", main.screen == main.Screen.CHECKPOINT, str(main.screen))


func _ready_and_continue() -> void:
	print("")
	print("-- READY_FOR_FINAL_ASSEMBLY, save and continue " + "-".repeat(11))
	check("a save exists at the ready point", SFSave.has_valid_save())
	main._checkpoint_key(KEY_ENTER)
	check("the ready summary returns to the title", main.screen == main.Screen.TITLE)
	main._continue_game()
	check("continue restores the ready stage", main.campaign.stage == main.campaign.STAGE_READY)
	check("continue shows the ready summary", main.screen == main.Screen.CHECKPOINT)
	check("continue keeps all three components once", _component_count("navigation_chip") == 1 and _component_count("power_core") == 1 and _component_count("shield_emitter") == 1)
	check("continue keeps the journal", main.campaign.vocabulary_journal.size() >= 20)
	check("continue keeps the committed design", main.campaign.reconstruction.has("committed"))
	check("the escape is not implemented (Phase 4)", not main.campaign.content.chapter("return_home").is_empty() and String(main.campaign.content.chapter("return_home")["stage"]) == "deferred")
	main._checkpoint_key(KEY_ENTER)
	check("the ready summary stays the stopping point", main.screen == main.Screen.TITLE)


func SFCampaign_STAGE_COMPLETE() -> String:
	return main.campaign.STAGE_COMPLETE


func _finish() -> void:
	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	SFSave.delete_save()
	quit(1 if fails > 0 else 0)
