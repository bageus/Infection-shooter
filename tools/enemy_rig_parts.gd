extends RefCounted
## Build-time helper of tools/build_enemy_rigs.gd: reads the merged part mesh
## written by tools/build_enemy_game_models.gd (<Name>_game.res + <Name>_parts.json)
## and derives rig joints and skin weights from the parts themselves.
##
## Parts are closed meshes cut at the joints, so joints are the centres of their
## cut ends ("caps"). Every part keeps its own bones; across a joint the weight
## blends over a short distance from the seam, and both sides of a seam carry the
## same weights, so the whole body deforms without tearing.

const PART_ID_SCALE := 32.0
const SOFT_SHARE := 0.46
# Share of the child bone on a seam. A little over half, so the seam and the cut tissue of the
# child stay with the child's piece when it is severed (body_part_topology takes >= 0.5).
const CHILD_SHARE := 0.53
# Joint blends reach this many cap radii from the seam on either side.
const SEAM_REACH := 1.3
# Rim vertices this close to another part's rim are on a seam (the build leaves them on it).
const SEAM_TOUCH := 0.004
# Spine chain as fractions of the way from Hips to Neck (matches the old hand-placed rigs).
const SPINE_AT := 0.294
const CHEST_AT := 0.65

var surfaces: Array = []
var part_names: Array = []
var part_ids := {}
var caps := {}
var _ids: Array = []


static func load_model(directory: String, enemy_name: String) -> RefCounted:
	var mesh := load(directory + enemy_name + "_game.res") as ArrayMesh
	var text := FileAccess.get_file_as_string(directory + enemy_name + "_parts.json")
	if mesh == null or text.is_empty() or mesh.get_surface_count() != 2:
		return null
	var model := new()
	for surface in 2:
		var arrays := mesh.surface_get_arrays(surface)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var ids := PackedInt32Array()
		ids.resize(colors.size())
		for index in colors.size():
			ids[index] = roundi(colors[index].r * PART_ID_SCALE)
		model.surfaces.append(arrays)
		model._ids.append(ids)
	for entry: Dictionary in (JSON.parse_string(text) as Dictionary).parts:
		model.part_names.append(String(entry.name))
		model.part_ids[String(entry.name)] = int(entry.id)
		model.caps[String(entry.name)] = entry.caps
	return model


func vertices(surface: int) -> PackedVector3Array:
	return surfaces[surface][Mesh.ARRAY_VERTEX]


func ids(surface: int) -> PackedInt32Array:
	return _ids[surface]


func part_vertices(part: String) -> PackedVector3Array:
	var result := PackedVector3Array()
	var wanted: int = part_ids[part]
	var all := vertices(0)
	var owners := ids(0)
	for index in all.size():
		if owners[index] == wanted:
			result.append(all[index])
	return result


## Triangle-weighted centres of the cut ends of `part`, split into `count`
## groups ordered from the highest to the lowest. A cut surface can come in
## several fragments; only fragments of real size count.
func cap_centers(part: String, count: int) -> Array[Vector3]:
	var patches: Array = caps[part]
	var biggest := 1
	for patch: Dictionary in patches:
		biggest = maxi(biggest, int(patch.triangles))
	var kept: Array = []
	for patch: Dictionary in patches:
		if int(patch.triangles) * 10 >= biggest:
			kept.append(patch)
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.center[1]) > float(b.center[1]))
	var groups: Array = [[]]
	if count == 2 and kept.size() > 1:
		# Two cut ends: split where the vertical gap between neighbouring fragments is largest.
		var split := 1
		var widest := -1.0
		for index in range(1, kept.size()):
			var gap := float(kept[index - 1].center[1]) - float(kept[index].center[1])
			if gap > widest:
				widest = gap
				split = index
		groups = [kept.slice(0, split), kept.slice(split)]
	else:
		groups = [kept]
		for extra in range(1, count):
			groups.append([])
	var result: Array[Vector3] = []
	for group: Array in groups:
		var sum := Vector3.ZERO
		var weight := 0.0
		for patch: Dictionary in group:
			sum += Vector3(patch.center[0], patch.center[1], patch.center[2]) * float(patch.triangles)
			weight += float(patch.triangles)
		result.append(sum / weight if weight > 0.0 else Vector3.ZERO)
	return result


func cap_radius(part: String) -> float:
	var biggest: Dictionary = {}
	for patch: Dictionary in caps[part]:
		if biggest.is_empty() or int(patch.triangles) > int(biggest.triangles):
			biggest = patch
	return float(biggest.radius) if not biggest.is_empty() else 0.05


## Rim of the skin (edges used by one triangle), position-welded within each part:
## {vertices: Array of skin vertex indices, edges: Array[Vector2i]}.
func skin_rims() -> Dictionary:
	var positions := vertices(0)
	var owners := ids(0)
	var indices: PackedInt32Array = surfaces[0][Mesh.ARRAY_INDEX]
	var canonical := PackedInt32Array()
	canonical.resize(positions.size())
	var first := {}
	for v in positions.size():
		var p := (positions[v] * 100000.0).round()
		var key := Vector4i(int(p.x), int(p.y), int(p.z), owners[v])
		if not first.has(key):
			first[key] = v
		canonical[v] = int(first[key])
	var edge_count := {}
	for t in range(0, indices.size(), 3):
		for k in 3:
			var a := canonical[indices[t + k]]
			var b := canonical[indices[t + (k + 1) % 3]]
			var edge := Vector2i(mini(a, b), maxi(a, b))
			edge_count[edge] = int(edge_count.get(edge, 0)) + 1
	var edges: Array = []
	var seen := {}
	for edge: Vector2i in edge_count:
		if edge_count[edge] == 1:
			edges.append(edge)
			seen[edge.x] = true
			seen[edge.y] = true
	return {"vertices": seen.keys(), "edges": edges}


## Centre of the highest cut end of `part` (the neck cut of the torso when the head part has no cap).
func top_cap(part: String) -> Vector3:
	var best := Vector3(0.0, -INF, 0.0)
	for patch: Dictionary in caps[part]:
		var center := Vector3(patch.center[0], patch.center[1], patch.center[2])
		if center.y > best.y:
			best = center
	return best


# ---------------------------------------------------------------- humanoids

static func humanoid_joints(model: RefCounted) -> Dictionary:
	var low := INF
	var high := -INF
	for point in model.vertices(0):
		low = minf(low, point.y)
		high = maxf(high, point.y)
	var scale := (high - low) / 1.9
	var points := {"Root": Vector3(0.0, low, 0.0)}
	var hips_sum := Vector3.ZERO
	for side: String in ["L", "R"]:
		var upper: Array[Vector3] = model.cap_centers("UpperArm_" + side, 2)
		var elbow: Vector3 = (upper[1] + model.cap_centers("Forearm_Hand_" + side, 1)[0]) * 0.5
		var tip := _farthest(model.part_vertices("Forearm_Hand_" + side), elbow)
		var thigh: Array[Vector3] = model.cap_centers("Thigh_" + side, 2)
		var knee: Vector3 = (thigh[1] + model.cap_centers("Shin_Foot_" + side, 1)[0]) * 0.5
		var prefix := side + "_"
		points[prefix + "UpperArm"] = upper[0]
		points[prefix + "Forearm"] = elbow
		points[prefix + "Hand"] = elbow.lerp(tip, 0.82)
		points[prefix + "HandTip"] = tip
		points[prefix + "Thigh"] = thigh[0]
		points[prefix + "Shin"] = knee
		_add_foot(points, prefix, model.part_vertices("Shin_Foot_" + side), thigh[0], knee, low, scale)
		hips_sum += thigh[0]
	var hips := hips_sum * 0.5 + Vector3(0.0, 0.04 * scale, 0.0)
	var neck: Vector3 = model.cap_centers("Head", 1)[0] if not (model.caps["Head"] as Array).is_empty() else model.top_cap("Torso")
	var head_top := -INF
	for point in model.part_vertices("Head"):
		head_top = maxf(head_top, point.y)
	points["Hips"] = hips
	points["Neck"] = neck
	points["Spine"] = hips.lerp(neck, SPINE_AT)
	points["Chest"] = hips.lerp(neck, CHEST_AT)
	points["Head"] = neck + Vector3(0.0, 0.08 * scale, 0.03 * scale)
	points["HeadTop"] = Vector3(neck.x, head_top, neck.z + 0.03 * scale)
	for side: String in ["L", "R"]:
		var shoulder: Vector3 = points[side + "_UpperArm"]
		var chest: Vector3 = points["Chest"]
		points[side + "_Shoulder"] = Vector3(lerpf(chest.x, shoulder.x, 0.7), shoulder.y + 0.05 * scale, lerpf(chest.z, shoulder.z, 0.5))
	# Every joint stays at the cut of its own side. The parts are posed asymmetrically (Titan's elbows
	# differ by 20 cm, Colossus' knees by 14 cm); averaging both sides put the pivots up to 10 cm off the
	# cuts, so limbs swung off their seams. The Mixamo retarget aims each bone, so it needs no symmetry.
	return points


static func _farthest(candidates: PackedVector3Array, from: Vector3) -> Vector3:
	var best := from
	for point in candidates:
		if point.distance_to(from) > best.distance_to(from):
			best = point
	return best


# Ankle, toe and toe tip from the lowest tenth of the shin-and-foot part.
static func _add_foot(points: Dictionary, prefix: String, vertices: PackedVector3Array, hip: Vector3, knee: Vector3, floor_y: float, scale: float) -> void:
	var sole := PackedVector3Array()
	for point in vertices:
		if point.y < floor_y + 0.1 * scale:
			sole.append(point)
	var front := -INF
	for point in sole:
		front = maxf(front, point.z)
	# The ankle continues the hip-knee line, so the rest leg is straight like the clips expect.
	var ankle_y := floor_y + 0.091 * scale
	var ankle := hip + (knee - hip) * ((ankle_y - hip.y) / (knee.y - hip.y))
	ankle.x = knee.x
	ankle.z = knee.z
	points[prefix + "Foot"] = ankle
	front = maxf(front, ankle.z + 0.12 * scale)
	points[prefix + "Toe"] = Vector3(ankle.x, floor_y + 0.04 * scale, lerpf(ankle.z, front, 0.6))
	points[prefix + "ToeTip"] = Vector3(ankle.x, floor_y + 0.03 * scale, front)


static func humanoid_weights(model: RefCounted, points: Dictionary, skeleton: Skeleton3D) -> Array:
	var scale: float = ((points["HeadTop"] as Vector3).y - (points["Root"] as Vector3).y) / 1.9
	var rims: Dictionary = model.skin_rims()
	var joints := _humanoid_blend_joints(model, points)
	for joint: Dictionary in joints:
		joint["seam"] = _seam(model, rims, joint.parent, joint.child)
		if (joint.seam as PackedVector3Array).is_empty() and joint.child == "Head":
			# Titan's head part is closed without a neck cut; its neck is the open top ring of the torso.
			joint["seam"] = _open_ring(model, rims, "Torso", model.top_cap("Torso"), 2.0 * float(joint.radius))
	var result: Array = []
	for surface in model.surfaces.size():
		var positions: PackedVector3Array = model.vertices(surface)
		var owners: PackedInt32Array = model.ids(surface)
		var rows: Array = []
		for index in positions.size():
			var part: String = model.part_names[owners[index]]
			var weights := _humanoid_base(part, positions[index], points, scale)
			for joint: Dictionary in joints:
				_blend_joint(weights, joint, part, positions[index])
			rows.append(_dense(weights, skeleton))
		result.append(rows)
	_weld_rims(model, rims, result[0])
	return result


# One blend per joint: the part on its parent side and the part on its child side. The shoulder
# seam blends into the clavicle bone, so the top of the shoulder follows the Mixamo shrug with the arm.
static func _humanoid_blend_joints(model: RefCounted, points: Dictionary) -> Array:
	var joints: Array = []
	joints.append({"parent": "Torso", "child": "Head", "radius": model.cap_radius("Head") if not (model.caps["Head"] as Array).is_empty() else 0.08,
		"parent_bone": "Neck", "child_bone": "Head"})
	for side: String in ["L", "R"]:
		var prefix: String = side + "_"
		joints.append({"parent": "Torso", "child": "UpperArm_" + side, "radius": model.cap_radius("UpperArm_" + side), "parent_bone": prefix + "Shoulder", "child_bone": prefix + "UpperArm"})
		joints.append({"parent": "UpperArm_" + side, "child": "Forearm_Hand_" + side, "radius": model.cap_radius("Forearm_Hand_" + side), "parent_bone": prefix + "UpperArm", "child_bone": prefix + "Forearm"})
		joints.append({"parent": "Torso", "child": "Thigh_" + side, "radius": model.cap_radius("Thigh_" + side), "parent_bone": "Hips", "child_bone": prefix + "Thigh"})
		joints.append({"parent": "Thigh_" + side, "child": "Shin_Foot_" + side, "radius": model.cap_radius("Shin_Foot_" + side), "parent_bone": prefix + "Thigh", "child_bone": prefix + "Shin"})
	return joints


static func _humanoid_base(part: String, vertex: Vector3, points: Dictionary, scale: float) -> Dictionary:
	if part == "Head":
		return {"Head": 1.0}
	if part == "Torso":
		var hips: Vector3 = points["Hips"]
		var axis: Vector3 = (points["Neck"] as Vector3) - hips
		var t := (vertex - hips).dot(axis) / axis.length_squared()
		var stops := [["Hips", 0.0], ["Spine", SPINE_AT], ["Chest", CHEST_AT], ["Neck", 1.0]]
		if t <= 0.0:
			return {"Hips": 1.0}
		for index in 3:
			var from: float = stops[index][1]
			var to: float = stops[index + 1][1]
			if t <= to:
				var k := (t - from) / (to - from)
				return {stops[index][0]: 1.0 - k, stops[index + 1][0]: k}
		# Above the neck only skin near the neck line follows the Neck bone; humps and shoulder
		# growths beside it (Titan) stay on the Chest, or they tear away from the head when it turns.
		var lateral := (vertex - hips - axis * t).length()
		var neck := 1.0 - smoothstep(0.1 * scale, 0.22 * scale, lateral)
		return {"Neck": neck, "Chest": 1.0 - neck}
	var prefix := ("L_" if part.ends_with("_L") else "R_")
	if part.begins_with("UpperArm"):
		return {prefix + "UpperArm": 1.0}
	if part.begins_with("Forearm_Hand"):
		var elbow: Vector3 = points[prefix + "Forearm"]
		var tip: Vector3 = points[prefix + "HandTip"]
		var along := (tip - elbow)
		var hand := smoothstep(0.68, 0.94, (vertex - elbow).dot(along) / along.length_squared())
		return {prefix + "Forearm": 1.0 - hand, prefix + "Hand": hand}
	if part.begins_with("Thigh"):
		return {prefix + "Thigh": 1.0}
	# Shin and foot: shin above the ankle, foot below it, toe in front of the toe joint.
	var ankle: Vector3 = points[prefix + "Foot"]
	var toe: Vector3 = points[prefix + "Toe"]
	var foot := smoothstep(ankle.y + 0.06 * scale, ankle.y - 0.03 * scale, vertex.y)
	var toe_share := smoothstep(toe.z - 0.03 * scale, toe.z + 0.04 * scale, vertex.z) * foot
	return {prefix + "Shin": 1.0 - foot, prefix + "Foot": foot - toe_share, prefix + "Toe": toe_share}


# Mixes `joint.parent_bone` into the child part's skin and `joint.child_bone` into the parent
# part's skin, fading with the distance from the seam (the rim the two parts share). On the seam
# both sides take the same mix. The old blend faded with the distance from a flat plane
# through the cap centre, but the cuts are slanted: rim vertices off that plane got a different
# mix on each side and the joint tore open by up to 12 cm (tools/measure_enemy_seams.gd).
static func _blend_joint(weights: Dictionary, joint: Dictionary, part: String, vertex: Vector3) -> void:
	var is_child: bool = part == joint.child
	if not is_child and part != joint.parent:
		return
	var reach: float = SEAM_REACH * float(joint.radius)
	var seam: PackedVector3Array = joint.seam
	var nearest := INF
	for point in seam:
		nearest = minf(nearest, vertex.distance_squared_to(point))
	var pull := 1.0 - smoothstep(0.0, reach, sqrt(nearest))
	if pull <= 0.0:
		return
	for bone: String in weights:
		weights[bone] = float(weights[bone]) * (1.0 - pull)
	weights[joint.child_bone] = float(weights.get(joint.child_bone, 0.0)) + pull * CHILD_SHARE
	weights[joint.parent_bone] = float(weights.get(joint.parent_bone, 0.0)) + pull * (1.0 - CHILD_SHARE)


# Rim points of `child` that lie on the rim of `parent` (the joint seam).
static func _seam(model: RefCounted, rims: Dictionary, parent: String, child: String) -> PackedVector3Array:
	var positions := model.vertices(0) as PackedVector3Array
	var owners := model.ids(0) as PackedInt32Array
	var parent_id: int = model.part_ids[parent]
	var child_id: int = model.part_ids[child]
	var result := PackedVector3Array()
	for v: int in rims.vertices:
		if owners[v] != child_id:
			continue
		if _rim_distance(positions, rims.edges, owners, parent_id, positions[v]).x < SEAM_TOUCH:
			result.append(positions[v])
	return result


# Rim points of `part` within `reach` of `center`.
static func _open_ring(model: RefCounted, rims: Dictionary, part: String, center: Vector3, reach: float) -> PackedVector3Array:
	var positions := model.vertices(0) as PackedVector3Array
	var owners := model.ids(0) as PackedInt32Array
	var result := PackedVector3Array()
	for v: int in rims.vertices:
		if owners[v] == model.part_ids[part] and positions[v].distance_to(center) < reach:
			result.append(positions[v])
	return result


# A rim vertex of the lower part id lies on a rim edge of the higher id (build_enemy_game_models
# moved it there); it takes the weights interpolated along that edge, so both sides of every
# seam deform exactly together whatever the blends gave them.
static func _weld_rims(model: RefCounted, rims: Dictionary, rows: Array) -> void:
	var positions := model.vertices(0) as PackedVector3Array
	var owners := model.ids(0) as PackedInt32Array
	var source := rows.duplicate()
	var welded := {}
	for v: int in rims.vertices:
		var best := Vector3(INF, 0.0, 0.0)
		var best_edge := Vector2i(-1, -1)
		for edge: Vector2i in rims.edges:
			if owners[edge.x] <= owners[v]:
				continue
			var hit := _edge_distance(positions, edge, positions[v])
			if hit.x < best.x:
				best = hit
				best_edge = edge
		if best.x < SEAM_TOUCH:
			var row := (source[best_edge.x] as PackedFloat32Array).duplicate()
			var to: PackedFloat32Array = source[best_edge.y]
			for b in row.size():
				row[b] = lerpf(row[b], to[b], best.y)
			welded[positions[v]] = row
	# UV splits of a rim vertex share its position and take the same row.
	for v in positions.size():
		if welded.has(positions[v]):
			rows[v] = welded[positions[v]]


# Nearest rim edge of part `part_id` to `point`: Vector2(distance, unused).
static func _rim_distance(positions: PackedVector3Array, edges: Array, owners: PackedInt32Array, part_id: int, point: Vector3) -> Vector2:
	var best := INF
	for edge: Vector2i in edges:
		if owners[edge.x] == part_id:
			best = minf(best, _edge_distance(positions, edge, point).x)
	return Vector2(best, 0.0)


# Vector3(distance from `point` to the segment, position along it 0..1, 0).
static func _edge_distance(positions: PackedVector3Array, edge: Vector2i, point: Vector3) -> Vector3:
	var a := positions[edge.x]
	var ab := positions[edge.y] - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	return Vector3(point.distance_to(a + ab * t), t, 0.0)


static func _dense(weights: Dictionary, skeleton: Skeleton3D) -> PackedFloat32Array:
	var row := PackedFloat32Array()
	row.resize(skeleton.get_bone_count())
	for bone: String in weights:
		row[skeleton.find_bone(bone)] = float(weights[bone])
	return row


# ---------------------------------------------------------------- horde

## Legs ordered by their angle round the body: {names, angles, joints}. A joint
## holds the leg root (A) and the middle of the leg (B); the leg root is the
## centre of its cut end.
static func horde_legs(model: RefCounted) -> Dictionary:
	var entries: Array = []
	for part: String in model.part_names:
		if not part.begins_with("Leg_"):
			continue
		var attach: Vector3 = model.cap_centers(part, 1)[0]
		var tip := _farthest(model.part_vertices(part), attach)
		var angle := fposmod(atan2(attach.x, attach.z), TAU)
		entries.append({"name": part, "angle": angle, "a": attach, "b": attach.lerp(tip, 0.5), "radius": model.cap_radius(part)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.angle) < float(b.angle))
	var result := {"names": [], "angles": [], "joints": [], "radii": []}
	for entry: Dictionary in entries:
		result.names.append(entry.name)
		result.angles.append(entry.angle)
		result.joints.append({"a": entry.a, "b": entry.b})
		result.radii.append(entry.radius)
	return result


static func horde_weights(model: RefCounted, author: RefCounted, skeleton: Skeleton3D, legs: Dictionary) -> Array:
	var result: Array = []
	var body_id: int = model.part_ids["Body"]
	for surface in model.surfaces.size():
		var positions: PackedVector3Array = model.vertices(surface)
		var owners: PackedInt32Array = model.ids(surface)
		var dome: Array = author.weights(positions, skeleton)
		var rows: Array = []
		for index in positions.size():
			if owners[index] == body_id:
				rows.append(author.add_cells(_horde_body_row(dome[index], skeleton), positions[index], skeleton))
			else:
				rows.append(_horde_leg_row(String(model.part_names[owners[index]]), positions[index], skeleton, legs))
		result.append(rows)
	return result


# The dome keeps its own weights; tentacle bones may hold at most 40% of it.
static func _horde_body_row(row: PackedFloat32Array, skeleton: Skeleton3D) -> PackedFloat32Array:
	var tentacle := 0.0
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone).begins_with("T"):
			tentacle += row[bone]
	if tentacle <= SOFT_SHARE:
		return row
	var keep := SOFT_SHARE / tentacle
	var moved := 0.0
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone).begins_with("T"):
			moved += row[bone] * (1.0 - keep)
			row[bone] *= keep
	row[skeleton.find_bone("Hips")] += moved
	return row


static func _horde_leg_slot(part: String, legs: Dictionary) -> int:
	return (legs.names as Array).find(part)


static func _horde_leg_row(part: String, vertex: Vector3, skeleton: Skeleton3D, legs: Dictionary) -> PackedFloat32Array:
	var slot := _horde_leg_slot(part, legs)
	var row := PackedFloat32Array()
	row.resize(skeleton.get_bone_count())
	if slot < 0:
		row[skeleton.find_bone("Hips")] = 1.0
		return row
	var joint: Dictionary = (legs.joints as Array)[slot]
	var a: Vector3 = joint.a
	var b: Vector3 = joint.b
	var along := (vertex - a).dot((b - a).normalized())
	var length := a.distance_to(b)
	var outer := smoothstep(0.5 * length, 1.2 * length, along)
	var near_body := SOFT_SHARE * (1.0 - smoothstep(0.0, 0.8 * float((legs.radii as Array)[slot]), along))
	row[skeleton.find_bone("T%d_A" % slot)] = (1.0 - outer) * (1.0 - near_body)
	row[skeleton.find_bone("T%d_B" % slot)] = outer * (1.0 - near_body)
	row[skeleton.find_bone("Hips")] = near_body
	return row
