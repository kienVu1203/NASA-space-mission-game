extends Node2D
## The Phase 2 shield-defense encounter screen. Draws the arena, the robot, Nick,
## the shield, the projectiles, the telegraphs and the combat HUD; owns input
## and pause. It owns no campaign state: when the fight is won it reports one
## result and the controller awards the reward exactly once.
##
## Controls
##   MOUSE    rotate the shield (always active, no button held)
##   SPACE    counterattack, only when the charge meter above Nick is full
##   ESC      pause (resume, retry, main menu)
##
## The screen is deliberately node-light: everything is drawn in _draw() from
## data/star_fall/encounters.json, so the presentation can never disagree with
## the combat model about shield coverage or projectile sizes.

signal duel_finished(outcome: String)
signal duel_aborted

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFEncounter := preload("res://core/star_fall/sf_encounter.gd")
const SFShield := preload("res://core/star_fall/sf_shield.gd")
const SFMenu := preload("res://core/star_fall/sf_menu.gd")
const SFDialogue := preload("res://core/star_fall/sf_dialogue.gd")

const VW := 640
const VH := 360

enum State { FIGHT, VICTORY, DEFEAT, PAUSED }

var skin
var ui
var boss: Dictionary = {}
var encounter

var state: int = State.FIGHT
var finished: bool = false
var time: float = 0.0
var pause_menu
var pause_origin: int = State.FIGHT
var pause_index: int = 0

var effects: Array = []
var shake: float = 0.0
var strike_flash: float = 0.0
var intro_banner: float = 4.5
## Set by the controller while a dialogue is open over this screen. When true,
## the arena does not tick: no projectiles move, no damage lands, and no combat
## key is consumed, so the dialogue owns all input fairly.
var input_locked: bool = false

## The robot's draw scale. The spec asks for a large, threatening presence in
## the rear layer; this keeps it a backdrop rather than a small sprite.
const BOSS_SCALE := 1.32
var _shake_offset: Vector2 = Vector2.ZERO

var _cursor_canvas: Vector2 = Vector2(320.0, 360.0)
var _ready_chime_played: bool = false


func setup(skin_ref, ui_ref, boss_data: Dictionary, all_data) -> void:
	skin = skin_ref
	ui = ui_ref
	boss = boss_data
	encounter = SFEncounter.new()
	encounter.setup(boss, all_data)


func _ready() -> void:
	pause_menu = SFMenu.new()
	intro_banner = 6.0
	refresh_pause_menu()
	queue_redraw()


# ---------------------------------------------------------------- lifecycle

## Starts a fresh attempt. Used by the controller on entry, and by retry.
func begin_attempt() -> void:
	encounter.reset()
	state = State.FIGHT
	finished = false
	effects.clear()
	shake = 0.0
	strike_flash = 0.0
	intro_banner = 6.0
	_ready_chime_played = false
	encounter.begin()
	queue_redraw()


func is_fighting() -> bool:
	return state == State.FIGHT and not input_locked and encounter.is_fighting()


func retry() -> void:
	# A retry resets only encounter-local state. Campaign flags, inventory,
	# materials and previously earned components are untouched.
	skin.audio.sfx_back()
	begin_attempt()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	# A dialogue owns every key while it is open over the arena. Without this,
	# the Space that advances Bill's briefing would also fire a counterattack.
	if input_locked:
		return
	if state == State.PAUSED:
		_pause_key(key_event.keycode)
		get_viewport().set_input_as_handled()
		return
	match key_event.keycode:
		KEY_ESCAPE:
			if state == State.FIGHT:
				audio_pause()
			elif state == State.DEFEAT:
				audio_pause()
			elif state == State.VICTORY:
				# The fight is already won; Esc must not skip the award, so it
				# simply opens the same continue path as Enter.
				_confirm_victory()
				get_viewport().set_input_as_handled()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E:
			match state:
				State.FIGHT:
					_try_counterattack()
				State.VICTORY:
					_confirm_victory()
				State.DEFEAT:
					retry()
		KEY_R:
			if state == State.DEFEAT:
				retry()


func _notification(what: int) -> void:
	# Losing focus mid-fight must not keep simulating, and must not leave the
	# player holding a key that lands invisibly.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		Input.action_release("move_up")
		Input.action_release("move_down")
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_release("run")
		# Losing focus mid-fight pauses, so attacks cannot land while the window
		# is in the background. During a briefing the dialogue already freezes the
		# arena, and opening a pause menu underneath it would strand the player.
		if state == State.FIGHT and not input_locked:
			_open_pause()


func audio_pause() -> void:
	skin.audio.sfx_back()
	_open_pause()


func _try_counterattack() -> void:
	if encounter.counterattack():
		skin.audio.sfx_counterattack()
		# The launch effect travels from Nick toward the robot.
		effects.append({
			"kind": "counter_launch",
			"from": encounter.nick_position,
			"to": encounter.boss_impact_point(),
			"t": 0.0,
			"life": float(encounter.combat.get("counterattack_lock_seconds", 0.55)) * 0.5,
		})
		shake = maxf(shake, 1.5)
		queue_redraw()
	else:
		skin.audio.sfx_denied()


func _confirm_victory() -> void:
	if finished:
		return
	finished = true
	skin.audio.sfx_confirm()
	duel_finished.emit("victory")


# ---------------------------------------------------------------- pause

func _open_pause() -> void:
	pause_origin = state
	state = State.PAUSED
	pause_menu.index = 0
	queue_redraw()


func _close_pause() -> void:
	state = pause_origin
	queue_redraw()


func refresh_pause_menu() -> void:
	if pause_menu == null:
		return
	pause_menu.set_items([
		{"id": "resume", "label": "RESUME", "enabled": true},
		{"id": "retry", "label": "RESTART FIGHT", "enabled": true},
		{"id": "menu", "label": "RETURN TO MAIN MENU", "enabled": true},
	], "resume")


func _pause_key(key: int) -> void:
	match key:
		KEY_UP, KEY_W:
			pause_menu.move_enabled(-1)
			skin.audio.sfx_select()
		KEY_DOWN, KEY_S:
			pause_menu.move_enabled(1)
			skin.audio.sfx_select()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			_activate_pause_item()
		KEY_ESCAPE:
			skin.audio.sfx_back()
			_close_pause()
	queue_redraw()


func _activate_pause_item() -> void:
	match pause_menu.current_id():
		"resume":
			skin.audio.sfx_blip()
			_close_pause()
		"retry":
			state = pause_origin
			retry()
		"menu":
			skin.audio.sfx_back()
			duel_aborted.emit()
	queue_redraw()


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	time += delta
	# A long frame (window drag, breakpoint) must not teleport projectiles past
	# the shield; the swept collision handles it, but capping keeps timers sane.
	var dt: float = minf(delta, 0.1)

	if input_locked:
		# A dialogue is up over the frozen arena. Only presentation time advances.
		ui.tick(dt)
		_update_effects(dt)
		queue_redraw()
		return

	if state == State.FIGHT:
		_update_cursor()
	_advance(dt)

	_update_effects(dt)
	shake = maxf(0.0, shake - dt * 6.0)
	strike_flash = maxf(0.0, strike_flash - dt * 3.0)
	ui.tick(dt)
	queue_redraw()


## Advances the arena by one step and applies everything it reported. The
## screen's `_process` and the headless tests both go through this one path, so
## a test exercises the same lifecycle the player does.
func _advance(dt: float) -> void:
	if state == State.PAUSED:
		return
	var events: Array = encounter.tick(dt)
	_consume(events)
	_sync_state_from_model()
	if state == State.FIGHT:
		intro_banner = maxf(0.0, intro_banner - dt)


## Mirrors the encounter's terminal phases onto this screen's presentation
## state. The 'victory'/'defeat' events do the same thing during normal play;
## this also covers a phase set directly (tests, a restored encounter), so the
## overlay can never disagree with the rules about whether the fight is over.
func _sync_state_from_model() -> void:
	if state == State.PAUSED:
		return
	if encounter.model.phase == encounter.model.PHASE_VICTORY and state != State.VICTORY:
		state = State.VICTORY
	elif encounter.model.phase == encounter.model.PHASE_DEFEAT and state != State.DEFEAT:
		state = State.DEFEAT


## Test entry point: advances the arena in fixed steps without a render loop.
## Returns nothing; the screen's state and the encounter's model are the result.
func advance_for(seconds: float, step: float = 0.05) -> void:
	var remaining: float = maxf(0.0, seconds)
	while remaining > 0.0001:
		var dt: float = minf(step, remaining)
		_advance(dt)
		remaining -= dt


## Reads the phase transitions the encounter reported and updates this screen.
func _consume(events: Array) -> void:
	for e in events:
		var event: Dictionary = e
		match String(event.get("kind", "")):
			"block":
				skin.audio.sfx_shield_block()
				_effect("spark", event.get("point", Vector2.ZERO), "f2a05a", 0.22)
			"hit":
				skin.audio.sfx_player_hurt()
				shake = maxf(shake, 3.0)
				_effect("hurt", event.get("point", Vector2.ZERO), "d9534f", 0.4)
			"absorb":
				skin.audio.sfx_shield_absorb()
				_effect("absorb", event.get("point", Vector2.ZERO), "7ef2c8", 0.5)
				var gained := int(event.get("gained", 0))
				if gained > 0:
					_effect("charge_text", Vector2(encounter.nick_position.x, encounter.nick_position.y - 46), "7ef2c8", 0.7, "+%d" % gained)
			"counter_strike":
				skin.audio.sfx_counter_hit()
				strike_flash = 1.0
				shake = maxf(shake, 5.0)
				_effect("burst", encounter.boss_impact_point(), "e5c04a", 0.55)
			"victory":
				skin.audio.sfx_boss_down()
				state = State.VICTORY
				_effect("burst", encounter.boss_impact_point(), "e5c04a", 0.9)
			"defeat":
				skin.audio.sfx_defeat()
				state = State.DEFEAT
	# Charge-full chime plays once per fill, not once per frame.
	if encounter.model.charge_full() and not _ready_chime_played:
		_ready_chime_played = true
		skin.audio.sfx_charge_ready()
	elif not encounter.model.charge_full():
		_ready_chime_played = false


func _effect(kind: String, at: Vector2, color_hex: String, life: float, text: String = "") -> void:
	effects.append({
		"kind": kind,
		"at": at,
		"color": color_hex,
		"t": 0.0,
		"life": life,
		"text": text,
	})


func _update_effects(dt: float) -> void:
	var keep: Array = []
	for e in effects:
		var entry: Dictionary = e
		entry["t"] = float(entry.get("t", 0.0)) + dt
		if float(entry["t"]) < float(entry.get("life", 0.2)):
			keep.append(entry)
	effects = keep


## Converts the current mouse position into arena canvas space and aims.
## `get_global_mouse_position()` runs the point through the canvas transform,
## which is where window scaling and letterboxing are applied, so raw window
## pixels never reach the shield.
func _update_cursor() -> void:
	var local := get_global_mouse_position()
	_cursor_canvas = local
	encounter.aim(local)


## Test and accessibility entry point: aim without a mouse device.
func set_cursor_canvas(p: Vector2) -> void:
	_cursor_canvas = p
	encounter.aim(p)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var offset := Vector2.ZERO
	if shake > 0.0:
		offset = Vector2(round(sin(time * 91.0) * shake), round(cos(time * 77.0) * shake * 0.6))
	_shake_offset = offset
	draw_set_transform(offset, 0.0, Vector2.ONE)

	_draw_arena()
	_draw_boss()
	_draw_emitters()
	_draw_telegraphs()
	_draw_projectiles()
	_draw_nick()
	_draw_shield()
	_draw_effects()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_shake_offset = Vector2.ZERO

	_draw_hud()
	_draw_state_overlay()
	ui.toast(self)


# ---------------------------------------------------------------- arena

func _visual_color(key: String, fallback: Color) -> Color:
	var v := String(boss.get("visual", {}).get(key, ""))
	if v == "":
		return fallback
	return Color(v)


func _draw_arena() -> void:
	var dark := _visual_color("shell", SFPalette.RUIN_BG)
	var silhouette := String(boss.get("visual", {}).get("silhouette", "industrial"))
	# Back wall.
	draw_rect(Rect2(0, 0, VW, VH), dark.darkened(0.45), true)

	if silhouette == "marine":
		_draw_coast_arena(dark)
	else:
		_draw_city_arena(dark)

	# Floor plane: everything below the horizon reads as ground.
	var ground_y: float = float(encounter.arena_config.get("ground_y", 300.0))
	draw_rect(Rect2(0, ground_y, VW, VH - ground_y), dark.darkened(0.2), true)
	draw_rect(Rect2(0, ground_y, VW, 2), _visual_color("armor", SFPalette.STEEL_DARK).darkened(0.35), true)
	# Perspective-free floor lines, spaced tighter toward the back.
	var y := ground_y + 6.0
	var step := 3.5
	while y < VH:
		draw_rect(Rect2(0, round(y), VW, 1), dark.darkened(0.05), true)
		y += step
		step += 0.8

	# Contact shade under the robot, so it sits in the room instead of floating.
	var shadow_w := 224.0
	draw_rect(Rect2(VW * 0.5 - shadow_w * 0.5, ground_y - 20.0, shadow_w, 22.0), Color(0, 0, 0, 0.22), true)


func _draw_city_arena(dark: Color) -> void:
	# Ruined street: broken facades, a distant skyline, waste in the gutters.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3311
	# Sky band behind the buildings.
	draw_rect(Rect2(0, 0, VW, 62), dark.darkened(0.55), true)
	for i in 24:
		var x := float(i) * 28.0
		var h := 18.0 + float((i * 37) % 40)
		draw_rect(Rect2(x, 62 - h, 24, h), dark.darkened(0.35), true)
		draw_rect(Rect2(x, 62 - h, 24, 1), dark.lightened(0.10), true)
		# A few dead windows.
		for wy in range(4, int(h) - 4, 7):
			if (i + wy) % 3 == 0:
				draw_rect(Rect2(x + 6, 62 - h + wy, 3, 3), dark.darkened(0.15), true)
	# Side facades framing the arena.
	for side in [0, 1]:
		var fx: float = 0.0 if side == 0 else 540.0
		draw_rect(Rect2(fx, 62, 100, 238), dark.darkened(0.28), true)
		for row in 6:
			for col in 2:
				var wx: float = fx + 12.0 + float(col) * 34.0
				var wy: float = 78.0 + float(row) * 34.0
				var lit: bool = rng.randf() < 0.18
				draw_rect(Rect2(wx, wy, 22, 20), SFPalette.INK if not lit else SFPalette.CYAN_DARK, true)
				draw_rect(Rect2(wx, wy, 22, 1), dark.lightened(0.06), true)
	# Ground clutter: boards, coils, cable runs, so the floor is readable.
	for i in 40:
		var px := rng.randf_range(10.0, VW - 10.0)
		var py := rng.randf_range(286.0, 356.0)
		var w := rng.randf_range(2.0, 7.0)
		draw_rect(Rect2(round(px), round(py), round(w), 1), dark.lightened(0.10), true)
	# A cable running into each side relay.
	draw_rect(Rect2(0, 232, 96, 2), dark.lightened(0.05), true)
	draw_rect(Rect2(544, 232, 96, 2), dark.lightened(0.05), true)


func _draw_coast_arena(dark: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9127
	# Overcast sky, then water stain, then the facility deck.
	draw_rect(Rect2(0, 0, VW, 90), dark.darkened(0.5), true)
	var band := 0
	while band < 8:
		var t := float(band) / 8.0
		draw_rect(Rect2(0, 90 + band * 8, VW, 8), dark.darkened(0.5).lerp(dark.darkened(0.2), t), true)
		band += 1
	# Polluted tide line: a violet stain with a bright rim, deliberately hideous.
	draw_rect(Rect2(0, 138, VW, 34), SFPalette.VIOLET.darkened(0.45), true)
	for i in 90:
		var sx := rng.randf_range(0.0, VW)
		var sy := rng.randf_range(140.0, 170.0)
		var c: Color = SFPalette.VIOLET_LIGHT if i % 4 == 0 else SFPalette.VIOLET
		c.a = 0.5
		draw_rect(Rect2(round(sx), round(sy), 2, 1), c, true)
	# Debris in the tide line.
	for i in 26:
		var dx := rng.randf_range(0.0, VW)
		var dy := rng.randf_range(142.0, 168.0)
		draw_rect(Rect2(round(dx), round(dy), rng.randi_range(2, 5), 1), dark.darkened(0.1), true)
	# Facility deck edges and pipe runs.
	draw_rect(Rect2(0, 172, 112, 128), dark.darkened(0.3), true)
	draw_rect(Rect2(528, 172, 112, 128), dark.darkened(0.3), true)
	for i in 4:
		draw_rect(Rect2(0, 186 + i * 30, 106, 3), _visual_color("armor", SFPalette.STEEL_DARK).darkened(0.3), true)
		draw_rect(Rect2(534, 186 + i * 30, 106, 3), _visual_color("armor", SFPalette.STEEL_DARK).darkened(0.3), true)
	# Pooled water reflecting the boss glow.
	var glow := _visual_color("glow", SFPalette.CYAN)
	for i in 60:
		var px := rng.randf_range(150.0, 490.0)
		var py := rng.randf_range(300.0, 352.0)
		var c2 := glow
		c2.a = rng.randf_range(0.04, 0.14)
		draw_rect(Rect2(round(px), round(py), rng.randi_range(2, 6), 1), c2, true)


# ---------------------------------------------------------------- boss

func _draw_boss() -> void:
	var ground_y: float = float(encounter.arena_config.get("ground_y", 300.0))
	var bob: float = sin(time * 1.1) * 1.5
	var base_y := ground_y - 14.0 + bob
	var silhouette := String(boss.get("visual", {}).get("silhouette", "industrial"))

	# The whole robot is behind Nick: it is backdrop, never an obstacle, so no
	# collision geometry is ever created for it. It is drawn around its ground
	# point so scaling it never moves its feet off the floor.
	draw_set_transform(_shake_offset + Vector2(VW * 0.5, base_y), 0.0, Vector2(BOSS_SCALE, BOSS_SCALE))
	if silhouette == "marine":
		_draw_toxic_tide(0.0, 0.0)
	else:
		_draw_scrap_king(0.0, 0.0)
	draw_set_transform(_shake_offset, 0.0, Vector2.ONE)

	# Damage flash over the chassis when a counterattack lands.
	if strike_flash > 0.0:
		var a: float = clampf(strike_flash, 0.0, 1.0) * 0.5
		var flash_w := 216.0 * BOSS_SCALE
		var flash_h := 140.0 * BOSS_SCALE
		draw_rect(Rect2(VW * 0.5 - flash_w * 0.5, base_y - 132.0 * BOSS_SCALE, flash_w, flash_h), Color(1.0, 0.94, 0.78, a * 0.35), true)
	# The contact shadow belongs under the feet, and must not scale with the
	# chassis flash.
	draw_rect(Rect2(VW * 0.5 - 118.0, base_y - 6.0, 236.0, 10.0), Color(0, 0, 0, 0.18), true)


func _boss_alive_tint() -> float:
	# The eye dims as health falls, so the boss visibly weakens.
	return 0.35 + 0.65 * encounter.health_fraction()


func _emitter_glow_level(emitter_id: String) -> float:
	var t: Dictionary = encounter.telegraph_for_emitter(emitter_id)
	if t.is_empty():
		return 0.0
	var duration: float = maxf(0.001, float(t.get("duration", 1.0)))
	var elapsed: float = float(t.get("elapsed", 0.0))
	return clampf(elapsed / duration, 0.0, 1.0)


func _draw_scrap_king(cx: float, base_y: float) -> void:
	var shell := _visual_color("shell", Color("2f3a38"))
	var armor := _visual_color("armor", SFPalette.STEEL_DARK)
	var light := _visual_color("armor_light", SFPalette.STEEL_MID)
	var glow := _visual_color("glow", SFPalette.RUST_LIGHT)
	var eye := _visual_color("eye", SFPalette.GOLD)

	# Legs: stubby, heavy, planted wide.
	for side in [-1.0, 1.0]:
		var lx: float = cx + side * 62.0
		draw_rect(Rect2(lx - 16, base_y - 44, 32, 44), shell, true)
		draw_rect(Rect2(lx - 20, base_y - 12, 40, 12), armor.darkened(0.25), true)
		draw_rect(Rect2(lx - 16, base_y - 44, 6, 32), light.darkened(0.2), true)
		# Piston.
		draw_rect(Rect2(lx - 3, base_y - 40, 6, 26), armor, true)

	# Torso: a slab of welded scrap.
	draw_rect(Rect2(cx - 86, base_y - 118, 172, 76), shell, true)
	draw_rect(Rect2(cx - 86, base_y - 118, 172, 6), light.darkened(0.15), true)
	draw_rect(Rect2(cx - 86, base_y - 48, 172, 6), armor.darkened(0.35), true)
	# Irregular armour plates.
	for i in 7:
		var px: float = cx - 78.0 + float(i) * 23.0
		var ph: float = 18.0 + float((i * 13) % 22)
		draw_rect(Rect2(px, base_y - 112.0 + float((i * 7) % 10), 19, ph), armor.darkened(0.12 + 0.06 * float(i % 3)), true)
		draw_rect(Rect2(px, base_y - 112.0 + float((i * 7) % 10), 19, 2), light.darkened(0.2), true)
	# Sorting arms, one raised on a telegraph.
	var armed_left := _emitter_glow_level("left") + _emitter_glow_level("top_left")
	var armed_right := _emitter_glow_level("right") + _emitter_glow_level("top_right")
	for side in [-1.0, 1.0]:
		var shoulder_x: float = cx + side * 88.0
		var raise_lvl: float = clampf(armed_left if side < 0.0 else armed_right, 0.0, 1.0)
		var arm_y: float = base_y - 108.0 - raise_lvl * 18.0
		draw_rect(Rect2(shoulder_x - 12, arm_y, 24, 26), armor, true)
		draw_rect(Rect2(shoulder_x - 8, arm_y + 24, 16, 34), shell.lightened(0.08), true)
		# Claw.
		draw_rect(Rect2(shoulder_x - 12, arm_y + 56, 10, 7), light.darkened(0.2), true)
		draw_rect(Rect2(shoulder_x + 2, arm_y + 56, 10, 7), light.darkened(0.2), true)
		# Magnet coil on the shoulder.
		draw_rect(Rect2(shoulder_x - 16, arm_y - 10, 32, 10), armor.darkened(0.3), true)
		draw_rect(Rect2(shoulder_x - 13, arm_y - 7, 26, 4), glow.darkened(0.2 + 0.4 * (1.0 - raise_lvl)), true)

	# Head: sensor cluster and a cracked screen.
	draw_rect(Rect2(cx - 30, base_y - 148, 60, 32), armor, true)
	draw_rect(Rect2(cx - 30, base_y - 148, 60, 3), light, true)
	draw_rect(Rect2(cx - 34, base_y - 142, 6, 20), shell, true)
	draw_rect(Rect2(cx + 28, base_y - 142, 6, 20), shell, true)
	# Eye slit.
	var tint := _boss_alive_tint()
	var eye_col := Color(eye.r, eye.g, eye.b, tint)
	draw_rect(Rect2(cx - 22, base_y - 138, 44, 8), SFPalette.INK, true)
	draw_rect(Rect2(cx - 19, base_y - 136, 16, 4), eye_col, true)
	draw_rect(Rect2(cx + 3, base_y - 136, 16, 4), eye_col, true)
	_px_glow(Vector2(cx - 11, base_y - 134), 10.0 + sin(time * 5.0) * 2.0, eye_col)
	_px_glow(Vector2(cx + 11, base_y - 134), 10.0 + sin(time * 5.0 + 1.6) * 2.0, eye_col)
	# Speaker grille.
	for i in 5:
		draw_rect(Rect2(cx - 16 + i * 7, base_y - 126, 4, 3), shell.lightened(0.12), true)
	# Damaged screens on the chest.
	draw_rect(Rect2(cx - 52, base_y - 100, 30, 22), SFPalette.INK, true)
	draw_rect(Rect2(cx - 50, base_y - 98, 26, 2), Color(glow.r, glow.g, glow.b, 0.55 * tint + 0.15), true)
	draw_rect(Rect2(cx - 50, base_y - 93, 16, 2), glow.darkened(0.3), true)
	draw_rect(Rect2(cx + 22, base_y - 100, 30, 22), SFPalette.INK, true)
	draw_rect(Rect2(cx + 24, base_y - 98, 20, 2), Color(glow.r, glow.g, glow.b, 0.35 * tint + 0.1), true)
	# Magnetic clamps and hanging cable.
	draw_rect(Rect2(cx - 60, base_y - 60, 120, 12), armor.darkened(0.4), true)
	for i in 6:
		draw_rect(Rect2(cx - 52 + i * 20, base_y - 58, 12, 8), SFPalette.INK, true)
		draw_rect(Rect2(cx - 52 + i * 20, base_y - 58, 12, 2), glow.darkened(0.35), true)
	# A cable dangling from the shoulder to the floor.
	var sway := sin(time * 1.7) * 3.0
	for i in 9:
		var t := float(i) / 8.0
		var cxp: float = cx + 100.0 + t * t * sway
		var cyp: float = base_y - 100.0 + t * 100.0
		draw_rect(Rect2(round(cxp), round(cyp), 2, 4), armor.darkened(0.2), true)


func _draw_toxic_tide(cx: float, base_y: float) -> void:
	var shell := _visual_color("shell", Color("1f3538"))
	var armor := _visual_color("armor", Color("3e6b70"))
	var light := _visual_color("armor_light", Color("6fa3a8"))
	var glow := _visual_color("glow", SFPalette.CYAN)
	var eye := _visual_color("eye", SFPalette.CYAN)
	var tint := _boss_alive_tint()

	# Splayed hydraulic base, unlike the Scrap King's planted legs.
	draw_rect(Rect2(cx - 96, base_y - 30, 192, 30), shell, true)
	draw_rect(Rect2(cx - 96, base_y - 30, 192, 4), light.darkened(0.2), true)
	for i in 5:
		draw_rect(Rect2(cx - 88 + i * 36, base_y - 24, 20, 22), armor.darkened(0.25), true)
		draw_rect(Rect2(cx - 88 + i * 36, base_y - 24, 20, 2), glow.darkened(0.55), true)

	# Vertical tank body: narrower and taller than the Scrap King.
	draw_rect(Rect2(cx - 56, base_y - 158, 112, 130), shell, true)
	# Tank bands.
	for i in 4:
		draw_rect(Rect2(cx - 56, base_y - 144 + i * 28, 112, 4), armor, true)
	# Corroded plating patches.
	for i in 9:
		var px: float = cx - 52.0 + float(i) * 12.0
		var py: float = base_y - 134.0 + float((i * 17) % 86)
		draw_rect(Rect2(px, py, 8, 6), SFPalette.RUST.darkened(0.25), true)
	# Central pressure gauge, alive.
	draw_rect(Rect2(cx - 24, base_y - 128, 48, 40), SFPalette.INK, true)
	draw_rect(Rect2(cx - 22, base_y - 126, 44, 2), Color(glow.r, glow.g, glow.b, tint * 0.7), true)
	# Rising fluid level inside the gauge.
	var fill: float = 30.0 * (0.35 + 0.65 * encounter.health_fraction())
	for i in int(fill / 3.0):
		draw_rect(Rect2(cx - 20, base_y - 92 - float(i) * 3.0, 40, 2), Color(glow.r, glow.g, glow.b, 0.16 + 0.02 * float(i)), true)
	# Head: a sensor cluster under a hood, with two pale eyes.
	draw_rect(Rect2(cx - 34, base_y - 186, 68, 30), armor, true)
	draw_rect(Rect2(cx - 34, base_y - 186, 68, 4), light, true)
	draw_rect(Rect2(cx - 40, base_y - 178, 8, 16), shell.lightened(0.1), true)
	draw_rect(Rect2(cx + 32, base_y - 178, 8, 16), shell.lightened(0.1), true)
	for side in [-1.0, 1.0]:
		var ex: float = cx + side * 13.0
		draw_rect(Rect2(ex - 7, base_y - 176, 14, 6), SFPalette.INK, true)
		var ec := Color(eye.r, eye.g, eye.b, tint)
		draw_rect(Rect2(ex - 5, base_y - 174, 10, 2), ec, true)
		_px_glow(Vector2(ex, base_y - 173), 9.0 + sin(time * 3.6 + side) * 2.0, ec)
	# Antenna mast, kept short enough that the encounter HUD never clips it.
	draw_rect(Rect2(cx + 22, base_y - 196, 2, 12), armor.darkened(0.2), true)
	_px_glow(Vector2(cx + 23, base_y - 197), 5.0 + sin(time * 6.0) * 1.5, Color(glow.r, glow.g, glow.b, 0.8))

	# Articulated arms: a continuous segmented boom, drawn as overlapping plates
	# rather than separated beads, so it reads as machinery and not as debris.
	for side in [-1.0, 1.0]:
		var shoulder_x: float = cx + side * 62.0
		var lvl: float = 0.0
		if side < 0.0:
			lvl = clampf(_emitter_glow_level("left_low") + _emitter_glow_level("left"), 0.0, 1.0)
		else:
			lvl = clampf(_emitter_glow_level("right_low") + _emitter_glow_level("right"), 0.0, 1.0)
		var swing: float = sin(time * 1.4 + side) * 2.0 + lvl * 9.0
		# Shoulder block.
		draw_rect(Rect2(shoulder_x - 12, base_y - 150, 24, 22), armor, true)
		draw_rect(Rect2(shoulder_x - 12, base_y - 150, 24, 2), light.darkened(0.15), true)
		draw_rect(Rect2(shoulder_x - 6, base_y - 142, 12, 6), glow.darkened(0.45 + 0.4 * (1.0 - lvl)), true)
		# Upper arm: short, thick, angled out.
		var elbow := Vector2(shoulder_x + side * 20.0 + swing, base_y - 118.0)
		var seg_a := Vector2(shoulder_x + side * 4.0, base_y - 132.0)
		draw_line(seg_a, elbow, armor, 11.0)
		draw_line(seg_a, elbow, light.darkened(0.35), 3.0)
		# Forearm: angles back in toward the nozzle, so the silhouette reads as
		# a jointed limb rather than a straight stick.
		var nozzle := Vector2(shoulder_x + side * 30.0 + swing, base_y - 84.0)
		draw_line(elbow, nozzle, armor.darkened(0.1), 9.0)
		draw_line(elbow, nozzle, glow.darkened(0.55), 2.0)
		# Elbow joint.
		draw_rect(Rect2(elbow.x - 6, elbow.y - 6, 12, 12), armor.lightened(0.08), true)
		draw_rect(Rect2(elbow.x - 3, elbow.y - 3, 6, 6), SFPalette.INK, true)
		# Nozzle housing.
		draw_rect(Rect2(nozzle.x - 8, nozzle.y - 5, 16, 12), armor.darkened(0.2), true)
		draw_rect(Rect2(nozzle.x - 8, nozzle.y - 5, 16, 2), light.darkened(0.25), true)
		draw_rect(Rect2(nozzle.x - 4, nozzle.y - 9, 8, 5), glow.darkened(0.25 + 0.5 * (1.0 - lvl)), true)

	# Outfall hose looping down to the floor, drawn as a continuous tube.
	var prev_hose := Vector2(cx + 84.0, base_y - 124.0)
	for i in 15:
		var t := float(i) / 14.0
		var hose := Vector2(cx + 84.0 + sin(t * PI) * 20.0, base_y - 124.0 + t * 124.0)
		draw_line(prev_hose, hose, armor.darkened(0.3), 6.0)
		draw_line(prev_hose, hose, light.darkened(0.5), 2.0)
		prev_hose = hose


# ---------------------------------------------------------------- emitters / telegraphs

func _draw_emitters() -> void:
	# Emitters sit at authored arena coordinates and are drawn unscaled, so the
	# warning rings line up exactly with where projectiles actually appear.
	for entry in boss.get("emitters", []) as Array:
		var emitter: Dictionary = entry
		var id := String(emitter.get("id", ""))
		var p := Vector2(float(emitter.get("x", 0.0)), float(emitter.get("y", 0.0)))
		# Off-screen emitters are drawn clamped to the frame as edge markers, so
		# the player can always see where an attack is coming from.
		var on_screen: bool = p.x >= 6.0 and p.x <= VW - 6.0 and p.y >= 6.0 and p.y <= VH - 6.0
		var draw_p := Vector2(clampf(p.x, 10.0, VW - 10.0), clampf(p.y, 34.0, VH - 14.0))
		var level := _emitter_glow_level(id)
		var glow := _visual_color("glow", SFPalette.CYAN)
		var base_col: Color = glow.darkened(0.55)
		if level > 0.0:
			var pulse: float = 0.5 + 0.5 * sin(time * 24.0)
			base_col = glow.lerp(SFPalette.PAPER, 0.25 + 0.35 * pulse)
			# Charge ring, growing as the projectile is about to launch.
			var r: float = 4.0 + level * 12.0
			_draw_ring(draw_p, r, Color(base_col.r, base_col.g, base_col.b, 0.35 + 0.4 * level))
			# Aim line from the emitter toward Nick, dim so it never hides a
			# projectile.
			var dir: Vector2 = (encounter.nick_position - draw_p)
			if dir.length_squared() > 1.0:
				dir = dir.normalized()
				var a_end: Vector2 = draw_p + dir * (58.0 + level * 26.0)
				draw_line(draw_p, a_end, Color(base_col.r, base_col.g, base_col.b, 0.18 + 0.22 * level), 1.0)
		if on_screen:
			# Machinery housing for emitters that sit inside the frame.
			draw_rect(Rect2(draw_p - Vector2(9, 9), Vector2(18, 18)), SFPalette.STEEL_DARK.darkened(0.25), true)
			draw_rect(Rect2(draw_p - Vector2(9, 9), Vector2(18, 2)), SFPalette.STEEL_MID.darkened(0.2), true)
		draw_rect(Rect2(draw_p - Vector2(4, 4), Vector2(8, 8)), base_col, true)
		draw_rect(Rect2(draw_p - Vector2(2, 2), Vector2(4, 4)), SFPalette.PAPER, true)


func _draw_telegraphs() -> void:
	for entry in encounter.telegraphs:
		var t: Dictionary = entry
		var duration: float = maxf(0.001, float(t.get("duration", 1.0)))
		var progress: float = clampf(float(t.get("elapsed", 0.0)) / duration, 0.0, 1.0)
		var from: Vector2 = t.get("position", Vector2.ZERO)
		var to: Vector2 = encounter.nick_position
		var beneficial := String(t.get("family", "hostile")) == "beneficial"
		var c: Color = SFPalette.CYAN if beneficial else SFPalette.RED
		# The lane fills in as the warning completes, so the direction is legible
		# even on a small window.
		var dir := to - from
		if dir.length_squared() < 1.0:
			continue
		var length: float = dir.length()
		var segments := 18
		for i in segments:
			var f0: float = float(i) / float(segments)
			if f0 > progress:
				break
			var f1: float = minf(progress, float(i + 1) / float(segments))
			var a := from.lerp(to, f0)
			var b := from.lerp(to, f1)
			var alpha: float = 0.10 + 0.22 * progress
			draw_line(a, b, Color(c.r, c.g, c.b, alpha), 2.0)
		# The emitter itself pulses harder.
		_draw_ring(from, 10.0 + 6.0 * progress, Color(c.r, c.g, c.b, 0.30 + 0.5 * progress))


func _draw_ring(center: Vector2, radius: float, color: Color) -> void:
	var segments := 20
	for i in segments:
		var a0: float = float(i) / float(segments) * TAU
		var a1: float = float(i + 1) / float(segments) * TAU
		draw_line(center + Vector2(cos(a0), sin(a0)) * radius, center + Vector2(cos(a1), sin(a1)) * radius, color, 1.0)


func _px_glow(center: Vector2, radius: float, color: Color) -> void:
	# A tiny dithered halo, so glowing parts read as light rather than as lines.
	var steps := int(radius)
	for i in steps:
		var f: float = float(i) / float(maxi(1, steps - 1))
		var a: float = (1.0 - f) * 0.16 * color.a
		var r: float = radius * f
		var c := Color(color.r, color.g, color.b, a)
		draw_rect(Rect2(center.x - r, center.y - r * 0.62, r * 2.0, maxf(1.0, r * 1.24)), c, true)


# ---------------------------------------------------------------- projectiles

func _draw_projectiles() -> void:
	for entry in encounter.field.projectiles:
		var p: Dictionary = entry
		if not bool(p.get("alive", false)):
			continue
		var pos: Vector2 = p["pos"]
		var dir: Vector2 = p.get("dir", Vector2(0, 1))
		var body := Color(String(p.get("color", "ffffff")))
		var outline := Color(String(p.get("outline", "000000")))
		var trail := Color(String(p.get("trail", "ffffff")))
		var r := float(p.get("radius", 4.0))

		# Trail: a short fading streak behind the projectile.
		draw_line(pos, pos - dir * (r * 3.2), Color(trail.r, trail.g, trail.b, 0.35), maxf(1.0, r * 0.9))
		draw_line(pos, pos - dir * (r * 1.6), Color(body.r, body.g, body.b, 0.55), maxf(1.0, r * 0.6))

		match String(p.get("shape", "chevron")):
			"chevron":
				_poly(_chevron(pos, dir, r), body, outline)
			"dart":
				_poly(_dart(pos, dir, r), body, outline)
			"shard":
				_poly(_shard(pos, dir, r), body, outline)
			"blob":
				_poly(_blob(pos, r), body, outline)
			"bolt":
				_poly(_bolt(pos, dir, r), body, outline)
			"diamond":
				# Beneficial: diamond plus a bright core, unmistakable at speed.
				_poly(_diamond(pos, r + 1.0), outline, outline)
				_poly(_diamond(pos, r), body, outline)
				draw_rect(Rect2(pos - Vector2(1.5, 1.5), Vector2(3, 3)), SFPalette.PAPER, true)
			"orb":
				# Beneficial: pale core and a hard rim, never red-coded.
				_poly(_blob(pos, r + 1.5), outline, outline)
				_poly(_blob(pos, r), body, outline)
				_poly(_blob(pos, r * 0.45), SFPalette.PAPER, body)
			_:
				draw_rect(Rect2(pos - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), body, true)


func _poly(points: PackedVector2Array, fill: Color, outline: Color = Color(0, 0, 0, 0)) -> void:
	if points.size() < 3:
		return
	if outline.a > 0.0:
		# A one-pixel outline: draw the same shape slightly expanded behind it.
		var center := Vector2.ZERO
		for p in points:
			center += p
		center /= float(points.size())
		var expanded := PackedVector2Array()
		for p in points:
			expanded.append(center + (p - center) * 1.35)
		draw_colored_polygon(expanded, outline)
	draw_colored_polygon(points, fill)


func _chevron(pos: Vector2, dir: Vector2, r: float) -> PackedVector2Array:
	var side := dir.orthogonal()
	return PackedVector2Array([
		pos + dir * (r * 1.6),
		pos - dir * (r * 0.6) + side * r,
		pos - dir * (r * 0.1),
		pos - dir * (r * 0.6) - side * r,
	])


func _dart(pos: Vector2, dir: Vector2, r: float) -> PackedVector2Array:
	var side := dir.orthogonal()
	return PackedVector2Array([
		pos + dir * (r * 2.1),
		pos - dir * r + side * (r * 0.7),
		pos - dir * (r * 1.3),
		pos - dir * r - side * (r * 0.7),
	])


func _shard(pos: Vector2, dir: Vector2, r: float) -> PackedVector2Array:
	var side := dir.orthogonal()
	return PackedVector2Array([
		pos + dir * (r * 0.6) + side * (r * 1.15),
		pos + dir * (r * 1.5),
		pos - dir * (r * 0.7) + side * (r * 0.5),
		pos - dir * (r * 1.2),
		pos - dir * (r * 0.4) - side * (r * 0.9),
	])


func _blob(pos: Vector2, r: float) -> PackedVector2Array:
	# A deliberately wobbly octagon: liquid, not geometric.
	var out := PackedVector2Array()
	for i in 9:
		var a: float = float(i) / 9.0 * TAU
		var wobble: float = 0.84 + 0.16 * sin(float(i) * 2.4 + pos.x * 0.1)
		out.append(pos + Vector2(cos(a), sin(a)) * r * wobble)
	return out


func _bolt(pos: Vector2, dir: Vector2, r: float) -> PackedVector2Array:
	var side := dir.orthogonal()
	return PackedVector2Array([
		pos + dir * (r * 1.7) + side * r * 0.4,
		pos + side * (r * 0.5),
		pos - dir * (r * 0.8) - side * r * 0.6,
		pos - dir * (r * 1.4),
		pos - dir * (r * 0.2) + side * r * 0.4,
	])


func _diamond(pos: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		pos + Vector2(0, -r * 1.45),
		pos + Vector2(r, 0),
		pos + Vector2(0, r * 1.45),
		pos + Vector2(-r, 0),
	])


# ---------------------------------------------------------------- nick / shield

func _draw_nick() -> void:
	var pos: Vector2 = encounter.nick_position
	var tex: Texture2D = skin.sprites.get("nick_up", null)
	# A wide contact shadow, because Nick is planted for the whole fight.
	skin.contact_shadow(self, pos, 22.0, 0.34)
	if tex != null:
		var size := tex.get_size()
		draw_texture_rect(tex, Rect2(pos.x - size.x * 0.5, pos.y - size.y, size.x, size.y), false)
	# The suit lights up while absorbing, so the benefit reads on Nick himself.
	if encounter.model.absorb_flash > 0.0:
		var a := clampf(encounter.model.absorb_flash / 0.3, 0.0, 1.0) * 0.35
		draw_rect(Rect2(pos.x - 14, pos.y - 26, 28, 28), Color(0.49, 0.95, 0.78, a), true)
	if encounter.model.damage_flash > 0.0:
		var a2 := clampf(encounter.model.damage_flash / 0.35, 0.0, 1.0)
		draw_rect(Rect2(0, 0, VW, VH), Color(0.85, 0.20, 0.20, 0.16 * a2), true)


func _draw_shield() -> void:
	var shield = encounter.shield
	var pos: Vector2 = encounter.nick_position
	var locked: bool = encounter.model.shield_locked()
	var points: PackedVector2Array = shield.arc_points(pos, 26, 0.0)
	var thickness: float = encounter.shield_thickness
	var inner: PackedVector2Array = shield.arc_points(pos, 26, -thickness)
	var col := SFPalette.CYAN if not locked else SFPalette.GOLD
	# Outer glow band.
	for i in points.size() - 1:
		draw_line(points[i], points[i + 1], Color(col.r, col.g, col.b, 0.10), 11.0)
	# Main band.
	for i in points.size() - 1:
		draw_line(points[i], points[i + 1], Color(col.r, col.g, col.b, 0.65), thickness)
	# Inner highlight, offset half a pixel so the edge stays crisp.
	for i in points.size() - 1:
		var a: Vector2 = points[i].lerp(inner[i], 0.72)
		var b: Vector2 = points[i + 1].lerp(inner[i + 1], 0.72)
		draw_line(a, b, Color(col.r, col.g, col.b, 0.30), 1.0)
	# Endpoint posts make the coverage limit explicit.
	for p in shield.arc_endpoints(pos, 0.0):
		draw_rect(Rect2((p as Vector2) - Vector2(2, 2), Vector2(4, 4)), SFPalette.PAPER, true)
	# A short direction tick from Nick, matching the authoritative direction.
	var dir: Vector2 = shield.direction
	draw_line(pos + dir * 12.0, pos + dir * (float(shield.radius) - 2.0), Color(col.r, col.g, col.b, 0.22), 1.0)
	# The cursor crosshair, drawn in the same space the shield reads.
	draw_rect(Rect2(_cursor_canvas - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, 0.5), true)



# ---------------------------------------------------------------- effects

func _draw_effects() -> void:
	for entry in effects:
		var e: Dictionary = entry
		var t: float = float(e.get("t", 0.0))
		var life: float = maxf(0.001, float(e.get("life", 0.2)))
		var f: float = clampf(t / life, 0.0, 1.0)
		var at: Vector2 = e.get("at", Vector2.ZERO)
		var c := Color(String(e.get("color", "ffffff")))
		match String(e.get("kind", "")):
			"spark":
				for i in 7:
					var ang: float = float(i) / 7.0 * TAU + f * 1.2
					var d: float = 4.0 + f * 16.0
					var p := at + Vector2(cos(ang), sin(ang)) * d
					draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(c.r, c.g, c.b, (1.0 - f) * 0.9), true)
			"hurt":
				draw_rect(Rect2(at - Vector2(7, 7), Vector2(14, 14)), Color(c.r, c.g, c.b, (1.0 - f) * 0.45), true)
				draw_rect(Rect2(at - Vector2(11, 1), Vector2(22, 2)), Color(c.r, c.g, c.b, (1.0 - f) * 0.6), true)
			"absorb":
				for i in 3:
					var rr := 6.0 + f * (10.0 + float(i) * 6.0)
					_draw_ring(at, rr, Color(c.r, c.g, c.b, (1.0 - f) * (0.6 - float(i) * 0.15)))
			"burst":
				for i in 4:
					var rr2 := 10.0 + f * (48.0 + float(i) * 14.0)
					_draw_ring(at, rr2, Color(c.r, c.g, c.b, (1.0 - f) * (0.5 - float(i) * 0.1)))
				if f < 0.5:
					draw_rect(Rect2(at - Vector2(16, 16), Vector2(32, 32)), Color(1, 1, 1, (0.5 - f) * 0.4), true)
			"counter_launch":
				var from: Vector2 = e.get("from", Vector2.ZERO)
				var to: Vector2 = e.get("to", Vector2.ZERO)
				var head: Vector2 = from.lerp(to, clampf(f * 1.35, 0.0, 1.0))
				var tail: Vector2 = from.lerp(to, clampf(f * 1.35 - 0.22, 0.0, 1.0))
				draw_line(tail, head, Color(1.0, 0.92, 0.6, 0.9), 4.0)
				draw_line(tail, head, SFPalette.PAPER, 1.0)
				_draw_ring(head, 6.0, Color(1.0, 0.96, 0.8, 0.6))
			"charge_text":
				var text := String(e.get("text", ""))
				if text != "":
					skin.text_c(self, at.x, at.y - f * 10.0, text, Color(c.r, c.g, c.b, 1.0 - f))


# ---------------------------------------------------------------- HUD

func _draw_hud() -> void:
	var alive_tint := _boss_alive_tint()

	# Boss health: its own strip along the top of the encounter.
	var boss_name := String(boss.get("name", "BOSS"))
	var subtitle := String(boss.get("subtitle", ""))
	draw_rect(Rect2(0, 0, VW, 26), Color(0.02, 0.04, 0.04, 0.88), true)
	draw_rect(Rect2(0, 26, VW, 1), SFPalette.STEEL_DARK, true)
	skin.text(self, Vector2(12, 5), boss_name, SFPalette.PAPER)
	skin.text(self, Vector2(12, 15), subtitle, SFPalette.PAPER_DIM)
	var bar_x := 180.0
	var bar_w := 300.0
	var boss_ratio: float = encounter.model.health_fraction()
	skin.bar(self, Vector2(bar_x, 8), Vector2(bar_w, 10), boss_ratio, _visual_color("glow", SFPalette.RUST_LIGHT).lerp(SFPalette.PAPER, 0.15), SFPalette.INK)
	# Band ticks, so the escalation is visible on the health bar itself.
	for entry in boss.get("bands", []) as Array:
		var band: Dictionary = entry
		var f: float = float(band.get("at_fraction", 1.0))
		if f >= 1.0:
			continue
		var tx: float = bar_x + bar_w * f
		draw_rect(Rect2(round(tx), 8, 1, 10), SFPalette.PAPER_DIM, true)
	skin.text_r(self, VW - 12, 9, "%d / %d" % [encounter.model.boss_health, encounter.model.boss_health_max], SFPalette.PAPER)

	# Nick's health: a separate, unmistakable element at the bottom left.
	var nick_panel := Rect2(10, 318, 186, 34)
	draw_rect(nick_panel, Color(0.03, 0.06, 0.06, 0.9), true)
	draw_rect(nick_panel, SFPalette.GREEN_OK.darkened(0.3), false, 1.0)
	skin.text(self, nick_panel.position + Vector2(7, 5), "NICK", SFPalette.GREEN_OK)
	skin.text_r(self, nick_panel.end.x - 7, nick_panel.position.y + 5,
		"%d / %d" % [encounter.model.nick_health, encounter.model.nick_health_max], SFPalette.PAPER)
	var hurt_ratio: float = encounter.model.nick_fraction()
	var nick_col := SFPalette.GREEN_OK
	if hurt_ratio <= 0.3:
		nick_col = SFPalette.RED
	elif hurt_ratio <= 0.6:
		nick_col = SFPalette.GOLD
	skin.bar(self, nick_panel.position + Vector2(7, 16), Vector2(nick_panel.size.x - 14, 11), hurt_ratio, nick_col, SFPalette.INK)
	if encounter.model.damage_flash > 0.0:
		var a := clampf(encounter.model.damage_flash / 0.35, 0.0, 1.0)
		draw_rect(nick_panel, Color(0.86, 0.25, 0.25, 0.25 * a), false, 2.0)
		skin.text_r(self, nick_panel.end.x - 7, nick_panel.position.y + 5, "-%d" % encounter.model.last_damage, Color(1, 0.85, 0.85, a))

	# The charge meter, directly above Nick's head, never confused with health.
	_draw_charge_meter()

	# Controls, bottom right, clear of the health panel.
	draw_rect(Rect2(424, 330, 208, 22), Color(0.03, 0.06, 0.06, 0.82), true)
	skin.text(self, Vector2(432, 336), "MOUSE  AIM SHIELD", SFPalette.PAPER_DIM)
	skin.text(self, Vector2(432, 344), "SPACE  COUNTERATTACK   ESC  PAUSE", SFPalette.PAPER_DIM)

	# Bill's one-line reminder for the first seconds of the fight.
	if intro_banner > 0.0 and state == State.FIGHT:
		var a2 := clampf(intro_banner, 0.0, 1.0)
		var w := 360.0
		var r := Rect2(VW * 0.5 - w * 0.5, 286, w, 15)
		draw_rect(r, Color(0.04, 0.07, 0.08, 0.86 * a2), true)
		skin.text_c(self, VW * 0.5, 290, "BLOCK HOSTILE ENERGY. ADMIT THE GREEN MOTES. SPACE WHEN FULL.",
			Color(SFPalette.PAPER.r, SFPalette.PAPER.g, SFPalette.PAPER.b, a2))


func _draw_charge_meter() -> void:
	var pos: Vector2 = encounter.nick_position
	var w := 64.0
	var h := 8.0
	var r := Rect2(pos.x - w * 0.5, pos.y - 44.0, w, h)
	var ratio: float = encounter.model.charge_fraction()
	var full: bool = encounter.model.charge_full()
	# A plate behind the label and the meter: the charge readout must never be
	# confused with the robot's own screens behind Nick.
	var plate := Rect2(r.position.x - 8.0, r.position.y - 14.0, r.size.x + 16.0, r.size.y + 18.0)
	draw_rect(plate, Color(0.02, 0.05, 0.05, 0.9), true)
	draw_rect(plate, Color(SFPalette.CYAN_DIM.r, SFPalette.CYAN_DIM.g, SFPalette.CYAN_DIM.b, 0.7), false, 1.0)
	skin.bar(self, r.position, r.size, ratio, SFPalette.CYAN if not full else SFPalette.GOLD, SFPalette.INK)
	skin.text_c(self, pos.x, r.position.y - 12.0, "CHARGE", SFPalette.PAPER_DIM)
	# No text inside the meter itself: it must never look like a health bar.
	for i in 4:
		var tx := r.position.x + r.size.x * (float(i + 1) / 5.0)
		draw_rect(Rect2(round(tx), r.position.y, 1, r.size.y), Color(0.02, 0.05, 0.05, 0.55), true)
	if full and state == State.FIGHT:
		var pulse: float = 0.62 + 0.38 * sin(time * 8.0)
		var label := "SPACE - COUNTERATTACK"
		var tw: float = skin.font.text_width(label) + 14.0
		# The indicator sits directly above the charge plate, clear of the
		# "CHARGE" caption, so the two never overlap.
		var lr := Rect2(pos.x - tw * 0.5, plate.position.y - 15.0, tw, 12)
		draw_rect(lr, Color(0.05, 0.09, 0.07, 0.95), true)
		draw_rect(lr, Color(SFPalette.GOLD.r, SFPalette.GOLD.g, SFPalette.GOLD.b, pulse), false, 1.0)
		skin.text_c(self, pos.x, lr.position.y + 3, label, Color(SFPalette.GOLD.r, SFPalette.GOLD.g, SFPalette.GOLD.b, pulse))
	elif encounter.model.shield_locked():
		skin.text_c(self, pos.x, plate.position.y - 12.0, "COUNTERATTACKING", SFPalette.GOLD)


# ---------------------------------------------------------------- overlays

func _draw_state_overlay() -> void:
	match state:
		State.VICTORY:
			if encounter.model.victory_timer >= encounter.model.victory_hold:
				_draw_victory_panel()
		State.DEFEAT:
			_draw_defeat_panel()
		State.PAUSED:
			_draw_pause_panel()


func _draw_victory_panel() -> void:
	ui.modal(self, Rect2(150, 110, 340, 140), SFPalette.CYAN)
	skin.text_c(self, 320, 124, "ENCOUNTER CLEARED", SFPalette.CYAN, 2)
	skin.wrap(self, Vector2(172, 152), 296,
		String(boss.get("name", "The robot")) + " has stopped attacking. The route is open.",
		SFPalette.PAPER, 1, 3)
	skin.text_c(self, 320, 196, "ENTER  CONTINUE", SFPalette.GOLD)
	skin.text_c(self, 320, 214, "REWARD IS AWARDED ONCE, ON CONTINUE", SFPalette.PAPER_DIM)


func _draw_defeat_panel() -> void:
	ui.modal(self, Rect2(150, 106, 340, 156), SFPalette.RED)
	skin.text_c(self, 320, 120, "NICK IS DOWN", SFPalette.RED, 2)
	skin.wrap(self, Vector2(172, 148), 296,
		"The encounter restarts. Progress, salvage and earlier rewards are kept.",
		SFPalette.PAPER, 1, 3)
	skin.text_c(self, 320, 196, "ENTER / R  RETRY", SFPalette.GOLD)
	skin.text_c(self, 320, 218, "ESC  PAUSE MENU", SFPalette.PAPER_DIM)


func _draw_pause_panel() -> void:
	ui.modal(self, Rect2(200, 96, 240, 160), SFPalette.CYAN)
	skin.text_c(self, 320, 108, "PAUSED", SFPalette.CYAN)
	ui.menu_list(self, pause_menu, Vector2(216, 128), 208.0, 20.0)
	skin.text_c(self, 320, 232, "ESC  RESUME", SFPalette.PAPER_DIM)
