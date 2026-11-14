extends RefCounted
## A vertical menu model used by the main menu, pause menu, settings and the
## construction part list. Pure selection logic: no nodes, no drawing.
##
## Item shape: {"id": String, "label": String, "detail": String,
##              "enabled": bool, "tone": String}

var items: Array = []
var index: int = 0


func set_items(list: Array, keep_id: String = "") -> void:
	items = list.duplicate(true)
	if keep_id != "":
		for i in items.size():
			if String((items[i] as Dictionary).get("id", "")) == keep_id:
				index = i
				return
	index = clampi(index, 0, maxi(0, items.size() - 1))


func size() -> int:
	return items.size()


func is_empty() -> bool:
	return items.is_empty()


func clamp_index() -> void:
	index = clampi(index, 0, maxi(0, items.size() - 1))


func move(delta_index: int) -> void:
	if items.is_empty():
		return
	var n := items.size()
	index = int(fposmod(float(index + delta_index), float(n)))


## Moves to the next enabled item, skipping disabled entries. Falls back to a
## plain move when everything is disabled so the cursor can never get stuck.
func move_enabled(direction: int) -> void:
	if items.is_empty():
		return
	var n := items.size()
	var candidate := index
	for _i in n:
		candidate = int(fposmod(float(candidate + direction), float(n)))
		if bool((items[candidate] as Dictionary).get("enabled", true)):
			index = candidate
			return
	move(direction)


func current() -> Dictionary:
	if items.is_empty() or index < 0 or index >= items.size():
		return {}
	return items[index] as Dictionary


func current_id() -> String:
	return String(current().get("id", ""))


func is_current_enabled() -> bool:
	return bool(current().get("enabled", true))


func index_of(item_id: String) -> int:
	for i in items.size():
		if String((items[i] as Dictionary).get("id", "")) == item_id:
			return i
	return -1
