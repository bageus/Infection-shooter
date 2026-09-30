extends RefCounted

# Mission composition only: explicit collaborators, no global context or lookup API.
var _container: Node3D
var _impacts: Node
var _player: Node3D
var _drop_weapon: Callable


func _init(container: Node3D, impacts: Node, player: Node3D, drop_weapon: Callable) -> void:
	_container = container
	_impacts = impacts
	_player = player
	_drop_weapon = drop_weapon


func bind_scene(node: Node) -> void:
	if node.has_method("configure_weapon_drop"):
		node.call("configure_weapon_drop", _drop_weapon)
	if node.has_method("configure_player"):
		node.call("configure_player", _player)
	if node.has_method("configure_world"):
		node.call("configure_world", _container, _impacts)
		return # Public root forwards dependencies to its own local components.
	for child in node.get_children():
		bind_scene(child)
