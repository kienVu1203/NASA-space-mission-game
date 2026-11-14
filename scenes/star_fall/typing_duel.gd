extends Node2D
## The Phase 3 typing encounter screen: the Sky Remnant at the Dawn Tower.
## Draws the arena, the boss, the falling words, Nick, the attacks and the
## learning panel; owns keyboard input, pause and the in-fight journal view.
## It owns no campaign state: it reports learned words and the outcome by
## signal, and the controller records them exactly once.
##
## Controls
##   LETTERS    type the falling words (first letter selects, finish to fire)
##   BACKSPACE  release the selected word
##   ESC        pause: resume, vocabulary journal, restart, main menu
##
## Input safety: only fresh key presses count (held-key echo is ignored), only
## A-Z letters reach the typing model, Ctrl/Alt/Meta chords are ignored, and
## every key is consumed here so no letter can leak into the exploration or
## shield-duel bindings (WASD movement, Space counterattack, M mute).

signal duel_finished(outcome: String)
signal duel_aborted
signal word_learned(entry_id: String)

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFTyping := preload("res://core/star_fall/sf_typing.gd")
const SFTypingEncounter := preload("res://core/star_fall/sf_typing_encounter.gd")
const SFMenu := preload("res://core/star_fall/sf_menu.gd")

const VW := 640
const VH := 360

enum State { FIGHT, VICTORY, DEFEAT, PAUSED, JOURNAL }

var skin
var ui
var vocab
var campaign
var typing_data: Dictionary = {}
var encounter

var state: int = State.FIGHT
var finished: bool = false
var time: float = 0.0
var pause_menu
var pause_origin: int = State.FIGHT
var journal_index: int = 0
## Set by the controller while a dialogue is open over this screen. The arena
## is frozen and every key belongs to the dialogue.
var input_locked: bool = false

var effects: Array = []
var shake: float = 0.0
var boss_flash: float = 0.0
var spawn_pulse: float = 0.0
var reset_flash: float = 0.0
var reset_letter: String = ""
var no_match_flash: float = 0.0
var no_match_letter: String = ""
var last_learned: Dictionary = {}
var last_learned_timer: float = 0.0
var hurt_flash: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO


func setup(skin_ref, ui_ref, typing_ref: Dictionary, deck: Array, seed_value: int, vocab_ref, campaign_ref) -> void:
	skin = skin_ref
	ui = ui_ref
	typing_data = typing_ref
	vocab = vocab_ref
	campaign = campaign_ref
	encounter = SFTypingEncounter.new()
	encounter.setup(typing_data, deck, seed_value)


func _ready() -> void:
	pause_menu = SFMenu.new()
	pause_menu.set_items([
		{"id": "resume", "label": "RESUME", "enabled": true},
		{"id": "journal", "label": "VOCABULARY JOURNAL", "enabled": true},
		{"id": "retry", "label": "RESTART FIGHT", "enabled": true},
		{"id": "menu", "label": "RETURN TO MAIN MENU", "enabled": true},
	], "resume")
	queue_redraw()


# ---------------------------------------------------------------- lifecycle

## A fresh attempt with the same deck. The fight itself starts with start_fight().
func begin_attempt() -> void:
	encounter.reset()
	state = State.FIGHT
	finished = false
	effects.clear()
	shake = 0.0
	boss_flash = 0.0
	reset_flash = 0.0
	no_match_flash = 0.0
	last_learned = {}
	last_learned_timer = 0.0
	queue_redraw()


func start_fight() -> void:
	encounter.begin()


## Retry after a defeat (or from the pause menu): campaign progress, earlier
## rewards and the journal are untouched; the encounter restarts at the easy
## stage with the same deck.
func retry() -> void:
	skin.audio.sfx_back()
	begin_attempt()
	start_fight()


func is_fighting() -> bool:
	return state == State.FIGHT and not input_locked and encounter.is_fighting()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if input_locked:
		return
	get_viewport().set_input_as_handled()
	handle_key(key.keycode, key.unicode, key.ctrl_pressed or key.alt_pressed or key.meta_pressed)


## The single key path, shared by real input and the tests.
func handle_key(keycode: int, unicode: int = 0, chord: bool = false) -> void:
	match state:
		State.PAUSED:
			_pause_key(keycode)
		State.JOURNAL:
			_journal_key(keycode)
		State.VICTORY:
			if keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E, KEY_ESCAPE]:
				_confirm_victory()
		State.DEFEAT:
			if keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_R]:
				retry()
			elif keycode == KEY_ESCAPE:
				_open_pause()
		State.FIGHT:
			if keycode == KEY_ESCAPE:
				skin.audio.sfx_back()
				_open_pause()
			elif keycode == KEY_BACKSPACE:
				encounter.cancel_target()
			elif not chord:
				var letter := SFTyping.letter_from_unicode(unicode)
				if letter != "":
					_consume(encounter.type_letter(letter))
	queue_redraw()


func _notification(what: int) -> void:
	# Losing focus pauses: nothing moves or hurts while the window is away.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == State.FIGHT and not input_locked and encounter.is_fighting():
			_open_pause()


func _confirm_victory() -> void:
	if finished or encounter.victory_timer < _victory_hold():
		return
	finished = true
	skin.audio.sfx_confirm()
	duel_finished.emit("victory")


func _victory_hold() -> float:
	return float((typing_data.get("timing", {}) as Dictionary).get("victory_hold_seconds", 1.8))


# ---------------------------------------------------------------- pause / journal

func _open_pause() -> void:
	pause_origin = state
	state = State.PAUSED
	pause_menu.index = 0


func _pause_key(keycode: int) -> void:
	match keycode:
		KEY_UP, KEY_W:
			pause_menu.move_enabled(-1)
			skin.audio.sfx_select()
		KEY_DOWN, KEY_S:
			pause_menu.move_enabled(1)
			skin.audio.sfx_select()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_pause_item()
		KEY_ESCAPE:
			skin.audio.sfx_back()
			state = pause_origin


func _activate_pause_item() -> void:
	match pause_menu.current_id():
		"resume":
			skin.audio.sfx_blip()
			state = pause_origin
		"journal":
			skin.audio.sfx_blip()
			journal_index = maxi(0, journal_entries().size() - 1)
			state = State.JOURNAL
		"retry":
			retry()
		"menu":
			skin.audio.sfx_back()
			duel_aborted.emit()


func _journal_key(keycode: int) -> void:
	match keycode:
		KEY_UP, KEY_W:
			journal_index = maxi(0, journal_index - 1)
			skin.audio.sfx_select()
		KEY_DOWN, KEY_S:
			journal_index = mini(maxi(0, journal_entries().size() - 1), journal_index + 1)
			skin.audio.sfx_select()
		KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE:
			skin.audio.sfx_back()
			state = State.PAUSED


## The journal as vocabulary entries, read from the campaign (read only).
func journal_entries() -> Array:
	var out: Array = []
	if campaign == null or vocab == null:
		return out
	for id in campaign.vocabulary_journal:
		var e: Dictionary = vocab.entry(String(id))
		if not e.is_empty():
			out.append(e)
	return out


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	time += delta
	var dt := minf(delta, 0.1)
	if not input_locked and (state == State.FIGHT or state == State.VICTORY):
		_advance(dt)
	_update_effects(dt)
	ui.tick(dt)
	queue_redraw()


## One simulation step. Pause, the journal, a dialogue and focus loss all skip
## this, so paused time never moves words, spawns, damages or counts as delay.
func _advance(dt: float) -> void:
	_consume(encounter.tick(dt))


## Test entry point: advances in fixed steps through the same path.
func advance_for(seconds: float, step: float = 0.05) -> void:
	var remaining := maxf(0.0, seconds)
	while remaining > 0.0001:
		var d := minf(step, remaining)
		if not input_locked and (state == State.FIGHT or state == State.VICTORY):
			_advance(d)
		remaining -= d


func _consume(events: Array) -> void:
	for e in events:
		var ev: Dictionary = e
		match String(ev["kind"]):
			"select":
				skin.audio.sfx_select()
			"advance":
				skin.audio.sfx_blip()
			"reset":
				skin.audio.sfx_denied()
				var word: Dictionary = encounter.target_word()
				reset_letter = String(word.get("text", "?"))[0] if not word.is_empty() else "?"
				reset_flash = 0.9
				shake = maxf(shake, 1.0)
			"no_match":
				no_match_letter = String(ev.get("letter", ""))
				no_match_flash = 0.7
			"complete":
				skin.audio.sfx_counterattack()
				var entry: Dictionary = vocab.entry(String(ev["id"])) if vocab != null else {}
				last_learned = entry
				last_learned_timer = 4.0
				_effect("word_burst", Vector2(float(ev["x"]), float(ev["y"])), "7ef2c8", 0.45, String(ev["text"]).to_upper())
				word_learned.emit(String(ev["id"]))
			"attack_hit":
				skin.audio.sfx_counter_hit()
				boss_flash = 1.0
				shake = maxf(shake, 3.0)
				_effect("burst", _boss_point(), "e5c04a", 0.5)
			"spawn":
				spawn_pulse = 0.5
			"miss":
				skin.audio.sfx_player_hurt()
				hurt_flash = 0.5
				shake = maxf(shake, 4.0)
				_effect("hurt", Vector2(float(ev["x"]), _danger_y()), "d9534f", 0.6, "-%d" % int(ev["damage"]))
			"victory":
				skin.audio.sfx_boss_down()
				state = State.VICTORY
				_effect("burst", _boss_point(), "f2d35a", 1.2)
			"defeat":
				skin.audio.sfx_defeat()
				state = State.DEFEAT


func _effect(kind: String, at: Vector2, color_hex: String, life: float, text: String = "") -> void:
	effects.append({"kind": kind, "at": at, "color": color_hex, "t": 0.0, "life": life, "text": text})


func _update_effects(dt: float) -> void:
	var keep: Array = []
	for e in effects:
		var entry: Dictionary = e
		entry["t"] = float(entry["t"]) + dt
		if float(entry["t"]) < float(entry["life"]):
			keep.append(entry)
	effects = keep
	shake = maxf(0.0, shake - dt * 8.0)
	boss_flash = maxf(0.0, boss_flash - dt * 3.0)
	spawn_pulse = maxf(0.0, spawn_pulse - dt)
	reset_flash = maxf(0.0, reset_flash - dt)
	no_match_flash = maxf(0.0, no_match_flash - dt)
	last_learned_timer = maxf(0.0, last_learned_timer - dt)
	hurt_flash = maxf(0.0, hurt_flash - dt)


# ---------------------------------------------------------------- geometry

func _arena() -> Dictionary:
	return typing_data.get("arena", {}) as Dictionary


func _boss_point() -> Vector2:
	var p: Dictionary = _arena().get("boss_point", {"x": 320, "y": 74}) as Dictionary
	return Vector2(float(p["x"]), float(p["y"]))


func _nick_point() -> Vector2:
	var p: Dictionary = _arena().get("nick", {"x": 320, "y": 318}) as Dictionary
	return Vector2(float(p["x"]), float(p["y"]))


func _spawn_y() -> float:
	return float(_arena().get("spawn_y", 112.0))


func _danger_y() -> float:
	return float(_arena().get("danger_y", 278.0))


func _visual(key: String, fallback: Color) -> Color:
	var v := String((encounter.boss.get("visual", {}) as Dictionary).get(key, ""))
	return Color(v) if v != "" else fallback


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_shake_offset = Vector2(round(sin(time * 91.0) * shake), round(cos(time * 77.0) * shake * 0.6)) if shake > 0.0 else Vector2.ZERO
	draw_set_transform(_shake_offset, 0.0, Vector2.ONE)
	_draw_backdrop()
	_draw_boss()
	_draw_lane_field()
	_draw_words()
	_draw_attacks()
	_draw_nick()
	_draw_effects()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_hud()
	_draw_learning_panel()
	_draw_overlay()
	ui.toast(self)


func _draw_backdrop() -> void:
	var sky := _visual("sky", Color("1a1424"))
	draw_rect(Rect2(0, 0, VW, VH), sky, true)
	# Dusk bands toward a sick orange horizon, continuous down to the ground so
	# no hard edge crosses the word field.
	for i in 26:
		var t := float(i) / 25.0
		draw_rect(Rect2(0, 26 + i * 10, VW, 10), sky.lerp(Color("4a2a2a"), t * 0.6), true)
	# Dead forest silhouettes on both flanks, kept low and dark so falling
	# text always sits on a calm background.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	for i in 26:
		var x := rng.randf_range(0.0, VW)
		if x > 120.0 and x < 520.0:
			continue
		var h := rng.randf_range(60.0, 150.0)
		draw_rect(Rect2(round(x), 300 - h, 4, h), Color("1c1820"), true)
		draw_rect(Rect2(round(x) - 6, 300 - h * 0.7, 6, 2), Color("1c1820"), true)
		draw_rect(Rect2(round(x) + 4, 300 - h * 0.5, 7, 2), Color("1c1820"), true)
	# Ground.
	draw_rect(Rect2(0, 286, VW, VH - 286), Color("17141a"), true)
	draw_rect(Rect2(0, 286, VW, 1), Color("2c2633"), true)


## The Sky Remnant: a living mass of smog with wings, a skull of fused debris
## and ember eyes. Not a robot. It flaps, its jaw opens when it sheds a word,
## it flashes when a pulse lands, and it dims as its health falls.
func _draw_boss() -> void:
	var c := _boss_point()
	var smog := _visual("smog", Color("3a3048"))
	var smog_light := _visual("smog_light", Color("5d4d70"))
	var bone := _visual("bone", Color("b9b2a0"))
	var ember := _visual("ember", Color("e07a3a"))
	var eye := _visual("eye", Color("f2d35a"))
	var health: float = encounter.health_fraction()
	var dying: bool = state == State.VICTORY
	var fade: float = clampf(1.0 - encounter.victory_timer / maxf(0.1, _victory_hold()), 0.0, 1.0) if dying else 1.0
	var flap := sin(time * 2.4) * 10.0
	var bob := sin(time * 1.3) * 3.0
	c.y += bob
	# Wings: layered smog fans, each a polygon from the shoulders outward.
	for side in [-1.0, 1.0]:
		for layer in 3:
			var spread := 150.0 - float(layer) * 26.0
			var col := smog.lerp(smog_light, float(layer) * 0.3)
			col.a = (0.85 - float(layer) * 0.15) * fade
			var tip_y := c.y - 30.0 - flap * (1.0 - float(layer) * 0.25)
			var pts := PackedVector2Array([
				c + Vector2(side * 18.0, -6.0),
				Vector2(c.x + side * spread * 0.55, tip_y - 6.0),
				Vector2(c.x + side * spread, tip_y + 4.0),
				Vector2(c.x + side * spread * 0.85, c.y + 10.0 + flap * 0.3),
				Vector2(c.x + side * spread * 0.5, c.y + 22.0),
				c + Vector2(side * 16.0, 18.0),
			])
			draw_colored_polygon(pts, col)
		# Ragged wing-edge streaks, like smoke tearing off.
		for i in 6:
			var ex: float = c.x + side * (40.0 + float(i) * 18.0)
			var ey: float = c.y + 14.0 + sin(time * 3.0 + float(i)) * 3.0
			draw_rect(Rect2(round(ex), round(ey), 2, 6 + (i % 3) * 3), Color(smog.r, smog.g, smog.b, 0.5 * fade), true)
	# Body core: a pulsing ember heart inside the smog.
	var pulse := 0.6 + 0.4 * sin(time * 4.0)
	for r in range(18, 4, -3):
		var a := (1.0 - float(r) / 18.0) * 0.45 * pulse * (0.4 + 0.6 * health) * fade
		draw_rect(Rect2(c.x - r, c.y + 4 - r * 0.7, r * 2, r * 1.4), Color(ember.r, ember.g, ember.b, a), true)
	# Skull of fused debris.
	var skull := Rect2(c.x - 20, c.y - 30, 40, 30)
	draw_rect(skull, Color(bone.r, bone.g, bone.b, fade), true)
	draw_rect(Rect2(skull.position, Vector2(skull.size.x, 3)), Color(bone.lightened(0.15).r, bone.lightened(0.15).g, bone.lightened(0.15).b, fade), true)
	draw_rect(Rect2(c.x - 24, c.y - 22, 4, 12), Color(bone.darkened(0.3).r, bone.darkened(0.3).g, bone.darkened(0.3).b, fade), true)
	draw_rect(Rect2(c.x + 20, c.y - 22, 4, 12), Color(bone.darkened(0.3).r, bone.darkened(0.3).g, bone.darkened(0.3).b, fade), true)
	# Horns of twisted rebar.
	for side in [-1.0, 1.0]:
		for i in 5:
			draw_rect(Rect2(round(c.x + side * (14.0 + float(i) * 4.0)), round(c.y - 32.0 - float(i) * 4.0), 3, 4), Color(bone.darkened(0.2).r, bone.darkened(0.2).g, bone.darkened(0.2).b, fade), true)
	# Eyes: bright while healthy, dimming with damage.
	var eye_a := (0.35 + 0.65 * health) * fade
	for side in [-1.0, 1.0]:
		var ep := Vector2(c.x + side * 9.0, c.y - 18.0)
		draw_rect(Rect2(ep.x - 5, ep.y - 3, 10, 6), Color(0.05, 0.03, 0.05, fade), true)
		draw_rect(Rect2(ep.x - 3, ep.y - 1, 6, 3), Color(eye.r, eye.g, eye.b, eye_a), true)
		_glow(ep, 9.0 + sin(time * 6.0 + side) * 2.0, Color(eye.r, eye.g, eye.b, eye_a))
	# Jaw: drops open when a word is shed.
	var jaw := spawn_pulse * 10.0
	draw_rect(Rect2(c.x - 14, c.y - 4 + jaw, 28, 6), Color(bone.darkened(0.15).r, bone.darkened(0.15).g, bone.darkened(0.15).b, fade), true)
	if jaw > 1.0:
		draw_rect(Rect2(c.x - 12, c.y - 2, 24, jaw), Color(ember.r, ember.g, ember.b, 0.8 * fade), true)
	# Dangling smog tendrils.
	for i in 7:
		var tx := c.x - 30.0 + float(i) * 10.0
		var tendril := 18.0 + float((i * 7) % 12)
		for j in int(tendril / 3.0):
			var sway := sin(time * 2.0 + float(i) + float(j) * 0.4) * float(j) * 0.6
			draw_rect(Rect2(round(tx + sway), round(c.y + 18.0 + float(j) * 3.0), 2, 2), Color(smog_light.r, smog_light.g, smog_light.b, 0.6 * fade), true)
	# Hit flash: the skull blanches and the core flares, rather than a box.
	if boss_flash > 0.0:
		draw_rect(skull, Color(1.0, 0.97, 0.88, 0.55 * boss_flash), true)
		_glow(c + Vector2(0, 4), 26.0 * boss_flash, Color(1.0, 0.9, 0.6, boss_flash))
	# Dissolve on defeat: haze drifting down and away.
	if dying:
		var k: float = encounter.victory_timer
		for i in 40:
			var px := c.x + sin(float(i) * 2.3) * (30.0 + k * 60.0)
			var py := c.y + cos(float(i) * 1.7) * 20.0 + k * 40.0 + float(i % 5) * 4.0
			draw_rect(Rect2(round(px), round(py), 2, 2), Color(smog_light.r, smog_light.g, smog_light.b, 0.5 * (1.0 - fade * 0.5)), true)


func _glow(center: Vector2, radius: float, color: Color) -> void:
	var steps := int(radius)
	for i in steps:
		var f := float(i) / float(maxi(1, steps - 1))
		var r := radius * f
		draw_rect(Rect2(center.x - r, center.y - r * 0.6, r * 2.0, maxf(1.0, r * 1.2)), Color(color.r, color.g, color.b, (1.0 - f) * 0.14 * color.a), true)


## A calm, darkened band behind the falling words and a visible danger line.
func _draw_lane_field() -> void:
	var top := _spawn_y() - 10.0
	draw_rect(Rect2(110, top, 420, _danger_y() - top), Color(0.04, 0.03, 0.06, 0.55), true)
	# Faint lane guides.
	for x in _arena().get("lanes_x", []) as Array:
		var lx := float(x)
		var y := top
		while y < _danger_y():
			draw_rect(Rect2(lx, y, 1, 3), Color(0.4, 0.35, 0.5, 0.16), true)
			y += 9.0
	# Danger line: hazard dashes and a label.
	var dy := _danger_y()
	var pulse := 0.6 + 0.4 * sin(time * 5.0)
	var x2 := 110.0
	var n := 0
	while x2 < 530.0:
		draw_rect(Rect2(x2, dy, 8, 2), Color(SFPalette.RED.r, SFPalette.RED.g, SFPalette.RED.b, (0.55 + 0.4 * pulse) if n % 2 == 0 else 0.25), true)
		x2 += 8.0
		n += 1
	skin.text(self, Vector2(112, dy + 4), "DANGER LINE", Color(SFPalette.RED.r, SFPalette.RED.g, SFPalette.RED.b, 0.8))


func _draw_words() -> void:
	var span := maxf(1.0, _danger_y() - _spawn_y())
	for w in encounter.active:
		var word: Dictionary = w
		var text := String(word["text"])
		var pos := Vector2(float(word["x"]), float(word["y"]))
		var selected: bool = int(word["uid"]) == encounter.typing.target_uid
		var typed: int = encounter.typing.progress if selected else 0
		var f := clampf((pos.y - _spawn_y()) / span, 0.0, 1.0)
		# Urgency: calm green, then gold, then red and blinking near the line.
		var border := SFPalette.GREEN_OK.lerp(SFPalette.GOLD, clampf(f / 0.65, 0.0, 1.0))
		if f > 0.65:
			border = SFPalette.GOLD.lerp(SFPalette.RED, clampf((f - 0.65) / 0.35, 0.0, 1.0))
		if f > 0.85 and int(time * 8.0) % 2 == 0:
			border = SFPalette.PAPER
		if selected:
			border = SFPalette.CYAN
		var tw: float = skin.font.text_width(text)
		var box := Rect2(round(pos.x - tw * 0.5 - 5.0), round(pos.y - 6.0), round(tw + 10.0), 13)
		# Short falling trail above the label.
		draw_rect(Rect2(pos.x - 1, box.position.y - 10, 2, 9), Color(border.r, border.g, border.b, 0.18), true)
		draw_rect(box, Color(0.05, 0.05, 0.08, 0.94), true)
		draw_rect(box, border, false, 2.0 if selected else 1.0)
		if selected:
			skin.text(self, Vector2(box.position.x - 8, box.position.y + 3), ">", SFPalette.CYAN)
		var x0 := box.position.x + 5.0
		if typed > 0:
			skin.text(self, Vector2(x0, box.position.y + 3), text.substr(0, typed), SFPalette.GOLD)
		skin.text(self, Vector2(x0 + skin.font.text_width(text.substr(0, typed)), box.position.y + 3), text.substr(typed), SFPalette.PAPER)


func _draw_attacks() -> void:
	var from := _nick_point() + Vector2(0, -16)
	var to := _boss_point()
	for a in encounter.attacks:
		var attack: Dictionary = a
		var t := clampf(float(attack["t"]) / maxf(0.01, float(attack["flight"])), 0.0, 1.0)
		var head := from.lerp(to, t)
		var tail := from.lerp(to, maxf(0.0, t - 0.18))
		draw_line(tail, head, Color(0.49, 0.95, 0.78, 0.9), 4.0)
		draw_line(tail, head, SFPalette.PAPER, 1.0)
		draw_rect(Rect2(head - Vector2(3, 3), Vector2(6, 6)), Color(0.8, 1.0, 0.92, 0.9), true)


func _draw_nick() -> void:
	var pos := _nick_point()
	skin.contact_shadow(self, pos, 20.0, 0.34)
	var tex: Texture2D = skin.sprites.get("nick_up", null)
	if tex != null:
		var size := tex.get_size()
		draw_texture_rect(tex, Rect2(pos.x - size.x * 0.5, pos.y - size.y, size.x, size.y), false)
	# A small defense console beside Nick: the facility equipment he types into.
	draw_rect(Rect2(pos.x + 14, pos.y - 12, 16, 12), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(pos.x + 16, pos.y - 10, 12, 5), SFPalette.CYAN_DIM if encounter.typing.has_target() else SFPalette.CYAN_DARK, true)
	if hurt_flash > 0.0:
		draw_rect(Rect2(0, 0, VW, VH), Color(0.85, 0.2, 0.2, 0.18 * hurt_flash / 0.5), true)


func _draw_effects() -> void:
	for e in effects:
		var entry: Dictionary = e
		var f := clampf(float(entry["t"]) / maxf(0.001, float(entry["life"])), 0.0, 1.0)
		var at: Vector2 = entry["at"]
		var c := Color(String(entry["color"]))
		match String(entry["kind"]):
			"word_burst":
				for i in 8:
					var ang := float(i) / 8.0 * TAU
					var p := at + Vector2(cos(ang), sin(ang)) * (6.0 + f * 22.0)
					draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(c.r, c.g, c.b, 1.0 - f), true)
				skin.text_c(self, at.x, at.y - 14.0 - f * 12.0, String(entry["text"]), Color(c.r, c.g, c.b, 1.0 - f))
			"burst":
				for i in 3:
					var r := 10.0 + f * (40.0 + float(i) * 14.0)
					_ring(at, r, Color(c.r, c.g, c.b, (1.0 - f) * (0.5 - float(i) * 0.12)))
			"hurt":
				draw_rect(Rect2(at.x - 20, at.y - 3, 40, 6), Color(c.r, c.g, c.b, (1.0 - f) * 0.6), true)
				skin.text_c(self, at.x, at.y - 16.0 - f * 10.0, String(entry["text"]), Color(1.0, 0.8, 0.8, 1.0 - f))


func _ring(center: Vector2, radius: float, color: Color) -> void:
	for i in 20:
		var a0 := float(i) / 20.0 * TAU
		var a1 := float(i + 1) / 20.0 * TAU
		draw_line(center + Vector2(cos(a0), sin(a0)) * radius, center + Vector2(cos(a1), sin(a1)) * radius, color, 1.0)


# ---------------------------------------------------------------- HUD

func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, VW, 26), Color(0.03, 0.02, 0.05, 0.9), true)
	draw_rect(Rect2(0, 26, VW, 1), Color("3a3048"), true)
	skin.text(self, Vector2(10, 5), String(encounter.boss.get("name", "SKY REMNANT")), SFPalette.PAPER)
	skin.text(self, Vector2(10, 15), String(encounter.boss.get("subtitle", "")).substr(0, 30), SFPalette.PAPER_DIM)
	var bar_x := 196.0
	var bar_w := 250.0
	skin.bar(self, Vector2(bar_x, 8), Vector2(bar_w, 10), encounter.health_fraction(), _visual("ember", SFPalette.RUST_LIGHT), SFPalette.INK)
	# One tick per required word, so the bar visibly equals the deck.
	var n: int = encounter.deck.size()
	for i in range(1, n):
		draw_rect(Rect2(round(bar_x + bar_w * float(i) / float(n)), 8, 1, 10), Color(0, 0, 0, 0.35), true)
	skin.text_r(self, VW - 10, 5, "WORDS %d / %d" % [encounter.completed_count(), n], SFPalette.PAPER)
	var stages: Array = (typing_data.get("deck", {}) as Dictionary).get("stages", []) as Array
	var si: int = encounter.current_stage()
	var band := String((stages[si] as Dictionary).get("band", "")) if si < stages.size() else ""
	skin.text_r(self, VW - 10, 15, "STAGE %d / %d  %s" % [si + 1, stages.size(), band.to_upper()], SFPalette.PAPER_DIM)

	# Nick's health and the controls, bottom left.
	var np := Rect2(8, 318, 186, 34)
	draw_rect(np, Color(0.03, 0.05, 0.05, 0.92), true)
	draw_rect(np, SFPalette.GREEN_OK.darkened(0.3), false, 1.0)
	skin.text(self, np.position + Vector2(7, 5), "NICK", SFPalette.GREEN_OK)
	skin.text_r(self, np.end.x - 7, np.position.y + 5, "%d / %d" % [encounter.nick_health, encounter.nick_health_max], SFPalette.PAPER)
	var ratio: float = encounter.nick_fraction()
	var col := SFPalette.GREEN_OK if ratio > 0.6 else (SFPalette.GOLD if ratio > 0.3 else SFPalette.RED)
	skin.bar(self, np.position + Vector2(7, 16), Vector2(np.size.x - 14, 11), ratio, col, SFPalette.INK)
	draw_rect(Rect2(8, 290, 186, 24), Color(0.03, 0.05, 0.05, 0.82), true)
	skin.text(self, Vector2(14, 294), "TYPE WORDS  BKSP RELEASE", SFPalette.PAPER_DIM)
	skin.text(self, Vector2(14, 304), "ESC  PAUSE / JOURNAL", SFPalette.PAPER_DIM)


## The compact learning panel: the selected word with its typed prefix and its
## short meaning, a clear reset notice, and brief success feedback.
func _draw_learning_panel() -> void:
	var r := Rect2(352, 290, 280, 62)
	draw_rect(r, Color(0.03, 0.05, 0.06, 0.94), true)
	var target: Dictionary = encounter.target_word()
	var accent := SFPalette.CYAN_DIM
	if reset_flash > 0.0:
		accent = SFPalette.RED
	draw_rect(r, accent, false, 1.0)
	var x := r.position.x + 8.0
	if not target.is_empty():
		var text := String(target["text"])
		var typed: int = encounter.typing.progress
		skin.text(self, Vector2(x, r.position.y + 6), text.substr(0, typed).to_upper(), SFPalette.GOLD, 2)
		skin.text(self, Vector2(x + skin.font.text_width(text.substr(0, typed).to_upper(), 2), r.position.y + 6), text.substr(typed).to_upper(), SFPalette.PAPER, 2)
		var entry: Dictionary = vocab.entry(String(target["id"])) if vocab != null else {}
		skin.wrap(self, Vector2(x, r.position.y + 26), r.size.x - 16, String(entry.get("definition", "")), SFPalette.PAPER_DIM, 1, 2 if reset_flash > 0.0 else 3)
	elif last_learned_timer > 0.0 and not last_learned.is_empty():
		skin.text(self, Vector2(x, r.position.y + 6), "LEARNED: " + String(last_learned.get("text", "")).to_upper(), SFPalette.GREEN_OK)
		skin.wrap(self, Vector2(x, r.position.y + 18), r.size.x - 16, String(last_learned.get("definition", "")), SFPalette.PAPER_DIM, 1, 3)
		skin.text_r(self, r.end.x - 8, r.end.y - 11, "SAVED TO JOURNAL", SFPalette.CYAN_DIM)
	else:
		skin.text(self, Vector2(x, r.position.y + 8), "TYPE THE FIRST LETTER", SFPalette.PAPER)
		skin.text(self, Vector2(x, r.position.y + 20), "OF A FALLING WORD TO SELECT IT.", SFPalette.PAPER_DIM)
		if no_match_flash > 0.0:
			skin.text(self, Vector2(x, r.position.y + 38), "NO WORD STARTS WITH '%s'" % no_match_letter.to_upper(), SFPalette.GOLD)
	if reset_flash > 0.0:
		# Inside the panel, on its bottom line, so it never covers the field.
		var b := Rect2(r.position.x + 1, r.end.y - 13, r.size.x - 2, 12)
		draw_rect(b, Color(0.25, 0.05, 0.05, 0.95), true)
		skin.text(self, Vector2(b.position.x + 7, b.position.y + 3), "WRONG LETTER - START AGAIN FROM '%s'" % reset_letter.to_upper(), SFPalette.PAPER)


# ---------------------------------------------------------------- overlays

func _draw_overlay() -> void:
	match state:
		State.VICTORY:
			if encounter.victory_timer >= _victory_hold():
				ui.modal(self, Rect2(150, 104, 340, 150), SFPalette.CYAN)
				skin.text_c(self, 320, 118, "SHIELD CLEARED", SFPalette.CYAN, 2)
				skin.wrap(self, Vector2(172, 146), 296,
					"The Sky Remnant has dispersed. %d words typed, %d missed and retried." % [encounter.deck.size(), encounter.misses],
					SFPalette.PAPER, 1, 3)
				skin.text_c(self, 320, 196, "ENTER  CONTINUE", SFPalette.GOLD)
				skin.text_c(self, 320, 214, "THE SHIELD EMITTER IS RECOVERED ON CONTINUE", SFPalette.PAPER_DIM)
		State.DEFEAT:
			ui.modal(self, Rect2(150, 100, 340, 160), SFPalette.RED)
			skin.text_c(self, 320, 114, "NICK IS DOWN", SFPalette.RED, 2)
			skin.wrap(self, Vector2(172, 142), 296,
				"The fight restarts from the easy words with the same deck. Your journal, salvage and earlier components are kept.",
				SFPalette.PAPER, 1, 4)
			skin.text_c(self, 320, 204, "ENTER / R  RETRY", SFPalette.GOLD)
			skin.text_c(self, 320, 224, "ESC  PAUSE MENU", SFPalette.PAPER_DIM)
		State.PAUSED:
			ui.modal(self, Rect2(196, 92, 248, 172), SFPalette.CYAN)
			skin.text_c(self, 320, 104, "PAUSED", SFPalette.CYAN)
			ui.menu_list(self, pause_menu, Vector2(212, 124), 216.0, 20.0)
			skin.text_c(self, 320, 244, "THE WORDS ARE FROZEN WHILE PAUSED", SFPalette.PAPER_DIM)
		State.JOURNAL:
			ui.journal_panel(self, journal_entries(), journal_index)
