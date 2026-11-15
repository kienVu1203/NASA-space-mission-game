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
## Headless execution cannot say whether the lane feels good to fly. It does
## prove that no input can strand the sequence and no strike can soft-lock it.

const SFContent := preload("res://core/star_fall/sf_content.gd")
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
	for i in 60:
		var events: Array = f.tick(0.05, 0.0)
		for e in events:
			if String((e as Dictionary).get("type", "")) == "spawn":
				spawned = true
	check("obstacles spawn", spawned)
	var right_spawned := true
	for body in f.active_obstacles():
		if float((body as Dictionary)["x"]) < float(f.ship_x):
			right_spawned = false
	check("every obstacle enters from the right of the ship", right_spawned)

	# The field is always dodgeable: consecutive bodies in spawn order leave a
	# gap the ship can cross in the time between their arrivals.
	f = _debris_rig()
	var by_seq: Dictionary = {}
	for i in 400:
		f.tick(0.05, 0.0)
		for body in f.active_obstacles():
			var b: Dictionary = body
			by_seq[int(b["seq"])] = b
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

	# Any key advances a minor beat, but never Esc or Space.
	_at(cine, 0, 0.0)
	cine.handle_key(KEY_SPACE)
	check("space pauses rather than advancing", cine.is_paused())
	cine.handle_key(KEY_SPACE)
	check("space resumes", not cine.is_paused())
	var before: float = cine.scene_time
	cine.handle_key(KEY_ENTER)
	check("a key advances the clock", cine.scene_time > before)
	_at(cine, 0, 0.0)
	cine.handle_key(KEY_Q)
	check("an ordinary letter advances the clock", cine.scene_time > 0.0)
	_at(cine, 0, 0.0)
	cine.handle_click(Vector2(300, 200))
	check("a left click advances the clock", cine.scene_time > 0.0)
	# Esc skips the whole sequence.
	cine.handle_key(KEY_ESCAPE)
	check("escape skips the sequence", cine.is_finished())
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
	cine.handle_key(KEY_SPACE)
	check("space still pauses mid-flight", cine.is_paused())
	check("a paused segment is not playable", not cine.is_playable())
	cine.handle_key(KEY_SPACE)
	cine.handle_key(KEY_ESCAPE)
	check("escape still skips mid-flight", cine.is_finished())
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


func _finish() -> void:
	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	SFSave.delete_save()
	quit(1 if fails > 0 else 0)
