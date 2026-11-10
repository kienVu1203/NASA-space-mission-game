extends Node
## Shared mission state. Screens read/write here; they never call each other.

var budget_total: float = 0.0
var budget_spent: float = 0.0
var mass_limit_kg: float = 0.0
var power_limit_w: float = 0.0
var selected: Dictionary = {} # e.g. {"destination": id, "launch_vehicle": id, "instruments": [ids]}

func reset() -> void:
	budget_spent = 0.0
	selected = {}
