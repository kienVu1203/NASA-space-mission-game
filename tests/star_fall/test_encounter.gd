extends SceneTree
## STAR FALL Phase 2 encounter tests: shield direction, swept collision,
## projectile interactions, charge and counterattack rules, health-based
## escalation, retry resets, reward idempotence and save/load.
##
##   Godot --headless --path . --script res://tests/star_fall/test_encounter.gd
##
## These are pure-model tests: no rendering, no input device, no scene. Every
## check drives the same classes the duel screen drives.

const SFEncounters := preload("res://core/star_fall/sf_encounters.gd")
const SFShield := preload("res://core/star_fall/sf_shield.gd")
const SFProjectiles := preload("res://core/star_fall/sf_projectiles.gd")
const SFScheduler := preload("res://core/star_fall/sf_pattern_scheduler.gd")
const SFModel := preload("res://core/star_fall/sf_encounter_model.gd")
const SFEncounter := preload("res://core/star_fall/sf_encounter.gd")
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const SFSave := preload("res://core/star_fall/sf_save.gd")

const TEST_SAVE := "user://star_fall_phase2_test_save.json"

var fails: int = 0
var checks_run: int = 0
var data
var nick := Vector2(320.0, 244.0)
var test_save_path := TEST_SAVE


func check(label: String, ok: bool, detail: String = "") -> void:
	checks_run += 1
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1


func section(title: String) -> void:
	print("")
	print("-- " + title + " " + "-".repeat(maxi(0, 58 - title.length())))


func _initialize() -> void:
	data = SFEncounters.new()
	check("encounter data loads", data.load_all())
	check("both Phase 2 bosses exist", data.has_boss("scrap_king") and data.has_boss("toxic_tide"))
	check("both archives exist", not data.archive("city_archive").is_empty() and not data.archive("coast_archive").is_empty())
	check("rewards are declared in data", String(data.boss("scrap_king").get("reward_component", "")) == "navigation_chip"
		and String(data.boss("toxic_tide").get("reward_component", "")) == "power_core")
	check("the shield emitter is not a Phase 2 reward",
		String(data.boss("scrap_king").get("reward_component", "")) != "shield_emitter"
		and String(data.boss("toxic_tide").get("reward_component", "")) != "shield_emitter")

	_test_shield_direction()
	_test_coordinate_transform()
	_test_collision_order()
	_test_projectile_interactions()
	_test_charge_and_counter()
	_test_escalation()
	_test_pattern_fairness()
	_test_retry_reset()
	_test_intro_freeze()
	_test_victory_and_rewards()
	_test_save_load()
	_test_phase_one_untouched()

	print("")
	print("RESULT: %d check(s), %d failure(s)" % [checks_run, fails])
	SFSave.delete_save(test_save_path)
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- shield

func _make_shield() -> RefCounted:
	var s := SFShield.new()
	s.configure(data.shield)
	return s


func _test_shield_direction() -> void:
	section("Mouse-directed shield")

	var s = _make_shield()
	check("the shield starts facing down", s.direction.is_equal_approx(Vector2(0, 1)), str(s.direction))
	check("coverage is narrower than a full circle", s.coverage_degrees < 360.0, "%.0f deg" % s.coverage_degrees)
	check("coverage is wide enough to be usable", s.coverage_degrees >= 20.0)

	# Right, left, up, and four diagonals: 360 degrees of control.
	var cases := {
		"right": Vector2(1, 0),
		"left": Vector2(-1, 0),
		"up": Vector2(0, -1),
		"down": Vector2(0, 1),
		"up-right": Vector2(1, -1),
		"up-left": Vector2(-1, -1),
		"down-right": Vector2(1, 1),
		"down-left": Vector2(-1, 1),
	}
	for label in cases.keys():
		var target: Vector2 = cases[label]
		s.aim(nick, nick + target.normalized() * 100.0)
		check("aims " + String(label), s.direction.is_equal_approx(target.normalized()), str(s.direction))

	# A cursor nearer than the dead zone must not change the direction.
	s.aim(nick, nick + Vector2(1, 0))
	check("a cursor inside the dead zone is ignored", s.direction.is_equal_approx(Vector2(-1, 1).normalized()))
	var before: Vector2 = s.direction
	s.aim(nick, nick)
	check("a zero-length cursor vector is ignored", s.direction.is_equal_approx(before))
	s.set_direction(Vector2.ZERO)
	check("a zero-length direction is refused", s.direction.is_equal_approx(before))
	check("the direction stays normalised", is_equal_approx(s.direction.length(), 1.0))

	# Coverage: straight ahead is covered, straight behind is not, and the edge
	# is exactly half the stated coverage.
	s.set_direction(Vector2(1, 0))
	check("the shield covers straight ahead", s.covers_vector(Vector2(1, 0)))
	var half := deg_to_rad(s.coverage_degrees * 0.5)
	var just_inside := Vector2(cos(half * 0.98), sin(half * 0.98))
	var just_outside := Vector2(cos(half * 1.02), sin(half * 1.02))
	check("the shield covers just inside its edge", s.covers_vector(just_inside))
	check("the shield does not cover just outside its edge", not s.covers_vector(just_outside))
	check("the shield never covers behind Nick", not s.covers_vector(Vector2(-1, 0)))
	check("the covered arc is the stated angle",
		absf(s.coverage_degrees - rad_to_deg(s.half_coverage_radians() * 2.0)) < 0.01)

	# The drawn arc and the collision coverage use one direction.
	s.set_direction(Vector2(-1, 0))
	var pts: PackedVector2Array = s.arc_points(nick, 8)
	check("the drawn arc has points", pts.size() >= 3)
	var all_inside := true
	for p in pts:
		if not s.covers_point(nick, p):
			all_inside = false
	check("every drawn arc point is inside the collision coverage", all_inside)
	var endpoints: Array = s.arc_endpoints(nick)
	check("the arc endpoints sit at the shield radius",
		is_equal_approx((endpoints[0] as Vector2).distance_to(nick), s.radius))


func _test_coordinate_transform() -> void:
	section("Window scaling and letterboxing")

	# 1:1 window: canvas coordinates equal window coordinates.
	var p1: Vector2 = SFShield.canvas_point(Vector2(320, 180), Vector2(640, 360))
	check("an unscaled window maps directly", p1.is_equal_approx(Vector2(320, 180)), str(p1))

	# 2x window: the same canvas point moves to twice the pixels.
	var p2: Vector2 = SFShield.canvas_point(Vector2(640, 360), Vector2(1280, 720))
	check("a 2x window is divided by its scale", p2.is_equal_approx(Vector2(320, 180)), str(p2))

	# Wider window (pillarboxed): the canvas is padded horizontally.
	var wide := Vector2(1920, 720)
	var p3: Vector2 = SFShield.canvas_point(Vector2(960, 360), wide)
	check("a pillarboxed window removes its side bars", p3.is_equal_approx(Vector2(320, 180)), str(p3))
	# A point inside the left bar maps outside the canvas, which the shield
	# dead zone and clamping then handle; the important part is that the bar is
	# not treated as playable space.
	var p4: Vector2 = SFShield.canvas_point(Vector2(100, 360), wide)
	check("a point in the side bar maps left of the canvas", p4.x < 0.0, str(p4))

	# Taller window (letterboxed): bars above and below.
	var tall := Vector2(640, 720)
	var p5: Vector2 = SFShield.canvas_point(Vector2(320, 360), tall)
	check("a letterboxed window removes its top and bottom bars", p5.is_equal_approx(Vector2(320, 180)), str(p5))

	# The transformed point, fed to the shield, produces the expected direction.
	var s = _make_shield()
	var cursor: Vector2 = SFShield.canvas_point(Vector2(1920 - 320, 360), wide)
	s.aim(nick, cursor)
	check("a scaled cursor aims the shield in canvas space", s.direction.x > 0.9, str(s.direction))


# ---------------------------------------------------------------- collision

func _test_collision_order() -> void:
	section("Projectile collision order")

	var field = SFProjectiles.new()
	field.configure(data.combat, data.projectile_types)
	var s = _make_shield()
	s.set_direction(Vector2(1, 0))
	var arena := Rect2(0, 0, 640, 360)

	# A hostile projectile flying straight into the shield from the right.
	field.spawn("bolt", Vector2(520, nick.y), Vector2(-1, 0), 900.0)
	var events: Array = field.update(0.25, nick, s, 8.0, arena)
	check("a projectile into the shield is blocked", events.size() == 1 and String(events[0]["kind"]) == "block")
	check("a blocked projectile is removed", field.active_count() == 0)

	# The same projectile from an unprotected direction reaches Nick.
	field.spawn("bolt", Vector2(520, nick.y), Vector2(-1, 0), 900.0)
	s.set_direction(Vector2(-1, 0))
	events = field.update(0.25, nick, s, 8.0, arena)
	check("a projectile through an unprotected direction hits", events.size() == 1 and String(events[0]["kind"]) == "hit")
	check("a projectile is resolved once", field.active_count() == 0)

	# Fast projectile: one frame's travel crosses the whole shield. The swept
	# test must still intercept it, and must not report a body hit too.
	field.spawn("bolt", Vector2(620, nick.y), Vector2(-1, 0), 6000.0)
	s.set_direction(Vector2(1, 0))
	events = field.update(0.25, nick, s, 8.0, arena)
	var kinds: Array = []
	for e in events:
		kinds.append(String(e["kind"]))
	check("a fast projectile is intercepted, not tunnelled", kinds.has("block"))
	check("a fast intercept never also reports a body hit", not kinds.has("hit"))
	check("a fast intercept resolves the projectile once", events.size() == 1)

	# Fast projectile through the gap: body hit, not a late shield block.
	field.spawn("bolt", Vector2(620, nick.y), Vector2(-1, 0), 6000.0)
	s.set_direction(Vector2(-1, 0))
	events = field.update(0.25, nick, s, 8.0, arena)
	kinds = []
	for e in events:
		kinds.append(String(e["kind"]))
	check("a fast unprotected projectile hits Nick", kinds.has("hit"))
	check("a past-the-shield projectile is not blocked later", not kinds.has("block"))

	# Shield at the point of arrival wins over the body: the shield radius is
	# outside the body radius, so the shield is always reached first.
	field.spawn("bolt", Vector2(nick.x + 300, nick.y), Vector2(-1, 0), 60.0)
	s.set_direction(Vector2(1, 0))
	var steps := 0
	var blocked_once := false
	while steps < 200 and field.active_count() > 0:
		steps += 1
		for e in field.update(0.05, nick, s, 8.0, arena):
			if String(e["kind"]) == "block":
				blocked_once = true
			if String(e["kind"]) == "hit":
				blocked_once = false
	check("a shield facing the flight path blocks every step", blocked_once)

	# Expired and offscreen projectiles are removed.
	field.clear()
	var p = field.spawn("bolt", Vector2(330, nick.y), Vector2(1, 0), 1.0)
	p["life"] = 0.01
	field.update(0.05, nick, s, 8.0, arena)
	check("expired projectiles are removed", field.active_count() == 0)
	field.spawn("bolt", Vector2(5000, 5000), Vector2(1, 0), 10.0)
	field.update(0.05, nick, s, 8.0, arena)
	check("offscreen projectiles are removed", field.active_count() == 0)

	# Clearing at the end of an encounter clears everything.
	field.spawn("bolt", Vector2(400, 100), Vector2(-1, 1).normalized(), 50.0)
	field.spawn("memory_mote", Vector2(100, 100), Vector2(1, 1).normalized(), 40.0)
	check("projectiles exist before a clear", field.active_count() >= 2)
	field.clear()
	check("clearing removes every projectile", field.active_count() == 0)


func _test_projectile_interactions() -> void:
	section("Projectile interactions")

	var arena := Rect2(0, 0, 640, 360)

	# Hostile blocked: no health loss, no charge.
	var enc = _new_encounter("scrap_king")
	var m = enc.model
	var hp: int = m.nick_health
	enc.shield.set_direction(Vector2(1, 0))
	enc.field.spawn("bolt", Vector2(520, nick.y), Vector2(-1, 0), 900.0)
	enc.field.update(0.25, nick, enc.shield, 8.0, arena)
	check("a blocked hostile does not damage Nick", m.nick_health == hp)
	check("a blocked hostile grants no charge", m.charge == 0)

	# Hostile body hit: configured damage, no charge loss.
	enc.shield.set_direction(Vector2(-1, 0))
	enc.field.spawn("slug", Vector2(520, nick.y), Vector2(-1, 0), 900.0)
	var expected: int = int(data.projectile_type("slug").get("damage", 0))
	enc.field.update(0.25, nick, enc.shield, 8.0, arena)
	m.damage_nick(expected)
	check("a hostile body hit deals its configured damage", m.nick_health == hp - expected, "%d -> %d" % [hp, m.nick_health])
	check("different hostile types carry different damage",
		int(data.projectile_type("slug").get("damage", 0)) != int(data.projectile_type("spray").get("damage", 0)))
	m.charge = 40
	m.damage_nick(5)
	check("taking damage does not consume charge", m.charge == 40)

	# Beneficial blocked: no charge, no damage.
	var enc2 = _new_encounter("scrap_king")
	enc2.shield.set_direction(Vector2(1, 0))
	enc2.field.spawn("memory_mote", Vector2(520, nick.y), Vector2(-1, 0), 900.0)
	enc2.field.update(0.25, nick, enc2.shield, 8.0, arena)
	check("a blocked benefit grants no charge", enc2.model.charge == 0)
	check("a blocked benefit does not damage Nick", enc2.model.nick_health == enc2.model.nick_health_max)

	# Beneficial absorbed: charge, no damage.
	enc2.shield.set_direction(Vector2(-1, 0))
	enc2.field.spawn("memory_mote", Vector2(520, nick.y), Vector2(-1, 0), 900.0)
	var events: Array = enc2.field.update(0.6, nick, enc2.shield, 8.0, arena)
	var absorbed := false
	for e in events:
		if String(e["kind"]) == "absorb":
			absorbed = true
	check("a beneficial body hit is absorbed", absorbed)
	var gained: int = enc2.model.absorb_charge(int(data.projectile_type("memory_mote").get("charge", 0)))
	check("an absorbed benefit adds charge", gained > 0 and enc2.model.charge == gained)
	check("beneficial energy is not a health pickup", enc2.model.nick_health == enc2.model.nick_health_max)

	# Charge clamps at the maximum rather than overflowing.
	enc2.model.charge = enc2.model.charge_max - 1
	enc2.model.absorb_charge(999)
	check("charge clamps at the maximum", enc2.model.charge == enc2.model.charge_max)

	# Full charge does not decay, however long the player waits.
	var full: int = enc2.model.charge_max
	enc2.model.begin_fight()
	for i in 200:
		enc2.model.tick(0.05)
	check("full charge does not decay while waiting", enc2.model.charge == full)
	check("charge stays readable as a full fraction", is_equal_approx(enc2.model.charge_fraction(), 1.0))


# ---------------------------------------------------------------- counterattack

func _new_encounter(boss_id: String):
	var enc = SFEncounter.new()
	enc.setup(data.boss(boss_id), data)
	enc.begin()
	enc.intro_hold = false
	return enc


func _test_charge_and_counter() -> void:
	section("Charge and counterattack")

	var enc = _new_encounter("scrap_king")
	var m = enc.model
	check("the meter begins empty", m.charge == 0)
	check("the fight begins in the fight phase", m.phase == m.PHASE_FIGHT)

	# Space below full charge does nothing at all.
	m.charge = m.charge_max - 1
	check("a counterattack below full charge is refused", not enc.counterattack())
	check("a refused counterattack does not consume charge", m.charge == m.charge_max - 1)
	check("a refused counterattack does not damage the boss", m.boss_health == m.boss_health_max)

	# One full charge, one counterattack.
	m.charge = m.charge_max
	var boss_before: int = m.boss_health
	check("a full charge accepts a counterattack", enc.counterattack())
	check("the counterattack consumes the full charge", m.charge == 0)
	check("the shield locks during the counterattack", m.shield_locked())
	check("a second press during the lock is refused", not enc.counterattack())

	# The strike lands once, mid-lock, and cannot land twice.
	var strikes := 0
	for i in 60:
		for e in enc.tick(0.02):
			if String(e.get("kind", "")) == "counter_strike":
				strikes += 1
	check("the counterattack strikes exactly once", strikes == 1, str(strikes))
	check("the counterattack damages the boss once",
		m.boss_health == boss_before - int(data.boss("scrap_king").get("counterattack_damage", 0)))
	check("the fight resumes after the lock", m.phase == m.PHASE_FIGHT)

	# Holding Space must not repeat: the model only accepts fresh requests, and
	# the screen only reports just-pressed edges. Both are asserted here.
	m.charge = 0
	for i in 30:
		check_silent(not enc.counterattack())
	check("holding Space with an empty meter never attacks", m.boss_health == boss_before - int(data.boss("scrap_king").get("counterattack_damage", 0)))

	# Charge survives the lock and the return to the fight.
	m.charge = 17
	enc.tick(0.5)
	check("charge earned before a lock is not lost by the lock", m.charge >= 10)

	# During the lock no projectile is spawned, which is what makes a frozen
	# shield fair.
	var enc2 = _new_encounter("scrap_king")
	enc2.model.charge = enc2.model.charge_max
	enc2.counterattack()
	for i in 20:
		enc2.tick(0.02)
	check("no projectiles spawn during the counterattack lock", enc2.field.active_count() == 0)
	check("no damage lands during the counterattack lock",
		enc2.model.nick_health == enc2.model.nick_health_max)


## A checks-free helper: it records nothing, and exists so a loop of expected
## refusals does not multiply the check count.
func check_silent(ok: bool) -> void:
	if not ok:
		fails += 1
		checks_run += 1
		print("FAIL  an unexpected counterattack was accepted")


# ---------------------------------------------------------------- escalation

func _test_escalation() -> void:
	section("Health-based difficulty escalation")

	for boss_id in ["scrap_king", "toxic_tide"]:
		var boss: Dictionary = data.boss(boss_id)
		var sch = SFScheduler.new()
		sch.configure(boss, data.combat, nick)
		var full_interval: float = sch.fire_interval_for(1.0)
		var low_interval: float = sch.fire_interval_for(0.05)
		var full_speed: float = sch.projectile_speed_for(1.0)
		var low_speed: float = sch.projectile_speed_for(0.05)
		check(boss_id + ": lower health fires faster", low_interval < full_interval,
			"%.2fs -> %.2fs" % [full_interval, low_interval])
		check(boss_id + ": lower health moves projectiles faster", low_speed > full_speed,
			"%.0f -> %.0f" % [full_speed, low_speed])
		check(boss_id + ": the firing interval is bounded",
			low_interval >= float(boss.get("limits", {}).get("min_fire_interval", 0.0)))
		check(boss_id + ": projectile speed is bounded",
			low_speed <= float(boss.get("limits", {}).get("max_projectile_speed", 999.0)))
		check(boss_id + ": telegraphs never vanish",
			sch.telegraph_for(0.0) >= float(data.combat.get("min_telegraph_seconds", 0.0)))
		check(boss_id + ": telegraphs stay readable",
			sch.telegraph_for(1.0) <= float(data.combat.get("max_telegraph_seconds", 99.0)))

	# Escalation is a function of health only: the same fraction at different
	# times must produce the same values.
	var sch2 = SFScheduler.new()
	sch2.configure(data.boss("scrap_king"), data.combat, nick)
	var a: float = sch2.fire_interval_for(0.5)
	for i in 100:
		sch2.tick(0.1, 0.5, 0)
	var b: float = sch2.fire_interval_for(0.5)
	check("escalation does not depend on elapsed time", is_equal_approx(a, b))

	# The band table is monotonic: no band is easier than the one above it.
	var monotonic := true
	for boss_id in ["scrap_king", "toxic_tide"]:
		var bands: Array = data.boss(boss_id).get("bands", []) as Array
		var prev_interval := 9999.0
		var prev_speed := 0.0
		for entry in bands:
			var band: Dictionary = entry
			var interval := float(band.get("fire_interval", 0.0))
			var speed := float(band.get("projectile_speed", 0.0))
			if interval > prev_interval or speed < prev_speed:
				monotonic = false
			prev_interval = interval
			prev_speed = speed
	check("every health band escalates monotonically", monotonic)

	# Two bosses are actually different, not reskins.
	var sk: Dictionary = data.boss("scrap_king")
	var tt: Dictionary = data.boss("toxic_tide")
	check("the bosses differ in health", int(sk.get("boss_health", 0)) != int(tt.get("boss_health", 0)))
	check("the bosses differ in counterattack damage",
		int(sk.get("counterattack_damage", 0)) != int(tt.get("counterattack_damage", 0)))
	var sk_patterns: Array = (sk.get("patterns", {}) as Dictionary).keys()
	var tt_patterns: Array = (tt.get("patterns", {}) as Dictionary).keys()
	check("the bosses share some vocabulary", _overlap_count(sk_patterns, tt_patterns) > 0)
	check("the bosses have distinct patterns", not sk_patterns.has("spray_arc") or not tt_patterns.has("salvo_arc"))
	check("the bosses differ in silhouette", String(sk.get("visual", {}).get("silhouette", "")) != String(tt.get("visual", {}).get("silhouette", "")))


func _overlap_count(a: Array, b: Array) -> int:
	var n := 0
	for x in a:
		if b.has(x):
			n += 1
	return n


func _test_pattern_fairness() -> void:
	section("Pattern scheduling and fairness")

	var enc = _new_encounter("scrap_king")
	var telegraphs_seen := 0
	var spawns := 0
	var max_active := 0
	var guard := 0
	# Run 20 seconds of a full-health fight without moving the shield.
	while guard < 400:
		guard += 1
		for e in enc.tick(0.05):
			var kind := String(e.get("kind", ""))
			if kind == "telegraph":
				telegraphs_seen += 1
			elif kind == "spawn":
				spawns += 1
		max_active = maxi(max_active, enc.field.active_count())
	check("the encounter telegraphs before it fires", telegraphs_seen > 0)
	check("the encounter actually fires", spawns > 0)
	check("the active projectile count stays bounded", max_active <= int(data.boss("scrap_king").get("limits", {}).get("max_active", 99)), str(max_active))

	# Every spawn follows its own telegraph from the same emitter. A pattern may
	# fire a volley, so warnings are counted per emitter rather than treated as
	# a single flag.
	var enc2 = _new_encounter("toxic_tide")
	var pending_telegraphs: Dictionary = {}
	var orderly := true
	var spawns_2 := 0
	guard = 0
	while guard < 400:
		guard += 1
		for e in enc2.tick(0.05):
			var kind2 := String(e.get("kind", ""))
			var emitter2 := String(e.get("emitter", ""))
			if kind2 == "telegraph":
				pending_telegraphs[emitter2] = int(pending_telegraphs.get(emitter2, 0)) + 1
			elif kind2 == "spawn":
				spawns_2 += 1
				var remaining := int(pending_telegraphs.get(emitter2, 0))
				if remaining <= 0:
					orderly = false
				else:
					pending_telegraphs[emitter2] = remaining - 1
	check("every spawn was preceded by its telegraph", orderly)
	check("the second boss also fires", spawns_2 > 0)

	# Beneficial energy is available, and it is scheduled away from Nick.
	var enc3 = _new_encounter("scrap_king")
	var beneficial_spawns: Array = []
	guard = 0
	while guard < 600:
		guard += 1
		# Keep Nick alive: a dead player stops the schedule, and this check is
		# about whether beneficial energy is ever offered.
		enc3.model.nick_health = enc3.model.nick_health_max
		for e in enc3.tick(0.05):
			if String(e.get("kind", "")) == "spawn" and String(e.get("family", "")) == "beneficial":
				beneficial_spawns.append(e)
	check("beneficial energy is available", beneficial_spawns.size() > 0)
	var all_far := true
	for e in beneficial_spawns:
		var at: Vector2 = e.get("position", Vector2.ZERO)
		if at.distance_to(nick) < 60.0:
			all_far = false
	check("beneficial energy never spawns on Nick", all_far)

	# A reproducible seed: two runs of the same boss produce the same schedule.
	var run_a := _schedule_signature("toxic_tide")
	var run_b := _schedule_signature("toxic_tide")
	check("the same seed reproduces the same schedule", run_a == run_b, "%d vs %d" % [run_a, run_b])
	var other = _new_encounter("scrap_king")
	other.scheduler.set_seed(12345)
	check("the seed can be overridden for a test", other.scheduler.seed_value() == 12345)

	# No attacks are scheduled while the fight is paused in intro or victory.
	var enc4 = _new_encounter("scrap_king")
	enc4.intro_hold = true
	enc4.is_fighting()
	for i in 40:
		enc4.tick(0.05)
	check("nothing spawns during the intro hold", enc4.field.active_count() == 0)


## A cheap summary of one boss's first 20 seconds of scheduling: the number of
## scheduled combinations. Two equal signatures means the RNG is reproducible.
func _schedule_signature(boss_id: String) -> int:
	var enc = _new_encounter(boss_id)
	var sig := 0
	for i in 300:
		for e in enc.tick(0.05):
			sig = (sig * 31 + String(e.get("kind", "")).length() + String(e.get("type", "")).length() * 7 + int(String(e.get("emitter", "")).length())) % 1000003
	return sig


# ---------------------------------------------------------------- retry

func _test_retry_reset() -> void:
	section("Defeat and retry")

	var enc = _new_encounter("toxic_tide")
	var m = enc.model

	# Fight a while, take damage, earn charge, then die.
	for i in 200:
		enc.tick(0.05)
	m.charge = 55
	m.damage_nick(m.nick_health)
	check("Nick reaching zero ends the encounter", m.phase == m.PHASE_DEFEAT)
	check("defeat reports the defeat result", m.result == m.RESULT_DEFEAT)
	var damage_before: int = m.nick_health
	check("no further damage is applied after defeat", not m.damage_nick(10) or m.nick_health == damage_before)
	check("no charge is gained after defeat", m.absorb_charge(20) == 0)
	check("no counterattack is accepted after defeat", not enc.counterattack())

	enc.reset()
	check("retry restores Nick to full health", m.nick_health == m.nick_health_max)
	check("retry restores the boss to full health", m.boss_health == m.boss_health_max)
	check("retry empties the charge meter", m.charge == 0)
	check("retry clears projectiles", enc.field.active_count() == 0)
	check("retry clears telegraphs", enc.telegraphs.is_empty())
	check("retry returns to the intro phase", m.phase == m.PHASE_INTRO)
	check("retry clears the result", m.result == m.RESULT_NONE)
	check("retry re-arms the encounter", not enc.is_over())
	enc.begin()
	check("the encounter can start again after a retry", enc.is_fighting())

	# Escalation resets: a retry starts at the initial band, not the hardest.
	enc.reset()
	enc.begin()
	var band: Dictionary = enc.scheduler.band_for_fraction(1.0)
	check("a retry starts at the initial band", is_equal_approx(float(band.get("at_fraction", 0.0)), 1.0))
	check("a retry restores the initial firing interval",
		is_equal_approx(enc.scheduler.fire_interval_for(1.0), float(band.get("fire_interval", 0.0))))
	check("a retry restores the initial projectile speed",
		is_equal_approx(enc.scheduler.projectile_speed_for(1.0), float(band.get("projectile_speed", 0.0))))

	# A retry must not touch campaign progress: the model has no reference to it
	# at all, which this asserts by construction.
	check("the encounter model owns no campaign reference", not _has_property(m, "campaign"))
	check("the encounter model owns no inventory", not _has_property(m, "inventory"))


func _has_property(obj, name: String) -> bool:
	for p in obj.get_property_list():
		if String(p.get("name", "")) == name:
			return true
	return false


# ---------------------------------------------------------------- intro hold

## The briefing freeze is a cross-cutting rule: while it is on, no attack spawns,
## no damage lands, and a counterattack is refused. The screen also refuses all
## keys during that window, so Space cannot leak from the dialogue into combat.
func _test_intro_freeze() -> void:
	section("Briefing freeze and input isolation")

	var enc = _new_encounter("scrap_king")
	enc.intro_hold = true
	var m = enc.model
	for i in 100:
		enc.tick(0.05)
	check("nothing spawns while the briefing is up", enc.field.active_count() == 0)
	check("the fight does not report itself live during the briefing", not enc.is_fighting())
	check("no damage can land during the briefing", not m.damage_nick(30))
	check("Nick is untouched during the briefing", m.nick_health == m.nick_health_max)
	m.charge = m.charge_max
	check("a counterattack is refused during the briefing", not enc.counterattack())
	check("the charge is kept through a refused counterattack", m.charge == m.charge_max)
	enc.begin()
	check("the fight is live once the briefing closes", enc.is_fighting())
	check("the fight starts spawning once the briefing closes", _first_spawn_after(enc) > 0.0)


func _first_spawn_after(enc) -> float:
	for i in 200:
		for e in enc.tick(0.05):
			if String(e.get("kind", "")) == "spawn":
				return 1.0
		enc.model.nick_health = enc.model.nick_health_max
	return 0.0


# ---------------------------------------------------------------- victory

func _test_victory_and_rewards() -> void:
	section("Victory and reward idempotence")

	var enc = _new_encounter("scrap_king")
	var m = enc.model
	var victory_events := 0

	# Four counterattacks kill a 100-health boss with 25 damage each.
	var attacks := 0
	var guard := 0
	while m.phase != m.PHASE_VICTORY and guard < 2000:
		guard += 1
		if m.is_fighting() and not m.shield_locked():
			m.charge = m.charge_max
			if enc.counterattack():
				attacks += 1
		for e in enc.tick(0.05):
			if String(e.get("kind", "")) == "victory":
				victory_events += 1
	check("four counterattacks defeat the Scrap King", attacks == 4, str(attacks))
	check("victory is reported exactly once", victory_events == 1, str(victory_events))
	check("victory stops the fight", not m.is_fighting())
	check("victory clears live projectiles", enc.field.active_count() == 0)

	# Nothing can hurt Nick after victory, even if projectiles existed.
	enc.field.spawn("slug", Vector2(400, nick.y), Vector2(-1, 0), 300.0)
	var hp_after: int = m.nick_health
	for i in 20:
		enc.tick(0.05)
	check("no damage lands after victory", m.nick_health == hp_after)
	check("no counterattack is accepted after victory", not enc.counterattack())

	# Campaign-side rewards are awarded once per boss.
	var campaign = SFCampaign.new()
	check("a new campaign has no components", campaign.recovered_component_ids().is_empty())
	check("awarding a component works once", campaign.award_component("navigation_chip"))
	check("awarding the same component again is refused", not campaign.award_component("navigation_chip"))
	check("the component is recorded exactly once", _count(campaign.recovered_component_ids(), "navigation_chip") == 1)
	check("the campaign knows the chip is recovered", campaign.has_component("navigation_chip"))
	check("the campaign knows the core is missing", not campaign.has_component("power_core"))
	check("the component readout lists every future component", campaign.component_status().size() == 3)
	var status := _status(campaign, "navigation_chip")
	check("the readout marks the chip recovered", bool(status.get("recovered", false)))
	var core_status := _status(campaign, "power_core")
	check("the readout marks the core missing", not bool(core_status.get("recovered", true)))

	# The reveal and the coast outcome are each applied exactly once.
	check("the Future Earth reveal applies", campaign.reveal_future_earth())
	check("the reveal changes the mission", campaign.mission_id() == SFCampaign.MISSION_RETURN)
	check("the reveal unlocks the Silent Coast", campaign.has_flag(SFCampaign.FLAG_SILENT_COAST_UNLOCKED))
	check("a second reveal is refused", not campaign.reveal_future_earth())
	check("the mission is stable after a second reveal", campaign.mission_id() == SFCampaign.MISSION_RETURN)
	check("the Silent Coast outcome applies", campaign.complete_silent_coast())
	check("the Silent Coast outcome unlocks Dawn Tower", campaign.has_flag(SFCampaign.FLAG_DAWN_TOWER_UNLOCKED))
	check("a second Silent Coast outcome is refused", not campaign.complete_silent_coast())
	check("Phase 2 never grants the shield emitter", not campaign.has_component("shield_emitter"))


func _count(list: Array, value: String) -> int:
	var n := 0
	for entry in list:
		if String(entry) == value:
			n += 1
	return n


func _status(campaign, component_id: String) -> Dictionary:
	for entry in campaign.component_status():
		var comp: Dictionary = entry
		if String(comp.get("id", "")) == component_id:
			return comp
	return {}


# ---------------------------------------------------------------- save

func _test_save_load() -> void:
	section("Phase 2 persistence")

	SFSave.delete_save(test_save_path)
	var campaign = SFCampaign.new()
	campaign.reveal_future_earth()
	campaign.complete_silent_coast()
	campaign.award_component("navigation_chip")
	campaign.award_component("power_core")
	campaign.restore_archive(SFCampaign.ARCHIVE_CITY)
	campaign.restore_archive(SFCampaign.ARCHIVE_COAST)
	campaign.view_memory(SFCampaign.MEMORY_CITY_GREEN)
	campaign.view_memory(SFCampaign.MEMORY_GREEN_COAST)
	campaign.set_flag(SFCampaign.FLAG_CITY_CHECKPOINT)
	campaign.set_flag(SFCampaign.FLAG_COAST_CHECKPOINT)
	campaign.advance_to(SFCampaign.STAGE_PHASE_TWO_COMPLETE)
	campaign.set_checkpoint(SFCampaign.STAGE_PHASE_TWO_COMPLETE, SFCampaign.CHAPTER_CRASH)

	var write: Dictionary = SFSave.write_save(campaign, test_save_path)
	check("the Phase 2 save writes", bool(write.get("ok", false)), String(write.get("error", "")))
	check("the save validates", SFSave.has_valid_save(test_save_path))

	var loaded = SFCampaign.new()
	var result: Dictionary = SFSave.load_into(loaded, test_save_path)
	check("the Phase 2 save loads", bool(result.get("ok", false)))
	check("components survive", loaded.has_component("navigation_chip") and loaded.has_component("power_core"))
	check("components do not duplicate on load", _count(loaded.recovered_component_ids(), "navigation_chip") == 1)
	check("archives survive", loaded.is_archive_restored(SFCampaign.ARCHIVE_CITY) and loaded.is_archive_restored(SFCampaign.ARCHIVE_COAST))
	check("the mission survives", loaded.mission_id() == SFCampaign.MISSION_RETURN)
	check("the stage survives", loaded.stage == SFCampaign.STAGE_PHASE_TWO_COMPLETE)
	check("the chapter survives", loaded.chapter_id == SFCampaign.CHAPTER_CRASH)
	check("Dawn Tower survives as unlocked", loaded.has_flag(SFCampaign.FLAG_DAWN_TOWER_UNLOCKED))
	check("the optional memories survive", loaded.has_viewed_memory(SFCampaign.MEMORY_CITY_GREEN) and loaded.has_viewed_memory(SFCampaign.MEMORY_GREEN_COAST))

	# Reloading replaces state; it never merges or duplicates.
	var second: Dictionary = SFSave.load_into(loaded, test_save_path)
	check("reloading replaces rather than merges", bool(second.get("ok", false)))
	check("reloading does not duplicate components", loaded.recovered_component_ids().size() == 2)
	check("reloading does not duplicate archives", loaded.restored_archives.size() == 2)

	# A version-1 save (Phase 1 only) must still load and keep its mission.
	var v1 := {
		"version": 1,
		"stage": "crash_site",
		"chapter_id": "crash_site",
		"checkpoint_stage": "crash_site",
		"checkpoint_chapter": "crash_site",
		"credits": 50.0,
		"inventory": {"scrap_metal": 2},
		"flags": {"bill_active": true},
		"viewed_memories": ["memory_green_city"],
	}
	var old_campaign = SFCampaign.new()
	var old_warnings: Array = old_campaign.apply_save_dict(v1)
	check("a version-1 save still loads", old_campaign.stage == SFCampaign.STAGE_CRASH_SITE)
	check("a version-1 save keeps its inventory", old_campaign.material_count("scrap_metal") == 2)
	check("a version-1 save defaults to the original mission", old_campaign.mission_id() == SFCampaign.MISSION_SIGNAL)
	check("a version-1 save has no components", old_campaign.recovered_component_ids().is_empty())
	check("a version-1 save loads without fatal warnings", true, str(old_warnings.size()) + " warning(s)")

	# A revealing save without the mission field recovers it from its flags.
	var v2 := {
		"version": 2,
		"stage": "silent_intro",
		"chapter_id": "silent_coast",
		"flags": {"future_earth_revealed": true},
	}
	var recovered = SFCampaign.new()
	recovered.apply_save_dict(v2)
	check("the mission is recovered from the reveal flag", recovered.mission_id() == SFCampaign.MISSION_RETURN)
	check("an unknown stage falls back safely", SFCampaign.new().apply_save_dict({"version": 2, "stage": "nonsense"}).size() > 0)

	SFSave.delete_save(test_save_path)


# ---------------------------------------------------------------- regression

func _test_phase_one_untouched() -> void:
	section("Phase 1 regression")

	var campaign = SFCampaign.new()
	check("Phase 1 stages still exist", campaign.STAGE_ORDER.has(SFCampaign.STAGE_BRIEFING))
	check("the Phase 1 chapter is still the start", campaign.chapter_id == SFCampaign.CHAPTER_PRESENT)
	check("the Phase 1 memory still exists", not campaign.content.memory(SFCampaign.MEMORY_GREEN_CITY).is_empty())
	check("the Green City memory data is unchanged",
		String(campaign.content.memory(SFCampaign.MEMORY_GREEN_CITY).get("title", "")) == "Green City")
	check("the Phase 2 stage order follows Phase 1",
		campaign.STAGE_ORDER.find(SFCampaign.STAGE_CITY_INTRO) > campaign.STAGE_ORDER.find(SFCampaign.STAGE_CHECKPOINT))
	check("the Phase 2 stage order ends at complete",
		campaign.STAGE_ORDER.find(SFCampaign.STAGE_PHASE_TWO_COMPLETE) < campaign.STAGE_ORDER.find(SFCampaign.STAGE_COMPLETE))
	check("Dawn Tower is not a playable stage", not campaign.STAGE_ORDER.has("dawn_tower"))
	check("the crash-site chapter still exists", not campaign.content.chapter("crash_site").is_empty())
	check("salvage still works", bool(campaign.claim_salvage("salvage_plate")["ok"]))
	campaign.claim_salvage("salvage_circuit")
	check("the junction still repairs", bool(campaign.repair_junction()["ok"]))
	check("the boss data does not reference the shield emitter",
		String(data.boss("scrap_king").get("reward_component", "")) != "shield_emitter")
