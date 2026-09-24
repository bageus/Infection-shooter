extends Node3D

const PIECE_SCRIPT = preload("res://game/presentation/office_floor/table_piece.gd")
const LEG_IDS := ["Leg_BL", "Leg_BR", "Leg_FL", "Leg_FR"]
const WOOD_MARKS := [
	preload("res://models/objects/textures/Splintered Wood Fracture Decal.png"),
	preload("res://models/objects/textures/Flat tan wood scuff decal.png")
]

@export var fragment_impulse := 1.8
@export var fragment_lifetime := 24.0

var _intact: Node3D
var _modular: Node3D
var _fragments: Node3D
var _secondary: Node3D
var _parts: Dictionary = {}
var _active: Dictionary = {}
var _started := false


func _ready() -> void:
	var visual := get_node("Visual")
	_intact = _find(visual, "Intact")
	_modular = _find(visual, "Modular")
	_fragments = _find(visual, "Fragments")
	_secondary = _find(visual, "TopSecondary")
	if _intact == null or _modular == null or _fragments == null or _secondary == null:
		push_error("07_table.glb is missing a destruction group")
		return
	_modular.hide()
	_fragments.hide()
	_secondary.hide()
	for group in [_modular, _fragments, _secondary]:
		_collect_parts(group)
	for name in ["Top"] + LEG_IDS:
		_add_modular_body(name)


func hit_piece(name: String, hit_position: Vector3, direction: Vector3) -> void:
	if not _active.has(name):
		return
	if not _started:
		_started = true
		_intact.hide()
		_modular.show()
		return
	var body: RigidBody3D = _active[name]
	_active.erase(name)
	call_deferred("_transition_piece", name, body, hit_position, direction)


func _transition_piece(name: String, body: RigidBody3D, hit_position: Vector3, direction: Vector3) -> void:
	var original: MeshInstance3D = _parts[name]
	var original_transform := original.global_transform
	var current_transform := body.global_transform
	body.queue_free()
	original.hide()
	if name == "Top":
		for index in range(1, 9):
			_spawn_piece("Top_%02d" % index, original_transform, current_transform, hit_position, direction, false)
	elif name.begins_with("Leg_"):
		_spawn_piece(name + "_lower", original_transform, current_transform, hit_position, direction, true)
		_spawn_piece(name + "_upper", original_transform, current_transform, hit_position, direction, true)
	elif name.begins_with("Top_"):
		_spawn_piece(name + "_A", original_transform, current_transform, hit_position, direction, true)
		_spawn_piece(name + "_B", original_transform, current_transform, hit_position, direction, true)


func _add_modular_body(name: String) -> void:
	var mesh: MeshInstance3D = _parts.get(name)
	if mesh == null:
		push_error("07_table.glb is missing modular part " + name)
		return
	var body := _make_body(mesh, name, false)
	add_child(body)
	body.global_transform = mesh.global_transform
	_active[name] = body


func _spawn_piece(name: String, original: Transform3D, current: Transform3D, hit_position: Vector3, direction: Vector3, final_stage: bool) -> void:
	var mesh: MeshInstance3D = _parts.get(name)
	if mesh == null:
		push_error("07_table.glb is missing fragment " + name)
		return
	var target := current * original.affine_inverse() * mesh.global_transform
	var body := _make_body(mesh, name, final_stage)
	get_parent().add_child(body)
	body.global_transform = target
	var copy := mesh.duplicate() as MeshInstance3D
	body.add_child(copy)
	copy.transform = Transform3D.IDENTITY
	copy.show()
	_active[name] = body
	_add_fracture_marks(body, mesh, hit_position)
	var offset := body.global_position - hit_position
	var away := (direction.normalized() + offset.normalized() * 0.5 + Vector3.UP * 0.5).normalized()
	body.apply_impulse(away * fragment_impulse, hit_position - body.global_position)
	get_tree().create_timer(fragment_lifetime if final_stage else fragment_lifetime * 2.0).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.queue_free()
	)


func _add_fracture_marks(body: RigidBody3D, mesh: MeshInstance3D, hit_position: Vector3) -> void:
	var tint := Color.WHITE
	if mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material != null:
			tint = material.albedo_color
	var normal := (body.global_position - hit_position).normalized()
	if normal.is_zero_approx():
		normal = Vector3.UP
	for index in 2:
		var mark := Decal.new()
		mark.texture_albedo = WOOD_MARKS[randi() % WOOD_MARKS.size()]
		mark.size = Vector3(0.18, 0.08, 0.18) * randf_range(0.7, 1.2)
		mark.modulate = tint.lerp(Color.WHITE, 0.25)
		body.add_child(mark)
		mark.global_position = body.global_position + normal * 0.02 + Vector3.UP * float(index) * 0.025
		mark.global_basis = Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, randf() * TAU)


func _make_body(mesh: MeshInstance3D, name: String, final_stage: bool) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.set_script(PIECE_SCRIPT)
	body.name = name
	body.set("table", self)
	body.set("piece_id", name)
	body.set("last_stage", final_stage)
	body.mass = 1.0 if name.begins_with("Top") else 0.4
	body.freeze = name == "Top" or name in LEG_IDS
	body.collision_layer = 1
	body.collision_mask = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bounds := mesh.get_aabb()
	box.size = bounds.size
	shape.shape = box
	shape.position = bounds.get_center()
	body.add_child(shape)
	return body


func _collect_parts(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			_parts[child.name] = child
		_collect_parts(child)


func _find(node: Node, name: String) -> Node3D:
	if node.name == name:
		return node as Node3D
	for child in node.get_children():
		var result := _find(child, name)
		if result != null:
			return result
	return null
