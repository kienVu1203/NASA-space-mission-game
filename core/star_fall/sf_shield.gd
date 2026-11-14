extends RefCounted
## Directional shield model for the Phase 2 encounters. Pure logic: no nodes,
## no input, no drawing. The screen feeds it a cursor position and asks it what
## it covers; the projectile field asks it the same question during collision.
##
## There is exactly one authoritative direction. Rendering and collision both
## read `direction`, so what the player sees and what the game blocks cannot
## drift apart. Continuous angular sweeps between `prev_direction` and
## `direction` are tracked so projectiles crossed during shield rotation are
## intercepted along the actual rotation path.

const PREVIOUS_DEFAULT_COVERAGE_DEGREES := 84.0
const DEFAULT_COVERAGE_DEGREES := 72.0

var radius: float = 44.0
var coverage_degrees: float = DEFAULT_COVERAGE_DEGREES
var previous_coverage_degrees: float = PREVIOUS_DEFAULT_COVERAGE_DEGREES
var thickness: float = 5.0
var min_cursor_distance: float = 14.0
var contact_tolerance: float = 3.0
var angular_tolerance_degrees: float = 2.5
var charge_meter_margin: float = 16.5
var direction: Vector2 = Vector2(0.0, 1.0)
var prev_direction: Vector2 = Vector2(0.0, 1.0)
var _sweep_segments: Array = []


## Applies data/star_fall/encounters.json "shield". Values are clamped so a bad
## data edit can never produce a zero-coverage or full-circle bubble.
func configure(config: Dictionary) -> void:
	radius = clampf(float(config.get("radius", radius)), 12.0, 160.0)
	coverage_degrees = clampf(float(config.get("coverage_degrees", coverage_degrees)), 10.0, 350.0)
	previous_coverage_degrees = float(config.get("previous_coverage_degrees", PREVIOUS_DEFAULT_COVERAGE_DEGREES))
	thickness = maxf(1.0, float(config.get("thickness", thickness)))
	min_cursor_distance = maxf(1.0, float(config.get("min_cursor_distance", min_cursor_distance)))
	contact_tolerance = maxf(0.0, float(config.get("contact_tolerance", contact_tolerance)))
	angular_tolerance_degrees = clampf(float(config.get("angular_tolerance_degrees", angular_tolerance_degrees)), 0.0, 15.0)
	charge_meter_margin = maxf(6.0, float(config.get("charge_meter_margin", charge_meter_margin)))
	var raw: Variant = config.get("initial_direction", {})
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		var v := Vector2(float(d.get("x", 0.0)), float(d.get("y", 1.0)))
		if v.length_squared() > 0.000001:
			direction = v.normalized()
			prev_direction = direction
	_sweep_segments.clear()


func reset(initial: Vector2 = Vector2(0.0, 1.0)) -> void:
	if initial.length_squared() > 0.000001:
		direction = initial.normalized()
	else:
		direction = Vector2(0.0, 1.0)
	prev_direction = direction
	_sweep_segments.clear()


func half_coverage_radians() -> float:
	return deg_to_rad(coverage_degrees) * 0.5


func angular_tolerance_radians() -> float:
	return deg_to_rad(angular_tolerance_degrees)


## Outer radial envelope of the shield (including band half-thickness and contact tolerance).
func outer_extent(override_thickness: float = -1.0) -> float:
	var band_t: float = thickness if override_thickness < 0.0 else override_thickness
	return radius + band_t * 0.5 + contact_tolerance


## Vertical distance above Nick's origin to the bottom edge of the charge meter plate.
func charge_meter_bottom_offset(override_thickness: float = -1.0) -> float:
	return outer_extent(override_thickness) + charge_meter_margin


## Points the shield at a cursor position. A cursor closer than
## `min_cursor_distance` is ignored, so the last valid direction survives and a
## zero-length vector can never reach the rotation maths.
func aim(nick_position: Vector2, cursor_position: Vector2) -> bool:
	var offset := cursor_position - nick_position
	if offset.length() < min_cursor_distance:
		return false
	return set_direction(offset)


func set_direction(v: Vector2) -> bool:
	if v.length_squared() < 0.000001:
		return false
	var next := v.normalized()
	if next.is_equal_approx(direction):
		return false
	var step_from := direction
	var delta_ang := step_from.angle_to(next)
	direction = next
	if absf(delta_ang) > 0.00001:
		_sweep_segments.append({"from": step_from, "delta": delta_ang})
	return true


## Snaps both `prev_direction` and `direction` without recording a rotation sweep.
func snap_direction(v: Vector2) -> bool:
	if v.length_squared() < 0.000001:
		return false
	direction = v.normalized()
	prev_direction = direction
	_sweep_segments.clear()
	return true


## Commits the current orientation at the end of a collision update step so the
## next step sweeps from this frame's authoritative orientation.
func commit_step() -> void:
	prev_direction = direction
	_sweep_segments.clear()


func has_swept() -> bool:
	if not _sweep_segments.is_empty():
		return true
	return absf(prev_direction.angle_to(direction)) > 0.0001


func total_sweep_radians() -> float:
	if _sweep_segments.is_empty():
		return absf(prev_direction.angle_to(direction))
	var total := 0.0
	for seg in _sweep_segments:
		var entry: Dictionary = seg
		total += absf(float(entry.get("delta", 0.0)))
	return total


## True when a vector from Nick to a point falls inside the shield's coverage.
func covers_vector(v: Vector2) -> bool:
	if v.length_squared() < 0.000001:
		return false
	var angle := absf(direction.angle_to(v.normalized()))
	return angle <= half_coverage_radians() + 0.000001


func covers_vector_with_pad(v: Vector2, angular_pad: float = 0.0) -> bool:
	if v.length_squared() < 0.000001:
		return false
	var angle := absf(direction.angle_to(v.normalized()))
	return angle <= half_coverage_radians() + maxf(0.0, angular_pad) + 0.000001


func prev_covers_vector(v: Vector2, angular_pad: float = 0.0) -> bool:
	if v.length_squared() < 0.000001:
		return false
	var angle := absf(prev_direction.angle_to(v.normalized()))
	return angle <= half_coverage_radians() + maxf(0.0, angular_pad) + 0.000001


## True when a vector `v` from Nick is crossed at any point along the shield's
## rotation path from `prev_direction` to `direction` during the current step.
## Uses the exact midpoint-angle test per rotation segment so angle wraparound
## at +/-PI is handled without discontinuities and without treating a rotation
## as a full 360-degree circle.
func swept_covers_vector(v: Vector2, angular_pad: float = 0.0) -> bool:
	if v.length_squared() < 0.000001:
		return false
	var u := v.normalized()
	var h := half_coverage_radians() + maxf(0.0, angular_pad) + 0.000001
	if absf(direction.angle_to(u)) <= h:
		return true
	if _sweep_segments.is_empty():
		var d_ang := prev_direction.angle_to(direction)
		if absf(d_ang) <= 0.00001:
			return false
		var mid := prev_direction.rotated(d_ang * 0.5)
		return absf(mid.angle_to(u)) <= (absf(d_ang) * 0.5 + h)
	for seg in _sweep_segments:
		var entry: Dictionary = seg
		var from_dir: Vector2 = entry.get("from", prev_direction)
		var delta_ang: float = float(entry.get("delta", 0.0))
		var mid_dir := from_dir.rotated(delta_ang * 0.5)
		if absf(mid_dir.angle_to(u)) <= (absf(delta_ang) * 0.5 + h):
			return true
	return false


func covers_point(nick_position: Vector2, point: Vector2) -> bool:
	return covers_vector(point - nick_position)


## World-space points along the visible arc. Used for drawing and for tests
## that need to reason about the shield's actual coverage.
func arc_points(nick_position: Vector2, segments: int = 24, extra_radius: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count: int = maxi(2, segments)
	var base_angle := direction.angle()
	var half := half_coverage_radians()
	var r: float = radius + extra_radius
	for i in count + 1:
		var t: float = float(i) / float(count)
		var angle: float = base_angle - half + t * half * 2.0
		out.append(nick_position + Vector2(cos(angle), sin(angle)) * r)
	return out


func arc_endpoints(nick_position: Vector2, extra_radius: float = 0.0) -> Array:
	var half := half_coverage_radians()
	var base_angle := direction.angle()
	var r: float = radius + extra_radius
	return [
		nick_position + Vector2(cos(base_angle - half), sin(base_angle - half)) * r,
		nick_position + Vector2(cos(base_angle + half), sin(base_angle + half)) * r,
	]


## Converts a raw window-space mouse position into the 640x360 canvas space
## this game draws in, accounting for both scaling and letterbox bars.
##
## The project stretches with `canvas_items`/`keep`. On a window whose aspect
## ratio differs from 16:9 Godot adds letterbox bars, so raw window pixels are
## NOT canvas pixels. Anything that receives window coordinates directly (a
## SubViewport, a tool, a test) must go through this.
static func canvas_point(mouse: Vector2, window_size: Vector2, base_size: Vector2 = Vector2(640, 360)) -> Vector2:
	if window_size.x <= 0.0 or window_size.y <= 0.0 or base_size.x <= 0.0 or base_size.y <= 0.0:
		return mouse
	var scale_x: float = window_size.x / base_size.x
	var scale_y: float = window_size.y / base_size.y
	var scale: float = minf(scale_x, scale_y)
	if scale <= 0.0:
		return mouse
	var drawn := base_size * scale
	var offset := (window_size - drawn) * 0.5
	return (mouse - offset) / scale
