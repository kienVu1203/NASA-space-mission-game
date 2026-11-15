extends Node2D
## Phase 4: the mission report. Every value comes from SFfinale.build_report(),
## which recomputes from the committed design and the recorded campaign state.
## Nothing on this screen is randomised, and nothing here can change the run.
##
## The score is shown with its published formula (data/star_fall/finale.json,
## report.score). Skipping the cinematic is stated plainly and has no effect.
##
## Layout: rows are measured, not assumed. A value too long for its column wraps
## under the label and the row grows, so no line can overlap the next one or run
## past the panel edge at any window scale.
##
## Controls
##   UP / DOWN, W / S   scroll
##   ENTER / SPACE / E  continue to the credits (or click CONTINUE)
##   MOUSE WHEEL        scroll
##   ESC                the shared pause menu (controller); never continues

signal closed

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFFinale := preload("res://core/star_fall/sf_finale.gd")

const VW := 640
const VH := 360
const ROW_GAP := 3.0
const VALUE_COLUMN := 150.0
const LINE_H := 11.0

var skin
var ui
var campaign
var finale_data: Dictionary = {}
var reconstruction_data: Dictionary = {}
var report: Dictionary = {}
var scroll: float = 0.0
var max_scroll: float = 0.0
var time: float = 0.0
var closed_once: bool = false
var _rows: Array = []          # laid-out rows: {"label", "value", "tone", "height", "wrap"}
var _panel: Rect2 = Rect2(0, 0, 0, 0)
var _inner: Rect2 = Rect2(0, 0, 0, 0)


func setup(skin_ref, ui_ref, campaign_ref, finale: Dictionary, reconstruction: Dictionary) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	finale_data = finale
	reconstruction_data = reconstruction


func _ready() -> void:
	report = SFFinale.build_report(campaign, reconstruction_data, finale_data)
	closed_once = false
	queue_redraw()


func _labels() -> Dictionary:
	return ((finale_data.get("report", {}) as Dictionary).get("labels", {}) as Dictionary)


func label(key: String, fallback: String = "") -> String:
	return String(_labels().get(key, fallback if fallback != "" else key.to_upper()))


# ---------------------------------------------------------------- input

const CONTINUE_BUTTON := Rect2(10, 340, 110, 18)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		get_viewport().set_input_as_handled()
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				handle_key(KEY_DOWN)
			MOUSE_BUTTON_WHEEL_UP:
				handle_key(KEY_UP)
			MOUSE_BUTTON_LEFT:
				if CONTINUE_BUTTON.has_point(get_local_mouse_position()):
					handle_key(KEY_ENTER)
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	handle_key(key.keycode)


func handle_key(keycode: int) -> void:
	match keycode:
		KEY_UP, KEY_W:
			scroll = maxf(0.0, scroll - 24.0)
			skin.audio.sfx_select()
		KEY_DOWN, KEY_S:
			scroll = minf(max_scroll, scroll + 24.0)
			skin.audio.sfx_select()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			if closed_once:
				return
			closed_once = true
			skin.audio.sfx_confirm()
			closed.emit()
	queue_redraw()


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


# ---------------------------------------------------------------- layout

## The report body, as (label, value, tone) triples. Built once per report.
func _report_rows() -> Array:
	var rows: Array = []
	var score: Dictionary = report.get("score", {}) as Dictionary
	var complete := bool(report.get("objective_complete", false))
	rows.append(["objective", label("completed") if complete else "-", "good" if complete else "bad"])
	rows.append(["memories", "%d" % int(report.get("memory_count", 0)), "plain"])
	var samples := ""
	if bool(report.get("samples_returned", false)):
		samples = "ENVIRONMENTAL SAMPLES"
	if bool(report.get("records_returned", false)):
		samples = (samples + ", " if samples != "" else "") + "ADDITIONAL RECORDS"
	rows.append(["samples", samples if samples != "" else label("none"), "plain"])
	rows.append(["components", "%d / 3" % (report.get("components", []) as Array).size(), "plain"])
	rows.append(["original", String(report.get("original_design", "-")), "plain"])
	rows.append(["reconstructed", String(report.get("reconstructed_design", "-")), "plain"])
	rows.append(["mass", "%.0f kg" % float(report.get("launch_mass_kg", 0.0)), "plain"])
	rows.append(["route", String(report.get("route_name", "-")).to_upper(), "plain"])
	var reserves: Dictionary = report.get("reserves", {}) as Dictionary
	var loaded := float(reserves.get("propellant_loaded_kg", 0.0))
	var left := float(reserves.get("propellant_kg", 0.0))
	var pct := 0.0 if loaded <= 0.0 else 100.0 * left / loaded
	rows.append(["propellant", "%.0f kg  (%.0f %%)" % [left, pct], "plain"])
	rows.append(["energy", "%.0f / %.0f Wh" % [
		float(reserves.get("battery_wh", 0.0)), float(reserves.get("battery_capacity_wh", 0.0))], "plain"])
	rows.append(["efficiency", "%.1f kg/unit  (%d units)" % [
		float(report.get("efficiency_kg_per_unit", 0.0)), int(report.get("material_units", 0))], "plain"])
	rows.append(["score", "%d" % int(score.get("total", 0)), "gold"])
	rows.append(["", String(score.get("formula", "")), "dim"])
	return rows


## Measures every row for the current panel width. Values that do not fit on the
## right wrap below their label; the row height follows.
func _layout(inner_width: float) -> void:
	_rows = []
	var value_width := inner_width - VALUE_COLUMN
	for entry in _report_rows():
		var e: Array = entry
		var label_text := "" if String(e[0]) == "" else label(String(e[0]))
		var value_text := String(e[1])
		var tone := String(e[2])
		var wrapped: bool = label_text != "" and skin.font.text_width(value_text) > value_width
		var lines: int = 1
		if label_text == "":
			lines = maxi(1, skin.wrap_line_count(value_text, inner_width))
		elif wrapped:
			lines = maxi(1, skin.wrap_line_count(value_text, value_width))
		var height: float = float(lines) * LINE_H + ROW_GAP
		_rows.append({"label": label_text, "value": value_text, "tone": tone, "height": height, "wrapped": wrapped or label_text == ""})


func _rows_height() -> float:
	var h := 0.0
	for r in _rows:
		h += float((r as Dictionary).get("height", 0.0))
	return h


func _decisions_height() -> float:
	var decisions: Array = report.get("decisions", []) as Array
	if decisions.is_empty():
		return 0.0
	var h := 18.0
	for line in decisions:
		h += float(skin.wrap_line_count(String(line), _inner.size.x)) * LINE_H + 2.0
	return h + 6.0


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	# A quiet starfield behind the report: the run is over.
	for i in 70:
		var c := Color(1, 1, 1, 0.10 + 0.14 * float(i % 4) / 4.0)
		draw_rect(Rect2(float((i * 89) % VW), float((i * 41) % VH), 1, 1), c, true)

	ui.header(self, label("title", "MISSION REPORT"),
		label("subtitle", "Compiled from the recorded run"),
		[String(report.get("route_name", "")).to_upper()])

	_panel = Rect2(40, 34, 560, 282)
	draw_rect(_panel, Color(0.04, 0.07, 0.08, 0.94), true)
	draw_rect(_panel, SFPalette.CYAN_DIM, false, 1.0)
	draw_rect(Rect2(_panel.position, Vector2(_panel.size.x, 1)), SFPalette.CYAN, true)

	_inner = Rect2(_panel.position + Vector2(14, 10), _panel.size - Vector2(28, 20))
	_layout(_inner.size.x)
	max_scroll = maxf(0.0, _rows_height() + _decisions_height() - _inner.size.y)
	scroll = clampf(scroll, 0.0, max_scroll)

	var clip_top := _inner.position.y
	var clip_bottom := _inner.end.y
	var y: float = _inner.position.y - scroll
	for r in _rows:
		var row: Dictionary = r
		var h := float(row.get("height", 0.0))
		var row_top := y
		var row_bottom := y + h
		y = row_bottom
		# Clip per row: a row fully above or below the panel is skipped, and a row
		# straddling the inner edge is still drawn, because its text is short.
		if row_bottom <= clip_top or row_top >= clip_bottom:
			continue
		var value_color: Color = SFPalette.PAPER
		match String(row.get("tone", "plain")):
			"good":
				value_color = SFPalette.GREEN_OK
			"bad":
				value_color = SFPalette.RED
			"gold":
				value_color = SFPalette.GOLD
			"dim":
				value_color = SFPalette.PAPER_DIM
		var label_text := String(row.get("label", ""))
		var value_text := String(row.get("value", ""))
		if label_text == "":
			skin.wrap(self, Vector2(_inner.position.x, row_top), _inner.size.x, value_text, value_color, 1, 6)
		elif bool(row.get("wrapped", false)):
			skin.text(self, Vector2(_inner.position.x, row_top), label_text, SFPalette.PAPER_DIM)
			skin.wrap(self, Vector2(_inner.position.x + VALUE_COLUMN, row_top), _inner.size.x - VALUE_COLUMN, value_text, value_color, 1, 6)
		else:
			skin.text(self, Vector2(_inner.position.x, row_top), label_text, SFPalette.PAPER_DIM)
			skin.text_r(self, _inner.end.x, row_top, value_text, value_color)

	# The decisions block follows the rows in the same scroll flow, so it can
	# never overlap a value however long the report grows.
	var decisions: Array = report.get("decisions", []) as Array
	if not decisions.is_empty():
		var dy := _inner.position.y + _rows_height() - scroll
		if dy > clip_top - 10.0 and dy < clip_bottom:
			draw_rect(Rect2(_inner.position.x, dy - 4.0, _inner.size.x, 1), SFPalette.STEEL_DARK, true)
			skin.text(self, Vector2(_inner.position.x, dy), label("decisions", "DECISIONS THAT ENABLED SUCCESS"), SFPalette.GOLD)
			var line_y := dy + 14.0
			for line in decisions:
				if line_y > clip_bottom:
					break
				line_y = skin.wrap(self, Vector2(_inner.position.x, line_y), _inner.size.x, String(line), SFPalette.PAPER, 1, 3) + 2.0

	draw_rect(Rect2(0, VH - 22, VW, 22), Color(0.02, 0.04, 0.05, 0.94), true)
	skin.text_c(self, VW * 0.5, VH - 16, label("continue_hint", "ENTER  CREDITS"), SFPalette.CYAN)
	skin.button(self, CONTINUE_BUTTON, "CONTINUE", true, true)
	if max_scroll > 0.0:
		# The hint doubles as the "there is more below" marker, so the decision
		# explanations are never missed when they start below the panel edge.
		var hint := "UP/DOWN SCROLL" if scroll >= max_scroll - 0.5 else "UP/DOWN SCROLL  v"
		skin.text_r(self, VW - 12, VH - 16, hint, SFPalette.PAPER_DIM)
	# The skip note sits just above the footer, clear of the panel and the hint.
	if bool(report.get("cinematic_skipped", false)):
		skin.text_c(self, VW * 0.5, VH - 30, label("skipped", ""), SFPalette.ASH_LIGHT)
	ui.toast(self)
