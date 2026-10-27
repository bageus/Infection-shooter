extends SceneTree
## Level chain rules: ordering, neighbours, entry triggers and arrival points.

const CHAIN := preload("res://game/bootstrap/app/level_chain.gd")
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _init() -> void:
	var chain := CHAIN.new()
	for map_name in ["a", "b", "c"]:
		_check(chain.add_map(map_name), "add " + map_name)
	_check(not chain.add_map("b"), "duplicate rejected")
	_check(chain.neighbour(1, 0) == "a" and chain.neighbour(1, 1) == "c", "b links to a and c")
	_check(chain.neighbour(0, 0) == "" and chain.neighbour(2, 1) == "", "ends have no outer neighbour")
	chain.set_entry_type(1, 1, "ceiling")
	_check(not chain.is_active(1, 1), "entry not placed is inactive")
	chain.place_entry(1, 1, 10.0, 5.0)
	_check(chain.is_active(1, 1), "placed ceiling entry is active")
	_check(chain.triggered_slot(1, 10.0, 5.0, 3.0) == 1, "climbing up triggers")
	_check(chain.triggered_slot(1, 10.0, 5.0, 1.0) == -1, "standing on the ground does not")
	_check(chain.triggered_slot(1, 40.0, 5.0, 3.0) == -1, "far away does not")
	chain.set_entry_type(1, 0, "floor")
	chain.place_entry(1, 0, 2.0, 2.0)
	_check(chain.is_active(1, 0) and chain.triggered_slot(1, 2.0, 2.0, -3.0) == -1, "the entry back to the previous map never triggers")
	chain.set_entry_type(1, 1, "floor")
	chain.place_entry(1, 1, 2.0, 2.0)
	_check(chain.triggered_slot(1, 2.0, 2.0, -3.0) == 1, "descending triggers floor entry")
	_check(chain.triggered_slot(1, 2.0, 2.0, 3.0) == -1, "floor entry ignores climbing")
	chain.set_entry_type(1, 1, "ceiling")
	chain.place_entry(1, 1, 10.0, 5.0)
	chain.set_entry_type(1, 0, "none")
	chain.set_entry_type(1, 1, "none")
	_check(chain.triggered_slot(1, 2.0, 2.0, -3.0) == -1, "none entry never triggers")
	chain.set_entry_type(1, 1, "ceiling")
	_check(chain.arrival(1, 1).is_empty(), "arrival needs the back entry of the next map")
	chain.set_entry_type(2, 0, "floor")
	chain.place_entry(2, 0, 7.0, 8.0)
	_check(chain.arrival(1, 1) == {"x": 7.0, "z": 8.0}, "arrival at the matching entry")
	_check(chain.triggered_slot(0, 0.0, 0.0, 5.0) == -1, "map without entries never triggers")
	chain.move_map(2, -1)
	_check(chain.names() == ["a", "c", "b"], "move up reorders")
	var copy := CHAIN.new()
	copy.load_dict(JSON.parse_string(JSON.stringify(chain.to_dict())))
	_check(copy.names() == ["a", "c", "b"] and copy.entry(2, 1).type == "ceiling", "round trip keeps data")
	copy.load_dict({"maps": [{"name": "x", "entries": [{"type": "bogus"}]}, {"name": "x"}]})
	_check(copy.names() == ["x"] and copy.entry(0, 0).type == "none" and copy.entry(0, 1).type == "none", "bad data repaired")
	chain.remove_map(0)
	_check(chain.names() == ["c", "b"], "remove")
	print("level chain tests: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
