extends RefCounted
const SFPalette := preload("res://core/starfall/sf_palette.gd")
## Builds every sprite in the game as pixel data at startup.
## Strictly 16x16 / 32x32 grids, 2-3 tone shading, no black outlines, all
## nearest-filtered. Nothing is loaded from disk.

static func build_all() -> Dictionary:
	var out: Dictionary = {}
	out["ship"] = _tex(_ship())
	out["scrap"] = _tex(_scrap())
	out["panel"] = _tex(_panel())
	out["satellite"] = _tex(_satellite())
	out["billboard"] = _tex(_billboard())
	out["packaging"] = _tex(_packaging())
	out["trophy"] = _tex(_trophy())
	out["specimen"] = _tex(_specimen())
	out["station"] = _tex(_station())
	out["earth"] = _tex(_earth())
	return out


# ---------------------------------------------------------------- helpers

static func _tex(img: Image) -> ImageTexture:
	var t := ImageTexture.create_from_image(img)
	return t


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


static func _hline(img: Image, x: int, y: int, w: int, c: Color) -> void:
	_rect(img, x, y, w, 1, c)


static func _vline(img: Image, x: int, y: int, h: int, c: Color) -> void:
	_rect(img, x, y, 1, h, c)


## Deterministic scatter, so sprite art is identical every launch.
static func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# ---------------------------------------------------------------- ship 32x32
## Compact industrial salvage hull, nose to the right, cyan cockpit visor.

static func _ship() -> Image:
	var img := _img(32, 32)
	var deep: Color = SFPalette.DEEP
	var sh: Color = SFPalette.SHADOW
	var mid: Color = SFPalette.MID
	var hi: Color = SFPalette.HIGH
	var cyan: Color = SFPalette.CYAN
	var cyan_dim: Color = SFPalette.CYAN_DIM

	# Side industrial pods (top / bottom).
	_rect(img, 9, 9, 13, 3, sh)
	_hline(img, 9, 9, 13, mid)
	_rect(img, 9, 21, 13, 3, sh)
	_hline(img, 9, 23, 13, mid)

	# Main hull.
	_rect(img, 7, 12, 18, 9, mid)
	_rect(img, 7, 12, 18, 2, hi)
	_rect(img, 7, 19, 18, 2, sh)
	_px(img, 7, 12, hi)

	# Nose wedge.
	_rect(img, 24, 13, 2, 7, hi)
	_rect(img, 26, 14, 2, 5, hi)
	_rect(img, 24, 13, 1, 1, mid)
	_px(img, 25, 19, high_or(mid, sh))

	# Cockpit visor.
	_rect(img, 18, 14, 5, 3, cyan)
	_rect(img, 21, 14, 2, 3, cyan_dim)
	_px(img, 18, 14, SFPalette.PAPER)

	# Cargo clamps forward.
	_rect(img, 22, 10, 3, 2, hi)
	_rect(img, 22, 20, 3, 2, sh)

	# Thruster nozzles at the rear.
	_rect(img, 5, 12, 3, 3, sh)
	_rect(img, 5, 18, 3, 3, sh)
	_vline(img, 5, 12, 3, deep)
	_vline(img, 5, 18, 3, deep)
	_px(img, 8, 11, mid)
	_px(img, 8, 21, mid)

	# Greebles and panel lines.
	_hline(img, 10, 17, 7, sh)
	_px(img, 12, 15, sh)
	_px(img, 13, 16, sh)
	_px(img, 20, 18, sh)
	_px(img, 9, 18, sh)
	_rect(img, 11, 10, 2, 2, mid)

	# Running lights.
	_px(img, 9, 12, cyan)
	_px(img, 9, 20, cyan)
	_px(img, 7, 16, cyan_dim)

	# Antenna dish.
	_rect(img, 14, 8, 2, 2, mid)
	_px(img, 14, 8, hi)
	return img


static func high_or(a: Color, b: Color) -> Color:
	return a if a.v > b.v else b


# ---------------------------------------------------------------- scrap 16x16

static func _scrap() -> Image:
	var img := _img(16, 16)
	var mid: Color = SFPalette.MID
	var hi: Color = SFPalette.HIGH
	var sh: Color = SFPalette.SHADOW
	var rows: Array = [
		[7, 9, 3], [6, 10, 4], [5, 11, 5], [4, 12, 6],
		[3, 13, 7], [3, 14, 8], [4, 12, 9], [5, 11, 10],
		[5, 9, 11], [6, 8, 12],
	]
	for e in rows:
		var entry: Array = e as Array
		var x0: int = entry[0]
		var x1: int = entry[1]
		var y: int = entry[2]
		_rect(img, x0, y, x1 - x0 + 1, 1, mid)
		_px(img, x0, y, hi)
		_px(img, x1, y, sh)
	# Bevel + crack.
	_px(img, 6, 5, hi)
	_px(img, 8, 6, hi)
	_px(img, 7, 7, sh)
	_px(img, 8, 8, sh)
	_px(img, 7, 9, sh)
	_px(img, 5, 9, hi)
	return img


# ---------------------------------------------------------------- panel 32x16

static func _panel() -> Image:
	var img := _img(32, 16)
	var blue: Color = SFPalette.BLUE
	var gold: Color = SFPalette.GOLD
	var sh: Color = SFPalette.SHADOW
	var hi: Color = SFPalette.HIGH
	# Frame.
	_hline(img, 1, 1, 29, gold)
	_hline(img, 1, 14, 26, gold)
	_vline(img, 1, 1, 14, gold)
	_vline(img, 29, 1, 8, gold)
	# Cells.
	for gy in 3:
		for gx in 5:
			var cx: int = 3 + gx * 5
			var cy: int = 3 + gy * 4
			_rect(img, cx, cy, 4, 3, blue)
			_px(img, cx, cy, SFPalette.CYAN_DIM)
	# Shadows between cells.
	for gx in 5:
		_vline(img, 2 + gx * 5, 3, 11, sh)
	# Crack.
	var crack: Array = [[21, 2], [20, 3], [20, 4], [19, 5], [18, 6], [18, 7], [17, 8], [16, 9], [15, 10], [15, 11], [14, 12]]
	for cc in crack:
		var c: Array = cc as Array
		_px(img, c[0], c[1], hi)
	# Broken right edge.
	_rect(img, 26, 9, 5, 2, Color(0, 0, 0, 0))
	_px(img, 26, 8, sh)
	_px(img, 25, 10, sh)
	_px(img, 27, 11, sh)
	return img


# ---------------------------------------------------------------- satellite 32x32

static func _satellite() -> Image:
	var img := _img(32, 32)
	var mid: Color = SFPalette.MID
	var hi: Color = SFPalette.HIGH
	var sh: Color = SFPalette.SHADOW
	var blue: Color = SFPalette.BLUE
	# Solar wings, with cell grids and gold bus bars.
	_rect(img, 1, 11, 11, 9, blue)
	_rect(img, 20, 11, 11, 9, blue)
	for gx in 4:
		_vline(img, 3 + gx * 3, 11, 9, SFPalette.CYAN_DIM)
		_vline(img, 21 + gx * 3, 11, 9, SFPalette.CYAN_DIM)
	_hline(img, 1, 11, 11, hi)
	_hline(img, 20, 11, 11, hi)
	_hline(img, 1, 19, 11, sh)
	_hline(img, 20, 19, 11, sh)
	_px(img, 1, 11, SFPalette.GOLD)
	_px(img, 31, 11, SFPalette.GOLD)
	# Boom arms to the bus.
	_rect(img, 12, 14, 8, 3, sh)
	_rect(img, 12, 14, 8, 1, mid)
	# Main bus, a fat cylinder.
	_rect(img, 11, 8, 10, 14, mid)
	_rect(img, 12, 8, 3, 14, hi)
	_rect(img, 18, 8, 3, 14, sh)
	_hline(img, 11, 21, 10, sh)
	_hline(img, 11, 8, 10, hi)
	# Instrument plate.
	_rect(img, 13, 17, 6, 3, sh)
	_rect(img, 14, 17, 4, 1, SFPalette.CYAN_DIM)
	# Antenna, bent by a collision.
	var ant: Array = [[16, 7], [16, 5], [17, 4], [18, 3], [19, 3], [20, 2]]
	for aa in ant:
		var a: Array = aa as Array
		_px(img, a[0], a[1], sh)
	_rect(img, 19, 1, 3, 2, mid)
	_px(img, 19, 1, hi)
	# Snapped secondary antenna.
	_px(img, 14, 7, sh)
	_px(img, 13, 6, sh)
	# Beacon housing.
	_rect(img, 15, 6, 2, 2, sh)
	_px(img, 15, 6, SFPalette.RED)
	# Stencilled label.
	_rect(img, 13, 11, 6, 3, hi)
	_px(img, 14, 12, sh)
	_px(img, 15, 12, sh)
	_px(img, 16, 12, sh)
	_px(img, 17, 13, SFPalette.CYAN)
	return img


# ---------------------------------------------------------------- billboard 32x22

static func _billboard() -> Image:
	var img := _img(32, 22)
	var deep: Color = SFPalette.DEEP
	var cyan: Color = SFPalette.CYAN
	var paper: Color = SFPalette.PAPER
	var gold: Color = SFPalette.GOLD
	var sh: Color = SFPalette.SHADOW
	# Board.
	_rect(img, 2, 2, 28, 15, deep)
	_hline(img, 2, 2, 28, cyan)
	_hline(img, 2, 16, 28, SFPalette.CYAN_DIM)
	_vline(img, 2, 2, 15, cyan)
	_vline(img, 29, 2, 15, SFPalette.CYAN_DIM)
	# Suggestion of headline copy.
	_rect(img, 5, 5, 20, 2, paper)
	_rect(img, 5, 9, 13, 1, paper)
	_rect(img, 5, 11, 17, 1, SFPalette.MID)
	_rect(img, 5, 13, 9, 1, gold)
	# Leaf mark.
	_px(img, 24, 9, SFPalette.GREEN)
	_px(img, 25, 9, SFPalette.GREEN)
	_px(img, 24, 10, SFPalette.GREEN)
	_px(img, 25, 11, SFPalette.GREEN)
	# Support strut, bent.
	_rect(img, 14, 17, 4, 4, sh)
	_rect(img, 15, 17, 1, 3, SFPalette.MID)
	_rect(img, 17, 19, 3, 2, sh)
	return img


# ---------------------------------------------------------------- packaging 16x16

static func _packaging() -> Image:
	var img := _img(16, 16)
	var gold: Color = SFPalette.GOLD
	var paper: Color = SFPalette.PAPER
	var sh: Color = SFPalette.SHADOW
	var cyan: Color = SFPalette.CYAN
	# Box A.
	_rect(img, 1, 6, 6, 7, gold)
	_rect(img, 1, 6, 6, 1, paper)
	_vline(img, 3, 6, 7, sh)
	_hline(img, 1, 12, 6, sh)
	# Box B.
	_rect(img, 7, 3, 7, 6, paper)
	_rect(img, 7, 3, 7, 1, SFPalette.HIGH)
	_vline(img, 10, 3, 6, sh)
	_hline(img, 7, 8, 7, sh)
	# Box C, partly behind.
	_rect(img, 8, 10, 6, 4, gold)
	_hline(img, 8, 13, 6, sh)
	_vline(img, 11, 10, 4, sh)
	# Tape.
	_rect(img, 2, 9, 4, 1, cyan)
	_px(img, 12, 5, cyan)
	return img


# ---------------------------------------------------------------- trophy 16x16

static func _trophy() -> Image:
	var img := _img(16, 16)
	var gold: Color = SFPalette.GOLD
	var hi: Color = Color(1.0, 0.86, 0.42)
	var sh: Color = Color(0.62, 0.44, 0.02)
	# Cup bowl.
	_hline(img, 5, 2, 6, hi)
	_rect(img, 4, 3, 8, 4, gold)
	_rect(img, 10, 3, 2, 4, sh)
	_hline(img, 5, 7, 6, sh)
	# Handles.
	_vline(img, 2, 3, 3, gold)
	_vline(img, 13, 3, 3, gold)
	_px(img, 3, 3, gold)
	_px(img, 12, 3, gold)
	_px(img, 3, 5, sh)
	_px(img, 12, 5, sh)
	# Stem and base.
	_rect(img, 7, 8, 2, 3, SFPalette.SHADOW)
	_rect(img, 5, 11, 6, 2, gold)
	_hline(img, 5, 11, 6, hi)
	_hline(img, 5, 12, 6, sh)
	_px(img, 5, 3, paper_hi())
	return img


static func paper_hi() -> Color:
	return SFPalette.PAPER


# ---------------------------------------------------------------- specimen 16x16

static func _specimen() -> Image:
	var img := _img(16, 16)
	var sh: Color = SFPalette.SHADOW
	var mid: Color = SFPalette.MID
	var hi: Color = SFPalette.HIGH
	var green: Color = SFPalette.GREEN
	var cyan: Color = SFPalette.CYAN
	# Outer shell.
	_rect(img, 3, 2, 10, 12, sh)
	_rect(img, 4, 3, 8, 10, mid)
	_rect(img, 4, 3, 8, 1, hi)
	_vline(img, 11, 3, 10, sh)
	# Viewing port.
	_rect(img, 5, 5, 5, 5, SFPalette.DEEP)
	_rect(img, 6, 6, 3, 3, green)
	_px(img, 6, 6, Color(0.55, 1.0, 0.72))
	_px(img, 8, 8, SFPalette.BLUE)
	# Status strip and bolts.
	_rect(img, 5, 11, 5, 1, cyan)
	_px(img, 4, 4, cyan)
	_px(img, 10, 4, cyan)
	_px(img, 4, 12, cyan)
	_px(img, 10, 12, cyan)
	return img


# ---------------------------------------------------------------- station 96x64

static func _station() -> Image:
	var img := _img(96, 64)
	var sh: Color = SFPalette.SHADOW
	var mid: Color = SFPalette.MID
	var hi: Color = SFPalette.HIGH
	var cyan: Color = SFPalette.CYAN
	var blue: Color = SFPalette.BLUE
	# Solar wings.
	_rect(img, 2, 24, 26, 16, blue)
	_rect(img, 68, 24, 26, 16, blue)
	for i in 5:
		_vline(img, 5 + i * 5, 24, 16, SFPalette.CYAN_DIM)
		_vline(img, 71 + i * 5, 24, 16, SFPalette.CYAN_DIM)
	_hline(img, 2, 24, 26, mid)
	_hline(img, 68, 24, 26, mid)
	_hline(img, 2, 39, 26, sh)
	_hline(img, 68, 39, 26, sh)
	# Trusses.
	_rect(img, 28, 30, 8, 4, sh)
	_rect(img, 60, 30, 8, 4, sh)
	_hline(img, 28, 30, 40, mid)
	# Main hub.
	_rect(img, 36, 18, 24, 28, mid)
	_rect(img, 36, 18, 24, 3, hi)
	_rect(img, 36, 43, 24, 3, sh)
	_vline(img, 58, 18, 28, sh)
	# Habitat module.
	_rect(img, 30, 8, 36, 10, sh)
	_hline(img, 30, 8, 36, mid)
	# Windows.
	for i in 4:
		_rect(img, 40 + i * 5, 26, 2, 3, cyan)
		_rect(img, 40 + i * 5, 35, 2, 2, SFPalette.CYAN_DIM)
	# Docking collar facing down.
	_rect(img, 42, 46, 12, 6, sh)
	_rect(img, 44, 48, 8, 4, SFPalette.DEEP)
	_rect(img, 44, 48, 8, 1, cyan)
	# Radiators.
	_rect(img, 20, 44, 14, 10, sh)
	_rect(img, 62, 44, 14, 10, sh)
	for i in 3:
		_hline(img, 21, 46 + i * 3, 12, mid)
		_hline(img, 63, 46 + i * 3, 12, mid)
	# Damage patches and beacons.
	_px(img, 38, 22, SFPalette.RED)
	_px(img, 57, 40, SFPalette.RED)
	_px(img, 34, 14, hi)
	_px(img, 61, 14, hi)
	_rect(img, 47, 12, 2, 1, SFPalette.ORANGE)
	_px(img, 31, 10, SFPalette.ORANGE)
	return img


# ---------------------------------------------------------------- earth 128x128

static func _earth() -> Image:
	var img := _img(128, 128)
	var r := 58
	var cx := 64
	var cy := 64
	var rng := _rng(90210)
	var deep: Color = SFPalette.DEEP
	var blue: Color = SFPalette.BLUE
	var mid: Color = SFPalette.MID
	var sh: Color = SFPalette.SHADOW
	var green: Color = SFPalette.GREEN
	var paper: Color = SFPalette.PAPER
	var gold: Color = SFPalette.GOLD
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx: int = x - cx
			var dy: int = y - cy
			var d2: int = dx * dx + dy * dy
			if d2 > r * r:
				continue
			var lit: float = clampf((-float(dx) - float(dy)) / 130.0 + 0.55, 0.0, 1.0)
			var c := blue.lerp(deep, 1.0 - lit)
			if lit > 0.72:
				c = blue.lerp(mid, (lit - 0.72) / 0.28 * 0.8)
			_px(img, x, y, c)
	# Continents / cloud bands, dithered, only inside the disc.
	for i in 460:
		var ang: float = rng.randf() * TAU
		var rad: float = sqrt(rng.randf()) * (r - 3)
		var x: int = cx + int(cos(ang) * rad)
		var y: int = cy + int(sin(ang) * rad)
		var lit2: float = clampf((-(x - cx) - (y - cy)) / 130.0 + 0.55, 0.0, 1.0)
		if lit2 < 0.25:
			continue
		if rng.randf() < 0.055:
			_px(img, x, y, green)
		elif rng.randf() < 0.10:
			_px(img, x, y, paper)
		elif rng.randf() < 0.12:
			_px(img, x, y, gold.darkened(0.35))
	# Terminator band.
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx2: int = x - cx
			var dy2: int = y - cy
			if dx2 * dx2 + dy2 * dy2 > r * r:
				continue
			if dx2 + dy2 > 84 and (dx2 + dy2 + x + y) % 3 == 0:
				_px(img, x, y, deep)
	return img
