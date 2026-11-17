extends SceneTree
## Measures how far the whole-enemy skin tears open at the part joints while clips play.
##   godot --headless --path . --script res://tools/measure_enemy_seams.gd [-- Hunger Brute ...]
## Loads each enemy body the way the anim viewer and the game do (catalog load_body: rig mesh,
## skin surface only, Mixamo clips merged), skins the vertices on the CPU at several poses and,
## for every open (rim) vertex of a part, finds the distance to the nearest rim edge of another
## part. A watertight body keeps that distance near zero in every pose. Prints the worst gap per
## enemy and the clip/time it happens in; exits 1 when a gap exceeds MAX_GAP (before the seam
## weights of 17.11.2026 the worst gaps were 98-297 mm; the source parts already sit up to 4 mm apart).
const CATALOG := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_catalog.gd")
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus"]
const CLIPS := ["Idle", "Walk", "Run", "AttackLeft", "AttackRight", "Scream", "Agonize", "Death"]
const TIMES := [0.15, 0.4, 0.65, 0.9]
## Rim vertices farther than this from every other part in the rest pose are not at a joint.
const REST_REACH := 0.004
const MAX_GAP := 0.01


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var only := OS.get_cmdline_user_args()
	var worst_all := 0.0
	for enemy: String in NAMES:
		if not only.is_empty() and not only.has(enemy):
			continue
		worst_all = maxf(worst_all, _measure(enemy))
	print("worst gap of all enemies: %.1f mm" % (worst_all * 1000.0))
	quit(1 if worst_all > MAX_GAP else 0)


func _measure(enemy: String) -> float:
	var body := CATALOG.load_body("res://game/features/infected/public/infected_%s.tscn" % enemy.to_lower())
	root.add_child(body)
	var player := CATALOG.find_player(body)
	var mesh_instance := body.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skeleton := mesh_instance.get_node(mesh_instance.skeleton) as Skeleton3D
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Same vertex order as the game mesh, whose vertex colour holds the part id.
	var game := load("res://models/objects/characters/enemy/game/%s_game.res" % enemy) as ArrayMesh
	var colors: PackedColorArray = game.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var part := PackedInt32Array()
	part.resize(colors.size())
	for v in colors.size():
		part[v] = roundi(colors[v].r * 32.0)
	var topology := _rims(rest, indices, part)
	var rim_vertices: PackedInt32Array = topology.vertices
	var component: PackedInt32Array = topology.component
	var edges: Array = topology.edges
	# Only rim vertices that touch another part in the rest pose are joint rims.
	var joint := PackedInt32Array()
	for v in rim_vertices:
		if _nearest(rest, v, edges, component) < REST_REACH:
			joint.append(v)
	var skin := mesh_instance.skin
	var worst := 0.0
	var worst_at := "rest"
	var rest_worst := 0.0
	for v in joint:
		rest_worst = maxf(rest_worst, _nearest(rest, v, edges, component))
	for clip: String in CLIPS:
		if not player.has_animation(clip):
			continue
		var length := player.get_animation(clip).length
		for t: float in TIMES:
			player.play(clip)
			player.seek(length * t, true)
			skeleton.force_update_all_bone_transforms()
			var posed := _skinned(rest, bones, weights, skeleton, skin)
			for v in joint:
				var gap := _nearest(posed, v, edges, component)
				if gap > worst:
					worst = gap
					worst_at = "%s @ %.2f, part %d at %s" % [clip, t, component[v], rest[v]]
	print("%s: %d joint rim vertices, rest gap %.1f mm, worst posed gap %.1f mm (%s)" % [enemy, joint.size(), rest_worst * 1000.0, worst * 1000.0, worst_at])
	body.queue_free()
	return worst


static func _skinned(rest: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array, skeleton: Skeleton3D, skin: Skin) -> PackedVector3Array:
	var matrices: Array[Transform3D] = []
	for b in skin.get_bind_count():
		matrices.append(skeleton.get_bone_global_pose(skin.get_bind_bone(b)) * skin.get_bind_pose(b))
	var per := bones.size() / rest.size()
	var out := PackedVector3Array()
	out.resize(rest.size())
	for v in rest.size():
		var p := Vector3.ZERO
		for k in per:
			var w := weights[v * per + k]
			if w > 0.0:
				p += (matrices[bones[v * per + k]] * rest[v]) * w
		out[v] = p
	return out


# Rim edges (used by one triangle) of the skin, position-welded within each part.
static func _rims(rest: PackedVector3Array, indices: PackedInt32Array, part: PackedInt32Array) -> Dictionary:
	var canonical := PackedInt32Array()
	canonical.resize(rest.size())
	var first := {}
	for v in rest.size():
		var p := (rest[v] * 100000.0).round()
		var key := Vector4i(int(p.x), int(p.y), int(p.z), part[v])
		if not first.has(key):
			first[key] = v
		canonical[v] = int(first[key])
	var edge_count := {}
	for t in range(0, indices.size(), 3):
		for k in 3:
			var ca := canonical[indices[t + k]]
			var cb := canonical[indices[t + (k + 1) % 3]]
			var edge := Vector2i(mini(ca, cb), maxi(ca, cb))
			edge_count[edge] = int(edge_count.get(edge, 0)) + 1
	var edges: Array = []
	var seen := {}
	for edge: Vector2i in edge_count:
		if edge_count[edge] == 1:
			edges.append(edge)
			seen[edge.x] = true
			seen[edge.y] = true
	return {"vertices": PackedInt32Array(seen.keys()), "component": part, "edges": edges}


# Distance from vertex v to the nearest rim edge of another connected part, at the given positions.
static func _nearest(positions: PackedVector3Array, v: int, edges: Array, component: PackedInt32Array) -> float:
	var best := INF
	var p := positions[v]
	var own := component[v]
	for edge: Vector2i in edges:
		if component[edge.x] == own:
			continue
		var a := positions[edge.x]
		var ab := positions[edge.y] - a
		var spot := a + ab * clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, p.distance_squared_to(spot))
	return sqrt(best)
