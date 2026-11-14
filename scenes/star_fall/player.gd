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

signal stepped


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


func _physics_process(delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		_moving = false
		queue_redraw()
		return

	var dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	# Normalised so diagonals are not faster than cardinals.
	if dir.length() > 1.0:
		dir = dir.normalized()

	var running := Input.is_action_pressed("run")
	var speed := run_speed if running else walk_speed
	velocity = dir * speed
	move_and_slide()

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
