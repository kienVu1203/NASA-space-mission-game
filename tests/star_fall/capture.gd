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
]
var hold: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
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


func _setup_checkpoint() -> void:
	main.campaign.view_memory(main.campaign.MEMORY_GREEN_CITY)
	main.campaign.set_flag(main.campaign.FLAG_COORDINATES_RECEIVED)
	main.campaign.mission_manifest["surviving_data_mb"] = main.campaign.surviving_data_mb()
	main.campaign.advance_to(main.campaign.STAGE_CHECKPOINT)
	main._go(main.Screen.CHECKPOINT)
