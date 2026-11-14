extends CharacterBody2D
## Nick, the player character. Movement and collision only: the world decides
## where he is and the main controller decides whether he may move.
##
## The node origin is Nick's ground-contact point, so Y-sorting against props
## behaves correctly. Presentation is drawn upward from the origin.

const SFPalette := preload("res://core/star_fall/sf_palette.gd")

var skin
var walk_speed: float = 58.0
var run_speed: float = 98.0
var input_enabled: bool = false
var facing: String = "down"

var _moving: bool = false
var _step_timer: float = 0.0
var _bob: float = 0.0
var _bob_time: float = 0.0
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
var mouse_run: bool = false
var _stuck_timer: float = 0.0

signal stepped
signal target_reached


func setup(skin_ref, walk_px: float, run_px: float) -> void:
	skin = skin_ref
	walk_speed = walk_px
	run_speed = run_px


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CircleShape2D.new()
	shape.radius = 5.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -5)
	add_child(collider)


func set_move_target(target: Vector2, run_to_target: bool = false) -> void:
	move_target = target
	has_move_target = true
	mouse_run = run_to_target
	_stuck_timer = 0.0


func clear_move_target() -> void:
	has_move_target = false
	mouse_run = false
	_stuck_timer = 0.0


func _physics_process(delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		_moving = false
		clear_move_target()
		queue_redraw()
		return

	var dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if dir != Vector2.ZERO:
		clear_move_target()
		if dir.length() > 1.0:
			dir = dir.normalized()
	elif has_move_target:
		var to_target: Vector2 = move_target - position
		if to_target.length() <= 4.5:
			clear_move_target()
			target_reached.emit()
		else:
			dir = to_target.normalized()

	var running := Input.is_action_pressed("run") or mouse_run
	var speed := run_speed if running else walk_speed
	var before_pos := position
	velocity = dir * speed
	move_and_slide()

	if has_move_target and dir != Vector2.ZERO:
		if position.distance_to(before_pos) < speed * delta * 0.2:
			_stuck_timer += delta
			if _stuck_timer > 0.28:
				clear_move_target()
				target_reached.emit()
		else:
			_stuck_timer = 0.0

	_moving = dir != Vector2.ZERO
	if _moving:
		if absf(dir.x) > absf(dir.y):
			facing = "right" if dir.x > 0.0 else "left"
		else:
			facing = "down" if dir.y > 0.0 else "up"
		_bob_time += delta * (11.0 if running else 7.0)
		_bob = 1.0 if sin(_bob_time * TAU) > 0.0 else 0.0
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.26 if running else 0.38
			stepped.emit()
	else:
		_bob = 0.0
		_step_timer = 0.0
	queue_redraw()


func _draw() -> void:
	if skin == null:
		return
	var tex: Texture2D = skin.sprites.get("nick_" + facing, null)
	if tex == null:
		return
	skin.contact_shadow(self, Vector2(0, 0), 12.0, 0.26)
	var size := tex.get_size()
	var draw_pos := Vector2(round(-size.x * 0.5), round(-size.y - _bob))
	draw_texture_rect(tex, Rect2(draw_pos, size), false)
