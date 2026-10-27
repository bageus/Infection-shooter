extends Node
## Location field size: an optional map setting that resizes the floor and the collision under it.
const DEFAULT_SIZE := Vector2(80.0, 60.0)
const LIMITS := Vector2(10.0, 400.0)
const KEY := "floor_size_v1"

var session: Variant
var width: SpinBox
var depth: SpinBox


static func valid(raw: Variant) -> bool:
	if not raw is Array or (raw as Array).size() != 2:
		return false
	for value: Variant in raw:
		if not (value is float or value is int) or float(value) < LIMITS.x or float(value) > LIMITS.y:
			return false
	return true


static func capture(session_context: Variant) -> Array:
	var floor_view := _floor(session_context)
	if floor_view == null:
		return []
	var size: Vector2 = floor_view.get("floor_size")
	return [size.x, size.y]


## A map without the key restores the default size, so a previous map's field never carries over.
static func restore(session_context: Variant, raw: Variant) -> void:
	var floor_view := _floor(session_context)
	if floor_view == null:
		return
	var size := Vector2(float(raw[0]), float(raw[1])) if valid(raw) else DEFAULT_SIZE
	floor_view.call("set_floor_size", size)
	var host: Node = session_context.get("host")
	var body := host.get_node_or_null("FloorBody") as StaticBody3D
	if body == null:
		return
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		box.size = Vector3(size.x, box.size.y, size.y)


static func _floor(session_context: Variant) -> Node3D:
	var host: Variant = session_context.get("host") if session_context is Node else null
	if host is Node:
		var floor_view := host.get_node_or_null("Floor") as Node3D
		if floor_view != null and floor_view.has_method("set_floor_size"):
			return floor_view
	return null


func setup(context: Variant) -> void:
	session = context


func build_row() -> Control:
	var box := VBoxContainer.new()
	box.name = "FloorSize"
	var title := Label.new()
	title.text = "Поле локации, м (ширина × глубина)"
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	width = _spin(row)
	depth = _spin(row)
	session.ui.visibility_changed.connect(refresh)
	refresh()
	return box


func refresh() -> void:
	var size: Array = capture(session)
	if size.is_empty() or width == null:
		return
	width.set_value_no_signal(size[0])
	depth.set_value_no_signal(size[1])


func _spin(row: Container) -> SpinBox:
	var input := SpinBox.new()
	input.min_value = LIMITS.x
	input.max_value = LIMITS.y
	input.step = 1.0
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.value_changed.connect(_size_changed)
	row.add_child(input)
	return input


func _size_changed(_value: float) -> void:
	restore(session, [width.value, depth.value])
