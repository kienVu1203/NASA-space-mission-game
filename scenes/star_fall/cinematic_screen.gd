extends Node2D
## Phase 4: the escape cinematic. Six scenes and the closing message, drawn
## entirely in-engine from generated sprites and primitives. No external video,
## no missing files, nothing that can fail to load.
##
## VELA is drawn only through `core/star_fall/sf_vela.gd`, the same renderer the
## workshop and the final-assembly gate use, so it is one ship in every shot.
## From the pad to the homecoming it stands upright: nose up, nozzles and
## landing legs at the bottom. Its presentation state decides the engines:
##   departure station  parked      engines off
##   launch             ignition -> ascending (flame from the bottom nozzles)
##   debris / portal    ascending -> portal_entry
##   home               descending -> landed (engines off)
##
## Two of the six scenes are playable:
##   * `debris_passage` — VELA climbs through a debris layer; bodies fall toward
##     it from above. A / D, Left / Right or the mouse steer across the corridor.
##     Grit and near misses meet the shield (ripple, spark, sound, small shake);
##     a large body on the hull shows a strike beat and restarts the segment.
##   * `portal` — the player lines VELA up under the opening; the portal then
##     captures the ship and draws it in. The scene ends only after the hull has
##     visibly crossed the portal plane.
## `SFFlight` owns those rules (pure); this screen feeds it input and draws it.
##
## The screen owns no campaign state. It reports exactly one outcome through
## `cinematic_finished(skipped)`; the controller applies every flag, checkpoint
## and stage change, so watching and skipping are guaranteed to leave the same
## persistent state.
##
## Scenes reflect what the player actually did. The departure station lights
## the junction cable only if it was repaired, the ship carries the modules the
## frozen design fitted, and the archive transfer at home sends as many packets
## as memories were really found.
##
## Controls
##   SPACE              pause / resume (pause freezes subtitles and the clock)
##   ESC                skip the rest of the sequence (safe, idempotent)
##   ANY OTHER KEY      fast-forward to the next minor beat
##   LEFT CLICK         the same, outside the HUD
##   A / D, Left/Right  steer during the playable segments
##   MOUSE              steer toward the pointer during the playable segments
##
## Safety: `skip()` and the natural end both call `_finish()` once. Focus loss
## pauses rather than letting the sequence run unseen. Leaving the screen is the
## controller's job (`_go()` frees this node), so no timer here outlives it.
## Every per-scene effect (contacts, shake, flight state, notices) is reset in
## `_next_scene()`, so nothing leaks into the next beat.

signal cinematic_finished(skipped: bool)

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFFinale := preload("res://core/star_fall/sf_finale.gd")
const SFFlight := preload("res://core/star_fall/sf_flight.gd")
const SFVela := preload("res://core/star_fall/sf_vela.gd")

const VW := 640
const VH := 360

## Keys that are never "any key": Esc skips, Space pauses.
const RESERVED_KEYS := [KEY_ESCAPE, KEY_SPACE]

# ---- departure station (scene A) timing, seconds of scene time
const TRANSFER_START := 2.6
const TRANSFER_END := 6.4
const WALK_START := 9.8
const BOARD_AT := 12.4
const ABOARD_AT := 13.4
const HATCH_SEALED := 14.2
const ARM_CLEAR := 15.8
const READY_AT := 16.6
## Where the departure pad stands. The launch starts from the same place.
const STATION_PAD := Vector2(320, 236)

# ---- launch (scene B)
const IGNITION_AT := 1.0
const LIFTOFF_AT := 3.2
const LAUNCH_ACCEL := 34.0
const CAMERA_RISE := 40.0
const SHIELD_ON_AT := 6.8
const STRATA_PARALLAX := 0.35
const STRATA_SPACING := 120.0
## Choreographed shield contacts during the ascent: [stratum, offset seconds
## from the moment that stratum reaches the ship, screen angle on the shield,
## heavy]. Each one is drawn as a body striking the bubble at that point, and
## its sound and shake fire on that frame.
const LAUNCH_CONTACTS := [
	[0, -0.10, -2.0, false], [0, 0.12, -1.2, false],
	[1, -0.05, -0.8, true], [1, 0.20, -2.5, false],
	[2, -0.12, -2.3, false], [2, 0.05, -1.0, false], [2, 0.22, -1.9, true],
	[3, 0.00, -0.6, false], [3, 0.15, -2.6, true],
	[4, -0.08, -1.4, false], [4, 0.10, -2.1, false],
	[5, 0.00, -1.7, true],
]
const CONTACT_LIFE := 0.45
const LIGHT_SFX_COOLDOWN := 0.12
const HEAVY_SFX_COOLDOWN := 0.22

# ---- home (scene F)
const HOME_PAD := Vector2(300, 236)
const TOUCHDOWN_AT := 5.4
const HATCH_OPEN_AT := 7.0
const RAMP_AT := 7.6
const EXIT_AT := 9.0
const RAMP_FOOT_AT := 10.4
const CELEBRATE_AT := 11.6
const CELEBRATE_SPOT := Vector2(426, 250)

var skin
var ui
var campaign
var finale_data: Dictionary = {}
var reconstruction_data: Dictionary = {}
var scenes: Array = []
var final_message: Dictionary = {}
var report: Dictionary = {}

var scene_index: int = 0
var scene_time: float = 0.0
var elapsed: float = 0.0
var paused: bool = false
var finished: bool = false
var skipped: bool = false
var show_final_message: bool = false
var reduced_motion: bool = false
var _finish_emitted: bool = false

# Playable segments.
var flight = null
var _flight_index: int = -1
var _hit_freeze: float = 0.0
var _hold_timer: float = 0.0
var _impact_point: Vector2 = Vector2.ZERO
var _shake_energy: float = 0.0
var _steer_stick: float = 0.0
var _mouse_target: float = 320.0
var _mouse_engaged: bool = false
var _assist_notice: String = ""
var _assist_notice_time: float = 0.0
var _notice: String = ""
var _notice_time: float = 0.0
# Shield contacts on screen: {"rel": offset from the ship centre, "heavy", "t0"}.
var _contacts: Array = []
var _last_light_sfx: float = -10.0
var _last_heavy_sfx: float = -10.0
# Cues fire once per scene entry, keyed by "scene:name".
var _fired_cues: Dictionary = {}
## The ascent's junk field, laid out once with a fixed seed.
var _strata_field: Array = []
var _modules: Array = []


func setup(skin_ref, ui_ref, campaign_ref, finale: Dictionary, reconstruction: Dictionary) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	finale_data = finale
	reconstruction_data = reconstruction


func _ready() -> void:
	var cinematic: Dictionary = finale_data.get("cinematic", {}) as Dictionary
	scenes = cinematic.get("scenes", []) as Array
	final_message = cinematic.get("final_message", {}) as Dictionary
	report = SFFinale.build_report(campaign, reconstruction_data, finale_data)
	# The frozen design's modules: every view of the ship shows these.
	_modules.clear()
	for id in SFVela.MODULE_IDS:
		if campaign == null or campaign.has_component(String(id)):
			_modules.append(String(id))
	_build_strata_field()
	scene_index = 0
	scene_time = 0.0
	elapsed = 0.0
	queue_redraw()


func _notification(what: int) -> void:
	# Losing focus pauses the sequence: it must never play unseen, and it must
	# never leave the player locked in a scene that moved on without them.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if not finished:
			paused = true
			queue_redraw()


# ---------------------------------------------------------------- timing

func current_scene() -> Dictionary:
	if show_final_message or scene_index < 0 or scene_index >= scenes.size():
		return {}
	return scenes[scene_index] as Dictionary


func scene_id() -> String:
	return String(current_scene().get("id", ""))


func scene_duration() -> float:
	if show_final_message:
		return float(final_message.get("duration", 8.0))
	return float(current_scene().get("duration", 10.0))


func is_paused() -> bool:
	return paused and not finished


func is_finished() -> bool:
	return finished


## The flight tuning block for the current scene, or empty.
func _flight_config() -> Dictionary:
	var flight_block: Dictionary = (finale_data.get("cinematic", {}) as Dictionary).get("flight", {}) as Dictionary
	var kind := String(current_scene().get("interactive", ""))
	if kind == "":
		return {}
	return flight_block.get(kind, {}) as Dictionary


func is_interactive() -> bool:
	return not _flight_config().is_empty()


## True while the player is flying the segment rather than reading it.
func is_playable() -> bool:
	if not is_interactive() or flight == null or paused or finished:
		return false
	return flight.is_active() and not flight.captured and _hit_freeze <= 0.0


## The VELA presentation state on screen right now. Tests use it to prove the
## engines are off on the pad and at home and on only in flight.
func ship_state() -> String:
	if show_final_message:
		return ""
	match String(current_scene().get("visual", "")):
		"crash_site":
			return SFVela.PARKED
		"launch":
			if scene_time < IGNITION_AT:
				return SFVela.PARKED
			if _launch_altitude(scene_time) < 12.0:
				return SFVela.IGNITION
			return SFVela.ASCENDING
		"debris", "sunlight":
			return SFVela.ASCENDING
		"portal":
			if flight != null and flight.captured:
				return SFVela.PORTAL_ENTRY
			return SFVela.ASCENDING
		"home":
			return SFVela.DESCENDING if scene_time < TOUCHDOWN_AT else SFVela.LANDED
	return ""


func engines_on() -> bool:
	var state := ship_state()
	return state != "" and SFVela.engines_on(state)


func shield_contacts_visible() -> int:
	return _contacts.size()


func advance_for(delta: float) -> void:
	if finished or paused:
		return
	elapsed += delta
	if _assist_notice_time > 0.0:
		_assist_notice_time = maxf(0.0, _assist_notice_time - delta)
	if _notice_time > 0.0:
		_notice_time = maxf(0.0, _notice_time - delta)
	if _shake_energy > 0.0:
		_shake_energy = maxf(0.0, _shake_energy - delta * 1.8)
	_prune_contacts()

	# A collision beat freezes the segment but not the clock: the subtitle that
	# is on screen stays readable while the ship recovers.
	if _hit_freeze > 0.0:
		_hit_freeze = maxf(0.0, _hit_freeze - delta)
		scene_time += delta
		if _hit_freeze <= 0.0 and flight != null:
			flight.restart()
			_contacts.clear()
			_notice = "STRIKE - RESTARTING THE PASSAGE"
			_notice_time = 1.6
		return

	if is_interactive():
		_tick_flight(delta)
		return

	scene_time += delta
	_fire_scene_cues()
	if scene_time >= scene_duration():
		_next_scene()


## The playable segment itself. The clock runs with it so the dialogue keeps
## pace; the segment, not the clock, decides when the scene is done.
func _tick_flight(delta: float) -> void:
	_ensure_flight()
	if flight == null:
		_next_scene()
		return
	if _hold_timer > 0.0:
		_hold_timer = maxf(0.0, _hold_timer - delta)
		scene_time += delta
		if _hold_timer <= 0.0:
			_next_scene()
		return

	scene_time += delta
	_fire_scene_cues()
	# A long-dead controller, or a player who simply holds still, is rescued by
	# the ship's own navigation chip. The timer is on the scene clock, which does
	# not reset on a collision, so it always fires however often the field is
	# restarted.
	var assist_after: float = float(_flight_config().get("assist_after_seconds", 26.0))
	if not flight.assist and assist_after > 0.0 and scene_time >= assist_after:
		flight.assist = true
		_assist_notice = "NAVIGATION CHIP TAKING THE STICK"
		_assist_notice_time = 2.4
		_sfx("sfx_signal_lock")
	var events: Array = flight.tick(delta, _steer_direction(delta))
	for entry in events:
		var e: Dictionary = entry
		match String(e.get("type", "")):
			"hit":
				_on_flight_hit(e)
			"shield":
				_on_flight_shield(e)
			"captured":
				_notice = "PORTAL CAPTURE"
				_notice_time = 2.0
				_sfx("sfx_signal_lock")
			"cleared":
				_on_segment_done(false)
			"entered":
				_on_segment_done(true)
			"assist":
				_assist_notice = "NAVIGATION CHIP TAKING THE STICK"
				_assist_notice_time = 2.4
				_sfx("sfx_signal_lock")
	# Only a flown segment ends the scene. The navigation assist guarantees that
	# a segment always finishes; this backstop exists so a cinematic can never
	# hang on a bug, and normal play never reaches it.
	if _hold_timer <= 0.0 and flight.is_active() and scene_time >= scene_duration() + 30.0:
		_on_segment_done(false)


func _on_flight_hit(event: Dictionary) -> void:
	_impact_point = _flight_to_screen(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	_hit_freeze = float(_flight_config().get("hit_freeze_seconds", 0.55))
	_shake_energy = 0.8
	_last_heavy_sfx = elapsed
	_sfx("sfx_impact")


func _on_flight_shield(event: Dictionary) -> void:
	var p := _flight_to_screen(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
	_add_contact(p - _flight_ship_center(), bool(event.get("heavy", false)))


func _on_segment_done(entered_portal: bool) -> void:
	if _hold_timer > 0.0 or flight == null:
		return
	_hold_timer = float(_flight_config().get("clear_hold_seconds", 1.5))
	if entered_portal:
		_sfx("sfx_rift")
	else:
		_sfx("sfx_signal_lock")


func _ensure_flight() -> void:
	var config: Dictionary = _flight_config()
	if config.is_empty():
		return
	if flight != null and _flight_index == scene_index:
		return
	flight = SFFlight.new()
	flight.configure(config)
	_flight_index = scene_index
	_hit_freeze = 0.0
	_hold_timer = 0.0
	_notice = ""
	_notice_time = 0.0
	_mouse_engaged = false
	_mouse_target = flight.ship_y


func _steer_direction(delta: float) -> float:
	if _mouse_engaged and flight != null and not flight.captured:
		flight.steer_toward(_mouse_target, delta)
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	var direction: float = 0.0
	if right and not left:
		direction = 1.0
	elif left and not right:
		direction = -1.0
	if direction == 0.0:
		direction = _steer_stick
	return direction


func _next_scene() -> void:
	if show_final_message:
		_finish(false)
		return
	scene_index += 1
	scene_time = 0.0
	_hit_freeze = 0.0
	_hold_timer = 0.0
	_shake_energy = 0.0
	_contacts.clear()
	_assist_notice = ""
	_assist_notice_time = 0.0
	_notice = ""
	_notice_time = 0.0
	flight = null
	_flight_index = -1
	if scene_index >= scenes.size():
		show_final_message = true
		scene_time = 0.0
	queue_redraw()


## Skips the rest of the sequence. Idempotent; repeated input is harmless.
func skip() -> void:
	if finished:
		return
	skipped = true
	_finish(true)


func _finish(was_skipped: bool) -> void:
	if _finish_emitted:
		return
	_finish_emitted = true
	finished = true
	paused = false
	skipped = was_skipped
	_contacts.clear()
	_shake_energy = 0.0
	cinematic_finished.emit(was_skipped)


# ---------------------------------------------------------------- cues

## Audio cues and choreographed contacts tied to scene beats. Each fires once
## per scene entry, so repeated frames, a pause and a resume never stack a
## second copy.
func _fire_scene_cues() -> void:
	var id := scene_id()
	if id == "leaving_crash_site":
		_cue("transfer", TRANSFER_START, "sfx_signal_sweep")
		_cue("transfer_done", TRANSFER_END, "sfx_memory")
		_cue("hatch", ABOARD_AT + 0.2, "sfx_install")
		_cue("ready", READY_AT, "sfx_preflight_pass")
	elif id == "launch":
		_cue("countdown", 0.1, "sfx_countdown")
		_cue("ignition", IGNITION_AT, "sfx_launch")
		_cue("shield", SHIELD_ON_AT, "sfx_power_up")
		for i in LAUNCH_CONTACTS.size():
			var spec: Array = LAUNCH_CONTACTS[i]
			var at: float = launch_contact_time(i)
			var key := "contact%d" % i
			if not _fired_cues.has(id + ":" + key) and scene_time >= at:
				_fired_cues[id + ":" + key] = true
				var ang: float = float(spec[2])
				var r: Vector2 = SFVela.shield_radii(1, SFVela.ASCENDING)
				_add_contact(Vector2(cos(ang) * r.x, sin(ang) * r.y), bool(spec[3]))
	elif id == "sunlight":
		_cue("warm", 6.0, "sfx_memory")
	elif id == "portal":
		_cue("open", 0.3, "sfx_signal_sweep")
	elif id == "home":
		_cue("touchdown", TOUCHDOWN_AT, "sfx_hull_creak")
		_cue("hatch", HATCH_OPEN_AT, "sfx_install")
		_cue("celebrate", CELEBRATE_AT, "sfx_confirm")


func _cue(key: String, at: float, sfx: String) -> void:
	var tag := scene_id() + ":" + key
	if _fired_cues.has(tag):
		return
	if scene_time < at:
		return
	_fired_cues[tag] = true
	_sfx(sfx)


func _sfx(sfx_name: String) -> void:
	if skin != null and skin.audio != null and skin.audio.has_method(sfx_name):
		skin.audio.call(sfx_name)


## One shield contact: a ripple on the bubble at `rel` from the ship centre, a
## short impact sound (lighter or heavier), and a brief shake. Sounds are rate
## limited so a burst of grit never stacks into noise; the ripple always shows.
func _add_contact(rel: Vector2, heavy: bool) -> void:
	_contacts.append({"rel": rel, "heavy": heavy, "t0": elapsed})
	while _contacts.size() > 14:
		_contacts.remove_at(0)
	_shake_energy = minf(0.6, _shake_energy + (0.32 if heavy else 0.12))
	if heavy:
		if elapsed - _last_heavy_sfx >= HEAVY_SFX_COOLDOWN:
			_last_heavy_sfx = elapsed
			_sfx("sfx_impact")
	elif elapsed - _last_light_sfx >= LIGHT_SFX_COOLDOWN and elapsed - _last_heavy_sfx >= 0.08:
		_last_light_sfx = elapsed
		_sfx("sfx_shield_block")


func _prune_contacts() -> void:
	var i := 0
	while i < _contacts.size():
		if elapsed - float((_contacts[i] as Dictionary)["t0"]) > CONTACT_LIFE:
			_contacts.remove_at(i)
		else:
			i += 1


## The live contacts as `SFVela.draw_shield` wants them, around `center`.
func _contact_list(center: Vector2) -> Array:
	var out: Array = []
	for entry in _contacts:
		var c: Dictionary = entry
		out.append({
			"pos": center + (c["rel"] as Vector2),
			"heavy": bool(c["heavy"]),
			"age": (elapsed - float(c["t0"])) / CONTACT_LIFE,
		})
	return out


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			handle_click(get_local_mouse_position())
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			paused = true
			queue_redraw()
		return
	if event is InputEventMouseMotion:
		handle_mouse_motion(get_local_mouse_position())
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	handle_key(key.keycode)


func handle_key(keycode: int) -> void:
	if finished:
		return
	match keycode:
		KEY_ESCAPE:
			skip()
			return
		KEY_SPACE:
			paused = not paused
			if paused:
				_sfx("sfx_back")
			else:
				_sfx("sfx_select")
			queue_redraw()
			return
	# A playable segment owns every other key: they steer (through the input
	# actions) and never touch the segment clock, so a player cannot skip past
	# the flight or trip the navigation assist by mashing.
	if is_interactive():
		return
	fast_forward()


## A left click advances a beat, unless it lands on the pause badge. During a
## playable segment a click steers, so it never skips dialogue.
func handle_click(pos: Vector2) -> void:
	if finished:
		return
	if Rect2(520, 4, 116, 22).has_point(pos):
		paused = not paused
		queue_redraw()
		return
	if is_interactive():
		if is_playable():
			_mouse_engaged = true
			_mouse_target = pos.x
		return
	fast_forward()


func handle_mouse_motion(pos: Vector2) -> void:
	if not is_interactive() or paused:
		return
	if pos.y < 30.0:
		return
	_mouse_engaged = true
	_mouse_target = clampf(pos.x, 0.0, float(VW))


## Moves the clock to the next subtitle beat. On the closing card it ends the
## sequence, exactly as ENTER always did.
func fast_forward() -> void:
	if finished:
		return
	if show_final_message:
		_finish(false)
		return
	if paused:
		paused = false
	var scene: Dictionary = current_scene()
	var lines: Array = scene.get("lines", []) as Array
	var next_at: float = scene_duration()
	for entry in lines:
		var at: float = float((entry as Dictionary).get("at", 0.0))
		if at > scene_time + 0.05:
			next_at = at
			break
	if next_at >= scene_duration():
		scene_time = maxf(scene_time, scene_duration() - 0.02)
	else:
		scene_time = maxf(scene_time, next_at)
	_sfx("sfx_select")
	queue_redraw()


## Test and capture entry point: steer without a keyboard or a mouse.
func set_steer(direction: float) -> void:
	_steer_stick = clampf(direction, -1.0, 1.0)
	_mouse_engaged = false


func _process(delta: float) -> void:
	advance_for(delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if show_final_message:
		_draw_final_message()
		if paused:
			_draw_paused()
		skin.vignette(self)
		return
	var scene: Dictionary = current_scene()
	if scene.is_empty():
		draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
		return
	match String(scene.get("visual", "")):
		"crash_site":
			_draw_scene_departure()
		"launch":
			_draw_scene_launch()
		"debris":
			_draw_scene_debris()
		"sunlight":
			_draw_scene_sunlight()
		"portal":
			_draw_scene_portal()
		"home":
			_draw_scene_home()
		_:
			draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)

	_draw_flight_hud()
	_draw_scene_header(scene)
	_draw_subtitle(scene)
	if paused:
		_draw_paused()
	skin.vignette(self)


func _draw_scene_header(scene: Dictionary) -> void:
	var title := String(scene.get("name", ""))
	# Scene titles fade in over the first second and stay quiet on screen.
	if scene_time < 1.0:
		return
	draw_rect(Rect2(0, 0, VW, 26), Color(0.02, 0.04, 0.05, 0.72), true)
	skin.text(self, Vector2(14, 8), title, SFPalette.CYAN)
	skin.text_r(self, 506, 8, "%d / %d" % [scene_index + 1, scenes.size()], SFPalette.PAPER_DIM)
	# A small pause badge, the only HUD button in the sequence.
	var badge := Rect2(520, 4, 116, 22)
	draw_rect(badge, Color(0.05, 0.09, 0.11, 0.95), true)
	draw_rect(badge, SFPalette.STEEL_DARK, false, 1.0)
	skin.text_c(self, badge.position.x + badge.size.x * 0.5, badge.position.y + 7,
		"II  PAUSE", SFPalette.PAPER_DIM)


## The playable segments draw their own thin state strip under the header:
## progress, the control hint, the route and the strike counter. It sits above
## the field, so nothing ever covers the ship or the dialogue.
func _draw_flight_hud() -> void:
	if not is_interactive() or flight == null:
		return
	var bar_y := 30.0
	var ratio: float = flight.progress_fraction()
	if flight.kind == "portal":
		ratio = 0.5 * flight.alignment_fraction() + 0.5 * flight.entry_fraction()
	draw_rect(Rect2(40, bar_y, VW - 80, 2), Color(0.10, 0.16, 0.18, 0.85), true)
	draw_rect(Rect2(40, bar_y, (VW - 80) * ratio, 2), SFPalette.CYAN, true)
	var kind := String(current_scene().get("interactive", ""))
	var hint := "A / D   LEFT / RIGHT   MOUSE"
	if kind == "portal":
		hint = "A / D   LEFT / RIGHT   MOUSE   LINE UP UNDER THE OPENING"
	draw_rect(Rect2(40, bar_y + 5, 290, 12), Color(0.02, 0.04, 0.05, 0.72), true)
	skin.text(self, Vector2(46, bar_y + 6), hint, SFPalette.PAPER_DIM)
	# Real recorded values only: the certified route, and the strikes this run
	# has actually taken. Neither is generated for effect.
	var right := ""
	if String(report.get("route_name", "")) != "":
		right = "ROUTE " + String(report.get("route_name", "")).to_upper()
	if flight.hits > 0:
		right += "   STRIKES %d" % flight.hits
	if flight.assist:
		right += "   NAV ASSIST"
	skin.text_r(self, VW - 40, bar_y + 6, right, SFPalette.CYAN_DIM)
	if _notice_time > 0.0:
		var pulse := 0.6 + 0.4 * sin(elapsed * 14.0)
		var col: Color = SFPalette.CYAN if flight.captured else SFPalette.RED
		skin.text_c(self, VW * 0.5, 48, _notice, Color(col.r, col.g, col.b, pulse))
	elif _assist_notice_time > 0.0:
		skin.text_c(self, VW * 0.5, 48, _assist_notice, SFPalette.CYAN)


## Shows the newest line whose `at` time has passed, with a short fade. Lines are
## data-driven, so subtitle wording and timing never live in this script.
func _draw_subtitle(scene: Dictionary) -> void:
	var lines: Array = scene.get("lines", []) as Array
	var active: Dictionary = {}
	for entry in lines:
		var line: Dictionary = entry
		if scene_time >= float(line.get("at", 0.0)):
			active = line
	if active.is_empty():
		return
	var text := String(active.get("text", ""))
	if text == "":
		return
	var since: float = scene_time - float(active.get("at", 0.0))
	var alpha: float = clampf(since / 0.35, 0.0, 1.0)
	var box := Rect2(40, VH - 64, VW - 80, 38)
	draw_rect(box, Color(0.02, 0.04, 0.05, 0.80 * alpha), true)
	draw_rect(box, Color(SFPalette.CYAN_DIM.r, SFPalette.CYAN_DIM.g, SFPalette.CYAN_DIM.b, 0.7 * alpha), false, 1.0)
	var c := Color(SFPalette.PAPER.r, SFPalette.PAPER.g, SFPalette.PAPER.b, alpha)
	skin.wrap(self, box.position + Vector2(12, 7), box.size.x - 24, text, c, 1, 2)
	var hint := String((finale_data.get("cinematic", {}) as Dictionary).get("skip_hint", "ESC SKIP"))
	skin.text_r(self, VW - 14, VH - 16, hint, SFPalette.ASH_LIGHT)


func _draw_paused() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.04, 0.05, 0.55), true)
	draw_rect(Rect2(200, 146, 240, 64), Color(0.04, 0.08, 0.09, 0.96), true)
	draw_rect(Rect2(200, 146, 240, 64), SFPalette.CYAN, false, 1.0)
	skin.text_c(self, VW * 0.5, 158, "PAUSED", SFPalette.CYAN, 2)
	skin.text_c(self, VW * 0.5, 184, "SPACE RESUME     ESC SKIP", SFPalette.PAPER_DIM)
	skin.text_c(self, VW * 0.5, 196, "ANY OTHER KEY NEXT BEAT", SFPalette.ASH_LIGHT)


# ---------------------------------------------------------------- shared art

## Screen shake. Driven only by real impacts and the ignition rumble, decays to
## zero, never under reduced motion, and never moves the HUD: only scene art
## calls it. It is recomputed from energy every frame, so it cannot drift.
func _shake_vector() -> Vector2:
	if reduced_motion or _shake_energy <= 0.0:
		return Vector2.ZERO
	var amount: float = _shake_energy * 3.0
	return Vector2(round(sin(elapsed * 47.0) * amount), round(cos(elapsed * 41.0) * amount * 0.7))


func _vela(origin: Vector2, state: String, extra: Dictionary = {}) -> void:
	var opts := {"modules": _modules, "time": elapsed}
	for key in extra:
		opts[key] = extra[key]
	SFVela.draw(self, origin, 1, state, opts)


## A filled ellipse from one-pixel rows, so every edge stays crisp.
func _draw_ellipse(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var cy: int = int(round(center.y))
	var half_h: int = maxi(1, int(round(radius_y)))
	for dy in range(-half_h, half_h):
		var f: float = (float(dy) + 0.5) / float(half_h)
		if absf(f) >= 1.0:
			continue
		var half_w: float = radius_x * sqrt(1.0 - f * f)
		draw_rect(Rect2(round(center.x - half_w), float(cy + dy), round(half_w * 2.0), 1.0), color, true)


func _draw_nick(ground: Vector2, dir: String, walking: bool, arm_up: float = 0.0, hop: float = 0.0) -> void:
	var g := Vector2(round(ground.x), round(ground.y))
	skin.contact_shadow(self, g, 12.0, 0.30 * (1.0 - clampf(hop / 8.0, 0.0, 0.6)))
	var tex: Texture2D = skin.sprites.get("nick_" + dir, null)
	var bob: float = 1.0 if walking and fmod(elapsed * 8.0, 2.0) < 1.0 else 0.0
	var top := g - Vector2(0, round(hop) + bob)
	if tex != null:
		skin.sprite_grounded(self, tex, top)
	else:
		draw_rect(Rect2(top.x - 6, top.y - 20, 12, 20), SFPalette.WARM, true)
	if arm_up > 0.0:
		# A raised arm over the right shoulder: suit sleeve and a glove.
		var lift: float = round(arm_up * 4.0)
		draw_rect(Rect2(top.x + 6, top.y - 15 - lift, 2, 6 + lift), SFPalette.WARM, true)
		draw_rect(Rect2(top.x + 6, top.y - 17 - lift, 2, 2), SFPalette.STEEL_MID, true)


## Pixel smoke: a soft row-ellipse puff.
func _puff(center: Vector2, r: float, color: Color) -> void:
	_draw_ellipse(center, r, r * 0.72, color)


# ---------------------------------------------------------------- scene A

## The departure station at the crash site. VELA stands parked on the pad,
## engines cold. Bill, at the service terminal, streams his memory core into
## the ship; his old shell powers down; Nick walks up the boarding ramp and the
## hatch seals; the umbilical swings clear and the departure checks go green.
func _draw_scene_departure() -> void:
	var t: float = scene_time
	var arm: float = 1.0 - clampf((t - (ARM_CLEAR - 1.0)) / 1.0, 0.0, 1.0)
	_draw_station(0.0, arm)
	var origin := SFVela.ground_origin(STATION_PAD)

	# Terminal, cable and Bill, left of the pad (behind the ship's foot line).
	var term_ground := STATION_PAD + Vector2(-84, 4)
	var term: Texture2D = skin.sprites.get("terminal", null)
	skin.contact_shadow(self, term_ground, 20.0, 0.30)
	if term != null:
		skin.sprite_grounded(self, term, term_ground)
	var port := SFVela.module_screen(origin, 1, SFVela.PARKED, "power_core") - Vector2(8, 0)
	var g0 := STATION_PAD
	var cable := PackedVector2Array([g0 + Vector2(-74, -10), g0 + Vector2(-58, 3), g0 + Vector2(-24, 3), g0 + Vector2(-18, -4), port])
	var cable_col: Color = SFPalette.STEEL_DARK
	if campaign != null and campaign.has_flag("power_repaired"):
		cable_col = SFPalette.CYAN_DARK
	for i in cable.size() - 1:
		draw_line(cable[i], cable[i + 1], Color(0.05, 0.07, 0.07), 3.0)
		draw_line(cable[i], cable[i + 1], cable_col, 1.0)
	var transfer: float = clampf((t - TRANSFER_START) / (TRANSFER_END - TRANSFER_START), 0.0, 1.0)
	if transfer > 0.0 and transfer < 1.0:
		for k in 6:
			var phase: float = fmod(elapsed * 0.9 + float(k) / 6.0, 1.0)
			var p := _along_polyline(cable, phase)
			draw_rect(Rect2(round(p.x) - 1, round(p.y) - 1, 3, 3), SFPalette.CYAN, true)
	# The transfer readout over the terminal.
	if t >= TRANSFER_START - 0.4:
		var panel := Rect2(186, STATION_PAD.y - 84.0, 102, 30)
		draw_rect(panel, Color(0.03, 0.06, 0.07, 0.92), true)
		draw_rect(panel, SFPalette.CYAN_DIM if transfer < 1.0 else SFPalette.GREEN_OK, false, 1.0)
		skin.text(self, panel.position + Vector2(5, 4), "MEMORY CORE", SFPalette.PAPER_DIM)
		skin.bar(self, panel.position + Vector2(5, 16), Vector2(panel.size.x - 10, 6), transfer,
			SFPalette.GREEN_OK if transfer >= 1.0 else SFPalette.CYAN)
		if transfer >= 1.0:
			skin.text_r(self, panel.end.x - 5, panel.position.y + 4, "DONE", SFPalette.GREEN_OK)
		else:
			skin.text_r(self, panel.end.x - 5, panel.position.y + 4, "%d%%" % int(transfer * 100.0), SFPalette.CYAN)
	# Bill: awake until the core has left the shell, then dark. One Bill only.
	var bill_ground := STATION_PAD + Vector2(-106, 6)
	var bill_tex: Texture2D = skin.sprites.get("bill_on" if t < TRANSFER_END + 0.4 else "bill_off", null)
	skin.contact_shadow(self, bill_ground, 14.0, 0.30)
	if bill_tex != null:
		skin.sprite_grounded(self, bill_tex, bill_ground)

	# Nick: waits by Bill, then walks to the ramp and climbs aboard.
	var nick_start := STATION_PAD + Vector2(-50, 8)
	var foot := SFVela.ramp_foot(origin, 1)
	var sill := SFVela.hatch_screen(origin, 1, SFVela.PARKED) + Vector2(2, 0)
	var hatch: float = 1.0 - clampf((t - ABOARD_AT) / (HATCH_SEALED - ABOARD_AT), 0.0, 1.0)
	var ramp: float = 1.0 - clampf((t - HATCH_SEALED) / 1.0, 0.0, 1.0)

	# The ship stands behind Nick whenever he is on the ground in front of it.
	_vela(origin, SFVela.PARKED, {"hatch": hatch, "ramp": ramp})
	if t < WALK_START:
		_draw_nick(nick_start, "right", false)
	elif t < BOARD_AT:
		var k: float = (t - WALK_START) / (BOARD_AT - WALK_START)
		_draw_nick(nick_start.lerp(foot + Vector2(2, 2), k), "right", true)
	elif t < ABOARD_AT:
		var k2: float = (t - BOARD_AT) / (ABOARD_AT - BOARD_AT)
		_draw_nick(foot.lerp(sill, k2), "up", true)

	# Departure checks, top right, below the header.
	if t >= ABOARD_AT:
		var checks := [
			["MEMORY CORE", TRANSFER_END], ["CREW ABOARD", ABOARD_AT],
			["HATCH SEALED", HATCH_SEALED], ["UMBILICAL CLEAR", ARM_CLEAR], ["PAD CLEAR", READY_AT - 0.3],
		]
		var box := Rect2(470, 36, 158, 76)
		draw_rect(box, Color(0.03, 0.06, 0.07, 0.88), true)
		draw_rect(box, SFPalette.STEEL_DARK, false, 1.0)
		skin.text(self, box.position + Vector2(6, 4), "DEPARTURE CHECKS", SFPalette.CYAN)
		for i in checks.size():
			var row: Array = checks[i]
			var ok: bool = t >= float(row[1])
			var y: float = box.position.y + 16.0 + float(i) * 11.0
			draw_rect(Rect2(box.position.x + 6, y + 1, 5, 5), SFPalette.GREEN_OK if ok else SFPalette.STEEL_DARK, true)
			skin.text(self, Vector2(box.position.x + 15, y), String(row[0]), SFPalette.PAPER if ok else SFPalette.PAPER_DIM)
		if t >= READY_AT:
			skin.text_c(self, VW * 0.5, 50, "READY FOR IGNITION", SFPalette.GREEN_OK)

	# Foreground rubble, in front of everything on the pad line.
	_draw_station_foreground(0.0)


func _along_polyline(points: PackedVector2Array, f: float) -> Vector2:
	var total: float = 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var target: float = total * clampf(f, 0.0, 1.0)
	for i in points.size() - 1:
		var seg: float = points[i].distance_to(points[i + 1])
		if target <= seg:
			return points[i].lerp(points[i + 1], target / maxf(0.01, seg))
		target -= seg
	return points[points.size() - 1]


## The crash-site launch station: ruined skyline, a hangar shell and fuel tanks
## behind, the pad, the service gantry with its umbilical arm, and floodlights.
## `offset` slides the whole station down as the ship climbs away from it.
func _draw_station(offset: float, arm: float) -> void:
	var horizon: float = STATION_PAD.y - 48.0 + offset
	# Sky: ash bands down to the horizon.
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	for band in 14:
		var f := float(band) / 13.0
		draw_rect(Rect2(0, round(horizon - 196.0 + float(band) * 14.0), VW, 15), SFPalette.INK.lerp(SFPalette.RUIN_DARK, f * f), true)
	if horizon - 120.0 > VH:
		return
	# Ruined skyline on the horizon.
	for i in 10:
		var bx: float = float(i) * 70.0 - 16.0
		var bh: float = 34.0 + float((i * 37) % 52)
		var bw: float = 40.0 + float((i * 17) % 22)
		draw_rect(Rect2(bx, horizon - bh, bw, bh), SFPalette.SOOT, true)
		draw_rect(Rect2(bx + bw * 0.6, horizon - bh - 4.0, 4, 4), SFPalette.SOOT, true)
		draw_rect(Rect2(bx + 6, horizon - bh + 8.0, 3, 2), Color(0.85, 0.55, 0.30, 0.35), true)
	# Hangar shell, half its ribs gone.
	for r in 7:
		var rx: float = 470.0 + float(r) * 22.0
		var rh: float = 58.0 - absf(float(r) - 3.0) * 9.0
		if r == 5:
			rh *= 0.5
		draw_rect(Rect2(rx, horizon - rh, 3, rh), SFPalette.STEEL_DARK.darkened(0.45), true)
	draw_rect(Rect2(470, horizon - 58.0, 136, 3), SFPalette.STEEL_DARK.darkened(0.45), true)
	# Ground plane: banded ash, lighter toward the camera.
	for band in 12:
		var f2 := float(band) / 11.0
		draw_rect(Rect2(0, round(horizon + float(band) * 10.0), VW, 11), SFPalette.ASH_PLAIN.darkened(0.45 - f2 * 0.25), true)
	draw_rect(Rect2(0, horizon + 120.0, VW, maxf(0.0, VH - horizon - 120.0)), SFPalette.ASH_PLAIN.darkened(0.2), true)
	# Fuel tanks, mid-ground left.
	for k in 2:
		var tx: float = 112.0 + float(k) * 30.0
		var ty: float = horizon + 22.0
		skin.contact_shadow(self, Vector2(tx + 10, ty), 26.0, 0.3)
		draw_rect(Rect2(tx, ty - 46.0, 20, 46), SFPalette.STEEL_MID.darkened(0.3), true)
		draw_rect(Rect2(tx, ty - 46.0, 4, 46), SFPalette.STEEL.darkened(0.3), true)
		draw_rect(Rect2(tx + 2, ty - 50.0, 16, 4), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(tx, ty - 26.0, 20, 2), SFPalette.RUST.darkened(0.2), true)
	# Floodlight masts and their cones toward the pad.
	for side in [-1, 1]:
		var mx: float = STATION_PAD.x + float(side) * 150.0
		var my: float = horizon + 34.0
		draw_rect(Rect2(mx - 1, my - 70.0, 2, 70), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(mx - 5, my - 74.0, 10, 4), SFPalette.WARM_DARK, true)
		var near_x: float = STATION_PAD.x - float(side) * 30.0
		var far_x: float = STATION_PAD.x + float(side) * 60.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(mx - 4, my - 70.0), Vector2(mx + 4, my - 70.0),
			Vector2(maxf(near_x, far_x), horizon + 56.0), Vector2(minf(near_x, far_x), horizon + 56.0),
		]), Color(1.0, 0.92, 0.70, 0.05))
	# Gantry tower right of the ship.
	var gx: float = 372.0
	var base: float = STATION_PAD.y + offset - 2.0
	var top: float = base - 126.0
	draw_rect(Rect2(gx, top, 2, base - top), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(gx + 14, top, 2, base - top), SFPalette.STEEL_DARK, true)
	var y: float = top
	while y < base - 12.0:
		draw_line(Vector2(gx + 1, y), Vector2(gx + 15, y + 12.0), SFPalette.STEEL_DARK.darkened(0.2), 1.0)
		draw_line(Vector2(gx + 15, y), Vector2(gx + 1, y + 12.0), SFPalette.STEEL_DARK.darkened(0.2), 1.0)
		draw_rect(Rect2(gx, y, 16, 1), SFPalette.STEEL_MID.darkened(0.2), true)
		y += 12.0
	draw_rect(Rect2(gx - 2, top - 3.0, 20, 3), SFPalette.STEEL_MID, true)
	var blink: float = 0.4 + 0.6 * float(fmod(elapsed, 1.2) < 0.6)
	draw_rect(Rect2(gx + 7, top - 6.0, 2, 3), Color(0.95, 0.30, 0.25, blink), true)
	# Service stairs up the far side of the tower.
	for s in 10:
		draw_rect(Rect2(gx + 17 + float(s % 2) * 6.0, base - 8.0 - float(s) * 12.0, 8, 2), SFPalette.STEEL_MID.darkened(0.25), true)
	# Umbilical arm to the upper hull, swinging clear before ignition.
	var origin := SFVela.ground_origin(Vector2(STATION_PAD.x, STATION_PAD.y + offset))
	var arm_y: float = origin.y - 78.0
	var reach: float = (gx - (origin.x + float(SFVela.HALF_WIDTH))) * arm
	if reach > 1.0:
		draw_rect(Rect2(gx - reach, arm_y, reach, 3), SFPalette.STEEL_MID, true)
		draw_rect(Rect2(gx - reach, arm_y + 3.0, reach, 1), SFPalette.STEEL_DARK, true)
	# The pad: a thick slab in perspective with hazard stripes on its face.
	var pc := Vector2(STATION_PAD.x, STATION_PAD.y + offset)
	_draw_ellipse(pc + Vector2(0, 6), 82.0, 15.0, SFPalette.STEEL_DARK.darkened(0.35))
	for i in 16:
		var hx: float = pc.x - 72.0 + float(i) * 9.0
		var ff: float = (hx - pc.x) / 82.0
		var hy: float = pc.y + 6.0 + 15.0 * sqrt(maxf(0.0, 1.0 - ff * ff)) - 4.0
		draw_rect(Rect2(hx, hy, 4, 2), SFPalette.GOLD.darkened(0.35) if i % 2 == 0 else SFPalette.INK, true)
	_draw_ellipse(pc, 82.0, 15.0, SFPalette.ASH_LIGHT.darkened(0.15))
	_draw_ellipse(pc, 76.0, 13.0, SFPalette.ASH_LIGHT.darkened(0.05))
	_draw_ellipse(pc, 48.0, 8.0, SFPalette.ASH_LIGHT.darkened(0.12))
	_draw_ellipse(pc, 44.0, 7.0, SFPalette.ASH_LIGHT.darkened(0.05))
	for li in 8:
		var a: float = float(li) / 8.0 * TAU
		var lp := pc + Vector2(cos(a) * 78.0, sin(a) * 14.0)
		draw_rect(Rect2(round(lp.x) - 1, round(lp.y) - 1, 2, 2), SFPalette.GOLD.darkened(0.2), true)


func _draw_station_foreground(offset: float) -> void:
	var rubble: Texture2D = skin.sprites.get("rubble", null)
	if rubble == null:
		return
	for spot in [Vector2(70, 284), Vector2(560, 280), Vector2(608, 290)]:
		var p: Vector2 = spot + Vector2(0, offset)
		if p.y - 30.0 > VH:
			continue
		skin.contact_shadow(self, p, 20.0, 0.25)
		skin.sprite_grounded(self, rubble, p)


# ---------------------------------------------------------------- scene B

## Ignition and vertical liftoff from the same pad, then the climb into the
## junk strata. The ship never tilts: the camera holds it near the middle of
## the frame while the station drops away and the debris layers stream past.
func _launch_altitude(t: float) -> float:
	if t <= LIFTOFF_AT:
		return 0.0
	return 0.5 * LAUNCH_ACCEL * pow(t - LIFTOFF_AT, 2.0)


func _launch_thrust(t: float) -> float:
	if t < IGNITION_AT:
		return 0.0
	if t < LIFTOFF_AT:
		var k: float = (t - IGNITION_AT) / (LIFTOFF_AT - IGNITION_AT)
		return lerpf(0.15, 1.3, k * k)
	return 1.15


## How far the strata have scrolled at altitude `h`.
func _strata_scroll(h: float) -> float:
	return STRATA_PARALLAX * maxf(0.0, h - CAMERA_RISE)


## The screen centre of the ship once the camera follows it.
func _launch_center_y() -> float:
	return SFVela.ground_origin(STATION_PAD).y - CAMERA_RISE - float(SFVela.LENGTH) * 0.5


## When stratum `k` reaches the ship: the contacts are timed from this, so a
## ripple always coincides with a band of junk crossing the hull.
func band_cross_time(k: int) -> float:
	var scroll_needed: float = _launch_center_y() + 40.0 + float(k) * STRATA_SPACING
	var h: float = CAMERA_RISE + scroll_needed / STRATA_PARALLAX
	return LIFTOFF_AT + sqrt(2.0 * h / LAUNCH_ACCEL)


func launch_contact_time(index: int) -> float:
	var spec: Array = LAUNCH_CONTACTS[index]
	return band_cross_time(int(spec[0])) + float(spec[1])


func _band_y(k: int, h: float) -> float:
	return -40.0 + _strata_scroll(h) - float(k) * STRATA_SPACING


func _draw_scene_launch() -> void:
	var t: float = scene_time
	var h: float = _launch_altitude(t)
	var rise: float = minf(h, CAMERA_RISE)
	var world: float = maxf(0.0, h - CAMERA_RISE)
	var shake := _shake_vector()
	# The ignition rumble: a small shudder on the pad, gone once airborne.
	var rumble: float = clampf((t - IGNITION_AT) / 1.2, 0.0, 1.0) * (1.0 - clampf((t - LIFTOFF_AT) / 1.5, 0.0, 1.0))
	if not reduced_motion and rumble > 0.0:
		shake += Vector2(round(sin(elapsed * 53.0) * rumble), 0.0)

	_draw_station(world, 0.0)
	# Sky darkening with altitude, laid over the station's sky.
	var dark: float = clampf(h / 900.0, 0.0, 1.0)
	if dark > 0.0:
		draw_rect(Rect2(0, 0, VW, VH), Color(SFPalette.INK.r, SFPalette.INK.g, SFPalette.INK.b, dark * 0.85), true)
		for i in 70:
			var sx := float((i * 83) % VW)
			var sy := float((i * 47) % 300)
			draw_rect(Rect2(sx, sy, 1, 1), Color(0.88, 0.93, 1.0, clampf(dark * 0.8 - 0.2, 0.0, 0.55)), true)

	var pad := Vector2(STATION_PAD.x, STATION_PAD.y + world)
	var origin := SFVela.ground_origin(STATION_PAD) - Vector2(0, rise) + shake
	var state := ship_state()
	# On the pad the flame meets the slab: its length is capped until the ship
	# clears it, and the pad glow and smoke carry the buildup instead.
	var thrust: float = minf(_launch_thrust(t), 0.3 + h / 30.0)

	# Smoke column and pad dust: they stay on the pad as the ship leaves it.
	_draw_launch_smoke(pad, t)
	# Strata behind the ship.
	if world > 0.0:
		_draw_strata(h, origin.x, 1.0)
	_vela(origin, state, {"thrust": thrust})
	_draw_pad_dust(pad, t)
	if pad.y - 40.0 < VH:
		_draw_station_foreground(world)

	var shield_on: float = clampf((t - SHIELD_ON_AT) / 0.6, 0.0, 1.0)
	var center := SFVela.center(origin, 1, state)
	_draw_contact_bodies(center)
	if shield_on > 0.0:
		SFVela.draw_shield(self, origin, 1, state, shield_on, elapsed, _contact_list(center))


## The ascent's debris laid out once. Each stratum gets more and larger bodies
## the higher it sits; every body keeps a stable height, size and tone, so a
## captured frame is reproducible and the field never reads as a grid.
func _build_strata_field() -> void:
	_strata_field.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90211
	for layer in 6:
		var count: int = 42 + layer * 14
		for i in count:
			var size: float = 2.5 + rng.randf() * (3.5 + float(layer) * 1.3)
			_strata_field.append({
				"layer": layer,
				"x": rng.randf_range(-30.0, 670.0),
				"dy": rng.randf_range(-28.0, 28.0),
				"drift": rng.randf_range(3.0, 11.0) * (1.0 if i % 2 == 0 else -1.0),
				"size": size,
				"tone": rng.randf_range(0.40, 0.70),
				# a third of each band sits nearer the camera, larger and faster
				"near": rng.randf() < 0.3,
			})


## The junk strata streaming down past the climbing ship. A corridor around the
## hull stays clear: the bodies that cross it are the choreographed contacts.
func _draw_strata(h: float, ship_x: float, fade: float) -> void:
	for layer in 6:
		var by: float = _band_y(layer, h)
		if by < -60.0 or by > VH + 60.0:
			continue
		draw_rect(Rect2(0, by - 24.0, VW, 48.0), Color(0.30, 0.26, 0.34, (0.05 + float(layer) * 0.012) * fade))
	for entry in _strata_field:
		var b: Dictionary = entry
		var layer2: int = int(b["layer"])
		var near: bool = bool(b["near"])
		var y: float = _band_y(layer2, h) * (1.12 if near else 1.0) + float(b["dy"])
		if y < -20.0 or y > VH + 20.0:
			continue
		var x: float = fposmod(float(b["x"]) - elapsed * float(b["drift"]), float(VW + 60)) - 30.0
		var size: float = float(b["size"]) * (1.5 if near else 1.0)
		if absf(x - ship_x) < 30.0 + size:
			continue
		_draw_chunk(Vector2(x, y), size, float(b["tone"]) * (0.8 if near else 1.0), fade)


func _draw_chunk(p: Vector2, size: float, tone: float, alpha: float) -> void:
	var w: float = maxf(2.0, round(size))
	var hh: float = maxf(2.0, round(size * 0.78))
	draw_rect(Rect2(round(p.x), round(p.y), w, hh), Color(tone, tone * 0.90, tone * 0.80, 0.95 * alpha))
	draw_rect(Rect2(round(p.x), round(p.y), w, 1.0), Color(minf(1.0, tone * 1.35), minf(1.0, tone * 1.28), tone * 1.15, 0.95 * alpha))
	draw_rect(Rect2(round(p.x), round(p.y) + hh - 1.0, w, 1.0), Color(tone * 0.5, tone * 0.46, tone * 0.42, 0.9 * alpha))
	if size > 5.0:
		draw_rect(Rect2(round(p.x + size * 0.6), round(p.y - 1.0), 2, 2), Color(0.10, 0.11, 0.14, 0.85 * alpha))


## The bodies that strike the shield during the ascent: each flies in from
## outside the corridor, meets the bubble on its contact frame, and glances off.
func _draw_contact_bodies(center: Vector2) -> void:
	if scene_id() != "launch":
		return
	var r: Vector2 = SFVela.shield_radii(1, SFVela.ASCENDING)
	for i in LAUNCH_CONTACTS.size():
		var spec: Array = LAUNCH_CONTACTS[i]
		var dt: float = scene_time - launch_contact_time(i)
		if dt < -0.35 or dt > 0.6:
			continue
		var ang: float = float(spec[2])
		var hit := center + Vector2(cos(ang) * r.x, sin(ang) * r.y)
		var outward := Vector2(cos(ang), sin(ang))
		var size: float = 6.0 if bool(spec[3]) else 3.0
		var p: Vector2
		if dt < 0.0:
			# Incoming from above and outside, falling into the contact point.
			p = hit + (outward * 60.0 + Vector2(0, -50)) * (-dt / 0.35)
		else:
			# Deflected: back out and down, the way the ship's climb carries it.
			p = hit + (outward * 46.0 + Vector2(0, 70)) * (dt / 0.6)
		_draw_chunk(p - Vector2(size, size) * 0.5, size, 0.62, 1.0 - clampf(dt / 0.6, 0.0, 1.0))


## The launch plume, standing on the pad: pixel puffs that rise, spread and fade.
func _draw_launch_smoke(pad: Vector2, t: float) -> void:
	var strength: float = clampf((t - IGNITION_AT) / 1.4, 0.0, 1.0) * (1.0 - clampf((t - 6.5) / 3.0, 0.0, 1.0))
	if strength <= 0.0 or pad.y - 240.0 > VH:
		return
	for i in 40:
		var f := float(i) / 39.0
		var age := fmod((t - IGNITION_AT) * 0.55 + f * 0.9, 1.0)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var px: float = pad.x + side * (10.0 + age * (40.0 + f * 70.0)) + sin(float(i) * 1.7 + elapsed * 0.6) * 6.0
		var py: float = pad.y - 4.0 - age * age * 60.0 - f * 8.0
		var tone: float = 0.40 + f * 0.16
		_puff(Vector2(px, py), (5.0 + age * 18.0) * (0.6 + strength * 0.5),
			Color(tone, tone * 0.96, tone * 0.90, (1.0 - age) * 0.40 * strength))
	# Glow where the flame meets the pad, only while the ship is still on it.
	if t < LIFTOFF_AT + 1.2 and t >= IGNITION_AT:
		_puff(pad + Vector2(0, -6), 18.0 * strength, Color(1.0, 0.68, 0.30, 0.22 * strength))


## Dust and loose scrap thrown off the pad at ignition, washing over the legs.
func _draw_pad_dust(pad: Vector2, t: float) -> void:
	var k: float = clampf((t - IGNITION_AT) / 3.6, 0.0, 1.0)
	if k <= 0.0 or k >= 1.0 or pad.y - 40.0 > VH:
		return
	var fade: float = 1.0 - k
	for i in 30:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var reach: float = floorf(float(i) * 0.5) / 14.0
		var dist: float = (14.0 + reach * 150.0) * (0.3 + k * 0.9)
		var p := Vector2(pad.x + side * dist, pad.y + 2.0 - reach * 8.0 - k * 10.0)
		_puff(p, (3.0 + k * 9.0) * (1.0 - reach * 0.45), Color(0.58, 0.56, 0.50, fade * 0.30))
	for i in 10:
		var fa := float(i) / 9.0
		var a2: float = PI + fa * PI
		var r2: float = 26.0 + k * (80.0 + fa * 50.0)
		var p2 := Vector2(pad.x + cos(a2) * r2, pad.y + sin(a2) * r2 * 0.25 - k * (1.0 - k) * 120.0)
		draw_rect(Rect2(round(p2.x), round(p2.y), 3, 2), SFPalette.STEEL_DARK, true)


# ---------------------------------------------------------------- scenes C, E

## Flight space to the screen: `x` (along-track) runs up, `y` across.
func _flight_to_screen(along: float, across: float) -> Vector2:
	return Vector2(across, float(VH) - along)


func _flight_ship_center() -> Vector2:
	if flight == null:
		return Vector2(VW * 0.5, VH * 0.5)
	return _flight_to_screen(flight.ship_x, flight.ship_y)


func _flight_origin() -> Vector2:
	return _flight_ship_center() + Vector2(0, float(SFVela.LENGTH) * 0.5)


## Debris passage: VELA climbs through the accumulated layer while bodies fall
## toward it. Background dust and a far debris layer drift slowly; heavier
## silhouettes slide past the corridor edges in front; the field itself fills
## the lane without ever covering the HUD or the dialogue.
func _draw_scene_debris() -> void:
	_ensure_flight()
	var shake: Vector2 = _shake_vector()
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.03, 0.06), true)
	for i in 90:
		var sx := float((i * 71) % VW)
		var sy := fposmod(float((i * 37) % VH) + elapsed * 6.0, float(VH))
		draw_rect(Rect2(round(sx), round(sy), 1, 1), Color(0.75, 0.82, 0.95, 0.30 + 0.25 * float(i % 3) / 3.0), true)
	# Far layer: small, slow, dim.
	for i in 46:
		var fx := float((i * 97) % VW)
		var fy := fposmod(float(i * 53) + elapsed * (14.0 + float(i % 3) * 4.0), float(VH + 20)) - 10.0
		var fs: float = 1.0 + float(i % 3)
		draw_rect(Rect2(round(fx), round(fy), fs, fs), Color(0.30, 0.33, 0.40, 0.45), true)
	# Mid layer: chunks outside the lane, a little faster.
	var lane_l: float = flight.lane_top if flight != null else 196.0
	var lane_r: float = flight.lane_bottom if flight != null else 444.0
	for i in 34:
		var side: bool = i % 2 == 0
		var mx: float = float((i * 41) % int(lane_l - 20.0)) + 6.0 if side else lane_r + 14.0 + float((i * 43) % int(VW - lane_r - 20.0))
		var my: float = fposmod(float(i * 67) + elapsed * (42.0 + float(i % 4) * 9.0), float(VH + 40)) - 20.0
		_draw_chunk(Vector2(mx, my), 3.0 + float(i % 4) * 1.6, 0.46, 0.85)
	if flight != null:
		_draw_obstacles(shake)
		_draw_grit(shake)
		_draw_play_ship(shake)
		if _hit_freeze > 0.0:
			_draw_impact_burst()
	# Foreground: large dark silhouettes sliding past the corridor edges.
	for i in 6:
		var left: bool = i % 2 == 0
		var gx: float = 40.0 + float(i) * 9.0 if left else VW - 70.0 - float(i) * 7.0
		var gy := fposmod(float(i * 131) + elapsed * 90.0, float(VH + 120)) - 60.0
		var gs: float = 14.0 + float(i % 3) * 5.0
		draw_rect(Rect2(round(gx), round(gy), gs, gs * 0.8), Color(0.07, 0.08, 0.10, 0.92), true)
		draw_rect(Rect2(round(gx), round(gy), gs, 1), Color(0.24, 0.24, 0.26, 0.9), true)


func _draw_obstacles(shake: Vector2) -> void:
	if flight == null:
		return
	for entry in flight.active_obstacles():
		var body: Dictionary = entry
		var p := _flight_to_screen(float(body["x"]), float(body["y"])) + shake
		var cx: float = p.x
		var cy: float = p.y
		# Along-track extent is screen height, across-track is screen width.
		var hw: float = float(body["hh"])
		var hh: float = float(body["hw"])
		var tone: int = int(body["tone"])
		var phase: float = float(body["phase"])
		var rim: Color = [Color("3a352c"), Color("3b332c"), Color("33302b")][tone]
		var face: Color = [Color("857966"), Color("7d7160"), Color("6e6759")][tone]
		var light: Color = [Color("a99a82"), Color("a09278"), Color("8f8674")][tone]
		var outer := PackedVector2Array()
		for k in 10:
			var ang := float(k) / 10.0 * TAU + phase
			var wobble: float = 0.82 + 0.18 * sin(float(k) * 2.7 + phase * 3.0)
			outer.append(Vector2(cx + cos(ang) * hw * wobble, cy + sin(ang) * hh * wobble))
		draw_colored_polygon(outer, rim)
		var inner := PackedVector2Array()
		for k in 10:
			var ang2 := float(k) / 10.0 * TAU + phase
			var wobble2: float = 0.72 + 0.16 * sin(float(k) * 2.7 + phase * 3.0)
			inner.append(Vector2(cx + cos(ang2) * hw * wobble2 - hw * 0.10,
				cy + sin(ang2) * hh * wobble2 - hh * 0.16))
		draw_colored_polygon(inner, face)
		draw_rect(Rect2(round(cx - hw * 0.5), round(cy - hh * 0.62), maxf(2.0, round(hw * 0.6)), 2), light, true)
		draw_rect(Rect2(round(cx - hw * 0.62), round(cy - hh * 0.58), 2, 2), Color(0.92, 0.86, 0.72, 0.85), true)


func _draw_grit(shake: Vector2) -> void:
	for entry in flight.grit:
		var g: Dictionary = entry
		var p := _flight_to_screen(float(g["x"]), float(g["y"])) + shake
		var s: float = maxf(1.0, round(float(g["r"])))
		var tone: float = [0.62, 0.55, 0.70][int(g["tone"])]
		draw_rect(Rect2(round(p.x), round(p.y), s, s), Color(tone, tone * 0.92, tone * 0.82), true)
		draw_rect(Rect2(round(p.x), round(p.y) - 3, 1, 3), Color(tone, tone, tone, 0.25), true)


## VELA in the lane: upright, engines burning, the shield around it.
func _draw_play_ship(shake: Vector2) -> void:
	if flight == null:
		return
	var origin := _flight_origin() + shake
	var state := ship_state()
	_vela(origin, state, {"thrust": 1.0})
	if flight.assist and not flight.captured:
		var c := SFVela.center(origin, 1, state)
		draw_rect(Rect2(c.x - 1, origin.y + 30, 2, 22), Color(0.30, 0.85, 0.90, 0.35), true)
	if flight.kind == "debris":
		SFVela.draw_shield(self, origin, 1, state, 1.0, elapsed, _contact_list(SFVela.center(origin, 1, state)))


func _draw_impact_burst() -> void:
	var life: float = 1.0 - clampf(_hit_freeze / maxf(0.01, float(_flight_config().get("hit_freeze_seconds", 0.55))), 0.0, 1.0)
	for i in 16:
		var ang := float(i) / 16.0 * TAU
		var r: float = 6.0 + life * 34.0
		var p := _impact_point + Vector2(cos(ang), sin(ang)) * r
		draw_rect(Rect2(round(p.x), round(p.y), 2, 2), Color(1.0, 0.72, 0.35, 1.0 - life), true)
	_puff(_impact_point, 8.0 + life * 10.0, Color(1.0, 0.85, 0.55, 0.35 * (1.0 - life)))
	skin.text_c(self, VW * 0.5, 62, "HULL STRIKE", Color(SFPalette.RED.r, SFPalette.RED.g, SFPalette.RED.b,
		0.6 + 0.4 * sin(elapsed * 18.0)))


## The portal. It opens above the ship; the player lines VELA up beneath it;
## the capture pulls the ship onto its axis and draws it up through the rim.
## The hull is hidden as it crosses the portal plane (a mask, not a stretch),
## and the transition flash comes only after the whole ship is through.
func _draw_scene_portal() -> void:
	_ensure_flight()
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.02, 0.06), true)
	for i in 80:
		draw_rect(Rect2(float((i * 71) % VW), float((i * 37) % VH), 1, 1), Color(0.72, 0.80, 0.98, 0.30), true)
	if flight == null:
		return
	var shake := _shake_vector()
	var pc := _flight_to_screen(flight.portal_x, flight.portal_y)
	var open: float = clampf(scene_time / 1.4, 0.0, 1.0)
	var rx: float = 46.0 * open
	var ry: float = 12.0 * open
	var pull: float = 1.0 if flight.captured else 0.35
	if flight.entered:
		pull = 0.0

	# Directional particles drifting into the opening, faster once captured.
	for i in 60:
		var lane: float = float((i * 53) % 260) - 130.0
		var f: float = fmod(float(i) * 0.137 + elapsed * (0.10 + pull * 0.35), 1.0)
		var start := Vector2(pc.x + lane * 1.6, pc.y + 230.0 - float(i % 5) * 12.0)
		var p := start.lerp(pc, f * f)
		draw_rect(Rect2(round(p.x), round(p.y), 1, 2), Color(0.66, 0.70, 1.0, 0.25 + 0.5 * f * pull), true)

	# The opening: the far half of the rim and the dark mouth behind the ship.
	if open > 0.0:
		_draw_ellipse(pc, rx + 6.0, ry + 3.0, Color(0.26, 0.16, 0.44, 0.45 * open))
		_draw_ellipse(pc, rx, ry, Color(0.10, 0.06, 0.22, 0.95))
		_draw_ellipse(pc, rx * 0.6, ry * 0.6, Color(0.20, 0.42, 0.62, 0.35 * open))
		for i in 18:
			var a: float = float(i) / 18.0 * TAU + elapsed * 1.4
			var sp := pc + Vector2(cos(a) * rx * 0.75, sin(a) * ry * 0.75)
			draw_rect(Rect2(round(sp.x), round(sp.y), 2, 1), Color(0.80, 0.86, 1.0, 0.55), true)
		_draw_portal_rim(pc, rx, ry, true)

	# The ship, masked at the portal plane.
	var origin := _flight_origin() + (Vector2.ZERO if flight.captured else shake)
	var clip_u: float = (origin.y - pc.y)
	if not flight.entered:
		var state := ship_state()
		_vela(origin, state, {"thrust": 1.0 + 0.4 * flight.entry_fraction(), "clip_u": clip_u})
	# The near half of the rim crosses in front of the hull.
	if open > 0.0:
		_draw_portal_rim(pc, rx, ry, false)

	# Alignment readout and the guide under the opening.
	if not flight.captured:
		var align: float = flight.alignment_fraction()
		skin.text(self, Vector2(44, 54), "ALIGNMENT", SFPalette.PAPER_DIM)
		draw_rect(Rect2(104, 55, 150, 6), Color(0.06, 0.10, 0.14, 0.92), true)
		draw_rect(Rect2(104, 55, 150.0 * align, 6), SFPalette.SHIELD_BLUE, true)
		draw_rect(Rect2(104, 55, 150, 6), SFPalette.STEEL_DARK, false, 1.0)
		var guide_col: Color = SFPalette.CYAN if flight.is_aligned() else Color(0.6, 0.6, 0.8, 0.5)
		var gy: float = pc.y + ry + 8.0
		while gy < origin.y - float(SFVela.LENGTH) - 6.0:
			draw_rect(Rect2(round(pc.x), round(gy), 1, 3), guide_col, true)
			gy += 7.0
		skin.text(self, Vector2(pc.x + rx + 10.0, pc.y - 3.0),
			"SIGNAL LOCKED" if flight.is_aligned() else "OPENING", guide_col)

	# The crossing: a short flash and tunnel streaks after the hull is through.
	if flight.entered:
		var hold: float = float(_flight_config().get("clear_hold_seconds", 1.2))
		var k: float = 1.0 - clampf(_hold_timer / maxf(0.01, hold), 0.0, 1.0)
		var flash: float = (1.0 - k) * (0.4 if reduced_motion else 0.8)
		for i in 24:
			var a2: float = float(i) / 24.0 * TAU
			var r0: float = 20.0 + k * 200.0
			var p0 := pc + Vector2(cos(a2), sin(a2) * 0.5) * r0
			var p1 := pc + Vector2(cos(a2), sin(a2) * 0.5) * (r0 + 30.0)
			draw_line(p0, p1, Color(0.85, 0.92, 1.0, 0.6 * (1.0 - k)), 1.0)
		draw_rect(Rect2(0, 0, VW, VH), Color(0.90, 0.96, 1.0, flash), true)


func _draw_portal_rim(pc: Vector2, rx: float, ry: float, back: bool) -> void:
	for i in 64:
		var a: float = float(i) / 64.0 * TAU + elapsed * 0.9
		var s: float = sin(a)
		if back != (s < 0.0):
			continue
		var p := pc + Vector2(cos(a) * rx, s * ry)
		var bright: float = 0.6 + 0.4 * sin(float(i) * 0.7 + elapsed * 5.0)
		draw_rect(Rect2(round(p.x) - 1, round(p.y), 3, 2), Color(0.70 + 0.3 * bright, 0.80, 1.0, 0.9), true)


# ---------------------------------------------------------------- scene D

## Sunlight. VELA has broken out, and the shot looks back at what the planet
## became: a world smothered in its own waste, ringed with scrap, hazed violet.
func _draw_scene_sunlight() -> void:
	var t: float = clampf(scene_time / 17.0, 0.0, 1.0)
	draw_rect(Rect2(0, 0, VW, VH), Color(0.04, 0.05, 0.09), true)
	var warm: float = clampf(t * 1.4, 0.0, 1.0)
	for i in 40:
		var f := 1.0 - float(i) / 39.0
		var c: Color = Color(0.04, 0.05, 0.09).lerp(Color(0.96, 0.73, 0.44), pow(f, 2.1) * 0.38 * warm)
		draw_rect(Rect2(0, VH - 6.0 - float(i) * 6.0, VW, 7), c, true)
	for i in 6:
		_draw_ellipse(Vector2(560, 46), 16.0 + float(i) * 12.0, 16.0 + float(i) * 12.0, Color(1.0, 0.88, 0.62, 0.04 * warm))

	_draw_trash_planet(Vector2(196, 286), 168.0, t, warm)

	# VELA, upright, cruising on a low burn.
	var drift: float = round(sin(elapsed * 0.5) * 3.0)
	_vela(Vector2(512, 214 + drift), SFVela.ASCENDING, {"thrust": 0.35})

	if t > 0.35:
		var bloom := clampf((t - 0.35) / 0.6, 0.0, 1.0) * 0.12
		draw_rect(Rect2(0, 0, VW, VH), Color(1.0, 0.92, 0.76, bloom), true)


## Future Earth from orbit: a violet-brown disc under a haze, wrapped in rings
## of scrap. The surface is deliberately hard to see. That is the point.
func _draw_trash_planet(center: Vector2, radius: float, t: float, warm: float) -> void:
	for ring in range(26, 0, -1):
		var rr: float = radius * float(ring) / 26.0
		var k: float = float(ring) / 26.0
		_draw_ellipse(center, rr, rr, Color(0.20, 0.17, 0.24).lerp(Color(0.34, 0.28, 0.31), k))
	for i in 22:
		var band_y: float = center.y - radius * 0.8 + float(i) * (radius * 1.6 / 22.0)
		var width: float = radius * 1.7
		var drift: float = sin(elapsed * 0.22 + float(i) * 0.6) * radius * 0.14
		var a: float = 0.10 + 0.07 * sin(float(i) * 1.3 + elapsed * 0.4)
		draw_rect(Rect2(round(center.x - width * 0.5 + drift), round(band_y), round(width), 4.0), Color(0.52, 0.44, 0.46, a), true)
	for i in 14:
		var ang := float(i) * 1.7 + t * 0.2
		var rr2: float = radius * (0.25 + float((i * 13) % 60) / 100.0)
		var p := center + Vector2(cos(ang) * rr2, sin(ang) * rr2 * 0.92)
		draw_rect(Rect2(round(p.x), round(p.y), 1, 1), Color(0.92, 0.55, 0.30, 0.35 + 0.25 * sin(elapsed + float(i))), true)
	for i in 30:
		var ang2 := float(i) / 30.0 * TAU
		var p2 := center + Vector2(cos(ang2), sin(ang2)) * (radius + 4.0)
		draw_rect(Rect2(round(p2.x), round(p2.y), 2, 2), Color(0.52, 0.42, 0.60, 0.28 * warm), true)
	var rings := [[radius * 1.34, 0.30, 40, 0.05], [radius * 1.58, 0.26, 52, 0.04], [radius * 1.86, 0.20, 40, 0.03]]
	for r in rings:
		var rr3: float = float(r[0])
		var squash: float = float(r[1])
		var count: int = int(r[2])
		var spin: float = float(r[3])
		for i in count:
			var ang3 := float(i) / float(count) * TAU + elapsed * spin + t * 0.3
			var p3 := center + Vector2(cos(ang3) * rr3, sin(ang3) * rr3 * squash)
			var size: int = 1 + (i % 3)
			draw_rect(Rect2(round(p3.x), round(p3.y), size, maxi(1, size - 1)), Color(0.58, 0.54, 0.48, 0.52), true)


# ---------------------------------------------------------------- scene F

## Home. A healthy present-day spaceport in the game's own angled 2.5D pixel
## style, built from the same props as the opening Earth level: trees, bushes,
## lamps, the tracking dish. VELA descends onto the pad, the engines cut, the
## hatch opens and the ramp comes down; Nick walks out onto the landing area
## and celebrates. The camera never leaves the wide, character-scale shot.
func _draw_scene_home() -> void:
	var t: float = scene_time
	_draw_home_backdrop()
	var rest := SFVela.ground_origin(HOME_PAD)
	var descend: float = clampf(t / TOUCHDOWN_AT, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - descend, 3.0)
	var origin := Vector2(rest.x, round(lerpf(-20.0, rest.y, eased)))
	var state := ship_state()
	var hatch: float = clampf((t - HATCH_OPEN_AT) / 0.8, 0.0, 1.0)
	var ramp: float = clampf((t - RAMP_AT) / 1.2, 0.0, 1.0)

	# Everything that stands on the ground, sorted by its ground line.
	var items: Array = []
	for spot in [Vector2(36, 128), Vector2(78, 122), Vector2(150, 118), Vector2(196, 124), Vector2(232, 116),
			Vector2(420, 120), Vector2(452, 126), Vector2(612, 130), Vector2(20, 290), Vector2(616, 286)]:
		items.append({"y": spot.y, "kind": "tree", "pos": spot})
	for spot in [Vector2(120, 210), Vector2(178, 286), Vector2(468, 286), Vector2(540, 240), Vector2(250, 300)]:
		items.append({"y": spot.y, "kind": "bush", "pos": spot})
	for spot in [Vector2(206, 230), Vector2(394, 226), Vector2(214, 262), Vector2(388, 264)]:
		items.append({"y": spot.y, "kind": "lamp", "pos": spot})
	items.append({"y": 178.0, "kind": "dish", "pos": Vector2(92, 178)})
	items.append({"y": 196.0, "kind": "station", "pos": Vector2(470, 196)})
	items.append({"y": HOME_PAD.y, "kind": "ship", "pos": origin})
	var nick := _home_nick(t, origin)
	if not nick.is_empty():
		items.append({"y": (nick["pos"] as Vector2).y + 0.5, "kind": "nick", "pos": nick["pos"], "nick": nick})
	items.sort_custom(func(a, b): return float(a["y"]) < float(b["y"]))

	for entry in items:
		var it: Dictionary = entry
		var p: Vector2 = it["pos"]
		match String(it["kind"]):
			"tree":
				_home_sprite("tree", p, 26.0)
			"bush":
				_home_sprite("bush", p, 16.0)
			"lamp":
				_home_sprite("lamp", p, 8.0)
			"dish":
				_draw_home_dish(p)
			"station":
				_draw_home_station(p, t)
			"ship":
				# The shadow grows as the ship comes down to the pad.
				_ground_shadow(HOME_PAD, 10.0 + 14.0 * eased, 0.25 * eased)
				_draw_home_descent_dust(t)
				_vela(p, state, {"thrust": lerpf(0.9, 0.35, eased), "hatch": hatch, "ramp": ramp})
			"nick":
				var n: Dictionary = it["nick"]
				_draw_nick(p, String(n["dir"]), bool(n["walking"]), float(n["arm"]), float(n["hop"]))

	# The archive transfer: packets from the ship to the receiving station, as
	# many as memories the run actually recorded.
	var memories: int = mini(8, int(report.get("memory_count", 0)))
	var shown := int(clampf((t - 12.2) / 6.0, 0.0, 1.0) * float(memories))
	var from := SFVela.module_screen(origin, 1, SFVela.LANDED, "navigation_chip")
	for i in shown:
		var phase := fmod(elapsed * 0.45 + float(i) * 0.13, 1.0)
		var p2 := from.lerp(Vector2(556, 132), phase)
		p2.y -= sin(phase * PI) * 22.0
		draw_rect(Rect2(round(p2.x), round(p2.y), 2, 2), Color(0.30, 0.85, 0.80, 0.85), true)


## Nick's place and pose on the pad at scene time `t`, or empty before he
## appears. Walk down the ramp, out onto the landing area, then celebrate.
func _home_nick(t: float, origin: Vector2) -> Dictionary:
	if t < EXIT_AT:
		return {}
	var sill := SFVela.hatch_screen(origin, 1, SFVela.LANDED) + Vector2(2, 0)
	var foot := SFVela.ramp_foot(origin, 1) + Vector2(2, 1)
	if t < RAMP_FOOT_AT:
		var k: float = (t - EXIT_AT) / (RAMP_FOOT_AT - EXIT_AT)
		return {"pos": sill.lerp(foot, k), "dir": "down", "walking": true, "arm": 0.0, "hop": 0.0}
	if t < CELEBRATE_AT:
		var k2: float = (t - RAMP_FOOT_AT) / (CELEBRATE_AT - RAMP_FOOT_AT)
		return {"pos": foot.lerp(CELEBRATE_SPOT, k2), "dir": "right", "walking": true, "arm": 0.0, "hop": 0.0}
	# Two small joyful hops with an arm up, then a slow wave.
	var c: float = t - CELEBRATE_AT
	var hop: float = 0.0
	if c < 1.6:
		hop = absf(sin(c / 0.8 * PI)) * 6.0
	var arm: float = 1.0 if c < 1.6 else 0.5 + 0.5 * sin(elapsed * 6.0)
	return {"pos": CELEBRATE_SPOT, "dir": "down", "walking": false, "arm": arm, "hop": hop}


## A flat oval shadow on the ground, for wide objects where a box shadow
## would read as a dark slab.
func _ground_shadow(center: Vector2, half_width: float, alpha: float) -> void:
	_draw_ellipse(center, half_width, 3.0, Color(0, 0, 0, alpha))


func _home_sprite(key: String, ground: Vector2, shadow: float) -> void:
	var tex: Texture2D = skin.sprites.get(key, null)
	skin.contact_shadow(self, ground, shadow, 0.24)
	if tex != null:
		skin.sprite_grounded(self, tex, ground)


func _draw_home_descent_dust(t: float) -> void:
	var k: float = clampf((t - (TOUCHDOWN_AT - 1.2)) / 2.2, 0.0, 1.0)
	if k <= 0.0 or k >= 1.0:
		return
	for i in 16:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var reach: float = floorf(float(i) * 0.5) / 7.0
		var p := HOME_PAD + Vector2(side * (12.0 + reach * 70.0 * k), -2.0 - reach * 4.0)
		_puff(p, 3.0 + k * 5.0, Color(0.86, 0.82, 0.70, (1.0 - k) * 0.40))


## Sky, distant hills, the meadow plane, the service road and the pad.
func _draw_home_backdrop() -> void:
	var horizon := 98.0
	for band in 8:
		var f := float(band) / 7.0
		draw_rect(Rect2(0, float(band) * 13.0, VW, 13), SFPalette.SKY_DEEP.lerp(SFPalette.SKY, f), true)
	# A small sun and a few pixel clouds; the sky stays a backdrop.
	_draw_ellipse(Vector2(566, 44), 8.0, 8.0, Color(1.0, 0.96, 0.78))
	_draw_ellipse(Vector2(566, 44), 11.0, 11.0, Color(1.0, 0.94, 0.70, 0.25))
	for i in 4:
		var cx: float = fposmod(float(i) * 173.0 + elapsed * 3.0, float(VW + 80)) - 40.0
		var cy: float = 40.0 + float((i * 23) % 36)
		draw_rect(Rect2(round(cx), cy, 28, 4), Color(1, 1, 1, 0.85), true)
		draw_rect(Rect2(round(cx) + 6, cy - 4, 14, 4), Color(1, 1, 1, 0.85), true)
		draw_rect(Rect2(round(cx) + 2, cy + 4, 22, 2), Color(0.86, 0.92, 0.98, 0.85), true)
	# Distant hills, stepped, two tones.
	for x in range(0, VW, 4):
		var h1: float = 10.0 + 8.0 * sin(float(x) * 0.012) + 5.0 * sin(float(x) * 0.031 + 1.0)
		draw_rect(Rect2(x, horizon - round(h1), 4, round(h1) + 2.0), SFPalette.GRASS_DARK.darkened(0.25), true)
		var h2: float = 5.0 + 4.0 * sin(float(x) * 0.02 + 2.0)
		draw_rect(Rect2(x, horizon - round(h2) + 4.0, 4, round(h2)), SFPalette.GRASS_DARK.darkened(0.1), true)
	# The meadow plane, darker toward the horizon.
	for band in 14:
		var f2 := float(band) / 13.0
		draw_rect(Rect2(0, horizon + 2.0 + float(band) * 19.0, VW, 20), SFPalette.GRASS_DARK.lerp(SFPalette.GRASS, f2), true)
	# Grass tufts: stable pixel flecks.
	for i in 140:
		var gx := float((i * 89) % VW)
		var gy := horizon + 8.0 + float((i * 53) % 250)
		draw_rect(Rect2(gx, gy, 1, 2), SFPalette.GRASS_LIGHT if i % 3 else SFPalette.GRASS_DARK, true)
	# Service road from the pad to the receiving station, in perspective.
	draw_colored_polygon(PackedVector2Array([
		Vector2(368, 244), Vector2(392, 256), Vector2(560, 206), Vector2(540, 198),
	]), SFPalette.CONCRETE_MID)
	draw_colored_polygon(PackedVector2Array([
		Vector2(392, 256), Vector2(394, 259), Vector2(562, 209), Vector2(560, 206),
	]), SFPalette.CONCRETE_DARK)
	# The landing pad: a slab with a front face, ring markings and edge lights.
	_draw_ellipse(HOME_PAD + Vector2(0, 4), 86.0, 27.0, SFPalette.CONCRETE_DARK)
	_draw_ellipse(HOME_PAD, 86.0, 27.0, SFPalette.CONCRETE_MID)
	_draw_ellipse(HOME_PAD, 80.0, 24.0, SFPalette.CONCRETE)
	_draw_ellipse(HOME_PAD, 52.0, 15.0, SFPalette.GOLD.darkened(0.15))
	_draw_ellipse(HOME_PAD, 49.0, 13.0, SFPalette.CONCRETE)
	for i in 10:
		var a: float = float(i) / 10.0 * TAU
		var lp := HOME_PAD + Vector2(cos(a) * 82.0, sin(a) * 25.0)
		var on: float = 0.6 + 0.4 * sin(elapsed * 3.0 + float(i))
		draw_rect(Rect2(round(lp.x) - 1, round(lp.y) - 1, 3, 2), Color(SFPalette.GOLD.r, SFPalette.GOLD.g, SFPalette.GOLD.b, on), true)


## Mission Control's tracking dish on a small hut, pulsing as it reacquires.
func _draw_home_dish(ground: Vector2) -> void:
	_ground_shadow(ground + Vector2(3, 0), 22.0, 0.24)
	draw_rect(Rect2(ground.x - 14, ground.y - 18, 34, 18), SFPalette.WARM, true)
	draw_rect(Rect2(ground.x - 14, ground.y - 22, 34, 4), SFPalette.WARM_DARK, true)
	draw_rect(Rect2(ground.x - 6, ground.y - 12, 8, 12), SFPalette.STEEL_MID, true)
	var dish: Texture2D = skin.sprites.get("dish", null)
	if dish != null:
		skin.sprite_grounded(self, dish, ground + Vector2(8, -22))
	var cycle := fmod(elapsed * 0.55, 1.0)
	if cycle < 0.5:
		var rr: float = 10.0 + cycle * 90.0
		for i in 20:
			var a := float(i) / 20.0 * TAU
			var p := ground + Vector2(8, -44) + Vector2(cos(a) * rr, sin(a) * rr * 0.5)
			draw_rect(Rect2(round(p.x), round(p.y), 1, 1), Color(0.30, 0.80, 0.75, 0.5 * (1.0 - cycle / 0.5)), true)


## The receiving station: a small 2.5D hangar with a roof face, a door onto the
## service road and windows that light as the archive arrives.
func _draw_home_station(ground: Vector2, t: float) -> void:
	var w := 130.0
	var h := 44.0
	_ground_shadow(ground + Vector2(w * 0.5 + 4.0, 1.0), w * 0.5 + 8.0, 0.24)
	draw_colored_polygon(PackedVector2Array([
		ground + Vector2(0, -h), ground + Vector2(12, -h - 14), ground + Vector2(w + 12, -h - 14), ground + Vector2(w, -h),
	]), SFPalette.STEEL_MID)
	draw_colored_polygon(PackedVector2Array([
		ground + Vector2(w, -h), ground + Vector2(w + 12, -h - 14), ground + Vector2(w + 12, -14), ground + Vector2(w, 0),
	]), SFPalette.WARM_DARK.darkened(0.15))
	draw_rect(Rect2(ground.x, ground.y - h, w, h), SFPalette.WARM, true)
	draw_rect(Rect2(ground.x, ground.y - h, w, 2), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x + 70, ground.y - 22, 20, 22), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x + 72, ground.y - 20, 16, 20), SFPalette.STEEL_MID.darkened(0.2), true)
	var memories: int = mini(8, int(report.get("memory_count", 0)))
	var lit := int(clampf((t - 12.2) / 6.0, 0.0, 1.0) * float(memories))
	for i in 6:
		# Three windows left of the door, three right of it.
		var wx: float = ground.x + 8.0 + float(i) * 18.0 if i < 3 else ground.x + 96.0 + float(i - 3) * 11.0
		var col: Color = SFPalette.GOLD if i < lit else Color("4e6d7a")
		draw_rect(Rect2(wx, ground.y - 34, 8, 6), col, true)
		draw_rect(Rect2(wx, ground.y - 28, 8, 1), SFPalette.WARM_DARK, true)
	# A small dish on the roof, receiving.
	draw_rect(Rect2(ground.x + 84, ground.y - h - 22, 2, 10), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x + 78, ground.y - h - 24, 14, 3), SFPalette.STEEL, true)


# ---------------------------------------------------------------- final card

func _draw_final_message() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var lines: Array = final_message.get("lines", []) as Array
	var rise: float = clampf(scene_time / maxf(0.01, scene_duration()), 0.0, 1.0)
	for i in 14:
		var f := float(i) / 14.0
		var y := VH - 40.0 - f * 120.0 * rise
		draw_rect(Rect2(0, y, VW, 10), SFPalette.INK.lerp(Color(0.20, 0.26, 0.36), (1.0 - f) * 0.5 * rise), true)
	var alpha: float = clampf((scene_time - 0.6) / 1.6, 0.0, 1.0)
	var y2 := 140.0
	for line in lines:
		skin.text_c(self, VW * 0.5, y2, String(line), Color(SFPalette.PAPER.r, SFPalette.PAPER.g, SFPalette.PAPER.b, alpha), 2)
		y2 += 34.0
	if alpha >= 1.0 and scene_time > 3.0:
		var pulse := 0.55 + 0.35 * sin(elapsed * 2.2)
		skin.text_c(self, VW * 0.5, VH - 24, "ANY KEY CONTINUE", Color(SFPalette.CYAN.r, SFPalette.CYAN.g, SFPalette.CYAN.b, pulse))
	skin.text_r(self, VW - 14, VH - 16, "ESC SKIP", SFPalette.ASH_LIGHT)
