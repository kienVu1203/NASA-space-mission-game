extends RefCounted
## Campaign milestone planner, used by the headless tests and the capture tool
## to walk a campaign forward one checkpoint at a time.
##
## The former player-facing `I + O + P` stage skip has been removed: this module
## no longer reads keys, launch flags or build type, and nothing in the game's
## input path calls it. `main.gd::_apply_qa_skip()` applies each milestone
## through the same campaign methods the normal flow uses, which keeps a walked
## campaign in a legal state; only test scripts call it.
##
## Planning: which campaign milestone is next, and whether it is already done.
## The plan is derived from recorded campaign state, never from the screen that
## happens to be open. This module never mutates the campaign and never touches
## a node, except for the two `apply_valid_*` helpers the tests use to build a
## legal design.

const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")
const SFReconstruction := preload("res://core/star_fall/sf_reconstruction.gd")
const SFReturnSim := preload("res://core/star_fall/sf_return_sim.gd")


# Milestones, in the order the campaign reaches them. Each one is a checkpoint
# boundary; the controller turns one into the state changes plus the screen.
const MILESTONE_BRIEFING := "briefing"
const MILESTONE_CONSTRUCTION := "construction"
const MILESTONE_BILL := "bill"
const MILESTONE_PHASE_ONE := "phase_one"
const MILESTONE_CITY := "city"
const MILESTONE_COAST := "coast"
const MILESTONE_PHASE_TWO := "phase_two"
const MILESTONE_DAWN := "dawn"
const MILESTONE_WORKSHOP := "workshop"
const MILESTONE_READY := "ready"
const MILESTONE_FINALE := "finale"
const MILESTONE_REPORT := "report"
const MILESTONE_DONE := "done"

const ORDER := [
	MILESTONE_BRIEFING,
	MILESTONE_CONSTRUCTION,
	MILESTONE_BILL,
	MILESTONE_PHASE_ONE,
	MILESTONE_CITY,
	MILESTONE_COAST,
	MILESTONE_PHASE_TWO,
	MILESTONE_DAWN,
	MILESTONE_WORKSHOP,
	MILESTONE_READY,
	MILESTONE_FINALE,
	MILESTONE_REPORT,
	MILESTONE_DONE,
]


## The next milestone the campaign has not reached yet.
static func next_milestone(campaign) -> String:
	for id in ORDER:
		if not milestone_done(campaign, String(id)):
			return String(id)
	return MILESTONE_DONE


static func milestone_index(id: String) -> int:
	return ORDER.find(id)


static func milestone_done(campaign, id: String) -> bool:
	# Judged from the stage, which only ever moves forward. A milestone is done
	# once the campaign has reached the stage that milestone lands on, so the
	# same press has the same meaning from any screen (including after Continue
	# on a save whose flags were written by an earlier phase).
	var at: int = _landing_index(id)
	if at < 0:
		return false
	return campaign.stage_index() >= at or _explicit_evidence(campaign, id)


## The stage index a milestone lands the campaign on, or -1 when it is terminal.
static func _landing_index(id: String) -> int:
	var order: Array = SFCampaign.STAGE_ORDER
	match id:
		MILESTONE_BRIEFING:
			return order.find(SFCampaign.STAGE_CONSTRUCTION)
		MILESTONE_CONSTRUCTION:
			return order.find(SFCampaign.STAGE_CRASH_SITE)
		MILESTONE_BILL:
			return order.find(SFCampaign.STAGE_CHECKPOINT)
		MILESTONE_PHASE_ONE:
			return order.find(SFCampaign.STAGE_CITY_INTRO)
		MILESTONE_CITY:
			return order.find(SFCampaign.STAGE_SILENT_INTRO)
		MILESTONE_COAST:
			return order.find(SFCampaign.STAGE_BASE_RETURN)
		MILESTONE_PHASE_TWO:
			return order.find(SFCampaign.STAGE_DAWN_INTRO)
		MILESTONE_DAWN:
			return order.find(SFCampaign.STAGE_RECONSTRUCTION)
		MILESTONE_WORKSHOP:
			return order.find(SFCampaign.STAGE_READY)
		MILESTONE_READY:
			return order.find(SFCampaign.STAGE_FINAL_ASSEMBLY)
		MILESTONE_FINALE:
			return order.find(SFCampaign.STAGE_MISSION_REPORT)
		MILESTONE_REPORT:
			return order.find(SFCampaign.STAGE_CREDITS)
		MILESTONE_DONE:
			return -1
	return -1


## Flags that prove a milestone was reached even when a save's stage is older.
## Kept narrow on purpose: the stage is the authority; these only cover stages
## that were rewritten by Phase 3 saves (the "complete" stopping point).
static func _explicit_evidence(campaign, id: String) -> bool:
	match id:
		MILESTONE_BRIEFING:
			return campaign.has_flag(SFCampaign.FLAG_BRIEFING_READ)
		MILESTONE_CONSTRUCTION:
			return campaign.has_flag(SFCampaign.FLAG_DESIGN_CONFIRMED) and campaign.has_confirmed_design()
		MILESTONE_WORKSHOP:
			return campaign.is_ready_for_final_assembly() and campaign.reconstruction.has("committed")
		MILESTONE_PHASE_ONE:
			return campaign.has_flag(SFCampaign.FLAG_CITY_ENTERED)
		MILESTONE_PHASE_TWO:
			return campaign.has_flag(SFCampaign.FLAG_DAWN_TOWER_UNLOCKED) \
				and campaign.has_flag(SFCampaign.FLAG_PHASE_TWO_COMPLETE)
		MILESTONE_READY:
			return campaign.has_final_assembly_snapshot()
		MILESTONE_FINALE:
			return campaign.is_return_complete()
		MILESTONE_REPORT:
			return campaign.has_flag(SFCampaign.FLAG_MISSION_REPORT_SEEN)
	return false


## A short human label for the overlay and the test output.
static func milestone_label(id: String) -> String:
	match id:
		MILESTONE_BRIEFING:
			return "BRIEFING"
		MILESTONE_CONSTRUCTION:
			return "CONSTRUCTION / PREFLIGHT"
		MILESTONE_BILL:
			return "CRASH SITE / BILL"
		MILESTONE_PHASE_ONE:
			return "PHASE 1 CHECKPOINT"
		MILESTONE_CITY:
			return "FORGOTTEN CITY / SCRAP KING"
		MILESTONE_COAST:
			return "SILENT COAST / TOXIC TIDE"
		MILESTONE_PHASE_TWO:
			return "BASE RETURN / PHASE 2"
		MILESTONE_DAWN:
			return "DAWN TOWER / SKY REMNANT"
		MILESTONE_WORKSHOP:
			return "RECONSTRUCTION WORKSHOP"
		MILESTONE_READY:
			return "FINAL ASSEMBLY"
		MILESTONE_FINALE:
			return "ESCAPE / RETURN HOME"
		MILESTONE_REPORT:
			return "MISSION REPORT"
		MILESTONE_DONE:
			return "CREDITS"
	return id.to_upper()


## Builds and confirms a valid day-one design from the shipped data. Used only
## when a QA skip passes the construction stage without playing it. Every value
## still comes from ship_parts.json and the real validator, so the confirmed
## design and manifest are exactly what a player could have produced.
static func apply_valid_day_one_design(campaign) -> bool:
	if campaign.has_confirmed_design() and campaign.has_flag(SFCampaign.FLAG_DESIGN_CONFIRMED):
		return true
	var content = campaign.content
	var slots: Array = content.required_slots()
	if slots.is_empty():
		return false
	# Fuel: the requirement first, then one step at a time to the tank limit. The
	# real validator decides; this only supplies a legal search space.
	var step := float(content.program.get("fuel_step_kg", 20.0))
	var min_fuel := float(content.requirements.get("minimum_fuel_kg", 180.0))
	var capacity := float(content.hull.get("fuel_capacity_kg", 600.0))
	var fuels: Array = []
	var fuel := min_fuel
	while fuel <= capacity:
		fuels.append(fuel)
		fuel += step
	var chosen: Dictionary = {}
	if not _choose_slots(content, slots, 0, chosen, fuels):
		return false
	for slot in chosen.keys():
		campaign.design.set_slot(String(slot), String(chosen[slot]))
	# The fuel that made the combination valid is applied last, so the confirmed
	# design carries exactly the propellant the validator checked.
	var applied := false
	for f in fuels:
		campaign.design.set_fuel(float(f), content)
		if campaign.design.is_valid(content):
			applied = true
			break
	if not applied:
		return false
	var result: Dictionary = campaign.confirm_design()
	return bool(result.get("ok", false))


## Breadth-limited search over the required slots. A combination only counts when
## the shipped validator accepts it at one of the candidate fuel loads, so the
## design this returns is a design the player could really have confirmed.
static func _choose_slots(content, slots: Array, index: int, chosen: Dictionary, fuels: Array) -> bool:
	if index >= slots.size():
		return _combination_is_valid(content, chosen, fuels)
	var slot := String(slots[index])
	var options: Array = content.components_for_slot(slot)
	if options.is_empty():
		return false
	for entry in options:
		var comp: Dictionary = entry
		chosen[slot] = String(comp.get("id", ""))
		if _choose_slots(content, slots, index + 1, chosen, fuels):
			return true
	chosen.erase(slot)
	return false


static func _combination_is_valid(content, chosen: Dictionary, fuels: Array) -> bool:
	var probe = campaign_design_script(content)
	if probe == null:
		return false
	var d = probe.new()
	for slot in chosen.keys():
		d.set_slot(String(slot), String(chosen[slot]))
	for f in fuels:
		d.set_fuel(float(f), content)
		if d.is_valid(content):
			return true
	return false


## The design script, loaded lazily so this module has no import cycle with the
## campaign. Returns null when it cannot be loaded.
static func campaign_design_script(content):
	if content == null:
		return null
	var res = load("res://core/star_fall/sf_design.gd")
	return res


## Builds a passing reconstruction design, certifies it, replenishes the fair
## material floor and fabricates it once. Used only when a QA skip passes the
## workshop. Every number comes from reconstruction.json and the real
## simulation, so the committed record is a design a player could have built.
static func apply_valid_reconstruction(campaign, reconstruction_data: Dictionary) -> Dictionary:
	if campaign.is_ready_for_final_assembly() and campaign.reconstruction.has("committed"):
		return {"ok": true, "message": "Already assembled."}
	var ws = SFReconstruction.new()
	ws.setup(reconstruction_data, campaign.original_propulsion_id(), {})
	var report: Dictionary = {}
	var fuels: Array = [0.0, 200.0, 400.0, 600.0, 800.0]
	for f in fuels:
		ws.set_fuel(float(f))
		report = ws.simulate(campaign.recovered_component_ids(), 30303)
		if bool(report.get("valid", false)):
			break
	if not bool(report.get("valid", false)):
		# Last attempt: exactly the propellant the simulation says it needs.
		var totals: Dictionary = report.get("totals", {}) as Dictionary
		ws.set_fuel(float(totals.get("propellant_needed_kg", 0.0)))
		report = ws.simulate(campaign.recovered_component_ids(), 30303)
	if not bool(report.get("valid", false)):
		return {"ok": false, "message": "No passing automated design."}
	# The workshop requires every recovered component to be fitted before it will
	# fabricate, so a skipped run installs them exactly as the workshop screen
	# would. install_component() applies its own rules (must be recovered, not
	# already fitted, not past final assembly).
	for id in SFReturnSim.REQUIRED_COMPONENTS:
		campaign.install_component(String(id))
	ws.replenish(campaign)
	var committed: Dictionary = ws.commit(campaign, report)
	return committed
