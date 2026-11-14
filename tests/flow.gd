extends SceneTree
## Drives the real controller with synthetic key events, all the way from the
## title screen to an ending, to prove the screen flow and input wiring work.

var fails: int = 0
var main_node: Node
var step: int = 0
var wait: int = 0

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  ") + label + ("" if detail == "" else "  [" + detail + "]"))
	if not ok:
		fails += 1

func key(k: int) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = k
	main_node._handle_key(k)

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/starfall/main.tscn")
	main_node = ps.instantiate()
	root.add_child(main_node)

func _process(delta: float) -> bool:
	step += 1
	if step < 4:
		return false
	wait += 1
	match step:
		4:
			check("boots on title", main_node.screen == 0)
			key(KEY_ENTER)
			check("title -> station", main_node.screen == 1)
			main_node.state.budget = 500.0
			key(KEY_1)
			check("key 1 buys cargo upgrade", main_node.state.upgrade_level(0) == 1)
			var guard := 0
			while main_node.station_index < main_node.state.upgrade_defs.size() and guard < 8:
				key(KEY_DOWN)
				guard += 1
			check("cursor reaches depart row", main_node.station_index == main_node.state.upgrade_defs.size())
			key(KEY_ENTER)
			check("station -> map", main_node.screen == 2)
			key(KEY_ENTER)
			check("map launches sector 1", main_node.screen == 3 and main_node.mission != null)
			main_node.mission._brief_timer = 0.0
			# Real input is polled from the keyboard; drive the model directly.
			main_node.mission.ship.fuel = 170.0
		8:
			check("mission updates", main_node.mission.elapsed > 0.0, str(main_node.mission.elapsed))
			# Pretend we hauled cargo home.
			var miss = main_node.mission
			miss.ship.cargo_value = 95.0
			miss.ship.cargo_mass = 20.0
			miss.ship.collected = 12
			miss.ship.position = miss.station_pos
			check("station proximity detected", miss.can_dock())
			key(KEY_E)
			check("dock -> report", main_node.screen == 4)
			check("sector 1 cleared by quota", main_node.state.is_cleared(0))
			check("sector 2 unlocked", main_node.state.is_unlocked(1))
		12:
			key(KEY_ENTER)
			check("report -> map", main_node.screen == 2)
			# Jump straight to the finale condition.
			main_node.state.bank_sortie(1, 200.0, 10.0, 5, false)
			main_node.state.bank_sortie(2, 240.0, 10.0, 5, true)
			check("all sectors cleared", main_node.state.all_sectors_cleared())
			check("specimen secured flag", main_node.state.specimen_secured)
			key(KEY_F)
			check("map -> finale", main_node.screen == 5)
		16:
			# Pick the third option: last specimen.
			key(KEY_DOWN)
			key(KEY_DOWN)
			key(KEY_ENTER)
			check("finale -> ending", main_node.screen == 6)
			check("ending key", main_node.ending_key == "last_specimen", main_node.ending_key)
		20:
			main_node.ending_char = 99999.0
			key(KEY_ENTER)
			check("ending resets to title", main_node.screen == 0)
			check("state reset", int(main_node.state.budget) > 0 and not main_node.state.specimen_secured)
		24:
			# Logs screen round trip.
			main_node._go(1)
			main_node.state.add_log("log_ticket")
			main_node.state.add_log("log_audit")
			key(KEY_L)
			check("station L opens logs", main_node.screen == 7)
			key(KEY_DOWN)
			check("logs cursor moves", main_node.logs_index == 1)
			key(KEY_ESCAPE)
			check("esc closes logs back to station", main_node.screen == 1)
			print("")
			print("RESULT: %d failure(s)" % fails)
			quit()
	return false
