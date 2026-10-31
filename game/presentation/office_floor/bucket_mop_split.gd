extends RefCounted
## A bucket with a mop comes apart on its first hit or touch: the mop becomes its own prop.
const FILE := "09_bucket_with_mop.glb"
const MOP_MODEL := "res://models/objects/enviroments/09/09_mop.glb"
const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")


static func split(prop: Node3D, direction: Vector3) -> void:
	if prop.has_meta(&"mop_split") or not prop.is_inside_tree() or prop.get("model_path").get_file() != FILE:
		return
	var mop_mesh := DAMAGE.find_named(prop.get("_visual"), "Mop") as Node3D
	if mop_mesh == null:
		return
	prop.set_meta(&"mop_split", true)
	mop_mesh.hide()
	# Shapes and new bodies change outside the physics callback that reported the contact.
	_finish.bind(prop, mop_mesh.global_transform, direction).call_deferred()


static func _finish(prop: Node3D, mop_transform: Transform3D, direction: Vector3) -> void:
	if not is_instance_valid(prop) or not prop.is_inside_tree():
		return
	prop.call("_rebuild_shapes")
	var mop = prop.get_script().new()
	mop.model_path = MOP_MODEL
	var effects = prop.get("effects_root")
	mop.configure_world(effects, prop.get("impact_pool"))
	var floor_view = prop.get("glass_debris_floor")
	if is_instance_valid(floor_view):
		mop.configure_glass_debris(floor_view)
	var world: Node = effects if is_instance_valid(effects) else prop.get_parent()
	world.add_child(mop)
	mop.global_transform = mop_transform
	mop.apply_central_impulse((direction.normalized() + Vector3.UP * 0.3).normalized() * maxf(0.5, mop.mass * 0.12))
