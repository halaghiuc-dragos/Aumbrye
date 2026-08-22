extends RefCounted
class_name DialogueCatalog

## Loads branching dialogue JSON from content/dialogue/ (DLG-4.1).

const DIALOGUE_DIR := "content/dialogue"

static var _definitions: Dictionary = {}
static var _load_attempted := false


## A copy, never the cached definition itself.
##
## Dictionaries are references in GDScript, so handing out the cache let a caller edit the catalog
## by accident — and one did: `DialogueRunner.end_dialogue()` called `clear()` on what it thought
## was its own copy. Finishing a single conversation emptied that definition for the rest of the
## session, and the NPC or stray could never be spoken to again.
static func get_dialogue(dialogue_id: String) -> Dictionary:
	_ensure_loaded()
	var definition: Variant = _definitions.get(dialogue_id, {})
	return (definition as Dictionary).duplicate(true) if definition is Dictionary else {}


static func clear_cache() -> void:
	_definitions.clear()
	_load_attempted = false


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	_definitions = ContentDirLoader.load_id_map(
		[DIALOGUE_DIR], "id", "DialogueCatalog", false, true
	)
