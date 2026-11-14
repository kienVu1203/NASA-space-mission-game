extends RefCounted
## Pattern scheduler for the Phase 2 encounters. Pure logic: no nodes, no
## drawing, no input, no engine timers. It owns spawn timing, health-based
## escalation and the telegraph window, and it reports what should happen as
## events. The encounter controller forwards those events to the projectile
## field and to the screen.
##
## Escalation is driven only by the fraction of boss health remaining, never by
## elapsed time. Each boss declares health bands in encounters.json; both firing
## frequency and projectile speed rise as health falls, and both are clamped by
## the boss's own `limits` block.
##
## Every random choice comes from a seeded RandomNumberGenerator, so a fight can
## be reproduced exactly in a test.

var boss_id: String = ""
var nick_position: Vector2 = Vector2(320.0, 244.0)

var _bands: Array = []
var _patterns: Dictionary = {}
var _emitters: Dictionary = {}
var _beneficial: Dictionary = {}
var _limits: Dictionary = {}
var _combat: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _seed: int = 0
var _clock: float = 0.0
var _fire_timer: float = 0.0
var _beneficial_timer: float = 0.0
var _pattern_cursor: int = 0
var _emitter_cursor: int = 0
var _pending: Array = []
var _current_band: Dictionary = {}
var _last_heading: Vector2 = Vector2.ZERO
var _opposite_lock_until: float = 0.0


func configure(boss: Dictionary, combat: Dictionary, nick: Vector2) -> void:
	boss_id = String(boss.get("id", ""))
	nick_position = nick
	_bands = boss.get("bands", []) as Array
	_patterns = _as_dict(boss.get("patterns", {}))
	_beneficial = _as_dict(boss.get("beneficial", {}))
	_limits = _as_dict(boss.get("limits", {}))
	_combat = combat
	_emitters = {}
	for e in boss.get("emitters", []) as Array:
		var emitter: Dictionary = _as_dict(e)
		_emitters[String(emitter.get("id", ""))] = emitter
	reset()
	set_seed(int(boss.get("seed", 0)))


func set_seed(value: int) -> void:
	_seed = value
	_rng.seed = value


func seed_value() -> int:
	return _seed


## Returns the encounter to its initial difficulty. Everything that could carry
## state across a retry lives here and is cleared.
func reset() -> void:
	_clock = 0.0
	_fire_timer = maxf(0.0, fire_interval_for(1.0) - 0.15)
	_beneficial_timer = maxf(0.0, beneficial_interval_for(1.0) * 0.65)
	_pattern_cursor = 0
	_emitter_cursor = 0
	_pending = []
	_current_band = {}
	_last_heading = Vector2.ZERO
	_opposite_lock_until = 0.0
	_rng.seed = _seed


# ---------------------------------------------------------------- bands

## The band in force at a given fraction of boss health. Bands are authored from
## full health downwards, and `at_fraction` is the health level at which that
## band *begins*: 1.0 is the opening band, 0.45 starts at 45% health. The active
## band is therefore the highest threshold at or below the current fraction,
## with the last band covering everything under its own threshold.
func band_for_fraction(fraction: float) -> Dictionary:
	var idx := band_index_for_fraction(fraction)
	if idx < 0:
		return {}
	return _as_dict(_bands[idx])


func band_index_for_fraction(fraction: float) -> int:
	if _bands.is_empty():
		return -1
	var f: float = clampf(fraction, 0.0, 1.0)
	var chosen := _bands.size() - 1
	for i in _bands.size():
		var threshold: float = float(_as_dict(_bands[i]).get("at_fraction", -1.0))
		if f >= threshold - 0.000001:
			chosen = i
			break
	return chosen


func current_band() -> Dictionary:
	return _current_band


func fire_interval_for(fraction: float) -> float:
	var band := band_for_fraction(fraction)
	var interval: float = float(band.get("fire_interval", 2.0))
	var floor_interval: float = float(_limits.get("min_fire_interval", 0.5))
	return maxf(floor_interval, interval)


func projectile_speed_for(fraction: float) -> float:
	var band := band_for_fraction(fraction)
	var speed: float = float(band.get("projectile_speed", 100.0))
	var maximum: float = float(_limits.get("max_projectile_speed", speed))
	return clampf(speed, 0.0, maximum)


func max_active_for(fraction: float) -> int:
	var band := band_for_fraction(fraction)
	return mini(int(band.get("max_active", 6)), int(_limits.get("max_active", 99)))


func telegraph_for(fraction: float) -> float:
	var band := band_for_fraction(fraction)
	var t: float = float(band.get("telegraph", 1.0))
	var lo: float = float(_combat.get("min_telegraph_seconds", 0.5))
	var hi: float = float(_combat.get("max_telegraph_seconds", 1.6))
	return clampf(t, lo, hi)


func beneficial_interval_for(fraction: float) -> float:
	var band := band_for_fraction(fraction)
	var interval: float = float(band.get("beneficial_interval", 6.0))
	if interval <= 0.0:
		interval = float(_beneficial.get("interval", 6.0))
	return maxf(1.0, interval)


# ---------------------------------------------------------------- ticking

## Advances the scheduler. Returns events in the order they become due:
##   {"kind": "telegraph", "emitter": String, "position": Vector2,
##    "heading": Vector2, "duration": float, "type": String, "family": String}
##   {"kind": "spawn", "emitter": String, "type": String, "family": String,
##    "position": Vector2, "heading": Vector2, "speed": float}
##
## `active_count` is the number of projectiles already in flight; the scheduler
## stops firing while the field is at the band's cap, so escalation can never
## overwhelm the arena. Timers keep accumulating while capped, so the fight
## resumes immediately once space frees up: the cap throttles rate, not pace.
func tick(delta: float, health_fraction: float, active_count: int) -> Array:
	_clock += delta
	var events: Array = []
	if delta < 0.0:
		return events

	var fraction := clampf(health_fraction, 0.0, 1.0)
	_current_band = band_for_fraction(fraction)

	_fire_timer += delta
	_beneficial_timer += delta

	var cap := max_active_for(fraction)
	var interval := fire_interval_for(fraction)
	if active_count == 0 and _pending.is_empty():
		_fire_timer = maxf(_fire_timer, interval - 0.20)
	if active_count + _pending_count() < cap:
		while _fire_timer >= interval and active_count + _pending_count() < cap:
			_fire_timer -= interval
			events.append_array(_schedule_pattern(fraction))

	# Beneficial energy is deliberately not throttled by the hostile projectile
	# cap: if a player leaves hostiles in flight, running out of motes would make
	# the fight unwinnable rather than merely hard.
	var b_interval := beneficial_interval_for(fraction)
	while _beneficial_timer >= b_interval:
		_beneficial_timer -= b_interval
		events.append_array(_schedule_beneficial(fraction))

	events.append_array(_flush_pending(fraction))
	return events


func pending_count() -> int:
	return _pending.size()


func _pending_count() -> int:
	return _pending.size()


func _flush_pending(fraction: float) -> Array:
	var events: Array = []
	var due: Array = []
	var authoritative_speed := projectile_speed_for(fraction)
	for entry in _pending:
		if float(entry.get("at", 0.0)) <= _clock:
			due.append(entry)
	for e in due:
		_pending.erase(e)
		var event: Dictionary = e["event"]
		event["kind"] = "spawn"
		event["speed"] = authoritative_speed
		events.append(event)
	return events


# ---------------------------------------------------------------- scheduling

func _schedule_pattern(fraction: float) -> Array:
	if _patterns.is_empty():
		return []
	var band: Dictionary = _current_band if not _current_band.is_empty() else band_for_fraction(fraction)
	var names: Array = band.get("patterns", []) as Array
	if names.is_empty():
		return []
	var pattern_name := String(names[_pattern_cursor % names.size()])
	_pattern_cursor += 1
	var pattern: Dictionary = _as_dict(_patterns.get(pattern_name, {}))
	if pattern.is_empty():
		return []

	var all_emitters: Array = pattern.get("emitters", []) as Array
	var ids: Array = []
	for e in all_emitters:
		var id := String(e)
		if _emitters.has(id):
			ids.append(id)
	if ids.is_empty():
		return []

	var count: int = clampi(int(pattern.get("count", 1)), 1, ids.size())
	var ordered: Array = []
	for i in count:
		ordered.append(String(ids[(_emitter_cursor + i) % ids.size()]))
	_emitter_cursor = (_emitter_cursor + count) % ids.size()

	var telegraph := telegraph_for(fraction)
	var speed := projectile_speed_for(fraction)
	var volley: int = clampi(int(pattern.get("volley", 1)), 1, int(_limits.get("max_volley", 3)))
	var spread: float = float(pattern.get("spread_degrees", 0.0))
	var jitter: float = float(pattern.get("jitter_degrees", 0.0))
	var stagger: float = maxf(0.0, float(pattern.get("stagger", 0.0)))
	var type_id := String(pattern.get("type", "bolt"))
	var family := "beneficial" if type_id.begins_with("memory") or type_id.begins_with("brine") else "hostile"

	var events: Array = []
	for i in ordered.size():
		var emitter: Dictionary = _as_dict(_emitters.get(String(ordered[i]), {}))
		var pos := _emitter_position(emitter)
		var heading := _heading_to_nick(pos)
		var delay: float = stagger * float(i)
		for v in volley:
			# Every projectile telegraphs itself, so a warning always precedes
			# exactly one impact. A volley therefore produces a cluster of
			# warnings at the same emitter, which reads as one strong charge-up
			# on screen (the screen counts per emitter, not per warning).
			events.append({
				"kind": "telegraph", "emitter": String(ordered[i]), "position": pos,
				"heading": heading, "duration": telegraph,
				"type": type_id, "family": family,
			})
			var offset := 0.0
			if volley > 1:
				offset = (float(v) - float(volley - 1) * 0.5) * spread
			var angle_jitter: float = _rng.randf_range(-jitter * 0.5, jitter * 0.5)
			var heading_v: Vector2 = heading.rotated(deg_to_rad(offset + angle_jitter))
			_pending.append({
				"at": _clock + telegraph + delay,
				"event": {
					"kind": "spawn", "emitter": String(ordered[i]), "type": type_id,
					"family": family, "position": pos, "heading": heading_v, "speed": speed,
				},
			})
			_last_heading = heading_v
			_opposite_lock_until = _clock + telegraph + delay + float(_combat.get("opposite_direction_push_seconds", 0.4))
	return events


func _schedule_beneficial(fraction: float) -> Array:
	var type_id := String(_beneficial.get("type", ""))
	if type_id == "":
		return []
	var options: Array = _beneficial.get("emitters", []) as Array
	var ids: Array = []
	for e in options:
		var id := String(e)
		if _emitters.has(id):
			ids.append(id)
	if ids.is_empty():
		return []
	var pick := String(ids[_rng.randi_range(0, ids.size() - 1)])
	var emitter: Dictionary = _as_dict(_emitters.get(pick, {}))
	var pos := _emitter_position(emitter)
	var telegraph: float = clampf(float(_beneficial.get("telegraph", 1.0)),
		float(_combat.get("min_telegraph_seconds", 0.5)),
		float(_combat.get("max_telegraph_seconds", 1.6)))
	var speed := projectile_speed_for(fraction)
	var heading := _heading_to_nick(pos)
	var event := {
		"kind": "spawn", "emitter": pick, "type": type_id, "family": "beneficial",
		"position": pos, "heading": heading, "speed": speed,
	}
	_pending.append({"at": _clock + telegraph, "event": event})
	return [{
		"kind": "telegraph", "emitter": pick, "position": pos, "heading": heading,
		"duration": telegraph, "type": type_id, "family": "beneficial",
	}]


## Number of milliseconds until the next scheduled spawn, used by the HUD to
## show a "incoming" cue. Returns -1 when nothing is pending.
func next_spawn_in() -> float:
	if _pending.is_empty():
		return -1.0
	var soonest: float = 999999.0
	for entry in _pending:
		soonest = minf(soonest, float(entry.get("at", 0.0)) - _clock)
	return maxf(0.0, soonest)


func clock() -> float:
	return _clock


# ---------------------------------------------------------------- helpers

func _emitter_position(emitter: Dictionary) -> Vector2:
	return Vector2(float(emitter.get("x", 0.0)), float(emitter.get("y", 0.0)))


func _heading_to_nick(from: Vector2) -> Vector2:
	var v := nick_position - from
	if v.length_squared() < 0.000001:
		return Vector2(0.0, 1.0)
	return v.normalized()


func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v as Dictionary
	return {}
