extends RefCounted

const LIMIT := 32

var planner: Variant
var stack: Array[Dictionary] = []


func record_transform(node: Node3D) -> void:
	_record({"kind": "transform", "node": weakref(node), "transform": node.transform, "scale": node.scale,
		"light_color": node.call("get_authored_color") if node.has_method("get_authored_color") else null,
		"light_energy": node.get_meta("planning_light_energy", -1.0), "light_angle": node.get_meta("planning_light_angle", -1.0)})


func record_player_spawn() -> void:
	_record({"kind": "player", "defined": planner.player_spawn_defined,
		"transform": planner.player_spawn_transform, "position": planner.main_player.transform})


func record_added(node: Node3D) -> void:
	_record({"kind": "added", "node": weakref(node)})


func record_deleted(node: Node3D) -> void:
	var records: Array[Dictionary] = [_capture(node)]
	var desk_id := str(node.get_meta("planning_desk_id", ""))
	if not desk_id.is_empty():
		for other in planner.placed:
			if is_instance_valid(other) and str(other.get_meta("planning_attachment", "")) == desk_id:
				records.append(_capture(other))
	_record({"kind": "deleted", "records": records})


func duplicate_selected() -> void:
	var source: Node3D = planner.selected
	if source == null or source == planner.main_player:
		return
	var copy := _restore(_capture(source), Vector3(0.5, 0, 0.5), true)
	if copy == null:
		return
	var old_id := str(source.get_meta("planning_desk_id", ""))
	if not old_id.is_empty():
		var new_id := str(copy.get_meta("planning_desk_id"))
		for other in planner.placed.duplicate():
			if other != copy and is_instance_valid(other) and str(other.get_meta("planning_attachment", "")) == old_id:
				var record := _capture(other)
				record["attachment"] = new_id
				_restore(record, Vector3(0.5, 0, 0.5), false)
	record_added(copy)
	planner._select(copy)


func undo() -> void:
	if stack.is_empty():
		return
	var action: Dictionary = stack.pop_back()
	match str(action["kind"]):
		"added":
			var node := (action["node"] as WeakRef).get_ref() as Node3D
			if is_instance_valid(node):
				planner._delete_node(node)
		"deleted":
			for record in action["records"]:
				_restore(record, Vector3.ZERO, false)
		"transform":
			var node := (action["node"] as WeakRef).get_ref() as Node3D
			if is_instance_valid(node):
				node.transform = action["transform"]
				node.scale = action["scale"]
				if action.get("light_color") is Color:
					node.call("set_authored_color", action["light_color"])
				if float(action["light_energy"]) >= 0.0:
					if node.has_method("set_authored_energy"):
						node.call("set_authored_energy", float(action["light_energy"]))
				if float(action["light_angle"]) >= 0.0:
					var spot := node.find_child("Light", true, false) as SpotLight3D
					if spot != null:
						spot.spot_angle = float(action["light_angle"])
						node.set_meta("planning_light_angle", spot.spot_angle)
				planner._sync_workstations()
		"player":
			planner.player_spawn_defined = bool(action["defined"])
			planner.player_spawn_transform = action["transform"]
			planner.main_player.transform = action["position"]
	planner._update_history_buttons()
	planner.controls._update_light_ui()
	planner.status.text = "Last action undone"


func _record(action: Dictionary) -> void:
	stack.append(action)
	if stack.size() > LIMIT:
		stack.pop_front()
	planner._update_history_buttons()


func _capture(node: Node3D) -> Dictionary:
	return {"path": str(node.get_meta("planning_scene_path", "")), "transform": node.transform,
		"scale": node.scale, "parent": node.get_parent(), "kind": str(node.get_meta("planning_actor_kind", "")),
		"desk_id": str(node.get_meta("planning_desk_id", "")), "attachment": str(node.get_meta("planning_attachment", "")),
		"zone": int(node.get_meta("planning_zone", -1)), "light_energy": float(node.get_meta("planning_light_energy", -1.0)),
		"light_color": node.call("get_authored_color") if node.has_method("get_authored_color") else null,
		"energy_multiplier": float(node.get("energy_multiplier")) if node.has_method("get_authored_energy") else 0.65,
		"light_angle": float(node.get_meta("planning_light_angle", -1.0)),
		"flicker_mode": int(node.get_meta("planning_flicker_mode", 0)), "flicker_step": float(node.get_meta("planning_flicker_step", 0.2))}


func _restore(record: Dictionary, offset: Vector3, new_desk: bool) -> Node3D:
	var path := str(record["path"])
	if path.is_empty():
		return null
	var node := planner._instantiate_asset(path) as Node3D
	if node == null:
		return null
	var parent := record["parent"] as Node3D
	if not is_instance_valid(parent):
		parent = planner.root
	parent.add_child(node)
	node.transform = record["transform"]
	node.position += offset
	node.scale = record["scale"]
	node.set_meta("planning_scene_path", path)
	if not str(record["kind"]).is_empty():
		node.set_meta("planning_actor_kind", record["kind"])
	if not str(record["desk_id"]).is_empty():
		var desk_id := str(Time.get_ticks_usec()) if new_desk else str(record["desk_id"])
		node.set_meta("planning_desk_id", desk_id)
		planner.workstation_transforms[desk_id] = node.global_transform
	if not str(record["attachment"]).is_empty():
		node.set_meta("planning_attachment", record["attachment"])
	if int(record["zone"]) >= 0:
		node.set_meta("planning_zone", record["zone"])
	if float(record["light_energy"]) >= 0.0:
		if node.has_method("set_authored_energy"):
			node.set("energy_multiplier", float(record.get("energy_multiplier", 0.65)))
			node.call("set_authored_energy", float(record["light_energy"]))
	if record.get("light_color") is Color:
		node.call("set_authored_color", record["light_color"])
	if float(record["light_angle"]) >= 0.0:
		var spot := node.find_child("Light", true, false) as SpotLight3D
		if spot != null:
			spot.spot_angle = float(record["light_angle"])
			node.set_meta("planning_light_angle", spot.spot_angle)
	if node.has_method("configure_flicker"):
		node.call("configure_flicker", int(record["flicker_mode"]), float(record["flicker_step"]))
	if node.has_method("set_target") and str(record["kind"]) == "enemy":
		node.call("set_target", planner.main_player)
	planner.placed.append(node)
	return node
