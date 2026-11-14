extends Node2D
## The assembly workshop: the whole spacecraft construction and preflight loop
## as one self-contained screen, laid out as a room.
##
## Parts sit on shelves along the walls, one shelf per slot, plus a fuel rack.
## The frame stands on a cradle in the middle. The flight-readiness dashboard
## runs along the bottom, so every number that gates launch is always visible.
## The inspector is a clipboard that opens over the cradle with the focused
## part's spec sheet and what installing it does to readiness.
##
## This screen owns no campaign state. It edits a working copy of the design
## through the campaign object and reports completion through signals; the main
## controller decides what happens next.
##
## Controls
##   UP/DOWN      move between shelves
##   LEFT/RIGHT   move along the shelf (on the fuel rack: adjust the load)
##   ENTER        install the focused part, or remove it if it is installed
##   I / TAB      open or close the inspector for the focused part
##   Q / E        adjust the fuel load in steps
##   V            run preflight validation
##   L            confirm the design (atomic: validates, then commits)
##   ESC          close the inspector, else leave the workshop (design is kept)
##   Mouse        hover focuses a part, left click installs, right click inspects

signal closed
signal design_confirmed_ok

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFDesign := preload("res://core/star_fall/sf_design.gd")

const SHELVES := ["computer", "propulsion", "power", "communications", "sensor", "fuel"]
const SHELF_W := 164.0
const SHELF_H := 68.0
const SHIP_GROUND := Vector2(320, 238)
const DASH := Rect2(8, 258, 624, 76)
const INSPECTOR := Rect2(196, 34, 248, 190)

var skin
var ui
var campaign

var shelf_index: int = 0
var focus: Dictionary = {}      # slot -> focused item index on that shelf
var inspecting: bool = false
var checks_run: bool = false
var fuel_flash: float = 0.0
var _blink: float = 0.0
var _hits: Array = []           # [{rect, shelf, item}] rebuilt each draw, for the mouse
var _check_btn := Rect2()
var _confirm_btn := Rect2()


func setup(skin_ref, ui_ref, campaign_ref) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref


func _ready() -> void:
	# Each shelf starts focused on whatever is already installed there.
	for s in SFDesign.SLOTS:
		var slot := String(s)
		focus[slot] = maxi(0, _index_of(slot, String(campaign.design.slot_component(slot))))
	queue_redraw()


func _index_of(slot: String, id: String) -> int:
	var options: Array = campaign.content.components_for_slot(slot)
	for i in options.size():
		if String((options[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func _current_slot() -> String:
	return String(SHELVES[shelf_index])


func _focused_part() -> Dictionary:
	var slot := _current_slot()
	if slot == "fuel":
		return {}
	var options: Array = campaign.content.components_for_slot(slot)
	if options.is_empty():
		return {}
	var i: int = clampi(int(focus.get(slot, 0)), 0, options.size() - 1)
	return options[i] as Dictionary


func _shelf_rect(i: int) -> Rect2:
	var x: float = 8.0 if i < 3 else 640.0 - 8.0 - SHELF_W
	return Rect2(x, 34.0 + float(i % 3) * (SHELF_H + 4.0), SHELF_W, SHELF_H)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit := _hit_at(get_global_mouse_position())
		if not hit.is_empty():
			_focus_hit(hit)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_handle_click(mb.button_index, get_global_mouse_position())
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_UP, KEY_W:
			_move_shelf(-1)
		KEY_DOWN, KEY_S:
			_move_shelf(1)
		KEY_LEFT, KEY_A:
			_move_item(-1)
		KEY_RIGHT, KEY_D:
			_move_item(1)
		KEY_Q:
			_adjust_fuel(-1)
		KEY_E:
			_adjust_fuel(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_toggle_install()
		KEY_I, KEY_TAB:
			inspecting = not inspecting
			skin.audio.sfx_select()
			queue_redraw()
		KEY_V:
			_run_preflight()
		KEY_L:
			_confirm()
		KEY_ESCAPE:
			skin.audio.sfx_back()
			if inspecting:
				inspecting = false
				queue_redraw()
			else:
				closed.emit()


func _hit_at(pos: Vector2) -> Dictionary:
	for h in _hits:
		if (h["rect"] as Rect2).has_point(pos):
			return h
	return {}


func _focus_hit(hit: Dictionary) -> void:
	shelf_index = int(hit["shelf"])
	focus[_current_slot()] = int(hit["item"])
	queue_redraw()


func _handle_click(button: int, pos: Vector2) -> void:
	if button == MOUSE_BUTTON_LEFT:
		if _check_btn.has_point(pos):
			_run_preflight()
			return
		if _confirm_btn.has_point(pos):
			_confirm()
			return
	var hit := _hit_at(pos)
	if hit.is_empty():
		return
	_focus_hit(hit)
	if button == MOUSE_BUTTON_LEFT:
		_toggle_install()
	elif button == MOUSE_BUTTON_RIGHT:
		inspecting = true
		skin.audio.sfx_select()


func _move_shelf(delta: int) -> void:
	shelf_index = int(fposmod(float(shelf_index + delta), float(SHELVES.size())))
	skin.audio.sfx_select()
	queue_redraw()


func _move_item(delta: int) -> void:
	var slot := _current_slot()
	if slot == "fuel":
		_adjust_fuel(delta)
		return
	var n: int = campaign.content.components_for_slot(slot).size()
	if n == 0:
		return
	focus[slot] = int(fposmod(float(int(focus.get(slot, 0)) + delta), float(n)))
	skin.audio.sfx_select()
	queue_redraw()


func _toggle_install() -> void:
	var comp := _focused_part()
	if comp.is_empty():
		skin.audio.sfx_denied()
		return
	var slot := _current_slot()
	var id := String(comp.get("id", ""))
	if String(campaign.design.slot_component(slot)) == id:
		campaign.design.clear_slot(slot)
		skin.audio.sfx_remove()
	else:
		campaign.design.set_slot(slot, id)
		skin.audio.sfx_install()
	# A design change always invalidates the previous validation result.
	checks_run = false
	queue_redraw()


func _adjust_fuel(steps: int) -> void:
	var before: float = campaign.design.fuel_kg
	campaign.design.adjust_fuel(steps, campaign.content)
	if is_equal_approx(before, campaign.design.fuel_kg):
		skin.audio.sfx_denied()
	else:
		skin.audio.sfx_select()
		fuel_flash = 0.25
	checks_run = false
	queue_redraw()


# ---------------------------------------------------------------- actions

func _run_preflight() -> void:
	checks_run = true
	if campaign.design.is_valid(campaign.content):
		skin.audio.sfx_confirm()
		Events.preflight_passed.emit()
	else:
		skin.audio.sfx_denied()
		var first: Dictionary = campaign.design.first_blocking_failure(campaign.content)
		Events.preflight_failed.emit(String(first.get("message", "")))
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
	_hits = []
	_draw_room()
	ui.header(self, "VELA ASSEMBLY WORKSHOP", "Pick parts off the shelves. Fly when the dashboard is all green.",
		["BUDGET %d CR" % int(campaign.credits), "MISSION: SIGNAL INVESTIGATION"])
	for i in SHELVES.size():
		var slot := String(SHELVES[i])
		if slot == "fuel":
			_draw_fuel_rack(i, _shelf_rect(i))
		else:
			_draw_shelf(i, slot, _shelf_rect(i))
	_draw_assembled_ship(SHIP_GROUND)
	_draw_dashboard(DASH)
	if inspecting:
		_draw_inspector(INSPECTOR)
	ui.footer(self, [
		"UP/DOWN:SHELF", "LEFT/RIGHT:PART", "ENTER:INSTALL", "I:INSPECT",
		"Q/E:FUEL", "V:CHECK", "L:CONFIRM", "ESC:BACK",
	])
	ui.toast(self)


func _draw_room() -> void:
	draw_rect(Rect2(0, 0, 640, 360), SFPalette.INK, true)
	# Back wall with panel seams, then the floor.
	draw_rect(Rect2(0, 27, 640, 213), SFPalette.RUIN_DARK, true)
	var x := 32.0
	while x < 640.0:
		draw_rect(Rect2(x, 27, 1, 213), SFPalette.RUIN, true)
		x += 64.0
	draw_rect(Rect2(0, 240, 640, 18), SFPalette.ASH_PLAIN, true)
	draw_rect(Rect2(0, 240, 640, 1), SFPalette.ASH_PLAIN_LIGHT, true)
	# Hazard stripe around the cradle.
	var sx := 250.0
	while sx < 390.0:
		draw_rect(Rect2(sx, 244, 6, 2), SFPalette.GOLD, true)
		sx += 12.0
	# Work lamps over the cradle.
	for lx in [280.0, 360.0]:
		var fx := float(lx)
		draw_rect(Rect2(fx - 1, 27, 2, 10), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(fx - 5, 37, 10, 3), SFPalette.STEEL, true)
		draw_rect(Rect2(fx - 3, 40, 6, 1), SFPalette.GOLD, true)


func _draw_shelf(i: int, slot: String, r: Rect2) -> void:
	var options: Array = campaign.content.components_for_slot(slot)
	var focused_shelf: bool = i == shelf_index
	var installed: String = String(campaign.design.slot_component(slot))
	var fi: int = clampi(int(focus.get(slot, 0)), 0, maxi(0, options.size() - 1))

	if focused_shelf:
		draw_rect(r.grow(2), SFPalette.CYAN_DIM, false, 1.0)

	# Shelf label tag and slot state.
	skin.text(self, Vector2(r.position.x + 2, r.position.y), String(SFPalette.SLOT_NAMES.get(slot, slot)),
		SFPalette.CYAN if focused_shelf else SFPalette.PAPER_DIM)
	if installed == "":
		var c: Color = SFPalette.RED
		c.a = 0.6 + 0.4 * sin(_blink * 4.0)
		skin.text_r(self, r.end.x - 2, r.position.y, "EMPTY", c)
	else:
		skin.text_r(self, r.end.x - 2, r.position.y, "INSTALLED", SFPalette.GREEN_OK)

	# Wall bracket and plank.
	var plank_y := r.position.y + 44.0
	draw_rect(Rect2(r.position.x, plank_y, r.size.x, 4), SFPalette.STEEL_MID if focused_shelf else SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(r.position.x, plank_y + 4, r.size.x, 1), SFPalette.SOOT, true)
	for bx in [r.position.x + 6.0, r.end.x - 9.0]:
		draw_rect(Rect2(float(bx), plank_y + 5, 3, 7), SFPalette.STEEL_DARK, true)

	# Parts on the plank, each in its own bay.
	var bay_w := 44.0
	var x0 := r.position.x + (r.size.x - bay_w * float(options.size())) * 0.5
	for k in options.size():
		var comp: Dictionary = options[k] as Dictionary
		var id := String(comp.get("id", ""))
		var bay := Rect2(x0 + bay_w * float(k) + 2.0, plank_y - 32.0, bay_w - 4.0, 32.0)
		_hits.append({"rect": bay, "shelf": i, "item": k})
		var is_focus: bool = focused_shelf and k == fi
		var is_in: bool = id == installed
		if is_focus:
			draw_rect(bay, SFPalette.RUIN, true)
			draw_rect(bay, SFPalette.CYAN, false, 1.0)
		elif is_in:
			draw_rect(bay, SFPalette.GREEN_OK.darkened(0.45), false, 1.0)
		_draw_part_icon(Vector2(bay.position.x + bay.size.x * 0.5, plank_y - 2.0), comp, is_in or is_focus)
		# Price tag hanging from the plank.
		skin.text_c(self, bay.position.x + bay.size.x * 0.5, plank_y + 7.0, "%dCR" % int(comp.get("cost", 0)),
			SFPalette.GOLD if is_focus else SFPalette.PAPER_DIM)

	# Name line: the focused part on the active shelf, else what is installed.
	var show: int = fi if focused_shelf else _index_of(slot, installed)
	if show >= 0 and show < options.size():
		var name := String(skin.font.fit(String((options[show] as Dictionary).get("name", "")), r.size.x - 4.0, 1))
		skin.text_c(self, r.position.x + r.size.x * 0.5, plank_y + 16.0, name, SFPalette.PAPER if focused_shelf else SFPalette.PAPER_DIM)


## Small pixel icon of a part, standing on the point p. Shape follows the slot;
## size follows the stat that matters for that slot (lift, output, quality).
func _draw_part_icon(p: Vector2, comp: Dictionary, lit: bool) -> void:
	var glow: Color = SFPalette.CYAN if lit else SFPalette.CYAN_DIM
	match String(comp.get("slot", "")):
		"computer":
			draw_rect(Rect2(p.x - 9, p.y - 14, 18, 14), SFPalette.STEEL_MID, true)
			draw_rect(Rect2(p.x - 7, p.y - 11, 14, 4), SFPalette.INK, true)
			draw_rect(Rect2(p.x - 6, p.y - 10, 8, 2), glow, true)
			draw_rect(Rect2(p.x - 7, p.y - 5, 2, 2), SFPalette.GREEN_OK, true)
		"propulsion":
			var w: float = 10.0 + float(comp.get("thrust_capacity_kg", 0)) / 240.0
			draw_rect(Rect2(p.x - w * 0.3, p.y - 22, w * 0.6, 8), SFPalette.STEEL_DARK, true)
			draw_rect(Rect2(p.x - w * 0.5, p.y - 14, w, 12), SFPalette.STEEL_DARK, true)
			draw_rect(Rect2(p.x - w * 0.5 + 1, p.y - 14, 3, 12), SFPalette.STEEL_MID, true)
			draw_rect(Rect2(p.x - w * 0.5, p.y - 3, w, 3), SFPalette.RUST, true)
		"power":
			if float(comp.get("power_output_w", 0)) >= 400.0:
				draw_rect(Rect2(p.x - 6, p.y - 22, 12, 22), SFPalette.ASH, true)
				draw_rect(Rect2(p.x - 5, p.y - 16, 10, 2), SFPalette.GOLD, true)
				draw_rect(Rect2(p.x - 5, p.y - 8, 10, 2), SFPalette.GOLD, true)
			else:
				draw_rect(Rect2(p.x - 14, p.y - 18, 28, 14), SFPalette.BLUE_ACCENT, true)
				for k in 5:
					draw_rect(Rect2(p.x - 12 + k * 6, p.y - 17, 1, 12), glow, true)
				draw_rect(Rect2(p.x - 1, p.y - 4, 2, 4), SFPalette.STEEL_DARK, true)
		"communications":
			draw_rect(Rect2(p.x - 1, p.y - 14, 2, 14), SFPalette.STEEL_DARK, true)
			draw_rect(Rect2(p.x - 8, p.y - 18, 16, 3), SFPalette.STEEL, true)
			draw_rect(Rect2(p.x - 4, p.y - 23, 8, 5), SFPalette.STEEL_MID, true)
			draw_rect(Rect2(p.x - 1, p.y - 22, 2, 2), glow, true)
		"sensor":
			var q := int(comp.get("sensor_quality", 0))
			var r := 4.0 + float(q) * 2.0
			draw_rect(Rect2(p.x - r, p.y - r * 2, r * 2, r * 2), SFPalette.STEEL_DARK, true)
			draw_rect(Rect2(p.x - r + 1, p.y - r * 2 + 1, r * 2 - 2, r * 2 - 2), SFPalette.CYAN_DIM, true)
			var lens: Color = SFPalette.CYAN
			if q >= 3:
				lens = SFPalette.GREEN_OK
			elif q <= 1:
				lens = SFPalette.RUST_LIGHT
			draw_rect(Rect2(p.x - 2, p.y - r * 2 + 2, 4, 3), lens, true)


func _draw_fuel_rack(i: int, r: Rect2) -> void:
	var focused_shelf: bool = i == shelf_index
	var d = campaign.design
	var cap := float(campaign.content.hull.get("fuel_capacity_kg", 0.0))
	var min_fuel := float(campaign.content.requirements.get("minimum_fuel_kg", 0.0))
	var ok: bool = d.fuel_kg >= min_fuel

	if focused_shelf:
		draw_rect(r.grow(2), SFPalette.CYAN_DIM, false, 1.0)
	skin.text(self, Vector2(r.position.x + 2, r.position.y), "FUEL RACK", SFPalette.CYAN if focused_shelf else SFPalette.PAPER_DIM)
	skin.text_r(self, r.end.x - 2, r.position.y, "%d / %d KG" % [int(d.fuel_kg), int(cap)], SFPalette.PAPER if ok else SFPalette.RED)

	# A horizontal propellant tank with a sight glass and the mission minimum.
	var tank := Rect2(r.position.x + 10, r.position.y + 14, r.size.x - 20, 22)
	draw_rect(tank, SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(tank.position.x + 2, tank.position.y + 2, tank.size.x - 4, 4), SFPalette.STEEL_MID, true)
	var glass := Rect2(tank.position.x + 6, tank.position.y + 8, tank.size.x - 12, 9)
	draw_rect(glass, SFPalette.INK, true)
	var ratio := clampf(d.fuel_kg / maxf(1.0, cap), 0.0, 1.0)
	var fill: Color = SFPalette.CYAN if ok else SFPalette.RED
	if fuel_flash > 0.0:
		fill = SFPalette.PAPER
	draw_rect(Rect2(glass.position, Vector2(round(glass.size.x * ratio), glass.size.y)), fill, true)
	var mx: float = glass.position.x + round(glass.size.x * clampf(min_fuel / maxf(1.0, cap), 0.0, 1.0))
	draw_rect(Rect2(mx, glass.position.y - 2, 1, glass.size.y + 4), SFPalette.GOLD, true)
	draw_rect(glass, SFPalette.STEEL_DARK, false, 1.0)
	draw_rect(Rect2(tank.position.x + 8, tank.end.y, 4, 4), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(tank.end.x - 12, tank.end.y, 4, 4), SFPalette.STEEL_DARK, true)
	skin.text_c(self, mx, tank.end.y + 6, "MIN %d" % int(min_fuel), SFPalette.GOLD)
	skin.text_c(self, r.position.x + r.size.x * 0.5, r.end.y - 9, "Q / E  ADJUST LOAD",
		SFPalette.PAPER_DIM if focused_shelf else SFPalette.ASH_LIGHT)


func _draw_dashboard(r: Rect2) -> void:
	skin.panel(self, r, Color(0.05, 0.08, 0.09), SFPalette.STEEL_DARK, true)
	var d = campaign.design
	var s: Dictionary = d.summary(campaign.content)
	var req: Dictionary = campaign.content.requirements
	var budget := float(campaign.content.program.get("start_credits", 100.0))
	var valid: bool = d.is_valid(campaign.content)
	var all_slots: bool = int(s["slots_filled"]) == int(s["slots_total"])

	skin.text(self, r.position + Vector2(6, 4), "FLIGHT READINESS", SFPalette.CYAN)
	skin.text_r(self, r.end.x - 6, r.position.y + 4, "%d / %d SLOTS FILLED" % [int(s["slots_filled"]), int(s["slots_total"])],
		SFPalette.GREEN_OK if all_slots else SFPalette.RED)

	# One gauge per launch requirement: [label, value, target, ratio, at_most].
	# at_most gauges pass when ratio <= 1 (mass, power, cost, data); the others
	# pass when ratio >= 1 (fuel, energy, sensor).
	var min_fuel := float(req.get("minimum_fuel_kg", 0.0))
	var min_q := int(req.get("minimum_sensor_quality", 0))
	var gauges: Array = [
		["MASS", "%.0f KG" % float(s["wet_mass_kg"]), "/ %.0f LIMIT" % float(s["mass_limit_kg"]),
			float(s["wet_mass_kg"]) / maxf(1.0, float(s["mass_limit_kg"])), true],
		["FUEL", "%.0f KG" % float(s["fuel_kg"]), "/ %.0f MIN" % min_fuel,
			float(s["fuel_kg"]) / maxf(1.0, min_fuel), false],
		["POWER", "%.0f W" % float(s["power_demand_w"]), "/ %.0f SUPPLY" % float(s["power_output_w"]),
			float(s["power_demand_w"]) / maxf(1.0, float(s["power_output_w"])), true],
		["ENERGY", "%.0f WH" % float(s["energy_stored_wh"]), "/ %.0f NEED" % float(s["energy_required_wh"]),
			float(s["energy_stored_wh"]) / maxf(1.0, float(s["energy_required_wh"])), false],
		["BUDGET", "%d CR" % int(s["cost"]), "/ %d CR" % int(budget),
			float(s["cost"]) / maxf(1.0, budget), true],
		["SENSOR", "Q%d" % int(s["sensor_quality"]), "/ Q%d MIN" % min_q,
			float(s["sensor_quality"]) / maxf(1.0, float(min_q)), false],
		["DATA", "%.0f MB" % float(s["data_capture_mb"]), "/ %.0f CAP" % float(s["data_capacity_mb"]),
			float(s["data_capture_mb"]) / maxf(1.0, float(s["data_capacity_mb"])), true],
	]
	var gw := (r.size.x - 12.0) / float(gauges.size())
	var gy := r.position.y + 15.0
	for k in gauges.size():
		var g: Array = gauges[k] as Array
		var gx := r.position.x + 6.0 + gw * float(k)
		var ratio := float(g[3])
		var good: bool = ratio <= 1.0 if bool(g[4]) else ratio >= 1.0
		var c: Color = SFPalette.GREEN_OK if good else SFPalette.RED
		skin.text(self, Vector2(gx, gy), String(g[0]), SFPalette.PAPER_DIM)
		skin.text(self, Vector2(gx, gy + 9), String(g[1]), c)
		skin.text(self, Vector2(gx, gy + 18), String(g[2]), SFPalette.ASH_LIGHT)
		skin.bar(self, Vector2(gx, gy + 27), Vector2(gw - 8.0, 4), ratio, c)

	# Status line: the first thing blocking launch, with its fix, and the buttons.
	var sy := r.position.y + 51.0
	draw_rect(Rect2(r.position.x + 6, sy - 3, r.size.x - 12, 1), SFPalette.STEEL_DARK, true)
	_check_btn = Rect2(r.end.x - 198, sy + 1, 94, 16)
	_confirm_btn = Rect2(r.end.x - 100, sy + 1, 94, 16)
	skin.button(self, _check_btn, "V  PREFLIGHT", false, true)
	skin.button(self, _confirm_btn, "L  CONFIRM", valid and checks_run, valid, SFPalette.GREEN_OK if valid else SFPalette.STEEL_DARK)
	var msg_w := _check_btn.position.x - r.position.x - 24.0
	var first: Dictionary = d.first_blocking_failure(campaign.content)
	var dot_c: Color = SFPalette.GREEN_OK if first.is_empty() else SFPalette.RED
	draw_rect(Rect2(r.position.x + 8, sy + 3, 4, 4), dot_c, true)
	if first.is_empty():
		var line := "ALL REQUIREMENTS MET." + ("  CONFIRM TO BUILD." if checks_run else "  RUN PREFLIGHT, THEN CONFIRM.")
		skin.text(self, Vector2(r.position.x + 16, sy + 1), line, SFPalette.GREEN_OK)
	else:
		skin.text(self, Vector2(r.position.x + 16, sy + 1), String(skin.font.fit(String(first.get("message", "")), msg_w, 1)), SFPalette.RED)
		skin.text(self, Vector2(r.position.x + 16, sy + 11), String(skin.font.fit(String(first.get("hint", "")), msg_w, 1)), SFPalette.GOLD)


## Clipboard over the cradle: the focused part's spec sheet, and what the
## design's readiness numbers become if it is installed (or removed).
func _draw_inspector(box: Rect2) -> void:
	skin.panel(self, box, Color(0.04, 0.07, 0.08, 0.97), SFPalette.CYAN, true)
	var x := box.position.x + 8.0
	var w := box.size.x - 16.0
	var y := box.position.y + 6.0
	var d = campaign.design
	var content = campaign.content
	var cur: Dictionary = d.summary(content)
	var comp := _focused_part()

	if comp.is_empty():
		skin.text(self, Vector2(x, y), "FUEL RACK", SFPalette.CYAN)
		y += 12.0
		y = skin.wrap(self, Vector2(x, y), w,
			"Rocket propellant, in kilograms. It is not electrical energy. Every kilogram loaded is launch mass the propulsion must lift.",
			SFPalette.PAPER, 1, 5) + 4.0
		skin.stat_row(self, Vector2(x, y), "LOADED", "%.0f KG" % float(cur["fuel_kg"]), SFPalette.PAPER, w)
		y += 10.0
		skin.stat_row(self, Vector2(x, y), "MISSION MINIMUM", "%.0f KG" % float(content.requirements.get("minimum_fuel_kg", 0.0)), SFPalette.GOLD, w)
		y += 10.0
		skin.stat_row(self, Vector2(x, y), "TANK CAPACITY", "%.0f KG" % float(cur["fuel_capacity_kg"]), SFPalette.PAPER, w)
		y += 10.0
		skin.stat_row(self, Vector2(x, y), "DRY MASS", "%.0f KG" % float(cur["dry_mass_kg"]), SFPalette.PAPER, w)
		y += 10.0
		skin.stat_row(self, Vector2(x, y), "LAUNCH MASS", "%.0f / %.0f KG" % [float(cur["wet_mass_kg"]), float(cur["mass_limit_kg"])],
			SFPalette.PAPER if float(cur["wet_mass_kg"]) <= float(cur["mass_limit_kg"]) else SFPalette.RED, w)
		skin.text_c(self, box.position.x + box.size.x * 0.5, box.end.y - 12, "I  CLOSE", SFPalette.PAPER_DIM)
		return

	var slot := String(comp.get("slot", ""))
	var id := String(comp.get("id", ""))
	var installed: bool = String(d.slot_component(slot)) == id
	skin.text(self, Vector2(x, y), String(skin.font.fit(String(comp.get("name", id)).to_upper(), w - 44.0, 1)), SFPalette.CYAN)
	skin.text_r(self, box.end.x - 8, y, "%d CR" % int(comp.get("cost", 0)), SFPalette.GOLD)
	y += 10.0
	skin.text(self, Vector2(x, y), String(SFPalette.SLOT_NAMES.get(slot, slot)), SFPalette.PAPER_DIM)
	if installed:
		skin.tag(self, Rect2(box.end.x - 60, y - 2, 52, 10), "INSTALLED", SFPalette.GREEN_OK)
	y += 12.0
	y = skin.wrap(self, Vector2(x, y), w, String(comp.get("description", "")), SFPalette.PAPER, 1, 4) + 2.0
	draw_rect(Rect2(x, y, w, 1), SFPalette.STEEL_DARK, true)
	y += 5.0

	# Spec sheet: only the numbers this part actually has.
	var specs: Array = [
		["MASS", "mass_kg", "%d KG", true],
		["POWER DRAW", "power_demand_w", "%d W", false],
		["POWER OUTPUT", "power_output_w", "%d W", false],
		["ENERGY STORAGE", "energy_storage_wh", "%d WH", false],
		["LIFT CAPACITY", "thrust_capacity_kg", "%d KG", false],
		["SENSOR QUALITY", "sensor_quality", "Q%d", false],
		["DATA YIELD", "data_gain_mb", "%d MB", false],
	]
	for spec in specs:
		var row: Array = spec as Array
		var v := int(comp.get(String(row[1]), 0))
		if v == 0 and not bool(row[3]):
			continue
		skin.stat_row(self, Vector2(x, y), String(row[0]), String(row[2]) % v, SFPalette.PAPER, w)
		y += 10.0

	# Readiness after the change, from a throwaway copy of the design.
	y += 2.0
	draw_rect(Rect2(x, y, w, 1), SFPalette.STEEL_DARK, true)
	y += 5.0
	skin.text(self, Vector2(x, y), "IF REMOVED" if installed else "IF INSTALLED", SFPalette.CYAN)
	y += 10.0
	var trial = SFDesign.new()
	trial.load_dict(d.to_dict())
	if installed:
		trial.clear_slot(slot)
	else:
		trial.set_slot(slot, id)
	var ts: Dictionary = trial.summary(content)
	var budget := float(content.program.get("start_credits", 100.0))
	_delta_row(x, y, w, "MASS", float(cur["wet_mass_kg"]), float(ts["wet_mass_kg"]), float(ts["mass_limit_kg"]), "KG", true)
	y += 10.0
	_delta_row(x, y, w, "POWER", float(cur["power_demand_w"]), float(ts["power_demand_w"]), float(ts["power_output_w"]), "W", true)
	y += 10.0
	_delta_row(x, y, w, "ENERGY", float(cur["energy_stored_wh"]), float(ts["energy_stored_wh"]), float(ts["energy_required_wh"]), "WH", false)
	y += 10.0
	_delta_row(x, y, w, "COST", float(cur["cost"]), float(ts["cost"]), budget, "CR", true)

	skin.text_c(self, box.position.x + box.size.x * 0.5, box.end.y - 12,
		"ENTER  REMOVE     I  CLOSE" if installed else "ENTER  INSTALL     I  CLOSE", SFPalette.PAPER_DIM)


func _delta_row(x: float, y: float, w: float, label: String, before: float, after: float, target: float, unit: String, at_most: bool) -> void:
	var good: bool = after <= target if at_most else after >= target
	skin.text(self, Vector2(x, y), label, SFPalette.PAPER_DIM)
	skin.text_r(self, x + w, y, "%.0f > %.0f / %.0f %s" % [before, after, target, unit], SFPalette.GREEN_OK if good else SFPalette.RED)


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
