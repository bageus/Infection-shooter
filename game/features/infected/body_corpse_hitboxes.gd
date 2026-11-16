extends RefCounted
## Bullet-only hit volumes on the parts of a corpse (split out of body_parts.gd).

const HITBOX := preload("res://game/features/infected/body_part_hitbox.gd")


static func enable(owner: Node) -> void:
	var parts: Dictionary = owner.parts
	var skeleton: Skeleton3D = owner.skeleton
	var hitboxes: Dictionary = owner._hitboxes
	if not owner.enabled:
		return
	for part: StringName in parts:
		if bool(parts[part].severed) or hitboxes.has(part):
			continue
		var nodes: Array = []
		for segment: Dictionary in parts[part].segments:
			var bone: int = segment.bone
			var attachment := BoneAttachment3D.new()
			attachment.name = "Hitbox_" + skeleton.get_bone_name(bone)
			attachment.bone_idx = bone
			skeleton.add_child(attachment)
			var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			var to_local := bone_world.affine_inverse()
			var start: Vector3 = to_local * owner._world(bone, segment.start)
			var finish: Vector3 = to_local * owner._world(bone, segment.end)
			var hitbox := HITBOX.new()
			hitbox.transform = Transform3D(even_out(bone_world.basis), Vector3.ZERO)
			hitbox.parts = owner
			hitbox.part = part
			var shape_node := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			var span := start.distance_to(finish)
			capsule.radius = maxf(float(segment.radius), 0.03)
			capsule.height = span + capsule.radius * 2.0
			shape_node.shape = capsule
			var axis := (finish - start).normalized() if span > 0.001 else Vector3.UP
			shape_node.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), (start + finish) * 0.5)
			hitbox.add_child(shape_node)
			attachment.add_child(hitbox)
			nodes.append(attachment)
		hitboxes[part] = nodes
	# Animation changes bone scale after setup; keep each body uniform or Jolt rejects it.
	if not skeleton.has_meta(&"corpse_hitbox_scales"):
		skeleton.set_meta(&"corpse_hitbox_scales", true)
		skeleton.skeleton_updated.connect(refresh_scales.bind(skeleton, hitboxes))


static func refresh_scales(skeleton: Skeleton3D, hitboxes: Dictionary) -> void:
	if not skeleton.is_inside_tree():
		return # global transforms are invalid outside the tree (planning builds bodies off-tree)
	for part: StringName in hitboxes:
		for node: Node in hitboxes[part]:
			if not is_instance_valid(node) or node.get_child_count() == 0:
				continue
			var attachment := node as BoneAttachment3D
			var hitbox := attachment.get_child(0) as Node3D
			var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(attachment.bone_idx)
			var target := even_out(bone_world.basis)
			if not hitbox.transform.basis.is_equal_approx(target):
				hitbox.transform = Transform3D(target, Vector3.ZERO)


# Jolt rejects a non-uniform scale on a body; bone scale is slightly uneven, so even it out.
static func even_out(bone_basis: Basis) -> Basis:
	var bone_scale := bone_basis.get_scale()
	var even := (bone_scale.x + bone_scale.y + bone_scale.z) / 3.0
	if even <= 0.001:
		return Basis()
	return Basis.from_scale(Vector3(even / maxf(bone_scale.x, 0.001), even / maxf(bone_scale.y, 0.001), even / maxf(bone_scale.z, 0.001)))
