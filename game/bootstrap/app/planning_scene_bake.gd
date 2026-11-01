extends RefCounted
## Bounded authored scene cloning; shared resources remain immutable.
const SCENE_SCRIPTS := preload("res://game/bootstrap/app/planning_scene_scripts.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const DOOR_OPTIONS := preload("res://game/bootstrap/app/planning_door_options.gd")
const DARKNESS := preload("res://game/bootstrap/app/planning_darkness_config.gd")
const WAVE_DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")
var catalog: Variant
var surface_settings: Dictionary = {}
var biomass_cache: Dictionary = {}

func _init(asset_catalog: Variant) -> void:
	catalog = asset_catalog

func save(nodes: Array, target: String) -> Error:
	var scene_root := Node3D.new()
	scene_root.name = "BaseOfficeLayout"
	for node: Node3D in nodes:
		if is_instance_valid(node):
			_append(node, scene_root)
	return _write(scene_root, target)

func save_async(nodes: Array, target: String, session: Node, status: Label) -> Error:
	var scene_root := Node3D.new()
	scene_root.name = "BaseOfficeLayout"
	var tree := session.get_tree()
	var started := Time.get_ticks_msec()
	for index in nodes.size():
		if is_instance_valid(nodes[index]):
			_append(nodes[index], scene_root)
		if index % 16 == 15 or Time.get_ticks_msec() - started >= 4:
			status.text = "BAKING SCENE | %d / %d" % [index + 1, nodes.size()]
			await tree.process_frame
			if not is_instance_valid(session) or not session.is_inside_tree():
				scene_root.free()
				return ERR_UNAVAILABLE
			started = Time.get_ticks_msec()
	return _write(scene_root, target)

func _write(scene_root: Node3D, target: String) -> Error:
	if not surface_settings.is_empty(): scene_root.set_meta("surface_decals_v1", surface_settings)
	if not biomass_cache.is_empty():
		var view := preload("res://game/presentation/office_floor/public/baked_biomass_floor.gd").new()
		view.name = "BakedFloorBiomass"
		view.cache = biomass_cache
		scene_root.add_child(view)
		view.owner = scene_root
		scene_root.set_meta("floor_biomass_v1", biomass_cache)
	var packed := PackedScene.new()
	var problem := packed.pack(scene_root)
	if problem == OK:
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		problem = ResourceSaver.save(packed, target)
		if problem == OK:
			problem = SCENE_SCRIPTS.canonicalize(target)
	scene_root.free()
	return problem

func _append(node: Node3D, scene_root: Node3D) -> void:
	var scene_path = str(node.get_meta("planning_scene_path", ""))
	if scene_path.is_empty():
		return
	var copy = catalog._instantiate_asset(scene_path)
	if copy == null:
		return
	if node.has_method("get_decor_pose"):
		copy.call("configure_decor_pose", node.call("get_decor_pose"))
	scene_root.add_child(copy)
	copy.owner = scene_root
	copy.transform = node.transform
	DARKNESS.apply(copy, DARKNESS.capture(node))
	if node.has_meta("planning_settled_transform") and node.get_meta("planning_settled_transform") == node.transform:
		copy.set_meta("planning_settled_transform", copy.transform)
	if node.has_meta("planning_object_id"):
		copy.set_meta("planning_object_id", node.get_meta("planning_object_id"))
	if node.has_method("has_display") and node.call("has_display"):
		copy.call("configure_display", node.call("get_display_config"))
	if node.has_method("get_loot_config") and node.has_meta(&"planning_loot"):
		copy.call("configure_loot", node.call("get_loot_config"))
	if node.has_method("has_fruit") and node.call("has_fruit") and bool(node.call("get_fruit_config")["enabled"]):
		copy.call("configure_fruit", node.call("get_fruit_config"))
	if TARGET.is_target(node):
		TARGET.configure(copy, true)
	var door := DOOR_OPTIONS.lockable_controller(node)
	var copy_door := DOOR_OPTIONS.lockable_controller(copy)
	if door != null and copy_door != null:
		copy_door.call("configure_lock_state", door.call("get_lock_state"))
		copy_door.call("configure_one_way", DOOR_OPTIONS.is_one_way(door))
	if node.has_method("get_enemy_stats") and node.has_meta(&"planning_enemy_stats"):
		copy.call("configure_stats", node.call("get_enemy_stats"))
	if node.has_method("get_death_cloud_config") and node.has_meta(&"planning_death_cloud"):
		copy.call("configure_death_cloud", node.call("get_death_cloud_config"))
	if node.has_method("get_spawn_config"):
		copy.call("configure_spawn", node.call("get_spawn_config"))
	if node.has_meta(WAVE_DIRECTOR.TRIGGER_META):
		copy.set_meta(WAVE_DIRECTOR.TRIGGER_META, node.get_meta(WAVE_DIRECTOR.TRIGGER_META))
	if node.has_method("get_fixture_config"):
		var fixture: Dictionary = node.call("get_fixture_config")
		copy.call("configure_fixture", str(fixture["shape"]), bool(fixture["visible_in_game"]))
	if node.has_method("get_blood_config"):
		var blood: Dictionary = node.call("get_blood_config")
		copy.call("configure_blood", str(blood["texture"]), str(blood["surface"]))
		copy.call("configure_blood_normal", node.get("surface_normal"))
		copy.call("configure_blood_attachment", node.call("get_blood_attachment"))
		if not biomass_cache.is_empty() and copy.has_method("set_floor_biomass_baked"):
			copy.call("set_floor_biomass_baked", true)
	if node.has_meta("planning_desk_id"):
		copy.set_meta("planning_desk_id", node.get_meta("planning_desk_id"))
	if node.has_meta("planning_attachment"):
		copy.set_meta("planning_attachment", node.get_meta("planning_attachment"))
	if node.has_meta("planning_zone"):
		copy.set_meta("planning_zone", node.get_meta("planning_zone"))
	if copy.has_method("configure_flicker"):
		copy.set("energy_multiplier", node.get("energy_multiplier"))
		copy.call("set_authored_color", node.call("get_authored_color"))
		copy.set_meta("planning_light_energy", node.get_meta("planning_light_energy", 3.0))
		copy.set_meta("planning_light_angle", node.get_meta("planning_light_angle", 48.0))
		copy.set_meta("planning_flicker_mode", node.get_meta("planning_flicker_mode", 0))
		copy.set_meta("planning_flicker_step", node.get_meta("planning_flicker_step", 0.2))
	# An instanced scene restores its own children on load; owning them
	# here too saved a second copy of every wall and pane on each bake.
	if copy.scene_file_path.is_empty() and not scene_path.begins_with(catalog.ENVIRONMENT_ROOT + "/"):
		_assign_owner_recursive(copy, scene_root)

func _assign_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_assign_owner_recursive(child, scene_owner)
