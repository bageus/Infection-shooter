extends SceneTree
## Breakable glass: bullets crack the pane 2-4 times before it shatters, the
## shards are irregular, and every shard falls from its own place in the
## pane (near the hit first, the rest crumbling after) — including the glass
## door, whose shards used to lie flat on the floor.

const SCENES := {
	"wall": "res://game/presentation/office_floor/public/structural/glass_wall_full.tscn",
	"half": "res://game/presentation/office_floor/public/structural/glass_partition_half.tscn",
	"blinds": "res://game/presentation/office_floor/public/structural/glass_partition_blinds.tscn",
	"door": "res://game/presentation/office_floor/public/structural/sliding_glass_door.tscn",
}

var failures := 0
var stage: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var x := 0.0
	for kind in SCENES:
		await _test_pane(kind, Vector3(x, 0, 0))
		x += 12.0
	stage.queue_free()
	await process_frame
	print("Glass crack tests: %d failure(s)." % failures)
	quit(failures)


func _test_pane(kind: String, at: Vector3) -> void:
	var effects := Node3D.new()
	stage.add_child(effects)
	var scene := (load(SCENES[kind]) as PackedScene).instantiate() as Node3D
	stage.add_child(scene)
	scene.global_position = at
	var glass := scene.get_node("GlassBody") as StaticBody3D
	glass.call("configure_world", effects, null)
	await physics_frame
	var pane := _pane_center(scene)
	var shards := _shards(scene)
	_expect(shards.size() >= 20, "%s: the pane is cut into many shards (%d)." % [kind, shards.size()])
	_expect(_irregular(shards), "%s: shards are uneven in size." % kind)
	var needed := int(glass.get("_cracks_needed"))
	_expect(needed >= 2 and needed <= 4, "%s: 2-4 cracks before shattering (%d)." % [kind, needed])
	for i in needed:
		var point := pane + Vector3(randf_range(-0.4, 0.4), randf_range(-0.5, 0.5), 0)
		glass.call("take_projectile_hit", 30.0, point, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	_expect(not bool(glass.get("_broken")) and int(glass.call("crack_count")) == needed, "%s: each hit leaves a crack, the pane holds." % kind)
	glass.call("take_projectile_hit", 30.0, pane, Vector3.BACK, Vector3.FORWARD, "PISTOL")
	_expect(bool(glass.get("_broken")), "%s: the hit after the last crack shatters the pane." % kind)
	_expect(int(glass.call("crack_count")) == 0, "%s: cracks go with the glass." % kind)
	await physics_frame
	var first := _fragments(effects)
	_expect(not first.is_empty() and first.size() < shards.size(), "%s: shards near the hit burst out first (%d of %d)." % [kind, first.size(), shards.size()])
	# Fragments start where their shard was, spread over the pane, not on one spot.
	var spread := _spread(first + _waiting_centers(shards))
	_expect(spread > 0.45, "%s: shards fall from their own places across the pane (spread %.2f m)." % [kind, spread])
	_expect(_mean_height(shards) > 0.8, "%s: the shards are up in the frame, not lying on the floor." % kind)
	await create_timer(1.4).timeout
	var all := _fragments(effects)
	var still := shards.filter(func(s: MeshInstance3D) -> bool: return is_instance_valid(s) and s.is_visible_in_tree()).size()
	_expect(still == 0, "%s: the rest of the glass crumbles away (%d left)." % [kind, still])
	_expect(all.size() >= mini(shards.size(), 40) - 2, "%s: every shard became a falling piece (%d)." % [kind, all.size()])
	for child in effects.get_children():
		child.queue_free()
	scene.queue_free()
	effects.queue_free()
	await process_frame


func _shards(scene: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for node in scene.find_children("GlassShard_*", "MeshInstance3D", true, false):
		out.append(node as MeshInstance3D)
	return out


func _pane_center(scene: Node3D) -> Vector3:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if "glass" in mesh.name.to_lower() and mesh.is_visible_in_tree() and absf(mesh.global_basis.determinant()) > 1e-9:
			return (mesh.global_transform * mesh.get_aabb()).get_center()
	return scene.global_position + Vector3.UP * 1.4


func _irregular(shards: Array[MeshInstance3D]) -> bool:
	var areas: Array[float] = []
	for shard in shards:
		var size := shard.get_aabb().size
		var sorted := [size.x, size.y, size.z]
		sorted.sort()
		areas.append(sorted[1] * sorted[2])
	areas.sort()
	return areas.size() > 4 and areas[-1] > areas[0] * 6.0


func _fragments(effects: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for child in effects.get_children():
		if str(child.name).begins_with("Fragment_"):
			out.append((child as Node3D).global_position)
	return out


func _waiting_centers(shards: Array[MeshInstance3D]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for shard in shards:
		if is_instance_valid(shard) and shard.is_visible_in_tree():
			out.append((shard.global_transform * shard.get_aabb()).get_center())
	return out


func _spread(points: Array[Vector3]) -> float:
	if points.size() < 2:
		return 0.0
	var mean := Vector3.ZERO
	for p in points:
		mean += p
	mean /= points.size()
	var total := 0.0
	for p in points:
		total += p.distance_to(mean)
	return total / points.size()


func _mean_height(shards: Array[MeshInstance3D]) -> float:
	var sum := 0.0
	for shard in shards:
		sum += (shard.global_transform * shard.get_aabb()).get_center().y
	return sum / maxf(1.0, shards.size())


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
