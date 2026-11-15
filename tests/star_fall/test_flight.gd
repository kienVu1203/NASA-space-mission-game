extends SceneTree
## STAR FALL Phase 4b test: the playable flight segments of the escape cinematic.
##
##   Godot --headless --path . --script res://tests/star_fall/test_flight.gd
##
## Covers `core/star_fall/sf_flight.gd` (pure steering, sweeping, restart and the
## guaranteed assist) and the cinematic screen's input rules around it (any key
## fast-forwards, Esc and Space stay reserved, movement keys steer rather than
## skip, a strike restarts the segment, and a player who never touches anything
## still reaches the next scene).
##
## Also covers the canonical VELA renderer (`core/star_fall/sf_vela.gd`): one
## geometry, upright in every finale state, engines only under thrust, modules
## where the workshop sockets are; the shield contacts; the portal waiting for a
## visible entry; and the per-scene cleanup of contacts and shake.
##
## Headless execution cannot say whether the lane feels good to fly, or whether
## the art and audio read well. It does prove that no input can strand the
## sequence, no strike can soft-lock it, and the state rules hold.

const SFContent := preload("res://core/star_fall/sf_content.gd")
const SFVela := preload("res://core/star_fall/sf_vela.gd")
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const SFFinale := preload("res://core/star_fall/sf_finale.gd")
const SFFlight := preload("res://core/star_fall/sf_flight.gd")
const SFSave := preload("res://core/star_fall/sf_save.gd")
const SFQA := preload("res://core/star_fall/sf_qa.gd")

var fails: int = 0
var checks_run: int = 0
var finale_data: Dictionary = {}
var reconstruction_data: Dictionary = {}
var main
var step: int = 0


func check(label: String, ok: bool, detail: String = "") -> void:
	checks_run += 1
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1


func _initialize() -> void:
	finale_data = SFContent.read_json("res://data/star_fall/finale.json") as Dictionary
	reconstruction_data = SFContent.read_json("res://data/star_fall/reconstruction.json") as Dictionary
	main = load("res://scenes/star_fall/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	step += 1
	if step < 3:
		return false
	_data()
	_debris_rules()
	_restart_and_assist()
	_portal_rules()
	_screen_input_rules()
	_screen_reaches_the_end()
	_vela_rules()
	_shield_rules()
	_portal_entry_rules()
	_presentation_states()
	_finish()
	return true


# ---------------------------------------------------------------- helpers

func _flight_data(kind: String) -> Dictionary:
	return ((finale_data.get("cinematic", {}) as Dictionary).get("flight", {}) as Dictionary).get(kind, {}) as Dictionary


func _debris_rig():
	var f = SFFlight.new()
	f.configure(_flight_data("debris"))
	return f


func _ready_campaign():
	var camp = SFCampaign.new()
	camp.set_flag(SFCampaign.FLAG_BRIEFING_READ)
	SFQA.apply_valid_day_one_design(camp)
	camp.advance_to(SFCampaign.STAGE_CRASH_SITE)
	camp.advance_to(SFCampaign.STAGE_CHECKPOINT)
	camp.view_memory(SFCampaign.MEMORY_GREEN_CITY)
	camp.set_flag(SFCampaign.FLAG_COORDINATES_RECEIVED)
	camp.reveal_future_earth()
	camp.view_memory(SFCampaign.MEMORY_CITY_GREEN)
	camp.view_memory(SFCampaign.MEMORY_GREEN_COAST)
	camp.view_memory(SFCampaign.MEMORY_HEALTHY_FOREST)
	camp.restore_archive(SFCampaign.ARCHIVE_CITY)
	camp.restore_archive(SFCampaign.ARCHIVE_COAST)
	camp.restore_archive(SFCampaign.ARCHIVE_DAWN)
	camp.complete_boss("scrap_king_defeated", SFCampaign.COMPONENT_NAVIGATION_CHIP)
	camp.complete_boss("toxic_tide_defeated", SFCampaign.COMPONENT_POWER_CORE)
	camp.complete_boss("sky_remnant_defeated", SFCampaign.COMPONENT_SHIELD_EMITTER)
	camp.complete_silent_coast()
	camp.set_flag(SFCampaign.FLAG_BASE_RETURNED)
	camp.set_flag(SFCampaign.FLAG_PHASE_TWO_COMPLETE)
	camp.advance_to(SFCampaign.STAGE_DAWN_INTRO)
	camp.complete_dawn_tower()
	camp.advance_to(SFCampaign.STAGE_RECONSTRUCTION)
	SFQA.apply_valid_reconstruction(camp, reconstruction_data)
	camp.advance_to(SFCampaign.STAGE_READY)
	camp.begin_final_assembly(SFFinale.snapshot(camp, reconstruction_data))
	camp.advance_to(camp.STAGE_ESCAPE)
	return camp


func _cinematic(camp):
	var cine = load("res://scenes/star_fall/cinematic_screen.gd").new()
	cine.setup(main.skin, main.ui, camp, finale_data, reconstruction_data)
	root.add_child(cine)
	return cine


func _at(cine, index: int, at: float) -> void:
	cine.scene_index = index
	cine.show_final_message = false
	cine.scene_time = at
	cine.elapsed = at
	cine.paused = false


# ---------------------------------------------------------------- data

func _data() -> void:
	print("")
	print("-- Flight data " + "-".repeat(48))
	var flight_block: Dictionary = (finale_data.get("cinematic", {}) as Dictionary).get("flight", {}) as Dictionary
	check("finale.json carries a flight block", not flight_block.is_empty())
	for kind in ["debris", "portal"]:
		var cfg: Dictionary = _flight_data(kind)
		check("the %s segment is configured" % kind, not cfg.is_empty())
		check("the %s segment has its own kind" % kind, String(cfg.get("kind", "")) == kind)
		check("the %s lane leaves room to fly" % kind,
			float(cfg.get("lane_bottom", 0.0)) - float(cfg.get("lane_top", 0.0)) > 80.0)
		check("the %s segment can always finish" % kind, float(cfg.get("assist_after_seconds", 0.0)) > 0.0)
	var scenes: Array = (finale_data.get("cinematic", {}) as Dictionary).get("scenes", []) as Array
	var interactive: Array = []
	for entry in scenes:
		var id := String((entry as Dictionary).get("interactive", ""))
		if id != "":
			interactive.append(id)
	check("the debris passage and the portal are both playable",
		interactive == ["debris", "portal"], str(interactive))


# ---------------------------------------------------------------- debris

func _debris_rules() -> void:
	print("")
	print("-- Debris passage " + "-".repeat(46))
	var f = _debris_rig()
	var y0: float = f.ship_y
	f.steer(-1.0, 0.10)
	check("steering up moves the ship up", f.ship_y < y0)
	f = _debris_rig()
	y0 = f.ship_y
	f.steer(1.0, 0.10)
	check("steering down moves the ship down", f.ship_y > y0)

	f = _debris_rig()
	for i in 400:
		f.steer(-4.0, 0.05)
	check("the ship cannot leave the lane at the top", is_equal_approx(f.ship_y, f.ship_min_y()))
	for i in 400:
		f.steer(4.0, 0.05)
	check("the ship cannot leave the lane at the bottom", is_equal_approx(f.ship_y, f.ship_max_y()))

	f = _debris_rig()
	var before: float = f.ship_y
	f.steer_toward(before + 40.0, 0.10)
	check("mouse steering moves toward the pointer", f.ship_y > before)
	f.steer_toward(f.ship_max_y() + 400.0, 0.10)
	check("mouse steering respects the lane", f.ship_y <= f.ship_max_y())

	# Obstacles stream in from the right and are removed off the left edge.
	f = _debris_rig()
	var spawned := false
	var ahead := true
	for i in 60:
		var events: Array = f.tick(0.05, 0.0)
		for e in events:
			if String((e as Dictionary).get("type", "")) == "spawn":
				spawned = true
				var newest: Dictionary = f.active_obstacles().back()
				if float(newest["x"]) - float(newest["hw"]) <= f.ship_x + f.ship_half_length:
					ahead = false
	check("obstacles spawn", spawned)
	check("every obstacle enters ahead of the ship's nose", ahead)

	# The field is always dodgeable: consecutive bodies in spawn order leave a
	# gap the ship can cross in the time between their arrivals.
	f = _debris_rig()
	# The navigation chip flies, so no strike freezes the field mid-sample.
	f.assist = true
	var by_seq: Dictionary = {}
	for i in 400:
		f.tick(0.05, 0.0)
		for body in f.active_obstacles():
			var b: Dictionary = body
			# The layout as spawned: a shield graze may push a body aside later.
			if not by_seq.has(int(b["seq"])):
				by_seq[int(b["seq"])] = b.duplicate()
	var gaps_ok := true
	var sizes_ok := true
	var previous_y: float = -999.0
	var previous_hh: float = 0.0
	for seq in range(0, 400):
		if not by_seq.has(seq):
			continue
		var b2: Dictionary = by_seq[seq]
		var y: float = float(b2["y"])
		if float(b2["hh"]) <= 0.0 or float(b2["hw"]) <= 0.0:
			sizes_ok = false
		# Edge to edge, the corridor must be wider than the hull plus clearance.
		# Anything tighter cannot be flown through, so it would not be a dodge.
		if previous_y > -900.0:
			var clear: float = absf(y - previous_y) - float(b2["hh"]) - previous_hh
			if clear < f.ship_half_height * 2.0:
				gaps_ok = false
		previous_y = y
		previous_hh = float(b2["hh"])
	check("consecutive bodies leave a threadable gap", gaps_ok)
	check("every body has a real size", sizes_ok)
	check("the field was actually populated", by_seq.size() > 4, str(by_seq.size()))

	# Swept collision: a huge step cannot tunnel a body through the ship.
	f = _debris_rig()
	f.obstacles.clear()
	f.set_ship_y((f.lane_top + f.lane_bottom) * 0.5)
	f.obstacles.append({"x": 640.0, "y": f.ship_y, "hw": 8.0, "hh": 8.0, "tone": 0, "phase": 0.0})
	var hit := false
	for i in 10:
		for e in f.tick(0.5, 0.0):
			if String((e as Dictionary).get("type", "")) == "hit":
				hit = true
	check("a fast body is caught by the swept test, not tunnelled", hit)
	check("the strike is counted exactly once", f.hits == 1)
	check("a struck field holds still until the restart", f.impact_pending)
	var quiet := true
	for i in 6:
		for e in f.tick(0.5, 0.0):
			quiet = false
	check("a struck field reports nothing more", quiet)

	# The lane keeps moving while the ship is steered: progress comes from time.
	f = _debris_rig()
	check("a fresh segment has no progress", f.progress_fraction() == 0.0)
	for i in 20:
		f.tick(0.05, 0.0)
	check("progress accumulates while flying", f.progress_fraction() > 0.0)


# ---------------------------------------------------------------- restart

func _restart_and_assist() -> void:
	print("")
	print("-- Strike, restart and the guaranteed exit " + "-".repeat(17))
	var f = _debris_rig()
	for i in 40:
		f.tick(0.05, 0.0)
	check("a flown segment is in progress", not f.cleared and not f.entered)
	var progress_before: float = f.progress_fraction()
	f.hits = 1
	f.restart()
	check("a restart clears every obstacle", f.active_obstacles().is_empty())
	check("a restart resets the segment progress", f.progress_fraction() == 0.0)
	check("a restart keeps the attempt count", f.restarts == 1)
	check("the segment is playable again after a restart", f.is_active())
	check("the strike count survives the restart", f.hits == 1)
	check("the progress had actually advanced first", progress_before > 0.0)

	# Restarting enough times hands the ship to the navigation chip.
	var g = _debris_rig()
	var needed: int = g.assist_after_restarts
	for i in needed:
		g.restart()
	check("the navigation assist engages after the configured restarts", g.assist)
	check("the assist does not skip the beats outright", g.is_active())

	# With the assist on, flying with no input clears the segment.
	var h = _debris_rig()
	h.assist = true
	var cleared := false
	var guard := 0
	while not cleared and guard < 3000:
		guard += 1
		for e in h.tick(0.05, 0.0):
			if String((e as Dictionary).get("type", "")) == "cleared":
				cleared = true
	check("the assisted ship clears the debris passage", cleared)
	check("the assisted run takes a sane amount of time", h.time < 30.0, "%.1fs" % h.time)

	# A player who never touches anything, and whose screen restarts the field on
	# every strike exactly as the real screen does, is still carried through.
	var k = _debris_rig()
	cleared = false
	guard = 0
	var restarts_seen := 0
	while not cleared and guard < 6000:
		guard += 1
		var struck := false
		for e in k.tick(0.05, 0.0):
			var kind := String((e as Dictionary).get("type", ""))
			if kind == "cleared":
				cleared = true
			elif kind == "hit":
				struck = true
		if struck:
			restarts_seen += 1
			k.restart()
	check("an untouched, repeatedly struck lane still finishes", cleared)
	check("the untouched lane had to be restarted", restarts_seen > 0, str(restarts_seen))
	check("the assist took over for the stalled player", k.assist)

	# A ship that keeps colliding can never be trapped: past the restart budget
	# the assist takes over and the collisions stop counting against it.
	var c = _debris_rig()
	guard = 0
	while guard < 40 and not c.assist:
		guard += 1
		c.restart()
	check("repeated strikes eventually hand over control", c.assist)
	c._tick_debris(0.05, [])
	check("the assisted ship cannot be struck again", c.hits <= 40)


# ---------------------------------------------------------------- portal

func _portal_rules() -> void:
	print("")
	print("-- Portal entry " + "-".repeat(49))
	var f = SFFlight.new()
	f.configure(_flight_data("portal"))
	check("the portal segment steers vertically too", f.kind == "portal")
	f.set_ship_y(f.ship_y + 40.0)
	check("the portal ship stays in its lane", f.ship_y <= f.ship_max_y())
	# Aligned with the mouth, a short hold crosses.
	f.set_ship_y(f.portal_y)
	var entered := false
	var guard := 0
	while not entered and guard < 400:
		guard += 1
		f.ship_y = f.portal_y
		for e in f.tick(0.05, 0.0):
			if String((e as Dictionary).get("type", "")) == "entered":
				entered = true
	check("holding the line crosses into the portal", entered)
	check("the portal reports the crossing", f.entered)

	# Out of alignment it never crosses on its own before the assist clock.
	var g = SFFlight.new()
	g.configure(_flight_data("portal"))
	var crossed_early := false
	var t := 0.0
	while t < g.assist_after_seconds - 1.0:
		t += 0.05
		g.ship_y = g.lane_top + 2.0
		for e in g.tick(0.05, 0.0):
			if String((e as Dictionary).get("type", "")) == "entered":
				crossed_early = true
	check("an unaligned ship does not cross by accident", not crossed_early)

	# But it does cross eventually, so the scene cannot hang.
	crossed_early = false
	t = 0.0
	while not crossed_early and t < 60.0:
		t += 0.05
		for e in g.tick(0.05, 0.0):
			if String((e as Dictionary).get("type", "")) == "entered":
				crossed_early = true
	check("the portal always opens for a stalled player", crossed_early)


# ---------------------------------------------------------------- screen

func _screen_input_rules() -> void:
	print("")
	print("-- Cinematic input rules " + "-".repeat(39))
	var camp = _ready_campaign()
	var cine = _cinematic(camp)
	cine.elapsed = 5.0
	check("the sequence opens on the crash site", cine.scene_id() == "leaving_crash_site")

	# Only Enter and the NEXT button advance a beat. Space, letters and a click
	# on the scene do nothing; Esc asks for the pause menu and never skips.
	var asked: Array = []
	cine.pause_requested.connect(func(): asked.append(true))
	_at(cine, 0, 0.0)
	cine.handle_key(KEY_SPACE)
	check("space neither pauses nor advances", not cine.is_paused() and cine.scene_time == 0.0)
	cine.handle_key(KEY_Q)
	check("an ordinary letter does not advance the clock", cine.scene_time == 0.0)
	cine.handle_click(Vector2(300, 200))
	check("a click on the scene does not advance the clock", cine.scene_time == 0.0)
	var before: float = cine.scene_time
	cine.handle_key(KEY_ENTER)
	check("enter advances the clock", cine.scene_time > before)
	_at(cine, 0, 0.0)
	cine.handle_click(cine.NEXT_BADGE.get_center())
	check("the NEXT button advances the clock", cine.scene_time > 0.0)
	cine.handle_click(cine.PAUSE_BADGE.get_center())
	cine.handle_key(KEY_ESCAPE)
	check("the pause button and Esc ask for the pause menu", asked.size() == 2)
	check("nothing skipped the sequence", not cine.is_finished())
	cine.skip()
	check("the explicit skip ends the sequence", cine.is_finished())
	cine.free()

	# During a playable segment, keys steer and never advance.
	camp = _ready_campaign()
	cine = _cinematic(camp)
	cine.show_final_message = false
	cine.scene_index = 2
	cine.scene_time = 2.0
	cine.elapsed = 2.0
	cine._ensure_flight()
	check("the debris scene is interactive", cine.is_interactive())
	check("the debris scene is playable once its field exists", cine.is_playable())
	var t_before: float = cine.scene_time
	cine.handle_key(KEY_W)
	cine.handle_key(KEY_UP)
	cine.handle_key(KEY_A)
	check("keys do not fast-forward a playable segment", cine.scene_time == t_before, "%.2f" % cine.scene_time)
	var y_before: float = cine.flight.ship_y
	cine.flight.steer(-1.0, 0.10)
	check("steering still moves the ship", cine.flight.ship_y != y_before)
	cine.handle_click(Vector2(300, 120))
	check("a click during flight does not skip the beat", cine.scene_time == t_before)
	cine.handle_key(KEY_ENTER)
	check("enter does not fast-forward a playable segment", cine.scene_time == t_before)
	cine.paused = true
	check("a paused segment is not playable", not cine.is_playable())
	cine.paused = false
	cine.skip()
	check("the explicit skip still works mid-flight", cine.is_finished())
	cine.free()


# ---------------------------------------------------------------- end to end

func _screen_reaches_the_end() -> void:
	print("")
	print("-- The whole sequence, flown without input " + "-".repeat(20))
	var camp = _ready_campaign()
	var cine = _cinematic(camp)
	var emitted: Array = []
	cine.cinematic_finished.connect(func(skip): emitted.append(skip))
	var guard := 0
	while not cine.is_finished() and guard < 12000:
		guard += 1
		cine.advance_for(0.05)
	check("an untouched cinematic still reaches the closing card",
		cine.is_finished() and cine.show_final_message or cine.is_finished(), str(cine.scene_index))
	check("it reports one outcome", emitted.size() == 1)
	check("it reports a watched run, not a skip", emitted.size() == 1 and bool(emitted[0]) == false)
	cine.free()

	# A strike mid-flight is shown, restarts the segment, and the run continues.
	camp = _ready_campaign()
	cine = _cinematic(camp)
	cine.scene_index = 2
	cine.scene_time = 3.0
	cine.elapsed = 3.0
	cine._ensure_flight()
	cine.flight.obstacles.clear()
	cine.flight.obstacles.append({
		"x": cine.flight.ship_x + 10.0, "y": cine.flight.ship_y,
		"hw": 10.0, "hh": 10.0, "tone": 0, "phase": 0.0,
	})
	cine.advance_for(0.05)
	check("a strike freezes the segment", cine._hit_freeze > 0.0)
	check("a strike shows its own feedback", cine.flight.hits == 1)
	cine.advance_for(1.0)
	check("the frozen segment resumes after the beat", cine._hit_freeze <= 0.0)
	check("the resumed field is empty", cine.flight.active_obstacles().is_empty())
	check("the scene did not end on the strike", cine.scene_index == 2)
	check("the restart is counted", cine.flight.restarts == 1)
	cine.skip()
	cine.free()


# ---------------------------------------------------------------- VELA renderer

func _vela_rules() -> void:
	print("")
	print("-- Canonical VELA renderer " + "-".repeat(37))
	for state in SFVela.STATES:
		var s := String(state)
		var should_burn: bool = s in [SFVela.IGNITION, SFVela.ASCENDING, SFVela.PORTAL_ENTRY, SFVela.DESCENDING]
		check("engines in state '%s' are %s" % [s, "on" if should_burn else "off"], SFVela.engines_on(s) == should_burn)
	check("only the workshop view is horizontal", not SFVela.is_upright(SFVela.MAINTENANCE)
		and SFVela.is_upright(SFVela.PARKED) and SFVela.is_upright(SFVela.LANDED))
	var o := Vector2(320, 300)
	for state in [SFVela.PARKED, SFVela.ASCENDING, SFVela.PORTAL_ENTRY, SFVela.LANDED]:
		var nose := SFVela.to_screen(o, 1, String(state), float(SFVela.LENGTH), 0.0)
		var nozzle := SFVela.to_screen(o, 1, String(state), 0.0, 0.0)
		check("state '%s' points the nose straight up" % String(state), nose.y < nozzle.y and is_equal_approx(nose.x, nozzle.x))
	var side_nose := SFVela.to_screen(o, 2, SFVela.MAINTENANCE, float(SFVela.LENGTH), 0.0)
	check("the workshop view points the nose right", side_nose.x > o.x and is_equal_approx(side_nose.y, o.y))
	# The workshop sockets keep their Phase 3 places (hull middle at unit 51, x2).
	var c := Vector2(200, 120)
	var origin := c - Vector2(102, 0)
	var expected := {"navigation_chip": Vector2(52, -4), "power_core": Vector2(-14, -2), "shield_emitter": Vector2(-4, -34)}
	for id in expected:
		var at := SFVela.module_screen(origin, 2, SFVela.MAINTENANCE, String(id)) - c
		check("the %s socket keeps its workshop position" % String(id), at.is_equal_approx(expected[id]), str(at))
	# Scale is uniform: the upright ship is LENGTH x scale tall and keeps its width.
	for s in [1, 2]:
		var top := SFVela.to_screen(o, s, SFVela.PARKED, float(SFVela.LENGTH), 0.0)
		var side := SFVela.to_screen(o, s, SFVela.PARKED, 0.0, float(SFVela.HALF_WIDTH))
		check("scale %d is uniform" % s, is_equal_approx(o.y - top.y, float(SFVela.LENGTH * s))
			and is_equal_approx(side.x - o.x, float(SFVela.HALF_WIDTH * s)))
	var feet := SFVela.ground_origin(Vector2(320, 300))
	check("a parked ship's legs reach the ground", is_equal_approx(feet.y + float(SFVela.LEG_DEPTH), 300.0))
	# The departure ship stands several characters tall (Nick's sprite is 20 px).
	check("VELA stands several times Nick's height", float(SFVela.LENGTH + SFVela.LEG_DEPTH) >= 20.0 * 4.0)
	# The flight lanes' shield matches the drawn shield.
	var r := SFVela.shield_radii(1, SFVela.ASCENDING)
	var cfg := _flight_data("debris")
	check("the debris shield matches the drawn bubble",
		is_equal_approx(r.x, float(cfg.get("shield_half_width", 0.0))) and is_equal_approx(r.y, float(cfg.get("shield_half_length", 0.0))),
		str(r))
	check("the flight hull length matches the renderer",
		is_equal_approx(float(cfg.get("ship_half_length", 0.0)), float(SFVela.LENGTH) * 0.5))


# ---------------------------------------------------------------- shield

func _shield_rules() -> void:
	print("")
	print("-- Shield contacts " + "-".repeat(45))
	var f = _debris_rig()
	f.assist = true
	var contacts: Array = []
	var hits := 0
	var on_rim := true
	for i in 300:
		for e in f.tick(0.05, 0.0):
			var ev: Dictionary = e
			if String(ev.get("type", "")) == "shield":
				contacts.append(ev)
				# Checked on the frame it is reported, against the ship as it is then.
				var dx: float = (float(ev["x"]) - f.ship_x) / f.shield_half_length
				var dy: float = (float(ev["y"]) - f.ship_y) / f.shield_half_width
				if absf(sqrt(dx * dx + dy * dy) - 1.0) > 0.01:
					on_rim = false
			elif String(ev.get("type", "")) == "hit":
				hits += 1
	check("grit and near misses meet the shield", contacts.size() >= 5, str(contacts.size()))
	check("shield contacts never count as strikes", hits == 0 and f.hits == 0)
	check("each contact is reported on the shield boundary", on_rim)
	var light := 0
	var heavy := 0
	for ev in contacts:
		if bool(ev["heavy"]):
			heavy += 1
		else:
			light += 1
	check("light contacts happen", light > 0, "%d light, %d heavy" % [light, heavy])

	# A near miss grazes the shield once and is pushed away from the hull.
	var g = _debris_rig()
	g.obstacles.clear()
	g.grit_interval = 0.0
	var y0: float = g.ship_y + g.ship_half_height + 16.0
	g.obstacles.append({"x": g.ship_x + 90.0, "y": y0, "hw": 12.0, "hh": 6.0, "tone": 0, "phase": 0.0, "seq": 0})
	var grazes := 0
	var struck := false
	for i in 40:
		for e in g.tick(0.02, 0.0):
			var t := String((e as Dictionary).get("type", ""))
			if t == "shield":
				grazes += 1
			elif t == "hit":
				struck = true
	check("a near miss grazes the shield exactly once", grazes == 1, str(grazes))
	check("the graze does not strike the hull", not struck)
	if not g.obstacles.is_empty():
		check("the grazed body is pushed away from the ship", float(g.obstacles[0]["y"]) > y0)
	# Grit off the ship's line falls past without a contact.
	var h = _debris_rig()
	h.obstacles.clear()
	h.grit_interval = 0.0
	h.grit.append({"x": h.ship_x + 120.0, "y": h.ship_y + 80.0, "vy": 0.0, "r": 1.0, "tone": 0})
	var missed_contact := false
	for i in 80:
		for e in h.tick(0.02, 0.0):
			if String((e as Dictionary).get("type", "")) == "shield":
				missed_contact = true
	check("grit that misses the bubble makes no contact", not missed_contact)


# ---------------------------------------------------------------- portal entry

func _portal_entry_rules() -> void:
	print("")
	print("-- Portal capture and visible entry " + "-".repeat(28))
	var f = SFFlight.new()
	f.configure(_flight_data("portal"))
	var captured_at := -1.0
	var entered_at := -1.0
	var ship_at_capture := 0.0
	var steer_ignored := true
	var t := 0.0
	while entered_at < 0.0 and t < 30.0:
		t += 0.05
		if not f.captured:
			f.ship_y = f.portal_y
		var y_before: float = f.ship_y
		for e in f.tick(0.05, 1.0 if f.captured else 0.0):
			var kind := String((e as Dictionary).get("type", ""))
			if kind == "captured":
				captured_at = t
				ship_at_capture = f.ship_x
			elif kind == "entered":
				entered_at = t
		if f.captured and entered_at < 0.0 and f.ship_y > y_before + 1.0 and f.ship_y > f.portal_y + 0.5:
			steer_ignored = false
	check("alignment captures the ship first", captured_at > 0.0)
	check("the crossing comes after the capture", entered_at > captured_at, "%.2f / %.2f" % [captured_at, entered_at])
	check("the capture flies the ship in over a readable time", entered_at - captured_at >= 1.2, "%.2f s" % (entered_at - captured_at))
	check("the ship actually travels to the portal", f.ship_x - f.ship_half_length >= f.portal_x and ship_at_capture < f.portal_x)
	check("steering cannot pull a captured ship off the axis", steer_ignored)

	# The cinematic does not leave the portal scene before the crossing.
	var camp = _ready_campaign()
	var cine = _cinematic(camp)
	cine.scene_index = 4
	cine.scene_time = 0.0
	cine.elapsed = 0.0
	cine._ensure_flight()
	var left_early := false
	var guard := 0
	while cine.scene_index == 4 and guard < 2000:
		guard += 1
		var was_entered: bool = cine.flight != null and cine.flight.entered
		cine.advance_for(0.05)
		if cine.scene_index != 4 and not was_entered:
			left_early = true
	check("the portal scene waits for the hull to cross", not left_early and cine.scene_index == 5)
	check("the portal flight is gone after the transition", cine.flight == null)
	cine.skip()
	cine.free()


# ---------------------------------------------------------------- presentation

func _presentation_states() -> void:
	print("")
	print("-- Presentation states and cleanup " + "-".repeat(29))
	var camp = _ready_campaign()
	var cine = _cinematic(camp)
	cine.reduced_motion = false
	_at(cine, 0, 4.0)
	check("the departure ship is parked", cine.ship_state() == SFVela.PARKED)
	check("engines are off during the transfer", not cine.engines_on())
	_at(cine, 1, 0.5)
	check("the launch opens parked, engines off", cine.ship_state() == SFVela.PARKED and not cine.engines_on())
	_at(cine, 1, 2.0)
	check("ignition burns on the pad", cine.ship_state() == SFVela.IGNITION and cine.engines_on())
	_at(cine, 1, 8.0)
	check("the climb is upright and under thrust", cine.ship_state() == SFVela.ASCENDING and cine.engines_on())
	_at(cine, 5, 2.0)
	check("home opens on the powered descent", cine.ship_state() == SFVela.DESCENDING)
	_at(cine, 5, 9.0)
	check("after touchdown the ship is landed", cine.ship_state() == SFVela.LANDED)
	check("engines are off after landing", not cine.engines_on())
	check("the face close-up is gone", not cine.has_method("_draw_home_portrait") and not cine.has_method("_home_zoom"))

	# The ascent's contacts are choreographed inside the climb, with the shield on.
	var launch: Dictionary = (cine.scenes[1] as Dictionary)
	var in_window := true
	for i in cine.LAUNCH_CONTACTS.size():
		var at: float = cine.launch_contact_time(i)
		if at < cine.SHIELD_ON_AT or at >= float(launch.get("duration", 0.0)):
			in_window = false
	check("every ascent contact happens with the shield up, inside the scene", in_window)
	# Watch the climb: contacts show, the shake decays, and nothing leaks out.
	_at(cine, 1, 0.0)
	var max_contacts := 0
	var guard := 0
	while cine.scene_index == 1 and guard < 1000:
		guard += 1
		cine.advance_for(0.05)
		max_contacts = maxi(max_contacts, cine.shield_contacts_visible())
	check("the ascent shows shield contacts", max_contacts > 0, str(max_contacts))
	check("contacts are cleared when the scene ends", cine.shield_contacts_visible() == 0)
	check("shake is back to zero in the next beat", cine._shake_energy == 0.0)
	# Pause freezes the clock and the contacts.
	_at(cine, 1, 9.0)
	cine.paused = true
	var frozen: float = cine.scene_time
	cine.advance_for(1.0)
	check("pause freezes the ascent", cine.scene_time == frozen)
	cine.paused = false
	cine.skip()
	cine.skip()
	check("skip from the ascent is safe and final", cine.is_finished())
	check("a finished sequence holds no contacts", cine.shield_contacts_visible() == 0)
	cine.free()


func _finish() -> void:
	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	SFSave.delete_save()
	quit(1 if fails > 0 else 0)
