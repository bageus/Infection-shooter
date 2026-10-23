extends Node3D
## Registers this exterior window with the shared skirt mesh that draws the building below it,
## down to the city ground, so the office does not hang above the backdrop.

const SKIRT := preload("res://game/presentation/office_floor/exterior_facade_skirt.gd")

var _skirt: Node


func _ready() -> void:
	call_deferred("_register")


func _exit_tree() -> void:
	if is_instance_valid(_skirt) and get_parent() != null:
		_skirt.call("remove_window", get_parent())


func _register() -> void:
	var window := get_parent() as Node3D
	var host := window.get_parent() if window != null else null
	if host == null:
		return
	_skirt = host.get_node_or_null("ExteriorFacadeSkirt")
	if _skirt == null:
		_skirt = SKIRT.new()
		host.add_child(_skirt)
	_skirt.call("add_window", window)
