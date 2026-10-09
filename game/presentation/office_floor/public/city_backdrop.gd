extends Node3D
## Mission-local decorative skyline. No textures, collision, lights or frame updates.

const FACADE := preload("res://game/presentation/office_floor/city_facade.gdshader")

@export var location_size := Vector2(80.0, 60.0)
@export_range(20.0, 100.0) var street_gap := 48.0
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
	for layer in 3:
		for side in 4:
			_build_side(side, layer, random, mesh)
	_build_roofs(mesh)
	_build_streets()

func _build_side(side: int, layer: int, random: RandomNumberGenerator, mesh: Mesh) -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.use_colors = true
	instances.instance_count = 8 + layer * 4
	var along_x := side < 2
	var boundary := location_size.y * 0.5 if along_x else location_size.x * 0.5
	var direction := -1.0 if side % 2 == 0 else 1.0
	for index in instances.instance_count:
		var width := random.randf_range(16.0, 24.0)
		var depth := random.randf_range(16.0, 24.0)
		var height := random.randf_range(42.0, 86.0) + float(layer) * 18.0
		if layer == 0 and index % 4 == 0:
			height = 104.0
		var along := (float(index) - float(instances.instance_count - 1) * 0.5) * (42.0 + layer * 12.0)
		var across := direction * (boundary + street_gap + float(layer) * 120.0 + depth * 0.5 + float(index % 2) * 12.0)
		var center := Vector3(along, -65.0 + height * 0.5, across)
		var size := Vector3(width, height, depth)
		if not along_x:
			center = Vector3(across, center.y, along)
			size = Vector3(depth, height, width)
		var building_transform := Transform3D(Basis.from_scale(size), center)
		building_transforms.append(building_transform)
		instances.set_instance_transform(index, building_transform)
		instances.set_instance_color(index, Color(random.randf(), float(layer) / 2.0, random.randf(), 1.0))
	var batch := MultiMeshInstance3D.new()
	batch.name = "CityLayer%dSide%d" % [layer, side]
	batch.multimesh = instances
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)

func _build_roofs(mesh: Mesh) -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = 32
	for index in 32:
		var body := building_transforms[index]
		var size := body.basis.get_scale()
		var roof_size := Vector3(size.x * 0.55, 3.0 + float(index % 3), size.z * 0.55)
		var center := body.origin + Vector3(0, size.y * 0.5 + roof_size.y * 0.5, 0)
		instances.set_instance_transform(index, Transform3D(Basis.from_scale(roof_size), center))
	var roofs := MultiMeshInstance3D.new()
	roofs.name = "RoofSetbacks"
	roofs.multimesh = instances
	roofs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(roofs)

func _build_streets() -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://game/presentation/office_floor/city_street.gdshader")
	for side in 4:
		var ground := MeshInstance3D.new()
		ground.name = "Street%d" % side
		var mesh := BoxMesh.new()
		var along_x := side < 2
		mesh.size = Vector3(1500, 0.2, street_gap) if along_x else Vector3(street_gap, 0.2, 1500)
		mesh.material = material
		ground.mesh = mesh
		var direction := -1.0 if side % 2 == 0 else 1.0
		ground.position = Vector3(0, -65.2, direction * (location_size.y + street_gap) * 0.5) if along_x else Vector3(direction * (location_size.x + street_gap) * 0.5, -65.2, 0)
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ground)
