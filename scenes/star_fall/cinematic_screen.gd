extends Node2D
## Phase 4: the escape cinematic. Six scenes and the closing message, drawn
## entirely in-engine from generated sprites and primitives. No external video,
## no missing files, nothing that can fail to load.
##
## Two of the six scenes are playable:
##   * `debris_passage` — VELA holds the left of the lane while meteoroids stream
##     in from the right. W/S, Up/Down or the mouse steer. A collision shows a
##     short impact beat and restarts the segment from the top. There is no
##     blocking transit panel: the field is the whole screen.
##   * `portal` — the player lines VELA up with the opening seam and flies it in.
## `SFFlight` owns those rules (pure); this screen feeds it input and draws it.
##
## The screen owns no campaign state. It reports exactly one outcome through
## `cinematic_finished(skipped)`; the controller applies every flag, checkpoint
## and stage change, so watching and skipping are guaranteed to leave the same
## persistent state.
##
## Scenes reflect what the player actually did. Scene A lights the junction only
## if it was repaired, and lists only memories that were really found. Scene C
## reads its route and absorbed-impact count from the certified simulation, and
## neither number is ever random.
##
## Controls
##   SPACE              pause / resume (pause freezes subtitles and the clock)
##   ESC                skip the rest of the sequence (safe, idempotent)
##   ANY OTHER KEY      fast-forward to the next minor beat
##   LEFT CLICK         the same, outside the HUD
##   W / S, Up / Down   steer during the playable segments
##   MOUSE              steer toward the pointer during the playable segments
##
## Safety: `skip()` and the natural end both call `_finish()` once. Focus loss
## pauses rather than letting the sequence run unseen. Leaving the screen is the
## controller's job (`_go()` frees this node), so no timer here outlives it.

signal cinematic_finished(skipped: bool)

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFFinale := preload("res://core/star_fall/sf_finale.gd")
const SFFlight := preload("res://core/star_fall/sf_flight.gd")

const VW := 640
const VH := 360

## Keys that are never "any key": Esc skips, Space pauses.
const RESERVED_KEYS := [KEY_ESCAPE, KEY_SPACE]
## Keys that steer a playable segment. They are read as input actions, not as
## raw keycodes, so the arrows and W/S both work and neither ever skips.
const STEER_KEYS := [KEY_W, KEY_S, KEY_UP, KEY_DOWN]

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
var finishing_time: float = 0.0
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
var _mouse_target_y: float = 180.0
var _mouse_engaged: bool = false
var _last_impact_sfx: float = -10.0
var _assist_notice: String = ""
var _assist_notice_time: float = 0.0
var _notice: String = ""
var _notice_time: float = 0.0
# Cues fire once per scene entry, keyed by "scene:name".
var _fired_cues: Dictionary = {}
## The transform the scene is drawn in. Identity except for the home scene's
## camera push; helper art restores to this rather than to identity, so a
## nested `draw_set_transform` can never silently un-zoom the frame.
var _draw_base: Transform2D = Transform2D.IDENTITY


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
	return flight.is_active() and _hit_freeze <= 0.0


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

	# A collision beat freezes the segment but not the clock: the subtitle that
	# is on screen stays readable while the ship recovers.
	if _hit_freeze > 0.0:
		_hit_freeze = maxf(0.0, _hit_freeze - delta)
		scene_time += delta
		if _hit_freeze <= 0.0 and flight != null:
			flight.restart()
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
	# A long-dead controller, or a player who simply holds still, is rescued by
	# the ship's own navigation chip. The timer is on the scene clock, which does
	# not reset on a collision, so it always fires however often the field is
	# restarted.
	var assist_after: float = float(_flight_config().get("assist_after_seconds", 26.0))
	if flight != null and not flight.assist and assist_after > 0.0 and scene_time >= assist_after:
		flight.assist = true
		_assist_notice = "NAVIGATION CHIP TAKING THE STICK"
		_assist_notice_time = 2.4
		skin.audio.sfx_signal_lock()
	var events: Array = flight.tick(delta, _steer_direction(delta))
	for entry in events:
		var e: Dictionary = entry
		match String(e.get("type", "")):
			"hit":
				_on_flight_hit(e)
			"cleared":
				_on_segment_done(false)
			"entered":
				_on_segment_done(true)
			"assist":
				_assist_notice = "NAVIGATION CHIP TAKING THE STICK"
				_assist_notice_time = 2.4
				skin.audio.sfx_signal_lock()
			"spawn":
				pass
	# Only a flown segment ends the scene. The navigation assist guarantees that
	# a segment always finishes; this backstop exists so a cinematic can never
	# hang on a bug, and normal play never reaches it.
	if _hold_timer <= 0.0 and flight.is_active() and scene_time >= scene_duration() + 30.0:
		_on_segment_done(false)


func _on_flight_hit(event: Dictionary) -> void:
	_impact_point = Vector2(float(event.get("x", 100.0)), float(event.get("y", 180.0)))
	_hit_freeze = float(_flight_config().get("hit_freeze_seconds", 0.55))
	_shake_energy = 1.0
	if elapsed - _last_impact_sfx > 0.25:
		_last_impact_sfx = elapsed
		skin.audio.sfx_impact()


func _on_segment_done(entered_portal: bool) -> void:
	if _hold_timer > 0.0 or flight == null:
		return
	_hold_timer = float(_flight_config().get("clear_hold_seconds", 1.5))
	if entered_portal:
		_shake_energy = 0.7
		skin.audio.sfx_rift()
	else:
		skin.audio.sfx_signal_lock()


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
	_mouse_target_y = flight.ship_y


func _steer_direction(delta: float) -> float:
	if _mouse_engaged and flight != null:
		flight.steer_toward(_mouse_target_y, delta)
	var up := Input.is_action_pressed("move_up")
	var down := Input.is_action_pressed("move_down")
	var direction: float = 0.0
	if down and not up:
		direction = 1.0
	elif up and not down:
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
	cinematic_finished.emit(was_skipped)


# ---------------------------------------------------------------- cues

## Audio and flash cues tied to scene beats. Each fires once per scene entry, so
## repeated frames, a pause and a resume never stack a second copy.
func _fire_scene_cues() -> void:
	var id := scene_id()
	if id == "launch":
		_cue("launch:ignition", 0.05, "sfx_launch")
		_cue("launch:shield", 5.9, "sfx_power_up")
		_cue("launch:shatter", 12.75, "sfx_impact")
	elif id == "sunlight":
		_cue("sunlight:warm", 6.0, "sfx_memory")
	elif id == "home":
		_cue("home:touchdown", 5.4, "sfx_impact")
		_cue("home:hatch", 7.6, "sfx_install")
		_cue("home:portrait", 19.0, "sfx_confirm")


func _cue(key: String, at: float, sfx: String) -> void:
	var tag := scene_id() + ":" + key
	if _fired_cues.has(tag):
		return
	if scene_time < at:
		return
	_fired_cues[tag] = true
	if skin != null and skin.audio != null and skin.audio.has_method(sfx):
		skin.audio.call(sfx)


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
				skin.audio.sfx_back()
			else:
				skin.audio.sfx_select()
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
			_mouse_target_y = pos.y
		return
	fast_forward()


func handle_mouse_motion(pos: Vector2) -> void:
	if not is_interactive() or paused:
		return
	if pos.y < 30.0:
		return
	_mouse_engaged = true
	_mouse_target_y = clampf(pos.y, 0.0, float(VH))


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
	skin.audio.sfx_select()
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
			_draw_scene_crash_site()
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
## the lane, so nothing ever covers the field or the dialogue.
func _draw_flight_hud() -> void:
	if not is_interactive() or flight == null:
		return
	var bar_y := 30.0
	var ratio: float = flight.progress_fraction()
	draw_rect(Rect2(40, bar_y, VW - 80, 2), Color(0.10, 0.16, 0.18, 0.85), true)
	draw_rect(Rect2(40, bar_y, (VW - 80) * ratio, 2), SFPalette.CYAN, true)
	var kind := String(current_scene().get("interactive", ""))
	var hint := "W / S   UP / DOWN   MOUSE"
	if kind == "portal":
		hint = "W / S   UP / DOWN   MOUSE   ALIGN WITH THE OPENING"
	draw_rect(Rect2(40, bar_y + 5, 250, 12), Color(0.02, 0.04, 0.05, 0.72), true)
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
		skin.text_c(self, VW * 0.5, 48, _notice, Color(SFPalette.RED.r, SFPalette.RED.g, SFPalette.RED.b, pulse))
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


# ---------------------------------------------------------------- scene A

## The crash site. Every repaired system the player actually touched is lit; the
## memory core moves from Bill's old body to the VELA; the shell powers down.
func _draw_scene_crash_site() -> void:
	var t: float = clampf(scene_time / 16.0, 0.0, 1.0)
	# Dark ash sky and the wreck field.
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var band := 0
	while band < 14:
		var f := float(band) / 14.0
		draw_rect(Rect2(0, 100 + band * 14, VW, 15), SFPalette.INK.lerp(SFPalette.RUIN_DARK, f * f), true)
		band += 1
	draw_rect(Rect2(0, 300, VW, VH - 300), SFPalette.ASH_PLAIN.darkened(0.28), true)
	draw_rect(Rect2(0, 300, VW, 2), SFPalette.ASH.darkened(0.2), true)

	# The VELA, rebuilt, resting nose right in the cradle. Its own gear carries
	# the weight, so the ship is clearly standing on the ground, not floating.
	_draw_ship_grounded(Vector2(452, 300), 1.0, 1.0, false)
	# Bill's shell on the left. It powers down as the core leaves it.
	var power: float = clampf(1.0 - t * 1.6, 0.0, 1.0)
	_draw_bill_shell(Vector2(140, 302), power)
	# The junction: lit only if the player repaired it.
	if campaign.has_flag("power_repaired"):
		var pulse: float = 0.55 + 0.35 * sin(elapsed * 3.0)
		draw_rect(Rect2(64, 288, 22, 14), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(68, 292, 14, 4), Color(0.40, 0.95, 0.85, pulse), true)
		draw_rect(Rect2(240, 300, 26, 2), Color(0.35, 0.75, 0.70, 0.30 * pulse), true)

	# The memory core, travelling from Bill to the VELA along an arc.
	var travel: float = clampf((scene_time - 1.2) / 4.0, 0.0, 1.0)
	if travel > 0.0 and travel < 1.0:
		var from := Vector2(140, 268)
		var to := Vector2(462, 276)
		var p: Vector2 = from.lerp(to, travel)
		p.y -= sin(travel * PI) * 54.0
		draw_rect(Rect2(p.x - 3, p.y - 3, 6, 6), SFPalette.CYAN, true)
		draw_rect(Rect2(p.x - 6, p.y - 1, 12, 2), Color(0.36, 0.90, 0.86, 0.35), true)
	elif travel >= 1.0:
		draw_rect(Rect2(458, 272, 8, 8), SFPalette.CYAN, true)

	# Dust and ground haze, tied to the scene clock rather than to randomness.
	for i in 22:
		var phase := fmod(float(i) * 0.37, 1.0)
		if phase > t:
			continue
		var dx := fmod(float(i) * 97.0 + elapsed * 9.0, VW)
		var dy := 316.0 - fmod(float(i) * 23.0 + elapsed * 4.0, 26.0)
		draw_rect(Rect2(round(dx), round(dy), 2, 1), Color(0.42, 0.46, 0.44, 0.35), true)


# ---------------------------------------------------------------- scene B

## Ascent. Ignition, a heavy smoke plume, then a long climb through stratified
## junk around the ruined planet with the blue shield up. The last, thickest
## shell overloads and shatters the shield exactly as VELA breaks into open
## space: the shield is spent winning the ascent, not protecting a cutscene.
func _draw_scene_launch() -> void:
	var t: float = clampf(scene_time / 15.0, 0.0, 1.0)
	var shake: Vector2 = _shake_vector()
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)

	# Sky at the pad gives way to black space as the ship leaves the ground.
	var low_sky: Color = SFPalette.ASH_PLAIN.lerp(SFPalette.INK, clampf(t * 1.8, 0.0, 1.0))
	draw_rect(Rect2(0, 0, VW, 250), SFPalette.INK.lerp(low_sky, 0.65 * (1.0 - t)), true)
	draw_rect(Rect2(0, 250, VW, VH - 250), low_sky, true)

	# Stars thin out as the frame fills with junk.
	for i in 70:
		var sx := float((i * 83) % VW)
		var sy := float((i * 47) % 236)
		var sa: float = clampf(t * 0.8 - 0.1, 0.0, 0.55)
		draw_rect(Rect2(sx, sy, 1, 1), Color(0.88, 0.93, 1.0, sa), true)

	# The ruined planet below fades in only once the ground has left the frame:
	# before that the picture is the pad and the wreck field.
	var planet_in: float = clampf((t - 0.34) / 0.30, 0.0, 1.0)
	if planet_in > 0.0:
		_draw_planet_limb(Vector2(320, 600), 320.0, planet_in * (1.0 - clampf((t - 0.86) / 0.14, 0.0, 0.6)))

	# The pad and the wreck field, in frame until the ship has climbed past them.
	var ground_y: float = 300.0 + pow(t, 0.55) * 760.0
	if ground_y < VH + 30.0:
		draw_rect(Rect2(0, ground_y, VW, VH - ground_y + 30.0), SFPalette.RUIN, true)
		draw_rect(Rect2(0, ground_y, VW, 2), SFPalette.ASH_PLAIN, true)
		# The cradle, left behind on the ground.
		draw_rect(Rect2(VW * 0.5 - 46, ground_y - 6, 92, 6), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(VW * 0.5 - 40, ground_y - 9, 8, 9), SFPalette.STEEL_MID, true)
		draw_rect(Rect2(VW * 0.5 + 32, ground_y - 9, 8, 9), SFPalette.STEEL_MID, true)

	# The ship: on the pad at ignition, then climbing nose up-right.
	var climb: float = clampf((t - 0.10) / 0.86, 0.0, 1.0)
	var eased: float = climb * climb * (3.0 - 2.0 * climb)
	var ship := Vector2(VW * 0.5 + sin(climb * 42.0) * 0.7, lerpf(282.0, 58.0, eased))
	ship += shake
	var rot: float = lerpf(-0.12, -1.18, clampf(climb * 3.2, 0.0, 1.0))
	var heavy: float = clampf(1.0 - t * 2.6, 0.0, 1.0)
	var thrust: float = 1.0 + heavy * 0.85

	# The smoke column stands on the pad and the ship rises through it, so the
	# plume is always behind the hull it belongs to.
	_draw_smoke_column(Vector2(VW * 0.5, 302.0), t, shake)
	_draw_ship(ship, 1.35, rot, thrust)
	_draw_ignition_dust(Vector2(VW * 0.5, 300.0), clampf(t / 0.40, 0.0, 1.0), shake)

	# Orbit debris strata: bands of junk the ship must push through. They thicken
	# toward the top of the climb, then break open after the shield fails.
	var shield_on: float = clampf((t - 0.36) / 0.10, 0.0, 1.0)
	var shattered: bool = t >= 0.855
	var strata_fade: float = 1.0 - clampf((t - 0.80) / 0.10, 0.0, 1.0)
	if strata_fade > 0.0:
		_draw_strata(ship, t, shield_on, strata_fade)
	if not shattered:
		if shield_on > 0.0:
			_draw_shield(ship, 1.0, shield_on)
	else:
		_draw_shield_shatter(ship, t)

	# A white impact flash on the frame the shield fails, reduced with the
	# accessibility setting.
	if absf(t - 0.856) < 0.012 and not reduced_motion:
		draw_rect(Rect2(0, 0, VW, VH), Color(1.0, 1.0, 1.0, 0.55), true)


## Lays out the ascent's debris once. Each stratum gets more and larger bodies
## the higher it sits, and every body keeps a stable height, size and tone, so a
## captured frame is reproducible and the field never reads as a repeating grid.
func _build_strata_field() -> void:
	_strata_field.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90211
	var layers := 6
	for layer in layers:
		var count: int = 22 + layer * 10
		for i in count:
			var size: float = 3.0 + rng.randf() * (3.0 + float(layer) * 1.1)
			_strata_field.append({
				"layer": layer,
				"x": rng.randf_range(-30.0, 670.0),
				"dy": rng.randf_range(-19.0, 19.0),
				# each body drifts at its own slow rate, so the field is alive
				"drift": rng.randf_range(3.0, 11.0),
				"phase": rng.randf_range(0.0, 6.283),
				"size": size,
				"tone": rng.randf_range(0.44, 0.70),
			})


## The launch plume: a column of billowing puffs standing on the pad. Laid down
## before the hull so the ship always reads on top of its own exhaust. The
## thruster flame itself belongs to the ship (`_draw_exhaust`), so it can never
## drift away from the nozzles as the hull tilts and climbs.
func _draw_smoke_column(base: Vector2, t: float, shake: Vector2) -> void:
	if t > 0.78:
		return
	var strength: float = clampf(t * 5.0, 0.0, 1.0) * clampf((0.78 - t) / 0.50, 0.0, 1.0)
	if strength <= 0.0:
		return
	# The column: puffs that rise, spread and fade, all on the scene clock. Each
	# is a soft disc; overlapping them densely is what makes the plume read as
	# smoke rather than as a row of bubbles.
	for i in 54:
		var f := float(i) / 53.0
		var age := fmod(t * 2.4 + f * 0.8, 1.0)
		var drift := sin(float(i) * 1.7 + elapsed * 0.7) * 14.0
		var spread: float = (f - 0.5) * 110.0
		var px: float = base.x + spread + drift
		var py: float = base.y - age * 300.0 + cos(float(i) * 2.3) * 7.0
		var radius: float = (7.0 + age * 26.0) * (0.6 + strength * 0.5)
		var tone: float = 0.36 + f * 0.18
		var alpha: float = (1.0 - age) * 0.46 * strength
		draw_circle(Vector2(px, py) + shake * 0.4, radius,
			Color(tone, tone * 0.95, tone * 0.88, alpha))
	# A bright core at the base, where the flame hits the pad.
	var core: float = 22.0 + sin(elapsed * 24.0) * 3.0
	draw_circle(base + shake * 0.3, core * strength, Color(1.0, 0.68, 0.30, 0.26 * strength))
	draw_circle(base + shake * 0.3, core * 0.55 * strength, Color(1.0, 0.94, 0.76, 0.30 * strength))


func _draw_ignition_dust(center: Vector2, k: float, shake: Vector2) -> void:
	if k >= 1.0:
		return
	var fade: float = 1.0 - k
	# A low cloud rolling out along the ground in both directions, densest near
	# the pad and thinning with distance. It is drawn after the hull, so it
	# washes over the landing gear the way real pad dust does.
	for i in 44:
		var f := float(i) / 43.0
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var reach: float = float(i / 2) / 21.0
		var dist: float = (10.0 + reach * 150.0) * (0.35 + k * 0.9)
		var px: float = center.x + float(side) * dist
		var py: float = center.y + 2.0 - reach * 10.0 - k * 12.0
		var radius: float = (4.0 + k * 11.0) * (1.0 - reach * 0.45)
		draw_circle(Vector2(px, py) + shake * 0.5, radius,
			Color(0.58, 0.56, 0.50, fade * 0.30))
	# Stones thrown clear of the pad, on a short arc.
	for i in 10:
		var fa := float(i) / 9.0
		var a2: float = PI + fa * PI
		var r2: float = 26.0 + k * (80.0 + fa * 50.0)
		var p2 := Vector2(center.x + cos(a2) * r2, center.y + sin(a2) * r2 * 0.20 - k * k * 60.0)
		draw_rect(Rect2(round(p2.x), round(p2.y), 3, 2), SFPalette.STEEL_DARK, true)


## Five junk strata between the pad and orbit, each denser than the last. The
## ship passes through one after another as it climbs; the body it is level with
## throws sparks and ripples off the shield. This is the "punching through" read.
func _draw_strata(ship: Vector2, t: float, shield_on: float, fade: float) -> void:
	var layers := 6
	var band_y: Array = []
	for layer in layers:
		var f := float(layer) / float(layers - 1)
		# The strata run from the pad to the top of frame and climb with the
		# ship, so the field fills the picture at every point of the ascent.
		band_y.append(318.0 - f * 400.0 - t * 96.0)
	# The soft body of each stratum first, under every body in it.
	for layer in layers:
		var by: float = float(band_y[layer])
		if by < -60.0 or by > VH + 60.0:
			continue
		var f2 := float(layer) / float(layers - 1)
		draw_rect(Rect2(0, by - 20.0, VW, 40.0), Color(0.30, 0.26, 0.34, (0.05 + f2 * 0.06) * fade))
	# Then the bodies.
	for entry in _strata_field:
		var b: Dictionary = entry
		var layer: int = int(b["layer"])
		var by2: float = float(band_y[layer])
		var y: float = by2 + float(b["dy"])
		if y < -20.0 or y > VH + 20.0:
			continue
		var x: float = fmod(float(b["x"]) - elapsed * float(b["drift"]), float(VW + 60)) - 30.0
		var size: float = float(b["size"])
		var tone: float = float(b["tone"])
		draw_rect(Rect2(round(x), round(y), round(size), maxf(2.0, round(size * 0.78))),
			Color(tone, tone * 0.90, tone * 0.80, 0.95 * fade))
		# A lit top edge and a dark underside, so a body reads as a chunk.
		draw_rect(Rect2(round(x), round(y), round(size), 1.0),
			Color(minf(1.0, tone * 1.35), minf(1.0, tone * 1.28), tone * 1.15, 0.95 * fade))
		draw_rect(Rect2(round(x), round(y + size * 0.78), round(size), 1.0),
			Color(tone * 0.50, tone * 0.46, tone * 0.42, 0.90 * fade))
		if size > 5.0:
			# A broken edge: one notch bitten out of the silhouette.
			draw_rect(Rect2(round(x + size * 0.6), round(y - 1.0), 2, 2),
				Color(0.10, 0.11, 0.14, 0.85 * fade))
	# Impact: when a stratum is level with the ship, ripples cross the shield and
	# sparks fly off it.
	var nearest: float = 999.0
	for layer in layers:
		nearest = minf(nearest, absf(float(band_y[layer]) - ship.y))
	if nearest < 30.0 and shield_on > 0.0:
		var strength: float = 1.0 - nearest / 30.0
		for i in 16:
			var ang := float(i) * 0.9 + elapsed * 2.0
			var r: float = 46.0 + fmod(elapsed * 90.0 + float(i) * 7.0, 26.0)
			var p := ship + Vector2(cos(ang), sin(ang) * 0.84) * r
			draw_rect(Rect2(round(p.x), round(p.y), 2, 2),
				Color(0.85, 0.98, 1.0, strength * 0.95))
		for i in 3:
			var ry: float = 26.0 + fmod(elapsed * 60.0 + float(i) * 9.0, 26.0)
			draw_arc(ship, ry, -1.0, 1.0, 14, Color(0.70, 0.94, 1.0, strength * 0.55), 2.0)


## The blue escape shield: a translucent bubble with a bright rim and a slow
## travelling shimmer, so its state is legible at a glance and it reads as a
## shield rather than as a halo.
func _draw_shield(center: Vector2, radius_scale: float, strength: float) -> void:
	var radius: float = 52.0 * radius_scale
	var pulse: float = 0.90 + 0.10 * sin(elapsed * 5.0)
	var rim_alpha: float = (0.55 + 0.45 * strength) * pulse
	# The glass: nested discs, brightest just inside the rim, so the bubble has
	# body and reads as energy rather than as a ring.
	for ring in 7:
		var rf: float = 1.0 - float(ring) * 0.055
		var alpha: float = (0.045 + float(ring) * 0.012) * strength
		draw_circle(center, radius * pulse * rf, Color(0.30, 0.70, 0.96, alpha))
	# A bright two-pixel rim.
	for i in 96:
		var ang := float(i) / 96.0 * TAU
		var p := center + Vector2(cos(ang), sin(ang) * 0.86) * radius * pulse
		var flicker: float = 0.80 + 0.20 * sin(float(i) * 0.5 + elapsed * 4.0)
		var rim: Color = SFPalette.SHIELD_BLUE_LIGHT
		draw_rect(Rect2(round(p.x), round(p.y), 1, 1), Color(rim.r, rim.g, rim.b, rim_alpha * flicker))
		var inward := center + Vector2(cos(ang), sin(ang) * 0.86) * radius * pulse * 0.94
		draw_rect(Rect2(round(inward.x), round(inward.y), 1, 1),
			Color(0.42, 0.80, 0.98, rim_alpha * 0.35 * flicker))
	# A shimmer band travelling around the bubble, and a specular highlight.
	for i in 18:
		var t: float = fmod(float(i) / 18.0 + elapsed * 0.18, 1.0)
		var ang2 := t * TAU
		var p2 := center + Vector2(cos(ang2), sin(ang2) * 0.86) * radius * pulse * 0.99
		draw_rect(Rect2(round(p2.x), round(p2.y), 2, 2), Color(0.82, 0.97, 1.0, 0.55 * strength))
	draw_rect(Rect2(round(center.x - radius * 0.42), round(center.y - radius * 0.62), 7, 3),
		Color(1.0, 1.0, 1.0, 0.30 * strength), true)


## The final debris shell overloading the emitter: fragments blown outward, a
## ring shockwave, and the bubble gone.
func _draw_shield_shatter(ship: Vector2, t: float) -> void:
	var k: float = clampf((t - 0.855) / 0.145, 0.0, 1.0)
	for i in 30:
		var ang := float(i) / 30.0 * TAU + 0.13
		var speed: float = 40.0 + float((i * 13) % 50)
		var p := ship + Vector2(cos(ang), sin(ang) * 0.8) * (40.0 + k * speed * 2.4)
		var size: int = 2 + int((i * 5) % 3)
		var fade: float = 1.0 - k
		draw_rect(Rect2(round(p.x), round(p.y), size, maxi(1, size - 1)),
			Color(SFPalette.SHIELD_BLUE_LIGHT.r, SFPalette.SHIELD_BLUE_LIGHT.g,
				SFPalette.SHIELD_BLUE_LIGHT.b, fade * 0.9))
	for ring in 2:
		var rr: float = 42.0 + k * (110.0 + float(ring) * 50.0)
		draw_arc(ship, rr, 0.0, TAU, 40,
			Color(0.55, 0.90, 1.0, (1.0 - k) * (0.5 - float(ring) * 0.2)), 2.0)


func _draw_far_debris(after: float) -> void:
	for i in 18:
		var x := fmod(float(i) * 71.0 - elapsed * (8.0 + float(i % 4) * 3.0), float(VW + 30)) - 15.0
		var y := float((i * 53) % 300)
		var size: int = 1 + i % 3
		draw_rect(Rect2(x, y, size, size), Color(0.40, 0.46, 0.50, 0.55 * after), true)


## The ruined planet's limb, seen from just above its junk belt: a violet-gray
## curve, hazed at the edge, filling the bottom of the frame under the ascent.
func _draw_planet_limb(center: Vector2, radius: float, strength: float) -> void:
	if strength <= 0.0:
		return
	var bands := 22
	for ring in bands:
		var f := float(ring) / float(bands - 1)
		var rr: float = radius * (1.0 - f * 0.24)
		var col: Color = Color(0.40, 0.30, 0.46, 0.30 * strength).lerp(
			Color(0.14, 0.15, 0.20, 0.24 * strength), f)
		draw_circle(center, rr, col)
	# A contaminated haze held above the limb.
	for i in 10:
		var ry: float = radius * 0.99 + float(i) * 3.0
		draw_circle(center, ry, Color(0.52, 0.40, 0.62, 0.055 * strength * (1.0 - float(i) / 10.0)))
	# A few bright fires on the surface, so it is unmistakably a *damaged* world.
	for i in 16:
		var ang := float(i) * 1.7
		var rr2: float = radius * (0.80 + float((i * 7) % 10) * 0.014)
		var p := center + Vector2(cos(ang) * rr2, sin(ang) * rr2)
		if p.y < 300.0:
			continue
		draw_rect(Rect2(round(p.x), round(p.y), 2, 1), Color(0.95, 0.58, 0.32, 0.55 * strength), true)


# ---------------------------------------------------------------- scene C

## Debris passage, now playable. VELA holds the left of the lane; meteoroids
## stream in from the right. No panel covers the field: the route and the
## recorded impact count sit in the header, and the dialogue stays at the edge.
func _draw_scene_debris() -> void:
	_ensure_flight()
	var shake: Vector2 = _shake_vector()
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.03, 0.06), true)
	# Starfield, drifting; sudden speed streaks while the ship is moving.
	for i in 90:
		var sx := float((i * 71) % VW) - fmod(elapsed * 6.0, float(VW))
		var sy := float((i * 37) % VH)
		if sx < 0.0:
			sx += float(VW)
		draw_rect(Rect2(round(sx), round(sy), 1, 1),
			Color(0.75, 0.82, 0.95, 0.30 + 0.25 * float(i % 3) / 3.0), true)
	for i in 10:
		var ly := 74.0 + fmod(float(i * 43) + elapsed * 120.0, 212.0)
		var lx := fmod(float(i * 137) + elapsed * 260.0, float(VW))
		draw_rect(Rect2(VW - lx, ly, 18, 1), Color(0.55, 0.66, 0.78, 0.16), true)
	# The planet's junk shell behind the lane, out of reach of the ship.
	if flight != null:
		_draw_debris_backdrop()
		_draw_obstacles(shake)
		_draw_play_ship(shake)
		if _hit_freeze > 0.0:
			_draw_impact_burst()


func _draw_debris_backdrop() -> void:
	for layer in 2:
		var alpha: float = 0.20 + float(layer) * 0.10
		for i in 26:
			var x := fmod(float(i) * 79.0 - elapsed * (10.0 + float(layer) * 6.0), float(VW + 60)) - 30.0
			var y := 60.0 + fmod(float(i * 47 + layer * 13), 280.0) * 0.75
			var size: float = 2.0 + float((i + layer) % 3)
			draw_rect(Rect2(x, y, size, size), Color(0.30, 0.34, 0.40, alpha), true)


func _draw_obstacles(shake: Vector2) -> void:
	if flight == null:
		return
	for entry in flight.active_obstacles():
		var body: Dictionary = entry
		var cx: float = float(body["x"]) + shake.x
		var cy: float = float(body["y"]) + shake.y
		var hw: float = float(body["hw"])
		var hh: float = float(body["hh"])
		var tone: int = int(body["tone"])
		var phase: float = float(body["phase"])
		var rim: Color = [Color("3a352c"), Color("3b332c"), Color("33302b")][tone]
		var face: Color = [Color("857966"), Color("7d7160"), Color("6e6759")][tone]
		var light: Color = [Color("a99a82"), Color("a09278"), Color("8f8674")][tone]
		# A lumpy silhouette: eight points, each pulled in or out by the body's
		# own phase, so no two rocks look stamped from the same mould.
		var outer := PackedVector2Array()
		for p in 10:
			var ang := float(p) / 10.0 * TAU + phase
			var wobble: float = 0.82 + 0.18 * sin(float(p) * 2.7 + phase * 3.0)
			outer.append(Vector2(cx + cos(ang) * hw * wobble, cy + sin(ang) * hh * wobble))
		draw_colored_polygon(outer, rim)
		# The lit face, offset up and left, so the rock is lit from the same side
		# as the ship.
		var inner := PackedVector2Array()
		for p in 10:
			var ang2 := float(p) / 10.0 * TAU + phase
			var wobble2: float = 0.72 + 0.16 * sin(float(p) * 2.7 + phase * 3.0)
			inner.append(Vector2(cx + cos(ang2) * hw * wobble2 - hw * 0.10,
				cy + sin(ang2) * hh * wobble2 - hh * 0.16))
		draw_colored_polygon(inner, face)
		# A lit crescent along the upper-left edge.
		var crescent := PackedVector2Array()
		for p in 5:
			var ang3 := PI * 0.9 + float(p) / 4.0 * PI * 0.75
			var rr: float = 0.86 + 0.10 * sin(float(p) * 2.7 + phase * 3.0)
			crescent.append(Vector2(cx + cos(ang3) * hw * rr - hw * 0.06,
				cy + sin(ang3) * hh * rr - hh * 0.12))
		if crescent.size() >= 3:
			draw_colored_polygon(crescent, light)
		# Craters, placed by the body's own phase so they tumble with it.
		var craters: int = 3 if hw > 10.0 else 2
		for c in craters:
			var ca: float = phase + float(c) * 2.1
			var cr: float = 0.30 + 0.12 * float(c)
			draw_circle(Vector2(cx + cos(ca) * hw * cr, cy + sin(ca) * hh * cr),
				maxf(1.0, hw * 0.16), rim.darkened(0.08))
		# A warm glint on the lit edge: the only warm pixel on the body.
		draw_rect(Rect2(round(cx - hw * 0.62), round(cy - hh * 0.58), 2, 2),
			Color(0.92, 0.86, 0.72, 0.85), true)


## VELA in the lane: nose right, exhaust trailing left, a small attitude tilt
## that follows the direction of travel so the ship always looks like it is
## flying where it is going.
func _draw_play_ship(shake: Vector2) -> void:
	if flight == null:
		return
	var pos: Vector2 = Vector2(flight.ship_x, flight.ship_y) + shake
	var tilt: float = 0.0
	if _steer_stick < 0.0:
		tilt = -0.10
	elif _steer_stick > 0.0:
		tilt = 0.10
	elif Input.is_action_pressed("move_up"):
		tilt = -0.10
	elif Input.is_action_pressed("move_down"):
		tilt = 0.10
	_draw_ship(pos, 0.92, tilt, 1.0)
	if flight.assist:
		# A faint cyan trail from the navigation chip, so the takeover is visible.
		draw_rect(Rect2(pos.x - 58, pos.y - 1, 22, 2), Color(0.30, 0.85, 0.90, 0.35), true)


func _draw_impact_burst() -> void:
	var life: float = 1.0 - clampf(_hit_freeze / maxf(0.01, float(_flight_config().get("hit_freeze_seconds", 0.55))), 0.0, 1.0)
	for i in 16:
		var ang := float(i) / 16.0 * TAU
		var r: float = 6.0 + life * 34.0
		var p := _impact_point + Vector2(cos(ang), sin(ang)) * r
		draw_rect(Rect2(round(p.x), round(p.y), 2, 2), Color(1.0, 0.72, 0.35, 1.0 - life), true)
	draw_circle(_impact_point, 8.0 + life * 10.0, Color(1.0, 0.85, 0.55, 0.35 * (1.0 - life)))
	skin.text_c(self, VW * 0.5, 62, "HULL STRIKE", Color(SFPalette.RED.r, SFPalette.RED.g, SFPalette.RED.b,
		0.6 + 0.4 * sin(elapsed * 18.0)))


# ---------------------------------------------------------------- scene D

## Sunlight. VELA has broken out, and the shot looks back at what the planet
## became: a world smothered in its own waste, ringed with scrap, hazed violet.
func _draw_scene_sunlight() -> void:
	var t: float = clampf(scene_time / 17.0, 0.0, 1.0)
	draw_rect(Rect2(0, 0, VW, VH), Color(0.04, 0.05, 0.09), true)
	# Warm light rises from the upper right and fills the frame slowly, in narrow
	# bands so the gradient has no visible step.
	var warm: float = clampf(t * 1.4, 0.0, 1.0)
	for i in 40:
		var f := 1.0 - float(i) / 39.0
		var c: Color = Color(0.04, 0.05, 0.09).lerp(Color(0.96, 0.73, 0.44), pow(f, 2.1) * 0.38 * warm)
		draw_rect(Rect2(0, VH - 6.0 - float(i) * 6.0, VW, 7), c, true)
	# Sun glow, upper right.
	for i in 10:
		draw_circle(Vector2(560, 46), 16.0 + float(i) * 9.0, Color(1.0, 0.88, 0.62, 0.035 * warm))

	_draw_trash_planet(Vector2(196, 286), 168.0, t, warm)

	# VELA small against the light, drifting clear of the belt.
	var drift := sin(elapsed * 0.5) * 5.0
	_draw_ship(Vector2(512, 152 + drift), 0.62, -0.08, 0.35)

	# A quiet lens bloom, kept restrained so it never weakens the beat.
	if t > 0.35:
		var bloom := clampf((t - 0.35) / 0.6, 0.0, 1.0) * 0.13
		draw_rect(Rect2(0, 0, VW, VH), Color(1.0, 0.92, 0.76, bloom), true)


## Future Earth from orbit: a violet-brown disc under a haze, wrapped in three
## rings of scrap, with broken satellites and ash clouds drifting over it. The
## surface is deliberately hard to see. That is the point of the shot.
func _draw_trash_planet(center: Vector2, radius: float, t: float, warm: float) -> void:
	# The disc, built from rings so the shading stays smooth and pixel-crisp.
	for ring in range(26, 0, -1):
		var rr: float = radius * float(ring) / 26.0
		var k: float = float(ring) / 26.0
		var col: Color = Color(0.20, 0.17, 0.24).lerp(Color(0.34, 0.28, 0.31), k)
		draw_circle(center, rr, col)
	# Smog bands across the disc, drifting, so the surface reads as obscured.
	for i in 22:
		var band_y: float = center.y - radius * 0.8 + float(i) * (radius * 1.6 / 22.0)
		var width: float = radius * 1.7
		var drift: float = sin(elapsed * 0.22 + float(i) * 0.6) * radius * 0.14
		var a: float = 0.10 + 0.07 * sin(float(i) * 1.3 + elapsed * 0.4)
		draw_rect(Rect2(center.x - width * 0.5 + drift, band_y, width, 4.0),
			Color(0.52, 0.44, 0.46, a), true)
	# A few stubborn bright spots: fires and broken city lights, not a healthy
	# surface. Sparse on purpose.
	for i in 14:
		var ang := float(i) * 1.7 + t * 0.2
		var rr2: float = radius * (0.25 + float((i * 13) % 60) / 100.0)
		var p := center + Vector2(cos(ang) * rr2, sin(ang) * rr2 * 0.92)
		draw_rect(Rect2(round(p.x), round(p.y), 1, 1),
			Color(0.92, 0.55, 0.30, 0.35 + 0.25 * sin(elapsed + float(i))), true)

	# Contaminated atmosphere: a violet-gray haze held to the limb.
	for i in 30:
		var ang2 := float(i) / 30.0 * TAU
		var p2 := center + Vector2(cos(ang2), sin(ang2)) * (radius + 4.0)
		draw_rect(Rect2(round(p2.x), round(p2.y), 2, 2), Color(0.52, 0.42, 0.60, 0.28 * warm), true)
	for i in 12:
		var ry: float = radius + 3.0 + float(i) * 2.0
		var a2: float = 0.05 * (1.0 - float(i) / 12.0)
		draw_circle(center, ry, Color(0.44, 0.34, 0.52, a2))

	# Three scrap rings, each with its own tilt and density.
	var rings := [
		[radius * 1.34, 0.30, 40, 0.05],
		[radius * 1.58, 0.26, 52, 0.04],
		[radius * 1.86, 0.20, 40, 0.03],
	]
	for r in rings:
		var rr3: float = float(r[0])
		var squash: float = float(r[1])
		var count: int = int(r[2])
		var spin: float = float(r[3])
		for i in count:
			var ang3 := float(i) / float(count) * TAU + elapsed * spin + t * 0.3
			if ang3 > 0.0 and ang3 < PI:
				continue
			var p3 := center + Vector2(cos(ang3) * rr3, sin(ang3) * rr3 * squash)
			var size: int = 1 + (i % 3)
			draw_rect(Rect2(round(p3.x), round(p3.y), size, maxi(1, size - 1)),
				Color(0.56, 0.52, 0.46, 0.5), true)
			_pending_ring_front.append(Vector3(p3.x, p3.y, float(size)))
	# The front halves of the rings are drawn after the planet so they cross it.
	for v in _pending_ring_front:
		var sz: int = int(v.z)
		draw_rect(Rect2(v.x, v.y, sz, maxi(1, sz - 1)), Color(0.60, 0.56, 0.50, 0.55), true)
	_pending_ring_front.clear()

	# Broken satellite silhouettes, tumbling slowly against the disc.
	for i in 4:
		var s := _satellite_position(center, radius, i, t)
		_draw_broken_satellite(s, float(i) * 0.7 + elapsed * 0.09, 0.55 + float(i % 2) * 0.25)


var _pending_ring_front: Array = []
## The climb's junk field, laid out once with a fixed seed: every body keeps its
## own height and size, so the strata read as a field rather than as columns.
var _strata_field: Array = []


func _satellite_position(center: Vector2, radius: float, index: int, t: float) -> Vector2:
	var ang: float = float(index) * 1.9 + t * 0.35 + 0.6
	var r: float = radius * (1.02 + float(index) * 0.10)
	return center + Vector2(cos(ang) * r, sin(ang) * r * 0.34 - radius * 0.12)


func _draw_broken_satellite(pos: Vector2, rot: float, size_scale: float) -> void:
	var body_w: float = 12.0 * size_scale
	var body_h: float = 6.0 * size_scale
	draw_set_transform_matrix(_draw_base * _local_transform(pos, rot, 1.0))
	draw_rect(Rect2(-body_w * 0.5, -body_h * 0.5, body_w, body_h), Color(0.34, 0.33, 0.32, 0.85), true)
	draw_rect(Rect2(-body_w * 0.5, -body_h * 0.5, body_w, 1), Color(0.48, 0.46, 0.42, 0.8), true)
	# A snapped solar wing on one side only.
	draw_rect(Rect2(-body_w * 0.5 - 12.0 * size_scale, -3.0 * size_scale, 11.0 * size_scale, 6.0 * size_scale),
		Color(0.22, 0.30, 0.42, 0.85), true)
	for bar in 3:
		draw_rect(Rect2(-body_w * 0.5 - 11.0 * size_scale + float(bar) * 3.6 * size_scale,
			-3.0 * size_scale, 1, 6.0 * size_scale), Color(0.10, 0.13, 0.18, 0.8), true)
	# The other wing is a bent stub.
	draw_rect(Rect2(body_w * 0.5, -1.0 * size_scale, 4.0 * size_scale, 3.0 * size_scale),
		Color(0.22, 0.30, 0.42, 0.85), true)
	draw_set_transform_matrix(_draw_base)


# ---------------------------------------------------------------- scene E

## The portal, flown by the player. The seam opens on the right; VELA must line
## up with it and hold the line long enough to cross. The recorded signal is
## drawn as a waveform so the seam is visibly the source that was found, not a
## coincidence.
func _draw_scene_portal() -> void:
	_ensure_flight()
	var shake: Vector2 = _shake_vector()
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.02, 0.06), true)
	var cx: float = flight.portal_x if flight != null else 512.0
	var cy: float = flight.portal_y if flight != null else 180.0
	var half_h: float = flight.portal_half_height if flight != null else 40.0
	var open: float = clampf(scene_time / 1.4, 0.0, 1.0)

	# The dead present day behind the seam: a faint healthy Earth, small and far
	# away, so the tear visibly leads somewhere better than the world behind us.
	draw_circle(Vector2(cx + 6.0, cy), 26.0 * open, Color(0.20, 0.44, 0.62, 0.30 * open))
	draw_circle(Vector2(cx + 4.0, cy - 2.0), 18.0 * open, Color(0.32, 0.58, 0.66, 0.22 * open))

	# Stars dragged toward the seam.
	for i in 110:
		var ang := float(i) * 2.399
		var r := 22.0 + float((i * 41) % 250)
		var pull: float = 1.0 / (1.0 + r / 110.0)
		var sx := cx + cos(ang) * r * (1.0 - pull * 0.25)
		var sy := cy + sin(ang) * r * 0.60
		draw_rect(Rect2(round(sx), round(sy), 1, 1), Color(0.72, 0.80, 0.98, 0.18 + pull * 0.5), true)

	# The tear: a lens shape, widest at its waist, tapering to sharp ends. A
	# vertical column of pixels would read as a dotted line, not an opening, so
	# the width is a real function of height.
	var tear_h: float = half_h * 5.0 * (0.35 + 0.65 * open)
	var rows: int = 76
	for i in rows:
		var p: float = (float(i) + 0.5) / float(rows)
		var y2 := cy - tear_h * 0.5 + p * tear_h
		# |2p-1| is 0 at the waist; the lens is widest there.
		var waist: float = 1.0 - absf(p * 2.0 - 1.0)
		var widths := [34.0, 22.0, 12.0, 4.5]
		var tones := [
			Color(0.26, 0.16, 0.44, 0.30),
			Color(0.40, 0.28, 0.66, 0.42),
			Color(0.62, 0.52, 0.92, 0.55),
			Color(0.90, 0.95, 1.0, 0.90),
		]
		for w in 4:
			var width: float = float(widths[w]) * pow(waist, 0.65) * open
			if width < 0.6:
				continue
			var tone: Color = tones[w]
			draw_rect(Rect2(round(cx - width * 0.5), round(y2), round(width), 3.0),
				Color(tone.r, tone.g, tone.b, tone.a * open), true)
	# Two bright lips where the ship must pass, and a slow shimmer up the seam.
	draw_rect(Rect2(cx - 6, cy - half_h - 1, 12, 2), Color(0.92, 0.98, 1.0, 0.90 * open), true)
	draw_rect(Rect2(cx - 6, cy + half_h - 1, 12, 2), Color(0.92, 0.98, 1.0, 0.90 * open), true)
	for i in 6:
		var phase := fmod(elapsed * 0.7 + float(i) * 0.17, 1.0)
		var sy2: float = cy - half_h + phase * half_h * 2.0
		draw_rect(Rect2(cx - 1, sy2, 2, 6), Color(0.95, 0.99, 1.0, 0.55 * (1.0 - absf(phase - 0.5) * 2.0)), true)

	# The alignment bracket and the hold meter: a readout at the left edge, kept
	# above the dialogue box so neither ever covers the other.
	if flight != null:
		var bracket_y: float = flight.ship_y
		draw_rect(Rect2(20, bracket_y - 8, 2, 16), SFPalette.CYAN, true)
		draw_rect(Rect2(22, bracket_y - 1, 10, 2), SFPalette.CYAN, true)
		var align: float = flight.alignment_fraction()
		# The meter sits under the control strip, well clear of the dialogue.
		skin.text(self, Vector2(44, 46), "ALIGNMENT", SFPalette.PAPER_DIM)
		draw_rect(Rect2(100, 46, 150, 6), Color(0.06, 0.10, 0.14, 0.92), true)
		draw_rect(Rect2(100, 46, 150.0 * align, 6), SFPalette.SHIELD_BLUE, true)
		draw_rect(Rect2(100, 46, 150, 6), SFPalette.STEEL_DARK, false, 1.0)
		if flight.is_aligned():
			skin.text_c(self, cx, cy - tear_h * 0.5 - 16, "SIGNAL LOCKED", SFPalette.CYAN)
		else:
			skin.text_c(self, cx, cy - tear_h * 0.5 - 16, "ALIGN WITH THE OPENING", SFPalette.PAPER_DIM)
		_draw_play_ship(shake)
		# The crossing: the seam brightens and the frame washes out.
		if flight.entered:
			var k: float = clampf(flight.time / maxf(0.01, flight.target_seconds), 0.0, 1.0)
			draw_rect(Rect2(0, 0, VW, VH), Color(0.88, 0.96, 1.0, 0.10 + k * 0.35), true)

	# The recorded signal, drawn as a repeating waveform under the seam.
	for i in 116:
		var wx := 44.0 + float(i) * 4.6
		var amp: float = 3.5 + 6.0 * clampf(scene_time / 4.0, 0.0, 1.0)
		var wy := 330.0 + sin(float(i) * 0.30 + elapsed * 5.0) * amp
		draw_rect(Rect2(wx, wy, 2, 1), Color(0.36, 0.78, 0.74, 0.50), true)


# ---------------------------------------------------------------- scene F

## Home. Present-day Earth, matching the healthy opening: bright sky, soft
## clouds, sunbeams, green hills and trees, a real landing pad. VELA touches
## down, the hatch opens, Nick steps out, and the camera pushes in on his face
## before the closing card. There is no second planet in this sky: the ground is
## present-day Earth, so the establishing globe is gone.
func _draw_scene_home() -> void:
	var t: float = clampf(scene_time / 24.0, 0.0, 1.0)
	var zoom: float = _home_zoom(t)
	var focus := Vector2(250.0, 236.0)
	_draw_base = Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), focus - focus * zoom)
	draw_set_transform_matrix(_draw_base)
	_draw_home_wide(t)
	_draw_base = Transform2D.IDENTITY
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var portrait := _portrait_alpha(t)
	if portrait > 0.0:
		_draw_home_portrait(portrait, t)


## The camera holds the wide shot, then pushes smoothly toward Nick between
## 14.4 s and 19.2 s of the scene. Reduced motion shortens the push rather than
## removing the close-up: the ending still needs to land on his face.
func _home_zoom(t: float) -> float:
	var start: float = 0.60
	var end: float = 0.80
	if t <= start:
		return 1.0
	var k: float = clampf((t - start) / (end - start), 0.0, 1.0)
	var eased: float = k * k * (3.0 - 2.0 * k)
	var peak: float = 2.4 if reduced_motion else 3.3
	return lerpf(1.0, peak, eased)


func _portrait_alpha(t: float) -> float:
	var start: float = 0.70
	var end: float = 0.80
	if t <= start:
		return 0.0
	return clampf((t - start) / (end - start), 0.0, 1.0)


func _draw_home_wide(t: float) -> void:
	var pad_y := 268.0
	# Daylight sky: a clean vertical gradient, banded so it stays pixel-crisp.
	var band := 0
	while band < 16:
		var f := float(band) / 15.0
		draw_rect(Rect2(0, band * 15, VW, 16), SFPalette.SKY_DEEP.lerp(SFPalette.SKY, f), true)
		band += 1
	# The sun, high and warm, with soft rays.
	draw_circle(Vector2(516, 52), 22.0, Color(1.0, 0.96, 0.78, 0.95))
	draw_circle(Vector2(516, 52), 30.0, Color(1.0, 0.94, 0.70, 0.20))
	for ray in 9:
		var ang := -3.0 + float(ray) * 0.30
		var reach: float = 90.0 + float(ray % 3) * 26.0
		for s in 10:
			var p := Vector2(516, 52) + Vector2(cos(ang), sin(ang)) * (26.0 + reach * float(s) / 10.0)
			draw_rect(Rect2(round(p.x), round(p.y), 2, 2), Color(1.0, 0.96, 0.80, 0.16 * (1.0 - float(s) / 10.0)), true)

	# Soft white clouds, drifting slowly.
	for i in 7:
		var cxx := fmod(float(i) * 97.0 + elapsed * 3.0, float(VW + 120)) - 60.0
		var cyy := 46.0 + float((i * 37) % 84)
		_draw_cloud(Vector2(cxx, cyy), 0.8 + float(i % 3) * 0.35, 0.85)

	# Ground, painted edge to edge before anything stands on it. The sky's last
	# band ends at y 240, so the ground base starts above that: an unpainted seam
	# between the two would read as a black strip along the horizon.
	draw_rect(Rect2(0, 206, VW, VH - 206), SFPalette.GRASS_DARK, true)
	# Distant hills, then the near meadow they sit behind.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 238), Vector2(96, 208), Vector2(196, 230),
		Vector2(288, 200), Vector2(408, 228), Vector2(VW, 204),
		Vector2(VW, 300), Vector2(0, 300),
	]), SFPalette.GRASS_DARK.darkened(0.16))
	draw_rect(Rect2(0, pad_y - 8, VW, VH - pad_y + 8), SFPalette.GRASS, true)
	draw_rect(Rect2(0, pad_y - 8, VW, 3), SFPalette.GRASS_LIGHT, true)
	for i in 12:
		var tx := 16.0 + float(i) * 58.0
		if tx > 150.0 and tx < 372.0:
			continue
		_draw_home_tree(Vector2(tx, pad_y - 6.0), 0.72 + float(i % 3) * 0.16)

	# The landing pad, seen at a shallow angle: concentric ellipses rather than a
	# flat disc, so it sits in the meadow instead of on top of it.
	var pad_c := Vector2(250, pad_y + 12)
	_draw_ellipse(pad_c, 96.0, 30.0, SFPalette.CONCRETE_DARK)
	_draw_ellipse(pad_c, 90.0, 27.0, SFPalette.CONCRETE_MID)
	_draw_ellipse(pad_c, 58.0, 17.0, SFPalette.CONCRETE)
	for marker in 8:
		var ang := float(marker) / 8.0 * TAU
		var p := pad_c + Vector2(cos(ang) * 74.0, sin(ang) * 22.0)
		draw_rect(Rect2(round(p.x) - 2, round(p.y) - 1, 4, 2), SFPalette.WARM_DARK, true)
	for light in 7:
		var ang2 := float(light) / 7.0 * TAU
		var lp := pad_c + Vector2(cos(ang2) * 92.0, sin(ang2) * 28.0)
		draw_rect(Rect2(round(lp.x), round(lp.y), 3, 3), SFPalette.GOLD, true)

	# VELA, gear down, descending and then settled on the near half of the pad.
	# The dust is gentle: this is a landing, not a crash.
	var rest_y: float = pad_c.y - 34.0
	var descend: float = clampf(t / 0.20, 0.0, 1.0)
	var eased: float = descend * descend * (3.0 - 2.0 * descend)
	var settled: bool = t > 0.20
	var ship_y: float = rest_y if settled else lerpf(70.0, rest_y, eased)
	if settled:
		var dust: float = clampf((t - 0.20) / 0.10, 0.0, 1.0)
		for i in 16:
			var ang := float(i) / 16.0 * PI
			var r: float = 22.0 + dust * 56.0
			var p := Vector2(250 + cos(ang + PI) * r, rest_y + 16.0 + sin(ang) * 6.0)
			draw_circle(p, 4.0 + dust * 3.0, Color(0.86, 0.82, 0.70, (1.0 - dust) * 0.45))
	_draw_ship(Vector2(250, ship_y), 1.05, -0.03, 0.55 if not settled else 0.12, true)

	# Hatch opening and Nick stepping out: from a third of the way in. He walks
	# forward and left, clear of the hull, and stops in the open on the pad.
	if t > 0.28:
		var walk: float = clampf((t - 0.28) / 0.14, 0.0, 1.0)
		var hatch := Vector2(212, ship_y + 2.0)
		draw_rect(Rect2(hatch.x - 7, hatch.y - 13, 14, 13), Color(0.06, 0.09, 0.11, 0.95), true)
		draw_rect(Rect2(hatch.x - 6, hatch.y - 12, 12, 12), Color(0.28, 0.40, 0.44, 0.95), true)
		draw_rect(Rect2(hatch.x - 5, hatch.y - 17, 10, 5), Color(0.46, 0.60, 0.64, 0.95 * walk), true)
		var nick_x: float = lerpf(hatch.x - 3.0, 180.0, walk)
		var nick_y: float = rest_y + 18.0
		# A soft contact shadow so he stands on the pad rather than floating.
		draw_circle(Vector2(nick_x, nick_y), 7.0, Color(0.10, 0.16, 0.10, 0.30))
		var nick_tex: Texture2D = skin.sprites.get("nick_standing", null)
		if nick_tex != null:
			var nick_size := Vector2(28, 36)
			draw_texture_rect(nick_tex, Rect2(nick_x - nick_size.x * 0.5, nick_y - nick_size.y + 1.0, nick_size.x, nick_size.y), false)
		else:
			draw_rect(Rect2(nick_x - 6, nick_y - 26, 12, 26), SFPalette.WARM, true)
		# A wave once he is clear of the hull.
		if walk >= 1.0:
			var wave: float = sin(elapsed * 6.0) * 2.0
			draw_rect(Rect2(nick_x + 9, nick_y - 32 + wave, 3, 9), SFPalette.WARM, true)

	# Mission Control: a dish on the ridge, reacquiring the signal.
	var mast := Vector2(78, pad_y - 6)
	draw_rect(Rect2(mast.x - 1, mast.y - 66, 3, 66), SFPalette.STEEL_DARK, true)
	var dish_y := mast.y - 66.0
	for i in 5:
		var w := 10.0 + float(i) * 6.0
		draw_rect(Rect2(mast.x - w * 0.5, dish_y + float(i) * 2.0, w, 2), SFPalette.STEEL_MID, true)
	var pulse_cycle := fmod(elapsed * 0.55, 1.0)
	if pulse_cycle < 0.5:
		var rr: float = 20.0 + pulse_cycle * 160.0
		for i in 26:
			var ang := float(i) / 26.0 * TAU
			draw_rect(Rect2(round(mast.x + cos(ang) * rr), round(dish_y + sin(ang) * rr * 0.55), 1, 1),
				Color(0.30, 0.80, 0.75, 0.5 * (1.0 - pulse_cycle / 0.5)), true)

	# The archive transfer: packets rising from the ship to the dish, as many as
	# memories the run actually recorded.
	var memories: int = mini(8, int(report.get("memory_count", 0)))
	var shown := int(clampf((t - 0.36) / 0.30, 0.0, 1.0) * float(memories))
	for i in 8:
		if i >= shown:
			continue
		var phase := fmod(elapsed * 0.5 + float(i) * 0.12, 1.0)
		var p := Vector2(250, ship_y - 24).lerp(Vector2(78, dish_y + 20), phase)
		p.y -= sin(phase * PI) * 28.0
		draw_rect(Rect2(round(p.x), round(p.y), 3, 3), Color(0.30, 0.85, 0.80, 0.8), true)

	# Communities receiving the record: a small science campus on the right ridge,
	# its windows lighting one by one as the archive arrives.
	for i in 7:
		var bx := 452.0 + float(i) * 22.0
		var bh := 12.0 + float((i * 29) % 16)
		draw_rect(Rect2(bx, 236.0 - bh, 15, bh), SFPalette.WARM.darkened(0.20), true)
		draw_rect(Rect2(bx, 236.0 - bh, 15, 1), SFPalette.WARM, true)
		if i < shown:
			draw_rect(Rect2(bx + 3, 236.0 - bh + 4, 2, 2), SFPalette.GOLD, true)
			draw_rect(Rect2(bx + 9, 236.0 - bh + 8, 2, 2), SFPalette.GOLD, true)
	# Ground haze, warm and low, fading in over a few bands so it has no edge.
	for h in 5:
		draw_rect(Rect2(0, pad_y + 20.0 + float(h) * 9.0, VW, 10.0),
			Color(0.55, 0.72, 0.45, 0.035 * float(h + 1)), true)


## A filled ellipse, built from single-pixel horizontal spans on integer rows so
## the edge stays crisp and there is no fractional banding at the base
## resolution. Used for the landing pad, which is drawn in perspective.
func _draw_ellipse(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var cy: int = int(round(center.y))
	var half_h: int = maxi(1, int(round(radius_y)))
	for dy in range(-half_h, half_h):
		# Sample at the middle of the pixel row, so the ellipse is symmetric.
		var f: float = (float(dy) + 0.5) / float(half_h)
		if absf(f) >= 1.0:
			continue
		var half_w: float = radius_x * sqrt(1.0 - f * f)
		draw_rect(Rect2(round(center.x - half_w), float(cy + dy), round(half_w * 2.0), 1.0), color, true)


func _draw_cloud(pos: Vector2, size: float, alpha: float) -> void:
	var c := Color(1.0, 1.0, 0.99, alpha)
	draw_circle(pos, 11.0 * size, c)
	draw_circle(pos + Vector2(12.0, 2.0) * size, 8.0 * size, c)
	draw_circle(pos + Vector2(-12.0, 3.0) * size, 7.0 * size, c)
	draw_circle(pos + Vector2(3.0, -6.0) * size, 7.0 * size, c)


func _draw_home_tree(ground: Vector2, size: float) -> void:
	draw_rect(Rect2(ground.x - 2, ground.y - 20 * size, 4, 20 * size), SFPalette.BARK, true)
	draw_rect(Rect2(ground.x - 2, ground.y - 20 * size, 1, 20 * size), SFPalette.BARK_DARK, true)
	draw_circle(ground + Vector2(0, -26.0 * size), 11.0 * size, SFPalette.LEAF_DARK)
	draw_circle(ground + Vector2(-4.0 * size, -30.0 * size), 8.0 * size, SFPalette.LEAF)
	draw_circle(ground + Vector2(5.0 * size, -31.0 * size), 7.0 * size, SFPalette.LEAF_LIGHT)


## The close-up: Nick, helmet open, laughing. Sun behind him, the pad blurred out
## of focus by a warm wash, and the closing line underneath.
func _draw_home_portrait(alpha: float, t: float) -> void:
	var face_c := Vector2(VW * 0.5, 148.0)
	draw_rect(Rect2(0, 0, VW, VH), Color(0.05, 0.09, 0.09, alpha), true)
	# The meadow behind him, thrown out of focus: warm green bands, a suggestion
	# of sky at the top, and no hard edges that would compete with the face.
	var band := 0
	while band < 18:
		var f := float(band) / 17.0
		var c: Color = SFPalette.SKY.lerp(SFPalette.GRASS_DARK, clampf(f * 1.7, 0.0, 1.0))
		c = c.lerp(Color(1.0, 0.96, 0.82), 0.10)
		draw_rect(Rect2(0, band * 20, VW, 21), Color(c.r, c.g, c.b, alpha), true)
		band += 1
	# Soft bokeh: warm discs, not readable shapes.
	var bokeh := [
		[Vector2(96, 108), 22.0], [Vector2(534, 92), 26.0], [Vector2(160, 220), 16.0],
		[Vector2(486, 236), 20.0], [Vector2(64, 44), 14.0], [Vector2(590, 190), 17.0],
	]
	for entry in bokeh:
		var b: Array = entry
		var pos: Vector2 = b[0]
		var r: float = float(b[1])
		draw_circle(pos, r, Color(1.0, 0.98, 0.86, 0.10 * alpha))
		draw_circle(pos, r * 0.6, Color(1.0, 0.98, 0.90, 0.12 * alpha))
	# Sunbeams from the upper right.
	for ray in 7:
		var ang := 0.9 + float(ray) * 0.14
		for s in 12:
			var p := Vector2(560, 20) + Vector2(cos(ang), sin(ang)) * (24.0 + float(s) * 26.0)
			draw_rect(Rect2(round(p.x), round(p.y), 3, 3),
				Color(1.0, 0.97, 0.82, alpha * 0.12 * (1.0 - float(s) / 12.0)), true)
	# The face, framed so nothing important is clipped by the header or the
	# subtitle box.
	var tex: Texture2D = skin.sprites.get("nick_portrait", null)
	var breathe: float = 1.0 + sin(elapsed * 1.6) * 0.006
	var zoom_in: float = 3.4 * breathe
	if tex != null:
		var size := Vector2(72, 72) * zoom_in
		draw_texture_rect(tex, Rect2(face_c.x - size.x * 0.5, face_c.y - size.y * 0.5, size.x, size.y),
			false, Color(1, 1, 1, alpha))
	else:
		draw_circle(face_c, 90.0, Color(SFPalette.SKIN.r, SFPalette.SKIN.g, SFPalette.SKIN.b, alpha))
	# His name, under the face, once the close-up has settled.
	if t > 0.84:
		var name_alpha: float = clampf((t - 0.84) / 0.05, 0.0, 1.0) * alpha
		skin.text_c(self, VW * 0.5, 262, "NICK", Color(SFPalette.PAPER.r, SFPalette.PAPER.g, SFPalette.PAPER.b, name_alpha))
		skin.text_c(self, VW * 0.5, 276, "HOME", Color(SFPalette.GOLD.r, SFPalette.GOLD.g, SFPalette.GOLD.b, name_alpha))
	# A soft vignette so the face carries the frame.
	for i in 8:
		var inset: float = float(i) * 5.0
		draw_rect(Rect2(inset, inset, VW - inset * 2, 4), Color(0, 0, 0, 0.05 * alpha), true)
		draw_rect(Rect2(inset, VH - inset - 4, VW - inset * 2, 4), Color(0, 0, 0, 0.05 * alpha), true)
		draw_rect(Rect2(inset, inset, 4, VH - inset * 2), Color(0, 0, 0, 0.05 * alpha), true)
		draw_rect(Rect2(VW - inset - 4, inset, 4, VH - inset * 2), Color(0, 0, 0, 0.05 * alpha), true)


# ---------------------------------------------------------------- final card

func _draw_final_message() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var lines: Array = final_message.get("lines", []) as Array
	# A slow sunrise behind the words, then nothing else.
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


# ---------------------------------------------------------------- shared art

## Screen shake for the launch and the debris lane. Never fires under the
## reduced-motion setting, and never moves the HUD: only the scene art calls it.
func _shake_vector() -> Vector2:
	if reduced_motion or _shake_energy <= 0.0:
		return Vector2.ZERO
	var amount: float = _shake_energy * 3.2
	return Vector2(sin(elapsed * 47.0) * amount, cos(elapsed * 41.0) * amount * 0.7)


## Draws VELA with its texture, in the direction it is travelling. `pos` is the
## sprite centre; `rotation` is applied about that centre, so the nose leads and
## the exhaust trails.
func _draw_ship(pos: Vector2, ship_scale: float, tilt: float, thrust: float, gear: bool = false) -> void:
	var key := "vela_ship_gear" if gear else "vela_ship"
	var tex: Texture2D = skin.sprites.get(key, skin.sprites.get("vela_ship", null))
	draw_set_transform_matrix(_draw_base * _local_transform(pos, tilt, ship_scale))
	if thrust > 0.0:
		_draw_exhaust(thrust)
	if tex != null:
		var size := tex.get_size()
		draw_texture(tex, -size * 0.5)
	else:
		draw_rect(Rect2(-30, -8, 60, 16), SFPalette.STEEL, true)
	draw_set_transform_matrix(_draw_base)


## Rotation + uniform scale about `origin`, as a matrix. Built from the basic
## two-axis constructor so it stays valid on Godot 4.0.
func _local_transform(origin: Vector2, tilt: float, uniform_scale: float) -> Transform2D:
	var c: float = cos(tilt) * uniform_scale
	var s: float = sin(tilt) * uniform_scale
	return Transform2D(Vector2(c, s), Vector2(-s, c), origin)


## Three layered flames off the left of the hull, flickering on the clock. Drawn
## in the ship's local space, so a tilted ship trails its flame correctly.
func _draw_exhaust(thrust: float) -> void:
	var flicker: float = 1.0 + sin(elapsed * 37.0) * 0.10 + sin(elapsed * 61.0) * 0.06
	var layers := [
		[34.0, 9.0, Color(1.0, 0.52, 0.20, 0.70)],
		[25.0, 6.4, Color(1.0, 0.78, 0.32, 0.88)],
		[15.0, 3.6, Color(0.86, 0.98, 1.0, 0.95)],
	]
	for i in 3:
		var spec: Array = layers[i]
		var flame: float = float(spec[0]) * thrust * flicker
		var w: float = float(spec[1])
		var c: Color = spec[2]
		draw_rect(Rect2(-36.0 - flame, -w * 0.5, flame, w), c, true)
	# A bright core right at the nozzle mouth.
	draw_rect(Rect2(-38.0, -2.0, 6.0, 4.0), Color(0.92, 0.99, 1.0, 0.95), true)


## Places the ship so its landing gear rests on `ground`.
func _draw_ship_grounded(ground: Vector2, ship_scale: float, thrust: float, gear: bool) -> void:
	var centre := Vector2(ground.x, ground.y - 14.0 * ship_scale)
	_draw_ship(centre, ship_scale, 0.0, thrust, gear)


## Bill's maintenance shell. `power` fades the eyes and chest light out as the
## memory core is removed.
func _draw_bill_shell(ground: Vector2, power: float) -> void:
	draw_rect(Rect2(ground.x - 12, ground.y - 30, 24, 30), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x - 12, ground.y - 30, 5, 30), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 9, ground.y - 46, 18, 16), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 6, ground.y - 44, 12, 8), SFPalette.RUIN_BG, true)
	var eye := Color(0.36, 0.95, 0.90, 0.15 + 0.85 * power)
	draw_rect(Rect2(ground.x - 4, ground.y - 42, 2, 2), eye, true)
	draw_rect(Rect2(ground.x + 2, ground.y - 42, 2, 2), eye, true)
	draw_rect(Rect2(ground.x - 6, ground.y - 22, 12, 6), Color(0.20, 0.60, 0.55, 0.10 + 0.70 * power), true)
	# Arms, drawn folded.
	draw_rect(Rect2(ground.x - 18, ground.y - 26, 6, 16), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x + 12, ground.y - 26, 6, 16), SFPalette.STEEL_DARK, true)
