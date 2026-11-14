extends RefCounted
const SFPalette := preload("res://core/starfall/sf_palette.gd")
const SFPixelFont := preload("res://core/starfall/sf_pixel_font.gd")
const SFSpriteFactory := preload("res://core/starfall/sf_sprites.gd")
const SFAudioScript := preload("res://core/starfall/sf_audio.gd")
## Drawing kit for the 480x270 pixel UI. Owns the font, the generated sprites
## and a reference to the synth. Every screen draws through this.

const VW := 480
const VH := 270

var font: SFPixelFont
var sprites: Dictionary
var audio: Node
var rng := RandomNumberGenerator.new()
var stars: Array = []
var stars_far: Array = []
var time: float = 0.0


func _init(synth) -> void:
	audio = synth
	font = SFPixelFont.new()
	sprites = SFSpriteFactory.build_all()
	rng.seed = 1337
	_build_stars()


func _build_stars() -> void:
	for i in 90:
		stars.append({
			"p": Vector2(rng.randi_range(0, VW - 1), rng.randi_range(0, VH - 1)),
			"c": SFPalette.STAR_DIM if rng.randf() < 0.7 else SFPalette.STAR_BRIGHT,
		})
	for i in 70:
		stars_far.append(Vector2(rng.randi_range(0, VW - 1), rng.randi_range(0, VH - 1)))


func tick(delta: float) -> void:
	time += delta


# ---------------------------------------------------------------- primitives

func text(ci: CanvasItem, pos: Vector2, s: String, c: Color = SFPalette.PAPER, scale: int = 1) -> void:
	font.draw_text(ci, pos, s, c, scale)


func text_c(ci: CanvasItem, cx: float, y: float, s: String, c: Color = SFPalette.PAPER, scale: int = 1) -> void:
	font.draw_centered(ci, cx, y, s, c, scale)


func text_r(ci: CanvasItem, rx: float, y: float, s: String, c: Color = SFPalette.PAPER, scale: int = 1) -> void:
	font.draw_text(ci, Vector2(rx - font.text_width(s, scale), y), s, c, scale)


func wrap(ci: CanvasItem, pos: Vector2, width: float, s: String, c: Color = SFPalette.PAPER, scale: int = 1, max_lines: int = 99) -> float:
	var lines: Array = font.wrap(s, width, scale)
	var y := pos.y
	var n := 0
	for line in lines:
		if n >= max_lines:
			break
		font.draw_text(ci, Vector2(pos.x, y), String(line), c, scale)
		y += font.line_height(scale) + 3 * scale
		n += 1
	return y


func rect(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position.round(), r.size.round()), c, true)


func frame(ci: CanvasItem, r: Rect2, c: Color, thickness: int = 1) -> void:
	var rr := Rect2(r.position.round(), r.size.round())
	ci.draw_rect(rr, c, false, float(thickness))


func panel(ci: CanvasItem, r: Rect2, fill: Color = SFPalette.NIGHT, border: Color = SFPalette.SHADOW, accent: bool = false) -> void:
	rect(ci, r, fill)
	frame(ci, r, border)
	if accent:
		var rr := Rect2(r.position.round(), r.size.round())
		ci.draw_rect(Rect2(rr.position, Vector2(rr.size.x, 1)), SFPalette.CYAN, true)


func bar(ci: CanvasItem, pos: Vector2, size: Vector2, ratio: float, c: Color, back: Color = SFPalette.DEEP) -> void:
	var p := pos.round()
	var s := size.round()
	ci.draw_rect(Rect2(p, s), back, true)
	var w: float = round(s.x * clampf(ratio, 0.0, 1.0))
	if w > 0.0:
		ci.draw_rect(Rect2(p, Vector2(w, s.y)), c, true)
	ci.draw_rect(Rect2(p, s), SFPalette.SHADOW, false, 1.0)


## Labelled resource bar used across HUD and station screens.
func stat_bar(ci: CanvasItem, pos: Vector2, label: String, value: float, total: float, c: Color, width: float = 84.0, suffix: String = "") -> void:
	text(ci, pos, label, SFPalette.MID)
	bar(ci, pos + Vector2(34, -1), Vector2(width, 7), value / maxf(1.0, total), c)
	var label_txt := "%d" % int(round(value)) if suffix == "" else "%d%s" % [int(round(value)), suffix]
	text_r(ci, pos.x + 34 + width - 2 + 40, pos.y, label_txt, SFPalette.PAPER)


func key_hint(ci: CanvasItem, pos: Vector2, key: String, label: String, c: Color = SFPalette.MID) -> float:
	var w := maxf(11.0, font.text_width(key) + 5)
	panel(ci, Rect2(pos, Vector2(w, 10)), SFPalette.DEEP, SFPalette.SHADOW)
	text_c(ci, pos.x + w * 0.5, pos.y + 2, key, SFPalette.CYAN)
	text(ci, pos + Vector2(w + 4, 2), label, c)
	return w + 6 + font.text_width(label)


func button(ci: CanvasItem, r: Rect2, label: String, focused: bool, enabled: bool = true) -> void:
	var fill := SFPalette.SHADOW if focused else SFPalette.NIGHT
	var border := SFPalette.CYAN if focused else SFPalette.SHADOW
	var tc := SFPalette.PAPER
	if not enabled:
		fill = SFPalette.NIGHT
		border = SFPalette.SHADOW.darkened(0.3)
		tc = SFPalette.MID.darkened(0.2)
	rect(ci, r, fill)
	frame(ci, r, border)
	if focused and enabled:
		ci.draw_rect(Rect2(r.position.round() + Vector2(1, 1), Vector2(r.size.x - 2, 1)), SFPalette.CYAN_DIM, true)
	text_c(ci, r.position.x + r.size.x * 0.5, r.position.y + (r.size.y - 7) * 0.5, label, tc)


func tag(ci: CanvasItem, r: Rect2, label: String, c: Color) -> void:
	rect(ci, r, SFPalette.DEEP)
	frame(ci, r, c)
	text_c(ci, r.position.x + r.size.x * 0.5, r.position.y + (r.size.y - 7) * 0.5, label, c)


func starfield(ci: CanvasItem, drift: Vector2 = Vector2.ZERO) -> void:
	ci.draw_rect(Rect2(0, 0, VW, VH), SFPalette.DEEP, true)
	# Sparse second tone band, matching the two background colors.
	for i in 6:
		var band_y: float = float(int((i * 53) + 11) % VH)
		ci.draw_rect(Rect2(0, band_y, VW, 1), SFPalette.NIGHT, true)
	for p in stars_far:
		var raw: Vector2 = (p as Vector2) + drift * 0.35
		var fp := Vector2(fmod(raw.x, VW), fmod(raw.y, VH))
		ci.draw_rect(Rect2(fp.floor(), Vector2(1, 1)), SFPalette.NIGHT.lightened(0.14), true)
	for sd in stars:
		var sdd: Dictionary = sd as Dictionary
		var sp: Vector2 = (sdd["p"] as Vector2) + drift
		sp = Vector2(fmod(sp.x, VW), fmod(sp.y, VH))
		ci.draw_rect(Rect2(sp.floor(), Vector2(1, 1)), sdd["c"] as Color, true)


func scanlines(ci: CanvasItem, alpha: float = 0.05) -> void:
	var c := Color(0, 0, 0, alpha)
	var y := 0.0
	while y < VH:
		ci.draw_rect(Rect2(0, y, VW, 1), c, true)
		y += 2.0


func vignette(ci: CanvasItem) -> void:
	# Cheaper than a shader: a few dark edge strips.
	var c1 := Color(0, 0, 0, 0.16)
	ci.draw_rect(Rect2(0, 0, VW, 6), c1, true)
	ci.draw_rect(Rect2(0, VH - 6, VW, 6), c1, true)
	ci.draw_rect(Rect2(0, 0, 3, VH), c1, true)
	ci.draw_rect(Rect2(VW - 3, 0, 3, VH), c1, true)
