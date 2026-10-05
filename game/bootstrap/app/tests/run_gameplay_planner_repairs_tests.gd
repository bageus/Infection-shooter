extends SceneTree

const DOOR := preload("res://game/presentation/office_floor/public/structural/sliding_glass_door.tscn")
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const PREFS := preload("res://game/bootstrap/app/menu/menu_preferences.gd")
const POPUP := preload("res://game/bootstrap/app/planner_color_popup.gd")
const SURFACE := preload("res://game/bootstrap/app/planning_surface_placement.gd")
var failures := 0
var stage: Node3D
var planner: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_audio()
	stage = MAIN.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	stage.set_physics_process(false)
	var player: Node3D = stage.get("player")
	player.set_physics_process(false)
	await _glass_pipeline()
	await _blood(player)
	paused = false
	stage.call("_on_planning_pressed")
	planner = stage.get("planning_mode")
	await _placement()
	await _picker_and_palette()
	planner.call("exit")
	stage.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	print("Gameplay/planner repairs tests: %d failures" % failures)
	quit(failures)


func _audio() -> void:
	var existed := FileAccess.file_exists(PREFS.FILE)
	var bytes := FileAccess.get_file_as_bytes(PREFS.FILE) if existed else PackedByteArray()
	var prefs := PREFS.new()
	prefs.values.effects_volume = .2
	prefs.values.music_volume = .8
	prefs.save_settings()
	var loaded := PREFS.new()
	loaded.load_settings()
	loaded.apply_to_game(self)
	_check(is_equal_approx(loaded.values.effects_volume, .2) and is_equal_approx(loaded.values.music_volume, .8), "Separate mix levels persist")
	for name in [&"SFX", &"UI", &"Music"]:
		var index := AudioServer.get_bus_index(name)
		_check(index >= 0, "Audio bus exists: " + str(name))
		if index >= 0:
			var expected := .8 if name == &"Music" else .2
			_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(index)), expected), "Bus obeys its own level: " + str(name))
	prefs.values.effects_volume = 0.0
	prefs.apply_to_game(self)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")), "Muting effects leaves music enabled")
	if existed:
		var file := FileAccess.open(PREFS.FILE, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
	else:
		DirAccess.remove_absolute(PREFS.FILE)
	prefs.reset()
	prefs.load_settings()
	prefs.apply_to_game(self)


func _blood(player: Node3D) -> void:
	var effects: Node3D = stage.get("blood_effects")
	_check(player.is_connected("projectile_blood", Callable(effects, "splatter_hit")), "Bootstrap binds player to common blood renderer")
	effects.call("clear_marks")
	player.call("take_damage", 5.0)
	await physics_frame
	await physics_frame
	_check(effects.call("statistics")["marks"] == 0, "Armour absorption creates no tissue blood")
	var wall := _wall(player.global_position + Vector3(0, 0, -1.0))
	var surfaces: Array[Node] = [wall]
	effects.call("configure_environment", surfaces)
	await physics_frame
	await physics_frame
	player.set("armor", 0.0)
	player.call("take_projectile_damage", 10.0, player.global_position, Vector3.FORWARD, "PISTOL")
	await physics_frame
	await physics_frame
	_check(effects.call("statistics")["marks"] > 0, "Player tissue damage produces supplied blood textures")
	var budget: Node3D = effects.get("_budget")
	var container: Node3D = budget.get("container")
	_check(_count_surface(container, wall) > 0, "Hit direction sprays onto the nearby wall")
	effects.call("clear_marks")
	var excluded: Array[RID] = [player.get_rid()]
	effects.call("severed_burst", player.global_position, Vector3.FORWARD, excluded)
	await physics_frame
	await physics_frame
	_check(container.get_child_count() >= 12, "Rupture combines many enlarged textured splashes")
	_check(_count_surface(container, wall) > 0, "Rupture reaches nearby walls")
	var floor_count := 0
	for mark in container.get_children():
		if mark.global_basis.y.y > .9:
			floor_count += 1
		_check(not mark.find_children("*", "Decal", true, false).is_empty() or not mark.find_children("*", "MeshInstance3D", true, false).is_empty() or not (mark.get("_projected") as Array).is_empty(), "Blood marks have a texture-bearing visual")
	_check(floor_count >= 8, "Rupture spreads over the floor")
	effects.call("clear_marks")
	player.set("_blood_motion_start", player.global_position)
	player.position.x += .6
	player.call("_update_move", 0.0)
	await physics_frame
	await physics_frame
	_check(effects.call("statistics")["marks"] > 0, "A wounded player leaves a movement trail")
	effects.call("clear_marks")
	paused = true
	player.call("take_damage", 1000.0)
	await physics_frame
	await physics_frame
	_check(effects.call("statistics")["marks"] > 0, "Final damage and death render even when game-over has paused simulation")
	var clock: float = budget.get("_clock")
	await create_timer(.15).timeout
	_check(is_equal_approx(clock, budget.get("_clock")), "Blood lifetime stays frozen during pause")
	paused = false
	player.set("health", player.get("max_health"))
	effects.call("clear_marks")
	wall.queue_free()
	await process_frame


func _count_surface(container: Node3D, body: Node3D) -> int:
	var count := 0
	for mark in container.get_children():
		if (mark.get("surface_ref") as WeakRef).get_ref() == body:
			count += 1
	return count


func _wall(point: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	stage.add_child(wall)
	wall.global_position = point
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(4, 3, .12)
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = shape.shape.size
	wall.add_child(mesh)
	return wall


func _placement() -> void:
	var geometry: RefCounted = planner.get("geometry")
	for model in ["01/01_floor_2x2.glb", "05/05_wall_TV_frameless_destructible.glb", "01/01_VECTRION_Destructible.glb"]:
		var item := planner.call("_instantiate_asset", "res://models/objects/enviroments/" + model) as Node3D
		stage.add_child(item)
		item.set("freeze", true)
		await process_frame
		item.scale = Vector3(1.5, 2.0, .8)
		var bounds: AABB = geometry.call("_combined_aabb", item)
		if "floor" in model:
			item.global_position = geometry.call("_snap_position_for", item, Vector3.ZERO)
			var grounded: AABB = item.global_transform * bounds
			_check(is_equal_approx(grounded.position.y, SURFACE.BASE_FLOOR_TOP + SURFACE.CLEARANCE), "Scaled flat carpet sits above the visible floor")
		else:
			_check(item.get_meta("planning_wall_mount", false), "TV/company logo is wall mounted: " + model)
			item.global_position = Vector3(3, 1.7, 4)
			item.set_meta("planning_wall_normal", Vector3.LEFT)
			geometry.call("_apply_wall_mount", item)
			var mounted: AABB = item.global_transform * bounds
			_check(absf(mounted.end.x - (3.0 - SURFACE.CLEARANCE)) < .0001, "Actual scaled back plane touches wall: " + model)
		if "floor" in model:
			item.global_position.y = -.2
			geometry.call("_restore_floor_surface", item, model)
			var restored: AABB = item.global_transform * bounds
			_check(is_equal_approx(restored.position.y, SURFACE.BASE_FLOOR_TOP + SURFACE.CLEARANCE), "Existing buried carpet is restored on load")
		item.queue_free()
	await process_frame


func _picker_and_palette() -> void:
	var controls: Node = planner.get("controls")
	_check(not stage.get_node("PlanningUI/Panel/VBox/Title").visible, "Large planner title is removed")
	var panel := stage.get_node("PlanningUI/Panel") as ScrollContainer
	_check(panel != null, "Entire palette can scroll to its bottom")
	controls.call("_show_lighting_catalog")
	var catalog: RefCounted = planner.get("catalog")
	var shapes: Array = catalog.get("lighting_catalog")
	_check(shapes.any(func(entry: Dictionary) -> bool: return entry.get("fixture_shape", "") == "linear"), "Linear lamp is present in the merged palette")
	_check(shapes.any(func(entry: Dictionary) -> bool: return entry.get("fixture_shape", "") == "rectangle"), "Rectangular lamp is present in the merged palette")
	var picker: ColorPickerButton = controls.get("default_light_color")
	picker.get_popup().popup()
	await process_frame
	POPUP.fit(picker.get_popup(), Vector2(640, 420))
	await process_frame
	var popup := picker.get_popup()
	_check(popup.position.x >= 0 and popup.position.y >= 0 and popup.position.x + popup.size.x <= 640 and popup.position.y + popup.size.y <= 420, "Lighting picker fits a short viewport")
	_check(picker.get_picker().get_parent() is ScrollContainer, "Picker controls remain scrollable")
	popup.hide()
	await process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _glass_pipeline() -> void:
	var impacts: Node = stage.get("impact_pool")
	var door := DOOR.instantiate() as Node3D
	stage.add_child(door)
	door.position = Vector3(15, 0, 0)
	var pane: Node3D = door.get_node("GlassBody")
	pane.call("configure_world", stage, impacts)
	var mesh: MeshInstance3D = pane.get("_glass_nodes")[0]
	var point := mesh.global_transform * mesh.get_aabb().get_center()
	var normal := mesh.global_basis.y.normalized()
	var bullet := preload("res://game/features/combat/public/prototype_bullet.tscn").instantiate()
	stage.add_child(bullet)
	bullet.call("configure_world", stage, impacts)
	bullet.call("setup_projectile", -normal, null, 26, 36, 34, "PISTOL", point + normal)
	bullet.set_physics_process(false)
	for hit in 8:
		bullet.call("_handle_hit", pane, point, normal)
	await process_frame
	_check(pane.call("crack_count") == 0, "Real projectile dispatch shatters glass and removes cracks")
	_check(pane.find_children("*", "MeshInstance3D", true, false).is_empty(), "No floating impact survives on the broken pane")
	bullet.queue_free()
	door.queue_free()
	await process_frame
