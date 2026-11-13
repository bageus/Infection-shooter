extends RefCounted
## Build-time helper of tools/build_enemy_rigs.gd: reads the merged part mesh
## written by tools/build_enemy_game_models.gd (<Name>_game.res + <Name>_parts.json)
## and derives rig joints and skin weights from the parts themselves.
##
## Parts are closed meshes cut at the joints, so joints are the centres of their
## cut ends ("caps"). Every part keeps its own bones; across a joint the weight
## blends over a short distance, never past a 40/60 split, so a part's own bones
## always own at least 60% of its skin (severing collapses exactly that part).

const PART_ID_SCALE := 32.0
const SOFT_SHARE := 0.46
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
	var neck: Vector3 = model.cap_centers("Head", 1)[0]
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
	_mirror(points)
	return points


# The clips are authored for a left-right symmetric rig, while the parts are slightly asymmetric:
# every joint pair takes the mean of both sides, and the spine chain sits on the centre line.
static func _mirror(points: Dictionary) -> void:
	for key: String in points.keys():
		if not key.begins_with("L_"):
			continue
		var left: Vector3 = points[key]
		var right: Vector3 = points["R_" + key.substr(2)]
		var mean := Vector3((absf(left.x) + absf(right.x)) * 0.5, (left.y + right.y) * 0.5, (left.z + right.z) * 0.5)
		points[key] = mean
		points["R_" + key.substr(2)] = Vector3(-mean.x, mean.y, mean.z)
	for key in ["Hips", "Spine", "Chest", "Neck", "Head", "HeadTop"]:
		points[key] = Vector3(0.0, (points[key] as Vector3).y, (points[key] as Vector3).z)


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
	var joints := _humanoid_blend_joints(model, points)
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
	return result


# One blend per joint: the part on its parent side and the part on its child side.
static func _humanoid_blend_joints(model: RefCounted, points: Dictionary) -> Array:
	var joints: Array = []
	joints.append({"parent": "Torso", "child": "Head", "at": points["Neck"], "axis": (points["Head"] as Vector3) - (points["Neck"] as Vector3),
		"radius": model.cap_radius("Head"), "parent_bone": "Neck", "child_bone": "Head"})
	for side: String in ["L", "R"]:
		var prefix: String = side + "_"
		joints.append({"parent": "Torso", "child": "UpperArm_" + side, "at": points[prefix + "UpperArm"], "axis": (points[prefix + "Forearm"] as Vector3) - (points[prefix + "UpperArm"] as Vector3),
			"radius": model.cap_radius("UpperArm_" + side), "parent_bone": "Chest", "child_bone": prefix + "UpperArm"})
		joints.append({"parent": "UpperArm_" + side, "child": "Forearm_Hand_" + side, "at": points[prefix + "Forearm"], "axis": (points[prefix + "Hand"] as Vector3) - (points[prefix + "Forearm"] as Vector3),
			"radius": model.cap_radius("Forearm_Hand_" + side), "parent_bone": prefix + "UpperArm", "child_bone": prefix + "Forearm"})
		joints.append({"parent": "Torso", "child": "Thigh_" + side, "at": points[prefix + "Thigh"], "axis": (points[prefix + "Shin"] as Vector3) - (points[prefix + "Thigh"] as Vector3),
			"radius": model.cap_radius("Thigh_" + side), "parent_bone": "Hips", "child_bone": prefix + "Thigh"})
		joints.append({"parent": "Thigh_" + side, "child": "Shin_Foot_" + side, "at": points[prefix + "Shin"], "axis": (points[prefix + "Foot"] as Vector3) - (points[prefix + "Shin"] as Vector3),
			"radius": model.cap_radius("Shin_Foot_" + side), "parent_bone": prefix + "Thigh", "child_bone": prefix + "Shin"})
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
		return {"Neck": 1.0}
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


# Mixes `joint.parent_bone` into the child part's skin, and `joint.child_bone`
# into the parent part's skin, fading with the distance from the joint plane.
static func _blend_joint(weights: Dictionary, joint: Dictionary, part: String, vertex: Vector3) -> void:
	var is_child: bool = part == joint.child
	if not is_child and part != joint.parent:
		return
	var at: Vector3 = joint.at
	var axis: Vector3 = (joint.axis as Vector3).normalized()
	var radius: float = joint.radius
	var along := (vertex - at).dot(axis)
	var reach := 1.2 * radius
	var share := 0.0
	if is_child:
		share = SOFT_SHARE * (1.0 - smoothstep(0.0, reach, along))
	else:
		share = SOFT_SHARE * smoothstep(-reach, 0.0, minf(along, 0.0))
	share *= 1.0 - smoothstep(2.0 * radius, 3.2 * radius, vertex.distance_to(at))
	if share <= 0.0:
		return
	var target: String = joint.parent_bone if is_child else joint.child_bone
	for bone: String in weights:
		weights[bone] = float(weights[bone]) * (1.0 - share)
	weights[target] = float(weights.get(target, 0.0)) + share


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
				rows.append(_horde_body_row(dome[index], skeleton))
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
