extends SceneTree
## Every door in the planner palette takes the open, key and sealed setting through its door controller.
const CATALOG := preload("res://game/bootstrap/app/planning_catalog.gd")
const PLANNER_DOOR := preload("res://game/bootstrap/app/planning_door_options.gd")
# Named like doors but not doors: a wall sign with no leaf.
const NOT_DOORS := ["13_wall_fire_door.glb"]
# Doors still waiting for a decision on how their glass leaf swings; remove an entry once it is settled.
const PENDING := ["lab_glass_door.tscn"]
const STATES := [&"key", &"sealed", &"open"]
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := CATALOG.new()
	catalog.call("_build_environment_catalogs")
	var checked := 0
	for entries: Array in catalog.group_catalogs.values():
		for entry: Dictionary in entries:
			var file := str(entry.path).get_file()
			if not file.contains("door") or file in NOT_DOORS or entry.get("name", "") in NOT_DOORS:
				continue
			if file.contains("elevator"):
				_check(not _is_lockable(entry), "%s is an elevator and has no setting" % file)
				continue
			if file in PENDING:
				continue
			checked += 1
			await _check_door(entry)
	_check(checked >= 6, "Every planner door entry is covered (%d checked)" % checked)
	print("Door lock coverage tests: %d failure(s)." % failures)
	quit(failures)


func _is_lockable(entry: Dictionary) -> bool:
	var node := (load(str(entry.path)) as PackedScene).instantiate() as Node3D
	var lockable := PLANNER_DOOR.lockable_controller(node) != null
	node.free()
	return lockable


func _check_door(entry: Dictionary) -> void:
	var label := str(entry.path).get_file()
	var scene := load(str(entry.path)) as PackedScene
	_check(scene != null, "%s loads" % label)
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	root.add_child(node)
	await process_frame
	var controller: Node = PLANNER_DOOR.lockable_controller(node)
	_check(controller != null, "%s has a door controller for the planner setting" % label)
	if controller != null:
		for state: StringName in STATES:
			controller.call("configure_lock_state", state)
			_check(controller.call("get_lock_state") == state, "%s keeps the %s state" % [label, state])
	node.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
