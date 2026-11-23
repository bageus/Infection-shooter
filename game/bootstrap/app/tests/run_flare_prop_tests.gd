extends SceneTree
## Floor flare: dark until the player comes close, then it ignites and fades in; the
## planner switch keeps it dark; the palette offers it and its flag survives a save.

const FLARE := preload("res://game/presentation/office_floor/public/props/flare_prop.tscn")
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_palette()
	await _test_ignites_near_player()
	await _test_stays_dark_far_away()
	await _test_switch_off()
	print("Flare prop tests: %d failure(s)." % _failures)
	quit(0 if _failures == 0 else 1)


func _flare(player_distance: float, enabled: bool) -> Node3D:
	for old: Node in get_nodes_in_group("player"):
		old.remove_from_group("player")
		old.queue_free()
	var flare := FLARE.instantiate() as Node3D
	root.add_child(flare)
	flare.call("set_flare_enabled", enabled)
	var light := flare.find_child("BudgetLight", true, false) as Node
	light.call("set_local_lighting_enabled", true)
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = Vector3(player_distance, 0.0, 0.0)
	return flare


func _light_of(flare: Node3D) -> OmniLight3D:
	return flare.find_child("BudgetLight", true, false) as OmniLight3D


func _test_palette() -> void:
	var catalog := CATALOG.new()
	var entries: Array = catalog.lighting_catalog.filter(func(entry: Dictionary) -> bool: return entry.get("kind") == "flare")
	_check(entries.size() == 1, "Lighting palette offers one flare")
	_check(entries.size() == 1 and str(entries[0]["path"]).ends_with("flare_prop.tscn"), "Flare palette entry points at the flare scene")


func _test_ignites_near_player() -> void:
	var flare := _flare(1.0, true)
	var light := _light_of(flare)
	await process_frame
	await process_frame
	_check(light.is_wanted(), "Flare ignites when the player is close")
	await create_timer(1.0).timeout
	_check(is_equal_approx(light.light_energy, 1.6), "Flare fades in to full brightness")
	_check(light.omni_attenuation > 0.0 and light.omni_range > 0.0, "Flare light falls off with distance")
	flare.queue_free()


func _test_stays_dark_far_away() -> void:
	var flare := _flare(10.0, true)
	var light := _light_of(flare)
	await process_frame
	_check(not light.is_wanted(), "Flare stays dark while the player is far")
	_check(light.light_energy == 0.0, "Dark flare emits no light")
	flare.queue_free()


func _test_switch_off() -> void:
	var flare := _flare(1.0, false)
	var light := _light_of(flare)
	await process_frame
	await create_timer(0.2).timeout
	_check(not light.is_wanted(), "Flare with the planner switch off stays dark next to the player")
	flare.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
		print("FAIL: ", message)
