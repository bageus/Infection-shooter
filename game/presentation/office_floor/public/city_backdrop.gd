extends Node3D
## Mission-local decorative skyline. No textures, collision, lights or frame updates.

const FACADE := preload("res://game/presentation/office_floor/city_facade.gdshader")

@export var location_size := Vector2(80.0, 60.0)
@export_range(20.0, 100.0) var street_gap := 30.0
@export var skyline_seed := 1042
var building_transforms: Array[Transform3D] = []

func _ready() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = skyline_seed
	var material := ShaderMaterial.new()
	material.shader = FACADE
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = material
	for side in 4:
		_build_side(side, random, mesh)

func _build_side(side: int, random: RandomNumberGenerator, mesh: Mesh) -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = 8
	var along_x := side < 2
	var boundary := location_size.y * 0.5 if along_x else location_size.x * 0.5
	var direction := -1.0 if side % 2 == 0 else 1.0
	for index in instances.instance_count:
		var width := random.randf_range(16.0, 24.0)
		var depth := random.randf_range(16.0, 24.0)
		var height := random.randf_range(72.0, 128.0)
		var along := (float(index) - 3.5) * 32.0
		var across := direction * (boundary + street_gap + depth * 0.5)
		var center := Vector3(along, -65.0 + height * 0.5, across)
		var size := Vector3(width, height, depth)
		if not along_x:
			center = Vector3(across, center.y, along)
			size = Vector3(depth, height, width)
		var building_transform := Transform3D(Basis.from_scale(size), center)
		building_transforms.append(building_transform)
		instances.set_instance_transform(index, building_transform)
	var batch := MultiMeshInstance3D.new()
	batch.name = "CitySide%d" % side
	batch.multimesh = instances
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)
