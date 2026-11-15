extends RefCounted
const SFPalette := preload("res://core/star_fall/sf_palette.gd")
## Builds every sprite in the game as pixel data at startup. Nothing is loaded
## from disk. Nick is a placeholder human astronaut, drawn honestly as such.

static func build_all() -> Dictionary:
	var out: Dictionary = {}
	for dir in ["down", "up", "left", "right"]:
		out["nick_" + dir] = _tex(_astronaut(dir))
	out["bill_off"] = _tex(_bill(false))
	out["bill_on"] = _tex(_bill(true))
	out["tree"] = _tex(_tree())
	out["bush"] = _tex(_bush())
	out["terminal"] = _tex(_terminal())
	out["console"] = _tex(_console())
	out["crates"] = _tex(_crates())
	out["lamp"] = _tex(_lamp())
	out["dish"] = _tex(_dish())
	out["rocket_frame"] = _tex(_rocket_frame())
	out["wreck"] = _tex(_wreck())
	out["salvage"] = _tex(_salvage())
	out["junction"] = _tex(_junction())
	out["rubble"] = _tex(_rubble())
	out["earth"] = _tex(_earth())
	out["pad_beacon"] = _tex(_pad_beacon())
	# Phase 2 exploration props.
	out["waste_pile"] = _tex(_waste_pile())
	out["board_stack"] = _tex(_board_stack())
	out["street_lamp"] = _tex(_street_lamp())
	out["control_door"] = _tex(_control_door(false))
	out["control_door_open"] = _tex(_control_door(true))
	out["facility_gate"] = _tex(_facility_gate(false))
	out["facility_gate_open"] = _tex(_facility_gate(true))
	out["shrine"] = _tex(_shrine())
	out["checkpoint"] = _tex(_checkpoint())
	out["harbor_crate"] = _tex(_harbor_crate())
	out["drum"] = _tex(_drum())
	out["pump"] = _tex(_pump())
	out["sample_point"] = _tex(_sample_point())
	out["record_terminal"] = _tex(_record_terminal())
	out["bill_phase_two"] = _tex(_bill(true))
	# Phase 3 exploration props.
	out["dead_tree"] = _tex(_dead_tree())
	out["dawn_tower"] = _tex(_dawn_tower())
	# Phase 3 recovered components: the world drop and the workshop icons.
	out["shield_emitter"] = _tex(_shield_emitter())
	out["navigation_chip"] = _tex(_navigation_chip())
	out["power_core"] = _tex(_power_core())
	# Phase 4 flight art: VELA seen from the side, nose right, and the one
	# human close-up in the game.
	out["vela_ship"] = _tex(_vela_ship())
	out["vela_ship_gear"] = _tex(_vela_ship_gear())
	out["nick_portrait"] = _tex(_nick_portrait())
	out["nick_standing"] = _tex(_nick_standing())
	return out


## VELA from the side, nose pointing right, exhaust end at the left. Built as a
## per-column profile so the silhouette reads as one continuous airframe rather
## than a stack of boxes: armoured hull, swept stabilisers, a tinted canopy and
## three nozzles. Origin is the centre of the sprite, so the flight code can
## place it at a lane height and later spin or scale it about that point.
static func _vela_ship() -> Image:
	var img := _img(72, 34)
	var hull: Color = SFPalette.STEEL
	var hull_mid: Color = SFPalette.STEEL_MID
	var hull_dark: Color = SFPalette.STEEL_DARK
	var plate: Color = Color("c3ccd2")
	var plate_dark: Color = Color("66727a")
	var trim: Color = SFPalette.EARTH_ORANGE
	var canopy: Color = Color("43b6e0")
	var canopy_hi: Color = Color("a9ecff")
	var cy := 17

	# --- swept stabiliser wings, drawn behind the hull. The leading edge is the
	# longest sweep: each column adds one row outward until the tip.
	var wing := 0
	while wing < 20:
		var wx: int = 16 + wing
		var reach: int = int(round(float(wing) * 0.42)) + 2
		if wing > 15:
			reach = maxi(0, 8 - (wing - 15) * 2)
		_rect(img, wx, cy - 4 - reach, 1, reach, hull_dark)
		_rect(img, wx, cy + 5, 1, reach, hull_dark)
		_px(img, wx, cy - 4 - reach, plate_dark)
		_px(img, wx, cy + 4 + reach, plate_dark)
		wing += 1

	# --- main hull: a smooth taper from the engine block to the nose tip.
	var x := 8
	while x < 71:
		var half := 0
		if x < 14:
			half = 8
		elif x < 44:
			half = 9
		elif x < 54:
			half = 9 - int(round(float(x - 44) * 0.35))
		elif x < 64:
			half = 5 - int(round(float(x - 54) * 0.34))
		else:
			half = maxi(1, 2 - int(round(float(x - 64) * 0.25)))
		_rect(img, x, cy - half, 1, half * 2 + 1, hull)
		# Light from above: the top third is the highlight, the bottom a shadow.
		var shade: int = maxi(1, int(float(half) / 3.0))
		_rect(img, x, cy - half, 1, shade, plate)
		_rect(img, x, cy + half - shade + 1, 1, shade, hull_dark)
		x += 1

	# --- armour plating: seams across the hull, a belt line, and rivets.
	var seam := 18
	while seam < 62:
		_rect(img, seam, cy - 6, 1, 12, hull_mid)
		seam += 9
	_rect(img, 10, cy + 2, 50, 1, plate_dark)
	var rivet := 14
	while rivet < 46:
		_px(img, rivet, cy - 6, plate)
		_px(img, rivet, cy + 7, hull_mid)
		rivet += 8

	# --- nose cone: a warm trim stripe and a sensor dot at the tip.
	_rect(img, 55, cy - 3, 12, 1, trim)
	_rect(img, 55, cy + 2, 9, 1, trim)
	_px(img, 69, cy, plate)
	_rect(img, 68, cy - 1, 2, 3, hull_dark)

	# --- cockpit canopy: tinted glass in an armoured frame.
	_rect(img, 38, cy - 6, 15, 8, hull_dark)
	_rect(img, 39, cy - 5, 13, 6, canopy)
	_rect(img, 40, cy - 4, 8, 2, canopy_hi)
	_rect(img, 49, cy - 1, 3, 2, canopy)
	_px(img, 47, cy - 5, Color("d8f7ff"))

	# --- engine block and three nozzles at the exhaust end.
	_rect(img, 4, cy - 8, 6, 17, hull_mid)
	_rect(img, 4, cy - 8, 6, 1, plate)
	_rect(img, 4, cy + 8, 6, 1, hull_dark)
	for nozzle in 3:
		var ny: int = cy - 6 + nozzle * 6
		_rect(img, 0, ny, 5, 4, hull_dark)
		_rect(img, 0, ny, 5, 1, plate_dark)
		_rect(img, 1, ny + 1, 3, 2, SFPalette.CYAN_DARK)
	# The shield emitter's own lamp, aft of the canopy.
	_rect(img, 30, cy - 7, 4, 2, SFPalette.CYAN_DARK)
	_px(img, 31, cy - 7, SFPalette.CYAN)
	return img


## The same airframe on the pad, with three landing struts down. Kept as its own
## sprite so the touchdown drawing cannot show struts in flight.
static func _vela_ship_gear() -> Image:
	var img := _vela_ship()
	var cy := 17
	# Three legs: one forward, two aft, each with a foot pad.
	_rect(img, 50, cy + 6, 2, 5, SFPalette.STEEL_DARK)
	_rect(img, 48, cy + 11, 6, 2, SFPalette.STEEL_MID)
	_rect(img, 22, cy + 7, 2, 5, SFPalette.STEEL_DARK)
	_rect(img, 19, cy + 12, 7, 2, SFPalette.STEEL_MID)
	_rect(img, 33, cy + 8, 2, 4, SFPalette.STEEL_DARK)
	_rect(img, 31, cy + 12, 6, 2, SFPalette.STEEL_MID)
	return img


## Nick, close up, helmet open. This is the only detailed human face in the
## game: the ending rests on it, so it is drawn rather than left to a 16x20
## walking sprite. He is mid-laugh: eyes creased shut, mouth open, one gloved
## hand raised. The helmet sits behind his head as an open ring, so the face is
## never boxed in by a rectangular shell.
##
## Proportions, on the 80x80 canvas: head oval centred (40, 41) at 17x21; hair
## crown to y 25; brows 33; creased eyes 38; nose 42-46; smile 49-55; chin 62.
## The canvas is deliberately taller than the face so the shoulder line can be
## cropped by the screen rather than by the sprite.
static func _nick_portrait() -> Image:
	var img := _img(80, 80)
	var suit: Color = SFPalette.WARM
	var suit_sh: Color = SFPalette.WARM_DARK
	var suit_hi: Color = Color("fbf6e4")
	var collar: Color = SFPalette.STEEL_MID
	var skin: Color = SFPalette.SKIN
	var skin_hi: Color = SFPalette.SKIN_LIGHT
	var skin_sh: Color = SFPalette.SKIN_DARK
	var hair: Color = SFPalette.HAIR
	var hair_hi: Color = SFPalette.HAIR_LIGHT
	var eye: Color = Color("2b3a44")
	var mouth: Color = Color("7d3f3b")
	var teeth: Color = Color("f7f2e4")
	var blush: Color = Color("df8a72")

	# --- the open helmet: a thick annulus behind the head.
	_disc(img, 40, 36, 33, suit_sh)
	_disc(img, 40, 34, 32, suit)
	# Hollow the front so the face reads against skin, not against white plastic.
	for y in range(0, 80):
		for x in range(0, 80):
			var dx: float = float(x) - 40.0
			var dy: float = float(y) - 34.0
			if sqrt(dx * dx + dy * dy) < 27.0 and y < 58:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	_arc(img, 40, 34, 31, 196.0, 344.0, suit_hi)

	# --- shoulders and suit.
	_rect(img, 5, 64, 70, 16, suit)
	_rect(img, 5, 64, 70, 2, suit_hi)
	_rect(img, 5, 76, 70, 4, suit_sh)
	_rect(img, 25, 59, 30, 6, collar)
	_rect(img, 25, 59, 30, 1, SFPalette.STEEL)
	_rect(img, 14, 69, 8, 4, SFPalette.EARTH_ORANGE)
	_rect(img, 58, 69, 8, 4, SFPalette.BLUE_ACCENT)

	# --- neck, drawn before the chin so the jawline overlaps it.
	_rect(img, 35, 53, 10, 10, skin_sh)
	_rect(img, 36, 53, 8, 2, skin)

	# --- head: an oval with light from the upper left.
	for y in range(18, 65):
		for x in range(20, 61):
			var nx: float = (float(x) - 40.0) / 17.0
			var ny: float = (float(y) - 41.0) / 21.0
			var d2: float = nx * nx + ny * ny
			if d2 > 1.0:
				continue
			var c: Color = skin
			if nx + ny < -0.55:
				c = skin_hi
			elif nx + ny > 0.70:
				c = skin_sh
			_px(img, x, y, c)
	# Ears.
	_disc(img, 22, 42, 3, skin)
	_disc(img, 58, 42, 3, skin)
	_px(img, 21, 43, skin_sh)
	_px(img, 59, 43, skin_sh)

	# --- hair: a cap that stops above the brows, with a side-swept fringe.
	# It is painted row by row inside the skull, and only above `hairline` on the
	# forehead, so no hair can ever fall across the eyes. The sides are allowed
	# lower, which is what gives the temples their shape.
	for y in range(12, 46):
		for x in range(20, 61):
			if not _inside_face(x, y):
				continue
			# Fraction across the head, -1 at the left edge and +1 at the right.
			var nx: float = (float(x) - 40.0) / 17.0
			# The hairline is a smooth curve across the forehead, lowest at the
			# temples, so the fringe has no straight edge to read as a gap.
			var hairline: float = 29.0 + absf(nx) * 9.0
			if nx > 0.25:
				# The fringe sweeps a little lower on the right.
				hairline += 3.0
			if float(y) < hairline:
				_px(img, x, y, hair)
	# Crown highlights, painted only inside the hair so nothing floats free.
	for i in 13:
		var hx: int = 30 + i
		if _inside_face(hx, 21):
			_px(img, hx, 21, hair_hi)
			_px(img, hx, 22, hair_hi)
	if _inside_face(45, 19):
		_px(img, 45, 19, hair_hi)
	if _inside_face(34, 18):
		_px(img, 34, 18, hair_hi)
	# A single strand falling over each temple.
	if _inside_face(25, 40):
		_px(img, 25, 40, hair)
	if _inside_face(25, 41):
		_px(img, 25, 41, hair)
	if _inside_face(55, 39):
		_px(img, 55, 39, hair)

	# --- brows: short, raised, well above the eyes.
	_arc(img, 32, 34, 6, 210.0, 330.0, hair)
	_arc(img, 48, 34, 6, 210.0, 330.0, hair)

	# --- eyes creased shut with a smile: an upward arc of lash, then a
	# highlight below it so the crease reads as happy rather than as a squint.
	_arc(img, 32, 40, 5, 205.0, 335.0, eye)
	_arc(img, 48, 40, 5, 205.0, 335.0, eye)
	_px(img, 27, 39, eye)
	_px(img, 43, 39, eye)
	_px(img, 29, 41, skin_hi)
	_px(img, 45, 41, skin_hi)
	# Laugh lines at the outer corners.
	_px(img, 24, 41, skin_sh)
	_px(img, 23, 42, skin_sh)
	_px(img, 56, 41, skin_sh)
	_px(img, 57, 42, skin_sh)

	# --- nose: a short bridge and a soft tip, one tone darker underneath.
	_rect(img, 40, 41, 2, 6, skin_sh)
	_rect(img, 39, 45, 4, 2, skin)
	_rect(img, 39, 46, 4, 1, skin_sh)
	_px(img, 40, 40, skin_hi)

	# --- cheeks, warm from the sun he has not seen in months.
	_ellipse_fill(img, 27, 45, 4, 2, blush)
	_ellipse_fill(img, 53, 45, 4, 2, blush)

	# --- an open, delighted laugh: a dark mouth with a band of teeth and a
	# tongue, framed by the upper lip.
	_ellipse_fill(img, 40, 52, 7, 4, mouth)
	_ellipse_fill(img, 40, 50, 6, 2, teeth)
	_ellipse_fill(img, 40, 55, 4, 2, Color("b05f5a"))
	_rect(img, 33, 49, 14, 1, skin_sh)
	_rect(img, 34, 56, 12, 1, skin_sh)
	_px(img, 32, 50, skin_sh)
	_px(img, 47, 50, skin_sh)

	# --- the raised glove, fingers spread, on the right.
	_rect(img, 62, 54, 11, 11, suit)
	_rect(img, 62, 54, 11, 2, suit_hi)
	_rect(img, 62, 63, 11, 2, suit_sh)
	_rect(img, 61, 48, 3, 7, suit)
	_rect(img, 65, 46, 3, 9, suit)
	_rect(img, 69, 48, 3, 8, suit)
	_rect(img, 73, 51, 3, 6, suit)
	_rect(img, 61, 48, 1, 7, suit_hi)
	_rect(img, 65, 46, 1, 9, suit_hi)
	_rect(img, 69, 48, 1, 8, suit_hi)
	_rect(img, 59, 60, 4, 4, suit_sh)
	_rect(img, 62, 62, 11, 1, SFPalette.STEEL_DARK)
	return img


## True when (x, y) falls inside the head oval. Shared by the hair cut-outs so
## the hair can never paint outside the face.
static func _inside_face(x: int, y: int) -> bool:
	var nx: float = (float(x) - 40.0) / 17.0
	var ny: float = (float(y) - 41.0) / 21.0
	return nx * nx + ny * ny <= 1.0


## Fills a flat-topped disc. Used for the helmet, the head and the ears.
static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx: int = x - cx
			var dy: int = y - cy
			if dx * dx + dy * dy <= r * r:
				_px(img, x, y, c)


## Fills an oval with independent x and y radii.
static func _ellipse_fill(img: Image, cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx: float = float(x - cx) / float(maxi(1, rx))
			var dy: float = float(y - cy) / float(maxi(1, ry))
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)


## A one-pixel arc between two angles, in degrees. Angles run clockwise from
## the positive x axis, matching Image coordinates.
static func _arc(img: Image, cx: int, cy: int, r: int, start_deg: float, end_deg: float, c: Color) -> void:
	var steps: int = maxi(8, r * 6)
	for i in steps + 1:
		var a: float = deg_to_rad(lerpf(start_deg, end_deg, float(i) / float(steps)))
		_px(img, cx + int(round(cos(a) * float(r))), cy + int(round(sin(a) * float(r))), c)


## Nick standing, seen from the front, small: stepping out of the hatch onto the
## pad. Reuses the walking sprite's read at a larger size with a wave arm.
static func _nick_standing() -> Image:
	var img := _img(20, 26)
	var suit: Color = SFPalette.WARM
	var suit_sh: Color = SFPalette.WARM_DARK
	var visor: Color = SFPalette.BLUE_ACCENT
	var visor_hi: Color = Color("6fc6f0")
	_rect(img, 6, 22, 3, 4, SFPalette.STEEL_DARK)
	_rect(img, 11, 22, 3, 4, SFPalette.STEEL_DARK)
	_rect(img, 5, 11, 10, 12, suit)
	_rect(img, 5, 20, 10, 2, suit_sh)
	_rect(img, 5, 11, 1, 10, suit_sh)
	_rect(img, 14, 11, 1, 10, suit_sh)
	_px(img, 8, 14, SFPalette.EARTH_ORANGE)
	_px(img, 9, 14, SFPalette.EARTH_ORANGE)
	_rect(img, 3, 12, 2, 7, suit)
	_rect(img, 2, 6, 2, 7, suit)
	_rect(img, 15, 12, 2, 6, suit)
	_rect(img, 5, 2, 10, 9, suit)
	_rect(img, 5, 2, 10, 1, Color("fbf6e4"))
	_rect(img, 4, 4, 1, 6, suit_sh)
	_rect(img, 15, 4, 1, 6, suit_sh)
	_rect(img, 6, 4, 8, 5, visor)
	_rect(img, 6, 4, 4, 2, visor_hi)
	_px(img, 12, 4, visor_hi)
	return img


## The shield emitter, as fallen from the tower crown: the same dark housing
## and cyan lens, with two small fins. Origin is the ground-contact point.
static func _shield_emitter() -> Image:
	var img := _img(18, 16)
	_rect(img, 3, 6, 12, 8, SFPalette.STEEL_DARK)
	_rect(img, 3, 6, 12, 1, SFPalette.STEEL_MID)
	_rect(img, 5, 8, 8, 4, SFPalette.CYAN_DIM)
	_rect(img, 7, 9, 4, 2, SFPalette.CYAN)
	_px(img, 7, 9, SFPalette.PAPER)
	_rect(img, 0, 8, 3, 4, SFPalette.STEEL_MID)
	_rect(img, 15, 8, 3, 4, SFPalette.STEEL_MID)
	_rect(img, 8, 2, 2, 4, SFPalette.STEEL_MID)
	_px(img, 8, 1, SFPalette.CYAN)
	_rect(img, 4, 14, 10, 2, SFPalette.INK)
	return img


## The navigation chip: a cyan circuit block with gold contacts.
static func _navigation_chip() -> Image:
	var img := _img(16, 12)
	_rect(img, 2, 2, 12, 8, SFPalette.CYAN_DARK)
	_rect(img, 2, 2, 12, 1, SFPalette.CYAN)
	_rect(img, 5, 4, 6, 4, SFPalette.INK)
	_rect(img, 6, 5, 4, 2, SFPalette.CYAN)
	for i in 4:
		_px(img, 3 + i * 3, 0, SFPalette.GOLD)
		_px(img, 3 + i * 3, 1, SFPalette.GOLD)
		_px(img, 3 + i * 3, 10, SFPalette.GOLD)
		_px(img, 3 + i * 3, 11, SFPalette.GOLD)
	return img


## The power core: a squat reactor can with a glowing gold window.
static func _power_core() -> Image:
	var img := _img(14, 16)
	_rect(img, 2, 2, 10, 13, SFPalette.STEEL_DARK)
	_rect(img, 1, 1, 12, 2, SFPalette.STEEL_MID)
	_rect(img, 1, 13, 12, 2, SFPalette.STEEL_MID)
	_rect(img, 4, 5, 6, 6, SFPalette.RUIN_DARK)
	_rect(img, 5, 6, 4, 4, SFPalette.GOLD)
	_px(img, 5, 6, SFPalette.PAPER)
	return img


## A standing dead trunk from the former Dawn forest: bare, grey, split.
static func _dead_tree() -> Image:
	var img := _img(24, 40)
	var trunk: Color = Color("5a5248")
	var dark: Color = Color("3b352f")
	var light: Color = Color("7a7064")
	_rect(img, 10, 10, 4, 30, trunk)
	_rect(img, 10, 10, 1, 30, dark)
	_rect(img, 13, 12, 1, 26, light)
	_rect(img, 8, 36, 8, 4, dark)
	# Bare branches, broken short.
	_rect(img, 4, 14, 6, 2, trunk)
	_rect(img, 3, 11, 2, 4, trunk)
	_rect(img, 14, 18, 6, 2, trunk)
	_rect(img, 19, 14, 2, 5, trunk)
	_rect(img, 11, 3, 2, 8, trunk)
	_rect(img, 7, 6, 4, 1, dark)
	# A pale split down the trunk and a scrap of ash at the root.
	_px(img, 12, 20, light)
	_px(img, 12, 21, light)
	_px(img, 11, 28, dark)
	_rect(img, 6, 39, 12, 1, Color("2a2622"))
	return img


## The Dawn Tower: a tall transmitter on a facility base, with the shield
## emitter glowing at its crown. Origin is the ground-contact point.
static func _dawn_tower() -> Image:
	var img := _img(64, 96)
	var base: Color = SFPalette.STEEL_DARK
	var mid: Color = SFPalette.STEEL_MID
	var hi: Color = SFPalette.STEEL
	var smog: Color = Color("3a3048")
	# Facility base.
	_rect(img, 4, 72, 56, 24, base)
	_rect(img, 4, 72, 56, 2, mid)
	_rect(img, 24, 80, 16, 16, SFPalette.INK)
	_rect(img, 25, 81, 14, 1, SFPalette.CYAN_DARK)
	for i in 4:
		_rect(img, 8 + i * 13, 77, 6, 4, SFPalette.INK)
	# Lattice mast.
	_rect(img, 26, 14, 3, 58, mid)
	_rect(img, 35, 14, 3, 58, base)
	var y := 18
	while y < 70:
		_rect(img, 28, y, 8, 1, hi)
		_px(img, 30, y + 2, mid)
		_px(img, 33, y + 4, mid)
		y += 7
	# Transmitter dishes.
	_rect(img, 16, 30, 10, 6, mid)
	_rect(img, 15, 31, 1, 4, hi)
	_rect(img, 38, 44, 10, 6, mid)
	_rect(img, 48, 45, 1, 4, hi)
	# Shield emitter crown, wrapped in smog.
	_rect(img, 22, 4, 20, 10, base)
	_rect(img, 26, 6, 12, 6, SFPalette.CYAN_DIM)
	_rect(img, 29, 7, 6, 3, SFPalette.CYAN)
	for i in 10:
		_px(img, 18 + (i * 7) % 28, 2 + (i * 5) % 12, smog)
		_px(img, 19 + (i * 7) % 28, 2 + (i * 5) % 12, smog)
	return img


# ---------------------------------------------------------------- helpers

static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


# ---------------------------------------------------------------- astronaut 16x20
## Placeholder art: a readable human astronaut in a warm-white suit with a
## blue visor. Not a final character design.

static func _astronaut(dir: String) -> Image:
	var img := _img(16, 20)
	var suit: Color = SFPalette.WARM
	var suit_sh: Color = SFPalette.WARM_DARK
	var boot: Color = SFPalette.STEEL_DARK
	var visor: Color = SFPalette.BLUE_ACCENT
	var visor_hi: Color = Color("6fc6f0")
	var pack: Color = SFPalette.STEEL_MID
	var pack_sh: Color = SFPalette.STEEL_DARK
	var emblem: Color = SFPalette.EARTH_ORANGE

	# Boots.
	_rect(img, 4, 17, 3, 3, boot)
	_rect(img, 9, 17, 3, 3, boot)

	# Suit torso.
	_rect(img, 4, 9, 8, 9, suit)
	_rect(img, 4, 16, 8, 2, suit_sh)
	_rect(img, 4, 9, 1, 7, suit_sh)
	_rect(img, 11, 9, 1, 7, suit_sh)
	# Chest emblem and belt.
	_px(img, 6, 11, emblem)
	_px(img, 7, 11, emblem)
	_rect(img, 4, 14, 8, 1, suit_sh)

	# Arms.
	_rect(img, 2, 10, 2, 6, suit)
	_rect(img, 12, 10, 2, 6, suit)
	_rect(img, 2, 15, 2, 2, suit_sh)
	_rect(img, 12, 15, 2, 2, suit_sh)

	# Helmet dome.
	_rect(img, 4, 2, 8, 7, suit)
	_rect(img, 4, 2, 8, 1, Color("fbf6e4"))
	_rect(img, 3, 3, 1, 5, suit_sh)
	_rect(img, 12, 3, 1, 5, suit_sh)

	if dir == "down":
		_rect(img, 5, 3, 6, 4, visor)
		_rect(img, 5, 3, 3, 2, visor_hi)
		_px(img, 9, 3, visor_hi)
	elif dir == "up":
		# Back of the helmet plus the life-support backpack.
		_rect(img, 5, 4, 6, 4, suit_sh)
		_rect(img, 5, 12, 6, 5, pack)
		_rect(img, 5, 12, 6, 1, SFPalette.STEEL)
		_px(img, 6, 14, SFPalette.CYAN_DIM)
		_px(img, 9, 14, SFPalette.CYAN_DIM)
		_rect(img, 5, 16, 6, 1, pack_sh)
	elif dir == "left":
		_rect(img, 3, 3, 5, 4, visor)
		_rect(img, 3, 3, 2, 2, visor_hi)
		_rect(img, 10, 11, 3, 5, pack)
		_rect(img, 10, 11, 3, 1, SFPalette.STEEL)
	else:
		_rect(img, 8, 3, 5, 4, visor)
		_rect(img, 8, 3, 2, 2, visor_hi)
		_rect(img, 3, 11, 3, 5, pack)
		_rect(img, 3, 11, 3, 1, SFPalette.STEEL)
	return img


# ---------------------------------------------------------------- Bill 14x18
## A boxy maintenance unit: dark chassis, cyan single eye, stubby treads.

static func _bill(powered: bool) -> Image:
	var img := _img(14, 18)
	var shell: Color = SFPalette.ASH_LIGHT if powered else SFPalette.ASH
	var shell_dark: Color = SFPalette.ASH if powered else SFPalette.ASH.darkened(0.35)
	var eye: Color = SFPalette.CYAN if powered else SFPalette.CYAN_DARK
	var joint: Color = SFPalette.STEEL_DARK

	# Treads.
	_rect(img, 2, 14, 10, 4, shell_dark)
	_rect(img, 3, 15, 2, 2, joint)
	_rect(img, 6, 15, 2, 2, joint)
	_rect(img, 9, 15, 2, 2, joint)

	# Body.
	_rect(img, 3, 6, 8, 9, shell)
	_rect(img, 3, 6, 8, 1, SFPalette.ASH_LIGHT if powered else SFPalette.ASH)
	_rect(img, 3, 13, 8, 1, shell_dark)
	# Chest panel.
	_rect(img, 5, 9, 4, 3, shell_dark)
	_px(img, 6, 10, eye)
	_px(img, 7, 10, eye)

	# Head.
	_rect(img, 4, 1, 6, 5, shell)
	_rect(img, 4, 1, 6, 1, SFPalette.ASH_LIGHT if powered else SFPalette.ASH)
	_rect(img, 5, 2, 4, 2, shell_dark)
	_rect(img, 6, 2, 2, 2, eye)
	if powered:
		_px(img, 6, 2, Color("c9fff9"))
	# Antenna.
	_rect(img, 10, 0, 1, 3, joint)
	_px(img, 10, 0, eye)

	# Arms.
	_rect(img, 1, 8, 2, 4, shell_dark)
	_rect(img, 11, 8, 2, 4, shell_dark)
	return img


# ---------------------------------------------------------------- vegetation

static func _tree() -> Image:
	var img := _img(32, 40)
	var trunk: Color = SFPalette.BARK
	var trunk_dark: Color = SFPalette.BARK_DARK
	var leaf_light: Color = SFPalette.LEAF_LIGHT
	var leaf: Color = SFPalette.LEAF
	var leaf_dark: Color = SFPalette.LEAF_DARK
	# Trunk, ground contact at the bottom-centre.
	_rect(img, 14, 22, 5, 18, trunk)
	_rect(img, 14, 22, 1, 18, trunk_dark)
	_rect(img, 12, 36, 9, 4, trunk_dark)
	# Canopy in three overlapping blobs.
	_rect(img, 8, 10, 17, 14, leaf)
	_rect(img, 5, 14, 24, 8, leaf)
	_rect(img, 10, 6, 12, 10, leaf_light)
	_rect(img, 4, 12, 8, 8, leaf_dark)
	_rect(img, 21, 13, 7, 8, leaf_dark)
	_rect(img, 8, 18, 6, 5, leaf_dark)
	_rect(img, 15, 3, 9, 8, leaf)
	_rect(img, 17, 2, 5, 7, leaf_light)
	# Dappled highlights.
	_px(img, 12, 9, SFPalette.LEAF_LIGHT.lightened(0.15))
	_px(img, 14, 8, SFPalette.LEAF_LIGHT.lightened(0.15))
	_px(img, 23, 6, SFPalette.LEAF_LIGHT.lightened(0.15))
	_px(img, 9, 13, SFPalette.LEAF_LIGHT.lightened(0.1))
	return img


static func _bush() -> Image:
	var img := _img(20, 14)
	var leaf: Color = SFPalette.LEAF
	var light: Color = SFPalette.LEAF_LIGHT
	var dark: Color = SFPalette.LEAF_DARK
	_rect(img, 3, 5, 14, 8, leaf)
	_rect(img, 1, 7, 18, 5, leaf)
	_rect(img, 5, 3, 9, 6, light)
	_rect(img, 2, 9, 5, 4, dark)
	_rect(img, 14, 8, 4, 5, dark)
	_rect(img, 8, 11, 6, 2, dark)
	_px(img, 7, 5, light.lightened(0.2))
	_px(img, 12, 4, light.lightened(0.2))
	# Tiny flowers.
	_px(img, 4, 6, SFPalette.GOLD)
	_px(img, 15, 7, SFPalette.GOLD)
	return img


# ---------------------------------------------------------------- technology props

static func _terminal() -> Image:
	var img := _img(20, 32)
	var body: Color = SFPalette.STEEL_MID
	var body_dark: Color = SFPalette.STEEL_DARK
	var screen: Color = SFPalette.CYAN_DARK
	var glow: Color = SFPalette.CYAN
	# Legs and base.
	_rect(img, 3, 27, 14, 5, body_dark)
	_rect(img, 8, 22, 4, 6, body)
	# Cabinet.
	_rect(img, 1, 8, 18, 15, body)
	_rect(img, 1, 8, 18, 1, SFPalette.STEEL)
	_rect(img, 1, 22, 18, 1, body_dark)
	# Screen.
	_rect(img, 4, 10, 12, 8, screen)
	_rect(img, 5, 11, 10, 1, glow)
	_rect(img, 5, 13, 7, 1, glow)
	_rect(img, 5, 15, 9, 1, SFPalette.CYAN_DIM)
	# Keyboard ledge.
	_rect(img, 4, 19, 12, 2, body_dark)
	# Antenna.
	_rect(img, 15, 2, 1, 6, body_dark)
	_px(img, 15, 1, SFPalette.EARTH_ORANGE)
	return img


static func _console() -> Image:
	var img := _img(28, 24)
	var body: Color = SFPalette.STEEL_MID
	var body_dark: Color = SFPalette.STEEL_DARK
	var panel: Color = SFPalette.WARM
	var accent: Color = SFPalette.BLUE_ACCENT
	# Bench.
	_rect(img, 2, 10, 24, 12, body)
	_rect(img, 2, 10, 24, 1, SFPalette.STEEL)
	_rect(img, 2, 20, 24, 2, body_dark)
	# Angled control face.
	_rect(img, 5, 6, 18, 5, panel)
	_rect(img, 5, 6, 18, 1, SFPalette.WARM_DARK)
	# Buttons and readouts.
	_px(img, 8, 8, accent)
	_px(img, 10, 8, SFPalette.GREEN_OK)
	_px(img, 12, 8, SFPalette.GOLD)
	_rect(img, 15, 7, 6, 3, SFPalette.CYAN_DARK)
	# Cable to the floor.
	_rect(img, 24, 14, 2, 8, body_dark)
	return img


static func _crates() -> Image:
	var img := _img(24, 20)
	var wood: Color = SFPalette.EARTH_ORANGE
	var wood_light: Color = Color("f0a95c")
	var wood_dark: Color = Color("a35f28")
	# Back crate.
	_rect(img, 12, 3, 11, 10, wood)
	_rect(img, 12, 3, 11, 1, wood_light)
	_rect(img, 21, 3, 2, 10, wood_dark)
	_rect(img, 12, 11, 11, 2, wood_dark)
	# Front crate.
	_rect(img, 1, 8, 14, 11, wood)
	_rect(img, 1, 8, 14, 1, wood_light)
	_rect(img, 13, 8, 2, 11, wood_dark)
	_rect(img, 1, 17, 14, 2, wood_dark)
	_rect(img, 6, 8, 2, 11, wood_dark)
	# Stencil.
	_px(img, 3, 12, SFPalette.WARM)
	_px(img, 4, 12, SFPalette.WARM)
	_px(img, 3, 14, SFPalette.WARM)
	return img


static func _lamp() -> Image:
	var img := _img(10, 44)
	var post: Color = SFPalette.STEEL_DARK
	var metal: Color = SFPalette.STEEL_MID
	_rect(img, 4, 6, 2, 34, post)
	_rect(img, 3, 36, 4, 3, metal)
	_rect(img, 1, 39, 8, 2, metal)
	# Lamp head.
	_rect(img, 2, 2, 6, 5, metal)
	_rect(img, 3, 4, 4, 2, SFPalette.WARM)
	_px(img, 3, 7, SFPalette.WARM)
	_px(img, 6, 7, SFPalette.WARM)
	return img


static func _dish() -> Image:
	var img := _img(22, 30)
	var metal: Color = SFPalette.STEEL_MID
	var light: Color = SFPalette.STEEL
	var dark: Color = SFPalette.STEEL_DARK
	# Base.
	_rect(img, 6, 27, 10, 3, dark)
	_rect(img, 9, 20, 4, 8, metal)
	# Dish, angled up-right.
	_rect(img, 4, 6, 14, 10, metal)
	_rect(img, 4, 6, 14, 1, light)
	_rect(img, 4, 15, 14, 1, dark)
	_rect(img, 4, 6, 1, 10, dark)
	_rect(img, 17, 6, 1, 10, light)
	_rect(img, 8, 9, 6, 4, SFPalette.WARM_DARK)
	# Feed horn.
	_rect(img, 10, 2, 2, 5, light)
	_px(img, 10, 1, SFPalette.CYAN)
	return img


static func _rocket_frame() -> Image:
	var img := _img(40, 64)
	var metal: Color = SFPalette.STEEL_MID
	var light: Color = SFPalette.STEEL
	var dark: Color = SFPalette.STEEL_DARK
	var warm: Color = SFPalette.WARM_DARK
	# Scaffold cradle.
	_rect(img, 2, 52, 36, 4, dark)
	_rect(img, 4, 30, 3, 22, dark)
	_rect(img, 33, 30, 3, 22, dark)
	_rect(img, 4, 30, 32, 2, dark)
	# Bare hull, nose up.
	_rect(img, 13, 12, 14, 40, metal)
	_rect(img, 13, 12, 3, 40, light)
	_rect(img, 24, 12, 3, 40, dark)
	_rect(img, 15, 4, 10, 9, metal)
	_rect(img, 17, 1, 6, 4, metal)
	_rect(img, 17, 1, 2, 4, light)
	_rect(img, 23, 1, 1, 4, dark)
	# Open slots: dark recesses with socket rims.
	_rect(img, 17, 18, 6, 6, SFPalette.INK)
	_rect(img, 17, 27, 6, 6, SFPalette.INK)
	_rect(img, 17, 36, 6, 6, SFPalette.INK)
	_rect(img, 17, 45, 6, 5, SFPalette.INK)
	# Two side sockets.
	_rect(img, 9, 22, 4, 6, SFPalette.INK)
	_rect(img, 27, 22, 4, 6, SFPalette.INK)
	# Warning stripes on the cradle.
	for i in 5:
		_rect(img, 6 + i * 6, 53, 3, 2, warm)
	# Loose cable.
	_rect(img, 9, 40, 4, 1, dark)
	_rect(img, 8, 41, 1, 4, dark)
	return img


static func _wreck() -> Image:
	var img := _img(56, 46)
	var metal: Color = SFPalette.ASH_LIGHT
	var light: Color = SFPalette.ASH
	var dark: Color = SFPalette.ASH.darkened(0.3)
	var rust: Color = SFPalette.RUST
	# Hull lying on its side, nose to the left, half-buried.
	_rect(img, 6, 20, 40, 16, metal)
	_rect(img, 6, 20, 40, 3, light)
	_rect(img, 6, 33, 40, 3, dark)
	# Torn nose.
	_rect(img, 2, 23, 5, 10, metal)
	_rect(img, 2, 23, 5, 2, light)
	_rect(img, 2, 31, 5, 2, dark)
	# Breach.
	_rect(img, 20, 21, 10, 8, SFPalette.INK)
	_px(img, 20, 21, light)
	_px(img, 29, 28, light)
	# Engine block at the rear, detached a little.
	_rect(img, 45, 24, 8, 9, dark)
	_rect(img, 45, 24, 8, 2, metal)
	_rect(img, 50, 26, 3, 5, SFPalette.INK)
	# Rust streaks.
	_rect(img, 12, 24, 1, 8, rust)
	_rect(img, 30, 26, 1, 6, rust)
	_rect(img, 38, 22, 1, 9, rust)
	# Scorch.
	_rect(img, 14, 36, 24, 3, SFPalette.INK)
	# Cables spilling out.
	_rect(img, 18, 36, 8, 1, dark)
	_rect(img, 24, 37, 1, 5, dark)
	_rect(img, 32, 36, 6, 1, dark)
	return img


static func _salvage() -> Image:
	var img := _img(14, 12)
	var metal: Color = SFPalette.ASH_LIGHT
	var light: Color = SFPalette.ASH_LIGHT.lightened(0.2)
	var dark: Color = SFPalette.ASH
	var cyan: Color = SFPalette.CYAN_DIM
	# A loose plate leaning against the ground.
	_rect(img, 2, 4, 10, 6, metal)
	_rect(img, 2, 4, 10, 1, light)
	_rect(img, 2, 9, 10, 1, dark)
	_rect(img, 11, 4, 1, 6, dark)
	# Circuit trace and a bolt.
	_rect(img, 4, 7, 5, 1, cyan)
	_px(img, 5, 6, cyan)
	_px(img, 8, 6, cyan)
	_px(img, 3, 5, dark)
	_px(img, 10, 8, dark)
	return img


static func _junction() -> Image:
	var img := _img(16, 20)
	var metal: Color = SFPalette.STEEL_DARK
	var light: Color = SFPalette.STEEL_MID
	var socket: Color = SFPalette.INK
	var live: Color = SFPalette.CYAN
	# Wall box.
	_rect(img, 2, 3, 12, 14, metal)
	_rect(img, 2, 3, 12, 1, light)
	_rect(img, 2, 16, 12, 1, SFPalette.INK)
	# Panel door ajar.
	_rect(img, 4, 6, 8, 8, socket)
	_rect(img, 4, 6, 8, 1, light)
	# Exposed terminals.
	_px(img, 6, 9, live)
	_px(img, 9, 9, live)
	_rect(img, 6, 12, 4, 1, SFPalette.ASH)
	# Conduit going down into the floor.
	_rect(img, 7, 17, 3, 3, light)
	return img


static func _rubble() -> Image:
	var img := _img(18, 10)
	var ash: Color = SFPalette.ASH
	var light: Color = SFPalette.ASH_LIGHT
	var dark: Color = SFPalette.ASH.darkened(0.3)
	for i in 6:
		var x: int = 1 + i * 3
		var h: int = 3 + (i * 5) % 5
		_rect(img, x, 9 - h, 3, h, ash if i % 2 == 0 else dark)
		_px(img, x, 9 - h, light)
	return img


## Launch-platform beacon: a striped gantry marker with a lit top.
static func _pad_beacon() -> Image:
	var img := _img(18, 40)
	var dark: Color = SFPalette.STEEL_DARK
	var mid: Color = SFPalette.STEEL_MID
	var warm: Color = SFPalette.WARM_DARK
	var cyan: Color = SFPalette.CYAN
	# Base.
	_rect(img, 1, 34, 16, 4, dark)
	_rect(img, 2, 33, 14, 1, mid)
	# Post.
	_rect(img, 7, 10, 4, 24, mid)
	_rect(img, 7, 10, 1, 24, SFPalette.STEEL)
	# Hazard stripes.
	for i in 5:
		_rect(img, 7, 28 - i * 4, 4, 2, warm)
	# Lamp head on a short arm.
	_rect(img, 4, 6, 10, 5, dark)
	_rect(img, 5, 7, 8, 3, cyan)
	_rect(img, 6, 8, 3, 1, Color("c9fff9"))
	_rect(img, 8, 1, 2, 5, dark)
	_px(img, 8, 0, cyan)
	return img


# ---------------------------------------------------------------- earth 96x96

static func _earth() -> Image:
	var img := _img(96, 96)
	var r: int = 46
	var cx: int = 48
	var cy: int = 48
	var rng := RandomNumberGenerator.new()
	rng.seed = 44121
	var ocean: Color = Color("3f8fc9")
	var ocean_deep: Color = Color("265f92")
	var land: Color = Color("6fb549")
	var land_light: Color = Color("8ccb5e")
	var cloud: Color = Color("f2f4e8")
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx: int = x - cx
			var dy: int = y - cy
			var d2: int = dx * dx + dy * dy
			if d2 > r * r:
				continue
			var lit: float = clampf((-float(dx) - float(dy)) / 110.0 + 0.6, 0.0, 1.0)
			_px(img, x, y, ocean_deep.lerp(ocean, lit))
	# Continents: a few large, coherent masses rather than uniform speckle.
	# Each mass is a cluster of overlapping discs of the same tone, which reads
	# as land at this size.
	var masses := [
		[Vector2(-0.42, -0.30), 0.30], [Vector2(-0.15, 0.10), 0.26],
		[Vector2(0.10, -0.48), 0.20], [Vector2(0.34, 0.26), 0.24],
		[Vector2(-0.50, 0.38), 0.17], [Vector2(0.46, -0.14), 0.15],
	]
	for mass in masses:
		var center: Vector2 = mass[0]
		var scale_r: float = mass[1]
		var mx: float = float(cx) + center.x * float(r)
		var my: float = float(cy) + center.y * float(r)
		var mr: float = scale_r * float(r)
		# Three overlapping lobes give an irregular coastline.
		for lobe in 3:
			var lx: float = mx + cos(float(lobe) * 2.1 + center.x * 5.0) * mr * 0.42
			var ly: float = my + sin(float(lobe) * 2.1 + center.y * 5.0) * mr * 0.42
			var lr: float = mr * (0.62 + 0.18 * float(lobe % 2))
			var reach: int = int(lr) + 1
			for dy in range(-reach, reach):
				for dx in range(-reach, reach):
					var d: float = sqrt(float(dx * dx + dy * dy))
					if d > lr:
						continue
					# Ragged edge: the last third of the radius is dithered.
					if d > lr * 0.68 and rng.randf() < 0.55:
						continue
					var px_i: int = int(round(lx)) + dx
					var py_i: int = int(round(ly)) + dy
					# Keep the land inside the lit hemisphere.
					var lit3: float = clampf((-(float(px_i - cx)) - float(py_i - cy)) / 110.0 + 0.6, 0.0, 1.0)
					if lit3 < 0.22:
						continue
					_px(img, px_i, py_i, land if d > lr * 0.5 else land_light)
	# Cloud wisps: short, soft, and broken, so they read as weather rather than
	# as white bars across the disc.
	for i in 34:
		var cy2: int = cy - r + 12 + rng.randi() % (r * 2 - 24)
		var start_x: int = cx - r + 12 + rng.randi() % (r * 2 - 24)
		var length: int = 3 + rng.randi() % 9
		for k in length:
			var cxx: int = start_x + k
			var lit4: float = clampf((-(float(cxx - cx)) - float(cy2 - cy)) / 110.0 + 0.6, 0.0, 1.0)
			if lit4 < 0.42:
				continue
			# Taper the ends so no wisp has a hard start or finish.
			var taper: float = 1.0 - absf(float(k) / float(length) * 2.0 - 1.0)
			if rng.randf() > taper * 0.85 + 0.15:
				continue
			_px(img, cxx, cy2, cloud)
			if rng.randf() < 0.35:
				_px(img, cxx, cy2 - 1, cloud)
	return img


# ---------------------------------------------------------------- phase 2 props
## Broken electronics heaped into a pile. Read as salvage, not as furniture:
## angular, layered, with a little cyan trace still lit.

static func _waste_pile() -> Image:
	var img := _img(26, 16)
	var metal: Color = SFPalette.ASH
	var light: Color = SFPalette.ASH_LIGHT
	var dark: Color = SFPalette.ASH.darkened(0.35)
	var board: Color = SFPalette.CYAN_DARK
	_rect(img, 2, 10, 22, 5, dark)
	_rect(img, 3, 9, 20, 4, metal)
	_rect(img, 4, 6, 9, 4, metal)
	_rect(img, 5, 5, 7, 2, light)
	_rect(img, 14, 7, 9, 3, dark)
	_rect(img, 15, 6, 7, 2, metal)
	_rect(img, 7, 2, 5, 4, dark)
	_rect(img, 8, 1, 3, 2, light)
	# Circuit traces and terminals.
	_rect(img, 5, 7, 6, 1, board)
	_rect(img, 16, 8, 5, 1, board)
	_px(img, 9, 6, SFPalette.CYAN_DIM)
	_px(img, 18, 7, SFPalette.CYAN_DIM)
	_px(img, 3, 12, SFPalette.RUST)
	_px(img, 22, 11, SFPalette.RUST)
	return img


## A leaning stack of stripped circuit boards, like a shelf that gave up.
static func _board_stack() -> Image:
	var img := _img(14, 18)
	var board: Color = SFPalette.CYAN_DARK
	var board_light: Color = SFPalette.CYAN_DIM
	var dark: Color = SFPalette.ASH.darkened(0.4)
	for i in 7:
		var w: int = 10 - (i % 3)
		var x: int = 1 + (i % 3)
		var y: int = 17 - i * 2
		_rect(img, x, y, w, 2, board if i % 2 == 0 else dark)
		_rect(img, x, y, w, 1, board_light if i % 3 == 0 else board)
		if i % 2 == 0:
			_px(img, x + 2, y + 1, SFPalette.CYAN)
	return img


## A bent street lamp that still works. The only warm light in the city.
static func _street_lamp() -> Image:
	var img := _img(14, 30)
	var pole: Color = SFPalette.STEEL_DARK
	var mid: Color = SFPalette.STEEL_MID
	var rest: Color = SFPalette.RUST
	_rect(img, 3, 27, 8, 3, SFPalette.CONCRETE_DARK)
	_rect(img, 6, 8, 2, 20, pole)
	_rect(img, 6, 8, 1, 20, mid)
	_rect(img, 6, 7, 6, 2, pole)
	_rect(img, 10, 7, 4, 3, SFPalette.GOLD.darkened(0.35))
	_rect(img, 11, 8, 2, 1, SFPalette.GOLD)
	_px(img, 7, 18, rest)
	_px(img, 8, 23, rest)
	return img


## The control-center door: heavy portal frame with distinct locked/unlocked states.
static func _control_door(unlocked: bool = false) -> Image:
	var img := _img(32, 36)
	var frame: Color = SFPalette.RUIN
	var panel: Color = SFPalette.STEEL_DARK
	var light: Color = SFPalette.STEEL_MID
	var accent: Color = SFPalette.CYAN if unlocked else SFPalette.RUST_LIGHT
	_rect(img, 0, 2, 32, 34, frame)
	_rect(img, 1, 2, 30, 2, light)
	# Overhead portal header bar with status beacon lights.
	_rect(img, 2, 4, 28, 4, SFPalette.INK)
	_rect(img, 4, 5, 6, 2, accent)
	_rect(img, 13, 5, 6, 2, SFPalette.PAPER if unlocked else accent)
	_rect(img, 22, 5, 6, 2, accent)
	# Side pillars with lit vertical guide strips.
	_rect(img, 2, 9, 3, 27, panel)
	_rect(img, 27, 9, 3, 27, panel)
	_rect(img, 3, 11, 1, 22, accent)
	_rect(img, 28, 11, 1, 22, accent)
	# Blast door panels.
	_rect(img, 5, 9, 22, 27, panel)
	_rect(img, 5, 9, 22, 1, light)
	if unlocked:
		# Parted blast doors revealing lit interior portal.
		_rect(img, 12, 10, 8, 26, SFPalette.INK)
		_rect(img, 14, 12, 4, 22, SFPalette.CYAN_DARK)
		_rect(img, 15, 14, 2, 18, SFPalette.CYAN)
		_rect(img, 6, 13, 4, 7, SFPalette.INK)
		_rect(img, 22, 13, 4, 7, SFPalette.INK)
		_rect(img, 7, 15, 2, 3, SFPalette.CYAN)
		_rect(img, 23, 15, 2, 3, SFPalette.CYAN)
	else:
		# Welded centre seam and lockdown bars.
		_rect(img, 15, 10, 2, 26, SFPalette.INK)
		for i in 6:
			_rect(img, 13, 11 + i * 4, 6, 1, SFPalette.RUST)
		_rect(img, 6, 13, 7, 9, SFPalette.INK)
		_rect(img, 7, 15, 5, 2, SFPalette.RUST_LIGHT)
		_rect(img, 19, 13, 7, 9, SFPalette.INK)
		_rect(img, 20, 15, 5, 2, SFPalette.RUST_LIGHT)
		_rect(img, 9, 26, 14, 2, light)
	return img


## Cleanup-facility portal gate on the Silent Coast: unmistakable industrial
## bulkhead arch with locked/unlocked beacon framing (distinct from pumps).
static func _facility_gate(unlocked: bool = false) -> Image:
	var img := _img(32, 36)
	var shell: Color = Color("243b3e")
	var metal: Color = Color("3e6b70")
	var light: Color = Color("6fa3a8")
	var accent: Color = SFPalette.CYAN if unlocked else SFPalette.GOLD
	# Heavy arch frame.
	_rect(img, 0, 3, 32, 33, shell)
	_rect(img, 1, 3, 30, 2, light)
	_rect(img, 2, 5, 28, 4, SFPalette.INK)
	_rect(img, 4, 6, 7, 2, accent)
	_rect(img, 13, 6, 6, 2, SFPalette.PAPER if unlocked else accent)
	_rect(img, 21, 6, 7, 2, accent)
	# Twin intake columns.
	_rect(img, 2, 10, 5, 26, metal)
	_rect(img, 25, 10, 5, 26, metal)
	_rect(img, 4, 12, 1, 21, accent)
	_rect(img, 27, 12, 1, 21, accent)
	# Central airlock hatch.
	_rect(img, 7, 10, 18, 26, SFPalette.STEEL_DARK)
	_rect(img, 7, 10, 18, 1, light)
	if unlocked:
		_rect(img, 11, 12, 10, 24, SFPalette.INK)
		_rect(img, 13, 14, 6, 20, SFPalette.CYAN_DARK)
		_rect(img, 15, 16, 2, 16, SFPalette.CYAN)
		_rect(img, 7, 34, 18, 2, SFPalette.CYAN)
	else:
		_rect(img, 9, 14, 14, 18, SFPalette.INK)
		_rect(img, 10, 18, 12, 2, SFPalette.RUST_LIGHT)
		_rect(img, 10, 24, 12, 2, SFPalette.GOLD)
		_rect(img, 15, 14, 2, 18, metal)
	return img


## A little maintenance shrine: a picture, a lamp, and four bolts.
static func _shrine() -> Image:
	var img := _img(18, 22)
	var metal: Color = SFPalette.STEEL_DARK
	var light: Color = SFPalette.STEEL_MID
	_rect(img, 2, 6, 14, 15, metal)
	_rect(img, 2, 6, 14, 1, light)
	_rect(img, 2, 20, 14, 1, SFPalette.INK)
	# The picture in the frame: green, and deliberately still green.
	_rect(img, 5, 9, 8, 8, SFPalette.GRASS_DARK)
	_rect(img, 6, 10, 6, 3, SFPalette.LEAF)
	_rect(img, 6, 14, 2, 2, SFPalette.LEAF_LIGHT)
	_px(img, 10, 14, SFPalette.GRASS_LIGHT)
	# Votive light.
	_rect(img, 7, 1, 4, 4, SFPalette.CYAN_DIM)
	_rect(img, 8, 2, 2, 2, SFPalette.CYAN)
	_px(img, 5, 18, SFPalette.GOLD)
	_px(img, 12, 18, SFPalette.GOLD)
	return img


## A checkpoint marker: a lit post with a ring, obvious from across the map.
static func _checkpoint() -> Image:
	var img := _img(16, 26)
	var post: Color = SFPalette.STEEL_DARK
	var gold: Color = SFPalette.GOLD
	_rect(img, 3, 23, 10, 3, SFPalette.CONCRETE_DARK)
	_rect(img, 7, 8, 2, 16, post)
	# Ring.
	_rect(img, 4, 4, 8, 2, gold)
	_rect(img, 4, 9, 8, 2, gold)
	_rect(img, 3, 6, 2, 3, gold)
	_rect(img, 11, 6, 2, 3, gold)
	_px(img, 8, 6, SFPalette.PAPER)
	_px(img, 8, 8, SFPalette.PAPER)
	return img


## A harbour crate, slatted and salt-stained.
static func _harbor_crate() -> Image:
	var img := _img(20, 16)
	var wood: Color = Color("5a4a38")
	var wood_light: Color = Color("72604a")
	var metal: Color = SFPalette.STEEL_DARK
	_rect(img, 1, 4, 18, 12, wood)
	_rect(img, 1, 4, 18, 2, wood_light)
	for i in 3:
		_rect(img, 2, 8 + i * 3, 16, 1, SFPalette.INK.darkened(0.2))
	_rect(img, 1, 4, 2, 12, metal)
	_rect(img, 17, 4, 2, 12, metal)
	# Salt bloom.
	_px(img, 6, 12, SFPalette.PAPER_DIM)
	_px(img, 13, 6, SFPalette.PAPER_DIM)
	return img


## A corroded chemical drum, lid open.
static func _drum() -> Image:
	var img := _img(14, 18)
	var body: Color = Color("4a5a52")
	var light: Color = Color("66776d")
	var rust: Color = SFPalette.RUST
	_rect(img, 2, 4, 10, 14, body)
	_rect(img, 2, 4, 10, 1, light)
	_rect(img, 3, 2, 8, 2, SFPalette.STEEL_DARK)
	_rect(img, 3, 8, 10, 1, SFPalette.INK.darkened(0.15))
	_rect(img, 3, 13, 10, 1, SFPalette.INK.darkened(0.15))
	_rect(img, 4, 6, 1, 9, rust)
	_rect(img, 9, 9, 1, 6, rust)
	_px(img, 6, 2, SFPalette.VIOLET_LIGHT)
	return img


## A marine pump housing, still connected to something.
static func _pump() -> Image:
	var img := _img(22, 24)
	var metal: Color = Color("3e6b70")
	var light: Color = Color("6fa3a8")
	var dark: Color = SFPalette.STEEL_DARK
	_rect(img, 1, 8, 20, 16, metal)
	_rect(img, 1, 8, 20, 2, light)
	_rect(img, 1, 22, 20, 1, SFPalette.INK)
	# Cylinder cap and pipe.
	_rect(img, 5, 4, 12, 5, dark)
	_rect(img, 6, 3, 10, 1, light)
	_rect(img, 15, 1, 4, 4, dark)
	# Gauge and valve.
	_rect(img, 4, 12, 6, 6, SFPalette.INK)
	_px(img, 6, 14, SFPalette.CYAN_DIM)
	_rect(img, 13, 13, 4, 2, light)
	_rect(img, 13, 17, 4, 2, light)
	_px(img, 2, 20, SFPalette.RUST_LIGHT)
	_px(img, 19, 20, SFPalette.RUST)
	return img


## A sampling point: a small marked post with a vial.
static func _sample_point() -> Image:
	var img := _img(12, 14)
	_rect(img, 3, 10, 6, 4, SFPalette.CONCRETE_DARK)
	_rect(img, 5, 3, 2, 8, SFPalette.STEEL_MID)
	_rect(img, 4, 1, 4, 3, SFPalette.STEEL_DARK)
	_px(img, 5, 2, SFPalette.VIOLET_LIGHT)
	_px(img, 6, 2, SFPalette.CYAN)
	return img


## A research record terminal, screen still faintly alive.
static func _record_terminal() -> Image:
	var img := _img(16, 24)
	var metal: Color = SFPalette.STEEL_DARK
	var light: Color = SFPalette.STEEL_MID
	_rect(img, 2, 8, 12, 15, metal)
	_rect(img, 2, 8, 12, 1, light)
	_rect(img, 4, 3, 8, 7, metal)
	_rect(img, 5, 4, 6, 5, SFPalette.INK)
	_rect(img, 6, 5, 4, 1, SFPalette.CYAN_DIM)
	_rect(img, 6, 7, 3, 1, SFPalette.CYAN_DARK)
	# Keypad.
	for row in 3:
		for col in 3:
			_px(img, 4 + col * 3, 12 + row * 3, SFPalette.ASH_LIGHT)
	return img
