extends RefCounted
## Hand-built 5x7 bitmap font, baked into a 1px atlas at startup and drawn as
## unscaled texture regions. No font files, so text stays pixel-crisp.

const GW := 5
const GH := 7
const CW := 6
const CH := 8

const GLYPHS := {
	" ": [0, 0, 0, 0, 0, 0, 0],
	"A": [14, 17, 17, 31, 17, 17, 17],
	"B": [30, 17, 17, 30, 17, 17, 30],
	"C": [14, 17, 16, 16, 16, 17, 14],
	"D": [30, 17, 17, 17, 17, 17, 30],
	"E": [31, 16, 16, 30, 16, 16, 31],
	"F": [31, 16, 16, 30, 16, 16, 16],
	"G": [14, 17, 16, 23, 17, 17, 15],
	"H": [17, 17, 17, 31, 17, 17, 17],
	"I": [14, 4, 4, 4, 4, 4, 14],
	"J": [7, 2, 2, 2, 2, 18, 12],
	"K": [17, 18, 20, 24, 20, 18, 17],
	"L": [16, 16, 16, 16, 16, 16, 31],
	"M": [17, 27, 21, 21, 17, 17, 17],
	"N": [17, 25, 21, 19, 17, 17, 17],
	"O": [14, 17, 17, 17, 17, 17, 14],
	"P": [30, 17, 17, 30, 16, 16, 16],
	"Q": [14, 17, 17, 17, 21, 18, 13],
	"R": [30, 17, 17, 30, 20, 18, 17],
	"S": [15, 16, 16, 14, 1, 1, 30],
	"T": [31, 4, 4, 4, 4, 4, 4],
	"U": [17, 17, 17, 17, 17, 17, 14],
	"V": [17, 17, 17, 17, 17, 10, 4],
	"W": [17, 17, 17, 21, 21, 27, 10],
	"X": [17, 17, 10, 4, 10, 17, 17],
	"Y": [17, 17, 10, 4, 4, 4, 4],
	"Z": [31, 1, 2, 4, 8, 16, 31],
	"a": [0, 0, 14, 1, 15, 17, 15],
	"b": [16, 16, 30, 17, 17, 17, 30],
	"c": [0, 0, 14, 17, 16, 17, 14],
	"d": [1, 1, 15, 17, 17, 17, 15],
	"e": [0, 0, 14, 17, 31, 16, 14],
	"f": [6, 9, 8, 28, 8, 8, 8],
	"g": [0, 15, 17, 17, 17, 15, 1],
	"h": [16, 16, 30, 17, 17, 17, 17],
	"i": [4, 0, 12, 4, 4, 4, 14],
	"j": [2, 0, 6, 2, 2, 2, 18],
	"k": [16, 16, 18, 20, 24, 20, 18],
	"l": [12, 4, 4, 4, 4, 4, 14],
	"m": [0, 0, 26, 21, 21, 21, 17],
	"n": [0, 0, 30, 17, 17, 17, 17],
	"o": [0, 0, 14, 17, 17, 17, 14],
	"p": [0, 0, 30, 17, 17, 30, 16],
	"q": [0, 0, 15, 17, 17, 15, 1],
	"r": [0, 0, 22, 25, 16, 16, 16],
	"s": [0, 0, 14, 16, 14, 1, 30],
	"t": [8, 8, 28, 8, 8, 9, 6],
	"u": [0, 0, 17, 17, 17, 17, 15],
	"v": [0, 0, 17, 17, 17, 10, 4],
	"w": [0, 0, 17, 17, 21, 21, 10],
	"x": [0, 0, 17, 10, 4, 10, 17],
	"y": [0, 17, 17, 17, 15, 1, 14],
	"z": [0, 0, 31, 2, 4, 8, 31],
	"0": [14, 17, 19, 21, 25, 17, 14],
	"1": [4, 12, 4, 4, 4, 4, 14],
	"2": [14, 17, 1, 2, 4, 8, 31],
	"3": [31, 2, 4, 2, 1, 17, 14],
	"4": [2, 6, 10, 18, 31, 2, 2],
	"5": [31, 16, 30, 1, 1, 17, 14],
	"6": [6, 8, 16, 30, 17, 17, 14],
	"7": [31, 1, 2, 4, 8, 8, 8],
	"8": [14, 17, 17, 14, 17, 17, 14],
	"9": [14, 17, 17, 15, 1, 2, 12],
	".": [0, 0, 0, 0, 0, 6, 6],
	",": [0, 0, 0, 0, 6, 6, 12],
	":": [0, 6, 6, 0, 6, 6, 0],
	";": [0, 6, 6, 0, 6, 6, 12],
	"!": [4, 4, 4, 4, 4, 0, 4],
	"?": [14, 17, 1, 2, 4, 0, 4],
	"'": [4, 4, 0, 0, 0, 0, 0],
	"\"": [10, 10, 0, 0, 0, 0, 0],
	"-": [0, 0, 0, 31, 0, 0, 0],
	"_": [0, 0, 0, 0, 0, 0, 31],
	"+": [0, 4, 4, 31, 4, 4, 0],
	"=": [0, 0, 31, 0, 31, 0, 0],
	"/": [1, 2, 2, 4, 8, 8, 16],
	"\\": [16, 8, 8, 4, 2, 2, 1],
	"(": [2, 4, 8, 8, 8, 4, 2],
	")": [8, 4, 2, 2, 2, 4, 8],
	"[": [14, 8, 8, 8, 8, 8, 14],
	"]": [14, 2, 2, 2, 2, 2, 14],
	"%": [25, 1, 2, 4, 8, 16, 19],
	"*": [0, 21, 14, 31, 14, 21, 0],
	"<": [2, 4, 8, 16, 8, 4, 2],
	">": [8, 4, 2, 1, 2, 4, 8],
	"#": [10, 31, 10, 10, 31, 10, 0],
	"$": [4, 15, 20, 14, 5, 30, 4],
	"&": [12, 18, 20, 8, 21, 18, 13],
	"@": [14, 17, 23, 21, 23, 16, 14],
	"^": [4, 10, 17, 0, 0, 0, 0],
	"|": [4, 4, 4, 4, 4, 4, 4],
	"~": [0, 8, 21, 2, 0, 0, 0],
	"·": [0, 0, 6, 6, 0, 0, 0],
	"—": [0, 0, 0, 31, 0, 0, 0],
}

var _tex: ImageTexture
var _cell_of: Dictionary = {}
var _fallback: int = 0


func _init() -> void:
	_build()


func _build() -> void:
	var keys: Array = GLYPHS.keys()
	var img := Image.create(keys.size() * CW, CH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in keys.size():
		var ch: String = keys[i]
		_cell_of[ch] = i
		var rows: Array = GLYPHS[ch]
		for y in GH:
			var row_bits: int = rows[y]
			for x in GW:
				if (row_bits & (1 << (GW - 1 - x))) != 0:
					img.set_pixel(i * CW + x, y, Color(1, 1, 1, 1))
	_tex = ImageTexture.create_from_image(img)
	_fallback = _cell_of.get("?", 0)


func draw_text(ci: CanvasItem, pos: Vector2, text: String, color: Color, scale: int = 1) -> void:
	var x: float = round(pos.x)
	var y: float = round(pos.y)
	for i in text.length():
		var ch := text.substr(i, 1)
		var cell: int = _cell_of.get(ch, _fallback)
		if ch != " ":
			ci.draw_texture_rect_region(
				_tex,
				Rect2(x, y, GW * scale, GH * scale),
				Rect2(cell * CW, 0, GW, GH),
				color
			)
		x += CW * scale


func draw_centered(ci: CanvasItem, center_x: float, y: float, text: String, color: Color, scale: int = 1) -> void:
	draw_text(ci, Vector2(center_x - text_width(text, scale) * 0.5, y), text, color, scale)


func draw_right(ci: CanvasItem, right_x: float, y: float, text: String, color: Color, scale: int = 1) -> void:
	draw_text(ci, Vector2(right_x - text_width(text, scale), y), text, color, scale)


func text_width(text: String, scale: int = 1) -> float:
	return maxf(0.0, (text.length() * CW - 1) * scale)


func line_height(scale: int = 1) -> float:
	return CH * scale


## Truncates to fit max_px, ending with a period rather than a cut word.
func fit(text: String, max_px: float, scale: int = 1) -> String:
	if text_width(text, scale) <= max_px:
		return text
	var limit := maxi(0, int(max_px / (CW * scale)) - 1)
	if limit <= 0:
		return ""
	var cut := text.substr(0, limit)
	var space := cut.rfind(" ")
	if space > limit / 2:
		cut = cut.substr(0, space)
	return cut + "."


## Trims text so it occupies at most max_lines at this width. When anything is
## removed the last line ends with "..", so a clipped description never reads
## as a truncated sentence.
func clip_lines(text: String, max_px: float, max_lines: int, scale: int = 1) -> String:
	var lines: Array = self.wrap(text, max_px, scale)
	if lines.size() <= max_lines:
		return text
	var kept: Array = []
	for i in max_lines:
		kept.append(String(lines[i]))
	var last: String = String(kept[max_lines - 1])
	var limit: int = maxi(1, int(max_px / (CW * scale)) - 3)
	if last.length() > limit:
		last = last.substr(0, limit)
		var space := last.rfind(" ")
		if space > limit / 2:
			last = last.substr(0, space)
	kept[max_lines - 1] = last.strip_edges() + ".."
	return "
".join(kept)


## Greedy word wrap. Returns lines no wider than max_px.
func wrap(text: String, max_px: float, scale: int = 1) -> Array:
	var out: Array = []
	var limit := maxi(1, int(max_px / (CW * scale)))
	for paragraph in text.split("\n"):
		var words := paragraph.split(" ", false)
		var line := ""
		for w in words:
			var candidate := w if line == "" else line + " " + w
			if candidate.length() > limit:
				if line != "":
					out.append(line)
				line = w
			else:
				line = candidate
		out.append(line)
	return out
