extends RefCounted
## Local player preferences: volumes, text speed, reduced motion and the Eco
## Arena practice unlock. Stored in its own file, never in the campaign save,
## so changing a setting can never grant inventory or move the story, and a
## practice session can never overwrite campaign progress.
##
## Missing or damaged files fall back to the defaults; nothing here is required
## to play.

const PATH := "user://star_fall_settings.cfg"

const DEFAULTS := {
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 0.9,
	"ui_volume": 0.8,
	"text_speed": 52.0,
	"reduced_motion": false,
	"practice_unlocked": false,
}


## Returns every known setting, defaults filled in, values clamped.
static func load_settings(path: String = PATH) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	for key in DEFAULTS:
		var value: Variant = cfg.get_value("star_fall", String(key), DEFAULTS[key])
		if typeof(value) != typeof(DEFAULTS[key]) and not (DEFAULTS[key] is float and (value is int or value is float)):
			continue
		out[key] = value
	for key in ["master_volume", "music_volume", "sfx_volume", "ui_volume"]:
		out[key] = clampf(float(out[key]), 0.0, 1.0)
	out["text_speed"] = clampf(float(out["text_speed"]), 20.0, 120.0)
	return out


static func save_settings(values: Dictionary, path: String = PATH) -> bool:
	var cfg := ConfigFile.new()
	for key in DEFAULTS:
		cfg.set_value("star_fall", String(key), values.get(key, DEFAULTS[key]))
	return cfg.save(path) == OK
