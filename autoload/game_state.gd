extends Node
## Shared state for the whole application.
##
## Two independent stores live here, deliberately:
##   campaign  - STAR FALL's persistent adventure state (owned by core/star_fall
##               sf_campaign.gd). Screens read and request changes through it.
##   budget_*  - the legacy NASA mission-planner demo state, kept so the old
##               skeleton screens and its tests still work.
##
## Screens never call each other. They read here and communicate through Events.
const SFCampaign := preload("res://core/star_fall/sf_campaign.gd")


# --- STAR FALL campaign -------------------------------------------------------
var campaign

# --- Legacy mission-planner demo state ---------------------------------------
var budget_total: float = 0.0
var budget_spent: float = 0.0
var mass_limit_kg: float = 0.0
var power_limit_w: float = 0.0
var selected: Dictionary = {} # e.g. {"destination": id, "launch_vehicle": id, "instruments": [ids]}


func _ready() -> void:
	campaign = SFCampaign.new()


## Legacy demo reset. Leaves the STAR FALL campaign untouched on purpose.
func reset() -> void:
	budget_spent = 0.0
	selected = {}


func reset_campaign() -> void:
	if campaign == null:
		campaign = SFCampaign.new()
	campaign.reset_campaign()
