extends Node2D
## Bill, Nick's companion maintenance unit (B-4). Follows Nick during
## exploration after being activated in Phase 1, stays a comfortable trailing
## distance behind him, steers around solid prop footprints, never blocks Nick
## or interaction targets, and participates in Y-sorting via `_sorted_root`.

const SFPalette := preload("res://core/star_fall/sf_palette.gd")

const FOLLOW_DISTANCE := 26.0
const MIN_DISTANCE := 18.0
const STOP_EPSILON := 2.5
const RECOVERY_DISTANCE := 112.0
const FOOT_RADIUS := 4.5

var skin
var world = null
var target = null

var prop_id: String = "bill_body"
var label: String = "Talk to Bill"
var interactive: bool = true
var highlighted: bool = false
var mouse_hovered: bool = false

var _trail_dir: Vector2 = Vector2(-1.0, 0.35).normalized()
var _velocity: Vector2 = Vector2.ZERO
var _moving: bool = false
var _bob: float = 0.0
var _bob_time: float = 0.0
var _pulse: float = 0.0
var _stuck_timer: float = 0.0


func setup(skin_ref, world_ref, target_node) -> void:
	skin = skin_ref
	world = world_ref
	target = target_node


func snap_behind(nick_pos: Vector2, nick_facing_vec: Vector2 = Vector2(0, 1)) -> void:
	var dir := -nick_facing_vec
	if dir.length_squared() < 0.001:
		dir = Vector2(-1.0, 0.25)
	_trail_dir = dir.normalized()
	var desired := nick_pos + _trail_dir * FOLLOW_DISTANCE
	position = _find_safe_spot(desired, nick_pos)
	_velocity = Vector2.ZERO
	_moving = false
	_bob = 0.0
	_stuck_timer = 0.0
	queue_redraw()


func hit_rect() -> Rect2:
	var w := 22.0
	var h := 24.0
	if skin != null:
		var tex: Texture2D = skin.sprites.get("bill_phase_two", skin.sprites.get("bill_on", null))
		if tex != null:
			w = maxf(20.0, float(tex.get_width()) + 8.0)
			h = maxf(22.0, float(tex.get_height()) + 8.0)
	return Rect2(position.x - w * 0.5, position.y - h + 4.0, w, h)


func step_follow(delta: float) -> void:
	_pulse += delta
	if target == null or not is_instance_valid(target):
		return
	if delta <= 0.0:
		return

	# Pause following while player input is locked (dialogue, pause menu, cutscenes).
	if not bool(target.input_enabled):
		_velocity = Vector2.ZERO
		_moving = false
		_bob = 0.0
		queue_redraw()
		return

	var nick_pos: Vector2 = target.position
	var nick_vel: Vector2 = target.velocity
	var nick_moving: bool = nick_vel.length_squared() > 1.0

	if nick_moving:
		var behind := -nick_vel.normalized()
		_trail_dir = _trail_dir.lerp(behind, minf(1.0, delta * 7.5)).normalized()
		if _trail_dir.length_squared() < 0.001:
			_trail_dir = behind

	var dist_to_nick: float = position.distance_to(nick_pos)
	if dist_to_nick > RECOVERY_DISTANCE:
		snap_behind(nick_pos, _facing_to_vec(String(target.facing)))
		return

	var desired: Vector2 = nick_pos + _trail_dir * FOLLOW_DISTANCE
	desired = _avoid_interactables(desired, nick_pos)
	desired = _clamp_world(desired)

	# If Nick walks directly into Bill's personal space, step aside smoothly
	# so Bill never overlaps Nick or stands in his way.
	var move_vec := Vector2.ZERO
	if dist_to_nick < MIN_DISTANCE:
		var away: Vector2 = (position - nick_pos)
		if away.length_squared() < 0.001:
			away = Vector2(_trail_dir.y, -_trail_dir.x)
		else:
			away = away.normalized()
		var side := Vector2(-away.y, away.x)
		var push_target := _clamp_world(nick_pos + (away * 0.75 + side * 0.65).normalized() * FOLLOW_DISTANCE)
		move_vec = push_target - position
	else:
		var to_desired: Vector2 = desired - position
		if to_desired.length() > STOP_EPSILON and (nick_moving or dist_to_nick > FOLLOW_DISTANCE + 4.0):
			move_vec = to_desired

	if move_vec.length() <= STOP_EPSILON:
		_velocity = Vector2.ZERO
		_moving = false
		_bob = 0.0
		_stuck_timer = 0.0
		queue_redraw()
		return

	var base_speed: float = maxf(float(target.walk_speed), nick_vel.length() * 1.06)
	if dist_to_nick > FOLLOW_DISTANCE * 1.65:
		base_speed = maxf(float(target.run_speed) * 1.08, base_speed * 1.35)
	var step_len: float = minf(move_vec.length(), base_speed * delta)
	var dir_norm: Vector2 = move_vec.normalized()
	var next_pos: Vector2 = _steer_move(position, dir_norm, step_len)

	var moved_dist: float = next_pos.distance_to(position)
	position = next_pos
	_velocity = (dir_norm * (moved_dist / maxf(0.0001, delta))) if moved_dist > 0.01 else Vector2.ZERO
	_moving = moved_dist > 0.08

	if _moving:
		_stuck_timer = 0.0
		_bob_time += delta * 8.0
		_bob = 1.0 if sin(_bob_time * TAU) > 0.0 else 0.0
	else:
		_bob = 0.0
		if dist_to_nick > FOLLOW_DISTANCE + 14.0:
			_stuck_timer += delta
			if _stuck_timer > 0.65:
				position = _find_safe_spot(desired, nick_pos)
				_stuck_timer = 0.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	step_follow(delta)


func _steer_move(from: Vector2, dir: Vector2, step_len: float) -> Vector2:
	var candidate := _clamp_world(from + dir * step_len)
	if not _collides(candidate):
		return candidate
	# Try sliding along X or Y or steering 45 degrees around solid props.
	var angles := [0.65, -0.65, 1.15, -1.15, 1.57, -1.57]
	for ang in angles:
		var rotated_dir := dir.rotated(float(ang))
		var alt := _clamp_world(from + rotated_dir * step_len)
		if not _collides(alt):
			return alt
	return from


func _find_safe_spot(preferred: Vector2, nick_pos: Vector2) -> Vector2:
	var clamped := _clamp_world(preferred)
	if not _collides(clamped):
		return clamped
	for i in 8:
		var ang: float = float(i) / 8.0 * TAU
		var spot := _clamp_world(nick_pos + Vector2(cos(ang), sin(ang)) * FOLLOW_DISTANCE)
		if not _collides(spot):
			return spot
	return clamped


func _avoid_interactables(desired: Vector2, nick_pos: Vector2) -> Vector2:
	if world == null:
		return desired
	for p in world._interactables:
		if p == self or not is_instance_valid(p):
			continue
		var prop_pos: Vector2 = p.position
		var d: float = desired.distance_to(prop_pos)
		if d < 18.0:
			var away: Vector2 = desired - prop_pos
			if away.length_squared() < 0.001:
				away = nick_pos - prop_pos
			if away.length_squared() < 0.001:
				away = Vector2(-1, 0)
			return prop_pos + away.normalized() * 19.0
	return desired


func _collides(pt: Vector2) -> bool:
	if world == null or not world.has_method("solid_rects"):
		return false
	var foot := Rect2(pt.x - FOOT_RADIUS, pt.y - FOOT_RADIUS * 2.0, FOOT_RADIUS * 2.0, FOOT_RADIUS * 2.0)
	for r in world.solid_rects():
		if (r as Rect2).intersects(foot):
			return true
	return false


func _clamp_world(pt: Vector2) -> Vector2:
	if world == null:
		return pt
	var b: Rect2 = world.bounds
	return Vector2(
		clampf(pt.x, b.position.x + 12.0, b.end.x - 12.0),
		clampf(pt.y, b.position.y + 18.0, b.end.y - 12.0)
	)


func _facing_to_vec(f: String) -> Vector2:
	match f:
		"up":
			return Vector2(0, -1)
		"left":
			return Vector2(-1, 0)
		"right":
			return Vector2(1, 0)
	return Vector2(0, 1)


func _draw() -> void:
	if skin == null:
		return
	var tex: Texture2D = skin.sprites.get("bill_phase_two", skin.sprites.get("bill_on", null))
	if tex == null:
		return
	skin.contact_shadow(self, Vector2(0, 0), 12.0, 0.24)
	if highlighted or mouse_hovered:
		var glow := Color(0.37, 0.90, 0.85, 0.45) if highlighted else Color(0.95, 0.82, 0.35, 0.40)
		glow.a = 0.32 + 0.22 * sin(_pulse * 5.0)
		var w := tex.get_width() + 6
		var h := tex.get_height() + 4
		draw_rect(Rect2(round(-w * 0.5), round(-h + 2), w, h), glow, false, 1.0)
	var size := tex.get_size()
	var draw_pos := Vector2(round(-size.x * 0.5), round(-size.y - _bob))
	draw_texture_rect(tex, Rect2(draw_pos, size), false)
