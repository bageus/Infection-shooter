extends RefCounted
## Bootstrap composition receives the exact completion voice; no service lookup.
static func show_main(tree: SceneTree, previous: Node, completion: Node = null) -> void:
	if is_instance_valid(completion):
		completion.call("to_main")
	var front := preload("res://game/bootstrap/app/menu/front_end.tscn").instantiate()
	front.set("completion_music", completion)
	tree.paused = false
	tree.root.add_child(front)
	tree.current_scene = front
	if is_instance_valid(previous):
		previous.queue_free()
