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
const SFArchive := preload("res://scenes/star_fall/archive_screen.gd")
const SFProgression := preload("res://scenes/star_fall/progression_screen.gd")

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
}

enum LaunchPhase {COUNTDOWN, ASCENT, SIGNAL, RIFT, CRASH, DONE}

const VW := 640
const VH := 360

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
var crash_shake: float = 0.0

# Memory playback.
var memory_id: String = ""
var memory_index: int = 0
var memory_chars: float = 0.0
var memory_next: Callable = Callable()

# Settings.
var setting_ambience: bool = true
var setting_text_speed: float = 52.0

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


func _ready() -> void:
	RenderingServer.set_default_clear_color(SFPalette.INK)
	campaign = GameState.campaign
	sites = SFSites.new()
	sites.load_all()

	audio = SFAudio.new()
	audio.name = "SFAudio"
	add_child(audio)
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
	# never writes or deletes anything.
	save_available = SFSave.has_valid_save()
	_rebuild_title_menu()


func _rebuild_title_menu() -> void:
	var items: Array = [
		{"id": "new", "label": "NEW GAME", "enabled": true},
		{"id": "continue", "label": "CONTINUE", "enabled": save_available},
		{"id": "settings", "label": "SETTINGS", "enabled": true},
		{"id": "quit", "label": "QUIT", "enabled": true},
	]
	var keep: String = String(title_menu.current_id()) if title_menu != null else ""
	title_menu.set_items(items, keep)
	# New Game is always a legal starting point for the cursor.
	if title_menu.index_of("continue") == title_menu.index and not save_available:
		title_menu.index = 0


func _rebuild_settings_menu() -> void:
	settings_menu.set_items([
		{"id": "ambience", "label": "AMBIENT SOUND", "detail": "ON" if setting_ambience else "OFF", "enabled": true},
		{"id": "text_speed", "label": "TEXT SPEED", "detail": "FAST" if setting_text_speed > 60.0 else ("SLOW" if setting_text_speed < 40.0 else "NORMAL"), "enabled": true},
		{"id": "back", "label": "BACK", "enabled": true},
	], String(settings_menu.current_id()))


func _rebuild_pause_menu() -> void:
	var items: Array = []
	if screen == Screen.WORLD:
		items.append({"id": "resume", "label": "RESUME", "enabled": true})
		items.append({"id": "save", "label": "SAVE PROGRESS", "enabled": true})
		items.append({"id": "settings", "label": "SETTINGS", "enabled": true})
		items.append({"id": "title", "label": "RETURN TO MAIN MENU", "enabled": true})
	else:
		items.append({"id": "resume", "label": "RESUME", "enabled": true})
		items.append({"id": "settings", "label": "SETTINGS", "enabled": true})
		items.append({"id": "title", "label": "RETURN TO MAIN MENU", "enabled": true})
	pause_menu.set_items(items, String(pause_menu.current_id()))


# ---------------------------------------------------------------- screen flow

func _go(next: int) -> void:
	if next == screen:
		queue_redraw()
		return
	previous_screen = screen
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
	if archive_screen != null:
		archive_screen.queue_free()
		archive_screen = null
	if progression_screen != null:
		progression_screen.queue_free()
		progression_screen = null

	screen = next
	blink = 0.0
	pause_open = false
	ui.clear_toast()

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
		Screen.ARCHIVE:
			_enter_archive()
		Screen.PROGRESSION:
			_enter_progression()
		Screen.SAVE_ERROR:
			if audio.has_method("stop_music"):
				audio.stop_music()
	queue_redraw()


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
	world.set_input_enabled(true)
	audio.set_ambience(_world_ambience(zone_id))
	if audio.has_method("play_music"):
		audio.play_music("earth" if zone_id == "spaceport" else "ruin")
	apply_focus_state()
	queue_redraw()


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
	var locked := dialogue != null or screen != Screen.WORLD
	if world != null:
		world.set_input_enabled(not locked)
	# While a dialogue is open over the duel, the arena is frozen: the player is
	# reading, so no attack may land and no key may be stolen from the dialogue.
	encounter_input_locked = dialogue != null
	if duel != null:
		duel.input_locked = encounter_input_locked


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


func _menu_item_at(menu, origin: Vector2, width: float, row_h: float, pos: Vector2) -> int:
	if menu == null:
		return -1
	for i in menu.items.size():
		var r := Rect2(origin.x, origin.y + float(i) * row_h, width, row_h - 2.0)
		if r.has_point(pos):
			return i
	return -1


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	var pos: Vector2 = get_local_mouse_position()
	if dialogue != null:
		return
	match screen:
		Screen.TITLE:
			var idx := _menu_item_at(title_menu, Vector2(421, 152), 174.0, 19.0, pos)
			if idx >= 0 and idx != title_menu.index and bool((title_menu.items[idx] as Dictionary).get("enabled", true)):
				title_menu.index = idx
				audio.sfx_select()
				queue_redraw()
		Screen.SETTINGS:
			var idx2 := _menu_item_at(settings_menu, Vector2(124, 100), 392.0, 22.0, pos)
			if idx2 >= 0 and idx2 != settings_menu.index:
				settings_menu.index = idx2
				audio.sfx_select()
				queue_redraw()
		Screen.WORLD:
			if world != null:
				world.handle_mouse_motion()
				if mm.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
					world.handle_mouse_click((mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if not mb.pressed:
		return
	var pos: Vector2 = get_local_mouse_position()

	if dialogue != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_dialogue_key(KEY_ENTER)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_handle_dialogue_key(KEY_ESCAPE)
		return

	match screen:
		Screen.TITLE:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var idx := _menu_item_at(title_menu, Vector2(421, 152), 174.0, 19.0, pos)
				if idx >= 0:
					title_menu.index = idx
					_title_activate()
					queue_redraw()
		Screen.SETTINGS:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_settings_key(KEY_ESCAPE)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				var idx2 := _menu_item_at(settings_menu, Vector2(124, 100), 392.0, 22.0, pos)
				if idx2 >= 0:
					settings_menu.index = idx2
					_settings_key(KEY_ENTER)
				elif pos.y >= 336.0:
					_settings_key(KEY_ESCAPE)
		Screen.WORLD:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				audio.sfx_back()
				_open_pause()
			elif mb.button_index == MOUSE_BUTTON_LEFT and world != null:
				# Check if player clicked the bottom-center interaction prompt or top-right zone/pause badge
				if world.focused_prop() != null and Rect2(220, 290, 200, 28).has_point(pos):
					world.try_interact()
				elif Rect2(520, 4, 116, 22).has_point(pos):
					audio.sfx_back()
					_open_pause()
				else:
					world.handle_mouse_click(mb.double_click)
		Screen.LAUNCH:
			if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and pos.y >= 330.0):
				_launch_key(KEY_ESCAPE)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_launch_key(KEY_ENTER)
		Screen.MEMORY:
			if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and pos.y >= 336.0 and pos.x > 330.0):
				_memory_key(KEY_ESCAPE)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_memory_key(KEY_ENTER)
		Screen.CHECKPOINT:
			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
				_checkpoint_key(KEY_ENTER)
		Screen.SAVE_ERROR:
			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
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
			campaign.advance_to(SFCampaign.STAGE_CRASH_INTRO)
			_finish_launch_state()
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
		SFCampaign.STAGE_CITY_BOSS:
			# A partially completed fight is never serialised: the checkpoint
			# before the encounter is the resume point.
			_begin_city_boss()
		SFCampaign.STAGE_CITY_ARCHIVE:
			campaign.advance_to(SFCampaign.STAGE_CITY_ARCHIVE)
			_enter_archive_scene(SFCampaign.ARCHIVE_CITY)
		SFCampaign.STAGE_SILENT_INTRO:
			_go(Screen.WORLD)
			if not campaign.has_flag(SFCampaign.FLAG_COAST_ENTERED):
				_show_coast_intro()
		SFCampaign.STAGE_COAST_BOSS:
			_begin_coast_boss()
		SFCampaign.STAGE_COAST_ARCHIVE:
			_enter_archive_scene(SFCampaign.ARCHIVE_COAST)
		SFCampaign.STAGE_BASE_RETURN:
			_go(Screen.PROGRESSION)
		SFCampaign.STAGE_PHASE_TWO_COMPLETE:
			_go(Screen.CHECKPOINT)
		_:
			_go(Screen.WORLD)


# ---------------------------------------------------------------- settings

func _settings_key(key: int) -> void:
	match key:
		KEY_UP, KEY_W:
			settings_menu.move_enabled(-1)
			audio.sfx_select()
			queue_redraw()
		KEY_DOWN, KEY_S:
			settings_menu.move_enabled(1)
			audio.sfx_select()
			queue_redraw()
		KEY_LEFT, KEY_A:
			_settings_adjust(-1)
		KEY_RIGHT, KEY_D:
			_settings_adjust(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if settings_menu.current_id() == "back":
				audio.sfx_back()
				_go(previous_screen if previous_screen != Screen.SETTINGS else Screen.TITLE)
			else:
				_settings_adjust(1)
		KEY_ESCAPE:
			audio.sfx_back()
			_go(previous_screen if previous_screen != Screen.SETTINGS else Screen.TITLE)


func _settings_adjust(direction: int) -> void:
	match settings_menu.current_id():
		"ambience":
			setting_ambience = not setting_ambience
			audio.set_muted(not setting_ambience)
			audio.sfx_select()
		"text_speed":
			if direction > 0:
				setting_text_speed = 90.0 if setting_text_speed >= 90.0 else (90.0 if setting_text_speed > 45.0 else 52.0)
			else:
				setting_text_speed = 30.0 if setting_text_speed <= 45.0 else 52.0
			audio.sfx_select()
	_rebuild_settings_menu()
	queue_redraw()


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
	_rebuild_pause_menu()
	pause_menu.index = 0
	pause_open = true
	if world != null:
		world.set_input_enabled(false)
	refresh_overlay()


func _close_pause() -> void:
	pause_open = false
	if world != null:
		world.set_input_enabled(dialogue == null)
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
	if campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED):
		_open_dialogue(["The archive inside is already restored.", "The route south is open."], "CONTROL CENTER")
		return
	if not campaign.has_flag(SFCampaign.FLAG_CITY_CHECKPOINT):
		audio.sfx_denied()
		_open_dialogue([
			"The door is welded shut. Something inside is already moving.",
			"Nick: \"Not without a saved route. If this goes wrong I want to come back here, not to the ridge.\"",
			"Use the checkpoint marker in the street first.",
		], "CONTROL CENTER DOOR")
		return
	_begin_city_boss()


func _approach_coast_gate() -> void:
	if campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED):
		_open_dialogue(["The facility is quiet. The archive inside is already restored."], "CLEANUP FACILITY")
		return
	if not campaign.has_flag(SFCampaign.FLAG_COAST_CHECKPOINT):
		audio.sfx_denied()
		_open_dialogue([
			"The intake is still pumping. The unit inside treats everything as contamination.",
			"Nick: \"Checkpoint first. I am not walking into that without a way back.\"",
			"Use the harbor checkpoint on the quay.",
		], "CLEANUP FACILITY INTAKE")
		return
	_begin_coast_boss()


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
	if world != null:
		world.set_prop_sprite("bill_body", "bill_on")
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
	signal_marker = 0.0
	signal_target = randf_range(0.25, 0.75)
	crash_shake = 0.0
	audio.set_ambience("none")
	audio.sfx_confirm()
	queue_redraw()


func _launch_key(key: int) -> void:
	match key:
		KEY_ESCAPE:
			# Skipping a cutscene never skips state: the finish routine applies
			# every required flag, stage change and save.
			_finish_launch_state()
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if launch_phase == LaunchPhase.SIGNAL:
				_signal_lock()
			elif launch_phase == LaunchPhase.CRASH or launch_phase == LaunchPhase.RIFT:
				_finish_launch_state()


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
	var lines: Array = campaign.content.dialogue_lines("crash")
	_open_dialogue(lines, "IMPACT", Callable(self, "_on_crash_intro_done"))


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
			if (launch_timer - delta < 0.8 and launch_timer >= 0.8) or (launch_timer - delta < 1.8 and launch_timer >= 1.8):
				if audio.has_method("sfx_countdown"):
					audio.sfx_countdown()
			if launch_timer > 2.6:
				launch_phase = LaunchPhase.ASCENT
				launch_timer = 0.0
				audio.sfx_launch()
		LaunchPhase.ASCENT:
			if launch_timer > 3.4:
				launch_phase = LaunchPhase.SIGNAL
				launch_timer = 0.0
				if audio.has_method("sfx_signal_sweep"):
					audio.sfx_signal_sweep()
		LaunchPhase.SIGNAL:
			signal_timer += delta
			signal_marker = 0.5 + 0.42 * sin(signal_timer * 2.1)
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
			if launch_timer > 2.6:
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
	audio.sfx_memory()
	campaign.view_memory(id)
	Events.memory_viewed.emit(id)
	_save_quietly()
	_go(Screen.MEMORY)


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
		KEY_ESCAPE:
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
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE:
			audio.sfx_confirm()
			# Two different summaries share this screen. After Phase 2 the
			# summary is the stopping point, so it returns to the title with the
			# save intact. After Phase 1 it leads into the Forgotten City, which
			# is where Bill's coordinates point.
			if campaign.has_flag(SFCampaign.FLAG_PHASE_TWO_COMPLETE):
				campaign.advance_to(SFCampaign.STAGE_COMPLETE)
				campaign.set_checkpoint(SFCampaign.STAGE_COMPLETE, SFCampaign.CHAPTER_CRASH)
				_save_quietly()
				_go(Screen.TITLE)
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
		_save_quietly()
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
		_save_quietly()
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

func _begin_city_boss() -> void:
	_start_encounter("scrap_king", "city_boss_intro")


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
	var boss_id := "scrap_king" if campaign.stage == SFCampaign.STAGE_CITY_BOSS else "toxic_tide"
	var boss_data: Dictionary = campaign.encounters().boss(boss_id)
	if boss_data.is_empty():
		push_error("Duel screen requested with no boss data")
		return
	var all_data = campaign.encounters()
	duel = SFDuel.new()
	duel.name = "Duel"
	duel.setup(skin, ui, boss_data, all_data)
	duel.duel_finished.connect(_on_duel_finished)
	duel.duel_aborted.connect(_on_duel_aborted)
	add_child(duel)
	duel.begin_attempt()
	queue_redraw()


## A duel ended. The screen reports only the outcome; every campaign change
## happens here, exactly once, and is saved before the next screen opens.
func _on_duel_finished(outcome: String) -> void:
	var is_city: bool = campaign.stage == SFCampaign.STAGE_CITY_BOSS
	if outcome != "victory":
		return
	if is_city:
		if _award_boss_victory("scrap_king"):
			_show_city_victory()
	else:
		if _award_boss_victory("toxic_tide"):
			_show_coast_victory()


## Applies a boss victory exactly once. Returns false when this boss was already
## defeated, so a replayed or double-emitted result can never duplicate rewards.
func _award_boss_victory(boss_id: String) -> bool:
	var boss_data: Dictionary = campaign.encounters().boss(boss_id)
	if boss_data.is_empty():
		return false
	var flag := String(boss_data.get("reward_flag", ""))
	if flag != "" and campaign.has_flag(flag):
		return false
	if flag != "":
		campaign.set_flag(flag)
	var component := String(boss_data.get("reward_component", ""))
	if component != "":
		campaign.award_component(component)
	_save_quietly()
	return true


func _show_city_victory() -> void:
	audio.set_ambience("ruin")
	var lines: Array = campaign.content.dialogue_lines("city_victory")
	_open_dialogue(lines, "SCRAP KING DOWN", Callable(self, "_on_city_victory_done"))


func _on_city_victory_done() -> void:
	campaign.set_checkpoint(SFCampaign.STAGE_CITY_ARCHIVE, SFCampaign.CHAPTER_CITY)
	_save_quietly()
	_enter_archive_scene(SFCampaign.ARCHIVE_CITY)


func _show_coast_victory() -> void:
	audio.set_ambience("coast")
	var lines: Array = campaign.content.dialogue_lines("coast_victory")
	_open_dialogue(lines, "TOXIC TIDE DOWN", Callable(self, "_on_coast_victory_done"))


func _on_coast_victory_done() -> void:
	campaign.set_checkpoint(SFCampaign.STAGE_COAST_ARCHIVE, SFCampaign.CHAPTER_COAST)
	_save_quietly()
	_enter_archive_scene(SFCampaign.ARCHIVE_COAST)


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
	if screen == Screen.LAUNCH:
		_process_launch(delta)
	if screen == Screen.MEMORY:
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
	return pause_open and screen == Screen.WORLD and dialogue == null


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

	var note_y: float = column.end.y - 14.0
	if not save_available:
		skin.text_c(self, column.position.x + column.size.x * 0.5, note_y, "NO SAVE YET", SFPalette.ASH_LIGHT)
	else:
		skin.text_c(self, column.position.x + column.size.x * 0.5, note_y, "SAVE AVAILABLE", SFPalette.CYAN_DIM)

	# Footer on a solid strip, never over the planet.
	draw_rect(Rect2(0, VH - 26, VW, 26), Color(0.03, 0.06, 0.08, 0.92), true)
	draw_rect(Rect2(0, VH - 26, VW, 1), SFPalette.STEEL_DARK, true)
	skin.text_c(self, VW * 0.5, VH - 20, "UP/DOWN SELECT     ENTER CONFIRM     ESC QUIT", SFPalette.PAPER_DIM)
	skin.text_c(self, VW * 0.5, VH - 10, "A FICTIONAL STORY. TIME TRAVEL IS NOT REAL.", SFPalette.ASH_LIGHT)
	skin.vignette(self)


# ---------------------------------------------------------------- settings draw

func _draw_settings() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	ui.header(self, "SETTINGS", "Local preferences. Nothing here affects the campaign.")
	var panel := Rect2(100, 60, 440, 200)
	ui.modal(self, panel)
	skin.text(self, panel.position + Vector2(14, 14), "SETTINGS", SFPalette.CYAN)
	ui.menu_list(self, settings_menu, panel.position + Vector2(24, 40), panel.size.x - 48, 22.0)
	skin.wrap(self, panel.position + Vector2(24, 130), panel.size.x - 48,
		"Ambient sound toggles the synthesised wind and machinery. Text speed changes how quickly dialogue appears.",
		SFPalette.PAPER_DIM, 1, 4)
	ui.footer(self, ["UP/DOWN:SELECT", "LEFT/RIGHT:CHANGE", "ESC:BACK"])


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
	_draw_day_sky()
	var pad_c := Vector2(VW * 0.5, 300)
	skin.contact_shadow(self, pad_c, 90.0, 0.35)
	draw_rect(Rect2(pad_c.x - 46, pad_c.y - 8, 92, 12), SFPalette.CONCRETE_DARK, true)
	# The assembled ship, nose up.
	_draw_ship_silhouette(pad_c + Vector2(0, -4))
	var n: int = 3 - int(launch_timer / 0.85)
	if n < 0:
		n = 0
	skin.text_c(self, VW * 0.5, 92, "LAUNCH CLEARANCE GRANTED", SFPalette.PAPER)
	skin.text_c(self, VW * 0.5, 130, "T-%d" % (n + 1) if n > 0 else "IGNITION", SFPalette.GOLD, 3)
	skin.text_c(self, VW * 0.5, 190, "VELA / SIGNAL INVESTIGATION", SFPalette.PAPER_DIM)
	skin.text_c(self, VW * 0.5, VH - 18, "ESC SKIP SEQUENCE", SFPalette.ASH_LIGHT)


func _draw_ascent() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	# Sky darkens as altitude increases.
	var t: float = clampf(launch_timer / 3.4, 0.0, 1.0)
	var sky_top := SFPalette.SKY_DEEP.lerp(SFPalette.INK, t)
	var sky_low := SFPalette.SKY.lerp(SFPalette.SKY_DEEP.darkened(0.35), t)
	draw_rect(Rect2(0, 0, VW, 240), sky_top, true)
	draw_rect(Rect2(0, 240, VW, 120), sky_low, true)
	# Thin the horizon line between the two bands.
	draw_rect(Rect2(0, 239, VW, 2), sky_low.lerp(sky_top, 0.5), true)
	# Stars fade in.
	for i in 60:
		var a := t * 0.9
		var x := float((i * 83) % VW)
		var y := float((i * 53) % 230)
		draw_rect(Rect2(x, y, 1, 1), Color(1, 1, 1, a), true)
	# Ground falls away, and the coastline recedes with it.
	var ground_y: float = 250.0 + t * 210.0
	if ground_y < VH:
		draw_rect(Rect2(0, ground_y, VW, VH - ground_y), SFPalette.GRASS_DARK, true)
		draw_rect(Rect2(0, ground_y, VW, 2), SFPalette.GRASS, true)
		# A shrinking curve of coastline reads as altitude.
		var cw: float = 900.0 * (1.0 - t * 0.55)
		var ch: float = 50.0 * (1.0 - t * 0.4)
		for i in 30:
			var ang: float = PI + (float(i) / 29.0) * PI
			var cp := Vector2(VW * 0.5 + cos(ang) * cw * 0.5, ground_y + sin(ang) * ch)
			draw_rect(Rect2(round(cp.x), round(cp.y), 2, 2), SFPalette.LEAF, true)
	var ship_y: float = 260.0 - t * 110.0
	_draw_ship_silhouette(Vector2(VW * 0.5, ship_y))
	# Exhaust, anchored to the engine bells at the base of the hull.
	var bell_y: float = ship_y - 4.0
	for i in 9:
		var ey: float = bell_y + float(i) * 6.0
		var w: float = 7.0 - float(i) * 0.55
		var a: float = 0.85 - float(i) * 0.085
		draw_rect(Rect2(round(VW * 0.5 - w * 0.5), round(ey), round(w), 5), Color(1.0, 0.72, 0.32, a), true)
		draw_rect(Rect2(round(VW * 0.5 - w * 0.22), round(ey), maxf(1.0, round(w * 0.44)), 4), Color(1.0, 0.92, 0.7, a), true)
	# A faint shockwave ring just above the pad line at ignition.
	if t < 0.35:
		var ring_r: float = 20.0 + t * 200.0
		var ring_a: float = (0.35 - t) / 0.35 * 0.5
		for i in 40:
			var ang2: float = float(i) / 40.0 * TAU
			draw_rect(Rect2(round(VW * 0.5 + cos(ang2) * ring_r), round(bell_y + 14.0 + sin(ang2) * ring_r * 0.28), 2, 1), Color(1.0, 0.9, 0.75, ring_a), true)
	var lines: Array = campaign.content.dialogue_lines("launch")
	var idx: int = mini(int(t * lines.size()), maxi(0, lines.size() - 1))
	if not lines.is_empty():
		skin.text_c(self, VW * 0.5, VH - 34, String(lines[idx]), SFPalette.PAPER)
	skin.text_c(self, VW * 0.5, VH - 16, "ESC SKIP SEQUENCE", SFPalette.ASH_LIGHT)


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
	skin.text_c(self, dial.position.x + dial.size.x * 0.5, dial.end.y - 20, "PRESS E WHEN THE MARKER CROSSES THE LOCK ZONE", SFPalette.PAPER_DIM)
	skin.text_c(self, VW * 0.5, 214, "THE SIGNAL IS NOT WHERE THE BRIEF SAID IT WOULD BE.", SFPalette.PAPER)
	if signal_attempts > 0 and signal_locks == 0:
		skin.text_c(self, VW * 0.5, 228, "Keep trying. The sequence resolves either way.", SFPalette.ASH_LIGHT)
	# Waveform, decorative but truthful about the lock count.
	for i in 120:
		var x := 60.0 + float(i) * 4.4
		var amp: float = 4.0 + float(signal_locks) * 3.0
		var y := 270.0 + sin(float(i) * 0.35 + time * 5.0) * amp
		draw_rect(Rect2(x, y, 2, 1), SFPalette.CYAN_DIM, true)
	skin.text_c(self, VW * 0.5, VH - 16, "ESC SKIP SEQUENCE", SFPalette.ASH_LIGHT)


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
	_draw_ship_silhouette(Vector2(cx + sin(time * 2.2) * 12.0 + 56.0, cy + 96.0))

	var lines: Array = campaign.content.dialogue_lines("rift")
	var idx: int = mini(int(launch_timer / 1.1), maxi(0, lines.size() - 1))
	if not lines.is_empty():
		draw_rect(Rect2(0, VH - 54, VW, 20), Color(0.02, 0.02, 0.05, 0.75), true)
		skin.text_c(self, VW * 0.5, VH - 48, String(lines[idx]), SFPalette.PAPER)
	skin.text_c(self, VW * 0.5, VH - 16, "ESC SKIP SEQUENCE", SFPalette.ASH_LIGHT)


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

	var lines: Array = campaign.content.dialogue_lines("crash")
	var idx: int = mini(int(launch_timer / 0.9), maxi(0, lines.size() - 1))
	if not lines.is_empty():
		draw_rect(Rect2(0, VH - 54, VW, 20), Color(0.02, 0.03, 0.03, 0.8), true)
		skin.text_c(self, VW * 0.5, VH - 48, String(lines[idx]), SFPalette.PAPER)
	skin.text_c(self, VW * 0.5, VH - 16, "ESC SKIP SEQUENCE", SFPalette.ASH_LIGHT)


## Ship drawing with a roll applied, used for the crash approach.
func _draw_ship_tilted(ground: Vector2, tilt: float) -> void:
	draw_set_transform(ground, tilt, Vector2.ONE)
	_draw_ship_silhouette(Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_day_sky() -> void:
	var g := 0
	while g < 10:
		var t := float(g) / 10.0
		draw_rect(Rect2(0, 0, VW, 200), SFPalette.SKY_DEEP.lerp(SFPalette.SKY, t), true)
		g += 1
	draw_rect(Rect2(0, 200, VW, 160), SFPalette.GRASS, true)
	draw_rect(Rect2(0, 200, VW, 3), SFPalette.GRASS_DARK, true)


## A compact side/three-quarter silhouette of the assembled ship, using the
## same visual language as the construction screen.
func _draw_ship_silhouette(ground: Vector2) -> void:
	draw_rect(Rect2(ground.x - 13, ground.y - 76, 26, 62), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 13, ground.y - 76, 5, 62), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x + 8, ground.y - 76, 5, 62), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x - 7, ground.y - 88, 14, 14), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x - 4, ground.y - 96, 8, 10), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 2, ground.y - 100, 4, 6), SFPalette.STEEL_MID, true)
	# Engine bells.
	draw_rect(Rect2(ground.x - 12, ground.y - 16, 8, 10), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x + 4, ground.y - 16, 8, 10), SFPalette.STEEL_DARK, true)
	# Cabin light.
	draw_rect(Rect2(ground.x - 3, ground.y - 70, 6, 5), SFPalette.CYAN_DIM, true)


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
	skin.text_c(self, cx, VH - 16, "ENTER CONTINUE     ESC SKIP", SFPalette.ASH_LIGHT)
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
			"Dawn Tower is unlocked on the chart. It is not built yet.",
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
		skin.text_c(self, VW * 0.5, panel.end.y - 18, "CHECKPOINT SAVED - PHASE 2 STOPS HERE", SFPalette.GREEN_OK)
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
	skin.text_c(self, VW * 0.5, VH - 23, "ENTER RETURN TO MAIN MENU", SFPalette.PAPER)
	if phase_two:
		skin.text_c(self, VW * 0.5, VH - 12, "DAWN TOWER IS UNLOCKED - PHASE 3 IS NOT PART OF THIS BUILD", SFPalette.ASH_LIGHT)
	else:
		skin.text_c(self, VW * 0.5, VH - 12, "FORGOTTEN CITY - PHASE 2", SFPalette.ASH_LIGHT)


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
	# Pause menu is an overlay on the world, so its keys are handled ahead of
	# the world. This mirrors the World branch of _unhandled_input.
	if screen != Screen.WORLD or dialogue != null or world == null:
		return
	if world.player.input_enabled:
		return
	if event is InputEventMouseMotion:
		var pos: Vector2 = get_local_mouse_position()
		var idx := _menu_item_at(pause_menu, Vector2(216, 126), 208.0, 20.0, pos)
		if idx >= 0 and idx != pause_menu.index:
			pause_menu.index = idx
			audio.sfx_select()
			get_viewport().set_input_as_handled()
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var pos2: Vector2 = get_local_mouse_position()
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				get_viewport().set_input_as_handled()
				audio.sfx_back()
				_close_pause()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var idx2 := _menu_item_at(pause_menu, Vector2(216, 126), 208.0, 20.0, pos2)
				get_viewport().set_input_as_handled()
				if idx2 >= 0:
					pause_menu.index = idx2
					_pause_activate()
				elif not Rect2(200, 96, 240, 146).has_point(pos2):
					audio.sfx_back()
					_close_pause()
				queue_redraw()
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		audio.sfx_back()
		_close_pause()
		return
	match key:
		KEY_UP, KEY_W:
			pause_menu.move_enabled(-1)
			audio.sfx_select()
			get_viewport().set_input_as_handled()
		KEY_DOWN, KEY_S:
			pause_menu.move_enabled(1)
			audio.sfx_select()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()
			_pause_activate()
	queue_redraw()


func _pause_activate() -> void:
	match pause_menu.current_id():
		"resume":
			audio.sfx_blip()
			_close_pause()
		"save":
			_manual_save()
		"settings":
			audio.sfx_blip()
			_rebuild_settings_menu()
			settings_menu.index = 0
			previous_screen = Screen.WORLD
			_go(Screen.SETTINGS)
		"title":
			audio.sfx_back()
			_save_quietly()
			_go(Screen.TITLE)
