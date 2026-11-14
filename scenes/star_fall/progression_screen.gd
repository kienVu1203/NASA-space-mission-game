extends Node2D
## Screen for the two campaign outcomes that are not exploration and not combat:
## the crash-site base return after the Silent Coast, and the Phase 2 summary.
##
## It is a readout screen: it shows the recovered components in the campaign's
## repair/progression interface and the unlocked next chapter. It owns no state;
## the controller passes in what to display and the screen reports when the
## player is done.
##
## Controls
##   ENTER / E / ESC   continue

signal closed

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const VW := 640
const VH := 360

var skin
var ui
var campaign
var mode: String = "base_return"
var lines: Array = []
var time: float = 0.0
var closed_once: bool = false


func setup(skin_ref, ui_ref, campaign_ref, screen_mode: String) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	mode = screen_mode


func _ready() -> void:
	if mode == "phase_two_complete":
		lines = campaign.content.dialogue_lines("phase_two_complete")
	else:
		lines = campaign.content.dialogue_lines("base_return")
	closed_once = false
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER \
			or key_event.keycode == KEY_E or key_event.keycode == KEY_SPACE \
			or key_event.keycode == KEY_ESCAPE:
		if closed_once:
			return
		closed_once = true
		skin.audio.sfx_confirm()
		closed.emit()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.RUIN_BG, true)
	_draw_base_backdrop()

	var title := "CRASH-SITE BASE" if mode != "phase_two_complete" else "PHASE 2 COMPLETE"
	var subtitle := "VELA repair interface" if mode != "phase_two_complete" else "Two components recovered"
	ui.header(self, title, subtitle, [campaign.mission_name().to_upper()])

	# Left: the VELA frame and what is now fitted to it.
	_draw_frame_panel(Rect2(28, 44, 240, 244))
	# Right: progression list.
	_draw_progress_panel(Rect2(292, 44, 320, 244))

	# Bill's line, drawn as prose rather than as a HUD label.
	var y := 296.0
	for i in mini(2, lines.size()):
		y = skin.wrap(self, Vector2(28, y), VW - 56, String(lines[i]), SFPalette.PAPER, 1, 2) + 3.0

	skin.text_c(self, VW * 0.5, VH - 12, "ENTER  CONTINUE", SFPalette.GOLD)
	ui.toast(self)


func _draw_base_backdrop() -> void:
	# A dark hangar with an open sky slot: the wreck is home base now.
	draw_rect(Rect2(0, 0, VW, 120), SFPalette.INK.lerp(SFPalette.SKY_DEEP, 0.18), true)
	var g := 0
	while g < 12:
		var t := float(g) / 12.0
		draw_rect(Rect2(0, 120 + g * 8, VW, 8), SFPalette.RUIN_BG.lerp(SFPalette.RUIN_DARK, t), true)
		g += 1
	draw_rect(Rect2(0, 216, VW, VH - 216), SFPalette.RUIN, true)
	draw_rect(Rect2(0, 216, VW, 2), SFPalette.ASH.darkened(0.35), true)
	# Floor grid, receding.
	var fy := 226.0
	var step := 4.0
	while fy < VH:
		draw_rect(Rect2(0, round(fy), VW, 1), SFPalette.RUIN_DARK, true)
		fy += step
		step += 0.9
	# Work lights.
	for i in 5:
		var lx := 64.0 + float(i) * 128.0
		draw_rect(Rect2(lx - 1, 0, 2, 24), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(lx - 5, 24, 10, 3), SFPalette.WARM_DARK, true)
		var flicker := 0.5 + 0.12 * sin(time * 2.0 + float(i))
		draw_rect(Rect2(lx - 22, 27, 44, 2), Color(0.95, 0.88, 0.70, 0.10 * flicker), true)
	# The wreck, small, inside the bay.
	_draw_vela_frame(Vector2(148, 214), 1.0)


func _draw_frame_panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0.04, 0.07, 0.08, 0.92), true)
	draw_rect(rect, SFPalette.CYAN_DIM, false, 1.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), SFPalette.CYAN, true)
	skin.text(self, rect.position + Vector2(10, 8), "VELA / RECOVERY FRAME", SFPalette.CYAN)
	skin.text_r(self, rect.end.x - 10, rect.position.y + 8, "DAMAGED", SFPalette.RUST_LIGHT)

	# The ship drawing grows with each recovered component.
	var recovered_count := 0
	for entry in campaign.component_status():
		if bool(entry.get("recovered", false)):
			recovered_count += 1

	_draw_vela_frame(Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 150), 1.6, recovered_count)

	# Fit status under the drawing.
	var fy := rect.end.y - 52
	for entry in campaign.component_status():
		var comp: Dictionary = entry
		var recovered: bool = bool(comp.get("recovered", false))
		var name := String(comp.get("name", comp.get("id", "")))
		var c: Color = SFPalette.GREEN_OK if recovered else SFPalette.PAPER_DIM
		draw_rect(Rect2(rect.position.x + 12, fy + 2, 5, 5), c, true)
		skin.text(self, Vector2(rect.position.x + 24, fy), name.to_upper(), c)
		skin.text_r(self, rect.end.x - 12, fy, "FITTED" if recovered else "MISSING", c)
		fy += 15.0


func _draw_progress_panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0.04, 0.07, 0.08, 0.92), true)
	draw_rect(rect, SFPalette.CYAN_DIM, false, 1.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), SFPalette.CYAN, true)
	skin.text(self, rect.position + Vector2(10, 8), "PROGRESSION", SFPalette.CYAN)

	var y := rect.position.y + 26.0
	# Mission.
	skin.text(self, Vector2(rect.position.x + 12, y), "MISSION", SFPalette.PAPER_DIM)
	skin.text_r(self, rect.end.x - 12, y, campaign.mission_name().to_upper(), SFPalette.GOLD)
	y += 20.0

	# Chapters: which are done, which is next.
	var rows: Array = [
		{"label": "CRASH SITE", "done": campaign.has_flag(SFCampaign.FLAG_BILL_ACTIVE), "note": "done" if campaign.has_flag(SFCampaign.FLAG_BILL_ACTIVE) else "open"},
		{"label": "FORGOTTEN CITY", "done": campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED), "note": "cleared" if campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED) else "locked"},
		{"label": "SILENT COAST", "done": campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED), "note": "cleared" if campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED) else ("unlocked" if campaign.has_flag(SFCampaign.FLAG_SILENT_COAST_UNLOCKED) else "locked")},
		{"label": "DAWN TOWER", "done": false, "note": "unlocked" if campaign.has_flag(SFCampaign.FLAG_DAWN_TOWER_UNLOCKED) else "locked"},
	]
	for r in rows:
		var row: Dictionary = r
		var c2: Color = SFPalette.GREEN_OK if bool(row["done"]) else (SFPalette.GOLD if String(row["note"]) == "unlocked" else SFPalette.PAPER_DIM)
		skin.text(self, Vector2(rect.position.x + 12, y), String(row["label"]), c2)
		skin.text_r(self, rect.end.x - 12, y, String(row["note"]).to_upper(), c2)
		y += 17.0

	# Archives.
	y += 8.0
	skin.text(self, Vector2(rect.position.x + 12, y), "ARCHIVES", SFPalette.PAPER_DIM)
	y += 16.0
	_draw_archive_row(rect, y, "CONTROL CENTER", campaign.has_flag(SFCampaign.FLAG_CITY_ARCHIVE_RESTORED))
	_draw_archive_row(rect, y + 16.0, "ENVIRONMENTAL", campaign.has_flag(SFCampaign.FLAG_COAST_ARCHIVE_RESTORED))

	# The objective, stated plainly, so the screen ends on what is next.
	var objective := "Return with the archive records."
	if campaign.has_flag(SFCampaign.FLAG_DAWN_TOWER_UNLOCKED):
		objective = "Next: the Dawn Tower transmitter."
	var oy: float = rect.end.y - 34.0
	draw_rect(Rect2(rect.position.x + 10, oy - 6, rect.size.x - 20, 26), SFPalette.RUIN_DARK, true)
	skin.wrap(self, Vector2(rect.position.x + 16, oy), rect.size.x - 32, objective, SFPalette.PAPER, 1, 2)


func _draw_archive_row(rect: Rect2, y: float, label: String, done: bool) -> void:
	var c: Color = SFPalette.GREEN_OK if done else SFPalette.PAPER_DIM
	skin.text(self, Vector2(rect.position.x + 24, y), label, c)
	skin.text_r(self, rect.end.x - 12, y, "RESTORED" if done else "PENDING", c)


## A compact side view of the VELA recovery frame. Each recovered component
## adds a visible, honest piece: the chip is a nav block, the core is a glowing
## reactor, and an empty frame has neither.
func _draw_vela_frame(ground: Vector2, scale: float, fitted: int = 0) -> void:
	var s := scale
	# Hull, laid on its side on a cradle.
	var hull := Rect2(ground.x - 30.0 * s, ground.y - 12.0 * s, 60.0 * s, 14.0 * s)
	draw_rect(hull, SFPalette.STEEL.darkened(0.1), true)
	draw_rect(Rect2(hull.position, Vector2(hull.size.x, 2.0 * s)), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(hull.position.x, hull.end.y - 2.0 * s, hull.size.x, 2.0 * s), SFPalette.STEEL_DARK, true)
	# Nose cone.
	draw_rect(Rect2(hull.end.x, hull.position.y + 3.0 * s, 6.0 * s, 8.0 * s), SFPalette.STEEL_MID, true)
	# Cradle.
	draw_rect(Rect2(hull.position.x - 4.0 * s, hull.end.y, hull.size.x + 8.0 * s, 2.0 * s), SFPalette.RUST.darkened(0.2), true)
	for i in 3:
		draw_rect(Rect2(hull.position.x + 4.0 * s + float(i) * 18.0 * s, hull.end.y, 2.0 * s, 5.0 * s), SFPalette.STEEL_DARK, true)

	# Slot 1: the navigation chip.
	var slot1 := Rect2(ground.x - 22.0 * s, ground.y - 9.0 * s, 10.0 * s, 6.0 * s)
	if fitted >= 1:
		draw_rect(slot1, SFPalette.CYAN_DARK, true)
		draw_rect(slot1, SFPalette.CYAN, false, 1.0)
		draw_rect(Rect2(slot1.position + Vector2(2.0, 2.0) * s, Vector2(6.0, 2.0) * s), SFPalette.CYAN, true)
	else:
		draw_rect(slot1, SFPalette.INK, true)
		draw_rect(slot1, SFPalette.STEEL_DARK, false, 1.0)

	# Slot 2: the power core.
	var slot2 := Rect2(ground.x + 2.0 * s, ground.y - 10.0 * s, 12.0 * s, 7.0 * s)
	if fitted >= 2:
		draw_rect(slot2, SFPalette.RUIN_DARK, true)
		draw_rect(slot2, SFPalette.GOLD, false, 1.0)
		var pulse := 0.55 + 0.35 * sin(time * 3.4)
		draw_rect(Rect2(slot2.position + Vector2(3.0, 2.0) * s, Vector2(6.0, 3.0) * s), Color(SFPalette.GOLD.r, SFPalette.GOLD.g, SFPalette.GOLD.b, pulse), true)
	else:
		draw_rect(slot2, SFPalette.INK, true)
		draw_rect(slot2, SFPalette.STEEL_DARK, false, 1.0)

	# Slot 3: the shield emitter is deliberately not fitted in Phase 2. Its empty
	# socket stays visible, and the fit list below the drawing says so plainly.
	var slot3 := Rect2(ground.x + 22.0 * s, ground.y - 11.0 * s, 6.0 * s, 8.0 * s)
	draw_rect(slot3, SFPalette.INK, true)
	draw_rect(slot3, SFPalette.STEEL_DARK.darkened(0.2), false, 1.0)
