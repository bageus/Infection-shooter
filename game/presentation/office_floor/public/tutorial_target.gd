extends RefCounted
## Planner "tutorial target" flag for bottles, loot crates, fire extinguishers and doors:
## a red-orange target ring with a small 3D arrow floats above the flagged object until it is broken.

const GROUP := &"tutorial_target"
const META := &"planning_tutorial_target"
const MARKER_NAME := "TutorialTargetMarker"
const COLOR := Color("ff5a1f")
const Marker := preload("res://game/presentation/office_floor/tutorial_target_marker.gd")


## "bottle", "crate", "extinguisher", "door", or "" when the object cannot be a target.
static func kind_of(node: Node) -> String:
	if node == null:
		return ""
	var file := str(node.get("model_path")).get_file().to_lower()
	if "fire_extinguisher" in file:
		return "extinguisher"
	if "water_bottle" in file:
		return "bottle"
	if "crate" in file:
		return "crate"
	var controller := node.get_node_or_null("DoorController")
	if controller != null and controller.has_method("is_lockable") and bool(controller.call("is_lockable")):
		return "door"
	return ""


static func applies_to(node: Node) -> bool:
	return not kind_of(node).is_empty()


static func is_target(node: Node) -> bool:
	return node != null and bool(node.get_meta(META, false))


## Flags or unflags the object; the marker is built once the object is inside the tree.
static func configure(node: Node3D, enabled: bool) -> void:
	if not applies_to(node):
		return
	if enabled:
		node.set_meta(META, true)
		node.add_to_group(GROUP, true) # persistent: a baked scene keeps the flag
	else:
		node.remove_meta(META)
		node.remove_from_group(GROUP)
	var old := node.get_node_or_null(MARKER_NAME)
	if old != null:
		old.free()
	if enabled:
		var marker := Marker.new()
		marker.name = MARKER_NAME
		node.add_child(marker)
		marker.owner = node.owner # saved with a baked scene


## Maps baked before the flag was persistent still carry its meta: flag those objects again.
static func adopt_baked(tree: SceneTree) -> void:
	for node: Node in tree.root.find_children("*", "Node3D", true, false):
		if node.has_meta(META) and not node.is_in_group(GROUP):
			configure(node as Node3D, true)


## A target is finished once the object is gone or has been broken, shattered or burst.
static func is_standing(node: Node) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	var damage: Variant = node.get("_damage")
	if damage == null:
		return true
	return not (bool(damage.broken) or bool(damage.glass_broken) or bool(damage.extinguisher_triggered)
			or bool(damage.transition_pending) or int(damage.variant_index) >= 0)


## Flagged objects of one kind that are still intact.
static func standing(tree: SceneTree, kind: String) -> Array[Node]:
	var found: Array[Node] = []
	for node in tree.get_nodes_in_group(GROUP):
		if kind_of(node) == kind and is_standing(node):
			found.append(node)
	return found
