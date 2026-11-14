extends RefCounted
## Loads and indexes STAR FALL's JSON content. Pure data access: no nodes, no
## UI, no signals. Every tuning value and every string of prose lives in
## data/star_fall/, so balance work never requires touching a script.

const DATA_DIR := "res://data/star_fall/"
const PARTS_FILE := "ship_parts.json"
const CAMPAIGN_FILE := "campaign.json"

var program: Dictionary = {}
var hull: Dictionary = {}
var requirements: Dictionary = {}
var components: Array = []
var materials: Dictionary = {}
var salvage: Dictionary = {}
var site_items: Dictionary = {}
var repair_cost: Dictionary = {}
var future_components: Array = []
var chapters: Array = []
var missions: Array = []
var memories: Dictionary = {}
var dialogue: Dictionary = {}
var checkpoint: Dictionary = {}

var _component_by_id: Dictionary = {}
var _chapter_by_id: Dictionary = {}
var _mission_by_id: Dictionary = {}
var _loaded: bool = false


## Loads data/star_fall/*.json into this object. Returns false when either
## file is missing or malformed; callers must handle that rather than assume
## a half-populated content object.
func load_all() -> bool:
	var parts: Variant = read_json(DATA_DIR + PARTS_FILE)
	var camp: Variant = read_json(DATA_DIR + CAMPAIGN_FILE)
	if not (parts is Dictionary) or not (camp is Dictionary):
		push_error("SFContent: could not load star_fall data")
		return false
	_ingest(parts as Dictionary, camp as Dictionary)
	_loaded = true
	return true


## Test and tooling entry point: build from in-memory dictionaries.
func load_from_dicts(parts: Dictionary, camp: Dictionary) -> bool:
	_ingest(parts, camp)
	_loaded = true
	return true


func is_loaded() -> bool:
	return _loaded


static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SFContent: missing %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


func _ingest(parts: Dictionary, camp: Dictionary) -> void:
	program = _as_dict(parts.get("program", {}))
	hull = _as_dict(parts.get("hull", {}))
	requirements = _as_dict(parts.get("mission_requirements", {}))
	components = _as_array(parts.get("components", []))
	materials = _as_dict(parts.get("materials", {}))
	salvage = _as_dict(parts.get("salvage", {}))
	site_items = _as_dict(parts.get("site_items", {}))
	repair_cost = _as_dict(parts.get("repair_cost", {}))

	chapters = _as_array(camp.get("chapters", []))
	missions = _as_array(camp.get("missions", []))
	dialogue = _as_dict(camp.get("dialogue", {}))
	checkpoint = _as_dict(camp.get("checkpoint", {}))
	memories = {}
	for m in _as_array(camp.get("memories", [])):
		var memory_entry := _as_dict(m)
		memories[String(memory_entry.get("id", ""))] = memory_entry

	_component_by_id = {}
	for c in components:
		var comp := _as_dict(c)
		var id := String(comp.get("id", ""))
		if id == "":
			push_error("SFContent: component without an id")
			continue
		_component_by_id[id] = comp
	_chapter_by_id = {}
	for ch in chapters:
		var chapter_entry := _as_dict(ch)
		_chapter_by_id[String(chapter_entry.get("id", ""))] = chapter_entry
	_mission_by_id = {}
	for mi in missions:
		var mission_entry := _as_dict(mi)
		_mission_by_id[String(mission_entry.get("id", ""))] = mission_entry


# ---------------------------------------------------------------- lookups

func component(id: String) -> Dictionary:
	return _as_dict(_component_by_id.get(id, {}))


func has_component(id: String) -> bool:
	return _component_by_id.has(id)


func components_for_slot(slot: String) -> Array:
	var out: Array = []
	for c in components:
		var comp := _as_dict(c)
		if String(comp.get("slot", "")) == slot:
			out.append(comp)
	return out


func required_slots() -> Array:
	return _as_array(requirements.get("required_slots", []))


func chapter(id: String) -> Dictionary:
	return _as_dict(_chapter_by_id.get(id, {}))


func chapter_ids() -> Array:
	var out: Array = []
	for ch in chapters:
		out.append(String(_as_dict(ch).get("id", "")))
	return out


func mission(id: String) -> Dictionary:
	return _as_dict(_mission_by_id.get(id, {}))


func memory(id: String) -> Dictionary:
	return _as_dict(memories.get(id, {}))


func dialogue_lines(key: String) -> Array:
	return _as_array(dialogue.get(key, []))


func material_name(id: String) -> String:
	var m := _as_dict(materials.get(id, {}))
	return String(m.get("name", id))


func material_short(id: String) -> String:
	var m := _as_dict(materials.get(id, {}))
	return String(m.get("short", id))


func site_item_name(id: String) -> String:
	var s := _as_dict(site_items.get(id, {}))
	return String(s.get("name", id))


# ---------------------------------------------------------------- helpers

func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v as Dictionary
	return {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		return v as Array
	return []
