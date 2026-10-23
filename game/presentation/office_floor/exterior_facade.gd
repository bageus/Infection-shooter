extends Node3D
## Builds the building facade under an exterior window, down to the city ground,
## so the office does not hang above the backdrop. Visual only: no collision and no shadow.

const CITY_GROUND_Y := -65.4 # FogGround in public/city_backdrop.gd
const CONCRETE := Color(0.24, 0.30, 0.39) # Same tone as the decorative city facades

@export var visual_path: NodePath = NodePath("Visual")


func _ready() -> void:
	call_deferred("_build_facade")


func _build_facade() -> void:
	var visual := get_parent().get_node_or_null(visual_path) as Node3D
	if visual == null:
		return
	var frame := visual.find_child("frame", true, false) as MeshInstance3D
	if frame == null or frame.mesh == null:
		return
	var bounds := frame.global_transform * frame.get_aabb()
	var top := bounds.position.y
	if top <= CITY_GROUND_Y:
		return
	var box := BoxMesh.new()
	box.size = Vector3(bounds.size.x, top - CITY_GROUND_Y, bounds.size.z)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CONCRETE
	box.material = material
	var facade := MeshInstance3D.new()
	facade.name = "ExteriorFacade"
	facade.mesh = box
	facade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(facade)
	var center := bounds.get_center()
	facade.global_position = Vector3(center.x, (top + CITY_GROUND_Y) * 0.5, center.z)
