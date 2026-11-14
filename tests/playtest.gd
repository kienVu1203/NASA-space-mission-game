extends SceneTree
## Headless playtest: drives the real mission model through collection,
## docking, quota progression and each ending. Prints PASS/FAIL per check.

var fails: int = 0

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1

func _init() -> void:
	var MG = load("res://core/starfall/sf_mission.gd")
	var GS = load("res://core/starfall/sf_game_state.gd")
	var SK = load("res://core/starfall/sf_skin.gd")
	var AU = load("res://core/starfall/audio_stub.gd") if false else load("res://core/starfall/sf_audio.gd")
	var st = GS.new()
	var sk = SK.new(null)
	var audio = AU.new()

	# --- sector 1 collection run -------------------------------------------
	var m = MG.new()
	m.setup(st, sk, audio, 0)
	m._brief_timer = 0.0
	check("sector 1 spawns debris", m.debris.size() == 25, str(m.debris.size()))

	var collected := 0
	var guard := 0
	while m.ship.storage_free() > 1.0 and guard < 400:
		guard += 1
		# Find nearest uncollected debris and tow it in from just outside pickup.
		var tgt = null
		for d in m.debris:
			if not d.collected:
				tgt = d
				break
		if tgt == null:
			break
		m.ship.position = tgt.position + Vector2(-30, 0)
		for i in 40:
			m.ship.beaming = true
			m._apply_beam(1.0 / 60.0)
			tgt.step(1.0 / 60.0, m.world)
			if tgt.collected:
				break
		if tgt.collected:
			collected += 1
		else:
			m.ship.power = m.ship.power_max
	check("beam collects debris", collected > 6, "collected=%d" % collected)
	check("hold fills up", m.ship.storage_free() < 3.2, "free=%.1f" % m.ship.storage_free())
	var refused = false
	for d in m.debris:
		if d.collected:
			continue
		var verdict: Dictionary = m.ship.can_take(d.entry)
		refused = not bool(verdict["ok"])
		break
	check("full hold blocks pickup", refused)
	check("cargo value accumulates", m.ship.cargo_value > 20.0, "value=%.1f" % m.ship.cargo_value)
	check("mass slows the ship", m.ship.acceleration() < float(m.ship.stats["accel"]), "accel=%.1f" % m.ship.acceleration())
	# The harness tops power back up when a tow stalls, so assert the drain rate.
	check("beam drains power", float(m.ship.stats["beam_drain"]) > 0.0 and m.ship.power_rate() > m.ship.stats["passive_power"])

	var rep: Dictionary = m.dock()
	check("dock returns a report", rep.has("value") and rep.has("collected"), str(rep.get("value")))
	check("budget rose", st.budget > 110.0, "budget=%.1f" % st.budget)

	# --- quota / unlock progression ----------------------------------------
	var st2 = GS.new()
	st2.bank_sortie(0, st2.sector_quota(0) + 1.0, 10.0, 8, false)
	check("quota clears sector 1", st2.is_cleared(0))
	check("sector 2 unlocks", st2.is_unlocked(1))
	check("sector 3 still locked", not st2.is_unlocked(2))
	st2.bank_sortie(1, st2.sector_quota(1) + 1.0, 20.0, 10, false)
	check("quota clears sector 2", st2.is_cleared(1))
	check("sector 3 unlocks", st2.is_unlocked(2))

	# --- specimen path -----------------------------------------------------
	var st3 = GS.new()
	var m3 = MG.new()
	m3.setup(st3, sk, audio, 2)
	var pod = null
	for d in m3.debris:
		if d.is_special():
			pod = d
	check("sector 3 contains the pod", pod != null)
	if pod != null:
		m3.ship.position = pod.position + Vector2(-26, 0)
		for i in 60:
			m3.ship.beaming = true
			m3._apply_beam(1.0 / 60.0)
			pod.step(1.0 / 60.0, m3.world)
			if pod.collected:
				break
		check("pod can be recovered", pod.collected)
		m3.dock()
		check("specimen secured in state", st3.specimen_secured)
		check("last_specimen ending offered", st3.endings_available().has("last_specimen"))

	# --- endings data ------------------------------------------------------
	for key in ["plastic_snow", "endless_loop", "last_specimen"]:
		check("ending data: " + key, st.endings.has(key) and (st.endings[key] as Dictionary).has("paragraphs"))

	# --- upgrades ----------------------------------------------------------
	var st4 = GS.new()
	st4.budget = 1000.0
	var before: float = float(st4.ship_stats()["storage"])
	st4.buy_upgrade(0)
	check("cargo upgrade raises storage", float(st4.ship_stats()["storage"]) > before, "%.1f -> %.1f" % [before, float(st4.ship_stats()["storage"])])
	var burn_before: float = float(st4.ship_stats()["fuel_burn"])
	st4.buy_upgrade(1)
	check("thruster upgrade cuts fuel burn", float(st4.ship_stats()["fuel_burn"]) < burn_before)
	st4.budget = 0.0
	check("upgrade blocked without budget", not st4.can_upgrade(2))

	# --- fuel / distress ---------------------------------------------------
	var st5 = GS.new()
	var m5 = MG.new()
	m5.setup(st5, sk, audio, 0)
	m5.ship.fuel = 0.0
	m5.ship.power = 0.0
	m5.ship.step(1.0 / 60.0, Vector2(1, 0), false, m5.world)
	check("ship disables with no fuel and no power", m5.ship.disabled)
	var rep5: Dictionary = m5.distress_tow()
	check("tow fee applies", float(rep5["fee"]) >= 0.0 and rep5["towed"])

	print("")
	print("RESULT: %d failure(s)" % fails)
	quit()
