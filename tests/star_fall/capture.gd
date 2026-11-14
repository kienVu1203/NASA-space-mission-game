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
	{"name": "09_signal", "setup": "_setup_signal", "wait": 12},
	{"name": "10_rift", "setup": "_setup_rift", "wait": 12},
	{"name": "11_crash", "setup": "_setup_crash", "wait": 10},
	{"name": "12_crash_site", "setup": "_setup_crash_site", "wait": 24},
	{"name": "13_memory", "setup": "_setup_memory", "wait": 24},
	{"name": "14_checkpoint", "setup": "_setup_checkpoint", "wait": 10},
	{"name": "15_forgotten_city", "setup": "_setup_forgotten_city", "wait": 20},
	{"name": "16_city_memory", "setup": "_setup_city_memory", "wait": 20},
	{"name": "17_scrap_king", "setup": "_setup_scrap_king", "wait": 40},
	{"name": "18_scrap_king_charge", "setup": "_setup_scrap_king_charged", "wait": 12},
	{"name": "19_counterattack", "setup": "_setup_counterattack", "wait": 6},
	{"name": "20_scrap_king_defeat", "setup": "_setup_scrap_king_defeat", "wait": 20},
	{"name": "21_city_archive", "setup": "_setup_city_archive", "wait": 20},
	{"name": "22_silent_coast", "setup": "_setup_silent_coast", "wait": 20},
	{"name": "22b_coast_memory", "setup": "_setup_coast_memory", "wait": 20},
	{"name": "23_toxic_tide", "setup": "_setup_toxic_tide", "wait": 40},
	{"name": "24_coast_archive", "setup": "_setup_coast_archive", "wait": 20},
	{"name": "25_base_return", "setup": "_setup_base_return", "wait": 20},
	{"name": "26_phase_two_summary", "setup": "_setup_phase_two_summary", "wait": 12},
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


func _setup_scrap_king() -> void:
	main.campaign.reset_campaign()
	main.campaign.set_flag(main.campaign.FLAG_CITY_CHECKPOINT)
	_start_boss("scrap_king")
	if main.duel != null:
		main.duel.encounter.aim(Vector2(470, 110))


func _setup_scrap_king_charged() -> void:
	if main.duel == null:
		return
	main.duel.encounter.model.charge = main.duel.encounter.model.charge_max
	main.duel.encounter.aim(Vector2(500, 130))
	main.duel._advance(0.4)


func _setup_counterattack() -> void:
	if main.duel == null:
		return
	main.duel.encounter.model.charge = main.duel.encounter.model.charge_max
	main.duel._try_counterattack()
	main.duel._advance(0.18)


func _setup_scrap_king_defeat() -> void:
	if main.duel == null:
		return
	var m = main.duel.encounter.model
	m.force_victory()
	main.duel._advance(2.2)


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


func _setup_checkpoint() -> void:
	main.campaign.view_memory(main.campaign.MEMORY_GREEN_CITY)
	main.campaign.set_flag(main.campaign.FLAG_COORDINATES_RECEIVED)
	main.campaign.mission_manifest["surviving_data_mb"] = main.campaign.surviving_data_mb()
	main.campaign.advance_to(main.campaign.STAGE_CHECKPOINT)
	main._go(main.Screen.CHECKPOINT)
