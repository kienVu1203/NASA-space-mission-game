extends RefCounted
## Versioned save/load for the STAR FALL campaign. Pure logic plus FileAccess:
## no nodes, no UI. The screen layer calls these functions and reports results.
##
## A save is a single JSON document in user:// with an explicit "version".
## Loading never overwrites the file, and a corrupted save is reported as an
## error rather than being silently replaced with empty progress.

const SAVE_PATH := "user://star_fall_save.json"
## Version 2 adds Phase 2 progression (recovered components, restored archives,
## the active mission). Version 1 documents still load: missing fields fall back
## to safe defaults in SFCampaign.apply_save_dict(). Version 3 adds the Phase 3
## vocabulary journal and reconstruction record; versions 1 and 2 still load.
const SCHEMA_VERSION := 3
const MIN_COMPATIBLE_VERSION := 1

## Load result codes.
const LOAD_OK := "ok"
const LOAD_MISSING := "missing"
const LOAD_CORRUPT := "corrupt"
const LOAD_VERSION := "version"


static func save_exists(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## Reads and structurally validates the save file without touching a campaign.
## Returns {"status": String, "data": Dictionary, "error": String}.
static func read_save(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": LOAD_MISSING, "data": {}, "error": "No save file."}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"status": LOAD_CORRUPT, "data": {}, "error": "The save file could not be opened."}
	var text := f.get_as_text()
	f.close()
	if text.strip_edges() == "":
		return {"status": LOAD_CORRUPT, "data": {}, "error": "The save file is empty."}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"status": LOAD_CORRUPT, "data": {}, "error": "The save file is not valid campaign data."}
	var data := parsed as Dictionary
	var version := int(data.get("version", 0))
	if version < MIN_COMPATIBLE_VERSION:
		return {"status": LOAD_CORRUPT, "data": {}, "error": "The save file has no usable version."}
	if version > SCHEMA_VERSION:
		return {"status": LOAD_VERSION, "data": data, "error": "This save was written by a newer version of the game."}
	if not (data.get("stage") is String):
		return {"status": LOAD_CORRUPT, "data": {}, "error": "The save file is missing its campaign stage."}
	return {"status": LOAD_OK, "data": data, "error": ""}


## Cheap validity test used to enable or disable Continue on the main menu.
static func has_valid_save(path: String = SAVE_PATH) -> bool:
	var result := read_save(path)
	return String(result.get("status", "")) == LOAD_OK


## Writes the campaign. Refuses to write a document that cannot be read back.
## Returns {"ok": bool, "error": String}.
static func write_save(campaign, path: String = SAVE_PATH) -> Dictionary:
	if campaign == null:
		return {"ok": false, "error": "No campaign to save."}
	var data: Dictionary = campaign.to_save_dict()
	data["version"] = SCHEMA_VERSION
	var text := JSON.stringify(data, "\t")
	# Round-trip check: a save that cannot be parsed is worse than no save.
	if not (JSON.parse_string(text) is Dictionary):
		return {"ok": false, "error": "The campaign could not be serialised."}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "The save file could not be written."}
	f.store_string(text)
	f.close()
	return {"ok": true, "error": ""}


## Loads a save into the campaign object. Progress is only replaced after the
## document passes validation, so a corrupt file never wipes a live campaign.
## Returns {"ok": bool, "status": String, "error": String, "warnings": Array}.
static func load_into(campaign, path: String = SAVE_PATH) -> Dictionary:
	var result := read_save(path)
	var status := String(result.get("status", ""))
	if status != LOAD_OK:
		return {
			"ok": false,
			"status": status,
			"error": String(result.get("error", "The save could not be loaded.")),
			"warnings": [],
		}
	var warnings: Array = campaign.apply_save_dict(result.get("data", {}) as Dictionary)
	return {"ok": true, "status": LOAD_OK, "error": "", "warnings": warnings}


static func delete_save(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK or _fallback_remove(path)


static func _fallback_remove(path: String) -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	var file := path.get_file()
	if not dir.file_exists(file):
		return false
	return dir.remove(file) == OK
