extends RefCounted
const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFPixelFont := preload("res://core/star_fall/sf_pixel_font.gd")
const SFSpriteFactory := preload("res://core/star_fall/sf_sprites.gd")
## Drawing kit for the 640x360 pixel presentation. Owns the font, the generated
## sprites and the synth reference. Every screen draws through this.

const VW := 640
const VH := 360

var font: SFPixelFont
var sprites: Dictionary
var audio: Node
var time: float = 0.0
var rng := RandomNumberGenerator.new()


func _init(synth) -> void:
	audio = synth
	font = SFPixelFont.new()
	sprites = SFSpriteFactory.build_all()
	rng.seed = 20261114


func tick(delta: float) -> void:
	time += delta


# ---------------------------------------------------------------- text

func text(ci: CanvasItem, pos: Vector2, s: String, c: Color = SFPalette.PAPER, scale: int = 1) -> void:
	font.draw_text(ci, pos, s, c, scale)


func text_c(ci: CanvasItem, cx: float, y: float, s: String, c: Color = SFPalette.PAPER, scale: int = 1) -> void:
	font.draw_centered(ci, cx, y, s, c, scale)


func text_r(ci: CanvasItem, rx: float, y: float, s: String, c: Color = SFPalette.PAPER, scale: int = 1) -> void:
	font.draw_right(ci, rx, y, s, c, scale)


## Draws wrapped text and returns the y below the last line drawn.
func wrap(ci: CanvasItem, pos: Vector2, width: float, s: String, c: Color = SFPalette.PAPER, scale: int = 1, max_lines: int = 99, line_gap: int = 3) -> float:
	var lines: Array = font.wrap(s, width, scale)
	var y := pos.y
	var n := 0
	for line in lines:
		if n >= max_lines:
			break
		font.draw_text(ci, Vector2(pos.x, y), String(line), c, scale)
		y += font.line_height(scale) + line_gap
		n += 1
	return y


## How many lines will `wrap()` use for this text at this width.
func wrap_line_count(s: String, width: float, scale: int = 1) -> int:
	return font.wrap(s, width, scale).size()


# ---------------------------------------------------------------- shapes

func rect(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position.round(), r.size.round()), c, true)


func frame(ci: CanvasItem, r: Rect2, c: Color, thickness: int = 1) -> void:
	ci.draw_rect(Rect2(r.position.round(), r.size.round()), c, false, float(thickness))


func panel(ci: CanvasItem, r: Rect2, fill: Color = SFPalette.INK, border: Color = SFPalette.STEEL_DARK, accent: bool = false) -> void:
	rect(ci, r, fill)
	frame(ci, r, border)
	if accent:
		var rr := Rect2(r.position.round(), r.size.round())
		ci.draw_rect(Rect2(rr.position, Vector2(rr.size.x, 1)), SFPalette.CYAN, true)


func bar(ci: CanvasItem, pos: Vector2, size: Vector2, ratio: float, c: Color, back: Color = SFPalette.INK) -> void:
	var p := pos.round()
	var s := size.round()
	ci.draw_rect(Rect2(p, s), back, true)
	var w: float = round(s.x * clampf(ratio, 0.0, 1.0))
	if w > 0.0:
		ci.draw_rect(Rect2(p, Vector2(w, s.y)), c, true)
	ci.draw_rect(Rect2(p, s), SFPalette.STEEL_DARK, false, 1.0)


func stat_row(ci: CanvasItem, pos: Vector2, label: String, value: String, value_color: Color = SFPalette.PAPER, width: float = 180.0) -> void:
	text(ci, pos, label, SFPalette.PAPER_DIM)
	text_r(ci, pos.x + width, pos.y, value, value_color)


func key_hint(ci: CanvasItem, pos: Vector2, key: String, label: String, c: Color = SFPalette.PAPER_DIM) -> float:
	var w := maxf(11.0, font.text_width(key) + 6)
	panel(ci, Rect2(pos, Vector2(w, 11)), SFPalette.RUIN_DARK, SFPalette.STEEL_DARK)
	text_c(ci, pos.x + w * 0.5, pos.y + 2, key, SFPalette.CYAN)
	text(ci, pos + Vector2(w + 5, 2), label, c)
	return w + 7 + font.text_width(label)


func button(ci: CanvasItem, r: Rect2, label: String, focused: bool, enabled: bool = true, accent: Color = SFPalette.CYAN) -> void:
	var fill := SFPalette.RUIN if focused else SFPalette.RUIN_DARK
	var border := accent if focused else SFPalette.STEEL_DARK
	var tc := SFPalette.PAPER
	if not enabled:
		fill = SFPalette.RUIN_DARK
		border = SFPalette.STEEL_DARK.darkened(0.25)
		tc = SFPalette.PAPER_DIM.darkened(0.25)
	rect(ci, r, fill)
	frame(ci, r, border)
	if focused and enabled:
		ci.draw_rect(Rect2(r.position.round() + Vector2(1, 1), Vector2(r.size.x - 2, 1)), accent, true)
	text_c(ci, r.position.x + r.size.x * 0.5, r.position.y + (r.size.y - 7) * 0.5, label, tc)


## Small coloured badge used for slot states, costs and quest flags.
func tag(ci: CanvasItem, r: Rect2, label: String, c: Color) -> void:
	rect(ci, r, SFPalette.INK)
	frame(ci, r, c)
	text_c(ci, r.position.x + r.size.x * 0.5, r.position.y + (r.size.y - 7) * 0.5, label, c)


func divider(ci: CanvasItem, y: float, color: Color = SFPalette.STEEL_DARK, inset: float = 0.0) -> void:
	ci.draw_rect(Rect2(inset, round(y), VW - inset * 2.0, 1), color, true)


## Soft contact shadow under a character or prop. Keeps the Y-sorted world
## readable without a lighting pass.
func contact_shadow(ci: CanvasItem, center: Vector2, width: float, alpha: float = 0.22) -> void:
	var w: float = round(width)
	var h: float = maxf(1.0, round(width * 0.28))
	var r := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	ci.draw_rect(r, Color(0, 0, 0, alpha * 0.55), true)
	ci.draw_rect(Rect2(r.position + Vector2(1, 0), Vector2(maxf(1.0, r.size.x - 2), r.size.y)), Color(0, 0, 0, alpha), true)


## Draws a sprite anchored so (pos) is its ground-contact point.
func sprite_grounded(ci: CanvasItem, tex: Texture2D, pos: Vector2, tint: Color = Color.WHITE) -> void:
	var size := tex.get_size()
	ci.draw_texture_rect(tex, Rect2(pos.x - size.x * 0.5, pos.y - size.y, size.x, size.y), false, tint)


func scanlines(ci: CanvasItem, alpha: float = 0.04) -> void:
	var c := Color(0, 0, 0, alpha)
	var y := 0.0
	while y < VH:
		ci.draw_rect(Rect2(0, y, VW, 1), c, true)
		y += 2.0


func vignette(ci: CanvasItem) -> void:
	var c1 := Color(0, 0, 0, 0.18)
	ci.draw_rect(Rect2(0, 0, VW, 8), c1, true)
	ci.draw_rect(Rect2(0, VH - 8, VW, 8), c1, true)
	ci.draw_rect(Rect2(0, 0, 4, VH), c1, true)
	ci.draw_rect(Rect2(VW - 4, 0, 4, VH), c1, true)


## Full-screen dim used behind modal panels.
func dim(ci: CanvasItem, alpha: float = 0.62) -> void:
	ci.draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.05, 0.05, alpha), true)
