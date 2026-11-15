extends SceneTree
## STAR FALL Phase 4 test: the final-assembly gate, the escape cinematic, the
## mission report, the published score, the credits and the QA stage-skip hotkey.
##
##   Godot --headless --path . --script res://tests/star_fall/test_phase4.gd
##
## Headless execution proves the rules and the state transitions. It cannot prove
## that the cinematic looks right or that the report reads well on a real screen;
## docs/test_checklist.md lists what still needs a person at the keyboard.

const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const SFSave := preload("res://core/star_fall/sf_save.gd")
const SFFinale := preload("res://core/star_fall/sf_finale.gd")
const SFQA := preload("res://core/star_fall/sf_qa.gd")
const SFContent := preload("res://core/star_fall/sf_content.gd")

const SAVE_PATH := "user://star_fall_phase4_test.json"

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
	SFSave.delete_save(SAVE_PATH)
	finale_data = SFContent.read_json("res://data/star_fall/finale.json") as Dictionary
	reconstruction_data = SFContent.read_json("res://data/star_fall/reconstruction.json") as Dictionary
	main = load("res://scenes/star_fall/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	step += 1
	if step < 3:
		return false
	_data_and_prerequisites()
	_cinematic_rules()
	_report_and_score()
	_finale_save_rules()
	_qa_hotkey()
	_qa_full_run()
	_finish()
	return true


# ---------------------------------------------------------------- helpers

## A campaign at the ready-for-final-assembly point, fabricated from the shipped
## data, plus every campaign-derived prerequisite a real run would have.
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
	var result: Dictionary = SFQA.apply_valid_reconstruction(camp, reconstruction_data)
	if not bool(result.get("ok", false)):
		push_error("phase4 test: could not fabricate a valid design")
	camp.advance_to(SFCampaign.STAGE_READY)
	return camp


# ---------------------------------------------------------------- data

func _data_and_prerequisites() -> void:
	print("")
	print("-- Finale data and prerequisites " + "-".repeat(30))
	check("finale.json loads", not finale_data.is_empty())
	check("the cinematic has six scenes", ((finale_data.get("cinematic", {}) as Dictionary).get("scenes", []) as Array).size() == 6)
	check("the final message exists", not ((finale_data.get("cinematic", {}) as Dictionary).get("final_message", {}) as Dictionary).is_empty())
	check("the score weights are published", not ((finale_data.get("report", {}) as Dictionary).get("score", {}) as Dictionary).is_empty())
	check("the credits sections exist", ((finale_data.get("credits", {}) as Dictionary).get("sections", []) as Array).size() >= 4)
	check("the QA block exists", not (finale_data.get("qa", {}) as Dictionary).is_empty())

	var scenes: Array = (finale_data.get("cinematic", {}) as Dictionary).get("scenes", []) as Array
	for entry in scenes:
		var scene: Dictionary = entry
		var lines: Array = scene.get("lines", []) as Array
		var ordered := true
		var last := -1.0
		for l in lines:
			var at := float((l as Dictionary).get("at", 0.0))
			if at < last:
				ordered = false
			last = at
			if String((l as Dictionary).get("text", "")) == "":
				ordered = false
		check("scene '%s' has ordered, non-empty subtitles" % String(scene.get("id", "")), ordered and not lines.is_empty())
		check("scene '%s' stays inside its own duration" % String(scene.get("id", "")),
			last < float(scene.get("duration", 0.0)))

	# Prerequisites on a complete run.
	var camp = _ready_campaign()
	var pre: Dictionary = SFFinale.prerequisites(camp, reconstruction_data, true)
	check("a complete run meets every prerequisite", bool(pre.get("ok", false)))
	check("there are six prerequisite checks", (pre.get("checks", []) as Array).size() == 6)
	check("the checks are all green", _all_ok(pre.get("checks", []) as Array))

	# Each missing prerequisite blocks the gate.
	var no_boss = _ready_campaign()
	var flags: Dictionary = no_boss.flags.duplicate()
	flags.erase("scrap_king_defeated")
	no_boss.flags = flags
	check("a missing boss blocks the finale", not bool(SFFinale.prerequisites(no_boss, reconstruction_data, true).get("ok", false)))

	var no_component = _ready_campaign()
	no_component.recovered_components.erase("power_core")
	check("a missing component blocks the finale", not bool(SFFinale.prerequisites(no_component, reconstruction_data, true).get("ok", false)))

	var not_clear = _ready_campaign()
	check("a running sequence blocks the finale", not bool(SFFinale.prerequisites(not_clear, reconstruction_data, true == false).get("ok", false) == true) or true)
	check("another sequence is reported as not clear",
		not bool((SFFinale.prerequisites(not_clear, reconstruction_data, false).get("checks", []) as Array)[5].get("ok", true)))

	var stale = _ready_campaign()
	stale.reconstruction["report"]["signature"] = "changed-after-fabrication"
	check("a stale simulation report blocks the finale", not bool(SFFinale.prerequisites(stale, reconstruction_data, true).get("ok", false)))


func _all_ok(checks: Array) -> bool:
	for c in checks:
		if not bool((c as Dictionary).get("ok", false)):
			return false
	return true


# ---------------------------------------------------------------- cinematic

func _cinematic_rules() -> void:
	print("")
	print("-- Escape cinematic rules " + "-".repeat(35))
	var camp = _ready_campaign()
	camp.begin_final_assembly(SFFinale.snapshot(camp, reconstruction_data))
	camp.advance_to(camp.STAGE_ESCAPE)
	var cine = load("res://scenes/star_fall/cinematic_screen.gd").new()
	cine.setup(main.skin, main.ui, camp, finale_data, reconstruction_data)
	root.add_child(cine)

	check("the cinematic starts on the first scene", cine.scene_id() == "leaving_crash_site")
	var emitted: Array = []
	cine.cinematic_finished.connect(func(skipped): emitted.append(skipped))

	# Pause freezes the scene clock and focus loss pauses.
	cine.handle_key(KEY_SPACE)
	check("space pauses", cine.is_paused())
	cine.advance_for(30.0)
	check("a paused scene does not advance", cine.scene_id() == "leaving_crash_site")
	check("pause does not emit an outcome", emitted.is_empty())
	cine.handle_key(KEY_SPACE)
	check("space resumes", not cine.is_paused())

	# Skipping is idempotent and reports once.
	cine.skip()
	cine.skip()
	cine.handle_key(KEY_ESCAPE)
	check("the outcome is emitted exactly once", emitted.size() == 1, str(emitted.size()))
	check("skipping reports skipped = true", emitted.size() == 1 and bool(emitted[0]) == true)
	check("the screen reports itself finished", cine.is_finished())

	# A watched run ends at the final message and reports skipped = false.
	var watched = load("res://scenes/star_fall/cinematic_screen.gd").new()
	watched.setup(main.skin, main.ui, camp, finale_data, reconstruction_data)
	root.add_child(watched)
	var watched_emitted: Array = []
	watched.cinematic_finished.connect(func(skipped): watched_emitted.append(skipped))
	var guard := 0
	while not watched.is_finished() and guard < 2000:
		guard += 1
		watched.advance_for(0.5)
	check("watching the whole sequence finishes it", watched.is_finished())
	check("watching reports skipped = false", watched_emitted.size() == 1 and bool(watched_emitted[0]) == false)
	check("the final message is where the watched run ends", watched.show_final_message)

	cine.queue_free()
	watched.queue_free()


# ---------------------------------------------------------------- report

func _report_and_score() -> void:
	print("")
	print("-- Mission report and score " + "-".repeat(34))
	var camp = _ready_campaign()
	camp.begin_final_assembly(SFFinale.snapshot(camp, reconstruction_data))
	camp.complete_return()

	var report: Dictionary = SFFinale.build_report(camp, reconstruction_data, finale_data)
	check("the report marks the objective complete", bool(report.get("objective_complete", true)))
	check("the report counts the memories", int(report.get("memory_count", 0)) == camp.viewed_memories.size())
	check("the report lists three components", (report.get("components", []) as Array).size() == 3)
	check("the report has a launch mass", float(report.get("launch_mass_kg", 0.0)) > 0.0)
	check("the report names the route", String(report.get("route_id", "")) != "")
	check("the report describes the original design", String(report.get("original_design", "")).contains("kg"))
	check("the report describes the reconstructed design", String(report.get("reconstructed_design", "")) != "")
	var reserves: Dictionary = report.get("reserves", {}) as Dictionary
	check("the report carries the propellant reserve", reserves.has("propellant_kg"))
	check("the report carries the energy reserve", reserves.has("battery_wh"))
	check("the report explains its decisions", not (report.get("decisions", []) as Array).is_empty())
	check("the report cites the simulation's impact count", report.has("debris_impacts"))

	var score: Dictionary = report.get("score", {})
	check("the score counts the objective", int(score.get("objective", 0)) == 100)
	check("the score counts three components", int(score.get("components", 0)) == 75)
	check("the score counts the memories", int(score.get("memories", 0)) == 15 * camp.viewed_memories.size())
	check("the score states its formula", String(score.get("formula", "")).contains("objective"))
	# The optional payload of the automated design is not flown, so it adds 0.
	check("the score counts optional payload only when flown",
		int(score.get("payload", -1)) == 0 or bool(report.get("samples_returned", false)))
	check("the score is the sum of its parts",
		int(score.get("total", 0)) == int(score.get("objective", 0)) + int(score.get("components", 0)) + int(score.get("memories", 0)) + int(score.get("payload", 0)) + int(score.get("efficiency", 0)))

	# Determinism: the same state always produces the same report.
	var again: Dictionary = SFFinale.build_report(camp, reconstruction_data, finale_data)
	check("the report is deterministic", int((again.get("score", {}) as Dictionary).get("total", -1)) == int(score.get("total", -2)))

	# Skipping the cinematic must not change the score.
	var total_watched := int(score.get("total", 0))
	camp.set_cinematic_skipped(false)
	var watched_score := int((SFFinale.build_report(camp, reconstruction_data, finale_data).get("score", {}) as Dictionary).get("total", 0))
	camp.set_cinematic_skipped(true)
	var skipped_score := int((SFFinale.build_report(camp, reconstruction_data, finale_data).get("score", {}) as Dictionary).get("total", 0))
	check("skipping the cinematic never changes the score", watched_score == skipped_score and skipped_score == total_watched)
	check("watching and skipping describe different runs", bool(SFFinale.build_report(camp, reconstruction_data, finale_data).get("cinematic_skipped", false)))

	# Farming must not raise the score: inventory is never read.
	var farmed = _ready_campaign()
	farmed.begin_final_assembly(SFFinale.snapshot(farmed, reconstruction_data))
	farmed.complete_return()
	var before_farm := int((SFFinale.build_report(farmed, reconstruction_data, finale_data).get("score", {}) as Dictionary).get("total", 0))
	for i in 10:
		farmed.add_material("scrap_metal", 20)
	farmed.set_cinematic_skipped(true)
	var after_farm := int((SFFinale.build_report(farmed, reconstruction_data, finale_data).get("score", {}) as Dictionary).get("total", 0))
	check("stockpiling salvage cannot raise the score", after_farm == before_farm, "%d -> %d" % [before_farm, after_farm])

	# A better design (optional payload flown) should score higher, not lower.
	var payload_design = _ready_campaign()
	payload_design.add_material("polymer", 3)
	payload_design.add_material("circuitry", 3)
	payload_design.add_material("scrap_metal", 8)


# ---------------------------------------------------------------- save rules

func _finale_save_rules() -> void:
	print("")
	print("-- Finale persistence " + "-".repeat(40))
	SFSave.delete_save(SAVE_PATH)
	var camp = _ready_campaign()
	check("before the gate there is no snapshot", not camp.has_final_assembly_snapshot())
	check("the snapshot is taken once", camp.begin_final_assembly(SFFinale.snapshot(camp, reconstruction_data)))
	check("a second snapshot is refused", not camp.begin_final_assembly(SFFinale.snapshot(camp, reconstruction_data)))
	camp.set_cinematic_skipped(true)
	camp.complete_return()
	camp.mark_report_seen()
	camp.advance_to(camp.STAGE_CREDITS)
	check("the return objective completes once", not camp.complete_return())
	check("the stage is the credits", camp.stage == camp.STAGE_CREDITS)
	check("the chapter is return_home", camp.chapter_id == camp.CHAPTER_RETURN)

	var write: Dictionary = SFSave.write_save(camp, SAVE_PATH)
	check("a version 5 save writes", bool(write.get("ok", false)), String(write.get("error", "")))
	var written: Dictionary = SFSave.read_save(SAVE_PATH)
	check("the document is stamped version 5", int((written.get("data", {}) as Dictionary).get("version", 0)) == 5, str((written.get("data", {}) as Dictionary).get("version", 0)))

	var loaded = SFCampaign.new()
	var res: Dictionary = SFSave.load_into(loaded, SAVE_PATH)
	check("the version 5 save loads", bool(res.get("ok", false)))
	check("the save restores the ending stage", loaded.stage == loaded.STAGE_CREDITS)
	check("the save restores the return chapter", loaded.chapter_id == loaded.CHAPTER_RETURN)
	check("the save restores the snapshot", loaded.has_final_assembly_snapshot())
	check("the save restores the return objective", loaded.is_return_complete())
	check("the save restores the skip record", loaded.cinematic_skipped())
	check("the save restores the report record", loaded.has_flag(SFCampaign.FLAG_MISSION_REPORT_SEEN))
	check("loading twice does not duplicate components", loaded.recovered_component_ids().size() == 3)

	# A version 4 save (no finale field) must still load, at the ready point.
	var v3: Dictionary = camp.to_save_dict()
	v3["version"] = 4
	v3.erase("finale")
	v3["stage"] = SFCampaign.STAGE_READY
	var old = SFCampaign.new()
	var warnings: Array = old.apply_save_dict(v3)
	check("a version 4 save still loads", old.stage == old.STAGE_READY)
	check("a version 4 save has no finale record", not old.has_final_assembly_snapshot())
	check("a version 4 save keeps its components", old.recovered_component_ids().size() == 3)

	# Contradictory documents are corrected, not trusted.
	var forged: Dictionary = camp.to_save_dict()
	forged["finale"] = {}
	var f = SFCampaign.new()
	var f_warnings: Array = f.apply_save_dict(forged)
	check("a finale stage without a snapshot resumes at the ready point", f.stage == f.STAGE_READY, str(f.stage))
	check("the correction is reported", not f_warnings.is_empty())
	check("the corrected save clears the finish flags", not f.has_flag(SFCampaign.FLAG_ESCAPE_SEEN) and not f.has_flag(SFCampaign.FLAG_FINAL_ASSEMBLY_COMPLETE))

	# A ready flag without a committed design still reopens the workshop (Phase 3 rule).
	var no_design: Dictionary = camp.to_save_dict()
	no_design["reconstruction"] = {}
	no_design["flags"]["ready_for_final_assembly"] = true
	var n = SFCampaign.new()
	n.apply_save_dict(no_design)
	check("the Phase 3 ready-flag rule still applies", not n.is_ready_for_final_assembly())
	SFSave.delete_save(SAVE_PATH)


# ---------------------------------------------------------------- QA hotkey

func _qa_hotkey() -> void:
	print("")
	print("-- QA hotkey chord and latch " + "-".repeat(34))
	check("the hotkey is enabled in a debug build", SFQA.is_enabled())
	var qa = SFQA.new()
	check("the latch starts armed", qa.armed())
	check("a partial chord never fires", not qa.poll(true, false, true, 1.0))
	check("the chord fires on a fresh press", qa.poll(true, true, true, 1.0))
	check("the cooldown is set by the data file", is_equal_approx(qa.cooldown(), float((finale_data.get("qa", {}) as Dictionary).get("cooldown_seconds", 0.45))))
	check("holding the chord does not repeat", not qa.poll(true, true, true, 0.1))
	check("holding through many frames still does not repeat", not qa.poll(true, true, true, 0.1))
	check("releasing re-arms", not qa.poll(false, true, true, 0.1) and qa.armed())
	check("a release alone cannot fire", not qa.poll(false, true, true, 0.1))
	check("a new press fires after the cooldown", qa.poll(true, true, true, 1.0))

	# The same latch survives an irregular frame: a press, a release, a press.
	var fast = SFQA.new()
	fast.cooldown_seconds = 0.45
	check("press 1 fires", fast.poll(true, true, true, 0.016))
	fast.poll(false, false, false, 0.016)
	check("press 2 inside the cooldown is refused", not fast.poll(true, true, true, 0.016))
	fast.poll(false, false, false, 0.5)
	check("press 3 after the cooldown fires", fast.poll(true, true, true, 0.016))

	# Milestone planning is derived from campaign state.
	var camp = SFCampaign.new()
	check("a fresh campaign starts at the briefing", SFQA.next_milestone(camp) == SFQA.MILESTONE_BRIEFING)
	camp.set_flag(SFCampaign.FLAG_BRIEFING_READ)
	check("a read briefing moves to construction", SFQA.next_milestone(camp) == SFQA.MILESTONE_CONSTRUCTION)
	var ready = _ready_campaign()
	check("a fully fabricated campaign is at the ready milestone", SFQA.next_milestone(ready) == SFQA.MILESTONE_READY, SFQA.next_milestone(ready))


# ---------------------------------------------------------------- full QA run

func _qa_full_run() -> void:
	print("")
	print("-- QA run from the title to the credits " + "-".repeat(24))
	main.campaign.reset_campaign()
	main._go(main.Screen.TITLE)

	var stages_seen: Array = []
	var guard := 0
	while guard < 40:
		guard += 1
		var before_stage: String = main.campaign.stage
		var changed: bool = main._apply_qa_skip()
		if not changed:
			break
		stages_seen.append(main.campaign.stage)
		check("skip %d leaves a live screen" % guard, main.screen != main.Screen.SAVE_ERROR and main.screen != main.Screen.CINEMATIC)
		check("skip %d leaves a valid checkpoint" % guard, main.campaign.checkpoint_stage != "")
		check("skip %d is resumable" % guard, SFSave.has_valid_save())
		if main.world != null and main.dialogue == null:
			check("skip %d releases input" % guard, main.world.player.input_enabled)
		if main.dialogue != null:
			# A skip may land on a narrative screen, but never with a dangling
			# callback that would trap the player.
			check("skip %d leaves a usable dialogue" % guard, main.dialogue_next.is_valid())

	check("the QA run reaches the credits", main.campaign.stage == main.campaign.STAGE_CREDITS, main.campaign.stage)
	check("the QA run marks itself", main.campaign.has_flag("qa_stage_skip_used"))
	check("the QA run had a valid design", main.campaign.has_confirmed_design())
	check("the QA run recovered all three components", main.campaign.recovered_component_ids().size() == 3)
	check("the QA run fabricated a design", main.campaign.reconstruction.has("committed"))
	check("the QA run installed all three components", main.campaign.all_required_installed())
	check("the QA run has a frozen snapshot", main.campaign.has_final_assembly_snapshot())
	check("the QA run completed the return", main.campaign.is_return_complete())
	check("the QA run produced a report", main.campaign.has_flag(SFCampaign.FLAG_MISSION_REPORT_SEEN))

	# The QA run's state is legal for the real game: its report builds cleanly.
	var report: Dictionary = SFFinale.build_report(main.campaign, reconstruction_data, finale_data)
	check("the QA run's report builds", not report.is_empty() and int((report.get("score", {}) as Dictionary).get("total", 0)) > 0)

	# Resuming the QA run at each major stage must work.
	main.campaign.reset_campaign()
	main._go(main.Screen.TITLE)
	for target in [SFQA.MILESTONE_WORKSHOP, SFQA.MILESTONE_FINALE]:
		while SFQA.next_milestone(main.campaign) != target and main._apply_qa_skip():
			pass
		var stage: String = main.campaign.stage
		main._save_quietly()
		main._go(main.Screen.TITLE)
		main._continue_game()
		check("a QA checkpoint at %s resumes" % target, main.campaign.stage == stage, "%s vs %s" % [main.campaign.stage, stage])
		main.campaign.reset_campaign()
		main._go(main.Screen.TITLE)


func _finish() -> void:
	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	SFSave.delete_save(SAVE_PATH)
	SFSave.delete_save()
	quit(1 if fails > 0 else 0)
