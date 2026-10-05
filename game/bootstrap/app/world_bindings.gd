extends RefCounted

# Mission composition only: explicit collaborators, no global context or lookup API.
var _container: Node3D
var _impacts: Node
var _player: Node3D
var _drop_weapon: Callable
var _particle_targets: Array[WeakRef] = []
var _electronic_particles := true
var _displays: Node


func _init(container: Node3D, impacts: Node, player: Node3D, drop_weapon: Callable, displays: Node = null) -> void:
	_container = container
	_impacts = impacts
	_player = player
	_drop_weapon = drop_weapon
	_displays = displays


func bind_scene(node: Node) -> void:
	_bind_particles(node)
	if node.has_method("configure_displays"):
		node.call("configure_displays", _displays)
	if node.has_method("configure_weapon_drop"):
		node.call("configure_weapon_drop", _drop_weapon)
	if node.has_method("configure_player"):
		node.call("configure_player", _player)
	if node.has_method("configure_world"):
		node.call("configure_world", _container, _impacts)
		return # Public root forwards dependencies to its own local components.
	for child in node.get_children():
		bind_scene(child)



func _bind_particles(node: Node) -> void:
	if node.has_method("configure_damage_particles"):
		node.call("configure_damage_particles", _electronic_particles)
		_particle_targets.append(weakref(node))
	for child in node.get_children():
		_bind_particles(child)


func set_electronic_particles_enabled(enabled: bool) -> void:
	_electronic_particles = enabled
	for index in range(_particle_targets.size() - 1, -1, -1):
		var target: Object = _particle_targets[index].get_ref()
		if target == null:
			_particle_targets.remove_at(index)
		else:
			target.call("configure_damage_particles", enabled)
