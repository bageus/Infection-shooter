extends SceneTree
## Wave loot: the drop roll gates it, the item roll picks medkit, armor or DNA by weight.

const LOOT := preload("res://game/bootstrap/app/web_wave_loot.gd")
const DROP_TABLE := preload("res://game/features/pickups/public/drop_table.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	_check(LOOT.pick(0.9, 0.1).is_empty(), "a high drop roll gives nothing")
	_check(LOOT.pick(0.1, 0.1) == "medkit" and LOOT.pick(0.1, 0.5) == "armor" and LOOT.pick(0.1, 0.9) == "dna", "item roll picks by weight")
	for id: String in LOOT.WEIGHTS:
		_check(DROP_TABLE.SCENES.has(id), "%s has a pickup scene" % id)
	print("web wave loot tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)
