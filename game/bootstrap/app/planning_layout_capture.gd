extends RefCounted
## One DTO projection for synchronous persistence and staged named-map snapshots.
const DOOR_OPTIONS := preload("res://game/bootstrap/app/planning_door_options.gd")
const WAVE_DIRECTOR := preload("res://game/features/spawning/public/wave_director.gd")


static func collect(objects: Node, nodes: Array, include_player: bool = true) -> Dictionary:
	var records: Array = []
	if include_player and objects.player_spawn_defined:
		records.append({
			"scene":"res://game/features/player/public/player.tscn",
			"x":objects.player_spawn_transform.origin.x, "y":objects.player_spawn_transform.origin.y, "z":objects.player_spawn_transform.origin.z,
			"rotation_y":objects.player_spawn_transform.basis.get_euler().y * 180.0 / PI,
			"scale_x":1.0, "scale_y":1.0, "scale_z":1.0
		})
	for node in nodes:
		if not is_instance_valid(node):
			continue
		# The player is saved once, as its spawn point above, not where it stands.
		if str(node.get_meta("planning_actor_kind", "")) == "player":
			continue
		var scene_path = str(node.get_meta("planning_scene_path", ""))
		if scene_path.is_empty():
			continue
		var save_position = node.position
		if str(node.get_meta("planning_actor_kind", "")) == "enemy":
			node.set_meta("planning_spawn_transform", node.transform)
		records.append({
			"scene": scene_path,
			"object_id": str(node.get_meta("planning_object_id", "")),
			"desk_id": node.get_meta("planning_desk_id", ""),
			"attachment": node.get_meta("planning_attachment", ""),
			"zone": node.get_meta("planning_zone", -1),
			"x": save_position.x, "y": save_position.y, "z": save_position.z,
			"rotation_y": node.rotation_degrees.y,
			"rotation_x": node.rotation_degrees.x, "rotation_z": node.rotation_degrees.z,
			"scale_x": node.scale.x, "scale_y": node.scale.y, "scale_z": node.scale.z,
			"light_energy": node.get_meta("planning_light_energy", 0.0),
			"light_angle": node.get_meta("planning_light_angle", 48.0),
			"flicker_mode": node.get_meta("planning_flicker_mode", 0),
			"flicker_step": node.get_meta("planning_flicker_step", 0.2),
			"darkness": node.get("darkness") if node.get("darkness") != null else 0.0,
			"permanent_darkness": node.get("permanent") if node.get("permanent") != null else false,
			"spawn_x": (node.get_meta("planning_spawn_transform") as Transform3D).origin.x if node.has_meta("planning_spawn_transform") else node.position.x,
			"spawn_y": (node.get_meta("planning_spawn_transform") as Transform3D).origin.y if node.has_meta("planning_spawn_transform") else node.position.y,
			"spawn_z": (node.get_meta("planning_spawn_transform") as Transform3D).origin.z if node.has_meta("planning_spawn_transform") else node.position.z
		})
		if node.has_meta("planning_settled_transform") and node.get_meta("planning_settled_transform") == node.transform:
			records[-1]["settled_physics"] = {"version": 1}
		if node.has_meta("planning_auto_fixture"):
			records[-1]["auto_fixture"] = str(node.get_meta("planning_auto_fixture"))
		if node.has_method("get_decor_pose"):
			records[-1]["decor_pose"] = node.call("get_decor_pose")
		if node.has_method("has_display") and node.call("has_display"):
			records[-1]["display"] = node.call("get_display_config")
		if node.has_method("get_loot_config") and node.has_meta(&"planning_loot"):
			records[-1]["loot"] = node.call("get_loot_config")
		var door := DOOR_OPTIONS.lockable_controller(node)
		if door != null:
			records[-1]["door_lock"] = str(door.call("get_lock_state"))
		if node.has_method("get_enemy_stats") and node.has_meta(&"planning_enemy_stats"):
			records[-1]["enemy_stats"] = node.call("get_enemy_stats")
		if node.has_method("get_spawn_config"):
			records[-1]["spawn_point"] = node.call("get_spawn_config")
		if node.has_meta(WAVE_DIRECTOR.TRIGGER_META):
			records[-1]["spawn_triggers"] = node.get_meta(WAVE_DIRECTOR.TRIGGER_META)
		if node.has_method("get_fixture_config"):
			var fixture: Dictionary = node.call("get_fixture_config")
			records[-1]["fixture_shape"] = str(fixture["shape"])
			records[-1]["fixture_visible_in_game"] = bool(fixture["visible_in_game"])
		if node.has_method("get_blood_config"):
			var blood: Dictionary = node.call("get_blood_config")
			records[-1]["blood_texture"] = str(blood["texture"])
			records[-1]["blood_surface"] = str(blood["surface"])
			records[-1]["blood_normal"] = blood["normal"]
			records[-1]["blood_attachment"] = node.call("get_blood_attachment")
		if node.has_method("get_authored_energy"):
			records[-1]["energy_multiplier"] = float(node.get("energy_multiplier"))
			var color: Color = node.call("get_authored_color")
			records[-1]["light_color"] = [color.r, color.g, color.b]
	return {"version": 8, "objects": records}



static func collect_async(objects: Node, tree: SceneTree, progress: Callable, alive: Callable) -> Dictionary:
	var data := collect(objects, [])
	for index in range(0, objects.placed.size(), 16):
		var batch: Array = objects.placed.slice(index, index + 16)
		data.objects.append_array(collect(objects, batch, false).objects)
		progress.call(0.95 + 0.025 * float(index + batch.size()) / objects.placed.size(), "snapshot")
		await tree.process_frame
		if not alive.call():
			return {"error": "loading cancelled"}
	return {"data": data}
