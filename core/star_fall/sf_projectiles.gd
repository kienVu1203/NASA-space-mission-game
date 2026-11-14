extends RefCounted
## Projectile field for the Phase 2 encounters. Pure logic: no nodes, no
## drawing, no input. One field per encounter; the screen draws `projectiles`
## and the encounter controller reads the events `update()` returns.
##
## Collision is swept, not sampled. Each frame a projectile's motion is a
## segment; the field solves where that segment crosses the shield shell and
## where it comes within Nick's body radius, then resolves whichever happens
## first. That ordering is what makes fast projectiles safe and is what stops a
## shield hit from also registering as a body hit.

## A projectile is a plain Dictionary so the whole field can be reset by
## clearing one Array:
## {
##   "type": String, "family": "hostile"|"beneficial", "pos": Vector2,
##   "dir": Vector2, "speed": float, "damage": int, "charge": int,
##   "radius": float, "age": float, "life": float, "alive": bool,
##   "shape": String, "color": String, "outline": String, "trail": String,
## }
var projectiles: Array = []

var life_seconds: float = 14.0
var offscreen_margin: float = 48.0
var _next_id: int = 1

var _types: Dictionary = {}


func configure(combat: Dictionary, types: Dictionary) -> void:
	life_seconds = maxf(1.0, float(combat.get("projectile_life_seconds", life_seconds)))
	offscreen_margin = maxf(0.0, float(combat.get("offscreen_margin", offscreen_margin)))
	_types = types


## Adds one projectile travelling from `position` along `direction`.
## Hostile and beneficial projectiles use the same authoritative speed at a
## given difficulty band (`speed`), without per-category speed multipliers.
## Returns the new entry so callers can tag it (for example with its emitter).
func spawn(type_id: String, position: Vector2, direction: Vector2, speed: float) -> Dictionary:
	var spec: Dictionary = _as_dict(_types.get(type_id, {}))
	var dir := direction.normalized() if direction.length_squared() > 0.000001 else Vector2(0.0, 1.0)
	var authoritative_speed: float = maxf(1.0, speed)
	var p := {
		"id": _next_id,
		"type": type_id,
		"family": String(spec.get("family", "hostile")),
		"pos": position,
		"prev": position,
		"dir": dir,
		"speed": authoritative_speed,
		"damage": int(spec.get("damage", 0)),
		"charge": int(spec.get("charge", 0)),
		"radius": float(spec.get("radius", 4.0)),
		"shape": String(spec.get("shape", "chevron")),
		"color": String(spec.get("color", "ffffff")),
		"outline": String(spec.get("outline", "000000")),
		"trail": String(spec.get("trail", "ffffff")),
		"age": 0.0,
		"life": life_seconds,
		"alive": true,
	}
	_next_id += 1
	projectiles.append(p)
	return p


## Synchronises all active projectiles (both hostile and beneficial) to the
## encounter's current authoritative band speed so difficulty transitions keep
## 100% speed parity across in-flight projectiles.
func sync_speeds(target_speed: float) -> void:
	var s := maxf(1.0, target_speed)
	for entry in projectiles:
		var p: Dictionary = entry
		if bool(p.get("alive", false)):
			p["speed"] = s


func clear() -> void:
	projectiles.clear()
	_next_id = 1


func active_count() -> int:
	var n := 0
	for p in projectiles:
		if bool((p as Dictionary).get("alive", false)):
			n += 1
	return n


## Advances every projectile and resolves collisions in travel order.
##
## `nick_position` is Nick's centre, `shield` is an SfShield configured for this
## encounter, `body_radius` is Nick's own radius (the shield radius is separate).
## `arena` is the 640x360 rect; projectiles outside it by more than the margin
## are removed.
##
## Returns events, in the order they happened:
##   {"kind": "block"|"hit"|"absorb", "point": Vector2, "projectile": Dictionary}
## Only alive projectiles are ever reported.
func update(delta: float, nick_position: Vector2, shield, body_radius: float, arena: Rect2) -> Array:
	var events: Array = []
	for entry in projectiles:
		var p: Dictionary = entry
		if not bool(p.get("alive", false)):
			continue
		p["age"] = float(p.get("age", 0.0)) + delta
		var p0: Vector2 = p["pos"]
		var p1: Vector2 = p0 + (p["dir"] as Vector2) * float(p["speed"]) * delta

		var outcome: Dictionary = _resolve_segment(p, p0, p1, nick_position, shield, body_radius)
		match String(outcome.get("kind", "fly")):
			"shield":
				p["alive"] = false
				p["pos"] = outcome.get("point", p1)
				events.append({"kind": "block", "point": p["pos"], "projectile": p})
			"body":
				p["alive"] = false
				p["pos"] = outcome.get("point", p1)
				var kind := "hit"
				if String(p.get("family", "hostile")) == "beneficial":
					kind = "absorb"
				events.append({"kind": kind, "point": p["pos"], "projectile": p})
			_:
				p["prev"] = p0
				p["pos"] = p1
				if float(p.get("age", 0.0)) >= float(p.get("life", life_seconds)):
					p["alive"] = false
				elif not _inside_arena(p1, arena):
					p["alive"] = false
	_prune()
	if shield != null and shield.has_method("commit_step"):
		shield.commit_step()
	return events


## Removes dead entries so the array does not grow without bound over a long
## fight. Ids are stable for anything that grabbed a reference earlier.
func _prune() -> void:
	var keep: Array = []
	for entry in projectiles:
		if bool((entry as Dictionary).get("alive", false)):
			keep.append(entry)
	projectiles = keep


## Resolves one frame of one projectile. Returns
## {"kind": "shield"|"body"|"fly", "point": Vector2}.
##
## This is the whole collision contract and it is public so tests can feed it
## arbitrary segments without running a frame loop. Both linear projectile
## travel and angular shield sweeps (`prev_direction` -> `direction`) are
## resolved continuously within the shield's radial reach `[r_inner, r_outer]`.
func _resolve_segment(p: Dictionary, p0: Vector2, p1: Vector2, nick_position: Vector2, shield, body_radius: float) -> Dictionary:
	var a: Vector2 = p0 - nick_position
	var b: Vector2 = p1 - p0
	var projectile_radius: float = float(p.get("radius", 4.0))
	var body_hit_r: float = maxf(1.0, body_radius) + projectile_radius

	var body_t := -1.0
	var body_point := Vector2.ZERO
	if a.length() <= body_hit_r:
		body_t = 0.0
		body_point = p0
	else:
		var body_hit: Dictionary = _segment_circle(a, b, body_hit_r)
		if bool(body_hit.get("ok", false)) and float(body_hit.get("t", -1.0)) >= 0.0:
			body_t = float(body_hit["t"])
			body_point = p0 + b * body_t

	var shield_t := -1.0
	var shield_point := Vector2.ZERO
	if shield != null and body_t != 0.0:
		var shield_r: float = float(shield.radius)
		var half_thick: float = float(shield.thickness) * 0.5
		var tol: float = float(shield.contact_tolerance)
		var r_outer: float = shield_r + half_thick + projectile_radius + tol
		var r_inner: float = maxf(body_hit_r + 1.0, shield_r - half_thick - projectile_radius - tol)
		var a_len: float = a.length()

		# Only projectiles outside or inside the shield's physical shell [r_inner, r_outer]
		# can be intercepted; a projectile already past r_inner is inside the shield orbit.
		if a_len >= r_inner - 0.001:
			var outer_iv: Dictionary = _segment_ball_interval(a, b, r_outer)
			if bool(outer_iv.get("ok", false)):
				var t_shell_0: float = float(outer_iv["t0"])
				var t_shell_1: float = float(outer_iv["t1"])
				var inner_iv: Dictionary = _segment_ball_interval(a, b, r_inner)
				if bool(inner_iv.get("ok", false)):
					var inner_enter: float = float(inner_iv["t0"])
					if inner_enter >= t_shell_0:
						t_shell_1 = minf(t_shell_1, inner_enter)
				if body_t >= 0.0:
					t_shell_1 = minf(t_shell_1, body_t)

				if t_shell_0 <= t_shell_1:
					var ang_pad: float = float(shield.angular_tolerance_radians()) if shield.has_method("angular_tolerance_radians") else 0.0
					var started_outside: bool = a_len > r_outer
					var vacated_lane: bool = started_outside and shield.prev_covers_vector(a, ang_pad) and not shield.covers_vector_with_pad(a, ang_pad)
					var substeps: int = 24
					for i in range(substeps + 1):
						var u: float = float(i) / float(substeps)
						var t: float = lerpf(t_shell_0, t_shell_1, u)
						var v: Vector2 = a + b * t
						var blocked: bool = shield.covers_vector_with_pad(v, ang_pad)
						if not blocked and not vacated_lane and shield.has_swept():
							blocked = shield.swept_covers_vector(v, ang_pad)
						if blocked:
							shield_t = t
							var dir_norm: Vector2 = v.normalized() if v.length_squared() > 0.000001 else (shield.direction as Vector2)
							shield_point = nick_position + dir_norm * shield_r
							break

	# Travel order: whichever the projectile reaches first wins, and a shield
	# interception always removes the projectile before the body can be hit.
	if shield_t >= 0.0 and (body_t < 0.0 or shield_t <= body_t):
		return {"kind": "shield", "point": shield_point}
	if body_t >= 0.0:
		return {"kind": "body", "point": body_point}
	return {"kind": "fly", "point": p1}


## Interval [t0, t1] subset of [0, 1] where |a + t*b| <= r.
## Returns {"ok": bool, "t0": float, "t1": float}.
func _segment_ball_interval(a: Vector2, b: Vector2, r: float) -> Dictionary:
	var qa: float = b.dot(b)
	var c: float = a.dot(a) - r * r
	if qa < 0.0000001:
		if c <= 0.0:
			return {"ok": true, "t0": 0.0, "t1": 1.0}
		return {"ok": false, "t0": -1.0, "t1": -1.0}
	var qb: float = 2.0 * a.dot(b)
	var disc: float = qb * qb - 4.0 * qa * c
	if disc < 0.0:
		return {"ok": false, "t0": -1.0, "t1": -1.0}
	var sq := sqrt(disc)
	var r0: float = (-qb - sq) / (2.0 * qa)
	var r1: float = (-qb + sq) / (2.0 * qa)
	var t0: float = maxf(0.0, r0)
	var t1: float = minf(1.0, r1)
	if t0 <= t1:
		return {"ok": true, "t0": t0, "t1": t1}
	return {"ok": false, "t0": -1.0, "t1": -1.0}


## Earliest intersection of segment a + t*b (t in [0,1]) with a circle of
## radius r centred on the origin. Only the entry point counts: a projectile
## that begins inside the circle has no entry in this segment.
##
## Returns {"ok": bool, "t": float}.
func _segment_circle(a: Vector2, b: Vector2, r: float) -> Dictionary:
	var c: float = a.dot(a) - r * r
	if c <= 0.0:
		return {"ok": false, "t": -1.0}
	var qa: float = b.dot(b)
	if qa < 0.0000001:
		return {"ok": false, "t": -1.0}
	var qb: float = 2.0 * a.dot(b)
	var disc: float = qb * qb - 4.0 * qa * c
	if disc < 0.0:
		return {"ok": false, "t": -1.0}
	var sq := sqrt(disc)
	var t0: float = (-qb - sq) / (2.0 * qa)
	if t0 >= 0.0 and t0 <= 1.0:
		return {"ok": true, "t": t0}
	return {"ok": false, "t": -1.0}


func _inside_arena(p: Vector2, arena: Rect2) -> bool:
	var m: float = offscreen_margin
	return p.x >= arena.position.x - m and p.x <= arena.end.x + m \
		and p.y >= arena.position.y - m and p.y <= arena.end.y + m


func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v as Dictionary
	return {}
