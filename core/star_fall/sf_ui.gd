extends RefCounted
const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFDialogue := preload("res://core/star_fall/sf_dialogue.gd")
## Shared UI drawing: header bars, dialogue boxes, HUD, toasts and modal
## frames. Pure drawing helpers over a skin object; no state of its own beyond
## a toast timer, which the owning screen ticks.

var skin
var toast_text: String = ""
var toast_tone: String = "info"
var toast_timer: float = 0.0


func _init(skin_ref) -> void:
	skin = skin_ref


func notify(text: String, tone: String = "info", seconds: float = 2.2) -> void:
	toast_text = text
	toast_tone = tone
	toast_timer = seconds
	if skin != null and skin.audio != null and skin.audio.has_method("sfx_toast"):
		skin.audio.sfx_toast()


## Drops any pending toast. Called when the screen changes, so a notice from
## one screen never bleeds into the next.
func clear_toast() -> void:
	toast_timer = 0.0
	toast_text = ""


func tick(delta: float) -> void:
	if toast_timer > 0.0:
		toast_timer = maxf(0.0, toast_timer - delta)


func toast_color() -> Color:
	match toast_tone:
		"warn":
			return SFPalette.GOLD
		"bad":
			return SFPalette.RED
		"good":
			return SFPalette.GREEN_OK
		"salvage":
			return SFPalette.CYAN
	return SFPalette.PAPER


## Header strip with a title, a subtitle and an optional right-hand block.
func header(ci: CanvasItem, title: String, subtitle: String = "", right_lines: Array = [], dark: bool = true) -> void:
	var fill: Color = SFPalette.INK if dark else SFPalette.RUIN_DARK
	ci.draw_rect(Rect2(0, 0, 640, 26), fill, true)
	ci.draw_rect(Rect2(0, 26, 640, 1), SFPalette.STEEL_DARK, true)
	skin.text(ci, Vector2(12, 6), title, SFPalette.CYAN)
	if subtitle != "":
		skin.text(ci, Vector2(12, 16), subtitle, SFPalette.PAPER_DIM)
	var y := 4.0
	for line in right_lines:
		skin.text_r(ci, 628, y, String(line), SFPalette.PAPER_DIM)
		y += 9.0


## Footer strip of keyboard hints. Hints that would run past the edge move to
## a second row, so no label is ever clipped or overlapped.
func footer(ci: CanvasItem, hints: Array) -> void:
	var top: float = 336.0
	ci.draw_rect(Rect2(0, top, 640, 24), SFPalette.INK, true)
	ci.draw_rect(Rect2(0, top, 640, 1), SFPalette.STEEL_DARK, true)
	var x := 10.0
	var y := top + 5.0
	for h in hints:
		var parts := String(h).split(":", true, 1)
		if parts.size() < 2:
			continue
		var key := parts[0].strip_edges()
		var label := parts[1].strip_edges()
		var width: float = maxf(11.0, skin.font.text_width(key) + 6) + 7.0 + skin.font.text_width(label) + 12.0
		if x + width > 632.0:
			if y + 12.0 > top + 23.0:
				break
			x = 10.0
			y += 11.0
		x += skin.key_hint(ci, Vector2(x, y), key, label) + 6.0


## Draws a dialogue box with the current line and a prompt. Returns nothing:
## the caller owns the dialogue model and advances it.
func dialogue_box(ci: CanvasItem, dialogue, speaker_hint: String = "") -> void:
	var box := Rect2(28, 246, 584, 88)
	ci.draw_rect(box, Color(0.04, 0.07, 0.08, 0.94), true)
	ci.draw_rect(box, SFPalette.CYAN_DIM, false, 1.0)
	ci.draw_rect(Rect2(box.position + Vector2(0, 0), Vector2(box.size.x, 1)), SFPalette.CYAN, true)
	if speaker_hint != "":
		skin.text(ci, box.position + Vector2(8, 5), speaker_hint, SFPalette.CYAN)
	var body_y := box.position.y + (18.0 if speaker_hint != "" else 8.0)
	skin.wrap(ci, Vector2(box.position.x + 10, body_y), box.size.x - 20, dialogue.visible_text(), SFPalette.PAPER, 1, 4)

	var p := Rect2(box.position.x + box.size.x - 74, box.end.y - 14, 66, 10)
	var label: String = "ENTER"
	if dialogue.is_last_line() and dialogue.is_line_complete():
		label = "ENTER"
	ci.draw_rect(p, SFPalette.RUIN, true)
	ci.draw_rect(p, SFPalette.CYAN_DIM, false, 1.0)
	skin.text_c(ci, p.position.x + p.size.x * 0.5, p.position.y + 2, label, SFPalette.CYAN)
	# Page dots.
	var dots: int = dialogue.lines.size()
	var dx := box.position.x + 10.0
	for i in dots:
		var c: Color = SFPalette.CYAN if i <= dialogue.index else SFPalette.STEEL_DARK
		ci.draw_rect(Rect2(dx + i * 5.0, box.end.y - 12, 3, 3), c, true)

	# Prompt hint for the very first line.
	if dialogue.index == 0 and dialogue.is_line_complete():
		skin.text_r(ci, box.end.x - 82, box.end.y - 12, "E OR ENTER", SFPalette.PAPER_DIM)


func hud(ci: CanvasItem, campaign, objective: String, inventory_rows: Array, zone_title: String = "") -> void:
	# Objective strip, top left.
	var w: float = clampf(skin.font.text_width(objective) + 20.0, 120.0, 400.0)
	ci.draw_rect(Rect2(8, 8, w, 16), Color(0.04, 0.07, 0.08, 0.78), true)
	ci.draw_rect(Rect2(8, 8, 3, 16), SFPalette.CYAN, true)
	skin.text(ci, Vector2(16, 13), objective, SFPalette.PAPER)

	# Zone title, top right.
	if zone_title != "":
		var zw: float = skin.font.text_width(zone_title) + 16.0
		ci.draw_rect(Rect2(632 - zw, 8, zw, 15), Color(0.04, 0.07, 0.08, 0.65), true)
		skin.text_r(ci, 626, 12, zone_title, SFPalette.PAPER_DIM)

	# Inventory strip, bottom left.
	if not inventory_rows.is_empty():
		var ih: float = 13.0 + float(inventory_rows.size()) * 11.0
		ci.draw_rect(Rect2(8, 336 - ih, 132, ih), Color(0.04, 0.07, 0.08, 0.72), true)
		skin.text(ci, Vector2(14, 336 - ih + 4), "CARRY %d/%d" % [campaign.inventory_used(), campaign.inventory_limit()], SFPalette.PAPER_DIM)
		var y := 336 - ih + 16
		for row in inventory_rows:
			skin.text(ci, Vector2(14, y), String(row), SFPalette.PAPER)
			y += 11.0


## Bottom-centre interaction prompt.
func prompt(ci: CanvasItem, text: String, blink: float) -> void:
	if text == "":
		return
	var w: float = skin.font.text_width(text) + 34.0
	var r := Rect2(320 - w * 0.5, 296, w, 17)
	ci.draw_rect(r, Color(0.04, 0.07, 0.08, 0.86), true)
	ci.draw_rect(r, SFPalette.CYAN_DIM, false, 1.0)
	var pulse := 0.7 + 0.3 * sin(blink * 4.0)
	skin.text(ci, Vector2(r.position.x + 6, r.position.y + 5), "E", Color(SFPalette.CYAN.r, SFPalette.CYAN.g, SFPalette.CYAN.b, pulse))
	skin.text(ci, Vector2(r.position.x + 16, r.position.y + 5), text, SFPalette.PAPER)


func toast(ci: CanvasItem) -> void:
	if toast_timer <= 0.0 or toast_text == "":
		return
	var a: float = clampf(toast_timer, 0.0, 1.0)
	var c := toast_color()
	c.a = a
	var w: float = skin.font.text_width(toast_text) + 16.0
	var r := Rect2(320 - w * 0.5, 268, w, 15)
	ci.draw_rect(r, Color(0.04, 0.07, 0.08, 0.9 * a), true)
	ci.draw_rect(r, Color(c.r, c.g, c.b, a * 0.8), false, 1.0)
	skin.text_c(ci, 320, 272, toast_text, c)


## Modal frame that dims the scene behind it. Returns the inner content rect.
func modal(ci: CanvasItem, rect: Rect2, accent: Color = SFPalette.CYAN) -> Rect2:
	ci.draw_rect(Rect2(0, 0, 640, 360), Color(0.02, 0.05, 0.05, 0.72), true)
	ci.draw_rect(rect, Color(0.06, 0.10, 0.11, 0.98), true)
	ci.draw_rect(rect, accent, false, 1.0)
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), accent, true)
	return Rect2(rect.position + Vector2(10, 10), rect.size - Vector2(20, 20))


## A small vertical menu drawn inside a panel. Returns the item rects.
func menu_list(ci: CanvasItem, menu, origin: Vector2, width: float, row_h: float = 18.0, accent: Color = SFPalette.CYAN) -> Array:
	var rects: Array = []
	for i in menu.items.size():
		var item: Dictionary = menu.items[i] as Dictionary
		var r := Rect2(origin.x, origin.y + float(i) * row_h, width, row_h - 2)
		var focused: bool = i == menu.index
		var enabled: bool = bool(item.get("enabled", true))
		skin.button(ci, r, String(item.get("label", "")), focused, enabled, accent)
		var detail := String(item.get("detail", ""))
		if detail != "" and focused:
			skin.text_r(ci, origin.x + width - 6, r.position.y + 5, detail, SFPalette.PAPER_DIM)
		rects.append(r)
	return rects


## Wrapped paragraph block. Returns the y below the text.
func paragraph(ci: CanvasItem, pos: Vector2, width: float, text: String, color: Color = SFPalette.PAPER, max_lines: int = 6) -> float:
	return skin.wrap(ci, pos, width, text, color, 1, max_lines)


## A labelled number row: label on the left, value right-aligned.
func value_row(ci: CanvasItem, pos: Vector2, label: String, value: String, width: float, good: bool = true) -> void:
	skin.text(ci, pos, label, SFPalette.PAPER_DIM)
	var c: Color = SFPalette.PAPER if good else SFPalette.RED
	skin.text_r(ci, pos.x + width, pos.y, value, c)


## The vocabulary journal: a list of learned words on the left and the selected
## entry's definition, example and note on the right. `entries` are vocabulary
## dictionaries in the order they were learned. Shared by the paused typing
## encounter and the exploration pause menu, so both read the same way.
func journal_panel(ci: CanvasItem, entries: Array, index: int, footer_hint: String = "UP/DOWN  BROWSE     ESC  BACK") -> void:
	var panel := Rect2(40, 34, 560, 292)
	modal(ci, panel, SFPalette.GREEN_OK)
	skin.text(ci, panel.position + Vector2(14, 10), "VOCABULARY JOURNAL", SFPalette.GREEN_OK)
	skin.text_r(ci, panel.end.x - 14, panel.position.y + 10, "%d WORDS LEARNED" % entries.size(), SFPalette.PAPER_DIM)
	if entries.is_empty():
		skin.wrap(ci, panel.position + Vector2(14, 40), panel.size.x - 28,
			"No words yet. Every word you type at the Dawn Tower is recorded here with its meaning.",
			SFPalette.PAPER, 1, 4)
		skin.text_c(ci, panel.position.x + panel.size.x * 0.5, panel.end.y - 14, footer_hint, SFPalette.PAPER_DIM)
		return
	var sel := clampi(index, 0, entries.size() - 1)
	# Word list: a scrolling window that keeps the selection visible.
	var rows := 14
	var first := clampi(sel - rows / 2, 0, maxi(0, entries.size() - rows))
	var list := Rect2(panel.position.x + 10, panel.position.y + 28, 150, panel.size.y - 52)
	ci.draw_rect(list, Color(0.03, 0.06, 0.06, 0.9), true)
	for i in range(first, mini(entries.size(), first + rows)):
		var e: Dictionary = entries[i]
		var y := list.position.y + 4.0 + float(i - first) * 16.0
		if i == sel:
			ci.draw_rect(Rect2(list.position.x + 2, y - 2, list.size.x - 4, 13), SFPalette.CYAN_DARK, true)
		skin.text(ci, Vector2(list.position.x + 8, y + 1), String(e.get("text", "")), SFPalette.PAPER if i == sel else SFPalette.PAPER_DIM)
	# Detail.
	var d: Dictionary = entries[sel]
	var dx := list.end.x + 14.0
	var dw := panel.end.x - dx - 14.0
	var y2 := panel.position.y + 32.0
	skin.text(ci, Vector2(dx, y2), String(d.get("text", "")).to_upper(), SFPalette.PAPER, 2)
	y2 += 22.0
	skin.text(ci, Vector2(dx, y2), "%s  /  %s" % [String(d.get("category", "")).to_upper(), String(d.get("band", "")).to_upper()], SFPalette.CYAN_DIM)
	y2 += 18.0
	skin.text(ci, Vector2(dx, y2), "MEANING", SFPalette.GOLD)
	y2 = skin.wrap(ci, Vector2(dx, y2 + 12.0), dw, String(d.get("definition", "")), SFPalette.PAPER, 1, 4) + 8.0
	skin.text(ci, Vector2(dx, y2), "EXAMPLE", SFPalette.GOLD)
	y2 = skin.wrap(ci, Vector2(dx, y2 + 12.0), dw, String(d.get("example", "")), SFPalette.PAPER_DIM, 1, 3) + 8.0
	var note := String(d.get("note", ""))
	if note != "":
		skin.text(ci, Vector2(dx, y2), "WHY IT MATTERS", SFPalette.GOLD)
		skin.wrap(ci, Vector2(dx, y2 + 12.0), dw, note, SFPalette.PAPER_DIM, 1, 3)
	skin.text_c(ci, panel.position.x + panel.size.x * 0.5, panel.end.y - 14, footer_hint, SFPalette.PAPER_DIM)
