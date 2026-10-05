extends Node

const CONTENT := preload("res://game/presentation/office_floor/display_content.gd")
const LAYOUT := preload("res://game/presentation/office_floor/display_wall_layout.gd")

var content := CONTENT.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
var displays: Array[Node3D] = []
var elapsed := 0.0
var dirty := false
var _layout_wait := 0.0
var _layout := LAYOUT.new()


func register_display(display: Node3D) -> void:
	if not displays.has(display):
		displays.append(display)
	request_layout()


func unregister_display(display: Node3D) -> void:
	displays.erase(display)
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
	var frames: Array[Vector4] = []
	for i in range(3):
		frames.append(content.frame_rect(i, elapsed))
	for display in displays:
		display.call("tick", elapsed, frames)
