extends SceneTree
## Every installed object with planner settings opens its settings panel when it is clicked,
## even while a palette item of the same kind is still active, and edits apply live and persist.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
# [label, catalog file, settings kind, panel node that must show]
const CASES := [
	["lamp", "planner_light.tscn", "lamp"],
	["door", "wall_door.tscn", "door"],
	["monitor", "05_monitor_destructible.glb", "display"],
	["laptop", "05_laptop_destructible.glb", "display"],
	["desk lamp", "05_lamp.glb", "display"],
	["crate", "04_crate_small_broken.glb", "loot"],
	["enemy", "infected_hunger.tscn", "enemy"],
	["plate", "09_fruit_plate_2.glb", "fruit"],
]
var failures := 0
var planner: Node
var objects: Node
var controls: Node


func _initialize() -> void:
	call_deferred("_run")


# Fixed test placements on the empty fixture floor.
const SPOTS := [Vector2(470, 230), Vector2(660, 230), Vector2(470, 460), Vector2(470, 560), Vector2(1040, 460), Vector2(960, 560), Vector2(850, 460), Vector2(1040, 300)]


func _run() -> void:
	var stage := MAIN.instantiate()
	# Authored furniture must not cover the settings targets at fixed pixels.
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	current_scene = stage
	await process_frame
	planner = stage.get("planning_mode")
	planner.enter()
	objects = planner.objects
	controls = planner.controls
	var placed: Array = []
	var index := 0
	for item: Array in CASES:
		var entry := _entry(str(item[1]))
		_check(not entry.is_empty(), "Catalog has " + str(item[0]))
		if entry.is_empty():
			continue
		var node := _place(entry, SPOTS[index])
		_check(node != null, "Placed " + str(item[0]))
		placed.append([item, entry, node])
		index += 1
	for row: Array in placed:
		var item: Array = row[0]
		var node: Node3D = row[2]
		if node == null:
			continue
		_check(controls.settings_kind(node) == str(item[2]), "Settings kind of %s is %s" % [item[0], item[2]])
		# The palette still holds this kind of object, as right after placing one.
		_arm(row[1])
		var count: int = objects.placed.size()
		var at := _screen_of(node)
		_click(at)
		_check(objects.selected == node, "Clicking the installed %s selects it" % item[0])
		_check(objects.placed.size() == count, "Clicking the installed %s places nothing" % item[0])
		_check(_panel_visible(str(item[2])), "The %s settings panel is open" % item[0])
		_edit_and_check(str(item[0]), node)
		# Nothing armed in the palette: a plain click selects it and its panel must stay open.
		objects._reset_selection()
		_click(at)
		_check(objects.selected == node, "Plain click selects the installed %s" % item[0])
		_check(_panel_visible(str(item[2])), "The %s settings panel stays open after a plain click" % item[0])
	# Persistence: save, reload, the edits are still there.
	var data: Dictionary = JSON.parse_string(JSON.stringify(planner.storage._collect_layout_data()))
	objects._reset_selection()
	objects._apply_layout_data(data)
	await process_frame
	_check_persisted()
	planner.exit()
	stage.queue_free()
	await process_frame
	print("Planner object settings tests: %d failure(s)." % failures)
	quit(1 if failures > 0 else 0)


func _entry(file_name: String) -> Dictionary:
	var lists: Array = [planner.catalog.lighting_catalog, planner.catalog.actor_catalog]
	lists.append_array(planner.catalog.group_catalogs.values())
	for list: Array in lists:
		for entry: Dictionary in list:
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
	if objects.placed.size() == before:
		return null
	return objects.placed.back()


func _screen_of(node: Node3D) -> Vector2:
	var box: AABB = planner.geometry._combined_aabb(node)
	var center: Vector3 = node.global_transform * box.get_center() if box.size.length_squared() > 0.0001 else node.global_position
	var base: Vector2 = planner.camera.unproject_position(center)
	# Another authored object can sit on the same pixel; take a point where this one is the pick.
	for radius in [0, 6, 12, 20, 30, 45, 60, 90]:
		for dx in [-2, -1, 0, 1, 2]:
			for dy in [-2, -1, 0, 1, 2]:
				var point: Vector2 = base + Vector2(dx, dy) * radius
				if planner.geometry._planned_object_at(point) == node:
					return point
	return base


func _click(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		# The planner's own input handler, so a headless window's stretch cannot move the click.
		planner._input(event)


func _panel_visible(kind: String) -> bool:
	match kind:
		"lamp": return controls.light_defaults.visible
		"door": return controls.door_options.panel.visible
		"display": return controls.display_options.panel.visible
		"enemy", "loot": return controls.loot_options.panel.visible
		"fruit": return controls.fruit_options.panel.visible
	return false


func _edit_and_check(label: String, node: Node3D) -> void:
	match label:
		"lamp":
			controls.default_light_energy.value = 7.5
			_check(is_equal_approx(node.get_authored_energy(), 7.5), "Lamp brightness applies live")
		"door":
			controls.door_options.state.select(2)
			controls.door_options.state.item_selected.emit(2)
			_check(controls.door_options.lockable_controller(node).get_lock_state() == &"sealed", "Door state applies live")
		"monitor", "laptop":
			controls.display_options.power.select(1)
			controls.display_options.power.item_selected.emit(1)
			_check(node.get_display_config()["power"] == "off", label + " power applies live")
		"desk lamp":
			controls.display_options.power.select(1)
			controls.display_options.power.item_selected.emit(1)
			_check(node.get_display_config()["power"] == "off", "Desk lamp power applies live")
			var glow := node.find_child("BudgetLight", true, false)
			_check(glow != null and not glow.is_wanted(), "Switched-off desk lamp stops lighting")
		"crate":
			controls.loot_options.mode.select(2)
			controls.loot_options.mode.item_selected.emit(2)
			_check(node.get_loot_config()["mode"] == "auto", "Crate loot applies live")
		"plate":
			controls.fruit_options.enabled.button_pressed = true
			controls.fruit_options.count.value = 4
			_check(node.get_fruit_config()["enabled"] and node.get_fruit_config()["count"] == 4, "Plate fruit applies live")
		"enemy":
			controls.loot_options.health.value = 155.0
			_check(is_equal_approx(float(node.get_enemy_stats()["health"]), 155.0), "Enemy health applies live")


func _check_persisted() -> void:
	var found := {}
	for node: Node3D in objects.placed:
		if not is_instance_valid(node):
			continue
		var kind: String = controls.settings_kind(node)
		match kind:
			"lamp":
				found["lamp"] = is_equal_approx(node.get_authored_energy(), 7.5) or found.get("lamp", false)
			"door":
				found["door"] = controls.door_options.lockable_controller(node).get_lock_state() == &"sealed" or found.get("door", false)
			"display":
				var file := str(node.get("model_path")).get_file()
				if file == "05_lamp.glb":
					found["desk lamp"] = node.get_display_config()["power"] == "off" or found.get("desk lamp", false)
				elif node.get_display_config()["power"] == "off":
					found["screen"] = true
			"loot":
				found["crate"] = node.get_loot_config()["mode"] == "auto" or found.get("crate", false)
			"enemy":
				found["enemy"] = is_equal_approx(float(node.get_enemy_stats()["health"]), 155.0) or found.get("enemy", false)
			"fruit":
				found["plate"] = (node.get_fruit_config()["enabled"] and node.get_fruit_config()["count"] == 4) or found.get("plate", false)
	for key: String in ["lamp", "door", "desk lamp", "screen", "crate", "enemy", "plate"]:
		_check(bool(found.get(key, false)), "Edited %s settings survive save and reload" % key)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
