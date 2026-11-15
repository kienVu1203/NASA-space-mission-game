extends RefCounted
## The playable flight segments of the escape cinematic.
##
## Two kinds share one lane model:
##   * `debris` — VELA holds the left of the field while bodies stream in from
##     the right. Steering is vertical only. A collision is reported to the
##     screen, which plays a short impact beat and then calls `restart()`, so
##     the segment begins again with an empty field and no progress carried.
##   * `portal` — no obstacles. The player lines the ship up with the opening
##     seam; enough time inside the mouth enters it.
##
## Pure by construction: no nodes, no `InputEvent`, no drawing, no campaign
## state. The screen feeds it a steering direction (and, for the mouse, a target
## height) and draws the returned state; the headless suite drives it directly.
##
## Guaranteed progress. After `assist_after_restarts` restarts, or once
## `assist_after_seconds` have passed, the navigation chip takes over: the ship
## is steered through the field and collisions stop restarting the segment. That
## keeps a player who never touches the controls out of a dead end, and it is
## what the story already says the chip does. Nothing here can strand the
## sequence, and nothing here can make a certified design fail.

const TAU_FULL := 6.283185307179586

## `debris` or `portal`.
var kind: String = "debris"

# Lane and ship.
var lane_top: float = 64.0
var lane_bottom: float = 282.0
var ship_x: float = 96.0
var ship_y: float = 173.0
var ship_half_height: float = 11.0
var steer_speed: float = 165.0

# Debris field.
var obstacle_speed: float = 150.0
var speed_growth: float = 70.0
var spawn_interval: float = 0.56
var spawn_jitter: float = 0.20
var max_obstacles: int = 11
var min_radius: float = 5.0
var max_radius: float = 15.0

# Portal.
var portal_x: float = 500.0
var portal_y: float = 180.0
var portal_home_y: float = 180.0
var portal_half_height: float = 42.0
var portal_drift: float = 28.0
var portal_drift_speed: float = 0.55
var align_seconds: float = 0.70

# Pacing and the guaranteed exit.
var target_seconds: float = 15.0
var assist_after_restarts: int = 2
var assist_after_seconds: float = 26.0

# State.
var time: float = 0.0
var progress: float = 0.0
var cleared: bool = false
var entered: bool = false
var hits: int = 0
var restarts: int = 0
var assist: bool = false
## Set when a body has struck the hull. The field holds still and reports
## nothing more until `restart()`: one strike is one strike, never a run of them
## across the frames the screen spends showing the impact.
var impact_pending: bool = false
var aligned_time: float = 0.0
var obstacles: Array = []

var _spawn_timer: float = 0.0
var _last_spawn_y: float = -999.0
var _last_spawn_hh: float = 0.0
var _spawn_seq: int = 0
var _seed: int = 7321
var _rng: RandomNumberGenerator = null


## Reads one block of `data/star_fall/finale.json` -> cinematic.flight.<kind>.
func configure(config: Dictionary) -> void:
	kind = String(config.get("kind", "debris"))
	lane_top = float(config.get("lane_top", 64.0))
	lane_bottom = float(config.get("lane_bottom", 282.0))
	ship_x = float(config.get("ship_x", 96.0))
	ship_half_height = float(config.get("ship_half_height", 11.0))
	steer_speed = float(config.get("steer_speed", 165.0))
	obstacle_speed = float(config.get("obstacle_speed", 150.0))
	speed_growth = float(config.get("speed_growth", 70.0))
	spawn_interval = float(config.get("spawn_interval", 0.56))
	spawn_jitter = float(config.get("spawn_jitter", 0.20))
	max_obstacles = int(config.get("max_obstacles", 11))
	min_radius = float(config.get("min_radius", 5.0))
	max_radius = float(config.get("max_radius", 15.0))
	portal_x = float(config.get("portal_x", 500.0))
	portal_home_y = float(config.get("portal_y", 180.0))
	portal_y = portal_home_y
	portal_half_height = float(config.get("portal_half_height", 42.0))
	portal_drift = float(config.get("portal_drift", 28.0))
	portal_drift_speed = float(config.get("portal_drift_speed", 0.55))
	align_seconds = float(config.get("align_seconds", 0.70))
	target_seconds = float(config.get("target_seconds", 15.0))
	assist_after_restarts = int(config.get("assist_after_restarts", 2))
	assist_after_seconds = float(config.get("assist_after_seconds", 26.0))
	_seed = int(config.get("seed", 7321))
	_rng = RandomNumberGenerator.new()
	_rng.seed = _seed
	begin()


## A fresh attempt from the top: counters and field clear.
func begin() -> void:
	hits = 0
	restarts = 0
	assist = false
	reset_segment()


## The segment state, without the attempt counters. A collision calls this
## through `restart()`, so the field is empty and progress is zero when play
## resumes; the subtitles, which live on the scene clock, keep running.
func reset_segment() -> void:
	obstacles.clear()
	time = 0.0
	progress = 0.0
	cleared = false
	entered = false
	impact_pending = false
	aligned_time = 0.0
	ship_y = (lane_top + lane_bottom) * 0.5
	_spawn_timer = spawn_interval * 0.8
	_last_spawn_y = -999.0
	_last_spawn_hh = 0.0
	_spawn_seq = 0
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	_rng.seed = _seed + restarts * 7919
	portal_y = portal_home_y


## A collision was shown and has finished its feedback beat. The attempt count
## decides when the navigation chip stops letting the field reset it.
func restart() -> void:
	restarts += 1
	if restarts >= assist_after_restarts:
		assist = true
	reset_segment()


# ---------------------------------------------------------------- steering

func ship_min_y() -> float:
	return lane_top + ship_half_height


func ship_max_y() -> float:
	return lane_bottom - ship_half_height


func set_ship_y(value: float) -> void:
	ship_y = clampf(value, ship_min_y(), ship_max_y())


## Keyboard steering: -1 up, +1 down, 0 held still.
func steer(direction: float, delta: float) -> void:
	if direction == 0.0:
		return
	set_ship_y(ship_y + direction * steer_speed * delta)


## Mouse steering: move toward the pointer height at the same top speed, with a
## small proportional pull so the ship settles instead of overshooting.
func steer_toward(target_y: float, delta: float) -> void:
	var gap: float = target_y - ship_y
	var step: float = steer_speed * 1.35 * delta
	if absf(gap) <= step:
		set_ship_y(target_y)
		return
	set_ship_y(ship_y + signf(gap) * step)


# ---------------------------------------------------------------- tick

## Advances one frame. Returns the events the screen cares about:
##   {"type": "hit"|"cleared"|"entered"|"assist"|"spawn"}
## The ship moves before the field: input is never a frame late.
func tick(delta: float, direction: float) -> Array:
	var events: Array = []
	if cleared or entered or impact_pending:
		return events
	time += delta
	if not assist and time >= assist_after_seconds:
		assist = true
		events.append({"type": "assist"})
	steer(direction, delta)
	if kind == "portal":
		_tick_portal(delta, events)
	else:
		_tick_debris(delta, events)
	return events


func _tick_debris(delta: float, events: Array) -> void:
	progress = clampf(time / maxf(0.01, target_seconds), 0.0, 1.0)
	if assist:
		_autopilot(delta)

	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and obstacles.size() < max_obstacles:
		_spawn_obstacle()
		_spawn_timer = maxf(0.16, spawn_interval + _rng.randf_range(-spawn_jitter, spawn_jitter))
		events.append({"type": "spawn"})

	var speed: float = obstacle_speed + speed_growth * progress
	var impact: Dictionary = {}
	var index: int = 0
	while index < obstacles.size():
		var body: Dictionary = obstacles[index]
		var previous_x: float = float(body["x"])
		var current_x: float = previous_x - speed * delta
		body["x"] = current_x
		if impact.is_empty() and not assist:
			# Swept on the horizontal axis: a step larger than the hull can
			# never tunnel through the ship without being reported.
			var half_w: float = float(body["hw"])
			var half_h: float = float(body["hh"])
			var vertical: bool = absf(ship_y - float(body["y"])) <= half_h + ship_half_height * 0.72
			if vertical and ship_x >= current_x - half_w - 4.0 and ship_x <= previous_x + half_w + 4.0:
				impact = {"type": "hit", "x": ship_x + half_w * 0.6, "y": float(body["y"])}
		if current_x < -90.0:
			obstacles.remove_at(index)
		else:
			index += 1
	if not impact.is_empty():
		hits += 1
		impact_pending = true
		# The field stays as it was for the impact frame; the screen freezes the
		# segment for a beat and then calls restart().
		events.append(impact)
		return
	if progress >= 1.0:
		cleared = true
		events.append({"type": "cleared"})


func _tick_portal(delta: float, events: Array) -> void:
	progress = clampf(time / maxf(0.01, target_seconds), 0.0, 1.0)
	if assist:
		portal_y = lerpf(portal_y, ship_y, clampf(delta * 2.6, 0.0, 1.0))
	else:
		portal_y = portal_home_y + sin(time * portal_drift_speed) * portal_drift
	if absf(ship_y - portal_y) <= portal_half_height:
		aligned_time += delta
	else:
		aligned_time = maxf(0.0, aligned_time - delta * 0.6)
	if aligned_time >= align_seconds:
		entered = true
		events.append({"type": "entered"})
	elif assist and time >= assist_after_seconds:
		entered = true
		events.append({"type": "entered"})


func _spawn_obstacle() -> void:
	var half_w: float = _rng.randf_range(min_radius, max_radius)
	var half_h: float = half_w * _rng.randf_range(0.74, 1.08)
	var low: float = lane_top + half_h + 2.0
	var high: float = lane_bottom - half_h - 2.0
	# Candidates are rejected until the lane between this body and the previous
	# one is wide enough for the hull to cross. Without this the field could
	# spawn a wall, and a wall is not a dodge. The two lane edges are always
	# offered as a fallback, and they always pass: the previous body can only be
	# at one height.
	var best: float = _rng.randf_range(low, high)
	var best_gap: float = -1.0
	for attempt in 12:
		var candidate: float = _rng.randf_range(low, high)
		var gap: float = separation(candidate, half_h, _last_spawn_y, _last_spawn_hh)
		if gap >= required_separation(half_h, _last_spawn_hh):
			best = candidate
			best_gap = gap
			break
		if gap > best_gap:
			best_gap = gap
			best = candidate
	if best_gap >= 0.0 and best_gap < required_separation(half_h, _last_spawn_hh):
		# No random candidate cleared the bar: take the far edge instead.
		var edge_gap: float = separation(high, half_h, _last_spawn_y, _last_spawn_hh)
		var low_gap: float = separation(low, half_h, _last_spawn_y, _last_spawn_hh)
		best = high if edge_gap >= low_gap else low
	_last_spawn_y = best
	_last_spawn_hh = half_h
	obstacles.append({
		"x": float(VW_SPAWN_X) + half_w,
		"y": best,
		"hw": half_w,
		"hh": half_h,
		"tone": _rng.randi_range(0, 2),
		"phase": _rng.randf_range(0.0, TAU_FULL),
		# Spawn order, so a test (or a debug overlay) can reason about the field
		# in the order the ship actually meets it.
		"seq": _spawn_seq,
	})
	_spawn_seq += 1


## The clear height between two bodies, measured edge to edge.
static func separation(y_a: float, half_h_a: float, y_b: float, half_h_b: float) -> float:
	if y_b < -900.0:
		return 9999.0
	return absf(y_a - y_b) - half_h_a - half_h_b


## The narrowest corridor the hull can fly through between two bodies.
func required_separation(half_h_a: float, half_h_b: float) -> float:
	return ship_half_height * 2.0 + 18.0


## Spawn just outside the right edge. Kept as a constant so the field is the
## same on every screen size; drawing never depends on it.
const VW_SPAWN_X := 676.0


## The navigation chip's own flying. It picks the larger free gap above or below
## each body in the near field and slides toward it; it never teleports.
func _autopilot(delta: float) -> void:
	var target: float = ship_y
	for entry in obstacles:
		var body: Dictionary = entry
		var dx: float = float(body["x"]) - ship_x
		if dx < -24.0 or dx > 250.0:
			continue
		var top: float = float(body["y"]) - float(body["hh"]) - ship_half_height - 10.0
		var bottom: float = float(body["y"]) + float(body["hh"]) + ship_half_height + 10.0
		if ship_y > top and ship_y < bottom:
			var room_above: float = top - lane_top
			var room_below: float = lane_bottom - bottom
			if room_above > room_below:
				target = top - 4.0
			else:
				target = bottom + 4.0
	steer_toward(clampf(target, ship_min_y(), ship_max_y()), delta)


# ---------------------------------------------------------------- queries

func is_active() -> bool:
	return not cleared and not entered


func alignment_fraction() -> float:
	if align_seconds <= 0.0:
		return 0.0
	return clampf(aligned_time / align_seconds, 0.0, 1.0)


func is_aligned() -> bool:
	return absf(ship_y - portal_y) <= portal_half_height


func active_obstacles() -> Array:
	return obstacles


func progress_fraction() -> float:
	return progress
