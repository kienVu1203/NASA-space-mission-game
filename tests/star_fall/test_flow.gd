extends SceneTree
## STAR FALL flow test: boots the real main scene and drives the whole Phase 1
## campaign through the same entry points the keyboard uses.
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

	# The accident must be a scripted event: skip it and check the state.
	main._launch_key(KEY_ESCAPE)
	check("skip reaches the crash site", main.screen == main.Screen.WORLD and main.zone == "crash_site")
	check("skip still applies the launch flag", main.campaign.has_flag("launched"))
	check("skip still applies the rift flag", main.campaign.has_flag("rift_seen"))
	check("skip still applies the crash flag", main.campaign.has_flag("crashed"))
	check("skip advances the chapter", main.campaign.chapter_id == "crash_site")
	check("skip saves at the crash site checkpoint", main.campaign.checkpoint_stage == main.campaign.STAGE_CRASH_SITE)
	check("a save now exists", SFSave.has_valid_save())
	check("skipping opens the impact dialogue", main.dialogue != null)
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
	print("-- Checkpoint and save/continue " + "-".repeat(31))
	check("the checkpoint screen opens", main.screen == main.Screen.CHECKPOINT, str(main.screen))
	check("the checkpoint stage is recorded", main.campaign.stage == main.campaign.STAGE_CHECKPOINT)
	check("a save exists at the checkpoint", SFSave.has_valid_save())

	# Continue must restore the campaign, not restart it.
	var saved_scrap: int = main.campaign.material_count("scrap_metal")
	var saved_memory: bool = main.campaign.has_viewed_memory("memory_green_city")

	main._checkpoint_key(KEY_ENTER)
	check("finishing returns to the title", main.screen == main.Screen.TITLE)
	check("the campaign is marked complete", main.campaign.stage == main.campaign.STAGE_COMPLETE)
	check("continue is available after saving", main.save_available)
	check("continue is enabled in the menu", bool(main.title_menu.items[1]["enabled"]))

	main._continue_game()
	check("continue restores the completed stage", main.campaign.stage == SFCampaign_STAGE_COMPLETE())
	check("continue restores inventory", main.campaign.material_count("scrap_metal") == saved_scrap)
	check("continue restores memories", main.campaign.has_viewed_memory("memory_green_city") == saved_memory)
	check("continue restores the confirmed design", main.campaign.has_confirmed_design())
	check("continue opens the checkpoint screen", main.screen == main.Screen.CHECKPOINT, str(main.screen))
	check("the restored save kept the design manifest", not main.campaign.mission_manifest.is_empty())


func SFCampaign_STAGE_COMPLETE() -> String:
	return main.campaign.STAGE_COMPLETE


func _finish() -> void:
	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	SFSave.delete_save()
	quit(1 if fails > 0 else 0)
