extends RefCounted
## Loads the authored world layouts in data/star_fall/sites.json. Pure data:
## no nodes, no signals. The world scene consumes these dictionaries.
const SFContent := preload("res://core/star_fall/sf_content.gd")

const SITES_PATH := "res://data/star_fall/sites.json"

var sites: Dictionary = {}
var loaded: bool = false


func load_all() -> bool:
	var raw: Variant = SFContent.read_json(SITES_PATH)
	if not (raw is Dictionary):
		push_error("SFSites: could not load %s" % SITES_PATH)
		return false
	sites = raw as Dictionary
	loaded = true
	return true


func site(id: String) -> Dictionary:
	var s: Variant = sites.get(id, {})
	if s is Dictionary:
		return (s as Dictionary).duplicate(true)
	return {}


func site_ids() -> Array:
	var out: Array = []
	for k in sites.keys():
		var key := String(k)
		if key.begins_with("_"):
			continue
		var v: Variant = sites[key]
		if v is Dictionary and (v as Dictionary).has("props"):
			out.append(key)
	return out
