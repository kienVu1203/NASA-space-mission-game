extends Node2D
## The Phase 3 VELA reconstruction workshop at the crash-site base. Keyboard
## and mouse: every part card, design row and action row is clickable. The rules live in core/star_fall/sf_reconstruction.gd and the physics
## in sf_return_sim.gd; this screen fits recovered parts to the frame, edits a
## selection, shows a free live preview, certifies a report on request, and
## asks the rules to fabricate once.
##
## Layout: the VELA in its repair bay with three visible sockets (left top),
## the recovered-component tray (left middle), salvage and fabrication cost
## (left bottom), the design rows, a one-line detail for the focused row, and
## the compact simulation report (right). The footer always states the next
## step.
##
## Controls
##   UP / DOWN       choose a row (the first row is the component tray)
##   LEFT / RIGHT    tray: choose a part; rows: change the option
##                   (fuel: -/+ 20 kg; SHIFT: 100 kg)
##   ENTER / SPACE   tray: install the chosen part (its socket is previewed
##                   while it is chosen); rows: toggle payload or run the action
##   V               run the simulation (certifies a report for this design)
##   F               fabricate and assemble (needs a passing, current report)
##   C               scavenge common materials up to the fair floor
##   ESC             leave the workshop (the selection is kept)
##   MOUSE           click a part card to fit it; click a row to select it,
##                   its < / > halves to change it, an action row to run it;
##                   LEAVE button leaves

signal closed
signal assembled

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFReconstruction := preload("res://core/star_fall/sf_reconstruction.gd")
const SFContent := preload("res://core/star_fall/sf_content.gd")

const VW := 640
const VH := 360
const SIM_SEED := 30303
const ROWS := ["components", "propulsion", "fuel", "protection", "storage", "environmental_samples",
	"additional_records", "route", "simulate", "scavenge", "fabricate"]
const COMPONENTS := ["navigation_chip", "power_core", "shield_emitter"]
const COMPONENT_SHORT := {"navigation_chip": "NAV CHIP", "power_core": "POWER CORE", "shield_emitter": "SHIELD"}
## Socket centres on the bay drawing, relative to the ship's centre.
const SFVela := preload("res://core/star_fall/sf_vela.gd")
## The workshop shows the canonical VELA at twice the finale's pixel scale.
const VELA_SCALE := 2

const BAY := Rect2(8, 30, 310, 150)
const TRAY := Rect2(8, 184, 310, 56)
const COST := Rect2(8, 244, 310, 78)
const DESIGN := Rect2(324, 30, 308, 150)
const DETAIL := Rect2(324, 184, 308, 36)
const REPORT := Rect2(324, 224, 308, 98)
const LEAVE_BUTTON := Rect2(560, 342, 70, 14)

var skin
var ui
var campaign
var workshop
var row: int = 0
var tray_index: int = 0
var report: Dictionary = {}        # the certified report, cleared by any change
var preview: Dictionary = {}       # always-current free preview
var input_locked: bool = false
var time: float = 0.0
var message: String = ""
var message_tone: String = "info"
var message_timer: float = 0.0
var install_flash_id: String = ""
var install_flash: float = 0.0
var recon_data: Dictionary = {}


func setup(skin_ref, ui_ref, campaign_ref) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	workshop = SFReconstruction.new()
	recon_data = SFContent.read_json("res://data/star_fall/reconstruction.json") as Dictionary
	var saved: Dictionary = campaign.reconstruction.get("committed", campaign.reconstruction.get("selection", {})) as Dictionary
	workshop.setup(recon_data, campaign.original_propulsion_id(), saved)
	# Open on the tray while a part still needs fitting, on the design otherwise.
	row = 0 if not campaign.all_required_installed() else 1
	for i in COMPONENTS.size():
		if _state(String(COMPONENTS[i])) == "ready":
			tray_index = i
			break
	_refresh_preview()


func is_locked_design() -> bool:
	return campaign.is_ready_for_final_assembly()


## "missing" (not recovered), "ready" (recovered, not fitted) or "fitted".
func _state(id: String) -> String:
	if campaign.is_component_installed(id):
		return "fitted"
	if campaign.has_component(id):
		return "ready"
	return "missing"


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event is InputEventMouseMotion:
		var hit := _hit_at(get_local_mouse_position())
		if not hit.is_empty() and _focus_hit(hit):
			skin.audio.sfx_select()
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			handle_click(get_local_mouse_position())
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or input_locked:
		return
	get_viewport().set_input_as_handled()
	handle_key(key.keycode, key.shift_pressed)


func handle_key(keycode: int, shift: bool = false) -> void:
	match keycode:
		KEY_ESCAPE:
			skin.audio.sfx_back()
			_store()
			closed.emit()
			return
		KEY_UP, KEY_W:
			row = posmod(row - 1, ROWS.size())
			skin.audio.sfx_select()
		KEY_DOWN, KEY_S:
			row = posmod(row + 1, ROWS.size())
			skin.audio.sfx_select()
		KEY_LEFT, KEY_A:
			_change(-1, shift)
		KEY_RIGHT, KEY_D:
			_change(1, shift)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate()
		KEY_V:
			run_simulation()
		KEY_F:
			fabricate()
		KEY_C:
			scavenge()
	queue_redraw()


## Clickable regions, in the same geometry the drawing uses.
func _hit_at(pos: Vector2) -> Dictionary:
	if LEAVE_BUTTON.has_point(pos):
		return {"kind": "leave"}
	if TRAY.has_point(pos):
		var w := (TRAY.size.x - 16.0) / 3.0
		for i in COMPONENTS.size():
			var card := Rect2(round(TRAY.position.x + 5 + i * (w + 3)), TRAY.position.y + 5, round(w), TRAY.size.y - 10)
			if card.has_point(pos):
				return {"kind": "card", "index": i}
		return {}
	var y := DESIGN.position.y + 19.0
	for i in range(1, ROWS.size()):
		var rr := Rect2(DESIGN.position.x + 4, y - 1, DESIGN.size.x - 8, 12)
		if rr.has_point(pos):
			return {"kind": "row", "index": i, "rect": rr}
		y += 13.0
	return {}


## Hover focuses what is under the pointer. Returns true when focus changed.
func _focus_hit(hit: Dictionary) -> bool:
	match String(hit["kind"]):
		"card":
			if row == 0 and tray_index == int(hit["index"]):
				return false
			row = 0
			tray_index = int(hit["index"])
			return true
		"row":
			if row == int(hit["index"]):
				return false
			row = int(hit["index"])
			return true
	return false


## One click, one action: a card fits that part; a value row steps its option
## by the half that was clicked (left: back, right: forward); a toggle or an
## action row runs it; LEAVE leaves.
func handle_click(pos: Vector2) -> void:
	var hit := _hit_at(pos)
	if hit.is_empty():
		return
	match String(hit["kind"]):
		"leave":
			handle_key(KEY_ESCAPE)
			return
		"card":
			row = 0
			tray_index = int(hit["index"])
			install(String(COMPONENTS[tray_index]))
		"row":
			row = int(hit["index"])
			var id := String(ROWS[row])
			if id in ["propulsion", "fuel", "protection", "storage", "route"]:
				var rr: Rect2 = hit["rect"]
				# The value sits on the right; its left half steps back.
				if pos.x >= rr.end.x - 120.0:
					_change(-1 if pos.x < rr.end.x - 60.0 else 1, false)
				else:
					skin.audio.sfx_select()
			else:
				_activate()
	queue_redraw()


func _change(direction: int, shift: bool) -> void:
	var id := String(ROWS[row])
	if id == "components":
		tray_index = posmod(tray_index + direction, COMPONENTS.size())
		skin.audio.sfx_select()
		return
	if is_locked_design():
		_say("The VELA is already assembled.", "info")
		return
	match id:
		"propulsion", "protection", "storage", "route":
			workshop.cycle(id, direction)
		"fuel":
			workshop.adjust_fuel(direction * (5 if shift else 1))
			skin.audio.sfx_fuel_tick()
		"environmental_samples", "additional_records":
			workshop.toggle_optional(id)
		_:
			return
	_design_changed()


func _activate() -> void:
	match String(ROWS[row]):
		"components":
			install(String(COMPONENTS[tray_index]))
		"environmental_samples", "additional_records":
			_change(1, false)
		"simulate":
			run_simulation()
		"scavenge":
			scavenge()
		"fabricate":
			fabricate()


func _design_changed() -> void:
	skin.audio.sfx_install()
	if not report.is_empty():
		_say("Design changed: the previous report no longer applies.", "warn")
	report = {}
	_refresh_preview()
	_store()


## The simulation sees only the parts actually fitted to the frame.
func _refresh_preview() -> void:
	preview = workshop.simulate(campaign.installed_component_ids(), SIM_SEED)


func _store() -> void:
	campaign.store_reconstruction_selection(workshop.to_dict())


# ---------------------------------------------------------------- actions

## Fits one recovered component to the VELA. The campaign validates and
## records it; the screen only plays the installation.
func install(id: String) -> bool:
	match _state(id):
		"missing":
			skin.audio.sfx_denied()
			_say("Not recovered yet: %s." % _component_name(id), "bad")
			return false
		"fitted":
			skin.audio.sfx_denied()
			_say("%s is already fitted." % _component_name(id), "info")
			return false
	if not campaign.install_component(id):
		skin.audio.sfx_denied()
		_say("The VELA is already assembled.", "info")
		return false
	skin.audio.sfx_install()
	install_flash_id = id
	install_flash = 0.9
	_say("%s installed." % _component_name(id), "good")
	if not report.is_empty():
		_say("%s installed. Run the simulation again." % _component_name(id), "warn")
	report = {}
	_refresh_preview()
	_store()
	# Move on to the next part that still needs fitting, if any.
	for i in COMPONENTS.size():
		if _state(String(COMPONENTS[i])) == "ready":
			tray_index = i
			break
	return true


## Certifies a report for the current design. Free: nothing is spent.
func run_simulation() -> Dictionary:
	skin.audio.sfx_preflight_scan()
	report = workshop.simulate(campaign.installed_component_ids(), SIM_SEED)
	if bool(report["valid"]):
		skin.audio.sfx_preflight_pass()
		_say("Simulation passed. Fabrication is unlocked for this exact design.", "good")
	else:
		skin.audio.sfx_preflight_fail()
		_say("Simulation failed: %s" % String((report["failures"] as Array)[0]), "bad")
	return report


func fabricate() -> Dictionary:
	var result: Dictionary = workshop.commit(campaign, report)
	if bool(result["ok"]):
		skin.audio.sfx_confirm()
		_say(String(result["message"]), "good")
		assembled.emit()
	else:
		skin.audio.sfx_denied()
		_say(String(result["message"]), "bad")
	return result


func scavenge() -> Dictionary:
	var added: Dictionary = workshop.replenish(campaign)
	if added.is_empty():
		skin.audio.sfx_denied()
		_say("Common materials are already at the scavenging floor.", "info")
	else:
		skin.audio.sfx_pickup()
		var parts: Array = []
		for m in added.keys():
			parts.append("+%d %s" % [int(added[m]), campaign.content.material_name(String(m))])
		_say("Scavenged the crash site: " + ", ".join(parts), "good")
	return added


func _say(text: String, tone: String) -> void:
	message = text
	message_tone = tone
	message_timer = 4.0


func report_is_current() -> bool:
	return not report.is_empty() and String(report.get("signature", "")) == workshop.signature()


## The single most useful next action, shown whenever no message is active.
func next_step() -> String:
	if is_locked_design():
		return "Assembled. The VELA is ready for final assembly."
	for id in COMPONENTS:
		if _state(String(id)) == "missing":
			return "Recover the %s first." % _component_name(String(id)).to_lower()
	for id in COMPONENTS:
		if _state(String(id)) == "ready":
			return "Install the %s: choose its card, press ENTER." % _component_name(String(id)).to_lower()
	var rep: Dictionary = report if report_is_current() else preview
	if not bool(rep.get("valid", false)):
		var tips: Array = rep.get("suggestions", []) as Array
		if not tips.is_empty():
			return "Fix: " + String(tips[0])
		var fails: Array = rep.get("failures", []) as Array
		return "Fix: " + (String(fails[0]) if not fails.is_empty() else "revise the design.")
	if not report_is_current():
		return "Press V to certify this design."
	if workshop.fabrication_units() > workshop.fabrication_capacity():
		return "Too many fabrication units. Simplify the design."
	if not workshop.shortfall(campaign).is_empty():
		return "Not enough salvage. Press C to scavenge, then F."
	return "Press F to fabricate and assemble."


func _component_name(id: String) -> String:
	for c in recon_data.get("recovered_components", []) as Array:
		if String((c as Dictionary)["id"]) == id:
			return String((c as Dictionary)["name"])
	return id.replace("_", " ")


func _process(delta: float) -> void:
	time += delta
	message_timer = maxf(0.0, message_timer - delta)
	install_flash = maxf(0.0, install_flash - delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.RUIN_BG, true)
	ui.header(self, "VELA RECONSTRUCTION WORKSHOP")
	_draw_bay(BAY)
	_draw_tray(TRAY)
	_draw_cost(COST)
	_draw_design(DESIGN)
	_draw_detail(DETAIL)
	if report_is_current():
		_draw_report(REPORT, report, true)
	else:
		_draw_report(REPORT, preview, false)
	_draw_footer()


func _previewed_component() -> String:
	if String(ROWS[row]) != "components":
		return ""
	var id := String(COMPONENTS[tray_index])
	return id if _state(id) == "ready" else ""


## The VELA in its repair bay, side view, nose to the right. Each socket shows
## the real part once it is fitted, an empty dark socket otherwise, and a
## blinking ghost of the chosen part while its installation is previewed.
func _draw_bay(r: Rect2) -> void:
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), SFPalette.CYAN_DIM, true)
	var fitted := 0
	for id in COMPONENTS:
		if _state(String(id)) == "fitted":
			fitted += 1
	skin.text(self, r.position + Vector2(8, 6), "VELA", SFPalette.CYAN)
	skin.text_r(self, r.end.x - 8, r.position.y + 6, "PARTS FITTED %d / 3" % fitted, SFPalette.GREEN_OK if fitted == 3 else SFPalette.PAPER_DIM)
	var c := Vector2(r.position.x + r.size.x * 0.5 - 6.0, r.position.y + 92.0)
	_draw_vela(c)
	var ghost := _previewed_component()
	for id in COMPONENTS:
		_draw_socket(String(id), _socket_at(c, String(id)), String(id) == ghost)
	# The installation preview: the chosen part blinks in its socket above.
	if ghost != "":
		skin.text_c(self, r.position.x + r.size.x * 0.5, r.end.y - 12, "ENTER: FIT THE %s HERE" % String(COMPONENT_SHORT[ghost]), SFPalette.CYAN)
	elif is_locked_design():
		skin.text_c(self, r.position.x + r.size.x * 0.5, r.end.y - 12, "ASSEMBLED", SFPalette.GREEN_OK)


## The canonical VELA (core/star_fall/sf_vela.gd) in its maintenance view, at
## twice the finale's pixel scale. `c` is the hull's middle.
func _draw_vela(c: Vector2) -> void:
	var done := is_locked_design()
	# Cradle and floor.
	draw_rect(Rect2(c.x - 110, c.y + 30, 220, 2), SFPalette.STEEL_DARK, true)
	for i in 4:
		draw_rect(Rect2(c.x - 72 + i * 48, c.y + 18, 4, 12), SFPalette.RUST.darkened(0.2), true)
	skin.contact_shadow(self, c + Vector2(0, 30), 180.0, 0.25)
	var fitted: Array = []
	for id in COMPONENTS:
		if _state(String(id)) == "fitted":
			fitted.append(String(id))
	SFVela.draw(self, _vela_origin(c), VELA_SCALE, SFVela.MAINTENANCE,
		{"modules": fitted, "time": time, "damaged": not done, "assembled": done})


func _vela_origin(c: Vector2) -> Vector2:
	# Unit 51 along the hull is the middle of the workshop drawing.
	return c - Vector2(51.0 * float(VELA_SCALE), 0)


## Where a component's socket sits on screen: the renderer's module position.
func _socket_at(c: Vector2, id: String) -> Vector2:
	return SFVela.module_screen(_vela_origin(c), VELA_SCALE, SFVela.MAINTENANCE, id)


func _draw_socket(id: String, at: Vector2, previewed: bool) -> void:
	var sock := Rect2(round(at.x - 11), round(at.y - 9), 22, 18)
	var state := _state(id)
	var tex: Texture2D = skin.sprites.get(id, null)
	draw_rect(sock, SFPalette.INK, true)
	if state == "fitted" and tex != null:
		var size := tex.get_size()
		draw_texture_rect(tex, Rect2(round(at.x - size.x * 0.5), round(at.y - size.y * 0.5), size.x, size.y), false)
		draw_rect(sock, SFPalette.GREEN_OK, false, 1.0)
	elif previewed and tex != null:
		var blink := 0.35 + 0.35 * sin(time * 6.0)
		var size := tex.get_size()
		draw_texture_rect(tex, Rect2(round(at.x - size.x * 0.5), round(at.y - size.y * 0.5), size.x, size.y), false, Color(1, 1, 1, blink))
		draw_rect(sock.grow(2.0), Color(SFPalette.CYAN.r, SFPalette.CYAN.g, SFPalette.CYAN.b, 0.5 + blink), false, 1.0)
	else:
		# Empty socket: a dashed outline so it reads as an attachment point.
		var x := sock.position.x
		while x < sock.end.x:
			draw_rect(Rect2(x, sock.position.y, 2, 1), SFPalette.STEEL_MID, true)
			draw_rect(Rect2(x, sock.end.y - 1, 2, 1), SFPalette.STEEL_MID, true)
			x += 4.0
	if install_flash > 0.0 and install_flash_id == id:
		var k := 1.0 - install_flash / 0.9
		draw_rect(sock, Color(1.0, 1.0, 0.9, install_flash * 0.6), true)
		var g := sock.grow(4.0 + k * 14.0)
		draw_rect(g, Color(SFPalette.GREEN_OK.r, SFPalette.GREEN_OK.g, SFPalette.GREEN_OK.b, install_flash), false, 1.0)
	# Socket label above, on a dark backing so it reads over the hull.
	var label := String(COMPONENT_SHORT[id])
	var lw: float = skin.font.text_width(label)
	draw_rect(Rect2(round(at.x - lw * 0.5 - 2), sock.position.y - 11, lw + 4, 10), Color(0.03, 0.05, 0.06, 0.85), true)
	var label_col := SFPalette.GREEN_OK if state == "fitted" else (SFPalette.CYAN if previewed else SFPalette.PAPER_DIM)
	skin.text_c(self, at.x, sock.position.y - 9, label, label_col)


## The recovered-component tray. Each card shows the actual part only if Nick
## has it, and its status in words plus a glyph, never by colour alone.
func _draw_tray(r: Rect2) -> void:
	var focused_row := String(ROWS[row]) == "components"
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), SFPalette.CYAN if focused_row else SFPalette.STEEL_DARK)
	var w := (r.size.x - 16.0) / 3.0
	for i in COMPONENTS.size():
		var id := String(COMPONENTS[i])
		var card := Rect2(round(r.position.x + 5 + i * (w + 3)), r.position.y + 5, round(w), r.size.y - 10)
		var state := _state(id)
		var focused := focused_row and i == tray_index
		draw_rect(card, SFPalette.CYAN_DARK if focused else Color(0.06, 0.09, 0.10, 1.0), true)
		draw_rect(card, SFPalette.CYAN if focused else SFPalette.STEEL_DARK, false, 2.0 if focused else 1.0)
		var tex: Texture2D = skin.sprites.get(id, null)
		var icon_c := card.position + Vector2(14, card.size.y * 0.5)
		if state != "missing" and tex != null:
			var size := tex.get_size()
			draw_texture_rect(tex, Rect2(round(icon_c.x - size.x * 0.5), round(icon_c.y - size.y * 0.5), size.x, size.y), false)
		else:
			skin.text_c(self, icon_c.x, icon_c.y - 3, "?", SFPalette.ASH_LIGHT)
		var tx := card.position.x + 28.0
		skin.text(self, Vector2(tx, card.position.y + 8), String(COMPONENT_SHORT[id]), SFPalette.PAPER if focused else SFPalette.PAPER_DIM)
		var status := ""
		var col := SFPalette.ASH_LIGHT
		match state:
			"fitted":
				status = "OK FITTED"
				col = SFPalette.GREEN_OK
			"ready":
				status = "+ READY"
				col = SFPalette.GOLD
			_:
				status = "X MISSING"
		skin.text(self, Vector2(tx, card.position.y + 22), status, col)


func _draw_cost(r: Rect2) -> void:
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), SFPalette.STEEL_DARK)
	var x := r.position.x + 8.0
	var y := r.position.y + 7.0
	skin.text(self, Vector2(x, y), "SALVAGE", SFPalette.PAPER_DIM)
	skin.text_r(self, r.end.x - 8, y, "NEED / HAVE", SFPalette.ASH_LIGHT)
	y += 13.0
	var cost: Dictionary = workshop.material_cost()
	var mx := x
	for m in ["scrap_metal", "circuitry", "polymer"]:
		var have_n: int = campaign.material_count(String(m))
		var need := int(cost.get(m, 0))
		var ok := have_n >= need
		skin.text(self, Vector2(mx, y), "%s %d/%d%s" % [campaign.content.material_short(String(m)), need, have_n, "" if ok else " !"],
			SFPalette.PAPER if ok else SFPalette.RED)
		mx += 98.0
	y += 14.0
	var units: int = workshop.fabrication_units()
	var cap: int = workshop.fabrication_capacity()
	skin.text(self, Vector2(x, y), "FABRICATION", SFPalette.PAPER_DIM)
	skin.text_r(self, r.end.x - 8, y, "%d / %d UNITS%s" % [units, cap, "" if units <= cap else " !"], SFPalette.PAPER if units <= cap else SFPalette.RED)
	y += 14.0
	skin.text(self, Vector2(x, y), "CARGO", SFPalette.PAPER_DIM)
	skin.text_r(self, r.end.x - 8, y, "MEMORY CORE + EVIDENCE ARCHIVE", SFPalette.PAPER)


func _row_value(id: String) -> String:
	match id:
		"propulsion":
			var p: Dictionary = workshop.propulsion_stats()
			return String(p.get("name", "")).to_upper()
		"fuel":
			return "%.0f kg" % float(workshop.selection["fuel_kg"])
		"protection", "storage", "route":
			return String(workshop.selected(id).get("short", ""))
		"environmental_samples", "additional_records":
			return "LOADED" if bool(workshop.selection["optional"][id]) else "LEFT BEHIND"
		"simulate":
			return "V"
		"scavenge":
			return "C"
		"fabricate":
			return "F"
	return ""


func _row_label(id: String) -> String:
	match id:
		"propulsion": return "ENGINE"
		"fuel": return "PROPELLANT"
		"protection": return "PROTECTION"
		"storage": return "DATA STORE"
		"environmental_samples": return "SAMPLES"
		"additional_records": return "RECORDS"
		"route": return "ROUTE"
		"simulate": return "SIMULATE"
		"scavenge": return "SCAVENGE"
		"fabricate": return "FABRICATE"
	return id.to_upper()


func _draw_design(r: Rect2) -> void:
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), SFPalette.CYAN_DIM, true)
	skin.text(self, r.position + Vector2(8, 6), "DESIGN", SFPalette.CYAN)
	var y := r.position.y + 19.0
	for i in range(1, ROWS.size()):
		var id := String(ROWS[i])
		var focused := i == row
		var action := id in ["simulate", "scavenge", "fabricate"]
		if id == "simulate":
			draw_rect(Rect2(r.position.x + 6, y - 2, r.size.x - 12, 1), SFPalette.STEEL_DARK, true)
		var rr := Rect2(r.position.x + 4, y - 1, r.size.x - 8, 12)
		if focused:
			draw_rect(rr, SFPalette.CYAN_DARK, true)
		var enabled := true
		if id == "fabricate":
			enabled = report_is_current() and bool(report.get("valid", false)) and not is_locked_design()
		var label_col := SFPalette.PAPER if focused else SFPalette.PAPER_DIM
		if not enabled:
			label_col = SFPalette.ASH_LIGHT
		skin.text(self, Vector2(rr.position.x + 4, y + 2), _row_label(id), label_col)
		var value := _row_value(id)
		if not action and focused and not is_locked_design():
			value = "< " + value + " >"
		skin.text_r(self, rr.end.x - 4, y + 2, value, SFPalette.GOLD if focused else SFPalette.PAPER)
		y += 13.0


## One or two lines about whatever is focused: the selection-based detail that
## replaces the long always-visible descriptions.
func _draw_detail(r: Rect2) -> void:
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), SFPalette.STEEL_DARK)
	var desc := ""
	match String(ROWS[row]):
		"components":
			var id := String(COMPONENTS[tray_index])
			var note := ""
			for c in recon_data.get("recovered_components", []) as Array:
				if String((c as Dictionary)["id"]) == id:
					note = String((c as Dictionary).get("note", ""))
			desc = "%s: %s" % [_component_name(id).to_upper(), note]
		"propulsion":
			var p: Dictionary = workshop.propulsion_stats()
			desc = "%s Isp %.0f s, lifts %.0f kg." % [String(workshop.selected("propulsion").get("description", "")), float(p.get("isp_s", 0)), float(p.get("thrust_capacity_kg", 0))]
		"protection", "storage", "route":
			desc = String(workshop.selected(String(ROWS[row])).get("description", ""))
		"fuel":
			desc = "Free from the Dawn depot, but every kilogram must be lifted. SHIFT: 100 kg steps."
		"environmental_samples":
			desc = "30 kg of sealed samples. Needs 25 W of cooling."
		"additional_records":
			desc = "240 MB more evidence. Longer relay sync before launch."
		"simulate":
			desc = "Free. Certifies a report for this exact design. Simplified educational model with invented values."
		"scavenge":
			desc = "Tops common materials up to a fair floor so no run is stranded."
		"fabricate":
			desc = "Spends salvage once. Needs all three parts fitted and a passing report."
	if is_locked_design() and String(ROWS[row]) != "components":
		desc = "Assembled. This design is final for the return mission."
	skin.wrap(self, Vector2(r.position.x + 8, r.position.y + 5), r.size.x - 16, desc, SFPalette.CYAN_DIM, 1, 3, 2)


func _draw_report(r: Rect2, rep: Dictionary, certified: bool) -> void:
	var valid := bool(rep.get("valid", false))
	var accent := SFPalette.STEEL_DARK
	if certified:
		accent = SFPalette.GREEN_OK if valid else SFPalette.RED
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), accent, true)
	var x := r.position.x + 8.0
	var y := r.position.y + 6.0
	var w := r.size.x - 16.0
	var title := "PREVIEW  (V CERTIFIES)"
	if certified:
		title = "REPORT: " + ("PASS" if valid else "FAIL")
	if is_locked_design():
		title = "ASSEMBLED"
	skin.text(self, Vector2(x, y), title, accent if certified or is_locked_design() else SFPalette.CYAN)
	y += 13.0
	var t: Dictionary = rep.get("totals", {}) as Dictionary
	if String(ROWS[row]) == "simulate":
		# Selection-based detail: per-stage consumption only when asked for.
		skin.text(self, Vector2(x, y), "STAGE", SFPalette.GOLD)
		skin.text_r(self, x + 150, y, "TIME", SFPalette.GOLD)
		skin.text_r(self, x + 200, y, "LOAD", SFPalette.GOLD)
		skin.text_r(self, x + 252, y, "DRAW", SFPalette.GOLD)
		skin.text_r(self, x + w, y, "PROP", SFPalette.GOLD)
		y += 11.0
		for s in rep.get("stages", []) as Array:
			var st: Dictionary = s
			skin.text(self, Vector2(x, y), String(st["name"]).to_upper(), SFPalette.PAPER_DIM)
			skin.text_r(self, x + 150, y, "%.0fs" % float(st["duration_s"]), SFPalette.PAPER)
			skin.text_r(self, x + 200, y, "%.0fW" % float(st["power_w"]), SFPalette.PAPER)
			skin.text_r(self, x + 252, y, "%.0fWh" % float(st["battery_draw_wh"]), SFPalette.PAPER)
			skin.text_r(self, x + w, y, "%.0fkg" % float(st["propellant_kg"]), SFPalette.PAPER)
			y += 10.0
		skin.text(self, Vector2(x, y + 3), "RESERVE %.0f kg / %.0f Wh" % [float(t.get("propellant_remaining_kg", 0)), float(t.get("battery_remaining_wh", 0))], SFPalette.PAPER_DIM)
		return
	# Eight compact checks in two columns, each with OK or NO in words.
	var stats := [
		["MASS", "%.0f/%.0f" % [float(t.get("wet_mass_kg", 0)), float(t.get("mass_limit_kg", 0))], float(t.get("wet_mass_kg", 0)) <= float(t.get("mass_limit_kg", 0))],
		["DV", "%.0f/%.0f" % [float(t.get("delta_v_available_m_s", 0)), float(t.get("delta_v_required_m_s", 0))], float(t.get("delta_v_available_m_s", 0)) >= float(t.get("delta_v_required_m_s", 0))],
		["POWER", "%.0f/%.0fW" % [float(t.get("peak_power_w", 0)), float(t.get("power_limit_w", 0))], float(t.get("peak_power_w", 0)) <= float(t.get("power_limit_w", 0))],
		["BUFFER", "%.0f/%.0f" % [float(t.get("battery_draw_wh", 0)), float(t.get("battery_usable_wh", 0))], float(t.get("battery_draw_wh", 0)) <= float(t.get("battery_usable_wh", 0))],
		["SHIELD", "%.0f/%.0f" % [float(t.get("protection_rating", 0)), float(t.get("protection_required", 0))], float(t.get("protection_rating", 0)) >= float(t.get("protection_required", 0))],
		["DATA", "%.0f/%.0f" % [float(t.get("payload_data_mb", 0)), float(t.get("data_capacity_mb", 0))], float(t.get("payload_data_mb", 0)) <= float(t.get("data_capacity_mb", 0))],
		["SYNC", "%.0f/%.0fs" % [float(t.get("sync_seconds", 0)), float(t.get("launch_window_seconds", 0))], float(t.get("sync_seconds", 0)) <= float(t.get("launch_window_seconds", 0))],
		["FUEL", "NEED %.0f" % float(t.get("propellant_needed_kg", 0)), true],
	]
	var col_w := (w - 8.0) * 0.5
	for i in stats.size():
		var s: Array = stats[i]
		var cx := x + float(i % 2) * (col_w + 8.0)
		var cy := y + floorf(float(i) / 2.0) * 10.0
		var ok := bool(s[2])
		skin.text(self, Vector2(cx, cy), "OK" if ok else "NO", SFPalette.GREEN_OK if ok else SFPalette.RED)
		skin.text(self, Vector2(cx + 16, cy), String(s[0]), SFPalette.PAPER_DIM)
		skin.text_r(self, cx + col_w, cy, String(s[1]), SFPalette.PAPER if ok else SFPalette.RED)
	y += 44.0
	var failures: Array = rep.get("failures", []) as Array
	if failures.is_empty():
		skin.text(self, Vector2(x, y), "Every check passes.", SFPalette.GREEN_OK)
	else:
		y = skin.wrap(self, Vector2(x, y), w, String(failures[0]), SFPalette.RED, 1, 2, 2)
		if failures.size() > 1:
			skin.text(self, Vector2(x, y), "+%d more problem%s" % [failures.size() - 1, "" if failures.size() == 2 else "s"], SFPalette.RED.darkened(0.2))


func _draw_footer() -> void:
	draw_rect(Rect2(0, VH - 34, VW, 34), Color(0.03, 0.05, 0.05, 0.92), true)
	if message_timer > 0.0:
		var c := SFPalette.PAPER
		match message_tone:
			"good": c = SFPalette.GREEN_OK
			"bad": c = SFPalette.RED
			"warn": c = SFPalette.GOLD
		skin.text_c(self, VW * 0.5, VH - 30, _fit(message, VW - 20.0), c)
	else:
		skin.text_c(self, VW * 0.5, VH - 30, _fit("NEXT: " + next_step(), VW - 20.0), SFPalette.GOLD)
	skin.text(self, Vector2(10, VH - 14), "CLICK OR ARROWS + ENTER   V SIMULATE   F FABRICATE   C SCAVENGE", SFPalette.PAPER_DIM)
	skin.button(self, LEAVE_BUTTON, "LEAVE", LEAVE_BUTTON.has_point(get_local_mouse_position()), true)


## Shortens a line to fit `width` pixels, so the footer never clips.
func _fit(text: String, width: float) -> String:
	var s := text
	while s.length() > 4 and skin.font.text_width(s) > width:
		s = s.substr(0, s.length() - 4) + "..."
	return s
