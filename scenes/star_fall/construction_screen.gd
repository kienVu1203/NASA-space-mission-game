extends Node2D
## The construction console: the whole spacecraft construction and preflight
## loop as one self-contained screen.
##
## This screen owns no campaign state. It edits a working copy of the design
## through the campaign object and reports completion through signals; the main
## controller decides what happens next.
##
## Controls
##   UP/DOWN      move the slot cursor
##   LEFT/RIGHT   cycle the component in the current slot (preview, no cost)
##   Q / E        adjust the fuel load in steps
##   V            run preflight validation
##   ENTER        confirm the design (atomic: validates, then commits)
##   ESC          leave the console (the working design is kept)

signal closed
signal design_confirmed_ok

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFUI := preload("res://core/star_fall/sf_ui.gd")
const SFDesign := preload("res://core/star_fall/sf_design.gd")
const SFMenu := preload("res://core/star_fall/sf_menu.gd")
const SFSkin := preload("res://core/star_fall/sf_skin.gd")

var skin
var ui
var campaign

var slot_menu
var current_slot: int = 0
var checks: Array = []
var checks_run: bool = false
var fuel_flash: float = 0.0
var _blink: float = 0.0
var _built_ship: Node2D = null

var _slot_fuel_row: int = 5   # the fuel row sits after the five slots
var _slot_rects: Array = []
var _option_rects: Array = []
var _dragging_fuel: bool = false


func setup(skin_ref, ui_ref, campaign_ref) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref


func _ready() -> void:
	slot_menu = SFMenu.new()
	_rebuild_slot_menu()
	queue_redraw()


func _rebuild_slot_menu() -> void:
	var items: Array = []
	var d = campaign.design
	for slot in SFDesign.SLOTS:
		var id := String(slot)
		items.append({
			"id": id,
			"label": SFPalette.SLOT_NAMES.get(id, id.to_upper()),
			"detail": _component_name(d.slot_component(id)),
			"enabled": true,
		})
	items.append({
		"id": "fuel",
		"label": "FUEL LOAD",
		"detail": "%d KG" % int(d.fuel_kg),
		"enabled": true,
	})
	slot_menu.set_items(items, String((items[current_slot] as Dictionary)["id"]))
	current_slot = clampi(current_slot, 0, items.size() - 1)


func _component_name(id: String) -> String:
	if id == "":
		return "EMPTY"
	return String(campaign.content.component(id).get("name", id))


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key := key_event.keycode
	match key:
		KEY_UP, KEY_W:
			slot_menu.move(-1)
			current_slot = slot_menu.index
			skin.audio.sfx_select()
			queue_redraw()
		KEY_DOWN, KEY_S:
			slot_menu.move(1)
			current_slot = slot_menu.index
			skin.audio.sfx_select()
			queue_redraw()
		KEY_LEFT, KEY_A:
			_cycle_component(-1)
		KEY_RIGHT, KEY_D:
			_cycle_component(1)
		KEY_Q:
			_adjust_fuel(-1)
		KEY_E:
			_adjust_fuel(1)
		KEY_V:
			_run_preflight()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm()
		KEY_ESCAPE:
			skin.audio.sfx_back()
			closed.emit()


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	var pos: Vector2 = get_local_mouse_position()
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging_fuel = false
		return

	if mb.button_index == MOUSE_BUTTON_RIGHT:
		skin.audio.sfx_back()
		closed.emit()
		return

	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		if pos.x < 188.0:
			slot_menu.move(-1)
			current_slot = slot_menu.index
			skin.audio.sfx_select()
			queue_redraw()
		else:
			_cycle_component(-1)
		return

	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if pos.x < 188.0:
			slot_menu.move(1)
			current_slot = slot_menu.index
			skin.audio.sfx_select()
			queue_redraw()
		else:
			_cycle_component(1)
		return

	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	# 1. Left column: slot list (A-E + F FUEL) or fuel tank on ship diagram
	for i in _slot_rects.size():
		var sr: Rect2 = _slot_rects[i] as Rect2
		if sr.has_point(pos):
			slot_menu.index = i
			current_slot = i
			skin.audio.sfx_select()
			queue_redraw()
			return

	if Rect2(80, 128, 36, 56).has_point(pos):
		slot_menu.index = _slot_fuel_row
		current_slot = _slot_fuel_row
		skin.audio.sfx_select()
		queue_redraw()
		return

	# 2. Middle column: component cards or fuel bar
	if String(slot_menu.current_id()) == "fuel":
		var fuel_box := Rect2(206, 66, 186, 46)
		if fuel_box.has_point(pos):
			_dragging_fuel = true
			_set_fuel_from_mouse_x(pos.x, fuel_box)
			return
	else:
		for item in _option_rects:
			var entry: Dictionary = item as Dictionary
			var r: Rect2 = entry["rect"] as Rect2
			if r.has_point(pos):
				_select_component_by_id(String(entry["id"]))
				return
		if Rect2(192, 32, 214, 28).has_point(pos):
			_cycle_component(1)
			return

	# 3. Right column: Confirm Design & Run Preflight Check buttons
	var confirm_rect := Rect2(418, 290, 206, 16)
	if confirm_rect.has_point(pos):
		_confirm()
		return
	var preflight_rect := Rect2(418, 306, 206, 22)
	if preflight_rect.has_point(pos) or Rect2(412, 160, 218, 128).has_point(pos):
		_run_preflight()
		return

	# 4. Footer bar shortcuts
	if pos.y >= 336.0:
		if pos.x > 520.0:
			skin.audio.sfx_back()
			closed.emit()
		elif pos.x > 420.0:
			_confirm()
		elif pos.x > 330.0:
			_run_preflight()


func _handle_mouse_motion(_mm: InputEventMouseMotion) -> void:
	if _dragging_fuel and String(slot_menu.current_id()) == "fuel":
		var pos: Vector2 = get_local_mouse_position()
		_set_fuel_from_mouse_x(pos.x, Rect2(206, 66, 186, 46))


func _set_fuel_from_mouse_x(mx: float, fuel_box: Rect2) -> void:
	var cap := float(campaign.content.hull.get("fuel_capacity_kg", 500.0))
	var step := float(campaign.content.hull.get("fuel_step_kg", 25.0))
	if step <= 0.0:
		step = 25.0
	var ratio: float = clampf((mx - (fuel_box.position.x + 4.0)) / maxf(1.0, fuel_box.size.x - 8.0), 0.0, 1.0)
	var target_kg: float = clampf(round((ratio * cap) / step) * step, 0.0, cap)
	if not is_equal_approx(target_kg, campaign.design.fuel_kg):
		campaign.design.set_fuel(target_kg, campaign.content)
		skin.audio.sfx_select()
		fuel_flash = 0.25
		_invalidate()
		_rebuild_slot_menu()
		queue_redraw()


func _select_component_by_id(comp_id: String) -> void:
	var slot: String = String(slot_menu.current_id())
	if comp_id == "":
		campaign.design.clear_slot(slot)
		skin.audio.sfx_remove()
	else:
		campaign.design.set_slot(slot, comp_id)
		skin.audio.sfx_install()
	_invalidate()
	_rebuild_slot_menu()
	queue_redraw()


func _cycle_component(delta: int) -> void:
	if slot_menu.current_id() == "fuel":
		_adjust_fuel(delta)
		return
	var slot: String = String(slot_menu.current_id())
	var options: Array = campaign.content.components_for_slot(slot)
	if options.is_empty():
		return
	var current: String = String(campaign.design.slot_component(slot))
	var index := -1
	for i in options.size():
		if String((options[i] as Dictionary).get("id", "")) == current:
			index = i
			break
	# Cycle order: empty, then each option in file order, then back to empty.
	var cursor: int = index + 1
	var count: int = options.size() + 1
	var next_position: int = int(fposmod(float(cursor + delta), float(count)))
	if next_position == 0:
		campaign.design.clear_slot(slot)
		skin.audio.sfx_remove()
	else:
		var comp: Dictionary = options[next_position - 1] as Dictionary
		campaign.design.set_slot(slot, String(comp.get("id", "")))
		skin.audio.sfx_install()
	# A design change always invalidates the previous validation result.
	_invalidate()
	_rebuild_slot_menu()
	queue_redraw()


func _adjust_fuel(steps: int) -> void:
	var before: float = campaign.design.fuel_kg
	campaign.design.adjust_fuel(steps, campaign.content)
	if is_equal_approx(before, campaign.design.fuel_kg):
		skin.audio.sfx_denied()
	else:
		skin.audio.sfx_select()
		fuel_flash = 0.25
	_invalidate()
	_rebuild_slot_menu()
	queue_redraw()


func _invalidate() -> void:
	if checks_run:
		checks_run = false
		checks = []


# ---------------------------------------------------------------- actions

func _run_preflight() -> void:
	checks = campaign.design.validate(campaign.content)
	checks_run = true
	var valid: bool = campaign.design.is_valid(campaign.content)
	if valid:
		skin.audio.sfx_confirm()
		Events.preflight_passed.emit()
		ui.notify("Preflight passed.", "good")
	else:
		skin.audio.sfx_denied()
		var first: Dictionary = campaign.design.first_blocking_failure(campaign.content)
		Events.preflight_failed.emit(String(first.get("message", "")))
		ui.notify("Preflight failed.", "bad")
	queue_redraw()


func _confirm() -> void:
	# Confirmation re-validates. It never trusts a stale pass, so the launch is
	# atomic: the commit only happens when every blocking check is green.
	var result: Dictionary = campaign.confirm_design()
	if bool(result.get("ok", false)):
		skin.audio.sfx_confirm()
		campaign.set_checkpoint("construction")
		design_confirmed_ok.emit()
	else:
		skin.audio.sfx_denied()
		checks = result.get("checks", []) as Array
		checks_run = true
		var errors: Array = result.get("errors", []) as Array
		var msg := "Design cannot be confirmed."
		if not errors.is_empty():
			msg = String(errors[0])
		ui.notify(msg, "bad")
	queue_redraw()


# ---------------------------------------------------------------- process

func _process(delta: float) -> void:
	_blink += delta
	ui.tick(delta)
	if fuel_flash > 0.0:
		fuel_flash = maxf(0.0, fuel_flash - delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), SFPalette.INK, true)
	ui.header(self, "VELA ASSEMBLY CONSOLE", "Install components, then run preflight.",
		["BUDGET %d CR" % int(campaign.credits), "MISSION: SIGNAL INVESTIGATION"])

	_draw_ship_column(Rect2(10, 32, 176, 296))
	_draw_component_column(Rect2(192, 32, 214, 296))
	_draw_summary_column(Rect2(412, 32, 218, 296))

	ui.footer(self, [
		"UP/DOWN:SLOT", "LEFT/RIGHT:PART", "Q/E:FUEL", "V:CHECK", "ENTER:OK", "ESC:BACK",
	])
	ui.toast(self)


func _draw_ship_column(rect: Rect2) -> void:
	draw_rect(rect, Color(0.07, 0.10, 0.12), true)
	draw_rect(rect, SFPalette.STEEL_DARK, false, 1.0)
	skin.text(self, rect.position + Vector2(6, 5), "ASSEMBLED FRAME", SFPalette.CYAN)

	# The ship drawing is a real visual read of the installed components: the
	# hull, propulsion pod size, power pod and sensor dome all change.
	var base := rect.position + Vector2(rect.size.x * 0.5, 196)
	_draw_assembled_ship(base)

	# Slot indicator list under the ship: serial letters, state and short name.
	_slot_rects.clear()
	var y := rect.position.y + 205.0
	var d = campaign.design
	var letters: Array = ["A", "B", "C", "D", "E"]
	var index: int = 0
	for slot in SFDesign.SLOTS:
		var id := String(slot)
		var comp_id: String = String(d.slot_component(id))
		var filled: bool = comp_id != ""
		var focused: bool = slot_menu.current_id() == id
		var row := Rect2(rect.position.x + 6, y, rect.size.x - 12, 13)
		_slot_rects.append(row)
		if focused:
			draw_rect(row, SFPalette.RUIN, true)
			draw_rect(Rect2(row.position, Vector2(2, row.size.y)), SFPalette.CYAN, true)
		var dot := Rect2(row.position.x + 7, row.position.y + 5, 4, 4)
		draw_rect(dot, SFPalette.GREEN_OK if filled else SFPalette.ASH, true)
		skin.text(self, Vector2(row.position.x + 16, row.position.y + 3), "%s %s" % [String(letters[index]), String(SFPalette.SLOT_NAMES.get(id, id))], SFPalette.PAPER if focused else SFPalette.PAPER_DIM)
		skin.text_r(self, row.end.x - 5, row.position.y + 3, "SET" if filled else "EMPTY", SFPalette.GREEN_OK if filled else SFPalette.ASH_LIGHT)
		y += 14.0
		index += 1

	var fuel_focused: bool = slot_menu.current_id() == "fuel"
	var fuel_row := Rect2(rect.position.x + 6, y, rect.size.x - 12, 13)
	_slot_rects.append(fuel_row)
	if fuel_focused:
		draw_rect(fuel_row, SFPalette.RUIN, true)
		draw_rect(Rect2(fuel_row.position, Vector2(2, fuel_row.size.y)), SFPalette.CYAN, true)
	var min_fuel_ok: bool = d.fuel_kg >= float(campaign.content.requirements.get("minimum_fuel_kg", 0.0))
	draw_rect(Rect2(fuel_row.position.x + 7, fuel_row.position.y + 5, 4, 4), SFPalette.GREEN_OK if min_fuel_ok else SFPalette.ASH, true)
	skin.text(self, Vector2(fuel_row.position.x + 16, fuel_row.position.y + 3), "F FUEL LOAD", SFPalette.PAPER if fuel_focused else SFPalette.PAPER_DIM)
	skin.text_r(self, fuel_row.end.x - 5, fuel_row.position.y + 3, "%dKG" % int(d.fuel_kg), SFPalette.GREEN_OK if min_fuel_ok else SFPalette.ASH_LIGHT)


## Draws the ship at a ground point, its shape driven by the design.
func _draw_assembled_ship(ground: Vector2) -> void:
	var d = campaign.design
	var hull: Dictionary = campaign.content.hull

	# Cradle and contact shadow.
	skin.contact_shadow(self, ground + Vector2(0, 4), 54.0, 0.30)

	# Propulsion: engine bells widen with the heavy cluster.
	var prop_id: String = String(d.slot_component("propulsion"))
	var heavy: bool = prop_id == "propulsion_heavy"
	var light: bool = prop_id == "propulsion_light"
	var bell_w: float = 14.0
	if heavy:
		bell_w = 22.0
	elif light:
		bell_w = 10.0
	draw_rect(Rect2(ground.x - bell_w * 0.5, ground.y - 22, bell_w, 12), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x - bell_w * 0.5 + 1, ground.y - 22, maxf(2.0, bell_w * 0.25), 12), SFPalette.STEEL_MID, true)
	if not prop_id.is_empty():
		draw_rect(Rect2(ground.x - bell_w * 0.5, ground.y - 13, bell_w, 3), SFPalette.RUST, true)

	# Main hull body, painted with the campaign palette.
	var body := Rect2(ground.x - 15, ground.y - 104, 30, 82)
	draw_rect(body, SFPalette.STEEL_MID, true)
	draw_rect(Rect2(body.position, Vector2(4, body.size.y)), SFPalette.STEEL, true)
	draw_rect(Rect2(body.end.x - 4, body.position.y, 4, body.size.y), SFPalette.STEEL_DARK, true)
	# Panel lines.
	var py := body.position.y + 16.0
	while py < body.end.y:
		draw_rect(Rect2(body.position.x + 4, py, body.size.x - 8, 1), SFPalette.STEEL_DARK, true)
		py += 16.0

	# Computer bay (upper hull), visible as a lit band when installed.
	var comp_id: String = String(d.slot_component("computer"))
	if comp_id != "":
		draw_rect(Rect2(ground.x - 9, ground.y - 96, 18, 8), SFPalette.INK, true)
		draw_rect(Rect2(ground.x - 7, ground.y - 94, 14, 4), SFPalette.CYAN_DIM, true)
		draw_rect(Rect2(ground.x - 7, ground.y - 94, 8, 1), SFPalette.CYAN, true)

	# Power plant: solar wings or a lit cell block.
	var power_id: String = String(d.slot_component("power"))
	if power_id == "power_solar_array":
		draw_rect(Rect2(ground.x - 40, ground.y - 74, 22, 26), SFPalette.BLUE_ACCENT, true)
		draw_rect(Rect2(ground.x + 18, ground.y - 74, 22, 26), SFPalette.BLUE_ACCENT, true)
		var i := 0
		while i < 4:
			draw_rect(Rect2(ground.x - 38 + i * 5, ground.y - 72, 1, 22), SFPalette.CYAN_DIM, true)
			draw_rect(Rect2(ground.x + 20 + i * 5, ground.y - 72, 1, 22), SFPalette.CYAN_DIM, true)
			i += 1
		draw_rect(Rect2(ground.x - 40, ground.y - 74, 22, 1), SFPalette.STEEL, true)
		draw_rect(Rect2(ground.x + 18, ground.y - 74, 22, 1), SFPalette.STEEL, true)
	elif power_id == "power_rtg_cell":
		draw_rect(Rect2(ground.x - 24, ground.y - 70, 10, 22), SFPalette.ASH, true)
		draw_rect(Rect2(ground.x + 14, ground.y - 70, 10, 22), SFPalette.ASH, true)
		draw_rect(Rect2(ground.x - 23, ground.y - 66, 8, 2), SFPalette.GOLD, true)
		draw_rect(Rect2(ground.x + 15, ground.y - 66, 8, 2), SFPalette.GOLD, true)

	# Communications mast.
	if d.slot_component("communications") != "":
		draw_rect(Rect2(ground.x + 14, ground.y - 118, 2, 20), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(ground.x + 10, ground.y - 120, 10, 2), SFPalette.STEEL, true)
		draw_rect(Rect2(ground.x + 12, ground.y - 126, 6, 6), SFPalette.STEEL_MID, true)
		draw_rect(Rect2(ground.x + 14, ground.y - 124, 2, 2), SFPalette.CYAN, true)

	# Sensor dome: changes size and glow tone with quality.
	var sensor_id: String = String(d.slot_component("sensor"))
	if sensor_id != "":
		var sensor: Dictionary = campaign.content.component(sensor_id)
		var q := int(sensor.get("sensor_quality", 0))
		var r := 4.0 + float(q) * 2.0
		draw_rect(Rect2(ground.x - r, ground.y - 112 - r, r * 2, r * 2), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(ground.x - r + 1, ground.y - 111 - r, r * 2 - 2, r * 2 - 2), SFPalette.CYAN_DIM, true)
		var lens: Color = SFPalette.CYAN
		if q >= 3:
			lens = SFPalette.GREEN_OK
		elif q <= 1:
			lens = SFPalette.RUST_LIGHT
		draw_rect(Rect2(ground.x - 2, ground.y - 110 - r, 4, 3), lens, true)

	# Nose cone and fuel gauge.
	draw_rect(Rect2(ground.x - 8, ground.y - 116, 16, 12), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 5, ground.y - 122, 10, 8), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x - 2, ground.y - 126, 4, 6), SFPalette.STEEL_MID, true)
	var fuel_ratio: float = 0.0
	var cap := float(hull.get("fuel_capacity_kg", 1.0))
	if cap > 0.0:
		fuel_ratio = clampf(d.fuel_kg / cap, 0.0, 1.0)
	draw_rect(Rect2(ground.x - 3, ground.y - 60, 6, 40), SFPalette.INK, true)
	var fh: float = round(38.0 * fuel_ratio)
	if fh > 0.0:
		draw_rect(Rect2(ground.x - 2, ground.y - 21 - fh, 4, fh), SFPalette.CYAN_DIM, true)
	draw_rect(Rect2(ground.x - 3, ground.y - 60, 6, 40), SFPalette.STEEL_DARK, false, 1.0)

	# Empty slot markers, so a missing part is visibly missing.
	var slot_markers := {
		"computer": Vector2(0, -92),
		"propulsion": Vector2(0, -18),
		"power": Vector2(-24, -60),
		"communications": Vector2(15, -108),
		"sensor": Vector2(0, -109),
	}
	for slot in slot_markers.keys():
		if d.slot_component(String(slot)) == "":
			var p: Vector2 = ground + (slot_markers[slot] as Vector2)
			var c: Color = SFPalette.RED
			c.a = 0.55 + 0.35 * sin(_blink * 4.0)
			draw_rect(Rect2(p.x - 3, p.y - 3, 6, 6), c, false, 1.0)
			draw_rect(Rect2(p.x - 1, p.y - 1, 2, 2), c, true)


func _draw_component_column(rect: Rect2) -> void:
	_option_rects.clear()
	draw_rect(rect, Color(0.07, 0.10, 0.12), true)
	draw_rect(rect, SFPalette.STEEL_DARK, false, 1.0)

	var current: String = String(slot_menu.current_id())
	var d = campaign.design

	if current == "fuel":
		_draw_fuel_panel(rect)
		return

	var slot_name := String(SFPalette.SLOT_NAMES.get(current, current.to_upper()))
	skin.text(self, rect.position + Vector2(6, 5), "SLOT: " + slot_name, SFPalette.CYAN)
	skin.text(self, rect.position + Vector2(6, 16), "CLICK OR LEFT / RIGHT TO SELECT", SFPalette.PAPER_DIM)

	var installed: String = String(d.slot_component(current))
	# Rows stop above the standing note at the bottom of the column.
	var rows_bottom: float = rect.end.y - 34.0
	var y := rect.position.y + 30.0
	var options: Array = campaign.content.components_for_slot(current)

	# The empty option is listed first so a player can always undo an install.
	var rows: Array = [{}]
	for o in options:
		rows.append(o)
	var drawn: int = 0

	for row_data in rows:
		var comp: Dictionary = row_data as Dictionary
		var is_empty: bool = comp.is_empty()
		var id := "" if is_empty else String(comp.get("id", ""))
		var selected: bool = id == installed
		var box_h := 20.0
		if not is_empty:
			# name line + stats line + up to two wrapped description lines
			var desc: String = String(comp.get("description", ""))
			var inner_w: float = rect.size.x - 30.0
			var desc_lines: int = skin.font.wrap(desc, inner_w, 1).size()
			box_h = 22.0 + float(mini(desc_lines, 2)) * 9.0
		var row := Rect2(rect.position.x + 5, y, rect.size.x - 10, box_h)
		if y + box_h > rows_bottom:
			# Whatever does not fit is reported as a count, never as clipped text.
			var hidden: int = rows.size() - drawn
			skin.text(self, Vector2(rect.position.x + 8, rows_bottom - 9),
				"+%d MORE - CYCLE TO SEE" % hidden, SFPalette.ASH_LIGHT)
			break
		_option_rects.append({"rect": row, "id": id})
		var fill := Color(0.05, 0.08, 0.09)
		if selected:
			fill = SFPalette.RUIN
		draw_rect(row, fill, true)
		if selected:
			draw_rect(Rect2(row.position, Vector2(2, row.size.y)), SFPalette.CYAN, true)
			draw_rect(row, SFPalette.CYAN_DIM, false, 1.0)
		else:
			draw_rect(row, SFPalette.STEEL_DARK.darkened(0.2), false, 1.0)

		if is_empty:
			skin.text(self, Vector2(row.position.x + 7, row.position.y + 6), "(leave empty)", SFPalette.ASH_LIGHT)
		else:
			var name := String(comp.get("name", id))
			var cost_txt := "%d CR" % int(comp.get("cost", 0))
			# Fit the name into the space left of the price, so they never collide.
			var price_w: float = skin.font.text_width(cost_txt, 1) + 10.0
			var name_txt: String = String(skin.font.fit(name, row.size.x - price_w - 12.0, 1))
			skin.text(self, Vector2(row.position.x + 7, row.position.y + 3), name_txt, SFPalette.PAPER if selected else SFPalette.PAPER_DIM)
			skin.text_r(self, row.end.x - 6, row.position.y + 3, cost_txt, SFPalette.GOLD if selected else SFPalette.PAPER_DIM)

			# Real numbers, with units, so the trade-offs are legible.
			var power_delta: float = float(comp.get("power_output_w", 0)) - float(comp.get("power_demand_w", 0))
			var stats := "%dKG  %+dW  %dWh" % [
				int(comp.get("mass_kg", 0)),
				int(round(power_delta)),
				int(comp.get("energy_storage_wh", 0)),
			]
			skin.text(self, Vector2(row.position.x + 7, row.position.y + 12), stats, SFPalette.PAPER_DIM)
			if String(comp.get("slot", "")) == "sensor":
				skin.text_r(self, row.end.x - 6, row.position.y + 12, "QUALITY %d" % int(comp.get("sensor_quality", 0)), SFPalette.CYAN)
			elif String(comp.get("slot", "")) == "propulsion":
				skin.text_r(self, row.end.x - 6, row.position.y + 12, "LIFTS %dKG" % int(comp.get("thrust_capacity_kg", 0)), SFPalette.CYAN)
			var desc: String = String(comp.get("description", ""))
			var desc_txt: String = String(skin.font.clip_lines(desc, row.size.x - 14.0, 2, 1))
			skin.wrap(self, Vector2(row.position.x + 7, row.position.y + 21), row.size.x - 14, desc_txt, SFPalette.ASH_LIGHT, 1, 2)
		y += box_h + 3.0
		drawn += 1

	var note := "Previewing costs nothing. Confirm only when preflight passes."
	skin.wrap(self, Vector2(rect.position.x + 6, rect.end.y - 26), rect.size.x - 12, note, SFPalette.ASH_LIGHT, 1, 2)


func _draw_fuel_panel(rect: Rect2) -> void:
	var d = campaign.design
	var cap := float(campaign.content.hull.get("fuel_capacity_kg", 0.0))
	skin.text(self, rect.position + Vector2(6, 5), "FUEL LOAD", SFPalette.CYAN)
	skin.text(self, rect.position + Vector2(6, 16), "Q / E TO ADJUST", SFPalette.PAPER_DIM)

	var big := Rect2(rect.position.x + 14, rect.position.y + 34, rect.size.x - 28, 46)
	draw_rect(big, SFPalette.INK, true)
	draw_rect(big, SFPalette.STEEL_DARK, false, 1.0)
	var bar_color := SFPalette.CYAN
	if d.fuel_kg < float(campaign.content.requirements.get("minimum_fuel_kg", 0.0)):
		bar_color = SFPalette.RED
	draw_rect(Rect2(big.position.x + 4, big.position.y + 26, big.size.x - 8, 10), SFPalette.RUIN_DARK, true)
	var ratio: float = clampf(d.fuel_kg / maxf(1.0, cap), 0.0, 1.0)
	draw_rect(Rect2(big.position.x + 4, big.position.y + 26, (big.size.x - 8) * ratio, 10), bar_color, true)
	skin.text_c(self, big.position.x + big.size.x * 0.5, big.position.y + 6, "%d KG OF %d KG" % [int(d.fuel_kg), int(cap)], SFPalette.PAPER)
	skin.text_c(self, big.position.x + big.size.x * 0.5, big.position.y + 38, "ROCKET PROPELLANT", SFPalette.PAPER_DIM)

	# The minimum marker is a hard mission requirement, drawn on the bar.
	var min_fuel := float(campaign.content.requirements.get("minimum_fuel_kg", 0.0))
	if cap > 0.0:
		var mx := big.position.x + 4 + (big.size.x - 8) * clampf(min_fuel / cap, 0.0, 1.0)
		draw_rect(Rect2(mx, big.position.y + 23, 1, 16), SFPalette.GOLD, true)
		skin.text_c(self, mx, big.position.y + 40, "MIN %d" % int(min_fuel), SFPalette.GOLD)

	skin.wrap(self, Vector2(rect.position.x + 8, rect.position.y + 92), rect.size.x - 16,
		"Fuel is propellant measured in kilograms. It is not electrical energy. Adding fuel raises launch mass, so a light thruster may no longer lift the ship.",
		SFPalette.PAPER_DIM, 1, 5)

	# Current budget impact.
	var s: Dictionary = d.summary(campaign.content)
	skin.text(self, Vector2(rect.position.x + 8, rect.position.y + 148), "DRY MASS", SFPalette.PAPER_DIM)
	skin.text_r(self, rect.end.x - 8, rect.position.y + 148, "%.0f KG" % float(s["dry_mass_kg"]), SFPalette.PAPER)
	skin.text(self, Vector2(rect.position.x + 8, rect.position.y + 160), "LAUNCH MASS", SFPalette.PAPER_DIM)
	skin.text_r(self, rect.end.x - 8, rect.position.y + 160, "%.0f KG" % float(s["wet_mass_kg"]), SFPalette.PAPER)
	skin.text(self, Vector2(rect.position.x + 8, rect.position.y + 172), "MASS LIMIT", SFPalette.PAPER_DIM)
	skin.text_r(self, rect.end.x - 8, rect.position.y + 172, "%.0f KG" % float(s["mass_limit_kg"]), SFPalette.PAPER)


func _draw_summary_column(rect: Rect2) -> void:
	draw_rect(rect, Color(0.07, 0.10, 0.12), true)
	draw_rect(rect, SFPalette.STEEL_DARK, false, 1.0)
	skin.text(self, rect.position + Vector2(6, 5), "MISSION READINESS", SFPalette.CYAN)

	var d = campaign.design
	var s: Dictionary = d.summary(campaign.content)
	var w := rect.size.x - 14.0
	var y := rect.position.y + 20.0

	_metric_row(rect.position.x + 7, y, w, "MASS", "%.0f kg" % float(s["wet_mass_kg"]), "limit %.0f" % float(s["mass_limit_kg"]), float(s["wet_mass_kg"]) <= float(s["mass_limit_kg"]))
	y += 15.0
	_metric_row(rect.position.x + 7, y, w, "FUEL", "%.0f kg" % float(s["fuel_kg"]), "min %.0f" % float(campaign.content.requirements.get("minimum_fuel_kg", 0.0)), float(s["fuel_kg"]) >= float(campaign.content.requirements.get("minimum_fuel_kg", 0.0)))
	y += 15.0
	_metric_row(rect.position.x + 7, y, w, "POWER", "%.0f W" % float(s["power_demand_w"]), "supply %.0f W" % float(s["power_output_w"]), float(s["power_demand_w"]) <= float(s["power_output_w"]))
	y += 15.0
	_metric_row(rect.position.x + 7, y, w, "ENERGY", "%.0f Wh" % float(s["energy_stored_wh"]), "need %.0f Wh" % float(s["energy_required_wh"]), float(s["energy_stored_wh"]) >= float(s["energy_required_wh"]))
	y += 15.0
	_metric_row(rect.position.x + 7, y, w, "COST", "%d cr" % int(s["cost"]), "budget %d" % int(campaign.content.program.get("start_credits", 100.0)), float(s["cost"]) <= float(campaign.content.program.get("start_credits", 100.0)))
	y += 15.0
	_metric_row(rect.position.x + 7, y, w, "DATA", "%.0f MB" % float(s["data_capture_mb"]), "cap %.0f MB" % float(s["data_capacity_mb"]), float(s["data_capture_mb"]) <= float(s["data_capacity_mb"]))
	y += 15.0
	_metric_row(rect.position.x + 7, y, w, "SENSOR", "Q%d" % int(s["sensor_quality"]), "need Q%d" % int(campaign.content.requirements.get("minimum_sensor_quality", 2)), int(s["sensor_quality"]) >= int(campaign.content.requirements.get("minimum_sensor_quality", 2)))

	# Preflight block. The metrics above end at a known y, so start below it.
	y = maxf(rect.position.y + 132.0, y + 10.0)
	draw_rect(Rect2(rect.position.x + 6, y, rect.size.x - 12, 1), SFPalette.STEEL_DARK, true)
	y += 5.0
	skin.text(self, Vector2(rect.position.x + 6, y), "PREFLIGHT", SFPalette.CYAN)
	y += 13.0

	if not checks_run:
		skin.wrap(self, Vector2(rect.position.x + 6, y), rect.size.x - 12,
			"Not run. Press V to validate the design.", SFPalette.PAPER_DIM, 1, 2)
		y += 22.0
	else:
		# Leave room for the confirm button and its caption at the bottom.
		var list_bottom: float = rect.end.y - 56.0
		var shown := 0
		for c in checks:
			var check: Dictionary = c
			if not bool(check.get("blocking", true)):
				continue
			if shown >= 8 or y > list_bottom - 10.0:
				break
			var ok := bool(check.get("ok", false))
			var color: Color = SFPalette.GREEN_OK if ok else SFPalette.RED
			draw_rect(Rect2(rect.position.x + 7, y + 2, 4, 4), color, true)
			var msg := String(check.get("message", ""))
			# Advance by the height actually drawn, so a wrapped message never
			# runs into the next one.
			var next_y: float = skin.wrap(self, Vector2(rect.position.x + 15, y), rect.size.x - 22,
				msg, SFPalette.PAPER if ok else SFPalette.RED, 1, 3)
			y = next_y + 2.0
			shown += 1
		# Actionable hint from the first failure only, to keep it focused.
		var first: Dictionary = d.first_blocking_failure(campaign.content)
		var hint := String(first.get("hint", ""))
		if hint != "" and y < list_bottom - 14.0:
			y += 3.0
			skin.wrap(self, Vector2(rect.position.x + 6, y), rect.size.x - 12, hint, SFPalette.GOLD, 1, 3)

	var valid: bool = d.is_valid(campaign.content)
	var confirm_rect := Rect2(rect.position.x + 6, rect.end.y - 38, rect.size.x - 12, 16)
	skin.button(self, confirm_rect, "ENTER  CONFIRM DESIGN", valid and checks_run, valid, SFPalette.GREEN_OK if valid else SFPalette.STEEL_DARK)
	skin.text_c(self, rect.position.x + rect.size.x * 0.5, rect.end.y - 18, "V  RUN PREFLIGHT CHECK", SFPalette.PAPER_DIM)


func _metric_row(x: float, y: float, w: float, label: String, value: String, target: String, good: bool) -> void:
	skin.text(self, Vector2(x, y), label, SFPalette.PAPER_DIM)
	var c: Color = SFPalette.PAPER if good else SFPalette.RED
	skin.text(self, Vector2(x + 60, y), value, c)
	skin.text_r(self, x + w, y, target, SFPalette.ASH_LIGHT)
