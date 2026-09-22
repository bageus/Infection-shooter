extends Node3D

@onready var marker: MeshInstance3D = $Marker
@onready var light: SpotLight3D = $Light

func _enter_tree() -> void:
	add_to_group("planner_lights")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	if marker != null:
		marker.visible = false
	if light != null:
		light.visible = true

func set_runtime_light_active(enabled: bool) -> void:
	visible = true
	if light != null:
		light.visible = enabled
		light.light_energy = float(get_meta("planning_light_energy", light.light_energy))
		if has_meta("planning_light_angle"):
			light.spot_angle = float(get_meta("planning_light_angle"))


func set_planning_visual(enabled: bool) -> void:
	visible = true
	if marker != null:
		marker.visible = enabled
		marker.top_level = true
		marker.global_position = global_position
	if light != null:
		light.visible = true
