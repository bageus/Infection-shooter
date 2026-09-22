extends Node3D

@onready var marker: MeshInstance3D = $Marker
@onready var light: OmniLight3D = $Light

func _ready() -> void:
	add_to_group("planner_lights")
	set_planning_visual(false)

func set_planning_visual(enabled: bool) -> void:
	visible = true
	if marker != null:
		marker.visible = enabled
		marker.top_level = true
		marker.global_position = global_position
	if light != null:
		light.visible = true
