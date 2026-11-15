extends Node2D
## STAR FALL - campaign controller.
##
## Owns the screen state machine, the dialogue overlay, pause/settings and the
## scripted launch sequence. Screens do not know about each other; this node
## connects them to the campaign object in GameState and to Events.
##
## Presentation runs at a 640x360 base resolution. The project stretches it to
## the window with integer-friendly scaling and nearest-neighbour filtering, so
## physics positions stay precise while the art stays crisp.
const SFSkin := preload("res://core/star_fall/sf_skin.gd")
const SFAudio := preload("res://core/star_fall/sf_audio.gd")
const SFUI := preload("res://core/star_fall/sf_ui.gd")
const SFDialogue := preload("res://core/star_fall/sf_dialogue.gd")
const SFMenu := preload("res://core/star_fall/sf_menu.gd")
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const SFSave := preload("res://core/star_fall/sf_save.gd")
const SFSites := preload("res://core/star_fall/sf_sites.gd")

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFWorld := preload("res://scenes/star_fall/world.gd")
const SFConstruction := preload("res://scenes/star_fall/construction_screen.gd")
const SFDuel := preload("res://scenes/star_fall/shield_duel.gd")
const SFEcoArenaScreen := preload("res://scenes/star_fall/eco_arena_screen.gd")
const SFArchive := preload("res://scenes/star_fall/archive_screen.gd")
const SFProgression := preload("res://scenes/star_fall/progression_screen.gd")
const SFTypingDuel := preload("res://scenes/star_fall/typing_duel.gd")
const SFWorkshop := preload("res://scenes/star_fall/reconstruction_screen.gd")
const SFVocabulary := preload("res://core/star_fall/sf_vocabulary.gd")
const SFContent := preload("res://core/star_fall/sf_content.gd")
# Phase 4.
const SFFinale := preload("res://core/star_fall/sf_finale.gd")
const SFQA := preload("res://core/star_fall/sf_qa.gd")
const SFSettings := preload("res://core/star_fall/sf_settings.gd")
const SFVela := preload("res://core/star_fall/sf_vela.gd")
const SFFinalAssembly := preload("res://scenes/star_fall/final_assembly_screen.gd")
const SFCinematic := preload("res://scenes/star_fall/cinematic_screen.gd")
const SFReport := preload("res://scenes/star_fall/mission_report_screen.gd")
const SFCredits := preload("res://scenes/star_fall/credits_screen.gd")

enum Screen {
	TITLE,
	SETTINGS,
	WORLD,
	CONSTRUCTION,
	LAUNCH,
	MEMORY,
	CHECKPOINT,
	DUEL,
	ARCHIVE,
	PROGRESSION,
	SAVE_ERROR,
	TYPING,
	WORKSHOP,
	JOURNAL,
	FINAL_ASSEMBLY,
	CINEMATIC,
	REPORT,
	CREDITS,
	ECO_ARENA,
}

enum LaunchPhase {COUNTDOWN, ASCENT, SIGNAL, RIFT, CRASH, DONE}

const VW := 640
const VH := 360

## Screens whose Esc / right-click opens the shared pause menu below. The
## encounter screens (shield duel, typing duel, Eco Arena) keep their own pause
## menus with retry options; the title, settings, journal and save-error screens
## are menus themselves, where Esc means back.
const MAIN_PAUSE_SCREENS := [
	Screen.WORLD, Screen.LAUNCH, Screen.MEMORY, Screen.CHECKPOINT, Screen.ARCHIVE,
	Screen.PROGRESSION, Screen.FINAL_ASSEMBLY, Screen.CINEMATIC, Screen.REPORT, Screen.CREDITS,
]

# Phase 1 launch timing (seconds). COUNTDOWN is the pad; ASCENT runs ignition,
# liftoff, atmosphere and space in that order, then the signal investigation.
const LAUNCH_PAD := Vector2(320, 286)
const COUNTDOWN_SECONDS := 2.6
const IGNITION_END := 1.4
const LIFTOFF_END := 3.0
const ATMOSPHERE_END := 5.6
const ASCENT_SECONDS := 7.2
## Pixels VELA climbs on screen before the camera starts following it.
const LAUNCH_FOLLOW := 120.0

# Settings panel layout, shared by the title settings screen and the pause menu.
const SETTINGS_PANEL := Rect2(100, 44, 440, 272)
const SETTINGS_ROW_H := 22.0
const VOLUME_IDS := ["master_volume", "music_volume", "sfx_volume", "ui_volume"]

const CHECKPOINT_CONTINUE := Rect2(500, 333, 128, 22)
const CHECKPOINT_MENU := Rect2(12, 333, 72, 22)
const MEMORY_NEXT := Rect2(394, 336, 70, 18)
const MEMORY_SKIP := Rect2(470, 336, 70, 18)
const SIGNAL_LOCK_BUTTON := Rect2(270, 240, 100, 18)

var skin
var ui
var audio
var sites
var campaign

var screen: int = Screen.TITLE
var previous_screen: int = Screen.TITLE
var time: float = 0.0
var blink: float = 0.0

# Dialogue overlay.
var dialogue = null
var dialogue_title: String = ""
var dialogue_next: Callable = Callable()

# Menus.
var title_menu
var settings_menu
var pause_menu
var save_error_menu
var save_error_text: String = ""

# World.
var world = null
var construction = null
var zone: String = "spaceport"

# Phase 2 screens.
var duel = null
var archive_screen = null
var progression_screen = null
var _archive_id: String = ""
var _pending_boss_id: String = ""

# Eco Arena: the Scrap King encounter (campaign) and the main-menu practice
# mode share one screen. Practice never reads or writes the campaign.
var eco_screen = null
var eco_data: Dictionary = {}
var eco_mode: String = "practice"
var _eco_resume: bool = false

# Phase 3 screens and content.
var typing_duel = null
var workshop_screen = null
var vocab = null
var typing_data: Dictionary = {}
var journal_index: int = 0
var journal_return: int = Screen.WORLD

# Phase 4 screens and content.
var assembly_screen = null
var cinematic_screen = null
var report_screen = null
var credits_screen = null
var finale_data: Dictionary = {}
var reconstruction_data: Dictionary = {}
var _finale_started: bool = false


# Encounter dialogue is read over a frozen arena; the duel checks this.
var encounter_input_locked: bool = false

# Launch sequence.
var launch_phase: int = LaunchPhase.COUNTDOWN
var launch_timer: float = 0.0
var signal_target: float = 0.5
var signal_marker: float = 0.0
var signal_locks: int = 0
var signal_attempts: int = 0
var signal_timer: float = 0.0
var signal_phase: float = 0.0
## While the player steers the reticle the automatic sweep waits this long.
var signal_manual: float = 0.0
var crash_shake: float = 0.0

# Memory playback.
var memory_id: String = ""
var memory_index: int = 0
var memory_chars: float = 0.0
var memory_next: Callable = Callable()

# Settings (core/star_fall/sf_settings.gd). Local preferences only: they live in
# their own file and never touch the campaign or its save.
var settings: Dictionary = {}
var setting_text_speed: float = 52.0
## Reduces screen shake and full-screen flashes without changing any rule. An
## accessibility preference: it never affects the score, the report or progress.
var setting_reduced_motion: bool = false

# Save status for the menu.
var save_available: bool = false

var _world_scene: Node2D = null
var _overlay_layer: CanvasLayer = null
var _overlay: Node2D = null
var _transition_layer: CanvasLayer = null
var _transition_node: Node2D = null
var transition_alpha: float = 0.0
var transition_timer: float = 0.0
var transition_duration: float = 0.28
var transition_style: int = 0
var _last_world_position: Vector2 = Vector2.ZERO
var _has_last_world_position: bool = false
var _last_zone: String = ""
var pause_open: bool = false
## The settings panel shown inside the pause menu (Esc returns to the menu).
var pause_settings_open: bool = false
var _pause_node: Node = null
var _slider_drag: String = ""
## Eco Arena practice is a reward for beating the Scrap King in the campaign.
## Stored with the settings, so practice stays separate from campaign progress.
var practice_unlocked: bool = false
var debug_jump = null               # scenes/star_fall/debug_jump.gd, debug builds only
var _transition_busy: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(SFPalette.INK)
	campaign = GameState.campaign
	sites = SFSites.new()
	sites.load_all()
	vocab = SFVocabulary.new()
	if not vocab.load_all():
		push_error("STAR FALL: the vocabulary library failed validation")
	typing_data = SFContent.read_json("res://data/star_fall/typing.json") as Dictionary
	finale_data = SFContent.read_json("res://data/star_fall/finale.json") as Dictionary
	if finale_data.is_empty():
		push_error("STAR FALL: finale.json failed to load")
	reconstruction_data = SFContent.read_json("res://data/star_fall/reconstruction.json") as Dictionary
	eco_data = SFContent.read_json("res://data/star_fall/eco_arena.json") as Dictionary
	if eco_data.is_empty():
		push_error("STAR FALL: eco_arena.json failed to load")
	audio = SFAudio.new()
	audio.name = "SFAudio"
	add_child(audio)
	_load_settings()
	skin = SFSkin.new(audio)
	ui = SFUI.new(skin)

	# In-world UI lives on its own layer so world children cannot cover it.
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "Overlay"
	_overlay_layer.layer = 10
	add_child(_overlay_layer)
	_overlay = Node2D.new()
	_overlay.name = "HudOverlay"
	_overlay.set_script(load("res://scenes/star_fall/hud_overlay.gd"))
	_overlay.game = self
	_overlay_layer.add_child(_overlay)

	# Transition layer sits above everything (layer 80) for cinematic scene transitions
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "TransitionLayer"
	_transition_layer.layer = 80
	add_child(_transition_layer)
	_transition_node = Node2D.new()
	_transition_node.name = "TransitionOverlay"
	_transition_node.draw.connect(_draw_transition)
	_transition_layer.add_child(_transition_node)

	# Developer phase hotkeys (Ctrl+Shift+Alt + key). Debug builds only, so an
	# exported release never contains them.
	if OS.is_debug_build():
		debug_jump = load("res://scenes/star_fall/debug_jump.gd").new()
		debug_jump.name = "DebugJump"
		debug_jump.main = self
		add_child(debug_jump)

	_build_menus()
	_refresh_save_state()
	_go(Screen.TITLE)
	set_process(true)


func _build_menus() -> void:
	title_menu = SFMenu.new()
	settings_menu = SFMenu.new()
	pause_menu = SFMenu.new()
	save_error_menu = SFMenu.new()
	save_error_menu.set_items([
		{"id": "title", "label": "BACK TO MAIN MENU", "enabled": true},
	])


func _refresh_save_state() -> void:
	# Continue is enabled only when the file parses and validates. Reading here
	# never writes the campaign save or deletes anything.
	save_available = SFSave.has_valid_save()
	# A save from before practice unlocks existed keeps what it earned: a
	# campaign that already beat the Scrap King unlocks practice here.
	if not practice_unlocked and save_available:
		var flags: Variant = (SFSave.read_save().get("data", {}) as Dictionary).get("flags", {})
		if flags is Dictionary and bool((flags as Dictionary).get(SFCampaign.FLAG_SCRAP_KING_DEFEATED, false)):
			_unlock_practice()
	_rebuild_title_menu()


# ---------------------------------------------------------------- settings store

func _load_settings() -> void:
	settings = SFSettings.load_settings()
	setting_text_speed = float(settings["text_speed"])
	setting_reduced_motion = bool(settings["reduced_motion"])
	practice_unlocked = bool(settings["practice_unlocked"])
	_apply_volumes()


func _apply_volumes() -> void:
	SFAudio.set_bus_volume("Master", float(settings.get("master_volume", 1.0)))
	SFAudio.set_bus_volume(SFAudio.BUS_MUSIC, float(settings.get("music_volume", 0.8)))
	SFAudio.set_bus_volume(SFAudio.BUS_SFX, float(settings.get("sfx_volume", 0.9)))
	SFAudio.set_bus_volume(SFAudio.BUS_UI, float(settings.get("ui_volume", 0.8)))


func _save_settings() -> void:
	settings["text_speed"] = setting_text_speed
	settings["reduced_motion"] = setting_reduced_motion
	settings["practice_unlocked"] = practice_unlocked
	# ponytail: headless test runs never write the player's real settings file;
	# SFSettings is checked directly against a temporary path instead.
	if DisplayServer.get_name() == "headless":
		return
	SFSettings.save_settings(settings)


func _unlock_practice() -> void:
	if practice_unlocked:
		return
	practice_unlocked = true
	_save_settings()


func _rebuild_title_menu() -> void:
	var items: Array = [
		{"id": "new", "label": "NEW GAME", "enabled": true},
		{"id": "continue", "label": "CONTINUE", "enabled": save_available},
		{"id": "eco_arena", "label": "ECO ARENA — 5-7 MIN" if practice_unlocked else "ECO ARENA — LOCKED", "enabled": practice_unlocked},
		{"id": "settings", "label": "SETTINGS", "enabled": true},
		{"id": "quit", "label": "QUIT", "enabled": true},
	]
	var keep: String = String(title_menu.current_id()) if title_menu != null else ""
	title_menu.set_items(items, keep)
	# New Game is always a legal starting point for the cursor.
	if title_menu.index_of("continue") == title_menu.index and not save_available:
		title_menu.index = 0


func _rebuild_settings_menu() -> void:
	var items: Array = []
	for id in VOLUME_IDS:
		items.append({"id": id, "label": {
			"master_volume": "MASTER VOLUME", "music_volume": "MUSIC",
			"sfx_volume": "EFFECTS", "ui_volume": "INTERFACE"}[id], "slider": true, "enabled": true})
	items.append({"id": "text_speed", "label": "TEXT SPEED", "detail": "FAST" if setting_text_speed > 60.0 else ("SLOW" if setting_text_speed < 40.0 else "NORMAL"), "enabled": true})
	items.append({"id": "reduced_motion", "label": "REDUCED MOTION", "detail": "ON" if setting_reduced_motion else "OFF", "enabled": true})
	items.append({"id": "back", "label": "BACK", "enabled": true})
	settings_menu.set_items(items, String(settings_menu.current_id()))


func _rebuild_pause_menu() -> void:
	var items: Array = [{"id": "resume", "label": "RESUME", "enabled": true}]
	if screen == Screen.WORLD:
		items.append({"id": "save", "label": "SAVE PROGRESS", "enabled": true})
	var skip_label := _pause_skip_label()
	if skip_label != "":
		items.append({"id": "skip", "label": skip_label, "enabled": true})
	if screen == Screen.WORLD and not campaign.vocabulary_journal.is_empty():
		items.append({"id": "journal", "label": "VOCABULARY JOURNAL", "enabled": true})
	items.append({"id": "settings", "label": "SETTINGS", "enabled": true})
	items.append({"id": "title", "label": "RETURN TO MAIN MENU", "enabled": true})
	pause_menu.set_items(items, String(pause_menu.current_id()))


## The one explicit skip a paused screen offers, or "" for none. Skipping is
## always the screen's own safe path, so it leaves the same campaign state as
## watching to the end.
func _pause_skip_label() -> String:
	match screen:
		Screen.CINEMATIC:
			return "SKIP SEQUENCE"
		Screen.MEMORY:
			return "SKIP MEMORY"
		Screen.FINAL_ASSEMBLY:
			if assembly_screen != null and assembly_screen.is_installing():
				return "SKIP ANIMATION"
	return ""


# ---------------------------------------------------------------- screen flow

func _go(next: int) -> void:
	if next == screen and not (next == Screen.WORLD and world != null and String(world.site.get("id", "")) != zone):
		queue_redraw()
		return
	previous_screen = screen
	# A pause never survives a screen change, and no gameplay sound outlives the
	# screen that started it.
	if pause_open:
		pause_open = false
		_resume_paused_node()
	# Also clears a pause left by an encounter screen's own menu.
	audio.set_paused(false)
	pause_settings_open = false
	_slider_drag = ""
	audio.stop_gameplay_voices()
	trigger_transition(0, 0.28)

	# Tear down the previous screen's nodes.
	if _world_scene != null:
		if world != null:
			_last_world_position = world.focus_position()
			_has_last_world_position = true
		_world_scene.queue_free()
		_world_scene = null
		world = null
	if construction != null:
		construction.queue_free()
		construction = null
	if duel != null:
		duel.queue_free()
		duel = null
	if eco_screen != null:
		eco_screen.queue_free()
		eco_screen = null
	if archive_screen != null:
		archive_screen.queue_free()
		archive_screen = null
	if progression_screen != null:
		progression_screen.queue_free()
		progression_screen = null
	if typing_duel != null:
		typing_duel.queue_free()
		typing_duel = null
	if workshop_screen != null:
		workshop_screen.queue_free()
		workshop_screen = null
	if assembly_screen != null:
		assembly_screen.queue_free()
		assembly_screen = null
	if cinematic_screen != null:
		cinematic_screen.queue_free()
		cinematic_screen = null
	if report_screen != null:
		report_screen.queue_free()
		report_screen = null
	if credits_screen != null:
		credits_screen.queue_free()
		credits_screen = null

	screen = next
	blink = 0.0
	pause_open = false
	_transition_busy = false
	ui.clear_toast()
	# The finale latch belongs to one attempt. Returning to the title (a new game,
	# a quit, or the end of the credits) clears it, so a later run can confirm
	# final assembly again. `begin_final_assembly()` still refuses a second
	# snapshot inside one run.
	if next == Screen.TITLE:
		_finale_started = false
		# Nothing from a session survives the trip to the title: an open dialogue
		# would otherwise sit over the menu and swallow its keys and clicks.
		dialogue = null
		dialogue_next = Callable()
		encounter_input_locked = false

	match next:
		Screen.TITLE:
			audio.set_ambience("none")
			if audio.has_method("play_music"):
				audio.play_music("title")
			_refresh_save_state()
		Screen.SETTINGS:
			_rebuild_settings_menu()
		Screen.WORLD:
			_enter_world(zone)
		Screen.CONSTRUCTION:
			if audio.has_method("play_music"):
				audio.play_music("construction")
			_enter_construction()
		Screen.LAUNCH:
			if audio.has_method("play_music"):
				audio.play_music("flight")
			_begin_launch()
		Screen.MEMORY:
			# The memory screen is driven by _play_memory(); entering it directly
			# must not restart the memory that was just set up.
			audio.set_ambience("none")
			if audio.has_method("play_music"):
				audio.play_music("memory")
		Screen.CHECKPOINT:
			audio.set_ambience("none")
			if audio.has_method("play_music"):
				audio.play_music("checkpoint")
		Screen.DUEL:
			_enter_duel()
		Screen.ECO_ARENA:
			_enter_eco_arena()
		Screen.ARCHIVE:
			_enter_archive()
		Screen.PROGRESSION:
			_enter_progression()
		Screen.SAVE_ERROR:
			if audio.has_method("stop_music"):
				audio.stop_music()
		Screen.TYPING:
			_enter_typing()
		Screen.WORKSHOP:
			_enter_workshop()
		Screen.FINAL_ASSEMBLY:
			if audio.has_method("play_music"):
				audio.play_music("construction")
			_enter_final_assembly()
		Screen.CINEMATIC:
			_enter_cinematic()
		Screen.REPORT:
			if audio.has_method("play_music"):
				audio.play_music("checkpoint")
			_enter_report()
		Screen.CREDITS:
			_enter_credits()
	queue_redraw()


## Pushes the accessibility preference to every screen that can shake or flash.
## Safe to call at any time; screens that are not open are simply skipped.
func apply_reduced_motion() -> void:
	if duel != null:
		duel.reduced_motion = setting_reduced_motion
	if typing_duel != null:
		typing_duel.reduced_motion = setting_reduced_motion
	if eco_screen != null:
		eco_screen.reduced_motion = setting_reduced_motion
	if cinematic_screen != null:
		cinematic_screen.reduced_motion = setting_reduced_motion


func _enter_world(zone_id: String) -> void:
	var zone_changed: bool = zone_id != _last_zone
	zone = zone_id
	var site: Dictionary = sites.site(zone_id)
	if site.is_empty():
		push_error("Unknown site: %s" % zone_id)
		_go(Screen.TITLE)
		return
	world = SFWorld.new()
	world.name = "World"
	world.setup(
		skin,
		site,
		_world_theme(zone_id),
		float(campaign.content.program.get("walk_speed", 58.0)),
		float(campaign.content.program.get("run_speed", 98.0))
	)
	# Returning from the console should not teleport Nick back to the gate.
	_last_zone = zone_id
	world.interact_requested.connect(_on_world_interact)
	world.interactable_focus_changed.connect(_on_world_focus_changed)
	add_child(world)
	_world_scene = world
	# A restored position must be applied after the world has entered the tree,
	# otherwise the camera's limits and the collision world are not ready.
	if _has_last_world_position and not zone_changed:
		world.set_player_position(_last_world_position)
	_sync_world_actors()
	world.set_input_enabled(true)
	audio.set_ambience(_world_ambience(zone_id))
	if audio.has_method("play_music"):
		audio.play_music("earth" if zone_id == "spaceport" else "ruin")
	apply_focus_state()
	queue_redraw()


func _sync_world_actors() -> void:
	if world == null:
		return
	for pid in [
		"salvage_plate", "salvage_circuit", "salvage_polymer", "scrap_extra",
		"salvage_city_scrap", "salvage_city_boards", "salvage_city_frame",
		"salvage_coast_plate", "salvage_coast_cable",
		"salvage_dawn_frame", "salvage_dawn_cells", "salvage_dawn_seal"
	]:
		if campaign.is_collected(pid):
			world.remove_prop(pid)
	# The shield emitter drop exists in the world only between the Sky
	# Remnant's defeat and the pickup, across revisits and save/load.
	if _shield_state() != SFCampaign.REWARD_AVAILABLE:
		world.remove_prop("dawn_shield_drop")
	# The power core drop likewise exists only between Toxic Tide's defeat and
	# the pickup.
	if _coast_reward_state() != SFCampaign.REWARD_AVAILABLE:
		world.remove_prop("coast_power_core_drop")
	if campaign.has_flag(SFCampaign.FLAG_POWER_REPAIRED):
		world.set_prop_sprite("power_connection", "junction")
	world.sync_companion(campaign.has_flag(SFCampaign.FLAG_BILL_ACTIVE))

	var city_unlocked: bool = campaign.has_flag(SFCampaign.FLAG_CITY_CHECKPOINT) or campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED)
	var city_cleared: bool = campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED)
	var city_status := "LOCKED - USE CHECKPOINT"
	var city_label := "Enter the control center"
	if city_cleared and _city_reward_state() == SFCampaign.REWARD_AVAILABLE:
		city_status = "CHIP WAITING - ENTER [E]"
		city_label = "Return to the sorting yard"
	elif city_cleared:
		city_status = "ROUTE OPEN - SILENT COAST ->"
		city_label = "Proceed to Silent Coast"
	elif city_unlocked:
		city_status = "UNLOCKED - ENTER [E]"
		city_label = "Enter the control center"
	world.configure_gate(
		"city_boss_gate",
		city_unlocked,
		city_cleared,
		"CONTROL CENTER",
		city_status,
		"control_door_open",
		"control_door",
		city_label
	)

	var coast_unlocked: bool = campaign.has_flag(SFCampaign.FLAG_COAST_CHECKPOINT) or campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED)
	var coast_cleared: bool = campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED)
	var coast_status := "LOCKED - USE CHECKPOINT"
	var coast_label := "Enter the cleanup facility"
	if coast_cleared and _coast_reward_state() == SFCampaign.REWARD_AVAILABLE:
		coast_status = "PICK UP THE POWER CORE FIRST"
		coast_label = "The power core is on the quay"
	elif coast_cleared:
		coast_status = "ROUTE OPEN - CRASH-SITE BASE ->"
		coast_label = "Return to crash-site base"
	elif coast_unlocked:
		coast_status = "UNLOCKED - ENTER [E]"
		coast_label = "Enter the cleanup facility"
	world.configure_gate(
		"coast_boss_gate",
		coast_unlocked,
		coast_cleared,
		"CLEANUP FACILITY",
		coast_status,
		"facility_gate_open",
		"facility_gate",
		coast_label
	)


## Which visual theme an authored site uses. Themes own ground drawing only;
## gameplay never branches on them.
func _world_theme(zone_id: String) -> String:
	match zone_id:
		"spaceport":
			return "earth"
		"forgotten_city":
			return "city"
		"silent_coast":
			return "coast"
		"dawn_tower":
			return "ruin"
	return "ruin"


func _world_ambience(zone_id: String) -> String:
	match zone_id:
		"spaceport":
			return "earth"
		"forgotten_city":
			return "city"
		"silent_coast":
			return "coast"
	return "ruin"


# ---------------------------------------------------------------- transitions

func trigger_transition(style: int = 0, duration: float = 0.28) -> void:
	if DisplayServer.get_name() == "headless":
		transition_alpha = 0.0
		return
	if setting_reduced_motion:
		# A short fade only: no full-screen white flash, no shutter wipe.
		style = 0
		duration = minf(duration, 0.18)
	transition_style = style
	transition_duration = maxf(0.05, duration)
	transition_timer = 0.0
	transition_alpha = 1.0
	if audio != null and audio.has_method("sfx_transition"):
		audio.sfx_transition()
	if _transition_node != null:
		_transition_node.queue_redraw()


func trigger_flash_transition(duration: float = 0.5) -> void:
	trigger_transition(1, duration)


func _draw_transition() -> void:
	if transition_alpha <= 0.001 or _transition_node == null:
		return
	if transition_style == 1:
		_transition_node.draw_rect(Rect2(0, 0, VW, VH), Color(1.0, 1.0, 1.0, transition_alpha), true)
	elif transition_style == 2:
		var slats: int = 16
		var slat_h: float = float(VH) / float(slats)
		for s in slats:
			var bar_h: float = slat_h * transition_alpha
			var y: float = float(s) * slat_h + (slat_h - bar_h) * 0.5
			_transition_node.draw_rect(Rect2(0, y, VW, bar_h), SFPalette.INK, true)
	else:
		_transition_node.draw_rect(Rect2(0, 0, VW, VH), Color(SFPalette.INK.r, SFPalette.INK.g, SFPalette.INK.b, transition_alpha), true)


func _enter_construction() -> void:
	construction = SFConstruction.new()
	construction.name = "Construction"
	construction.setup(skin, ui, campaign)
	construction.closed.connect(_on_construction_closed)
	construction.design_confirmed_ok.connect(_on_design_confirmed)
	add_child(construction)
	queue_redraw()


func apply_focus_state() -> void:
	var locked := dialogue != null or screen != Screen.WORLD or pause_open
	if world != null:
		world.set_input_enabled(not locked)
	# While a dialogue is open over the duel, the arena is frozen: the player is
	# reading, so no attack may land and no key may be stolen from the dialogue.
	encounter_input_locked = dialogue != null
	if duel != null:
		duel.input_locked = encounter_input_locked
	if typing_duel != null:
		typing_duel.input_locked = encounter_input_locked
	if eco_screen != null:
		eco_screen.input_locked = encounter_input_locked
	if workshop_screen != null:
		workshop_screen.input_locked = encounter_input_locked
	if assembly_screen != null:
		assembly_screen.input_locked = encounter_input_locked
	if progression_screen != null:
		progression_screen.input_locked = encounter_input_locked
	if archive_screen != null:
		archive_screen.input_locked = encounter_input_locked


# ---------------------------------------------------------------- input

func _notification(what: int) -> void:
	# Releasing input on focus loss prevents a held key from sticking when the
	# player alt-tabs away mid-run.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if world != null:
			world.release_input()
		Input.action_release("move_up")
		Input.action_release("move_down")
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_release("run")
		# A sequence must never play on unseen.
		if (screen == Screen.LAUNCH or screen == Screen.CINEMATIC) and dialogue == null:
			_open_pause()


## True when Esc opens the shared pause menu on the current screen.
func uses_main_pause() -> bool:
	return screen in MAIN_PAUSE_SCREENS


## Mouse position in screen space (640x360). Read from the overlay layer, which
## no camera moves, so hit regions match what is drawn at any window size,
## letterbox or world camera offset.
func _ui_mouse() -> Vector2:
	if _overlay != null:
		return _overlay.get_local_mouse_position()
	return get_local_mouse_position()


func _unhandled_input(event: InputEvent) -> void:
	# The construction console owns its own input while it is open.
	if screen == Screen.CONSTRUCTION:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
		return

	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_M:
		var muted: bool = bool(audio.toggle_muted())
		ui.notify("AUDIO MUTED" if muted else "AUDIO ON", "info")
		return

	if dialogue != null:
		_handle_dialogue_key(key_event.keycode)
		return

	# Esc is the one pause key (normally taken in _input before reaching here).
	if key_event.keycode == KEY_ESCAPE and uses_main_pause():
		audio.sfx_back()
		_open_pause()
		return

	# Screens that own their whole keyboard take it before the global match, so a
	# letter can never leak into the campaign shortcuts below.
	match screen:
		Screen.FINAL_ASSEMBLY:
			if assembly_screen != null:
				assembly_screen.handle_key(key_event.keycode)
			return
		Screen.CINEMATIC:
			if cinematic_screen != null:
				cinematic_screen.handle_key(key_event.keycode)
			return
		Screen.REPORT:
			if report_screen != null:
				report_screen.handle_key(key_event.keycode)
			return
		Screen.CREDITS:
			if credits_screen != null:
				credits_screen.handle_key(key_event.keycode)
			return

	match screen:
		Screen.TITLE:
			_title_key(key_event.keycode)
		Screen.SETTINGS:
			_settings_key(key_event.keycode)
		Screen.WORLD:
			_world_key(key_event.keycode)
		Screen.LAUNCH:
			_launch_key(key_event.keycode)
		Screen.MEMORY:
			_memory_key(key_event.keycode)
		Screen.CHECKPOINT:
			_checkpoint_key(key_event.keycode)
		Screen.SAVE_ERROR:
			_save_error_key(key_event.keycode)
		Screen.JOURNAL:
			_journal_key(key_event.keycode)


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	var pos: Vector2 = _ui_mouse()
	if dialogue != null:
		return
	match screen:
		Screen.TITLE:
			if title_menu.hover(pos):
				audio.sfx_select()
				queue_redraw()
		Screen.SETTINGS:
			_settings_mouse_motion(pos)
		Screen.SAVE_ERROR:
			if save_error_menu.hover(pos):
				audio.sfx_select()
		Screen.WORLD:
			if world != null:
				world.handle_mouse_motion()
				if mm.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
					world.handle_mouse_click((mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	var pos: Vector2 = _ui_mouse()
	if screen == Screen.SETTINGS and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_settings_release()
		return
	if not mb.pressed:
		return

	if dialogue != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_dialogue_key(KEY_ENTER)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_handle_dialogue_key(KEY_ESCAPE)
		return

	# Right-click is the mouse twin of Esc on every screen with the shared pause.
	if mb.button_index == MOUSE_BUTTON_RIGHT and uses_main_pause():
		audio.sfx_back()
		_open_pause()
		return

	match screen:
		Screen.TITLE:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var idx: int = title_menu.item_at(pos)
				if idx >= 0:
					title_menu.index = idx
					_title_activate()
					queue_redraw()
		Screen.SETTINGS:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_settings_click(pos)
		Screen.WORLD:
			if mb.button_index == MOUSE_BUTTON_LEFT and world != null:
				# The interaction prompt and the zone badge (the pause button) are
				# HUD buttons; any other click walks.
				if world.focused_prop() != null and Rect2(220, 290, 200, 28).has_point(pos):
					world.try_interact()
				elif ui.hud_menu_rect.has_point(pos):
					audio.sfx_back()
					_open_pause()
				else:
					world.handle_mouse_click(mb.double_click)
		Screen.LAUNCH:
			if mb.button_index == MOUSE_BUTTON_LEFT and launch_phase == LaunchPhase.SIGNAL and SIGNAL_LOCK_BUTTON.has_point(pos):
				_signal_lock()
		Screen.MEMORY:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if MEMORY_SKIP.has_point(pos):
					_skip_memory()
				else:
					_memory_key(KEY_ENTER)
		Screen.CHECKPOINT:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if CHECKPOINT_CONTINUE.has_point(pos):
					_checkpoint_key(KEY_ENTER)
				elif CHECKPOINT_MENU.has_point(pos):
					audio.sfx_back()
					_open_pause()
		Screen.JOURNAL:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if ui.journal_back_rect.has_point(pos):
					_journal_key(KEY_ESCAPE)
				else:
					var row: int = ui.journal_row_at(pos)
					if row >= 0 and row != journal_index:
						journal_index = row
						audio.sfx_select()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_journal_key(KEY_ESCAPE)
		Screen.SAVE_ERROR:
			if mb.button_index == MOUSE_BUTTON_LEFT and save_error_menu.click(pos) != "":
				_save_error_key(KEY_ENTER)


# ---------------------------------------------------------------- title

func _title_key(key: int) -> void:
	match key:
		KEY_UP, KEY_W:
			title_menu.move_enabled(-1)
			audio.sfx_select()
		KEY_DOWN, KEY_S:
			title_menu.move_enabled(1)
			audio.sfx_select()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_title_activate()
		KEY_ESCAPE:
			get_tree().quit()
	queue_redraw()


func _title_activate() -> void:
	if not title_menu.is_current_enabled():
		audio.sfx_denied()
		if title_menu.current_id() == "eco_arena":
			ui.notify("Practice unlocks after the Scrap King falls in the campaign.", "warn", 3.0)
		else:
			ui.notify("No valid save to continue.", "warn")
		return
	match title_menu.current_id():
		"new":
			audio.sfx_confirm()
			campaign.reset_campaign()
			campaign.advance_to(SFCampaign.STAGE_BRIEFING)
			campaign.set_checkpoint(SFCampaign.STAGE_BRIEFING, SFCampaign.CHAPTER_PRESENT)
			zone = "spaceport"
			_go(Screen.WORLD)
			_start_briefing()
		"continue":
			_continue_game()
		"eco_arena":
			_start_eco_practice()
		"settings":
			audio.sfx_blip()
			_go(Screen.SETTINGS)
		"quit":
			get_tree().quit()


func _continue_game() -> void:
	var result: Dictionary = SFSave.load_into(campaign)
	if not bool(result.get("ok", false)):
		audio.sfx_denied()
		save_error_text = String(result.get("error", "The save could not be loaded."))
		_go(Screen.SAVE_ERROR)
		return
	audio.sfx_confirm()
	var warnings: Array = result.get("warnings", []) as Array
	if not warnings.is_empty():
		ui.notify(String(warnings[0]), "warn", 4.0)
	_resume_from_campaign()


## Places the player where the saved campaign stage left off. This is the only
## place that maps campaign stages onto screens.
func _resume_from_campaign() -> void:
	match campaign.chapter_id:
		SFCampaign.CHAPTER_CITY:
			zone = "forgotten_city"
		SFCampaign.CHAPTER_COAST:
			zone = "silent_coast"
		SFCampaign.CHAPTER_DAWN:
			zone = "dawn_tower"
		SFCampaign.CHAPTER_PRESENT:
			zone = "spaceport"
		_:
			zone = "crash_site"
	match campaign.stage:
		SFCampaign.STAGE_MENU:
			campaign.advance_to(SFCampaign.STAGE_BRIEFING)
			_go(Screen.WORLD)
			_start_briefing()
		SFCampaign.STAGE_BRIEFING:
			_go(Screen.WORLD)
			_start_briefing()
		SFCampaign.STAGE_CONSTRUCTION:
			_go(Screen.CONSTRUCTION)
		SFCampaign.STAGE_LAUNCH, SFCampaign.STAGE_FLIGHT:
			# The first launch is never skipped: a save made mid-sequence (or a
			# return to the menu from its pause) replays it from the pad.
			campaign.advance_to(SFCampaign.STAGE_LAUNCH)
			_go(Screen.LAUNCH)
		SFCampaign.STAGE_CRASH_INTRO, SFCampaign.STAGE_CRASH_SITE:
			_go(Screen.WORLD)
		SFCampaign.STAGE_MEMORY:
			_go(Screen.WORLD)
			if campaign.has_flag(SFCampaign.FLAG_POWER_REPAIRED):
				_begin_memory()
		SFCampaign.STAGE_CHECKPOINT, SFCampaign.STAGE_COMPLETE:
			# An old save that finished Phase 1 resumes at the Phase 1 summary,
			# which now continues into the Forgotten City.
			_go(Screen.CHECKPOINT)
		SFCampaign.STAGE_CITY_INTRO:
			_go(Screen.WORLD)
			if not campaign.has_flag(SFCampaign.FLAG_CITY_ENTERED):
				_show_city_intro()
		SFCampaign.STAGE_CITY_BOSS, SFCampaign.STAGE_CITY_ARCHIVE:
			# A partially completed fight is never serialised: the checkpoint
			# before the encounter is the resume point. A defeated boss whose
			# chip was never picked up reopens the arena with the chip and the
			# Super Core waiting (older saves too); a collected chip goes on to
			# the archive.
			var city_state: String = _city_reward_state()
			if city_state == SFCampaign.REWARD_UNDEFEATED or city_state == SFCampaign.REWARD_AVAILABLE:
				_begin_city_boss()
			else:
				campaign.advance_to(SFCampaign.STAGE_CITY_ARCHIVE)
				_enter_archive_scene(SFCampaign.ARCHIVE_CITY)
		SFCampaign.STAGE_SILENT_INTRO:
			_go(Screen.WORLD)
			if not campaign.has_flag(SFCampaign.FLAG_COAST_ENTERED):
				_show_coast_intro()
		SFCampaign.STAGE_COAST_BOSS, SFCampaign.STAGE_COAST_ARCHIVE:
			# A defeated Toxic Tide is never fought again: an uncollected power
			# core waits on the quay (older saves too); a collected one goes on
			# to the archive.
			match _coast_reward_state():
				SFCampaign.REWARD_UNDEFEATED:
					_begin_coast_boss()
				SFCampaign.REWARD_AVAILABLE:
					campaign.advance_to(SFCampaign.STAGE_SILENT_INTRO)
					zone = "silent_coast"
					_go(Screen.WORLD)
				_:
					campaign.advance_to(SFCampaign.STAGE_COAST_ARCHIVE)
					_enter_archive_scene(SFCampaign.ARCHIVE_COAST)
		SFCampaign.STAGE_BASE_RETURN:
			_go(Screen.PROGRESSION)
		SFCampaign.STAGE_PHASE_TWO_COMPLETE:
			_go(Screen.CHECKPOINT)
		SFCampaign.STAGE_DAWN_INTRO:
			_go(Screen.WORLD)
			if not campaign.has_flag(SFCampaign.FLAG_DAWN_ENTERED):
				_show_dawn_intro()
		SFCampaign.STAGE_DAWN_BOSS:
			# Never resumed mid-fight: the pre-boss checkpoint is the resume point.
			# A boss already defeated is never fought again: resume on the slope,
			# where an uncollected shield is still waiting.
			if campaign.has_flag(SFCampaign.FLAG_SKY_REMNANT_DEFEATED):
				campaign.advance_to(SFCampaign.STAGE_DAWN_INTRO)
				_go(Screen.WORLD)
			else:
				_begin_dawn_boss()
		SFCampaign.STAGE_DAWN_ARCHIVE:
			_enter_archive_scene(SFCampaign.ARCHIVE_DAWN)
		SFCampaign.STAGE_RECONSTRUCTION:
			_go(Screen.WORKSHOP)
		SFCampaign.STAGE_READY:
			_go(Screen.CHECKPOINT)
		SFCampaign.STAGE_FINAL_ASSEMBLY:
			# The design is frozen and the snapshot is safe. Resuming here reopens
			# the gate, which continues into the installation and the escape.
			_go(Screen.FINAL_ASSEMBLY)
		SFCampaign.STAGE_ESCAPE:
			# A cinematic is never resumed mid-flight: the pre-finale checkpoint
			# (final_assembly) is the documented safe resume point.
			_replay_escape()
		SFCampaign.STAGE_RETURN_HOME, SFCampaign.STAGE_MISSION_REPORT:
			_go(Screen.REPORT)
		SFCampaign.STAGE_CREDITS:
			_go(Screen.CREDITS)
		_:
			_go(Screen.WORLD)


# ---------------------------------------------------------------- settings

func _settings_key(key: int) -> void:
	match key:
		KEY_UP, KEY_W:
			settings_menu.move_enabled(-1)
			audio.sfx_select()
		KEY_DOWN, KEY_S:
			settings_menu.move_enabled(1)
			audio.sfx_select()
		KEY_LEFT, KEY_A:
			_settings_adjust(-1)
		KEY_RIGHT, KEY_D:
			_settings_adjust(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if settings_menu.current_id() == "back":
				_settings_back()
			else:
				_settings_adjust(1)
		KEY_ESCAPE:
			_settings_back()
	queue_redraw()
	refresh_overlay()


## Leaves the settings panel for its parent: the pause menu when it was opened
## there, otherwise the title. Values are already applied and saved.
func _settings_back() -> void:
	audio.sfx_back()
	_slider_drag = ""
	_save_settings()
	if pause_settings_open:
		pause_settings_open = false
		refresh_overlay()
		return
	_go(Screen.TITLE)


func _settings_adjust(direction: int) -> void:
	var id := String(settings_menu.current_id())
	if id in VOLUME_IDS:
		_set_volume(id, float(settings.get(id, 1.0)) + 0.1 * float(direction))
		audio.sfx_select()
		_save_settings()
		return
	match id:
		"text_speed":
			if direction > 0:
				setting_text_speed = 90.0 if setting_text_speed >= 90.0 else (90.0 if setting_text_speed > 45.0 else 52.0)
			else:
				setting_text_speed = 30.0 if setting_text_speed <= 45.0 else 52.0
			if dialogue != null:
				dialogue.chars_per_second = setting_text_speed
			audio.sfx_select()
		"reduced_motion":
			setting_reduced_motion = not setting_reduced_motion
			apply_reduced_motion()
			audio.sfx_select()
		_:
			return
	_rebuild_settings_menu()
	_save_settings()
	queue_redraw()
	refresh_overlay()


func _set_volume(id: String, value: float) -> void:
	settings[id] = snappedf(clampf(value, 0.0, 1.0), 0.05)
	_apply_volumes()
	queue_redraw()
	refresh_overlay()


## The slider track inside a settings row.
func _slider_rect(row: Rect2) -> Rect2:
	return Rect2(row.position.x + 150.0, row.position.y + 6.0, row.size.x - 210.0, 8.0)


func _slider_value_at(id: String, pos: Vector2) -> void:
	var i: int = settings_menu.index_of(id)
	if i < 0 or i >= settings_menu.rects.size():
		return
	var bar := _slider_rect(settings_menu.rects[i] as Rect2)
	_set_volume(id, (pos.x - bar.position.x) / maxf(1.0, bar.size.x))


func _settings_mouse_motion(pos: Vector2) -> void:
	if _slider_drag != "":
		_slider_value_at(_slider_drag, pos)
		return
	if settings_menu.hover(pos):
		audio.sfx_select()
		queue_redraw()
		refresh_overlay()


## A click selects the row and acts once: a slider jumps to the pointer and
## follows it while the button is held, a toggle changes, BACK goes back.
func _settings_click(pos: Vector2) -> void:
	var i: int = settings_menu.item_at(pos)
	if i < 0:
		return
	settings_menu.index = i
	var id := String(settings_menu.current_id())
	if id in VOLUME_IDS:
		_slider_drag = id
		_slider_value_at(id, pos)
		audio.sfx_select()
	elif id == "back":
		_settings_back()
	else:
		_settings_adjust(1)
	queue_redraw()
	refresh_overlay()


func _settings_release() -> void:
	if _slider_drag != "":
		_slider_drag = ""
		_save_settings()


## Draws the settings panel onto `ci` (the controller on the title screen, the
## overlay inside the pause menu), and records the row rects for the mouse.
func draw_settings_panel(ci: CanvasItem) -> void:
	var panel := SETTINGS_PANEL
	ui.modal(ci, panel)
	skin.text(ci, panel.position + Vector2(14, 12), "SETTINGS", SFPalette.CYAN)
	var origin := panel.position + Vector2(20, 30)
	var width := panel.size.x - 40.0
	var rects: Array = []
	for i in settings_menu.items.size():
		var item: Dictionary = settings_menu.items[i] as Dictionary
		var r := Rect2(origin.x, origin.y + float(i) * SETTINGS_ROW_H, width, SETTINGS_ROW_H - 2.0)
		var focused: bool = i == settings_menu.index
		skin.button(ci, r, "", focused, true)
		var id := String(item.get("id", ""))
		if id == "back":
			skin.text_c(ci, r.position.x + r.size.x * 0.5, r.position.y + 6, "BACK", SFPalette.PAPER)
		else:
			skin.text(ci, r.position + Vector2(10, 6), String(item.get("label", "")), SFPalette.PAPER)
		if bool(item.get("slider", false)):
			var v: float = float(settings.get(id, 1.0))
			var bar := _slider_rect(r)
			ci.draw_rect(bar, SFPalette.INK, true)
			ci.draw_rect(Rect2(bar.position, Vector2(round(bar.size.x * v), bar.size.y)), SFPalette.CYAN if focused else SFPalette.CYAN_DIM, true)
			ci.draw_rect(bar, SFPalette.STEEL_DARK, false, 1.0)
			ci.draw_rect(Rect2(bar.position.x + round(bar.size.x * v) - 1, bar.position.y - 2, 3, bar.size.y + 4), SFPalette.PAPER, true)
			skin.text_r(ci, r.end.x - 10, r.position.y + 6, "%d%%" % int(round(v * 100.0)), SFPalette.PAPER_DIM)
		elif String(item.get("detail", "")) != "":
			skin.text_r(ci, r.end.x - 10, r.position.y + 6, String(item.get("detail", "")), SFPalette.CYAN_DIM if not focused else SFPalette.CYAN)
		rects.append(r)
	settings_menu.rects = rects
	var y := origin.y + float(settings_menu.items.size()) * SETTINGS_ROW_H + 6.0
	skin.wrap(ci, Vector2(origin.x, y), width,
		"Saved on this computer. Nothing here changes the campaign, the report or the score. Reduced motion removes screen shake and flashes.",
		SFPalette.PAPER_DIM, 1, 3)
	skin.text_c(ci, panel.position.x + panel.size.x * 0.5, panel.end.y - 14,
		"UP/DOWN SELECT   LEFT/RIGHT OR DRAG ADJUST   ESC BACK", SFPalette.ASH_LIGHT)


# ---------------------------------------------------------------- world

func _world_key(key: int) -> void:
	match key:
		KEY_ESCAPE:
			audio.sfx_back()
			_open_pause()
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if world != null:
				world.try_interact()


func _on_world_focus_changed(label: String) -> void:
	queue_redraw()


func _open_pause() -> void:
	if pause_open or not uses_main_pause():
		return
	_rebuild_pause_menu()
	pause_menu.index = 0
	pause_open = true
	pause_settings_open = false
	if world != null:
		world.set_input_enabled(false)
		world.release_input()
	for action in ["move_up", "move_down", "move_left", "move_right", "run"]:
		Input.action_release(action)
	# The screen underneath is frozen outright: no process, no input. Its timers,
	# spawns, cinematic clock and animations all stop where they are.
	_pause_node = _paused_screen_node()
	if _pause_node != null:
		_pause_node.process_mode = Node.PROCESS_MODE_DISABLED
	if cinematic_screen != null:
		cinematic_screen.paused = true
	audio.set_paused(true)
	refresh_overlay()


func _paused_screen_node() -> Node:
	match screen:
		Screen.WORLD:
			return _world_scene
		Screen.ARCHIVE:
			return archive_screen
		Screen.PROGRESSION:
			return progression_screen
		Screen.FINAL_ASSEMBLY:
			return assembly_screen
		Screen.CINEMATIC:
			return cinematic_screen
		Screen.REPORT:
			return report_screen
		Screen.CREDITS:
			return credits_screen
	return null


func _resume_paused_node() -> void:
	if _pause_node != null and is_instance_valid(_pause_node):
		_pause_node.process_mode = Node.PROCESS_MODE_INHERIT
	_pause_node = null
	if cinematic_screen != null:
		cinematic_screen.paused = false


func _close_pause() -> void:
	if not pause_open:
		return
	pause_open = false
	pause_settings_open = false
	_slider_drag = ""
	_resume_paused_node()
	apply_focus_state()
	audio.set_paused(false)
	refresh_overlay()


# ---------------------------------------------------------------- interaction

func _on_world_interact(object_id: String, prop) -> void:
	match object_id:
		"briefing":
			_start_briefing()
		"construction":
			if not campaign.has_flag(SFCampaign.FLAG_BRIEFING_READ):
				_open_dialogue(["The console wants a mission authorization.", "Read the briefing terminal first."], "CONSOLE")
				audio.sfx_denied()
			else:
				audio.sfx_blip()
				_go(Screen.CONSTRUCTION)
		"vela":
			_inspect_vela()
		"launch":
			_attempt_launch()
		"crates", "dish":
			var lines: Array = prop.lines as Array if prop != null else []
			_open_dialogue(lines, "INSPECTION")
		"crash_vela":
			if campaign.has_flag(SFCampaign.FLAG_WORKSHOP_UNLOCKED):
				audio.sfx_blip()
				_go(Screen.WORKSHOP)
			else:
				_inspect_wreck()
		"bill_body":
			_interact_bill(prop)
		"power_connection":
			_repair_junction()
		# Phase 2: Forgotten City.
		"memory_city_green":
			var city_lines: Array = campaign.content.dialogue_lines("city_memory")
			_open_dialogue(city_lines, "MAINTENANCE SHRINE", Callable(self, "_on_city_shrine_done"))
		"city_checkpoint", "coast_checkpoint":
			_use_checkpoint(object_id)
		"city_boss_gate":
			_approach_city_gate()
		# Phase 2: Silent Coast.
		"memory_green_coast":
			var coast_lines: Array = campaign.content.dialogue_lines("coast_memory")
			_open_dialogue(coast_lines, "COASTAL PROJECTOR", Callable(self, "_on_coast_shrine_done"))
		"coast_records":
			_read_coast_records()
		"sample_coast_water", "sample_coast_sediment":
			_take_sample(object_id)
		"coast_boss_gate":
			_approach_coast_gate()
		"coast_power_core_drop":
			_collect_power_core_drop()
		# Phase 3: Dawn Tower.
		"dawn_memory":
			_open_dialogue(campaign.content.dialogue_lines("dawn_memory"), "SURVEY PROJECTOR",
				Callable(self, "_on_dawn_projector_done"))
		"dawn_checkpoint":
			_use_dawn_checkpoint()
		"dawn_terminal":
			_open_dialogue(campaign.content.dialogue_lines("dawn_terminal"), "DEFENSE CONSOLE")
		"dawn_boss_gate":
			_approach_dawn_gate()
		"dawn_shield_drop":
			_collect_shield_drop()
		_:
			if object_id.begins_with("salvage") or object_id == "scrap_extra":
				_collect_salvage(object_id)


## After the city shrine's dialogue, play the optional memory itself. The memory
## screen returns to the world, not to a chapter transition.
func _on_city_shrine_done() -> void:
	_view_chapter_memory(SFCampaign.MEMORY_CITY_GREEN, Callable(self, "_return_to_world"))


func _on_coast_shrine_done() -> void:
	_view_chapter_memory(SFCampaign.MEMORY_GREEN_COAST, Callable(self, "_return_to_world"))


func _return_to_world() -> void:
	audio.set_ambience(_world_ambience(zone))
	_go(Screen.WORLD)


## The control-center door. It refuses entry until the checkpoint is used, so
## the player always has a resume point before the fight, and the refusal is
## diegetic rather than a system message.
func _approach_city_gate() -> void:
	if _transition_busy or screen != Screen.WORLD or dialogue != null:
		return
	if campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED):
		_transition_busy = true
		if _city_reward_state() == SFCampaign.REWARD_AVAILABLE:
			_begin_city_boss()
			return
		if not campaign.has_flag(SFCampaign.FLAG_CITY_ARCHIVE_RESTORED):
			campaign.advance_to(SFCampaign.STAGE_CITY_ARCHIVE)
			_enter_archive_scene(SFCampaign.ARCHIVE_CITY)
			return
		_open_dialogue(["The archive inside is already restored.", "The route south to the Silent Coast is open."], "CONTROL CENTER", Callable(self, "_travel_city_to_coast"))
		return
	if not campaign.has_flag(SFCampaign.FLAG_CITY_CHECKPOINT):
		audio.sfx_denied()
		_open_dialogue([
			"The door is welded shut. Something inside is already moving.",
			"Nick: \"Not without a saved route. If this goes wrong I want to come back here, not to the ridge.\"",
			"Use the checkpoint marker in the street first.",
		], "CONTROL CENTER DOOR")
		return
	_transition_busy = true
	_begin_city_boss()


func _approach_coast_gate() -> void:
	if _transition_busy or screen != Screen.WORLD or dialogue != null:
		return
	if campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED):
		if _coast_reward_state() == SFCampaign.REWARD_AVAILABLE:
			_open_dialogue(["Bill: \"The power core fell out of the intake onto the quay. It is still warm. Pick it up first.\""], "CLEANUP FACILITY")
			return
		_transition_busy = true
		if not campaign.has_flag(SFCampaign.FLAG_COAST_ARCHIVE_RESTORED):
			campaign.advance_to(SFCampaign.STAGE_COAST_ARCHIVE)
			_enter_archive_scene(SFCampaign.ARCHIVE_COAST)
			return
		_open_dialogue(["The facility is quiet. The archive inside is already restored.", "The route back to the crash-site base is clear."], "CLEANUP FACILITY", Callable(self, "_travel_coast_to_base"))
		return
	if not campaign.has_flag(SFCampaign.FLAG_COAST_CHECKPOINT):
		audio.sfx_denied()
		_open_dialogue([
			"The intake is still pumping. The unit inside treats everything as contamination.",
			"Nick: \"Checkpoint first. I am not walking into that without a way back.\"",
			"Use the harbor checkpoint on the quay.",
		], "CLEANUP FACILITY INTAKE")
		return
	_transition_busy = true
	_begin_coast_boss()


func _travel_city_to_coast() -> void:
	_transition_busy = false
	zone = "silent_coast"
	if campaign.stage == SFCampaign.STAGE_CITY_INTRO or campaign.stage == SFCampaign.STAGE_CITY_BOSS or campaign.stage == SFCampaign.STAGE_CITY_ARCHIVE:
		campaign.advance_to(SFCampaign.STAGE_SILENT_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_SILENT_INTRO, SFCampaign.CHAPTER_COAST)
	_save_quietly()
	_go(Screen.WORLD)
	if not campaign.has_flag(SFCampaign.FLAG_COAST_ENTERED):
		_show_coast_intro()


func _travel_coast_to_base() -> void:
	_transition_busy = false
	_enter_base_return(true)


## Launch is available only from a confirmed design. Pressing the beacon
## before that points the player back at the console.
func _attempt_launch() -> void:
	if campaign.has_flag(SFCampaign.FLAG_DESIGN_CONFIRMED) and campaign.has_confirmed_design():
		audio.sfx_confirm()
		campaign.advance_to(SFCampaign.STAGE_LAUNCH)
		_go(Screen.LAUNCH)
		return
	audio.sfx_denied()
	var lines: Array = ["The pad is cold. No flight clearance has been filed."]
	if not campaign.has_flag(SFCampaign.FLAG_BRIEFING_READ):
		lines.append("Read the mission briefing at the terminal first.")
	else:
		lines.append("Assemble the VELA at the console and pass preflight.")
	lines.append("Nothing launches until the design is confirmed.")
	_open_dialogue(lines, "LAUNCH PLATFORM")


func _start_briefing() -> void:
	var lines: Array = []
	lines.append_array(campaign.content.dialogue_lines("briefing_intro"))
	lines.append_array(campaign.content.dialogue_lines("briefing_requirements"))
	lines.append_array(campaign.content.dialogue_lines("briefing_outro"))
	_open_dialogue(lines, "MISSION BRIEFING", Callable(self, "_on_briefing_done"))


func _on_briefing_done() -> void:
	campaign.set_flag(SFCampaign.FLAG_BRIEFING_READ)
	campaign.advance_to(SFCampaign.STAGE_CONSTRUCTION)
	campaign.set_checkpoint(SFCampaign.STAGE_CONSTRUCTION, SFCampaign.CHAPTER_PRESENT)
	ui.notify("Briefing logged. The assembly console is ready.", "good", 3.0)
	_save_quietly()


func _inspect_vela() -> void:
	var lines: Array = []
	lines.append("The frame is bare. Five slots, and a mission that needs all of them.")
	lines.append("The console beside it holds every part in the program's inventory.")
	lines.append("Build it, run the preflight check, and it flies.")
	_open_dialogue(lines, "VELA / STANDARD HULL")


func _inspect_wreck() -> void:
	var lines: Array = []
	if not campaign.has_flag(SFCampaign.FLAG_VELA_INSPECTED):
		lines.append_array(campaign.content.dialogue_lines("crash_vela"))
		lines.append_array(campaign.content.dialogue_lines("blueprint_memory"))
		campaign.set_flag(SFCampaign.FLAG_VELA_INSPECTED)
		# The launch design leaves a tangible mark: surviving data capacity, and
		# a small amount of extra salvage that scales with the sensor quality.
		var bonus: int = campaign.crash_salvage_bonus()
		var added: int = campaign.add_material("scrap_metal", bonus)
		if added > 0:
			ui.notify("+%d Scrap Metal from the wreck" % added, "salvage", 3.0)
		var data_mb: float = campaign.surviving_data_mb()
		if data_mb > 0.0:
			campaign.mission_manifest["surviving_data_mb"] = data_mb
			lines.append("The flight computer kept %.0f MB of the observation. It is not much, but it is real." % data_mb)
		_save_quietly()
	else:
		var manifest: Dictionary = campaign.mission_manifest
		var q := int(manifest.get("sensor_quality", 0))
		var data := float(manifest.get("surviving_data_mb", 0.0))
		lines.append("The wreck is stable. Sensor quality %d survived the impact." % q)
		lines.append("Recovered science data: %.0f MB." % data)
		if campaign.has_flag(SFCampaign.FLAG_BILL_ACTIVE):
			lines.append("Bill is waiting by the junction. He does not rush me.")
	_open_dialogue(lines, "DAMAGED VELA")


func _collect_salvage(object_id: String) -> void:
	var result: Dictionary = campaign.claim_salvage(object_id)
	if bool(result.get("ok", false)):
		audio.sfx_pickup()
		ui.notify(String(result.get("message", "Collected.")), "salvage")
		if world != null:
			world.remove_prop(object_id)
		Events.salvage_collected.emit(object_id, String(result.get("material", "")), int(result.get("added", 0)))
		_save_quietly()
	else:
		audio.sfx_denied()
		ui.notify(String(result.get("message", "Cannot collect.")), "bad")
		if String(result.get("message", "")).findn("Carry limit") >= 0:
			Events.inventory_full.emit()


func _repair_junction() -> void:
	if campaign.has_flag(SFCampaign.FLAG_POWER_REPAIRED):
		_open_dialogue(["The junction is live. Whatever behind the wall was waiting has power now."], "POWER JUNCTION")
		return
	if not campaign.can_repair_junction():
		audio.sfx_denied()
		var lines: Array = ["The junction needs bridging material and a spare circuit."]
		lines.append("Cost: %s." % campaign.repair_cost_text())
		lines.append("Search the wreck site for salvage.")
		_open_dialogue(lines, "EMERGENCY POWER JUNCTION")
		return
	var result: Dictionary = campaign.repair_junction()
	if bool(result.get("ok", false)):
		if audio.has_method("sfx_spark"):
			audio.sfx_spark()
		audio.sfx_power_up()
		var lines: Array = campaign.content.dialogue_lines("junction_repair")
		_open_dialogue(lines, "POWER RESTORED", Callable(self, "_on_junction_repaired"))
		_save_quietly()
	else:
		audio.sfx_denied()
		ui.notify(String(result.get("message", "")), "bad")


func _on_junction_repaired() -> void:
	if world != null:
		world.set_prop_sprite("power_connection", "junction")
	ui.notify("The dormant robot has power.", "good", 3.0)


func _interact_bill(prop) -> void:
	if campaign.has_flag(SFCampaign.FLAG_BILL_ACTIVE):
		var idle: Array = campaign.content.dialogue_lines("bill_idle")
		_open_dialogue(_pick_idle_lines(idle), "BILL", Callable(self, "_on_bill_idle_done"))
		return
	if not campaign.has_flag(SFCampaign.FLAG_POWER_REPAIRED):
		audio.sfx_denied()
		_open_dialogue([
			"A maintenance unit, folded into the wall. No lights, no movement.",
			"The power junction across the site is dead. Nothing here will wake up without it.",
		], "DORMANT ROBOT")
		return
	if audio.has_method("sfx_bill_boot"):
		audio.sfx_bill_boot()
	else:
		audio.sfx_power_up()
	var lines: Array = campaign.content.dialogue_lines("bill_activation")
	_open_dialogue(lines, "MAINTENANCE UNIT B-4", Callable(self, "_on_bill_activated"))


func _pick_idle_lines(pool: Array) -> Array:
	if pool.is_empty():
		return ["Bill is quiet."]
	var start := int(time / 7.0) % pool.size()
	var out: Array = []
	out.append(String(pool[start]))
	if pool.size() > 1:
		out.append(String(pool[(start + 1) % pool.size()]))
	return out


func _on_bill_idle_done() -> void:
	pass


func _on_bill_activated() -> void:
	campaign.set_flag(SFCampaign.FLAG_BILL_ACTIVE)
	_sync_world_actors()
	audio.sfx_memory()
	_begin_memory()


# ---------------------------------------------------------------- dialogue

func _open_dialogue(lines: Array, title_text: String = "", on_done: Callable = Callable()) -> void:
	if lines.is_empty():
		return
	dialogue = SFDialogue.new(lines, title_text)
	dialogue.chars_per_second = setting_text_speed
	dialogue_title = title_text
	dialogue_next = on_done
	apply_focus_state()
	queue_redraw()


func _handle_dialogue_key(key: int) -> void:
	match key:
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			var finished: bool = dialogue.advance()
			if dialogue_title == "BILL" and audio.has_method("sfx_blip_bill"):
				audio.sfx_blip_bill()
			elif (dialogue_title.findn("CONTROL") >= 0 or dialogue_title.findn("COMM") >= 0 or dialogue_title.findn("RADIO") >= 0) and audio.has_method("sfx_blip_control"):
				audio.sfx_blip_control()
			elif audio.has_method("sfx_blip_nick"):
				audio.sfx_blip_nick()
			else:
				audio.sfx_blip()
			if finished:
				var cb := dialogue_next
				dialogue = null
				dialogue_next = Callable()
				apply_focus_state()
				if cb.is_valid():
					cb.call()
			queue_redraw()
		KEY_ESCAPE:
			# Escape closes the overlay without skipping required state changes.
			# The completion callback still runs, so no flags are lost.
			var cb2 := dialogue_next
			dialogue = null
			dialogue_next = Callable()
			apply_focus_state()
			audio.sfx_back()
			if cb2.is_valid():
				cb2.call()
			queue_redraw()


# ---------------------------------------------------------------- construction

func _on_construction_closed() -> void:
	audio.set_ambience("earth") if campaign.chapter_id == SFCampaign.CHAPTER_PRESENT else audio.set_ambience("ruin")
	_go(Screen.WORLD)


func _on_design_confirmed() -> void:
	# The construction screen already validated and committed atomically.
	campaign.advance_to(SFCampaign.STAGE_LAUNCH)
	campaign.set_checkpoint(SFCampaign.STAGE_LAUNCH, SFCampaign.CHAPTER_PRESENT)
	_save_quietly()
	_go(Screen.LAUNCH)


# ---------------------------------------------------------------- launch

func _begin_launch() -> void:
	launch_phase = LaunchPhase.COUNTDOWN
	launch_timer = 0.0
	signal_locks = 0
	signal_attempts = 0
	signal_timer = 0.0
	signal_marker = 0.5
	signal_phase = 0.0
	signal_manual = 0.0
	signal_target = randf_range(0.25, 0.75)
	crash_shake = 0.0
	audio.set_ambience("none")
	audio.sfx_confirm()
	queue_redraw()


func _launch_key(key: int) -> void:
	# The launch sequence cannot be skipped, in any build. Esc pauses (handled
	# before this); only the signal investigation takes keys: A/D or the arrows
	# tune the reticle (read in _process_launch), E / Enter / Space lock it.
	match key:
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if launch_phase == LaunchPhase.SIGNAL:
				_signal_lock()


func _signal_lock() -> void:
	signal_attempts += 1
	var dist := absf(signal_marker - signal_target)
	if dist < 0.09:
		signal_locks += 1
		if audio.has_method("sfx_signal_lock"):
			audio.sfx_signal_lock()
		else:
			audio.sfx_confirm()
		signal_target = randf_range(0.2, 0.8)
	else:
		audio.sfx_denied()
	if signal_locks >= 3:
		launch_phase = LaunchPhase.RIFT
		launch_timer = 0.0
		audio.sfx_rift()
	queue_redraw()


## Applies the full post-launch state and moves on. Idempotent, so pressing
## skip twice is harmless.
func _finish_launch_state() -> void:
	campaign.set_flag(SFCampaign.FLAG_LAUNCHED)
	campaign.set_flag(SFCampaign.FLAG_RIFT_SEEN)
	campaign.set_flag(SFCampaign.FLAG_CRASHED)
	campaign.advance_to(SFCampaign.STAGE_CRASH_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_CRASH_SITE, SFCampaign.CHAPTER_CRASH)
	_save_quietly()
	zone = "crash_site"
	_go(Screen.WORLD)
	_show_crash_intro()


func _show_crash_intro() -> void:
	# The "crash" lines already played as captions during the cutscene.
	_on_crash_intro_done()


func _on_crash_intro_done() -> void:
	campaign.advance_to(SFCampaign.STAGE_CRASH_SITE)
	campaign.set_checkpoint(SFCampaign.STAGE_CRASH_SITE, SFCampaign.CHAPTER_CRASH)
	if audio.has_method("sfx_checkpoint"):
		audio.sfx_checkpoint()
	ui.notify("Explore the wreck site. E to interact.", "info", 3.0)


func _process_launch(delta: float) -> void:
	launch_timer += delta
	match launch_phase:
		LaunchPhase.COUNTDOWN:
			# One beep per displayed number (T-3, T-2, T-1), in step with _draw_countdown.
			var step: int = int(launch_timer / 0.85)
			if (launch_timer <= delta or step != int((launch_timer - delta) / 0.85)) and step < 3:
				if audio.has_method("sfx_countdown"):
					audio.sfx_countdown()
			if launch_timer > COUNTDOWN_SECONDS:
				launch_phase = LaunchPhase.ASCENT
				launch_timer = 0.0
				# Ignition: the roar starts with the flame at the bottom nozzles.
				audio.sfx_launch()
		LaunchPhase.ASCENT:
			# Liftoff gets its own push as VELA leaves the pad.
			if launch_timer - delta < IGNITION_END and launch_timer >= IGNITION_END:
				audio.sfx_launch()
			if launch_timer > ASCENT_SECONDS:
				launch_phase = LaunchPhase.SIGNAL
				launch_timer = 0.0
				if audio.has_method("sfx_signal_sweep"):
					audio.sfx_signal_sweep()
		LaunchPhase.SIGNAL:
			signal_timer += delta
			# The reticle sweeps on its own; A/D or the arrows steer it, and the
			# sweep resumes from wherever the player left it.
			var steer: float = Input.get_axis("move_left", "move_right")
			if absf(steer) > 0.1:
				signal_marker = clampf(signal_marker + steer * 0.55 * delta, 0.0, 1.0)
				signal_manual = 1.2
				signal_phase = asin(clampf((signal_marker - 0.5) / 0.42, -1.0, 1.0))
			elif signal_manual > 0.0:
				signal_manual = maxf(0.0, signal_manual - delta)
			else:
				signal_phase += delta * 2.1
				signal_marker = 0.5 + 0.42 * sin(signal_phase)
			# The sequence always resolves. Three locks are the guided path; a
			# player who never presses the key still reaches the rift.
			if signal_timer > 20.0:
				launch_phase = LaunchPhase.RIFT
				launch_timer = 0.0
				audio.sfx_rift()
		LaunchPhase.RIFT:
			crash_shake = sin(launch_timer * 24.0) * 3.0
			if launch_timer - delta < 1.0 and launch_timer >= 1.0:
				if audio.has_method("sfx_alarm"):
					audio.sfx_alarm()
			if launch_timer - delta < 2.0 and launch_timer >= 2.0:
				if audio.has_method("sfx_hull_creak"):
					audio.sfx_hull_creak()
			if launch_timer > 3.2:
				launch_phase = LaunchPhase.CRASH
				launch_timer = 0.0
				trigger_flash_transition(0.6)
				audio.sfx_impact()
		LaunchPhase.CRASH:
			crash_shake = maxf(0.0, crash_shake - delta * 4.0)
			if launch_timer > 3.8:
				launch_phase = LaunchPhase.DONE
				_finish_launch_state()


# ---------------------------------------------------------------- memory

func _begin_memory() -> void:
	_play_memory(SFCampaign.MEMORY_GREEN_CITY, Callable(self, "_finish_memory"))


## Plays any memory from campaign.json, then runs `on_done`. Phase 1 uses this
## for the Green City and the end-of-Phase-1 checkpoint; Phase 2 uses it for the
## optional chapter memories, which return to the world instead.
func _play_memory(id: String, on_done: Callable) -> void:
	memory_id = id
	memory_index = 0
	memory_chars = 0.0
	memory_next = on_done
	audio.set_ambience("none")
	campaign.view_memory(id)
	Events.memory_viewed.emit(id)
	_save_quietly()
	_go(Screen.MEMORY)
	# After the screen change, which cuts gameplay sounds from the last screen.
	audio.sfx_memory()


func _memory_lines() -> Array:
	return campaign.content.memory(memory_id).get("lines", []) as Array


func _memory_key(key: int) -> void:
	match key:
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			var line := String(_memory_lines()[mini(memory_index, _memory_lines().size() - 1)]) if not _memory_lines().is_empty() else ""
			if int(memory_chars) < line.length():
				memory_chars = float(line.length())
				audio.sfx_select()
			else:
				memory_index += 1
				memory_chars = 0.0
				audio.sfx_blip()
				if memory_index >= _memory_lines().size():
					_finish_memory_playback()


## The explicit skip (the SKIP button or SKIP MEMORY in the pause menu). It runs
## the same completion callback as reading to the end.
func _skip_memory() -> void:
	audio.sfx_back()
	_finish_memory_playback()


## Leaves the memory screen and runs its completion callback. Used by both the
## Phase 1 memory (which ends Phase 1) and the optional Phase 2 memories (which
## return to exploration).
func _finish_memory_playback() -> void:
	var cb := memory_next
	memory_next = Callable()
	if cb.is_valid():
		cb.call()


func _finish_memory() -> void:
	# Every required state change happens here, whether the player read the
	# memory or skipped it.
	campaign.view_memory(memory_id)
	Events.memory_viewed.emit(memory_id)
	campaign.set_flag(SFCampaign.FLAG_COORDINATES_RECEIVED)
	campaign.advance_to(SFCampaign.STAGE_CHECKPOINT)
	campaign.set_checkpoint(SFCampaign.STAGE_CHECKPOINT, SFCampaign.CHAPTER_CRASH)
	_save_quietly()
	_go(Screen.CHECKPOINT)


# ---------------------------------------------------------------- checkpoint

func _checkpoint_key(key: int) -> void:
	match key:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			# Esc pauses here (handled earlier); it never starts the next chapter.
			audio.sfx_confirm()
			# Two different summaries share this screen. After Phase 2 the
			# summary is the stopping point, so it returns to the title with the
			# save intact. After Phase 1 it leads into the Forgotten City, which
			# is where Bill's coordinates point.
			# Phase 3 ends at READY_FOR_FINAL_ASSEMBLY: that summary now opens the
			# Phase 4 final-assembly gate rather than returning to the title.
			if campaign.is_ready_for_final_assembly():
				_save_quietly()
				_go(Screen.FINAL_ASSEMBLY)
				return
			# The Phase 2 summary now continues into the Dawn Tower.
			if campaign.has_flag(SFCampaign.FLAG_PHASE_TWO_COMPLETE):
				campaign.advance_to(SFCampaign.STAGE_DAWN_INTRO)
				campaign.set_checkpoint(SFCampaign.STAGE_DAWN_INTRO, SFCampaign.CHAPTER_DAWN)
				_save_quietly()
				zone = "dawn_tower"
				_go(Screen.WORLD)
				_show_dawn_intro()
				return
			campaign.advance_to(SFCampaign.STAGE_CITY_INTRO)
			campaign.set_checkpoint(SFCampaign.STAGE_CITY_INTRO, SFCampaign.CHAPTER_CITY)
			_save_quietly()
			zone = "forgotten_city"
			_go(Screen.WORLD)
			_show_city_intro()


# ---------------------------------------------------------------- phase 2 world

## Enters the Forgotten City exploration section. Idempotent: the intro only
## plays once, and the checkpoint is only set on first entry.
func _show_city_intro() -> void:
	campaign.set_flag(SFCampaign.FLAG_CITY_ENTERED)
	campaign.advance_to(SFCampaign.STAGE_CITY_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_CITY_INTRO, SFCampaign.CHAPTER_CITY)
	_save_quietly()
	var lines: Array = campaign.content.dialogue_lines("city_intro")
	_open_dialogue(lines, "FORGOTTEN CITY", Callable(self, "_on_city_intro_done"))


func _on_city_intro_done() -> void:
	ui.notify("Follow the street. The control center is at the far end.", "info", 3.0)
	if not campaign.has_flag(SFCampaign.FLAG_CITY_CHECKPOINT):
		ui.notify("Use the checkpoint before the control door.", "warn", 4.0)


func _show_coast_intro() -> void:
	campaign.set_flag(SFCampaign.FLAG_COAST_ENTERED)
	campaign.advance_to(SFCampaign.STAGE_SILENT_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_SILENT_INTRO, SFCampaign.CHAPTER_COAST)
	_save_quietly()
	var lines: Array = campaign.content.dialogue_lines("coast_intro")
	_open_dialogue(lines, "SILENT COAST", Callable(self, "_on_coast_intro_done"))


func _on_coast_intro_done() -> void:
	ui.notify("Optional: samples and records are on the quay.", "info", 4.0)


## The maintenance shrine: an optional memory, safe to view more than once.
func _view_chapter_memory(id: String, done: Callable) -> void:
	if campaign.has_viewed_memory(id):
		audio.sfx_blip()
		ui.notify("This projection has already been archived.", "info", 2.5)
		return
	_play_memory(id, done)


func _use_checkpoint(object_id: String) -> void:
	if object_id == "city_checkpoint":
		var first: bool = not campaign.has_flag(SFCampaign.FLAG_CITY_CHECKPOINT)
		campaign.set_flag(SFCampaign.FLAG_CITY_CHECKPOINT)
		campaign.set_checkpoint(SFCampaign.STAGE_CITY_BOSS, SFCampaign.CHAPTER_CITY)
		_sync_world_actors()
		_save_quietly()
		if first:
			ui.notify("EXIT UNLOCKED: CONTROL CENTER OPEN", "good", 3.5)
		var lines: Array = campaign.content.dialogue_lines("city_checkpoint") if first else [
			"Route marker confirmed. The control center is still ahead.",
			"Saving here means a failed fight does not cost you the walk.",
		]
		_open_dialogue(lines, "CHECKPOINT")
		return
	if object_id == "coast_checkpoint":
		var first_coast: bool = not campaign.has_flag(SFCampaign.FLAG_COAST_CHECKPOINT)
		campaign.set_flag(SFCampaign.FLAG_COAST_CHECKPOINT)
		campaign.set_checkpoint(SFCampaign.STAGE_COAST_BOSS, SFCampaign.CHAPTER_COAST)
		_sync_world_actors()
		_save_quietly()
		if first_coast:
			ui.notify("EXIT UNLOCKED: CLEANUP FACILITY OPEN", "good", 3.5)
		var coast_lines: Array = campaign.content.dialogue_lines("coast_checkpoint") if first_coast else [
			"Harbor marker confirmed. The facility intake is ahead.",
			"Saving here means a failed fight does not cost you the quay.",
		]
		_open_dialogue(coast_lines, "CHECKPOINT")


## The optional coastal research records: flavour, and a small material reward
## for the first read. Never required to finish the chapter.
func _read_coast_records() -> void:
	if not campaign.is_collected("coast_records_read"):
		campaign.mark_collected("coast_records_read")
		var added: int = campaign.add_material("circuitry", 2)
		if added > 0:
			ui.notify("+%d Circuitry recovered from the terminal" % added, "salvage", 3.0)
			_save_quietly()
	_open_dialogue([
		"Catch report, year 14: the report is a formality.",
		"Discharge permit: the ocean was expected to dilute it.",
		"A survey with nine dead sampling points out of ten. The tenth is the outfall.",
		"Nick: \"They documented it. They just did not stop it.\"",
	], "COASTAL RECORDS")


func _take_sample(object_id: String) -> void:
	var entry: Dictionary = {
		"sample_coast_water": {
			"material": "polymer",
			"lines": ["A sealed sample. The vial fogs on the outside, not the inside.",
				"Bill: \"Label it before the label dissolves. That has happened before.\""],
		},
		"sample_coast_sediment": {
			"material": "circuitry",
			"lines": ["Sediment with a rainbow sheen and a smell that survives the seal.",
				"Bill: \"This is evidence. Please do not drop it.\""],
		},
	}.get(object_id, {}) as Dictionary
	if object_id == "" or not campaign.is_collected(object_id):
		campaign.mark_collected(object_id)
		var material := String(entry.get("material", "polymer"))
		var added: int = campaign.add_material(material, 1)
		if added > 0:
			ui.notify("+%d %s" % [added, campaign.content.material_name(material)], "salvage", 2.5)
			_save_quietly()
		else:
			ui.notify("Carry limit reached. The sample can wait.", "warn", 2.5)
	_open_dialogue(entry.get("lines", ["A sealed sample from the shoreline."]) as Array, "SAMPLE")


# ---------------------------------------------------------------- phase 2 bosses

## The Scrap King encounter is the Eco Arena in campaign mode. The control
## center checkpoint is the resume point; a boss already defeated reopens the
## arena with its Super Core and chip still waiting.
func _begin_city_boss() -> void:
	var resume: bool = _city_reward_state() == SFCampaign.REWARD_AVAILABLE
	campaign.advance_to(SFCampaign.STAGE_CITY_BOSS)
	campaign.set_checkpoint(SFCampaign.STAGE_CITY_BOSS, SFCampaign.CHAPTER_CITY)
	_save_quietly()
	zone = "forgotten_city"
	_open_eco_arena("campaign", resume)
	var key: String = "city_reward_waiting" if resume else "city_boss_intro"
	_open_dialogue(campaign.content.dialogue_lines(key), "SCRAP KING'S SORTING YARD")


func _begin_coast_boss() -> void:
	_start_encounter("toxic_tide", "coast_boss_intro")


## Enters a shield-defense encounter. The intro dialogue plays over the arena,
## and the fight does not start until it closes, so the player is never taking
## damage while reading.
func _start_encounter(boss_id: String, intro_key: String) -> void:
	var boss_data: Dictionary = campaign.encounters().boss(boss_id)
	if boss_data.is_empty():
		push_error("Unknown encounter: %s" % boss_id)
		return
	var stage: String = SFCampaign.STAGE_CITY_BOSS
	if boss_id == "toxic_tide":
		stage = SFCampaign.STAGE_COAST_BOSS
	campaign.advance_to(stage)
	# The checkpoint is the pre-encounter marker, never mid-fight.
	campaign.set_checkpoint(stage, campaign.chapter_id)
	_save_quietly()

	_go(Screen.DUEL)
	# _go() built the duel and started it; hold the fight until the briefing ends.
	if duel != null:
		duel.encounter.intro_hold = true
	var lines: Array = campaign.content.dialogue_lines(intro_key)
	_open_dialogue(lines, String(boss_data.get("name", "ENCOUNTER")), Callable(self, "_on_encounter_intro_done"))


func _on_encounter_intro_done() -> void:
	if duel != null:
		duel.encounter.begin()
	audio.set_ambience("none")
	audio.sfx_rift()


func _enter_duel() -> void:
	# Only Toxic Tide still uses the shield duel; the Scrap King is the Eco Arena.
	var boss_id := "toxic_tide"
	var boss_data: Dictionary = campaign.encounters().boss(boss_id)
	if boss_data.is_empty():
		push_error("Duel screen requested with no boss data")
		return
	var all_data = campaign.encounters()
	duel = SFDuel.new()
	duel.name = "Duel"
	duel.setup(skin, ui, boss_data, all_data)
	duel.reduced_motion = setting_reduced_motion
	duel.duel_finished.connect(_on_duel_finished)
	duel.duel_aborted.connect(_on_duel_aborted)
	add_child(duel)
	duel.begin_attempt()
	queue_redraw()


## The Toxic Tide duel ended. Only the defeat is recorded here: the shield
## duel already stopped spawning and cleared every projectile, the screen (and
## Nick's fixed-position lock) is freed when the world returns, and the power
## core drops onto the quay to be picked up. Nothing is awarded on victory.
func _on_duel_finished(outcome: String) -> void:
	if outcome != "victory":
		return
	if not campaign.defeat_boss(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED):
		return
	# Back to exploration: resuming this save lands on the quay with the drop.
	campaign.advance_to(SFCampaign.STAGE_SILENT_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_SILENT_INTRO, SFCampaign.CHAPTER_COAST)
	_save_quietly()
	audio.set_ambience("coast")
	_open_dialogue(campaign.content.dialogue_lines("coast_victory_drop"), "TOXIC TIDE DOWN",
		Callable(self, "_on_coast_drop_ready"))


func _on_coast_drop_ready() -> void:
	zone = "silent_coast"
	_go(Screen.WORLD)
	if _coast_reward_state() == SFCampaign.REWARD_AVAILABLE:
		ui.notify("The power core fell onto the quay. E to collect it.", "info", 4.0)


## Picks up Toxic Tide's power core. The campaign refuses a second pickup, so
## the reward is granted exactly once; the world prop is removed either way.
func _collect_power_core_drop() -> void:
	var got: bool = campaign.collect_boss_reward(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED, SFCampaign.COMPONENT_POWER_CORE)
	if world != null:
		world.remove_prop("coast_power_core_drop")
	if not got:
		return
	audio.sfx_pickup()
	ui.notify("POWER CORE RECOVERED", "good", 4.0)
	_save_quietly()
	_show_coast_victory()


func _city_reward_state() -> String:
	return campaign.reward_state(SFCampaign.FLAG_SCRAP_KING_DEFEATED, SFCampaign.COMPONENT_NAVIGATION_CHIP)


func _coast_reward_state() -> String:
	return campaign.reward_state(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED, SFCampaign.COMPONENT_POWER_CORE)


## QA stage skip only: records the boss and collects its dropped reward in one
## step, through the same idempotent campaign methods real play uses. Returns
## false when the boss was already defeated; a missing reward is still picked
## up, and nothing can duplicate.
func _award_boss_victory(boss_id: String) -> bool:
	var boss_data: Dictionary = campaign.encounters().boss(boss_id)
	if boss_data.is_empty():
		return false
	var flag := String(boss_data.get("reward_flag", ""))
	var first: bool = campaign.defeat_boss(flag)
	campaign.collect_boss_reward(flag, String(boss_data.get("reward_component", "")))
	_save_quietly()
	return first


func _show_city_victory() -> void:
	audio.set_ambience("ruin")
	var lines: Array = campaign.content.dialogue_lines("city_victory")
	_open_dialogue(lines, "SCRAP KING DOWN", Callable(self, "_on_city_victory_done"))


func _on_city_victory_done() -> void:
	campaign.advance_to(SFCampaign.STAGE_CITY_ARCHIVE)
	campaign.set_checkpoint(SFCampaign.STAGE_CITY_ARCHIVE, SFCampaign.CHAPTER_CITY)
	_save_quietly()
	_enter_archive_scene(SFCampaign.ARCHIVE_CITY)


func _show_coast_victory() -> void:
	audio.set_ambience("coast")
	var lines: Array = campaign.content.dialogue_lines("coast_victory")
	_open_dialogue(lines, "POWER CORE RECOVERED", Callable(self, "_on_coast_victory_done"))


func _on_coast_victory_done() -> void:
	campaign.advance_to(SFCampaign.STAGE_COAST_ARCHIVE)
	campaign.set_checkpoint(SFCampaign.STAGE_COAST_ARCHIVE, SFCampaign.CHAPTER_COAST)
	_save_quietly()
	_enter_archive_scene(SFCampaign.ARCHIVE_COAST)


# ---------------------------------------------------------------- eco arena

## Main-menu practice. The campaign object and the save file are never read
## or written on this path: the arena keeps all its state in its own model.
func _start_eco_practice() -> void:
	# The guard lives here, not only on the menu row, so no input path can open
	# practice before the campaign has earned it.
	if not practice_unlocked:
		audio.sfx_denied()
		ui.notify("Practice unlocks after the Scrap King falls in the campaign.", "warn", 3.0)
		return
	audio.sfx_confirm()
	_open_eco_arena("practice", false)


func _open_eco_arena(mode_id: String, resume: bool) -> void:
	eco_mode = mode_id
	_eco_resume = resume
	if screen == Screen.ECO_ARENA:
		screen = Screen.TITLE  # a re-entry always builds a fresh screen
	_go(Screen.ECO_ARENA)


func _enter_eco_arena() -> void:
	eco_screen = SFEcoArenaScreen.new()
	eco_screen.name = "EcoArena"
	eco_screen.setup(skin, ui, eco_data, eco_mode, _eco_resume)
	eco_screen.reduced_motion = setting_reduced_motion
	eco_screen.arena_finished.connect(_on_eco_finished)
	eco_screen.arena_aborted.connect(_on_eco_aborted)
	if eco_mode == "campaign":
		eco_screen.boss_defeated.connect(_on_eco_boss_defeated)
		eco_screen.reward_collected.connect(_on_eco_reward_collected)
	add_child(eco_screen)
	audio.set_ambience("none")
	if audio.has_method("play_music"):
		audio.play_music("ruin")
	apply_focus_state()
	queue_redraw()


## Campaign: the Junkyard Colossus is down. Only the defeat is recorded; the
## navigation chip is awarded when Nick picks it up in the arena.
func _on_eco_boss_defeated() -> void:
	if campaign.defeat_boss(SFCampaign.FLAG_SCRAP_KING_DEFEATED):
		_save_quietly()
	_unlock_practice()


func _on_eco_reward_collected() -> void:
	if campaign.collect_boss_reward(SFCampaign.FLAG_SCRAP_KING_DEFEATED, SFCampaign.COMPONENT_NAVIGATION_CHIP):
		_save_quietly()


func _on_eco_finished(choice: String) -> void:
	if eco_mode != "campaign":
		_go(Screen.TITLE)
		return
	if choice == "continue" and campaign.has_component(SFCampaign.COMPONENT_NAVIGATION_CHIP):
		_show_city_victory()


func _on_eco_aborted() -> void:
	if eco_mode != "campaign":
		_go(Screen.TITLE)
		return
	campaign.set_checkpoint(SFCampaign.STAGE_CITY_BOSS, SFCampaign.CHAPTER_CITY)
	_save_quietly()
	zone = "forgotten_city"
	_go(Screen.WORLD)


## Leaving the fight from its pause menu returns to exploration. The fight is
## not marked as cleared, and the pre-encounter checkpoint is intact.
func _on_duel_aborted() -> void:
	campaign.set_checkpoint(campaign.stage, campaign.chapter_id)
	_save_quietly()
	match campaign.chapter_id:
		SFCampaign.CHAPTER_CITY:
			zone = "forgotten_city"
		SFCampaign.CHAPTER_COAST:
			zone = "silent_coast"
		_:
			zone = "crash_site"
	_go(Screen.WORLD)


# ---------------------------------------------------------------- archives

func _enter_archive_scene(archive_id: String) -> void:
	campaign.restore_archive(archive_id)
	_archive_id = archive_id
	_go(Screen.ARCHIVE)


func _enter_archive() -> void:
	archive_screen = SFArchive.new()
	archive_screen.name = "Archive"
	archive_screen.setup(skin, ui, campaign, _archive_id)
	archive_screen.archive_closed.connect(_on_archive_closed)
	add_child(archive_screen)
	audio.set_ambience("none")
	queue_redraw()


## Closing an archive applies the chapter outcome. Both paths are idempotent, so
## closing early, closing late or reloading the save all produce the same state.
func _on_archive_closed() -> void:
	if _archive_id == SFCampaign.ARCHIVE_CITY:
		if campaign.reveal_future_earth():
			_save_quietly()
			_announce_mission_changed()
		campaign.set_checkpoint(SFCampaign.STAGE_SILENT_INTRO, SFCampaign.CHAPTER_COAST)
		_save_quietly()
		zone = "silent_coast"
		campaign.advance_to(SFCampaign.STAGE_SILENT_INTRO)
		_go(Screen.WORLD)
		_show_coast_intro()
		return
	if _archive_id == SFCampaign.ARCHIVE_COAST:
		if campaign.complete_silent_coast():
			_save_quietly()
		campaign.set_checkpoint(SFCampaign.STAGE_BASE_RETURN, SFCampaign.CHAPTER_CRASH)
		_save_quietly()
		_enter_base_return(true)
		return
	if _archive_id == SFCampaign.ARCHIVE_DAWN:
		var first: bool = campaign.complete_dawn_tower()
		campaign.advance_to(SFCampaign.STAGE_RECONSTRUCTION)
		campaign.set_checkpoint(SFCampaign.STAGE_RECONSTRUCTION, SFCampaign.CHAPTER_CRASH)
		_save_quietly()
		zone = "crash_site"
		_go(Screen.WORKSHOP)
		if first:
			ui.notify("RECONSTRUCTION WORKSHOP UNLOCKED", "good", 4.0)
			_open_dialogue(campaign.content.dialogue_lines("workshop_intro"), "BILL")


## Announces the mission change once, after the reveal. Kept out of the data
## path because it is UI feedback, not campaign state.
func _announce_mission_changed() -> void:
	ui.notify("OBJECTIVE CHANGED: RETURN WITH EVIDENCE", "good", 4.0)
	Events.notice.emit("OBJECTIVE CHANGED: RETURN WITH EVIDENCE", "good")


# ---------------------------------------------------------------- base return

func _enter_base_return(play_dialogue: bool) -> void:
	campaign.advance_to(SFCampaign.STAGE_BASE_RETURN)
	campaign.set_checkpoint(SFCampaign.STAGE_BASE_RETURN, SFCampaign.CHAPTER_CRASH)
	_save_quietly()
	zone = "crash_site"
	_go(Screen.PROGRESSION)
	if play_dialogue and progression_screen != null:
		_open_dialogue(campaign.content.dialogue_lines("base_return"), "CRASH-SITE BASE",
			Callable(self, "_on_base_return_done"))


func _on_base_return_done() -> void:
	campaign.advance_to(SFCampaign.STAGE_PHASE_TWO_COMPLETE)
	campaign.set_checkpoint(SFCampaign.STAGE_PHASE_TWO_COMPLETE, SFCampaign.CHAPTER_CRASH)
	_save_quietly()


func _enter_progression() -> void:
	progression_screen = SFProgression.new()
	progression_screen.name = "Progression"
	progression_screen.setup(skin, ui, campaign, "base_return")
	progression_screen.closed.connect(_on_progression_closed)
	add_child(progression_screen)
	audio.set_ambience("ruin")
	queue_redraw()


## Finishing the base-return readout is the end of Phase 2. From here the
## campaign returns to the title; Dawn Tower is recorded as unlocked but is not
## playable in this phase.
func _on_progression_closed() -> void:
	campaign.complete_silent_coast()
	campaign.advance_to(SFCampaign.STAGE_PHASE_TWO_COMPLETE)
	campaign.set_checkpoint(SFCampaign.STAGE_PHASE_TWO_COMPLETE, SFCampaign.CHAPTER_CRASH)
	_save_quietly()
	var lines: Array = campaign.content.dialogue_lines("phase_two_complete")
	if lines.is_empty():
		_go(Screen.CHECKPOINT)
		return
	_open_dialogue(lines, "PHASE 2 COMPLETE", Callable(self, "_on_phase_two_done"))


func _on_phase_two_done() -> void:
	_go(Screen.CHECKPOINT)


# ---------------------------------------------------------------- phase 3

## Enters the Dawn Tower. Idempotent: the intro plays once, on first entry.
func _show_dawn_intro() -> void:
	campaign.set_flag(SFCampaign.FLAG_DAWN_ENTERED)
	campaign.advance_to(SFCampaign.STAGE_DAWN_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_DAWN_INTRO, SFCampaign.CHAPTER_DAWN)
	_save_quietly()
	_open_dialogue(campaign.content.dialogue_lines("dawn_intro"), "DAWN TOWER", Callable(self, "_on_dawn_intro_done"))


func _on_dawn_intro_done() -> void:
	ui.notify("Find the survey projector and the checkpoint on the boardwalk.", "info", 4.0)


## The survey projector plays the healthy-forest memory, then returns to the
## slope. Viewing it is required before the tower: the fight should be about
## something the player has seen.
func _on_dawn_projector_done() -> void:
	if campaign.has_viewed_memory(SFCampaign.MEMORY_HEALTHY_FOREST):
		ui.notify("The survey is already archived in Bill's index.", "info", 2.5)
		return
	_play_memory(SFCampaign.MEMORY_HEALTHY_FOREST, Callable(self, "_return_to_world"))


func _use_dawn_checkpoint() -> void:
	var first: bool = not campaign.has_flag(SFCampaign.FLAG_DAWN_CHECKPOINT)
	campaign.set_flag(SFCampaign.FLAG_DAWN_CHECKPOINT)
	campaign.set_checkpoint(SFCampaign.STAGE_DAWN_BOSS, SFCampaign.CHAPTER_DAWN)
	_save_quietly()
	var lines: Array = campaign.content.dialogue_lines("dawn_checkpoint") if first else [
		"Boardwalk marker confirmed. The tower gate is up the slope.",
		"A failed fight restarts at the tower, not at the ridge.",
	]
	_open_dialogue(lines, "CHECKPOINT")


## The tower gate refuses entry until the checkpoint is used and the forest
## memory has been seen, and says so in the fiction.
func _approach_dawn_gate() -> void:
	if campaign.has_flag(SFCampaign.FLAG_SKY_REMNANT_DEFEATED):
		if _shield_state() == SFCampaign.REWARD_AVAILABLE:
			_open_dialogue(["Bill: \"The emitter fell onto the slope just below the gate. It is still glowing. Pick it up first.\""], "DAWN TOWER")
		elif not campaign.has_flag(SFCampaign.FLAG_DAWN_ARCHIVE_RESTORED):
			_open_dialogue(["The shield is quiet. The archive inside is waking up."], "DAWN TOWER",
				Callable(self, "_on_shield_collected_done"))
		else:
			_open_dialogue(["The shield is quiet. The archive inside is already restored."], "DAWN TOWER")
		return
	if not campaign.has_viewed_memory(SFCampaign.MEMORY_HEALTHY_FOREST):
		audio.sfx_denied()
		_open_dialogue([
			"Bill: \"Before we go in, there is a projector on the boardwalk. I would like you to see what this slope was.\"",
		], "DAWN TOWER GATE")
		return
	if not campaign.has_flag(SFCampaign.FLAG_DAWN_CHECKPOINT):
		audio.sfx_denied()
		_open_dialogue([
			"Smog moves behind the shield like something breathing.",
			"Nick: \"Checkpoint first. I want a way back if this goes badly.\"",
		], "DAWN TOWER GATE")
		return
	_begin_dawn_boss()


## Starts the typing encounter. The briefing (and, the first time, Bill's
## tutorial) plays over a frozen arena; nothing spawns until it closes.
func _begin_dawn_boss() -> void:
	campaign.advance_to(SFCampaign.STAGE_DAWN_BOSS)
	campaign.set_checkpoint(SFCampaign.STAGE_DAWN_BOSS, SFCampaign.CHAPTER_DAWN)
	_save_quietly()
	_go(Screen.TYPING)
	var lines: Array = campaign.content.dialogue_lines("dawn_boss_intro").duplicate()
	if not campaign.has_flag(SFCampaign.FLAG_TYPING_TUTORIAL_SEEN):
		lines.append_array(campaign.content.dialogue_lines("typing_tutorial"))
	_open_dialogue(lines, "SKY REMNANT", Callable(self, "_on_dawn_boss_intro_done"))


func _on_dawn_boss_intro_done() -> void:
	campaign.set_flag(SFCampaign.FLAG_TYPING_TUTORIAL_SEEN)
	_save_quietly()
	if typing_duel != null:
		typing_duel.start_fight()
	audio.set_ambience("none")
	audio.sfx_rift()


## The deck seed changes with the journal size, so a new attempt after leaving
## the tower practises fresh words; a retry inside the fight keeps its deck.
func _enter_typing() -> void:
	var boss: Dictionary = typing_data.get("boss", {}) as Dictionary
	var stages: Array = (typing_data.get("deck", {}) as Dictionary).get("stages", []) as Array
	var seed_value: int = int(boss.get("seed", 1)) + campaign.vocabulary_journal.size()
	var deck: Array = vocab.select_deck(stages, seed_value)
	typing_duel = SFTypingDuel.new()
	typing_duel.name = "TypingDuel"
	# The attempt history makes every attempt's word order differ from the last,
	# including the first attempt after leaving the tower or reloading.
	typing_duel.setup(skin, ui, typing_data, deck, seed_value, vocab, campaign,
		campaign.typing_attempts, campaign.typing_last_order)
	typing_duel.reduced_motion = setting_reduced_motion
	typing_duel.duel_finished.connect(_on_typing_finished)
	typing_duel.duel_aborted.connect(_on_typing_aborted)
	typing_duel.word_learned.connect(_on_word_learned)
	typing_duel.attempt_started.connect(_on_typing_attempt_started)
	add_child(typing_duel)
	typing_duel.begin_attempt()
	audio.set_ambience("none")
	queue_redraw()


## A word was typed. The journal is persistent study progress, saved the first
## time each entry is learned; it never counts as boss damage.
func _on_word_learned(entry_id: String) -> void:
	if campaign.record_vocabulary(entry_id):
		_save_quietly()


func _on_typing_attempt_started(attempt: int, order: Array) -> void:
	campaign.record_typing_attempt(attempt, order)


func _typing_reward_flag() -> String:
	return String((typing_data.get("boss", {}) as Dictionary).get("reward_flag", SFCampaign.FLAG_SKY_REMNANT_DEFEATED))


func _typing_reward_component() -> String:
	return String((typing_data.get("boss", {}) as Dictionary).get("reward_component", SFCampaign.COMPONENT_SHIELD_EMITTER))


func _shield_state() -> String:
	return campaign.reward_state(_typing_reward_flag(), _typing_reward_component())


## The typing fight was won. Only the defeat is recorded here: the shield
## emitter drops onto the slope and is awarded when Nick picks it up.
func _on_typing_finished(outcome: String) -> void:
	if outcome != "victory":
		return
	campaign.defeat_boss(_typing_reward_flag())
	# Back to exploration. Resuming this save lands on the slope with the drop.
	campaign.advance_to(SFCampaign.STAGE_DAWN_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_DAWN_INTRO, SFCampaign.CHAPTER_DAWN)
	_save_quietly()
	_open_dialogue(campaign.content.dialogue_lines("dawn_victory"), "SKY REMNANT DISPERSED",
		Callable(self, "_on_dawn_victory_done"))


## The encounter screen (and every shot, word and lock in it) is freed here;
## Nick walks again on the slope with Bill, the emitter glowing nearby.
func _on_dawn_victory_done() -> void:
	zone = "dawn_tower"
	_go(Screen.WORLD)
	if _shield_state() == SFCampaign.REWARD_AVAILABLE:
		ui.notify("The shield emitter fell below the gate. E to collect it.", "info", 4.0)


## Picks up the shield emitter. The campaign refuses a second pickup, so the
## reward is granted exactly once; the world prop is removed on success.
func _collect_shield_drop() -> void:
	if not campaign.collect_boss_reward(_typing_reward_flag(), _typing_reward_component()):
		if world != null:
			world.remove_prop("dawn_shield_drop")
		return
	if world != null:
		world.remove_prop("dawn_shield_drop")
	audio.sfx_pickup()
	ui.notify("SHIELD EMITTER RECOVERED", "good", 4.0)
	_save_quietly()
	_open_dialogue(campaign.content.dialogue_lines("shield_collected"), "SHIELD EMITTER",
		Callable(self, "_on_shield_collected_done"))


func _on_shield_collected_done() -> void:
	campaign.advance_to(SFCampaign.STAGE_DAWN_ARCHIVE)
	campaign.set_checkpoint(SFCampaign.STAGE_DAWN_ARCHIVE, SFCampaign.CHAPTER_DAWN)
	_save_quietly()
	_enter_archive_scene(SFCampaign.ARCHIVE_DAWN)


## Leaving the fight from its pause menu returns to the slope. Nothing is
## awarded; the pre-boss checkpoint and the journal are kept.
func _on_typing_aborted() -> void:
	campaign.set_checkpoint(SFCampaign.STAGE_DAWN_BOSS, SFCampaign.CHAPTER_DAWN)
	_save_quietly()
	zone = "dawn_tower"
	_go(Screen.WORLD)


func _enter_workshop() -> void:
	workshop_screen = SFWorkshop.new()
	workshop_screen.name = "Workshop"
	workshop_screen.setup(skin, ui, campaign)
	workshop_screen.closed.connect(_on_workshop_closed)
	workshop_screen.assembled.connect(_on_workshop_assembled)
	add_child(workshop_screen)
	if audio.has_method("play_music"):
		audio.play_music("construction")
	audio.set_ambience("ruin")
	queue_redraw()


## Leaving the workshop keeps the selection (saved) and returns to the base.
func _on_workshop_closed() -> void:
	_save_quietly()
	if campaign.is_ready_for_final_assembly():
		_go(Screen.CHECKPOINT)
		return
	zone = "crash_site"
	_go(Screen.WORLD)
	ui.notify("The workshop is at the wreck. E to reopen it.", "info", 3.0)


## The design was fabricated. This is READY_FOR_FINAL_ASSEMBLY, the end of
## Phase 3; the escape itself is Phase 4.
func _on_workshop_assembled() -> void:
	campaign.advance_to(SFCampaign.STAGE_READY)
	campaign.set_checkpoint(SFCampaign.STAGE_READY, SFCampaign.CHAPTER_CRASH)
	_save_quietly()
	_open_dialogue(campaign.content.dialogue_lines("workshop_ready"), "READY FOR FINAL ASSEMBLY",
		Callable(self, "_on_ready_dialogue_done"))


func _on_ready_dialogue_done() -> void:
	_go(Screen.CHECKPOINT)


# ---------------------------------------------------------------- phase 4
#
# Final assembly, the escape cinematic, the report and the credits. The stage
# machine is unchanged; these are four more screens. Every persistent change is
# applied here, exactly once, and saved before the next screen opens.

## A save written during the escape resumes at the start of the escape, not in
## the middle of a scene. Watching it again and skipping it leave the same state,
## because every outcome is idempotent.
func _replay_escape() -> void:
	if not campaign.has_final_assembly_snapshot():
		# A contradictory save (escape stage, no snapshot) falls back to the gate.
		campaign.advance_to(SFCampaign.STAGE_READY)
		_go(Screen.CHECKPOINT)
		return
	_go(Screen.CINEMATIC)


## The pre-finale gate. Reached from the ready summary, and revalidated on entry.
func _enter_final_assembly() -> void:
	assembly_screen = SFFinalAssembly.new()
	assembly_screen.name = "FinalAssembly"
	assembly_screen.setup(skin, ui, campaign, finale_data, reconstruction_data)
	assembly_screen.assembly_started.connect(_on_assembly_started)
	assembly_screen.installation_done.connect(_on_installation_done)
	assembly_screen.closed.connect(_on_assembly_closed)
	add_child(assembly_screen)
	assembly_screen.refresh()
	audio.set_ambience("ruin")
	queue_redraw()


func _on_assembly_closed() -> void:
	# Back to the ready summary. Nothing has been frozen, so no finale flag has
	# been written and the run can be left there or resumed later. (The design
	# itself stays locked: fabrication is already committed, and the workshop's
	# own rule refuses changes once it is assembled.)
	_go(Screen.CHECKPOINT)


## The player confirmed final assembly. This is the one irreversible transition:
## snapshot, pre-finale checkpoint, save, then the installation animation. The
## gate latches on its own too, so a double activation can never reach here twice.
func _on_assembly_started() -> void:
	if _finale_started:
		return
	_finale_started = true
	var snapshot: Dictionary = SFFinale.snapshot(campaign, reconstruction_data)
	if not campaign.begin_final_assembly(snapshot):
		# Already assembled by an earlier run: continue the sequence rather than
		# starting a second one. Watching, skipping and reloading all converge.
		if assembly_screen != null:
			assembly_screen.play_installation()
		return
	campaign.advance_to(SFCampaign.STAGE_FINAL_ASSEMBLY)
	campaign.set_checkpoint(SFCampaign.STAGE_FINAL_ASSEMBLY, SFCampaign.CHAPTER_CRASH)
	_save_quietly()
	if audio.has_method("play_music"):
		audio.play_music("flight")
	if assembly_screen != null:
		assembly_screen.play_installation()
	queue_redraw()


## The installation animation finished or was skipped. Start the escape.
func _on_installation_done() -> void:
	campaign.advance_to(SFCampaign.STAGE_ESCAPE)
	campaign.set_checkpoint(SFCampaign.STAGE_ESCAPE, SFCampaign.CHAPTER_RETURN)
	_save_quietly()
	_go(Screen.CINEMATIC)


func _enter_cinematic() -> void:
	cinematic_screen = SFCinematic.new()
	cinematic_screen.name = "Cinematic"
	cinematic_screen.setup(skin, ui, campaign, finale_data, reconstruction_data)
	cinematic_screen.reduced_motion = setting_reduced_motion
	cinematic_screen.cinematic_finished.connect(_on_cinematic_finished)
	cinematic_screen.pause_requested.connect(_on_screen_pause_requested)
	add_child(cinematic_screen)
	audio.set_ambience("none")
	if audio.has_method("play_music"):
		audio.play_music("flight")
	queue_redraw()


## The cinematic ended, naturally or by skip. Both paths land here exactly once,
## and every persistent outcome is applied here rather than in the screen, so
## watching and skipping cannot diverge.
## A screen's own pause button (the cinematic badge) opens the shared pause.
func _on_screen_pause_requested() -> void:
	audio.sfx_back()
	_open_pause()


func _on_cinematic_finished(skipped: bool) -> void:
	campaign.set_cinematic_skipped(skipped)
	campaign.complete_return()
	campaign.advance_to(SFCampaign.STAGE_RETURN_HOME)
	campaign.set_checkpoint(SFCampaign.STAGE_RETURN_HOME, SFCampaign.CHAPTER_RETURN)
	_save_quietly()
	_go(Screen.REPORT)


func _enter_report() -> void:
	report_screen = SFReport.new()
	report_screen.name = "MissionReport"
	report_screen.setup(skin, ui, campaign, finale_data, reconstruction_data)
	report_screen.closed.connect(_on_report_closed)
	add_child(report_screen)
	audio.set_ambience("none")
	queue_redraw()


func _on_report_closed() -> void:
	campaign.mark_report_seen()
	campaign.advance_to(SFCampaign.STAGE_MISSION_REPORT)
	campaign.set_checkpoint(SFCampaign.STAGE_MISSION_REPORT, SFCampaign.CHAPTER_RETURN)
	_save_quietly()
	_go(Screen.CREDITS)


func _enter_credits() -> void:
	credits_screen = SFCredits.new()
	credits_screen.name = "Credits"
	credits_screen.setup(skin, ui, campaign, finale_data)
	credits_screen.closed.connect(_on_credits_closed)
	add_child(credits_screen)
	audio.set_ambience("none")
	if audio.has_method("play_music"):
		audio.play_music("title")
	queue_redraw()


## The campaign is complete. The save keeps the ending state, so Continue brings
## the player back to the credits rather than to a dead screen.
func _on_credits_closed() -> void:
	campaign.advance_to(SFCampaign.STAGE_CREDITS)
	campaign.set_checkpoint(SFCampaign.STAGE_CREDITS, SFCampaign.CHAPTER_RETURN)
	_save_quietly()
	_go(Screen.TITLE)


# ---------------------------------------------------------------- milestone driver
#
# The former I + O + P stage skip is gone: no key, chord or launch flag reaches
# this code. `_apply_qa_skip()` survives only as the headless test driver that
# walks a campaign milestone by milestone through the real campaign methods
# (tests/star_fall/test_flow.gd, test_phase4.gd and capture.gd call it). It has
# no input binding in any build.

## Polled every frame. Only the chord triggers anything; individual I, O or P
## presses fall through to whatever screen owns input, so normal controls are
## unaffected. The controller applies exactly one milestone per press.
## Advances one campaign milestone, using the same campaign methods the normal
## flow uses. Returns true when something changed. Public so the tests can drive
## it directly without simulating key state.
func _apply_qa_skip() -> bool:
	# A dialogue or a running cinematic is finished cleanly first, so a skip
	# never strands input in a callback that expected another screen.
	if dialogue != null:
		var cb := dialogue_next
		dialogue = null
		dialogue_next = Callable()
		apply_focus_state()
		if cb.is_valid():
			cb.call()
		return true
	var milestone: String = SFQA.next_milestone(campaign)
	if milestone == SFQA.MILESTONE_DONE:
		ui.notify("QA: CAMPAIGN COMPLETE", "good", 2.5)
		return false
	campaign.mark_qa_stage_skip_used()
	match milestone:
		SFQA.MILESTONE_BRIEFING:
			_qa_briefing()
		SFQA.MILESTONE_CONSTRUCTION:
			_qa_construction()
		SFQA.MILESTONE_BILL:
			_qa_bill()
		SFQA.MILESTONE_PHASE_ONE:
			_qa_phase_one()
		SFQA.MILESTONE_CITY:
			_qa_city()
		SFQA.MILESTONE_COAST:
			_qa_coast()
		SFQA.MILESTONE_PHASE_TWO:
			_qa_phase_two()
		SFQA.MILESTONE_DAWN:
			_qa_dawn()
		SFQA.MILESTONE_WORKSHOP:
			_qa_workshop()
		SFQA.MILESTONE_READY:
			_qa_ready()
		SFQA.MILESTONE_FINALE:
			_qa_finale()
		SFQA.MILESTONE_REPORT:
			_qa_report()
	_save_quietly()
	ui.notify("QA: %s" % SFQA.milestone_label(milestone), "info", 2.5)
	queue_redraw()
	return true


## Clears any overlay so a skip always starts from a live, unlocked screen. Every
## skip helper calls this before moving the campaign on.
func _qa_clear_overlay() -> void:
	pause_open = false
	_transition_busy = false
	dialogue = null
	dialogue_next = Callable()
	transition_alpha = 0.0
	ui.clear_toast()
	# Releasing the lock here matters when a skip lands on the screen it was
	# already on: without it, a cleared dialogue could leave the world frozen.
	apply_focus_state()


func _qa_briefing() -> void:
	_qa_clear_overlay()
	campaign.set_flag(SFCampaign.FLAG_BRIEFING_READ)
	campaign.advance_to(SFCampaign.STAGE_CONSTRUCTION)
	campaign.set_checkpoint(SFCampaign.STAGE_CONSTRUCTION, SFCampaign.CHAPTER_PRESENT)
	zone = "spaceport"
	_go(Screen.WORLD)


func _qa_construction() -> void:
	_qa_clear_overlay()
	# A valid day-one design from the shipped data, so the crash-stage salvage
	# bonus, surviving data and the repaired-engine stats all stay meaningful.
	SFQA.apply_valid_day_one_design(campaign)
	campaign.set_flag(SFCampaign.FLAG_LAUNCHED)
	campaign.set_flag(SFCampaign.FLAG_RIFT_SEEN)
	campaign.set_flag(SFCampaign.FLAG_CRASHED)
	campaign.advance_to(SFCampaign.STAGE_CRASH_INTRO)
	campaign.advance_to(SFCampaign.STAGE_CRASH_SITE)
	campaign.set_checkpoint(SFCampaign.STAGE_CRASH_SITE, SFCampaign.CHAPTER_CRASH)
	zone = "crash_site"
	_go(Screen.WORLD)


func _qa_bill() -> void:
	_qa_clear_overlay()
	campaign.set_flag(SFCampaign.FLAG_VELA_INSPECTED)
	campaign.set_flag(SFCampaign.FLAG_POWER_REPAIRED)
	campaign.view_memory(SFCampaign.MEMORY_GREEN_CITY)
	campaign.set_flag(SFCampaign.FLAG_BILL_ACTIVE)
	campaign.set_flag(SFCampaign.FLAG_COORDINATES_RECEIVED)
	campaign.advance_to(SFCampaign.STAGE_CHECKPOINT)
	campaign.set_checkpoint(SFCampaign.STAGE_CHECKPOINT, SFCampaign.CHAPTER_CRASH)
	_go(Screen.CHECKPOINT)


func _qa_phase_one() -> void:
	_qa_clear_overlay()
	campaign.set_flag(SFCampaign.FLAG_CITY_ENTERED)
	campaign.advance_to(SFCampaign.STAGE_CITY_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_CITY_INTRO, SFCampaign.CHAPTER_CITY)
	zone = "forgotten_city"
	_go(Screen.WORLD)


func _qa_city() -> void:
	_qa_clear_overlay()
	campaign.set_flag(SFCampaign.FLAG_CITY_CHECKPOINT)
	_award_boss_victory("scrap_king")
	campaign.restore_archive(SFCampaign.ARCHIVE_CITY)
	campaign.reveal_future_earth()
	campaign.advance_to(SFCampaign.STAGE_SILENT_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_SILENT_INTRO, SFCampaign.CHAPTER_COAST)
	zone = "silent_coast"
	_go(Screen.WORLD)


func _qa_coast() -> void:
	_qa_clear_overlay()
	campaign.set_flag(SFCampaign.FLAG_COAST_CHECKPOINT)
	_award_boss_victory("toxic_tide")
	campaign.restore_archive(SFCampaign.ARCHIVE_COAST)
	campaign.complete_silent_coast()
	campaign.set_flag(SFCampaign.FLAG_BASE_RETURNED)
	campaign.advance_to(SFCampaign.STAGE_BASE_RETURN)
	campaign.set_checkpoint(SFCampaign.STAGE_BASE_RETURN, SFCampaign.CHAPTER_CRASH)
	zone = "crash_site"
	_go(Screen.PROGRESSION)


func _qa_phase_two() -> void:
	_qa_clear_overlay()
	campaign.complete_silent_coast()
	campaign.set_flag(SFCampaign.FLAG_BASE_RETURNED)
	campaign.set_flag(SFCampaign.FLAG_PHASE_TWO_COMPLETE)
	campaign.advance_to(SFCampaign.STAGE_PHASE_TWO_COMPLETE)
	campaign.advance_to(SFCampaign.STAGE_DAWN_INTRO)
	campaign.set_checkpoint(SFCampaign.STAGE_DAWN_INTRO, SFCampaign.CHAPTER_DAWN)
	zone = "dawn_tower"
	_go(Screen.WORLD)


func _qa_dawn() -> void:
	_qa_clear_overlay()
	campaign.set_flag(SFCampaign.FLAG_DAWN_ENTERED)
	campaign.set_flag(SFCampaign.FLAG_DAWN_CHECKPOINT)
	campaign.view_memory(SFCampaign.MEMORY_HEALTHY_FOREST)
	var boss: Dictionary = typing_data.get("boss", {}) as Dictionary
	campaign.complete_boss(String(boss.get("reward_flag", SFCampaign.FLAG_SKY_REMNANT_DEFEATED)),
		String(boss.get("reward_component", SFCampaign.COMPONENT_SHIELD_EMITTER)))
	campaign.complete_dawn_tower()
	campaign.advance_to(SFCampaign.STAGE_RECONSTRUCTION)
	campaign.set_checkpoint(SFCampaign.STAGE_RECONSTRUCTION, SFCampaign.CHAPTER_CRASH)
	zone = "crash_site"
	_go(Screen.WORKSHOP)


func _qa_workshop() -> void:
	_qa_clear_overlay()
	var result: Dictionary = SFQA.apply_valid_reconstruction(campaign, reconstruction_data)
	if not bool(result.get("ok", false)):
		ui.notify("QA: workshop design failed", "bad", 3.0)
		return
	campaign.advance_to(SFCampaign.STAGE_READY)
	campaign.set_checkpoint(SFCampaign.STAGE_READY, SFCampaign.CHAPTER_CRASH)
	_go(Screen.CHECKPOINT)


## Freezes the snapshot exactly as the real gate does, then opens the gate so the
## next press continues into the installation and the escape.
func _qa_ready() -> void:
	_qa_clear_overlay()
	if not campaign.has_final_assembly_snapshot():
		var snapshot: Dictionary = SFFinale.snapshot(campaign, reconstruction_data)
		campaign.begin_final_assembly(snapshot)
	campaign.advance_to(SFCampaign.STAGE_FINAL_ASSEMBLY)
	campaign.set_checkpoint(SFCampaign.STAGE_FINAL_ASSEMBLY, SFCampaign.CHAPTER_CRASH)
	_go(Screen.FINAL_ASSEMBLY)


func _qa_finale() -> void:
	_qa_clear_overlay()
	if not campaign.has_final_assembly_snapshot():
		campaign.begin_final_assembly(SFFinale.snapshot(campaign, reconstruction_data))
	campaign.set_cinematic_skipped(true)
	campaign.complete_return()
	campaign.advance_to(SFCampaign.STAGE_RETURN_HOME)
	campaign.set_checkpoint(SFCampaign.STAGE_RETURN_HOME, SFCampaign.CHAPTER_RETURN)
	_go(Screen.REPORT)


func _qa_report() -> void:
	_qa_clear_overlay()
	campaign.mark_report_seen()
	campaign.advance_to(SFCampaign.STAGE_MISSION_REPORT)
	campaign.advance_to(SFCampaign.STAGE_CREDITS)
	campaign.set_checkpoint(SFCampaign.STAGE_CREDITS, SFCampaign.CHAPTER_RETURN)
	_go(Screen.CREDITS)


func journal_entries() -> Array:
	var out: Array = []
	for id in campaign.vocabulary_journal:
		var e: Dictionary = vocab.entry(String(id))
		if not e.is_empty():
			out.append(e)
	return out


func _journal_key(key: int) -> void:
	match key:
		KEY_UP, KEY_W:
			journal_index = maxi(0, journal_index - 1)
			audio.sfx_select()
		KEY_DOWN, KEY_S:
			journal_index = mini(maxi(0, campaign.vocabulary_journal.size() - 1), journal_index + 1)
			audio.sfx_select()
		KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE:
			audio.sfx_back()
			_go(journal_return)


func _draw_ready_summary() -> void:
	var panel := Rect2(80, 34, 480, 220)
	draw_rect(panel, Color(0.05, 0.09, 0.10, 0.94), true)
	draw_rect(panel, SFPalette.GREEN_OK, false, 1.0)
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 1)), SFPalette.GREEN_OK, true)
	skin.text_c(self, VW * 0.5, panel.position.y + 14, "READY FOR FINAL ASSEMBLY", SFPalette.GREEN_OK, 2)
	var rec: Dictionary = campaign.reconstruction.get("report", {}) as Dictionary
	var t: Dictionary = rec.get("totals", {}) as Dictionary
	var route := String(rec.get("route_id", "")).replace("_", " ").to_upper()
	var body := [
		"Navigation chip, power core and shield emitter are fitted to the rebuilt VELA.",
		"Bill's memory core and the Dawn Project evidence archive are loaded.",
		"Route: %s. Launch mass %.0f kg, delta-v %.0f of %.0f m/s needed." % [route, float(t.get("wet_mass_kg", 0)), float(t.get("delta_v_available_m_s", 0)), float(t.get("delta_v_required_m_s", 0))],
		"%d environmental words in the journal." % campaign.vocabulary_journal.size(),
	]
	var y: float = panel.position.y + 44.0
	for line in body:
		y = skin.wrap(self, Vector2(panel.position.x + 20, y), panel.size.x - 40, String(line), SFPalette.PAPER, 1, 3) + 5.0
	skin.text_c(self, VW * 0.5, panel.end.y - 18, "PHASE 3 COMPLETE - CHECKPOINT SAVED", SFPalette.GREEN_OK)
	draw_rect(Rect2(0, VH - 30, VW, 30), Color(0.03, 0.05, 0.05, 0.9), true)
	skin.text_c(self, VW * 0.5, VH - 23, "ENTER  FINAL ASSEMBLY", SFPalette.PAPER)
	skin.text_c(self, VW * 0.5, VH - 12, "PHASE 4: COMPLETE ASSEMBLY AND LAUNCH", SFPalette.ASH_LIGHT)
	_draw_checkpoint_buttons()


## The healthy Dawn forest: layered trunks, a full canopy, birds, a boardwalk.
func _draw_forest_hologram(cx: float, cy: float, flicker: float) -> void:
	var base_y := cy + 34.0
	var leaf := Color(0.30, 0.85, 0.50, 0.62 * flicker)
	var leaf_hi := Color(0.55, 1.0, 0.65, 0.62 * flicker)
	var trunk := Color(0.35, 0.65, 0.50, 0.55 * flicker)
	for i in 9:
		var tx := cx - 92.0 + float(i) * 23.0
		var th := 40.0 + float((i * 29) % 26)
		draw_rect(Rect2(tx, base_y - th, 3, th), trunk, true)
		draw_rect(Rect2(tx - 9, base_y - th - 10, 21, 16), leaf, true)
		draw_rect(Rect2(tx - 5, base_y - th - 14, 13, 6), leaf_hi, true)
	# Birds over the canopy.
	for i in 4:
		var bx := cx - 60.0 + float(i) * 38.0
		var by := base_y - 86.0 - float(i % 2) * 8.0
		draw_rect(Rect2(bx, by, 3, 1), leaf_hi, true)
		draw_rect(Rect2(bx + 3, by - 1, 3, 1), leaf_hi, true)
	# Boardwalk with two survey figures.
	draw_rect(Rect2(cx - 96, base_y - 4, 192, 3), Color(0.5, 0.95, 0.8, 0.5 * flicker), true)
	for i in 2:
		var fx := cx - 20.0 + float(i) * 34.0
		draw_rect(Rect2(fx, base_y - 14, 4, 10), leaf_hi, true)
		draw_rect(Rect2(fx, base_y - 18, 4, 4), Color(0.8, 1.0, 0.9, 0.6 * flicker), true)
	draw_rect(Rect2(cx - 96, base_y, 192, 2), Color(0.4, 0.95, 0.8, 0.35 * flicker), true)


# ---------------------------------------------------------------- save error

func _save_error_key(key: int) -> void:
	match key:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE:
			audio.sfx_back()
			_go(Screen.TITLE)


# ---------------------------------------------------------------- saving

func _save_quietly() -> void:
	var result: Dictionary = SFSave.write_save(campaign)
	if bool(result.get("ok", false)):
		Events.game_saved.emit()
		save_available = true
	else:
		Events.save_failed.emit(String(result.get("error", "")))
		ui.notify(String(result.get("error", "Save failed.")), "bad", 3.0)


func _manual_save() -> void:
	var result: Dictionary = SFSave.write_save(campaign)
	if bool(result.get("ok", false)):
		audio.sfx_confirm()
		ui.notify("Progress saved.", "good")
		Events.game_saved.emit()
		save_available = true
	else:
		audio.sfx_denied()
		ui.notify("Save failed: " + String(result.get("error", "")), "bad", 3.0)


# ---------------------------------------------------------------- process

func _process(delta: float) -> void:
	time += delta
	blink += delta
	if not pause_open:
		campaign.play_seconds += delta
	skin.tick(delta)
	ui.tick(delta)
	if transition_alpha > 0.0:
		if DisplayServer.get_name() == "headless":
			transition_alpha = 0.0
		else:
			transition_timer += delta
			transition_alpha = maxf(0.0, 1.0 - (transition_timer / transition_duration))
		if _transition_node != null:
			_transition_node.queue_redraw()
	if dialogue != null:
		dialogue.tick(delta)
	if screen == Screen.LAUNCH and not pause_open:
		_process_launch(delta)
	if screen == Screen.MEMORY and not pause_open:
		var lines: Array = _memory_lines()
		if not lines.is_empty():
			var line := String(lines[mini(memory_index, lines.size() - 1)])
			if int(memory_chars) < line.length():
				memory_chars = minf(float(line.length()), memory_chars + setting_text_speed * delta)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


# ---------------------------------------------------------------- overlay queries

## True when the pause menu is showing. The overlay node asks this.
func is_pause_open() -> bool:
	return pause_open and dialogue == null


## Requests a redraw of the in-world overlay layer, if it exists.
func refresh_overlay() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)

	# The world and construction screen draw themselves as child nodes.
	match screen:
		Screen.TITLE:
			_draw_title()
		Screen.SETTINGS:
			_draw_settings()
		Screen.WORLD:
			# The world draws itself; its HUD draws on the overlay layer.
			pass
		Screen.CONSTRUCTION:
			pass
		Screen.LAUNCH:
			_draw_launch()
		Screen.MEMORY:
			_draw_memory()
		Screen.CHECKPOINT:
			_draw_checkpoint()
		Screen.SAVE_ERROR:
			_draw_save_error()
		Screen.JOURNAL:
			ui.journal_panel(self, journal_entries(), journal_index)

	if screen != Screen.WORLD:
		ui.toast(self)
	refresh_overlay()


# ---------------------------------------------------------------- title draw

func _draw_title() -> void:
	# Night sky fading into a bright horizon over a living planet.
	var band := 0
	while band < 20:
		var t: float = float(band) / 20.0
		var c := SFPalette.INK.lerp(SFPalette.SKY_DEEP, t * t)
		draw_rect(Rect2(0, 104 + band * 5, VW, 5), c, true)
		band += 1
	# Daylight water band below the horizon.
	draw_rect(Rect2(0, 204, VW, 156), SFPalette.SKY, true)
	draw_rect(Rect2(0, 204, VW, 6), SFPalette.SKY.lightened(0.08), true)
	# Earth disc, low and left, cropped by the bottom edge so the menu column
	# on the right has clear sky behind it.
	var earth: Texture2D = skin.sprites["earth"]
	draw_texture_rect(earth, Rect2(12, 176, 272, 272), false, Color(1, 1, 1, 0.92))
	# Sparse stars behind.
	for i in 70:
		var x := float((i * 97) % VW)
		var y := float((i * 41) % 150)
		var c2 := Color(1, 1, 1, 0.12 + 0.18 * float(i % 5) / 5.0)
		draw_rect(Rect2(x, y, 1, 1), c2, true)

	# Title block.
	draw_rect(Rect2(0, 0, VW, 150), Color(0.03, 0.06, 0.08, 0.55), true)
	skin.text_c(self, VW * 0.5, 20, "A PIXEL-ART ADVENTURE", SFPalette.PAPER_DIM, 1)
	skin.text_c(self, VW * 0.5, 34, "STAR", SFPalette.PAPER, 4)
	skin.text_c(self, VW * 0.5, 74, "FALL", SFPalette.CYAN, 4)
	draw_rect(Rect2(VW * 0.5 - 110, 110, 220, 1), SFPalette.CYAN_DIM, true)
	skin.text_c(self, VW * 0.5, 118, "BUILD THE VELA. LISTEN TO THE SIGNAL.", SFPalette.PAPER)

	# Menu, in its own solid column on the right so it never sits on the planet.
	var column := Rect2(408, 140, 200, 146)
	draw_rect(column, Color(0.03, 0.06, 0.08, 0.86), true)
	draw_rect(column, SFPalette.CYAN_DIM, false, 1.0)
	draw_rect(Rect2(column.position, Vector2(column.size.x, 1)), SFPalette.CYAN, true)
	ui.menu_list(self, title_menu, column.position + Vector2(13, 12), column.size.x - 26, 19.0, SFPalette.CYAN)

	if not practice_unlocked:
		skin.text_c(self, column.position.x + column.size.x * 0.5, column.end.y + 8.0, "ECO ARENA PRACTICE UNLOCKS", SFPalette.ASH_LIGHT)
		skin.text_c(self, column.position.x + column.size.x * 0.5, column.end.y + 18.0, "AFTER THE SCRAP KING FALLS", SFPalette.ASH_LIGHT)
	var note_y: float = column.end.y - 14.0
	if not save_available:
		skin.text_c(self, column.position.x + column.size.x * 0.5, note_y, "NO SAVE YET", SFPalette.ASH_LIGHT)
	else:
		skin.text_c(self, column.position.x + column.size.x * 0.5, note_y, "SAVE AVAILABLE", SFPalette.CYAN_DIM)

	# Footer on a solid strip, never over the planet.
	draw_rect(Rect2(0, VH - 26, VW, 26), Color(0.03, 0.06, 0.08, 0.92), true)
	draw_rect(Rect2(0, VH - 26, VW, 1), SFPalette.STEEL_DARK, true)
	skin.text_c(self, VW * 0.5, VH - 20, "CLICK OR UP/DOWN + ENTER     ESC QUIT", SFPalette.PAPER_DIM)
	skin.text_c(self, VW * 0.5, VH - 10, "A FICTIONAL STORY. TIME TRAVEL IS NOT REAL.", SFPalette.ASH_LIGHT)
	skin.vignette(self)


# ---------------------------------------------------------------- settings draw

func _draw_settings() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	ui.header(self, "SETTINGS", "Local preferences. Nothing here affects the campaign.")
	draw_settings_panel(self)


# ---------------------------------------------------------------- launch draw

func _draw_launch() -> void:
	match launch_phase:
		LaunchPhase.COUNTDOWN:
			_draw_countdown()
		LaunchPhase.ASCENT:
			_draw_ascent()
		LaunchPhase.SIGNAL:
			_draw_signal()
		LaunchPhase.RIFT:
			_draw_rift()
		LaunchPhase.CRASH:
			_draw_crash()
		LaunchPhase.DONE:
			pass


func _draw_countdown() -> void:
	# A. Ready on the pad: engines off, the gantry beside it, a launch-ready cue.
	_draw_launch_sky(0.0)
	_draw_launch_pad(0.0, 0.0, 0.0)
	_draw_ship_silhouette(LAUNCH_PAD)
	var n: int = 3 - int(launch_timer / 0.85)
	if n < 0:
		n = 0
	_launch_caption_box(34, 74)
	skin.text_c(self, VW * 0.5, 40, "VELA READY ON PAD 1 - LAUNCH CLEARANCE GRANTED", SFPalette.PAPER)
	skin.text_c(self, VW * 0.5, 54, "T-%d" % n if n > 0 else "IGNITION", SFPalette.GOLD, 3)
	skin.text_c(self, VW * 0.5, 96, "ENGINES OFF   PREFLIGHT PASSED   SIGNAL INVESTIGATION", SFPalette.PAPER_DIM)


func _draw_ascent() -> void:
	# B. Ignition, C. liftoff, D. atmosphere, E. space: one continuous shot.
	# VELA keeps its built design and stays upright, nose up, flame below.
	var t: float = launch_timer
	var thrust: float = clampf(t / IGNITION_END, 0.0, 1.0)
	var rise: float = 0.0
	if t > IGNITION_END:
		rise = pow(t - IGNITION_END, 2.0) * 60.0
	var climb: float = minf(rise, LAUNCH_FOLLOW)
	var cam: float = maxf(0.0, rise - LAUNCH_FOLLOW)
	var altitude: float = clampf((t - IGNITION_END) / (ATMOSPHERE_END - IGNITION_END), 0.0, 1.0)
	var space: float = clampf((t - ATMOSPHERE_END) / (ASCENT_SECONDS - ATMOSPHERE_END), 0.0, 1.0)

	_draw_launch_sky(altitude)
	# Clouds slide past once the camera follows the climb.
	for layer in 3:
		var base_y: float = -60.0 - float(layer) * 150.0 + cam * (0.9 + float(layer) * 0.15)
		if base_y < -40.0 or base_y > VH + 20.0:
			continue
		for i in 7:
			var cx: float = fmod(float(i) * 113.0 + float(layer) * 47.0, float(VW + 80)) - 40.0
			var cw: float = 48.0 + float((i * 37 + layer * 11) % 40)
			var a: float = 0.55 * (1.0 - space)
			draw_rect(Rect2(round(cx), round(base_y + float((i * 23) % 30)), cw, 7), Color(0.92, 0.95, 0.97, a), true)
			draw_rect(Rect2(round(cx + 8.0), round(base_y + float((i * 23) % 30) - 4.0), cw - 16.0, 5), Color(1.0, 1.0, 1.0, a * 0.8), true)
	# E. Earth below: the curved limb rises into view as the sky goes black.
	if space > 0.0:
		var limb_top: float = VH + 20.0 - space * 190.0
		var radius: float = 900.0
		var y: float = limb_top
		while y < VH:
			var dy: float = y - (limb_top + radius)
			var half: float = sqrt(maxf(0.0, radius * radius - dy * dy))
			var depth: float = (y - limb_top) / 60.0
			var col: Color = SFPalette.SKY.lerp(SFPalette.SKY_DEEP, clampf(depth, 0.0, 1.0))
			draw_rect(Rect2(round(VW * 0.5 - half), y, round(half * 2.0), 2), col, true)
			y += 2.0
		# Atmosphere glow along the limb.
		for i in 64:
			var ang: float = PI + float(i) / 63.0 * PI
			var gx: float = VW * 0.5 + cos(ang) * radius
			var gy: float = limb_top + radius + sin(ang) * radius
			if gy < VH and gx > -4.0 and gx < VW + 4.0:
				draw_rect(Rect2(round(gx), round(gy) - 1, 12, 2), Color(SFPalette.CYAN.r, SFPalette.CYAN.g, SFPalette.CYAN.b, 0.55), true)
	# The pad and its smoke fall away below once the camera follows.
	if cam < VH:
		_draw_launch_pad(cam, thrust, t)
	# Restrained vibration around ignition and liftoff only.
	var shake_x: float = 0.0
	if not setting_reduced_motion and t > 0.3 and t < LIFTOFF_END:
		shake_x = round(sin(time * 47.0) * (1.0 if t < IGNITION_END else 0.6))
	var ship_ground := Vector2(LAUNCH_PAD.x + shake_x, LAUNCH_PAD.y - climb)
	SFVela._draw_flame(self, ship_ground + Vector2(0, -10), 1, 0.35 + 0.65 * thrust, time)
	_draw_ship_silhouette(ship_ground, rise < 1.0)

	# Captions: none while the engines build up on the pad, the first line from
	# liftoff, the second (the signal) once VELA reaches orbit.
	var lines: Array = campaign.content.dialogue_lines("launch")
	var idx: int = -1
	if t >= IGNITION_END:
		idx = 0 if t < ATMOSPHERE_END else 1
	idx = mini(idx, lines.size() - 1)
	var stage_label := "IGNITION"
	if t >= ATMOSPHERE_END:
		stage_label = "ORBIT - EARTH BELOW"
	elif t >= LIFTOFF_END:
		stage_label = "ATMOSPHERIC ASCENT"
	elif t >= IGNITION_END:
		stage_label = "LIFTOFF"
	_launch_caption_box(VH - 46, 36)
	skin.text_c(self, VW * 0.5, VH - 42, stage_label if t >= IGNITION_END else "IGNITION - ENGINES LIT", SFPalette.GOLD)
	if idx >= 0:
		skin.text_c(self, VW * 0.5, VH - 28, String(lines[idx]), SFPalette.PAPER)


func _launch_caption_box(y: float, h: float) -> void:
	draw_rect(Rect2(60, y, VW - 120, h), Color(0.02, 0.04, 0.05, 0.72), true)
	draw_rect(Rect2(60, y, VW - 120, 1), SFPalette.CYAN_DARK, true)


## Day sky that darkens toward space as `altitude` goes 0 -> 1.
func _draw_launch_sky(altitude: float) -> void:
	var bands := 18
	for b in bands:
		var f: float = float(b) / float(bands - 1)
		var day: Color = SFPalette.SKY_DEEP.lerp(SFPalette.SKY, f)
		var night: Color = SFPalette.INK.lerp(SFPalette.SKY_DEEP.darkened(0.55), f * 0.6)
		draw_rect(Rect2(0, float(b) * 20.0, VW, 20), day.lerp(night, altitude), true)
	if altitude > 0.25:
		var a: float = (altitude - 0.25) / 0.75
		for i in 70:
			draw_rect(Rect2(float((i * 83) % VW), float((i * 53) % 300), 1, 1), Color(1, 1, 1, a * (0.4 + 0.5 * float(i % 3) / 2.0)), true)


## The launch site: grass, a concrete deck over a flame trench, the service
## gantry with its access arm, and floodlight masts for scale. `cam` moves the
## whole site down as the camera follows VELA; `thrust` and `t` drive the
## exhaust smoke at the pad (none while the engines are off).
func _draw_launch_pad(cam: float, thrust: float, t: float) -> void:
	var g: float = LAUNCH_PAD.y + cam
	draw_rect(Rect2(0, g - 40, VW, VH - g + 40 + cam), SFPalette.GRASS_DARK, true)
	draw_rect(Rect2(0, g - 40, VW, 3), SFPalette.GRASS, true)
	# Distant tree line and a hangar for scale.
	for i in 16:
		var tx: float = float(i) * 42.0 + float((i * 17) % 13)
		draw_rect(Rect2(tx, g - 52 - float((i * 7) % 6), 26, 14), SFPalette.LEAF_DARK, true)
	draw_rect(Rect2(470, g - 78, 120, 40), SFPalette.CONCRETE_DARK, true)
	draw_rect(Rect2(470, g - 78, 120, 3), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(500, g - 62, 60, 24), SFPalette.STEEL_DARK, true)
	# Deck and trench.
	draw_rect(Rect2(LAUNCH_PAD.x - 70, g - 2, 140, 14), SFPalette.CONCRETE_DARK, true)
	draw_rect(Rect2(LAUNCH_PAD.x - 70, g - 2, 140, 2), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(LAUNCH_PAD.x - 18, g + 2, 36, 10), SFPalette.INK, true)
	for i in 6:
		draw_rect(Rect2(LAUNCH_PAD.x - 66 + float(i) * 26.0, g + 4, 2, 8), SFPalette.STEEL_DARK, true)
	# Service gantry: a lattice tower left of the ship with an access arm.
	var gx: float = LAUNCH_PAD.x - 64.0
	draw_rect(Rect2(gx, g - 150, 14, 148), SFPalette.STEEL_DARK, true)
	var ly: float = g - 146.0
	while ly < g - 4.0:
		draw_rect(Rect2(gx + 1, ly, 12, 1), SFPalette.STEEL_MID, true)
		draw_rect(Rect2(gx + 6, ly, 2, 8), SFPalette.STEEL_MID, true)
		ly += 10.0
	var arm_open: float = clampf(t / 0.8, 0.0, 1.0) if thrust > 0.0 else 0.0
	draw_rect(Rect2(gx + 14, g - 112, 30.0 - 18.0 * arm_open, 3), SFPalette.RUST, true)
	draw_rect(Rect2(gx + 3, g - 156, 8, 6), SFPalette.RED, true)
	# Floodlight masts.
	for mx in [LAUNCH_PAD.x - 150.0, LAUNCH_PAD.x + 150.0]:
		draw_rect(Rect2(mx, g - 120, 2, 118), SFPalette.STEEL_MID, true)
		draw_rect(Rect2(mx - 5, g - 124, 12, 4), SFPalette.PAPER, true)
	skin.contact_shadow(self, Vector2(LAUNCH_PAD.x, g + 2), 70.0, 0.30)
	# Exhaust smoke: builds during ignition, then rolls out along the deck.
	if thrust > 0.0:
		var puffs: int = int(clampf(t / IGNITION_END, 0.0, 1.0) * 14.0) + (10 if t > IGNITION_END else 0)
		for i in puffs:
			var side: float = -1.0 if i % 2 == 0 else 1.0
			var spread: float = 10.0 + float(i) * 4.0 + maxf(0.0, t - IGNITION_END) * 30.0
			var px: float = LAUNCH_PAD.x + side * minf(spread, 240.0) + sin(float(i) * 2.3 + t) * 6.0
			var py: float = g + 4.0 - float((i * 7) % 18) - maxf(0.0, t - IGNITION_END) * 6.0
			var r: float = 6.0 + float(i % 4) * 3.0 + maxf(0.0, t - IGNITION_END) * 4.0
			var a: float = 0.55 * clampf(1.0 - maxf(0.0, t - LIFTOFF_END) / 3.0, 0.0, 1.0)
			draw_rect(Rect2(round(px - r), round(py - r * 0.6), round(r * 2.0), round(r * 1.2)), Color(0.86, 0.86, 0.84, a), true)
			draw_rect(Rect2(round(px - r * 0.6), round(py - r), round(r * 1.2), round(r * 0.6)), Color(0.95, 0.95, 0.93, a * 0.8), true)


func _draw_signal() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	# Instrument panel around a tuning dial.
	var dial := Rect2(200, 92, 240, 96)
	draw_rect(dial, Color(0.05, 0.10, 0.11), true)
	draw_rect(dial, SFPalette.CYAN_DIM, false, 1.0)
	skin.text(self, dial.position + Vector2(8, 6), "SIGNAL TUNING", SFPalette.CYAN)
	skin.text_r(self, dial.end.x - 8, dial.position.y + 6, "LOCK %d / 3" % signal_locks, SFPalette.PAPER)

	var track := Rect2(dial.position.x + 12, dial.position.y + 32, dial.size.x - 24, 24)
	draw_rect(track, SFPalette.INK, true)
	draw_rect(track, SFPalette.STEEL_DARK, false, 1.0)
	# Target zone.
	var tz := Rect2(track.position.x + (track.size.x - 20) * signal_target, track.position.y, 20, track.size.y)
	draw_rect(tz, Color(0.2, 0.7, 0.6, 0.35), true)
	draw_rect(tz, SFPalette.CYAN, false, 1.0)
	# Moving marker.
	var mx := track.position.x + (track.size.x - 4) * signal_marker
	draw_rect(Rect2(mx, track.position.y - 2, 4, track.size.y + 4), SFPalette.PAPER, true)
	skin.text_c(self, dial.position.x + dial.size.x * 0.5, dial.end.y - 20, "A/D OR ARROWS TUNE   E OR LOCK TO LOCK", SFPalette.PAPER_DIM)
	skin.text_c(self, VW * 0.5, 214, "THE SIGNAL IS NOT WHERE THE BRIEF SAID IT WOULD BE.", SFPalette.PAPER)
	if signal_attempts > 0 and signal_locks == 0:
		skin.text_c(self, VW * 0.5, 228, "Keep trying. The sequence resolves either way.", SFPalette.ASH_LIGHT)
	skin.button(self, SIGNAL_LOCK_BUTTON, "LOCK SIGNAL", SIGNAL_LOCK_BUTTON.has_point(_ui_mouse()), true)
	# Waveform, decorative but truthful about the lock count.
	for i in 120:
		var x := 60.0 + float(i) * 4.4
		var amp: float = 4.0 + float(signal_locks) * 3.0
		var y := 270.0 + sin(float(i) * 0.35 + time * 5.0) * amp
		draw_rect(Rect2(x, y, 2, 1), SFPalette.CYAN_DIM, true)


func _draw_rift() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color(0.04, 0.02, 0.09), true)
	var cx := VW * 0.5 + crash_shake
	var cy := VH * 0.44

	# Stars dragged toward the tear, longer nearer the seam.
	for i in 110:
		var ang := float(i) * 2.399
		var r := 26.0 + float((i * 37) % 260)
		var pull: float = 1.0 / (1.0 + r / 90.0)
		var x := cx + cos(ang) * r * (1.0 - pull * 0.55)
		var y := cy + sin(ang) * r * 0.62
		var c := Color(0.75, 0.80, 0.95, 0.20 + pull * 0.5)
		draw_rect(Rect2(round(x), round(y), 1, 1), c, true)
		# Streak toward the seam.
		draw_rect(Rect2(round(x), round(y), maxf(1.0, round(r * 0.03)), 1), Color(c.r, c.g, c.b, c.a * 0.5), true)

	# The tear: a ragged vertical seam, brightest in the middle.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	var seam := 0
	while seam < 40:
		var t: float = float(seam) / 40.0
		var y2: float = cy - 178.0 + t * 356.0
		# Width tapers to nothing at both ends.
		var taper: float = sin(t * PI)
		var jitter: float = sin(float(seam) * 1.9 + time * 6.0) * 3.5
		var glow_w: float = 2.0 + taper * 26.0
		var glow := Color(0.42, 0.28, 0.62, 0.10 + taper * 0.18)
		draw_rect(Rect2(round(cx + jitter - glow_w * 0.5), round(y2), round(glow_w), 3), glow, true)
		# Core.
		var core_w: float = maxf(1.0, taper * 5.0)
		var core := Color(0.80, 0.92, 1.0, 0.55 + taper * 0.42)
		draw_rect(Rect2(round(cx + jitter - core_w * 0.5), round(y2), round(core_w), 2), core, true)
		# Violet edge light.
		if seam % 2 == 0:
			draw_rect(Rect2(round(cx + jitter + glow_w * 0.42), round(y2), 1, 2), Color(0.55, 0.35, 0.80, 0.7), true)
			draw_rect(Rect2(round(cx + jitter - glow_w * 0.42), round(y2), 1, 2), Color(0.55, 0.35, 0.80, 0.7), true)
		seam += 1

	# The VELA, small against the tear, being pulled off course.
	_draw_ship_silhouette(Vector2(cx + sin(time * 2.2) * 12.0 + 56.0, cy + 96.0), false)

	var lines: Array = campaign.content.dialogue_lines("rift")
	var idx: int = mini(int(launch_timer / 1.1), maxi(0, lines.size() - 1))
	if not lines.is_empty():
		draw_rect(Rect2(0, VH - 54, VW, 20), Color(0.02, 0.02, 0.05, 0.75), true)
		skin.text_c(self, VW * 0.5, VH - 48, String(lines[idx]), SFPalette.PAPER)


func _draw_crash() -> void:
	var shake := crash_shake
	# Sky: ash haze fading upward into black.
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var band := 0
	while band < 16:
		var t: float = float(band) / 16.0
		var c: Color = SFPalette.INK.lerp(SFPalette.RUIN_DARK, t * t)
		draw_rect(Rect2(0, 120 + band * 12, VW, 13), c, true)
		band += 1
	# Ground line.
	draw_rect(Rect2(0, 312, VW, VH - 312), SFPalette.ASH_PLAIN.darkened(0.3), true)
	draw_rect(Rect2(0, 312, VW, 2), SFPalette.ASH.darkened(0.2), true)

	# The VELA comes down and settles: it falls into frame, then stops.
	var settle: float = clampf(launch_timer / 0.55, 0.0, 1.0)
	var ease: float = 1.0 - pow(1.0 - settle, 3.0)
	var ship_y: float = 96.0 + ease * 168.0
	var tilt: float = (1.0 - ease) * 0.18
	_draw_ship_tilted(Vector2(VW * 0.5 + shake * 2.0, ship_y), tilt)

	# Impact debris: throws outward and falls.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	for i in 44:
		var life: float = fmod(float(i) * 0.13, 1.0)
		var t: float = clampf(launch_timer / 1.8, 0.0, 1.0)
		if life > t:
			continue
		var ang: float = rng.randf_range(-PI, 0.0)
		var speed: float = rng.randf_range(70.0, 230.0)
		var age: float = maxf(0.0, launch_timer - life * 1.8)
		var px: float = VW * 0.5 + cos(ang) * speed * age * 0.6 + shake
		var py: float = ship_y + sin(ang) * speed * age + 210.0 * age * age
		if py > 316.0:
			continue
		var size: int = 2 if i % 3 else 3
		var c: Color = SFPalette.ASH_LIGHT if i % 4 else SFPalette.RUST
		draw_rect(Rect2(round(px), round(py), size, maxi(1, size - 1)), c, true)

	# Smoke columns rising from the impact point.
	if launch_timer > 0.4:
		var smoke_age: float = launch_timer - 0.4
		for i in 16:
			var drift: float = float(i) * 0.16
			var rise: float = smoke_age * (26.0 + float(i) * 2.0)
			var sx: float = VW * 0.5 + sin(float(i) * 2.1 + smoke_age) * (10.0 + float(i) * 3.5) + drift * 12.0
			var sy: float = 300.0 - rise
			if sy < 40.0:
				continue
			var alpha: float = clampf(1.0 - (300.0 - sy) / 280.0, 0.0, 1.0) * 0.30
			var rad: float = 8.0 + float(i) * 1.4
			for dy in range(int(-rad), int(rad) + 1):
				for dx in range(int(-rad), int(rad) + 1):
					var d2: float = float(dx * dx + dy * dy) / (rad * rad)
					if d2 > 1.0 or (dx + dy + i) % 3 == 0:
						continue
					draw_rect(Rect2(round(sx + float(dx)), round(sy + float(dy)), 1, 1), Color(0.30, 0.33, 0.32, alpha * (1.0 - d2)), true)

	# First-frame flash.
	if launch_timer < 0.14:
		draw_rect(Rect2(0, 0, VW, VH), Color(1.0, 0.96, 0.88, 0.7 * (1.0 - launch_timer / 0.14)), true)

	# Captions start once the ship has settled.
	var lines: Array = campaign.content.dialogue_lines("crash")
	if not lines.is_empty() and launch_timer >= 0.55:
		var idx: int = mini(int((launch_timer - 0.55) / 1.0), lines.size() - 1)
		draw_rect(Rect2(0, VH - 54, VW, 20), Color(0.02, 0.03, 0.03, 0.8), true)
		skin.text_c(self, VW * 0.5, VH - 48, String(lines[idx]), SFPalette.PAPER)


## Ship drawing with a roll applied, used for the crash approach.
func _draw_ship_tilted(ground: Vector2, tilt: float) -> void:
	draw_set_transform(ground, tilt, Vector2.ONE)
	_draw_ship_silhouette(Vector2.ZERO, tilt <= 0.001)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A compact side/three-quarter silhouette of the assembled ship, using the
## same visual language as the construction screen.
## The player-built day-one VELA, drawn by the same function as the assembly
## console, so the pad, the climb, the rift and the crash all show one ship.
func _draw_ship_silhouette(ground: Vector2, grounded: bool = true) -> void:
	SFConstruction.draw_day_one_ship(self, skin, ground, campaign.design, campaign.content, time, false, grounded)


# ---------------------------------------------------------------- memory draw

func _draw_memory() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var data: Dictionary = campaign.content.memory(memory_id)
	var lines: Array = data.get("lines", []) as Array

	var cx := VW * 0.5
	var cy := 190.0
	var flicker := 0.82 + 0.18 * sin(time * 17.0) * sin(time * 3.0)
	# Projection cone, shared by both holograms.
	for i in 18:
		var t := float(i) / 18.0
		var w := 30.0 + t * 170.0
		var a := 0.05 + 0.06 * (1.0 - t) * flicker
		draw_rect(Rect2(cx - w * 0.5, cy - 96 + t * 122, w, 2), Color(0.35, 0.95, 0.85, a), true)

	# The hologram matches the memory's `scene` field in campaign.json: the
	# Green City memories are projected city blocks, the coastal memory is a
	# working harbour. Data decides, not this script.
	if campaign.content.memory_scene(memory_id) == "coast":
		_draw_coast_hologram(cx, cy, flicker)
	elif campaign.content.memory_scene(memory_id) == "forest":
		_draw_forest_hologram(cx, cy, flicker)
	else:
		_draw_city_hologram(cx, cy, flicker)

	# Frame and text.
	skin.text_c(self, cx, 26, String(data.get("title", "MEMORY")).to_upper(), SFPalette.CYAN, 2)
	skin.text_c(self, cx, 50, String(data.get("frame", "")), SFPalette.PAPER_DIM)

	var box := Rect2(90, 246, 460, 66)
	draw_rect(box, Color(0.04, 0.08, 0.09, 0.95), true)
	draw_rect(box, SFPalette.CYAN_DIM, false, 1.0)
	if not lines.is_empty():
		var idx := mini(memory_index, lines.size() - 1)
		var text := String(lines[idx])
		var visible := text
		if int(memory_chars) < text.length():
			visible = text.substr(0, int(memory_chars))
		skin.wrap(self, box.position + Vector2(12, 10), box.size.x - 24, visible, SFPalette.PAPER, 1, 4)
		skin.text_r(self, box.end.x - 10, box.end.y - 12, "%d / %d" % [idx + 1, lines.size()], SFPalette.PAPER_DIM)
	skin.text(self, Vector2(100, VH - 20), "ENTER OR CLICK: NEXT", SFPalette.ASH_LIGHT)
	var mouse := _ui_mouse()
	skin.button(self, MEMORY_NEXT, "NEXT", MEMORY_NEXT.has_point(mouse), true)
	skin.button(self, MEMORY_SKIP, "SKIP", MEMORY_SKIP.has_point(mouse), true)
	skin.scanlines(self, 0.05)


func _draw_city_hologram(cx: float, cy: float, flicker: float) -> void:
	var base_y := cy + 34
	for i in 9:
		var bx := cx - 84.0 + float(i) * 19.0
		var bh := 22.0 + float((i * 37) % 46)
		var col := Color(0.18, 0.55, 0.45, 0.55 * flicker)
		draw_rect(Rect2(bx, base_y - bh, 13, bh), col, true)
		draw_rect(Rect2(bx, base_y - bh, 13, 1), Color(0.45, 0.85, 0.7, 0.6 * flicker), true)
		# Lit windows.
		for wy in range(2, int(bh) - 2, 5):
			draw_rect(Rect2(bx + 3, base_y - bh + wy, 2, 2), Color(0.6, 1.0, 0.8, 0.5 * flicker), true)
	# Trees.
	for i in 5:
		var tx := cx - 92.0 + float(i) * 46.0
		draw_rect(Rect2(tx, base_y - 10, 2, 10), Color(0.4, 0.7, 0.35, 0.5 * flicker), true)
		draw_rect(Rect2(tx - 4, base_y - 18, 10, 9), Color(0.35, 0.8, 0.45, 0.5 * flicker), true)
	draw_rect(Rect2(cx - 90, base_y, 180, 2), Color(0.4, 0.95, 0.8, 0.35 * flicker), true)


## A working harbour hologram: clear water, boats, gulls, and a shoreline.
## Brighter and higher-contrast than the city hologram, because the whole point
## of this memory is that the water used to be clear.
func _draw_coast_hologram(cx: float, cy: float, flicker: float) -> void:
	var horizon := cy - 12.0
	var water := Color(0.22, 0.78, 0.70, 0.72 * flicker)
	var deep := Color(0.10, 0.46, 0.48, 0.62 * flicker)
	var foam := Color(0.66, 1.0, 0.92, 0.72 * flicker)
	var land := Color(0.30, 0.60, 0.38, 0.66 * flicker)

	# Water: a filled body first, then scan bands on top so it reads as a
	# projected volume rather than a few thin lines.
	draw_rect(Rect2(cx - 96.0, horizon + 4.0, 192.0, 58.0), deep, true)
	for i in 16:
		var t := float(i) / 15.0
		var wy := horizon + 4.0 + t * 58.0
		var alpha := (0.34 + 0.26 * (1.0 - t)) * flicker
		draw_rect(Rect2(cx - 96.0, wy, 192.0, 1), Color(water.r, water.g, water.b, alpha), true)
	# A band of light where the water meets the sky.
	draw_rect(Rect2(cx - 96.0, horizon + 4.0, 192.0, 2), foam, true)

	# Shoreline: a low, broken beach strip along the near edge, narrower than
	# the water so it reads as sand rather than as a fence.
	for i in 10:
		var sx := cx - 96.0 + float(i) * 20.0
		var sh := 3.0 + float((i * 13) % 4)
		draw_rect(Rect2(sx, horizon + 62.0 - sh, 18.0, sh), land, true)
		draw_rect(Rect2(sx, horizon + 62.0 - sh, 18.0, 1), Color(0.55, 0.85, 0.55, 0.6 * flicker), true)

	# Two boats with masts, floating on the lit half of the water.
	for i in 2:
		var bx := cx - 40.0 + float(i) * 74.0
		var by := horizon + 18.0 + float(i) * 10.0
		# Hull, lit along the gunwale.
		draw_rect(Rect2(bx - 16.0, by, 32.0, 6.0), Color(0.72, 1.0, 0.94, 0.78 * flicker), true)
		draw_rect(Rect2(bx - 16.0, by + 5.0, 32.0, 1), deep, true)
		# Cabin and mast.
		draw_rect(Rect2(bx - 5.0, by - 5.0, 10.0, 5.0), Color(0.55, 0.95, 0.88, 0.7 * flicker), true)
		draw_rect(Rect2(bx + 1.0, by - 22.0, 2.0, 17.0), foam, true)
		draw_rect(Rect2(bx - 9.0, by - 20.0, 10.0, 2.0), Color(0.55, 0.95, 0.88, 0.7 * flicker), true)
		# Reflection: broken, shorter than the hull.
		for r in 4:
			draw_rect(Rect2(bx - 12.0 + float(r % 2) * 3.0, by + 7.0 + float(r) * 2.0, 24.0 - float(r) * 3.0, 1), Color(water.r, water.g, water.b, 0.34 * flicker), true)

	# Gulls: two short strokes each, clear against the dark sky.
	for i in 3:
		var gx := cx - 64.0 + float(i) * 56.0
		var gy := horizon - 26.0 - float(i % 2) * 10.0
		draw_rect(Rect2(gx, gy, 4, 1), foam, true)
		draw_rect(Rect2(gx + 1, gy - 2, 2, 2), foam, true)
		draw_rect(Rect2(gx + 4, gy - 1, 3, 1), foam, true)

	# The net, held by someone just at the edge of the frame.
	draw_rect(Rect2(cx + 56.0, horizon + 22.0, 2.0, 18.0), foam, true)
	for n in 6:
		var ang := -PI * 0.5 + (float(n) - 2.5) * 0.30
		var nx := cx + 57.0 + cos(ang) * 11.0
		var ny := horizon + 40.0 + sin(ang) * 11.0
		draw_rect(Rect2(nx, ny, 1, 3), foam, true)
	draw_rect(Rect2(cx - 96.0, horizon + 62.0, 192.0, 1), Color(0.5, 1.0, 0.88, 0.5 * flicker), true)


# ---------------------------------------------------------------- checkpoint draw

func _draw_checkpoint() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.RUIN_BG, true)
	# Dawn over the ruined horizon: cyan band, dark land.
	var g := 0
	while g < 10:
		var t := float(g) / 10.0
		draw_rect(Rect2(0, 120 + g * 10, VW, 10), SFPalette.RUIN_DARK.lerp(SFPalette.CYAN_DARK, t * 0.4), true)
		g += 1
	draw_rect(Rect2(0, 240, VW, 120), SFPalette.RUIN, true)
	# Distant city, the destination.
	for i in 11:
		var bx := 120.0 + float(i) * 34.0
		var bh := 30.0 + float((i * 53) % 70)
		draw_rect(Rect2(bx, 240 - bh, 22, bh), SFPalette.RUIN_DARK, true)
		draw_rect(Rect2(bx, 240 - bh, 22, 1), SFPalette.VIOLET, true)
	draw_rect(Rect2(0, 240, VW, 2), SFPalette.VIOLET_LIGHT, true)

	# The same screen closes both phases, so its copy follows the campaign.
	# Phase 1's summary is a waypoint on the road to the Forgotten City; Phase
	# 2's is the end of this build.
	var phase_two: bool = campaign.has_flag(SFCampaign.FLAG_PHASE_TWO_COMPLETE)
	if campaign.is_ready_for_final_assembly():
		_draw_ready_summary()
		return
	var data: Dictionary = campaign.content.checkpoint
	var panel := Rect2(88, 40, 464, 190)
	draw_rect(panel, Color(0.05, 0.09, 0.10, 0.94), true)
	draw_rect(panel, SFPalette.CYAN, false, 1.0)
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 1)), SFPalette.CYAN, true)

	var title := String(data.get("title", "PHASE 1 COMPLETE")) if not phase_two else "PHASE 2 COMPLETE"
	skin.text_c(self, VW * 0.5, panel.position.y + 14, title.to_upper(), SFPalette.CYAN, 2)
	var body: Array = data.get("body", []) as Array
	if phase_two:
		body = [
			"Navigation chip and power core are fitted to the VELA's frame.",
			"The control-center and environmental archives are restored.",
			"Nick is carrying the record the machines were built to erase.",
			"Dawn Tower is unlocked on the chart. The shield emitter is waiting there.",
		]
	var y: float = panel.position.y + 44.0
	for line in body:
		y = skin.wrap(self, Vector2(panel.position.x + 20, y), panel.size.x - 40, String(line), SFPalette.PAPER, 1, 3) + 4.0

	if phase_two:
		var comps := "CHIP %s   CORE %s   EMITTER %s" % [
			"FITTED" if campaign.has_component(SFCampaign.COMPONENT_NAVIGATION_CHIP) else "MISSING",
			"FITTED" if campaign.has_component(SFCampaign.COMPONENT_POWER_CORE) else "MISSING",
			"FITTED" if campaign.has_component(SFCampaign.COMPONENT_SHIELD_EMITTER) else "MISSING",
		]
		skin.text_c(self, VW * 0.5, panel.end.y - 34, comps, SFPalette.GOLD)
		skin.text_c(self, VW * 0.5, panel.end.y - 18, "PHASE 2 COMPLETE - CHECKPOINT SAVED", SFPalette.GREEN_OK)
	else:
		var manifest: Dictionary = campaign.mission_manifest
		if not manifest.is_empty():
			var stats := "SHIP %s   SENSOR Q%d   DATA %.0f MB   SALVAGE %d" % [
				String(manifest.get("ship", "VELA")),
				int(manifest.get("sensor_quality", 0)),
				float(manifest.get("surviving_data_mb", 0.0)),
				campaign.inventory_used(),
			]
			skin.text_c(self, VW * 0.5, panel.end.y - 34, stats, SFPalette.GOLD)
		skin.text_c(self, VW * 0.5, panel.end.y - 18, "PHASE 1 COMPLETE - CHECKPOINT SAVED", SFPalette.GREEN_OK)

	# Footer on its own strip, clear of the panel above it.
	draw_rect(Rect2(0, VH - 30, VW, 30), Color(0.03, 0.05, 0.05, 0.9), true)
	draw_rect(Rect2(0, VH - 30, VW, 1), SFPalette.CYAN_DARK, true)
	if phase_two:
		skin.text_c(self, VW * 0.5, VH - 23, "ENTER  CONTINUE TO THE DAWN TOWER", SFPalette.PAPER)
		skin.text_c(self, VW * 0.5, VH - 12, "DAWN TOWER - PHASE 3", SFPalette.ASH_LIGHT)
	else:
		skin.text_c(self, VW * 0.5, VH - 23, "ENTER  CONTINUE", SFPalette.PAPER)
		skin.text_c(self, VW * 0.5, VH - 12, "FORGOTTEN CITY - PHASE 2", SFPalette.ASH_LIGHT)
	_draw_checkpoint_buttons()


func _draw_checkpoint_buttons() -> void:
	var mouse := _ui_mouse()
	skin.button(self, CHECKPOINT_CONTINUE, "CONTINUE", true, true, SFPalette.GREEN_OK if CHECKPOINT_CONTINUE.has_point(mouse) else SFPalette.CYAN)
	skin.button(self, CHECKPOINT_MENU, "MENU", CHECKPOINT_MENU.has_point(mouse), true)


# ---------------------------------------------------------------- save error draw

func _draw_save_error() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var panel := Rect2(90, 90, 460, 170)
	ui.modal(self, panel, SFPalette.RED)
	skin.text(self, panel.position + Vector2(16, 14), "SAVE COULD NOT BE LOADED", SFPalette.RED)
	skin.wrap(self, panel.position + Vector2(16, 38), panel.size.x - 32, save_error_text, SFPalette.PAPER, 1, 5)
	skin.wrap(self, panel.position + Vector2(16, 106), panel.size.x - 32,
		"Your save file has been left untouched. Starting a new game will not delete it.",
		SFPalette.PAPER_DIM, 1, 3)
	ui.menu_list(self, save_error_menu, panel.position + Vector2(130, 126), 200.0, 18.0)


# ---------------------------------------------------------------- pause menu input

func _input(event: InputEvent) -> void:
	# The shared pause menu owns all input while it is open, ahead of every
	# screen, so nothing leaks into the frozen screen underneath.
	if pause_open:
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
			_pause_input(event)
		return
	# Esc opens it. A dialogue gets Esc first (it closes the dialogue), so one
	# key press can never both close a modal and reopen pause.
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE and dialogue == null and uses_main_pause():
			get_viewport().set_input_as_handled()
			audio.sfx_back()
			_open_pause()


func _pause_input(event: InputEvent) -> void:
	if pause_settings_open:
		_pause_settings_input(event)
		return
	var pos: Vector2 = _ui_mouse()
	if event is InputEventMouseMotion:
		if pause_menu.hover(pos):
			audio.sfx_select()
			refresh_overlay()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		# Only a left click on a row acts; right click never resumes.
		if mb.button_index == MOUSE_BUTTON_LEFT and pause_menu.click(pos) != "":
			_pause_activate()
		refresh_overlay()
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_ESCAPE:
			audio.sfx_back()
			_close_pause()
		KEY_UP, KEY_W:
			pause_menu.move_enabled(-1)
			audio.sfx_select()
		KEY_DOWN, KEY_S:
			pause_menu.move_enabled(1)
			audio.sfx_select()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_pause_activate()
	refresh_overlay()


func _pause_settings_input(event: InputEvent) -> void:
	var pos: Vector2 = _ui_mouse()
	if event is InputEventMouseMotion:
		_settings_mouse_motion(pos)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_settings_release()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_settings_click(pos)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			_settings_key(k.keycode)
	refresh_overlay()


func _pause_activate() -> void:
	match pause_menu.current_id():
		"resume":
			audio.sfx_blip()
			_close_pause()
		"save":
			_manual_save()
		"skip":
			_close_pause()
			match screen:
				Screen.CINEMATIC:
					if cinematic_screen != null:
						cinematic_screen.skip()
				Screen.MEMORY:
					_skip_memory()
				Screen.FINAL_ASSEMBLY:
					if assembly_screen != null:
						assembly_screen.skip_installation()
		"journal":
			audio.sfx_blip()
			journal_return = Screen.WORLD
			journal_index = maxi(0, campaign.vocabulary_journal.size() - 1)
			_go(Screen.JOURNAL)
		"settings":
			audio.sfx_blip()
			_rebuild_settings_menu()
			settings_menu.index = 0
			pause_settings_open = true
		"title":
			audio.sfx_back()
			_save_quietly()
			_go(Screen.TITLE)
	refresh_overlay()
