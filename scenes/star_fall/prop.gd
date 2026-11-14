extends Node2D
## One authored world prop: drawn with its origin at the ground-contact point
## and given a small ground-level collision footprint so Nick's upper body can
## overlap tall props while his feet cannot walk through them.
##
## Interaction data comes from data/star_fall/sites.json. The world owns the
## decision about what an interaction means.

var skin
var sprite_key: String = ""
var prop_id: String = ""
var label: String = ""
var lines: Array = []
var interactive: bool = false
var highlighted: bool = false
var solid_size: Vector2 = Vector2.ZERO

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
	if highlighted:
		_pulse += delta
	queue_redraw()


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

	if highlighted:
		var glow := Color(0.37, 0.90, 0.85, 0.5)
		glow.a = 0.35 + 0.25 * sin(_pulse * 5.0)
		var w := tex.get_width() + 8
		var h := tex.get_height() + 4
		draw_rect(Rect2(round(-w * 0.5), round(-h + 2), w, h), glow, false, 1.0)

	var size := tex.get_size()
	draw_texture_rect(tex, Rect2(Vector2(round(-size.x * 0.5), round(-size.y)), size), false)

