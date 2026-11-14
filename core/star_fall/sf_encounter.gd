extends RefCounted
## One complete Phase 2 shield-defense encounter: lifecycle and legal
## transitions only. Pure logic; the duel screen owns drawing and input.
##
## Composition (each part is separately testable and separately tuned):
##   SfEncounterModel      health, charge, phases, counterattack arbitration
##   SfPatternScheduler    spawn timing, telegraphs, health-band escalation
##   SfProjectileField     movement, swept collision, removal
##   SfShield              one authoritative cursor direction and its coverage
##
## This class glues them together and enforces the rules that span them:
##   - attacks stop the moment the boss dies;
##   - a retry resets every encounter-local value;
##   - shield interception always resolves before body impact;
##   - the counterattack damages the boss exactly once.
##
## The campaign layer never reads this class directly. The screen reports the
## finished outcome through one signal, and the controller awards rewards once.

const SFEncounterModel := preload("res://core/star_fall/sf_encounter_model.gd")
const SFPatternScheduler := preload("res://core/star_fall/sf_pattern_scheduler.gd")
const SFProjectileField := preload("res://core/star_fall/sf_projectiles.gd")
const SFShield := preload("res://core/star_fall/sf_shield.gd")

var boss: Dictionary = {}
var combat: Dictionary = {}
var arena_config: Dictionary = {}
var nick_position: Vector2 = Vector2(320.0, 244.0)
var arena: Rect2 = Rect2(0, 0, 640, 360)
var body_radius: float = 8.0

var model
var scheduler
var field
var shield

## Shield band thickness in pixels, from the data file. Presentation only; the
## collision model uses the same radius it is drawn at.
var shield_thickness: float = 5.0

## Set while a briefing dialogue covers the arena. The fight cannot start, and
## nothing can damage Nick or feed charge, until this is false. It is mirrored
## onto the model's own `frozen` flag each tick, so the guarantee holds for a
## caller that reaches the model directly rather than through this class.
var intro_hold: bool = false

## Fired feedback, so the screen can retrigger flashes without polling phases.
var last_block_at: float = 0.0
var last_hit_at: float = 0.0
var last_absorb_at: float = 0.0
var last_strike_at: float = 0.0
var last_spawn_at: float = 0.0
var clock: float = 0.0

## Telegraphs currently being shown. Each entry is the scheduler event plus
## "elapsed". Cleared when the fight ends or resets.
var telegraphs: Array = []


func setup(boss_data: Dictionary, all_data) -> void:
	boss = boss_data
	combat = all_data.combat
	arena_config = all_data.arena
	var nick: Dictionary = arena_config.get("nick", {})
	nick_position = Vector2(float(nick.get("x", 320.0)), float(nick.get("y", 244.0)))
	arena = Rect2(0.0, 0.0,
		float(arena_config.get("width", 640.0)),
		float(arena_config.get("height", 360.0)))

	shield = SFShield.new()
	shield.configure(all_data.shield)
	shield_thickness = maxf(1.0, float(all_data.shield.get("thickness", 5.0)))
	body_radius = maxf(1.0, float(all_data.shield.get("body_radius", 8.0)))

	model = SFEncounterModel.new()
	model.configure(boss, combat)

	field = SFProjectileField.new()
	field.configure(combat, all_data.projectile_types)

	scheduler = SFPatternScheduler.new()
	scheduler.configure(boss, combat, nick_position)

	reset()


## Full reset, including a retry. Everything is rebuilt from the data, so a
## retry cannot inherit charge, health, projectiles, telegraphs, escalation or
## scheduling position from a previous attempt.
func reset() -> void:
	model.reset()
	model.frozen = false
	scheduler.reset()
	field.clear()
	telegraphs.clear()
	intro_hold = false
	clock = 0.0
	last_block_at = 0.0
	last_hit_at = 0.0
	last_absorb_at = 0.0
	last_strike_at = 0.0
	last_spawn_at = 0.0
	shield.configure(shield_config())


func shield_config() -> Dictionary:
	var cfg: Dictionary = {
		"radius": shield.radius,
		"thickness": shield.thickness,
		"coverage_degrees": shield.coverage_degrees,
		"previous_coverage_degrees": shield.previous_coverage_degrees,
		"min_cursor_distance": shield.min_cursor_distance,
		"contact_tolerance": shield.contact_tolerance,
		"angular_tolerance_degrees": shield.angular_tolerance_degrees,
		"charge_meter_margin": shield.charge_meter_margin,
		"initial_direction": {"x": 0.0, "y": 1.0},
	}
	return cfg


## Authoritative travel speed shared by both hostile and beneficial energy at
## the current boss health band.
func authoritative_projectile_speed() -> float:
	if scheduler == null or model == null:
		return 100.0
	return scheduler.projectile_speed_for(model.health_fraction())


## Screen-space rectangle of the charge meter bar anchored above Nick and
## completely outside the shield's visible and collision envelope.
func charge_meter_rect() -> Rect2:
	var w := 64.0
	var h := 6.0
	var bottom_offset: float = shield.charge_meter_bottom_offset(shield_thickness)
	var bar_bottom_y: float = nick_position.y - bottom_offset
	var bar_top_y: float = bar_bottom_y - h
	return Rect2(nick_position.x - w * 0.5, bar_top_y, w, h)


## Full outer plate bounds of the charge meter (including label and frame),
## used to verify clearance from the shield and top HUD.
func charge_plate_rect() -> Rect2:
	var bar := charge_meter_rect()
	return Rect2(bar.position.x - 10.0, bar.position.y - 16.0, bar.size.x + 20.0, bar.size.y + 20.0)


func begin() -> void:
	intro_hold = false
	model.frozen = false
	model.begin_fight()


func is_fighting() -> bool:
	return model.is_fighting() and not intro_hold


func is_over() -> bool:
	return model.is_over()


func result() -> String:
	return model.result


# ---------------------------------------------------------------- input

## Points the shield at a cursor position in canvas space. Ignored while the
## shield is locked by a counterattack, so the visible arc cannot move during an
## animation the player cannot act in.
func aim(cursor_canvas_position: Vector2) -> void:
	if model.shield_locked():
		return
	shield.aim(nick_position, cursor_canvas_position)


## One just-pressed Space edge. Returns true when a counterattack was accepted.
func counterattack() -> bool:
	model.frozen = intro_hold
	if intro_hold or not model.is_fighting():
		return false
	if not model.request_counterattack():
		return false
	# The lock is a short, fair pause: the field is cleared and the scheduler is
	# held, so no projectile can land while the shield is frozen.
	field.clear()
	telegraphs.clear()
	last_strike_at = clock
	return true


# ---------------------------------------------------------------- tick

## Advances one frame. Returns the events that happened, so the screen can play
## feedback:
##   {"kind": "block"|"hit"|"absorb", "point": Vector2, "projectile": Dictionary}
##   {"kind": "counter_strike"}
##   {"kind": "counter_done"}
##   {"kind": "victory_ready"}
##   {"kind": "victory"}  once, on the frame the boss reaches zero health
func tick(delta: float) -> Array:
	clock += delta
	# Mirror the freeze onto the model before anything else runs, so no rule can
	# observe it in a half-applied state.
	model.frozen = intro_hold
	var events: Array = []
	if delta <= 0.0:
		return events

	# Phase timers run in every phase, so flashes finish and the victory hold
	# completes even while nothing else moves.
	var model_events: Array = model.tick(delta)
	for e in model_events:
		var kind := String(e.get("kind", ""))
		if kind == "counter_strike":
			var died: bool = model.apply_counterattack()
			events.append({"kind": "counter_strike", "point": boss_impact_point()})
			if died:
				_stop_combat()
				events.append({"kind": "victory"})
		elif kind == "victory_ready":
			events.append({"kind": "victory_ready"})
		else:
			events.append(e)

	# `intro_hold` is the encounter-level freeze used while a briefing dialogue is
	# up. It is separate from the model's phase because the briefing happens
	# after `begin()`: the fight is in its fight phase, but the player is reading.
	if intro_hold or model.is_over() or not model.accepts_attacks():
		_tick_telegraphs(delta, false)
		return events

	var sched_events: Array = scheduler.tick(delta, model.health_fraction(), field.active_count())
	for e in sched_events:
		var kind := String(e.get("kind", ""))
		if kind == "telegraph":
			var telegraph := {
				"kind": "telegraph",
				"emitter": String(e.get("emitter", "")),
				"position": e.get("position", Vector2.ZERO),
				"heading": e.get("heading", Vector2.ZERO),
				"duration": float(e.get("duration", 0.8)),
				"elapsed": 0.0,
				"type": String(e.get("type", "")),
				"family": String(e.get("family", "hostile")),
			}
			# One visual warning per emitter: a volley's cluster of warnings
			# reads as a single, stronger charge-up rather than five overlapping
			# rings on one coil.
			var merged := false
			for existing in telegraphs:
				var t: Dictionary = existing
				if String(t.get("emitter", "")) == String(telegraph["emitter"]):
					t["duration"] = maxf(float(t.get("duration", 0.0)), float(telegraph["duration"]))
					t["elapsed"] = minf(float(t.get("elapsed", 0.0)), float(telegraph["elapsed"]))
					merged = true
					break
			if not merged:
				telegraphs.append(telegraph)
			# Forwarded as well as stored: the screen draws from `telegraphs`,
			# and a caller that only watches events still sees every warning.
			events.append(telegraph.duplicate())
		elif kind == "spawn":
			var type_id := String(e.get("type", ""))
			var family := String(e.get("family", "hostile"))
			var spawn_speed := authoritative_projectile_speed()
			field.spawn(type_id, e.get("position", Vector2.ZERO), e.get("heading", Vector2(0, 1)), spawn_speed)
			last_spawn_at = clock
			# The forwarded event keeps the family, type, position, and speed so a
			# listener (the HUD, a test) can inspect spawned projectiles directly.
			events.append({
				"kind": "spawn",
				"emitter": String(e.get("emitter", "")),
				"type": type_id,
				"family": family,
				"position": e.get("position", Vector2.ZERO),
				"speed": spawn_speed,
			})

	# Enforce speed parity across active projectiles when difficulty bands change.
	field.sync_speeds(authoritative_projectile_speed())
	var collisions: Array = field.update(delta, nick_position, shield, body_radius, arena)
	for c in collisions:
		var collision: Dictionary = c
		var projectile: Dictionary = collision.get("projectile", {})
		var point: Vector2 = collision.get("point", Vector2.ZERO)
		match String(collision.get("kind", "")):
			"block":
				model.note_block()
				last_block_at = clock
				events.append({"kind": "block", "point": point, "projectile": projectile})
			"hit":
				var amount := int(projectile.get("damage", 0))
				var died: bool = model.damage_nick(amount)
				last_hit_at = clock
				events.append({"kind": "hit", "point": point, "projectile": projectile})
				if died:
					_stop_combat()
					events.append({"kind": "defeat"})
			"absorb":
				var gained: int = model.absorb_charge(int(projectile.get("charge", 0)))
				last_absorb_at = clock
				events.append({"kind": "absorb", "point": point, "projectile": projectile, "gained": gained})

	_tick_telegraphs(delta, true)
	return events


func _tick_telegraphs(delta: float, running: bool) -> void:
	var keep: Array = []
	for entry in telegraphs:
		var t: Dictionary = entry
		if running:
			t["elapsed"] = float(t.get("elapsed", 0.0)) + delta
		if bool(t.get("spawned", false)):
			continue
		if float(t.get("elapsed", 0.0)) >= float(t.get("duration", 0.0)):
			continue
		keep.append(t)
	telegraphs = keep


## Stops spawning, movement, damage and charge gain, and clears every live
## projectile. Called on victory and on defeat, so nothing left in flight can
## hurt Nick after the outcome is decided.
func _stop_combat() -> void:
	field.clear()
	telegraphs.clear()


## Where a counterattack lands, in arena space: the centre of the robot's
## chassis, which is drawn behind Nick.
func boss_impact_point() -> Vector2:
	return Vector2(arena.size.x * 0.5, float(arena_config.get("ground_y", 300.0)) - 88.0)


func telegraph_for_emitter(emitter_id: String) -> Dictionary:
	for entry in telegraphs:
		var t: Dictionary = entry
		if String(t.get("emitter", "")) == emitter_id:
			return t
	return {}


func health_fraction() -> float:
	return model.health_fraction()


func phase() -> String:
	return model.phase
