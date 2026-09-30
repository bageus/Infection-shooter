extends RefCounted

# Build the asset catalog and route palette choices.
var planner: Variant


func _init(context: Node) -> void:
	planner = context


func _build_environment_catalogs() -> void:
	planner.group_catalogs.clear()
	for group_index in range(1, 14):
		var group = "%02d" % group_index
		var directory = planner.ENVIRONMENT_ROOT + "/" + group
		var entries: Array = []
		planner.group_catalogs[group] = entries
		var handle = DirAccess.open(directory)
		if handle == null:
			continue
		handle.list_dir_begin()
		var file_name = handle.get_next()
		while not file_name.is_empty():
			if not handle.current_is_dir() and file_name.to_lower().ends_with(".glb") and file_name not in ["16_toilet_floor.glb", "16_wall_urinal.glb", "16_wall_hand_dryer.glb", "16_sink_pedestal.glb"]:
				var model_path = directory + "/" + file_name
				var special_scene = _environment_scene_for(file_name)
				entries.append({
					"name": _environment_display_name(file_name),
					"path": special_scene if not special_scene.is_empty() else model_path,
					"kind": "" if not special_scene.is_empty() else "environment"
				})
			file_name = handle.get_next()
		handle.list_dir_end()
		entries.sort_custom(func(a, b): return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
		planner.group_catalogs[group] = entries


func _environment_display_name(file_name: String) -> String:
	if file_name.begins_with("01_floor_") and file_name != "01_floor_pad.glb":
		return "Carpet " + file_name.trim_prefix("01_floor_").get_basename().replace("_", " ")
	return file_name.get_basename().replace("_", " ")


func _environment_scene_for(file_name: String) -> String:
	var structural = {
		"01_column.glb": "column", "01_elevator_cabin_freight.glb": "elevator_cabin_freight",
		"01_elevator_cabin_passenger.glb": "elevator_cabin_passenger", "01_elevator_door.glb": "elevator_door",
		"01_floor_pad.glb": "floor_pad", "01_wall_door.glb": "wall_door",
		"01_wall_door_without.glb": "wall_door_2_without", "01_wall_emergency_door.glb": "wall_emergency_door",
		"01_wall_half_panel.glb": "wall_half_panel", "01_wall_straight.glb": "wall_straight",
		"01_window_double.glb": "window_double", "01_only_door.glb": "only_door_2",
		"01_glass_door_breakable.glb": "sliding_glass_door",
		"01_glass_partition_blinds_breakable.glb": "glass_partition_blinds",
		"01_glass_partition_half_breakable.glb": "glass_partition_half",
		"01_glass_wall_full_breakable.glb": "glass_wall_full"
	}
	if structural.has(file_name):
		return "res://game/presentation/office_floor/public/structural/" + str(structural[file_name]) + ".tscn"
	if file_name == "07_table.glb":
		return "res://game/presentation/office_floor/public/props/07_table.tscn"
	var pickups = {
		"12_ammo_pistols.glb": "ammo_pistol_pickup", "12_ammo_shotgun.glb": "ammo_shotgun_pickup",
		"12_ammo_uzi.glb": "ammo_uzi_pickup", "12_antidote.glb": "antidote_pickup",
		"12_medkit.glb": "medkit_pickup"
	}
	if pickups.has(file_name):
		return "res://game/features/pickups/public/" + str(pickups[file_name]) + ".tscn"
	return ""


func _rebuild_palette() -> void:
	planner.palette.clear()
	for entry: Dictionary in planner.active_catalog:
		planner.palette.add_item(str(entry.get("name", "")))


func _show_structure_catalog() -> void:
	planner.light_defaults.hide()
	planner.view._reset_selection()
	planner.active_catalog = planner.group_catalogs["01"]
	planner.ui.get_node("Panel/VBox/GroupTabs").show()
	_rebuild_palette()
	planner.status.text = "STRUCTURE | choose building object"


func _show_structure_group(group_name: String) -> void:
	planner.light_defaults.hide()
	planner.view._reset_selection()
	planner.active_catalog = planner.group_catalogs.get(group_name, [])
	_rebuild_palette()
	planner.status.text = "STRUCTURE " + group_name


func _show_lighting_catalog() -> void:
	planner.view._reset_selection()
	planner.light_defaults.show()
	planner.ui.get_node("Panel/VBox/GroupTabs").hide()
	planner.active_catalog = planner.lighting_catalog
	_rebuild_palette()
	planner.status.text = "LIGHTING | lights and darkness zones"


func _show_actor_catalog() -> void:
	planner.light_defaults.hide()
	planner.view._reset_selection()
	planner.ui.get_node("Panel/VBox/GroupTabs").hide()
	planner.active_catalog = planner.actor_catalog
	_rebuild_palette()
	planner.status.text = "ACTORS | place/remove Player and Infected"


func _on_palette_selected(index: int) -> void:
	var entry: Dictionary = planner.active_catalog[index]
	planner.selected_path = str(entry.get("path", ""))
	planner.selected_kind = str(entry.get("kind", ""))
	planner.rotation_y = 0.0
	planner.view._select(null)
	planner.objects._rebuild_preview()


func _instantiate_asset(asset_path: String) -> Node3D:
	if asset_path.begins_with(planner.ENVIRONMENT_ROOT + "/") and asset_path.ends_with(".glb"):
		if asset_path.get_file().begins_with("09_") and planner.WORKSTATIONS.VARIANTS["paper"].has(asset_path.get_file().get_basename()):
			var paper = planner.PAPER_PROP_SCENE.instantiate() as Node3D
			paper.set("model_path", asset_path)
			return paper
		if asset_path.get_file() in ["02_toilet_new.glb", "02_wall_urinal_improved.glb", "05_wall_hand_dryer_improved.glb", "02_sink_pedestal_improved.glb", "16_toilet_floor.glb", "16_wall_urinal.glb", "16_wall_hand_dryer.glb", "16_sink_pedestal.glb"]:
			var fixture = planner.BATHROOM_FIXTURE_SCENE.instantiate() as Node3D
			fixture.set("model_path", asset_path)
			return fixture
		if asset_path.get_file() in ["01_stairs.glb", "01_stairs_2.glb"]:
			var staircase = planner.STAIRCASE_SCENE.instantiate() as Node3D
			staircase.set("model_path", asset_path)
			return staircase
		var environment = planner.ENVIRONMENT_SCENE.instantiate() as Node3D
		environment.set("model_path", asset_path)
		return environment
	var packed = load(asset_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D
