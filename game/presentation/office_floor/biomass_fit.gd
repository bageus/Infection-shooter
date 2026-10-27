extends Node3D
## Automatic fitting of planner biomass (ADR-0061). Every biomass decal owns one
## of these. Pieces that share a surface and touch each other are grouped; the
## first piece of a group draws the whole group as one fused mass and the others
## hide, so adjacent pieces read as a single body. Fusion runs on a worker
## thread, and a piece that moves shows its own relief until it settles.

const ATLAS := preload("res://game/presentation/office_floor/biomass_atlas.gd")
const FUSION := preload("res://game/presentation/office_floor/biomass_fusion.gd")
const MESH := preload("res://game/presentation/office_floor/biomass_mesh.gd")

## Seconds a piece must rest before the group is refitted.
const SETTLE := 0.35
## Pieces closer than this (metres, in the surface plane) count as touching.
const JOIN_GAP := 0.12
const PLANE_TOLERANCE := 0.04
const NORMAL_DOT := 0.97
const TARGET_PPU := 450.0
## Longest side (metres) of the box round one fused group, and the cell size
## of the lookup grid used to find neighbours.
const MAX_SPAN := 3.5
const CELL := 2.0

var piece: Node3D
var shown_signature := 0
var _last_transform := Transform3D()
var _wait := 0.05
var _members: Array[WeakRef] = []
var _task := -1
static var _orphans: Array[int] = []
var _job: Dictionary = {}
var _queued: Dictionary = {}


func _ready() -> void:
	piece = get_parent() as Node3D
	_last_transform = piece.global_transform
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not is_processing() and is_instance_valid(piece) and piece.is_inside_tree():
		if not piece.global_transform.is_equal_approx(_last_transform):
			set_process(true)


func _process(delta: float) -> void:
	if piece == null or not piece.is_inside_tree():
		return
	var current := piece.global_transform
	if not current.is_equal_approx(_last_transform):
		_last_transform = current
		_wait = SETTLE
		show_own_relief()
	if _wait >= 0.0:
		_wait -= delta
		if _wait < 0.0:
			_fit_neighbours()
	_collect_job()
	if _wait < 0.0 and _task < 0 and _queued.is_empty():
		set_process(false)


func _exit_tree() -> void:
	_release_members()
	if _task < 0:
		return
	# A large group can take tens of seconds to fuse, and waiting here would also make this thread run
	# other pieces' queued fusions. The worker is told to stop and is collected on later frames.
	var cancel: Array = _job.get("cancel", [])
	if not cancel.is_empty():
		cancel[0] = true
	_orphans.append(_task)
	_task = -1
	var tree := get_tree()
	if not tree.process_frame.is_connected(_reap_orphans):
		tree.process_frame.connect(_reap_orphans)


## Collects cancelled fusions of pieces that left the tree, without ever blocking a frame.
static func _reap_orphans() -> void:
	for task in _orphans.duplicate():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_orphans.erase(task)
	if _orphans.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.process_frame.disconnect(_reap_orphans)


# Restores the piece's own cell and wakes anything it hid.
func show_own_relief() -> void:
	shown_signature = 0
	_queued = {}
	_release_members()
	piece.call("biomass_show_cell")


func release() -> void:
	set_process(true)
	_wait = 0.05
	shown_signature = 0
	piece.call("biomass_show_cell")


func _release_members() -> void:
	for reference in _members:
		var other := reference.get_ref() as Node
		if other != null and is_instance_valid(other) and other != piece and other.has_node("BiomassFit"):
			other.get_node("BiomassFit").call("release")
	_members.clear()


func _fit_neighbours() -> void:
	var parent := piece.get_parent()
	if parent == null:
		return
	var frame := Engine.get_process_frames()
	if int(parent.get_meta("biomass_fit_frame", -1)) == frame:
		return
	parent.set_meta("biomass_fit_frame", frame)
	var pieces: Array[Node3D] = []
	for child in parent.get_children():
		if child.has_meta("biomass_piece") and (child as Node3D).is_inside_tree() and not bool(child.call("biomass_excluded")):
			pieces.append(child as Node3D)
	for group in _groups(pieces):
		_fit_group(group)


# Pieces on one surface that touch, as arrays in scene order. A group never
# grows past MAX_SPAN, so a long generated vein splits into masses that each
# keep a sharp image instead of one blurred map for the whole level.
func _groups(pieces: Array[Node3D]) -> Array:
	var infos: Array[Dictionary] = []
	var cells := {}
	var widest := 0.0
	for index in pieces.size():
		var piece_node := pieces[index]
		var frame: Transform3D = piece_node.call("biomass_frame")
		var reach := ATLAS.FOOTPRINT.length() * 0.5 * maxf(frame.basis.x.length(), 0.001) + JOIN_GAP
		widest = maxf(widest, reach)
		infos.append({"frame": frame, "attachment": piece_node.call("get_blood_attachment"), "reach": reach})
		var key := Vector2i(floori(frame.origin.x / CELL), floori(frame.origin.z / CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(index)
	var parents := range(pieces.size())
	var boxes: Array[AABB] = []
	for info in infos:
		var origin: Vector3 = (info["frame"] as Transform3D).origin
		var span := Vector3.ONE * float(info["reach"])
		boxes.append(AABB(origin - span, span * 2.0))
	for i in pieces.size():
		var origin_i: Vector3 = (infos[i]["frame"] as Transform3D).origin
		var near := ceili((float(infos[i]["reach"]) + widest) / CELL)
		var home := Vector2i(floori(origin_i.x / CELL), floori(origin_i.z / CELL))
		var candidates: Array[int] = []
		for dx in range(-near, near + 1):
			for dz in range(-near, near + 1):
				for j: int in cells.get(home + Vector2i(dx, dz), []):
					if j > i:
						candidates.append(j)
		candidates.sort()
		for j in candidates:
			var root_i: int = _root(parents, i)
			var root_j: int = _root(parents, j)
			if root_i == root_j or not _touching(infos[i], infos[j]):
				continue
			var merged := boxes[root_i].merge(boxes[root_j])
			if maxf(merged.size.x, maxf(merged.size.y, merged.size.z)) > MAX_SPAN:
				continue
			parents[maxi(root_i, root_j)] = mini(root_i, root_j)
			boxes[mini(root_i, root_j)] = merged
	var by_root := {}
	for index in pieces.size():
		var root_index := _root(parents, index)
		if not by_root.has(root_index):
			by_root[root_index] = []
		by_root[root_index].append(pieces[index])
	return by_root.values()


func _root(parents: Array, index: int) -> int:
	while parents[index] != index:
		index = parents[index]
	return index


func _touching(a: Dictionary, b: Dictionary) -> bool:
	var frame_a: Transform3D = a["frame"]
	var frame_b: Transform3D = b["frame"]
	if a["attachment"] != b["attachment"]:
		return false
	var normal := frame_a.basis.z.normalized()
	if normal.dot(frame_b.basis.z.normalized()) < NORMAL_DOT:
		return false
	if absf(normal.dot(frame_b.origin - frame_a.origin)) > PLANE_TOLERANCE:
		return false
	if frame_a.origin.distance_to(frame_b.origin) > float(a["reach"]) + float(b["reach"]):
		return false
	var scale_a := maxf(frame_a.basis.x.length(), 0.001)
	var other := _plane_transform(frame_a.affine_inverse() * frame_b)
	var polygon_a := _footprint(Transform2D.IDENTITY)
	var polygon_b := Geometry2D.offset_polygon(_footprint(other), JOIN_GAP / scale_a)
	if polygon_b.is_empty():
		return false
	return not Geometry2D.intersect_polygons(polygon_a, polygon_b[0]).is_empty()


static func _footprint(xform: Transform2D) -> PackedVector2Array:
	var half := ATLAS.FOOTPRINT * 0.5
	return PackedVector2Array([xform * Vector2(-half.x, -half.y), xform * Vector2(half.x, -half.y), xform * Vector2(half.x, half.y), xform * Vector2(-half.x, half.y)])


static func _plane_transform(local: Transform3D) -> Transform2D:
	return Transform2D(Vector2(local.basis.x.x, local.basis.x.y), Vector2(local.basis.y.x, local.basis.y.y), Vector2(local.origin.x, local.origin.y))


func _fit_group(group: Array) -> void:
	var leader: Node3D = group[0]
	var leader_fit: Node = leader.get_node("BiomassFit")
	if group.size() == 1:
		if int(leader_fit.shown_signature) != 0:
			leader_fit.show_own_relief()
		return
	var leader_frame: Transform3D = leader.call("biomass_frame")
	var inverse := leader_frame.affine_inverse()
	var members: Array = []
	var signature: Array = []
	var others: Array[WeakRef] = []
	for piece_node: Node3D in group:
		var xform := _plane_transform(inverse * (piece_node.call("biomass_frame") as Transform3D))
		var cell: int = piece_node.call("biomass_cell")
		members.append({"cell": cell, "xform": xform})
		signature.append([cell, snappedf(xform.x.x, 0.001), snappedf(xform.x.y, 0.001), snappedf(xform.y.x, 0.001), snappedf(xform.y.y, 0.001), snappedf(xform.origin.x, 0.001), snappedf(xform.origin.y, 0.001)])
		if piece_node != leader:
			others.append(weakref(piece_node))
			var fit: Node = piece_node.get_node("BiomassFit")
			if int(fit.shown_signature) != 0 or not fit._members.is_empty():
				fit.show_own_relief()
	var key := hash(signature)
	leader_fit.call("adopt", others, members, key)


# Called on the group's first piece with the pieces it speaks for.
func adopt(others: Array[WeakRef], members: Array, key: int) -> void:
	var fresh: Array[WeakRef] = []
	for reference in _members:
		var old := reference.get_ref() as Node
		var kept := false
		for candidate in others:
			if candidate.get_ref() == old:
				kept = true
		if not kept and old != null and old.has_node("BiomassFit"):
			old.get_node("BiomassFit").call("release")
	fresh.append_array(others)
	_members = fresh
	if key == shown_signature or key == int(_job.get("key", 0)) or key == int(_queued.get("key", 0)):
		return
	var job := {"members": members, "key": key}
	if _task >= 0:
		_queued = job
	else:
		_start(job)


func _start(job: Dictionary) -> void:
	set_process(true)
	_job = job
	var members: Array = job["members"]
	var albedo := ATLAS.albedo_bytes()
	var relief := ATLAS.relief_bytes()
	var output := _job
	var cancel := [false]
	output["cancel"] = cancel
	_task = WorkerThreadPool.add_task(func() -> void: output["result"] = FUSION.fuse(members, albedo, relief, TARGET_PPU, cancel))


func _collect_job() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var finished := _job
	_job = {}
	if not _queued.is_empty():
		var next := _queued
		_queued = {}
		_start(next)
	var result: Dictionary = finished.get("result", {})
	if result.is_empty() or not is_instance_valid(piece):
		return
	if _members.is_empty():
		return
	shown_signature = int(finished["key"])
	piece.call("biomass_show_fused", MESH.fused_patch(result))
	for reference in _members:
		var other := reference.get_ref() as Node3D
		if other != null and is_instance_valid(other):
			other.call("biomass_hide")
