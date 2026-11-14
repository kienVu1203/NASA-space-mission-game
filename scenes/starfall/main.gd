extends Node2D
## Operation: Starfall - one controller for the whole game.
##
## Everything renders into a 480x270 back buffer and is blitted to the window
## at an integer-ish scale with nearest-neighbour filtering, so the pixel art
## stays sharp at any window size.

const Pal := preload("res://core/starfall/sf_palette.gd")
const GameState := preload("res://core/starfall/sf_game_state.gd")
const SkinKit := preload("res://core/starfall/sf_skin.gd")
const Audio := preload("res://core/starfall/sf_audio.gd")
const Mission := preload("res://core/starfall/sf_mission.gd")

const VW := 480
const VH := 270

enum Screen { TITLE, STATION, MAP, MISSION, REPORT, FINALE, ENDING, LOGS }

var state
var skin
var audio
var mission

var screen: int = Screen.TITLE
var previous_screen: int = Screen.TITLE
var time: float = 0.0
var blink: float = 0.0

# Cursor state per screen.
var station_index: int = 0
var map_index: int = 0
var report: Dictionary = {}
var finale_index: int = 0
var ending_key: String = ""
var toast: String = ""
var toast_timer: float = 0.0
var toast_color: Color = Pal.PAPER
var logs_index: int = 0
var paused: bool = false
var ending_par_index: int = 0
var ending_char: float = 0.0
var shown_logs: Array = []
var _last_mission_logs: Array = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(Pal.DEEP)
	audio = Audio.new()
	audio.name = "SFAudio"
	add_child(audio)
	state = GameState.new()
	skin = SkinKit.new(audio)
	set_process_mode(Node.PROCESS_MODE_ALWAYS)
	_go(Screen.TITLE)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_handle_wheel(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_handle_wheel(1)


func _handle_key(key: int) -> void:
	if key == KEY_M:
		var muted: bool = audio.toggle_muted()
		_notify("AUDIO MUTED" if muted else "AUDIO ON", Pal.MID)
		return

	match screen:
		Screen.TITLE:
			_title_key(key)
		Screen.STATION:
			_station_key(key)
		Screen.MAP:
			_map_key(key)
		Screen.MISSION:
			_mission_key(key)
		Screen.REPORT:
			_report_key(key)
		Screen.FINALE:
			_finale_key(key)
		Screen.ENDING:
			_ending_key(key)
		Screen.LOGS:
			_logs_key(key)


func _to_virtual_pos(pos: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	var scale: float = min(vp.x / VW, vp.y / VH)
	if scale >= 2.0:
		scale = floor(scale)
	var origin := ((vp - Vector2(VW, VH) * scale) * 0.5).floor()
	return (pos - origin) / maxf(scale, 0.001)


func _handle_mouse_motion(pos: Vector2) -> void:
	var p := _to_virtual_pos(pos)
	match screen:
		Screen.STATION:
			for i in state.upgrade_defs.size():
				var row := Rect2(186, 52 + i * 33, 182, 30)
				if row.has_point(p):
					if station_index != i:
						station_index = i
						audio.sfx_select()
					return
			var depart := Rect2(8, 196, VW - 16, 22)
			if depart.has_point(p) and station_index != state.upgrade_defs.size():
				station_index = state.upgrade_defs.size()
				audio.sfx_select()
		Screen.MAP:
			var list_x: float = 196.0
			for i in 3:
				var box := Rect2(list_x, 30 + i * 57, VW - list_x - 8, 52)
				if box.has_point(p) and map_index != i:
					map_index = i
					audio.sfx_select()
					return
		Screen.FINALE:
			for i in 3:
				var row := Rect2(34, 135 + i * 30, VW - 68, 27)
				if row.has_point(p) and finale_index != i:
					finale_index = i
					audio.sfx_select()
					return
		Screen.MISSION:
			if mission != null:
				mission.set_mouse_virtual_pos(p)


func _handle_click(pos: Vector2) -> void:
	var p := _to_virtual_pos(pos)
	match screen:
		Screen.TITLE:
			_go(Screen.STATION)
			audio.sfx_blip()
		Screen.STATION:
			for i in state.upgrade_defs.size():
				var row := Rect2(186, 52 + i * 33, 182, 30)
				if row.has_point(p):
					station_index = i
					_station_activate(_station_options())
					return
			var depart := Rect2(8, 196, VW - 16, 22)
			if depart.has_point(p):
				station_index = state.upgrade_defs.size()
				_station_activate(_station_options())
				return
			var archive_box := Rect2(378, 34, 94, 46)
			if archive_box.has_point(p):
				_open_logs()
		Screen.MAP:
			var list_x: float = 196.0
			for i in 3:
				var box := Rect2(list_x, 30 + i * 57, VW - list_x - 8, 52)
				if box.has_point(p):
					map_index = i
					_start_mission()
					return
			var earth_c := Vector2(84, 136)
			for i in 3:
				var ang: float = -0.9 + float(i) * 0.75
				var rx2: float = 80.0 + i * 52.0
				var ry2: float = 30.0 + i * 20.0
				var marker: Vector2 = earth_c + Vector2(cos(ang) * rx2, sin(ang) * ry2 * 0.55)
				if p.distance_to(marker) <= 14.0:
					if map_index == i:
						_start_mission()
					else:
						map_index = i
						audio.sfx_select()
					return
			if state.finale_available() and Rect2(VW - 190, VH - 26, 182, 20).has_point(p):
				audio.sfx_blip()
				_go(Screen.FINALE)
		Screen.MISSION:
			if mission == null:
				return
			mission.set_mouse_virtual_pos(p)
			if paused:
				var box := Rect2(VW * 0.5 - 96, VH * 0.5 - 34, 192, 68)
				if Rect2(box.position.x, box.position.y + 20, box.size.x, 14).has_point(p):
					paused = false
					audio.sfx_blip()
				elif Rect2(box.position.x, box.position.y + 34, box.size.x, 14).has_point(p):
					mission = null
					_go(Screen.MAP)
				elif Rect2(box.position.x, box.position.y + 46, box.size.x, 14).has_point(p):
					var muted: bool = audio.toggle_muted()
					_notify("AUDIO MUTED" if muted else "AUDIO ON", Pal.MID)
				return
			if p.y >= VH - 26.0 and (mission.ship.disabled or mission.can_dock()):
				_mission_key(KEY_E)
		Screen.REPORT:
			if Rect2(VW * 0.5 - 80, VH - 32, 75, 16).has_point(p):
				_open_logs()
			else:
				_report_key(KEY_ENTER)
		Screen.FINALE:
			for i in 3:
				var row := Rect2(34, 135 + i * 30, VW - 68, 27)
				if row.has_point(p):
					finale_index = i
					_finale_key(KEY_ENTER)
					return
		Screen.ENDING:
			_ending_key(KEY_ENTER)
		Screen.LOGS:
			var list_box := Rect2(8, 26, 148, VH - 44)
			if list_box.has_point(p) and not shown_logs.is_empty():
				var visible_rows := 21
				var first: int = clampi(logs_index - visible_rows / 2, 0, maxi(0, shown_logs.size() - visible_rows))
				var row_idx: int = first + int((p.y - (list_box.position.y + 3.0)) / 10.0)
				if row_idx >= 0 and row_idx < shown_logs.size():
					logs_index = row_idx
					audio.sfx_select()
			elif p.y >= VH - 20.0:
				_logs_key(KEY_ESCAPE)


func _handle_right_click(pos: Vector2) -> void:
	var p := _to_virtual_pos(pos)
	match screen:
		Screen.STATION:
			_station_key(KEY_ESCAPE)
		Screen.MAP:
			_map_key(KEY_ESCAPE)
		Screen.MISSION:
			if mission != null:
				mission.set_mouse_virtual_pos(p)
				if paused:
					paused = false
					audio.sfx_back()
		Screen.REPORT:
			_report_key(KEY_ESCAPE)
		Screen.FINALE:
			_finale_key(KEY_ESCAPE)
		Screen.LOGS:
			_logs_key(KEY_ESCAPE)


func _handle_wheel(dir: int) -> void:
	var key := KEY_DOWN if dir > 0 else KEY_UP
	match screen:
		Screen.STATION:
			_station_key(key)
		Screen.MAP:
			_map_key(key)
		Screen.FINALE:
			_finale_key(key)
		Screen.LOGS:
			_logs_key(key)


func _notify(msg: String, color: Color = Pal.PAPER) -> void:
	toast = msg
	toast_color = color
	toast_timer = 2.6


func _go(next: int) -> void:
	previous_screen = screen
	screen = next
	blink = 0.0
	paused = false
	if next == Screen.MAP:
		map_index = clampf(map_index, 0, 2)
	elif next == Screen.MISSION:
		_paused_audio_off()


# ---------------------------------------------------------------- title

func _title_key(key: int) -> void:
	if key == KEY_ENTER or key == KEY_SPACE or key == KEY_KP_ENTER:
		audio.sfx_blip()
		_go(Screen.STATION)
	elif key == KEY_ESCAPE:
		get_tree().quit()


# ---------------------------------------------------------------- station

func _station_key(key: int) -> void:
	var options := _station_options()
	if key == KEY_UP or key == KEY_W:
		station_index = (station_index - 1 + options.size() + 1) % (options.size() + 1)
		audio.sfx_select()
	elif key == KEY_DOWN or key == KEY_S:
		station_index = (station_index + 1) % (options.size() + 1)
		audio.sfx_select()
	elif key == KEY_ENTER or key == KEY_SPACE or key == KEY_E:
		_station_activate(options)
	elif key == KEY_ESCAPE:
		_go(Screen.TITLE) if station_index == options.size() else _go(Screen.MAP)
	elif key >= KEY_1 and key <= KEY_4:
		var idx: int = key - KEY_1
		_try_upgrade(idx)
	elif key == KEY_L:
		_open_logs()


func _station_options() -> Array:
	var out: Array = []
	out.append("upgrade_0")
	out.append("upgrade_1")
	out.append("upgrade_2")
	out.append("upgrade_3")
	return out


func _try_upgrade(index: int) -> void:
	if index < 0 or index >= state.upgrade_defs.size():
		return
	if state.upgrade_level(index) >= 3:
		audio.sfx_denied()
		_notify("ALREADY AT MAX SPEC", Pal.MID)
		return
	if not state.can_upgrade(index):
		audio.sfx_denied()
		_notify("INSUFFICIENT BUDGET", Pal.ORANGE)
		return
	var def: Dictionary = state.upgrade_defs[index] as Dictionary
	if state.buy_upgrade(index):
		audio.sfx_chime()
		_notify("%s INSTALLED - MK %d" % [String(def.get("name", "")), state.upgrade_level(index)], Pal.CYAN)


func _station_activate(options: Array) -> void:
	audio.sfx_blip()
	if station_index == options.size():
		_go(Screen.MAP)
		return
	_try_upgrade(station_index)


# ---------------------------------------------------------------- map

func _map_key(key: int) -> void:
	if key == KEY_UP or key == KEY_W:
		map_index = (map_index - 1 + 3) % 3
		audio.sfx_select()
	elif key == KEY_DOWN or key == KEY_S:
		map_index = (map_index + 1) % 3
		audio.sfx_select()
	elif key == KEY_ENTER or key == KEY_SPACE:
		_start_mission()
	elif key == KEY_ESCAPE:
		audio.sfx_back()
		_go(Screen.STATION)
	elif key == KEY_L:
		_open_logs()
	elif key == KEY_F and state.finale_available():
		audio.sfx_blip()
		_go(Screen.FINALE)


func _start_mission() -> void:
	if not state.is_unlocked(map_index):
		audio.sfx_denied()
		_notify("SECTOR LOCKED - CLEAR PRIOR QUOTA", Pal.ORANGE)
		return
	audio.sfx_blip()
	mission = Mission.new()
	mission.setup(state, skin, audio, map_index)
	_last_mission_logs = []
	_go(Screen.MISSION)


# ---------------------------------------------------------------- mission

func _mission_key(key: int) -> void:
	if mission == null:
		return
	if key == KEY_ESCAPE:
		paused = not paused
		audio.sfx_back()
		return
	if paused:
		if key == KEY_ENTER or key == KEY_SPACE:
			paused = false
		elif key == KEY_Q:
			mission = null
			_go(Screen.MAP)
		return
	if key == KEY_E:
		if mission.ship.disabled:
			_complete_mission(mission.distress_tow())
		elif mission.can_dock():
			_complete_mission(mission.dock())
		else:
			audio.sfx_denied()
	elif key == KEY_L:
		_open_logs()


func _complete_mission(result: Dictionary) -> void:
	report = result
	_last_mission_logs = mission.log_queue.duplicate()
	audio.sfx_dock()
	_go(Screen.REPORT)
	mission = null


# ---------------------------------------------------------------- report

func _report_key(key: int) -> void:
	if key == KEY_ENTER or key == KEY_SPACE or key == KEY_E:
		audio.sfx_blip()
		if state.finale_available():
			_go(Screen.FINALE)
		else:
			_go(Screen.MAP)
	elif key == KEY_L:
		_open_logs()
	elif key == KEY_ESCAPE:
		audio.sfx_back()
		_go(Screen.MAP)


# ---------------------------------------------------------------- finale

func _finale_options() -> Array:
	return ["plastic_snow", "endless_loop", "last_specimen"]


func _finale_key(key: int) -> void:
	var opts := _finale_options()
	if key == KEY_UP or key == KEY_W:
		finale_index = (finale_index - 1 + opts.size()) % opts.size()
		audio.sfx_select()
	elif key == KEY_DOWN or key == KEY_S:
		finale_index = (finale_index + 1) % opts.size()
		audio.sfx_select()
	elif key == KEY_ENTER or key == KEY_SPACE:
		var pick := String(opts[finale_index])
		if pick == "last_specimen" and not state.specimen_secured:
			audio.sfx_denied()
			_notify("NO SPECIMEN SECURED - RETURN TO K-9", Pal.ORANGE)
			return
		_choose_ending(pick)
	elif key == KEY_ESCAPE:
		audio.sfx_back()
		_go(Screen.MAP)
	elif key == KEY_L:
		_open_logs()


func _choose_ending(pick: String) -> void:
	ending_key = pick
	state.ending = pick
	ending_par_index = 0
	ending_char = 0.0
	if pick == "plastic_snow":
		audio.sfx_laser()
	else:
		audio.sfx_chime()
	_go(Screen.ENDING)


# ---------------------------------------------------------------- logs

func _open_logs() -> void:
	shown_logs = state.found_logs.duplicate()
	if shown_logs.is_empty():
		audio.sfx_denied()
		_notify("NO LOGS IN THE ARCHIVE YET", Pal.MID)
		return
	audio.sfx_blip()
	logs_index = clampi(logs_index, 0, shown_logs.size() - 1)
	previous_screen = screen
	screen = Screen.LOGS


func _logs_key(key: int) -> void:
	if shown_logs.is_empty():
		screen = previous_screen
		return
	if key == KEY_UP or key == KEY_W:
		logs_index = (logs_index - 1 + shown_logs.size()) % shown_logs.size()
		audio.sfx_select()
	elif key == KEY_DOWN or key == KEY_S:
		logs_index = (logs_index + 1) % shown_logs.size()
		audio.sfx_select()
	elif key == KEY_ESCAPE or key == KEY_L:
		audio.sfx_back()
		screen = previous_screen


# ---------------------------------------------------------------- ending

func _ending_key(key: int) -> void:
	# First press fast-forwards the typewriter, second starts a new shift.
	if key == KEY_ENTER or key == KEY_SPACE:
		if int(ending_char) < _ending_total_chars():
			ending_char = float(_ending_total_chars())
			audio.sfx_select()
		else:
			audio.sfx_back()
			state.reset()
			_go(Screen.TITLE)
	elif key == KEY_ESCAPE:
		audio.sfx_back()
		state.reset()
		_go(Screen.TITLE)


func _ending_paragraphs() -> Array:
	var data: Dictionary = (state.endings.get(ending_key, {}) as Dictionary)
	return data.get("paragraphs", []) as Array


# ---------------------------------------------------------------- process

func _process(delta: float) -> void:
	time += delta
	blink += delta
	skin.tick(delta)
	if toast_timer > 0.0:
		toast_timer -= delta
	if screen == Screen.ENDING:
		ending_char += delta * 190.0
	if screen == Screen.MISSION and mission != null and not paused:
		mission.update(delta)
	queue_redraw()


func _paused_audio_off() -> void:
	audio.set_thruster(0.0)
	audio.set_beam(0.0)
	audio.set_warning(false)


# ---------------------------------------------------------------- draw

func _draw() -> void:
	var vp := get_viewport_rect().size
	var scale: float = min(vp.x / VW, vp.y / VH)
	# Prefer whole-number scaling when there is room; keeps pixels uniform.
	if scale >= 2.0:
		scale = floor(scale)
	var origin := ((vp - Vector2(VW, VH) * scale) * 0.5).floor()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(0, 0, vp.x, vp.y), Pal.DEEP, true)

	match screen:
		Screen.TITLE:
			_draw_title(origin, scale)
		Screen.STATION:
			_draw_station(origin, scale)
		Screen.MAP:
			_draw_map(origin, scale)
		Screen.MISSION:
			_draw_mission(origin, scale)
		Screen.REPORT:
			_draw_report(origin, scale)
		Screen.FINALE:
			_draw_finale(origin, scale)
		Screen.ENDING:
			_draw_ending(origin, scale)
		Screen.LOGS:
			_draw_logs(origin, scale)

	# Global toast.
	if toast_timer > 0.0 and screen != Screen.MISSION:
		draw_set_transform(origin, 0.0, Vector2(scale, scale))
		var a: float = clampf(toast_timer, 0.0, 1.0)
		var c := toast_color
		c.a = a
		var w: float = skin.font.text_width(toast) + 12
		skin.panel(self, Rect2(VW * 0.5 - w * 0.5, VH - 24, w, 14), Color(0.043, 0.059, 0.098, 0.9 * a), c)
		skin.text_c(self, VW * 0.5, VH - 20, toast, c)


func _begin(origin: Vector2, scale: float) -> void:
	draw_set_transform(origin, 0.0, Vector2(scale, scale))


func _end() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- title screen

func _draw_title(origin: Vector2, scale: float) -> void:
	_begin(origin, scale)
	skin.starfield(self, Vector2(time * 5.0, 0.0))

	# Earth rises from the bottom edge, dimmed, with a littered ring across it.
	var earth: Texture2D = skin.sprites["earth"]
	var planet_c := Vector2(VW * 0.5, VH + 34.0)
	draw_set_transform(origin + planet_c * scale, 0.0, Vector2(scale * 1.9, scale * 1.9))
	draw_texture_rect(earth, Rect2(-64, -64, 128, 128), false, Color(0.85, 0.9, 1.0, 0.55))
	draw_set_transform(origin, 0.0, Vector2(scale, scale))

	for i in 84:
		var ang: float = float(i) / 84.0 * TAU + 0.4
		var wobble: float = 1.0 + 0.05 * sin(float(i) * 2.7)
		var p := planet_c + Vector2(cos(ang) * 205.0 * wobble, sin(ang) * 40.0 * wobble - 96.0)
		if p.y > VH or p.y < 0:
			continue
		var c: Color = Pal.MID if i % 4 != 0 else Pal.ORANGE
		c.a = 0.5 + 0.28 * sin(time * 1.4 + float(i) * 0.5)
		draw_rect(Rect2(p.floor(), Vector2(1, 1)), c, true)

	# Title block, high contrast against the dark band.
	draw_rect(Rect2(0, 22, VW, 76), Color(0.043, 0.059, 0.098, 0.72), true)
	skin.text_c(self, VW * 0.5, 30, "OPERATION", Pal.MID, 1)
	skin.text_c(self, VW * 0.5, 42, "STARFALL", Pal.CYAN, 3)
	skin.text_c(self, VW * 0.5, 72, "AN ORBITAL SALVAGE SATIRE", Pal.PAPER)
	draw_rect(Rect2(VW * 0.5 - 78, 84, 156, 1), Pal.SHADOW, true)

	var lines := [
		"THE LAST STATION NEEDS DEBRIS COLLECTED.",
		"THE DEBRIS IS EVERYTHING WE EVER ADVERTISED.",
		"THE PLAN TO FIX IT IS PROBABLY WORSE.",
	]
	var y: float = 96
	for l in lines:
		skin.text_c(self, VW * 0.5, y, String(l), Pal.MID)
		y += 10

	var pulse: float = 0.55 + 0.45 * sin(blink * 3.0)
	draw_rect(Rect2(VW * 0.5 - 46, 138, 92, 14), Color(0.043, 0.059, 0.098, 0.8), true)
	skin.text_c(self, VW * 0.5, 142, "PRESS ENTER", Color(Pal.CYAN.r, Pal.CYAN.g, Pal.CYAN.b, pulse))
	skin.text_c(self, VW * 0.5, 164, "A DARK SATIRE. NO REAL SATELLITES WERE HARMED.", Pal.SHADOW.lightened(0.35))

	# Control legend on a solid strip so it never sits on the planet.
	draw_rect(Rect2(0, VH - 30, VW, 30), Color(0.043, 0.059, 0.098, 0.92), true)
	draw_rect(Rect2(0, VH - 30, VW, 1), Pal.SHADOW, true)
	skin.text_c(self, VW * 0.5, VH - 24, "WASD MOVE     SPACE TRACTOR     E DOCK", Pal.PAPER)
	skin.text_c(self, VW * 0.5, VH - 12, "L LOGS     M MUTE     ESC BACK", Pal.MID)
	skin.scanlines(self, 0.06)
	skin.vignette(self)
	_end()


# ---------------------------------------------------------------- station screen

func _draw_station(origin: Vector2, scale: float) -> void:
	_begin(origin, scale)
	draw_rect(Rect2(0, 0, VW, VH), Pal.DEEP, true)
	# Dilapidated station view: big hull panel, flickering lights.
	var station_tex: Texture2D = skin.sprites["station"]
	# Flickering emergency strip along the very top edge, above the panels.
	for i in 12:
		var lx: float = 6 + i * 39.0
		var on: bool = sin(time * (1.6 + i * 0.31) + i) > -0.45
		var lc: Color = Pal.CYAN if on else Pal.SHADOW.darkened(0.4)
		lc.a = 0.5
		draw_rect(Rect2(lx, 23, 22, 1), lc, true)

	# Header.
	draw_rect(Rect2(0, 0, VW, 26), Pal.NIGHT, true)
	draw_rect(Rect2(0, 26, VW, 1), Pal.SHADOW, true)
	skin.text(self, Vector2(8, 6), "THE LAST SPACE STATION", Pal.CYAN)
	skin.text(self, Vector2(8, 15), "SALVAGE OPERATIONS CONSOLE - SHIFT 214", Pal.MID)
	skin.text_r(self, VW - 8, 6, "BUDGET", Pal.MID)
	skin.text_r(self, VW - 8, 15, "%d CR" % int(round(state.budget)), Pal.GOLD)
	# Station badge, in the gap between the title and the budget block.
	draw_set_transform(origin + Vector2(330, 13) * scale, 0.0, Vector2(scale * 0.32, scale * 0.32))
	draw_texture_rect(station_tex, Rect2(-48, -32, 96, 64), false)
	draw_set_transform(origin, 0.0, Vector2(scale, scale))

	# Left: resources.
	var panel_l := Rect2(8, 34, 168, 154)
	skin.panel(self, panel_l, Pal.NIGHT, Pal.SHADOW, true)
	skin.text(self, panel_l.position + Vector2(6, 5), "STATION STATUS", Pal.CYAN)
	var stats: Dictionary = state.ship_stats()
	var y: float = panel_l.position.y + 18
	var rows := [
		["FUEL TANK", float(stats["fuel"]), float(stats["fuel"]), Pal.CYAN, "%d" % int(stats["fuel"])],
		["POWER CELL", float(stats["power"]), float(stats["power"]), Pal.CYAN, "%d" % int(stats["power"])],
		["CARGO HOLD", float(stats["storage"]), 90.0, Pal.CYAN, "%d t" % int(stats["storage"])],
		["TRACTOR R", float(stats["beam_radius"]), 130.0, Pal.CYAN, "%d m" % int(stats["beam_radius"])],
	]
	for row in rows:
		skin.text(self, Vector2(panel_l.position.x + 6, y), String(row[0]), Pal.MID)
		skin.bar(self, Vector2(panel_l.position.x + 6, y + 9), Vector2(110, 4), float(row[1]) / maxf(1.0, float(row[2])), row[3] as Color)
		skin.text_r(self, panel_l.end.x - 6, y, String(row[4]), Pal.PAPER)
		y += 20

	y += 4
	var fw: float = panel_l.size.x - 12
	skin.text(self, Vector2(panel_l.position.x + 6, y), skin.font.fit("PERSONNEL 1/9 ACTIVE", fw), Pal.MID)
	skin.text(self, Vector2(panel_l.position.x + 6, y + 10), "LIFE SUPPORT NOMINAL-ISH", Pal.MID)
	skin.text(self, Vector2(panel_l.position.x + 6, y + 20), "MORALE: AUTOMATED", Pal.MID)

	# Center: upgrades.
	var panel_c := Rect2(182, 34, 190, 154)
	skin.panel(self, panel_c, Pal.NIGHT, Pal.SHADOW, true)
	skin.text(self, panel_c.position + Vector2(6, 5), "SHIP UPGRADES", Pal.CYAN)
	var uy: float = panel_c.position.y + 18
	for i in state.upgrade_defs.size():
		var def: Dictionary = state.upgrade_defs[i] as Dictionary
		var lvl: int = state.upgrade_level(i)
		var cost: int = state.upgrade_cost(i)
		var focused: bool = station_index == i
		var row := Rect2(panel_c.position.x + 4, uy, panel_c.size.x - 8, 30)
		if focused:
			skin.rect(self, row, Pal.SHADOW)
			skin.frame(self, row, Pal.CYAN)
		skin.text(self, Vector2(row.position.x + 4, row.position.y + 4), "%d %s" % [i + 1, String(def.get("name", ""))], Pal.PAPER)
		# Pips.
		for p in 3:
			var pc: Color = Pal.CYAN if p < lvl else Pal.SHADOW
			draw_rect(Rect2(row.position.x + 4 + p * 6, row.position.y + 14, 4, 4), pc, true)
		var cost_txt := "MAX" if cost < 0 else ("%d CR" % cost)
		var cost_col: Color = Pal.GOLD if cost >= 0 and state.budget >= cost else (Pal.MID if cost >= 0 else Pal.CYAN_DIM)
		skin.text_r(self, row.end.x - 4, row.position.y + 4, cost_txt, cost_col)
		skin.text(self, Vector2(row.position.x + 4, row.position.y + 21), skin.font.fit(String(def.get("desc", "")), row.size.x - 8), Pal.MID)
		uy += 33

	# Right: archive + quota + depart.
	var panel_r := Rect2(378, 34, 94, 154)
	skin.panel(self, panel_r, Pal.NIGHT, Pal.SHADOW, true)
	skin.text(self, panel_r.position + Vector2(6, 5), "ARCHIVE", Pal.CYAN)
	skin.text(self, panel_r.position + Vector2(6, 18), "%d / %d LOGS" % [state.log_count(), state.logs.size()], Pal.PAPER)
	skin.bar(self, panel_r.position + Vector2(6, 28), Vector2(80, 4), float(state.log_count()) / maxf(1.0, float(state.logs.size())), Pal.GOLD)
	skin.text(self, panel_r.position + Vector2(6, 40), "SECTORS", Pal.MID)
	for i in 3:
		var cleared: bool = state.is_cleared(i)
		var s: Dictionary = state.sector(i)
		var col: Color = Pal.GREEN if cleared else (Pal.ORANGE if state.is_unlocked(i) else Pal.SHADOW)
		var mark := "OK" if cleared else ("--" if not state.is_unlocked(i) else "OPEN")
		skin.text(self, panel_r.position + Vector2(6, 52 + i * 10), "%s %s" % [String(s.get("designation", "")).substr(7, 3), mark], col)
	skin.text(self, panel_r.position + Vector2(6, 90), "PROTOCOL", Pal.MID)
	var proto := "LOCKED"
	var pcol := Pal.SHADOW
	if state.finale_available():
		proto = "READY"
		pcol = Pal.ORANGE
	elif state.is_cleared(2):
		proto = "ARMED"
		pcol = Pal.ORANGE
	skin.text(self, panel_r.position + Vector2(6, 100), proto, pcol)

	# Depart button.
	var depart := Rect2(8, 196, VW - 16, 22)
	var dep_focus: bool = station_index == state.upgrade_defs.size()
	skin.button(self, depart, "OPEN ORBITAL MAP   [ENTER]", dep_focus, true)
	skin.text_c(self, VW * 0.5, 226, "ARROWS SELECT   ENTER CONFIRM   1-4 BUY   L LOGS   M MUTE", Pal.MID)

	# PA ticker at the bottom.
	var idle: Array = state.pa.get("station_idle", []) as Array
	if not idle.is_empty():
		var idx: int = int(time / 7.0) % idle.size()
		draw_rect(Rect2(0, VH - 16, VW, 12), Pal.NIGHT, true)
		skin.text(self, Vector2(6, VH - 13), "PA:", Pal.CYAN)
		skin.text(self, Vector2(24, VH - 13), String(idle[idx]), Pal.PAPER)

	skin.scanlines(self, 0.06)
	skin.vignette(self)
	_end()


# ---------------------------------------------------------------- orbital map

func _draw_map(origin: Vector2, scale: float) -> void:
	_begin(origin, scale)
	skin.starfield(self, Vector2(time * 4.0, time * 1.5))
	# Header.
	draw_rect(Rect2(0, 0, VW, 22), Pal.NIGHT, true)
	draw_rect(Rect2(0, 22, VW, 1), Pal.SHADOW, true)
	skin.text(self, Vector2(8, 4), "ORBITAL SALVAGE MAP", Pal.CYAN)
	skin.text(self, Vector2(8, 13), "SELECT A SECTOR. FUEL IS YOUR RESPONSIBILITY.", Pal.MID)
	skin.text_r(self, VW - 8, 4, "BUDGET %d CR" % int(state.budget), Pal.GOLD)
	skin.text_r(self, VW - 8, 13, "LOGS %d/%d" % [state.log_count(), state.logs.size()], Pal.MID)

	# Map graphic: Earth at left, 3 orbit arcs.
	var earth_c := Vector2(84, 136)
	draw_set_transform(origin, 0.0, Vector2(scale, scale))
	var earth: Texture2D = skin.sprites["earth"]
	draw_texture_rect(earth, Rect2(earth_c - Vector2(32, 32), Vector2(64, 64)), false, Color(1, 1, 1, 0.85))
	for i in 3:
		var rx: float = 80.0 + i * 52.0
		var ry: float = 30.0 + i * 20.0
		var arc_col: Color = Pal.SHADOW if not state.is_unlocked(i) else (Pal.GREEN if state.is_cleared(i) else Pal.CYAN_DIM)
		arc_col.a = 0.8
		var steps := 46
		for k in steps:
			var t: float = float(k) / float(steps)
			var ang: float = -1.15 + t * 2.3
			draw_rect(Rect2((earth_c + Vector2(cos(ang) * rx, sin(ang) * ry * 0.55)).floor(), Vector2(1, 1)), arc_col, true)

	# Sector markers.
	for i in 3:
		var ang: float = -0.9 + float(i) * 0.75
		var rx2: float = 80.0 + i * 52.0
		var ry2: float = 30.0 + i * 20.0
		var p: Vector2 = earth_c + Vector2(cos(ang) * rx2, sin(ang) * ry2 * 0.55)
		var col: Color = Pal.SHADOW
		if state.is_unlocked(i):
			col = Pal.GREEN if state.is_cleared(i) else Pal.CYAN
		if i == map_index:
			var ring: Color = Pal.CYAN
			ring.a = 0.55 + 0.4 * sin(blink * 4.0)
			for k in 24:
				var a2: float = float(k) / 24.0 * TAU
				draw_rect(Rect2((p + Vector2(cos(a2), sin(a2)) * 9.0).floor(), Vector2(1, 1)), ring, true)
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), col, true)
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), Pal.DEEP, true)

	# Sector list on the right.
	var list_x: float = 196.0
	for i in 3:
		var s: Dictionary = state.sector(i)
		var unlocked: bool = state.is_unlocked(i)
		var cleared: bool = state.is_cleared(i)
		var box := Rect2(list_x, 30 + i * 57, VW - list_x - 8, 52)
		var focused: bool = i == map_index
		skin.panel(self, box, Pal.SHADOW if focused else Pal.NIGHT, Pal.CYAN if focused else Pal.SHADOW, focused)
		skin.text(self, box.position + Vector2(6, 4), skin.font.fit("ACT %s - %s" % [["I", "II", "III"][i], String(s.get("tagline", ""))], box.size.x - 86), Pal.MID)
		skin.text(self, box.position + Vector2(6, 14), String(s.get("name", "")), Pal.PAPER)
		var haze: String = String(s.get("hazard", ""))
		var hcol: Color = Pal.GREEN if haze == "LOW" else (Pal.ORANGE if haze == "MEDIUM" else Pal.RED)
		skin.text_r(self, box.end.x - 6, box.position.y + 4, "HAZARD " + haze, hcol)
		skin.text(self, box.position + Vector2(6, 24), "DIST %s   QUOTA %d CR" % [String(s.get("distance", "")), int(state.sector_quota(i))], Pal.MID)
		# Quota bar.
		var prog: float = state.quota_progress(i)
		skin.bar(self, box.position + Vector2(6, 33), Vector2(box.size.x - 70, 5), prog, Pal.GREEN if cleared else Pal.CYAN)
		skin.text_r(self, box.end.x - 6, box.position.y + 33, "%d/%d" % [int(state.sector_banked(i)), int(state.sector_quota(i))], Pal.PAPER)
		var status := "LOCKED"
		var scol: Color = Pal.SHADOW
		if cleared:
			status = "CLEARED"
			scol = Pal.GREEN
		elif unlocked:
			status = "AVAILABLE"
			scol = Pal.CYAN
		skin.text(self, box.position + Vector2(6, 42), status, scol)
		if focused and unlocked:
			skin.text_r(self, box.end.x - 6, box.position.y + 42, "ENTER LAUNCH", Pal.PAPER)

	# Footer.
	var foot := Rect2(8, VH - 26, VW - 16, 20)
	skin.panel(self, foot, Pal.NIGHT, Pal.SHADOW)
	var hint := "UP/DOWN SELECT   ENTER LAUNCH   ESC STATION   L LOGS"
	skin.text(self, foot.position + Vector2(6, 6), hint, Pal.MID)
	if state.finale_available():
		var fc: Color = Pal.ORANGE
		fc.a = 0.6 + 0.4 * sin(blink * 3.0)
		skin.text_r(self, foot.end.x - 6, foot.position.y + 6, "F  PROTOCOL STARFALL READY", fc)

	skin.scanlines(self, 0.05)
	skin.vignette(self)
	_end()


# ---------------------------------------------------------------- mission

func _draw_mission(origin: Vector2, scale: float) -> void:
	if mission == null:
		return
	mission.draw(self, skin, origin, scale)
	if paused:
		draw_set_transform(origin, 0.0, Vector2(scale, scale))
		draw_rect(Rect2(0, 0, VW, VH), Color(0.043, 0.059, 0.098, 0.82), true)
		var box := Rect2(VW * 0.5 - 96, VH * 0.5 - 34, 192, 68)
		skin.panel(self, box, Pal.NIGHT, Pal.CYAN, true)
		skin.text_c(self, VW * 0.5, box.position.y + 8, "SHIFT SUSPENDED", Pal.CYAN)
		skin.text_c(self, VW * 0.5, box.position.y + 24, "ESC OR ENTER   RESUME", Pal.PAPER)
		skin.text_c(self, VW * 0.5, box.position.y + 36, "Q   ABANDON SORTIE (NO PAY)", Pal.ORANGE)
		skin.text_c(self, VW * 0.5, box.position.y + 48, "M   MUTE AUDIO", Pal.MID)
		_end()


# ---------------------------------------------------------------- report

func _draw_report(origin: Vector2, scale: float) -> void:
	_begin(origin, scale)
	draw_rect(Rect2(0, 0, VW, VH), Pal.DEEP, true)
	skin.starfield(self, Vector2(0, time * 3.0))
	var panel_r := Rect2(40, 14, VW - 80, VH - 30)
	skin.panel(self, panel_r, Pal.NIGHT, Pal.SHADOW, true)
	draw_rect(Rect2(panel_r.position, Vector2(panel_r.size.x, 1)), Pal.CYAN, true)
	skin.text(self, panel_r.position + Vector2(10, 8), "SORTIE REPORT", Pal.CYAN)
	var desig := String(report.get("sector_designation", ""))
	var sname := String(report.get("sector_name", ""))
	skin.text_r(self, panel_r.end.x - 10, panel_r.position.y + 8, "%s - %s" % [desig, sname], Pal.MID)

	var y: float = panel_r.position.y + 26
	var col_l: float = panel_r.position.x + 12
	var col_r: float = panel_r.end.x - 12

	# Left column: numbers.
	skin.text(self, Vector2(col_l, y), "ITEMS RECOVERED", Pal.MID)
	skin.text_r(self, col_r, y, "%d" % int(report.get("collected", 0)), Pal.PAPER)
	y += 12
	skin.text(self, Vector2(col_l, y), "PAYLOAD MASS", Pal.MID)
	skin.text_r(self, col_r, y, "%.1f t" % float(report.get("mass", 0.0)), Pal.PAPER)
	y += 12
	skin.text(self, Vector2(col_l, y), "MATERIAL VALUE", Pal.MID)
	skin.text_r(self, col_r, y, "%d CR" % int(round(float(report.get("value", 0.0)) + float(report.get("fee", 0.0)))), Pal.GOLD)
	if float(report.get("fee", 0.0)) > 0.0:
		y += 12
		skin.text(self, Vector2(col_l, y), "DISTRESS TOW FEE", Pal.ORANGE)
		skin.text_r(self, col_r, y, "-%d CR" % int(round(float(report.get("fee", 0.0)))), Pal.ORANGE)
	y += 12
	skin.text(self, Vector2(col_l, y), "BANKED", Pal.MID)
	skin.text_r(self, col_r, y, "%d CR" % int(round(float(report.get("value", 0.0)))), Pal.PAPER)
	if float(report.get("bonus", 0.0)) > 0.0:
		y += 12
		skin.text(self, Vector2(col_l, y), "QUOTA BONUS", Pal.GREEN)
		skin.text_r(self, col_r, y, "+%d CR" % int(round(float(report.get("bonus", 0.0)))), Pal.GREEN)
	y += 12
	skin.text(self, Vector2(col_l, y), "BUDGET NOW", Pal.MID)
	skin.text_r(self, col_r, y, "%d CR" % int(round(state.budget)), Pal.GOLD)

	# Quota bar.
	y += 18
	var quota: float = float(report.get("quota", 1.0))
	var banked: float = float(report.get("banked", 0.0))
	skin.text(self, Vector2(col_l, y), "SECTOR QUOTA", Pal.MID)
	skin.text_r(self, col_r, y, "%d / %d" % [int(banked), int(quota)], Pal.PAPER)
	skin.bar(self, Vector2(col_l, y + 10), Vector2(panel_r.size.x - 24, 7), clampf(banked / maxf(1.0, quota), 0.0, 1.0), Pal.GREEN if banked >= quota else Pal.CYAN)

	# Haul manifest, itemised the way the station insists on itemising it.
	y += 24
	skin.text(self, Vector2(col_l, y), "MANIFEST", Pal.CYAN)
	y += 12
	var haul: Dictionary = report.get("haul", {}) as Dictionary
	if haul.is_empty():
		skin.text(self, Vector2(col_l, y), "NO MATERIAL OF RECORD.", Pal.MID)
		y += 11
	else:
		var order: Array = ["scrap", "panel", "packaging", "billboard", "satellite", "trophy", "specimen"]
		for kind in order:
			if not haul.has(kind):
				continue
			var data: Dictionary = state.debris_types.get(kind, {}) as Dictionary
			var count := int(haul[kind])
			skin.text(self, Vector2(col_l, y), "%dX  %s" % [count, String(data.get("name", kind))], Pal.PAPER)
			skin.text_r(self, col_r, y, "%d CR" % int(round(float(data.get("value", 0.0)) * count)), Pal.GOLD)
			y += 10
	y += 4
	skin.text(self, Vector2(col_l, y), "FINDINGS", Pal.CYAN)
	y += 12
	if bool(report.get("towed", false)):
		skin.wrap(self, Vector2(col_l, y), panel_r.size.x - 24, "TOWED BACK BY REMOTE. THE FEE WAS DEDUCTED FROM YOUR MATERIAL VALUE. THE STATION CALLS THIS A NOMINAL OUTCOME.", Pal.ORANGE, 1, 2)
		y += 18
	if bool(report.get("specimen", false)):
		skin.wrap(self, Vector2(col_l, y), panel_r.size.x - 24, "SEALED RESEARCH POD IS IN THE HOLD. MANIFEST CLASSIFICATION: NON-ESSENTIAL CARGO.", Pal.GREEN, 1, 2)
		y += 18
	var logs_new: Array = _last_mission_logs
	if not logs_new.is_empty():
		skin.wrap(self, Vector2(col_l, y), panel_r.size.x - 24, "%d NEW LOG(S) ARCHIVED. PRESS L TO READ." % logs_new.size(), Pal.GOLD, 1, 1)
		y += 12
	y += 4
	var report_line := String(report.get("report_line", ""))
	skin.wrap(self, Vector2(col_l, y), panel_r.size.x - 24, report_line, Pal.PAPER, 1, 3)

	# Continue.
	var pulse: float = 0.55 + 0.45 * sin(blink * 3.0)
	var cont := "ENTER   CONTINUE"
	if state.finale_available():
		cont = "ENTER   PROTOCOL STARFALL BRIEFING"
	draw_rect(Rect2(panel_r.position.x + 2, panel_r.end.y - 27, panel_r.size.x - 4, 25), Color(0.043, 0.059, 0.098, 0.9), true)
	draw_rect(Rect2(panel_r.position.x + 10, panel_r.end.y - 27, panel_r.size.x - 20, 1), Pal.SHADOW, true)
	skin.text_c(self, VW * 0.5, panel_r.end.y - 22, cont, Color(Pal.CYAN.r, Pal.CYAN.g, Pal.CYAN.b, pulse))
	skin.text_c(self, VW * 0.5, panel_r.end.y - 11, "L  ARCHIVE        ESC  MAP", Pal.MID)
	skin.scanlines(self, 0.05)
	_end()


# ---------------------------------------------------------------- finale

func _draw_finale(origin: Vector2, scale: float) -> void:
	_begin(origin, scale)
	skin.starfield(self, Vector2(0, time * 2.0))
	# The planet, now visibly dimmed by the ring.
	var earth: Texture2D = skin.sprites["earth"]
	draw_set_transform(origin + Vector2(VW * 0.5, VH * 0.5 + 96) * scale, 0.0, Vector2(scale * 1.4, scale * 1.4))
	draw_texture_rect(earth, Rect2(-44, -28, 88, 88), false, Color(0.72, 0.78, 0.88, 0.9))
	draw_set_transform(origin, 0.0, Vector2(scale, scale))
	# Ring.
	for i in 90:
		var ang: float = float(i) / 90.0 * TAU
		var p := Vector2(VW * 0.5, VH * 0.5 + 96) + Vector2(cos(ang) * 214.0, sin(ang) * 42.0)
		var c: Color = Pal.MID if i % 4 != 0 else Pal.ORANGE
		c.a = 0.55 + 0.35 * sin(time * 2.0 + i * 0.3)
		draw_rect(Rect2(p.floor(), Vector2(1, 1)), c, true)

	draw_rect(Rect2(0, 0, VW, VH), Color(0.043, 0.059, 0.098, 0.55), true)

	var box := Rect2(24, 14, VW - 48, VH - 40)
	skin.panel(self, box, Color(0.086, 0.106, 0.180, 0.96), Pal.ORANGE, true)
	skin.text(self, box.position + Vector2(10, 8), "PROTOCOL STARFALL - OPERATOR DECISION", Pal.ORANGE)
	skin.text_r(self, box.end.x - 10, box.position.y + 8, "CLEARANCE: PENDING YOU", Pal.MID)
	draw_rect(Rect2(box.position.x + 2, box.position.y + 20, box.size.x - 4, 1), Pal.SHADOW, true)

	var txt := "THE LASER CLEARS THE ORBIT IN NINETY-ONE SECONDS. THE TECHNICAL SCAN ATTACHED TO IT DISAGREES WITH THE PRESS RELEASE."
	skin.wrap(self, box.position + Vector2(10, 26), box.size.x - 20, txt, Pal.PAPER, 1, 4)

	# Two documents, side by side, so the contradiction is the composition.
	var dcol := Color(0.043, 0.059, 0.098, 0.9)
	var doc_y: float = box.position.y + 68.0
	var doc_l := Rect2(box.position.x + 10, doc_y, (box.size.x - 30) * 0.5, 46)
	var doc_r := Rect2(doc_l.end.x + 10, doc_y, doc_l.size.x, 46)
	skin.panel(self, doc_l, dcol, Pal.CYAN)
	skin.text(self, doc_l.position + Vector2(5, 4), "MARKETING DOCUMENT", Pal.CYAN)
	skin.wrap(self, doc_l.position + Vector2(5, 14), doc_l.size.x - 10, "CLEAN SKIES. ORBIT CLEAR. A 100% CLEARANCE EVENT.", Pal.PAPER, 1, 3)
	skin.panel(self, doc_r, dcol, Pal.RED)
	skin.text(self, doc_r.position + Vector2(5, 4), "ENGINEERING ATTACHMENT 4", Pal.RED)
	skin.wrap(self, doc_r.position + Vector2(5, 14), doc_r.size.x - 10, "PARTICULATE DISPERSAL. ATMOSPHERIC DEPOSITION: UNAVOIDABLE.", Pal.PAPER, 1, 3)

	# Options.
	var oy: float = doc_l.end.y + 7
	for i in 3:
		var key := String(_finale_options()[i])
		var data: Dictionary = (state.endings.get(key, {}) as Dictionary)
		var row := Rect2(box.position.x + 10, oy, box.size.x - 20, 27)
		var focused: bool = i == finale_index
		var enabled: bool = key != "last_specimen" or state.specimen_secured
		skin.rect(self, row, Pal.SHADOW if focused else Color(0.043, 0.059, 0.098, 0.4))
		skin.frame(self, row, Pal.CYAN if focused else Pal.SHADOW)
		var title := String(data.get("title", ""))
		var tcol: Color = Pal.PAPER if enabled else Pal.MID
		skin.text(self, row.position + Vector2(6, 4), "%d  %s" % [i + 1, title], tcol)
		var desc := ""
		var dcol2 := Pal.MID
		if key == "plastic_snow":
			desc = "FIRE THE LASER. ORBIT CLEARS. THE SKY RECEIVES THE REST."
			dcol2 = Pal.CYAN
		elif key == "endless_loop":
			desc = "KEEP WORKING THE QUOTA. CHANGE NOTHING UPSTREAM."
			dcol2 = Pal.ORANGE
		else:
			if state.specimen_secured:
				desc = "REFUSE THE LASER. PROTECT THE POD. TRANSMIT A LIFECYCLE."
				dcol2 = Pal.GREEN
			else:
				desc = "REQUIRES THE SEALED RESEARCH POD FROM SECTOR K-9."
				dcol2 = Pal.RED
		skin.text(self, row.position + Vector2(6, 15), desc, dcol2)
		oy += 30

	draw_rect(Rect2(box.position.x + 2, box.end.y - 16, box.size.x - 4, 14), Color(0.043, 0.059, 0.098, 0.9), true)
	skin.text_c(self, VW * 0.5, box.end.y - 12, "UP/DOWN SELECT    ENTER DECIDE    ESC BACK TO MAP", Pal.MID)
	skin.scanlines(self, 0.05)
	_end()


# ---------------------------------------------------------------- ending

func _draw_ending(origin: Vector2, scale: float) -> void:
	_begin(origin, scale)
	var data: Dictionary = (state.endings.get(ending_key, {}) as Dictionary)
	var color_name := String(data.get("color", "cyan"))
	var accent: Color = Pal.CYAN
	if color_name == "orange":
		accent = Pal.ORANGE
	elif color_name == "green":
		accent = Pal.GREEN

	# Background varies by ending.
	if ending_key == "plastic_snow":
		draw_rect(Rect2(0, 0, VW, VH), Pal.DEEP, true)
		for i in 120:
			var px: float = fmod(float(i * 61 + int(time * 12.0) * (1 + i % 3)), VW)
			var py: float = fmod(float(i * 37 + int(time * 20.0)), VH)
			var c: Color = Pal.PAPER if i % 5 == 0 else Pal.MID
			c.a = 0.5 + 0.4 * sin(time * 2.0 + i)
			draw_rect(Rect2(Vector2(px, py).floor(), Vector2(1, 1)), c, true)
	elif ending_key == "last_specimen":
		skin.starfield(self, Vector2(0, time * 2.0))
		var green := Color(Pal.GREEN.r, Pal.GREEN.g, Pal.GREEN.b, 0.06)
		for i in 18:
			var gx: float = fmod(float(i * 83), VW)
			var gy: float = fmod(float(i * 47) + time * 4.0, VH)
			draw_rect(Rect2(Vector2(gx, gy).floor(), Vector2(2, 2)), green, true)
	else:
		skin.starfield(self, Vector2(0, time * 1.2))

	var box := Rect2(26, 16, VW - 52, VH - 40)
	skin.panel(self, box, Color(0.086, 0.106, 0.180, 0.94), accent, true)
	skin.text(self, box.position + Vector2(10, 8), String(data.get("tag", "")), accent)
	skin.text_c(self, VW * 0.5, box.position.y + 24, String(data.get("title", "")), accent, 2)
	draw_rect(Rect2(box.position.x + 10, box.position.y + 44, box.size.x - 20, 1), Pal.SHADOW, true)

	# Typewriter body, clipped to leave a footer for the closing beat.
	var paras: Array = _ending_paragraphs()
	var budget_chars: int = int(ending_char)
	var y: float = box.position.y + 52
	var total_w: float = box.size.x - 20
	var body_limit: float = box.end.y - 66
	for p in paras:
		if budget_chars <= 0:
			break
		var text := String(p)
		var visible := text
		if budget_chars < text.length():
			visible = text.substr(0, budget_chars)
		var lines: Array = skin.font.wrap(visible, total_w, 1)
		for line in lines:
			if y > body_limit:
				break
			skin.text(self, Vector2(box.position.x + 10, y), String(line), Pal.PAPER)
			y += 11
			# Cull the remainder of this paragraph if it will not fit.
			if y <= body_limit:
				pass
		y += 4
		budget_chars -= text.length()

	var done: bool = int(ending_char) >= _ending_total_chars()
	if done:
		var foot_y: float = box.end.y - 44
		draw_rect(Rect2(box.position.x + 10, foot_y - 5, box.size.x - 20, 1), Pal.SHADOW, true)
		skin.wrap(self, Vector2(box.position.x + 10, foot_y), total_w, String(data.get("epilogue", "")), accent, 1, 2)
		skin.text(self, Vector2(box.position.x + 10, box.end.y - 22), String(data.get("stat_line", "")), Pal.MID)
		var pulse: float = 0.55 + 0.45 * sin(blink * 3.0)
		skin.text_c(self, VW * 0.5, box.end.y - 12, "ENTER  NEW SHIFT", Color(Pal.CYAN.r, Pal.CYAN.g, Pal.CYAN.b, pulse))
	else:
		skin.text(self, Vector2(box.end.x - 12, box.end.y - 12), "_", Color(accent.r, accent.g, accent.b, 0.4 + 0.6 * sin(blink * 8.0)))

	skin.scanlines(self, 0.05)
	_end()


func _ending_total_chars() -> int:
	var total: int = 0
	for p in _ending_paragraphs():
		total += String(p).length()
	return total


# ---------------------------------------------------------------- logs

func _draw_logs(origin: Vector2, scale: float) -> void:
	_begin(origin, scale)
	draw_rect(Rect2(0, 0, VW, VH), Pal.DEEP, true)
	draw_rect(Rect2(0, 0, VW, 20), Pal.NIGHT, true)
	draw_rect(Rect2(0, 20, VW, 1), Pal.SHADOW, true)
	skin.text(self, Vector2(8, 4), "STATION ARCHIVE - RECOVERED LOGS", Pal.CYAN)
	skin.text_r(self, VW - 8, 4, "%d / %d" % [shown_logs.size(), state.logs.size()], Pal.MID)

	# Index list.
	var list_box := Rect2(8, 26, 148, VH - 44)
	skin.panel(self, list_box, Pal.NIGHT, Pal.SHADOW)
	var visible_rows := 21
	var first: int = clampi(logs_index - visible_rows / 2, 0, maxi(0, shown_logs.size() - visible_rows))
	for row in range(first, mini(shown_logs.size(), first + visible_rows)):
		var log_id := String(shown_logs[row])
		var entry: Dictionary = (state.logs.get(log_id, {}) as Dictionary)
		var yy: float = list_box.position.y + 4 + float(row - first) * 10.0
		var focused: bool = row == logs_index
		if focused:
			skin.rect(self, Rect2(list_box.position.x + 2, yy - 1, list_box.size.x - 4, 10), Pal.SHADOW)
		skin.text(self, Vector2(list_box.position.x + 5, yy), String(entry.get("tag", "")) + " " + String(entry.get("title", "")).substr(0, 12), Pal.CYAN if focused else Pal.MID)

	# Reader.
	var read_box := Rect2(162, 26, VW - 170, VH - 44)
	skin.panel(self, read_box, Color(0.086, 0.106, 0.180, 0.98), Pal.SHADOW, true)
	if logs_index >= 0 and logs_index < shown_logs.size():
		var log_id := String(shown_logs[logs_index])
		var entry: Dictionary = (state.logs.get(log_id, {}) as Dictionary)
		skin.text(self, read_box.position + Vector2(8, 6), String(entry.get("title", "")), Pal.CYAN)
		skin.text(self, read_box.position + Vector2(8, 16), String(entry.get("tag", "")) + " FILE", Pal.MID)
		draw_rect(Rect2(read_box.position.x + 8, read_box.position.y + 26, read_box.size.x - 16, 1), Pal.SHADOW, true)
		skin.wrap(self, read_box.position + Vector2(8, 32), read_box.size.x - 16, String(entry.get("body", "")), Pal.PAPER, 1, 18)

	skin.text(self, Vector2(8, VH - 12), "UP/DOWN SELECT   ESC CLOSE   M MUTE", Pal.MID)
	skin.vignette(self)
	_end()
