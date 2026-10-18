extends SceneTree
## Regression coverage for preview self-hit, durable templates and weapon maps.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const FILES := preload("res://game/bootstrap/app/desk_setup_template_files.gd")
const VISUALS := preload("res://game/bootstrap/app/desk_setup_visuals.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const TABLE := "res://models/objects/enviroments/07/07_table_square.glb"
const RECEPTION := "res://models/objects/enviroments/07/07_reception_counter_two_heights_2.glb"
const SHELF := "res://models/objects/enviroments/03/03_bookshelf.glb"
var failures := 0

class LegacyMode extends Node:
	var desk: Node3D
	var zones: Array[Dictionary] = []
	var stations: Array = []
	var items: Array[Node3D] = []
	func _attachments() -> Array[Node3D]:
		return items


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_legacy_surfaces()
	var stage := MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	await physics_frame
	stage.call("_on_planning_pressed")
	var planner: Node = stage.get("planning_mode")
	await _preview_self_hit(planner)
	await _templates(planner)
	await _weapons(planner)
	await _freed_glass(planner)
	planner.call("exit")
	stage.queue_free()
	await process_frame
	print("Placement/templates/weapons tests: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _preview_self_hit(planner: Node) -> void:
	var camera := planner.get("camera") as Camera3D
	var editor: Node = planner.get("objects")
	var geometry: RefCounted = planner.get("geometry")
	var preview := StaticBody3D.new()
	preview.set_meta("planning_preview", true)
	(planner.get("host") as Node).add_child(preview)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	collision.shape = box
	preview.add_child(collision)
	preview.global_position = Vector3(28, 1, 22)
	camera.global_position = Vector3(28, 12, 30)
	camera.look_at(Vector3(28, 0, 22))
	await physics_frame
	var screen := camera.unproject_position(Vector3(28, 0, 22))
	for step in 24:
		var point: Vector3 = geometry.call("_screen_to_surface", screen, preview)
		_check(point.y < .1, "Surface ray excludes active preview collision, step %d" % step)
		preview.global_position.y = point.y + 1.0
	_check((geometry.call("_mount_exclusions", preview) as Array).has(preview.get_rid()), "Root collider excluded")
	preview.free()
	# Exercise a real dynamic imported object repeatedly through planner updates.
	editor.set("selected_path", TABLE)
	editor.set("selected_kind", "environment")
	editor.call("_rebuild_preview")
	await process_frame
	var actual := editor.get("preview") as RigidBody3D
	_check(actual != null and actual.freeze, "Imported preview is frozen")
	_check(actual.process_mode == Node.PROCESS_MODE_DISABLED, "Preview cannot animate")
	editor.call("_update_preview", screen)
	var first := actual.global_position
	for step in 60:
		editor.call("_update_preview", screen)
		await physics_frame
	_check(first.distance_to(actual.global_position) < .001, "Preview height remains stable for 60 ticks")
	editor.call("_reset_selection")


func _templates(planner: Node) -> void:
	var name_part := "regression_" + str(Time.get_ticks_usec())
	var setup: Node = planner.get("desk_setup")
	for path in [TABLE, SHELF, RECEPTION, "res://models/objects/enviroments/08/08_divider_full_H_desk.glb", "res://models/objects/enviroments/08/08_divider_full_U_desk.glb"]:
		var desk := planner.call("_instantiate_asset", path) as Node3D
		(planner.get("root") as Node).add_child(desk)
		desk.set_meta("planning_scene_path", path)
		desk.set_meta("planning_desk_id", "regression_desk")
		desk.global_position = Vector3(28, 0, 22)
		desk.rotation.y = .7
		if path == TABLE:
			var overlay := MeshInstance3D.new()
			overlay.mesh = BoxMesh.new()
			overlay.mesh.size = Vector3(80, .001, 80)
			overlay.set_meta("planning_bounds_excluded", true)
			desk.add_child(overlay)
		if path == RECEPTION:
			planner.call("_select", desk)
			var controls: Node = planner.get("controls")
			_check(controls.get("desk_setup_button").visible, "Installed reception exposes the template button")
			controls.call("_open_desk_setup")
			_check(bool(setup.get("active")), "Reception template editor opens through the normal planner action")
		else:
			setup.call("open", desk)
		(setup.get("template_name") as LineEdit).text = name_part
		var zones: Array = setup.get("zones")
		if path == TABLE:
			var actual: AABB = planner.get("geometry")._combined_aabb(desk)
			_check(Vector2(zones[0].x, zones[0].z).distance_to(Vector2(actual.get_center().x, actual.get_center().z)) < .01, "Service overlays do not shift the table zones")
		zones[0]["name"] = "Полка / стол"
		zones[0]["required"] = false
		zones[0]["category"] = "Mouse"
		setup.call("_place_model", "05_computer_mouse", Vector3(float(zones[0].x), float(zones[0].height), float(zones[0].z)))
		_check((setup.call("_attachments") as Array).size() == 1, "Table/shelf item is attached")
		setup.call("close")
		setup.call("open", desk)
		zones = setup.get("zones")
		_check(zones[0].category == "Mouse", "Reopening preserves the existing item's zone category")
		await _drag_existing(planner, setup, path)
		var expected: Array = zones.duplicate(true)
		setup.call("_save")
		var key: String = planner.get("catalog").WORKSTATIONS.desk_name(path)
		var matching := FILES.list_for(key).filter(func(item: Dictionary) -> bool: return item.name == name_part)
		_check(matching.size() == 1, "Table/shelf template appears on disk")
		if matching.size() == 1:
			var saved_path: String = matching[0].path
			var saved := FILES.load(saved_path, key)
			_check(saved.get("items", []).size() == 1, "Template persists its attached item")
			_check(not saved.is_empty() and saved.zones[0].name == expected[0].name, "Unicode zone survives JSON")
			# Overwriting also uses the validated temporary file.
			zones[0]["name"] = "Replacement"
			setup.call("_save")
			_check(FILES.load(saved_path, key).zones[0].name == "Replacement", "Existing template can be overwritten")
			zones[0]["name"] = "Unsaved edit"
			setup.call("_load")
			_check((setup.get("zones") as Array)[0].name == "Replacement", "UI reload restores saved zone")
			_check((setup.call("_attachments") as Array).size() == 1, "UI reload restores saved item")
			_check(FILES.load(saved_path, "wrong_model").is_empty(), "Model types remain isolated")
			await _spawned_template(planner, setup, path, FILES.load(saved_path, key))
			setup.call("close")
			setup.set("edit_state", preload("res://game/bootstrap/app/desk_setup_edit_state.gd").new())
			setup.call("open", desk)
			_check((setup.get("zones") as Array)[0].category == "Mouse", "Legacy map derives a typed zone: " + path)
			await _drag_existing(planner, setup, path)
			DirAccess.remove_absolute(saved_path)
		if path == RECEPTION:
			await _reception_surfaces(planner, setup)
		if path == TABLE:
			var camera := planner.get("camera") as Camera3D
			(setup.get("markers") as Node).call("show_top_view", camera)
			_check((-camera.global_basis.z).dot(Vector3.DOWN) > .999999, "TOP VIEW looks exactly down")
			(setup.get("markers") as Node).call("zoom_view", camera, -.4)
			_check((-camera.global_basis.z).dot(Vector3.DOWN) > .999999, "Zoom preserves top view")
			(setup.get("markers") as Node).call("rotate_view", camera, Vector2(0, 8))
			_check((-camera.global_basis.z).dot(Vector3.DOWN) < .99, "Orbit returns to angled view")
		for item: Node3D in setup.call("_attachments"):
			(planner.get("objects").placed as Array).erase(item)
			item.free()
		setup.call("close")
		desk.free()


func _spawned_template(planner: Node, setup: Node, path: String, saved: Dictionary) -> void:
	var desk := planner.call("_instantiate_asset", path) as Node3D
	(planner.get("root") as Node).add_child(desk)
	desk.set_meta("planning_scene_path", path)
	desk.set_meta("planning_desk_id", "spawned_template")
	desk.global_position = Vector3(30, 0, 24)
	var workstations := preload("res://game/bootstrap/app/workstation_templates.gd")
	var items := workstations.from_saved_template(desk, path, planner.get("root"), Callable(planner, "_instantiate_asset"))
	for item in items:
		item.set_meta("planning_attachment", "spawned_template")
		(planner.get("objects").placed as Array).append(item)
	var previous: Node3D = setup.get("desk")
	setup.call("open", desk)
	_check((setup.get("zones") as Array)[0].name == saved.zones[0].name, "Placement retains exact saved template zones: " + path)
	_check(not desk.has_meta("planning_template_edit"), "Transient placement snapshot is consumed")
	await _drag_existing(planner, setup, path)
	setup.call("close")
	for item in items:
		(planner.get("objects").placed as Array).erase(item)
		item.free()
	desk.free()
	setup.call("open", previous)


func _drag_existing(planner: Node, setup: Node, path: String, target_item: Node3D = null) -> void:
	await process_frame
	var attached: Array = setup.call("_attachments")
	_check(not attached.is_empty(), "Template retains editable attachments: " + path)
	if attached.is_empty():
		return
	var item: Node3D = target_item if target_item != null else attached[0]
	var camera := planner.get("camera") as Camera3D
	var bounds: AABB = planner.get("geometry")._combined_aabb(item)
	var screen := camera.unproject_position(item.to_global(bounds.get_center()))
	_check(camera.get_viewport().get_visible_rect().has_point(screen), "Template camera includes its editable surface: " + path)
	setup.call("_click_world", screen, true)
	_check(setup.get("dragged") == item, "Shift click picks a visible attachment: " + path)
	var before := item.global_position
	var target := before + (setup.get("desk") as Node3D).global_basis.x * 0.05
	setup.call("_drag_item", camera.unproject_position(target))
	_check(item.global_position.distance_to(before) > 0.02, "Existing item moves after reopening: " + path)


func _weapons(planner: Node) -> void:
	var controls: Node = planner.get("controls")
	controls.call("_show_weapon_catalog")
	var entries: Array = planner.get("catalog").active_catalog
	_check(entries.size() == 8, "Palette contains all eight weapon slots")
	var records: Array = []
	for i in entries.size():
		var path: String = entries[i].path
		records.append({"scene": path, "x": 20.0 + i, "y": .4, "z": 20.0})
	var editor: Node = planner.get("objects")
	var result: Dictionary = editor.call("_apply_layout_data", {"version": 8, "objects": records})
	_check(result.get("loaded", 0) == 8, "All weapon scenes load from map v8")
	var saved: Dictionary = planner.get("storage").call("_collect_layout_data")
	var weapon_records: Array = saved.objects.filter(func(entry: Dictionary) -> bool: return "weapon_pickups/" in str(entry.scene))
	_check(weapon_records.size() == 8, "Map snapshot retains all weapon scene identities")
	result = editor.call("_apply_layout_data", {"version": 8, "objects": weapon_records})
	_check(result.get("loaded", 0) == 8, "Weapon snapshot reloads")
	var pickups: Array = (editor.get("placed") as Array).filter(func(node: Node3D) -> bool: return node.is_in_group("weapon_pickups"))
	for i in pickups.size():
		var item: Node3D = pickups[i]
		_check(int(item.get("weapon_index")) == i, "Reload preserves weapon index %d" % i)
		var position := item.global_position
		item.call("_process", .1)
		_check(item.global_position.y >= position.y and item.global_position.y < position.y + .08, "Runtime bob starts at saved height")
		item.call("_process", 3.0)
		_check(item.global_position.y >= position.y, "Authored weapon does not bob below support")


func _freed_glass(planner: Node) -> void:
	var prop := PROP.instantiate()
	var mesh := MeshInstance3D.new()
	var collision := CollisionShape3D.new()
	prop.add_child(collision)
	collision.shape = BoxShape3D.new()
	var geometry: RefCounted = prop.get("_geometry")
	(geometry.get("shapes") as Array).append(collision)
	(geometry.get("meshes") as Array).append(mesh)
	mesh.free()
	_check(prop.call("get_projectile_material", 0) == "wood", "Freed mesh does not enter typed glass dispatch")
	prop.call("take_projectile_hit_at_shape", 0.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, "GRENADE", 0)
	prop.free()


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _legacy_surfaces() -> void:
	var mode := LegacyMode.new()
	root.add_child(mode)
	mode.desk = Node3D.new()
	mode.add_child(mode.desk)
	mode.desk.position = Vector3(3, 0, 4)
	mode.desk.rotation.y = .7
	for z in [-1.0, 1.0, 3.0]:
		mode.stations.append({"x": 0.0, "z": z, "usable_width": 1.0, "usable_depth": .8})
		mode.zones.append({"x": 0.0, "z": z, "height": .904, "floor": false, "category": "Other", "width": .65, "depth": .35})
	for z in [-1.0, 1.0]:
		var item := MeshInstance3D.new()
		item.mesh = BoxMesh.new()
		item.mesh.size = Vector3(.1, .05, .1)
		mode.add_child(item)
		item.global_position = mode.desk.to_global(Vector3(0, .929, z))
		item.set_meta("planning_scene_path", "res://models/objects/enviroments/05/05_computer_mouse.glb")
		mode.items.append(item)
	preload("res://game/bootstrap/app/desk_setup_edit_state.gd").new().restore(mode)
	_check(mode.zones.size() == 3, "Legacy restoration keeps the empty workstation surface")
	for item in mode.items:
		var zone: Dictionary = mode.zones[int(item.get_meta("planning_zone"))]
		_check(is_equal_approx(zone.height, .904), "Legacy station without grid_height keeps its profile height")
		_check(absf(float(zone.z) - mode.desk.to_local(item.global_position).z) < .001, "Equal-height workstations keep separate typed zones")
	mode.free()


func _reception_surfaces(planner: Node, setup: Node) -> void:
	var desk := setup.get("desk") as RigidBody3D
	_check(desk.freeze, "The planner keeps reception runtime physics anchored")
	var zones: Array = setup.get("zones")
	var upper_slot := -1
	for index in zones.size():
		if is_equal_approx(float(zones[index].height), 1.1):
			upper_slot = index
	_check(upper_slot >= 0, "Reception exposes its upper countertop as a separate editable surface")
	if upper_slot < 0:
		return
	setup.set("zone_index", upper_slot)
	zones[upper_slot].category = "Mouse"
	var zone: Dictionary = zones[upper_slot]
	setup.call("_place_model", "05_computer_mouse", Vector3(zone.x, zone.height, zone.z))
	var attachments: Array = setup.call("_attachments")
	_check(attachments.size() == 2, "Both reception countertops hold editable items")
	for item: Node3D in attachments:
		var slot := int(item.get_meta("planning_zone"))
		var bounds: AABB = planner.get("catalog").WORKSTATIONS._bounds(item)
		var expected_y: float = desk.to_global(Vector3.UP * float(zones[slot].height)).y
		_check(absf(bounds.position.y - expected_y) < .03, "Reception items rest on the actual authored countertop")
		await _drag_existing(planner, setup, RECEPTION, item)
	setup.call("_save")
	var name_part: String = setup.get("template_name").text
	var matching := FILES.list_for("reception_2").filter(func(item: Dictionary) -> bool: return item.name == name_part)
	_check(matching.size() == 1, "Two-height reception template is saved")
	if matching.size() == 1:
		var saved_path: String = matching[0].path
		var saved := FILES.load(saved_path, "reception_2")
		_check(saved.get("items", []).size() == 2, "Reception template preserves both countertop items")
		setup.call("_load")
		_check((setup.call("_attachments") as Array).size() == 2, "Both reception items survive template application")
		DirAccess.remove_absolute(saved_path)
		DirAccess.remove_absolute(saved_path + ".bak")
	preload("res://game/bootstrap/app/planning_physics.gd").resume([desk])
	_check(desk.freeze, "Leaving Planning does not release the reception anchor")
