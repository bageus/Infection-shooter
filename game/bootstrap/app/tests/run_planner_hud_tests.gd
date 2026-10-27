extends SceneTree
## HUD hit regions, bounded layouts, palette separation and disabled fog selection.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const ZONE := preload("res://game/presentation/office_floor/public/props/darkness_zone.tscn")
const SURFACES := preload("res://game/presentation/office_floor/public/surface_decor_catalog.gd")
var failures := 0
var stage: Node3D
var planner: Node
var controls: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1200, 700)
	stage = MAIN.instantiate()
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	current_scene = stage
	await process_frame
	planner = stage.get("planning_mode")
	planner.enter()
	controls = planner.controls
	var layout: RefCounted = controls.hud_layout
	_check(layout.right.offset_top == 8, "Right HUD aligns with the other HUDs")
	_check(layout.main.has_node("MapManager") and layout.main.has_node("Save"), "Main owns map and layout controls")
	for name in ["FogOfWarToggle", "LocalLights", "AutoFireAlarms", "AutoLightSwitches", "SurfaceDecalSettings", "LightingPreview", "LightTopView", "Clear", "Close"]:
		_check(layout.main.has_node(name), "Main contains " + name)
	_check(layout.constructor.has_node("ChainList"), "Constructor owns the chain list")
	_check(not layout.main.has_node("ChainList"), "Chain controls stay out of Main")
	var left := planner.ui.get_node("Panel") as Control
	var width := left.size.x
	var maps := layout.main.get_node("MapManager/Maps") as OptionButton
	maps.add_item("long map name ".repeat(100))
	maps.select(maps.item_count - 1)
	layout.selected_name.text = "long selected object name ".repeat(100)
	controls.status.text = "long notification ".repeat(200)
	await process_frame
	await process_frame
	_check(layout.selection.size.y <= 44, "Selection HUD stays within two compact lines")
	for name in ["Items", "Weapons", "Biomass", "Decals"]:
		_check(left.has_node("VBox/Tabs/" + name), name + " is a top palette tab")
	controls.palette.add_item("very long catalogue name ".repeat(20))
	for size in [Vector2i(1024, 600), Vector2i(1200, 700), Vector2i(1600, 900)]:
		root.size = size
		await process_frame
		await process_frame
		_assert_hud_separation(layout, left)
		_check(is_equal_approx(left.size.x, width), "Long entries and viewport changes keep the palette width fixed")
		_check(controls.palette.fixed_column_width > 0 and controls.palette.fixed_column_width <= controls.palette.size.x, "Palette entries share one column as wide as the list, so they centre on one axis")
		_check(left.get_node("VBox").size.x <= width, "Palette contents fit within the fixed HUD")
		_check(is_equal_approx(layout.right.size.x, 360.0) and layout.right_content.size.x <= 360, "Long map names cannot widen the right HUD")
	await _exercise_tabs(layout, left)
	await _exercise_selection()
	_exercise_center_button(layout)
	await _exercise_decal_roundtrip()
	planner.exit()
	stage.queue_free()
	await process_frame
	print("Planner HUD tests: %d failure(s)." % failures)
	quit(failures)


func _exercise_tabs(layout: RefCounted, left: Control) -> void:
	layout.right_tabs.current_tab = 1
	await process_frame
	_check(layout.constructor.is_visible_in_tree() and not layout.main.is_visible_in_tree(), "Constructor tab switches its whole content")
	layout.toggle_right()
	_check(not layout.right.visible and layout.collapse.is_visible_in_tree(), "Collapsed HUD keeps a restore handle")
	_check(layout.contains_point(layout.collapse.get_global_rect().get_center()), "Restore handle consumes world input")
	layout.toggle_right()
	_check(layout.right_tabs.current_tab == 1, "Restoring keeps the selected tab")
	layout.right_tabs.current_tab = 0
	controls._show_actor_catalog()
	await process_frame
	await process_frame
	_check(controls.spawn_options.panel.get_parent() == controls.palette.get_parent(), "Wave settings share the palette scroll")
	_assert_hud_separation(layout, left)
	controls._toggle_help()
	await process_frame
	await process_frame
	_check(layout.help_scroll.visible, "Help opens inside the center scroll")
	_assert_hud_separation(layout, left)
	layout.toggle_right()
	await process_frame
	await process_frame
	_assert_hud_separation(layout, left)
	layout.toggle_right()
	controls._toggle_help()
	controls._show_blood_catalog()
	_check(planner.catalog.active_catalog.size() == 44 and not controls.biomass_options.panel.visible, "Blood contains only blood and no generator")
	controls._show_biomass_catalog()
	_check(planner.catalog.active_catalog.size() == 6 and controls.biomass_options.panel.visible, "Biomass has its own patches and generator")
	controls.decal_palette.choose_category("floor")
	for material: String in SURFACES.FLOOR_MATERIALS:
		controls.decal_palette.choose_material(material)
		var entries: Array = planner.catalog.active_catalog
		_check(not entries.is_empty() and entries.all(func(entry: Dictionary) -> bool: return str(entry.blood_texture).begins_with("surface:" + material + ":")), "Floor filters " + material)
	controls.decal_palette.choose_category("walls")
	_check(controls.blood_surface.selected == 1 and planner.catalog.active_catalog.size() == 40, "Wall decals default to wall placement")
	controls.decal_palette.choose_category("glass")
	_check(planner.catalog.active_catalog.size() == 24, "Glass offers cracks and impacts")
	controls._show_item_catalog()
	_check(not controls.decal_palette.panel.visible and not controls.biomass_options.panel.visible, "Items hides unrelated palette options")


func _assert_hud_separation(layout: RefCounted, left: Control) -> void:
	var parts: Array[Control] = [controls.planning_toolbar, layout.selection, left, layout.collapse]
	if layout.right.visible:
		parts.append(layout.right)
	if layout.help_scroll.visible:
		parts.append(layout.help_scroll)
	for i in parts.size():
		for j in range(i + 1, parts.size()):
			_check(not parts[i].get_global_rect().intersects(parts[j].get_global_rect()), "HUD rectangles do not overlap: %s / %s" % [parts[i].name, parts[j].name])
	_check(layout.selection.size.y <= 44, "Selection stays within two lines at every viewport size")


func _exercise_selection() -> void:
	var camera: Camera3D = planner.camera
	camera.global_position = Vector3(120, 12, 120)
	camera.global_rotation = Vector3(-PI * .5, 0, 0)
	var cube := Node3D.new()
	cube.name = "SelectedTestObject"
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	cube.add_child(mesh)
	planner.root.add_child(cube)
	cube.position = Vector3(120, .5, 120)
	planner.objects.placed.append(cube)
	var zone := ZONE.instantiate() as Node3D
	planner.root.add_child(zone)
	zone.position = Vector3(120, 3, 120)
	planner.objects.placed.append(zone)
	await process_frame
	zone.call("set_fog_of_war_enabled", true)
	var screen := camera.unproject_position(cube.global_position)
	_check(planner._planned_object_at(screen) == zone, "Enabled zone can be selected above an object")
	zone.call("set_fog_of_war_enabled", false)
	_check(not zone.is_processing() and planner._planned_object_at(screen) == cube, "Disabled fog has no processing or picking presence")
	planner._select(cube)
	_check("SelectedTestObject" in controls.hud_layout.selected_name.text, "Separate selection HUD always names the object")
	_check(controls.status.get_parent().get_parent() == controls.hud_layout.selection, "Object information is below the action toolbar")
	zone.call("set_fog_of_war_enabled", true)
	_check(planner._planned_object_at(screen) == zone, "Re-enabling restores editable fog")
	controls.light_view.set_enabled(true)
	controls._show_weapon_catalog()
	_check(controls.light_view.active and controls.light_view.button.visible, "Top view works across palettes")
	controls.light_view.set_enabled(false)


func _exercise_center_button(layout: RefCounted) -> void:
	_check(controls.center_button.get_parent() == controls.undo_button.get_parent(), "Центр локации sits with Undo and Duplicate")
	var floor_view := stage.get_node("Floor") as Node3D
	var field_center := floor_view.global_position
	floor_view.call("set_floor_size", Vector2(120, 90))
	planner.camera.global_position = Vector3(40, 12, -25)
	planner.camera_anchor = planner.camera.global_position
	controls.center_button.pressed.emit()
	var p: Vector3 = planner.camera.global_position
	_check(is_equal_approx(p.x, field_center.x) and is_equal_approx(p.z, field_center.z), "Центр локации moves the camera to the centre of a resized field")
	_check(is_equal_approx(p.y, 12.0), "Центр локации keeps the camera height")
	_check(is_equal_approx(planner.camera_anchor.x, p.x) and is_equal_approx(planner.camera_anchor.z, p.z), "Центр локации updates the camera anchor")
	floor_view.call("set_floor_size", Vector2(80, 60))


func _exercise_decal_roundtrip() -> void:
	planner.objects._reset_selection()
	var nodes: Array[Node3D] = []
	var entries: Array = SURFACES.entries("floor") + SURFACES.entries("walls") + SURFACES.entries("glass")
	# The last frame also covers the second wood/paper sheet and out-of-range handling.
	var kinds: Dictionary = {}
	for entry: Dictionary in entries:
		kinds[str(entry.blood_texture).get_slice(":", 1)] = entry
	for entry: Dictionary in kinds.values():
		var id := str(entry.blood_texture)
		var texture: Dictionary = SURFACES.texture_entry(id)
		var atlas: AtlasTexture = texture.get("texture")
		var pixels := atlas.atlas.get_image()
		if pixels.is_compressed():
			pixels.decompress()
		_check(not pixels.get_region(Rect2i(atlas.region)).is_empty(), "Atlas pixels exist: " + id)
		var node: Node3D = planner._instantiate_asset(str(entry.path))
		controls._configure_new_asset(node, entry)
		planner.root.add_child(node)
		node.position = Vector3(130 + nodes.size(), .0135, 130)
		node.set_meta("planning_scene_path", entry.path)
		planner.objects.placed.append(node)
		nodes.append(node)
		var packed := PackedScene.new()
		_check(packed.pack(node) == OK, "Manual decal packs: " + id)
		var unpacked := packed.instantiate() as Node3D
		_check(str(unpacked.call("get_blood_config").texture) == id, "Packed scene retains surface texture: " + id)
		unpacked.free()
	var capture := preload("res://game/bootstrap/app/planning_layout_capture.gd")
	var data: Dictionary = JSON.parse_string(JSON.stringify(capture.collect(planner.objects, nodes)))
	var restored: Dictionary = planner.objects._apply_layout_data(data)
	_check(not restored.has("error"), "Manual decals reload through the map loader")
	for entry: Dictionary in kinds.values():
		var found := false
		for node: Node3D in planner.objects.placed:
			if is_instance_valid(node) and node.has_method("get_blood_config") and str(node.call("get_blood_config").texture) == str(entry.blood_texture):
				found = true
		_check(found, "Map JSON retains manual decal: " + str(entry.blood_texture))
	await process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
