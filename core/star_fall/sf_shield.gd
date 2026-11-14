extends RefCounted
## Directional shield model for the Phase 2 encounters. Pure logic: no nodes,
## no input, no drawing. The screen feeds it a cursor position and asks it what
## it covers; the projectile field asks it the same question during collision.
##
## There is exactly one authoritative direction. Rendering and collision both
## read `direction`, so what the player sees and what the game blocks cannot
## drift apart.

var radius: float = 44.0
var coverage_degrees: float = 84.0
var min_cursor_distance: float = 14.0
var direction: Vector2 = Vector2(0.0, 1.0)


## Applies data/star_fall/encounters.json "shield". Values are clamped so a bad
## data edit can never produce a zero-coverage or full-circle bubble.
func configure(config: Dictionary) -> void:
	radius = clampf(float(config.get("radius", radius)), 12.0, 160.0)
	coverage_degrees = clampf(float(config.get("coverage_degrees", coverage_degrees)), 10.0, 350.0)
	min_cursor_distance = maxf(1.0, float(config.get("min_cursor_distance", min_cursor_distance)))
	var raw: Variant = config.get("initial_direction", {})
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		var v := Vector2(float(d.get("x", 0.0)), float(d.get("y", 1.0)))
		if v.length_squared() > 0.000001:
			direction = v.normalized()


func half_coverage_radians() -> float:
	return deg_to_rad(coverage_degrees) * 0.5


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
	direction = next
	return true


## True when a vector from Nick to a point falls inside the shield's coverage.
func covers_vector(v: Vector2) -> bool:
	if v.length_squared() < 0.000001:
		return false
	var angle := absf(direction.angle_to(v.normalized()))
	return angle <= half_coverage_radians() + 0.000001


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
