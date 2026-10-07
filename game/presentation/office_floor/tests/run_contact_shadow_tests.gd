extends SceneTree
## Light contact shadows under furniture: floor-standing pieces get one,
## wall-mounted, small kickable and raised items do not; the shadow follows
## the prop, fades while it is lifted and hides with its visual.

const PROP_SCENE := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const MODELS := "res://models/objects/enviroments/"
const TABLE := MODELS + "07/07_table_longest.glb"
const CHAIR := MODELS + "06/06_simple_chair.glb"
const CLOCK := MODELS + "09/09_wall_clock.glb"
const MUG := MODELS + "09/09_mug.glb"
const CABINET := MODELS + "03/03_file_cabinet_smaller.glb"

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var table := _prop(stage, TABLE, Vector3.ZERO)
	var chair := _prop(stage, CHAIR, Vector3(3, 0, 0))
	var clock := _prop(stage, CLOCK, Vector3(6, 1.6, 0))
	var mug := _prop(stage, MUG, Vector3(8, 0, 0))
	var raised := _prop(stage, CABINET, Vector3(10, 0.8, 0))
	await process_frame
	_expect(_quad(table) != null and _quad(chair) != null, "Tables and chairs on the floor cast a contact shadow.")
	_expect(_quad(clock) == null, "Wall-mounted items cast none.")
	_expect(_quad(mug) == null, "Small kickable items cast none.")
	_expect(_quad(raised) == null, "Items standing above the floor cast none on it.")
	var quad := _quad(table)
	if quad == null:
		_finish(stage)
		return
	var half: Vector2 = quad.get_instance_shader_parameter(&"half_size")
	_expect(half.x > 1.0 or half.y > 1.0, "The shadow covers the long table's footprint (%s)." % half)
	_expect(absf(quad.global_position.y - 0.0165) < 0.005, "The shadow lies on the floor (%.4f)." % quad.global_position.y)
	var before := quad.global_position.z
	table.global_position += Vector3(0, 0, 2)
	await process_frame
	_expect(absf(quad.global_position.z - before - 2.0) < 0.05, "The shadow follows a moved table (%.2f m)." % (quad.global_position.z - before))
	table.global_position += Vector3(0, 1.0, 0)
	await process_frame
	_expect(float(quad.get_instance_shader_parameter(&"presence")) < 0.1, "A lifted table leaves its shadow behind faded.")
	table.global_position -= Vector3(0, 1.0, 0)
	await process_frame
	_expect(float(quad.get_instance_shader_parameter(&"presence")) > 0.9, "Back on the floor the shadow returns.")
	(table.get("_visual") as Node3D).hide()
	_expect(not quad.is_visible_in_tree(), "A broken (hidden) table takes its shadow with it.")
	_finish(stage)


func _finish(stage: Node3D) -> void:
	stage.queue_free()
	await process_frame
	print("Contact shadow tests: %d failure(s)." % failures)
	quit(failures)


func _prop(stage: Node3D, model: String, at: Vector3) -> RigidBody3D:
	var prop := PROP_SCENE.instantiate() as RigidBody3D
	prop.set("model_path", model)
	prop.position = at
	prop.freeze = true
	stage.add_child(prop)
	return prop


func _quad(prop: Node) -> MeshInstance3D:
	return prop.get_node_or_null("ContactShadow/ContactShadowQuad") as MeshInstance3D


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
