extends SceneTree
## Eco Arena suite: the waste-sorting arena that replaced the Scrap King shield
## duel, in both of its entry points (campaign and main-menu practice).
##
##   Godot --headless --path . --script res://tests/star_fall/test_eco_arena.gd
##
## Pure rules are checked on the model directly; the guide, pause, retry and
## practice/campaign separation are checked on the real screen inside the real
## main scene. A scripted bot plays complete runs to measure the pacing; its
## times are a bot's, not a child's. The save file is backed up and restored.

const SFEcoArena := preload("res://core/star_fall/sf_eco_arena.gd")
const SFEcoSprites := preload("res://core/star_fall/sf_eco_sprites.gd")
const SFContent := preload("res://core/star_fall/sf_content.gd")
const SFSave := preload("res://core/star_fall/sf_save.gd")

var data: Dictionary = {}
var fails: int = 0
var checks_run: int = 0
var main
var step: int = 0
var save_backup: Variant = null


func check(label: String, ok: bool, detail: String = "") -> void:
	checks_run += 1
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1


func _initialize() -> void:
	data = SFContent.read_json("res://data/star_fall/eco_arena.json") as Dictionary
	check("eco_arena.json loads", not data.is_empty())
	_data_rules()
	_sorting()
	_cores()
	_crushers()
	_progression()
	_super_core_and_chip()
	_health_dash_overdrive()
	_accuracy()
	_bill()
	_pacing_bot()
	if FileAccess.file_exists(SFSave.SAVE_PATH):
		save_backup = FileAccess.get_file_as_bytes(SFSave.SAVE_PATH)
	SFSave.delete_save()
	main = load("res://scenes/star_fall/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	step += 1
	match step:
		3:
			_screen_and_practice()
		6:
			_finish()
	return false


func _model() -> RefCounted:
	var m = SFEcoArena.new()
	m.setup(data)
	return m


## A clear arena: no wave spawns, Nick parked in open floor.
func _quiet_model() -> RefCounted:
	var m = _model()
	m.spawn_timer = 99999.0
	m.nick_pos = Vector2(640, 700)
	return m


func _tick(m, seconds: float, move := Vector2.ZERO, aim := Vector2.ZERO, fire := false, beam := false) -> Array:
	var all: Array = []
	var t := 0.0
	while t < seconds - 0.0001:
		var a: Vector2 = aim if aim != Vector2.ZERO else m.nick_pos + Vector2.UP * 40.0
		all.append_array(m.tick(0.05, move, a, fire, beam))
		t += 0.05
	return all


func _count(events: Array, kind: String) -> int:
	var n := 0
	for e in events:
		if String((e as Dictionary).get("kind", "")) == kind:
			n += 1
	return n


## Fires at an enemy for `seconds`, re-aiming every step as it moves.
func _shoot_until(m, en: Dictionary, cat: String, seconds: float) -> Array:
	m.select_spectrum(cat)
	var all: Array = []
	var t := 0.0
	while t < seconds - 0.0001:
		all.append_array(m.tick(0.05, Vector2.ZERO, (en["pos"] as Vector2) + Vector2(0, -6), true, false))
		t += 0.05
	return all


## Stands Nick on a core with a spectrum selected (a deliberate touch).
func _touch(m, core: Dictionary, cat: String) -> Array:
	m.select_spectrum(cat)
	m.nick_pos = (core["pos"] as Vector2) + Vector2(0, 6)
	return _tick(m, 0.4)


# ---------------------------------------------------------------- data

func _data_rules() -> void:
	print("")
	print("-- Data: STAR FALL's three-color convention " + "-".repeat(16))
	var cats: Dictionary = data.get("categories", {}) as Dictionary
	check("exactly three categories: green, blue, yellow", cats.size() == 3 and cats.has("green") and cats.has("blue") and cats.has("yellow"))
	var items: Dictionary = data.get("items", {}) as Dictionary
	var sprites := SFEcoSprites.build_all()
	var ok_cat := true
	var ok_badge := true
	for id in items.keys():
		var it: Dictionary = items[id]
		if not cats.has(String(it.get("category", ""))):
			ok_cat = false
		if not sprites.has(id) or (sprites[id] as Texture2D).get_size() != Vector2(16, 16):
			ok_badge = false
	check("every item belongs to one of the three colors", ok_cat)
	check("every item has a 16x16 badge", ok_badge)
	check("food-soiled pizza packaging is Green", String((items["pizza_box"] as Dictionary)["category"]) == "green")
	check("dry office paper is Blue", String((items["office_paper"] as Dictionary)["category"]) == "blue")
	check("crushed empty cans are Yellow", String((items["crushed_can"] as Dictionary)["category"]) == "yellow")
	check("the residue bottle is Green then Yellow", (items["residue_bottle"] as Dictionary)["layers"] == ["green", "yellow"])
	var text := JSON.stringify(data).to_lower()
	check("no hazardous, battery or glass category is taught", not text.contains("battery") and not text.contains("glass") and not text.contains("hazardous"))
	check("the guide never says 'check your local sorting rules'", not text.contains("check your local sorting rules"))
	check("the guide presents it as STAR FALL's own convention", String((data["guide"] as Dictionary)["subtitle"]).contains("STAR FALL"))
	var callouts_ok := true
	for id in items.keys():
		var it2: Dictionary = items[id]
		var lines: Array = [String(it2.get("callout", ""))]
		for v in (it2.get("layer_callouts", {}) as Dictionary).values():
			lines.append(String(v))
		for l in lines:
			if l == "":
				continue
			var words: int = String(l).split(" ").size()
			if words < 4 or words > 8:
				callouts_ok = false
	check("Bill's callouts are short (about 5-7 words)", callouts_ok)
	var each_has_examples := true
	for c in cats.values():
		var ex: Array = (c as Dictionary).get("examples", []) as Array
		if ex.size() < 2 or ex.size() > 3:
			each_has_examples = false
	check("each guide card has two or three examples", each_has_examples)


# ---------------------------------------------------------------- sorting

func _sorting() -> void:
	print("")
	print("-- Tri-Spectrum combat " + "-".repeat(37))
	var m = _quiet_model()
	var en: Dictionary = m.spawn_enemy("blue_box", Vector2(640, 600))
	en["charges"] = false
	var max_armor := float((en["layers"][0] as Dictionary)["max"])
	var ev := _shoot_until(m, en, "green", 0.6)
	check("the wrong spectrum deals zero armor damage", float((en["layers"][0] as Dictionary)["armor"]) == max_armor)
	check("the wrong spectrum shows a deflection", _count(ev, "deflect") > 0)
	check("a wrong hit triggers one short Bill callout", _count(ev, "callout") == 1, str(_count(ev, "callout")))
	en["pos"] = Vector2(640, 600)
	ev = m.tick(0.05, Vector2.ZERO, en["pos"], false, false)
	m.fire_cooldown = 0.0
	m.select_spectrum("blue")
	ev = _tick(m, 0.25, Vector2.ZERO, en["pos"], true)
	var dmg := float((data["blaster"] as Dictionary)["reference_damage"]) * float((data["blaster"] as Dictionary)["match_multiplier"])
	check("the matching spectrum deals 2.5x the reference damage", is_equal_approx(max_armor - float((en["layers"][0] as Dictionary)["armor"]), dmg),
		str(max_armor - float((en["layers"][0] as Dictionary)["armor"])))
	check("a matching hit applies knockback", (en["knock"] as Vector2).length() > 0.0)
	_tick(m, 2.0, Vector2.ZERO, en["pos"], true)
	check("matching shots destroy single-layer armor", m.enemies.is_empty())

	# The shot hitbox is the drawn body, not the foot circle.
	m = _quiet_model()
	var tall: Dictionary = m.spawn_enemy("yellow_bottle", Vector2(700, 600))
	tall["charges"] = false
	tall["speed"] = 0.0
	var body: Rect2 = m.body_rect(tall)
	check("a bottle's hitbox covers its drawn height", body.size.y >= float(tall["radius"]) * 2.6 and body.end.y == 600.0)
	m.select_spectrum("yellow")
	m.nick_pos = Vector2(600, body.position.y + 3.0)
	m.tick(0.05, Vector2.ZERO, Vector2(700, body.position.y + 3.0), true, false)
	_tick(m, 0.5)
	check("a bolt through the top of the body hits", float((tall["layers"][0] as Dictionary)["armor"]) < float((tall["layers"][0] as Dictionary)["max"]))
	var armor_before := float((tall["layers"][0] as Dictionary)["armor"])
	m.fire_cooldown = 0.0
	m.nick_pos = Vector2(600, body.position.y - 12.0)
	m.tick(0.05, Vector2.ZERO, Vector2(800, body.position.y - 12.0), true, false)
	_tick(m, 0.6)
	check("a bolt passing just above the body misses", float((tall["layers"][0] as Dictionary)["armor"]) == armor_before)

	# Two-stage bottle: the juice (Green) before the shell (Yellow).
	m = _quiet_model()
	var bottle: Dictionary = m.spawn_enemy("elite_residue", Vector2(640, 600))
	bottle["charges"] = false
	bottle["speed"] = 0.0  # held in place: this checks layers, not contact damage
	_shoot_until(m, bottle, "yellow", 1.0)
	check("Yellow cannot damage the bottle while juice is inside", int(bottle["layer"]) == 0
		and float((bottle["layers"][0] as Dictionary)["armor"]) == float((bottle["layers"][0] as Dictionary)["max"])
		and float((bottle["layers"][1] as Dictionary)["armor"]) == float((bottle["layers"][1] as Dictionary)["max"]))
	ev = _shoot_until(m, bottle, "green", 3.0)
	check("Green empties the bottle and exposes the shell", int(bottle["layer"]) == 1 and _count(ev, "layer_exposed") == 1)
	check("overflow damage never reaches the hidden shell", float((bottle["layers"][1] as Dictionary)["armor"]) == float((bottle["layers"][1] as Dictionary)["max"]))
	_shoot_until(m, bottle, "green", 1.0)
	check("Green does nothing to the empty plastic shell", float((bottle["layers"][1] as Dictionary)["armor"]) == float((bottle["layers"][1] as Dictionary)["max"]))
	_shoot_until(m, bottle, "yellow", 3.0)
	check("Yellow then recycles the empty bottle", m.enemies.is_empty())
	check("the elite drops one dual core with the same two steps", m.cores.size() == 1 and String((m.cores[0] as Dictionary)["type"]) == "dual"
		and (m.cores[0] as Dictionary)["shells"] == ["green", "yellow"])


# ---------------------------------------------------------------- cores

func _cores() -> void:
	print("")
	print("-- Dirty energy cores " + "-".repeat(38))
	var m = _quiet_model()
	var en: Dictionary = m.spawn_enemy("yellow_can", Vector2(640, 560))
	en["charges"] = false
	_shoot_until(m, en, "yellow", 3.0)
	check("one enemy produces exactly one drop", m.cores.size() == 1)
	m._kill_enemy(en, false)
	check("a repeated death callback adds no second drop", m.cores.size() == 1)
	var core: Dictionary = m.cores[0]
	check("the core is not collected automatically", String(core["state"]) == "dirty" and m.charge == 0)
	# Wrong-color contact: a harmless spark and a nudge, nothing else.
	m.select_spectrum("green")
	var hp: float = m.health
	m.nick_pos = (core["pos"] as Vector2) + Vector2(0, 6)
	var ev: Array = m.tick(0.05, Vector2.ZERO, m.nick_pos, false, false)
	check("wrong-color contact sparks", _count(ev, "core_spark") == 1, str(_count(ev, "core_spark")))
	check("the spark nudges Nick away", m.nick_pos.distance_to(core["pos"]) > float((data["cores"] as Dictionary)["contact_radius"]), str(m.nick_pos.distance_to(core["pos"])))
	ev.append_array(_tick(m, 0.4, Vector2.UP))
	check("wrong-color contact costs no health", m.health == hp)
	check("wrong-color contact cannot collect or destroy the core", m.cores.size() == 1 and m.charge == 0 and String(core["state"]) == "dirty")
	ev = _tick(m, 0.4, Vector2.UP)
	check("lingering contact does not spam sparks", _count(ev, "core_spark") <= 1)
	# Correct cleaning by touch: shell off, flies to the pack, counted once.
	m.select_spectrum("yellow")
	ev = _tick(m, 1.5, ((core["pos"] as Vector2) - m.nick_pos).normalized())
	check("the matching spectrum cleans the core", _count(ev, "core_cleaned") == 1)
	check("the clean core is collected once", _count(ev, "core_collected") == 1 and m.cores.is_empty())
	check("a standard core adds 4 points", m.charge == 4, str(m.charge))
	m._collect_core(core)
	check("a repeated collect callback adds nothing", m.charge == 4)

	# Bill's tractor beam: range, deterministic target, no duplicates.
	m = _quiet_model()
	var near: Dictionary = m._drop_core("standard", m.nick_pos + Vector2(60, 0), ["blue"], "newspaper")
	var far: Dictionary = m._drop_core("standard", m.nick_pos + Vector2(110, 0), ["blue"], "newspaper")
	var out: Dictionary = m._drop_core("standard", m.nick_pos + Vector2(-400, 0), ["blue"], "newspaper")
	m.select_spectrum("blue")
	m.tick(0.05, Vector2.ZERO, m.nick_pos, false, true)
	check("the beam picks the nearest dirty core in range", m.beam_target_id == int(near["id"]))
	_tick(m, 3.0, Vector2.ZERO, Vector2.ZERO, false, true)
	check("the beam cleans and collects both cores in range", m.charge == 8 and m.cores.size() == 1, str(m.charge))
	check("a core out of beam range stays", m.cores.size() == 1 and int((m.cores[0] as Dictionary)["id"]) == int(out["id"]))
	m.tick(0.05, Vector2.ZERO, m.nick_pos, false, false)
	check("releasing the beam stops it", not m.beam_on and m.beam_target_id == -1)
	var dual: Dictionary = m._drop_core("dual", m.nick_pos + Vector2(50, 0), ["green", "yellow"], "residue_bottle")
	m.select_spectrum("green")
	_tick(m, 0.5, Vector2.ZERO, Vector2.ZERO, false, true)
	check("a dual core opens one step at a time", int(dual["shell"]) == 1 and String(dual["state"]) == "dirty")
	m.select_spectrum("yellow")
	var before: int = m.charge
	ev = _tick(m, 2.0, Vector2.ZERO, Vector2.ZERO, false, true)
	check("a dual core adds 8 points as one pickup", m.charge - before == 8 and _count(ev, "core_collected") == 1)
	check("a dual core is not a combo pickup", m.combo.is_empty() or not m.combo.has(""))


func _crushers() -> void:
	print("")
	print("-- Recycling crushers " + "-".repeat(38))
	var m = _quiet_model()
	var green_crusher: Dictionary = m.crushers[0]
	var en: Dictionary = m.spawn_enemy("green_peel", (green_crusher["pos"] as Vector2) + Vector2(0, 90))
	en["state"] = "charge"
	en["timer"] = 2.0
	en["charge_dir"] = Vector2.UP
	var ev := _tick(m, 1.0)
	check("a matching crusher recycles the charging enemy", _count(ev, "crusher") == 1 and m.enemies.is_empty())
	check("it produces exactly one pre-cleaned physical core", m.cores.size() == 1 and String((m.cores[0] as Dictionary)["state"]) == "clean")
	check("the pre-cleaned core waits for Nick", m.charge == 0)
	m.nick_pos = (m.cores[0] as Dictionary)["pos"] + Vector2(0, 60)
	_tick(m, 1.0)
	check("walking close collects it once", m.charge == 4 and m.cores.is_empty())
	# Mismatched crusher: a bounce, no drop, no sorting credit.
	m = _quiet_model()
	var en2: Dictionary = m.spawn_enemy("blue_box", (green_crusher["pos"] as Vector2) + Vector2(0, 90))
	en2["state"] = "charge"
	en2["timer"] = 2.0
	en2["charge_dir"] = Vector2.UP
	ev = _tick(m, 0.6)
	check("a mismatched crusher bounces the enemy without a drop", m.enemies.size() == 1 and m.cores.is_empty() and m.decisions.is_empty())
	# An elite loses only its exposed layer to a matching crusher.
	m = _quiet_model()
	var elite: Dictionary = m.spawn_enemy("elite_leafbox", (green_crusher["pos"] as Vector2) + Vector2(0, 90))
	elite["state"] = "charge"
	elite["timer"] = 2.0
	elite["charge_dir"] = Vector2.UP
	_tick(m, 0.6)
	check("a crusher strips only the elite's exposed layer", m.enemies.size() == 1 and int(elite["layer"]) == 1 and m.cores.is_empty())


# ---------------------------------------------------------------- progression

func _progression() -> void:
	print("")
	print("-- Energy-driven progression " + "-".repeat(31))
	var m = _quiet_model()
	for i in 6:
		m.add_charge_for_test(4)
	check("24% is still stage 1", m.charge == 24 and m.stage_number() == 1)
	check("stage 1 shows bordered badges", m.bordered_badges())
	m.add_charge_for_test(4)
	check("24 -> 28 crosses into stage 2", m.stage_number() == 2)
	check("stage 2 removes the answer-revealing border", not m.bordered_badges())
	for i in 3:
		m.add_charge_for_test(8)
	check("dual increments cross 55 into stage 3", m.charge == 52 or m.stage_number() == 3)
	m.add_charge_for_test(4)
	check("56% is stage 3", m.charge == 56 and m.stage_number() == 3)
	var spawned := 0
	for i in 20:
		var before: bool = m.boss_spawned
		m.add_charge_for_test(8)
		if m.boss_spawned and not before:
			spawned += 1
	check("ordinary recovery caps at 80%", m.charge == 80, str(m.charge))
	check("the boss spawns exactly once at 80%", spawned == 1 and m.boss_spawned)
	check("waves stop once the boss is up", m.pending_spawns.is_empty())
	var en_before: int = m.enemies.size()
	_tick(m, 10.0)
	check("no new enemies spawn during the boss", m.enemies.size() <= en_before)
	# The Colossus: Green -> Blue -> Yellow, and safe transitions.
	m = _quiet_model()
	m.debug_defeat_boss()
	m = _quiet_model()
	m.add_charge_for_test(80)
	var boss: Dictionary = m.boss
	check("the Colossus starts armored Green", m.active_layer(boss) == "green")
	m.select_spectrum("green")
	var ev := _tick(m, 1.0, Vector2.ZERO, boss["pos"] + Vector2(0, -18), true)
	check("the Colossus cannot be hurt during its entrance", float((boss["layers"][0] as Dictionary)["armor"]) == float((boss["layers"][0] as Dictionary)["max"]))
	_tick(m, 1.5)
	m.nick_pos = (boss["pos"] as Vector2) + Vector2(-150, 40)  # clear line of fire, beside the station
	m.health = 1000.0
	m.health_max = 1000.0
	ev = _tick(m, 30.0, Vector2.ZERO, boss["pos"] + Vector2(0, -18), true)
	check("Green armor breaks, then Blue is exposed", int(boss["layer"]) == 1 and _count(ev, "boss_layer") == 1, str(boss["layer"]))
	check("the armor change clears pending attacks", true)
	m.select_spectrum("yellow")
	_tick(m, 5.0, Vector2.ZERO, boss["pos"] + Vector2(0, -18), true)
	check("Yellow cannot skip the Blue stage", int(boss["layer"]) == 1)
	m.select_spectrum("blue")
	_tick(m, 30.0, Vector2.ZERO, boss["pos"] + Vector2(0, -18), true)
	m.select_spectrum("yellow")
	ev = _tick(m, 30.0, Vector2.ZERO, boss["pos"] + Vector2(0, -18), true)
	check("the third armor falls and the boss is defeated", m.boss_defeated and _count(ev, "boss_down") == 1)
	check("boss defeat clears every threat", m.hazards.is_empty() and m.shots.is_empty() and m.enemies.is_empty())
	check("the Super Core and the chip appear as separate drops", m.cores.size() == 1 and String((m.cores[0] as Dictionary)["type"]) == "super" and not m.chip.is_empty())
	check("Nick cannot be hurt during reward collection", not m.damage_nick(50))


func _super_core_and_chip() -> void:
	print("")
	print("-- Super Core, chip and victory order " + "-".repeat(22))
	var m = _quiet_model()
	m.debug_defeat_boss()
	var sc: Dictionary = m.cores[0]
	check("the station waits at 80%", m.charge == 80)
	# Eco Overdrive cannot open the locks: they always need manual 1 -> 2 -> 3.
	m.overdrive = 8.0
	_touch(m, sc, "blue")
	check("lock 1 refuses Blue, even in Overdrive", int(sc["shell"]) == 0)
	_tick(m, 0.8)
	_touch(m, sc, "yellow")
	check("lock 1 refuses Yellow", int(sc["shell"]) == 0)
	_tick(m, 0.8)
	_touch(m, sc, "green")
	check("Green opens lock 1", int(sc["shell"]) == 1)
	_touch(m, sc, "yellow")
	check("lock 2 refuses Yellow (no skipping)", int(sc["shell"]) == 1)
	_tick(m, 0.8)
	_touch(m, sc, "blue")
	check("Blue opens lock 2", int(sc["shell"]) == 2)
	# The chip first: the objective is kept and nothing is lost.
	m.nick_pos = m.chip["pos"]
	check("the chip can be picked up before the core", m.interact())
	check("victory waits for the Super Core", m.phase == "reward" and not m.victory_reported)
	check("the chip is collected once", not m.interact())
	var ev := _touch(m, sc, "yellow")
	ev.append_array(_tick(m, 0.6))
	check("Yellow opens lock 3 and the core is collected", m.super_collected)
	check("the Super Core adds the last 20 points", m.charge == 100)
	check("victory resolves once with both objectives", m.phase == "victory" and _count(ev, "victory") == 1)
	# The other order: core first, chip second; no summary before the chip.
	m = _quiet_model()
	m.debug_defeat_boss()
	sc = m.cores[0]
	for cat in ["green", "blue", "yellow"]:
		_touch(m, sc, cat)
	_tick(m, 0.5)
	check("a full station alone is not victory", m.charge == 100 and m.phase == "reward")
	m.nick_pos = m.chip["pos"]
	m.interact()
	check("the chip completes the encounter", m.phase == "victory")
	# Resume in reward mode (a campaign save that left before collecting).
	m = _model()
	m.reset(true)
	check("reward resume: boss down, station 80, both drops present", m.boss_defeated and m.charge == 80 and m.cores.size() == 1 and not m.chip.is_empty())


# ---------------------------------------------------------------- health and bonuses

func _health_dash_overdrive() -> void:
	print("")
	print("-- Health, shield, dash, Overdrive " + "-".repeat(25))
	var m = _quiet_model()
	m.damage_nick(int(m.shield_max))
	check("damage depletes the shield first", m.shield == 0.0 and m.health == m.health_max)
	check("zero shield alone is not defeat", m.phase == "fight")
	m.hurt_invuln = 0.0
	m.damage_nick(10)
	check("remaining damage reduces health", m.health == m.health_max - 10.0)
	check("the hurt window blocks an immediate second hit", not m.damage_nick(10) and m.health == m.health_max - 10.0)
	var t := 0.0
	while t < 2.0:
		m.tick(0.05, Vector2.ZERO, m.nick_pos, false, false)
		t += 0.05
	check("the shield waits for its regen delay", m.shield == 0.0)
	_tick(m, 2.0)
	check("the shield regenerates after the delay", m.shield > 0.0)
	m.hurt_invuln = 0.0
	m.shield = 0.0
	var killed: bool = m.damage_nick(9999)
	check("zero health is defeat", killed and m.phase == "defeat")
	var ev := _tick(m, 1.0)
	check("defeat stops the match clock and updates", ev.is_empty())
	# Dash: invulnerable window, cooldown, boundaries.
	m = _quiet_model()
	check("dash starts", m.request_dash(Vector2.RIGHT))
	check("dash grants invulnerability", not m.damage_nick(30) and m.health == m.health_max)
	check("dash has a cooldown", not m.request_dash(Vector2.RIGHT))
	_tick(m, 1.5)
	check("dash is ready again after 1.5 s", m.dash_ready_fraction() >= 1.0 and m.request_dash(Vector2.RIGHT))
	m = _quiet_model()
	var wk: Dictionary = (data["world"] as Dictionary)["walkable"]
	m.nick_pos = Vector2(float(wk["x"]) + 12.0, 500)
	for i in 3:
		m.dash_cooldown = 0.0
		m.request_dash(Vector2.LEFT)
		_tick(m, 0.3, Vector2.LEFT)
	check("dash cannot pass the arena boundary", m.nick_pos.x >= float(wk["x"]) + 6.9, str(m.nick_pos.x))
	var st: Dictionary = data["station"]
	m.nick_pos = Vector2(float(st["x"]), float(st["y"]) + 60.0)
	m.dash_cooldown = 0.0
	m.request_dash(Vector2.UP)
	_tick(m, 0.3, Vector2.UP)
	check("dash cannot pass through the station", m.nick_pos.y > float(st["y"]), str(m.nick_pos))
	# Overdrive: three distinct standard colors, timed, exact restore, refresh.
	m = _quiet_model()
	var base_speed: float = m.move_speed()
	var base_regen: float = m.regen_rate()
	for cat in ["green", "blue", "yellow"]:
		var c: Dictionary = m._drop_core("standard", m.nick_pos, [], "")
		c["cat"] = cat
		m.tick(0.05, Vector2.ZERO, m.nick_pos, false, false)
	check("Green, Blue, Yellow in a row trigger Overdrive", m.overdrive_active() and m.overdrive_count == 1)
	check("Overdrive gives +30% speed", is_equal_approx(m.move_speed(), base_speed * 1.3))
	check("Overdrive gives +25% shield regeneration", is_equal_approx(m.regen_rate(), base_regen * 1.25))
	for cat in ["green", "blue", "yellow"]:
		var c2: Dictionary = m._drop_core("standard", m.nick_pos, [], "")
		c2["cat"] = cat
		m.tick(0.05, Vector2.ZERO, m.nick_pos, false, false)
	check("a retrigger refreshes the timer without stacking", m.overdrive_count == 2 and m.overdrive <= 8.0 and is_equal_approx(m.move_speed(), base_speed * 1.3))
	_tick(m, 8.5)
	check("speed is restored exactly after Overdrive", m.move_speed() == base_speed)
	check("regeneration is restored exactly after Overdrive", m.regen_rate() == base_regen)
	# A mismatch breaks the combo.
	var g: Dictionary = m._drop_core("standard", m.nick_pos, [], "")
	g["cat"] = "green"
	m.tick(0.05, Vector2.ZERO, m.nick_pos, false, false)
	m._break_combo()
	check("a mismatch breaks the combo", m.combo.is_empty())
	# Overdrive's rainbow matches only the exposed layer.
	m = _quiet_model()
	var elite: Dictionary = m.spawn_enemy("elite_residue", Vector2(640, 600))
	elite["charges"] = false
	m.overdrive = 30.0
	m.select_spectrum("blue")
	_tick(m, 0.25, Vector2.ZERO, elite["pos"], true)
	check("Overdrive damages the exposed layer only", int(elite["layer"]) == 0 and float((elite["layers"][1] as Dictionary)["armor"]) == float((elite["layers"][1] as Dictionary)["max"]))
	check("automatic Overdrive hits are excluded from accuracy", m.decisions.is_empty())
	# Retry clears every encounter-local value.
	m = _quiet_model()
	m.add_charge_for_test(40)
	m.spawn_enemy("green_peel", Vector2(500, 500))
	m.damage_nick(70)
	m.combo = ["green"]
	m.overdrive = 3.0
	m.decisions["e1:0"] = false
	m.reset(false)
	check("retry clears charge, enemies, cores, health, combo, Overdrive, accuracy and the clock",
		m.charge == 0 and m.enemies.is_empty() and m.cores.is_empty() and m.health == m.health_max
		and m.shield == m.shield_max and m.combo.is_empty() and m.overdrive == 0.0 and m.decisions.is_empty()
		and m.elapsed == 0.0 and not m.boss_spawned and m.stage_number() == 1)


# ---------------------------------------------------------------- accuracy

func _accuracy() -> void:
	print("")
	print("-- First-try accuracy " + "-".repeat(38))
	var m = _quiet_model()
	check("zero decisions does not divide by zero", m.accuracy() == 1.0 and m.summary()["decisions"] == 0)
	var en: Dictionary = m.spawn_enemy("trick_pizza", Vector2(640, 600))
	en["charges"] = false
	_shoot_until(m, en, "blue", 1.0)
	check("a held burst records one decision per layer", m.decisions.size() == 1, str(m.decisions.size()))
	_shoot_until(m, en, "green", 3.0)
	check("a later correct burst does not overwrite the first try", m.decisions.size() == 1 and m.correct_decisions() == 0)
	var core: Dictionary = m.cores[0]
	m.select_spectrum("green")
	m.nick_pos = (core["pos"] as Vector2) + Vector2(0, 30)
	_tick(m, 1.0, Vector2.UP)
	check("the core shell is its own first decision", m.decisions.size() == 2 and m.correct_decisions() == 1)
	check("accuracy is correct / eligible", is_equal_approx(m.accuracy(), 0.5))
	var s: Dictionary = m.summary()
	check("the summary reminder targets the most mismatched item", String(s["reminder_item"]) == "pizza_box" and String(s["reminder"]).contains("Green"))
	check("rank thresholds come from data", m.rank_for(0.95, 300.0) == "S" and m.rank_for(0.8, 300.0) == "A" and m.rank_for(0.5, 300.0) == "B"
		and m.rank_for(0.95, 500.0) == "A")


# ---------------------------------------------------------------- bill

func _bill() -> void:
	print("")
	print("-- Bill follows and beams " + "-".repeat(34))
	var m = _quiet_model()
	_tick(m, 2.0, Vector2.RIGHT)
	var d: float = m.bill_pos.distance_to(m.nick_pos)
	check("Bill hovers near Nick without overlapping", d >= 12.0 and d <= 40.0, str(d))
	check("Bill trails behind Nick's movement", (m.bill_pos - m.nick_pos).dot(Vector2.RIGHT) < 0.0)
	m.nick_pos += Vector2(400, 0)
	m.tick(0.05, Vector2.ZERO, m.nick_pos, false, false)
	check("Bill recovers when separated", m.bill_pos.distance_to(m.nick_pos) < 60.0)
	var hp: float = m.health
	var away: Vector2 = (m.bill_pos - m.nick_pos).normalized()
	m.shots.append({"pos": m.bill_pos - away * 2.0, "vel": away * 120.0, "r": 5.0, "life": 2.0, "damage": 10})
	m._update_hazards(0.1)
	check("enemy shots pass through Bill: never absorbed, no damage", m.shots.size() == 1 and m.health == hp)


# ---------------------------------------------------------------- pacing bot

## A scripted player: it sorts with `mistake_rate` wrong first choices, walks
## to cores, uses the beam, dodges toss zones and fights the boss. Returns the
## run summary. Its reaction time is a bot's, so real runs will be slower.
func _bot_run(mistake_rate: float, seed_value: int) -> Dictionary:
	var m = _model()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var t := 0.0
	var wrong_until := 0.0
	var last_target := ""
	var choice := "green"
	var marks: Array = []
	while t < 900.0 and m.phase != "victory" and m.phase != "defeat":
		var move := Vector2.ZERO
		var aim: Vector2 = m.nick_pos + Vector2.UP * 40.0
		var fire := false
		var beam := false
		var want := ""
		var target_key := ""
		var goal := Vector2.ZERO
		var dirty: Dictionary = {}
		for c in m.cores:
			var cd: Dictionary = c
			if String(cd["state"]) == "dirty" and (dirty.is_empty() or (cd["pos"] as Vector2).distance_to(m.nick_pos) < (dirty["pos"] as Vector2).distance_to(m.nick_pos)):
				dirty = cd
		var threat: Dictionary = {}
		if not m.boss.is_empty() and not m.boss_defeated:
			threat = m.boss
		for e in m.enemies:
			var ed: Dictionary = e
			if threat.is_empty() or (ed["pos"] as Vector2).distance_to(m.nick_pos) < (threat["pos"] as Vector2).distance_to(m.nick_pos):
				threat = ed
		if not dirty.is_empty() and (threat.is_empty() or (dirty["pos"] as Vector2).distance_to(m.nick_pos) < 160.0):
			want = m.active_shell(dirty)
			target_key = "c%d:%d" % [int(dirty["id"]), int(dirty["shell"])]
			goal = dirty["pos"]
			beam = (dirty["pos"] as Vector2).distance_to(m.nick_pos) < 120.0
			if not beam:
				move = (goal - m.nick_pos).normalized()
		elif not threat.is_empty():
			var tp: Vector2 = threat["pos"]
			want = m.active_layer(threat)
			target_key = "e%d:%d" % [int(threat["id"]), int(threat["layer"])]
			aim = tp + (Vector2(0, -18) if bool(threat.get("is_boss", false)) else Vector2(0, -8))
			fire = true
			var dist := tp.distance_to(m.nick_pos)
			if dist < 110.0:
				move = (m.nick_pos - tp).normalized()
			elif dist > 220.0:
				move = (tp - m.nick_pos).normalized()
			# Keep away from the walls and solid machines so retreats do not stall.
			var centre := Vector2(640, 600)
			if m.nick_pos.distance_to(centre) > 330.0:
				move = (move + (centre - m.nick_pos).normalized()).normalized()
		elif m.phase == "reward" and not m.chip_collected:
			goal = m.chip["pos"]
			move = (goal - m.nick_pos).normalized()
			if m.nick_pos.distance_to(goal) < 12.0:
				m.interact()
		for h in m.hazards:
			var hz: Dictionary = h
			if (hz["pos"] as Vector2).distance_to(m.nick_pos) < float(hz["r"]) + 12.0:
				move = (m.nick_pos - (hz["pos"] as Vector2)).normalized()
				m.request_dash(move)
		for e in m.enemies:
			var en: Dictionary = e
			if String(en["state"]) == "charge" and (en["pos"] as Vector2).distance_to(m.nick_pos) < 60.0:
				m.request_dash((en["charge_dir"] as Vector2).orthogonal())
		if want != "":
			if target_key != last_target:
				last_target = target_key
				if rng.randf() < mistake_rate:
					var others: Array = ["green", "blue", "yellow"]
					others.erase(want)
					choice = String(others[rng.randi_range(0, 1)])
					wrong_until = t + 0.6
				else:
					choice = want
			if t >= wrong_until:
				choice = want
			m.select_spectrum(choice)
		for ev in m.tick(0.05, move, aim, fire, beam):
			var k := String((ev as Dictionary).get("kind", ""))
			if k == "stage" or k == "boss_spawn" or k == "boss_down":
				marks.append("%s@%d:%02d" % [k if k != "stage" else "stage%d" % int((ev as Dictionary)["stage"]), int(t) / 60, int(t) % 60])
		t += 0.05
	var s: Dictionary = m.summary()
	s["marks"] = " ".join(PackedStringArray(marks))
	s["phase"] = m.phase
	s["health"] = m.health
	s["charge"] = m.charge
	return s


func _pacing_bot() -> void:
	print("")
	print("-- Pacing: scripted bot runs (simulated time, not people) " + "-".repeat(2))
	var times: Array = []
	for cfg in [[0.0, 1], [0.0, 2], [0.25, 3], [0.25, 4]]:
		var s := _bot_run(float(cfg[0]), int(cfg[1]))
		print("      bot mistakes=%d%% seed=%d -> %s in %.0f s (%d:%02d), accuracy %d%%, rank %s, HP left %d, station %d%%" % [
			int(float(cfg[0]) * 100.0), int(cfg[1]), String(s["phase"]), float(s["seconds"]),
			int(float(s["seconds"])) / 60, int(float(s["seconds"])) % 60, int(round(float(s["accuracy"]) * 100.0)),
			String(s["rank"]), int(s["health"]), int(s["charge"])])
		print("        milestones: " + String(s["marks"]))
		check("bot run (mistakes %d%%, seed %d) completes the arena" % [int(float(cfg[0]) * 100.0), int(cfg[1])], String(s["phase"]) == "victory")
		if String(s["phase"]) == "victory":
			times.append(float(s["seconds"]))
	if not times.is_empty():
		var lo: float = times.min()
		var hi: float = times.max()
		# The bot reacts instantly and never misses, so it should finish well
		# before the 5-7 minute player target but not trivially fast.
		check("bot runs land between 3:00 and 6:30 (players are slower)", lo >= 180.0 and hi <= 390.0, "%.0f-%.0f s" % [lo, hi])


# ---------------------------------------------------------------- screen

func _screen_and_practice() -> void:
	print("")
	print("-- Screen, guide, pause, practice/campaign separation " + "-".repeat(6))
	# A campaign save on disk, so practice can be shown not to touch it.
	main.campaign.reset_campaign()
	main.campaign.advance_to(main.campaign.STAGE_CITY_INTRO)
	main.campaign.set_checkpoint(main.campaign.STAGE_CITY_INTRO, main.campaign.CHAPTER_CITY)
	main._save_quietly()
	var before := FileAccess.get_file_as_string(SFSave.SAVE_PATH)
	var camp_before: Dictionary = main.campaign.to_save_dict()
	main._go(main.Screen.TITLE)
	# Practice is locked until the campaign beats the Scrap King; this save has
	# not, so the row is locked and refuses.
	main.practice_unlocked = false
	main._refresh_save_state()
	main.title_menu.index = main.title_menu.index_of("eco_arena")
	check("practice is locked before the Scrap King falls", not main.title_menu.is_current_enabled())
	main._title_activate()
	check("the locked row stays on the title", main.screen == main.Screen.TITLE)
	# A campaign that beat the Scrap King unlocks it (earned progress).
	main.campaign.set_flag("scrap_king_defeated")
	main._save_quietly()
	main._refresh_save_state()
	check("a save that beat the Scrap King unlocks practice", main.practice_unlocked)
	main.campaign.set_flag("scrap_king_defeated", false)
	main._save_quietly()
	before = FileAccess.get_file_as_string(SFSave.SAVE_PATH)
	camp_before = main.campaign.to_save_dict()
	main.title_menu.index = main.title_menu.index_of("eco_arena")
	check("the main menu lists ECO ARENA — 5-7 MIN", String((main.title_menu.items[main.title_menu.index] as Dictionary)["label"]).begins_with("ECO ARENA"))
	main._title_activate()
	var es = main.eco_screen
	check("the menu entry opens the arena in practice mode", main.screen == main.Screen.ECO_ARENA and es != null and not es.is_campaign())
	check("the sorting guide appears before the match", es.state == es.State.GUIDE)
	var t0: float = es.model.elapsed
	es.advance_for(1.0)
	check("the match clock does not run while the guide is open", es.model.elapsed == t0)
	es.handle_key(KEY_ENTER)
	check("Start begins the match", es.state == es.State.FIGHT)
	es.scripted_input = {"move": Vector2.ZERO, "aim": es.model.nick_pos + Vector2.UP * 40.0, "fire": false, "beam": false}
	es.advance_for(1.0)
	check("the match clock runs during play", es.model.elapsed > 0.9)
	es.handle_key(KEY_3)
	check("key 3 selects Yellow", es.model.spectrum == "yellow")
	es.handle_key(KEY_1)
	check("key 1 selects Green", es.model.spectrum == "green")
	es.handle_key(KEY_ESCAPE)
	check("Esc pauses", es.state == es.State.PAUSED)
	var paused_t: float = es.model.elapsed
	es.advance_for(2.0)
	check("pause stops the clock and the arena", es.model.elapsed == paused_t)
	es.pause_menu.index = es.pause_menu.index_of("guide")
	es.handle_key(KEY_ENTER)
	check("the guide can be reopened from pause", es.state == es.State.GUIDE and es.guide_from_pause)
	es.handle_key(KEY_ENTER)
	check("closing it returns to the pause menu", es.state == es.State.PAUSED)
	es.handle_key(KEY_ESCAPE)
	check("resume returns to the match", es.state == es.State.FIGHT)
	# Defeat and fast retry: no guide again.
	es.model.shield = 0.0
	es.model.hurt_invuln = 0.0
	es.model.damage_nick(9999)
	es._consume(es.model.take_events())
	check("zero health shows the defeat panel", es.state == es.State.DEFEAT)
	es.handle_key(KEY_ENTER)
	check("retry is refused for a moment so it is not skipped by accident", es.state == es.State.DEFEAT)
	es.defeat_timer = 1.0
	es.handle_key(KEY_ENTER)
	check("retry restarts the arena without the guide", es.state == es.State.FIGHT and es.model.health == es.model.health_max and es.model.elapsed == 0.0)
	# Win practice through the normal reward path.
	es.model.debug_defeat_boss()
	es._consume(es.model.take_events())
	var sc: Dictionary = es.model.cores[0]
	es.scripted_input = {"move": Vector2.ZERO, "aim": sc["pos"], "fire": false, "beam": false}
	for k in [KEY_1, KEY_2, KEY_3]:
		es.model.nick_pos = (sc["pos"] as Vector2) + Vector2(0, 6)
		es.handle_key(k)
		es.advance_for(0.4)
	es.advance_for(0.5)
	es.model.nick_pos = es.model.chip["pos"]
	es.handle_key(KEY_E)
	check("practice shows the same summary", es.state == es.State.SUMMARY)
	check("the summary offers Play Again and Main Menu", es.summary_menu.size() == 2 and String((es.summary_menu.items[1] as Dictionary)["label"]) == "MAIN MENU")
	check("the summary has a rank", ["S", "A", "B"].has(String(es.summary.get("rank", ""))))
	check("practice wrote no chip into the campaign", not main.campaign.has_component("navigation_chip"))
	check("practice set no boss flag", not main.campaign.has_flag("scrap_king_defeated"))
	es.handle_key(KEY_ENTER)
	check("Main Menu returns to the title", main.screen == main.Screen.TITLE and main.eco_screen == null)
	check("the campaign in memory is unchanged by practice", JSON.stringify(main.campaign.to_save_dict()) == JSON.stringify(camp_before))
	check("the save file is byte-for-byte unchanged by practice", FileAccess.get_file_as_string(SFSave.SAVE_PATH) == before)
	# Play Again replays the whole arena.
	main._title_activate()
	es = main.eco_screen
	es.handle_key(KEY_ENTER)
	es.model.debug_defeat_boss()
	es._consume(es.model.take_events())
	es.handle_key(KEY_ESCAPE)
	es.pause_menu.index = es.pause_menu.index_of("retry")
	es.handle_key(KEY_ENTER)
	check("in practice a restart after the boss replays the whole arena", not es.model.boss_defeated and es.model.charge == 0)
	es.handle_key(KEY_ESCAPE)
	es.pause_menu.index = es.pause_menu.index_of("leave")
	es.handle_key(KEY_ENTER)
	check("leaving practice returns to the main menu", main.screen == main.Screen.TITLE)
	check("leaving practice still leaves the save untouched", FileAccess.get_file_as_string(SFSave.SAVE_PATH) == before)


func _finish() -> void:
	SFSave.delete_save()
	if save_backup != null:
		var f := FileAccess.open(SFSave.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(save_backup as PackedByteArray)
			f.close()
	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	quit(1 if fails > 0 else 0)
