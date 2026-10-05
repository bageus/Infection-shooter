extends Node
## Legacy planner lifecycle adapter; Godot handles view-frustum render culling.
var player: Node3D
var roots: Array = []
var enabled := false


func setup(target: Node3D, managed_roots: Array) -> void:
	player = target
	roots = managed_roots
	rebuild()


func rebuild() -> void:
	for branch: Node in roots:
		if not is_instance_valid(branch):
			continue
		for child in branch.get_children():
			if child is Node3D:
				(child as Node3D).visible = true
				if child.process_mode == Node.PROCESS_MODE_DISABLED:
					child.process_mode = Node.PROCESS_MODE_INHERIT


func set_runtime_enabled(_value: bool) -> void:
	enabled = false
	rebuild()
