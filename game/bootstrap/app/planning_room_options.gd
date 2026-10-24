extends Node
## Planner panel: joins exploration darkness zones into one room. Zones with the same
## room number open together with the room's doors and darken again when they close.

var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var room: SpinBox
var _updating := false


static func applies_to(node: Node) -> bool:
	return node != null and node.is_in_group("darkness_zone") and not bool(node.get("permanent"))


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "RoomOptions"
	title = Label.new()
	panel.add_child(title)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Комната № (0 — без группы)"
	row.add_child(label)
	room = SpinBox.new()
	room.min_value = 0
	room.max_value = 99
	room.step = 1
	room.value_changed.connect(_changed)
	row.add_child(room)
	panel.add_child(row)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func update() -> void:
	var target: Node3D = objects.selected
	panel.visible = applies_to(target)
	if not panel.visible:
		return
	_updating = true
	title.text = "ЗАТЕМНЕНИЕ | комната"
	room.value = int(target.get("room_id"))
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


func _changed(value: float) -> void:
	var target: Node3D = objects.selected
	if _updating or not applies_to(target):
		return
	target.set("room_id", int(value))
	target.set_meta("planning_room", int(value))
