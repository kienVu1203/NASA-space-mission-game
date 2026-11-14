extends Node2D
## Phase 4: final assembly. The pre-finale gate.
##
## The screen shows every finale prerequisite from data and from the campaign,
## and offers one irreversible action: Complete Assembly and Launch. It owns no
## campaign state. On a valid confirmation it emits `assembly_started` once; the
## controller freezes the snapshot, writes the pre-finale checkpoint, locks the
## workshop and calls play_installation(); this screen then animates the install
## and emits `installation_done`, and the controller starts the cinematic.
##
## Controls
##   UP / DOWN, W / S   choose CONFIRM or BACK
##   ENTER / SPACE / E  activate
##   ESC                back, or skip the installation animation
##
## Double activation is refused: `_started` latches on the first valid confirm,
## so two clicks on the same frame cannot open two sequences.

signal assembly_started
signal installation_done
signal closed

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFMenu := preload("res://core/star_fall/sf_menu.gd")
const SFFinale := preload("res://core/star_fall/sf_finale.gd")
const SFContent := preload("res://core/star_fall/sf_content.gd")

const VW := 640
const VH := 360

enum Phase { REVIEW, INSTALLING, DONE }

var skin
var ui
var campaign
var finale_data: Dictionary = {}
var reconstruction_data: Dictionary = {}
var checks: Array = []
var menu
var phase: int = Phase.REVIEW
var install_timer: float = 0.0
var install_seconds: float = 3.4
var time: float = 0.0
var message: String = ""
var message_tone: String = "warn"
var message_timer: float = 0.0
var _started: bool = false
## Set by the controller while a dialogue is open over this screen. Every key
## belongs to the dialogue then, so the gate cannot be confirmed by accident.
var input_locked: bool = false


func setup(skin_ref, ui_ref, campaign_ref, finale: Dictionary, reconstruction: Dictionary) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	finale_data = finale
	reconstruction_data = reconstruction
	install_seconds = float((finale_data.get("assembly", {}) as Dictionary).get("install_seconds", 3.4))


func _ready() -> void:
	menu = SFMenu.new()
	var labels: Dictionary = (finale_data.get("assembly", {}) as Dictionary).get("check_labels", {}) as Dictionary
	menu.set_items([
		{"id": "confirm", "label": String(_assembly().get("confirm_label", "COMPLETE ASSEMBLY AND LAUNCH")), "enabled": true},
		{"id": "back", "label": String(_assembly().get("back_label", "RETURN TO THE WORKSHOP")), "enabled": true},
	])
	menu.index = 0
	# The check labels are kept here so _draw does not have to rebuild them.
	_check_labels = labels
	refresh()
	queue_redraw()


var _check_labels: Dictionary = {}


func _assembly() -> Dictionary:
	return finale_data.get("assembly", {}) as Dictionary


## Revalidates the prerequisites. Called on entry and again on confirmation, so
## the panel can never show a stale result.
func refresh() -> void:
	checks = SFFinale.prerequisites(campaign, reconstruction_data, true).get("checks", []) as Array


func prerequisites_met() -> bool:
	for c in checks:
		if not bool((c as Dictionary).get("ok", false)):
			return false
	return not checks.is_empty()


func is_installing() -> bool:
	return phase == Phase.INSTALLING


func has_started() -> bool:
	return _started


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
	if input_locked:
		return
	if phase == Phase.INSTALLING:
		if keycode == KEY_ESCAPE or keycode == KEY_ENTER or keycode == KEY_SPACE:
			# Skipping the installation animation is safe: the outcome is applied
			# by the controller before the animation starts.
			_finish_installation()
		return
	if phase == Phase.DONE:
		return
	match keycode:
		KEY_UP, KEY_W:
			menu.move_enabled(-1)
			skin.audio.sfx_select()
		KEY_DOWN, KEY_S:
			menu.move_enabled(1)
			skin.audio.sfx_select()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			activate()
		KEY_ESCAPE:
			skin.audio.sfx_back()
			closed.emit()
	queue_redraw()


## Activates the current row. Public so the controller and the tests use the
## same path the keyboard does.
func activate() -> void:
	if phase != Phase.REVIEW or input_locked:
		return
	if menu.current_id() == "back":
		skin.audio.sfx_back()
		closed.emit()
		return
	if _started:
		return
	refresh()
	if not prerequisites_met():
		skin.audio.sfx_denied()
		_say("Finale prerequisites are not met. Review the list.", "bad")
		return
	_started = true
	skin.audio.sfx_confirm()
	assembly_started.emit()


## Called by the controller once the snapshot, checkpoint and control locks are
## applied. Starts the install animation; `installation_done` follows.
func play_installation() -> void:
	if phase != Phase.REVIEW:
		return
	phase = Phase.INSTALLING
	install_timer = 0.0
	skin.audio.sfx_power_up()
	queue_redraw()


func _finish_installation() -> void:
	if phase != Phase.INSTALLING:
		return
	phase = Phase.DONE
	skin.audio.sfx_checkpoint()
	installation_done.emit()


func _process(delta: float) -> void:
	time += delta
	if message_timer > 0.0:
		message_timer = maxf(0.0, message_timer - delta)
	if phase == Phase.INSTALLING:
		install_timer += delta
		if install_timer >= install_seconds:
			_finish_installation()
	queue_redraw()


func _say(text: String, tone: String) -> void:
	message = text
	message_tone = tone
	message_timer = 3.0


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.RUIN_BG, true)
	_draw_workshop_backdrop()

	var title := String(_assembly().get("title", "FINAL ASSEMBLY"))
	if phase == Phase.INSTALLING or phase == Phase.DONE:
		title = "ASSEMBLY"
	ui.header(self, title, String(_assembly().get("subtitle", "")), [campaign.mission_name().to_upper()])

	_draw_frame_panel(Rect2(24, 42, 232, 232))
	_draw_check_panel(Rect2(272, 42, 344, 232))

	if phase == Phase.INSTALLING:
		_draw_install_progress()
	elif phase == Phase.DONE:
		skin.text_c(self, VW * 0.5, VH - 22, "ASSEMBLY COMPLETE", SFPalette.GREEN_OK)
		ui.toast(self)
		return
	else:
		ui.menu_list(self, menu, Vector2(272, 286), 344.0, 19.0, SFPalette.GREEN_OK)
		skin.text_c(self, VW * 0.5, VH - 18,
			"UP/DOWN: SELECT     ENTER: ACTIVATE     ESC: BACK", SFPalette.PAPER_DIM)

	if message_timer > 0.0 and message != "":
		var c: Color = SFPalette.RED if message_tone == "bad" else SFPalette.GOLD
		c.a = clampf(message_timer, 0.0, 1.0)
		skin.text_c(self, VW * 0.5, VH - 32, message, c)
	ui.toast(self)


func _draw_workshop_backdrop() -> void:
	# The crash-site workshop at night, lit by work lamps.
	draw_rect(Rect2(0, 0, VW, 150), SFPalette.INK.lerp(SFPalette.SKY_DEEP, 0.14), true)
	var g := 0
	while g < 14:
		var t := float(g) / 14.0
		draw_rect(Rect2(0, 150 + g * 8, VW, 8), SFPalette.RUIN_BG.lerp(SFPalette.RUIN, t), true)
		g += 1
	draw_rect(Rect2(0, 262, VW, VH - 262), SFPalette.RUIN, true)
	draw_rect(Rect2(0, 262, VW, 2), SFPalette.ASH.darkened(0.4), true)
	var fy := 272.0
	var step := 4.0
	while fy < VH:
		draw_rect(Rect2(0, round(fy), VW, 1), SFPalette.RUIN_DARK, true)
		fy += step
		step += 0.85
	# Wreck silhouette at the far left, out of the panels' way.
	draw_rect(Rect2(8, 236, 16, 28), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(12, 224, 8, 14), SFPalette.STEEL_MID, true)
	for i in 4:
		var lx := 96.0 + float(i) * 150.0
		draw_rect(Rect2(lx - 1, 0, 2, 18), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(lx - 4, 18, 8, 3), SFPalette.WARM_DARK, true)
		var flicker := 0.55 + 0.12 * sin(time * 2.2 + float(i) * 1.7)
		draw_rect(Rect2(lx - 20, 21, 40, 2), Color(0.95, 0.88, 0.70, 0.10 * flicker), true)


func _draw_frame_panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0.04, 0.07, 0.08, 0.92), true)
	draw_rect(rect, SFPalette.STEEL_DARK, false, 1.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), SFPalette.GREEN_OK, true)
	skin.text(self, rect.position + Vector2(10, 8), "VELA / FROZEN DESIGN", SFPalette.GREEN_OK)

	# The recovered frame with three fitted components, drawn as installed.
	var ground := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 168.0)
	_draw_frame(ground)
	var fitted := 0
	for id in SFFinale.COMPONENTS:
		if campaign.has_component(String(id)):
			fitted += 1
	skin.text_c(self, rect.position.x + rect.size.x * 0.5, rect.position.y + 184.0,
		"COMPONENTS FITTED  %d / 3" % fitted, SFPalette.GOLD if fitted < 3 else SFPalette.GREEN_OK)

	# Design summary from the committed record, not from the screen's opinion.
	var ws = SFFinale.workshop_for(campaign, reconstruction_data)
	var y := rect.position.y + 198.0
	for group in ["propulsion", "route"]:
		var o: Dictionary = ws.selected(group)
		var label := String(o.get("short", o.get("name", "")))
		if label != "":
			skin.text(self, Vector2(rect.position.x + 10, y), label, SFPalette.PAPER)
			y += 11.0


func _draw_frame(ground: Vector2) -> void:
	# A repaired three-quarter frame, kept in the same visual language as the
	# construction screen and the launch silhouette.
	draw_rect(Rect2(ground.x - 26, ground.y - 96, 52, 76), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 26, ground.y - 96, 10, 76), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x + 17, ground.y - 96, 9, 76), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x - 14, ground.y - 114, 28, 20), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x - 8, ground.y - 128, 16, 16), SFPalette.STEEL, true)
	draw_rect(Rect2(ground.x - 4, ground.y - 136, 8, 10), SFPalette.STEEL_MID, true)
	draw_rect(Rect2(ground.x - 24, ground.y - 22, 14, 18), SFPalette.STEEL_DARK, true)
	draw_rect(Rect2(ground.x + 10, ground.y - 22, 14, 18), SFPalette.STEEL_DARK, true)
	# Three component lights, lit only when installed.
	var order := SFFinale.COMPONENTS
	for i in order.size():
		var on: bool = campaign.has_component(String(order[i]))
		var c: Color = SFPalette.CYAN if on else SFPalette.RUIN_DARK
		draw_rect(Rect2(ground.x - 16 + float(i) * 11, ground.y - 78, 7, 5), c, true)


func _draw_check_panel(rect: Rect2) -> void:
	draw_rect(rect, Color(0.04, 0.07, 0.08, 0.92), true)
	draw_rect(rect, SFPalette.STEEL_DARK, false, 1.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), SFPalette.CYAN, true)
	skin.text(self, rect.position + Vector2(10, 8), "FINALE PREREQUISITES", SFPalette.CYAN)
	var y := rect.position.y + 26.0
	for c in checks:
		var check: Dictionary = c
		var ok := bool(check.get("ok", false))
		var id := String(check.get("id", ""))
		var label := String(_check_labels.get(id, id.to_upper()))
		draw_rect(Rect2(rect.position.x + 10, y, 8, 8), SFPalette.GREEN_OK if ok else SFPalette.RED, true)
		skin.text(self, Vector2(rect.position.x + 24, y - 1), label, SFPalette.PAPER if ok else SFPalette.PAPER_DIM)
		y += 16.0
	y += 6.0
	skin.wrap(self, Vector2(rect.position.x + 10, y), rect.size.x - 20,
		String(_assembly().get("locked_note", "")), SFPalette.ASH_LIGHT, 1, 3)


func _draw_install_progress() -> void:
	var t: float = clampf(install_timer / maxf(0.01, install_seconds), 0.0, 1.0)
	var steps: Array = _assembly().get("steps", []) as Array
	var panel := Rect2(160, 286, 320, 40)
	draw_rect(panel, Color(0.03, 0.06, 0.06, 0.94), true)
	draw_rect(panel, SFPalette.GREEN_OK, false, 1.0)
	skin.bar(self, panel.position + Vector2(10, 8), Vector2(panel.size.x - 20, 8), t, SFPalette.GREEN_OK)
	var idx: int = mini(steps.size() - 1, int(t * float(steps.size())))
	if idx >= 0 and not steps.is_empty():
		skin.text(self, panel.position + Vector2(10, 22), String(steps[idx]), SFPalette.PAPER)
	skin.text_c(self, VW * 0.5, VH - 14, "ESC SKIP ANIMATION", SFPalette.PAPER_DIM)
