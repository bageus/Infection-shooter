extends RefCounted

const ENVIRONMENT_ROOT = "res://models/objects/enviroments"
const ENVIRONMENT_SCENE = preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BATHROOM_FIXTURE_SCENE = preload("res://game/presentation/office_floor/public/props/bathroom_fixture.tscn")
const PAPER_PROP_SCENE = preload("res://game/presentation/office_floor/public/props/paper_prop.tscn")
const STAIRCASE_SCENE = preload("res://game/presentation/office_floor/public/structural/staircase.tscn")
const WORKSTATIONS = preload("res://game/bootstrap/app/workstation_templates.gd")
const BLOOD_DECAL_SCENE := "res://game/presentation/office_floor/public/props/blood_decal.tscn"
# Texture ids of the in-game blood set ("<category>_<variant>"), see planner_decor_v1.
const BLOOD_CATEGORIES := ["splatter", "stain", "smear", "pool", "drops"]
const BLOOD_VARIANTS := 9

var bind_asset: Callable
var active_catalog: Array = []
var group_catalogs: Dictionary = {}
var lighting_catalog = [
	{"name":"Точечный светильник","path":"res://game/presentation/office_floor/public/props/planner_light.tscn","kind":"light","fixture_shape":"point"},
	{"name":"Длинный узкий светильник","path":"res://game/presentation/office_floor/public/props/planner_light.tscn","kind":"light","fixture_shape":"linear"},
	{"name":"Прямоугольный светильник","path":"res://game/presentation/office_floor/public/props/planner_light.tscn","kind":"light","fixture_shape":"rectangle"},
	{"name":"Permanent Darkness","path":"res://game/presentation/office_floor/public/props/darkness_zone.tscn","kind":"darkness"},
	{"name":"Exploration Darkness","path":"res://game/presentation/office_floor/public/props/darkness_zone.tscn","kind":"exploration_darkness"}
]
# Enemy paths accepted by map loading; includes the retired mutant alias.
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
	{"name":"Hunger","path":ENEMY_SCENES[2],"kind":"enemy"},
	{"name":"Revenant","path":ENEMY_SCENES[3],"kind":"enemy"},
	{"name":"Brute","path":ENEMY_SCENES[4],"kind":"enemy"},
	{"name":"Titan","path":ENEMY_SCENES[5],"kind":"enemy"},
	{"name":"Colossus","path":ENEMY_SCENES[6],"kind":"enemy"},
	{"name":"Horde","path":ENEMY_SCENES[7],"kind":"enemy"}
]


# Dead infected and loose body parts placed as decoration (ADR-0017).
var gore_catalog = [
	{"name":"Corpse Zombie","path":"res://game/features/infected/public/decor/corpse_zombie.tscn","kind":"decor"},
	{"name":"Corpse Zombie mutilated","path":"res://game/features/infected/public/decor/corpse_zombie_mutilated.tscn","kind":"decor"},
	{"name":"Head Zombie","path":"res://game/features/infected/public/decor/part_zombie_head.tscn","kind":"decor"},
	{"name":"Arm Zombie","path":"res://game/features/infected/public/decor/part_zombie_arm.tscn","kind":"decor"},
	{"name":"Leg Zombie","path":"res://game/features/infected/public/decor/part_zombie_leg.tscn","kind":"decor"},
	{"name":"Corpse Hunger","path":"res://game/features/infected/public/decor/corpse_hunger.tscn","kind":"decor"},
	{"name":"Corpse Hunger mutilated","path":"res://game/features/infected/public/decor/corpse_hunger_mutilated.tscn","kind":"decor"},
	{"name":"Head Hunger","path":"res://game/features/infected/public/decor/part_hunger_head.tscn","kind":"decor"},
	{"name":"Arm Hunger","path":"res://game/features/infected/public/decor/part_hunger_arm.tscn","kind":"decor"},
	{"name":"Leg Hunger","path":"res://game/features/infected/public/decor/part_hunger_leg.tscn","kind":"decor"},
	{"name":"Corpse Revenant","path":"res://game/features/infected/public/decor/corpse_revenant.tscn","kind":"decor"},
	{"name":"Corpse Revenant mutilated","path":"res://game/features/infected/public/decor/corpse_revenant_mutilated.tscn","kind":"decor"},
	{"name":"Head Revenant","path":"res://game/features/infected/public/decor/part_revenant_head.tscn","kind":"decor"},
	{"name":"Arm Revenant","path":"res://game/features/infected/public/decor/part_revenant_arm.tscn","kind":"decor"},
	{"name":"Leg Revenant","path":"res://game/features/infected/public/decor/part_revenant_leg.tscn","kind":"decor"},
	{"name":"Corpse Brute","path":"res://game/features/infected/public/decor/corpse_brute.tscn","kind":"decor"},
	{"name":"Corpse Brute mutilated","path":"res://game/features/infected/public/decor/corpse_brute_mutilated.tscn","kind":"decor"},
	{"name":"Head Brute","path":"res://game/features/infected/public/decor/part_brute_head.tscn","kind":"decor"},
	{"name":"Arm Brute","path":"res://game/features/infected/public/decor/part_brute_arm.tscn","kind":"decor"},
	{"name":"Leg Brute","path":"res://game/features/infected/public/decor/part_brute_leg.tscn","kind":"decor"},
	{"name":"Corpse Titan","path":"res://game/features/infected/public/decor/corpse_titan.tscn","kind":"decor"},
	{"name":"Corpse Titan mutilated","path":"res://game/features/infected/public/decor/corpse_titan_mutilated.tscn","kind":"decor"},
	{"name":"Head Titan","path":"res://game/features/infected/public/decor/part_titan_head.tscn","kind":"decor"},
	{"name":"Arm Titan","path":"res://game/features/infected/public/decor/part_titan_arm.tscn","kind":"decor"},
	{"name":"Leg Titan","path":"res://game/features/infected/public/decor/part_titan_leg.tscn","kind":"decor"},
	{"name":"Corpse Colossus","path":"res://game/features/infected/public/decor/corpse_colossus.tscn","kind":"decor"},
	{"name":"Corpse Colossus mutilated","path":"res://game/features/infected/public/decor/corpse_colossus_mutilated.tscn","kind":"decor"},
	{"name":"Head Colossus","path":"res://game/features/infected/public/decor/part_colossus_head.tscn","kind":"decor"},
	{"name":"Arm Colossus","path":"res://game/features/infected/public/decor/part_colossus_arm.tscn","kind":"decor"},
	{"name":"Leg Colossus","path":"res://game/features/infected/public/decor/part_colossus_leg.tscn","kind":"decor"},
	{"name":"Corpse Horde","path":"res://game/features/infected/public/decor/corpse_horde.tscn","kind":"decor"},
	{"name":"Corpse Horde mutilated","path":"res://game/features/infected/public/decor/corpse_horde_mutilated.tscn","kind":"decor"},
	{"name":"Tentacle Horde","path":"res://game/features/infected/public/decor/part_horde_tentacle.tscn","kind":"decor"}
]


# Blood decals from the in-game texture set; surface and size come from the
# planner's blood options.
func blood_catalog() -> Array:
	var entries: Array = []
	for category: String in BLOOD_CATEGORIES:
		for variant in range(1, BLOOD_VARIANTS + 1):
			var texture_id := "%s_%02d" % [category, variant]
			entries.append({"name": "Blood " + texture_id.replace("_", " "), "path": BLOOD_DECAL_SCENE, "kind": "blood", "blood_texture": texture_id})
	return entries


func _build_environment_catalogs() -> void:
	group_catalogs.clear()
	for group_index in range(1, 13): # model groups 01-12
		var group = "%02d" % group_index
		var directory = ENVIRONMENT_ROOT + "/" + group
		var entries: Array = []
		group_catalogs[group] = entries
		# ResourceLoader also lists models in exported builds, where the source
		# .glb files are replaced by their imported resources.
		for file_name: String in ResourceLoader.list_directory(directory):
			if file_name.to_lower().ends_with(".glb"):
				var model_path = directory + "/" + file_name
				var special_scene = _environment_scene_for(file_name)
				entries.append({
					"name": _environment_display_name(file_name),
					"path": special_scene if not special_scene.is_empty() else model_path,
					"kind": "" if not special_scene.is_empty() else "environment"
				})
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
	# The retired group 16 bathroom set was replaced by improved models.
	var bathroom := {
		"16_toilet_floor.glb": ENVIRONMENT_ROOT + "/02/02_toilet_new.glb",
		"16_wall_urinal.glb": ENVIRONMENT_ROOT + "/02/02_wall_urinal_improved.glb",
		"16_wall_hand_dryer.glb": ENVIRONMENT_ROOT + "/05/05_wall_hand_dryer_improved.glb",
		"16_sink_pedestal.glb": ENVIRONMENT_ROOT + "/02/02_sink_pedestal_improved.glb",
	}
	if bathroom.has(old_path.get_file()):
		return str(bathroom[old_path.get_file()])
	if old_path.begins_with("res://models/objects/Office_Set/"):
		return ""
	var legacy_prop = "res://game/presentation/office_floor/public/props/"
	if old_path.begins_with(legacy_prop) and old_path.ends_with(".tscn"):
		if old_path.get_file() in ["planner_light.tscn", "darkness_zone.tscn", "environment_prop.tscn", "blood_decal.tscn"]:
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

