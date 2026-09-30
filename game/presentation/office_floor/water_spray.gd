extends RefCounted

const VIEW := preload("res://game/presentation/office_floor/water_spray_view.gd")


static func spawn(host: Node3D, outlet: Vector3, reverse_direction: bool = false) -> void:
	var scene := host.get("effects_root") as Node3D
	if not is_instance_valid(scene):
		return
	var spray := VIEW.new() as Node3D
	spray.call("configure", host, outlet, reverse_direction)
	scene.add_child(spray)
