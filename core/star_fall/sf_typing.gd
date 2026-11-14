extends RefCounted
## Typing target selection and progress. Pure logic: no nodes, no input events.
## The screen turns key events into single lowercase letters; this class decides
## what each letter means.
##
## Rules
##   - No target: a letter selects the active word that starts with it. When
##     several match, the one closest to the danger line wins (largest y), then
##     the oldest (lowest uid). The selecting letter counts as progress.
##   - With a target: letters apply only to that word. A correct letter
##     advances it; finishing the word reports "complete".
##   - A wrong letter resets only the target's progress to zero. The word stays
##     selected, the wrong key is NOT reinterpreted as a new selection, and the
##     next valid input must be the word's first letter.
##   - release() is the one supported cancellation (Backspace in the screen).

var target_uid: int = -1
var progress: int = 0


func reset() -> void:
	target_uid = -1
	progress = 0


func has_target() -> bool:
	return target_uid >= 0


## Maps a key's unicode value to a typing letter. Returns "" for anything that
## is not A-Z/a-z (digits, punctuation, space, accented letters). Upper and
## lower case match the same target.
static func letter_from_unicode(code: int) -> String:
	if code >= 65 and code <= 90:
		code += 32
	if code >= 97 and code <= 122:
		return char(code)
	return ""


## Applies one letter. `words` is the active list: dictionaries with at least
## "uid", "text" and "y". Returns {"kind": String, "uid": int, "progress": int}
## where kind is select | advance | complete | reset | no_match | ignored.
func input(letter: String, words: Array) -> Dictionary:
	if letter.length() != 1:
		return _result("ignored", -1)
	var word: Dictionary = _find(words, target_uid)
	if word.is_empty():
		# The target fell or was removed: behave as if nothing were selected.
		target_uid = -1
		progress = 0
		var pick := _pick_new(letter, words)
		if pick.is_empty():
			return _result("no_match", -1)
		target_uid = int(pick["uid"])
		progress = 1
		if progress >= String(pick["text"]).length():
			return _complete()
		return _result("select", target_uid)

	var text := String(word["text"])
	if text[progress] == letter:
		progress += 1
		if progress >= text.length():
			return _complete()
		return _result("advance", target_uid)
	progress = 0
	return _result("reset", target_uid)


## Explicit cancellation: drop the target without touching any other word.
func release() -> void:
	target_uid = -1
	progress = 0


## A word left the field (completed elsewhere, missed, or the fight reset).
func on_word_removed(uid: int) -> void:
	if uid == target_uid:
		release()


func _complete() -> Dictionary:
	var uid := target_uid
	var done := progress
	target_uid = -1
	progress = 0
	return {"kind": "complete", "uid": uid, "progress": done}


func _result(kind: String, uid: int) -> Dictionary:
	return {"kind": kind, "uid": uid, "progress": progress}


func _find(words: Array, uid: int) -> Dictionary:
	if uid < 0:
		return {}
	for w in words:
		if int((w as Dictionary).get("uid", -1)) == uid:
			return w
	return {}


func _pick_new(letter: String, words: Array) -> Dictionary:
	var best: Dictionary = {}
	for w in words:
		var word: Dictionary = w
		var text := String(word.get("text", ""))
		if text == "" or text[0] != letter:
			continue
		if best.is_empty():
			best = word
			continue
		var y := float(word.get("y", 0.0))
		var by := float(best.get("y", 0.0))
		if y > by or (is_equal_approx(y, by) and int(word["uid"]) < int(best["uid"])):
			best = word
	return best
