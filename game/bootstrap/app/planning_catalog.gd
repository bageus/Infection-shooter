extends RefCounted

const ENVIRONMENT_ROOT = "res://models/objects/enviroments"
const ENVIRONMENT_SCENE = preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BATHROOM_FIXTURE_SCENE = preload("res://game/presentation/office_floor/public/props/bathroom_fixture.tscn")
const PAPER_PROP_SCENE = preload("res://game/presentation/office_floor/public/props/paper_prop.tscn")
const STAIRCASE_SCENE = preload("res://game/presentation/office_floor/public/structural/staircase.tscn")
const WORKSTATIONS = preload("res://game/bootstrap/app/workstation_templates.gd")

var bind_asset: Callable
var active_catalog: Array = []
var group_catalogs: Dictionary = {}
var lighting_catalog = [
	{"name":"Omni Light","path":"res://game/presentation/office_floor/public/props/planner_light.tscn","kind":"light"},
	{"name":"Permanent Darkness","path":"res://game/presentation/office_floor/public/props/darkness_zone.tscn","kind":"darkness"},
	{"name":"Exploration Darkness","path":"res://game/presentation/office_floor/public/props/darkness_zone.tscn","kind":"exploration_darkness"}
]
# Scenes that are loaded and saved as enemies; keep in sync with actor_catalog.
const ENEMY_SCENES := [
	"res://game/features/infected/public/infected_capsule.tscn",
	"res://game/features/infected/public/mutant_level2.tscn",
	"res://game/features/infected/public/infected_hunger.tscn",
	"res://game/features/infected/public/infected_revenant.tscn",
	"res://game/features/infected/public/infected_brute.tscn",
	"res://game/features/infected/public/infected_titan.tscn",
	"res://game/features/infected/public/infected_colossus.tscn",
	"res://game/features/infected/public/infected_horde.tscn"
]
var actor_catalog = [
	{"name":"Player Spawn","path":"","kind":"player"},
	{"name":"Zombie L1","path":ENEMY_SCENES[0],"kind":"enemy"},
	{"name":"Mutant L2","path":ENEMY_SCENES[1],"kind":"enemy"},
	{"name":"Hunger","path":ENEMY_SCENES[2],"kind":"enemy"},
	{"name":"Revenant","path":ENEMY_SCENES[3],"kind":"enemy"},
	{"name":"Brute","path":ENEMY_SCENES[4],"kind":"enemy"},
	{"name":"Titan","path":ENEMY_SCENES[5],"kind":"enemy"},
	{"name":"Colossus","path":ENEMY_SCENES[6],"kind":"enemy"},
	{"name":"Horde","path":ENEMY_SCENES[7],"kind":"enemy"}
]


func _build_environment_catalogs() -> void:
	group_catalogs.clear()
	for group_index in range(1, 14):
		var group = "%02d" % group_index
		var directory = ENVIRONMENT_ROOT + "/" + group
		var entries: Array = []
		group_catalogs[group] = entries
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
		group_catalogs[group] = entries


func _environment_display_name(file_name: String) -> String:
	if file_name.begins_with("01_floor_") and file_name != "01_floor_pad.glb":
		return "Carpet " + file_name.trim_prefix("01_floor_").get_basename().replace("_", " ")
	return file_name.get_basename().replace("_", " ")


func _environment_scene_for(file_name: String) -> String:
	var structural = {
		"01_column.glb": "res://game/presentation/office_floor/public/structural/column.tscn", "01_elevator_cabin_freight.glb": "res://game/presentation/office_floor/public/structural/elevator_cabin_freight.tscn",
		"01_elevator_cabin_passenger.glb": "res://game/presentation/office_floor/public/structural/elevator_cabin_passenger.tscn", "01_elevator_door.glb": "res://game/presentation/office_floor/public/structural/elevator_door.tscn",
		"01_floor_pad.glb": "res://game/presentation/office_floor/public/structural/floor_pad.tscn", "01_wall_door.glb": "res://game/presentation/office_floor/public/structural/wall_door.tscn",
		"01_wall_door_without.glb": "res://game/presentation/office_floor/public/structural/wall_door_2_without.tscn", "01_wall_emergency_door.glb": "res://game/presentation/office_floor/public/structural/wall_emergency_door.tscn",
		"01_wall_half_panel.glb": "res://game/presentation/office_floor/public/structural/wall_half_panel.tscn", "01_wall_straight.glb": "res://game/presentation/office_floor/public/structural/wall_straight.tscn",
		"01_window_double.glb": "res://game/presentation/office_floor/public/structural/window_double.tscn", "01_only_door.glb": "res://game/presentation/office_floor/public/structural/only_door_2.tscn",
		"01_glass_door_breakable.glb": "res://game/presentation/office_floor/public/structural/sliding_glass_door.tscn",
		"01_glass_partition_blinds_breakable.glb": "res://game/presentation/office_floor/public/structural/glass_partition_blinds.tscn",
		"01_glass_partition_half_breakable.glb": "res://game/presentation/office_floor/public/structural/glass_partition_half.tscn",
		"01_glass_wall_full_breakable.glb": "res://game/presentation/office_floor/public/structural/glass_wall_full.tscn"
	}
	if structural.has(file_name):
		return str(structural[file_name])
	if file_name == "07_table.glb":
		return "res://game/presentation/office_floor/public/props/07_table.tscn"
	var pickups = {
		"12_ammo_pistols.glb": "res://game/features/pickups/public/ammo_pistol_pickup.tscn", "12_ammo_shotgun.glb": "res://game/features/pickups/public/ammo_shotgun_pickup.tscn",
		"12_ammo_uzi.glb": "res://game/features/pickups/public/ammo_uzi_pickup.tscn", "12_antidote.glb": "res://game/features/pickups/public/antidote_pickup.tscn",
		"12_medkit.glb": "res://game/features/pickups/public/medkit_pickup.tscn"
	}
	if pickups.has(file_name):
		return str(pickups[file_name])
	return ""







func _instantiate_asset(asset_path: String) -> Node3D:
	var node := _create_asset(asset_path)
	if node != null and bind_asset.is_valid():
		bind_asset.call(node)
	return node


func _create_asset(asset_path: String) -> Node3D:
	if asset_path.begins_with(ENVIRONMENT_ROOT + "/") and asset_path.ends_with(".glb"):
		if asset_path.get_file().begins_with("09_") and WORKSTATIONS.VARIANTS["paper"].has(asset_path.get_file().get_basename()):
			var paper = PAPER_PROP_SCENE.instantiate() as Node3D
			paper.set("model_path", asset_path)
			return paper
		if asset_path.get_file() in ["02_toilet_new.glb", "02_wall_urinal_improved.glb", "05_wall_hand_dryer_improved.glb", "02_sink_pedestal_improved.glb", "16_toilet_floor.glb", "16_wall_urinal.glb", "16_wall_hand_dryer.glb", "16_sink_pedestal.glb"]:
			var fixture = BATHROOM_FIXTURE_SCENE.instantiate() as Node3D
			fixture.set("model_path", asset_path)
			return fixture
		if asset_path.get_file() in ["01_stairs.glb", "01_stairs_2.glb"]:
			var staircase = STAIRCASE_SCENE.instantiate() as Node3D
			staircase.set("model_path", asset_path)
			return staircase
		var environment = ENVIRONMENT_SCENE.instantiate() as Node3D
		environment.set("model_path", asset_path)
		return environment
	var packed = load(asset_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


func _migrate_scene_path(old_path: String) -> String:
	var replacements = {
		"res://models/objects/01_wall_door.glb": "res://game/presentation/office_floor/public/structural/wall_door.tscn",
		"res://models/objects/01_wall_door_2.glb": "res://game/presentation/office_floor/public/structural/wall_door.tscn",
		"res://models/objects/01_wall_inner_corner.blend": "",
		"res://game/presentation/office_floor/public/structural/wall_inner_corner.tscn": ""
	}
	if replacements.has(old_path):
		return str(replacements[old_path])
	if old_path.begins_with("res://models/objects/Office_Set/"):
		return ""
	var legacy_prop = "res://game/presentation/office_floor/public/props/"
	if old_path.begins_with(legacy_prop) and old_path.ends_with(".tscn"):
		if old_path.get_file() in ["planner_light.tscn", "darkness_zone.tscn", "environment_prop.tscn"]:
			return old_path
		if old_path.get_file() == "07_table.tscn":
			return old_path
		var legacy_name = old_path.get_file().get_basename().substr(3).to_lower()
		for group in group_catalogs.values():
			for entry: Dictionary in group:
				if str(entry["name"]).substr(3).replace(" ", "_").to_lower() == legacy_name:
					return str(entry["path"])
		return ""
	return old_path
