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
# The renderer drops lights beyond its per-frame limit, so PlanningLighting keeps
# only the lamps nearest to the camera lit and tells each one whether it may cast shadows.
var _budget_lit := true
var _budget_shadow := false
# Brightness share the budget has granted so far: a lamp fades in and out instead of jumping.
const BUDGET_FADE_SECONDS := 0.25
var _budget_fade := 0.0
var _sub_lights: Array[SpotLight3D] = []

func _enter_tree() -> void:
	add_to_group("planner_lights")
	add_to_group("budget_lights")


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
	if light == null or not _is_on():
		return
	_budget_fade = move_toward(_budget_fade, _budget_target(), delta / BUDGET_FADE_SECONDS)
	if flicker_mode == 0:
		_flicker_factor = 1.0
	else:
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
	set_process(_needs_process())


func _budget_target() -> float:
	return 1.0 if _is_active() else 0.0


func _needs_process() -> bool:
	return _is_on() and (flicker_mode != 0 or _budget_fade != _budget_target())

func set_local_lighting_enabled(enabled: bool) -> void:
	_local_lighting_enabled = enabled
	_sync_activation()


func set_runtime_light_active(enabled: bool) -> void:
	_runtime_active = enabled
	_sync_activation()
	if light != null and has_meta("planning_light_angle"):
		light.spot_angle = float(get_meta("planning_light_angle"))


func _is_on() -> bool:
	return _local_lighting_enabled and _runtime_active


func _is_active() -> bool:
	return _is_on() and _budget_lit


## Number of spot lights this fixture needs while lit (the renderer limit is shared).
func get_light_cost() -> int:
	return 1 + _sub_lights.size()


## Distance at which the authored cone stops lighting anything.
func get_light_radius() -> float:
	return light.spot_range if light != null else 0.0


## Narrows the cone so it ends at a wall `gap` metres away (INF restores it). Used for lamps without a shadow.
## shortcut: assumes the floor is at y = 0 and clamps at MIN_CLIP_ANGLE, so a lamp hugging a wall still leaks a little.
const MIN_CLIP_ANGLE := 15.0
var _authored_angle := -1.0


func set_wall_gap(gap: float) -> void:
	if light == null or (_authored_angle < 0.0 and is_inf(gap)):
		return
	if _authored_angle < 0.0:
		_authored_angle = light.spot_angle
	var angle := _authored_angle
	if not is_inf(gap):
		angle = minf(_authored_angle, maxf(rad_to_deg(atan(gap / maxf(global_position.y, 0.5))), MIN_CLIP_ANGLE))
	if is_inf(gap):
		_authored_angle = -1.0
	if not is_equal_approx(angle, light.spot_angle):
		light.spot_angle = angle
		sync_sub_lights()


func set_budget_lit(lit: bool, shadow: bool) -> void:
	if lit == _budget_lit and shadow == _budget_shadow:
		return
	_budget_lit = lit
	_budget_shadow = shadow
	_sync_activation(true)


func get_budget_lit() -> bool:
	return _budget_lit


## Spot lights of a long fixture copy the cone/color of the authored main light.
func sync_sub_lights() -> void:
	if light == null:
		return
	# Shadows switch on only once the lamp is fully lit, so a fading lamp never pops a shadow.
	var shadowed := _budget_shadow and light.visible and _budget_fade >= 1.0
	light.shadow_enabled = shadowed
	for extra in _sub_lights:
		extra.spot_angle = light.spot_angle
		extra.spot_range = light.spot_range
		extra.spot_angle_attenuation = light.spot_angle_attenuation
		extra.spot_attenuation = light.spot_attenuation
		extra.light_color = light.light_color
		extra.visible = light.visible
		extra.shadow_enabled = shadowed


## Only a budget change fades; switching lighting on or off applies at once.
func _sync_activation(fade_budget := false) -> void:
	visible = true
	_sync_fixture_visibility()
	if not fade_budget or not _is_on():
		_budget_fade = _budget_target()
	set_process(_needs_process())
	if light != null:
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
		var split := _sub_lights.size() + 1
		# A long fixture shares its output between its lights, slightly brighter in total.
		var share := 1.0 if split == 1 else 0.7 / float(split)
		light.light_energy = get_authored_energy() * energy_multiplier * _flicker_factor * share * _budget_fade if _is_on() else 0.0
		light.visible = _is_on() and _budget_fade > 0.0
		for extra in _sub_lights:
			extra.light_energy = light.light_energy
		sync_sub_lights()
	if _diffuser_material != null:
		var glow := get_authored_energy() * energy_multiplier * _flicker_factor if _is_on() else 0.0
		_diffuser_material.emission_energy_multiplier = minf(glow, 2.0)


func get_authored_color() -> Color:
	return get_meta("planning_light_color", light_color)


func set_authored_color(color: Color) -> void:
	light_color = color


func _apply_color() -> void:
	if light != null:
		light.light_color = light_color
		for extra in _sub_lights:
			extra.light_color = light_color
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
	# The fixture hangs under the ceiling: nothing above it lights it, so it casts no shadow.
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fixture.add_child(housing)
	var diffuser := MeshInstance3D.new()
	diffuser.name = "Diffuser"
	diffuser.mesh = _fixture_mesh(true)
	diffuser.position.y = -0.046
	_diffuser_material = StandardMaterial3D.new()
	_diffuser_material.emission_enabled = true
	diffuser.material_override = _diffuser_material
	diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fixture.add_child(diffuser)
	_build_sub_lights()
	_apply_color()
	_apply_energy()
	_sync_fixture_visibility()


# Where the spot lights sit on the fixture so the glow spreads over the whole
# emitting surface: along a linear fixture, over a rectangle's corners.
func _light_offsets() -> Array[Vector2]:
	match fixture_shape:
		"linear":
			return [Vector2(-0.4, 0.0), Vector2(0.4, 0.0)]
		"rectangle":
			return [Vector2(-0.22, -0.16), Vector2(0.22, -0.16), Vector2(-0.22, 0.16), Vector2(0.22, 0.16)]
	return [Vector2.ZERO]


func _build_sub_lights() -> void:
	for extra in _sub_lights:
		if is_instance_valid(extra):
			extra.free()
	_sub_lights.clear()
	if light == null:
		return
	var offsets := _light_offsets()
	light.position = Vector3(offsets[0].x, light.position.y, offsets[0].y)
	for index in range(1, offsets.size()):
		var extra := light.duplicate() as SpotLight3D
		extra.name = "SubLight%d" % index
		extra.position = Vector3(offsets[index].x, light.position.y, offsets[index].y)
		add_child(extra)
		_sub_lights.append(extra)


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
