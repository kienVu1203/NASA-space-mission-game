extends RefCounted
## The Phase 3 typing encounter: the Sky Remnant fight. Pure logic: no nodes, no
## input events, no drawing. The screen feeds it letters and frame deltas and
## draws what it reports.
##
## Collections (an entry is one vocabulary id from the deck)
##   deck       the finite ordered selection for this attempt (never the library)
##   pending    deck entries not yet completed and not currently falling
##   active     falling word instances (at most one per entry)
##   completed  entries typed successfully; each pays out exactly once
##   attacks    projectiles in flight; boss damage lands when one arrives
##
## Accounting
##   boss_health_max = deck.size() * damage_per_word. Only an arriving attack
##   lowers it, and an attack is only created by the first completion of an
##   entry, so the boss reaches zero exactly when the whole deck is complete and
##   the last attack lands. Misses never change boss health.
##
## Time
##   Everything advances only through tick(dt), and the screen stops calling it
##   while paused, unfocused, or under a dialogue. Paused time therefore never
##   moves words, spawns, deals damage, or counts as typing delay.

const SFTyping := preload("res://core/star_fall/sf_typing.gd")

const PHASE_INTRO := "intro"
const PHASE_FIGHT := "fight"
const PHASE_VICTORY := "victory"
const PHASE_DEFEAT := "defeat"

var config: Dictionary = {}
var boss: Dictionary = {}
var deck: Array = []
var typing = SFTyping.new()

var phase: String = PHASE_INTRO
var time: float = 0.0               # fight time only
var pending: Array = []             # [{"index", "not_before"}], kept in deck order
var active: Array = []              # [{"uid", "index", "id", "text", "x", "y", "speed", "lane", "stage"}]
var completed: Dictionary = {}      # deck index -> true
var attacks: Array = []             # [{"index", "t", "flight"}]
var nick_health: int = 100
var nick_health_max: int = 100
var boss_health: int = 0
var boss_health_max: int = 0
var victory_timer: float = 0.0

# Counters for the result screen and the tests.
var misses: int = 0
var resets: int = 0
var keystrokes: int = 0
var miss_count_by_index: Dictionary = {}

# Pacing state.
var travel_scale: float = 1.0
var gap_scale: float = 1.0
var recent_misses: int = 0
var clean_streak: int = 0
var slow_mode: bool = false         # observed pace needs single-word pressure
var observations: Array = []        # [{"chars", "seconds"}]
var _first_key_time: float = -1.0
var _spawn_timer: float = 0.0
var _next_uid: int = 1
var _rng := RandomNumberGenerator.new()
var _seed: int = 0


## `typing_data` is data/star_fall/typing.json; `deck_entries` comes from
## SFVocabulary.select_deck().
func setup(typing_data: Dictionary, deck_entries: Array, seed_value: int) -> void:
	config = typing_data
	boss = typing_data.get("boss", {}) as Dictionary
	deck = deck_entries.duplicate(true)
	_seed = seed_value
	reset()


## A retry: every encounter-local value returns to its starting state. The deck
## is kept, so a retry practises the same words from the easy stage.
func reset() -> void:
	typing.reset()
	phase = PHASE_INTRO
	time = 0.0
	pending = []
	for e in deck:
		pending.append({"index": int((e as Dictionary)["index"]), "not_before": 0.0})
	active = []
	completed = {}
	attacks = []
	nick_health_max = int(_health().get("nick_health", 100))
	nick_health = nick_health_max
	boss_health_max = deck.size() * damage_per_word()
	boss_health = boss_health_max
	victory_timer = 0.0
	misses = 0
	resets = 0
	keystrokes = 0
	miss_count_by_index = {}
	travel_scale = 1.0
	gap_scale = 1.0
	recent_misses = 0
	clean_streak = 0
	slow_mode = false
	observations = []
	_first_key_time = -1.0
	_spawn_timer = float(_timing().get("first_spawn_delay", 1.0))
	_next_uid = 1
	_rng.seed = _seed


## Leaves the intro (tutorial / briefing) phase. Nothing spawns before this.
func begin() -> void:
	if phase == PHASE_INTRO:
		phase = PHASE_FIGHT


func is_fighting() -> bool:
	return phase == PHASE_FIGHT


func is_over() -> bool:
	return phase == PHASE_VICTORY or phase == PHASE_DEFEAT


func damage_per_word() -> int:
	return int(_health().get("damage_per_word", 10))


func completed_count() -> int:
	return completed.size()


func remaining_count() -> int:
	return deck.size() - completed.size()


func health_fraction() -> float:
	return float(boss_health) / float(maxi(1, boss_health_max))


func nick_fraction() -> float:
	return float(nick_health) / float(maxi(1, nick_health_max))


func deck_entry(index: int) -> Dictionary:
	if index < 0 or index >= deck.size():
		return {}
	return deck[index]


## The stage the fight is in: the stage of the earliest deck entry not yet
## completed. Stages therefore advance only as words are actually finished.
func current_stage() -> int:
	for e in deck:
		var entry: Dictionary = e
		if not completed.has(int(entry["index"])):
			return int(entry["stage"])
	return maxi(0, _stages().size() - 1)


func target_word() -> Dictionary:
	for w in active:
		if int((w as Dictionary)["uid"]) == typing.target_uid:
			return w
	return {}


# ---------------------------------------------------------------- input

## One typed letter (already lowercased by SFTyping.letter_from_unicode).
## Returns a list of events for the screen.
func type_letter(letter: String) -> Array:
	var events: Array = []
	if phase != PHASE_FIGHT or letter == "":
		return events
	keystrokes += 1
	var had_target: bool = typing.has_target()
	var result: Dictionary = typing.input(letter, active)
	match String(result["kind"]):
		"select":
			_first_key_time = time
			events.append({"kind": "select", "uid": int(result["uid"])})
		"advance":
			# Pace is measured from selection, resets included: conservative.
			events.append({"kind": "advance", "uid": int(result["uid"]), "progress": int(result["progress"])})
		"reset":
			resets += 1
			events.append({"kind": "reset", "uid": int(result["uid"])})
		"no_match":
			events.append({"kind": "no_match", "letter": letter})
		"complete":
			if not had_target:
				_first_key_time = time
			events.append_array(_complete_word(int(result["uid"])))
	return events


## Backspace: drop the current target without penalty.
func cancel_target() -> void:
	typing.release()


func _complete_word(uid: int) -> Array:
	var events: Array = []
	var word: Dictionary = {}
	for w in active:
		if int((w as Dictionary)["uid"]) == uid:
			word = w
			break
	if word.is_empty():
		return events
	active.erase(word)
	var index := int(word["index"])
	if completed.has(index):
		# Impossible by construction (one active instance per entry), but a
		# second completion must never pay out twice.
		return events
	completed[index] = true
	attacks.append({"index": index, "t": 0.0, "flight": float(_attack().get("flight_seconds", 0.45))})
	_record_observation(String(word["text"]).length())
	clean_streak += 1
	if clean_streak >= int(_pacing().get("pressure_clear_completions", 3)):
		recent_misses = 0
	if active.is_empty():
		_spawn_timer = minf(_spawn_timer, float(_pacing().get("idle_gap_seconds", 0.6)))
	events.append({"kind": "complete", "uid": uid, "index": index, "id": String(word["id"]),
		"text": String(word["text"]), "x": float(word["x"]), "y": float(word["y"])})
	return events


# ---------------------------------------------------------------- simulation

## Advances the fight. Returns spawn / miss / attack_hit / victory / defeat events.
func tick(dt: float) -> Array:
	var events: Array = []
	if phase == PHASE_VICTORY:
		victory_timer += dt
		return events
	if phase != PHASE_FIGHT:
		return events
	time += dt

	# Attacks in flight resolve first, so a word finished just before the end
	# always lands its damage.
	var landed: Array = []
	for a in attacks:
		var attack: Dictionary = a
		attack["t"] = float(attack["t"]) + dt
		if float(attack["t"]) >= float(attack["flight"]):
			landed.append(attack)
	for a in landed:
		attacks.erase(a)
		boss_health = maxi(0, boss_health - damage_per_word())
		events.append({"kind": "attack_hit", "index": int((a as Dictionary)["index"])})

	if completed.size() >= deck.size():
		# Every required entry is complete: no more spawns, no more word damage.
		if attacks.is_empty():
			# Defensive: accounting guarantees zero here; never strand the fight.
			boss_health = 0
			phase = PHASE_VICTORY
			victory_timer = 0.0
			events.append({"kind": "victory"})
		return events

	# Words descend; any that reach the danger line are misses.
	var danger_y := float(_arena().get("danger_y", 280.0))
	var fallen: Array = []
	for w in active:
		var word: Dictionary = w
		word["y"] = float(word["y"]) + float(word["speed"]) * dt
		if float(word["y"]) >= danger_y:
			fallen.append(word)
	for w in fallen:
		events.append_array(_miss_word(w))
		if phase == PHASE_DEFEAT:
			return events

	_spawn_timer -= dt
	if _spawn_timer <= 0.0:
		var spawned := _try_spawn()
		if not spawned.is_empty():
			events.append(spawned)
	return events


func _miss_word(word: Dictionary) -> Array:
	var events: Array = []
	active.erase(word)
	typing.on_word_removed(int(word["uid"]))
	var index := int(word["index"])
	misses += 1
	miss_count_by_index[index] = int(miss_count_by_index.get(index, 0)) + 1
	# Requeue after a fair delay, in deck order, so it is never respawned at
	# the bottom and never dropped from the required deck.
	_insert_pending(index, time + float(_timing().get("requeue_delay_seconds", 4.0)))
	var dmg := int(_health().get("miss_damage", 12))
	nick_health = maxi(0, nick_health - dmg)
	recent_misses += 1
	clean_streak = 0
	# A miss never speeds the fight up: stretch travel time, restore gaps.
	travel_scale = minf(float(_pacing().get("travel_scale_max", 1.4)), travel_scale + float(_pacing().get("miss_travel_step", 0.1)))
	gap_scale = maxf(gap_scale, 1.0)
	events.append({"kind": "miss", "index": index, "id": String(word["id"]), "text": String(word["text"]),
		"x": float(word["x"]), "damage": dmg})
	if nick_health <= 0:
		phase = PHASE_DEFEAT
		active.clear()
		attacks.clear()
		typing.reset()
		events.append({"kind": "defeat"})
	return events


func _insert_pending(index: int, not_before: float) -> void:
	var at := pending.size()
	for i in pending.size():
		if int((pending[i] as Dictionary)["index"]) > index:
			at = i
			break
	pending.insert(at, {"index": index, "not_before": not_before})


func max_active_now() -> int:
	var stage: Dictionary = _stage(current_stage())
	var cap := int(stage.get("max_active", 1))
	if slow_mode:
		cap = 1
	if recent_misses >= int(_pacing().get("pressure_miss_threshold", 2)):
		cap -= 1
	return maxi(1, cap)


func fall_seconds_now() -> float:
	return float(_stage(current_stage()).get("fall_seconds", 10.0)) * travel_scale


func spawn_gap_now() -> float:
	return float(_stage(current_stage()).get("spawn_gap", 2.0)) * gap_scale


func _try_spawn() -> Dictionary:
	if active.size() >= max_active_now():
		_spawn_timer = 0.1
		return {}
	var candidate := _pick_pending()
	if candidate < 0:
		_spawn_timer = 0.1
		return {}
	var lane := _pick_lane()
	if lane < 0:
		_spawn_timer = float(_timing().get("lane_retry_seconds", 0.25))
		return {}
	var pending_entry: Dictionary = pending[candidate]
	pending.remove_at(candidate)
	var index := int(pending_entry["index"])
	var entry: Dictionary = deck[index]
	var spawn_y := float(_arena().get("spawn_y", 110.0))
	var danger_y := float(_arena().get("danger_y", 280.0))
	var lanes: Array = _arena().get("lanes_x", [320]) as Array
	var word := {
		"uid": _next_uid,
		"index": index,
		"id": String(entry["id"]),
		"text": String(entry["text"]),
		"stage": int(entry["stage"]),
		"lane": lane,
		"x": float(lanes[lane]),
		"y": spawn_y,
		"speed": (danger_y - spawn_y) / maxf(1.0, fall_seconds_now()),
	}
	_next_uid += 1
	active.append(word)
	_spawn_timer = spawn_gap_now()
	return {"kind": "spawn", "uid": int(word["uid"]), "index": index, "text": String(word["text"])}


## The next pending entry that is ready, in deck order, preferring a first
## letter no active word uses. Looks a few entries ahead only, so variety is
## never bought by skipping the stage order.
func _pick_pending() -> int:
	var used: Dictionary = {}
	for w in active:
		used[String((w as Dictionary)["text"])[0]] = true
	var lookahead := int(_timing().get("distinct_letter_lookahead", 3))
	var first_ready := -1
	var seen := 0
	for i in pending.size():
		var p: Dictionary = pending[i]
		if float(p["not_before"]) > time:
			continue
		var index := int(p["index"])
		if int((deck[index] as Dictionary)["stage"]) > current_stage() + 1:
			break
		if first_ready < 0:
			first_ready = i
		if not used.has(String((deck[index] as Dictionary)["text"])[0]):
			return i
		seen += 1
		if seen >= lookahead:
			break
	return first_ready


func _pick_lane() -> int:
	# One word per lane: labels in separate columns can never overlap, and with
	# fewer active words than lanes there is always a free lane.
	var lanes: Array = _arena().get("lanes_x", [320]) as Array
	var busy: Dictionary = {}
	for w in active:
		busy[int((w as Dictionary)["lane"])] = true
	var free: Array = []
	for lane in lanes.size():
		if not busy.has(lane):
			free.append(lane)
	if free.is_empty():
		return -1
	return int(free[_rng.randi_range(0, free.size() - 1)])


# ---------------------------------------------------------------- pacing

func _record_observation(chars: int) -> void:
	var seconds := maxf(0.2, time - _first_key_time) if _first_key_time >= 0.0 else 0.0
	_first_key_time = -1.0
	if seconds <= 0.0:
		return
	observations.append({"chars": chars, "seconds": seconds})
	var window := int(_pacing().get("window", 6))
	while observations.size() > window:
		observations.remove_at(0)
	_adapt()


## Observed typing speed over the recent window, or -1 until enough words have
## been typed. One short word is never enough to judge a player.
func observed_chars_per_second() -> float:
	if observations.size() < int(_pacing().get("min_observations", 4)):
		return -1.0
	var chars := 0.0
	var seconds := 0.0
	for o in observations:
		chars += float((o as Dictionary)["chars"])
		seconds += float((o as Dictionary)["seconds"])
	return chars / maxf(0.001, seconds)


func _adapt() -> void:
	var cps := observed_chars_per_second()
	if cps <= 0.0:
		return
	var p := _pacing()
	var step := float(p.get("adjust_step", 0.06))
	var stage_index := current_stage()
	var avg_len := _average_length(stage_index)
	# Words are typed one after another, so the time to clear a full field is
	# the per-word time multiplied by how many words the stage allows at once.
	var per_word := avg_len / cps + float(p.get("reaction_seconds", 1.4))
	var needed := per_word * float(int(_stage(stage_index).get("max_active", 1)))
	var fall := float(_stage(stage_index).get("fall_seconds", 10.0)) * travel_scale
	if needed > fall * float(p.get("slow_ratio", 0.7)):
		# Slower typist: one word at a time, more travel time, more room.
		slow_mode = true
		travel_scale = minf(float(p.get("travel_scale_max", 1.4)), travel_scale + step)
		gap_scale = minf(float(p.get("gap_scale_max", 1.3)), gap_scale + step)
	elif needed < fall * float(p.get("slow_clear_ratio", 0.45)):
		slow_mode = false
	if needed < fall * float(p.get("fast_ratio", 0.35)) and recent_misses == 0:
		# Faster typist: shorter empty gaps. Travel time is left alone, so the
		# band progression and readability stay intact.
		gap_scale = maxf(float(p.get("gap_scale_min", 0.5)), gap_scale - step)


func _average_length(stage_index: int) -> float:
	var total := 0.0
	var n := 0
	for e in deck:
		if int((e as Dictionary)["stage"]) == stage_index:
			total += float(String((e as Dictionary)["text"]).length())
			n += 1
	return total / float(maxi(1, n))


## Pre-fight duration estimate in seconds, from documented assumptions:
## per word, typing time (chars / cps) plus a reaction delay; plus mistake
## overhead (a reset retypes about half a word) at `mistake_rate`; plus retry
## overhead for missed words (requeue delay plus a fall) at `miss_rate`; plus
## the opening delay. It is a planning number, not a promise.
static func estimate_seconds(deck_entries: Array, typing_data: Dictionary, chars_per_second: float = -1.0) -> float:
	var est: Dictionary = typing_data.get("estimate", {}) as Dictionary
	var pacing: Dictionary = typing_data.get("pacing", {}) as Dictionary
	var timing: Dictionary = typing_data.get("timing", {}) as Dictionary
	var stages: Array = (typing_data.get("deck", {}) as Dictionary).get("stages", []) as Array
	var cps := chars_per_second if chars_per_second > 0.0 else float(est.get("assumed_chars_per_second", 1.8))
	var reaction := float(pacing.get("reaction_seconds", 1.4))
	var mistake := float(est.get("mistake_rate", 0.08))
	var miss := float(est.get("miss_rate", 0.05))
	var total := float(timing.get("first_spawn_delay", 1.0))
	for e in deck_entries:
		var entry: Dictionary = e
		var length := float(String(entry["text"]).length())
		var typing_time := length / cps
		total += typing_time + reaction + mistake * 0.5 * typing_time
		var stage: Dictionary = stages[int(entry["stage"])] if int(entry["stage"]) < stages.size() else {}
		total += miss * (float(timing.get("requeue_delay_seconds", 4.0)) + float(stage.get("fall_seconds", 10.0)))
	return total


# ---------------------------------------------------------------- config

func _stages() -> Array:
	return (config.get("deck", {}) as Dictionary).get("stages", []) as Array


func _stage(i: int) -> Dictionary:
	var stages := _stages()
	if stages.is_empty():
		return {}
	return stages[clampi(i, 0, stages.size() - 1)] as Dictionary


func _arena() -> Dictionary:
	return config.get("arena", {}) as Dictionary


func _health() -> Dictionary:
	return config.get("health", {}) as Dictionary


func _attack() -> Dictionary:
	return config.get("attack", {}) as Dictionary


func _timing() -> Dictionary:
	return config.get("timing", {}) as Dictionary


func _pacing() -> Dictionary:
	return config.get("pacing", {}) as Dictionary
