extends SceneTree
## How flat each enemy stands: heel and toe heights of both feet while Idle and Walk play.
##   godot --headless --path . --script res://tools/measure_enemy_feet.gd [-- Hunger Brute ...]
## Loads the body like the anim viewer (catalog load_body), skins the shin-and-foot parts on the CPU
## and splits each sole into its back (heel) and front (toe) third by the rest pose. Prints, per clip,
## how close the heel and the toes of each foot come to the rest floor over the clip. A foot standing
## on its toes keeps its heel several cm up; a floating foot keeps its toes up too.
const CATALOG := preload("res://game/bootstrap/app/enemy_anim_viewer/enemy_anim_catalog.gd")
const SEAMS := preload("res://tools/measure_enemy_seams.gd")
const NAMES := ["Hunger", "Revenant", "Brute", "Titan", "Colossus"]
const CLIPS := ["Idle", "Walk"]
const FRAMES := 16
## Heel and toes each reach the floor within this (crouched zombie walks keep the heel 2-3 cm up); on
## 17.11.2026 Titan and Colossus stood 4-5 cm on their toes in Idle and 13 cm in Walk.
const MAX_LIFT := 0.04


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var only := OS.get_cmdline_user_args()
	var worst := 0.0
	for enemy: String in NAMES:
		if only.is_empty() or only.has(enemy):
			worst = maxf(worst, _measure(enemy))
	print("worst foot lift: %.1f mm" % (worst * 1000.0))
	quit(1 if worst > MAX_LIFT else 0)


func _measure(enemy: String) -> float:
	var body := CATALOG.load_body("res://game/features/infected/public/infected_%s.tscn" % enemy.to_lower())
	root.add_child(body)
	var player := CATALOG.find_player(body)
	var mesh_instance := body.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skeleton := mesh_instance.get_node(mesh_instance.skeleton) as Skeleton3D
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var game := load("res://models/objects/characters/enemy/game/%s_game.res" % enemy) as ArrayMesh
	var colors: PackedColorArray = game.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var ids := {}
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://models/objects/characters/enemy/game/%s_parts.json" % enemy)).parts:
		ids[entry.name] = int(entry.id)
	var feet := {}
	var floor_y := INF
	for side in ["L", "R"]:
		var id: int = ids["Shin_Foot_" + side]
		var low := INF
		for v in rest.size():
			if roundi(colors[v].r * 32.0) == id:
				low = minf(low, rest[v].y)
		var sole := PackedInt32Array()
		var back := INF
		var front := -INF
		for v in rest.size():
			if roundi(colors[v].r * 32.0) == id and rest[v].y < low + 0.06:
				sole.append(v)
				back = minf(back, rest[v].z)
				front = maxf(front, rest[v].z)
		var heel := PackedInt32Array()
		var toe := PackedInt32Array()
		for v in sole:
			if rest[v].z < lerpf(back, front, 0.33):
				heel.append(v)
			elif rest[v].z > lerpf(back, front, 0.67):
				toe.append(v)
		feet[side] = [heel, toe]
		floor_y = minf(floor_y, low)
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var at_rest := SEAMS._skinned(rest, arrays[Mesh.ARRAY_BONES], arrays[Mesh.ARRAY_WEIGHTS], skeleton, mesh_instance.skin)
	var line := enemy + ": rest heel %+.0f mm" % ((_lowest(at_rest, feet["L"][0]) - floor_y) * 1000.0)
	var worst := 0.0
	for clip: String in CLIPS:
		var length := player.get_animation(clip).length
		for side: String in feet:
			var samples := []
			for i in FRAMES:
				player.play(clip)
				player.seek(length * float(i) / FRAMES, true)
				skeleton.force_update_all_bone_transforms()
				var posed := SEAMS._skinned(rest, arrays[Mesh.ARRAY_BONES], arrays[Mesh.ARRAY_WEIGHTS], skeleton, mesh_instance.skin)
				samples.append([_lowest(posed, feet[side][0]), _lowest(posed, feet[side][1])])
			# Lowest each end of the sole gets over the clip, above the rest floor: a planted heel
			# comes down to ~0 at least once; the toes too, or the foot floats.
			var heel_lift := INF
			var toe_lift := INF
			for sample: Array in samples:
				heel_lift = minf(heel_lift, sample[0] - floor_y)
				toe_lift = minf(toe_lift, sample[1] - floor_y)
			worst = maxf(worst, maxf(heel_lift, toe_lift))
			line += "  %s %s heel %+.0f toe %+.0f mm" % [clip, side, heel_lift * 1000.0, toe_lift * 1000.0]
	print(line)
	body.queue_free()
	return worst


static func _lowest(positions: PackedVector3Array, vertices: PackedInt32Array) -> float:
	var low := INF
	for v in vertices:
		low = minf(low, positions[v].y)
	return low
