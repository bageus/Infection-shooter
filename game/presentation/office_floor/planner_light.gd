extends Node3D

@onready var marker: MeshInstance3D = $Marker
@onready var light: SpotLight3D = $Light
var flicker_mode := 0
var flicker_step := 0.2
var _elapsed := 0.0
var _target_energy := 3.0
var _display_energy := 3.0
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
		configure_flicker(int(get_meta("planning_flicker_mode", 0)), float(get_meta("planning_flicker_step", 0.2)))


func configure_flicker(mode: int, step_seconds: float) -> void:
	flicker_mode = clampi(mode, 0, 3)
	flicker_step = clampf(step_seconds, 0.05, 3.0)
	set_meta("planning_flicker_mode", flicker_mode)
	set_meta("planning_flicker_step", flicker_step)
	_elapsed = 0.0
	if light != null:
		_display_energy = float(get_meta("planning_light_energy", light.light_energy))
		_target_energy = _display_energy
		light.light_energy = _display_energy


func _process(delta: float) -> void:
	if light == null:
		return
	var base_energy := float(get_meta("planning_light_energy", 3.0))
	if flicker_mode == 0:
		light.light_energy = base_energy
		return
	_elapsed += delta
	if _elapsed >= flicker_step:
		_elapsed = fmod(_elapsed, flicker_step)
		match flicker_mode:
			1:
				_target_energy = base_energy * _rng.randf_range(0.12, 1.0)
			2:
				_target_energy = base_energy * _rng.randf_range(0.3, 1.0)
			3:
				_target_energy = 0.0 if _rng.randf() < 0.16 else base_energy
				if _target_energy == 0.0:
					_display_energy = 0.0
	_display_energy = lerpf(_display_energy, _target_energy, minf(delta * (24.0 if flicker_mode == 1 else 4.0), 1.0))
	light.light_energy = _display_energy

func set_runtime_light_active(_enabled: bool) -> void:
	visible = true
	if light != null:
		light.visible = true
		if flicker_mode == 0:
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
