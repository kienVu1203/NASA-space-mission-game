extends Node2D
## Phase 4: the escape cinematic. Six scenes and the closing message, drawn
## entirely in-engine from generated sprites and primitives. No external video,
## no missing files, nothing that can fail to load.
##
## The screen owns no campaign state. It reports exactly one outcome through
## `cinematic_finished(skipped)`; the controller applies every flag, checkpoint
## and stage change, so watching and skipping are guaranteed to leave the same
## persistent state.
##
## Scenes reflect what the player actually did. Scene A lights the junction only
## if it was repaired, and lists only memories that were really found. Scene C
## reads its telemetry from the certified simulation of the frozen design, so
## every number on screen is a recorded engineering value, never a random one.
##
## Controls
##   SPACE      pause / resume (pause also freezes subtitles and the scene clock)
##   ESC        skip the rest of the sequence (safe, idempotent, same outcome)
##   ENTER      advance to the next scene, or skip the closing message
##
## Safety: `skip()` and the natural end both call `_finish()` once. Focus loss
## pauses rather than letting the sequence run unseen. Leaving the screen is the
## controller's job (`_go()` frees this node), so no timer here outlives it.

signal cinematic_finished(skipped: bool)

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFFinale := preload("res://core/star_fall/sf_finale.gd")

const VW := 640
const VH := 360

var skin
var ui
var campaign
var finale_data: Dictionary = {}
var reconstruction_data: Dictionary = {}
var scenes: Array = []
var final_message: Dictionary = {}
var report: Dictionary = {}

var scene_index: int = 0
var scene_time: float = 0.0
var elapsed: float = 0.0
var finishing_time: float = 0.0
var paused: bool = false
var finished: bool = false
var skipped: bool = false
var show_final_message: bool = false
var _finish_emitted: bool = false


func setup(skin_ref, ui_ref, campaign_ref, finale: Dictionary, reconstruction: Dictionary) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	finale_data = finale
	reconstruction_data = reconstruction


func _ready() -> void:
	var cinematic: Dictionary = finale_data.get("cinematic", {}) as Dictionary
	scenes = cinematic.get("scenes", []) as Array
	final_message = cinematic.get("final_message", {}) as Dictionary
	report = SFFinale.build_report(campaign, reconstruction_data, finale_data)
	scene_index = 0
	scene_time = 0.0
	elapsed = 0.0
	queue_redraw()


func _notification(what: int) -> void:
	# Losing focus pauses the sequence: it must never play unseen, and it must
	# never leave the player locked in a scene that moved on without them.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if not finished:
			paused = true
			queue_redraw()


# ---------------------------------------------------------------- timing

func current_scene() -> Dictionary:
	if show_final_message or scene_index < 0 or scene_index >= scenes.size():
		return {}
	return scenes[scene_index] as Dictionary


func scene_id() -> String:
	return String(current_scene().get("id", ""))


func scene_duration() -> float:
	if show_final_message:
		return float(final_message.get("duration", 8.0))
	return float(current_scene().get("duration", 10.0))


func is_paused() -> bool:
	return paused and not finished


func is_finished() -> bool:
	return finished


func advance_for(delta: float) -> void:
	if finished or paused:
		return
	scene_time += delta
	elapsed += delta
	if scene_time >= scene_duration():
		_next_scene()


func _next_scene() -> void:
	if show_final_message:
		_finish(false)
		return
	scene_index += 1
	scene_time = 0.0
	if scene_index >= scenes.size():
		show_final_message = true
		scene_time = 0.0
	queue_redraw()


## Skips the rest of the sequence. Idempotent; repeated input is harmless.
func skip() -> void:
	if finished:
		return
	skipped = true
	_finish(true)


func _finish(was_skipped: bool) -> void:
	if _finish_emitted:
		return
	_finish_emitted = true
	finished = true
	paused = false
	skipped = was_skipped
	cinematic_finished.emit(was_skipped)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	handle_key(key.keycode)


func handle_key(keycode: int) -> void:
	if finished:
		return
	match keycode:
		KEY_ESCAPE:
			skip()
		KEY_SPACE:
			paused = not paused
			if paused:
				skin.audio.sfx_back()
			else:
				skin.audio.sfx_select()
			queue_redraw()
		KEY_ENTER, KEY_KP_ENTER, KEY_E:
			# ENTER nudges the sequence along. It never skips a scene outright,
			# so a player cannot lose a beat by mashing confirm.
			if show_final_message:
				_finish(false)
			else:
				scene_time = maxf(scene_time, scene_duration() - 0.01)
			queue_redraw()


func _process(delta: float) -> void:
	advance_for(delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if show_final_message:
		_draw_final_message()
		return
	var scene: Dictionary = current_scene()
	if scene.is_empty():
		draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
		return
	match String(scene.get("visual", "")):
		"crash_site":
			_draw_scene_crash_site()
		"launch":
			_draw_scene_launch()
		"debris":
			_draw_scene_debris()
		"sunlight":
			_draw_scene_sunlight()
		"portal":
			_draw_scene_portal()
		"home":
			_draw_scene_home()
		_:
			draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)

	_draw_scene_header(scene)
	_draw_subtitle(scene)
	if paused:
		_draw_paused()
	skin.vignette(self)


func _draw_scene_header(scene: Dictionary) -> void:
	var title := String(scene.get("name", ""))
	# Scene titles fade in over the first second and stay quiet on screen.
	if scene_time < 1.0:
		return
	draw_rect(Rect2(0, 0, VW, 26), Color(0.02, 0.04, 0.05, 0.72), true)
	skin.text(self, Vector2(14, 8), title, SFPalette.CYAN)
	skin.text_r(self, VW - 14, 8, "%d / %d" % [scene_index + 1, scenes.size()], SFPalette.PAPER_DIM)


## Shows the newest line whose `at` time has passed, with a short fade. Lines are
## data-driven, so subtitle wording and timing never live in this script.
func _draw_subtitle(scene: Dictionary) -> void:
	var lines: Array = scene.get("lines", []) as Array
	var active: Dictionary = {}
	for entry in lines:
		var line: Dictionary = entry
		if scene_time >= float(line.get("at", 0.0)):
			active = line
	if active.is_empty():
		return
	var text := String(active.get("text", ""))
	if text == "":
		return
	var since: float = scene_time - float(active.get("at", 0.0))
	var alpha: float = clampf(since / 0.35, 0.0, 1.0)
	var box := Rect2(40, VH - 70, VW - 80, 40)
	draw_rect(box, Color(0.02, 0.04, 0.05, 0.80 * alpha), true)
	draw_rect(box, Color(SFPalette.CYAN_DIM.r, SFPalette.CYAN_DIM.g, SFPalette.CYAN_DIM.b, 0.7 * alpha), false, 1.0)
	var c := Color(SFPalette.PAPER.r, SFPalette.PAPER.g, SFPalette.PAPER.b, alpha)
	skin.wrap(self, box.position + Vector2(12, 8), box.size.x - 24, text, c, 1, 2)
	var hint := String((finale_data.get("cinematic", {}) as Dictionary).get("skip_hint", "ESC SKIP"))
	skin.text_r(self, VW - 14, VH - 16, hint, SFPalette.ASH_LIGHT)


func _draw_paused() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.04, 0.05, 0.55), true)
	draw_rect(Rect2(224, 150, 192, 60), Color(0.04, 0.08, 0.09, 0.96), true)
	draw_rect(Rect2(224, 150, 192, 60), SFPalette.CYAN, false, 1.0)
	skin.text_c(self, VW * 0.5, 162, "PAUSED", SFPalette.CYAN, 2)
	skin.text_c(self, VW * 0.5, 186, "SPACE RESUME     ESC SKIP", SFPalette.PAPER_DIM)


# ---------------------------------------------------------------- scene A

## The crash site. Every repaired system the player actually touched is lit; the
## memory core moves from Bill's old body to the VELA; the shell powers down.
func _draw_scene_crash_site() -> void:
	var t: float = clampf(scene_time / 16.0, 0.0, 1.0)
	# Dark ash sky and the wreck field.
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var band := 0
	while band < 14:
		var f := float(band) / 14.0
		draw_rect(Rect2(0, 100 + band * 14, VW, 15), SFPalette.INK.lerp(SFPalette.RUIN_DARK, f * f), true)
		band += 1
	draw_rect(Rect2(0, 300, VW, VH - 300), SFPalette.ASH_PLAIN.darkened(0.28), true)
	draw_rect(Rect2(0, 300, VW, 2), SFPalette.ASH.darkened(0.2), true)

	# The VELA, rebuilt, nose up at the cradle on the right.
	_draw_vela(Vector2(452, 300), 1.0, t)
	# Bill's shell on the left. It powers down as the core leaves it.
	var power: float = clampf(1.0 - t * 1.6, 0.0, 1.0)
	_draw_bill_shell(Vector2(140, 302), power)
	# The junction: lit only if the player repaired it.
	if campaign.has_flag("power_repaired"):
		var pulse: float = 0.55 + 0.35 * sin(elapsed * 3.0)
		draw_rect(Rect2(64, 288, 22, 14), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(68, 292, 14, 4), Color(0.40, 0.95, 0.85, pulse), true)
		draw_rect(Rect2(240, 300, 26, 2), Color(0.35, 0.75, 0.70, 0.30 * pulse), true)

	# The memory core, travelling from Bill to the VELA along an arc.
	var travel: float = clampf((scene_time - 1.2) / 4.0, 0.0, 1.0)
	if travel > 0.0 and travel < 1.0:
		var from := Vector2(140, 268)
		var to := Vector2(452, 214)
		var p: Vector2 = from.lerp(to, travel)
		p.y -= sin(travel * PI) * 54.0
		draw_rect(Rect2(p.x - 3, p.y - 3, 6, 6), SFPalette.CYAN, true)
		draw_rect(Rect2(p.x - 6, p.y - 1, 12, 2), Color(0.36, 0.90, 0.86, 0.35), true)
	elif travel >= 1.0:
		draw_rect(Rect2(448, 210, 8, 8), SFPalette.CYAN, true)

	# Dust and ground haze, tied to the scene clock rather than to randomness.
	for i in 22:
		var phase := fmod(float(i) * 0.37, 1.0)
		if phase > t:
			continue
		var dx := fmod(float(i) * 97.0 + elapsed * 9.0, VW)
		var dy := 316.0 - fmod(float(i) * 23.0 + elapsed * 4.0, 26.0)
		draw_rect(Rect2(round(dx), round(dy), 2, 1), Color(0.42, 0.46, 0.44, 0.35), true)


# ---------------------------------------------------------------- scene B

func _draw_scene_launch() -> void:
	var t: float = clampf(scene_time / 15.0, 0.0, 1.0)
	# Sky darkens with altitude; ground falls away.
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var sky_top: Color = SFPalette.SKY_DEEP.lerp(SFPalette.INK, clampf(t * 1.3, 0.0, 1.0))
	var sky_low: Color = SFPalette.SKY.lerp(SFPalette.RUIN_DARK, clampf(t * 1.1, 0.0, 1.0))
	draw_rect(Rect2(0, 0, VW, 236), sky_top, true)
	draw_rect(Rect2(0, 236, VW, VH - 236), sky_low, true)
	for i in 60:
		var a := clampf(t * 1.4 - 0.2, 0.0, 0.9)
		draw_rect(Rect2(float((i * 83) % VW), float((i * 47) % 210), 1, 1), Color(1, 1, 1, a), true)
	var ground_y: float = 262.0 + t * 260.0
	if ground_y < VH:
		draw_rect(Rect2(0, ground_y, VW, VH - ground_y), SFPalette.RUIN, true)
		draw_rect(Rect2(0, ground_y, VW, 2), SFPalette.ASH_PLAIN, true)
	var ship_y: float = 288.0 - t * 150.0
	_draw_vela(Vector2(VW * 0.5, ship_y), 1.15, 1.0)
	# Exhaust plume, anchored under the bells.
	var bell_y := ship_y - 10.0
	for i in 10:
		var ey := bell_y + float(i) * 6.5
		var w := 9.0 - float(i) * 0.7
		var a := 0.85 - float(i) * 0.08
		draw_rect(Rect2(round(VW * 0.5 - w * 0.5), round(ey), round(w), 5), Color(1.0, 0.70, 0.30, a), true)
	# Dust thrown outward at ignition, settling as the ship climbs.
	if t < 0.55:
		var k: float = t / 0.55
		for i in 30:
			var ang := PI + (float(i) / 29.0) * PI
			var r: float = 30.0 + k * 190.0
			var px := VW * 0.5 + cos(ang) * r
			var py := ship_y + 8.0 + sin(ang) * r * 0.34 - k * 14.0
			draw_rect(Rect2(round(px), round(py), 2, 2), Color(0.55, 0.55, 0.50, (1.0 - k) * 0.5), true)
	# Loose scrap tumbling up and back down.
	for i in 8:
		var life := fmod(float(i) * 0.21, 1.0)
		var age := maxf(0.0, t - life * 0.5)
		if age <= 0.0:
			continue
		var sx := VW * 0.5 + (float(i) - 3.5) * 26.0 * (1.0 - age)
		var sy := ship_y + 12.0 - sin(age * PI) * 46.0
		draw_rect(Rect2(round(sx), round(sy), 3, 2), SFPalette.STEEL_DARK, true)


# ---------------------------------------------------------------- scene C

## Debris passage. Telemetry is read from the certified simulation: the reported
## debris impact count, the route, delta-v, propellant and buffer reserves.
func _draw_scene_debris() -> void:
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.03, 0.06), true)
	# Distant starfield, drifting slowly.
	for i in 90:
		var x := float((i * 71) % VW) - fmod(elapsed * 6.0, float(VW))
		var y := float((i * 37) % VH)
		if x < 0.0:
			x += float(VW)
		draw_rect(Rect2(round(x), round(y), 1, 1), Color(0.75, 0.82, 0.95, 0.35 + 0.25 * float(i % 3) / 3.0), true)

	# The ship centre-right, shield up.
	var ship := Vector2(430.0, 200.0 + sin(elapsed * 0.7) * 4.0)
	_draw_vela(ship, 0.95, 1.0)
	var shield_r: float = 52.0
	var shield_c := Color(0.35, 0.85, 0.95, 0.10 + 0.05 * sin(elapsed * 2.4))
	for i in 36:
		var ang := float(i) / 36.0 * TAU
		var p := ship + Vector2(cos(ang), sin(ang) * 0.78) * shield_r
		draw_rect(Rect2(round(p.x), round(p.y), 1, 1), shield_c, true)

	# Small bodies crossing the lane; the navigation chip steers around the big
	# ones, which pass wide of the hull.
	for i in 14:
		var phase := fmod(float(i) * 0.29 + elapsed * (0.10 + 0.02 * float(i % 3)), 1.0)
		var y := 70.0 + float((i * 53) % 220)
		var x := VW + 20.0 - phase * float(VW + 60)
		var big: bool = i % 5 == 0
		var size: int = 7 if big else 3
		var offset := 0.0 if not big else (34.0 if i % 2 == 0 else -40.0)
		draw_rect(Rect2(round(x), round(y + offset), size, maxi(2, size - 2)), SFPalette.STEEL_DARK if big else SFPalette.ASH, true)

	# Shield impact sparks, scaled to the impact count the report certifies.
	var impacts := int(report.get("debris_impacts", 0))
	var spark_count: int = mini(10, maxi(1, int(float(impacts) / 3.0)))
	for i in spark_count:
		var cycle := fmod(elapsed * 0.8 + float(i) * 0.37, 1.0)
		if cycle > 0.35:
			continue
		var ang2 := float(i) * 1.7
		var p2 := ship + Vector2(cos(ang2), sin(ang2) * 0.8) * (shield_r + 2.0)
		var fade: float = 1.0 - cycle / 0.35
		draw_rect(Rect2(round(p2.x), round(p2.y), 2, 2), Color(0.55, 0.95, 1.0, fade), true)

	# Telemetry panel, left. Every value is real recorded engineering state.
	_draw_telemetry_panel()


func _draw_telemetry_panel() -> void:
	var panel := Rect2(16, 40, 226, 176)
	draw_rect(panel, Color(0.03, 0.06, 0.08, 0.90), true)
	draw_rect(panel, SFPalette.CYAN_DIM, false, 1.0)
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 1)), SFPalette.CYAN, true)
	skin.text(self, panel.position + Vector2(10, 8), "TRANSIT TELEMETRY", SFPalette.CYAN)
	var totals: Dictionary = {}
	var sim := SFFinale.simulation_for(campaign, reconstruction_data)
	totals = sim.get("totals", {}) as Dictionary
	var rows: Array = [
		["ROUTE", String(report.get("route_name", "-")).to_upper()],
		["LAUNCH MASS", "%.0f kg" % float(report.get("launch_mass_kg", 0.0))],
		["DELTA-V", "%.0f / %.0f m/s" % [float(totals.get("delta_v_available_m_s", 0.0)), float(totals.get("delta_v_required_m_s", 0.0))]],
		["PROPELLANT LEFT", "%.0f kg" % float(totals.get("propellant_remaining_kg", 0.0))],
		["BUFFER LEFT", "%.0f Wh" % float(totals.get("battery_remaining_wh", 0.0))],
		["PEAK POWER", "%.0f W" % float(totals.get("peak_power_w", 0.0))],
		["IMPACTS ABSORBED", "%d" % int(totals.get("debris_impacts", 0))],
	]
	var y := panel.position.y + 28.0
	for row in rows:
		var r: Array = row
		skin.text(self, Vector2(panel.position.x + 10, y), String(r[0]), SFPalette.PAPER_DIM)
		skin.text_r(self, panel.end.x - 10, y, String(r[1]), SFPalette.PAPER)
		y += 15.0
	skin.text(self, Vector2(panel.position.x + 10, panel.end.y - 22), "FROM THE CERTIFIED REPORT", SFPalette.ASH_LIGHT)


# ---------------------------------------------------------------- scene D

func _draw_scene_sunlight() -> void:
	var t: float = clampf(scene_time / 17.0, 0.0, 1.0)
	# Warm light rises from the lower edge and fills the frame slowly, in narrow
	# bands so the gradient has no visible step.
	draw_rect(Rect2(0, 0, VW, VH), Color(0.05, 0.07, 0.12), true)
	var warm: float = clampf(t * 1.35, 0.0, 1.0)
	var bands := 40
	for i in bands:
		# i = 0 is the bottom band, which carries the most light.
		var f := 1.0 - float(i) / float(bands - 1)
		var c: Color = Color(0.05, 0.07, 0.12).lerp(Color(0.95, 0.72, 0.42), pow(f, 1.7) * 0.62 * warm)
		draw_rect(Rect2(0, VH - 6.0 - float(i) * 6.0, VW, 7), c, true)
	# Future Earth below, half-lit: the same planet, later. The terminator is a
	# true half-disc, so it cannot show a rectangular edge over the sphere.
	var earth_c := Vector2(210, 268)
	var radius := 150.0
	for ring in range(24, 0, -1):
		var rr: float = radius * float(ring) / 24.0
		var col: Color = Color(0.23, 0.32, 0.30, 0.45).lerp(Color(0.42, 0.50, 0.44, 0.55), float(ring) / 24.0)
		draw_circle(earth_c, rr, col)
	draw_circle(earth_c, radius * 0.98, Color(0.12, 0.18, 0.17, 0.35))
	var night := PackedVector2Array()
	for i in 25:
		var ang := -PI * 0.5 + PI * float(i) / 24.0
		night.append(earth_c + Vector2(-cos(ang) * radius, sin(ang) * radius))
	draw_colored_polygon(night, Color(0.02, 0.04, 0.06, 0.30))
	# A soft rim light along the terminator, drawn as one-pixel steps.
	for i in 30:
		var ang := float(i) / 29.0 * TAU
		var p := earth_c + Vector2(cos(ang), sin(ang)) * radius
		draw_rect(Rect2(round(p.x), round(p.y), 1, 1), Color(0.95, 0.80, 0.58, 0.20), true)
	# VELA small against the light, drifting.
	_draw_vela(Vector2(500, 150 + sin(elapsed * 0.5) * 5.0), 0.62, 1.0)
	# A quiet lens bloom, kept restrained so it never weakens the beat.
	if t > 0.35:
		var bloom := clampf((t - 0.35) / 0.6, 0.0, 1.0) * 0.16
		draw_rect(Rect2(0, 0, VW, VH), Color(1.0, 0.92, 0.76, bloom), true)


# ---------------------------------------------------------------- scene E

func _draw_scene_portal() -> void:
	var t: float = clampf(scene_time / 14.0, 0.0, 1.0)
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.02, 0.06), true)
	# Stars dragged toward a seam, which is the fictional way home.
	var cx := VW * 0.5
	var cy := VH * 0.46
	for i in 110:
		var ang := float(i) * 2.399
		var r := 22.0 + float((i * 41) % 250)
		var pull: float = 1.0 / (1.0 + r / 110.0)
		var x := cx + cos(ang) * r * (1.0 - pull * 0.4 * t)
		var y := cy + sin(ang) * r * 0.60
		draw_rect(Rect2(round(x), round(y), 1, 1), Color(0.72, 0.80, 0.98, 0.18 + pull * 0.5), true)
	# The seam widens as the access window opens.
	var open: float = clampf((t - 0.15) / 0.55, 0.0, 1.0)
	var seam_h := 300.0 * open
	var seam_w := 2.0 + 26.0 * open
	var rng := RandomNumberGenerator.new()
	rng.seed = 4417
	var seg := 0
	while seg < 44:
		var p := float(seg) / 44.0
		var y2 := cy - seam_h * 0.5 + p * seam_h
		var taper := sin(p * PI)
		var jitter := sin(float(seg) * 1.9 + elapsed * 5.0) * 3.0
		draw_rect(Rect2(round(cx + jitter - seam_w * 0.5), round(y2), round(seam_w), 3),
			Color(0.44, 0.30, 0.66, 0.10 + taper * 0.22 * open), true)
		draw_rect(Rect2(round(cx + jitter - 2.0), round(y2), 4, 2),
			Color(0.84, 0.94, 1.0, (0.5 + taper * 0.4) * open), true)
		seg += 1
	# VELA crosses from right to left through the seam.
	var cross: float = clampf((t - 0.45) / 0.45, 0.0, 1.0)
	var ship_x: float = lerpf(VW + 80.0, cx - 120.0, cross)
	_draw_vela(Vector2(ship_x, cy + 40.0), 0.70, 1.0)
	# The recorded signal, drawn as a repeating waveform under the seam.
	if t > 0.05:
		for i in 120:
			var wx := 60.0 + float(i) * 4.3
			var amp: float = 5.0 + 6.0 * t
			var wy := 330.0 + sin(float(i) * 0.30 + elapsed * 5.0) * amp
			draw_rect(Rect2(wx, wy, 2, 1), Color(0.36, 0.78, 0.74, 0.55), true)


# ---------------------------------------------------------------- scene F

## Home. Present-day Earth drawn to match the title screen's healthy planet, the
## archive leaving the ship, and the final words on a quiet frame.
func _draw_scene_home() -> void:
	var t: float = clampf(scene_time / 24.0, 0.0, 1.0)
	# Daylight sky and living ground, the same palette as the opening.
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.SKY, true)
	var band := 0
	while band < 12:
		var f := float(band) / 12.0
		draw_rect(Rect2(0, band * 17, VW, 18), SFPalette.SKY_DEEP.lerp(SFPalette.SKY, f), true)
		band += 1
	draw_rect(Rect2(0, 250, VW, VH - 250), SFPalette.GRASS, true)
	draw_rect(Rect2(0, 250, VW, 3), SFPalette.GRASS_DARK, true)
	# The same planet art the title screen uses: visually matching the opening.
	var earth: Texture2D = skin.sprites.get("earth", null)
	if earth != null:
		draw_texture_rect(earth, Rect2(VW - 250, 150, 250, 250), false, Color(1, 1, 1, 0.95))
	# VELA on the pad, cooling.
	_draw_vela(Vector2(150, 286), 0.8, 1.0)
	# Mission Control: a dish and a mast, with a signal pulse on reacquisition.
	var mast := Vector2(78, 288)
	draw_rect(Rect2(mast.x - 1, mast.y - 66, 3, 66), SFPalette.STEEL_DARK, true)
	var dish_y := mast.y - 66.0
	for i in 5:
		var w := 10.0 + float(i) * 6.0
		draw_rect(Rect2(mast.x - w * 0.5, dish_y + float(i) * 2.0, w, 2), SFPalette.STEEL_MID, true)
	var pulse_cycle := fmod(elapsed * 0.55, 1.0)
	if pulse_cycle < 0.5:
		var rr: float = 20.0 + pulse_cycle * 160.0
		for i in 26:
			var ang := float(i) / 26.0 * TAU
			draw_rect(Rect2(round(mast.x + cos(ang) * rr), round(dish_y + sin(ang) * rr * 0.55), 1, 1),
				Color(0.30, 0.80, 0.75, 0.5 * (1.0 - pulse_cycle / 0.5)), true)

	# The archive transfer: packets rising from the ship to the dish.
	var shown := int(clampf(t / 0.62, 0.0, 1.0) * float(mini(8, report.get("memory_count", 0))))
	for i in 8:
		if i >= shown:
			continue
		var phase := fmod(elapsed * 0.5 + float(i) * 0.12, 1.0)
		var p := Vector2(150, 230).lerp(Vector2(78, 222), phase)
		p.y -= sin(phase * PI) * 28.0
		draw_rect(Rect2(round(p.x), round(p.y), 3, 3), Color(0.30, 0.85, 0.80, 0.8), true)

	# Communities receiving the record: a few lit windows on the horizon.
	for i in 9:
		var bx := 250.0 + float(i) * 36.0
		var bh := 16.0 + float((i * 29) % 26)
		draw_rect(Rect2(bx, 250.0 - bh, 22, bh), SFPalette.WARM_DARK.darkened(0.45), true)
		if i < shown:
			draw_rect(Rect2(bx + 4, 250.0 - bh + 5, 3, 3), SFPalette.GOLD, true)
			draw_rect(Rect2(bx + 13, 250.0 - bh + 10, 3, 3), SFPalette.GOLD, true)


# ---------------------------------------------------------------- final card

func _draw_final_message() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	var lines: Array = final_message.get("lines", []) as Array
	# A slow sunrise behind the words, then nothing else.
	var rise: float = clampf(scene_time / maxf(0.01, scene_duration()), 0.0, 1.0)
	for i in 14:
		var f := float(i) / 14.0
		var y := VH - 40.0 - f * 120.0 * rise
		draw_rect(Rect2(0, y, VW, 10), SFPalette.INK.lerp(Color(0.20, 0.26, 0.36), (1.0 - f) * 0.5 * rise), true)
	var alpha: float = clampf((scene_time - 0.6) / 1.6, 0.0, 1.0)
	var y2 := 140.0
	for line in lines:
		skin.text_c(self, VW * 0.5, y2, String(line), Color(SFPalette.PAPER.r, SFPalette.PAPER.g, SFPalette.PAPER.b, alpha), 2)
		y2 += 34.0
	if alpha >= 1.0 and scene_time > 3.0:
		var pulse := 0.55 + 0.35 * sin(elapsed * 2.2)
		skin.text_c(self, VW * 0.5, VH - 24, "ENTER CONTINUE", Color(SFPalette.CYAN.r, SFPalette.CYAN.g, SFPalette.CYAN.b, pulse))
	skin.text_r(self, VW - 14, VH - 16, "ESC SKIP", SFPalette.ASH_LIGHT)


# ---------------------------------------------------------------- shared art

## The repaired VELA, reusing the construction/launch visual language so the ship
## on screen is recognisably the one the player built.
func _draw_vela(ground: Vector2, ship_scale: float, glow: float) -> void:
	var w := 26.0 * ship_scale
	var h := 62.0 * ship_scale
	draw_rect(Rect2(ground.x - w * 0.5, ground.y - h - 12.0 * ship_scale, w, h), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - w * 0.5, ground.y - h - 12.0 * ship_scale, w * 0.2, h), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x + w * 0.3, ground.y - h - 12.0 * ship_scale, w * 0.2, h), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x - w * 0.27, ground.y - h - 32.0 * ship_scale, w * 0.54, 20.0 * ship_scale), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x - w * 0.16, ground.y - h - 52.0 * ship_scale, w * 0.32, 20.0 * ship_scale), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - w * 0.2, ground.y - 4.0 * ship_scale, w * 0.36, 12.0 * ship_scale), SFPalette.STEEL_DARK, true)
	# Cabin light, the shield emitter glow, and the three component lights.
	draw_rect(Rect2(ground.x - 3.0 * ship_scale, ground.y - h, 6.0 * ship_scale, 5.0 * ship_scale), Color(0.36, 0.90, 0.86, 0.85 * glow), true)
	for i in 3:
		draw_rect(Rect2(ground.x - 9.0 * ship_scale + float(i) * 7.0 * ship_scale, ground.y - h - 6.0 * ship_scale, 3.0 * ship_scale, 3.0 * ship_scale),
			Color(0.36, 0.95, 0.90, 0.9 * glow), true)


## Bill's maintenance shell. `power` fades the eyes and chest light out as the
## memory core is removed.
func _draw_bill_shell(ground: Vector2, power: float) -> void:
	draw_rect(Rect2(ground.x - 12, ground.y - 30, 24, 30), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x - 12, ground.y - 30, 5, 30), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 9, ground.y - 46, 18, 16), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 6, ground.y - 44, 12, 8), SFPalette.RUIN_BG, true)
	var eye := Color(0.36, 0.95, 0.90, 0.15 + 0.85 * power)
	draw_rect(Rect2(ground.x - 4, ground.y - 42, 2, 2), eye, true)
	draw_rect(Rect2(ground.x + 2, ground.y - 42, 2, 2), eye, true)
	draw_rect(Rect2(ground.x - 6, ground.y - 22, 12, 6), Color(0.20, 0.60, 0.55, 0.10 + 0.70 * power), true)
	# Arms, drawn folded.
	draw_rect(Rect2(ground.x - 18, ground.y - 26, 6, 16), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x + 12, ground.y - 26, 6, 16), SFPalette.STEEL_DARK, true)
