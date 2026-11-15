extends Node2D
## Phase 4: credits. A restrained scroll over the healthy planet, with the
## project's own asset and source notes (data/star_fall/finale.json, credits).
## The roll opens with the six team members, exactly as listed in the data,
## drawn at double size. It credits only what the repository genuinely
## contains: original procedural art and audio, the engine, and the project's
## own tooling. No agency imagery, logo or affiliation appears.
##
## Controls
##   UP / DOWN, W / S, mouse wheel   scroll manually
##   ENTER / SPACE / E, RETURN button continue to the title
##   ESC                              the shared pause menu (controller)
##
## Ending here is deliberate: the credit roll is the last screen. Whatever the
## player does, the controller applies the same completion state once.

signal closed

const SFPalette := preload("res://core/star_fall/sf_palette.gd")

const VW := 640
const VH := 360
const RETURN_BUTTON := Rect2(470, 333, 156, 20)
const TEAM_LINE_H := 24.0
const LINE_H := 14.0

var skin
var ui
var campaign
var finale_data: Dictionary = {}
var scroll: float = 0.0
var scroll_seconds: float = 46.0
var time: float = 0.0
var closed_once: bool = false
var holding: bool = false


func setup(skin_ref, ui_ref, campaign_ref, finale: Dictionary) -> void:
	skin = skin_ref
	ui = ui_ref
	campaign = campaign_ref
	finale_data = finale


func _ready() -> void:
	scroll_seconds = float((finale_data.get("credits", {}) as Dictionary).get("scroll_seconds", 46.0))
	scroll = 0.0
	closed_once = false
	queue_redraw()


func _credits() -> Dictionary:
	return finale_data.get("credits", {}) as Dictionary


func _sections() -> Array:
	return _credits().get("sections", []) as Array


## Total pixel height of the roll, so the end of the scroll is known rather than
## guessed. Each heading costs a title row plus a gap; each line is one row.
func content_height() -> float:
	var h := 0.0
	for s in _sections():
		var section: Dictionary = s
		h += 24.0 + float((section.get("lines", []) as Array).size()) * _line_h(section) + 16.0
	return h + 60.0


func _line_h(section: Dictionary) -> float:
	return TEAM_LINE_H if bool(section.get("team", false)) else LINE_H


func at_end() -> bool:
	return scroll >= content_height()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		get_viewport().set_input_as_handled()
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				handle_key(KEY_DOWN)
			MOUSE_BUTTON_WHEEL_UP:
				handle_key(KEY_UP)
			MOUSE_BUTTON_LEFT:
				if RETURN_BUTTON.has_point(get_local_mouse_position()):
					handle_key(KEY_ENTER)
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	handle_key(key.keycode)


func handle_key(keycode: int) -> void:
	match keycode:
		KEY_UP, KEY_W, KEY_DOWN, KEY_S:
			holding = true
			scroll = clampf(scroll + (18.0 if keycode == KEY_DOWN or keycode == KEY_S else -18.0), 0.0, content_height())
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
			if closed_once:
				return
			closed_once = true
			skin.audio.sfx_confirm()
			closed.emit()
	queue_redraw()


func _process(delta: float) -> void:
	time += delta
	# The roll advances on its own, in delta time, so it behaves the same at any
	# frame rate. Pressing a scroll key does not stop it; it only nudges it.
	var per_second: float = content_height() / maxf(8.0, scroll_seconds)
	scroll = minf(content_height(), scroll + per_second * delta)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), SFPalette.INK, true)
	_draw_backdrop()
	# The roll is clipped between the header and the footer bands, so no line can
	# run behind either strip however the window is scaled.
	var band_top := 34.0
	var band_bottom := VH - 34.0
	var y: float = band_top + 24.0 - scroll
	for s in _sections():
		var section: Dictionary = s
		var team: bool = bool(section.get("team", false))
		if y >= band_top + 8.0 and y <= band_bottom - 8.0:
			skin.text_c(self, VW * 0.5, y, String(section.get("heading", "")), SFPalette.CYAN)
			draw_rect(Rect2(VW * 0.5 - 90.0, y + 12.0, 180.0, 1), SFPalette.STEEL_DARK, true)
		y += 24.0
		for line in section.get("lines", []) as Array:
			# A line is drawn only when all of it fits inside the band, so no name
			# is ever cut by the header or footer strip.
			var h: float = 14.0 if team else 7.0
			if y >= band_top + 6.0 and y + h <= band_bottom - 6.0:
				skin.text_c(self, VW * 0.5, y, String(line), SFPalette.WARM if team else SFPalette.PAPER, 2 if team else 1)
			y += _line_h(section)
		y += 16.0

	# Header strip keeps the credits readable against the moving backdrop. It is
	# drawn before the closing card so the card sits in the open middle band.
	draw_rect(Rect2(0, 0, VW, band_top), Color(0.02, 0.04, 0.05, 0.96), true)
	draw_rect(Rect2(0, band_top, VW, 1), SFPalette.STEEL_DARK, true)
	skin.text(self, Vector2(14, band_top * 0.5 - 4.0), String(_credits().get("title", "CREDITS")), SFPalette.CYAN)
	skin.text_r(self, VW - 14, band_top * 0.5 - 4.0, "STAR FALL", SFPalette.PAPER_DIM)

	# Footer strip, drawn last so it always covers the roll behind it.
	draw_rect(Rect2(0, band_bottom, VW, VH - band_bottom), Color(0.02, 0.04, 0.05, 0.96), true)
	draw_rect(Rect2(0, band_bottom, VW, 1), SFPalette.STEEL_DARK, true)
	if at_end():
		var msg: Array = _credits().get("final_message", []) as Array
		var my := 104.0
		for line in msg:
			skin.text_c(self, VW * 0.5, my, String(line), SFPalette.WARM, 2)
			my += 30.0
		skin.text(self, Vector2(14, band_bottom + 11.0), "ENTER OR CLICK: RETURN TO TITLE", SFPalette.PAPER_DIM)
	else:
		skin.text(self, Vector2(14, band_bottom + 11.0), "UP/DOWN OR WHEEL SCROLL     ESC PAUSE", SFPalette.PAPER_DIM)
	skin.button(self, RETURN_BUTTON, "RETURN TO TITLE", at_end() or RETURN_BUTTON.has_point(get_local_mouse_position()), true)


func _draw_backdrop() -> void:
	# The living present-day planet, drawn dim so the words stay readable.
	var earth: Texture2D = null
	if skin != null and skin.sprites != null:
		earth = skin.sprites.get("earth", null)
	if earth != null:
		draw_texture_rect(earth, Rect2(VW * 0.5 - 200, VH - 170, 400, 400), false, Color(0.42, 0.52, 0.52, 0.55))
	for i in 50:
		var c := Color(1, 1, 1, 0.08 + 0.12 * float(i % 3) / 3.0)
		draw_rect(Rect2(float((i * 101) % VW), float((i * 53) % VH), 1, 1), c, true)
	draw_rect(Rect2(0, 0, VW, VH), Color(0.02, 0.04, 0.05, 0.62), true)
