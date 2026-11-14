extends RefCounted
## Pure physics + resource model for one EVA sortie. No nodes, no UI, fully
## deterministic given the same inputs: easy to unit test and to retune from
## data/starfall/balance.json.

var stats: Dictionary
var velocity: Vector2 = Vector2.ZERO
var position: Vector2 = Vector2.ZERO
var heading: float = 0.0
var fuel: float = 100.0
var power: float = 100.0
var fuel_max: float = 100.0
var power_max: float = 100.0
var cargo_mass: float = 0.0
var cargo_storage: float = 0.0
var cargo_value: float = 0.0
var collected: int = 0
var spec: bool = false
var thrusting: bool = false
var beaming: bool = false
var disabled: bool = false
var overburdened: bool = false

var _mass_factor: float = 46.0


func _init(ship_stats: Dictionary, start: Vector2) -> void:
	stats = ship_stats
	position = start
	fuel_max = float(stats.get("fuel", 100.0))
	power_max = float(stats.get("power", 100.0))
	fuel = fuel_max
	power = power_max
	_mass_factor = float(stats.get("mass_factor", 46.0))


func total_mass() -> float:
	return float(stats.get("dry_mass", 18.0)) + cargo_mass


func storage_capacity() -> float:
	return float(stats.get("storage", 40.0))


func storage_free() -> float:
	return maxf(0.0, storage_capacity() - cargo_storage)


func cargo_ratio() -> float:
	var cap := storage_capacity()
	if cap <= 0.0:
		return 1.0
	return clampf(cargo_storage / cap, 0.0, 1.0)


## Heavier loads accelerate and turn less. Dry ship = 1.0.
func agility() -> float:
	var dry := float(stats.get("dry_mass", 18.0))
	return dry / maxf(1.0, total_mass())


func acceleration() -> float:
	return float(stats.get("accel", 265.0)) * agility()


func max_speed() -> float:
	return float(stats.get("max_speed", 300.0)) * (0.55 + 0.45 * agility())


func beam_radius() -> float:
	return float(stats.get("beam_radius", 58.0))


func pickup_radius() -> float:
	return float(stats.get("pickup_radius", 14.0))


func is_out_of_fuel() -> bool:
	return fuel <= 0.0


func can_beam() -> bool:
	return power > 0.5 and not disabled


func can_take(entry: Dictionary) -> Dictionary:
	var need := float(entry.get("storage", 1.0))
	var need_power := float(entry.get("power_cost", 1.0))
	if storage_free() + 0.001 < need:
		return {"ok": false, "reason": "HOLD FULL"}
	if power < need_power:
		return {"ok": false, "reason": "NO POWER"}
	return {"ok": true, "reason": ""}


func add_cargo(entry: Dictionary) -> void:
	cargo_mass += float(entry.get("mass", 0.0))
	cargo_storage += float(entry.get("storage", 0.0))
	cargo_value += float(entry.get("value", 0.0))
	power = maxf(0.0, power - float(entry.get("power_cost", 0.0)))
	collected += 1
	if bool(entry.get("special", false)):
		spec = true


## One fixed-step update. input is a normalized direction (or ZERO).
## Returns true if the ship should be considered dead (no fuel and no power).
func step(delta: float, input: Vector2, want_beam: bool, world: Rect2) -> void:
	var dir := input
	if dir.length() > 1.0:
		dir = dir.normalized()

	thrusting = false
	if not disabled and dir.length_squared() > 0.0001 and fuel > 0.0:
		thrusting = true
		var accel := acceleration()
		velocity += dir * accel * delta
		# Fuel burn scales with load: heavy hauling costs more.
		var burn := float(stats.get("fuel_burn", 1.85))
		var load_penalty := 1.0 + cargo_ratio() * 0.55
		fuel = maxf(0.0, fuel - burn * load_penalty * delta)
		heading = lerp_angle(heading, dir.angle(), clampf(9.0 * delta, 0.0, 1.0))

	# Space drag: very light, so drift stays readable but never infinite.
	var drag := float(stats.get("drag", 0.15))
	velocity -= velocity * drag * delta
	var cap := max_speed()
	if velocity.length() > cap:
		velocity = velocity.normalized() * cap

	position += velocity * delta

	# Passive systems always draw a trickle.
	power = maxf(0.0, power - float(stats.get("passive_power", 0.22)) * delta)

	beaming = want_beam and can_beam()
	if beaming:
		power = maxf(0.0, power - float(stats.get("beam_drain", 4.2)) * delta)

	# Soft world bounds, so the ship can never be lost off-map.
	var margin := 40.0
	if position.x < world.position.x + margin:
		position.x = world.position.x + margin
		velocity.x = absf(velocity.x) * 0.2
	elif position.x > world.end.x - margin:
		position.x = world.end.x - margin
		velocity.x = -absf(velocity.x) * 0.2
	if position.y < world.position.y + margin:
		position.y = world.position.y + margin
		velocity.y = absf(velocity.y) * 0.2
	elif position.y > world.end.y - margin:
		position.y = world.end.y - margin
		velocity.y = -absf(velocity.y) * 0.2

	overburdened = cargo_ratio() >= 0.999
	disabled = fuel <= 0.0 and power <= 0.0


## Fuel spent per second at full thrust with the current load, for UI readouts.
func fuel_rate() -> float:
	var burn := float(stats.get("fuel_burn", 1.85))
	return burn * (1.0 + cargo_ratio() * 0.55)


func power_rate() -> float:
	var passive := float(stats.get("passive_power", 0.22))
	if beaming:
		return passive + float(stats.get("beam_drain", 4.2))
	return passive


func summary() -> Dictionary:
	return {
		"fuel": fuel,
		"fuel_max": fuel_max,
		"power": power,
		"power_max": power_max,
		"cargo_mass": cargo_mass,
		"cargo_storage": cargo_storage,
		"storage_capacity": storage_capacity(),
		"cargo_value": cargo_value,
		"collected": collected,
		"specimen": spec,
		"disabled": disabled,
	}
