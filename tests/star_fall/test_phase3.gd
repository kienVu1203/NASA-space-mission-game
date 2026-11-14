extends SceneTree
## STAR FALL Phase 3 suite: vocabulary library, typing rules, the Sky Remnant
## encounter accounting and pacing, the reconstruction workshop, the return
## simulation, rewards and persistence.
##
##   Godot --headless --path . --script res://tests/star_fall/test_phase3.gd
##
## The simulated typists below are scripted bots. Their timings are evidence
## that the rules leave slow and fast profiles a viable path; they are not
## playtest data and say nothing about real children or adults.

const SFVocabulary := preload("res://core/star_fall/sf_vocabulary.gd")
const SFTyping := preload("res://core/star_fall/sf_typing.gd")
const SFTypingEncounter := preload("res://core/star_fall/sf_typing_encounter.gd")
const SFContent := preload("res://core/star_fall/sf_content.gd")
const SFReconstruction := preload("res://core/star_fall/sf_reconstruction.gd")
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const SFSave := preload("res://core/star_fall/sf_save.gd")

const ALL_COMPONENTS := ["navigation_chip", "power_core", "shield_emitter"]
var recon_data: Dictionary = {}

var fails: int = 0
var checks_run: int = 0
var vocab
var typing_data: Dictionary = {}


func check(label: String, ok: bool, detail: String = "") -> void:
	checks_run += 1
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1


func section(title: String) -> void:
	print("")
	print("-- " + title + " " + "-".repeat(maxi(4, 60 - title.length())))


func _initialize() -> void:
	vocab = SFVocabulary.new()
	typing_data = SFContent.read_json("res://data/star_fall/typing.json") as Dictionary
	_test_vocabulary()
	_test_deck()
	_test_typing_rules()
	_test_encounter_accounting()
	_test_miss_and_requeue()
	_test_retry_and_pause()
	_test_simulated_typists()
	_extra_tests()
	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	quit(1 if fails > 0 else 0)


func _extra_tests() -> void:
	recon_data = SFContent.read_json("res://data/star_fall/reconstruction.json") as Dictionary
	_test_simulation_model()
	_test_workshop_designs()
	_test_workshop_rules()
	_test_campaign_rewards_and_save()


# ---------------------------------------------------------------- vocabulary

func _test_vocabulary() -> void:
	section("Vocabulary library")
	var ok: bool = vocab.load_all()
	check("the library loads and validates", ok, ", ".join(vocab.errors.slice(0, 3)))
	check("the library has at least 180 entries", vocab.size() >= 180, str(vocab.size()))
	var ids: Dictionary = {}
	var texts: Dictionary = {}
	var bad_chars := 0
	var empty := 0
	for e in vocab.entries:
		var entry: Dictionary = e
		ids[String(entry["id"])] = true
		texts[String(entry["text"])] = true
		if not SFVocabulary.is_valid_target(String(entry["text"])):
			bad_chars += 1
		if String(entry.get("definition", "")).strip_edges() == "" or String(entry.get("example", "")).strip_edges() == "":
			empty += 1
	check("every id is unique", ids.size() == vocab.size())
	check("every typing text is unique", texts.size() == vocab.size())
	check("no typing text has invalid characters", bad_chars == 0, str(bad_chars))
	check("no entry has an empty definition or example", empty == 0, str(empty))
	for band in vocab.bands:
		check("band '%s' has entries" % band, vocab.entries_for_band(String(band)).size() >= 20)
	for cat in vocab.categories:
		var n := 0
		for e in vocab.entries:
			if String((e as Dictionary)["category"]) == String(cat):
				n += 1
		check("category '%s' is covered" % cat, n >= 5, str(n))

	# The validator itself must catch every class of defect.
	var broken := {
		"bands": ["foundation"], "categories": ["nature"],
		"entries": [
			{"id": "a", "text": "tree", "definition": "x", "example": "x", "category": "nature", "band": "foundation"},
			{"id": "a", "text": "tree", "definition": "", "example": "x", "category": "space", "band": "expert"},
			{"id": "c", "text": "Bio-Fuel", "definition": "x", "example": "x", "category": "nature", "band": "foundation"},
			{"id": "d", "text": "eau", "example": "x", "category": "nature", "band": "foundation"},
		],
	}
	var errs: Array = SFVocabulary.validate_dict(broken)
	var joined := " | ".join(errs)
	check("the validator reports duplicate ids", joined.findn("duplicate id") >= 0)
	check("the validator reports duplicate typing text", joined.findn("duplicate typing text") >= 0)
	check("the validator reports empty definitions", joined.findn("'definition'") >= 0)
	check("the validator reports unknown bands", joined.findn("unknown band") >= 0)
	check("the validator reports unknown categories", joined.findn("unknown category") >= 0)
	check("the validator reports invalid characters", joined.findn("lowercase a-z") >= 0)
	check("accented and hyphenated text is rejected", not SFVocabulary.is_valid_target("café") and not SFVocabulary.is_valid_target("re-use"))


func _stages() -> Array:
	return (typing_data["deck"] as Dictionary)["stages"] as Array


func _test_deck() -> void:
	section("Encounter deck selection")
	var deck: Array = vocab.select_deck(_stages(), 51207)
	var want := 0
	for s in _stages():
		want += int((s as Dictionary)["count"])
	check("the deck has the configured size", deck.size() == want, "%d of %d" % [deck.size(), want])
	check("the deck is far smaller than the library", deck.size() * 4 < vocab.size())
	var seen: Dictionary = {}
	var dup := false
	for e in deck:
		if seen.has(String((e as Dictionary)["id"])):
			dup = true
		seen[String((e as Dictionary)["id"])] = true
	check("no entry repeats inside one deck", not dup)
	var ordered := true
	var last_stage := 0
	for e in deck:
		var entry: Dictionary = e
		if int(entry["stage"]) < last_stage:
			ordered = false
		last_stage = int(entry["stage"])
	check("the deck runs from the easy stage to the hard stage", ordered)
	var first_band := String(vocab.entry(String((deck[0] as Dictionary)["id"]))["band"])
	var last_band := String(vocab.entry(String((deck[deck.size() - 1] as Dictionary)["id"]))["band"])
	check("the deck opens with foundation words", first_band == "foundation", first_band)
	check("the deck closes with advanced words", last_band == "advanced", last_band)
	var deck2: Array = vocab.select_deck(_stages(), 51207)
	check("the same seed selects the same deck", str(deck) == str(deck2))
	var deck3: Array = vocab.select_deck(_stages(), 999)
	check("a different seed selects a different deck", str(deck) != str(deck3))
	var est: float = SFTypingEncounter.estimate_seconds(deck, typing_data)
	print("      estimated duration at the assumed pace: %.0f s (%.1f min)" % [est, est / 60.0])
	check("the planned duration is in the 3-4 minute target", est >= 150.0 and est <= 270.0, "%.0f s" % est)


# ---------------------------------------------------------------- typing

func _w(uid: int, text: String, y: float) -> Dictionary:
	return {"uid": uid, "text": text, "y": y}


func _test_typing_rules() -> void:
	section("Typing targets and progress")
	var t = SFTyping.new()
	var words := [_w(1, "tree", 150.0), _w(2, "tide", 200.0), _w(3, "soil", 180.0)]
	var r: Dictionary = t.input("t", words)
	check("a first letter selects a word", String(r["kind"]) == "select")
	check("with two matches the word closest to the bottom wins", t.target_uid == 2)
	check("the selecting letter counts as progress", t.progress == 1)
	r = t.input("i", words)
	check("a correct letter advances the target", String(r["kind"]) == "advance" and t.progress == 2)
	r = t.input("s", words)
	check("a wrong letter resets the target", String(r["kind"]) == "reset" and t.progress == 0)
	check("the reset keeps the word selected", t.target_uid == 2)
	check("the wrong key does not select another word", t.target_uid != 3)
	r = t.input("i", words)
	check("after a reset the next letter must be the first letter", String(r["kind"]) == "reset" and t.progress == 0)
	r = t.input("t", words)
	check("restarting from the first letter works", String(r["kind"]) == "advance" and t.progress == 1)
	t.input("i", words)
	t.input("d", words)
	r = t.input("e", words)
	check("finishing the word completes it", String(r["kind"]) == "complete" and int(r["uid"]) == 2)
	check("completion clears the target", not t.has_target())
	r = t.input("x", words)
	check("a letter that matches nothing is a harmless no-match", String(r["kind"]) == "no_match" and not t.has_target())
	check("uppercase maps to the same letter", SFTyping.letter_from_unicode(84) == "t")
	check("digits are ignored", SFTyping.letter_from_unicode(55) == "")
	check("space is ignored", SFTyping.letter_from_unicode(32) == "")
	check("accented letters are ignored", SFTyping.letter_from_unicode(233) == "")
	t.input("s", words)
	t.release()
	check("explicit cancellation drops the target", not t.has_target() and t.progress == 0)
	t.input("s", words)
	t.on_word_removed(3)
	check("a removed target is released", not t.has_target())


# ---------------------------------------------------------------- encounter

func _new_encounter(seed_value: int = 51207):
	var enc = SFTypingEncounter.new()
	enc.setup(typing_data, vocab.select_deck(_stages(), seed_value), seed_value)
	return enc


func _type_word(enc, text: String) -> Array:
	var events: Array = []
	for i in text.length():
		events.append_array(enc.type_letter(text[i]))
	return events


func _wait_for_word(enc, max_seconds: float = 30.0) -> Dictionary:
	var t := 0.0
	while enc.active.is_empty() and t < max_seconds and enc.is_fighting():
		enc.tick(0.05)
		t += 0.05
	return enc.active[0] if not enc.active.is_empty() else {}


func _count_kind(events: Array, kind: String) -> int:
	var n := 0
	for e in events:
		if String((e as Dictionary)["kind"]) == kind:
			n += 1
	return n


func _test_encounter_accounting() -> void:
	section("Boss health and attack accounting")
	var enc = _new_encounter()
	check("boss health is deck size x damage per word", enc.boss_health_max == enc.deck.size() * enc.damage_per_word())
	enc.tick(5.0)
	check("nothing spawns during the intro", enc.active.is_empty())
	enc.begin()
	var word := _wait_for_word(enc)
	check("a word spawns after the fight begins", not word.is_empty())
	check("the opening word is a foundation word", String(vocab.entry(String(word["id"]))["band"]) == "foundation")
	check("only one word is active at the start", enc.active.size() == 1)
	var text := String(word["text"])
	var partial: Array = []
	for i in text.length() - 1:
		partial.append_array(enc.type_letter(text[i]))
	check("individual letters never fire", enc.attacks.is_empty() and _count_kind(partial, "complete") == 0)
	enc.type_letter("q" if text[text.length() - 1] != "q" else "z")
	check("a wrong letter does not hurt Nick", enc.nick_health == enc.nick_health_max)
	var events := _type_word(enc, text)
	check("a completed word fires exactly one attack", _count_kind(events, "complete") == 1 and enc.attacks.size() == 1)
	check("boss health waits for the attack to land", enc.boss_health == enc.boss_health_max)
	var hits := 0
	for i in 20:
		hits += _count_kind(enc.tick(0.05), "attack_hit")
	check("the attack lands once", hits == 1)
	check("the landed attack deals one unit of damage", enc.boss_health == enc.boss_health_max - enc.damage_per_word())
	var idx := int(word["index"])
	_type_word(enc, text)
	check("an already completed entry cannot deal damage again", enc.completed.size() == 1 and enc.attacks.is_empty())

	# Finish the deck: boss death only when every entry is complete.
	var guard := 0
	while not enc.is_over() and guard < 20000:
		guard += 1
		enc.tick(0.05)
		if not enc.active.is_empty() and enc.remaining_count() > 1:
			_type_word(enc, String((enc.active[0] as Dictionary)["text"]))
		elif not enc.active.is_empty():
			check("the boss is alive while one entry remains", enc.boss_health > 0 and enc.phase == enc.PHASE_FIGHT)
			_type_word(enc, String((enc.active[0] as Dictionary)["text"]))
			check("the final attack is in flight before victory", enc.attacks.size() >= 1 and enc.phase == enc.PHASE_FIGHT)
		enc.nick_health = enc.nick_health_max
	check("the encounter is won", enc.phase == enc.PHASE_VICTORY)
	check("every deck entry was completed", enc.completed.size() == enc.deck.size())
	check("boss health is exactly zero at victory", enc.boss_health == 0)
	check("victory leaves no stray words or attacks", enc.active.is_empty() and enc.attacks.is_empty())
	check("letters after victory do nothing", enc.type_letter("a").is_empty())


func _test_miss_and_requeue() -> void:
	section("Missed words and the pending queue")
	var enc = _new_encounter()
	enc.begin()
	var word := _wait_for_word(enc)
	var index := int(word["index"])
	enc.type_letter(String(word["text"])[0])
	var damage := 0
	var miss_events := 0
	var t := 0.0
	while t < 30.0 and not enc.active.is_empty() and int((enc.active[0] as Dictionary)["index"]) == index:
		var ev: Array = enc.tick(0.05)
		miss_events += _count_kind(ev, "miss")
		t += 0.05
	damage = enc.nick_health_max - enc.nick_health
	check("a word reaching the bottom registers one miss", miss_events == 1 and enc.misses == 1)
	check("the miss applies its damage once", damage == int(typing_data["health"]["miss_damage"]), str(damage))
	check("the miss clears the selected target", not enc.typing.has_target())
	var still_falling := false
	for w in enc.active:
		if int((w as Dictionary)["index"]) == index:
			still_falling = true
	check("the missed word left the field", not still_falling)
	var requeued := false
	var ready_at := 0.0
	for p in enc.pending:
		if int((p as Dictionary)["index"]) == index:
			requeued = true
			ready_at = float((p as Dictionary)["not_before"])
	check("the missed entry returns to the pending queue", requeued)
	check("the missed entry waits a fair delay", ready_at >= enc.time + 1.0)
	check("a miss does not damage the boss", enc.boss_health == enc.boss_health_max)
	check("a miss does not complete the entry", not enc.completed.has(index))
	check("a miss does not change the required deck", enc.deck.size() == enc.remaining_count())
	# The entry must come back, and never twice at once.
	var back := false
	var duplicates := false
	t = 0.0
	while t < 40.0 and not back:
		enc.tick(0.05)
		t += 0.05
		var copies := 0
		for w in enc.active:
			if int((w as Dictionary)["index"]) == index:
				copies += 1
		if copies > 1:
			duplicates = true
		if copies == 1:
			back = true
		if not enc.active.is_empty() and int((enc.active[0] as Dictionary)["index"]) != index:
			_type_word(enc, String((enc.active[0] as Dictionary)["text"]))
	check("the missed entry is reintroduced", back)
	check("an entry never has two falling copies", not duplicates)
	var spawn_y := float(typing_data["arena"]["spawn_y"])
	for w in enc.active:
		if int((w as Dictionary)["index"]) == index:
			check("the reintroduced word starts at the top, not the danger line", float((w as Dictionary)["y"]) < spawn_y + 20.0)
	check("pacing slowed after the miss", enc.travel_scale > 1.0)

	# Overlap: active words never share a lane.
	var enc2 = _new_encounter(7)
	enc2.begin()
	var shared := false
	for i in 4000:
		enc2.tick(0.05)
		var lanes: Dictionary = {}
		for w in enc2.active:
			var lane := int((w as Dictionary)["lane"])
			if lanes.has(lane):
				shared = true
			lanes[lane] = true
		enc2.nick_health = enc2.nick_health_max
		if enc2.is_over():
			break
	check("active words never share a lane", not shared)


func _test_retry_and_pause() -> void:
	section("Defeat, retry and pause")
	var enc = _new_encounter()
	enc.begin()
	var deck_before := str(enc.deck)
	var guard := 0
	_wait_for_word(enc)
	_type_word(enc, String((enc.active[0] as Dictionary)["text"]))
	while enc.phase != enc.PHASE_DEFEAT and guard < 40000:
		guard += 1
		enc.tick(0.05)
	check("passive play eventually defeats Nick", enc.phase == enc.PHASE_DEFEAT)
	check("defeat clears falling words and attacks", enc.active.is_empty() and enc.attacks.is_empty())
	check("defeat stops input", enc.type_letter("a").is_empty())
	var h: int = enc.nick_health
	enc.tick(5.0)
	check("defeat stops further damage", enc.nick_health == h)
	enc.reset()
	check("retry restores Nick's health", enc.nick_health == enc.nick_health_max)
	check("retry restores boss health", enc.boss_health == enc.boss_health_max)
	check("retry clears completions and misses", enc.completed.is_empty() and enc.misses == 0)
	check("retry clears typing progress", not enc.typing.has_target())
	check("retry reuses the same deck", str(enc.deck) == deck_before)
	check("retry restarts at the easy stage", enc.current_stage() == 0)
	check("retry clears pacing adjustments", enc.travel_scale == 1.0 and enc.gap_scale == 1.0)
	check("retry returns to the intro hold", enc.phase == enc.PHASE_INTRO)
	enc.begin()
	var w := _wait_for_word(enc)
	var y0 := float(w["y"])
	# Pausing = not ticking. Nothing moves and no time is counted.
	var t0: float = enc.time
	check("without ticks no word moves and no time passes", float((enc.active[0] as Dictionary)["y"]) == y0 and enc.time == t0)


# ---------------------------------------------------------------- bots

## Plays a whole encounter as a scripted typist: `cps` characters per second,
## a fixed reaction delay before each word, and a wrong key every
## `error_every` characters (0 = never). Returns the result.
func _bot(cps: float, error_every: int, reaction: float, seed_value: int = 51207) -> Dictionary:
	var enc = _new_encounter(seed_value)
	enc.begin()
	var dt := 0.02
	var char_timer := 0.0
	var wait := reaction
	var typed_since_error := 0
	var guard := 0
	while not enc.is_over() and guard < 60000:
		guard += 1
		enc.tick(dt)
		if enc.active.is_empty() or not enc.is_fighting():
			wait = reaction
			continue
		if not enc.typing.has_target() and wait > 0.0:
			wait -= dt
			continue
		char_timer += dt
		while char_timer >= 1.0 / cps and enc.is_fighting() and not enc.active.is_empty():
			char_timer -= 1.0 / cps
			var target: Dictionary = enc.target_word()
			if target.is_empty():
				# Pick the lowest word, as a sensible player would.
				target = enc.active[0]
				for a in enc.active:
					if float((a as Dictionary)["y"]) > float(target["y"]):
						target = a
				enc.type_letter(String(target["text"])[0])
				typed_since_error += 1
				continue
			var text := String(target["text"])
			typed_since_error += 1
			if error_every > 0 and typed_since_error >= error_every:
				typed_since_error = 0
				enc.type_letter("q" if text[enc.typing.progress] != "q" else "z")
				continue
			var before: int = enc.completed.size()
			enc.type_letter(text[enc.typing.progress])
			if enc.completed.size() > before:
				wait = reaction
				break
	return {"won": enc.phase == enc.PHASE_VICTORY, "time": enc.time, "misses": enc.misses,
		"resets": enc.resets, "health": enc.nick_health, "travel": enc.travel_scale, "gap": enc.gap_scale}


func _test_simulated_typists() -> void:
	section("Simulated typing profiles (bots, not playtests)")
	var profiles := [
		{"name": "fast (5 cps, no errors)", "cps": 5.0, "err": 0, "react": 0.6},
		{"name": "target (1.8 cps, 1 error per 25 keys)", "cps": 1.8, "err": 25, "react": 1.4},
		{"name": "slow (1.2 cps, 1 error per 15 keys)", "cps": 1.2, "err": 15, "react": 1.8},
	]
	for p in profiles:
		var prof: Dictionary = p
		var r := _bot(float(prof["cps"]), int(prof["err"]), float(prof["react"]))
		print("      %-38s won=%s  time=%.0f s  misses=%d  resets=%d  health=%d  travel=%.2f  gap=%.2f" % [
			String(prof["name"]), str(r["won"]), float(r["time"]), int(r["misses"]), int(r["resets"]),
			int(r["health"]), float(r["travel"]), float(r["gap"])])
		check("the %s profile can win" % String(prof["name"]), bool(r["won"]))
	var fast := _bot(5.0, 0, 0.6)
	var mid := _bot(1.8, 25, 1.4)
	check("the target typist lands near the 3-4 minute goal", float(mid["time"]) >= 150.0 and float(mid["time"]) <= 270.0, "%.0f s" % float(mid["time"]))
	check("a faster typist finishes sooner", float(fast["time"]) < float(mid["time"]))
	check("a fast typist gets shorter gaps", float(fast["gap"]) < 1.0)


# ---------------------------------------------------------------- workshop

## Builds a workshop design and fuels it with exactly what the report asks for.
func _design(original: String, route: String, propulsion: String, protection: String, storage: String,
		samples: bool = false, records: bool = false):
	var w = SFReconstruction.new()
	w.setup(recon_data, original)
	w.set_choice("route", route)
	w.set_choice("propulsion", propulsion)
	w.set_choice("protection", protection)
	w.set_choice("storage", storage)
	w.set_optional("environmental_samples", samples)
	w.set_optional("additional_records", records)
	var probe: Dictionary = w.simulate(ALL_COMPONENTS, 1)
	var need := float(probe["totals"]["propellant_needed_kg"])
	if need < INF:
		w.set_fuel(need)
	return w


func _failed_ids(report: Dictionary) -> Array:
	var out: Array = []
	for c in report["checks"]:
		if not bool((c as Dictionary)["ok"]):
			out.append(String((c as Dictionary)["id"]))
	return out


func _test_simulation_model() -> void:
	section("Return simulation model")
	var w = _design("propulsion_light", "extended_arc", "repair_original", "protection_none", "storage_compact", true)
	var r: Dictionary = w.simulate(ALL_COMPONENTS, 42)
	check("a light-engine extended design is valid", bool(r["valid"]), ", ".join(r["failures"]))
	var units_ok := true
	for st in r["stages"]:
		var stage: Dictionary = st
		var expect := float(stage["power_w"]) * float(stage["duration_s"]) / 3600.0
		if absf(expect - float(stage["energy_used_wh"])) > 0.001:
			units_ok = false
	check("every stage uses energy_Wh = power_W x seconds / 3600", units_ok)
	var stage_ids: Array = []
	for st in r["stages"]:
		stage_ids.append(String((st as Dictionary)["id"]))
	check("the report has per-stage consumption", stage_ids == ["prelaunch_sync", "ascent", "transit", "rift"], str(stage_ids))
	var t: Dictionary = r["totals"]
	check("propellant contributes to wet mass", absf(float(t["wet_mass_kg"]) - float(t["dry_mass_kg"]) - float(t["propellant_kg"])) < 0.001)
	check("a propellant reserve is reported", float(t["propellant_remaining_kg"]) > 0.0)
	check("a buffer reserve is reported", float(t["battery_remaining_wh"]) > 0.0)
	var r2: Dictionary = w.simulate(ALL_COMPONENTS, 42)
	check("identical inputs and seed give identical reports", str(r) == str(r2))
	var r3: Dictionary = w.simulate(ALL_COMPONENTS, 43)
	check("the seed changes only informational debris detail", bool(r3["valid"]) == bool(r["valid"]) and str(r3["checks"]) == str(r["checks"]))

	var no_emitter: Dictionary = w.simulate(["navigation_chip", "power_core"], 42)
	check("a missing component fails the simulation", not bool(no_emitter["valid"]) and _failed_ids(no_emitter).has("components"))
	check("the failure names the missing part", String(no_emitter["failures"][0]).findn("shield emitter") >= 0)

	w.set_fuel(0.0)
	var dry_r: Dictionary = w.simulate(ALL_COMPONENTS, 42)
	check("no propellant fails delta-v", _failed_ids(dry_r).has("delta_v"))
	check("the delta-v failure suggests a propellant amount", String(dry_r["suggestions"][0]).findn("Load at least") >= 0)
	w.set_fuel(900.0)
	var heavy_r: Dictionary = w.simulate(ALL_COMPONENTS, 42)
	check("an overloaded tank fails launch mass", _failed_ids(heavy_r).has("mass"))

	var hungry = _design("propulsion_heavy", "extended_arc", "repair_original", "shield_amplifier", "storage_array", true)
	var hr: Dictionary = hungry.simulate(ALL_COMPONENTS, 42)
	check("a power-hungry long route fails energy", _failed_ids(hr).has("energy"), ", ".join(hr["failures"]))
	check("the same design also fails peak power", _failed_ids(hr).has("peak_power"))
	var unprotected = _design("propulsion_heavy", "fast_corridor", "repair_original", "protection_none", "storage_compact")
	check("the fast route without an upgrade fails protection", _failed_ids(unprotected.simulate(ALL_COMPONENTS, 1)).has("protection"))
	var no_store = _design("propulsion_heavy", "extended_arc", "repair_original", "protection_none", "storage_none")
	check("the mandatory payload does not fit the chip store alone", _failed_ids(no_store.simulate(ALL_COMPONENTS, 1)).has("data"))
	var slow_sync = _design("propulsion_heavy", "fast_corridor", "repair_original", "armor_plating", "storage_array", false, true)
	check("extra records overrun the fast route's relay window", _failed_ids(slow_sync.simulate(ALL_COMPONENTS, 1)).has("sync"))


func _test_workshop_designs() -> void:
	section("Viable return designs and trade-offs")
	var a = _design("propulsion_light", "extended_arc", "repair_original", "protection_none", "storage_compact", true)
	var b = _design("propulsion_light", "fast_corridor", "rebuilt_cluster", "shield_amplifier", "storage_compact")
	var c = _design("propulsion_heavy", "fast_corridor", "repair_original", "armor_plating", "storage_compact")
	var d = _design("propulsion_heavy", "extended_arc", "repair_original", "protection_none", "storage_array", true, true)
	var named := {"A extended / repaired light / samples": a, "B fast / rebuilt cluster / amplifier": b,
		"C fast / repaired heavy / plating": c, "D extended / repaired heavy / array+samples+records": d}
	for key in named.keys():
		var rep: Dictionary = named[key].simulate(ALL_COMPONENTS, 7)
		var units: int = named[key].fabrication_units()
		print("      %-50s valid=%s fab=%d cost=%s wet=%.0f kg fuel=%.0f kg" % [String(key), str(rep["valid"]), units,
			str(named[key].material_cost()), float(rep["totals"]["wet_mass_kg"]), float(named[key].selection["fuel_kg"])])
		check("design %s passes" % String(key), bool(rep["valid"]), ", ".join(rep["failures"]))
		check("design %s fits fabrication capacity" % String(key), units <= named[key].fabrication_capacity())
	var light_fast = _design("propulsion_light", "fast_corridor", "repair_original", "shield_amplifier", "storage_compact")
	check("the repaired light engine cannot fly the fast route", not bool(light_fast.simulate(ALL_COMPONENTS, 1)["valid"]))
	var b_samples = _design("propulsion_light", "fast_corridor", "rebuilt_cluster", "shield_amplifier", "storage_compact", true)
	check("the amplifier build cannot also cool samples (peak power)", _failed_ids(b_samples.simulate(ALL_COMPONENTS, 1)).has("peak_power"))
	check("the fast plated build needs more propellant than the extended build",
		float(c.selection["fuel_kg"]) > float(a.selection["fuel_kg"]))
	# Every valid Phase 1 build carries forward: both day-one engines have a
	# passing return design whose salvage fits the guaranteed floor.
	var floor_map: Dictionary = recon_data["replenish_floor"]
	for original in ["propulsion_light", "propulsion_heavy"]:
		var w = _design(String(original), "extended_arc", "repair_original", "protection_none", "storage_compact")
		var ok: bool = bool(w.simulate(ALL_COMPONENTS, 1)["valid"])
		var cost: Dictionary = w.material_cost()
		var affordable := true
		for m in cost.keys():
			if int(cost[m]) > int(floor_map.get(m, 0)):
				affordable = false
		check("a %s Phase 1 build has a passing, always-affordable return" % String(original), ok and affordable)


func _fresh_campaign():
	var camp = SFCampaign.new()
	camp.confirmed_design = {"slots": {"propulsion": "propulsion_light"}, "fuel_kg": 200.0}
	return camp


func _test_workshop_rules() -> void:
	section("Workshop transactions")
	var camp = _fresh_campaign()
	for id in ALL_COMPONENTS:
		camp.award_component(String(id))
	var w = SFReconstruction.new()
	w.setup(recon_data, camp.original_propulsion_id())
	w.set_choice("route", "extended_arc")
	w.set_fuel(460.0)
	var before := str(camp.inventory)
	var report: Dictionary = w.simulate(camp.recovered_component_ids(), 9)
	check("the default extended design passes once fuelled", bool(report["valid"]), ", ".join(report["failures"]))
	check("simulating spends nothing", str(camp.inventory) == before)
	var refused: Dictionary = w.commit(camp, report)
	check("fabrication is refused without salvage", not bool(refused["ok"]) and String(refused["message"]).findn("salvage") >= 0)
	check("a refused fabrication spends nothing", str(camp.inventory) == before)
	var added: Dictionary = w.replenish(camp)
	check("scavenging tops materials up to the floor", camp.material_count("scrap_metal") == 8 and camp.material_count("circuitry") == 4 and camp.material_count("polymer") == 3, str(added))
	check("scavenging twice adds nothing more", w.replenish(camp).is_empty())
	w.adjust_fuel(1)
	check("changing the design makes the old report stale", String(report["signature"]) != w.signature())
	var stale: Dictionary = w.commit(camp, report)
	check("a stale report cannot fabricate", not bool(stale["ok"]))
	w.adjust_fuel(-1)
	report = w.simulate(camp.recovered_component_ids(), 9)
	var cost: Dictionary = w.material_cost()
	var held := {"scrap_metal": camp.material_count("scrap_metal"), "circuitry": camp.material_count("circuitry"), "polymer": camp.material_count("polymer")}
	var done: Dictionary = w.commit(camp, report)
	check("a current passing report fabricates", bool(done["ok"]), String(done["message"]))
	var exact := true
	for m in held.keys():
		if camp.material_count(String(m)) != int(held[m]) - int(cost.get(m, 0)):
			exact = false
	check("fabrication spends exactly the design cost", exact)
	check("fabrication reaches READY_FOR_FINAL_ASSEMBLY", camp.is_ready_for_final_assembly())
	var after := str(camp.inventory)
	var again: Dictionary = w.commit(camp, report)
	check("a second fabrication is refused", not bool(again["ok"]))
	check("a second fabrication spends nothing", str(camp.inventory) == after)

	var camp2 = _fresh_campaign()
	camp2.award_component("navigation_chip")
	camp2.award_component("power_core")
	var w2 = SFReconstruction.new()
	w2.setup(recon_data, "propulsion_light")
	w2.set_fuel(460.0)
	w2.replenish(camp2)
	var r2: Dictionary = w2.simulate(camp2.recovered_component_ids(), 9)
	check("missing the shield emitter rejects final assembly", not bool(w2.commit(camp2, r2)["ok"]))
	var big = _design("propulsion_light", "fast_corridor", "rebuilt_cluster", "shield_amplifier", "storage_array", true, true)
	check("an over-ambitious design exceeds fabrication capacity", big.fabrication_units() > big.fabrication_capacity())


func _test_campaign_rewards_and_save() -> void:
	section("Rewards, journal and save version 3")
	var camp = _fresh_campaign()
	camp.award_component("navigation_chip")
	camp.award_component("power_core")
	check("the boss reward applies once", camp.complete_boss("sky_remnant_defeated", "shield_emitter"))
	check("a repeated boss result is refused", not camp.complete_boss("sky_remnant_defeated", "shield_emitter"))
	check("the shield emitter is recorded exactly once", camp.recovered_component_ids().count("shield_emitter") == 1)
	check("the three required components are all recovered", camp.recovered_component_ids().size() == 3)
	check("the Dawn outcome applies once", camp.complete_dawn_tower() and not camp.complete_dawn_tower())
	check("the workshop is unlocked", camp.has_flag("workshop_unlocked"))
	check("a journal entry records once", camp.record_vocabulary("v_soil") and not camp.record_vocabulary("v_soil"))
	camp.record_vocabulary("v_habitat")
	camp.advance_to(camp.STAGE_RECONSTRUCTION)
	camp.store_reconstruction_selection({"route": "fast_corridor"})
	var path := "user://star_fall_phase3_test.json"
	check("a version 3 save writes", bool(SFSave.write_save(camp, path)["ok"]))
	var loaded = SFCampaign.new()
	var res: Dictionary = SFSave.load_into(loaded, path)
	check("the version 3 save loads", bool(res["ok"]))
	check("the save keeps the stage", loaded.stage == loaded.STAGE_RECONSTRUCTION)
	check("the save keeps the chapter at the base", loaded.chapter_id == loaded.CHAPTER_CRASH)
	check("the save keeps the journal", loaded.vocabulary_journal == ["v_soil", "v_habitat"])
	check("the save keeps the shield emitter once", loaded.recovered_component_ids().count("shield_emitter") == 1)
	check("the save keeps the workshop selection", String(loaded.reconstruction["selection"]["route"]) == "fast_corridor")
	SFSave.load_into(loaded, path)
	check("loading twice never duplicates", loaded.vocabulary_journal.size() == 2 and loaded.recovered_component_ids().size() == 3)
	var v2: Dictionary = camp.to_save_dict()
	v2["version"] = 2
	v2.erase("vocabulary_journal")
	v2.erase("reconstruction")
	var old = SFCampaign.new()
	old.apply_save_dict(v2)
	check("a version 2 save loads with an empty journal", old.vocabulary_journal.is_empty() and old.reconstruction.is_empty())
	var forged: Dictionary = camp.to_save_dict()
	forged["flags"]["ready_for_final_assembly"] = true
	var f = SFCampaign.new()
	var warnings: Array = f.apply_save_dict(forged)
	check("a ready flag without a committed design is cleared", not f.is_ready_for_final_assembly() and not warnings.is_empty())
	SFSave.delete_save(path)
	check("Phase 2 bosses still award their own components",
		String(camp.content.encounters.boss("scrap_king").get("reward_component", "")) == "navigation_chip"
		and String(camp.content.encounters.boss("toxic_tide").get("reward_component", "")) == "power_core")
	check("Dawn Tower is now a playable chapter", String(camp.content.chapter("dawn_tower").get("stage", "")) == "dawn_tower")
	check("Return Home stays deferred", String(camp.content.chapter("return_home").get("stage", "")) == "deferred")
