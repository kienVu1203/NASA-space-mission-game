extends Node2D
## Archive restoration screen for the Forgotten City and the Silent Coast.
##
## The robot is defeated; this screen restores the facility's records and lets
## the player read them. The archive content comes from campaign.json, so the
## prose never lives in a script.
##
## The page flip is the only interaction: Left/Right (or A/D) moves between
## records, Enter/Esc finishes. Finishing emits `archive_closed`, and the
## controller applies the campaign outcome (the Future Earth reveal for the
## Forgotten City, the environmental lesson for the Silent Coast) exactly once,
## whether the player read every entry or none of them.
##
## Controls
##   LEFT/RIGHT (A/D)   previous / next record
##   ENTER / E / ESC    close and apply the outcome

signal archive_closed

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const VW := 640
const VH := 360

var skin
var ui
var campaign
var archive_id: String = ""
var archive: Dictionary = {}
var entries: Array = []
var index: int = 0
var closed: bool = false
var time: float = 0.0
var reveal_hold: float = 0.0

# The reveal caption shown on the last page of the city archive. It comes from
# data, never from this script: see campaign.json dialogue "city_archive_done".
var reveal_lines: Array = []


func setup(skin_ref, ui_ref, campaign_ref, id: String) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	archive_id = id


func _ready() -> void:
	archive = campaign.content.archive(archive_id)
	entries = archive.get("entries", []) as Array
	index = 0
	closed = false
	if archive_id == campaign.ARCHIVE_CITY:
		reveal_lines = campaign.content.dialogue_lines("city_archive_done")
	elif archive_id == campaign.ARCHIVE_COAST:
		reveal_lines = campaign.content.dialogue_lines("coast_archive_done")
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_LEFT, KEY_A:
			_move(-1)
		KEY_RIGHT, KEY_D:
			_move(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_ESCAPE:
			_finish()
	get_viewport().set_input_as_handled()


func _move(delta: int) -> void:
	if entries.is_empty():
		return
	var next: int = clampi(index + delta, 0, entries.size() - 1)
	if next == index:
		skin.audio.sfx_denied()
		return
	index = next
	skin.audio.sfx_select()
	queue_redraw()


## Closes the screen once. The caller applies the campaign state in response to
## the signal, so a double press cannot double-award anything.
func _finish() -> void:
	if closed:
		return
	closed = true
	skin.audio.sfx_confirm()
	queue_redraw()
	archive_closed.emit()


func _process(delta: float) -> void:
	time += delta
	reveal_hold = minf(1.0, reveal_hold + delta * 1.5)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)

	# Archive frame: a restored terminal projecting its record pages.
	_draw_projection_backdrop()

	var title := String(archive.get("title", "ARCHIVE")).to_upper()
	var subtitle := String(archive.get("subtitle", ""))
	ui.header(self, title, subtitle, ["ARCHIVE %d / %d" % [index + 1, maxi(1, entries.size())]])

	var page := Rect2(48, 40, 420, 244)
	draw_rect(page, Color(0.05, 0.09, 0.10, 0.96), true)
	draw_rect(page, SFPalette.CYAN_DIM, false, 1.0)
	draw_rect(Rect2(page.position, Vector2(page.size.x, 1)), SFPalette.CYAN, true)

	if entries.is_empty():
		skin.text(self, page.position + Vector2(16, 18), "NO RECORDS RECOVERED", SFPalette.PAPER_DIM)
	else:
		var entry: Dictionary = entries[clampi(index, 0, entries.size() - 1)]
		var heading := String(entry.get("heading", "RECORD"))
		skin.text(self, page.position + Vector2(16, 14), heading, SFPalette.CYAN)
		draw_rect(Rect2(page.position.x + 16, page.position.y + 28, page.size.x - 32, 1), SFPalette.STEEL_DARK, true)
		var y: float = page.position.y + 38
		for line in entry.get("lines", []) as Array:
			y = skin.wrap(self, Vector2(page.position.x + 16, y), page.size.x - 32, String(line), SFPalette.PAPER, 1, 5) + 6.0

	# Page list on the right, so the archive reads as a body of evidence.
	var list_x := 484.0
	skin.text(self, Vector2(list_x, 46), "RECORDS", SFPalette.PAPER_DIM)
	var ly := 60.0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var focused: bool = i == index
		var lr := Rect2(list_x, ly, 140, 22)
		draw_rect(lr, SFPalette.RUIN if focused else SFPalette.RUIN_DARK, true)
		draw_rect(lr, SFPalette.CYAN if focused else SFPalette.STEEL_DARK, false, 1.0)
		skin.text(self, Vector2(lr.position.x + 6, lr.position.y + 7), String(e.get("heading", "")).substr(0, 21), SFPalette.PAPER if focused else SFPalette.PAPER_DIM)
		ly += 25.0
		if ly > 290.0:
			break

	# Reveal strip: appears on the city archive and names what the player has
	# just understood. It is prose from data, not a HUD label.
	if not reveal_lines.is_empty() and index >= entries.size() - 1:
		var strip := Rect2(48, 292, 576, 44)
		draw_rect(strip, Color(0.06, 0.10, 0.09, 0.94 * reveal_hold), true)
		draw_rect(strip, Color(SFPalette.GOLD.r, SFPalette.GOLD.g, SFPalette.GOLD.b, 0.9 * reveal_hold), false, 1.0)
		var line := String(reveal_lines[reveal_lines.size() - 1])
		skin.wrap(self, Vector2(strip.position.x + 10, strip.position.y + 7), strip.size.x - 20, line,
			Color(SFPalette.GOLD.r, SFPalette.GOLD.g, SFPalette.GOLD.b, reveal_hold), 1, 2)

	var hints := "LEFT / RIGHT  RECORDS     ENTER  CLOSE"
	skin.text_c(self, VW * 0.5, VH - 12, hints, SFPalette.PAPER_DIM)
	ui.toast(self)
	skin.scanlines(self, 0.04)


func _draw_projection_backdrop() -> void:
	# A soft cyan cone from the bottom centre, plus file-slot ticks: the archive
	# is a restored terminal, not a floating panel.
	var flicker := 0.85 + 0.15 * sin(time * 13.0) * sin(time * 3.1)
	for i in 16:
		var t := float(i) / 16.0
		var w := 80.0 + t * 480.0
		var a := 0.03 + 0.05 * (1.0 - t) * flicker
		draw_rect(Rect2(VW * 0.5 - w * 0.5, 300 - t * 260, w, 2), Color(0.35, 0.95, 0.85, a), true)
	for i in 40:
		var x := float((i * 89) % VW)
		var y := float((i * 53) % VH)
		draw_rect(Rect2(x, y, 1, 1), Color(0.3, 0.7, 0.65, 0.10), true)
