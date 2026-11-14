extends RefCounted
## Developer test shortcuts: campaign states for jumping straight to each
## phase. Pure logic: no nodes, no input. scenes/star_fall/debug_jump.gd maps
## key chords onto these presets and asks the controller to resume.
##
## Each preset is cumulative and goes through the same campaign methods the
## real flow uses (confirm_design, view_memory, restore_archive,
## reveal_future_earth, complete_silent_coast, defeat_boss,
## collect_boss_reward, complete_dawn_tower), so the result is a state the game
## can reach legitimately, never an impossible flag mix. Debug builds only.

const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")

## key: the digit or letter pressed with Ctrl+Shift+Alt.
## stage: the campaign stage the controller resumes at.
## position: optional exploration spot for Nick (world pixels).
const PRESETS := [
	{"id": "construction", "key": "1", "title": "P1 CONSTRUCTION CONSOLE", "stage": "construction"},
	{"id": "crash_site", "key": "2", "title": "P1 CRASH SITE", "stage": "crash_site"},
	{"id": "forgotten_city", "key": "3", "title": "P2 FORGOTTEN CITY", "stage": "city_intro"},
	{"id": "scrap_king", "key": "4", "title": "P2 SCRAP KING FIGHT", "stage": "city_boss"},
	{"id": "silent_coast", "key": "5", "title": "P2 SILENT COAST", "stage": "silent_intro"},
	{"id": "toxic_tide", "key": "6", "title": "P2 TOXIC TIDE FIGHT", "stage": "coast_boss"},
	{"id": "dawn_tower", "key": "7", "title": "P3 DAWN TOWER GATE", "stage": "dawn_intro", "position": Vector2(360, 150)},
	{"id": "sky_remnant", "key": "8", "title": "P3 SKY REMNANT FIGHT", "stage": "dawn_boss"},
	{"id": "shield_drop", "key": "9", "title": "P3 SHIELD DROP", "stage": "dawn_intro", "position": Vector2(372, 150)},
	{"id": "workshop", "key": "0", "title": "P3 WORKSHOP", "stage": "reconstruction"},
]

## How far each preset runs through the campaign, in order.
const STEPS := {
	"construction": 1,
	"crash_site": 2,
	"forgotten_city": 3,
	"scrap_king": 4,
	"silent_coast": 5,
	"toxic_tide": 6,
	"dawn_tower": 7,
	"sky_remnant": 8,
	"shield_drop": 9,
	"workshop": 10,
}


static func preset(id: String) -> Dictionary:
	for p in PRESETS:
		if String((p as Dictionary)["id"]) == id:
			return p
	return {}


static func preset_for_key(key: String) -> Dictionary:
	for p in PRESETS:
		if String((p as Dictionary)["key"]) == key:
			return p
	return {}


## Replaces the campaign with the state for preset `id`. Returns false for an
## unknown id, leaving the campaign untouched.
static func apply(campaign, id: String) -> bool:
	var p := preset(id)
	if p.is_empty():
		return false
	var step := int(STEPS[id])
	campaign.reset_campaign()

	# Phase 1: briefing read and a valid design ready (config A in the contract).
	campaign.set_flag(SFCampaign.FLAG_BRIEFING_READ)
	var d = campaign.design
	d.set_slot("computer", "flight_computer_standard")
	d.set_slot("propulsion", "propulsion_light")
	d.set_slot("power", "power_solar_array")
	d.set_slot("communications", "comms_standard")
	d.set_slot("sensor", "sensor_spectrometer")
	d.fuel_kg = 240.0
	if step >= 2:
		campaign.confirm_design()
		campaign.set_flag(SFCampaign.FLAG_LAUNCHED)
		campaign.set_flag(SFCampaign.FLAG_RIFT_SEEN)
		campaign.set_flag(SFCampaign.FLAG_CRASHED)
	if step >= 3:
		# The rest of Phase 1: wreck inspected, junction live, Bill awake, memory.
		campaign.set_flag(SFCampaign.FLAG_VELA_INSPECTED)
		campaign.set_flag(SFCampaign.FLAG_POWER_REPAIRED)
		campaign.set_flag(SFCampaign.FLAG_BILL_ACTIVE)
		campaign.view_memory(SFCampaign.MEMORY_GREEN_CITY)
		campaign.set_flag(SFCampaign.FLAG_COORDINATES_RECEIVED)
		campaign.set_flag(SFCampaign.FLAG_CITY_ENTERED)
	if step >= 4:
		campaign.set_flag(SFCampaign.FLAG_CITY_CHECKPOINT)
	if step >= 5:
		campaign.set_flag(SFCampaign.FLAG_SCRAP_KING_DEFEATED)
		campaign.award_component(SFCampaign.COMPONENT_NAVIGATION_CHIP)
		campaign.restore_archive(SFCampaign.ARCHIVE_CITY)
		campaign.reveal_future_earth()
		campaign.set_flag(SFCampaign.FLAG_COAST_ENTERED)
	if step >= 6:
		campaign.set_flag(SFCampaign.FLAG_COAST_CHECKPOINT)
	if step >= 7:
		campaign.set_flag(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED)
		campaign.award_component(SFCampaign.COMPONENT_POWER_CORE)
		campaign.restore_archive(SFCampaign.ARCHIVE_COAST)
		campaign.complete_silent_coast()
		campaign.set_flag(SFCampaign.FLAG_BASE_RETURNED)
		# Dawn Tower: intro seen, forest memory viewed, checkpoint used.
		campaign.set_flag(SFCampaign.FLAG_DAWN_ENTERED)
		campaign.view_memory(SFCampaign.MEMORY_HEALTHY_FOREST)
		campaign.set_flag(SFCampaign.FLAG_DAWN_CHECKPOINT)
	if step >= 8:
		campaign.set_flag(SFCampaign.FLAG_TYPING_TUTORIAL_SEEN)
	if step >= 9:
		campaign.defeat_boss(SFCampaign.FLAG_SKY_REMNANT_DEFEATED)
	if step >= 10:
		campaign.collect_boss_reward(SFCampaign.FLAG_SKY_REMNANT_DEFEATED, SFCampaign.COMPONENT_SHIELD_EMITTER)
		campaign.restore_archive(SFCampaign.ARCHIVE_DAWN)
		campaign.complete_dawn_tower()

	var stage := String(p["stage"])
	campaign.advance_to(stage)
	campaign.set_checkpoint(stage, campaign.chapter_id)
	return true
