extends RefCounted
## VELA, the one spacecraft drawing in the finale. Every Phase 3/4 view of the
## ship goes through this file: the reconstruction workshop, the final-assembly
## preview, the departure station, the launch, the debris ascent, the portal and
## the homecoming. Nothing else draws VELA, so the ship cannot drift into a
## different design from one scene to the next.
##
## The canonical design is the workshop drawing (the "Reference 1" view): a long
## gray segmented hull, a stepped tapered nose, a rear engine block with a wide
## nozzle bell, panel seams, a dorsal emitter mast and cyan accents. The geometry
## lives once, in ship units:
##   u  along the hull, 0 at the nozzle exit plane, LENGTH at the nose tip
##   v  across the hull, negative is the dorsal (mast) side
##
## Orientation is a mapping, not a rotation of the whole picture:
##   maintenance  u -> +x (nose right), v -> +y   (workshop cradle view)
##   every other  u -> -y (nose up),    v -> +x   (parked, flight, landed)
## Flames, landing legs, the boarding ramp and the shield are drawn in screen
## space from that mapping, so a flame always leaves the bottom nozzles and the
## legs always stand under the ship. Scale is a whole number, so pixel edges
## stay crisp and the ship is never stretched.
##
## Drawing helper, pure otherwise: it reads no campaign state and plays no
## audio. Callers pass the fitted module list from the frozen design.

const SFPalette := preload("res://core/star_fall/sf_palette.gd")

const MAINTENANCE := "maintenance"
const PARKED := "parked"
const IGNITION := "ignition"
const ASCENDING := "ascending"
const PORTAL_ENTRY := "portal_entry"
const DESCENDING := "descending"
const LANDED := "landed"
const STATES := [MAINTENANCE, PARKED, IGNITION, ASCENDING, PORTAL_ENTRY, DESCENDING, LANDED]

## Nozzle exit to nose tip, in ship units (pixels at scale 1).
const LENGTH := 97
## Half the hull width.
const HALF_WIDTH := 9
## How far the landing feet reach below the nozzle exit plane.
const LEG_DEPTH := 8
## The access hatch, on the ventral (+v) side, low on the hull.
const HATCH_U0 := 14
const HATCH_U1 := 23

const MODULE_IDS := ["navigation_chip", "power_core", "shield_emitter"]
## Module centres in ship units. The workshop places its sockets from these, so
## an installed part sits in the same place in every view.
const MODULES := {
	"navigation_chip": Vector2(77, -2),
	"power_core": Vector2(44, -1),
	"shield_emitter": Vector2(49, -17),
}


# ---------------------------------------------------------------- state rules

static func is_upright(state: String) -> bool:
	return state != MAINTENANCE


## Engines burn only while the ship is under thrust. Parked, landed and the
## workshop never show a flame, whatever thrust a caller passes.
static func engines_on(state: String) -> bool:
	return state == IGNITION or state == ASCENDING or state == PORTAL_ENTRY or state == DESCENDING


## Landing legs are down on the ground and on approach to the pad.
static func legs_down(state: String) -> bool:
	return state == PARKED or state == IGNITION or state == LANDED or state == DESCENDING


## The origin (nozzle exit centre) that stands an upright ship on `ground`.
static func ground_origin(ground: Vector2, scale: int = 1) -> Vector2:
	return Vector2(round(ground.x), round(ground.y) - float(LEG_DEPTH * scale))


## The screen position of a point in ship units.
static func to_screen(origin: Vector2, scale: int, state: String, u: float, v: float) -> Vector2:
	if is_upright(state):
		return Vector2(origin.x + v * float(scale), origin.y - u * float(scale))
	return Vector2(origin.x + u * float(scale), origin.y + v * float(scale))


## The hull's visual centre on screen.
static func center(origin: Vector2, scale: int, state: String) -> Vector2:
	return to_screen(origin, scale, state, float(LENGTH) * 0.5, 0.0)


static func module_screen(origin: Vector2, scale: int, state: String, id: String) -> Vector2:
	var m: Vector2 = MODULES.get(id, Vector2.ZERO)
	return to_screen(origin, scale, state, m.x, m.y)


## The hatch sill (where Nick steps in or out) on screen.
static func hatch_screen(origin: Vector2, scale: int, state: String) -> Vector2:
	return to_screen(origin, scale, state, float(HATCH_U0), float(HALF_WIDTH))


## The foot of the boarding ramp on the ground, right of an upright ship.
static func ramp_foot(origin: Vector2, scale: int) -> Vector2:
	var sill := hatch_screen(origin, scale, PARKED)
	var drop: float = float((HATCH_U0 + LEG_DEPTH) * scale)
	return Vector2(sill.x + drop, sill.y + drop)


## The shield's half-extents on screen: it wraps the whole silhouette.
static func shield_radii(scale: int, state: String) -> Vector2:
	var along: float = (float(LENGTH) * 0.5 + 11.0) * float(scale)
	var across: float = (float(HALF_WIDTH) + 12.0) * float(scale)
	return Vector2(across, along) if is_upright(state) else Vector2(along, across)


## Projects a screen point onto the shield boundary, along the ray from the
## centre. Contact effects are drawn there, so a hit lands on the bubble.
static func shield_contact(origin: Vector2, scale: int, state: String, from: Vector2) -> Vector2:
	var c := center(origin, scale, state)
	var r := shield_radii(scale, state)
	var d := from - c
	if d.length() < 0.01:
		d = Vector2(0, -1)
	var k: float = 1.0 / sqrt(pow(d.x / r.x, 2.0) + pow(d.y / r.y, 2.0))
	return c + d * k


# ---------------------------------------------------------------- drawing

## Draws the ship. Options:
##   modules    Array of fitted module ids (default: all three)
##   time       seconds, for flicker and blinking lights
##   thrust     0..1.5, used only when engines_on(state)
##   damaged    scorch marks and a duller hull (the workshop before assembly)
##   assembled  the workshop's ready glow at the engine (maintenance only)
##   clip_u     hide every part of the hull beyond this many units (portal)
##   hatch      0..1, the access hatch opening
##   ramp       0..1, the boarding ramp lowering (upright only)
static func draw(ci: CanvasItem, origin: Vector2, scale: int, state: String, opts: Dictionary = {}) -> void:
	var s: int = maxi(1, scale)
	var o := Vector2(round(origin.x), round(origin.y))
	var up: bool = is_upright(state)
	var time: float = float(opts.get("time", 0.0))
	var clip: float = float(opts.get("clip_u", 9999.0))
	var damaged: bool = bool(opts.get("damaged", false))
	var modules: Array = opts.get("modules", MODULE_IDS) as Array
	var thrust: float = float(opts.get("thrust", 1.0))
	var hatch: float = clampf(float(opts.get("hatch", 0.0)), 0.0, 1.0)
	var ramp: float = clampf(float(opts.get("ramp", 0.0)), 0.0, 1.0)
	var k := [ci, o, s, up, clip]

	if up and engines_on(state) and thrust > 0.0:
		_draw_flame(ci, o, s, thrust, time)
	if up:
		_draw_legs(ci, o, s, legs_down(state))

	var hull: Color = SFPalette.STEEL.darkened(0.15) if damaged else SFPalette.STEEL
	var top: Color = SFPalette.STEEL_MID
	var bottom: Color = SFPalette.STEEL_DARK

	# Nozzle bell and engine block.
	_r(k, 1, -8, 3, 16, SFPalette.STEEL_MID.darkened(0.2))
	_r(k, 1, -8, 3, 1, SFPalette.STEEL_MID)
	_r(k, 1, -5, 1, 2, SFPalette.CYAN_DARK)
	_r(k, 1, 3, 1, 2, SFPalette.CYAN_DARK)
	_r(k, 4, -6, 8, 12, SFPalette.STEEL_DARK)
	_r(k, 4, -6, 8, 1, SFPalette.STEEL_MID.darkened(0.1))

	# Main hull: the long segmented body.
	_r(k, 12, -9, 70, 18, hull)
	_r(k, 12, -9, 70, 1, top)
	_r(k, 12, 8, 70, 1, bottom)
	_r(k, 12, 4, 70, 1, hull.darkened(0.08))

	# Stepped nose taper, layered like the workshop drawing.
	for i in 15:
		var u: int = 82 + i
		var half: int = maxi(1, int(round(9.0 * (1.0 - float(i) / 15.0))))
		_r(k, u, -half, 1, half * 2, SFPalette.STEEL_MID)
		var inner: int = maxi(0, half - 3)
		if inner > 0:
			_r(k, u, -inner, 1, inner * 2, SFPalette.STEEL_MID.darkened(0.06))
		_r(k, u, half - 1, 1, 1, SFPalette.STEEL_MID.darkened(0.18))

	# Panel seams: one pixel wide at every scale.
	for i in 5:
		_seam(k, 20 + i * 13, -8, 16, SFPalette.STEEL_DARK)

	# Cockpit glass near the nose: the cyan accent that reads in every view.
	_r(k, 84, -5, 4, 3, SFPalette.CYAN_DARK)
	_r(k, 85, -5, 2, 2, SFPalette.CYAN)

	# The dorsal emitter mast.
	_r(k, 48, -13, 2, 4, SFPalette.STEEL_DARK)

	# The access hatch, ventral side, low on the hull.
	_r(k, HATCH_U0, 6, HATCH_U1 - HATCH_U0, 3, SFPalette.STEEL_MID)
	_seam(k, HATCH_U0, 6, 3, SFPalette.STEEL_DARK)
	_seam(k, HATCH_U1 - 1, 6, 3, SFPalette.STEEL_DARK)
	if hatch > 0.0:
		var open_u: int = int(round(float(HATCH_U1 - HATCH_U0 - 2) * hatch))
		if open_u > 0:
			_r(k, HATCH_U0 + 1, 6, open_u, 3, Color(0.05, 0.08, 0.09))
			_r(k, HATCH_U0 + 1, 6, open_u, 1, Color(0.95, 0.86, 0.60, 0.8))

	if damaged:
		_r(k, 31, 2, 7, 3, SFPalette.RUIN_DARK)
		_r(k, 63, -6, 5, 2, SFPalette.RUIN_DARK)

	for id in modules:
		_draw_module(k, String(id), time)

	if not up and bool(opts.get("assembled", false)):
		var glow: float = 0.4 + 0.3 * sin(time * 4.0)
		_r(k, -3, -4, 4, 8, Color(0.37, 0.90, 0.85, glow))

	if up and ramp > 0.0:
		_draw_ramp(ci, o, s, ramp)


## One installed module, in the same place in every view.
static func _draw_module(k: Array, id: String, time: float) -> void:
	var blink: float = 0.6 + 0.4 * sin(time * 3.0)
	match id:
		"navigation_chip":
			_r(k, 74, -5, 7, 6, SFPalette.STEEL_DARK)
			_r(k, 75, -4, 5, 4, Color("1d3b34"))
			_r(k, 76, -3, 1, 2, SFPalette.GREEN_OK)
			_r(k, 78, -3, 1, 2, Color(SFPalette.CYAN.r, SFPalette.CYAN.g, SFPalette.CYAN.b, blink))
		"power_core":
			_r(k, 41, -4, 7, 6, SFPalette.STEEL_DARK)
			_r(k, 42, -3, 5, 4, SFPalette.CYAN_DARK)
			_r(k, 43, -2, 3, 2, Color(SFPalette.CYAN.r, SFPalette.CYAN.g, SFPalette.CYAN.b, 0.7 + 0.3 * blink))
		"shield_emitter":
			_r(k, 47, -17, 5, 4, SFPalette.STEEL_DARK)
			_r(k, 48, -16, 3, 2, SFPalette.SHIELD_BLUE)
			_r(k, 49, -16, 1, 1, SFPalette.SHIELD_BLUE_LIGHT)


## A rectangle in ship units, mapped to the screen and clipped at `clip_u`.
static func _r(k: Array, u0: float, v0: float, du: float, dv: float, c: Color) -> void:
	var clip: float = float(k[4])
	if u0 >= clip:
		return
	var u1: float = minf(u0 + du, clip)
	if u1 <= u0:
		return
	var ci: CanvasItem = k[0]
	var o: Vector2 = k[1]
	var s: float = float(k[2])
	if bool(k[3]):
		ci.draw_rect(Rect2(o.x + v0 * s, o.y - u1 * s, dv * s, (u1 - u0) * s), c, true)
	else:
		ci.draw_rect(Rect2(o.x + u0 * s, o.y + v0 * s, (u1 - u0) * s, dv * s), c, true)


## A seam across the hull at `u`: exactly one screen pixel thick.
static func _seam(k: Array, u: float, v0: float, dv: float, c: Color) -> void:
	if u >= float(k[4]):
		return
	var ci: CanvasItem = k[0]
	var o: Vector2 = k[1]
	var s: float = float(k[2])
	if bool(k[3]):
		ci.draw_rect(Rect2(o.x + v0 * s, o.y - u * s - 1.0, dv * s, 1), c, true)
	else:
		ci.draw_rect(Rect2(o.x + u * s, o.y + v0 * s, 1, dv * s), c, true)


## Two landing legs standing under an upright hull, or folded against it.
static func _draw_legs(ci: CanvasItem, o: Vector2, s: int, down: bool) -> void:
	var col: Color = SFPalette.STEEL_DARK
	var foot: Color = SFPalette.STEEL_MID
	for side in [-1, 1]:
		var sx: float = float(side)
		if down:
			# A strut from the engine block out to a foot pad on the ground.
			for step in LEG_DEPTH + 6:
				var y: float = o.y - float(6 - step) * float(s)
				var x: float = o.x + sx * (float(HALF_WIDTH - 2) + float(step) * 0.75) * float(s)
				ci.draw_rect(Rect2(round(x) - (float(s) if side < 0 else 0.0), round(y), float(s), float(s)), col, true)
			var fx: float = o.x + sx * (float(HALF_WIDTH - 2) + float(LEG_DEPTH + 5) * 0.75) * float(s)
			ci.draw_rect(Rect2(round(fx) - 3.0 * float(s), o.y + float((LEG_DEPTH - 1) * s), 6.0 * float(s), float(s)), foot, true)
		else:
			# Stowed: a short strut flat against the engine block.
			var x2: float = o.x + sx * float(HALF_WIDTH - 2) * float(s) - (float(s) if side < 0 else 0.0)
			ci.draw_rect(Rect2(round(x2), o.y - 10.0 * float(s), float(s), 8.0 * float(s)), col, true)


## The boarding ramp from the hatch sill down to the ground, at 45 degrees.
static func _draw_ramp(ci: CanvasItem, o: Vector2, s: int, amount: float) -> void:
	var sill := hatch_screen(o, s, PARKED)
	var steps: int = int(round(float(HATCH_U0 + LEG_DEPTH) * amount))
	for i in steps:
		var p := sill + Vector2(float(i * s), float(i * s))
		ci.draw_rect(Rect2(p.x, p.y, 3.0 * float(s), float(s)), SFPalette.STEEL_MID, true)
		ci.draw_rect(Rect2(p.x, p.y + float(s), 3.0 * float(s), float(s)), SFPalette.STEEL_DARK, true)


## The engine flame, below the nozzle bell. Independent of the hull: a parked or
## landed ship never reaches this function.
static func _draw_flame(ci: CanvasItem, o: Vector2, s: int, thrust: float, time: float) -> void:
	var flicker: float = 1.0 + sin(time * 37.0) * 0.10 + sin(time * 61.0) * 0.06
	var layers := [
		[30.0, 7.0, Color(1.0, 0.52, 0.20, 0.70)],
		[22.0, 5.0, Color(1.0, 0.78, 0.32, 0.88)],
		[13.0, 3.0, Color(0.86, 0.98, 1.0, 0.95)],
	]
	for spec in layers:
		var length: float = float(spec[0]) * thrust * flicker * float(s)
		var half: float = float(spec[1]) * float(s)
		var c: Color = spec[2]
		# Stepped taper: full width at the nozzle, narrowing in four bands.
		for band in 4:
			var f0: float = float(band) / 4.0
			var w: float = round(half * (1.0 - f0 * 0.7))
			ci.draw_rect(Rect2(o.x - w, o.y + round(length * f0), w * 2.0, ceilf(length / 4.0)), c, true)
	ci.draw_rect(Rect2(o.x - 3.0 * float(s), o.y, 6.0 * float(s), 2.0 * float(s)), Color(0.92, 0.99, 1.0, 0.95), true)


## The escape shield: a translucent ellipse around the whole silhouette, a
## pixel rim, and a ripple at every contact. `contacts` holds dictionaries with
## `pos` (screen), `age` (0 new .. 1 gone) and `heavy`.
static func draw_shield(ci: CanvasItem, origin: Vector2, scale: int, state: String,
		strength: float, time: float, contacts: Array = []) -> void:
	if strength <= 0.0:
		return
	var c := center(origin, scale, state)
	var r := shield_radii(scale, state)
	var pulse: float = 0.96 + 0.04 * sin(time * 5.0)
	# Body: pixel rows, faint, so the hull stays readable through it.
	var half_h: int = int(round(r.y * pulse))
	for dy in range(-half_h, half_h + 1):
		var f: float = float(dy) / float(half_h)
		var half_w: float = r.x * pulse * sqrt(maxf(0.0, 1.0 - f * f))
		ci.draw_rect(Rect2(round(c.x - half_w), round(c.y) + float(dy), round(half_w * 2.0), 1),
			Color(0.30, 0.70, 0.96, 0.07 * strength), true)
	# Rim.
	var rim: Color = SFPalette.SHIELD_BLUE_LIGHT
	for i in 120:
		var ang: float = float(i) / 120.0 * TAU
		var p := c + Vector2(cos(ang) * r.x, sin(ang) * r.y) * pulse
		var flicker: float = 0.75 + 0.25 * sin(float(i) * 0.5 + time * 4.0)
		ci.draw_rect(Rect2(round(p.x), round(p.y), 1, 1), Color(rim.r, rim.g, rim.b, 0.70 * strength * flicker), true)
	# Contacts: a bright arc along the rim around the hit, widening as it fades,
	# with sparks thrown outward.
	for entry in contacts:
		var hit: Dictionary = entry
		var age: float = clampf(float(hit.get("age", 1.0)), 0.0, 1.0)
		if age >= 1.0:
			continue
		var pos: Vector2 = hit.get("pos", c)
		var heavy: bool = bool(hit.get("heavy", false))
		var d := pos - c
		var base_ang: float = atan2(d.y / r.y, d.x / r.x)
		var spread: float = (0.25 + age * (0.9 if heavy else 0.55))
		var fade: float = 1.0 - age
		for j in 18:
			var a: float = base_ang + (float(j) / 17.0 - 0.5) * spread * 2.0
			var p2 := c + Vector2(cos(a) * r.x, sin(a) * r.y)
			ci.draw_rect(Rect2(round(p2.x) - 1, round(p2.y) - 1, 2, 2), Color(0.88, 0.98, 1.0, fade), true)
		var sparks: int = 8 if heavy else 5
		for j in sparks:
			var a2: float = base_ang + (float(j) / float(maxi(1, sparks - 1)) - 0.5) * 1.4
			var dist: float = 3.0 + age * (16.0 if heavy else 10.0)
			var p3 := pos + Vector2(cos(a2), sin(a2)) * dist
			ci.draw_rect(Rect2(round(p3.x), round(p3.y), 1, 1), Color(1.0, 0.86, 0.55, fade), true)
		ci.draw_rect(Rect2(round(pos.x) - 2, round(pos.y) - 2, 4, 4), Color(1.0, 1.0, 1.0, fade * (0.9 if heavy else 0.6)), true)
