extends Node2D
## In-world HUD. Lives on its own CanvasLayer above the world node, because a
## Node2D's children always draw above the parent's own `_draw()`.
##
## Drawing must happen here rather than being forwarded to the controller:
## Godot only allows draw_* calls inside the node's own `_draw()`.

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")

var game = null
var blink: float = 0.0


func _process(delta: float) -> void:
	blink += delta
	queue_redraw()


func _draw() -> void:
	if game == null or game.world == null or game.campaign == null:
		return
	var skin = game.skin
	var ui = game.ui
	var campaign = game.campaign

	# Objective and zone header.
	var objective: String = _objective_text()
	var rows: Array = []
	if campaign.chapter_id == SFCampaign.CHAPTER_CRASH:
		for m in ["scrap_metal", "circuitry", "polymer"]:
			var n: int = campaign.material_count(String(m))
			if n > 0:
				rows.append("%d  %s" % [n, campaign.content.material_name(String(m)).to_upper()])
		ui.hud(self, campaign, objective, rows, "UNIDENTIFIED SITE")
	else:
		ui.hud(self, campaign, objective, rows, "SPACEPORT WORKSHOP")

	# Interaction prompt for whatever Nick is standing next to.
	if game.dialogue == null and game.world.focused_prop() != null:
		var prop = game.world.focused_prop()
		var label := String(prop.label)
		if label == "":
			label = "Interact"
		ui.prompt(self, label, blink)

	if campaign.chapter_id == SFCampaign.CHAPTER_PRESENT:
		skin.text_r(self, 628, 348, "DAY ONE", SFPalette.ASH_LIGHT)

	# Dialogue sits above the HUD, and locks movement while it is open.
	if game.dialogue != null:
		ui.dialogue_box(self, game.dialogue, game.dialogue_title)

	# Pause overlay and toasts are the top-most layers.
	if game.is_pause_open():
		_draw_pause(skin, ui)

	ui.toast(self)


func _draw_pause(skin, ui) -> void:
	ui.modal(self, Rect2(200, 96, 240, 146), SFPalette.CYAN)
	skin.text_c(self, 320, 108, "PAUSED", SFPalette.CYAN)
	ui.menu_list(self, game.pause_menu, Vector2(216, 126), 208.0, 20.0)
	skin.text_c(self, 320, 222, "ESC RESUME", SFPalette.PAPER_DIM)


func _objective_text() -> String:
	var campaign = game.campaign
	if campaign.chapter_id == SFCampaign.CHAPTER_PRESENT:
		if not campaign.has_flag(SFCampaign.FLAG_BRIEFING_READ):
			return "Read the mission briefing [E]"
		if not campaign.has_flag(SFCampaign.FLAG_DESIGN_CONFIRMED):
			return "Build the VELA at the console [E]"
		return "Launch from the pad beacon [E]"
	if not campaign.has_flag(SFCampaign.FLAG_VELA_INSPECTED):
		return "Inspect the wreck [E]"
	if not campaign.has_flag(SFCampaign.FLAG_POWER_REPAIRED):
		return "Salvage material, repair the junction"
	if not campaign.has_flag(SFCampaign.FLAG_BILL_ACTIVE):
		return "Wake the maintenance unit"
	if not campaign.has_flag(SFCampaign.FLAG_COORDINATES_RECEIVED):
		return "View the memory"
	return "Coordinates received"
