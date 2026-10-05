extends Node3D

@export_range(0.0, 2.0, 0.01) var energy_multiplier := 0.65:
	set(value):
		energy_multiplier = maxf(value, 0.0)
		_apply_energy()

@export var light_color := Color(1.0, 0.92, 0.78, 1.0):
	set(value):
		light_color = Color(value.r, value.g, value.b, 1.0)
		set_meta("planning_light_color", light_color)
		_apply_color()

# Defaults preserve invisible fixtures in legacy authored scenes/maps.
@export_enum("point", "linear", "rectangle") var fixture_shape := "point"
@export var fixture_visible_in_game := false
var _planning_visual := false
var _fixture: Node3D
var _diffuser_material: StandardMaterial3D

@onready var marker: MeshInstance3D = $Marker
@onready var light: SpotLight3D = $Light
var flicker_mode := 0
var flicker_step := 0.2
var _elapsed := 0.0
var _target_factor := 1.0
var _flicker_factor := 1.0
var _rng := RandomNumberGenerator.new()
var _local_lighting_enabled := false
var _runtime_active := true

func _enter_tree() -> void:
	add_to_group("planner_lights")


func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	if marker != null:
		marker.visible = false
	if light != null:
		if not has_meta("planning_light_color"):
			# Old authored scenes keep their original per-instance color.
			light_color = light.light_color
		else:
			light_color = get_meta("planning_light_color")
		# Capture a legacy scene value once, before applying the multiplier.
		if not has_meta("planning_light_energy"):
			set_meta("planning_light_energy", light.light_energy)
		configure_flicker(int(get_meta("planning_flicker_mode", 0)), float(get_meta("planning_flicker_step", 0.2)))
	_build_fixture()


func configure_flicker(mode: int, step_seconds: float) -> void:
	flicker_mode = clampi(mode, 0, 3)
	flicker_step = clampf(step_seconds, 0.05, 3.0)
	set_meta("planning_flicker_mode", flicker_mode)
	set_meta("planning_flicker_step", flicker_step)
	_elapsed = 0.0
	_flicker_factor = 1.0
	_target_factor = 1.0
	_sync_activation()


func _process(delta: float) -> void:
	if light == null or not _is_active():
		return
	if flicker_mode == 0:
		_flicker_factor = 1.0
		_apply_energy()
		return
	_elapsed += delta
	if _elapsed >= flicker_step:
		_elapsed = fmod(_elapsed, flicker_step)
		match flicker_mode:
			1:
				_target_factor = _rng.randf_range(0.12, 1.0)
			2:
				_target_factor = _rng.randf_range(0.3, 1.0)
			3:
				_target_factor = 0.0 if _rng.randf() < 0.16 else 1.0
				if _target_factor == 0.0:
					_flicker_factor = 0.0
	_flicker_factor = lerpf(_flicker_factor, _target_factor, minf(delta * (24.0 if flicker_mode == 1 else 4.0), 1.0))
	_apply_energy()

func set_local_lighting_enabled(enabled: bool) -> void:
	_local_lighting_enabled = enabled
	_sync_activation()


func set_runtime_light_active(enabled: bool) -> void:
	_runtime_active = enabled
	_sync_activation()
	if light != null and has_meta("planning_light_angle"):
		light.spot_angle = float(get_meta("planning_light_angle"))


func _is_active() -> bool:
	return _local_lighting_enabled and _runtime_active


func _sync_activation() -> void:
	visible = true
	_sync_fixture_visibility()
	set_process(_is_active() and flicker_mode != 0)
	if light != null:
		light.visible = _is_active()
		_apply_energy()


func set_planning_visual(enabled: bool) -> void:
	_planning_visual = enabled
	visible = true
	if marker != null:
		marker.visible = enabled
		marker.top_level = true
		marker.global_position = global_position
	_sync_activation()


func get_authored_energy() -> float:
	return float(get_meta("planning_light_energy", 3.0))


func set_authored_energy(energy: float) -> void:
	set_meta("planning_light_energy", maxf(energy, 0.0))
	_apply_energy()


func _apply_energy() -> void:
	if light != null:
		light.light_energy = get_authored_energy() * energy_multiplier * _flicker_factor if _is_active() else 0.0
	if _diffuser_material != null:
		_diffuser_material.emission_energy_multiplier = minf(light.light_energy, 2.0) if light != null else 0.0


func get_authored_color() -> Color:
	return get_meta("planning_light_color", light_color)


func set_authored_color(color: Color) -> void:
	light_color = color


func _apply_color() -> void:
	if light != null:
		light.light_color = light_color
	if _diffuser_material != null:
		_diffuser_material.albedo_color = light_color
		_diffuser_material.emission = light_color


func configure_fixture(shape: String, visible_in_game: bool) -> void:
	var next_shape := shape if shape in ["point", "linear", "rectangle"] else "point"
	var rebuild := fixture_shape != next_shape
	fixture_shape = next_shape
	fixture_visible_in_game = visible_in_game
	if is_node_ready() and (_fixture == null or rebuild):
		_build_fixture()
	_sync_fixture_visibility()


func get_fixture_config() -> Dictionary:
	return {"shape": fixture_shape, "visible_in_game": fixture_visible_in_game}


func _build_fixture() -> void:
	# Geometry and materials are per-instance; shared scene resources stay immutable.
	if _fixture == null:
		_fixture = Node3D.new()
		_fixture.name = "Fixture"
		add_child(_fixture)
	for child in _fixture.get_children():
		child.free()
	var housing := MeshInstance3D.new()
	housing.name = "Housing"
	housing.mesh = _fixture_mesh(false)
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.16, 0.18, 0.21)
	frame.metallic = 0.65
	frame.roughness = 0.4
	housing.material_override = frame
	_fixture.add_child(housing)
	var diffuser := MeshInstance3D.new()
	diffuser.name = "Diffuser"
	diffuser.mesh = _fixture_mesh(true)
	diffuser.position.y = -0.046
	_diffuser_material = StandardMaterial3D.new()
	_diffuser_material.emission_enabled = true
	diffuser.material_override = _diffuser_material
	_fixture.add_child(diffuser)
	_apply_color()
	_apply_energy()
	_sync_fixture_visibility()


func _fixture_mesh(diffuser: bool) -> PrimitiveMesh:
	if fixture_shape == "point":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.145 if diffuser else 0.18
		cylinder.bottom_radius = cylinder.top_radius
		cylinder.height = 0.012 if diffuser else 0.08
		return cylinder
	var box := BoxMesh.new()
	var footprint := Vector2(1.2, 0.16) if fixture_shape == "linear" else Vector2(0.8, 0.6)
	if diffuser:
		footprint -= Vector2(0.04, 0.04)
	box.size = Vector3(footprint.x, 0.012 if diffuser else 0.08, footprint.y)
	return box


func _sync_fixture_visibility() -> void:
	if _fixture != null:
		_fixture.visible = _planning_visual or (fixture_visible_in_game and _runtime_active)
