extends SceneTree
## Dev tool: renders every screen to user://shot_<name>.png so the build can be
## eyeballed without playing through it. Run headless or windowed:
##   godot --path . --script res://tests/capture.gd

var frames: int = 0
var idx: int = 0
var hold: int = 0
var main_node: Node
var shots: Array = [
	{"screen": "title", "wait": 14},
	{"screen": "station", "wait": 12},
	{"screen": "map", "wait": 12},
	{"screen": "mission", "wait": 40},
	{"screen": "flight", "wait": 20},
	{"screen": "report", "wait": 40},
	{"screen": "finale", "wait": 40},
	{"screen": "ending", "wait": 60},
	{"screen": "logs", "wait": 40},
]


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/starfall/main.tscn")
	main_node = ps.instantiate()
	root.add_child(main_node)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 4:
		return false
	hold += 1
	if idx >= shots.size():
		quit()
		return true
	var shot: Dictionary = shots[idx]
	if hold < int(shot["wait"]):
		if String(shot["screen"]) == "flight":
			main_node.mission.ship.beaming = true
			main_node.mission.ship.thrusting = true
			main_node.mission._throttle = 1.0
			for i in 10:
				main_node.mission._update_fx(0.05)
		return false
	_snap(String(shot["screen"]))
	idx += 1
	hold = 0
	if idx < shots.size():
		_advance(String(shots[idx]["screen"]))
	return false


func _advance(next: String) -> void:
	var m = main_node
	match next:
		"station":
			m.screen = 1
		"map":
			m.screen = 2
		"mission":
			m.state.budget = 400.0
			m.map_index = 0
			m._start_mission()
			m.mission._brief_timer = 0.0
		"flight":
			var miss = m.mission
			for d in miss.debris:
				miss.ship.position = d.position + Vector2(-46, 14)
				miss.ship.heading = 0.2
				break
			for i in 12:
				miss._update_fx(0.06)
		"report":
			var miss = m.mission
			if miss != null:
				# Actually collect a handful so the manifest is populated.
				for d in miss.debris:
					if miss.ship.storage_free() < 6.0:
						break
					if d.collected:
						continue
					miss.ship.position = d.position + Vector2(-20, 0)
					for i in 40:
						miss.ship.beaming = true
						miss._apply_beam(1.0 / 30.0)
						if d.collected:
							break
					miss.ship.power = miss.ship.power_max
				m._complete_mission(miss.dock())
		"finale":
			m._go(5)
		"ending":
			m._choose_ending("plastic_snow")
			m.ending_char = 99999.0
		"logs":
			m._open_logs()


func _snap(name: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://shot_%s.png" % name)
	print("saved ", name, " -> ", ProjectSettings.globalize_path("user://shot_%s.png" % name))
