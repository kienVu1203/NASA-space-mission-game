extends RefCounted
## The environmental vocabulary library and encounter-deck selection. Pure data
## and rules: no nodes, no UI.
##
## Library  = every reviewed entry in data/star_fall/vocabulary.json.
## Deck     = the finite, ordered selection one boss attempt must complete.
## The deck is never the whole library, so a large library cannot turn a
## three-to-four minute fight into a vocabulary examination.

const DATA_PATH := "res://data/star_fall/vocabulary.json"
const REQUIRED_FIELDS := ["id", "text", "definition", "example", "category", "band"]

var bands: Array = []
var categories: Array = []
var entries: Array = []
var _by_id: Dictionary = {}
var errors: Array = []


func load_all() -> bool:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("SFVocabulary: missing %s" % DATA_PATH)
		return false
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (raw is Dictionary):
		push_error("SFVocabulary: %s is not a JSON object" % DATA_PATH)
		return false
	return load_from_dict(raw as Dictionary)


## Loads and validates. Returns false (and keeps `errors`) on any problem, so a
## broken library is reported instead of silently producing a short deck.
func load_from_dict(data: Dictionary) -> bool:
	errors = validate_dict(data)
	bands = data.get("bands", []) as Array
	categories = data.get("categories", []) as Array
	entries = []
	_by_id = {}
	for e in data.get("entries", []) as Array:
		if e is Dictionary:
			var entry: Dictionary = e
			entries.append(entry)
			_by_id[String(entry.get("id", ""))] = entry
	for err in errors:
		push_error("SFVocabulary: " + String(err))
	return errors.is_empty()


## Every rule the library must satisfy. Returns human-readable error strings.
static func validate_dict(data: Dictionary) -> Array:
	var out: Array = []
	var band_list: Array = data.get("bands", []) as Array
	var cat_list: Array = data.get("categories", []) as Array
	if band_list.is_empty():
		out.append("no difficulty bands declared")
	if cat_list.is_empty():
		out.append("no categories declared")
	var raw_entries: Variant = data.get("entries", [])
	if not (raw_entries is Array):
		out.append("entries is not an array")
		return out
	var seen_ids: Dictionary = {}
	var seen_text: Dictionary = {}
	var index := 0
	for e in raw_entries as Array:
		index += 1
		if not (e is Dictionary):
			out.append("entry %d is not an object" % index)
			continue
		var entry: Dictionary = e
		var label := String(entry.get("id", "entry %d" % index))
		for field in REQUIRED_FIELDS:
			if not entry.has(field) or String(entry[field]).strip_edges() == "":
				out.append("%s: missing or empty '%s'" % [label, field])
		var id := String(entry.get("id", ""))
		var text := String(entry.get("text", ""))
		if id != "":
			if seen_ids.has(id):
				out.append("%s: duplicate id" % id)
			seen_ids[id] = true
		if text != "":
			if not is_valid_target(text):
				out.append("%s: typing text '%s' must be lowercase a-z only" % [label, text])
			if seen_text.has(text):
				out.append("%s: duplicate typing text '%s'" % [label, text])
			seen_text[text] = true
		if not band_list.has(String(entry.get("band", ""))):
			out.append("%s: unknown band '%s'" % [label, String(entry.get("band", ""))])
		if not cat_list.has(String(entry.get("category", ""))):
			out.append("%s: unknown category '%s'" % [label, String(entry.get("category", ""))])
	return out


## Typing targets are lowercase ASCII letters only: no spaces, hyphens,
## apostrophes, digits or accented characters.
static func is_valid_target(text: String) -> bool:
	if text.length() < 2:
		return false
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 97 or c > 122:
			return false
	return true


func size() -> int:
	return entries.size()


func entry(id: String) -> Dictionary:
	return _by_id.get(id, {}) as Dictionary


func has_entry(id: String) -> bool:
	return _by_id.has(id)


func entries_for_band(band: String) -> Array:
	var out: Array = []
	for e in entries:
		if String((e as Dictionary).get("band", "")) == band:
			out.append(e)
	return out


## Builds one attempt's deck. Each stage draws `count` distinct entries from its
## band with a seeded shuffle, preferring unused first letters and categories so
## a deck is varied, then orders the stage from shorter to longer words. The
## result is deterministic for a seed and never repeats an entry.
##
## Returns Array of {"id", "text", "stage", "index"} in play order.
func select_deck(stages: Array, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var deck: Array = []
	var used: Dictionary = {}
	for stage_index in stages.size():
		var stage: Dictionary = stages[stage_index]
		var pool: Array = entries_for_band(String(stage.get("band", "")))
		_shuffle(pool, rng)
		var want := int(stage.get("count", 0))
		var picked: Array = []
		var letters: Dictionary = {}
		var cats: Dictionary = {}
		# Two passes: first insist on a fresh first letter and category, then
		# fill whatever is still missing from the rest of the shuffled pool.
		for strict in [true, false]:
			for e in pool:
				if picked.size() >= want:
					break
				var entry: Dictionary = e
				var id := String(entry["id"])
				if used.has(id):
					continue
				var text := String(entry["text"])
				if strict and (letters.has(text[0]) or cats.has(String(entry["category"]))):
					continue
				picked.append(entry)
				used[id] = true
				letters[text[0]] = true
				cats[String(entry["category"])] = true
		picked.sort_custom(_shorter_first)
		for e in picked:
			var entry: Dictionary = e
			deck.append({
				"id": String(entry["id"]),
				"text": String(entry["text"]),
				"stage": stage_index,
				"index": deck.size(),
			})
	return deck


func _shorter_first(a: Dictionary, b: Dictionary) -> bool:
	var la := String(a["text"]).length()
	var lb := String(b["text"]).length()
	if la != lb:
		return la < lb
	return String(a["id"]) < String(b["id"])


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	# Fisher-Yates with the seeded generator; Array.shuffle() uses the global RNG.
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp
