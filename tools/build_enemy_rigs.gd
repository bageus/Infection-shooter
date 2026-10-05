extends SceneTree
## Auto-rigs the static enemy game meshes and bakes enemy animation clips.
##
## Run after tools/build_enemy_game_models.gd and an editor import:
##   godot --headless --path . --script res://tools/build_enemy_rigs.gd
##
## For every humanoid in enemy_rig_joints.json and for the Horde blob it writes
## into models/objects/characters/enemy/game/:
##   <Name>_rig_mesh.res  skinned copy of <Name>_game.res (4 weights/vertex)
##   <Name>_anims.res     AnimationLibrary (Idle, Walk, Run, attacks, Death, extras)
##   <Name>_rig.tscn      Visual > Skeleton3D > Mesh + AnimationPlayer

const AUTHOR := preload("res://tools/enemy_animation_author.gd")
const HORDE_AUTHOR := preload("res://tools/horde_animation_author.gd")
const OUTPUT_DIR := "res://models/objects/characters/enemy/game/"
const JOINTS_PATH := "res://tools/enemy_rig_joints.json"
const HUMANOID_BONES := [
	["Root", ""], ["Hips", "Root"], ["Spine", "Hips"], ["Chest", "Spine"], ["Neck", "Chest"], ["Head", "Neck"],
	["L_Shoulder", "Chest"], ["L_UpperArm", "L_Shoulder"], ["L_Forearm", "L_UpperArm"], ["L_Hand", "L_Forearm"],
	["R_Shoulder", "Chest"], ["R_UpperArm", "R_Shoulder"], ["R_Forearm", "R_UpperArm"], ["R_Hand", "R_Forearm"],
	["L_Thigh", "Hips"], ["L_Shin", "L_Thigh"], ["L_Foot", "L_Shin"], ["L_Toe", "L_Foot"],
	["R_Thigh", "Hips"], ["R_Shin", "R_Thigh"], ["R_Foot", "R_Shin"], ["R_Toe", "R_Foot"],
]
# Skin segment end for every weighted bone, plus its typical thickness.
const SEGMENTS := {
	"Hips": ["Spine", 0.15], "Spine": ["Chest", 0.16], "Chest": ["Neck", 0.17], "Neck": ["Head", 0.07], "Head": ["HeadTop", 0.1],
	"Shoulder": ["UpperArm", 0.08], "UpperArm": ["Forearm", 0.065], "Forearm": ["Hand", 0.055], "Hand": ["HandTip", 0.045],
	"Thigh": ["Shin", 0.085], "Shin": ["Foot", 0.065], "Foot": ["Toe", 0.055], "Toe": ["ToeTip", 0.04],
}
const LEG_PARTS := ["Thigh", "Shin", "Foot", "Toe"]
# Per enemy clip style; speeds are derived from stride and printed for scenes.
# Per enemy clip style. walk_mps/run_mps are the gameplay speeds (metres per
# second, world units) the clips are paced for; scale is the Body scale.
const STYLES := {
	"Hunger": {"scale": 1.0, "walk_mps": 2.16, "run_mps": 5.4, "walk_swing": 28.0, "run_swing": 40.0, "lean": 30.0, "reach": 1.0, "heavy": 0.0, "attack_seconds": 0.9, "death_seconds": 1.5},
	"Revenant": {"scale": 1.0, "walk_mps": 1.84, "run_mps": 4.6, "walk_swing": 27.0, "run_swing": 38.0, "lean": 26.0, "reach": 0.8, "heavy": 0.1, "attack_seconds": 1.0, "death_seconds": 1.6},
	"Brute": {"scale": 1.1, "walk_mps": 1.64, "run_mps": 4.1, "walk_swing": 26.0, "run_swing": 36.0, "lean": 24.0, "reach": 0.6, "heavy": 0.35, "attack_seconds": 1.1, "death_seconds": 1.7},
	"Titan": {"scale": 1.35, "walk_mps": 1.32, "run_mps": 3.3, "walk_swing": 24.0, "run_swing": 32.0, "lean": 20.0, "reach": 0.4, "heavy": 0.7, "attack_seconds": 1.3, "death_seconds": 2.0},
	"Colossus": {"scale": 1.55, "walk_mps": 1.16, "run_mps": 2.9, "walk_swing": 22.0, "run_swing": 30.0, "lean": 18.0, "reach": 0.3, "heavy": 1.0, "attack_seconds": 1.4, "death_seconds": 2.2, "slam": true, "slam_seconds": 1.7},
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var joints: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JOINTS_PATH))
	var failures := 0
	for enemy_name: String in joints:
		if enemy_name.begins_with("_"):
			continue
		if not _build_humanoid(enemy_name, joints[enemy_name]):
			failures += 1
	if not _build_horde():
		failures += 1
	print("Enemy rigs built, failures: %d" % failures)
	quit(failures)


# ---------------------------------------------------------------- humanoids

func _build_humanoid(enemy_name: String, joints: Dictionary) -> bool:
	var source := load(OUTPUT_DIR + enemy_name + "_game.res") as ArrayMesh
	if source == null:
		push_error("Missing game mesh for " + enemy_name)
		return false
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var floor_y := INF
	for vertex in vertices:
		floor_y = minf(floor_y, vertex.y)
	var points := {}
	for key: String in joints:
		var value: Array = joints[key]
		points[key] = Vector3(value[0], value[1], value[2])
	points["Root"] = Vector3(0.0, floor_y, 0.0)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	for entry: Array in HUMANOID_BONES:
		var index := skeleton.add_bone(entry[0])
		var parent: String = entry[1]
		var origin: Vector3 = points[entry[0]]
		if not parent.is_empty():
			skeleton.set_bone_parent(index, skeleton.find_bone(parent))
			origin -= points[parent] as Vector3
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, origin))
	skeleton.reset_bone_poses()
	var segments := []
	for entry: Array in HUMANOID_BONES:
		var bone: String = entry[0]
		var part := bone.substr(2) if bone.begins_with("L_") or bone.begins_with("R_") else bone
		if not SEGMENTS.has(part):
			continue
		var prefix := bone.substr(0, 2) if part != bone else ""
		var spec: Array = SEGMENTS[part]
		segments.append({
			"bone": skeleton.find_bone(bone), "a": points[bone], "b": points[prefix + String(spec[0])],
			"radius": float(spec[1]), "initial": float(spec[1]), "side": 1.0 if prefix == "L_" else (-1.0 if prefix == "R_" else 0.0),
			"leg": part in LEG_PARTS,
		})
	var hips_y: float = (points["Hips"] as Vector3).y
	var weights := _humanoid_weights(vertices, arrays[Mesh.ARRAY_INDEX], segments, hips_y)
	_debug_dump(enemy_name, vertices, weights, skeleton)
	var author := AUTHOR.new()
	author.setup(skeleton)
	var style: Dictionary = STYLES[enemy_name]
	var library: AnimationLibrary = author.build_humanoid_library(style)
	print("%s: pace %s, hips %.2f, leg %.2f" % [enemy_name, author.pace(style), author.hips_height, author.leg_length])
	return _save_rig(enemy_name, skeleton, arrays, weights, library)


# Geodesic skinning: each bone grows over the welded mesh surface from seed
# vertices hugging its segment, so thick limbs never pull nearby torso skin
# along. Vertices no seed can reach fall back to the nearest segment.
func _humanoid_weights(vertices: PackedVector3Array, indices: PackedInt32Array, segments: Array, hips_y: float) -> Array:
	var count := vertices.size()
	var bone_count := 0
	for segment: Dictionary in segments:
		bone_count = maxi(bone_count, int(segment.bone) + 1)
	var graph := _welded_graph(vertices, indices)
	var nearest := PackedInt32Array()
	var nearest_distance := PackedFloat32Array()
	nearest.resize(count)
	nearest_distance.resize(count)
	for v in count:
		var best := -1
		var best_value := INF
		for s in segments.size():
			if not _allowed(vertices[v], segments[s], hips_y):
				continue
			var value := _segment_distance(vertices[v], segments[s].a, segments[s].b)
			if value < best_value:
				best_value = value
				best = s
		nearest[v] = best
		nearest_distance[v] = best_value
	var geodesic := []
	for s in segments.size():
		var segment: Dictionary = segments[s]
		var distances := PackedFloat32Array()
		for v in count:
			if nearest[v] == s:
				distances.append(nearest_distance[v])
		var seeds := PackedInt32Array()
		if distances.size() > 0:
			var sorted := distances.duplicate()
			sorted.sort()
			var torso := float(segment.side) == 0.0
			var limit := sorted[mini(sorted.size() - 1, int(sorted.size() * (0.6 if torso else 0.35)))]
			for v in count:
				if nearest[v] == s and nearest_distance[v] <= limit:
					seeds.append(v)
		geodesic.append(_dijkstra(graph, vertices, seeds, segment, hips_y))
	var dense: Array[PackedFloat32Array] = []
	for v in count:
		var row := PackedFloat32Array()
		row.resize(bone_count)
		var total := 0.0
		for s in segments.size():
			var distance: float = (geodesic[s] as PackedFloat32Array)[v]
			if distance == INF:
				continue
			var weight := 1.0 / pow(distance + 0.015, 4.0)
			row[int(segments[s].bone)] += weight
			total += weight
		if total <= 0.0 and nearest[v] >= 0:
			row[int(segments[nearest[v]].bone)] = 1.0
			total = 1.0
		if total > 0.0:
			for b in bone_count:
				row[b] /= total
		dense.append(row)
	var neighbours: Array = graph.neighbours
	for iteration in 2:
		var smoothed: Array[PackedFloat32Array] = []
		for v in count:
			var row := dense[v].duplicate()
			var around: PackedInt32Array = neighbours[graph.canonical[v]]
			if around.size() > 0:
				for b in bone_count:
					var mean := 0.0
					for n in around:
						mean += dense[n][b]
					row[b] = row[b] * 0.6 + mean / float(around.size()) * 0.4
			smoothed.append(row)
		dense = smoothed
	var allowed_bones := {}
	for segment: Dictionary in segments:
		allowed_bones[int(segment.bone)] = segment
	for v in count:
		for b in bone_count:
			if allowed_bones.has(b) and not _allowed(vertices[v], allowed_bones[b], hips_y):
				dense[v][b] = 0.0
	return dense


# Multi-source shortest paths over the welded surface, confined to the
# region the bone may influence. Returns a distance per original vertex.
func _dijkstra(graph: Dictionary, vertices: PackedVector3Array, seeds: PackedInt32Array, segment: Dictionary, hips_y: float) -> PackedFloat32Array:
	var count := vertices.size()
	var canonical: PackedInt32Array = graph.canonical
	var neighbours: Array = graph.neighbours
	var best := PackedFloat32Array()
	best.resize(count)
	best.fill(INF)
	var heap_cost := PackedFloat32Array()
	var heap_node := PackedInt32Array()
	for seed in seeds:
		var c := canonical[seed]
		if best[c] > 0.0:
			best[c] = 0.0
			_heap_push(heap_cost, heap_node, 0.0, c)
	while heap_node.size() > 0:
		var cost := heap_cost[0]
		var node := heap_node[0]
		_heap_pop(heap_cost, heap_node)
		if cost > best[node]:
			continue
		for next in neighbours[node] as PackedInt32Array:
			if not _allowed(vertices[next], segment, hips_y):
				continue
			var candidate := cost + vertices[node].distance_to(vertices[next])
			if candidate < best[next]:
				best[next] = candidate
				_heap_push(heap_cost, heap_node, candidate, next)
	var result := PackedFloat32Array()
	result.resize(count)
	for v in count:
		result[v] = best[canonical[v]]
	return result


static func _heap_push(costs: PackedFloat32Array, nodes: PackedInt32Array, cost: float, node: int) -> void:
	costs.append(cost)
	nodes.append(node)
	var i := costs.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if costs[parent] <= costs[i]:
			break
		var tc := costs[parent]
		costs[parent] = costs[i]
		costs[i] = tc
		var tn := nodes[parent]
		nodes[parent] = nodes[i]
		nodes[i] = tn
		i = parent


static func _heap_pop(costs: PackedFloat32Array, nodes: PackedInt32Array) -> void:
	var last := costs.size() - 1
	costs[0] = costs[last]
	nodes[0] = nodes[last]
	costs.resize(last)
	nodes.resize(last)
	var i := 0
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var smallest := i
		if left < last and costs[left] < costs[smallest]:
			smallest = left
		if right < last and costs[right] < costs[smallest]:
			smallest = right
		if smallest == i:
			break
		var tc := costs[smallest]
		costs[smallest] = costs[i]
		costs[i] = tc
		var tn := nodes[smallest]
		nodes[smallest] = nodes[i]
		nodes[i] = tn
		i = smallest


func _allowed(vertex: Vector3, segment: Dictionary, hips_y: float) -> bool:
	var side := float(segment.side)
	if side > 0.0 and vertex.x < -0.025:
		return false
	if side < 0.0 and vertex.x > 0.025:
		return false
	if bool(segment.leg) and vertex.y > hips_y + 0.06:
		return false
	return true


static func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.000001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


# UV seams duplicate vertices; weld by position so paths cross seams.
# neighbours is indexed by canonical (welded) vertex.
func _welded_graph(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var weld := {}
	var canonical := PackedInt32Array()
	canonical.resize(vertices.size())
	for v in vertices.size():
		var key := Vector3i(roundi(vertices[v].x * 10000.0), roundi(vertices[v].y * 10000.0), roundi(vertices[v].z * 10000.0))
		if not weld.has(key):
			weld[key] = v
		canonical[v] = int(weld[key])
	var links := {}
	for t in range(0, indices.size(), 3):
		for k in 3:
			var a := canonical[indices[t + k]]
			var b := canonical[indices[t + (k + 1) % 3]]
			if a == b:
				continue
			if not links.has(a):
				links[a] = {}
			if not links.has(b):
				links[b] = {}
			links[a][b] = true
			links[b][a] = true
	var neighbours := []
	neighbours.resize(vertices.size())
	for v in vertices.size():
		var around := PackedInt32Array()
		if links.has(v):
			for n: int in links[v]:
				around.append(n)
		neighbours[v] = around
	return {"canonical": canonical, "neighbours": neighbours}


# Optional weight dump for offline inspection (set RIG_DEBUG_DIR).
func _debug_dump(enemy_name: String, vertices: PackedVector3Array, dense: Array, skeleton: Skeleton3D) -> void:
	var folder := OS.get_environment("RIG_DEBUG_DIR")
	if folder.is_empty():
		return
	var rows := []
	for v in vertices.size():
		var row: PackedFloat32Array = dense[v]
		var best := 0
		for b in row.size():
			if row[b] > row[best]:
				best = b
		rows.append([vertices[v].x, vertices[v].y, vertices[v].z, best, row[best]])
	var names := []
	for b in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(b))
	var file := FileAccess.open(folder.path_join(enemy_name + "_weights.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "bones": names}))


# ---------------------------------------------------------------- shared output

func _save_rig(enemy_name: String, skeleton: Skeleton3D, arrays: Array, dense: Array, library: AnimationLibrary) -> bool:
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(count * 4)
	weights.resize(count * 4)
	for v in count:
		var row: PackedFloat32Array = dense[v]
		var picks := []
		for b in row.size():
			if row[b] > 0.0:
				picks.append([row[b], b])
		picks.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
		picks = picks.slice(0, 4)
		var total := 0.0
		for pick: Array in picks:
			total += float(pick[0])
		for k in 4:
			if k < picks.size() and total > 0.0 and float(picks[k][0]) / total >= 0.02:
				bones[v * 4 + k] = int(picks[k][1])
				weights[v * 4 + k] = float(picks[k][0]) / total
		var kept := 0.0
		for k in 4:
			kept += weights[v * 4 + k]
		if kept <= 0.0:
			bones[v * 4] = 1
			weights[v * 4] = 1.0
		else:
			for k in 4:
				weights[v * 4 + k] /= kept
	var skinned := arrays.duplicate()
	skinned[Mesh.ARRAY_BONES] = bones
	skinned[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, skinned)
	mesh.resource_name = enemy_name + "_rig"
	var mesh_path := OUTPUT_DIR + enemy_name + "_rig_mesh.res"
	var library_path := OUTPUT_DIR + enemy_name + "_anims.res"
	if ResourceSaver.save(mesh, mesh_path) != OK or ResourceSaver.save(library, library_path) != OK:
		push_error("Cannot save rig resources for " + enemy_name)
		return false
	var skin := Skin.new()
	for index in skeleton.get_bone_count():
		skin.add_bind(index, skeleton.get_bone_global_rest(index).affine_inverse())
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.add_child(skeleton)
	skeleton.owner = visual
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = load(mesh_path)
	mesh_instance.skin = skin
	mesh_instance.skeleton = NodePath("..")
	var material := load(OUTPUT_DIR + enemy_name + "_game.tres") as Material
	if material != null:
		mesh_instance.set_surface_override_material(0, material)
	skeleton.add_child(mesh_instance)
	mesh_instance.owner = visual
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library(&"", load(library_path))
	visual.add_child(player)
	player.owner = visual
	var packed := PackedScene.new()
	packed.pack(visual)
	var scene_path := OUTPUT_DIR + enemy_name + "_rig.tscn"
	var error := ResourceSaver.save(packed, scene_path)
	visual.free()
	if error != OK:
		push_error("Cannot save %s: %d" % [scene_path, error])
		return false
	print("%s rig: %d bones, %d vertices -> %s" % [enemy_name, skin.get_bind_count(), count, scene_path])
	return true


# ---------------------------------------------------------------- horde

func _build_horde() -> bool:
	var source := load(OUTPUT_DIR + "Horde_game.res") as ArrayMesh
	if source == null:
		return false
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var author := HORDE_AUTHOR.new()
	var skeleton: Skeleton3D = author.build_skeleton(vertices)
	var dense: Array = author.weights(vertices, skeleton)
	var library: AnimationLibrary = author.build_library(skeleton)
	print("Horde: crawl %.2f m/s, ram %.2f m/s" % [author.crawl_speed(), author.ram_speed()])
	return _save_rig("Horde", skeleton, arrays, dense, library)
