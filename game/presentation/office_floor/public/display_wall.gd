extends Node

const CONTENT := preload("res://game/presentation/office_floor/display_content.gd")
const LAYOUT := preload("res://game/presentation/office_floor/display_wall_layout.gd")

var content := CONTENT.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
var displays: Array[Node3D] = []
var elapsed := 0.0
var _animated: Array[Node3D] = []
var _frames: Array[Vector4] = []
var _next_frame_time := 0.0
var dirty := false
var _layout_wait := 0.0
var _layout := LAYOUT.new()
var _lighting_wait := 0.0
const MAX_GLOW_LIGHTS := 16
const MAX_SHADOW_LIGHTS := 4
const GLOW_DISTANCE := 24.0
const SHADOW_DISTANCE := 16.0


func register_display(display: Node3D) -> void:
	if not displays.has(display):
		displays.append(display)
	update_animation(display)
	request_layout()
	_lighting_wait = 0.0


func unregister_display(display: Node3D) -> void:
	displays.erase(display)
	_animated.erase(display)
	request_layout()
	_lighting_wait = 0.0


func request_layout() -> void:
	dirty = true


func _process(delta: float) -> void:
	elapsed += delta
	_lighting_wait -= delta
	if _lighting_wait <= 0.0:
		_lighting_wait = .2
		_refresh_lights()
	_layout_wait -= delta
	if dirty and _layout_wait <= 0.0:
		_layout_wait = .15
		dirty = false
		_layout.apply(displays)
	if _animated.is_empty() or elapsed < _next_frame_time:
		return
	_frames.clear()
	var delay := INF
	for i in range(3):
		_frames.append(content.frame_rect(i, elapsed))
		delay = minf(delay, content.frame_delay(i, elapsed))
	_next_frame_time = elapsed + delay
	for display in _animated:
		display.call("tick", elapsed, _frames)


# Called locally by a display whenever its powered/content state changes.
func update_animation(display: Node3D) -> void:
	_lighting_wait = 0.0
	_animated.erase(display)
	if display.get("powered"):
		for screen: Dictionary in display.get("screens"):
			if screen["dynamic"]:
				_animated.append(display)
				break
	_next_frame_time = 0.0


func _refresh_lights() -> void:
	var camera := get_viewport().get_camera_3d()
	var settings: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []
	for display in displays:
		if not is_instance_valid(display):
			continue
		for screen: Dictionary in display.get("screens"):
			var light := screen.light as SpotLight3D
			var powered := bool(display.get("powered")) and display.is_visible_in_tree()
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
		if float(setting.distance) <= SHADOW_DISTANCE and shadow_count < MAX_SHADOW_LIGHTS:
			setting.shadows = true
			shadow_count += 1
	# Apply the complete decision once, avoiding shadow-atlas churn every .2s.
	for setting in settings:
		var light := setting.light as SpotLight3D
		if light.visible != bool(setting.visible):
			light.visible = setting.visible
		if light.shadow_enabled != bool(setting.shadows):
			light.shadow_enabled = setting.shadows
