extends SceneTree
## Dev tool: renders key screens to PNG so the build can be eyeballed without
## playing through it. This is a presentation check only; it is not a
## substitute for playing the game.
##
##   Godot --path . --script res://tests/star_fall/capture.gd
##
## Images land in user://captures/ (Windows:
## %APPDATA%\Godot\app_userdata\STAR FALL\captures\).
## Needs a real display; it will not work in --headless.

const OUT_DIR := "user://captures/"
const SFSave := preload("res://core/star_fall/sf_save.gd")
const SFQA := preload("res://core/star_fall/sf_qa.gd")

var main
var frame: int = 0
var shot: int = 0
var plan: Array = [
	{"name": "01_title", "setup": "_setup_title", "wait": 6},
	{"name": "02_briefing", "setup": "_setup_briefing", "wait": 24},
	{"name": "03_world_earth", "setup": "_setup_world", "wait": 20},
	{"name": "04_construction", "setup": "_setup_construction", "wait": 12},
	{"name": "05_preflight_fail", "setup": "_setup_preflight_fail", "wait": 8},
	{"name": "06_preflight_pass", "setup": "_setup_preflight_pass", "wait": 8},
	{"name": "07_countdown", "setup": "_setup_launch", "wait": 8},
	{"name": "08_ascent", "setup": "_setup_ascent", "wait": 12},
	{"name": "08b_ignition", "setup": "_setup_ignition", "wait": 6},
	{"name": "08c_atmosphere", "setup": "_setup_atmosphere", "wait": 6},
	{"name": "08d_space", "setup": "_setup_space", "wait": 6},
	{"name": "09_signal", "setup": "_setup_signal", "wait": 12},
	{"name": "10_rift", "setup": "_setup_rift", "wait": 12},
	{"name": "11_crash", "setup": "_setup_crash", "wait": 10},
	{"name": "12_crash_site", "setup": "_setup_crash_site", "wait": 24},
	{"name": "13_memory", "setup": "_setup_memory", "wait": 24},
	{"name": "14_checkpoint", "setup": "_setup_checkpoint", "wait": 10},
	{"name": "15_forgotten_city", "setup": "_setup_forgotten_city", "wait": 20},
	{"name": "16_city_memory", "setup": "_setup_city_memory", "wait": 20},
	# The Scrap King encounter is the Eco Arena (campaign mode).
	{"name": "17_eco_guide", "setup": "_setup_eco_guide", "wait": 30},
	{"name": "18_eco_stage1", "setup": "_setup_eco_stage1", "wait": 30},
	{"name": "19_eco_stage2", "setup": "_setup_eco_stage2", "wait": 30},
	{"name": "20_eco_boss", "setup": "_setup_eco_boss", "wait": 30},
	{"name": "20b_eco_reward", "setup": "_setup_eco_reward", "wait": 30},
	{"name": "20c_eco_summary", "setup": "_setup_eco_summary", "wait": 30},
	{"name": "21_city_archive", "setup": "_setup_city_archive", "wait": 20},
	{"name": "22_silent_coast", "setup": "_setup_silent_coast", "wait": 20},
	{"name": "22b_coast_memory", "setup": "_setup_coast_memory", "wait": 20},
	{"name": "23_toxic_tide", "setup": "_setup_toxic_tide", "wait": 40},
	{"name": "23b_power_core_drop", "setup": "_setup_power_core_drop", "wait": 20},
	{"name": "24_coast_archive", "setup": "_setup_coast_archive", "wait": 20},
	{"name": "25_base_return", "setup": "_setup_base_return", "wait": 20},
	{"name": "26_phase_two_summary", "setup": "_setup_phase_two_summary", "wait": 12},
	{"name": "27_dawn_tower", "setup": "_setup_dawn_tower", "wait": 20},
	{"name": "28_forest_memory", "setup": "_setup_forest_memory", "wait": 24},
	{"name": "29_sky_remnant", "setup": "_setup_sky_remnant", "wait": 30},
	{"name": "30_typing_reset", "setup": "_setup_typing_reset", "wait": 4},
	{"name": "31_typing_journal", "setup": "_setup_typing_journal", "wait": 6},
	{"name": "35_shield_drop", "setup": "_setup_shield_drop", "wait": 20},
	{"name": "32_dawn_archive", "setup": "_setup_dawn_archive", "wait": 20},
	{"name": "33_workshop", "setup": "_setup_workshop", "wait": 10},
	{"name": "36_workshop_fitted", "setup": "_setup_workshop_fitted", "wait": 12},
	{"name": "34_ready_summary", "setup": "_setup_ready_summary", "wait": 10},
	# Phase 4.
	{"name": "46_final_assembly", "setup": "_setup_final_assembly", "wait": 10},
	{"name": "47_assembly_install", "setup": "_setup_assembly_install", "wait": 30},
	{"name": "48_escape_departure", "setup": "_setup_escape_departure", "wait": 40},
	{"name": "48b_escape_boarding", "setup": "_setup_escape_boarding", "wait": 18},
	{"name": "49_escape_launch", "setup": "_setup_escape_launch", "wait": 24},
	{"name": "49b_escape_ignition", "setup": "_setup_escape_ignition", "wait": 18},
	{"name": "49c_escape_liftoff", "setup": "_setup_escape_liftoff", "wait": 18},
	{"name": "50_escape_debris", "setup": "_setup_escape_debris", "wait": 24},
	{"name": "51_escape_sunlight", "setup": "_setup_escape_sunlight", "wait": 24},
	{"name": "52_escape_portal", "setup": "_setup_escape_portal", "wait": 24},
	{"name": "52b_escape_portal_entry", "setup": "_setup_escape_portal_entry", "wait": 18},
	{"name": "53_escape_home", "setup": "_setup_escape_home", "wait": 28},
	{"name": "53b_escape_celebration", "setup": "_setup_escape_celebration", "wait": 24},
	{"name": "54_final_message", "setup": "_setup_final_message", "wait": 20},
	{"name": "55_mission_report", "setup": "_setup_mission_report", "wait": 10},
	{"name": "56_credits", "setup": "_setup_credits", "wait": 16},
	{"name": "57_pause_settings", "setup": "_setup_pause_settings", "wait": 8},
]
var hold: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Optional filter, so a single screen can be re-rendered without walking the
	# whole plan (a long run can return stale frames on a window that has lost
	# focus):
	#   godot --path . --script res://tests/star_fall/capture.gd -- --shots=17,18
	var only := ""
	var args: Array = []
	args.append_array(OS.get_cmdline_args())
	# Arguments after a bare "--" are user arguments on some builds, and are not
	# included above on others. Both sources are checked so the filter works the
	# same way whichever list the engine populates.
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if String(arg).begins_with("--shots="):
			only = String(arg).substr(8)
	if only != "":
		var wanted := only.split(",", false)
		var filtered: Array = []
		for entry in plan:
			var item: Dictionary = entry
			var name := String(item.get("name", ""))
			for w in wanted:
				if name.begins_with(String(w).strip_edges() + "_"):
					filtered.append(item)
					break
		plan = filtered
	main = load("res://scenes/star_fall/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 4:
		return false
	if hold > 0:
		hold -= 1
		if hold == 1:
			# Freeze the frame we are about to capture. The overlay keeps its
			# own process running, so the HUD stays drawn.
			main.set_process(false)
		if hold == 0:
			_capture(String(plan[shot]["name"]))
			main.set_process(true)
			shot += 1
		return false
	if shot >= plan.size():
		# This tool drives the campaign forward to pose each screen, which can
		# write a save. Remove it so a screenshot run never touches real progress.
		SFSave.delete_save()
		print("captured %d screens" % plan.size())
		quit()
		return false
	call(String(plan[shot]["setup"]))
	hold = int(plan[shot]["wait"])
	return false


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	var err := img.save_png(path)
	print(("captured " if err == OK else "FAILED ") + path + "  screen=" + str(main.screen))


# ---------------------------------------------------------------- setups

func _setup_title() -> void:
	main.campaign.reset_campaign()
	main._go(main.Screen.TITLE)


func _setup_briefing() -> void:
	main.campaign.reset_campaign()
	main.campaign.advance_to(main.campaign.STAGE_BRIEFING)
	main.zone = "spaceport"
	main._go(main.Screen.WORLD)
	main._start_briefing()


func _setup_world() -> void:
	main.dialogue = null
	main.apply_focus_state()
	main.campaign.set_flag(main.campaign.FLAG_BRIEFING_READ)
	main._go(main.Screen.WORLD)


func _fill_viable_design() -> void:
	var d = main.campaign.design
	d.clear()
	d.set_slot("computer", "flight_computer_standard")
	d.set_slot("propulsion", "propulsion_light")
	d.set_slot("power", "power_solar_array")
	d.set_slot("communications", "comms_standard")
	d.set_slot("sensor", "sensor_spectrometer")
	d.fuel_kg = 240.0


func _setup_construction() -> void:
	main.campaign.set_flag(main.campaign.FLAG_BRIEFING_READ)
	_fill_viable_design()
	main._go(main.Screen.CONSTRUCTION)
	if main.construction != null:
		main.construction.slot_menu.index = 4
		main.construction.current_slot = 4


func _setup_preflight_fail() -> void:
	main.campaign.design.set_slot("sensor", "sensor_low_gain")
	if main.construction != null:
		main.construction._run_preflight()


func _setup_preflight_pass() -> void:
	_fill_viable_design()
	if main.construction != null:
		main.construction._run_preflight()


func _setup_launch() -> void:
	main.campaign.confirm_design()
	main._go(main.Screen.LAUNCH)


func _setup_ascent() -> void:
	main.launch_phase = main.LaunchPhase.ASCENT
	main.launch_timer = 1.8


func _setup_ignition() -> void:
	main.launch_phase = main.LaunchPhase.ASCENT
	main.launch_timer = 0.9


func _setup_atmosphere() -> void:
	main.launch_phase = main.LaunchPhase.ASCENT
	main.launch_timer = 4.3


func _setup_space() -> void:
	main.launch_phase = main.LaunchPhase.ASCENT
	main.launch_timer = 6.6


func _setup_signal() -> void:
	main.launch_phase = main.LaunchPhase.SIGNAL
	main.launch_timer = 1.0
	main.signal_timer = 2.0
	main.signal_locks = 1
	main.signal_marker = 0.62
	main.signal_target = 0.58


func _setup_rift() -> void:
	main.launch_phase = main.LaunchPhase.RIFT
	main.launch_timer = 1.2
	main.crash_shake = 2.0


func _setup_crash() -> void:
	main.launch_phase = main.LaunchPhase.CRASH
	main.launch_timer = 1.4
	main.crash_shake = 0.4


func _setup_crash_site() -> void:
	main._finish_launch_state()
	main.dialogue = null
	main.apply_focus_state()


func _setup_memory() -> void:
	main.campaign.set_flag(main.campaign.FLAG_POWER_REPAIRED)
	main.campaign.set_flag(main.campaign.FLAG_BILL_ACTIVE)
	main.memory_chars = 999.0
	main._begin_memory()


# ---------------------------------------------------------------- phase 2 setups
## These pose Phase 2 screens with real campaign state. They walk the same entry
## points the game does, so a screenshot cannot show a state the player can never
## reach.

func _clear_dialogue() -> void:
	main.dialogue = null
	main.dialogue_next = Callable()
	main.apply_focus_state()


func _enter_city() -> void:
	main.campaign.advance_to(main.campaign.STAGE_CITY_INTRO)
	main.campaign.set_flag(main.campaign.FLAG_CITY_ENTERED)
	main.zone = "forgotten_city"
	main._go(main.Screen.WORLD)
	_clear_dialogue()


func _setup_forgotten_city() -> void:
	main.campaign.reset_campaign()
	main.campaign.advance_to(main.campaign.STAGE_CHECKPOINT)
	main.campaign.set_flag(main.campaign.FLAG_BILL_ACTIVE)
	main.campaign.set_flag(main.campaign.FLAG_COORDINATES_RECEIVED)
	main.campaign.set_flag(main.campaign.FLAG_CITY_CHECKPOINT)
	main.campaign.set_checkpoint(main.campaign.STAGE_CITY_BOSS, main.campaign.CHAPTER_CITY)
	_enter_city()


func _setup_city_memory() -> void:
	main.memory_chars = 999.0
	main._play_memory(main.campaign.MEMORY_CITY_GREEN, Callable(main, "_return_to_world"))


func _start_boss(boss_id: String) -> void:
	var stage: String = main.campaign.STAGE_CITY_BOSS
	var zone: String = "forgotten_city"
	if boss_id == "toxic_tide":
		stage = main.campaign.STAGE_COAST_BOSS
		zone = "silent_coast"
	main.zone = zone
	main.campaign.advance_to(stage)
	main.campaign.set_checkpoint(stage, main.campaign.chapter_id)
	main._go(main.Screen.DUEL)
	_clear_dialogue()
	if main.duel != null:
		main.duel._advance(2.5)


func _start_eco() -> void:
	main.campaign.reset_campaign()
	main.campaign.set_flag(main.campaign.FLAG_BILL_ACTIVE)
	main.campaign.set_flag(main.campaign.FLAG_CITY_ENTERED)
	main.campaign.set_flag(main.campaign.FLAG_CITY_CHECKPOINT)
	main._begin_city_boss()
	_clear_dialogue()


## Poses the arena and freezes it, so the capture shows exactly this moment.
func _freeze_eco(es) -> void:
	es.banner_timer = 0.0
	es._snap_camera()
	es._update_presentation(0.0)
	es.set_process(false)
	es.queue_redraw()


func _eco_enemy(m, type_id: String, offset: Vector2) -> Dictionary:
	var e: Dictionary = m.spawn_enemy(type_id, m.nick_pos + offset)
	e["charges"] = false
	e["speed"] = 0.0
	return e


func _setup_eco_guide() -> void:
	_start_eco()


func _setup_eco_stage1() -> void:
	var es = main.eco_screen
	if es == null:
		return
	es.start_from_guide()
	var m = es.model
	m.nick_pos = Vector2(560, 640)
	var target := _eco_enemy(m, "blue_box", Vector2(80, -70))
	_eco_enemy(m, "green_peel", Vector2(-110, -40))
	_eco_enemy(m, "yellow_bottle", Vector2(140, 20))
	_eco_enemy(m, "yellow_can", Vector2(-60, 70))
	m._drop_core("standard", m.nick_pos + Vector2(-40, 26), ["yellow"], "aluminum_can")
	m._drop_core("standard", m.nick_pos + Vector2(60, 40), ["green"], "banana_peel")
	m.add_charge_for_test(12)
	m.select_spectrum("blue")
	es.scripted_input = {"move": Vector2.ZERO, "aim": (target["pos"] as Vector2) + Vector2(0, -6), "fire": true, "beam": false}
	es.advance_for(0.25)
	_freeze_eco(es)


func _setup_eco_stage2() -> void:
	_start_eco()
	var es = main.eco_screen
	if es == null:
		return
	es.start_from_guide()
	var m = es.model
	m.add_charge_for_test(32)
	m.nick_pos = Vector2(820, 560)
	var pizza := _eco_enemy(m, "trick_pizza", Vector2(-90, -60))
	_eco_enemy(m, "trick_paper", Vector2(90, -50))
	_eco_enemy(m, "trick_crushed", Vector2(110, 60))
	var elite := _eco_enemy(m, "elite_residue", Vector2(-120, 50))
	m._drop_core("dual", m.nick_pos + Vector2(-30, 40), ["green", "yellow"], "residue_bottle")
	m.select_spectrum("blue")
	es.scripted_input = {"move": Vector2.ZERO, "aim": (pizza["pos"] as Vector2) + Vector2(0, -6), "fire": true, "beam": true}
	es.advance_for(0.3)
	m.select_spectrum("blue")
	_freeze_eco(es)


func _setup_eco_boss() -> void:
	_start_eco()
	var es = main.eco_screen
	if es == null:
		return
	es.start_from_guide()
	var m = es.model
	m.add_charge_for_test(80)
	m.boss["state"] = "fight"
	m.boss["timer"] = 0.0
	m.boss["toss_t"] = 0.05
	m.nick_pos = (m.boss["pos"] as Vector2) + Vector2(-60, 150)
	m.select_spectrum("green")
	es.scripted_input = {"move": Vector2.ZERO, "aim": (m.boss["pos"] as Vector2) + Vector2(0, -30), "fire": true, "beam": false}
	es.advance_for(0.6)
	_freeze_eco(es)


func _setup_eco_reward() -> void:
	_start_eco()
	var es = main.eco_screen
	if es == null:
		return
	es.start_from_guide()
	var m = es.model
	m.debug_defeat_boss()
	es._consume(m.take_events())
	var sc: Dictionary = m.cores[0]
	m.nick_pos = (sc["pos"] as Vector2) + Vector2(0, 6)
	es.scripted_input = {"move": Vector2.ZERO, "aim": sc["pos"], "fire": false, "beam": false}
	m.select_spectrum("green")
	es.advance_for(0.3)
	m.nick_pos = (m.chip["pos"] as Vector2) + Vector2(0, 8)
	es.advance_for(0.1)
	_freeze_eco(es)


func _setup_eco_summary() -> void:
	var es = main.eco_screen
	if es == null:
		return
	es.set_process(true)
	var m = es.model
	var sc: Dictionary = m.cores[0] if not m.cores.is_empty() else {}
	if not sc.is_empty():
		for cat in ["blue", "yellow"]:
			m.nick_pos = (sc["pos"] as Vector2) + Vector2(0, 6)
			m.select_spectrum(cat)
			es.advance_for(0.4)
	m.mismatch_counts["pizza_box"] = 2
	m.decisions["e1:0"] = false
	m.decisions["e2:0"] = true
	m.decisions["e3:0"] = true
	m.elapsed = 371.0
	m.nick_pos = m.chip["pos"]
	m.interact()
	es._consume(m.take_events())
	_freeze_eco(es)


func _setup_power_core_drop() -> void:
	main.campaign.set_flag(main.campaign.FLAG_TOXIC_TIDE_DEFEATED)
	main.campaign.advance_to(main.campaign.STAGE_SILENT_INTRO)
	main.zone = "silent_coast"
	main._go(main.Screen.WORLD)
	_clear_dialogue()
	if main.world != null:
		main.world.set_player_position(Vector2(530, 250))


func _setup_city_archive() -> void:
	main.campaign.set_flag(main.campaign.FLAG_SCRAP_KING_DEFEATED)
	main.campaign.award_component("navigation_chip")
	main._archive_id = main.campaign.ARCHIVE_CITY
	main._go(main.Screen.ARCHIVE)
	if main.archive_screen != null:
		main.archive_screen.index = maxi(0, main.archive_screen.entries.size() - 1)
		main.archive_screen.reveal_hold = 1.0


func _setup_coast_memory() -> void:
	main.campaign.reveal_future_earth()
	main.memory_chars = 999.0
	main._play_memory(main.campaign.MEMORY_GREEN_COAST, Callable(main, "_return_to_world"))


func _setup_silent_coast() -> void:
	main.campaign.set_flag(main.campaign.FLAG_BILL_ACTIVE)
	main.campaign.reveal_future_earth()
	main.campaign.set_flag(main.campaign.FLAG_COAST_CHECKPOINT)
	main.campaign.set_checkpoint(main.campaign.STAGE_COAST_BOSS, main.campaign.CHAPTER_COAST)
	main.campaign.advance_to(main.campaign.STAGE_SILENT_INTRO)
	main.zone = "silent_coast"
	main._go(main.Screen.WORLD)
	_clear_dialogue()


func _setup_toxic_tide() -> void:
	_start_boss("toxic_tide")
	if main.duel != null:
		main.duel.encounter.model.charge = 68
		main.duel.encounter.aim(Vector2(320, 360))


func _setup_coast_archive() -> void:
	main.campaign.set_flag(main.campaign.FLAG_TOXIC_TIDE_DEFEATED)
	main.campaign.award_component("navigation_chip")
	main.campaign.award_component("power_core")
	main._archive_id = main.campaign.ARCHIVE_COAST
	main._go(main.Screen.ARCHIVE)
	if main.archive_screen != null:
		main.archive_screen.index = maxi(0, main.archive_screen.entries.size() - 1)


func _setup_base_return() -> void:
	main.campaign.reveal_future_earth()
	main.campaign.complete_silent_coast()
	main.campaign.award_component("navigation_chip")
	main.campaign.award_component("power_core")
	main.campaign.restore_archive(main.campaign.ARCHIVE_CITY)
	main.campaign.restore_archive(main.campaign.ARCHIVE_COAST)
	main.campaign.advance_to(main.campaign.STAGE_BASE_RETURN)
	main.zone = "crash_site"
	main._go(main.Screen.PROGRESSION)
	_clear_dialogue()


func _setup_phase_two_summary() -> void:
	main.campaign.reveal_future_earth()
	main.campaign.complete_silent_coast()
	main.campaign.award_component("navigation_chip")
	main.campaign.award_component("power_core")
	main.campaign.advance_to(main.campaign.STAGE_PHASE_TWO_COMPLETE)
	main.campaign.set_checkpoint(main.campaign.STAGE_PHASE_TWO_COMPLETE, main.campaign.CHAPTER_CRASH)
	main._go(main.Screen.CHECKPOINT)


# ---------------------------------------------------------------- phase 3

func _phase3_campaign() -> void:
	main.campaign.reveal_future_earth()
	main.campaign.complete_silent_coast()
	main.campaign.award_component("navigation_chip")
	main.campaign.award_component("power_core")
	if not main.campaign.has_confirmed_design():
		main.campaign.confirmed_design = {"slots": {"propulsion": "propulsion_light"}, "fuel_kg": 200.0}


func _setup_dawn_tower() -> void:
	_phase3_campaign()
	main.campaign.advance_to(main.campaign.STAGE_DAWN_INTRO)
	main.campaign.set_flag(main.campaign.FLAG_DAWN_ENTERED)
	main.zone = "dawn_tower"
	_clear_dialogue()
	main._go(main.Screen.WORLD)
	if main.world != null:
		main.world.set_player_position(Vector2(330, 170))


func _setup_forest_memory() -> void:
	main.memory_id = main.campaign.MEMORY_HEALTHY_FOREST
	main.memory_index = 3
	main.memory_chars = 999.0
	main._go(main.Screen.MEMORY)


func _setup_sky_remnant() -> void:
	_phase3_campaign()
	main.campaign.set_flag(main.campaign.FLAG_TYPING_TUTORIAL_SEEN)
	main._begin_dawn_boss()
	_clear_dialogue()
	var duel = main.typing_duel
	if duel == null:
		return
	duel.start_fight()
	var enc = duel.encounter
	# Play into the second stage so two words are falling, then select one.
	var guard := 0
	while enc.completed_count() < 9 and guard < 4000:
		guard += 1
		duel.advance_for(0.05)
		if not enc.active.is_empty() and enc.completed_count() < 9:
			var t := String((enc.active[0] as Dictionary)["text"])
			for i in t.length():
				duel.handle_key(KEY_A, t.unicode_at(i))
	guard = 0
	while enc.active.size() < 2 and guard < 400:
		guard += 1
		duel.advance_for(0.05)
	duel.advance_for(1.2)
	if not enc.active.is_empty():
		var word: Dictionary = enc.active[enc.active.size() - 1]
		var text := String(word["text"])
		for i in mini(2, text.length() - 1):
			duel.handle_key(KEY_A, text.unicode_at(i))


func _setup_typing_reset() -> void:
	var duel = main.typing_duel
	if duel != null:
		duel.handle_key(KEY_Q, 113)


func _setup_typing_journal() -> void:
	var duel = main.typing_duel
	if duel != null:
		duel.handle_key(KEY_ESCAPE)
		duel.handle_key(KEY_DOWN)
		duel.handle_key(KEY_ENTER)


func _setup_shield_drop() -> void:
	_phase3_campaign()
	main.campaign.defeat_boss("sky_remnant_defeated")
	main.campaign.advance_to(main.campaign.STAGE_DAWN_INTRO)
	main.campaign.set_flag(main.campaign.FLAG_DAWN_ENTERED)
	main.zone = "dawn_tower"
	_clear_dialogue()
	main._go(main.Screen.WORLD)
	if main.world != null:
		main.world.set_player_position(Vector2(392, 168))


func _setup_dawn_archive() -> void:
	_phase3_campaign()
	main.campaign.complete_boss("sky_remnant_defeated", "shield_emitter")
	main._archive_id = main.campaign.ARCHIVE_DAWN
	main._go(main.Screen.ARCHIVE)
	if main.archive_screen != null:
		main.archive_screen.index = maxi(0, main.archive_screen.entries.size() - 1)


func _setup_workshop() -> void:
	_phase3_campaign()
	main.campaign.defeat_boss("sky_remnant_defeated")
	main.campaign.collect_boss_reward("sky_remnant_defeated", "shield_emitter")
	main.campaign.install_component("navigation_chip")
	main.campaign.install_component("power_core")
	main.campaign.complete_dawn_tower()
	main.campaign.advance_to(main.campaign.STAGE_RECONSTRUCTION)
	main.zone = "crash_site"
	main._go(main.Screen.WORKSHOP)
	_clear_dialogue()
	var ws = main.workshop_screen
	if ws != null:
		ws.workshop.set_choice("route", "fast_corridor")
		ws.workshop.set_choice("propulsion", "rebuilt_cluster")
		ws.workshop.set_choice("protection", "shield_amplifier")
		ws.workshop.set_fuel(float(ws.workshop.simulate(main.campaign.recovered_component_ids(), 1)["totals"]["propellant_needed_kg"]))
		ws._design_changed()
		ws.run_simulation()
		# Previewing the shield's socket before installing it.
		ws.row = 0
		ws.tray_index = 2


func _setup_workshop_fitted() -> void:
	var ws = main.workshop_screen
	if ws != null:
		ws.install("shield_emitter")
		ws.row = 1
		ws.run_simulation()


func _setup_ready_summary() -> void:
	var ws = main.workshop_screen
	if ws != null:
		for id in ["navigation_chip", "power_core", "shield_emitter"]:
			main.campaign.install_component(String(id))
		ws.scavenge()
		main.campaign.add_material("circuitry", 6)
		main.campaign.add_material("polymer", 2)
		ws.run_simulation()
		ws.fabricate()
	_clear_dialogue()
	main._go(main.Screen.CHECKPOINT)


# ---------------------------------------------------------------- phase 4

## Drive the campaign to a complete, fabricated, ready state through the QA
## helpers, so the Phase 4 screens pose from real recorded state.
func _phase4_campaign() -> void:
	main.campaign.reset_campaign()
	main._go(main.Screen.TITLE)
	var guard := 0
	while SFQA.next_milestone(main.campaign) != SFQA.MILESTONE_READY and guard < 30:
		guard += 1
		main._apply_qa_skip()
	_clear_dialogue()
	main._go(main.Screen.CHECKPOINT)


func _setup_final_assembly() -> void:
	_phase4_campaign()
	main._checkpoint_key(KEY_ENTER)
	_clear_dialogue()


func _setup_assembly_install() -> void:
	# Standalone-capable: a filtered --shots=36 run has not posed the gate yet.
	if main.screen != main.Screen.FINAL_ASSEMBLY or main.assembly_screen == null:
		_phase4_campaign()
		main._checkpoint_key(KEY_ENTER)
		_clear_dialogue()
	if main.assembly_screen != null and not main.assembly_screen.has_started():
		main.assembly_screen.activate()
	if main.assembly_screen != null:
		main.assembly_screen.install_timer = 1.4


## Poses one cinematic scene at an exact clock value and freezes its process, so
## the captured frame is the pose that was asked for rather than wherever the
## scene drifted during the hold. The playable segments are stepped by hand here
## because their shape depends on the flight model, not on the clock.
func _escape_to(scene_index: int, at: float) -> void:
	if main.cinematic_screen == null:
		main._go(main.Screen.CINEMATIC)
	var cine = main.cinematic_screen
	cine.set_process(false)
	cine.scene_index = scene_index
	cine.show_final_message = false
	cine.scene_time = at
	cine.elapsed = at
	cine.paused = false
	cine.flight = null
	cine._flight_index = -1
	cine._hit_freeze = 0.0
	cine._hold_timer = 0.0
	# Its own process is off, so nothing else will schedule the redraw.
	cine.queue_redraw()
	# A previous screen may have left the sequence paused; a capture always wants
	# the running pose.
	cine.paused = false


func _start_escape() -> void:
	if main.screen == main.Screen.CINEMATIC or main.screen == main.Screen.REPORT or main.screen == main.Screen.CREDITS:
		return
	_phase4_campaign()
	var gate = main.assembly_screen
	if gate == null:
		main._checkpoint_key(KEY_ENTER)
		gate = main.assembly_screen
	if gate != null:
		gate.activate()
		gate._finish_installation()
	_clear_dialogue()


func _setup_escape_departure() -> void:
	_start_escape()
	# The departure station: Bill's core streaming into the parked VELA.
	_escape_to(0, 4.5)


func _setup_escape_boarding() -> void:
	_start_escape()
	# Nick on the boarding ramp, hatch open, engines cold.
	_escape_to(0, 12.9)


func _setup_escape_launch() -> void:
	_start_escape()
	# Mid-climb on a heavy shield contact: the ripple, the glancing body.
	var cine = main.cinematic_screen
	var at: float = cine.launch_contact_time(2) if cine != null else 10.4
	_escape_to(1, at - 0.3)
	_advance_escape(0.3 + 0.08)


func _setup_escape_ignition() -> void:
	_start_escape()
	# On the pad: ignition building, smoke and dust, legs still down.
	_escape_to(1, 2.6)


func _setup_escape_liftoff() -> void:
	_start_escape()
	# Clear of the pad, climbing straight up out of the station.
	_escape_to(1, 4.9)


## Runs the cinematic clock forward from a posed frame so the timed contacts
## fire as they do in play. Earlier contacts are marked done first, so only
## the ones inside this window appear.
func _advance_escape(seconds: float) -> void:
	var cine = main.cinematic_screen
	if cine == null:
		return
	if cine.scene_id() == "launch":
		for i in cine.LAUNCH_CONTACTS.size():
			if cine.launch_contact_time(i) < cine.scene_time:
				cine._fired_cues["launch:contact%d" % i] = true
		for key in ["countdown", "ignition", "shield"]:
			cine._fired_cues["launch:" + key] = true
	var t := 0.0
	while t < seconds:
		cine.advance_for(1.0 / 30.0)
		t += 1.0 / 30.0
	cine.queue_redraw()


func _setup_escape_debris() -> void:
	_start_escape()
	_escape_to(2, 7.0)
	_populate_flight()


func _setup_escape_sunlight() -> void:
	_start_escape()
	_escape_to(3, 8.0)


func _setup_escape_portal() -> void:
	_start_escape()
	_escape_to(4, 6.0)
	_populate_flight()
	var cine = main.cinematic_screen
	if cine != null and cine.flight != null:
		cine.flight.ship_y = cine.flight.portal_y


func _setup_escape_portal_entry() -> void:
	_start_escape()
	_escape_to(4, 6.0)
	_populate_flight()
	var cine = main.cinematic_screen
	if cine == null or cine.flight == null:
		return
	# Captured and half way through the rim: the hull masked at the portal plane.
	var guard := 0
	while guard < 600 and (not cine.flight.captured or cine.flight.entry_fraction() < 0.72):
		guard += 1
		if not cine.flight.captured:
			cine.flight.ship_y = cine.flight.portal_y
		cine.flight.tick(1.0 / 30.0, 0.0)
	cine.queue_redraw()


func _setup_escape_home() -> void:
	_start_escape()
	# Landed, engines off, the ramp down and Nick stepping out.
	_escape_to(5, 9.6)


func _setup_escape_celebration() -> void:
	_start_escape()
	# Nick on the landing area, mid-hop with an arm up. No close-up.
	_escape_to(5, 12.0)


## Steps the playable segment for a few seconds of flight with no steering, so
## the field has obstacles in it and the ship sits where the lane put it.
func _populate_flight() -> void:
	var cine = main.cinematic_screen
	if cine == null:
		return
	cine._ensure_flight()
	if cine.flight == null:
		return
	# Long enough for the field to fill: a capture should show mid-passage, not
	# the first two seconds. The navigation chip flies so no strike freezes the
	# frame; the last half second runs through the screen so shield contacts
	# show exactly as in play.
	cine.flight.assist = cine.flight.kind == "debris"
	for i in 135:
		if cine.flight.kind == "portal":
			# Held off the axis, so the pre-roll does not fly it in already.
			cine.flight.ship_y = cine.flight.lane_top + 12.0
		cine.flight.tick(1.0 / 30.0, 0.0)
	if cine.flight.kind == "debris":
		for i in 15:
			cine.advance_for(1.0 / 30.0)
	cine.flight.assist = false
	cine.queue_redraw()


func _setup_final_message() -> void:
	_start_escape()
	if main.cinematic_screen != null:
		main.cinematic_screen.show_final_message = true
		main.cinematic_screen.scene_time = 4.0
		main.cinematic_screen.elapsed = 4.0


func _setup_mission_report() -> void:
	_start_escape()
	if main.cinematic_screen != null:
		main.cinematic_screen.skip()
	_clear_dialogue()


func _setup_credits() -> void:
	_setup_mission_report()
	if main.report_screen != null:
		main.report_screen.handle_key(KEY_ENTER)
	if main.credits_screen != null:
		main.credits_screen.scroll = 0.0
	_clear_dialogue()


func _setup_checkpoint() -> void:
	main.campaign.view_memory(main.campaign.MEMORY_GREEN_CITY)
	main.campaign.set_flag(main.campaign.FLAG_COORDINATES_RECEIVED)
	main.campaign.mission_manifest["surviving_data_mb"] = main.campaign.surviving_data_mb()
	main.campaign.advance_to(main.campaign.STAGE_CHECKPOINT)
	main._go(main.Screen.CHECKPOINT)


func _setup_pause_settings() -> void:
	main._go(main.Screen.REPORT)
	main._open_pause()
	main.pause_menu.index = main.pause_menu.index_of("settings")
	main._pause_activate()
