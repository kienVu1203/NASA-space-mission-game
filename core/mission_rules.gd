class_name MissionRules
## Win/lose and scoring rules. Pure functions.

static func within_budget(spent: float, total: float) -> bool:
	return spent <= total
