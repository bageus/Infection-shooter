extends SceneTree
## Real moving leaves retain placed, restored and runtime blood in both render paths.
const IMPACTS := preload("res://game/features/combat/public/impact_effects.gd")
const EFFECTS := preload("res://game/presentation/office_floor/public/blood_effects_3d.tscn")
const BLOOD := preload("res://game/presentation/office_floor/public/props/blood_decal.tscn")
const PLACEMENT := preload("res://game/bootstrap/app/planning_blood_placement.gd")
const STRUCTURAL := "res://game/presentation/office_floor/public/structural/"
class Host extends Node:
	var impact_pool: Node
var failures := 0
var stage: Node3D
var impacts: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	impacts = IMPACTS.new()
	stage.add_child(impacts)
	camera = Camera3D.new()
	stage.add_child(camera)
	for file in ["wall_door.tscn", "wall_door_3.tscn", "wall_emergency_door.tscn", "elevator_door.tscn", "sliding_glass_door.tscn"]:
		for side in [-1.0, 1.0]:
			await _door(file, side)
	stage.queue_free()
	await process_frame
	await process_frame
	print("Door blood attachment tests: %d failures" % failures)
	quit(1 if failures else 0)

func _door(file: String, side: float) -> void:
	var door := load(STRUCTURAL + file).instantiate() as Node3D
	door.set_meta("planning_scene_path", STRUCTURAL + file)
	door.set_meta("planning_object_id", "door")
	# Both orders occur in scene composition: configure before and after _ready.
	if file == "wall_door.tscn":
		door.call("configure_world", stage, impacts)
	stage.add_child(door)
	door.position = Vector3(5, .2, 7)
	door.rotation.y = .63
	door.scale = Vector3.ONE * 1.2
	door.call("configure_world", stage, impacts)
	var controller := door.get_node("DoorController")
	controller.set_physics_process(false)
	await _settle()
	var leaf := _leaf(door)
	if leaf == null:
		var parts: Array = controller.get("_door_parts")
		if not parts.is_empty():
			leaf = _first_mesh(parts[0])
	_expect(leaf != null, file + ": fixture has a moving leaf")
	if leaf == null:
		door.queue_free()
		return
	var center := leaf.global_transform * leaf.get_aabb().get_center()
	var normal := door.global_basis.z.normalized() * side
	var placed := await _place(door, leaf, center, normal)
	var restored := await _restore(placed, leaf)
	var marks: Array[Node3D] = [placed]
	marks.append_array(restored)
	var runtimes: Array[Node3D] = []
	for decal in [false, true]:
		var effects := await _runtime(door, leaf, center, normal, decal)
		runtimes.append(effects)
		for mark: Node3D in effects.get("_budget").get("container").get_children():
			var surface: Node = mark.get("surface_ref").get_ref()
			if impacts.call("resolve_surface", surface, mark.global_position, -normal).get("anchor") == leaf:
				marks.append(mark)
	_expect(marks.size() > 1 + restored.size(), file + ": runtime blood reaches the actual leaf")
	await _check_motion(controller, leaf, marks, file)
	for mark in [placed] + restored:
		mark.queue_free()
	for effects in runtimes:
		effects.queue_free()
	door.queue_free()
	await _settle()

func _place(door: Node3D, leaf: MeshInstance3D, center: Vector3, normal: Vector3) -> Node3D:
	camera.global_position = center + normal * 3.0
	camera.look_at(center, Vector3.UP)
	await _settle()
	var preview := _blood()
	var host := Host.new()
	host.impact_pool = impacts
	var session := {"camera": camera, "host": host}
	preview.global_position = PLACEMENT.probe(session, preview, camera.unproject_position(center))
	var reference: Variant = preview.get_meta("blood_probe_anchor") if preview.has_meta("blood_probe_anchor") else null
	_expect(reference is WeakRef and reference.get_ref() == leaf, str(door.name) + ": probe resolves the visible moving leaf")
	var mark := _blood()
	mark.global_position = preview.global_position
	PLACEMENT.apply_probe(mark, preview)
	_expect(str(mark.call("get_blood_attachment")["mesh"]) == str(leaf.name), "Placed mark persists its leaf anchor")
	preview.queue_free()
	host.free()
	return mark

func _restore(placed: Node3D, leaf: MeshInstance3D) -> Array[Node3D]:
	var marks: Array[Node3D] = []
	var configs: Array[Dictionary] = []
	# Current saved attachment, old unbound blood, and a stale frame attachment.
	for kind in ["saved", "unbound", "frame"]:
		var mark := _blood()
		mark.global_transform = placed.global_transform
		mark.call("configure_blood_normal", placed.get("surface_normal"))
		if kind == "saved":
			mark.call("configure_blood_attachment", placed.call("get_blood_attachment"))
		elif kind == "frame":
			mark.call("configure_blood_attachment", {"owner": "door", "mesh": "Visual"})
		marks.append(mark)
		configs.append(mark.call("get_blood_attachment"))
	PLACEMENT.restore_attachments([stage], impacts)
	for i in marks.size():
		_expect(marks[i].get("_anchor").get_ref() == leaf, "Saved/legacy mark restores the actual runtime leaf")
		_expect(marks[i].call("get_blood_attachment") == configs[i], "Runtime recovery preserves every authored attachment field")
	await PLACEMENT.restore_attachments_async([stage], self, func() -> bool: return true, impacts)
	for i in marks.size():
		_expect(marks[i].get("_anchor").get_ref() == leaf and marks[i].call("get_blood_attachment") == configs[i], "Async recovery preserves the same runtime anchor and authored fields")
	return marks

func _runtime(door: Node3D, leaf: MeshInstance3D, center: Vector3, normal: Vector3, decal: bool) -> Node3D:
	var effects := EFFECTS.instantiate() as Node3D
	effects.set("splatter_size", Vector2(.2, .3))
	stage.add_child(effects)
	effects.call("configure_world", stage, impacts)
	var budget: Node = effects.get("_budget")
	var settings: Dictionary = budget.get("settings")
	settings["decal"] = decal
	effects.call("configure_environment", [door] as Array[Node])
	await _settle()
	var excluded: Array[RID] = []
	effects.call("splatter_exit", center + normal * .4, -normal, 100.0, excluded)
	await _settle()
	var count := 0
	for mark: Node3D in budget.get("container").get_children():
		var body: Node = mark.get("surface_ref").get_ref()
		if impacts.call("resolve_surface", body, mark.global_position, -normal).get("anchor") != leaf:
			continue
		count += 1
		if decal:
			_expect(mark.get("_decal") != null, "Native Decal path is exercised")
		else:
			var pieces: Array = mark.get("_projected")
			_expect(not pieces.is_empty(), "Compatibility clipped geometry is exercised")
			for reference: WeakRef in pieces:
				var piece: Node3D = reference.get_ref()
				_expect(piece != null and piece.get_parent() == leaf, "Projected runtime blood is parented to the actual leaf mesh")
	_expect(count > 0, "Runtime blood reaches a moving leaf in each render path")
	return effects

func _check_motion(controller: Node, leaf: MeshInstance3D, marks: Array[Node3D], file: String) -> void:
	var offsets: Array[Transform3D] = []
	for mark in marks:
		offsets.append(leaf.global_transform.affine_inverse() * mark.global_transform)
	var closed := leaf.global_transform
	for amount in [.5, 1.0, 0.0]:
		controller.set("_open_amount", amount)
		controller.set("_swing_side", 1.0)
		controller.call("_update_door_visuals", Vector3(0, 0, 1))
		await _settle()
		if amount > 0:
			_expect(not leaf.global_transform.is_equal_approx(closed), file + ": leaf really moves")
		for i in marks.size():
			_expect((leaf.global_transform.affine_inverse() * marks[i].global_transform).is_equal_approx(offsets[i]), file + ": blood follows opening and closing")

func _blood() -> Node3D:
	var mark := BLOOD.instantiate() as Node3D
	mark.call("configure_blood", "splatter_03", "object")
	mark.set_meta("planning_object_id", "")
	stage.add_child(mark)
	mark.call("configure_world", stage, impacts)
	return mark

func _leaf(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		var lower := node.name.to_lower()
		if "doorleaf" in lower or "door_leaf" in lower or lower == "doorglass" or "innerdoor_left" in lower or "innetdoor_left" in lower or "door_left" in lower:
			return node
	for child in node.get_children():
		var found := _leaf(child)
		if found != null:
			return found
	return null

func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null

func _settle() -> void:
	for i in 3:
		await physics_frame
	await process_frame

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
