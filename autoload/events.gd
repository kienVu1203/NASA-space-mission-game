extends Node
## Signal bus. Emit/connect here instead of referencing other screens.

signal design_confirmed
signal simulation_finished(success: bool)
signal restart_requested
