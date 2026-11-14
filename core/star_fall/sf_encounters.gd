extends RefCounted
## Loads data/star_fall/encounters.json: the Phase 2 shield-defense tuning.
## Pure data access: no nodes, no UI, no signals. Tuning changes belong in the
## JSON file, never in this script.
##
## The file owns arena geometry, shield geometry, projectile types, boss health
## bands, pattern definitions, telegraphs, rewards and archive metadata.

const DATA_PATH := "res://data/star_fall/encounters.json"

var arena: Dictionary = {}
var shield: Dictionary = {}
var combat: Dictionary = {}
var projectile_types: Dictionary = {}
var bosses: Array = []
var archives: Dictionary = {}

var _boss_by_id: Dictionary = {}
var _loaded: bool = false


func load_all() -> bool:
	var raw: Variant = _read_json(DATA_PATH)
	if not (raw is Dictionary):
		push_error("SFEcounters: could not load %s" % DATA_PATH)
		return false
	_ingest(raw as Dictionary)
	_loaded = true
	return true


## Test and tooling entry point: build from an in-memory dictionary.
func load_from_dict(data: Dictionary) -> bool:
	_ingest(data)
	_loaded = true
	return true


func is_loaded() -> bool:
	return _loaded


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SFEcounters: missing %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


func _ingest(data: Dictionary) -> void:
	arena = _as_dict(data.get("arena", {}))
	shield = _as_dict(data.get("shield", {}))
	combat = _as_dict(data.get("combat", {}))
	projectile_types = _as_dict(data.get("projectile_types", {}))
	bosses = _as_array(data.get("bosses", []))
	archives = _as_dict(data.get("archives", {}))

	_boss_by_id = {}
	for entry in bosses:
		var boss: Dictionary = _as_dict(entry)
		var id := String(boss.get("id", ""))
		if id == "":
			push_error("SFEcounters: boss without an id")
			continue
		boss["bands"] = _sorted_bands(_as_array(boss.get("bands", [])))
		_boss_by_id[id] = boss


## Bands are authored from full health downwards. Sorting here means a data
## file can list them in any order without silently changing the escalation.
func _sorted_bands(bands: Array) -> Array:
	var sorted: Array = bands.duplicate()
	sorted.sort_custom(func(a, b): return float(_as_dict(a).get("at_fraction", 0.0)) > float(_as_dict(b).get("at_fraction", 0.0)))
	return sorted


# ---------------------------------------------------------------- lookups

func boss(id: String) -> Dictionary:
	return _as_dict(_boss_by_id.get(id, {}))


func has_boss(id: String) -> bool:
	return _boss_by_id.has(id)


func boss_ids() -> Array:
	var out: Array = []
	for id in _boss_by_id.keys():
		out.append(String(id))
	out.sort()
	return out


func boss_for_chapter(chapter_id: String) -> Dictionary:
	for id in _boss_by_id.keys():
		var boss: Dictionary = _as_dict(_boss_by_id[id])
		if String(boss.get("chapter_id", "")) == chapter_id:
			return boss
	return {}


func projectile_type(id: String) -> Dictionary:
	return _as_dict(projectile_types.get(id, {}))


func projectile_family(id: String) -> String:
	return String(projectile_type(id).get("family", "hostile"))


func archive(id: String) -> Dictionary:
	return _as_dict(archives.get(id, {}))


func archive_ids() -> Array:
	var out: Array = []
	for id in archives.keys():
		out.append(String(id))
	out.sort()
	return out


# ---------------------------------------------------------------- helpers

func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v as Dictionary
	return {}


func _as_array(v: Variant) -> Array:
	if v is Array:
		return v as Array
	return []
