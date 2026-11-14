extends Node2D
## One authored world prop: drawn with its origin at the ground-contact point
## and given a small ground-level collision footprint so Nick's upper body can
## overlap tall props while his feet cannot walk through them.
##
## Interaction data comes from data/star_fall/sites.json. The world owns the
## decision about what an interaction means.

const SFPalette := preload("res://core/star_fall/sf_palette.gd")

var skin
var sprite_key: String = ""
var prop_id: String = ""
var label: String = ""
var lines: Array = []
var interactive: bool = false
var highlighted: bool = false
var mouse_hovered: bool = false
var solid_size: Vector2 = Vector2.ZERO

var is_exit_gate: bool = false
var gate_unlocked: bool = false
var gate_cleared: bool = false
var destination_badge: String = ""
var status_subtext: String = ""

var _pulse: float = 0.0


func setup(skin_ref, data: Dictionary) -> void:
	skin = skin_ref
	sprite_key = String(data.get("sprite", ""))
	prop_id = String(data.get("interact", ""))
	label = String(data.get("label", ""))
	lines = data.get("lines", []) as Array
	interactive = prop_id != ""
	var solid: Variant = data.get("solid", [])
	if solid is Array and (solid as Array).size() >= 2:
		solid_size = Vector2(float((solid as Array)[0]), float((solid as Array)[1]))
	position = Vector2(float(data.get("x", 0)), float(data.get("y", 0)))
	if prop_id == "city_boss_gate":
		is_exit_gate = true
		destination_badge = "CONTROL CENTER"
		status_subtext = "LOCKED - USE CHECKPOINT"
	elif prop_id == "coast_boss_gate":
		is_exit_gate = true
		destination_badge = "CLEANUP FACILITY"
		status_subtext = "LOCKED - USE CHECKPOINT"


func _ready() -> void:
	if solid_size != Vector2.ZERO:
		var body := StaticBody2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(solid_size.x, maxf(4.0, solid_size.y))
		var collider := CollisionShape2D.new()
		collider.shape = shape
		# Footprint sits on the ground, centred under the origin.
		collider.position = Vector2(0, -shape.size.y * 0.5)
		body.add_child(collider)
		add_child(body)


func _process(delta: float) -> void:
	if highlighted or mouse_hovered or is_exit_gate or prop_id.ends_with("checkpoint"):
		_pulse += delta
	queue_redraw()


func configure_gate_state(unlocked: bool, cleared: bool, dest_title: String, subtext: String, next_label: String = "") -> void:
	is_exit_gate = true
	gate_unlocked = unlocked
	gate_cleared = cleared
	if dest_title != "":
		destination_badge = dest_title
	status_subtext = subtext
	if next_label != "":
		label = next_label
	queue_redraw()


func hit_rect() -> Rect2:
	var w := 24.0
	var h := 24.0
	if skin != null:
		var tex: Texture2D = skin.sprites.get(sprite_key, null)
		if tex != null:
			w = maxf(22.0, float(tex.get_width()) + 10.0)
			h = maxf(22.0, float(tex.get_height()) + 10.0)
	return Rect2(position.x - w * 0.5, position.y - h + 4.0, w, h)


func set_sprite(key: String) -> void:
	sprite_key = key
	queue_redraw()


func _draw() -> void:
	if skin == null:
		return
	var tex: Texture2D = skin.sprites.get(sprite_key, null)
	if tex == null:
		return

	# Contact shadow: props are sorted by their ground point, so the shadow
	# belongs at the origin, not under the visible sprite centre.
	var shadow_w: float = clampf(tex.get_width() * 0.65, 10.0, 34.0)
	skin.contact_shadow(self, Vector2(0, 0), shadow_w, 0.20)

	var size := tex.get_size()
	if is_exit_gate:
		_draw_exit_framing(size)

	if highlighted or mouse_hovered:
		var glow := Color(0.37, 0.90, 0.85, 0.5) if highlighted else Color(0.95, 0.82, 0.35, 0.45)
		glow.a = 0.35 + 0.25 * sin(_pulse * 5.0)
		var w := tex.get_width() + 8
		var h := tex.get_height() + 4
		draw_rect(Rect2(round(-w * 0.5), round(-h + 2), w, h), glow, false, 1.0)

	draw_texture_rect(tex, Rect2(Vector2(round(-size.x * 0.5), round(-size.y)), size), false)

	if is_exit_gate:
		_draw_exit_overhead(size)
	elif prop_id.ends_with("checkpoint"):
		_draw_checkpoint_badge(size)


func _draw_exit_framing(size: Vector2) -> void:
	var pulse: float = 0.55 + 0.45 * sin(_pulse * 4.2)
	var accent: Color = SFPalette.CYAN if gate_unlocked else SFPalette.RUST_LIGHT
	if gate_cleared:
		accent = SFPalette.GREEN_OK
	# Threshold pad and animated chevrons in front of the gate.
	var pad_w: float = maxf(38.0, size.x + 12.0)
	var pad_rect := Rect2(round(-pad_w * 0.5), -2.0, pad_w, 12.0)
	draw_rect(pad_rect, Color(0.03, 0.06, 0.07, 0.78), true)
	draw_rect(pad_rect, Color(accent.r, accent.g, accent.b, 0.45 + 0.35 * pulse), false, 1.0)
	for i in 3:
		var cx: float = -10.0 + float(i) * 10.0
		var c_alpha: float = (0.35 + 0.50 * pulse) if gate_unlocked else 0.28
		draw_rect(Rect2(cx - 2.0, 2.0, 4.0, 2.0), Color(accent.r, accent.g, accent.b, c_alpha), true)
		draw_rect(Rect2(cx - 1.0, 5.0, 2.0, 2.0), Color(SFPalette.PAPER.r, SFPalette.PAPER.g, SFPalette.PAPER.b, c_alpha), true)
	# Flanking beacon posts.
	var post_x: float = round(size.x * 0.5) + 4.0
	for side in [-1.0, 1.0]:
		var px: float = side * post_x
		draw_rect(Rect2(px - 2.0, -size.y + 4.0, 4.0, size.y - 4.0), SFPalette.STEEL_DARK, true)
		draw_rect(Rect2(px - 1.0, -size.y + 6.0, 2.0, size.y - 10.0), Color(accent.r, accent.g, accent.b, 0.45 + 0.45 * pulse), true)


func _draw_exit_overhead(size: Vector2) -> void:
	if destination_badge == "":
		return
	var pulse: float = 0.65 + 0.35 * sin(_pulse * 4.5)
	var accent: Color = SFPalette.CYAN if gate_unlocked else SFPalette.RUST_LIGHT
	if gate_cleared:
		accent = SFPalette.GREEN_OK
	var title_w: float = skin.font.text_width(destination_badge)
	var sub_w: float = skin.font.text_width(status_subtext) if status_subtext != "" else 0.0
	var box_w: float = maxf(title_w, sub_w) + 12.0
	var box_h: float = 20.0 if status_subtext != "" else 11.0
	var top_y: float = round(-size.y - box_h - 5.0)
	var cx: float = minf(0.0, round(632.0 - position.x - box_w * 0.5))
	var box := Rect2(round(cx - box_w * 0.5), top_y, box_w, box_h)
	draw_rect(box, Color(0.02, 0.05, 0.06, 0.90), true)
	draw_rect(box, Color(accent.r, accent.g, accent.b, 0.80 * pulse), false, 1.0)
	skin.text_c(self, cx, top_y + 2.0, destination_badge, SFPalette.PAPER)
	if status_subtext != "":
		skin.text_c(self, cx, top_y + 11.0, status_subtext, accent)
	if highlighted or mouse_hovered:
		var prompt_text := "[E] " + label.to_upper()
		var pw: float = skin.font.text_width(prompt_text) + 10.0
		var pcx: float = minf(0.0, round(632.0 - position.x - pw * 0.5))
		var pr := Rect2(round(pcx - pw * 0.5), top_y - 13.0, pw, 11.0)
		draw_rect(pr, Color(0.04, 0.09, 0.09, 0.94), true)
		draw_rect(pr, SFPalette.GOLD, false, 1.0)
		skin.text_c(self, pcx, pr.position.y + 2.0, prompt_text, SFPalette.GOLD)


func _draw_checkpoint_badge(size: Vector2) -> void:
	var tag := "CHECKPOINT"
	var tw: float = skin.font.text_width(tag) + 8.0
	var top_y: float = round(-size.y - 13.0)
	var box := Rect2(round(-tw * 0.5), top_y, tw, 10.0)
	draw_rect(box, Color(0.02, 0.05, 0.06, 0.84), true)
	draw_rect(box, Color(SFPalette.GOLD.r, SFPalette.GOLD.g, SFPalette.GOLD.b, 0.65), false, 1.0)
	skin.text_c(self, 0.0, top_y + 2.0, tag, SFPalette.GOLD)

