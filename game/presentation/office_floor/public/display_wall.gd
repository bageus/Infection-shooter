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


func register_display(display: Node3D) -> void:
	if not displays.has(display):
		displays.append(display)
	request_layout()


func unregister_display(display: Node3D) -> void:
	displays.erase(display)
	_animated.erase(display)
	request_layout()


func request_layout() -> void:
	dirty = true


func _process(delta: float) -> void:
	elapsed += delta
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
	_animated.erase(display)
	if display.get("powered"):
		for screen: Dictionary in display.get("screens"):
			if screen["dynamic"]:
				_animated.append(display)
				break
	_next_frame_time = 0.0
