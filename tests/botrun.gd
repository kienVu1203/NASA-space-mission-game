extends SceneTree
## Balance bot: flies the ship with real physics toward the nearest debris,
## tows it, and reports whether Act I is clearable in one sortie and how
## tight fuel/power actually are.

func _init() -> void:
	var MG = load("res://core/starfall/sf_mission.gd")
	var GS = load("res://core/starfall/sf_game_state.gd")
	var SK = load("res://core/starfall/sf_skin.gd")
	var AU = load("res://core/starfall/sf_audio.gd")
	var sk = SK.new(null)
	var audio = AU.new()

	for idx in 3:
		var st = GS.new()
		var m = MG.new()
		m.setup(st, sk, audio, idx)
		var dt := 1.0 / 60.0
		var simulated := 0.0
		var held := 0.0
		var full_at := -1.0
		while simulated < 420.0:
			simulated += dt
			var tgt = null
			var best := INF
			for d in m.debris:
				if d.collected:
					continue
				var dist: float = m.ship.position.distance_to(d.position)
				if dist < best:
					best = dist
					tgt = d
			if tgt == null:
				break
			var to_t: Vector2 = tgt.position - m.ship.position
			var dir: Vector2 = Vector2.ZERO
			if best > 22.0:
				dir = to_t.normalized()
			m.ship.step(dt, dir, best < 40.0, m.world)
			tgt.step(dt, m.world)
			if best < 40.0:
				m._apply_beam(dt)
			if full_at < 0.0 and m.ship.storage_free() < 1.0:
				full_at = simulated
			if m.ship.storage_free() < 1.0 and m.ship.cargo_value > 0.0:
				held = m.ship.cargo_value
				if m.ship.fuel < m.ship.fuel_max * 0.35:
					break
			if m.ship.disabled:
				break
		m.ship.position = m.station_pos
		var rep: Dictionary = m.dock()
		print("SECTOR %d  t=%.0fs  items=%d  value=%d  mass=%.0f  fuel=%d/%d  power=%d/%d  full_at=%.0fs  cleared=%s" % [
			idx + 1, simulated, int(rep["collected"]), int(rep["value"]), float(rep["mass"]),
			int(m.ship.fuel), int(m.ship.fuel_max), int(m.ship.power), int(m.ship.power_max),
			full_at, str(rep["cleared_now"])])
		print("           banked=%d / quota=%d" % [int(rep["banked"]), int(rep["quota"])])
	print("done")
	quit()
