extends Node

const VIEW := preload("res://game/presentation/office_floor/display_view.gd")
const CONTENT := preload("res://game/presentation/office_floor/display_content.gd")
const LAYOUT := preload("res://game/presentation/office_floor/display_wall_layout.gd")

var content := CONTENT.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
var displays: Array[Node3D] = []
var elapsed := 0.0
var _animated: Array[Node3D] = []
var _visible_animated: Array[Node3D] = []
var _frames: Array[Vector4] = []
var _next_frame_time := 0.0
var dirty := false
var _layout_wait := 0.0
var _layout := LAYOUT.new()
var _lighting_wait := 0.0
var _lighting_dirty := true
var _cached_view: Array = []
var _cached_shadows := false
var _cached_displays: Array[Node3D] = []
var _light_inputs := {}
# Legacy/custom adapters keep polling compatibility; native DisplayView reports changes.
var _polled_displays: Array[Node3D] = []
# Displays that are neither in the frustum nor near the camera are not re-drawn.
var _in_view := {}
var shadows_allowed := true
const MAX_GLOW_LIGHTS := 16
const MAX_SHADOW_LIGHTS := 4
const GLOW_DISTANCE := 24.0
const SHADOW_DISTANCE := 16.0
const ALWAYS_TICK_DISTANCE := 8.0


func register_display(display: Node3D) -> void:
	if not displays.has(display):
		displays.append(display)
	update_animation(display)
	request_layout()
	_lighting_wait = 0.0
	_lighting_dirty = true


func set_shadows_allowed(allowed: bool) -> void:
	shadows_allowed = allowed
	_lighting_wait = 0.0
	_lighting_dirty = true


func unregister_display(display: Node3D) -> void:
	displays.erase(display)
	_in_view.erase(display)
	_light_inputs.erase(display)
	_animated.erase(display)
	_visible_animated.erase(display)
	request_layout()
	_lighting_wait = 0.0
	_lighting_dirty = true


func request_layout() -> void:
	dirty = true


func _process(delta: float) -> void:
	elapsed += delta
	_lighting_wait -= delta
	if _lighting_wait <= 0.0:
		_lighting_wait = .2
		var view := _view_state(get_viewport().get_camera_3d())
		if view != _cached_view:
			_cached_view = view
			_refresh_lights(false)
		elif _lighting_changed():
			_refresh_lights()
	_layout_wait -= delta
	if dirty and _layout_wait <= 0.0:
		_layout_wait = .15
		dirty = false
		_layout.apply(displays)
	if _visible_animated.is_empty() or elapsed < _next_frame_time:
		return
	_frames.clear()
	var delay := INF
	for i in range(3):
		_frames.append(content.frame_rect(i, elapsed))
		delay = minf(delay, content.frame_delay(i, elapsed))
	_next_frame_time = elapsed + delay
	for display in _visible_animated:
		display.call("tick", elapsed, _frames)


# Called locally by a display whenever its powered/content state changes.
func update_animation(display: Node3D) -> void:
	_lighting_wait = 0.0
	_lighting_dirty = true
	_animated.erase(display)
	_visible_animated.erase(display)
	if display.get("powered"):
		for screen: Dictionary in display.get("screens"):
			if screen["dynamic"]:
				_animated.append(display)
				if _in_view.get(display, true) and display.is_visible_in_tree():
					_visible_animated.append(display)
				break
	_next_frame_time = 0.0


func _invalidate_lighting() -> void:
	# Motion keeps the existing .2s budget cadence; configure/register still refresh promptly.
	_lighting_dirty = true


func _lighting_changed() -> bool:
	if _lighting_dirty or shadows_allowed != _cached_shadows or displays != _cached_displays:
		return true
	for display in _polled_displays:
		if not is_instance_valid(display):
			if _light_inputs.has(display):
				return true
			continue
		if not _light_inputs.has(display):
			return true
		var saved: Array = _light_inputs[display]
		if display.global_transform != saved[0] or display.is_visible_in_tree() != saved[1] \
			or bool(display.get("powered")) != saved[2]:
			return true
		var screens: Array = display.get("screens")
		if screens.size() != saved[3].size():
			return true
		for index in screens.size():
			var light: SpotLight3D = screens[index].light
			if light != saved[3][index] or light.global_position != saved[4][index]:
				return true
	return false


func _view_state(camera: Camera3D) -> Array:
	return [] if camera == null else [camera.get_instance_id(), camera.global_transform,
		camera.get_camera_transform(), camera.get_camera_projection()]


func _remember_inputs() -> void:
	_cached_displays = displays.duplicate()
	var current := {}
	_polled_displays.clear()
	for display in displays:
		if not is_instance_valid(display) or display is VIEW:
			continue
		_polled_displays.append(display)
		if not _light_inputs.has(display):
			_light_inputs[display] = [Transform3D.IDENTITY, false, false, [], PackedVector3Array()]
		var saved: Array = _light_inputs[display]
		saved[0] = display.global_transform
		saved[1] = display.is_visible_in_tree()
		saved[2] = bool(display.get("powered"))
		var screens: Array = display.get("screens")
		saved[3].resize(screens.size())
		saved[4].resize(screens.size())
		for index in screens.size():
			var light: SpotLight3D = screens[index].light
			saved[3][index] = light
			saved[4][index] = light.global_position
		current[display] = saved
	_light_inputs = current


func _refresh_lights(capture_inputs: bool = true) -> void:
	var camera := get_viewport().get_camera_3d()
	var settings: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	for display in displays:
		if not is_instance_valid(display):
			continue
		_update_view(display, camera)
		var powered := bool(display.get("powered")) and display.is_visible_in_tree()
		for screen: Dictionary in display.get("screens"):
			var light := screen.light as SpotLight3D
			var setting := {"light": light, "visible": powered and camera == null, "shadows": false}
			settings.append(setting)
			if not powered or camera == null:
				continue
			var distance := camera.global_position.distance_to(light.global_position)
			if distance <= GLOW_DISTANCE and camera.is_position_in_frustum(light.global_position):
				setting["distance"] = distance
				candidates.append(setting)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var shadow_count := 0
	for index in mini(MAX_GLOW_LIGHTS, candidates.size()):
		var setting := candidates[index]
		setting.visible = true
		if shadows_allowed and float(setting.distance) <= SHADOW_DISTANCE and shadow_count < MAX_SHADOW_LIGHTS:
			setting.shadows = true
			shadow_count += 1
	# Apply the complete decision once, avoiding shadow-atlas churn every .2s.
	for setting in settings:
		var light := setting.light as SpotLight3D
		if light.visible != bool(setting.visible):
			light.visible = setting.visible
		if light.shadow_enabled != bool(setting.shadows):
			light.shadow_enabled = setting.shadows

	_visible_animated.clear()
	for display in _animated:
		if _in_view.get(display, true) and display.is_visible_in_tree() and bool(display.get("powered")):
			_visible_animated.append(display)
	_cached_shadows = shadows_allowed
	_lighting_dirty = not capture_inputs
	if capture_inputs:
		_cached_view = _view_state(camera)
		_remember_inputs()


func _update_view(display: Node3D, camera: Camera3D) -> void:
	var seen := camera == null or camera.is_position_in_frustum(display.global_position) \
		or camera.global_position.distance_to(display.global_position) <= ALWAYS_TICK_DISTANCE
	if seen and not _in_view.get(display, true):
		_next_frame_time = 0.0
	_in_view[display] = seen
