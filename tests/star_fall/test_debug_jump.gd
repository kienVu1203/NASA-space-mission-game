extends SceneTree
## STAR FALL debug-hotkey suite: every Ctrl+Shift+Alt phase jump lands on the
## right screen with a consistent campaign, and the in-fight commands (win,
## heal, salvage) go through the normal reward paths.
##
##   Godot --headless --path . --script res://tests/star_fall/test_debug_jump.gd
##
## Like test_flow.gd, this deletes user://star_fall_save.json. Back up a real
## save first.

const SFSave := preload("res://core/star_fall/sf_save.gd")
const SFDebugPresets := preload("res://core/star_fall/sf_debug_presets.gd")
const DebugJump := preload("res://scenes/star_fall/debug_jump.gd")

var main
var dj
var step: int = 0
var fails: int = 0
var checks_run: int = 0


func check(label: String, ok: bool, detail: String = "") -> void:
	checks_run += 1
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1


func finish_dialogue() -> void:
	var guard := 0
	while main.dialogue != null and guard < 400:
		guard += 1
		main._handle_dialogue_key(KEY_ENTER)


func _initialize() -> void:
	SFSave.delete_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DebugJump.BACKUP_PATH))
	main = load("res://scenes/star_fall/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	step += 1
	if step == 3:
		_run()
		print("")
		print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
		SFSave.delete_save()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DebugJump.BACKUP_PATH))
		quit(1 if fails > 0 else 0)
	return false


func _key(code: int, ctrl: bool, shift: bool, alt: bool, echo: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = echo
	ev.keycode = code
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	return ev


func _drop_present() -> bool:
	return main.world != null and main.world.prop_by_id("dawn_shield_drop") != null \
		and not main.world.prop_by_id("dawn_shield_drop").is_queued_for_deletion()


func _run() -> void:
	print("-- Debug hotkeys " + "-".repeat(44))
	dj = main.debug_jump
	check("the hotkey component exists in a debug build", dj != null and OS.is_debug_build())
	if dj == null:
		return

	# The chord: all three modifiers, a fresh press.
	check("Ctrl+Shift+Alt+key is a chord", DebugJump.is_chord(_key(KEY_1, true, true, true)))
	check("Ctrl+Shift+key alone is not", not DebugJump.is_chord(_key(KEY_1, true, true, false)))
	check("a plain key is not", not DebugJump.is_chord(_key(KEY_1, false, false, false)))
	check("held-key echo is not", not DebugJump.is_chord(_key(KEY_1, true, true, true, true)))
	check("an unbound key is not a command", not dj.handle_key(KEY_Z))

	# A real save exists before the first jump: it is backed up once.
	SFSave.write_save(main.campaign)
	check("every preset has a unique key", _unique_keys())
	var expect := {
		"construction": [main.Screen.CONSTRUCTION, ""],
		"crash_site": [main.Screen.WORLD, "crash_site"],
		"forgotten_city": [main.Screen.WORLD, "forgotten_city"],
		"scrap_king": [main.Screen.DUEL, ""],
		"silent_coast": [main.Screen.WORLD, "silent_coast"],
		"toxic_tide": [main.Screen.DUEL, ""],
		"dawn_tower": [main.Screen.WORLD, "dawn_tower"],
		"sky_remnant": [main.Screen.TYPING, ""],
		"shield_drop": [main.Screen.WORLD, "dawn_tower"],
		"workshop": [main.Screen.WORKSHOP, ""],
	}
	for p in SFDebugPresets.PRESETS:
		var id := String((p as Dictionary)["id"])
		var keycode := KEY_0 + int(String((p as Dictionary)["key"]))
		check("%s: Ctrl+Shift+Alt+%s is handled" % [id, String(p["key"])], dj.handle_key(keycode))
		var e: Array = expect[id]
		check("%s: lands on the right screen" % id, main.screen == int(e[0]) and (String(e[1]) == "" or main.zone == String(e[1])),
			"%s %s" % [str(main.screen), main.zone])
		check("%s: the stage matches the preset" % id, main.campaign.stage == String(p["stage"]), main.campaign.stage)
	check("the first jump backed up the existing save", FileAccess.file_exists(DebugJump.BACKUP_PATH))

	# Spot checks that each phase is consistent, not just on the right screen.
	dj.jump("dawn_tower")
	finish_dialogue()
	check("Dawn Tower: both Phase 2 components, no shield, no drop",
		main.campaign.has_component("navigation_chip") and main.campaign.has_component("power_core")
		and not main.campaign.has_component("shield_emitter") and not _drop_present())
	main._on_world_interact("dawn_boss_gate", main.world.prop_by_id("dawn_boss_gate"))
	check("Dawn Tower: the gate opens the fight (memory and checkpoint done)", main.screen == main.Screen.TYPING)

	# V wins the typing fight through the normal reward path.
	dj.jump("sky_remnant")
	finish_dialogue()
	check("Sky Remnant: the fight is running", main.typing_duel != null and main.typing_duel.encounter.is_fighting())
	main.typing_duel.encounter.nick_health = 10
	check("K heals Nick in the typing fight", dj.handle_key(KEY_K) and main.typing_duel.encounter.nick_health == main.typing_duel.encounter.nick_health_max)
	check("V wins the typing fight", dj.handle_key(KEY_V) and main.typing_duel.encounter.phase == "victory")
	check("the forced win has consistent accounting", main.typing_duel.encounter.boss_health == 0
		and main.typing_duel.encounter.credited.size() == main.typing_duel.encounter.total_letters())
	main.typing_duel.advance_for(3.0)
	main.typing_duel.handle_key(KEY_ENTER)
	finish_dialogue()
	check("the win drops the shield on the slope", main.screen == main.Screen.WORLD and _drop_present()
		and main.campaign.reward_state("sky_remnant_defeated", "shield_emitter") == "available")

	dj.jump("shield_drop")
	check("Shield drop: the pickup is waiting", _drop_present() and not main.campaign.has_component("shield_emitter"))

	# V wins a shield duel and the Phase 2 reward is awarded once.
	dj.jump("scrap_king")
	finish_dialogue()
	check("Scrap King: the navigation chip is not yet recovered", not main.campaign.has_component("navigation_chip"))
	main.duel.encounter.model.nick_health = 5
	check("K heals Nick in the shield duel", dj.handle_key(KEY_K) and main.duel.encounter.model.nick_health == main.duel.encounter.model.nick_health_max)
	check("V wins the shield duel", dj.handle_key(KEY_V) and main.duel.state == main.duel.State.VICTORY)
	main.duel._confirm_victory()
	check("the duel win awards the navigation chip once", main.campaign.recovered_component_ids().count("navigation_chip") == 1)

	# The workshop preset: shield collected but not fitted; M adds salvage.
	dj.jump("workshop")
	finish_dialogue()
	var ws = main.workshop_screen
	check("Workshop: all three parts ready, none fitted", ws != null and ws._state("shield_emitter") == "ready" and main.campaign.installed_component_ids().is_empty())
	var scrap: int = main.campaign.material_count("scrap_metal")
	check("M adds salvage", dj.handle_key(KEY_M) and main.campaign.material_count("scrap_metal") == scrap + 10)
	check("V outside a fight does nothing", not dj.win_fight())
	check("H toggles the help list", dj.handle_key(KEY_H) and dj.help_visible and dj.handle_key(KEY_H) and not dj.help_visible)

	# The construction preset leaves a valid design ready to confirm.
	dj.jump("construction")
	check("Construction: the pre-filled design passes validation", main.campaign.design.is_valid(main.campaign.content))


func _unique_keys() -> bool:
	var seen: Dictionary = {}
	for p in SFDebugPresets.PRESETS:
		var k := String((p as Dictionary)["key"])
		if seen.has(k):
			return false
		seen[k] = true
	return true
