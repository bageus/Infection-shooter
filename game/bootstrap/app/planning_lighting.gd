extends Node

@export var local_lights_enabled := false:
	set(value):
		local_lights_enabled = value
		if is_inside_tree():
			_apply_local_lights()
		if is_instance_valid(_local_toggle):
			_local_toggle.set_pressed_no_signal(value)

var _local_toggle: CheckButton
var _scene_tree: SceneTree
var world_environment: WorldEnvironment
var _saved_energy := 0.0
var _saved_source := Environment.AMBIENT_SOURCE_DISABLED
var _saved_color := Color.WHITE
var _planning := false
var _game_lighting := true


func setup(environment_node: WorldEnvironment, selector: OptionButton = null, local_toggle: CheckButton = null) -> void:
	if world_environment == environment_node:
		return
	if _planning:
		_restore_ambient()
	_local_toggle = local_toggle
	if _local_toggle != null:
		_local_toggle.set_pressed_no_signal(local_lights_enabled)
		_local_toggle.toggled.connect(set_local_lights_enabled)
	_scene_tree = get_tree()
	if not _scene_tree.node_added.is_connected(_on_node_added):
		_scene_tree.node_added.connect(_on_node_added)
	_apply_local_lights()
	world_environment = environment_node
	_planning = false
	if world_environment != null and world_environment.environment != null:
		# Editor illumination must never mutate the shared scene resource.
		world_environment.environment = world_environment.environment.duplicate() as Environment
		_capture_ambient()
	if selector != null:
		selector.select(0 if _game_lighting else 1)
		selector.item_selected.connect(_on_preview_selected)


func set_local_lights_enabled(enabled: bool) -> void:
	local_lights_enabled = enabled


func _apply_local_lights() -> void:
	for lamp: Node in get_tree().get_nodes_in_group("planner_lights"):
		_on_node_added(lamp)


func _on_node_added(node: Node) -> void:
	# Late map loads and planner duplicates obey the same application setting.
	if node.is_in_group("planner_lights") and node.has_method("set_local_lighting_enabled"):
		node.call("set_local_lighting_enabled", local_lights_enabled)


func set_planning_mode(enabled: bool) -> void:
	if world_environment == null or world_environment.environment == null or enabled == _planning:
		return
	if enabled:
		_capture_ambient()
	_planning = enabled
	_apply_preview()


func _on_preview_selected(index: int) -> void:
	set_game_lighting(index == 0)


func set_game_lighting(enabled: bool) -> void:
	_game_lighting = enabled
	if _planning:
		_apply_preview()


func _capture_ambient() -> void:
	var environment := world_environment.environment
	_saved_source = environment.ambient_light_source
	_saved_color = environment.ambient_light_color
	_saved_energy = environment.ambient_light_energy


func _apply_preview() -> void:
	_restore_ambient()
	if _planning and not _game_lighting:
		var environment := world_environment.environment
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.62, 0.68, 0.78, 1.0)
		environment.ambient_light_energy = 0.38


func _restore_ambient() -> void:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	var environment := world_environment.environment
	environment.ambient_light_source = _saved_source
	environment.ambient_light_color = _saved_color
	environment.ambient_light_energy = _saved_energy


func _exit_tree() -> void:
	if _scene_tree != null and _scene_tree.node_added.is_connected(_on_node_added):
		_scene_tree.node_added.disconnect(_on_node_added)
	if _planning:
		_restore_ambient()
