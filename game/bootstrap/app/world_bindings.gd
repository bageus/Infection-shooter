extends RefCounted
const VISUAL_BUDGET := preload("res://game/features/infected/public/visual_preparation_budget.gd")
const CHASE_BUDGET := preload("res://game/features/infected/public/chase_search_budget.gd")

# Mission composition only: explicit collaborators, no global context or lookup API.
var _container: Node3D
var _impacts: Node
var _player: Node3D
var _drop_weapon: Callable
var _particle_targets: Dictionary = {}
var _electronic_particles := true
var _displays: Node
var _visual_budget: Node
var _chase_budget: Node
var debris_floor: Node3D


func _init(container: Node3D, impacts: Node, player: Node3D, drop_weapon: Callable, displays: Node = null, camera: Node3D = null) -> void:
	_container = container
	_impacts = impacts
	_player = player
	_drop_weapon = drop_weapon
	_displays = displays
	if is_instance_valid(_container):
		_chase_budget = CHASE_BUDGET.new()
		_chase_budget.name = "ChaseSearchBudget"
		_container.add_child(_chase_budget)
		_visual_budget = VISUAL_BUDGET.new()
		_visual_budget.name = "VisualPreparationBudget"
		_visual_budget.camera = camera
		_container.add_child(_visual_budget)


func bind_scene(node: Node) -> void:
	_bind_particles(node)
	_bind_collaborators(node)


func _bind_collaborators(node: Node) -> void:
	if node.has_method("configure_glass_debris"):
		node.call("configure_glass_debris", debris_floor)
	if node.has_method("configure_visual_preparation") and is_instance_valid(_visual_budget) and is_instance_valid(_visual_budget.camera):
		node.call("configure_visual_preparation", _visual_budget)
	if node.has_method("configure_chase_budget"):
		node.call("configure_chase_budget", _chase_budget)
	if node.has_method("configure_displays"):
		node.call("configure_displays", _displays)
	if node.has_method("configure_weapon_drop"):
		node.call("configure_weapon_drop", _drop_weapon)
	if node.has_method("configure_loot_drop"):
		node.call("configure_loot_drop", _drop_weapon)
	if node.has_method("configure_player"):
		node.call("configure_player", _player)
	if node.has_method("configure_world"):
		node.call("configure_world", _container, _impacts)
		return # Public root forwards dependencies to its own local components.
	for child in node.get_children():
		_bind_collaborators(child)



func _bind_particles(node: Node) -> void:
	var id := node.get_instance_id()
	if node.has_method("configure_damage_particles") and not _particle_targets.has(id):
		node.call("configure_damage_particles", _electronic_particles)
		_particle_targets[id] = weakref(node)
	for child in node.get_children():
		_bind_particles(child)


func set_electronic_particles_enabled(enabled: bool) -> void:
	_electronic_particles = enabled
	for id in _particle_targets.keys():
		var target: Object = _particle_targets[id].get_ref()
		if target == null:
			_particle_targets.erase(id)
		else:
			target.call("configure_damage_particles", enabled)
