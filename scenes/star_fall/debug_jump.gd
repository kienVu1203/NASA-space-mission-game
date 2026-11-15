extends CanvasLayer
## Developer test hotkeys: hold CTRL + SHIFT + ALT and press a key.
## Added by main.gd in debug builds only (running from the editor or
## `godot --path .`); an exported release build never creates this node.
##
##   1..0  jump to a Phase 1-3 point (see SFDebugPresets.PRESETS)
##   F     Phase 4: ready for final assembly (workshop design fabricated)
##   E     Phase 4: the escape cinematic (final snapshot frozen)
##   R     Phase 4: the mission report
##   C     Phase 4: the credits
##   V     win the current boss fight (shield duel, typing duel, or the
##         Eco Arena: the Colossus falls and its two drops appear)
##   K     heal Nick to full in the current fight
##   M     add salvage (+10 scrap metal, circuitry, polymer)
##   H     show / hide this list on screen
##
## The three-modifier chord cannot be typed by accident: the typing duel
## ignores Ctrl/Alt chords and no game control uses all three. The chord is
## read in _input(), before any screen's _unhandled_input(), and consumed.
##
## A jump replaces the campaign in memory, then resumes through the
## controller's normal resume path, so every screen, dialogue and autosave
## behaves exactly as in real play. Autosaves will overwrite the save file, so
## the first jump of a session copies the existing save to
## user://star_fall_save.before_debug.json first.

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFDebugPresets := preload("res://core/star_fall/sf_debug_presets.gd")
const SFSave := preload("res://core/star_fall/sf_save.gd")

const BACKUP_PATH := "user://star_fall_save.before_debug.json"

var main
var help_visible: bool = false
var _backed_up: bool = false
var _drawer: Node2D


func _ready() -> void:
	layer = 95
	_drawer = Node2D.new()
	_drawer.name = "DebugHelp"
	_drawer.draw.connect(_draw_help)
	add_child(_drawer)


## True for a fresh key press with Ctrl, Shift and Alt all held.
static func is_chord(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	return k.pressed and not k.echo and k.ctrl_pressed and k.shift_pressed and k.alt_pressed


func _input(event: InputEvent) -> void:
	if not is_chord(event):
		return
	if handle_key((event as InputEventKey).keycode):
		get_viewport().set_input_as_handled()


## The single entry point, shared by real input and the tests. Returns true
## when the key was a debug command.
func handle_key(keycode: int) -> bool:
	# Digit and letter keycodes equal their ASCII codes (KEY_F == "F").
	if keycode < 128:
		var p := SFDebugPresets.preset_for_key(char(keycode))
		if not p.is_empty():
			jump(String(p["id"]))
			return true
	match keycode:
		KEY_V:
			win_fight()
			return true
		KEY_K:
			heal()
			return true
		KEY_M:
			add_salvage()
			return true
		KEY_H:
			help_visible = not help_visible
			_drawer.queue_redraw()
			return true
	return false


# ---------------------------------------------------------------- commands

func jump(id: String) -> bool:
	var p := SFDebugPresets.preset(id)
	if p.is_empty():
		return false
	_backup_save_once()
	if not SFDebugPresets.apply(main.campaign, id):
		return false
	# Close whatever was open: a dialogue, the pause menu, a remembered spot.
	main.dialogue = null
	main.dialogue_next = Callable()
	main.pause_open = false
	main._has_last_world_position = false
	main._resume_from_campaign()
	if p.has("position") and main.world != null:
		main.world.set_player_position(p["position"] as Vector2)
	main.apply_focus_state()
	main.ui.notify("DEBUG: " + String(p["title"]), "warn", 2.5)
	return true


## Ends the current boss fight as a victory. The screen's own victory overlay
## and the controller's reward path then run as usual.
func win_fight() -> bool:
	if main.typing_duel != null:
		var duel = main.typing_duel
		if duel.encounter.force_victory():
			duel.state = duel.State.VICTORY
			main.ui.notify("DEBUG: SKY REMNANT DEFEATED - ENTER TO CONTINUE", "warn", 2.5)
			return true
	if main.eco_screen != null:
		var es = main.eco_screen
		if es.model.debug_defeat_boss():
			es._consume(es.model.take_events())
			main.ui.notify("DEBUG: COLOSSUS DOWN - UNLOCK THE SUPER CORE, TAKE THE CHIP", "warn", 2.5)
			return true
	if main.duel != null:
		var sd = main.duel
		if not sd.encounter.model.is_over():
			sd.encounter.model.force_victory()
			sd.encounter.field.clear()
			sd.state = sd.State.VICTORY
			main.ui.notify("DEBUG: BOSS DEFEATED - ENTER TO CONTINUE", "warn", 2.5)
			return true
	main.ui.notify("DEBUG: no fight to win here", "info", 1.5)
	return false


func heal() -> bool:
	if main.typing_duel != null:
		main.typing_duel.encounter.nick_health = main.typing_duel.encounter.nick_health_max
	elif main.duel != null:
		main.duel.encounter.model.nick_health = main.duel.encounter.model.nick_health_max
	elif main.eco_screen != null:
		main.eco_screen.model.health = main.eco_screen.model.health_max
		main.eco_screen.model.shield = main.eco_screen.model.shield_max
	else:
		main.ui.notify("DEBUG: no fight to heal in", "info", 1.5)
		return false
	main.ui.notify("DEBUG: NICK HEALED", "warn", 1.5)
	return true


func add_salvage() -> int:
	var added := 0
	for m in ["scrap_metal", "circuitry", "polymer"]:
		added += int(main.campaign.add_material(String(m), 10))
	main.ui.notify("DEBUG: +%d SALVAGE" % added, "warn", 1.5)
	return added


## Keeps a copy of the real save before the first jump of a session, because
## the jumped campaign autosaves over it at the next checkpoint.
func _backup_save_once() -> void:
	if _backed_up:
		return
	_backed_up = true
	if not SFSave.save_exists():
		return
	var from := ProjectSettings.globalize_path(SFSave.SAVE_PATH)
	var to := ProjectSettings.globalize_path(BACKUP_PATH)
	if DirAccess.copy_absolute(from, to) != OK:
		push_warning("Debug jump: could not back up the save to %s" % BACKUP_PATH)


# ---------------------------------------------------------------- help

func _draw_help() -> void:
	if not help_visible or main == null:
		return
	var skin = main.skin
	var lines: Array = ["DEBUG HOTKEYS  (HOLD CTRL + SHIFT + ALT)", ""]
	for p in SFDebugPresets.PRESETS:
		lines.append("%s   %s" % [String((p as Dictionary)["key"]), String((p as Dictionary)["title"])])
	lines.append_array(["", "V   WIN THE CURRENT FIGHT", "K   HEAL NICK", "M   +10 OF EACH SALVAGE", "H   HIDE THIS LIST"])
	var r := Rect2(8, 30, 264, 14 + lines.size() * 10)
	_drawer.draw_rect(r, Color(0.02, 0.03, 0.04, 0.92), true)
	_drawer.draw_rect(r, SFPalette.GOLD, false, 1.0)
	var y := r.position.y + 7.0
	for i in lines.size():
		skin.text(_drawer, Vector2(r.position.x + 8, y), String(lines[i]), SFPalette.GOLD if i == 0 else SFPalette.PAPER)
		y += 10.0
