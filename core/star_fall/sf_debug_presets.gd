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
##
## A preset is atomic and complete: every map before the target is finished as
## a player would have left it. Its authored collectibles are claimed through
## claim_salvage (or marked collected when the carry limit refuses them), the
## junction is repaired by paying its real cost, and each earlier boss is
## defeated and its dropped component picked up through defeat_boss +
## collect_boss_reward, so no reward can exist both in the inventory and as a
## world drop, and no unique component can be granted twice. None of this runs
## outside debug_jump.gd: no normal transition, menu or key reaches it.

const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const SFContent := preload("res://core/star_fall/sf_content.gd")
const SFQA := preload("res://core/star_fall/sf_qa.gd")
const SFFinale := preload("res://core/star_fall/sf_finale.gd")

## key: the digit or letter pressed with Ctrl+Shift+Alt.
## stage: the campaign stage the controller resumes at.
## position: optional exploration spot for Nick (world pixels).
const PRESETS := [
	{"id": "construction", "key": "1", "title": "P1 CONSTRUCTION CONSOLE", "stage": "construction"},
	{"id": "crash_site", "key": "2", "title": "P1 CRASH SITE", "stage": "crash_site"},
	{"id": "forgotten_city", "key": "3", "title": "P2 FORGOTTEN CITY", "stage": "city_intro"},
	{"id": "scrap_king", "key": "4", "title": "P2 SCRAP KING ECO ARENA", "stage": "city_boss"},
	{"id": "silent_coast", "key": "5", "title": "P2 SILENT COAST", "stage": "silent_intro"},
	{"id": "toxic_tide", "key": "6", "title": "P2 TOXIC TIDE FIGHT", "stage": "coast_boss"},
	{"id": "dawn_tower", "key": "7", "title": "P3 DAWN TOWER GATE", "stage": "dawn_intro", "position": Vector2(360, 150)},
	{"id": "sky_remnant", "key": "8", "title": "P3 SKY REMNANT FIGHT", "stage": "dawn_boss"},
	{"id": "shield_drop", "key": "9", "title": "P3 SHIELD DROP", "stage": "dawn_intro", "position": Vector2(372, 150)},
	{"id": "workshop", "key": "0", "title": "P3 WORKSHOP", "stage": "reconstruction"},
	# Phase 4 uses letters: the digits are taken, and I/O/P stay vocabulary letters.
	{"id": "final_assembly", "key": "F", "title": "P4 READY FOR FINAL ASSEMBLY", "stage": "ready_for_final_assembly"},
	{"id": "escape", "key": "E", "title": "P4 ESCAPE CINEMATIC", "stage": "escape"},
	{"id": "mission_report", "key": "R", "title": "P4 MISSION REPORT", "stage": "return_home"},
	{"id": "credits", "key": "C", "title": "P4 CREDITS", "stage": "credits"},
]

const RECONSTRUCTION_PATH := "res://data/star_fall/reconstruction.json"

## Authored collectible ids per map, as placed in data/star_fall/sites.json.
## The boss drops are not listed: they are awarded only through the boss rules.
const SITE_COLLECTIBLES := {
	"crash_site": ["salvage_plate", "salvage_polymer", "salvage_circuit", "scrap_extra"],
	"forgotten_city": ["salvage_city_scrap", "salvage_city_boards", "salvage_city_frame"],
	"silent_coast": ["salvage_coast_plate", "salvage_coast_cable"],
	"dawn_tower": ["salvage_dawn_frame", "salvage_dawn_cells", "salvage_dawn_seal"],
}
## The coast's optional terminal and samples: [collected id, material, amount],
## matching what main.gd grants for reading or taking them.
const COAST_EXTRAS := [
	["coast_records_read", "circuitry", 2],
	["sample_coast_water", "polymer", 1],
	["sample_coast_sediment", "circuitry", 1],
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
	"final_assembly": 11,
	"escape": 12,
	"mission_report": 13,
	"credits": 14,
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
		# The rest of Phase 1: salvage gathered, wreck inspected, junction paid
		# for and live, Bill awake, memory seen.
		_clear_site(campaign, "crash_site")
		campaign.set_flag(SFCampaign.FLAG_VELA_INSPECTED)
		if not bool(campaign.repair_junction().get("ok", false)):
			campaign.set_flag(SFCampaign.FLAG_POWER_REPAIRED)
		campaign.set_flag(SFCampaign.FLAG_BILL_ACTIVE)
		campaign.view_memory(SFCampaign.MEMORY_GREEN_CITY)
		campaign.set_flag(SFCampaign.FLAG_COORDINATES_RECEIVED)
		campaign.set_flag(SFCampaign.FLAG_CITY_ENTERED)
	if step >= 4:
		campaign.set_flag(SFCampaign.FLAG_CITY_CHECKPOINT)
	if step >= 5:
		_clear_site(campaign, "forgotten_city")
		campaign.defeat_boss(SFCampaign.FLAG_SCRAP_KING_DEFEATED)
		campaign.collect_boss_reward(SFCampaign.FLAG_SCRAP_KING_DEFEATED, SFCampaign.COMPONENT_NAVIGATION_CHIP)
		campaign.restore_archive(SFCampaign.ARCHIVE_CITY)
		campaign.reveal_future_earth()
		campaign.set_flag(SFCampaign.FLAG_COAST_ENTERED)
	if step >= 6:
		campaign.set_flag(SFCampaign.FLAG_COAST_CHECKPOINT)
	if step >= 7:
		_clear_site(campaign, "silent_coast")
		for extra in COAST_EXTRAS:
			if campaign.mark_collected(String(extra[0])):
				campaign.add_material(String(extra[1]), int(extra[2]))
		campaign.defeat_boss(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED)
		campaign.collect_boss_reward(SFCampaign.FLAG_TOXIC_TIDE_DEFEATED, SFCampaign.COMPONENT_POWER_CORE)
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
		_clear_site(campaign, "dawn_tower")
		campaign.collect_boss_reward(SFCampaign.FLAG_SKY_REMNANT_DEFEATED, SFCampaign.COMPONENT_SHIELD_EMITTER)
		campaign.restore_archive(SFCampaign.ARCHIVE_DAWN)
		campaign.complete_dawn_tower()
	# Phase 4: the same calls the QA milestones and the real finale make, so the
	# save passes the load-time finale checks (committed design, frozen snapshot).
	if step >= 11:
		var recon: Dictionary = SFContent.read_json(RECONSTRUCTION_PATH) as Dictionary
		if not bool(SFQA.apply_valid_reconstruction(campaign, recon).get("ok", false)):
			push_error("Debug preset %s: no valid workshop design could be fabricated" % id)
			return false
		if step >= 12:
			campaign.begin_final_assembly(SFFinale.snapshot(campaign, recon))
	if step >= 13:
		campaign.complete_return()
	if step >= 14:
		campaign.mark_report_seen()

	var stage := String(p["stage"])
	campaign.advance_to(stage)
	campaign.set_checkpoint(stage, campaign.chapter_id)
	return true


## Finishes one map's authored collectibles the way a player would.
static func _clear_site(campaign, site_id: String) -> void:
	for id in SITE_COLLECTIBLES.get(site_id, []):
		if not bool(campaign.claim_salvage(String(id)).get("ok", false)):
			campaign.mark_collected(String(id))
