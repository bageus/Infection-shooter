extends Node

var world_environment: WorldEnvironment
var _saved_energy := 0.0
var _saved_source := Environment.AMBIENT_SOURCE_DISABLED

func setup(environment_node: WorldEnvironment) -> void:
	world_environment = environment_node
	if world_environment != null and world_environment.environment != null:
		_saved_energy = world_environment.environment.ambient_light_energy
		_saved_source = world_environment.environment.ambient_light_source

func set_planning_mode(enabled: bool) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var environment := world_environment.environment
	if enabled:
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.62, 0.68, 0.78, 1.0)
		environment.ambient_light_energy = 0.38
	else:
		environment.ambient_light_source = _saved_source
		environment.ambient_light_energy = _saved_energy
