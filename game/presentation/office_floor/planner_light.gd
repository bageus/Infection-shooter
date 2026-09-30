extends Node3D

@export_range(0.0, 2.0, 0.01) var energy_multiplier := 0.65:
	set(value):
		energy_multiplier = maxf(value, 0.0)
		_apply_energy()

@onready var marker: MeshInstance3D = $Marker
@onready var light: SpotLight3D = $Light
var flicker_mode := 0
var flicker_step := 0.2
var _elapsed := 0.0
var _target_factor := 1.0
var _flicker_factor := 1.0
var _rng := RandomNumberGenerator.new()

func _enter_tree() -> void:
	add_to_group("planner_lights")


func _ready() -> void:
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	if marker != null:
		marker.visible = false
	if light != null:
		light.visible = true
		# Capture a legacy scene value once, before applying the multiplier.
		if not has_meta("planning_light_energy"):
			set_meta("planning_light_energy", light.light_energy)
		configure_flicker(int(get_meta("planning_flicker_mode", 0)), float(get_meta("planning_flicker_step", 0.2)))


func configure_flicker(mode: int, step_seconds: float) -> void:
	flicker_mode = clampi(mode, 0, 3)
	flicker_step = clampf(step_seconds, 0.05, 3.0)
	set_meta("planning_flicker_mode", flicker_mode)
	set_meta("planning_flicker_step", flicker_step)
	_elapsed = 0.0
	_flicker_factor = 1.0
	_target_factor = 1.0
	_apply_energy()


func _process(delta: float) -> void:
	if light == null:
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

func set_runtime_light_active(_enabled: bool) -> void:
	visible = true
	if light != null:
		light.visible = true
		_apply_energy()
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


func get_authored_energy() -> float:
	return float(get_meta("planning_light_energy", 3.0))


func set_authored_energy(energy: float) -> void:
	set_meta("planning_light_energy", maxf(energy, 0.0))
	_apply_energy()


func _apply_energy() -> void:
	if light != null:
		light.light_energy = get_authored_energy() * energy_multiplier * _flicker_factor
