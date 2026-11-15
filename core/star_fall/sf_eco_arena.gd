extends RefCounted
## Eco Arena rules (pure, no nodes). One implementation serves both entry
## points: the campaign's Scrap King encounter and the standalone practice mode.
## The screen feeds input through the methods below and draws what this model
## reports; campaign state is never touched here.
##
## STAR FALL's three colors are a simplified game convention:
##   green  ORGANIC: food, leaves, food-soiled uncoated paper
##   blue   CLEAN PAPER: clean cardboard, dry newspaper, office paper
##   yellow PLASTIC & METAL: empty plastic bottles, drink cans, tin cans
##
## Progression is energy-driven: stages change when station charge crosses
## the thresholds in data (cores add whole points, so 24 -> 28 crosses 25).
## Ordinary cores stop at `boss_at`; the boss spawns once there, and only its
## three-lock Super Core takes the station to 100.
##
## Accuracy: the first manual color decision for each enemy armor layer and
## for each core shell counts once. Overdrive hits are automatic and excluded.

const PHASE_FIGHT := "fight"     # waves and, later, the boss
const PHASE_REWARD := "reward"   # boss down; Super Core and chip wait in the arena
const PHASE_VICTORY := "victory"
const PHASE_DEFEAT := "defeat"

const RAINBOW := "rainbow"

var data: Dictionary = {}
var categories: Array = ["green", "blue", "yellow"]

var phase: String = PHASE_FIGHT
var elapsed: float = 0.0

# Nick.
var nick_pos: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.DOWN
var aim_point: Vector2 = Vector2.ZERO
var health: float = 100.0
var health_max: float = 100.0
var shield: float = 50.0
var shield_max: float = 50.0
var regen_wait: float = 0.0
var hurt_invuln: float = 0.0
var dash_time: float = 0.0
var dash_cooldown: float = 0.0
var dash_invuln: float = 0.0
var dash_dir: Vector2 = Vector2.DOWN
var spectrum: String = "green"
var fire_cooldown: float = 0.0
var last_damage: int = 0

var bill_pos: Vector2 = Vector2.ZERO

# The world.
var enemies: Array = []
var pending_spawns: Array = []
var bolts: Array = []
var hazards: Array = []      # boss trash-toss landing zones
var shots: Array = []        # boss junk-ring projectiles
var cores: Array = []
var crushers: Array = []
var chip: Dictionary = {}
var boss: Dictionary = {}

# Progression.
var charge: int = 0
var stage_index: int = 0
var spawn_timer: float = 0.0
var boss_spawned: bool = false
var boss_defeated: bool = false
var super_collected: bool = false
var chip_collected: bool = false
var victory_reported: bool = false

# Combo and Overdrive.
var combo: Array = []
var overdrive: float = 0.0
var overdrive_count: int = 0

# Beam.
var beam_on: bool = false
var beam_target_id: int = -1
var beam_progress: float = 0.0

# Coaching.
var callout_text: String = ""
var callout_timer: float = 0.0
var callout_cooldown: float = 0.0
var callout_priority: int = 0

# Accuracy.
var decisions: Dictionary = {}       # "e<id>:<layer>" / "c<id>:<shell>" -> bool
var mismatch_counts: Dictionary = {} # item id -> wrong decisions

var rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _events: Array = []


func setup(arena_data: Dictionary) -> void:
	data = arena_data
	var order: Array = data.get("category_order", []) as Array
	if not order.is_empty():
		categories = order.duplicate()
	reset(false)


## A fresh attempt: every encounter-local value. With `resume_reward` the boss
## is already down (a campaign save that left before collecting): the arena
## opens at the boss threshold with the Super Core and the chip waiting.
func reset(resume_reward: bool = false) -> void:
	var nick: Dictionary = _d("nick")
	phase = PHASE_FIGHT
	elapsed = 0.0
	nick_pos = _v(_d("world").get("nick_start", {}), Vector2(640, 640))
	facing = Vector2.UP
	aim_point = nick_pos + Vector2.UP * 40.0
	health_max = float(nick.get("health", 100))
	health = health_max
	shield_max = float(nick.get("shield", 50))
	shield = shield_max
	regen_wait = 0.0
	hurt_invuln = 0.0
	dash_time = 0.0
	dash_cooldown = 0.0
	dash_invuln = 0.0
	dash_dir = Vector2.UP
	spectrum = String(categories[0])
	fire_cooldown = 0.0
	last_damage = 0
	bill_pos = nick_pos + Vector2(-14, 12)
	enemies.clear()
	pending_spawns.clear()
	bolts.clear()
	hazards.clear()
	shots.clear()
	cores.clear()
	chip = {}
	boss = {}
	charge = 0
	stage_index = 0
	boss_spawned = false
	boss_defeated = false
	super_collected = false
	chip_collected = false
	victory_reported = false
	combo.clear()
	overdrive = 0.0
	overdrive_count = 0
	beam_on = false
	beam_target_id = -1
	beam_progress = 0.0
	callout_text = ""
	callout_timer = 0.0
	callout_cooldown = 0.0
	callout_priority = 0
	decisions.clear()
	mismatch_counts.clear()
	_next_id = 1
	_events.clear()
	rng.seed = int(_d("pacing").get("seed", 1))
	spawn_timer = float(_d("pacing").get("first_spawn_delay", 1.5))
	crushers.clear()
	for c in data.get("crushers", []) as Array:
		var cd: Dictionary = (c as Dictionary).duplicate(true)
		cd["pos"] = Vector2(float(cd.get("x", 0)), float(cd.get("y", 0)))
		cd["timer"] = 0.0
		cd["slam"] = 0.0
		crushers.append(cd)
	if resume_reward:
		charge = boss_at()
		stage_index = stages().size()
		boss_spawned = true
		boss_defeated = true
		phase = PHASE_REWARD
		_spawn_rewards()
		_events.clear()


# ---------------------------------------------------------------- queries

func stages() -> Array:
	return data.get("stages", []) as Array


func boss_at() -> int:
	return int(data.get("boss_at", 80))


## The stage the waves are in (1-based); 4 once the boss threshold is reached.
func stage_number() -> int:
	return stage_index + 1


func current_stage() -> Dictionary:
	var list := stages()
	if list.is_empty():
		return {}
	return list[mini(stage_index, list.size() - 1)] as Dictionary


## Stage 1 badges carry an answer-revealing colored border; later stages do not.
func bordered_badges() -> bool:
	return stage_index < stages().size() and bool(current_stage().get("bordered_badges", false))


func is_active() -> bool:
	return phase == PHASE_FIGHT or phase == PHASE_REWARD


func is_invulnerable() -> bool:
	return hurt_invuln > 0.0 or dash_invuln > 0.0 or phase != PHASE_FIGHT


func is_dashing() -> bool:
	return dash_time > 0.0


func dash_ready_fraction() -> float:
	var cd := float(_d("dash").get("cooldown", 1.5))
	if cd <= 0.0:
		return 1.0
	return clampf(1.0 - dash_cooldown / cd, 0.0, 1.0)


func overdrive_active() -> bool:
	return overdrive > 0.0


func move_speed() -> float:
	var base := float(_d("nick").get("speed", 92.0))
	return base * (float(_d("overdrive").get("speed_multiplier", 1.3)) if overdrive_active() else 1.0)


func regen_rate() -> float:
	var base := float(_d("nick").get("shield_regen_per_second", 10.0))
	return base * (float(_d("overdrive").get("regen_multiplier", 1.25)) if overdrive_active() else 1.0)


func item(item_id: String) -> Dictionary:
	return (data.get("items", {}) as Dictionary).get(item_id, {}) as Dictionary


func category(cat: String) -> Dictionary:
	return (data.get("categories", {}) as Dictionary).get(cat, {}) as Dictionary


func enemy_by_id(id: int) -> Dictionary:
	for e in enemies:
		if int((e as Dictionary)["id"]) == id:
			return e
	return {}


func core_by_id(id: int) -> Dictionary:
	for c in cores:
		if int((c as Dictionary)["id"]) == id:
			return c
	return {}


func active_layer(target: Dictionary) -> String:
	var layers: Array = target.get("layers", []) as Array
	var i := int(target.get("layer", 0))
	if i < 0 or i >= layers.size():
		return ""
	return String((layers[i] as Dictionary)["cat"])


func active_shell(core: Dictionary) -> String:
	var shells: Array = core.get("shells", []) as Array
	var i := int(core.get("shell", 0))
	if i < 0 or i >= shells.size():
		return ""
	return String(shells[i])


func accuracy() -> float:
	if decisions.is_empty():
		return 1.0
	return float(correct_decisions()) / float(decisions.size())


func correct_decisions() -> int:
	var n := 0
	for k in decisions.keys():
		if bool(decisions[k]):
			n += 1
	return n


func rank_for(acc: float, seconds: float) -> String:
	for r in data.get("ranks", []) as Array:
		var rd: Dictionary = r
		if acc >= float(rd.get("min_accuracy", 0.0)) and seconds <= float(rd.get("max_seconds", 999999.0)):
			return String(rd.get("rank", "B"))
	return "B"


## The completion readout for the summary screen.
func summary() -> Dictionary:
	var worst := ""
	var worst_n := 0
	var keys: Array = mismatch_counts.keys()
	keys.sort()
	for k in keys:
		if int(mismatch_counts[k]) > worst_n:
			worst_n = int(mismatch_counts[k])
			worst = String(k)
	var acc := accuracy()
	return {
		"seconds": elapsed,
		"accuracy": acc,
		"correct": correct_decisions(),
		"decisions": decisions.size(),
		"rank": rank_for(acc, elapsed),
		"reminder_item": worst,
		"reminder": String(item(worst).get("reminder", "")) if worst != "" else "",
	}


# ---------------------------------------------------------------- input

func select_spectrum(cat: String) -> bool:
	if not categories.has(cat) or not is_active():
		return false
	spectrum = cat
	return true


func cycle_spectrum(step: int) -> void:
	var i := categories.find(spectrum)
	select_spectrum(String(categories[posmod(i + step, categories.size())]))


func request_dash(move: Vector2) -> bool:
	if not is_active() or dash_cooldown > 0.0 or dash_time > 0.0:
		return false
	var d := _d("dash")
	dash_dir = move.normalized() if move.length_squared() > 0.0001 else facing
	dash_time = float(d.get("duration", 0.16))
	dash_cooldown = float(d.get("cooldown", 1.5))
	dash_invuln = float(d.get("invulnerable_seconds", 0.24))
	_emit({"kind": "dash"})
	return true


## E pressed: picks up the chip when Nick stands at it. Returns true on pickup.
func interact() -> bool:
	if phase != PHASE_REWARD or chip.is_empty() or chip_collected:
		return false
	if nick_pos.distance_to(chip["pos"]) > float(_d("cores").get("chip_pickup_radius", 22.0)):
		return false
	chip_collected = true
	_emit({"kind": "chip_collected", "pos": chip["pos"]})
	_check_victory()
	return true


func near_chip() -> bool:
	return phase == PHASE_REWARD and not chip.is_empty() and not chip_collected \
		and nick_pos.distance_to(chip["pos"]) <= float(_d("cores").get("chip_pickup_radius", 22.0))


# ---------------------------------------------------------------- tick

## Advances the arena one step. `move` is the raw input vector (normalised
## here), `aim` is a world point, `fire` and `beam` are held states.
## Returns the events that happened this step.
func tick(delta: float, move: Vector2, aim: Vector2, fire: bool, beam: bool) -> Array:
	_events = []
	var dt := clampf(delta, 0.0, 0.1)
	callout_timer = maxf(0.0, callout_timer - dt)
	callout_cooldown = maxf(0.0, callout_cooldown - dt)
	if callout_timer <= 0.0:
		callout_priority = 0
	if not is_active():
		beam_on = false
		return take_events()
	elapsed += dt
	aim_point = aim
	_update_nick(dt, move)
	_update_bill(dt)
	if fire:
		_fire()
	fire_cooldown = maxf(0.0, fire_cooldown - dt)
	_update_bolts(dt)
	if phase == PHASE_FIGHT:
		_update_spawns(dt)
		_update_enemies(dt)
		_update_boss(dt)
		_update_hazards(dt)
	_update_crushers(dt)
	_update_beam(dt, beam)
	_update_cores(dt)
	_update_overdrive(dt)
	return take_events()


## Events raised outside tick() (dash, interact) are collected here, once.
func take_events() -> Array:
	var out := _events
	_events = []
	return out


func _update_nick(dt: float, move: Vector2) -> void:
	hurt_invuln = maxf(0.0, hurt_invuln - dt)
	dash_invuln = maxf(0.0, dash_invuln - dt)
	dash_cooldown = maxf(0.0, dash_cooldown - dt)
	var dir := move.normalized() if move.length_squared() > 0.0001 else Vector2.ZERO
	if dir != Vector2.ZERO:
		facing = dir
	var step := dir * move_speed() * dt
	if dash_time > 0.0:
		var dash_t := minf(dt, dash_time)
		step = dash_dir * float(_d("dash").get("speed", 360.0)) * dash_t + dir * move_speed() * (dt - dash_t)
		dash_time = maxf(0.0, dash_time - dt)
	nick_pos = _move_circle(nick_pos, step, float(_d("nick").get("radius", 7.0)), true)
	# Shield regeneration after a delay; damage resets the delay.
	if regen_wait > 0.0:
		regen_wait = maxf(0.0, regen_wait - dt)
	elif shield < shield_max:
		shield = minf(shield_max, shield + regen_rate() * dt)


func _update_bill(dt: float) -> void:
	var b := _d("bill")
	var perp := Vector2(-facing.y, facing.x)
	var target := nick_pos - facing * float(b.get("follow_distance", 20.0)) + perp * float(b.get("side_offset", 10.0))
	if bill_pos.distance_to(nick_pos) > float(b.get("recover_distance", 150.0)):
		bill_pos = target  # separated (a long dash, a corner): reappear beside Nick
		return
	bill_pos = bill_pos.lerp(target, clampf(float(b.get("lerp_rate", 6.0)) * dt, 0.0, 1.0))
	var gap := float(b.get("min_gap", 13.0))
	var away := bill_pos - nick_pos
	if away.length() < gap:
		bill_pos = nick_pos + (away.normalized() if away.length() > 0.01 else -facing) * gap


## Moves a circle through the walkable rectangle and the solid circles in
## small steps, so a dash can never tunnel through a boundary.
func _move_circle(pos: Vector2, step: Vector2, radius: float, solid_boss: bool) -> Vector2:
	var steps := maxi(1, int(ceil(step.length() / maxf(1.0, radius * 0.5))))
	var p := pos
	var part := step / float(steps)
	for i in steps:
		p += part
		p = _resolve(p, radius, solid_boss)
	return p


func _resolve(p: Vector2, radius: float, solid_boss: bool) -> Vector2:
	var w := _d("world").get("walkable", {}) as Dictionary
	var rect := Rect2(float(w.get("x", 0)), float(w.get("y", 0)), float(w.get("w", 1280)), float(w.get("h", 960)))
	p.x = clampf(p.x, rect.position.x + radius, rect.end.x - radius)
	p.y = clampf(p.y, rect.position.y + radius, rect.end.y - radius)
	for s in _solids(solid_boss):
		var sd: Array = s
		var c: Vector2 = sd[0]
		var min_d: float = float(sd[1]) + radius
		var off := p - c
		var dist := off.length()
		if dist < min_d:
			p = c + (off / dist if dist > 0.01 else Vector2.DOWN) * min_d
	return p


func _solids(include_boss: bool) -> Array:
	var st := _d("station")
	var out: Array = [[Vector2(float(st.get("x", 640)), float(st.get("y", 470))), float(st.get("solid_radius", 34))]]
	for c in crushers:
		out.append([(c as Dictionary)["pos"], float((c as Dictionary).get("solid_radius", 20))])
	if include_boss and not boss.is_empty() and not boss_defeated:
		out.append([boss["pos"], float(boss["radius"])])
	return out


# ---------------------------------------------------------------- blaster

func _fire() -> void:
	if fire_cooldown > 0.0:
		return
	var bl := _d("blaster")
	var dir := aim_point - nick_pos
	if dir.length() < 1.0:
		dir = facing
	dir = dir.normalized()
	fire_cooldown = float(bl.get("fire_interval", 0.18))
	var cat := RAINBOW if overdrive_active() else spectrum
	bolts.append({
		"id": _new_id(),
		"pos": nick_pos + Vector2(0, -6) + dir * float(bl.get("muzzle_offset", 10.0)),
		"dir": dir,
		"speed": float(bl.get("projectile_speed", 340.0)),
		"life": float(bl.get("projectile_life", 1.1)),
		"cat": cat,
	})
	_emit({"kind": "fire", "cat": cat})


func _update_bolts(dt: float) -> void:
	var keep: Array = []
	var r := float(_d("blaster").get("projectile_radius", 3.0))
	for b in bolts:
		var bolt: Dictionary = b
		bolt["life"] = float(bolt["life"]) - dt
		if float(bolt["life"]) <= 0.0:
			continue
		var from: Vector2 = bolt["pos"]
		var to: Vector2 = from + (bolt["dir"] as Vector2) * float(bolt["speed"]) * dt
		# Swept test: the earliest target along this frame's segment wins, so a
		# fast bolt never skips an enemy and resolves exactly once.
		var best_t := 2.0
		var best: Dictionary = {}
		if phase == PHASE_FIGHT:
			for e in enemies:
				var en: Dictionary = e
				var t := _segment_rect(from, to, body_rect(en).grow(r))
				if t >= 0.0 and t < best_t:
					best_t = t
					best = en
			if not boss.is_empty() and not boss_defeated:
				var tb := _segment_rect(from, to, body_rect(boss).grow(r))
				if tb >= 0.0 and tb < best_t:
					best_t = tb
					best = boss
		for s in _solids(false):
			var ts := _segment_circle(from, to, (s as Array)[0], float((s as Array)[1]))
			if ts >= 0.0 and ts < best_t:
				best_t = ts
				best = {"solid": true}
		if best_t <= 1.0:
			var at := from.lerp(to, best_t)
			if best.has("solid"):
				_emit({"kind": "bolt_blocked", "pos": at})
			else:
				_hit_target(best, bolt, at)
			continue
		if not _in_world(to):
			continue
		bolt["pos"] = to
		keep.append(bolt)
	bolts = keep


func _hit_target(target: Dictionary, bolt: Dictionary, at: Vector2) -> void:
	var is_boss: bool = bool(target.get("is_boss", false))
	if is_boss and String(boss.get("state", "")) != "fight":
		_emit({"kind": "deflect", "pos": at, "cat": active_layer(target), "guarded": true})
		return
	var layer_cat := active_layer(target)
	if layer_cat == "":
		return
	var manual: bool = String(bolt["cat"]) != RAINBOW
	var matched: bool = not manual or String(bolt["cat"]) == layer_cat
	var item_id := _target_item(target)
	if manual:
		_record_decision("e%d:%d" % [int(target["id"]), int(target["layer"])], matched, item_id)
	if not matched:
		_emit({"kind": "deflect", "pos": at, "cat": layer_cat, "item": item_id})
		_break_combo()
		_coach(item_id, layer_cat)
		return
	var bl := _d("blaster")
	var dmg := float(bl.get("reference_damage", 4.0)) * float(bl.get("match_multiplier", 2.5))
	var layer: Dictionary = (target["layers"] as Array)[int(target["layer"])]
	# Overflow damage is discarded: one hit never reaches a hidden layer.
	layer["armor"] = maxf(0.0, float(layer["armor"]) - dmg)
	_emit({"kind": "hit", "pos": at, "cat": layer_cat, "item": item_id, "boss": is_boss, "auto": not manual})
	if not is_boss:
		target["knock"] = (bolt["dir"] as Vector2) * float(bl.get("knockback", 70.0))
		target["flash"] = 0.12
	else:
		boss["flash"] = 0.12
	if float(layer["armor"]) <= 0.0:
		_layer_broken(target, is_boss)


func _layer_broken(target: Dictionary, is_boss: bool) -> void:
	var layers: Array = target["layers"]
	if int(target["layer"]) + 1 < layers.size():
		target["layer"] = int(target["layer"]) + 1
		_emit({"kind": "boss_layer" if is_boss else "layer_exposed", "pos": target["pos"], "cat": active_layer(target), "id": int(target["id"])})
		if is_boss:
			boss["state"] = "transition"
			boss["timer"] = float(_d("boss").get("transition_seconds", 1.4))
			hazards.clear()
			shots.clear()
		return
	if is_boss:
		_defeat_boss()
	else:
		_kill_enemy(target, false)


func _target_item(target: Dictionary) -> String:
	if bool(target.get("is_boss", false)):
		var items: Array = _d("boss").get("layer_items", []) as Array
		var i := int(boss.get("layer", 0))
		return String(items[i]) if i < items.size() else ""
	return String(target.get("item", ""))


# ---------------------------------------------------------------- enemies

func _update_spawns(dt: float) -> void:
	var pacing := _d("pacing")
	# Telegraphed spawns materialise after their warning, never on top of Nick.
	var still: Array = []
	for p in pending_spawns:
		var ps: Dictionary = p
		ps["t"] = float(ps["t"]) - dt
		if float(ps["t"]) > 0.0:
			still.append(ps)
			continue
		var def: Dictionary = (data.get("enemies", {}) as Dictionary).get(String(ps["type"]), {}) as Dictionary
		if (ps["pos"] as Vector2).distance_to(nick_pos) < float(def.get("radius", 11.0)) + 24.0:
			ps["t"] = 0.3
			still.append(ps)
			continue
		_create_enemy(String(ps["type"]), ps["pos"])
	pending_spawns = still
	if boss_spawned:
		return
	spawn_timer -= dt
	if spawn_timer > 0.0:
		return
	var st := current_stage()
	spawn_timer = float(st.get("spawn_interval", 6.0))
	var room := int(st.get("max_alive", 4)) - enemies.size() - pending_spawns.size()
	var group := mini(room, rng.randi_range(int(st.get("group_min", 1)), int(st.get("group_max", 2))))
	for i in group:
		pending_spawns.append({
			"type": _pick_type(st.get("pool", {}) as Dictionary),
			"pos": _pick_spawn_point(float(pacing.get("min_spawn_distance", 240.0))),
			"t": float(pacing.get("spawn_telegraph", 0.9)),
		})


func _pick_type(pool: Dictionary) -> String:
	var keys: Array = pool.keys()
	keys.sort()
	var total := 0
	for k in keys:
		total += int(pool[k])
	var roll := rng.randi_range(1, maxi(1, total))
	for k in keys:
		roll -= int(pool[k])
		if roll <= 0:
			return String(k)
	return String(keys[0])


func _pick_spawn_point(min_dist: float) -> Vector2:
	var far: Array = []
	var best := Vector2.ZERO
	var best_d := -1.0
	for sp in data.get("spawn_points", []) as Array:
		var p := _v(sp, Vector2.ZERO)
		var d := p.distance_to(nick_pos)
		if d >= min_dist:
			far.append(p)
		if d > best_d:
			best_d = d
			best = p
	if far.is_empty():
		return best
	return far[rng.randi_range(0, far.size() - 1)]


func _create_enemy(type_id: String, pos: Vector2) -> Dictionary:
	var def: Dictionary = (data.get("enemies", {}) as Dictionary).get(type_id, {}) as Dictionary
	var layers: Array = []
	for cat in def.get("layers", []) as Array:
		layers.append({"cat": String(cat), "armor": float(def.get("armor", 30)), "max": float(def.get("armor", 30))})
	var pacing := _d("pacing")
	var e := {
		"id": _new_id(), "type": type_id, "item": String(def.get("item", "")),
		"pos": pos, "layers": layers, "layer": 0,
		"radius": float(def.get("radius", 11.0)), "speed": float(def.get("speed", 34.0)),
		"contact_damage": int(def.get("contact_damage", 8)), "charges": bool(def.get("charges", false)),
		"silhouette": String(def.get("silhouette", "blob")), "elite": bool(def.get("elite", false)),
		"stained": bool(def.get("stained", false)), "core": String(def.get("core", "standard")),
		"state": "walk", "timer": 0.0, "charge_dir": Vector2.ZERO,
		"charge_cd": rng.randf_range(float(pacing.get("charge_cooldown_min", 3.5)), float(pacing.get("charge_cooldown_max", 6.0))),
		"contact_cd": 0.0, "knock": Vector2.ZERO, "flash": 0.0, "dead": false,
	}
	enemies.append(e)
	_emit({"kind": "enemy_spawn", "id": int(e["id"]), "pos": pos})
	return e


## Test and tooling entry point: places an enemy directly.
func spawn_enemy(type_id: String, pos: Vector2) -> Dictionary:
	return _create_enemy(type_id, pos)


func _update_enemies(dt: float) -> void:
	var pacing := _d("pacing")
	var nr := float(_d("nick").get("radius", 7.0))
	for e in enemies:
		var en: Dictionary = e
		if bool(en["dead"]):
			continue
		en["flash"] = maxf(0.0, float(en["flash"]) - dt)
		en["contact_cd"] = maxf(0.0, float(en["contact_cd"]) - dt)
		var to_nick: Vector2 = nick_pos - (en["pos"] as Vector2)
		var dir := to_nick.normalized() if to_nick.length() > 0.5 else Vector2.ZERO
		var vel := Vector2.ZERO
		match String(en["state"]):
			"walk":
				vel = dir * float(en["speed"])
				en["charge_cd"] = float(en["charge_cd"]) - dt
				if bool(en["charges"]) and float(en["charge_cd"]) <= 0.0 and to_nick.length() < float(pacing.get("charge_trigger_range", 210.0)):
					en["state"] = "tele"
					en["timer"] = float(pacing.get("charge_telegraph", 0.7))
					en["charge_dir"] = dir if dir != Vector2.ZERO else Vector2.DOWN
			"tele":
				en["timer"] = float(en["timer"]) - dt
				if float(en["timer"]) <= 0.0:
					en["state"] = "charge"
					en["timer"] = float(pacing.get("charge_duration", 0.8))
			"charge":
				vel = (en["charge_dir"] as Vector2) * float(pacing.get("charge_speed", 190.0))
				en["timer"] = float(en["timer"]) - dt
				if float(en["timer"]) <= 0.0:
					_end_charge(en)
			"stun":
				en["timer"] = float(en["timer"]) - dt
				if float(en["timer"]) <= 0.0:
					en["state"] = "walk"
		var knock: Vector2 = en["knock"]
		en["knock"] = knock * maxf(0.0, 1.0 - 8.0 * dt)
		var before: Vector2 = en["pos"]
		en["pos"] = _move_circle(before, (vel + knock) * dt, float(en["radius"]), false)
		if String(en["state"]) == "charge":
			_check_crushers(en)
			# A charge that slams into scenery stops instead of grinding along it.
			if (en["pos"] as Vector2).distance_to(before) < float(pacing.get("charge_speed", 190.0)) * dt * 0.3:
				_end_charge(en)
		if bool(en["dead"]):
			continue
		if (en["pos"] as Vector2).distance_to(nick_pos) <= float(en["radius"]) + nr and float(en["contact_cd"]) <= 0.0:
			en["contact_cd"] = float(pacing.get("contact_cooldown", 0.8))
			damage_nick(int(en["contact_damage"]))
	# Light separation so a group never stacks into one sprite.
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			var a: Dictionary = enemies[i]
			var b: Dictionary = enemies[j]
			var off: Vector2 = (b["pos"] as Vector2) - (a["pos"] as Vector2)
			var min_d := float(a["radius"]) + float(b["radius"])
			if off.length() < min_d and off.length() > 0.01:
				var push := off.normalized() * (min_d - off.length()) * 0.5
				a["pos"] = _resolve((a["pos"] as Vector2) - push, float(a["radius"]), false)
				b["pos"] = _resolve((b["pos"] as Vector2) + push, float(b["radius"]), false)
	enemies = enemies.filter(func(x): return not bool((x as Dictionary)["dead"]))


func _end_charge(en: Dictionary) -> void:
	var pacing := _d("pacing")
	en["state"] = "walk"
	en["charge_cd"] = rng.randf_range(float(pacing.get("charge_cooldown_min", 3.5)), float(pacing.get("charge_cooldown_max", 6.0)))


## Removes an enemy through the single authoritative death path: one drop per
## enemy, whether it was shot down or recycled by a crusher.
func _kill_enemy(en: Dictionary, precleaned: bool) -> void:
	if bool(en.get("dead", false)):
		return
	en["dead"] = true
	var shells: Array = []
	if not precleaned:
		for l in en["layers"] as Array:
			shells.append(String((l as Dictionary)["cat"]))
		if String(en["core"]) != "dual":
			shells = [shells[shells.size() - 1]]
	_drop_core(String(en["core"]), en["pos"], shells, String(en["item"]))
	_emit({"kind": "enemy_down", "pos": en["pos"], "id": int(en["id"]), "recycled": precleaned, "item": String(en["item"])})


func _drop_core(core_type: String, pos: Vector2, shells: Array, item_id: String) -> Dictionary:
	var it := item(item_id)
	var core := {
		"id": _new_id(), "type": core_type, "pos": _resolve(pos, 8.0, true),
		"shells": shells, "shell": 0, "item": item_id,
		"cat": String(it.get("category", "")) if core_type == "standard" else "",
		"state": "clean" if shells.is_empty() else "dirty",
		"collected": false, "touching": false, "attempt_cd": 0.0, "last_spectrum": "",
	}
	cores.append(core)
	_emit({"kind": "core_drop", "id": int(core["id"]), "pos": core["pos"], "type": core_type, "clean": shells.is_empty()})
	return core


# ---------------------------------------------------------------- crushers

func _update_crushers(dt: float) -> void:
	for c in crushers:
		var cd: Dictionary = c
		cd["timer"] = maxf(0.0, float(cd["timer"]) - dt)
		cd["slam"] = maxf(0.0, float(cd["slam"]) - dt)


## A charging enemy reached a crusher mouth. A matching crusher strips the
## exposed layer: a single-layer enemy (or an elite's last layer) is recycled
## through the normal death path with one pre-cleaned core; an elite with
## layers left keeps them and is stunned. A mismatched crusher only bounces
## the enemy: no damage, no drop, no sorting credit.
func _check_crushers(en: Dictionary) -> void:
	for c in crushers:
		var cd: Dictionary = c
		if float(cd["timer"]) > 0.0:
			continue
		if (en["pos"] as Vector2).distance_to(cd["pos"]) > float(cd.get("mouth_radius", 40)) + float(en["radius"]):
			continue
		cd["timer"] = float(cd.get("cooldown", 1.2))
		cd["slam"] = 0.35
		var matched: bool = String(cd.get("category", "")) == active_layer(en)
		_emit({"kind": "crusher", "id": String(cd.get("id", "")), "pos": cd["pos"], "match": matched, "cat": String(cd.get("category", ""))})
		en["state"] = "stun"
		en["timer"] = 0.8
		var away: Vector2 = ((en["pos"] as Vector2) - (cd["pos"] as Vector2)).normalized()
		en["knock"] = away * 140.0
		if not matched:
			return
		if int(en["layer"]) + 1 < (en["layers"] as Array).size():
			en["layer"] = int(en["layer"]) + 1
			_emit({"kind": "layer_exposed", "pos": en["pos"], "cat": active_layer(en), "id": int(en["id"])})
		else:
			_kill_enemy(en, true)
		return


# ---------------------------------------------------------------- boss

func _spawn_boss() -> void:
	if boss_spawned:
		return
	boss_spawned = true
	var bd := _d("boss")
	var layers: Array = []
	for cat in bd.get("layers", []) as Array:
		layers.append({"cat": String(cat), "armor": float(bd.get("armor", 220)), "max": float(bd.get("armor", 220))})
	boss = {
		"id": _new_id(), "is_boss": true, "pos": _v(_d("world").get("boss_spawn", {}), Vector2(640, 230)),
		"layers": layers, "layer": 0, "radius": float(bd.get("radius", 30.0)),
		"state": "entry", "timer": float(bd.get("entry_seconds", 2.0)),
		"toss_t": float((bd.get("toss", {}) as Dictionary).get("interval", 2.8)),
		"ring_t": float((bd.get("ring", {}) as Dictionary).get("interval", 5.2)),
		"ring_warn": 0.0, "contact_cd": 0.0, "flash": 0.0,
	}
	pending_spawns.clear()
	_emit({"kind": "boss_spawn", "pos": boss["pos"]})


func _update_boss(dt: float) -> void:
	if boss.is_empty() or boss_defeated:
		return
	var bd := _d("boss")
	boss["flash"] = maxf(0.0, float(boss["flash"]) - dt)
	boss["contact_cd"] = maxf(0.0, float(boss["contact_cd"]) - dt)
	if String(boss["state"]) != "fight":
		boss["timer"] = float(boss["timer"]) - dt
		if float(boss["timer"]) <= 0.0:
			boss["state"] = "fight"
		return
	var to_nick: Vector2 = nick_pos - (boss["pos"] as Vector2)
	if to_nick.length() > 110.0:
		boss["pos"] = _move_circle(boss["pos"], to_nick.normalized() * float(bd.get("speed", 20.0)) * dt, float(boss["radius"]), false)
	var nr := float(_d("nick").get("radius", 7.0))
	if (boss["pos"] as Vector2).distance_to(nick_pos) <= float(boss["radius"]) + nr + 1.5 and float(boss["contact_cd"]) <= 0.0:
		boss["contact_cd"] = 0.8
		damage_nick(int(bd.get("contact_damage", 14)))
	# Trash toss: telegraphed landing zones around Nick, with gaps to dash into.
	var toss: Dictionary = bd.get("toss", {}) as Dictionary
	boss["toss_t"] = float(boss["toss_t"]) - dt
	if float(boss["toss_t"]) <= 0.0:
		boss["toss_t"] = float(toss.get("interval", 2.8))
		var n := int(toss.get("targets", 3))
		var spread := float(toss.get("spread", 70.0))
		var base_ang := rng.randf_range(0.0, TAU)
		for i in n:
			var off := Vector2.ZERO if i == 0 else Vector2.RIGHT.rotated(base_ang + TAU * float(i) / float(maxi(1, n - 1))) * spread
			hazards.append({"pos": _resolve(nick_pos + off, 4.0, false), "r": float(toss.get("radius", 26.0)),
				"t": float(toss.get("telegraph", 1.15)), "life": float(toss.get("telegraph", 1.15)), "damage": int(toss.get("damage", 18))})
		_emit({"kind": "toss_warn"})
	# Junk ring: a telegraphed burst with a gap of missing pieces.
	var ring: Dictionary = bd.get("ring", {}) as Dictionary
	if float(boss["ring_warn"]) > 0.0:
		boss["ring_warn"] = float(boss["ring_warn"]) - dt
		if float(boss["ring_warn"]) <= 0.0:
			_fire_ring(ring)
	else:
		boss["ring_t"] = float(boss["ring_t"]) - dt
		if float(boss["ring_t"]) <= 0.0:
			boss["ring_t"] = float(ring.get("interval", 5.2))
			boss["ring_warn"] = float(ring.get("telegraph", 0.8))
			_emit({"kind": "ring_warn"})


func _fire_ring(ring: Dictionary) -> void:
	var count := int(ring.get("count", 14))
	var gap := int(ring.get("gap", 3))
	var start := rng.randi_range(0, count - 1)
	for i in count:
		if posmod(i - start, count) < gap:
			continue
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / float(count))
		shots.append({"pos": (boss["pos"] as Vector2) + Vector2(0, -14) + dir * 20.0, "vel": dir * float(ring.get("speed", 90.0)),
			"r": float(ring.get("radius", 5.0)), "life": float(ring.get("life", 7.0)), "damage": int(ring.get("damage", 10))})
	_emit({"kind": "ring_fire"})


func _update_hazards(dt: float) -> void:
	var nr := float(_d("nick").get("radius", 7.0))
	var keep: Array = []
	for h in hazards:
		var hz: Dictionary = h
		hz["t"] = float(hz["t"]) - dt
		if float(hz["t"]) > 0.0:
			keep.append(hz)
			continue
		_emit({"kind": "toss_land", "pos": hz["pos"]})
		if (hz["pos"] as Vector2).distance_to(nick_pos) <= float(hz["r"]) + nr:
			damage_nick(int(hz["damage"]))
	hazards = keep
	var keep_shots: Array = []
	for s in shots:
		var sh: Dictionary = s
		sh["life"] = float(sh["life"]) - dt
		var from: Vector2 = sh["pos"]
		var to: Vector2 = from + (sh["vel"] as Vector2) * dt
		if _segment_circle(from, to, nick_pos, float(sh["r"]) + nr) >= 0.0:
			damage_nick(int(sh["damage"]))
			continue
		if float(sh["life"]) <= 0.0 or not _in_world(to):
			continue
		sh["pos"] = to
		keep_shots.append(sh)
	shots = keep_shots


func _defeat_boss() -> void:
	if boss_defeated:
		return
	boss_defeated = true
	phase = PHASE_REWARD
	# Every remaining threat resolves safely before the rewards appear.
	hazards.clear()
	shots.clear()
	pending_spawns.clear()
	for e in enemies:
		_emit({"kind": "enemy_cleared", "pos": (e as Dictionary)["pos"]})
	enemies.clear()
	_emit({"kind": "boss_down", "pos": boss["pos"]})
	_spawn_rewards()


func _spawn_rewards() -> void:
	var rs: Dictionary = _d("world").get("reward_spawn", {}) as Dictionary
	_drop_core("super", _v(rs.get("super_core", {}), Vector2(600, 300)), categories.duplicate(), "")
	chip = {"pos": _v(rs.get("navigation_chip", {}), Vector2(690, 300))}
	_emit({"kind": "rewards_spawn"})


## Debug and test entry point: ends the boss fight through the normal path.
func debug_defeat_boss() -> bool:
	if boss_defeated or not is_active():
		return false
	charge = maxi(charge, boss_at())
	stage_index = stages().size()
	_spawn_boss()
	_defeat_boss()
	return true


# ---------------------------------------------------------------- damage

## Shield first, then health. Invulnerability (hurt window, dash, any
## non-fight phase) blocks the whole hit. Returns true on the killing blow.
func damage_nick(amount: int) -> bool:
	if amount <= 0 or is_invulnerable():
		return false
	var rest := float(amount)
	var absorbed := minf(shield, rest)
	shield -= absorbed
	rest -= absorbed
	health = maxf(0.0, health - rest)
	last_damage = amount
	regen_wait = float(_d("nick").get("shield_regen_delay", 2.5))
	hurt_invuln = float(_d("nick").get("hurt_invulnerable_seconds", 0.6))
	_emit({"kind": "nick_hurt", "amount": amount, "shield_only": rest <= 0.0, "pos": nick_pos})
	if absorbed > 0.0 and shield <= 0.0:
		_emit({"kind": "shield_break"})
	if health <= 0.0:
		phase = PHASE_DEFEAT
		beam_on = false
		bolts.clear()
		hazards.clear()
		shots.clear()
		_emit({"kind": "defeat"})
		return true
	return false


# ---------------------------------------------------------------- cores

func _update_beam(dt: float, held: bool) -> void:
	beam_on = held and is_active()
	if not beam_on:
		beam_target_id = -1
		beam_progress = 0.0
		return
	var range_px := float(_d("cores").get("beam_range", 130.0))
	# Deterministic target: keep the current core while it stays eligible,
	# otherwise the nearest dirty core in range (lowest id breaks a tie).
	var current := core_by_id(beam_target_id)
	if current.is_empty() or String(current["state"]) != "dirty" or (current["pos"] as Vector2).distance_to(nick_pos) > range_px:
		var best_id := -1
		var best_d := INF
		for c in cores:
			var cd: Dictionary = c
			if String(cd["state"]) != "dirty":
				continue
			var d := (cd["pos"] as Vector2).distance_to(nick_pos)
			if d <= range_px and (d < best_d or (is_equal_approx(d, best_d) and int(cd["id"]) < best_id)):
				best_d = d
				best_id = int(cd["id"])
		if best_id != beam_target_id:
			beam_progress = 0.0
		beam_target_id = best_id
		current = core_by_id(best_id)
	if current.is_empty():
		return
	beam_progress += dt
	if beam_progress >= float(_d("cores").get("beam_clean_seconds", 0.3)):
		beam_progress = 0.0
		if _attempt_clean(current, "beam"):
			pass


func _update_cores(dt: float) -> void:
	var cfg := _d("cores")
	var contact := float(cfg.get("contact_radius", 15.0))
	var magnet_range := float(cfg.get("beam_range", 130.0))
	for c in cores:
		var core: Dictionary = c
		if bool(core["collected"]):
			continue
		core["attempt_cd"] = maxf(0.0, float(core["attempt_cd"]) - dt)
		var dist := (core["pos"] as Vector2).distance_to(nick_pos)
		if String(core["state"]) == "dirty":
			var touching: bool = dist <= contact
			var entered: bool = touching and not bool(core["touching"])
			core["touching"] = touching
			if touching and float(core["attempt_cd"]) <= 0.0 and (entered or spectrum != String(core["last_spectrum"])):
				_attempt_clean(core, "touch")
		elif dist <= magnet_range:
			# A clean core travels to Nick's pack and resolves exactly once.
			var to: Vector2 = nick_pos - (core["pos"] as Vector2)
			var step := float(cfg.get("magnet_speed", 240.0)) * dt
			core["pos"] = nick_pos if to.length() <= step else (core["pos"] as Vector2) + to.normalized() * step
			if (core["pos"] as Vector2).distance_to(nick_pos) <= float(cfg.get("collect_radius", 9.0)):
				_collect_core(core)
	cores = cores.filter(func(x): return not bool((x as Dictionary)["collected"]))


## One cleaning decision against the core's exposed shell. Matching removes
## that shell; the wrong color sparks harmlessly and nudges Nick back. The
## first decision for each shell is recorded for accuracy.
func _attempt_clean(core: Dictionary, how: String) -> bool:
	var shell := active_shell(core)
	if shell == "":
		return false
	var item_id := String(core.get("item", ""))
	if String(core["type"]) == "super":
		item_id = ""
	var matched: bool = spectrum == shell
	if how == "beam" and not matched and spectrum == String(core["last_spectrum"]):
		return false  # the same wrong color again: no repeated spark
	core["last_spectrum"] = spectrum
	_record_decision("c%d:%d" % [int(core["id"]), int(core["shell"])], matched, item_id)
	if not matched:
		var cfg := _d("cores")
		core["attempt_cd"] = float(cfg.get("spark_cooldown", 0.7))
		_emit({"kind": "core_spark", "id": int(core["id"]), "pos": core["pos"], "cat": shell})
		if how == "touch":
			var away: Vector2 = nick_pos - (core["pos"] as Vector2)
			nick_pos = _move_circle(nick_pos, (away.normalized() if away.length() > 0.1 else Vector2.DOWN) * float(cfg.get("nudge", 22.0)), float(_d("nick").get("radius", 7.0)), true)
		_break_combo()
		if item_id != "":
			_coach(item_id, shell)
		return false
	core["attempt_cd"] = 0.15
	core["shell"] = int(core["shell"]) + 1
	var done: bool = int(core["shell"]) >= (core["shells"] as Array).size()
	_emit({"kind": "super_unlock" if String(core["type"]) == "super" else "core_cleaned", "id": int(core["id"]), "pos": core["pos"], "cat": shell, "done": done, "lock": int(core["shell"])})
	if done:
		core["state"] = "clean"
	return true


func _collect_core(core: Dictionary) -> void:
	if bool(core["collected"]):
		return
	core["collected"] = true
	var cfg := _d("cores")
	var before := charge
	match String(core["type"]):
		"super":
			super_collected = true
			charge = 100
		"dual":
			charge = mini(charge + int(cfg.get("dual_value", 8)), _charge_cap())
		_:
			charge = mini(charge + int(cfg.get("standard_value", 4)), _charge_cap())
	_emit({"kind": "core_collected", "id": int(core["id"]), "type": String(core["type"]), "gained": charge - before, "pos": core["pos"]})
	if String(core["type"]) == "standard" and String(core["cat"]) != "":
		_advance_combo(String(core["cat"]))
	_check_stage()
	_check_victory()


func _charge_cap() -> int:
	return 100 if super_collected else boss_at()


func _check_stage() -> void:
	var list := stages()
	while stage_index < list.size() and charge >= int((list[stage_index] as Dictionary).get("until", 100)):
		stage_index += 1
		if stage_index < list.size():
			_emit({"kind": "stage", "stage": stage_number(), "name": String(current_stage().get("name", ""))})
	if stage_index >= list.size() and not boss_spawned and phase == PHASE_FIGHT:
		_spawn_boss()


func _check_victory() -> void:
	if victory_reported or not super_collected or not chip_collected:
		return
	victory_reported = true
	phase = PHASE_VICTORY
	beam_on = false
	_emit({"kind": "victory"})


## Test entry point: adds charge as if cores had been collected.
func add_charge_for_test(points: int) -> void:
	charge = mini(charge + points, _charge_cap())
	_check_stage()


# ---------------------------------------------------------------- combo

func _advance_combo(cat: String) -> void:
	if combo.has(cat):
		combo = [cat]
	else:
		combo.append(cat)
	_emit({"kind": "combo", "count": combo.size()})
	if combo.size() >= categories.size():
		combo.clear()
		# Retrigger refreshes the full duration; it never stacks or multiplies.
		overdrive = float(_d("overdrive").get("duration", 8.0))
		overdrive_count += 1
		_emit({"kind": "overdrive"})


func _break_combo() -> void:
	if not combo.is_empty():
		combo.clear()
		_emit({"kind": "combo", "count": 0})


func _update_overdrive(dt: float) -> void:
	if overdrive <= 0.0:
		return
	overdrive = maxf(0.0, overdrive - dt)
	if overdrive <= 0.0:
		_emit({"kind": "overdrive_end"})


# ---------------------------------------------------------------- coaching

func _record_decision(key: String, correct: bool, item_id: String) -> void:
	if decisions.has(key):
		return
	decisions[key] = correct
	if not correct and item_id != "":
		mismatch_counts[item_id] = int(mismatch_counts.get(item_id, 0)) + 1


## Bill's short correction. Rate-limited; a trick or layered item may replace
## a basic message, but nothing floods the screen.
func _coach(item_id: String, cat: String) -> void:
	var it := item(item_id)
	var text := String((it.get("layer_callouts", {}) as Dictionary).get(cat, it.get("callout", "")))
	if text == "":
		return
	var prio := 2 if bool(it.get("trick", false)) or it.has("layers") else 1
	if callout_cooldown > 0.0 and (prio <= callout_priority or text == callout_text):
		return
	var cfg := _d("callouts")
	callout_text = text
	callout_priority = prio
	callout_timer = float(cfg.get("show_seconds", 2.2))
	callout_cooldown = float(cfg.get("cooldown", 2.6))
	_emit({"kind": "callout", "text": text})


# ---------------------------------------------------------------- helpers

func _emit(e: Dictionary) -> void:
	_events.append(e)


func _new_id() -> int:
	_next_id += 1
	return _next_id


func _d(key: String) -> Dictionary:
	return data.get(key, {}) as Dictionary


func _v(raw: Variant, fallback: Vector2) -> Vector2:
	if raw is Dictionary:
		return Vector2(float((raw as Dictionary).get("x", fallback.x)), float((raw as Dictionary).get("y", fallback.y)))
	return fallback


func _in_world(p: Vector2) -> bool:
	var wd := _d("world")
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= float(wd.get("width", 1280)) and p.y <= float(wd.get("height", 960))


## The shot hitbox: the screen-space body each enemy is drawn with (its
## ground point is the bottom edge), so a bolt that visibly touches the sprite
## hits it. Ground contact (touch damage, crushers, walls) still uses the
## foot circle. eco_arena_screen.gd draws inside these same bounds.
func body_rect(target: Dictionary) -> Rect2:
	var p: Vector2 = target["pos"]
	if bool(target.get("is_boss", false)):
		return Rect2(p.x - 46.0, p.y - 86.0, 92.0, 86.0)
	var r := float(target.get("radius", 10.0))
	match String(target.get("silhouette", "blob")):
		"box":
			return Rect2(p.x - r - 5.0, p.y - r * 1.85 - 14.0, r * 2.0 + 10.0, r * 1.85 + 14.0)
		"sheet":
			return Rect2(p.x - r - 4.0, p.y - r * 1.9 - 6.0, r * 2.0 + 8.0, r * 1.9 + 6.0)
		"bottle":
			return Rect2(p.x - r * 0.75, p.y - r * 2.6 - 8.0, r * 1.5, r * 2.6 + 8.0)
		"can":
			return Rect2(p.x - r * 0.8, p.y - r * 2.2 - 7.0, r * 1.6, r * 2.2 + 7.0)
		"crushed":
			return Rect2(p.x - r - 2.0, p.y - r * 1.7 - 2.0, r * 2.0 + 4.0, r * 1.7 + 2.0)
	return Rect2(p.x - r, p.y - r * 2.0 - 2.0, r * 2.0, r * 2.0 + 2.0)


## Earliest t in [0, 1] where the segment a->b enters the rectangle, or -1.
static func _segment_rect(a: Vector2, b: Vector2, rect: Rect2) -> float:
	if rect.has_point(a):
		return 0.0
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var lo: float = rect.position[axis]
		var hi: float = rect.end[axis]
		if absf(d[axis]) < 0.000001:
			if a[axis] < lo or a[axis] > hi:
				return -1.0
			continue
		var ta: float = (lo - a[axis]) / d[axis]
		var tb: float = (hi - a[axis]) / d[axis]
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return -1.0
	return t0


## Earliest t in [0, 1] where the segment a->b enters the circle, or -1.
static func _segment_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> float:
	var d := b - a
	var f := a - c
	if f.length_squared() <= r * r:
		return 0.0
	var qa := d.dot(d)
	if qa < 0.000001:
		return -1.0
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return -1.0
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else -1.0
