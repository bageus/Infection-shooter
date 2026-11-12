extends RefCounted
const VISUAL_BUDGET := preload("res://game/features/infected/public/visual_preparation_budget.gd")
const CHASE_BUDGET := preload("res://game/features/infected/public/chase_search_budget.gd")
const BIOMASS_STEP := preload("res://game/presentation/office_floor/public/biomass_footstep_surface.gd")

# Mission composition only: explicit collaborators, no global context or lookup API.
var _container: Node3D
var _impacts: Node
var _player: Node3D
var _drop_weapon: Callable
var _loot_needs: Callable
var _displays: Node
var _visual_budget: Node
var _chase_budget: Node
var debris_floor: Node3D


func _init(container: Node3D, impacts: Node, player: Node3D, drop_weapon: Callable, displays: Node = null, camera: Node3D = null) -> void:
	_container = container
	_impacts = impacts
	_player = player
	_drop_weapon = drop_weapon
	_loot_needs = Callable(self, "_needs_snapshot").bind(player)
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
	_bind_collaborators(node)


func _bind_collaborators(node: Node) -> void:
	if node.has_method("configure_footstep_surface"):
		var query := Callable(debris_floor, "has_glass_at") if is_instance_valid(debris_floor) else Callable()
		var container := _container
		node.call("configure_footstep_surface", query, func(point: Vector3) -> bool: return BIOMASS_STEP.has_biomass_at(container, point))
	if node.has_method("configure_glass_debris"):
		node.call("configure_glass_debris", debris_floor)
	if node.has_method("configure_floor_debris") and is_instance_valid(debris_floor):
		node.call("configure_floor_debris", debris_floor)
	if node.has_method("configure_visual_preparation") and is_instance_valid(_visual_budget) and is_instance_valid(_visual_budget.camera):
		node.call("configure_visual_preparation", _visual_budget)
	if node.has_method("configure_chase_budget"):
		node.call("configure_chase_budget", _chase_budget)
	if node.has_method("configure_displays"):
		node.call("configure_displays", _displays)
	if node.has_method("configure_weapon_drop"):
		node.call("configure_weapon_drop", _drop_weapon)
	if node.has_method("configure_loot_drop"):
		node.call("configure_loot_drop", _drop_weapon, _loot_needs)
	if node.has_method("configure_player"):
		node.call("configure_player", _player)
	if node.has_method("configure_world"):
		node.call("configure_world", _container, _impacts)
		return # Public root forwards dependencies to its own local components.
	for child in node.get_children():
		_bind_collaborators(child)



## What the player needs right now, for auto crate loot (see loot_config.gd crate_weights).
func _needs_snapshot(player: Node3D) -> Dictionary:
	var carried: Array[int] = player.carried_weapon_indices()
	var weapons: Array = player.get("weapons")
	var reserve := {}
	for index in carried:
		var gun: Node = weapons[index]
		var cap := float(gun.get("max_reserve_ammo"))
		if cap > 0.0 and gun.has_method("carried_ammo"):
			reserve[index] = float(gun.call("carried_ammo")) / cap
	var max_health := maxf(float(player.get("max_health")), 1.0)
	return {"carried": carried, "reserve": reserve, "health": float(player.get("health")) / max_health, "antidotes": int(player.get("antidotes"))}
