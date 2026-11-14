extends RefCounted
## One drifting piece of debris. Position/velocity are simulated in 2D so the
## field feels alive, and the tractor beam can pull it without touching nodes.

var id: int = 0
var kind: String = "scrap"
var entry: Dictionary = {}
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var spin: float = 0.0
var spin_rate: float = 0.0
var rotation: float = 0.0
var size: Vector2 = Vector2(16, 16)
var radius: float = 7.0
var collected: bool = false
var pull: float = 0.0          # eased 0..1 while being tractored
var blink_phase: float = 0.0
var flash: float = 0.0


func _init(debris_id: int, kind_name: String, data: Dictionary, pos: Vector2, seed_value: int) -> void:
	id = debris_id
	kind = kind_name
	entry = data
	position = pos
	radius = float(data.get("radius", 7.0))
	var sprite := String(data.get("sprite", kind_name))
	match sprite:
		"panel":
			size = Vector2(32, 16)
		"billboard":
			size = Vector2(32, 22)
		_:
			size = Vector2(16, 16)
	if sprite == "satellite" or sprite == "billboard" or sprite == "specimen":
		size = Vector2(32, 32) if sprite != "billboard" else Vector2(32, 22)
		if sprite == "specimen":
			size = Vector2(16, 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ang: float = rng.randf() * TAU
	var speed: float = rng.randf_range(2.0, 9.0)
	velocity = Vector2(cos(ang), sin(ang)) * speed
	spin_rate = rng.randf_range(-0.7, 0.7)
	rotation = rng.randf() * TAU
	blink_phase = rng.randf() * TAU


func mass() -> float:
	return float(entry.get("mass", 1.0))


func value() -> float:
	return float(entry.get("value", 1.0))


func display_name() -> String:
	return String(entry.get("name", kind.to_upper()))


func is_special() -> bool:
	return bool(entry.get("special", false))


func step(delta: float, world: Rect2) -> void:
	if collected:
		return
	position += velocity * delta
	rotation += spin_rate * delta
	blink_phase += delta * 3.0
	flash = maxf(0.0, flash - delta * 2.0)
	var pad := 30.0
	if position.x < world.position.x + pad:
		position.x = world.position.x + pad
		velocity.x = absf(velocity.x)
	elif position.x > world.end.x - pad:
		position.x = world.end.x - pad
		velocity.x = -absf(velocity.x)
	if position.y < world.position.y + pad:
		position.y = world.position.y + pad
		velocity.y = absf(velocity.y)
	elif position.y > world.end.y - pad:
		position.y = world.end.y - pad
		velocity.y = -absf(velocity.y)


## Heavy pieces resist the beam more, per the mass trade-off.
func pull_strength() -> float:
	return 1.0 / (0.55 + mass() * 0.09)
