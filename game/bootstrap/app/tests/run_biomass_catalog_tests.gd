extends SceneTree
## The planner offers the six biomass patches as blood decals (ADR-0061), so
## saving, undo and the surface probes need no biomass-specific code.

const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const DECAL := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")

var failures := 0


func _init() -> void:
	var entries: Array = CATALOG.new().biomass_catalog()
	_expect(entries.size() == 6, "The planner lists six biomass patches.")
	for entry: Dictionary in entries:
		_expect(str(entry["kind"]) == "blood" and str(entry["blood_texture"]).begins_with("biomass_"), "Entry %s is a biomass blood decal." % entry["name"])
		var piece := DECAL.instantiate() as Node3D
		piece.call("configure_blood", str(entry["blood_texture"]), "wall")
		_expect(piece.call("get_blood_config")["texture"] == entry["blood_texture"], "%s round-trips through the blood config." % entry["name"])
		piece.free()
	print("biomass catalog tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		print("FAIL: ", message)
