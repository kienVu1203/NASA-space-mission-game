extends Node2D
## The Eco Arena screen: the pre-match sorting guide, the angled top-down
## arena (camera, Y-sorted drawing, contact shadows), the HUD, pause, defeat
## and retry, and the summary. It owns no campaign state. The same screen runs
## both entry points:
##   campaign  the Scrap King encounter. It reports `boss_defeated` and
##             `reward_collected` so the controller records the boss and awards
##             navigation_chip only when Nick picks the chip up.
##   practice  the main-menu Eco Arena. Nothing is reported to the campaign.
##
## Controls
##   WASD / ARROWS  move (diagonals normalised)    SHIFT  dash
##   MOUSE          aim                            LEFT CLICK  fire
##   1 / 2 / 3      Green / Blue / Yellow           WHEEL  cycle spectrum
##   RIGHT CLICK / E (hold)  Bill's sorting beam    E  pick up the chip
##   ESC            pause (resume, guide, restart, leave)

signal boss_defeated
signal reward_collected
signal arena_finished(choice: String)   # "continue" (campaign) or "menu"
signal arena_aborted

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFEcoArena := preload("res://core/star_fall/sf_eco_arena.gd")
const SFEcoSprites := preload("res://core/star_fall/sf_eco_sprites.gd")
const SFMenu := preload("res://core/star_fall/sf_menu.gd")

const VW := 640
const VH := 360
const RETRY_DELAY := 0.5
const START_BUTTON := Rect2(250, 326, 140, 22)

## Presentation only: which body each badge item is drawn with.
const SILHOUETTE := {
	"banana_peel": "blob", "food_scraps": "blob", "leaves": "blob",
	"pizza_box": "box", "cardboard_box": "box", "leaf_box": "box",
	"newspaper": "sheet", "office_paper": "sheet",
	"plastic_bottle": "bottle", "residue_bottle": "bottle",
	"aluminum_can": "can", "tin_can": "can", "crushed_can": "crushed",
}

enum State { GUIDE, FIGHT, PAUSED, DEFEAT, SUMMARY }

var skin
var ui
var data: Dictionary = {}
var model
var mode: String = "practice"
var resume_reward: bool = false
var state: int = State.GUIDE
var guide_from_pause: bool = false
var guide_seen: bool = false
var pause_menu
var summary_menu
var summary: Dictionary = {}
var badges: Dictionary = {}
## Set by the controller while a dialogue is open over this screen: nothing
## ticks and no key is consumed.
var input_locked: bool = false
var reduced_motion: bool = false
## Tests drive the arena without devices: {move, aim, fire, beam}.
var scripted_input: Variant = null

var time: float = 0.0
var cam: Vector2 = Vector2.ZERO
var cam_draw: Vector2 = Vector2.ZERO
var effects: Array = []
var shake: float = 0.0
var defeat_timer: float = 0.0
var banner_text: String = ""
var banner_timer: float = 0.0
var _boss_reported: bool = false
var _reward_reported: bool = false
var _finished: bool = false
var _sound_gate: Dictionary = {}


func setup(skin_ref, ui_ref, arena_data: Dictionary, mode_id: String, resume: bool = false) -> void:
	skin = skin_ref
	ui = ui_ref
	data = arena_data
	mode = mode_id
	resume_reward = resume
	model = SFEcoArena.new()
	model.setup(data)
	model.reset(resume_reward)
	_boss_reported = resume_reward
	badges = SFEcoSprites.build_all()
	pause_menu = SFMenu.new()
	summary_menu = SFMenu.new()
	refresh_menus()
	_snap_camera()


func is_campaign() -> bool:
	return mode == "campaign"


func refresh_menus() -> void:
	pause_menu.set_items([
		{"id": "resume", "label": "RESUME", "enabled": true},
		{"id": "guide", "label": "SORTING GUIDE", "enabled": true},
		{"id": "retry", "label": "RESTART ARENA", "enabled": true},
		{"id": "leave", "label": "LEAVE THE ARENA" if is_campaign() else "MAIN MENU", "enabled": true},
	], "resume")
	summary_menu.set_items([
		{"id": "again", "label": "PLAY AGAIN", "enabled": true},
		{"id": "done", "label": "CONTINUE" if is_campaign() else "MAIN MENU", "enabled": true},
	], "done")


# ---------------------------------------------------------------- lifecycle

## Closes the guide. The first time it starts the match; reopened from pause
## it returns to the pause menu. The match clock never runs while it is open.
func start_from_guide() -> void:
	guide_seen = true
	if guide_from_pause:
		guide_from_pause = false
		state = State.PAUSED
	else:
		state = State.FIGHT
		banner("SORT, CLEAN, RECOVER!", 2.0)
	skin.audio.sfx_confirm()
	queue_redraw()


func open_guide_from_pause() -> void:
	guide_from_pause = true
	state = State.GUIDE
	queue_redraw()


## A retry resets only this encounter and skips the guide; campaign progress
## earned before the arena is untouched. In the campaign, once the boss is
## down a restart keeps it down (the defeat is already saved); `full` (Play
## Again) always replays the whole arena.
func retry(full: bool = false) -> void:
	model.reset(resume_reward and not full)
	effects.clear()
	shake = 0.0
	defeat_timer = 0.0
	banner_timer = 0.0
	summary = {}
	_reward_reported = false
	_finished = false
	state = State.FIGHT
	_snap_camera()
	skin.audio.sfx_back()
	queue_redraw()


func is_fighting() -> bool:
	return state == State.FIGHT and not input_locked and model.is_active()


func banner(text: String, seconds: float = 2.5) -> void:
	banner_text = text
	banner_timer = seconds


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_mouse_button(mb)
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_M:
		return  # the global mute shortcut belongs to the controller
	get_viewport().set_input_as_handled()
	handle_key(k.keycode)


func handle_key(key: int) -> void:
	match state:
		State.GUIDE:
			match key:
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
					start_from_guide()
				KEY_ESCAPE:
					if guide_from_pause:
						start_from_guide()
					else:
						_open_pause()
		State.FIGHT:
			match key:
				KEY_1, KEY_KP_1:
					_select("green")
				KEY_2, KEY_KP_2:
					_select("blue")
				KEY_3, KEY_KP_3:
					_select("yellow")
				KEY_SHIFT:
					model.request_dash(_move_input())
					_consume(model.take_events())
				KEY_E:
					model.interact()
					_consume(model.take_events())
				KEY_ESCAPE:
					skin.audio.sfx_back()
					_open_pause()
		State.PAUSED:
			match key:
				KEY_UP, KEY_W:
					pause_menu.move_enabled(-1)
					skin.audio.sfx_select()
				KEY_DOWN, KEY_S:
					pause_menu.move_enabled(1)
					skin.audio.sfx_select()
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
					_activate_pause(String(pause_menu.current_id()))
				KEY_ESCAPE:
					_close_pause()
		State.DEFEAT:
			match key:
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_R:
					if defeat_timer >= RETRY_DELAY:
						retry()
				KEY_ESCAPE:
					_open_pause()
		State.SUMMARY:
			match key:
				KEY_UP, KEY_W, KEY_LEFT, KEY_A:
					summary_menu.move_enabled(-1)
					skin.audio.sfx_select()
				KEY_DOWN, KEY_S, KEY_RIGHT, KEY_D:
					summary_menu.move_enabled(1)
					skin.audio.sfx_select()
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_activate_summary(String(summary_menu.current_id()))
	queue_redraw()


func _mouse_button(mb: InputEventMouseButton) -> void:
	var pos := get_global_mouse_position()
	match state:
		State.GUIDE:
			if mb.button_index == MOUSE_BUTTON_LEFT and START_BUTTON.has_point(pos):
				start_from_guide()
		State.FIGHT:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				model.cycle_spectrum(-1)
				skin.audio.sfx_select()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				model.cycle_spectrum(1)
				skin.audio.sfx_select()
		State.DEFEAT:
			if mb.button_index == MOUSE_BUTTON_LEFT and defeat_timer >= RETRY_DELAY:
				retry()
		State.SUMMARY:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				for i in summary_menu.items.size():
					if _summary_button(i).has_point(pos):
						summary_menu.index = i
						_activate_summary(String(summary_menu.current_id()))
	get_viewport().set_input_as_handled()
	queue_redraw()


func _select(cat: String) -> void:
	if model.select_spectrum(cat):
		skin.audio.sfx_select()


func _open_pause() -> void:
	state = State.PAUSED
	pause_menu.index = 0
	queue_redraw()


func _close_pause() -> void:
	skin.audio.sfx_blip()
	if not guide_seen:
		state = State.GUIDE
	elif not model.is_active():
		state = State.DEFEAT if model.phase == SFEcoArena.PHASE_DEFEAT else State.SUMMARY
	else:
		state = State.FIGHT
	queue_redraw()


func _activate_pause(id: String) -> void:
	match id:
		"resume":
			_close_pause()
		"guide":
			skin.audio.sfx_blip()
			open_guide_from_pause()
		"retry":
			guide_seen = true
			retry()
		"leave":
			skin.audio.sfx_back()
			arena_aborted.emit()


func _activate_summary(id: String) -> void:
	match id:
		"again":
			retry(true)
		"done":
			if _finished:
				return
			_finished = true
			skin.audio.sfx_confirm()
			arena_finished.emit("continue" if is_campaign() else "menu")


func _notification(what: int) -> void:
	# Focus loss pauses the match so nothing lands while the window is away.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == State.FIGHT and not input_locked:
			_open_pause()


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	time += delta
	var dt := minf(delta, 0.1)
	ui.tick(dt)
	if not input_locked:
		if state == State.FIGHT:
			_advance(dt)
		elif state == State.DEFEAT:
			defeat_timer += dt
	_update_presentation(dt)
	queue_redraw()


## One arena step with the current input. `_process` and the tests share it.
func _advance(dt: float) -> void:
	if state != State.FIGHT:
		return
	var move := _move_input()
	var aim: Vector2 = model.nick_pos + Vector2.UP * 40.0
	var fire := false
	var beam := false
	if scripted_input is Dictionary:
		var si: Dictionary = scripted_input
		aim = si.get("aim", aim)
		fire = bool(si.get("fire", false))
		beam = bool(si.get("beam", false))
	elif is_inside_tree():
		aim = get_global_mouse_position() + cam_draw
		fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		beam = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_action_pressed("interact")
	_consume(model.tick(dt, move, aim, fire, beam))


func advance_for(seconds: float, step: float = 0.05) -> void:
	var left := seconds
	while left > 0.0001:
		var dt := minf(step, left)
		_advance(dt)
		_update_presentation(dt)
		left -= dt


func _move_input() -> Vector2:
	if scripted_input is Dictionary:
		return (scripted_input as Dictionary).get("move", Vector2.ZERO)
	if not is_inside_tree():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _update_presentation(dt: float) -> void:
	var keep: Array = []
	for e in effects:
		var fx: Dictionary = e
		fx["t"] = float(fx["t"]) + dt
		if float(fx["t"]) < float(fx["life"]):
			keep.append(fx)
	effects = keep
	shake = maxf(0.0, shake - dt * 8.0)
	banner_timer = maxf(0.0, banner_timer - dt)
	for k in _sound_gate.keys():
		_sound_gate[k] = maxf(0.0, float(_sound_gate[k]) - dt)
	var target := _camera_target()
	cam = cam.lerp(target, clampf(10.0 * dt, 0.0, 1.0))
	cam_draw = cam.round()


func _camera_target() -> Vector2:
	var w: Dictionary = data.get("world", {}) as Dictionary
	var focus: Vector2 = model.nick_pos
	# While the Colossus is up, lean toward it so its tall body stays in view.
	if not model.boss.is_empty() and not model.boss_defeated:
		focus = focus.lerp((model.boss["pos"] as Vector2) + Vector2(0, -40), 0.4)
	var t: Vector2 = focus - Vector2(VW * 0.5, VH * 0.54)
	t.x = clampf(t.x, 0.0, float(w.get("width", 1280)) - VW)
	t.y = clampf(t.y, 0.0, float(w.get("height", 960)) - VH)
	return t


func _snap_camera() -> void:
	cam = _camera_target()
	cam_draw = cam.round()


func _consume(events: Array) -> void:
	for e in events:
		var ev: Dictionary = e
		var at: Vector2 = ev.get("pos", model.nick_pos)
		match String(ev.get("kind", "")):
			"fire":
				var pitch: float = {"green": 0.85, "blue": 1.0, "yellow": 1.2}.get(String(ev.get("cat", "")), 1.1)
				_sound("fire", 0.12, Callable(skin.audio, "sfx_blaster").bind(pitch))
			"hit":
				var cat := _fx_cat(ev)
				_fx("hit_" + cat, at, 0.35)
				_sound("hit", 0.06, Callable(self, "_hit_sound").bind(String(ev.get("cat", ""))))
			"deflect":
				_fx("deflect", at, 0.25)
				_sound("deflect", 0.1, Callable(skin.audio, "sfx_shield_block"))
			"bolt_blocked":
				_fx("puff", at, 0.2)
			"layer_exposed":
				_fx("layer", at, 0.6)
				_fx_text("NEXT LAYER!", at + Vector2(0, -30), SFPalette.PAPER)
				skin.audio.sfx_surge()
			"enemy_down":
				_fx("burst", at, 0.5)
				if bool(ev.get("recycled", false)):
					_fx_text("RECYCLED!", at + Vector2(0, -30), SFPalette.GREEN_OK)
				skin.audio.sfx_counter_hit()
			"enemy_cleared":
				_fx("puff", at, 0.4)
			"core_drop":
				_fx("pop", at, 0.3)
			"core_spark":
				_fx("spark", at, 0.3)
				_sound("static", 0.12, Callable(skin.audio, "sfx_static"))
			"core_cleaned":
				_fx("shell", at, 0.45)
				skin.audio.sfx_install()
			"super_unlock":
				_fx("shell", at, 0.6)
				_fx_text("LOCK %d OPEN" % int(ev.get("lock", 1)), at + Vector2(0, -48), _cat_color(String(ev.get("cat", ""))))
				skin.audio.sfx_signal_lock()
			"core_collected":
				var gained := int(ev.get("gained", 0))
				_fx_text(("+%d%%" % gained) if gained > 0 else "STATION FULL", model.nick_pos + Vector2(0, -34), SFPalette.CYAN)
				skin.audio.sfx_pickup()
			"stage":
				banner("STAGE %d — %s" % [int(ev.get("stage", 1)), String(ev.get("name", ""))], 3.0)
				skin.audio.sfx_checkpoint()
			"boss_spawn":
				banner(String((data.get("boss", {}) as Dictionary).get("name", "BOSS")), 3.0)
				skin.audio.sfx_alarm()
				shake = maxf(shake, 4.0)
			"boss_layer":
				_fx("burst", at + Vector2(0, -30), 0.7)
				_fx_text("ARMOR BROKEN!", at + Vector2(0, -80), SFPalette.GOLD)
				skin.audio.sfx_counter_hit()
				shake = maxf(shake, 3.0)
			"boss_down":
				_fx("burst", at + Vector2(0, -30), 1.0)
				banner("COLOSSUS DOWN — UNLOCK THE SUPER CORE", 3.5)
				skin.audio.sfx_boss_down()
				shake = maxf(shake, 5.0)
				_report_boss()
			"nick_hurt":
				_fx("hurt", at, 0.3)
				skin.audio.sfx_player_hurt()
				shake = maxf(shake, 2.5)
			"defeat":
				skin.audio.sfx_defeat()
				state = State.DEFEAT
				defeat_timer = 0.0
			"overdrive":
				banner("ECO OVERDRIVE!", 2.0)
				skin.audio.sfx_power_up()
			"overdrive_end":
				skin.audio.sfx_back()
			"combo":
				if int(ev.get("count", 0)) > 0:
					skin.audio.sfx_blip()
			"crusher":
				var matched: bool = bool(ev.get("match", false))
				_fx("slam", at, 0.4)
				if not matched:
					_fx_text("WRONG CRUSHER", at + Vector2(0, -44), SFPalette.RED)
				skin.audio.sfx_impact()
				shake = maxf(shake, 2.0)
			"toss_land":
				_fx("land", at, 0.4)
				_sound("land", 0.1, Callable(skin.audio, "sfx_impact"))
			"ring_fire":
				skin.audio.sfx_surge()
			"dash":
				_fx("dash", model.nick_pos, 0.25)
				skin.audio.sfx_blip()
			"chip_collected":
				_fx("burst", at, 0.6)
				skin.audio.sfx_pickup()
				banner(String(_reward_info().get("name", "CHIP")) + " RECOVERED", 2.5)
				_report_reward()
			"callout":
				skin.audio.sfx_blip_bill()
			"victory":
				summary = model.summary()
				summary_menu.index = summary_menu.index_of("done")
				state = State.SUMMARY
				skin.audio.sfx_preflight_pass()


func _fx_cat(ev: Dictionary) -> String:
	return "rainbow" if bool(ev.get("auto", false)) else String(ev.get("cat", ""))


func _hit_sound(cat: String) -> void:
	match cat:
		"green":
			skin.audio.sfx_sort_organic()
		"blue":
			skin.audio.sfx_sort_paper()
		_:
			skin.audio.sfx_sort_metal()


func _sound(key: String, gap: float, play: Callable) -> void:
	if float(_sound_gate.get(key, 0.0)) > 0.0:
		return
	_sound_gate[key] = gap
	play.call()


## Campaign only, once each: the boss is recorded, then the chip on pickup.
func _report_boss() -> void:
	if not is_campaign() or _boss_reported:
		return
	resume_reward = true  # a restart after this point keeps the boss down
	_boss_reported = true
	boss_defeated.emit()


func _report_reward() -> void:
	if _reward_reported:
		return
	_reward_reported = true
	if is_campaign():
		reward_collected.emit()


func _reward_info() -> Dictionary:
	return data.get("campaign_reward" if is_campaign() else "practice_reward", {}) as Dictionary


func _fx(kind: String, at: Vector2, life: float) -> void:
	if effects.size() > 90:
		return
	effects.append({"kind": kind, "at": at, "t": 0.0, "life": life, "seed": randi() % 997})


func _fx_text(text: String, at: Vector2, c: Color) -> void:
	effects.append({"kind": "text", "at": at, "t": 0.0, "life": 0.9, "text": text, "color": c, "seed": 0})


# ---------------------------------------------------------------- helpers

func _cat_color(cat: String) -> Color:
	if cat == "rainbow":
		return Color.from_hsv(fmod(time * 1.6, 1.0), 0.55, 1.0)
	var c: Dictionary = (data.get("categories", {}) as Dictionary).get(cat, {}) as Dictionary
	return Color(String(c.get("color", "ffffff")))


func _cat_dark(cat: String) -> Color:
	var c: Dictionary = (data.get("categories", {}) as Dictionary).get(cat, {}) as Dictionary
	return Color(String(c.get("dark", "333333")))


func _badge_item(e: Dictionary) -> String:
	var it: Dictionary = model.item(String(e.get("item", "")))
	var lb: Dictionary = it.get("layer_badges", {}) as Dictionary
	var cat: String = model.active_layer(e)
	return String(lb.get(cat, e.get("item", "")))


func _targeted_enemy() -> Dictionary:
	var aim: Vector2 = model.aim_point
	# The cursor over an enemy's body (its shot hitbox) targets it first.
	for e in model.enemies:
		if model.body_rect(e).grow(4.0).has_point(aim):
			return e
	var best: Dictionary = {}
	var best_d := 48.0
	for e in model.enemies:
		var d := ((e as Dictionary)["pos"] as Vector2 + Vector2(0, -10)).distance_to(aim)
		if d < best_d:
			best_d = d
			best = e
	if not best.is_empty():
		return best
	var dir: Vector2 = (aim - model.nick_pos).normalized()
	var best_score := 0.97
	for e in model.enemies:
		var off: Vector2 = (e as Dictionary)["pos"] - model.nick_pos
		if off.length() > 320.0 or off.length() < 1.0:
			continue
		var score := off.normalized().dot(dir)
		if score > best_score:
			best_score = score
			best = e
	return best


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if state == State.GUIDE:
		_draw_guide()
		ui.toast(self)
		return
	var off := cam_draw
	if shake > 0.0 and not reduced_motion:
		off += Vector2(roundf(sin(time * 83.0) * shake), roundf(cos(time * 71.0) * shake * 0.6))
	draw_set_transform(-off, 0.0, Vector2.ONE)
	_draw_floor(off)
	_draw_ground_markers()
	_draw_sorted()
	_draw_projectiles()
	_draw_beam()
	_draw_effects()
	_draw_world_badges()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()
	match state:
		State.PAUSED:
			_draw_pause()
		State.DEFEAT:
			_draw_defeat()
		State.SUMMARY:
			_draw_summary()
	ui.toast(self)


func _draw_floor(off: Vector2) -> void:
	var w: Dictionary = data.get("world", {}) as Dictionary
	var wk: Dictionary = w.get("walkable", {}) as Dictionary
	var rect := Rect2(float(wk.get("x", 40)), float(wk.get("y", 92)), float(wk.get("w", 1200)), float(wk.get("h", 828)))
	var view := Rect2(off, Vector2(VW, VH))
	draw_rect(view, Color("161c18"), true)
	# Floor plates, only the visible ones.
	var tile := 32.0
	var x0 := floorf(maxf(rect.position.x, view.position.x) / tile) * tile
	var y0 := floorf(maxf(rect.position.y, view.position.y) / tile) * tile
	var y := y0
	while y < minf(rect.end.y, view.end.y):
		var x := x0
		while x < minf(rect.end.x, view.end.x):
			var odd: bool = (int(x / tile) + int(y / tile)) % 2 == 0
			var r := Rect2(maxf(x, rect.position.x), maxf(y, rect.position.y), tile, tile).intersection(rect)
			draw_rect(r, Color("2a3530") if odd else Color("26302b"), true)
			draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color("33403a"), true)
			x += tile
		y += tile
	# Back wall with a lit face, so the arena reads as a sunken yard.
	draw_rect(Rect2(0, 0, float(w.get("width", 1280)), rect.position.y - 34), Color("0f1513"), true)
	draw_rect(Rect2(0, rect.position.y - 34, float(w.get("width", 1280)), 34), Color("3b4a43"), true)
	var px := 0.0
	while px < float(w.get("width", 1280)):
		draw_rect(Rect2(px, rect.position.y - 34, 1, 34), Color("2c3833"), true)
		draw_rect(Rect2(px + 6, rect.position.y - 26, 20, 4), Color("4f6158"), true)
		px += 64.0
	for i in int(float(w.get("width", 1280)) / 24.0):
		var c := SFPalette.GOLD.darkened(0.35) if i % 2 == 0 else Color("1d2421")
		draw_rect(Rect2(float(i) * 24.0, rect.position.y - 6, 24, 6), c, true)
	# Side and front rims.
	draw_rect(Rect2(0, rect.position.y, rect.position.x, rect.size.y), Color("0f1513"), true)
	draw_rect(Rect2(rect.end.x, rect.position.y, float(w.get("width", 1280)) - rect.end.x, rect.size.y), Color("0f1513"), true)
	draw_rect(Rect2(0, rect.end.y, float(w.get("width", 1280)), float(w.get("height", 960)) - rect.end.y), Color("0f1513"), true)
	draw_rect(Rect2(rect.position.x - 2, rect.position.y, 2, rect.size.y), Color("4f6158"), true)
	draw_rect(Rect2(rect.end.x, rect.position.y, 2, rect.size.y), Color("4f6158"), true)
	draw_rect(Rect2(rect.position.x, rect.end.y, rect.size.x, 3), Color("4f6158"), true)
	# The station floor ring: the charge, readable in the world.
	var st: Dictionary = data.get("station", {}) as Dictionary
	var sc := Vector2(float(st.get("x", 640)), float(st.get("y", 470)))
	var rr := float(st.get("ring_radius", 62))
	draw_arc(sc, rr, 0.0, TAU, 48, Color(0.05, 0.1, 0.1, 0.9), 7.0)
	var frac := float(model.charge) / 100.0
	if frac > 0.0:
		draw_arc(sc, rr, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, SFPalette.CYAN, 5.0)
	for t in [25, 55, 80]:
		var a := -PI * 0.5 + TAU * float(t) / 100.0
		draw_line(sc + Vector2(cos(a), sin(a)) * (rr - 5), sc + Vector2(cos(a), sin(a)) * (rr + 5), SFPalette.PAPER_DIM, 1.0)
	skin.text_c(self, sc.x, sc.y + rr - 20, "%d%%" % model.charge, SFPalette.CYAN, 2)
	# Crusher pads and their color-coded mouths.
	for c in model.crushers:
		var cd: Dictionary = c
		var cat := String(cd.get("category", ""))
		var p: Vector2 = cd["pos"]
		draw_circle(p + Vector2(0, 6), float(cd.get("mouth_radius", 40)), Color(_cat_dark(cat).r, _cat_dark(cat).g, _cat_dark(cat).b, 0.45))
		draw_arc(p + Vector2(0, 6), float(cd.get("mouth_radius", 40)), 0.0, TAU, 32, _cat_color(cat), 1.0)


func _draw_ground_markers() -> void:
	# Spawn warnings: a ring and an exclamation mark before anything appears.
	for p in model.pending_spawns:
		var ps: Dictionary = p
		var pulse := 0.5 + 0.5 * sin(time * 10.0)
		draw_arc(ps["pos"], 14.0, 0.0, TAU, 20, Color(1, 0.85, 0.4, 0.4 + 0.4 * pulse), 2.0)
		skin.text_c(self, (ps["pos"] as Vector2).x, (ps["pos"] as Vector2).y - 4, "!", SFPalette.GOLD)
	# Trash-toss landing zones: the fill grows until impact.
	for h in model.hazards:
		var hz: Dictionary = h
		var f := 1.0 - clampf(float(hz["t"]) / maxf(0.01, float(hz["life"])), 0.0, 1.0)
		draw_circle(hz["pos"], float(hz["r"]) * f, Color(0.85, 0.3, 0.2, 0.25))
		draw_arc(hz["pos"], float(hz["r"]), 0.0, TAU, 24, Color(0.95, 0.35, 0.25, 0.9), 2.0)
	# Charge telegraphs: the lane a charger will run down.
	for e in model.enemies:
		var en: Dictionary = e
		if String(en["state"]) == "tele":
			var from: Vector2 = en["pos"]
			var to: Vector2 = from + (en["charge_dir"] as Vector2) * 150.0
			var a := 0.4 + 0.4 * sin(time * 18.0)
			draw_line(from, to, Color(0.95, 0.35, 0.25, a), 3.0)


## Everything that stands on the floor is drawn back to front by its ground
## contact point, so Nick passes in front of and behind machines correctly.
func _draw_sorted() -> void:
	var items: Array = []
	var st: Dictionary = data.get("station", {}) as Dictionary
	items.append([float(st.get("y", 470)), "station", {}])
	for c in model.crushers:
		items.append([((c as Dictionary)["pos"] as Vector2).y, "crusher", c])
	for e in model.enemies:
		items.append([((e as Dictionary)["pos"] as Vector2).y, "enemy", e])
	for c in model.cores:
		items.append([((c as Dictionary)["pos"] as Vector2).y, "core", c])
	if not model.chip.is_empty() and not model.chip_collected:
		items.append([(model.chip["pos"] as Vector2).y, "chip", model.chip])
	if not model.boss.is_empty() and not model.boss_defeated:
		items.append([(model.boss["pos"] as Vector2).y, "boss", model.boss])
	items.append([model.bill_pos.y, "bill", {}])
	items.append([model.nick_pos.y + 0.1, "nick", {}])
	items.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for it in items:
		var entry: Array = it
		match String(entry[1]):
			"station":
				_draw_station()
			"crusher":
				_draw_crusher(entry[2])
			"enemy":
				_draw_enemy(entry[2])
			"core":
				_draw_core(entry[2])
			"chip":
				_draw_chip()
			"boss":
				_draw_boss()
			"bill":
				_draw_bill()
			"nick":
				_draw_nick()


func _draw_station() -> void:
	var st: Dictionary = data.get("station", {}) as Dictionary
	var p := Vector2(float(st.get("x", 640)), float(st.get("y", 470)))
	skin.contact_shadow(self, p, 70.0, 0.4)
	draw_rect(Rect2(p.x - 30, p.y - 30, 60, 30), Color("3d4b46"), true)
	draw_rect(Rect2(p.x - 30, p.y - 36, 60, 8), Color("56685f"), true)
	draw_rect(Rect2(p.x - 18, p.y - 58, 36, 24), Color("2c3833"), true)
	var glow := 0.4 + 0.6 * float(model.charge) / 100.0
	draw_rect(Rect2(p.x - 10, p.y - 54, 20, 16), Color(0.37, 0.9, 0.85, 0.35 + 0.4 * glow * (0.8 + 0.2 * sin(time * 4.0))), true)
	draw_rect(Rect2(p.x - 30, p.y - 30, 60, 30), SFPalette.STEEL_DARK, false, 1.0)
	skin.text_c(self, p.x, p.y - 22, "RECOVERY", SFPalette.PAPER_DIM)


func _draw_crusher(cd: Dictionary) -> void:
	var cat := String(cd.get("category", ""))
	var p: Vector2 = cd["pos"]
	var slam: float = float(cd.get("slam", 0.0))
	skin.contact_shadow(self, p, 48.0, 0.4)
	var col := _cat_color(cat)
	draw_rect(Rect2(p.x - 22, p.y - 26, 44, 26), Color("3b4440"), true)
	draw_rect(Rect2(p.x - 22, p.y - 26, 44, 5), col, true)
	var jaw := 10.0 if slam <= 0.0 else 2.0
	draw_rect(Rect2(p.x - 22, p.y - 46, 44, 16 - jaw * 0.3), Color("525d64"), true)
	draw_rect(Rect2(p.x - 20, p.y - 30 - jaw, 40, 4), Color("8a949b"), true)
	_draw_shape(String(_category(cat).get("shape", "round")), p + Vector2(-12, -14), 5.0, col)
	var icon: Texture2D = badges.get(String(_category(cat).get("icon", "")), null)
	if icon != null:
		draw_texture(icon, p + Vector2(-2, -21))
	skin.text_c(self, p.x, p.y + 3, String(_category(cat).get("name", "")), col)


func _category(cat: String) -> Dictionary:
	return (data.get("categories", {}) as Dictionary).get(cat, {}) as Dictionary


func _draw_shape(shape: String, c: Vector2, r: float, col: Color) -> void:
	match shape:
		"round":
			draw_circle(c, r, col)
		"square":
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col, true)
		_:
			draw_rect(Rect2(c - Vector2(r * 0.6, r * 1.3), Vector2(r * 1.2, r * 2.6)), col, true)


func _draw_enemy(e: Dictionary) -> void:
	var p: Vector2 = e["pos"]
	var r := float(e["radius"])
	var bitem := _badge_item(e)
	var sil := String(SILHOUETTE.get(bitem, "blob"))
	var bob := 0.0 if reduced_motion else roundf(sin(time * 7.0 + float(e["id"])) * 1.0)
	var top := p + Vector2(0, -r * 2.0 + bob)
	skin.contact_shadow(self, p, r * 2.4, 0.42)
	# Little robot legs under the waste armor.
	draw_rect(Rect2(p.x - r * 0.6, p.y - 4, 3, 4), Color("2a2f2c"), true)
	draw_rect(Rect2(p.x + r * 0.6 - 3, p.y - 4, 3, 4), Color("2a2f2c"), true)
	var body_c := p + Vector2(0, -r + bob - 2)
	match sil:
		"blob":
			draw_circle(body_c, r, Color("3d6b2f"))
			draw_circle(body_c + Vector2(-2, -3), r * 0.7, Color("5a9440"))
			for i in 3:
				draw_rect(Rect2(body_c.x - r + float(i) * r * 0.8, body_c.y + r * 0.5, 2, 4), Color("3d6b2f"), true)
		"box":
			var stained: bool = bitem == "pizza_box"
			var leafy: bool = bitem == "leaf_box"
			var bw := r * 2.0
			var bh := r * 1.7
			draw_rect(Rect2(body_c.x - bw * 0.5, body_c.y - bh * 0.5, bw, bh), Color("b08452"), true)
			draw_rect(Rect2(body_c.x - bw * 0.5, body_c.y - bh * 0.5 - 4, bw, 5), Color("d8ad72"), true)
			draw_rect(Rect2(body_c.x - bw * 0.5 - 5, body_c.y - 2, 5, 3), Color("b08452"), true)
			draw_rect(Rect2(body_c.x + bw * 0.5, body_c.y - 2, 5, 3), Color("b08452"), true)
			if stained:
				# Contamination must read at a glance: big grease blots and sauce.
				draw_circle(body_c + Vector2(-r * 0.4, -r * 0.2), r * 0.45, Color("6e4419"))
				draw_circle(body_c + Vector2(r * 0.45, r * 0.3), r * 0.35, Color("6e4419"))
				draw_rect(Rect2(body_c.x - 3, body_c.y - bh * 0.5 - 4, 8, 4), Color("c8452f"), true)
				draw_colored_polygon(PackedVector2Array([body_c + Vector2(-6, -bh * 0.5 - 4), body_c + Vector2(6, -bh * 0.5 - 4), body_c + Vector2(0, -bh * 0.5 - 12)]), Color("f0c060"))
			if leafy:
				for i in 4:
					draw_circle(body_c + Vector2(-r + float(i) * r * 0.66, -bh * 0.5 - 5), 4.0, Color("79cf5c") if i % 2 == 0 else Color("3f8f3a"))
			draw_rect(Rect2(body_c.x - bw * 0.5, body_c.y - bh * 0.5, bw, bh), Color("5a4026"), false, 1.0)
		"sheet":
			for i in 3:
				var o := Vector2(float(i) * 2.0 - 2.0, -float(i) * 2.0)
				draw_rect(Rect2(body_c.x - r + o.x, body_c.y - r * 0.9 + o.y, r * 2.0, r * 1.8), Color("fafaf0") if i == 2 else Color("cfcfc8"), true)
			for i in 4:
				draw_rect(Rect2(body_c.x - r + 4, body_c.y - r * 0.9 - 2 + float(i) * 4.0, r * 2.0 - 8, 1), Color("8f8f8f"), true)
			draw_rect(Rect2(body_c.x - r - 4, body_c.y, 4, 2), Color("fafaf0"), true)
			draw_rect(Rect2(body_c.x + r, body_c.y, 4, 2), Color("fafaf0"), true)
		"bottle":
			var h := r * 2.6
			var bx := body_c.x - r * 0.75
			var by := p.y - h - 2 + bob
			draw_rect(Rect2(bx, by, r * 1.5, h), Color(0.62, 0.85, 0.94, 0.85), true)
			draw_rect(Rect2(body_c.x - 3, by - 6, 6, 6), Color("2c5d9e"), true)
			if bitem == "residue_bottle":
				var slosh := 0.0 if reduced_motion else sin(time * 5.0) * 1.5
				draw_rect(Rect2(bx, by + h * 0.4 + slosh, r * 1.5, h * 0.6 - slosh), Color("f0a030"), true)
			draw_rect(Rect2(bx + 2, by + 3, 2, h - 6), Color(1, 1, 1, 0.7), true)
			draw_rect(Rect2(bx, by + h * 0.3, r * 1.5, 3), Color("2c5d9e"), true)
			draw_rect(Rect2(bx, by, r * 1.5, h), Color("1d3a5c"), false, 1.0)
			top = Vector2(body_c.x, by - 6)
		"can":
			var silver: bool = bitem == "tin_can"
			var h2 := r * 2.2
			var cx := body_c.x - r * 0.8
			var cy := p.y - h2 - 2 + bob
			draw_rect(Rect2(cx, cy, r * 1.6, h2), Color("aab6bd") if silver else Color("d24a3a"), true)
			draw_rect(Rect2(cx, cy - 3, r * 1.6, 4), Color("e2e8ea"), true)
			draw_rect(Rect2(body_c.x - 2, cy - 5, 4, 2), Color("8a949b"), true)
			draw_rect(Rect2(cx + 2, cy + 2, 2, h2 - 4), Color(1, 1, 1, 0.8), true)
			if silver:
				for i in 3:
					draw_rect(Rect2(cx, cy + 4 + float(i) * h2 * 0.28, r * 1.6, 1), Color("7d8a92"), true)
			draw_rect(Rect2(cx, cy, r * 1.6, h2), Color("3a2422") if not silver else Color("3c454b"), false, 1.0)
			top = Vector2(body_c.x, cy - 5)
		"crushed":
			var pts := PackedVector2Array([
				body_c + Vector2(-r - 2, 2), body_c + Vector2(-r * 0.4, -r * 0.6), body_c + Vector2(0, -r * 0.2),
				body_c + Vector2(r * 0.5, -r * 0.7), body_c + Vector2(r + 2, 1), body_c + Vector2(r * 0.4, r * 0.6),
				body_c + Vector2(-r * 0.3, r * 0.4)])
			draw_colored_polygon(pts, Color("d24a3a"))
			draw_rect(Rect2(body_c.x - r * 0.6, body_c.y - 1, r * 1.2, 2), Color("e2e8ea"), true)
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, Color("3a2422"), 1.0)
	# The item badge rides on the armor as a large, readable detail.
	var tex: Texture2D = badges.get(bitem, null)
	if tex != null and sil != "bottle" and sil != "can":
		draw_texture(tex, (body_c - Vector2(8, 8)).round())
	# Sensor eye.
	draw_rect(Rect2(top.x - 3, top.y + 3, 2, 2), SFPalette.RED, true)
	draw_rect(Rect2(top.x + 1, top.y + 3, 2, 2), SFPalette.RED, true)
	if float(e["flash"]) > 0.0:
		draw_circle(body_c, r + 1.0, Color(1, 1, 1, 0.45))
	if bool(e.get("elite", false)):
		draw_arc(body_c, r + 5.0, 0.0, TAU, 24, Color(1, 1, 1, 0.35 + 0.2 * sin(time * 5.0)), 1.0)
	if String(e["state"]) == "stun":
		skin.text_c(self, top.x, top.y - 10, "* *", SFPalette.GOLD)
	elif String(e["state"]) == "tele":
		skin.text_c(self, top.x, top.y - 10, "!", SFPalette.RED)


func _draw_core(core: Dictionary) -> void:
	var p: Vector2 = core["pos"]
	var bob := 0.0 if reduced_motion else roundf(sin(time * 4.0 + float(core["id"])) * 1.5)
	var c := p + Vector2(0, -8 + bob)
	skin.contact_shadow(self, p, 14.0, 0.35)
	var super_core: bool = String(core["type"]) == "super"
	var rad := 9.0 if super_core else 5.0
	draw_circle(c, rad + 3.0, Color(0.37, 0.9, 0.85, 0.25 + 0.15 * sin(time * 6.0)))
	draw_circle(c, rad, SFPalette.CYAN)
	draw_circle(c + Vector2(-1, -1), rad * 0.4, SFPalette.PAPER)
	if String(core["state"]) != "dirty":
		return
	var shell: String = model.active_shell(core)
	if super_core:
		# The three educational locks, always shown in order.
		var shells: Array = core["shells"]
		for i in shells.size():
			if i < int(core["shell"]):
				continue
			draw_arc(c, rad + 4.0 + float(i) * 3.0, 0.0, TAU, 28, _cat_color(String(shells[i])), 2.0)
		return
	match shell:
		"green":
			for i in 5:
				var a := float(i) / 5.0 * TAU + time * 0.4
				draw_line(c + Vector2(cos(a), sin(a)) * 3.0, c + Vector2(cos(a + 1.2), sin(a + 1.2)) * 8.0, Color("3f8f3a"), 2.0)
		"blue":
			draw_rect(Rect2(c.x - 7, c.y - 6, 14, 12), Color("b08452"), true)
			draw_rect(Rect2(c.x - 7, c.y - 6, 14, 3), Color("d8ad72"), true)
			draw_rect(Rect2(c.x - 2, c.y - 2, 4, 4), SFPalette.CYAN, true)
		"yellow":
			draw_rect(Rect2(c.x - 6, c.y - 8, 12, 15), Color("aab6bd"), true)
			draw_rect(Rect2(c.x - 6, c.y - 8, 12, 2), Color("e2e8ea"), true)
			draw_rect(Rect2(c.x - 2, c.y - 2, 4, 4), SFPalette.CYAN, true)
	if String(core["type"]) == "dual":
		skin.text_c(self, c.x, c.y - 18, "x2", SFPalette.GOLD)


func _draw_chip() -> void:
	var p: Vector2 = model.chip["pos"]
	var bob := 0.0 if reduced_motion else roundf(sin(time * 3.0) * 2.0)
	skin.contact_shadow(self, p, 16.0, 0.35)
	draw_arc(p + Vector2(0, -8), 14.0, 0.0, TAU, 24, Color(0.9, 0.75, 0.3, 0.5 + 0.3 * sin(time * 5.0)), 2.0)
	var tex: Texture2D = skin.sprites.get("navigation_chip", null)
	if tex != null:
		var s := tex.get_size()
		draw_texture(tex, Vector2(p.x - s.x * 0.5, p.y - s.y - 2 + bob).round())
	skin.text_c(self, p.x, p.y - 34 + bob, "V", SFPalette.GOLD)


func _draw_boss() -> void:
	var b: Dictionary = model.boss
	var p: Vector2 = b["pos"]
	var cat: String = model.active_layer(b)
	var col := _cat_color(cat)
	var entering: bool = String(b["state"]) == "entry"
	var alpha := 1.0
	if entering:
		alpha = clampf(1.0 - float(b["timer"]) / 2.0, 0.2, 1.0)
	skin.contact_shadow(self, p, 80.0, 0.45 * alpha)
	# Legs and hips.
	draw_rect(Rect2(p.x - 26, p.y - 18, 12, 18), Color(0.2, 0.22, 0.2, alpha), true)
	draw_rect(Rect2(p.x + 14, p.y - 18, 12, 18), Color(0.2, 0.22, 0.2, alpha), true)
	# Torso, armored in the active material.
	var torso := Rect2(p.x - 32, p.y - 66, 64, 50)
	draw_rect(torso, Color(0.24, 0.27, 0.25, alpha), true)
	match cat:
		"green":
			draw_circle(p + Vector2(-14, -50), 16.0, Color(0.24, 0.42, 0.18, alpha))
			draw_circle(p + Vector2(14, -38), 18.0, Color(0.35, 0.58, 0.25, alpha))
			for k in ["banana_peel", "leaves", "food_scraps"]:
				var tex: Texture2D = badges.get(k, null)
				var i := ["banana_peel", "leaves", "food_scraps"].find(k)
				if tex != null:
					draw_texture(tex, p + Vector2(-26 + i * 18, -60 + (i % 2) * 14), Color(1, 1, 1, alpha))
		"blue":
			for i in 3:
				draw_rect(Rect2(p.x - 30 + i * 20, p.y - 64 + (i % 2) * 6, 20, 40), Color(0.69, 0.52, 0.32, alpha), true)
				draw_rect(Rect2(p.x - 30 + i * 20, p.y - 64 + (i % 2) * 6, 20, 40), Color(0.35, 0.25, 0.15, alpha), false, 1.0)
			var tb: Texture2D = badges.get("newspaper", null)
			if tb != null:
				draw_texture(tb, p + Vector2(-8, -52), Color(1, 1, 1, alpha))
		"yellow":
			for i in 4:
				var silver := i % 2 == 0
				draw_rect(Rect2(p.x - 30 + i * 15, p.y - 70, 13, 50), Color(0.67, 0.71, 0.74, alpha) if silver else Color(0.82, 0.29, 0.23, alpha), true)
				draw_rect(Rect2(p.x - 28 + i * 15, p.y - 68, 2, 46), Color(1, 1, 1, 0.7 * alpha), true)
	# Arms with a junk-claw, and the head with its sensor bar.
	draw_rect(Rect2(p.x - 46, p.y - 60, 14, 34), Color(0.3, 0.33, 0.31, alpha), true)
	draw_rect(Rect2(p.x + 32, p.y - 60, 14, 34), Color(0.3, 0.33, 0.31, alpha), true)
	draw_rect(Rect2(p.x - 18, p.y - 86, 36, 22), Color(0.2, 0.22, 0.21, alpha), true)
	var eye := 0.6 + 0.4 * sin(time * 6.0)
	if float(b.get("ring_warn", 0.0)) > 0.0:
		eye = 1.0
		draw_arc(p + Vector2(0, -40), 50.0 + 6.0 * sin(time * 20.0), 0.0, TAU, 32, Color(1, 0.4, 0.3, 0.6), 2.0)
	draw_rect(Rect2(p.x - 13, p.y - 79, 26, 5), Color(0.95, 0.25, 0.2, eye * alpha), true)
	draw_rect(torso, Color(col.r, col.g, col.b, 0.9 * alpha), false, 2.0)
	if float(b.get("flash", 0.0)) > 0.0:
		draw_rect(torso, Color(1, 1, 1, 0.35), true)
	if String(b["state"]) == "transition":
		skin.text_c(self, p.x, p.y - 100, "REARMING...", SFPalette.PAPER)


func _draw_bill() -> void:
	var p: Vector2 = model.bill_pos
	var bob := 0.0 if reduced_motion else roundf(sin(time * 2.6) * 1.0)
	skin.contact_shadow(self, p, 14.0, 0.3)
	var tex: Texture2D = skin.sprites.get("bill_on", null)
	if tex != null:
		var s := tex.get_size()
		draw_texture_rect(tex, Rect2(p.x - s.x * 0.5, p.y - s.y - 6 + bob, s.x, s.y), false)


func _draw_nick() -> void:
	var p: Vector2 = model.nick_pos
	var aim: Vector2 = model.aim_point - p
	var dir := "down"
	if absf(aim.x) > absf(aim.y):
		dir = "right" if aim.x > 0.0 else "left"
	elif aim.y < 0.0:
		dir = "up"
	skin.contact_shadow(self, p, 18.0, 0.38)
	if model.is_dashing() and not reduced_motion:
		draw_circle(p + Vector2(0, -10) - model.dash_dir * 10.0, 6.0, Color(0.37, 0.9, 0.85, 0.3))
	var flicker: bool = model.hurt_invuln > 0.0 and int(time * 20.0) % 2 == 0
	var tex: Texture2D = skin.sprites.get("nick_" + dir, null)
	if tex != null and not flicker:
		var s := tex.get_size()
		draw_texture_rect(tex, Rect2(p.x - s.x * 0.5, p.y - s.y, s.x, s.y), false)
	if model.overdrive_active():
		draw_arc(p + Vector2(0, -10), 14.0, 0.0, TAU, 20, _cat_color("rainbow"), 1.0)
	# Blaster tip in the active spectrum.
	var tip := p + Vector2(0, -8) + aim.normalized() * 10.0
	draw_rect(Rect2(tip - Vector2(2, 2), Vector2(4, 4)), _cat_color(SFEcoArena.RAINBOW if model.overdrive_active() else model.spectrum), true)


func _draw_projectiles() -> void:
	for b in model.bolts:
		var bolt: Dictionary = b
		var c := _cat_color(String(bolt["cat"]))
		var p: Vector2 = bolt["pos"]
		draw_line(p - (bolt["dir"] as Vector2) * 7.0, p, Color(c.r, c.g, c.b, 0.5), 2.0)
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), c, true)
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(1, 1, 1, 0.9), true)
	for s in model.shots:
		var sh: Dictionary = s
		var sp: Vector2 = sh["pos"]
		skin.contact_shadow(self, sp + Vector2(0, 10), 8.0, 0.3)
		draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color("4a4a44"), true)
		draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Color("f2a05a"), false, 1.0)


func _draw_beam() -> void:
	if not model.beam_on:
		return
	var from: Vector2 = model.bill_pos + Vector2(0, -16)
	var core: Dictionary = model.core_by_id(model.beam_target_id)
	if core.is_empty():
		var reach: Vector2 = model.nick_pos + (model.aim_point - model.nick_pos).limit_length(40.0)
		draw_line(from, reach, Color(0.37, 0.9, 0.85, 0.25), 1.0)
		return
	var to: Vector2 = (core["pos"] as Vector2) + Vector2(0, -8)
	var ok: bool = model.spectrum == model.active_shell(core)
	var c := _cat_color(model.spectrum) if ok else Color(0.95, 0.3, 0.25)
	var wobble := 0.0 if reduced_motion else sin(time * 30.0)
	draw_line(from, to, Color(c.r, c.g, c.b, 0.35), 5.0)
	draw_line(from, to + Vector2(wobble, 0), Color(c.r, c.g, c.b, 0.95), 1.0)
	draw_arc(to, 9.0, 0.0, TAU, 16, Color(c.r, c.g, c.b, 0.8), 1.0)


func _draw_effects() -> void:
	for e in effects:
		var fx: Dictionary = e
		var f := clampf(float(fx["t"]) / maxf(0.001, float(fx["life"])), 0.0, 1.0)
		var at: Vector2 = fx["at"]
		var a := 1.0 - f
		var kind := String(fx["kind"])
		match kind:
			"hit_green":
				for i in 6:
					var ang := float(i + int(fx["seed"])) * 1.1
					draw_circle(at + Vector2(cos(ang), sin(ang) + f) * (3.0 + f * 12.0), 2.0, Color(0.36, 0.76, 0.35, a))
			"hit_blue":
				for i in 6:
					var ang2 := float(i + int(fx["seed"])) * 1.3
					draw_rect(Rect2(at + Vector2(cos(ang2), sin(ang2)) * (3.0 + f * 14.0), Vector2(3, 2)), Color(0.98, 0.96, 0.88, a) if i % 2 == 0 else Color(0.85, 0.68, 0.45, a), true)
			"hit_yellow", "hit_rainbow":
				var sc := Color(1.0, 0.92, 0.5, a) if kind == "hit_yellow" else Color(_cat_color("rainbow"), a)
				for i in 6:
					var ang3 := float(i) / 6.0 * TAU + float(fx["seed"])
					draw_line(at + Vector2(cos(ang3), sin(ang3)) * 2.0, at + Vector2(cos(ang3), sin(ang3)) * (5.0 + f * 10.0), sc, 1.0)
			"deflect":
				draw_arc(at, 4.0 + f * 6.0, 0.0, TAU, 12, Color(1, 1, 1, a * 0.8), 1.0)
				draw_line(at + Vector2(-5, -5), at + Vector2(5, 5), Color(0.95, 0.35, 0.3, a), 1.0)
				draw_line(at + Vector2(-5, 5), at + Vector2(5, -5), Color(0.95, 0.35, 0.3, a), 1.0)
			"layer", "shell":
				draw_arc(at + Vector2(0, -10), 6.0 + f * 18.0, 0.0, TAU, 20, Color(1, 1, 1, a * 0.8), 2.0)
			"burst":
				for i in 3:
					draw_arc(at, 6.0 + f * (24.0 + float(i) * 10.0), 0.0, TAU, 24, Color(0.9, 0.75, 0.3, a * (0.7 - float(i) * 0.2)), 2.0)
			"puff", "pop":
				draw_circle(at + Vector2(0, -6), 3.0 + f * 6.0, Color(0.7, 0.7, 0.65, a * 0.5))
			"spark":
				for i in 5:
					var ang4 := float(i) * 1.7 + float(fx["seed"])
					draw_line(at + Vector2(0, -8), at + Vector2(0, -8) + Vector2(cos(ang4), sin(ang4)) * (4.0 + f * 6.0), Color(0.8, 0.9, 1.0, a), 1.0)
			"hurt":
				draw_rect(Rect2(at + Vector2(-8, -20), Vector2(16, 20)), Color(0.85, 0.2, 0.2, a * 0.35), true)
			"slam":
				draw_arc(at, 10.0 + f * 30.0, 0.0, TAU, 24, Color(1, 1, 1, a * 0.6), 2.0)
			"land":
				draw_circle(at, 6.0 + f * 16.0, Color(0.6, 0.5, 0.4, a * 0.5))
			"dash":
				draw_circle(at + Vector2(0, -10), 6.0, Color(0.37, 0.9, 0.85, a * 0.4))
			"text":
				skin.text_c(self, at.x, at.y - f * 12.0, String(fx["text"]), Color(fx["color"], a))


## Readability layer: the badge over the targeted enemy and next to nearby
## dirty cores. Stage 1 adds a glowing border in the answer color; from stage 2
## the border is neutral and the item icon must carry the decision.
func _draw_world_badges() -> void:
	var border: bool = model.bordered_badges()
	var target := _targeted_enemy()
	if not target.is_empty():
		var tp: Vector2 = (target["pos"] as Vector2) + Vector2(0, -float(target["radius"]) * 2.0 - 30.0)
		_badge(_badge_item(target), tp, model.active_layer(target), border)
		var layers: Array = target["layers"]
		if layers.size() > 1:
			for i in layers.size():
				var filled: bool = i >= int(target["layer"])
				draw_rect(Rect2(tp.x - layers.size() * 4 + i * 8 + 1, tp.y + 12, 6, 3), SFPalette.PAPER if filled else SFPalette.STEEL_DARK, true)
	var range_px := float((data.get("cores", {}) as Dictionary).get("beam_range", 130.0))
	for c in model.cores:
		var core: Dictionary = c
		if String(core["state"]) != "dirty" or (core["pos"] as Vector2).distance_to(model.nick_pos) > range_px:
			continue
		var cp: Vector2 = (core["pos"] as Vector2) + Vector2(16, -22)
		if String(core["type"]) == "super":
			var shells: Array = core["shells"]
			var x := (core["pos"] as Vector2).x - 26.0
			for i in shells.size():
				var done: bool = i < int(core["shell"])
				var cat := String(shells[i])
				draw_rect(Rect2(x + i * 18, cp.y - 8, 15, 13), SFPalette.INK, true)
				draw_rect(Rect2(x + i * 18, cp.y - 8, 15, 13), _cat_color(cat), false, 1.0)
				skin.text_c(self, x + i * 18 + 7.5, cp.y - 5, "OK" if done else String(_category(cat).get("key", "")), SFPalette.GREEN_OK if done else _cat_color(cat))
			continue
		_badge(String(core["item"]), cp, model.active_shell(core), border)
		var shells2: Array = core["shells"]
		if shells2.size() > 1:
			for i in shells2.size():
				if i < int(core["shell"]):
					continue
				_draw_shape(String(_category(String(shells2[i])).get("shape", "round")), cp + Vector2(-6 + (i - int(core["shell"])) * 10, 14), 3.0, SFPalette.PAPER)


func _badge(item_id: String, center: Vector2, cat: String, bordered: bool) -> void:
	var r := Rect2(center - Vector2(10, 10), Vector2(20, 20))
	draw_rect(r, Color(0.04, 0.06, 0.06, 0.9), true)
	if bordered:
		var c := _cat_color(cat)
		draw_rect(r.grow(1.0), Color(c.r, c.g, c.b, 0.5 + 0.3 * sin(time * 6.0)), false, 2.0)
	else:
		draw_rect(r, SFPalette.STEEL_MID, false, 1.0)
	var tex: Texture2D = badges.get(item_id, null)
	if tex != null:
		draw_texture(tex, (center - Vector2(8, 8)).round())


# ---------------------------------------------------------------- HUD

func _draw_hud() -> void:
	# Top-left: health, shield, match time.
	draw_rect(Rect2(6, 6, 150, 40), Color(0.03, 0.06, 0.06, 0.88), true)
	draw_rect(Rect2(6, 6, 150, 40), SFPalette.STEEL_DARK, false, 1.0)
	skin.text(self, Vector2(12, 11), "HP", SFPalette.GREEN_OK)
	var hp_ratio: float = model.health / maxf(1.0, model.health_max)
	skin.bar(self, Vector2(40, 10), Vector2(76, 8), hp_ratio, SFPalette.RED if hp_ratio < 0.3 else SFPalette.GREEN_OK, SFPalette.INK)
	skin.text(self, Vector2(12, 23), "SHIELD", SFPalette.SHIELD_BLUE)
	skin.bar(self, Vector2(52, 22), Vector2(64, 8), model.shield / maxf(1.0, model.shield_max), SFPalette.SHIELD_BLUE, SFPalette.INK)
	skin.text_r(self, 150, 11, "%d" % int(ceil(model.health)), SFPalette.PAPER)
	skin.text_r(self, 150, 23, "%d" % int(ceil(model.shield)), SFPalette.PAPER)
	skin.text(self, Vector2(12, 35), "TIME " + _clock(model.elapsed), SFPalette.PAPER_DIM)
	# Top-right: station charge, the three combo pips, Overdrive.
	draw_rect(Rect2(VW - 156, 6, 150, 40), Color(0.03, 0.06, 0.06, 0.88), true)
	draw_rect(Rect2(VW - 156, 6, 150, 40), SFPalette.STEEL_DARK, false, 1.0)
	skin.text(self, Vector2(VW - 150, 11), "STATION", SFPalette.CYAN)
	skin.text_r(self, VW - 12, 11, "%d%%" % model.charge, SFPalette.PAPER)
	skin.bar(self, Vector2(VW - 150, 21), Vector2(138, 6), float(model.charge) / 100.0, SFPalette.CYAN, SFPalette.INK)
	skin.text(self, Vector2(VW - 150, 33), "COMBO", SFPalette.PAPER_DIM)
	var cats: Array = model.categories
	for i in cats.size():
		var cat := String(cats[i])
		var lit: bool = model.combo.has(cat)
		var pc := Vector2(VW - 104 + i * 14, 36)
		_draw_shape(String(_category(cat).get("shape", "round")), pc, 4.0, _cat_color(cat) if lit else SFPalette.STEEL_DARK)
	if model.overdrive_active():
		skin.text_r(self, VW - 12, 33, "OD %.1f" % model.overdrive, _cat_color("rainbow"))
	# Top-center: stage, or the remaining objective after the boss.
	var objective := _objective()
	if objective != "":
		var w: float = skin.font.text_width(objective) + 16.0
		draw_rect(Rect2(VW * 0.5 - w * 0.5, 6, w, 13), Color(0.03, 0.06, 0.06, 0.85), true)
		skin.text_c(self, VW * 0.5, 9, objective, SFPalette.GOLD if model.phase == SFEcoArena.PHASE_REWARD else SFPalette.PAPER_DIM)
	if not model.boss.is_empty() and not model.boss_defeated:
		_draw_boss_bar()
	# Bottom-center: the three spectrum slots.
	var slot_w := 92.0
	var x0 := VW * 0.5 - slot_w * 1.5
	for i in cats.size():
		var cat2 := String(cats[i])
		var cd := _category(cat2)
		var selected: bool = model.spectrum == cat2
		var r := Rect2(x0 + i * slot_w + 2, 322 - (3 if selected else 0), slot_w - 4, 30)
		draw_rect(r, Color(0.03, 0.06, 0.06, 0.92), true)
		var cc := _cat_color(cat2)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), cc, true)
		draw_rect(r, cc if selected else SFPalette.STEEL_DARK, false, 2.0 if selected else 1.0)
		skin.text(self, r.position + Vector2(4, 7), String(cd.get("key", "")), SFPalette.PAPER if selected else SFPalette.PAPER_DIM)
		var icon: Texture2D = badges.get(String(cd.get("icon", "")), null)
		if icon != null:
			draw_texture(icon, r.position + Vector2(12, 7))
		_draw_shape(String(cd.get("shape", "round")), r.position + Vector2(r.size.x - 8, 12), 3.0, cc)
		var lines: Array = cd.get("slot_lines", [String(cd.get("name", ""))]) as Array
		for li in lines.size():
			skin.text(self, r.position + Vector2(32, 7 + li * 10), String(lines[li]), cc if selected else SFPalette.PAPER_DIM)
		if selected:
			var mx := r.position.x + r.size.x * 0.5
			draw_colored_polygon(PackedVector2Array([Vector2(mx - 4, r.position.y - 6), Vector2(mx + 4, r.position.y - 6), Vector2(mx, r.position.y - 2)]), cc)
	# Dash readiness.
	var dash_r := Rect2(x0 + slot_w * 3 + 4, 330, 44, 16)
	draw_rect(dash_r, Color(0.03, 0.06, 0.06, 0.92), true)
	var ready: bool = model.dash_ready_fraction() >= 1.0
	skin.text_c(self, dash_r.position.x + 22, dash_r.position.y + 2, "DASH", SFPalette.CYAN if ready else SFPalette.PAPER_DIM)
	skin.bar(self, dash_r.position + Vector2(4, 11), Vector2(36, 3), model.dash_ready_fraction(), SFPalette.CYAN if ready else SFPalette.STEEL_MID, SFPalette.INK)
	# Bill's coaching line and the chip prompt, never on top of each other.
	var prompt_y := 300.0
	if model.near_chip():
		var label := "E  " + String(_reward_info().get("label", "PICK UP"))
		var pw: float = skin.font.text_width(label) + 20.0
		draw_rect(Rect2(VW * 0.5 - pw * 0.5, prompt_y, pw, 15), Color(0.05, 0.09, 0.07, 0.95), true)
		draw_rect(Rect2(VW * 0.5 - pw * 0.5, prompt_y, pw, 15), SFPalette.GOLD, false, 1.0)
		skin.text_c(self, VW * 0.5, prompt_y + 4, label, SFPalette.GOLD)
		prompt_y -= 18.0
	if model.callout_timer > 0.0 and model.callout_text != "":
		var line: String = "BILL: " + model.callout_text
		var lw: float = skin.font.text_width(line) + 20.0
		var ca := clampf(model.callout_timer * 2.0, 0.0, 1.0)
		draw_rect(Rect2(VW * 0.5 - lw * 0.5, prompt_y, lw, 15), Color(0.04, 0.08, 0.09, 0.92 * ca), true)
		draw_rect(Rect2(VW * 0.5 - lw * 0.5, prompt_y, lw, 15), Color(SFPalette.CYAN, ca), false, 1.0)
		skin.text_c(self, VW * 0.5, prompt_y + 4, line, Color(SFPalette.PAPER, ca))
	if banner_timer > 0.0 and banner_text != "":
		var ba := clampf(banner_timer, 0.0, 1.0)
		var bw: float = skin.font.text_width(banner_text, 2) + 24.0
		draw_rect(Rect2(VW * 0.5 - bw * 0.5, 120, bw, 26), Color(0.03, 0.06, 0.06, 0.85 * ba), true)
		skin.text_c(self, VW * 0.5, 126, banner_text, Color(SFPalette.GOLD, ba), 2)
	# Cursor crosshair in the active spectrum.
	if state == State.FIGHT and is_inside_tree():
		var m := get_global_mouse_position()
		var cc2 := _cat_color(SFEcoArena.RAINBOW if model.overdrive_active() else model.spectrum)
		draw_line(m + Vector2(-5, 0), m + Vector2(-2, 0), cc2, 1.0)
		draw_line(m + Vector2(2, 0), m + Vector2(5, 0), cc2, 1.0)
		draw_line(m + Vector2(0, -5), m + Vector2(0, -2), cc2, 1.0)
		draw_line(m + Vector2(0, 2), m + Vector2(0, 5), cc2, 1.0)


func _draw_boss_bar() -> void:
	var b: Dictionary = model.boss
	var layers: Array = b["layers"]
	var w := 180.0
	var x := VW * 0.5 - w * 0.5
	draw_rect(Rect2(x - 4, 22, w + 8, 20), Color(0.03, 0.06, 0.06, 0.88), true)
	skin.text_c(self, VW * 0.5, 24, String((data.get("boss", {}) as Dictionary).get("name", "BOSS")), SFPalette.RED)
	var seg := w / float(layers.size())
	for i in layers.size():
		var l: Dictionary = layers[i]
		var ratio := float(l["armor"]) / maxf(1.0, float(l["max"]))
		skin.bar(self, Vector2(x + i * seg + 1, 33), Vector2(seg - 2, 6), ratio, _cat_color(String(l["cat"])), SFPalette.INK)


func _objective() -> String:
	if model.phase == SFEcoArena.PHASE_REWARD:
		var core_left := false
		for c in model.cores:
			if String((c as Dictionary)["type"]) == "super":
				core_left = true
		if core_left and int(model.charge) < 100:
			return "UNLOCK THE SUPER CORE: 1 > 2 > 3"
		if not model.chip_collected:
			return String(_reward_info().get("label", "PICK UP THE CHIP"))
		return ""
	if not model.boss.is_empty():
		return ""
	var st: Dictionary = model.current_stage()
	return "STAGE %d  %s  NEXT %d%%" % [model.stage_number(), String(st.get("name", "")), int(st.get("until", 80))]


func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- panels

func _draw_guide() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var g: Dictionary = data.get("guide", {}) as Dictionary
	skin.text_c(self, VW * 0.5, 8, String(g.get("title", "SORTING GUIDE")), SFPalette.CYAN, 2)
	skin.text_c(self, VW * 0.5, 26, String(g.get("subtitle", "")), SFPalette.PAPER_DIM)
	var cats: Array = model.categories
	for i in cats.size():
		var cat := String(cats[i])
		var cd := _category(cat)
		var card := Rect2(12 + i * 210, 38, 196, 214)
		var col := _cat_color(cat)
		draw_rect(card, Color(0.05, 0.08, 0.09, 1.0), true)
		draw_rect(card, col, false, 1.0)
		# Large color swatch with the category name on it.
		draw_rect(Rect2(card.position, Vector2(card.size.x, 26)), col, true)
		skin.text_c(self, card.position.x + card.size.x * 0.5, card.position.y + 4, String(cd.get("card_title", cat)), SFPalette.INK)
		skin.text_c(self, card.position.x + card.size.x * 0.5, card.position.y + 15, "PRESS " + String(cd.get("key", "")), SFPalette.INK)
		# Category icon (doubled) inside its shape frame.
		var icon: Texture2D = badges.get(String(cd.get("icon", "")), null)
		var ic := card.position + Vector2(card.size.x * 0.5, 50)
		_draw_shape(String(cd.get("shape", "round")), ic, 19.0, _cat_dark(cat))
		if icon != null:
			draw_texture_rect(icon, Rect2(ic - Vector2(16, 16), Vector2(32, 32)), false)
		skin.text(self, card.position + Vector2(8, 76), "KEY", SFPalette.PAPER_DIM)
		draw_rect(Rect2(card.position + Vector2(30, 73), Vector2(13, 13)), SFPalette.INK, true)
		draw_rect(Rect2(card.position + Vector2(30, 73), Vector2(13, 13)), col, false, 1.0)
		skin.text_c(self, card.position.x + 36.5, card.position.y + 76, String(cd.get("key", "")), col)
		# Two or three recognisable examples.
		var ey := card.position.y + 94
		for ex in cd.get("examples", []) as Array:
			var tex: Texture2D = badges.get(String(ex), null)
			if tex != null:
				draw_texture(tex, Vector2(card.position.x + 8, ey))
			skin.text(self, Vector2(card.position.x + 30, ey + 5), String(model.item(String(ex)).get("name", ex)), SFPalette.PAPER)
			ey += 20
		skin.wrap(self, Vector2(card.position.x + 8, card.position.y + 160), card.size.x - 16, String(cd.get("explanation", "")), SFPalette.PAPER_DIM, 1, 4)
	var ry := 258.0
	for rule in g.get("rules", []) as Array:
		skin.text_c(self, VW * 0.5, ry, String(rule), SFPalette.PAPER)
		ry += 11
	skin.text_c(self, VW * 0.5, ry + 2, "WASD MOVE  SHIFT DASH  MOUSE AIM  CLICK FIRE  1-3/WHEEL COLOR  RMB/E BEAM", SFPalette.PAPER_DIM)
	var label := "BACK" if guide_from_pause else "START"
	skin.button(self, START_BUTTON, label + "  [ENTER]", true, true, SFPalette.GOLD)


func _draw_pause() -> void:
	ui.modal(self, Rect2(200, 92, 240, 170), SFPalette.CYAN)
	skin.text_c(self, 320, 104, "PAUSED", SFPalette.CYAN)
	ui.menu_list(self, pause_menu, Vector2(216, 122), 208.0, 20.0)
	skin.text_c(self, 320, 244, "THE MATCH CLOCK IS STOPPED", SFPalette.PAPER_DIM)


func _draw_defeat() -> void:
	ui.modal(self, Rect2(150, 110, 340, 130), SFPalette.RED)
	skin.text_c(self, 320, 124, "NICK IS DOWN", SFPalette.RED, 2)
	skin.wrap(self, Vector2(172, 150), 296, "The arena restarts from the beginning. Progress before the arena is kept.", SFPalette.PAPER, 1, 3)
	if defeat_timer >= RETRY_DELAY:
		skin.text_c(self, 320, 196, "ENTER / R / CLICK  RETRY", SFPalette.GOLD)
	skin.text_c(self, 320, 216, "ESC  PAUSE MENU", SFPalette.PAPER_DIM)


func _summary_button(i: int) -> Rect2:
	return Rect2(190 + i * 136, 290, 124, 20)


func _draw_summary() -> void:
	ui.modal(self, Rect2(120, 54, 400, 268), SFPalette.CYAN)
	skin.text_c(self, 320, 66, "STATION FULLY CHARGED", SFPalette.CYAN, 2)
	var acc := float(summary.get("accuracy", 1.0))
	var n := int(summary.get("decisions", 0))
	skin.stat_row(self, Vector2(150, 96), "COMPLETION TIME", _clock(float(summary.get("seconds", 0.0))), SFPalette.PAPER, 200.0)
	skin.stat_row(self, Vector2(150, 110), "FIRST-TRY SORTING", ("%d%%  (%d / %d)" % [int(roundf(acc * 100.0)), int(summary.get("correct", 0)), n]) if n > 0 else "NO DECISIONS", SFPalette.PAPER, 200.0)
	skin.stat_row(self, Vector2(150, 124), "REWARD", String(_reward_info().get("name", "")), SFPalette.GOLD, 200.0)
	draw_rect(Rect2(400, 92, 90, 50), SFPalette.INK, true)
	draw_rect(Rect2(400, 92, 90, 50), SFPalette.GOLD, false, 1.0)
	skin.text_c(self, 445, 96, "RANK", SFPalette.PAPER_DIM)
	skin.text_c(self, 445, 108, String(summary.get("rank", "B")), SFPalette.GOLD, 4)
	var reminder := String(summary.get("reminder", ""))
	if reminder == "":
		reminder = "Every material was sorted right on the first try. Great sorting!"
	skin.text(self, Vector2(150, 160), "REMEMBER", SFPalette.CYAN)
	var item_id := String(summary.get("reminder_item", ""))
	var tex: Texture2D = badges.get(item_id, null)
	var tx := 150.0
	if tex != null:
		draw_texture(tex, Vector2(150, 174))
		tx = 172.0
	skin.wrap(self, Vector2(tx, 176), 490.0 - tx, reminder, SFPalette.PAPER, 1, 5)
	skin.text_c(self, 320, 260, "RANK USES FIRST-TRY ACCURACY AND MATCH TIME. PAUSES NEVER COUNT.", SFPalette.PAPER_DIM)
	for i in summary_menu.items.size():
		var it: Dictionary = summary_menu.items[i]
		skin.button(self, _summary_button(i), String(it.get("label", "")), i == summary_menu.index, true, SFPalette.GOLD)
