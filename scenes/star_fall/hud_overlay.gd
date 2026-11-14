extends Node2D
## In-world HUD. Lives on its own CanvasLayer above the world node, because a
## Node2D's children always draw above the parent's own `_draw()`.
##
## Drawing must happen here rather than being forwarded to the controller:
## Godot only allows draw_* calls inside the node's own `_draw()`.
##
## The overlay outlives any one screen: the dialogue box is drawn here for every
## screen (the duel, the archives, the memories), so a single dialogue model and
## a single input path serve the whole campaign. World-only elements (objective,
## inventory, interaction prompt, pause) are guarded on `game.world`.

const SFPalette := preload("res://core/star_fall/sf_palette.gd")
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")

var game = null
var blink: float = 0.0


func _process(delta: float) -> void:
	blink += delta
	queue_redraw()


func _draw() -> void:
	if game == null or game.campaign == null:
		return
	var skin = game.skin
	var ui = game.ui
	var campaign = game.campaign

	if game.world != null:
		# Objective and zone header.
		var objective: String = _objective_text()
		var rows: Array = []
		if campaign.chapter_id != SFCampaign.CHAPTER_PRESENT:
			for m in ["scrap_metal", "circuitry", "polymer"]:
				var n: int = campaign.material_count(String(m))
				if n > 0:
					rows.append("%d  %s" % [n, campaign.content.material_name(String(m)).to_upper()])
		ui.hud(self, campaign, objective, rows, _zone_title())

		# Directional route cue for Phase 2 checkpoints and unlocked exits.
		if game.dialogue == null and not game.is_pause_open():
			_draw_route_cue(skin, campaign)

		# Interaction prompt for whatever Nick is standing next to.
		if game.dialogue == null and game.world.focused_prop() != null:
			var prop = game.world.focused_prop()
			var label := String(prop.label)
			if label == "":
				label = "Interact"
			ui.prompt(self, label, blink)

		if campaign.chapter_id == SFCampaign.CHAPTER_PRESENT:
			skin.text_r(self, 628, 348, "DAY ONE", SFPalette.ASH_LIGHT)

		# Pause overlay and toasts are the top-most layers.
		if game.is_pause_open():
			_draw_pause(skin, ui)

		ui.toast(self)

	# Dialogue sits above every screen, and locks movement while it is open.
	if game.dialogue != null:
		ui.dialogue_box(self, game.dialogue, game.dialogue_title)


func _draw_pause(skin, ui) -> void:
	ui.modal(self, Rect2(200, 96, 240, 146), SFPalette.CYAN)
	skin.text_c(self, 320, 108, "PAUSED", SFPalette.CYAN)
	ui.menu_list(self, game.pause_menu, Vector2(216, 126), 208.0, 20.0)
	skin.text_c(self, 320, 222, "ESC RESUME", SFPalette.PAPER_DIM)


func _zone_title() -> String:
	var campaign = game.campaign
	match campaign.chapter_id:
		SFCampaign.CHAPTER_PRESENT:
			return "SPACEPORT WORKSHOP"
		SFCampaign.CHAPTER_CITY:
			return "FORGOTTEN CITY"
		SFCampaign.CHAPTER_COAST:
			return "SILENT COAST"
	return "UNIDENTIFIED SITE"


func _objective_text() -> String:
	var campaign = game.campaign
	if campaign.chapter_id == SFCampaign.CHAPTER_PRESENT:
		if not campaign.has_flag(SFCampaign.FLAG_BRIEFING_READ):
			return "Read the mission briefing [E]"
		if not campaign.has_flag(SFCampaign.FLAG_DESIGN_CONFIRMED):
			return "Build the VELA at the console [E]"
		return "Launch from the pad beacon [E]"

	if campaign.chapter_id == SFCampaign.CHAPTER_CITY:
		if not campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED):
			if not campaign.has_flag(SFCampaign.FLAG_CITY_CHECKPOINT):
				return "Find the checkpoint, then the control center"
			return "UNLOCKED: Enter the control center [E]"
		if not campaign.has_flag(SFCampaign.FLAG_CITY_ARCHIVE_RESTORED):
			return "Restore the control-center archive"
		return "NEXT ROUTE: Proceed to Silent Coast [E]"

	if campaign.chapter_id == SFCampaign.CHAPTER_COAST:
		if not campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED):
			if not campaign.has_flag(SFCampaign.FLAG_COAST_CHECKPOINT):
				return "Find the harbor checkpoint"
			return "UNLOCKED: Enter the cleanup facility [E]"
		if not campaign.has_flag(SFCampaign.FLAG_COAST_ARCHIVE_RESTORED):
			return "Restore the environmental archive"
		return "NEXT ROUTE: Return to crash-site base [E]"

	if not campaign.has_flag(SFCampaign.FLAG_VELA_INSPECTED):
		return "Inspect the wreck [E]"
	if not campaign.has_flag(SFCampaign.FLAG_POWER_REPAIRED):
		return "Salvage material, repair the junction"
	if not campaign.has_flag(SFCampaign.FLAG_BILL_ACTIVE):
		return "Wake the maintenance unit"
	if not campaign.has_flag(SFCampaign.FLAG_COORDINATES_RECEIVED):
		return "View the memory"
	if campaign.has_flag(SFCampaign.FLAG_PHASE_TWO_COMPLETE):
		return "Dawn Tower is unlocked"
	return "Coordinates received"


func _draw_route_cue(skin, campaign) -> void:
	if game.world == null or game.world.player == null:
		return
	var target_prop_id := ""
	var cue_label := ""
	var accent: Color = SFPalette.CYAN
	if campaign.chapter_id == SFCampaign.CHAPTER_CITY:
		if not campaign.has_flag(SFCampaign.FLAG_CITY_CHECKPOINT) and not campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED):
			target_prop_id = "city_checkpoint"
			cue_label = "STEP 1: CHECKPOINT"
			accent = SFPalette.GOLD
		else:
			target_prop_id = "city_boss_gate"
			cue_label = "EXIT: SILENT COAST" if campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED) else "EXIT UNLOCKED: CONTROL CENTER"
			accent = SFPalette.GREEN_OK if campaign.has_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED) else SFPalette.CYAN
	elif campaign.chapter_id == SFCampaign.CHAPTER_COAST:
		if not campaign.has_flag(SFCampaign.FLAG_COAST_CHECKPOINT) and not campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED):
			target_prop_id = "coast_checkpoint"
			cue_label = "STEP 1: HARBOR CHECKPOINT"
			accent = SFPalette.GOLD
		else:
			target_prop_id = "coast_boss_gate"
			cue_label = "EXIT: CRASH-SITE BASE" if campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED) else "EXIT UNLOCKED: CLEANUP FACILITY"
			accent = SFPalette.GREEN_OK if campaign.has_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED) else SFPalette.CYAN
	if target_prop_id == "":
		return
	var prop = game.world.prop_by_id(target_prop_id)
	if prop == null:
		return
	var delta_vec: Vector2 = prop.position - game.world.player.position
	if delta_vec.length() < 36.0:
		return
	var arrow := "->"
	if absf(delta_vec.x) >= absf(delta_vec.y) * 0.65:
		if delta_vec.y < -45.0:
			arrow = "^->" if delta_vec.x >= 0.0 else "<-^"
		elif delta_vec.y > 45.0:
			arrow = "v->" if delta_vec.x >= 0.0 else "<-v"
		else:
			arrow = "->" if delta_vec.x >= 0.0 else "<-"
	else:
		arrow = "^" if delta_vec.y < 0.0 else "v"
	var text := "%s  %s" % [cue_label, arrow]
	var pulse: float = 0.65 + 0.35 * sin(blink * 4.5)
	var tw: float = skin.font.text_width(text) + 14.0
	var box := Rect2(628.0 - tw, 32.0, tw, 13.0)
	draw_rect(box, Color(0.02, 0.05, 0.06, 0.88), true)
	draw_rect(box, Color(accent.r, accent.g, accent.b, 0.85 * pulse), false, 1.0)
	skin.text_c(self, box.position.x + box.size.x * 0.5, box.position.y + 3.0, text, accent)
