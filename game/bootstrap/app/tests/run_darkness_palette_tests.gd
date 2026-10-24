extends SceneTree
const OPTIONS := preload("res://game/bootstrap/app/planning_room_options.gd")
const HISTORY := preload("res://game/bootstrap/app/planning_edit_history.gd")
const BAKE := preload("res://game/bootstrap/app/planning_scene_bake.gd")
const CAPTURE := preload("res://game/bootstrap/app/planning_layout_capture.gd")
const GEOMETRY := preload("res://game/bootstrap/app/planning_geometry.gd")
const ZONE := preload("res://game/presentation/office_floor/public/props/darkness_zone.tscn")
const FILE := "user://darkness_palette_test.tscn"
var failures := 0
var session: TestSession
var objects: TestObjects
var options: Node
var host: Node3D

class TestControls extends RefCounted:
	func _update_light_ui() -> void: pass

class TestObjects extends Node:
	var selected: Node3D
	var main_player: Node3D
	var preview: Node3D
	var selected_kind := "exploration_darkness"
	var placed: Array[Node3D] = []
	var root: Node3D
	var host: Node3D
	var session: Node
	var controls := TestControls.new()
	var status := Label.new()
	var workstation_transforms := {}
	var active := true
	var player_spawn_defined := false
	func _update_history_buttons() -> void: pass
	func _sync_workstations() -> void: pass
	func _select(node: Node3D) -> void: selected = node
	func _instantiate_asset(_path: String) -> Node3D: return ZONE.instantiate()

class TestSession extends Node:
	var ui: Control
	var host: Node3D
	var active := true
	var catalog := {"active_catalog": [1], "lighting_catalog": [1]}
	var edit_history: RefCounted

class TestCatalog extends RefCounted:
	func _instantiate_asset(_path: String) -> Node3D: return ZONE.instantiate()

func _init() -> void:
	call_deferred("_run")

func _make_ui() -> Control:
	var ui := Control.new()
	var panel := VBoxContainer.new()
	panel.name = "Panel"
	ui.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "VBox"
	panel.add_child(box)
	var palette := ItemList.new()
	palette.name = "Palette"
	box.add_child(palette)
	return ui

func _zone(group: int, preview: bool = false) -> Node3D:
	var node := ZONE.instantiate() as Node3D
	node.set("room_id", group)
	node.set_meta("planning_scene_path", ZONE.resource_path)
	if preview: node.set_meta("planning_preview", true)
	host.add_child(node)
	return node

func _run() -> void:
	host = Node3D.new()
	root.add_child(host)
	session = TestSession.new()
	host.add_child(session)
	session.ui = _make_ui()
	host.add_child(session.ui)
	session.host = host
	objects = TestObjects.new()
	host.add_child(objects)
	host.add_child(objects.status)
	objects.root = host
	objects.session = session
	session.edit_history = HISTORY.new()
	session.edit_history.planner = objects
	options = OPTIONS.new()
	session.add_child(options)
	options.setup(session, objects)
	objects.preview = _zone(0, true)
	options.update()
	_check(options.panel.visible, "Palette darkness has settings before placement")
	options.height.value = 4.5
	options.room.value = 7
	_check(objects.preview.position.y == 4.5 and objects.preview.get("room_id") == 7, "Palette height and group update the preview")
	var first := _zone(0)
	options.configure_new(first, {"kind": "exploration_darkness"})
	options.apply_default_height(first)
	_check(first.get("room_id") == 7 and not first.get("permanent") and first.position.y == 4.5, "New zones inherit palette defaults")
	var second := _zone(7)
	var other := _zone(2)
	await _test_groups(first, second, other)
	_test_selected(first)
	_test_persistence(first)
	session.active = false
	options.update()
	_check(options.highlights.markers.is_empty(), "Leaving planning clears group highlights")
	host.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	print("Darkness palette tests: %d failure(s)." % failures)
	quit(failures)

func _test_groups(first: Node3D, second: Node3D, other: Node3D) -> void:
	options.update()
	_check(options.list.item_count == 3 and options.list.get_selected_id() == -1, "Groups are distinct and exclude the palette preview")
	options.list.select(options.list.get_item_index(7))
	options.list.item_selected.emit(options.list.selected)
	_check(options.highlights.markers.size() == 2, "Selecting a group highlights all its zones only")
	first.call("set_fog_of_war_enabled", false)
	options.highlights._process(0)
	_check(options.highlights.markers[first.get_instance_id()].visual.visible, "Highlight works with fog disabled")
	var geometry := GEOMETRY.new()
	_check(geometry._combined_aabb(first).size.x > 0.0, "Authored scaling bounds remain available while disabled fog is excluded from picking")
	first.position = Vector3(3, 5, 2)
	first.scale = Vector3(2, 1, 3)
	options.highlights._process(0)
	_check(options.highlights.markers[first.get_instance_id()].visual.global_transform == first.global_transform, "Highlight follows moving and scaling zones")
	var late := _zone(7)
	options.update()
	_check(options.highlights.markers.size() == 3, "New group members are included")
	late.queue_free()
	second.queue_free()
	await process_frame
	options.update()
	_check(options.highlights.markers.size() == 1, "Deleted members disappear from the highlight")
	_check(other.get("room_id") == 2 and first.get_child_count() == 1, "Highlight never edits other groups or authored children")

func _test_selected(first: Node3D) -> void:
	objects.selected = first
	options.update()
	options.height.value = 6.0
	_check(first.position.y == 6.0, "Height field edits an installed zone")
	session.edit_history.undo()
	_check(first.position.y == 5.0, "Height edit can be undone")
	options.update()
	options.room.value = 9
	_check(first.get("room_id") == 9, "Group field edits an installed zone")
	session.edit_history.undo()
	_check(first.get("room_id") == 7, "Group edit can be undone")
	objects.selected = null
	options.update()
	_check(options.height.value == 4.5 and options.room.value == 7, "Selection edits preserve parked palette defaults")

func _test_persistence(first: Node3D) -> void:
	first.set("permanent", false)
	first.set("darkness", 0.65)
	objects.selected = first
	session.edit_history.duplicate_selected()
	var copy: Node3D = objects.placed.back()
	_check(copy.get("room_id") == 7 and not copy.get("permanent") and copy.position.y == first.position.y, "Duplicate preserves group, type and height")
	var data := CAPTURE.collect(objects, [first], false)
	_check(data.objects[0].room_id == 7 and data.objects[0].y == 5.0, "JSON snapshot keeps group and height")
	var baker := BAKE.new(TestCatalog.new())
	_check(baker.save([first], FILE) == OK, "Authored scene can be saved")
	var baked := (load(FILE) as PackedScene).instantiate()
	var zone := baked.get_child(0)
	_check(zone.get("room_id") == 7 and not zone.get("permanent") and is_equal_approx(zone.get("darkness"), 0.65), "Baked scene retains darkness group and authored parameters")
	_check(zone.position.y == 5.0 and zone.get_child_count() == 1, "Baked scene keeps height without editor highlights")
	baked.free()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
