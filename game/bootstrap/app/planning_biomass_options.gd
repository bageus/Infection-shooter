extends Node
## Planner panel in the dedicated Biomass palette (ADR-0062): an amount slider and an
## "Apply biomass" button. Applying lays a procedural network of biomass decals
## across the floor that joins every spawn hole (biomass_generator.gd); it
## replaces the network applied before in this session and is one undo step.

const GENERATOR := preload("res://game/bootstrap/app/biomass_generator.gd")
const TILT := preload("res://game/bootstrap/app/planning_tilt.gd")
const BLOOD_SCENE := "res://game/presentation/office_floor/public/props/blood_decal.tscn"
const HOLE_GROUP := &"enemy_spawn_points"
const TAG := &"planning_biomass_generated"
## Solid ground probe: a box above the floor, so the floor itself is never hit.
const PROBE_SIZE := Vector3(0.45, 1.1, 0.45)
const PROBE_LIFT := 0.3
const WORLD_MASK := 1

var session: Variant
var panel: VBoxContainer
var amount: HSlider
var readout: Label
var apply_button: Button


## Anchor sets the insertion point; the palette owner controls visibility.
func setup(context: Variant, anchor: Control) -> void:
	session = context
	panel = VBoxContainer.new()
	panel.name = "BiomassGenerator"
	var title := Label.new()
	title.text = "Procedural biomass"
	panel.add_child(title)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var label := Label.new()
	label.text = "Amount"
	row.add_child(label)
	amount = HSlider.new()
	amount.name = "BiomassAmount"
	amount.min_value = 5.0
	amount.max_value = 100.0
	amount.step = 5.0
	amount.value = 40.0
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.custom_minimum_size.x = 140.0
	amount.value_changed.connect(_amount_changed)
	row.add_child(amount)
	readout = Label.new()
	row.add_child(readout)
	apply_button = Button.new()
	apply_button.name = "ApplyBiomass"
	apply_button.text = "Apply biomass"
	apply_button.tooltip_text = "Joins every spawn hole with winding biomass; replaces the previous procedural biomass"
	apply_button.pressed.connect(apply)
	panel.add_child(apply_button)
	var box: Node = anchor.get_parent()
	box.add_child(panel)
	box.move_child(panel, anchor.get_index() + 1)
	panel.visible = anchor.visible
	_amount_changed(amount.value)


func _amount_changed(value: float) -> void:
	readout.text = "%d%%" % int(value)


## Lays a new network (or tells why it cannot). Returns the pieces placed.
func apply(seed_value: int = 0) -> Array[Node3D]:
	var floor_view: Node3D = session.host.get_node_or_null("Floor")
	var holes := _holes()
	if floor_view == null or not floor_view.get("floor_size") is Vector2:
		_say("No floor to lay biomass on")
		return []
	if holes.is_empty():
		_say("Place at least one spawn hole first (Enemies tab)")
		return []
	var size: Vector2 = floor_view.get("floor_size")
	var level := Rect2(Vector2(floor_view.global_position.x, floor_view.global_position.z) - size * 0.5, size)
	var floor_y := floor_view.global_position.y + float(floor_view.get("tile_y")) + 0.0125
	_clear_previous()
	var plan := GENERATOR.plan(level, holes, _solid_probe(floor_y), amount.value / 100.0, seed_value if seed_value != 0 else randi_range(1, 2147483646))
	var nodes: Array[Node3D] = []
	for piece in plan:
		var node := _place(piece, floor_y)
		if node != null:
			nodes.append(node)
	if not nodes.is_empty():
		session.edit_history.call("record_added_group", nodes)
	session.call("_update_status")
	_say("Biomass applied: %d pieces joining %d spawn holes" % [nodes.size(), holes.size()])
	return nodes


func _say(text: String) -> void:
	session.controls.status.text = text


func _holes() -> Array[Vector2]:
	var holes: Array[Vector2] = []
	for point in get_tree().get_nodes_in_group(HOLE_GROUP):
		var hole := point as Node3D
		if hole != null and hole.is_inside_tree() and not hole.is_queued_for_deletion() and session.root.is_ancestor_of(hole):
			holes.append(Vector2(hole.global_position.x, hole.global_position.z))
	return holes


func _clear_previous() -> void:
	for node: Node3D in session.placed.duplicate():
		if is_instance_valid(node) and node.has_meta(TAG):
			session.placed.erase(node)
			node.queue_free()


func _place(piece: Dictionary, floor_y: float) -> Node3D:
	var node: Node3D = session.call("_instantiate_asset", BLOOD_SCENE)
	if node == null:
		return null
	node.call("configure_blood", str(piece["texture"]), "floor")
	node.scale = Vector3.ONE * float(piece["scale"])
	session.root.add_child(node)
	var at: Vector2 = piece["position"]
	node.position = Vector3(at.x, floor_y, at.y)
	TILT.write(node, float(piece["yaw"]), Basis.IDENTITY)
	node.set_meta("planning_scene_path", BLOOD_SCENE)
	node.set_meta(TAG, true)
	session.placed.append(node)
	return node


# True where a wall or piece of furniture stands at a floor point. The holes
# themselves and moving characters do not count.
func _solid_probe(floor_y: float) -> Callable:
	var space: PhysicsDirectSpaceState3D = session.root.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = PROBE_SIZE
	return func(point: Vector2) -> bool:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, floor_y + PROBE_LIFT + PROBE_SIZE.y * 0.5, point.y))
		query.collision_mask = WORLD_MASK
		for hit in space.intersect_shape(query, 8):
			if not _ignored(hit["collider"] as Node):
				return true
		return false


func _ignored(collider: Node) -> bool:
	var node := collider
	while node != null:
		if node is CharacterBody3D or node.is_in_group(HOLE_GROUP):
			return true
		node = node.get_parent()
	return false
