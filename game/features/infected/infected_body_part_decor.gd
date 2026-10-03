extends "res://game/features/infected/severed_part.gd"
## Planner decoration: a loose head, limb or tentacle lying on the floor
## (ADR-0017). It is built from the same enemy model as the live part, can
## be shot around and never expires.

const BODY_PARTS := preload("res://game/features/infected/body_parts.gd")
const MESH := preload("res://game/features/infected/body_part_mesh.gd")

@export var visual_scene: PackedScene
@export var animation_library: AnimationLibrary
@export var visual_scale := 1.0
@export var part := &"arm_r"
@export var pose_clip := "Idle"


func _init() -> void:
	lifetime = INF
	bleeding = false


func _ready() -> void:
	_build()
	super._ready()


func _build() -> void:
	if visual_scene == null or not is_inside_tree():
		return
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * visual_scale
	add_child(holder)
	var visual := visual_scene.instantiate() as Node3D
	holder.add_child(visual)
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player := players[0] as AnimationPlayer
		if animation_library != null:
			for library_name in player.get_animation_library_list():
				player.remove_animation_library(library_name)
			player.add_animation_library(&"", animation_library)
		if player.has_animation(pose_clip):
			player.play(pose_clip)
			player.seek(0.0, true)
			player.pause()
	var parts := BODY_PARTS.new()
	add_child(parts)
	if parts.setup(self, holder, 1.0) and parts.parts.has(part):
		var info: Dictionary = parts.parts[part]
		var materials: Array = []
		for material: ShaderMaterial in parts._entries[0].materials:
			var copy := material.duplicate() as ShaderMaterial
			var wounds := PackedVector4Array()
			wounds.resize(BODY_PARTS.MAX_WOUNDS)
			var cut: Vector3 = info.segments[0].start
			wounds[0] = Vector4(cut.x, cut.y, cut.z, float(info.segments[0].radius) * 1.25)
			copy.set_shader_parameter("wounds", wounds)
			materials.append(copy)
		var built := MESH.build_piece(parts._entries[0].data, info.bones, parts.skeleton, materials)
		if not built.is_empty():
			_assemble(built, parts._world(info.bones[0], info.segments[0].start), float(info.segments[0].radius) * visual_scale)
	parts.free()
	holder.free()


# Lays the part down along X with its cut end at -X, centred on this body.
func _assemble(built: Dictionary, cut_world: Vector3, cap_radius: float) -> void:
	var local_center: Vector3 = global_transform.affine_inverse() * built.center
	var cut := global_transform.affine_inverse() * cut_world - local_center
	var lie := Basis(Quaternion((-cut).normalized() if cut.length_squared() > 0.0001 else Vector3.RIGHT, Vector3.RIGHT))
	var visual := MeshInstance3D.new()
	visual.mesh = built.mesh
	visual.basis = lie
	add_child(visual)
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = built.points
	shape.shape = hull
	shape.basis = lie
	add_child(shape)
	var cap := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = maxf(cap_radius * 0.6, 0.012)
	sphere.height = sphere.radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.02, 0.02)
	material.roughness = 0.25
	sphere.material = material
	cap.mesh = sphere
	cap.transform = Transform3D(Basis(Quaternion(Vector3.UP, Vector3.LEFT)) * Basis.from_scale(Vector3(1.0, 0.4, 1.0)), lie * cut)
	add_child(cap)
	var bounds := AABB(built.points[0], Vector3.ZERO)
	for point: Vector3 in built.points:
		bounds = bounds.expand(point)
	mass = clampf(bounds.size.x * bounds.size.y * bounds.size.z * 120.0, 0.3, 25.0)
