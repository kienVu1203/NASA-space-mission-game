extends Node2D
## One authored, self-contained exploration area. Builds its props from
## data/star_fall/sites.json, keeps the ground plane and background layered
## under a Y-sorted prop layer, and owns camera follow.
##
## The world knows nothing about campaign stages or UI. It reports an
## interaction request through signals and the main controller decides what it
## means.

const SFProp := preload("res://scenes/star_fall/prop.gd")
const SFPlayer := preload("res://scenes/star_fall/player.gd")
const SFPalette := preload("res://core/star_fall/sf_palette.gd")

signal interact_requested(object_id: String, prop)
signal interactable_focus_changed(label: String)

var skin
var site: Dictionary = {}
var theme_name: String = "earth"
var player
var camera: Camera2D
var props: Array = []
var _interactables: Array = []
var _focused = null
var bounds: Rect2 = Rect2(0, 0, 1280, 720)
var walk_speed: float = 58.0
var run_speed: float = 98.0

var _sorted_root: Node2D
var _time: float = 0.0
var _ambient: Array = []
var _rng := RandomNumberGenerator.new()
var _step_var: int = 1


func setup(skin_ref, site_data: Dictionary, theme: String, walk_px: float = 58.0, run_px: float = 98.0) -> void:
	skin = skin_ref
	site = site_data
	theme_name = theme
	walk_speed = walk_px
	run_speed = run_px


func _ready() -> void:
	_rng.seed = 9182 if theme_name == "earth" else 4471
	var b: Dictionary = site.get("bounds", {})
	bounds = Rect2(float(b.get("x", 0)), float(b.get("y", 0)), float(b.get("w", 1280)), float(b.get("h", 720)))

	if theme_name == "earth":
		_build_ambient_earth()
	else:
		_build_ambient_ruin()

	# Props are grouped in a Y-sorted branch so their draw order follows their
	# ground-contact points automatically.
	_sorted_root = Node2D.new()
	_sorted_root.name = "Sorted"
	_sorted_root.y_sort_enabled = true
	add_child(_sorted_root)

	var props_data: Array = site.get("props", []) as Array
	for p in props_data:
		var prop := SFProp.new()
		prop.setup(skin, p as Dictionary)
		_sorted_root.add_child(prop)
		props.append(prop)
		if prop.interactive:
			_interactables.append(prop)

	player = SFPlayer.new()
	player.name = "Nick"
	player.setup(skin, walk_speed, run_speed)
	var start: Dictionary = site.get("player_start", {})
	player.position = Vector2(float(start.get("x", 320)), float(start.get("y", 520)))
	player.stepped.connect(_on_player_stepped)
	_sorted_root.add_child(player)

	camera = Camera2D.new()
	camera.name = "Camera"
	# 1:1 magnification: the authored space (720x400) is slightly larger than
	# the 640x360 viewport, so the camera pans a little without magnifying the
	# art. Every source pixel stays exactly one screen pixel.
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.position.x + bounds.size.x)
	camera.limit_bottom = int(bounds.position.y + bounds.size.y)
	player.add_child(camera)
	camera.make_current()

	_build_boundary()


func _build_boundary() -> void:
	# Four static walls just outside the authored bounds, so movement can never
	# leave the area even if a prop is missing.
	var thickness := 64.0
	var walls := [
		Rect2(bounds.position.x - thickness, bounds.position.y - thickness, bounds.size.x + thickness * 2.0, thickness),
		Rect2(bounds.position.x - thickness, bounds.position.y + bounds.size.y, bounds.size.x + thickness * 2.0, thickness),
		Rect2(bounds.position.x - thickness, bounds.position.y, thickness, bounds.size.y),
		Rect2(bounds.position.x + bounds.size.x, bounds.position.y, thickness, bounds.size.y),
	]
	for r in walls:
		var rect: Rect2 = r
		var body := StaticBody2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.position = rect.position + rect.size * 0.5
		body.add_child(collider)
		add_child(body)


# ---------------------------------------------------------------- ambient life

func _build_ambient_earth() -> void:
	# A few pollen motes and two drifting cloud shadows: restrained parallax
	# with no gameplay effect.
	for i in 26:
		_ambient.append({
			"p": Vector2(_rng.randf_range(0, bounds.size.x), _rng.randf_range(0, bounds.size.y)),
			"speed": Vector2(_rng.randf_range(-5.0, 9.0), _rng.randf_range(-3.0, 2.0)),
			"c": Color(1.0, 0.98, 0.82, _rng.randf_range(0.22, 0.5)),
		})
	# Slow drifting shade patches. Drawn as dithered ovals, never as rectangles.
	for i in 3:
		_ambient.append({
			"cloud": true,
			"p": Vector2(_rng.randf_range(0, bounds.size.x), _rng.randf_range(120, bounds.size.y)),
			"speed": Vector2(_rng.randf_range(2.0, 4.5), 0.0),
			"size": Vector2(_rng.randf_range(120, 190), _rng.randf_range(46, 70)),
		})


func _build_ambient_ruin() -> void:
	for i in 30:
		_ambient.append({
			"p": Vector2(_rng.randf_range(0, bounds.size.x), _rng.randf_range(0, bounds.size.y)),
			"speed": Vector2(_rng.randf_range(-3.0, 4.0), _rng.randf_range(-1.0, 1.0)),
			"c": Color(0.5, 0.6, 0.7, _rng.randf_range(0.12, 0.35)),
		})
	# No cloud shadows here: hard-edged rectangles read as rendering faults on
	# a flat ash plain. The drifting motes alone carry the motion.


# ---------------------------------------------------------------- runtime

func set_input_enabled(value: bool) -> void:
	if player != null:
		player.input_enabled = value
	if not value:
		_clear_focus()


func focus_position() -> Vector2:
	if player == null:
		return Vector2.ZERO
	return player.position


func set_player_position(p: Vector2) -> void:
	if player != null:
		player.position = p
		if camera != null:
			camera.reset_smoothing()


func prop_by_id(object_id: String):
	for p in props:
		if p.prop_id == object_id:
			return p
	return null


## Removes a collected salvage prop from the world and from the focus list.
func remove_prop(object_id: String) -> void:
	var prop = prop_by_id(object_id)
	if prop == null:
		return
	if _focused == prop:
		_clear_focus()
	_interactables.erase(prop)
	props.erase(prop)
	prop.queue_free()


func set_prop_sprite(object_id: String, key: String) -> void:
	var prop = prop_by_id(object_id)
	if prop != null:
		prop.set_sprite(key)


func _process(delta: float) -> void:
	_time += delta
	for a in _ambient:
		var entry: Dictionary = a
		var p: Vector2 = (entry["p"] as Vector2) + (entry["speed"] as Vector2) * delta
		var margin := 80.0
		if p.x < -margin:
			p.x = bounds.size.x + margin
		elif p.x > bounds.size.x + margin:
			p.x = -margin
		if p.y < -margin:
			p.y = bounds.size.y + margin
		elif p.y > bounds.size.y + margin:
			p.y = -margin
		entry["p"] = p

	_update_focus()
	queue_redraw()


func _update_focus() -> void:
	if player == null or not player.input_enabled:
		_clear_focus()
		return
	var best = null
	var best_dist := 34.0
	for p in _interactables:
		var d: float = player.position.distance_to(p.position)
		if d < best_dist:
			best_dist = d
			best = p
	if best != _focused:
		if _focused != null:
			_focused.highlighted = false
		_focused = best
		if _focused != null:
			_focused.highlighted = true
			interactable_focus_changed.emit(String(_focused.label))
		else:
			interactable_focus_changed.emit("")


func _clear_focus() -> void:
	if _focused != null:
		_focused.highlighted = false
		_focused = null
		interactable_focus_changed.emit("")


func focused_prop():
	return _focused


func try_interact() -> void:
	if _focused == null:
		return
	interact_requested.emit(String(_focused.prop_id), _focused)


func release_input() -> void:
	# Called when the window loses focus, so movement cannot stick.
	if player != null:
		player.velocity = Vector2.ZERO
		player.input_enabled = false


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var b := bounds
	# Ground plane. Drawn in world space, under the sorted layer.
	if theme_name == "earth":
		_draw_earth_ground(b)
	else:
		_draw_ruin_ground(b)


## Dithered ellipse used for drifting shade. Rows of pixels with a random
## skip near the rim, so there is no rectangular edge to read as a glitch.
func _draw_shade_patch(center: Vector2, size: Vector2, color: Color) -> void:
	var rx: float = size.x * 0.5
	var ry: float = size.y * 0.5
	var step: int = 3
	var py: float = -ry
	while py <= ry:
		var span: float = sqrt(maxf(0.0, 1.0 - (py * py) / (ry * ry))) * rx
		var px: float = -span
		while px <= span:
			var falloff: float = 1.0 - pow(absf(px) / maxf(1.0, span), 3.0)
			if (int(px) + int(py) * 3) % 5 == 0:
				pass
			else:
				var c := color
				c.a *= falloff
				draw_rect(Rect2(round(center.x + px), round(center.y + py), step, 2), c, true)
			px += float(step)
		py += 2.0


func _draw_earth_ground(b: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 771
	# Grass base. Broad tonal bands plus a soft vertical gradient give the
	# ground depth without a lighting pass.
	draw_rect(b, SFPalette.GRASS, true)
	var strips := 24
	for i in strips:
		var t: float = float(i) / float(strips)
		var c: Color = SFPalette.GRASS_LIGHT.lerp(SFPalette.GRASS, t * 0.85)
		draw_rect(Rect2(b.position.x, b.position.y + b.size.y * t, b.size.x, b.size.y / float(strips) + 1.0), c, true)
	# Dense grass tufts, deterministic. Drawn after the apron is known so the
	# concrete stays clean.
	for k in 1500:
		var gx: float = rng.randf_range(b.position.x, b.position.x + b.size.x)
		var gy: float = rng.randf_range(b.position.y, b.position.y + b.size.y)
		if gx > 148.0 and gx < 575.0 and gy > 116.0 and gy < 336.0:
			continue
		var tuft: Color = SFPalette.GRASS_DARK if rng.randf() < 0.55 else SFPalette.LEAF_LIGHT
		draw_rect(Rect2(floor(gx), floor(gy), 1, 2), tuft, true)
	# Wildflowers in warm and white tones.
	for k in 90:
		var fx: float = rng.randf_range(b.position.x + 4, b.position.x + b.size.x - 4)
		var fy: float = rng.randf_range(b.position.y + 4, b.position.y + b.size.y - 4)
		if fx > 148.0 and fx < 575.0 and fy > 116.0 and fy < 336.0:
			continue
		var flower: Color = SFPalette.WARM if rng.randf() < 0.5 else SFPalette.GOLD
		draw_rect(Rect2(floor(fx), floor(fy), 2, 2), flower, true)

	# Distant treeline behind the play area: a darker green band that reads as
	# depth without any playable collision.
	draw_rect(Rect2(b.position.x, b.position.y, b.size.x, 26), SFPalette.GRASS_DARK.darkened(0.12), true)
	var tx := b.position.x
	var trng := RandomNumberGenerator.new()
	trng.seed = 5501
	while tx < b.position.x + b.size.x:
		var th: float = trng.randf_range(10.0, 22.0)
		var tw: float = trng.randf_range(14.0, 26.0)
		draw_rect(Rect2(tx, b.position.y + 26 - th, tw, th), SFPalette.LEAF_DARK.darkened(0.15), true)
		tx += tw * 0.7
	draw_rect(Rect2(b.position.x, b.position.y + 26, b.size.x, 3), SFPalette.GRASS_DARK, true)

	# Concrete apron in front of the workshop: the working courtyard.
	var apron := Rect2(b.position.x + 150.0, b.position.y + 118.0, 420.0, 214.0)
	draw_rect(apron, SFPalette.CONCRETE, true)
	draw_rect(Rect2(apron.position, Vector2(apron.size.x, 4)), SFPalette.WARM, true)
	draw_rect(Rect2(apron.position.x, apron.position.y, 4, apron.size.y), SFPalette.CONCRETE_MID, true)
	draw_rect(Rect2(apron.end.x - 4, apron.position.y, 4, apron.size.y), SFPalette.CONCRETE_MID, true)
	draw_rect(Rect2(apron.position.x, apron.end.y - 4, apron.size.x, 4), SFPalette.CONCRETE_DARK, true)
	# Expansion joints.
	var jx := apron.position.x + 90.0
	while jx < apron.end.x:
		draw_rect(Rect2(floor(jx), apron.position.y + 6, 1, apron.size.y - 12), SFPalette.CONCRETE_MID, true)
		jx += 90.0
	var jy := apron.position.y + 90.0
	while jy < apron.end.y:
		draw_rect(Rect2(apron.position.x + 6, floor(jy), apron.size.x - 12, 1), SFPalette.CONCRETE_MID, true)
		jy += 90.0

	# Walkway from the site edge to the apron, flush with the apron's bottom band.
	var walk_top: float = apron.position.y + apron.size.y - 52.0
	var path := Rect2(b.position.x, walk_top, apron.position.x - b.position.x, 42)
	draw_rect(path, SFPalette.CONCRETE_MID, true)
	draw_rect(Rect2(path.position, Vector2(path.size.x, 2)), SFPalette.CONCRETE, true)
	draw_rect(Rect2(path.position.x, path.end.y - 2, path.size.x, 2), SFPalette.CONCRETE_DARK, true)
	var joint_x: float = path.position.x + 26.0
	while joint_x < path.end.x:
		draw_rect(Rect2(floor(joint_x), path.position.y + 4, 1, path.size.y - 8), SFPalette.CONCRETE_DARK, true)
		joint_x += 26.0

	# Launch pad ring at the far right of the apron.
	var pad_c := Vector2(b.position.x + 516, b.position.y + 258)
	for k in 90:
		var ang: float = float(k) / 90.0 * TAU
		draw_rect(Rect2((pad_c + Vector2(cos(ang), sin(ang) * 0.55) * 82.0).floor(), Vector2(2, 2)), SFPalette.WARM, true)
	draw_rect(Rect2(pad_c.x - 70, pad_c.y - 36, 140, 72), SFPalette.CONCRETE_DARK, true)
	draw_rect(Rect2(pad_c.x - 62, pad_c.y - 30, 124, 60), SFPalette.CONCRETE_MID, true)

	# Ambient motes and cloud shadows, behind everything sorted.
	for a in _ambient:
		var entry: Dictionary = a
		if bool(entry.get("cloud", false)):
			var cp: Vector2 = entry["p"] as Vector2
			var cs: Vector2 = entry["size"] as Vector2
			_draw_shade_patch(cp, cs, Color(0.13, 0.26, 0.16, 0.16))
		else:
			draw_rect(Rect2((entry["p"] as Vector2).floor(), Vector2(1, 1)), entry["c"] as Color, true)


## Soft round dither blob. This is the workhorse of the ruined ground: it has
## no hard edge, so scattered ash and scorch read as material, not geometry.
func _soft_blob(center: Vector2, radius: float, color: Color, density: float, rng: RandomNumberGenerator) -> void:
	var r: int = int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d: float = sqrt(float(dx * dx + dy * dy)) / maxf(1.0, radius)
			if d > 1.0:
				continue
			# Density falls off towards the rim, so the edge dissolves.
			if rng.randf() > density * (1.0 - d * d):
				continue
			var c := color
			c.a *= 1.0 - d * 0.55
			draw_rect(Rect2(center.x + float(dx), center.y + float(dy), 1, 1), c, true)


func _draw_ruin_ground(b: Rect2) -> void:
	# Value structure, from the ground up:
	#   ash plain (lightest) -> soot drifts (mid) -> scorch and rift (darkest)
	# That ordering is what makes the props and the wreck readable at all.
	var rng := RandomNumberGenerator.new()
	rng.seed = 331
	var brng := RandomNumberGenerator.new()
	brng.seed = 8123

	# Ash plain, slightly graded so the far edge recedes.
	var strips := 22
	for i in strips:
		var t: float = float(i) / float(strips)
		var c: Color = SFPalette.ASH_PLAIN_LIGHT.lerp(SFPalette.ASH_PLAIN, t * 0.7)
		draw_rect(Rect2(b.position.x, b.position.y + b.size.y * t, b.size.x, b.size.y / float(strips) + 1.0), c, true)

	# Grit and pebbles, denser near the camera.
	for g in 1600:
		var gx: float = rng.randf_range(b.position.x, b.position.x + b.size.x)
		var gy: float = rng.randf_range(b.position.y, b.position.y + b.size.y)
		var depth: float = (gy - b.position.y) / b.size.y
		if rng.randf() > 0.18 + depth * 0.82:
			continue
		var tone: Color = SFPalette.ASH.darkened(0.15) if rng.randf() < 0.6 else SFPalette.ASH_LIGHT
		tone.a = 0.35 + depth * 0.45
		draw_rect(Rect2(floor(gx), floor(gy), 2, 1), tone, true)

	# Soot drifts: dark soft patches, so the plain is not a flat slab.
	for a in 22:
		var ap := Vector2(rng.randf_range(b.position.x, b.position.x + b.size.x), rng.randf_range(b.position.y + 40.0, b.position.y + b.size.y))
		var ar: float = rng.randf_range(30.0, 80.0)
		var soot: Color = SFPalette.RUIN_DARK
		soot.a = 0.30
		_soft_blob(ap, ar, soot, 0.5, rng)

	# Rubble fields: clusters of broken concrete, lighter than the plain so
	# they read as debris rather than as holes.
	for cluster in 16:
		var cp := Vector2(rng.randf_range(b.position.x + 20.0, b.position.x + b.size.x - 20.0),
			rng.randf_range(b.position.y + 56.0, b.position.y + b.size.y - 16.0))
		var count: int = rng.randi_range(4, 12)
		var spread: float = rng.randf_range(10.0, 30.0)
		for piece in count:
			var pp := cp + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread * 0.4, spread * 0.4))
			var pw: float = rng.randf_range(2.0, 7.0)
			var ph: float = rng.randf_range(1.0, 3.0)
			var pc: Color = SFPalette.ASH if rng.randf() < 0.6 else SFPalette.ASH_LIGHT
			draw_rect(Rect2(round(pp.x), round(pp.y), round(pw), round(ph)), pc, true)
			# Contact shadow under each piece, so it sits on the ground.
			draw_rect(Rect2(round(pp.x), round(pp.y) + round(ph), round(pw), 1), SFPalette.RUIN_DARK, true)

	# Contamination: a broad soft stain with a bright core and a short runnel.
	var pool_c := Vector2(b.position.x + 438, b.position.y + 208)
	for ring in 3:
		var rad: float = 34.0 - float(ring) * 9.0
		var tint: Color = SFPalette.VIOLET if ring == 0 else SFPalette.VIOLET.darkened(0.35)
		tint.a = 0.22
		_soft_blob(pool_c + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-3.0, 3.0)), rad, tint, 0.7, rng)
	for bead in 30:
		var bp := pool_c + Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-9.0, 9.0))
		draw_rect(Rect2(round(bp.x), round(bp.y), 1, 1), SFPalette.VIOLET_LIGHT, true)
	for st in 26:
		var wob := sin(float(st) * 0.5) * 2.5
		var rp := pool_c + Vector2(wob, 10.0 + float(st) * 2.2)
		if rng.randf() < 0.75:
			draw_rect(Rect2(round(rp.x), round(rp.y), 2, 1), SFPalette.VIOLET, true)

	# Crash gouge: dark turned earth with a hot end, cut across the plain.
	var scar_path := PackedVector2Array([
		Vector2(b.position.x + 30, b.position.y + 292),
		Vector2(b.position.x + 104, b.position.y + 268),
		Vector2(b.position.x + 162, b.position.y + 246),
		Vector2(b.position.x + 232, b.position.y + 232),
		Vector2(b.position.x + 288, b.position.y + 206),
		Vector2(b.position.x + 344, b.position.y + 196),
		Vector2(b.position.x + 378, b.position.y + 180),
	])
	for ni in range(scar_path.size() - 1):
		var pa: Vector2 = scar_path[ni]
		var pb: Vector2 = scar_path[ni + 1]
		var steps := 34
		for st2 in steps:
			var local: float = float(st2) / float(steps)
			var t2: float = (float(ni) + local) / float(scar_path.size() - 1)
			var base: Vector2 = pa.lerp(pb, local)
			var half: float = 3.0 + t2 * 9.0
			# Earth banked up along both edges, dithered so it has no hard rim.
			for band in 7:
				var offset: float = (float(band) / 6.0) * (half + 5.0)
				for side in [-1.0, 1.0]:
					if rng.randf() < 0.42:
						continue
					var bank: Color = SFPalette.ASH_LIGHT if side < 0.0 else SFPalette.ASH.darkened(0.2)
					bank.a = 0.42
					var bw: float = rng.randf_range(2.0, 5.0)
					draw_rect(Rect2(round(base.x) - bw * 0.5, round(base.y + side * offset), round(bw), 1), bank, true)
			# The trench floor: solid, dark, widening toward the wreck.
			draw_rect(Rect2(round(base.x) - round(half), round(base.y), maxf(2.0, round(half * 2.0)), 2), SFPalette.SOOT, true)
			# A hot line deep in the floor near the impact.
			if t2 > 0.7 and st2 % 3 == 0:
				draw_rect(Rect2(round(base.x), round(base.y) + 1, 1, 1), SFPalette.RUST, true)
			# Embers scattered just outside the banks.
			if st2 % 2 == 0:
				var ep := base + Vector2(rng.randf_range(-half - 5.0, half + 5.0), rng.randf_range(-6.0, 6.0))
				draw_rect(Rect2(round(ep.x), round(ep.y), 1, 1), SFPalette.RUST_LIGHT if rng.randf() < 0.5 else SFPalette.RUST, true)

	# Distant ruined skyline. A very dark band behind it separates the towers
	# from the ash plain, so the silhouettes read as depth, not as a stripe.
	draw_rect(Rect2(b.position.x, b.position.y, b.size.x, 44), SFPalette.RUIN_BG, true)
	var haze := 0
	while haze < 4:
		var hc: Color = SFPalette.RUIN_BG.lerp(SFPalette.RUIN_DARK, float(haze) / 4.0)
		draw_rect(Rect2(b.position.x, b.position.y + 44 + haze * 2, b.size.x, 2), hc, true)
		haze += 1
	var bx := b.position.x
	while bx < b.position.x + b.size.x:
		var tower_h: float = brng.randf_range(12.0, 32.0)
		var tower_w: float = brng.randf_range(16.0, 34.0)
		# Towers sit a shade above the void so their shape is legible.
		draw_rect(Rect2(bx, b.position.y + 44 - tower_h, tower_w, tower_h), SFPalette.RUIN, true)
		draw_rect(Rect2(bx, b.position.y + 44 - tower_h, tower_w, 1), SFPalette.ASH.darkened(0.4), true)
		# Windows: a few lit, most dead.
		for wy in range(6, int(tower_h) - 4, 7):
			if brng.randf() < 0.22:
				draw_rect(Rect2(bx + tower_w * 0.35, b.position.y + 44 - tower_h + wy, 2, 2), SFPalette.CYAN_DARK, true)
			elif brng.randf() < 0.3:
				draw_rect(Rect2(bx + tower_w * 0.65, b.position.y + 44 - tower_h + wy, 2, 2), SFPalette.RUIN_BG, true)
		bx += tower_w * 0.8

	for a2 in _ambient:
		var entry: Dictionary = a2
		if bool(entry.get("cloud", false)):
			var cp2: Vector2 = entry["p"] as Vector2
			var cs: Vector2 = entry["size"] as Vector2
			_draw_shade_patch(cp2, cs, Color(0.02, 0.05, 0.05, 0.22))
		else:
			draw_rect(Rect2((entry["p"] as Vector2).floor(), Vector2(1, 1)), entry["c"] as Color, true)


func _on_player_stepped() -> void:
	if skin != null and skin.audio != null:
		_step_var = 2 if _step_var == 1 else 1
		if theme_name == "earth":
			if skin.audio.has_method("sfx_step_earth"):
				skin.audio.sfx_step_earth(_step_var)
			else:
				skin.audio.sfx_step()
		else:
			if skin.audio.has_method("sfx_step_ruin"):
				skin.audio.sfx_step_ruin(_step_var)
			else:
				skin.audio.sfx_step()
