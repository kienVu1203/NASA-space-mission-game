extends RefCounted
## One salvage sortie: world simulation and rendering for the top-down mode.
## Pure model + draw calls; the game controller feeds input and handles screens.

const Pal := preload("res://core/starfall/sf_palette.gd")
const ShipModel := preload("res://core/starfall/sf_ship_model.gd")
const DebrisModel := preload("res://core/starfall/sf_debris_model.gd")
const VW := 480
const VH := 270
const TOP_BAND := 25.0
const BOTTOM_BAND := 26.0

var state
var skin
var audio
var mission_index: int = 0
var sector: Dictionary = {}
var sector_id: String = ""
var ship
var debris: Array = []
var world: Rect2 = Rect2(0, 0, 2400, 1800)
var camera: Vector2 = Vector2.ZERO
var station_pos: Vector2 = Vector2.ZERO
var dock_radius: float = 76.0
var finished: bool = false
var towed: bool = false
var elapsed: float = 0.0
var toasts: Array = []
var pa_line: String = ""
var pa_timer: float = 0.0
var pa_queue: Array = []
var log_queue: Array = []
var impact_cooldown: float = 0.0
var rng := RandomNumberGenerator.new()
var collect_fx: Array = []
var haul: Dictionary = {}
var exhaust: Array = []
var _next_id: int = 0
var _hold_full_notified: bool = false
var _throttle: float = 0.0
var _scan_angle: float = 0.0
var _brief_timer: float = 0.0
var _vo: Vector2 = Vector2.ZERO
var _vs: float = 1.0


func setup(p_state, p_skin, p_audio, index: int) -> void:
	state = p_state
	skin = p_skin
	audio = p_audio
	mission_index = index
	sector = state.sector(index)
	sector_id = String(sector.get("id", ""))
	var runs: int = 0
	var st: Dictionary = state.sector_state.get(sector_id, {}) as Dictionary
	if st.has("runs"):
		runs = int(st["runs"])
	rng.seed = hash(sector_id) * 7919 + 13 + runs * 104729
	var cfg: Dictionary = state.balance.get("world", {}) as Dictionary
	var w := float(cfg.get("width", 2400.0))
	var h := float(cfg.get("height", 1800.0))
	world = Rect2(0, 0, w, h)
	station_pos = Vector2(w * 0.5, h * 0.5)
	dock_radius = float(cfg.get("dock_radius", 76.0))
	ship = ShipModel.new(state.ship_stats(), station_pos + Vector2(-70, -74))
	_spawn_debris()
	camera = _camera_target()
	_push_pa_for_act()
	_shove_toast("%s - %s" % [String(sector.get("designation", "")), String(sector.get("name", ""))], Pal.CYAN)
	_brief_timer = 3.0
	_scan_angle = 0.0


func _spawn_debris() -> void:
	debris.clear()
	var spawn: Dictionary = sector.get("spawn", {}) as Dictionary
	var radius_arr: Array = sector.get("spawn_radius", [300.0, 900.0]) as Array
	var r_min := float(radius_arr[0])
	var r_max := float(radius_arr[1])
	for key in spawn.keys():
		var count := int(spawn[key])
		var kind := String(key)
		var data: Dictionary = (state.debris_types.get(kind, {}) as Dictionary)
		if data.is_empty():
			continue
		for i in count:
			var ang: float = rng.randf() * TAU
			var dist: float = rng.randf_range(r_min, r_max)
			var pos := station_pos + Vector2(cos(ang), sin(ang)) * dist
			pos.x = clampf(pos.x, 90.0, world.size.x - 90.0)
			pos.y = clampf(pos.y, 70.0, world.size.y - 70.0)
			debris.append(DebrisModel.new(_next_id, kind, data, pos, rng.randi()))
			_next_id += 1


func _push_pa_for_act() -> void:
	var key := "act1_start"
	var act := int(sector.get("act", 1))
	if act == 2:
		key = "act2_start"
	elif act >= 3:
		key = "act3_start"
	var lines: Array = state.pa.get(key, []) as Array
	for l in lines:
		pa_queue.append(String(l))
	if not pa_queue.is_empty():
		pa_line = String(pa_queue.pop_front())
		pa_timer = 7.0


func _shove_toast(msg: String, color: Color = Pal.PAPER) -> void:
	toasts.append({"text": msg, "color": color, "life": 3.4})
	if toasts.size() > 5:
		toasts.pop_front()


# ---------------------------------------------------------------- update

func update(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	_scan_angle += delta * 1.6
	impact_cooldown = maxf(0.0, impact_cooldown - delta)
	_brief_timer = maxf(0.0, _brief_timer - delta)

	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1.0
	var want_beam: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	ship.step(delta, move, want_beam, world)
	_throttle = lerpf(_throttle, 1.0 if ship.thrusting else 0.0, clampf(delta * 10.0, 0.0, 1.0))
	audio.set_thruster(_throttle)
	audio.set_beam(1.0 if ship.beaming else 0.0)

	for d in debris:
		d.step(delta, world)

	_apply_beam(delta)
	_check_impacts(delta)
	_update_camera(delta)
	_update_fx(delta)
	_update_warnings()
	_update_toasts(delta)


func _update_toasts(delta: float) -> void:
	for t in toasts:
		t["life"] = float(t["life"]) - delta
	while not toasts.is_empty() and float(toasts[0]["life"]) <= 0.0:
		toasts.pop_front()

	if pa_timer > 0.0:
		pa_timer -= delta
	elif pa_queue.is_empty():
		pa_timer = 0.0
	else:
		pa_line = String(pa_queue.pop_front())
		pa_timer = 6.5


func _update_warnings() -> void:
	var fuel_low: bool = ship.fuel / maxf(1.0, ship.fuel_max) < 0.2
	var power_low: bool = ship.power / maxf(1.0, ship.power_max) < 0.2
	var any := fuel_low or power_low
	audio.set_warning(any, ship.fuel / maxf(1.0, ship.fuel_max) < 0.08 or ship.power / maxf(1.0, ship.power_max) < 0.08)


func _apply_beam(delta: float) -> void:
	if not ship.beaming:
		return
	var origin: Vector2 = ship.position
	var reach: float = ship.beam_radius()
	var best: Variant = null
	var best_d: float = INF
	for d in debris:
		if d.collected:
			continue
		var dist: float = origin.distance_to(d.position)
		if dist < reach and dist < best_d:
			best_d = dist
			best = d
	if best == null:
		return
	var target = best
	var pull_dir: Vector2 = (origin - target.position).normalized()
	target.velocity = target.velocity.lerp(pull_dir * ship.stats.get("beam_pull", 560.0), clampf(delta * 5.0, 0.0, 1.0))
	target.pull = minf(1.0, target.pull + delta * 2.0)
	var touch: float = ship.pickup_radius() + maxf(6.0, target.radius * 0.5)
	if best_d <= touch:
		_try_collect(target)


func _try_collect(d) -> void:
	if d.collected:
		return
	var check: Dictionary = ship.can_take(d.entry)
	if not bool(check.get("ok", false)):
		if not _hold_full_notified:
			_hold_full_notified = true
			_shove_toast(String(check.get("reason", "HOLD FULL")), Pal.ORANGE)
			audio.sfx_denied()
			if String(check.get("reason", "")) == "HOLD FULL":
				var lines: Array = state.pa.get("hold_full", []) as Array
				if not lines.is_empty():
					pa_queue.append(String(lines[0]))
		return
	_hold_full_notified = false
	var value: float = d.value()
	ship.add_cargo(d.entry)
	d.collected = true
	var kind := String(d.kind)
	if haul.has(kind):
		haul[kind] = int(haul[kind]) + 1
	else:
		haul[kind] = 1
	collect_fx.append({"p": d.position, "t": 0.5, "color": Pal.DEBRIS_COLORS.get(d.kind, Pal.HIGH)})
	audio.sfx_clank()
	_shove_toast("+%d  %s" % [int(round(value)), d.display_name()], Pal.CYAN)
	# Satellites carry a small pool of logs, so a full archive is reachable.
	var log_id := ""
	var pool: Array = d.entry.get("logs", []) as Array
	if not pool.is_empty():
		var start_i: int = int(rng.randi()) % pool.size()
		for off in pool.size():
			var cand := String(pool[(start_i + off) % pool.size()])
			if not state.found_logs.has(cand):
				log_id = cand
				break
		if log_id == "":
			log_id = String(pool[start_i])
	else:
		log_id = String(d.entry.get("log", ""))
	if log_id != "" and state.add_log(log_id):
		log_queue.append(log_id)
		_shove_toast("LOG ARCHIVED - PRESS L TO READ", Pal.GOLD)
	if d.is_special():
		audio.sfx_specimen()
		_shove_toast("SEALED POD SECURED. DO NOT VAPORIZE.", Pal.GREEN)


func _check_impacts(_delta: float) -> void:
	if impact_cooldown > 0.0:
		return
	var ship_r := 13.0
	for d in debris:
		if d.collected:
			continue
		if d.position.distance_to(ship.position) < ship_r + d.radius * 0.7:
			var rel: float = (d.velocity - ship.velocity).length()
			var speed: float = float(state.balance.get("impact_speed", 95.0))
			if rel > speed:
				var loss: float = float(ship.stats.get("impact_power_loss", 4.0)) * (rel / speed)
				ship.power = maxf(0.0, ship.power - loss)
				impact_cooldown = 0.7
				audio.sfx_thump()
				_shove_toast("HULL EVENT - POWER -%d" % int(round(loss)), Pal.ORANGE)
				var lines: Array = state.pa.get("impact", []) as Array
				if not lines.is_empty() and rng.randf() < 0.5:
					pa_queue.append(String(lines[0]))
				# Collision bounces the ship, which reads as inertia.
				ship.velocity += (ship.position - d.position).normalized() * 55.0
				d.velocity += (d.position - ship.position).normalized() * 40.0
				break


func _camera_target() -> Vector2:
	var half := Vector2(VW, VH) * 0.5
	var target: Vector2 = ship.position - half + Vector2(0, 26)
	target.x = clampf(target.x, 0.0, maxf(0.0, world.size.x - VW))
	target.y = clampf(target.y, 0.0, maxf(0.0, world.size.y - VH))
	return target


func _update_camera(delta: float) -> void:
	camera = camera.lerp(_camera_target(), clampf(delta * 6.0, 0.0, 1.0))


func _update_fx(delta: float) -> void:
	for f in collect_fx:
		f["t"] = float(f["t"]) - delta
	while not collect_fx.is_empty() and float(collect_fx[0]["t"]) <= 0.0:
		collect_fx.pop_front()

	# Thruster exhaust: 2x2 fading squares behind the hull.
	if ship.thrusting and rng.randf() < 0.9:
		var back: Vector2 = ship.position - Vector2(cos(ship.heading), sin(ship.heading)) * 12.0
		exhaust.append({
			"p": back + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)),
			"v": -Vector2(cos(ship.heading), sin(ship.heading)) * rng.randf_range(40, 90) + ship.velocity * 0.1,
			"t": 0.42, "life": 0.42,
		})
	for e in exhaust:
		e["p"] = (e["p"] as Vector2) + (e["v"] as Vector2) * delta
		e["t"] = float(e["t"]) - delta
	while not exhaust.is_empty() and float(exhaust[0]["t"]) <= 0.0:
		exhaust.pop_front()
	if exhaust.size() > 120:
		exhaust = exhaust.slice(exhaust.size() - 120)


# ---------------------------------------------------------------- sortie end

func at_station() -> bool:
	return ship.position.distance_to(station_pos) <= dock_radius


func can_dock() -> bool:
	return at_station() and not finished


func dock() -> Dictionary:
	finished = true
	towed = false
	audio.sfx_dock()
	audio.set_thruster(0.0)
	audio.set_beam(0.0)
	audio.set_warning(false)
	return _finalize(1.0)


func distress_tow() -> Dictionary:
	finished = true
	towed = true
	audio.sfx_back()
	audio.set_thruster(0.0)
	audio.set_beam(0.0)
	audio.set_warning(false)
	return _finalize(0.7)


func _finalize(multiplier: float) -> Dictionary:
	var value: float = ship.cargo_value * multiplier
	var report: Dictionary = state.bank_sortie(mission_index, value, ship.cargo_mass, ship.collected, ship.spec)
	report["towed"] = towed
	report["fee"] = ship.cargo_value - value
	report["elapsed"] = elapsed
	report["specimen"] = ship.spec
	report["fuel_left"] = ship.fuel
	report["power_left"] = ship.power
	report["sector_name"] = String(sector.get("name", ""))
	report["sector_designation"] = String(sector.get("designation", ""))
	report["report_line"] = String(sector.get("report", ""))
	report["haul"] = haul.duplicate()
	report["hold"] = ship.cargo_ratio()
	return report


# ---------------------------------------------------------------- drawing

func draw(ci: CanvasItem, sk, origin: Vector2, scale: float) -> void:
	_vo = origin
	_vs = scale
	# World layer.
	ci.draw_set_transform(origin, 0.0, Vector2(scale, scale))
	_draw_world(ci)
	# HUD layer, same virtual space.
	ci.draw_set_transform(origin, 0.0, Vector2(scale, scale))
	_draw_hud(ci)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Sprite-space transform. draw_set_transform replaces rather than composes,
## so every rotated sprite has to fold the view transform in itself.
func _sprite_xform(ci: CanvasItem, view_pos: Vector2, rot: float = 0.0) -> void:
	ci.draw_set_transform(_vo + view_pos * _vs, rot, Vector2(_vs, _vs))


func _restore_xform(ci: CanvasItem) -> void:
	ci.draw_set_transform(_vo, 0.0, Vector2(_vs, _vs))


func _draw_world(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, VW, VH), Pal.DEEP, true)
	var cam: Vector2 = camera.round()
	# Deterministic star parallax.
	for i in 46:
		var px: float = fmod(float(i * 97), VW)
		var py: float = fmod(float(i * 53 + i * i), VH)
		var sp: Vector2 = Vector2(px, py)
		var col: Color = Pal.STAR_DIM if i % 3 != 0 else Pal.STAR_BRIGHT
		ci.draw_rect(Rect2(sp.floor(), Vector2(1, 1)), col, true)
	for i in 12:
		var bp: Vector2 = Vector2(fmod(float(i * 131 + 20), VW), fmod(float(i * 79 + 40), VH))
		ci.draw_rect(Rect2(bp.floor(), Vector2(1, 1)), Pal.NIGHT.lightened(0.22), true)

	_draw_station(ci, cam)

	# Debris.
	for d in debris:
		if d.collected:
			continue
		var p: Vector2 = (d.position - cam).round()
		if p.x < -40 or p.x > VW + 40:
			continue
		# Keep the play field clear of the HUD bands.
		if p.y < TOP_BAND - 10 or p.y > VH - BOTTOM_BAND - 14:
			continue
		var tex: Texture2D = skin.sprites.get(String(d.entry.get("sprite", d.kind)), null)
		if tex == null:
			continue
		var size := Vector2(tex.get_size())
		_sprite_xform(ci, p, d.rotation)
		ci.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
		# Blinking beacon on satellites and the pod.
		if d.kind == "satellite" or d.kind == "specimen":
			if sin(d.blink_phase * 2.0) > 0.2:
				ci.draw_rect(Rect2(Vector2(-2, -size.y * 0.5 + 1), Vector2(1, 1)), Pal.RED, true)
		_restore_xform(ci)
		# Target brackets when inside the beam.
		var dist: float = ship.position.distance_to(d.position)
		if dist < ship.beam_radius():
			var r: float = d.radius + 5.0
			var rect := Rect2((d.position - cam) - Vector2(r, r), Vector2(r * 2, r * 2))
			_draw_brackets(ci, rect, Pal.CYAN_DIM)

	# Beam.
	if ship.beaming:
		_draw_beam(ci, cam)

	# Collect pops.
	for f in collect_fx:
		var t: float = float(f["t"]) / 0.5
		var p2: Vector2 = (f["p"] as Vector2) - cam
		var r2: float = (1.0 - t) * 16.0 + 2.0
		var col2: Color = f["color"] as Color
		col2.a = t
		ci.draw_rect(Rect2((p2 - Vector2(r2, 1)).round(), Vector2(2, 2)), col2, true)

	# Exhaust particles.
	for e in exhaust:
		var life: float = float(e["t"]) / float(e["life"])
		var ep: Vector2 = ((e["p"] as Vector2) - cam).round()
		var col: Color = Pal.CYAN.lerp(Pal.ORANGE, 1.0 - life)
		col.a = clampf(life * 1.4, 0.0, 1.0)
		ci.draw_rect(Rect2(ep, Vector2(2, 2)), col, true)

	# Ship under the damage flash.
	var ship_screen: Vector2 = (ship.position - cam).round()
	_sprite_xform(ci, ship_screen, ship.heading)
	var ship_tex: Texture2D = skin.sprites["ship"]
	ci.draw_texture_rect(ship_tex, Rect2(-16, -16, 32, 32), false)
	_restore_xform(ci)

	if ship.beaming:
		# Beam origin dot at the nose.
		ci.draw_rect(Rect2(ship_screen + Vector2(14, -1), Vector2(2, 2)), Pal.CYAN, true)

	_draw_offscreen_markers(ci, cam)
	_draw_scan_sweep(ci, cam)


func _draw_brackets(ci: CanvasItem, rect: Rect2, col: Color) -> void:
	var l := 3.0
	ci.draw_rect(Rect2(rect.position, Vector2(l, 1)), col, true)
	ci.draw_rect(Rect2(rect.position, Vector2(1, l)), col, true)
	ci.draw_rect(Rect2(Vector2(rect.end.x - l, rect.position.y), Vector2(l, 1)), col, true)
	ci.draw_rect(Rect2(Vector2(rect.end.x - 1, rect.position.y), Vector2(1, l)), col, true)
	ci.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 1), Vector2(l, 1)), col, true)
	ci.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - l), Vector2(1, l)), col, true)
	ci.draw_rect(Rect2(Vector2(rect.end.x - l, rect.end.y - 1), Vector2(l, 1)), col, true)
	ci.draw_rect(Rect2(Vector2(rect.end.x - 1, rect.end.y - l), Vector2(1, l)), col, true)


func _draw_station(ci: CanvasItem, cam: Vector2) -> void:
	var tex: Texture2D = skin.sprites["station"]
	var size := Vector2(tex.get_size())
	var p: Vector2 = (station_pos - cam).round()
	if p.x < -120 or p.x > VW + 120:
		return
	if p.y < -60 or p.y > VH + 60:
		return
	_sprite_xform(ci, p)
	ci.draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
	_restore_xform(ci)
	# Docking ring, pulsing so the way home is always legible.
	var pulse: float = 0.5 + 0.5 * sin(_scan_angle * 1.4)
	var ring: Color = Pal.CYAN
	ring.a = 0.25 + pulse * 0.45
	_draw_circle_px(ci, p, dock_radius, ring, 1.0)
	skin.text_c(ci, p.x, p.y + 44, "DOCK", Pal.CYAN if at_station() else Pal.MID)


func _draw_circle_px(ci: CanvasItem, center: Vector2, radius: float, col: Color, step: float = 1.0) -> void:
	var a: float = 0.0
	while a < TAU:
		var q: Vector2 = center + Vector2(cos(a), sin(a)) * radius
		ci.draw_rect(Rect2(q.floor(), Vector2(1, 1)), col, true)
		a += step / maxf(8.0, radius * 0.35)


func _draw_beam(ci: CanvasItem, cam: Vector2) -> void:
	var origin: Vector2 = ship.position - cam
	var target: Variant = null
	var best: float = INF
	for d in debris:
		if d.collected:
			continue
		var dist: float = ship.position.distance_to(d.position)
		if dist < ship.beam_radius() and dist < best:
			best = dist
			target = d
	if target == null:
		# Idle arc showing the field radius.
		var arc_col: Color = Pal.CYAN_DIM
		arc_col.a = 0.35
		_draw_circle_px(ci, origin, ship.beam_radius(), arc_col, 1.4)
		return
	var end: Vector2 = (target.position - cam)
	var dir: Vector2 = (end - origin).normalized()
	var steps: int = int(origin.distance_to(end) / 3.0)
	for i in steps:
		var t: float = float(i) / maxf(1.0, float(steps))
		var p: Vector2 = origin.lerp(end, t)
		var jitter: Vector2 = dir.orthogonal() * sin(elapsed * 40.0 + i * 0.9) * 1.5
		var col: Color = Pal.CYAN
		col.a = 0.75 - absf(t - 0.5) * 0.7
		ci.draw_rect(Rect2((p + jitter).floor(), Vector2(1, 1)), col, true)


func _draw_offscreen_markers(ci: CanvasItem, cam: Vector2) -> void:
	if ship.position.distance_to(station_pos) < 300.0:
		return
	var dir: Vector2 = (station_pos - ship.position).normalized()
	var center := Vector2(VW, VH) * 0.5
	var edge := center + dir * 105.0
	edge.x = clampf(edge.x, 16.0, VW - 16.0)
	edge.y = clampf(edge.y, 26.0, VH - 26.0)
	var col: Color = Pal.CYAN
	col.a = 0.5 + 0.3 * sin(elapsed * 3.0)
	ci.draw_rect(Rect2(edge.floor(), Vector2(3, 3)), col, true)
	skin.text_c(ci, edge.x, edge.y + 5, "STN", col)


func _draw_scan_sweep(ci: CanvasItem, cam: Vector2) -> void:
	# Faint sensor sweep to sell the salvage-ship instrumentation.
	var center: Vector2 = ship.position - cam
	var col := Color(Pal.CYAN.r, Pal.CYAN.g, Pal.CYAN.b, 0.08)
	var r: float = 30.0
	while r < ship.beam_radius() + 24.0:
		_draw_circle_px(ci, center, r, col, 3.0)
		r += 18.0


# ---------------------------------------------------------------- HUD

func _draw_hud(ci: CanvasItem) -> void:
	# Top status strip: two rows, four blocks, generous spacing.
	ci.draw_rect(Rect2(0, 0, VW, 24), Color(0.043, 0.059, 0.098, 0.88), true)
	ci.draw_rect(Rect2(0, 24, VW, 1), Pal.SHADOW, true)

	var fuel_ratio: float = ship.fuel / maxf(1.0, ship.fuel_max)
	var pwr_ratio: float = ship.power / maxf(1.0, ship.power_max)
	var fuel_col: Color = Pal.CYAN
	if fuel_ratio < 0.2:
		fuel_col = Pal.ORANGE
	if fuel_ratio < 0.08:
		fuel_col = Pal.RED
	var pwr_col: Color = Pal.CYAN
	if pwr_ratio < 0.2:
		pwr_col = Pal.ORANGE
	if pwr_ratio < 0.08:
		pwr_col = Pal.RED

	# Block 1: fuel + power.
	skin.text(ci, Vector2(6, 2), "FUEL", Pal.MID)
	skin.bar(ci, Vector2(30, 3), Vector2(54, 5), fuel_ratio, fuel_col)
	skin.text(ci, Vector2(88, 2), "%d" % int(round(ship.fuel)), Pal.PAPER)
	skin.text(ci, Vector2(6, 11), "PWR", Pal.MID)
	skin.bar(ci, Vector2(30, 12), Vector2(54, 5), pwr_ratio, pwr_col)
	skin.text(ci, Vector2(88, 11), "%d" % int(round(ship.power)), Pal.PAPER)

	# Block 2: hold + mass.
	var ratio: float = ship.cargo_ratio()
	var hold_col: Color = Pal.CYAN if ratio < 0.85 else Pal.ORANGE
	skin.text(ci, Vector2(112, 2), "HOLD", Pal.MID)
	skin.bar(ci, Vector2(140, 3), Vector2(44, 5), ratio, hold_col)
	skin.text(ci, Vector2(192, 2), "%d%%" % int(round(ratio * 100.0)), Pal.PAPER)
	skin.text(ci, Vector2(112, 11), "MASS", Pal.MID)
	skin.text(ci, Vector2(140, 11), "%dT" % int(round(ship.total_mass())), Pal.PAPER)
	skin.text(ci, Vector2(166, 11), "AGL%d%%" % int(round(ship.agility() * 100.0)), Pal.CYAN_DIM)

	# Block 3: cargo value + quota.
	skin.text(ci, Vector2(226, 2), "CARGO", Pal.MID)
	skin.text(ci, Vector2(262, 2), "%d CR" % int(round(ship.cargo_value)), Pal.GOLD)
	skin.text(ci, Vector2(226, 11), "QUOTA", Pal.MID)
	var quota: float = state.sector_quota(mission_index)
	var banked: float = state.sector_banked(mission_index)
	var combined: float = minf(quota, banked + ship.cargo_value)
	skin.bar(ci, Vector2(262, 12), Vector2(44, 5), combined / maxf(1.0, quota), Pal.GREEN)
	skin.text(ci, Vector2(310, 11), "%d/%d" % [int(combined), int(quota)], Pal.PAPER)

	# Block 4: timer + item count, right aligned.
	skin.text_r(ci, VW - 6, 2, "T+%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], Pal.MID)
	skin.text_r(ci, VW - 6, 11, "%d ITEMS" % ship.collected, Pal.PAPER)

	# Cargo bay fill pips down the right edge.
	var pips: int = 10
	for i in pips:
		var filled: bool = float(i) / float(pips) < ratio
		var pc: Color = (hold_col if filled else Pal.SHADOW.darkened(0.35))
		ci.draw_rect(Rect2(VW - 4, 30 + i * 5, 2, 3), pc, true)

	# Bottom bar: solid, so drifting debris never reads as UI.
	var bar_top: float = VH - BOTTOM_BAND
	ci.draw_rect(Rect2(0, bar_top, VW, BOTTOM_BAND), Color(0.043, 0.059, 0.098, 0.96), true)
	ci.draw_rect(Rect2(0, bar_top, VW, 1), Pal.SHADOW, true)

	# Row 1 of the bar: PA transmission.
	if pa_line != "" and pa_timer > 0.0:
		var pa_alpha: float = clampf(minf(pa_timer, 1.5), 0.0, 1.0)
		var col: Color = Pal.PAPER
		col.a = pa_alpha
		skin.text(ci, Vector2(6, bar_top + 3), "PA", Color(Pal.CYAN.r, Pal.CYAN.g, Pal.CYAN.b, pa_alpha))
		var line: String = pa_line
		var max_chars: int = int((VW - 34) / 6)
		if line.length() > max_chars:
			line = line.substr(0, max_chars)
		skin.text(ci, Vector2(22, bar_top + 3), line, col)
	else:
		skin.text(ci, Vector2(6, bar_top + 3), "PA", Pal.SHADOW)
		skin.text(ci, Vector2(22, bar_top + 3), "NO TRANSMISSIONS PENDING", Pal.SHADOW)

	# Row 2 of the bar: contextual prompt + static hints.
	var hint_row: float = bar_top + 14
	if ship.disabled:
		skin.text(ci, Vector2(6, hint_row), "E   DISTRESS TOW  (-30% FEE)", Pal.RED)
	elif at_station():
		var pulse: float = 0.6 + 0.4 * sin(elapsed * 4.0)
		skin.text(ci, Vector2(6, hint_row), "E   DOCK AT STATION", Color(Pal.CYAN.r, Pal.CYAN.g, Pal.CYAN.b, pulse))
	else:
		skin.text(ci, Vector2(6, hint_row), "HOLD SPACE   TRACTOR BEAM", Pal.MID)
	# Static hints flow after the prompt so they can never collide with it.
	var logs_x: float = 6.0
	if ship.disabled:
		logs_x = 6.0 + skin.font.text_width("E   DISTRESS TOW  (-30% FEE)") + 10.0
	elif at_station():
		logs_x = 6.0 + skin.font.text_width("E   DOCK AT STATION") + 10.0
	else:
		logs_x = 6.0 + skin.font.text_width("HOLD SPACE   TRACTOR BEAM") + 10.0
	skin.text(ci, Vector2(logs_x, hint_row), "L LOGS", Pal.MID)
	skin.text_r(ci, VW - 6, hint_row, "M MUTE    ESC PAUSE", Pal.MID)

	# Toasts float above the bar on their own dark plates.
	var ty: float = bar_top - 14.0
	for i in range(toasts.size() - 1, -1, -1):
		var t: Dictionary = toasts[i]
		var a: float = clampf(float(t["life"]), 0.0, 1.0)
		var col: Color = t["color"] as Color
		col.a = a
		var msg: String = String(t["text"])
		var tw: float = skin.font.text_width(msg) + 10.0
		ci.draw_rect(Rect2(4, ty - 2, tw, 11), Color(0.043, 0.059, 0.098, 0.8 * a), true)
		skin.text(ci, Vector2(9, ty), msg, col)
		ty -= 11.0

	# Mission brief, wrapped and sized to its content.
	if _brief_timer > 0.0:
		var brief: Array = sector.get("brief", []) as Array
		var bw: float = VW - 120.0
		var rows: Array = []
		for line in brief:
			for w in skin.font.wrap(String(line), bw - 18.0, 1):
				rows.append(String(w))
		var bh: float = 26.0 + rows.size() * 11.0 + 16.0
		var bx: float = (VW - bw) * 0.5
		var by: float = (VH - bh) * 0.5 - 6.0
		var box := Rect2(bx, by, bw, bh)
		skin.panel(ci, box, Color(0.043, 0.059, 0.098, 0.94), Pal.CYAN)
		ci.draw_rect(Rect2(box.position, Vector2(box.size.x, 1)), Pal.CYAN, true)
		skin.text_c(ci, box.position.x + box.size.x * 0.5, box.position.y + 6, "MISSION BRIEF", Pal.CYAN)
		ci.draw_rect(Rect2(box.position.x + 9, box.position.y + 16, box.size.x - 18, 1), Pal.SHADOW, true)
		var ly: float = box.position.y + 22
		for row in rows:
			skin.text(ci, Vector2(box.position.x + 9, ly), String(row), Pal.PAPER)
			ly += 11.0
		ci.draw_rect(Rect2(box.position.x + 9, box.end.y - 17, box.size.x - 18, 1), Pal.SHADOW, true)
		skin.text_c(ci, box.position.x + box.size.x * 0.5, box.end.y - 12, "WASD MOVE   SPACE TRACTOR   E DOCK", Pal.MID)

	if ship.disabled:
		var box2 := Rect2(VW * 0.5 - 100, VH * 0.5 - 22, 200, 44)
		skin.panel(ci, box2, Color(0.043, 0.059, 0.098, 0.95), Pal.RED)
		skin.text_c(ci, VW * 0.5, box2.position.y + 6, "SYSTEMS DEPLETED", Pal.RED)
		skin.text_c(ci, VW * 0.5, box2.position.y + 18, "CARGO CAN STILL BE RECOVERED", Pal.PAPER)
		skin.text_c(ci, VW * 0.5, box2.position.y + 30, "PRESS E FOR A REMOTE TOW", Pal.ORANGE)

	if ship.beaming:
		var bcol: Color = Pal.CYAN
		bcol.a = 0.7
		skin.text(ci, Vector2(6, 28), "TRACTOR ENGAGED", bcol)
