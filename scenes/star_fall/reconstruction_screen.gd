extends Node2D
## The Phase 3 VELA reconstruction workshop at the crash-site base. Panel
## driven, keyboard only. The rules live in core/star_fall/sf_reconstruction.gd
## and the physics in sf_return_sim.gd; this screen edits a selection, shows a
## free live preview, certifies a report on request, and asks the rules to
## fabricate once.
##
## Controls
##   UP / DOWN       choose a row
##   LEFT / RIGHT    change the row's option (fuel: -/+ 20 kg; SHIFT: 100 kg)
##   ENTER / SPACE   toggle optional payload, or run the row's action
##   V               run the simulation (certifies a report for this design)
##   F               fabricate and assemble (needs a passing, current report)
##   C               scavenge common materials up to the fair floor
##   ESC             leave the workshop (the selection is kept)

signal closed
signal assembled

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFReconstruction := preload("res://core/star_fall/sf_reconstruction.gd")
const SFContent := preload("res://core/star_fall/sf_content.gd")

const VW := 640
const VH := 360
const SIM_SEED := 30303
const ROWS := ["propulsion", "fuel", "protection", "storage", "environmental_samples", "additional_records",
	"route", "simulate", "scavenge", "fabricate"]

var skin
var ui
var campaign
var workshop
var row: int = 0
var report: Dictionary = {}        # the certified report, cleared by any change
var preview: Dictionary = {}       # always-current free preview
var input_locked: bool = false
var time: float = 0.0
var message: String = ""
var message_tone: String = "info"
var message_timer: float = 0.0


func setup(skin_ref, ui_ref, campaign_ref) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	workshop = SFReconstruction.new()
	var data: Dictionary = SFContent.read_json("res://data/star_fall/reconstruction.json") as Dictionary
	var saved: Dictionary = campaign.reconstruction.get("committed", campaign.reconstruction.get("selection", {})) as Dictionary
	workshop.setup(data, campaign.original_propulsion_id(), saved)
	_refresh_preview()


func is_locked_design() -> bool:
	return campaign.is_ready_for_final_assembly()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
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


func _change(direction: int, shift: bool) -> void:
	if is_locked_design():
		_say("The VELA is already assembled.", "info")
		return
	var id := String(ROWS[row])
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


func _refresh_preview() -> void:
	preview = workshop.simulate(campaign.recovered_component_ids(), SIM_SEED)


func _store() -> void:
	campaign.store_reconstruction_selection(workshop.to_dict())


# ---------------------------------------------------------------- actions

## Certifies a report for the current design. Free: nothing is spent.
func run_simulation() -> Dictionary:
	skin.audio.sfx_preflight_scan()
	report = workshop.simulate(campaign.recovered_component_ids(), SIM_SEED)
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


func _process(delta: float) -> void:
	time += delta
	message_timer = maxf(0.0, message_timer - delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.RUIN_BG, true)
	ui.header(self, "VELA RECONSTRUCTION WORKSHOP", "Salvage and limited fabrication. Simplified educational model, not NASA data.")
	_draw_rows(Rect2(8, 30, 300, 222))
	_draw_fixed(Rect2(8, 256, 300, 66))
	if report_is_current():
		_draw_report(Rect2(314, 30, 318, 292), report, true)
	else:
		_draw_report(Rect2(314, 30, 318, 292), preview, false)
	_draw_footer()


func _row_value(id: String) -> String:
	match id:
		"propulsion":
			var p: Dictionary = workshop.propulsion_stats()
			return String(p.get("name", ""))
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
		"propulsion": return "PROPULSION"
		"fuel": return "PROPELLANT"
		"protection": return "PROTECTION"
		"storage": return "DATA STORAGE"
		"environmental_samples": return "SAMPLES (OPTIONAL)"
		"additional_records": return "RECORDS (OPTIONAL)"
		"route": return "ROUTE"
		"simulate": return "RUN SIMULATION"
		"scavenge": return "SCAVENGE MATERIALS"
		"fabricate": return "FABRICATE AND ASSEMBLE"
	return id.to_upper()


func _draw_rows(r: Rect2) -> void:
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), SFPalette.CYAN_DIM, true)
	var y := r.position.y + 8.0
	for i in ROWS.size():
		var id := String(ROWS[i])
		var focused := i == row
		var rr := Rect2(r.position.x + 6, y - 3, r.size.x - 12, 15)
		var action := id in ["simulate", "scavenge", "fabricate"]
		if action and i == 7:
			draw_rect(Rect2(r.position.x + 6, y - 5, r.size.x - 12, 1), SFPalette.STEEL_DARK, true)
		if focused:
			draw_rect(rr, SFPalette.CYAN_DARK, true)
		var enabled := true
		if id == "fabricate":
			enabled = report_is_current() and bool(report.get("valid", false)) and not is_locked_design()
		var label_col := SFPalette.PAPER if focused else SFPalette.PAPER_DIM
		if not enabled:
			label_col = SFPalette.ASH_LIGHT
		skin.text(self, Vector2(rr.position.x + 6, y + 2), _row_label(id), label_col)
		var value := _row_value(id)
		if not action and focused and not is_locked_design():
			value = "< " + value + " >"
		skin.text_r(self, rr.end.x - 6, y + 2, value, SFPalette.GOLD if focused else SFPalette.PAPER)
		y += 18.0
	# Short description of the focused option.
	var desc := ""
	match String(ROWS[row]):
		"propulsion":
			var p: Dictionary = workshop.propulsion_stats()
			desc = "%s Isp %.0f s, lifts %.0f kg." % [String(workshop.selected("propulsion").get("description", "")), float(p.get("isp_s", 0)), float(p.get("thrust_capacity_kg", 0))]
		"protection", "storage", "route":
			desc = String(workshop.selected(String(ROWS[row])).get("description", ""))
		"fuel":
			desc = "Propellant from the Dawn depot. Free, but every kilogram must be lifted."
		"environmental_samples":
			desc = "30 kg of sealed samples. Needs 25 W of cooling."
		"additional_records":
			desc = "240 MB more evidence. Longer relay sync before launch."
		"simulate":
			desc = "Free. Certifies a report for this exact design."
		"scavenge":
			desc = "Tops common materials up to a fair floor so no run is stranded."
		"fabricate":
			desc = "Spends salvage once. Needs a passing report for this design."
	if is_locked_design():
		desc = "Assembled. This design is final for the return mission."
	skin.wrap(self, Vector2(r.position.x + 8, r.end.y - 22), r.size.x - 16, desc, SFPalette.CYAN_DIM, 1, 2, 2)


func _draw_fixed(r: Rect2) -> void:
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), SFPalette.STEEL_DARK)
	var x := r.position.x + 8.0
	var y := r.position.y + 6.0
	skin.text(self, Vector2(x, y), "RECOVERED", SFPalette.PAPER_DIM)
	var cx := x + 64.0
	for comp in [["navigation_chip", "CHIP"], ["power_core", "CORE"], ["shield_emitter", "EMITTER"]]:
		var have: bool = campaign.has_component(String(comp[0]))
		skin.text(self, Vector2(cx, y), String(comp[1]), SFPalette.GREEN_OK if have else SFPalette.RED)
		cx += 60.0
	y += 13.0
	skin.text(self, Vector2(x, y), "MANDATORY  BILL'S MEMORY CORE, EVIDENCE ARCHIVE", SFPalette.PAPER_DIM)
	y += 13.0
	# Materials: held vs this design's cost.
	var cost: Dictionary = workshop.material_cost()
	var mx := x
	for m in ["scrap_metal", "circuitry", "polymer"]:
		var have_n: int = campaign.material_count(String(m))
		var need := int(cost.get(m, 0))
		var col := SFPalette.PAPER if have_n >= need else SFPalette.RED
		skin.text(self, Vector2(mx, y), "%s %d/%d" % [campaign.content.material_short(String(m)), need, have_n], col)
		mx += 92.0
	y += 13.0
	var units: int = workshop.fabrication_units()
	var cap: int = workshop.fabrication_capacity()
	skin.text(self, Vector2(x, y), "FABRICATION %d / %d UNITS" % [units, cap], SFPalette.PAPER if units <= cap else SFPalette.RED)
	skin.text_r(self, r.end.x - 8, y, "COST / HELD", SFPalette.ASH_LIGHT)


func _draw_report(r: Rect2, rep: Dictionary, certified: bool) -> void:
	var valid := bool(rep.get("valid", false))
	var accent := SFPalette.STEEL_DARK
	if certified:
		accent = SFPalette.GREEN_OK if valid else SFPalette.RED
	skin.panel(self, r, Color(0.04, 0.07, 0.08, 0.95), accent, true)
	var x := r.position.x + 8.0
	var y := r.position.y + 6.0
	var title := "LIVE PREVIEW  (V CERTIFIES)"
	if certified:
		title = "SIMULATION REPORT: " + ("PASS" if valid else "FAIL")
	if is_locked_design():
		title = "ASSEMBLED: READY FOR FINAL ASSEMBLY"
	skin.text(self, Vector2(x, y), title, accent if certified or is_locked_design() else SFPalette.CYAN)
	skin.text_r(self, r.end.x - 8, y, "SEED %d" % int(rep.get("seed", 0)), SFPalette.ASH_LIGHT)
	y += 14.0
	var t: Dictionary = rep.get("totals", {}) as Dictionary
	var w := r.size.x - 16.0
	var lines := [
		["MASS (WET / LIMIT)", "%.0f / %.0f kg" % [float(t.get("wet_mass_kg", 0)), float(t.get("mass_limit_kg", 0))], float(t.get("wet_mass_kg", 0)) <= float(t.get("mass_limit_kg", 0))],
		["DELTA-V (HAVE / NEED)", "%.0f / %.0f m/s" % [float(t.get("delta_v_available_m_s", 0)), float(t.get("delta_v_required_m_s", 0))], float(t.get("delta_v_available_m_s", 0)) >= float(t.get("delta_v_required_m_s", 0))],
		["PROPELLANT NEEDED", "%.0f kg" % float(t.get("propellant_needed_kg", 0)), true],
		["PEAK POWER", "%.0f / %.0f W" % [float(t.get("peak_power_w", 0)), float(t.get("power_limit_w", 0))], float(t.get("peak_power_w", 0)) <= float(t.get("power_limit_w", 0))],
		["BUFFER DRAW", "%.0f / %.0f Wh" % [float(t.get("battery_draw_wh", 0)), float(t.get("battery_usable_wh", 0))], float(t.get("battery_draw_wh", 0)) <= float(t.get("battery_usable_wh", 0))],
		["PROTECTION", "%.0f / %.0f" % [float(t.get("protection_rating", 0)), float(t.get("protection_required", 0))], float(t.get("protection_rating", 0)) >= float(t.get("protection_required", 0))],
		["DATA", "%.0f / %.0f MB" % [float(t.get("payload_data_mb", 0)), float(t.get("data_capacity_mb", 0))], float(t.get("payload_data_mb", 0)) <= float(t.get("data_capacity_mb", 0))],
		["RELAY SYNC", "%.0f / %.0f s" % [float(t.get("sync_seconds", 0)), float(t.get("launch_window_seconds", 0))], float(t.get("sync_seconds", 0)) <= float(t.get("launch_window_seconds", 0))],
	]
	for l in lines:
		ui.value_row(self, Vector2(x, y), String(l[0]), String(l[1]), w, bool(l[2]))
		y += 11.0
	y += 4.0
	# Per-stage consumption.
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
	skin.text(self, Vector2(x, y + 2), "RESERVES  %.0f kg PROPELLANT   %.0f Wh BUFFER" % [float(t.get("propellant_remaining_kg", 0)), float(t.get("battery_remaining_wh", 0))], SFPalette.PAPER_DIM)
	y += 16.0
	# Failures with actionable suggestions.
	var failures: Array = rep.get("failures", []) as Array
	var suggestions: Array = rep.get("suggestions", []) as Array
	if failures.is_empty():
		skin.wrap(self, Vector2(x, y), w, "Every check passes on this design.", SFPalette.GREEN_OK, 1, 2)
	else:
		for i in mini(2, failures.size()):
			y = skin.wrap(self, Vector2(x, y), w, "- " + String(failures[i]), SFPalette.RED, 1, 2, 2)
		if not suggestions.is_empty():
			skin.wrap(self, Vector2(x, y + 2), w, "TRY: " + String(suggestions[0]), SFPalette.GOLD, 1, 2, 2)


func _draw_footer() -> void:
	draw_rect(Rect2(0, VH - 34, VW, 34), Color(0.03, 0.05, 0.05, 0.92), true)
	if message_timer > 0.0:
		var c := SFPalette.PAPER
		match message_tone:
			"good": c = SFPalette.GREEN_OK
			"bad": c = SFPalette.RED
			"warn": c = SFPalette.GOLD
		skin.text_c(self, VW * 0.5, VH - 30, message.substr(0, 100), c)
	skin.text_c(self, VW * 0.5, VH - 14, "UP/DOWN ROW   LEFT/RIGHT CHANGE   V SIMULATE   F FABRICATE   C SCAVENGE   ESC LEAVE", SFPalette.PAPER_DIM)
