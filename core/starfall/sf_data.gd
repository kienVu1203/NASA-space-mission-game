extends RefCounted
## Loads Operation: Starfall's JSON content. Data lives in data/starfall/ so
## tuning never requires touching a script.

const DIR := "res://data/starfall/"


static func read_json(file_name: String) -> Variant:
	var path := DIR + file_name
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is JSON:
			var j: JSON = res
			return j.data
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SFData: missing %s" % path)
		return null
	return JSON.parse_string(f.get_as_text())


static func credits(value: float) -> String:
	return "%d" % int(round(value))


static func pct(value: float, total: float) -> int:
	if total <= 0.0:
		return 0
	return int(round(clampf(value / total, 0.0, 1.0) * 100.0))
