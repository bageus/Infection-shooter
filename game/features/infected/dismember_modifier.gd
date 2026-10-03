extends SkeletonModifier3D
## Collapses severed bones to their joint after animation (ADR-0017).
## Children inherit the zero scale, so the whole limb disappears and the
## partially weighted skin around the joint closes into a stump.

var severed := PackedInt32Array()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for bone in severed:
		skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.0005)
