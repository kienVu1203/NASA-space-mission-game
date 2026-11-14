extends Node
## Signal bus. Emit/connect here instead of referencing other screens.
##
## A signal's payload is data only: never a node reference. Screens translate
## events into their own local presentation.

# --- STAR FALL campaign -------------------------------------------------------

## Emitted whenever the campaign stage changes. The main controller listens.
signal campaign_stage_changed(previous_stage: String, next_stage: String)
## Emitted when the ship design is modified (preview never emits this).
signal design_changed
## Emitted when the design passes preflight validation.
signal preflight_passed
## Emitted when preflight validation is attempted and fails.
signal preflight_failed(first_message: String)
## Emitted when a salvage object is collected.
signal salvage_collected(object_id: String, material: String, amount: int)
## Emitted when the inventory cannot accept a pickup.
signal inventory_full
## Emitted when a quest flag changes.
signal quest_flag_changed(flag: String, value: bool)
## Emitted when a memory is viewed.
signal memory_viewed(memory_id: String)
## Emitted for short on-screen notices ("+3 Scrap Metal").
signal notice(text: String, tone: String)
## Emitted after a save is written successfully.
signal game_saved
## Emitted when a save operation fails, with a player-facing reason.
signal save_failed(reason: String)

# --- Legacy mission-planner demo ---------------------------------------------
signal design_confirmed
signal simulation_finished(success: bool)
signal restart_requested
