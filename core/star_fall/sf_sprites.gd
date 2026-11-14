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
	out["control_door"] = _tex(_control_door())
	out["shrine"] = _tex(_shrine())
	out["checkpoint"] = _tex(_checkpoint())
	out["harbor_crate"] = _tex(_harbor_crate())
	out["drum"] = _tex(_drum())
	out["pump"] = _tex(_pump())
	out["sample_point"] = _tex(_sample_point())
	out["record_terminal"] = _tex(_record_terminal())
	out["bill_phase_two"] = _tex(_bill(true))
	return out


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


## The control-center door: welded, warn, and too important to be a wall.
static func _control_door() -> Image:
	var img := _img(30, 34)
	var frame: Color = SFPalette.RUIN
	var panel: Color = SFPalette.STEEL_DARK
	var light: Color = SFPalette.STEEL_MID
	var rust: Color = SFPalette.RUST
	_rect(img, 0, 2, 30, 32, frame)
	_rect(img, 3, 5, 24, 29, panel)
	_rect(img, 3, 5, 24, 1, light)
	# Centre seam, welded over.
	_rect(img, 14, 6, 2, 28, SFPalette.INK)
	for i in 6:
		_rect(img, 13, 8 + i * 4, 4, 1, rust)
	# Hazard chevrons and a dead panel.
	_rect(img, 5, 11, 7, 9, SFPalette.INK)
	_px(img, 6, 12, SFPalette.CYAN_DARK)
	_rect(img, 19, 11, 6, 9, SFPalette.INK)
	_rect(img, 20, 13, 4, 1, SFPalette.CYAN_DIM)
	_rect(img, 20, 16, 4, 1, SFPalette.ASH)
	# Handle bar.
	_rect(img, 9, 25, 12, 2, light)
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
