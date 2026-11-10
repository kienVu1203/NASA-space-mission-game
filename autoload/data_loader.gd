extends Node
## Loads JSON files from res://data/.

func load_json(file_name: String) -> Variant:
	var f := FileAccess.open("res://data/%s" % file_name, FileAccess.READ)
	if f == null:
		push_error("Missing data file: %s" % file_name)
		return null
	return JSON.parse_string(f.get_as_text())
