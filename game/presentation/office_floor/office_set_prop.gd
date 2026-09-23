@tool
extends Node3D

@export_file("*.fbx") var model_path := ""
@export var wall_mount := false
@export var surface_placeable := true

var _visual: Node3D
var _body: StaticBody3D

func _ready() -> void:
	set_meta("planning_wall_mount", wall_mount)
	set_meta("planning_surface_placeable", surface_placeable)
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		return
	_visual = packed.instantiate() as Node3D
	if _visual == null:
		return
	_visual.name = "Visual"
	add_child(_visual)
	_body = StaticBody3D.new()
	_body.name = "Body"
	add_child(_body)
	call_deferred("_build_collision")

func _build_collision() -> void:
	if _visual == null or _body == null:
		return
	var meshes := _visual.find_children("*", "MeshInstance3D", true, false)
	for child in meshes:
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := BoxShape3D.new()
		box.size = mesh_instance.get_aabb().size
		var shape := CollisionShape3D.new()
		shape.shape = box
		_body.add_child(shape)
		var mesh_to_body := _body.global_transform.affine_inverse() * mesh_instance.global_transform
		shape.transform = mesh_to_body
		shape.position += mesh_to_body.basis * mesh_instance.get_aabb().get_center()
