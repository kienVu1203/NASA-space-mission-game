extends RefCounted
## A dialogue box model: an ordered list of lines, a typewriter cursor and a
## small block of context lines the speaker can show behind the current one.
## Pure logic. The view reads it and draws; input calls advance().
##
## A line can carry an optional "speaker" prefix already embedded in the text
## (for example "Bill: ..."), because the data file owns the prose.

var lines: Array = []
var index: int = 0
var chars: float = 0.0
var chars_per_second: float = 52.0

var title: String = ""
var accent: String = "cyan"


func _init(line_list: Array = [], title_text: String = "", accent_name: String = "cyan") -> void:
	lines = line_list.duplicate()
	index = 0
	chars = 0.0
	title = title_text
	accent = accent_name


func is_empty() -> bool:
	return lines.is_empty()


func current_text() -> String:
	if index < 0 or index >= lines.size():
		return ""
	return String(lines[index])


func visible_text() -> String:
	var t := current_text()
	var n := int(chars)
	if n >= t.length():
		return t
	return t.substr(0, n)


func is_line_complete() -> bool:
	return int(chars) >= current_text().length()


func is_last_line() -> bool:
	return index >= lines.size() - 1


## Completes the current line, or advances to the next one.
## Returns true when the whole sequence is finished.
func advance() -> bool:
	if is_empty():
		return true
	if not is_line_complete():
		chars = float(current_text().length())
		return false
	if is_last_line():
		index = lines.size()
		return true
	index += 1
	chars = 0.0
	return false


func tick(delta: float) -> void:
	if is_empty() or index >= lines.size():
		return
	if not is_line_complete():
		chars = minf(float(current_text().length()), chars + chars_per_second * delta)


func progress() -> float:
	if lines.is_empty():
		return 1.0
	return float(index) / float(lines.size())
