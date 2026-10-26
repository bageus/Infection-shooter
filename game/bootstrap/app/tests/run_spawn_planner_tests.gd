extends SceneTree
## Spawn points in the planner: palette tab, settings panel, enemy links, save and reload,
## undo, and the first wave once the planner closes.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
const VALIDATOR := preload("res://game/bootstrap/app/planning_layout_validator.gd")
const SPOTS := [Vector2(470, 230), Vector2(660, 230), Vector2(470, 460), Vector2(660, 460), Vector2(850, 460)]
var failures := 0
var planner: Node
var objects: Node
var controls: Node
var options: Node
var stage: Node3D
var hole: Node3D
var hole_id := ""
var guards: Array[Node3D] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)


func _run() -> void:
	stage = MAIN.instantiate() as Node3D
	# Exercise the wave editor on an empty floor; authored furniture must not
	# occlude the guard click or block the spawn hole at these test coordinates.
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	current_scene = stage
	await process_frame
	planner = stage.get("planning_mode")
	planner.enter()
	objects = planner.objects
	controls = planner.controls
	options = controls.spawn_options
	_check(not options.panel.visible, "wave panel is hidden on the structure tab")
	controls._show_actor_catalog()
	_check(options.panel.visible and options.hint.visible, "actors tab shows the wave panel with a hint")
	var hole_entry := _entry("spawn_point.tscn")
	_check(not hole_entry.is_empty() and hole_entry["kind"] == "spawn_point", "the enemies tab has the spawn hole")
	_arm(hole_entry)
	_check(options.point_box.visible and options.title.text.contains("размещение"), "armed spawn hole opens its settings for the next one")
	# Defaults for the next hole: 8 brutes, bursts of 4.
	options.editor.entries_box.get_child(0).get_child(0).select(2)
	options.editor.entries_box.get_child(0).get_child(0).item_selected.emit(2)
	options.editor.entries_box.get_child(0).get_child(1).value = 8
	options.editor.rule_option.select(1)
	options.editor.rule_option.item_selected.emit(1)
	options.editor.batch_spin.value = 4
	hole = _place(hole_entry, SPOTS[0])
	_check(hole != null, "spawn hole placed")
	var config: Dictionary = hole.call("get_spawn_config")
	var queue: Dictionary = config["queues"][0]
	_check(queue["enemies"] == [{"enemy": "brute", "count": 8}] and queue["rule"] == "burst" and queue["batch"] == 4, "the new hole starts with the panel defaults %s" % str(config))
	_check(hole.global_position.y == 0.0, "the hole lies on the floor")
	hole_id = str(hole.get_meta("planning_object_id", ""))
	_check(hole_id.begins_with("spawn_"), "the hole has an id for links")
	_check(controls.settings_kind(hole) == "spawn", "spawn hole has its own settings kind")
	for index in 2:
		guards.append(_place(_entry("infected_hunger.tscn"), SPOTS[1 + index]))
	_check(guards[0] != null and guards[1] != null, "two guards placed")
	_edit_and_link()
	await _persistence()
	stage.queue_free()
	await process_frame
	print("Spawn planner tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _edit_and_link() -> void:
	# Select the hole, edit through the panel.
	objects._reset_selection()
	objects._select(hole)
	_check(options.panel.visible and options.point_box.visible and not options.enemy_box.visible, "selected hole shows its settings")
	_check(options.link_note.text.contains("нет связанных"), "an unlinked hole warns that it will not fire")
	options.editor.entries_box.get_child(0).get_child(1).value = 12
	options.editor.interval_spin.value = 2.5
	options.editor.trigger_option.select(1)
	options.editor.trigger_option.item_selected.emit(1)
	var edited: Dictionary = hole.call("get_spawn_config")["queues"][0]
	_check(edited["enemies"][0]["count"] == 12 and edited["interval"] == 2.5 and edited["trigger"] == "all", "panel edits reach the hole")
	_queue_editing()
	# A real click on a guard keeps the wave panel open (clearing the preview must not hide it).
	objects._reset_selection()
	objects._click_world(planner.camera.unproject_position(guards[0].global_position + Vector3(0, 1, 0)))
	_check(objects.selected == guards[0], "clicking a guard selects it")
	_check(options.panel.visible and options.enemy_box.visible, "the wave list stays open after a click on a guard")
	# Link both guards to the hole.
	for guard in guards:
		objects._select(guard)
		_check(options.enemy_box.visible and not options.point_box.visible, "selected guard shows the wave list")
		_check(options.link_list.get_child_count() >= 1, "wave list names the hole")
		var box := options.link_list.get_child(0) as CheckBox
		box.button_pressed = true
		_check(Array(guard.get_meta(DIRECTOR.TRIGGER_META, [])).has(hole_id), "ticking the hole links the guard")
	objects._select(hole)
	_check(options.link_note.text.contains("2"), "the hole counts its two guards")
	# Undo of a link.
	objects._select(guards[1])
	planner.edit_history.call("undo")
	_check(not guards[1].has_meta(DIRECTOR.TRIGGER_META), "undo removes the last link")
	(options.link_list.get_child(0) as CheckBox).button_pressed = true


func _queue_editing() -> void:
	var editor: Node = options.editor
	editor.add_queue_button.pressed.emit()
	_check(editor.current == 1 and hole.call("get_spawn_config")["queues"].size() == 2, "adding a queue selects it")
	_check(editor.start_row.visible and editor.delay_row.visible and not editor.trigger_row.visible, "a later queue starts by time by default")
	editor.add_entry_button.pressed.emit()
	editor.delay_spin.value = 5.0
	var queue: Dictionary = hole.call("get_spawn_config")["queues"][1]
	_check(queue["enemies"].size() == 2 and queue["delay"] == 5.0, "a queue holds several kinds and its own delay")
	_check(queue["enemies"][0]["enemy"] != queue["enemies"][1]["enemy"] or queue["enemies"][0]["count"] != 0, "the added kind is valid")
	editor.start_option.select(1)
	editor.start_option.item_selected.emit(1)
	_check(editor.trigger_row.visible and not editor.delay_row.visible, "trigger start shows the trigger rule")
	editor.start_option.select(0)
	editor.start_option.item_selected.emit(0)
	editor.queue_option.select(0)
	editor.queue_option.item_selected.emit(0)
	_check(editor.current == 0 and not editor.start_row.visible, "the first queue has no start choice")


func _persistence() -> void:
	# Save and reload.
	var data: Dictionary = JSON.parse_string(JSON.stringify(planner.storage._collect_layout_data()))
	_check(VALIDATOR.error(data).is_empty(), "saved layout validates")
	var spawn_records: Array = data["objects"].filter(func(record: Dictionary) -> bool: return record.has("spawn_point"))
	var linked_records: Array = data["objects"].filter(func(record: Dictionary) -> bool: return record.has("spawn_triggers"))
	_check(spawn_records.size() == 1 and linked_records.size() == 2, "layout records one hole and two linked guards")
	var broken: Dictionary = data.duplicate(true)
	broken["objects"][data["objects"].find(linked_records[0])]["spawn_triggers"] = "nope"
	_check(not VALIDATOR.error(broken).is_empty(), "validator rejects bad spawn_triggers")
	objects._reset_selection()
	objects._apply_layout_data(data)
	await process_frame
	var reloaded: Node3D = _find_hole()
	_check(reloaded != null, "hole survives reload")
	if reloaded != null:
		var again: Dictionary = reloaded.call("get_spawn_config")
		var first: Dictionary = again["queues"][0]
		_check(first["enemies"][0] == {"enemy": "brute", "count": 12} and first["trigger"] == "all" and first["interval"] == 2.5, "hole settings survive reload")
		_check(again["queues"].size() == 2 and again["queues"][1]["enemies"].size() == 2 and again["queues"][1]["delay"] == 5.0, "extra queue and its infected survive reload")
		_check(str(reloaded.get_meta("planning_object_id", "")) == hole_id, "hole id survives reload")
		var linked: Array = options.linked_enemies(hole_id)
		_check(linked.size() == 2, "both links survive reload (%d)" % linked.size())
		await _mission(reloaded, linked)


func _mission(reloaded: Node3D, linked: Array) -> void:
	# Close the planner; killing a guard fires the wave once.
	reloaded.call("configure_spawn", {"queues": [{"enemies": [{"enemy": "hunger", "count": 3}], "interval": 0.1, "rule": "stream", "trigger": "any"}]})
	planner.exit()
	var director: Node = stage.get("wave_director")
	_check(director.is_armed(), "closing the planner arms the director")
	linked[0].call("take_damage", 9999.0)
	for tick in 40:
		await physics_frame
	_check(director.has_fired(hole_id), "a linked death after the planner closes fires the wave")
	var spawned := 0
	for enemy in stage.get_node("Gameplay/Enemies").get_children():
		spawned += 1 if enemy.has_meta(&"spawned_by") else 0
	_check(spawned >= 1, "the wave spawned infected in the mission (%d)" % spawned)
	planner.enter()
	await process_frame
	await process_frame
	var left := 0
	for enemy in stage.get_node("Gameplay/Enemies").get_children():
		left += 1 if enemy.has_meta(&"spawned_by") and not enemy.is_queued_for_deletion() else 0
	_check(left == 0 and not director.is_armed(), "entering the planner clears the wave")
	planner.exit()


func _find_hole() -> Node3D:
	for node in objects.placed:
		if is_instance_valid(node) and node.has_method("configure_spawn"):
			return node
	return null


func _entry(file_name: String) -> Dictionary:
	for entry: Dictionary in planner.catalog.actor_catalog:
		if str(entry.get("path", "")).get_file() == file_name:
			return entry
	return {}


func _arm(entry: Dictionary) -> void:
	objects._reset_selection()
	objects.selected_path = str(entry.get("path", ""))
	objects.selected_kind = str(entry.get("kind", ""))
	objects.selected_entry = entry
	objects._rebuild_preview()


func _place(entry: Dictionary, screen: Vector2) -> Node3D:
	_arm(entry)
	var before: int = objects.placed.size()
	objects._place_selected(screen)
	objects._reset_selection()
	return objects.placed.back() if objects.placed.size() > before else null
