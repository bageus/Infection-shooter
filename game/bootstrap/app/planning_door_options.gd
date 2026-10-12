extends Node
## Planner panel: whether a door is open, closed (the emergency key opens it) or
## sealed for good. Works on the selected door, or on the palette preview until it is placed.

# Same ids as interactive_door.gd (LOCK_STATES), in menu order.
const LOCK_STATES := [&"open", &"key", &"sealed"]
const STATE_LABELS := ["Открыта", "Закрыта, открывается ключом", "Заперта навсегда"]

var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var state: OptionButton
var _updating := false


## The door controller of a placed or previewed object, or null when it is not a lockable door.
static func lockable_controller(node: Node) -> Node:
	if node == null:
		return null
	var controller := node.get_node_or_null("DoorController")
	if controller != null and controller.has_method("is_lockable") and bool(controller.call("is_lockable")):
		return controller
	return null


static func is_valid_state(value: Variant) -> bool:
	return LOCK_STATES.has(StringName(str(value)))


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "DoorOptions"
	title = Label.new()
	panel.add_child(title)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Состояние"
	row.add_child(label)
	state = OptionButton.new()
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text: String in STATE_LABELS:
		state.add_item(text)
	state.item_selected.connect(_changed)
	row.add_child(state)
	panel.add_child(row)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func update() -> void:
	var controller := lockable_controller(_target())
	panel.visible = controller != null
	if not panel.visible:
		return
	_updating = true
	var suffix := "" if objects.selected != null else " | размещение"
	title.text = "ДВЕРЬ" + suffix
	state.select(maxi(LOCK_STATES.find(controller.call("get_lock_state")), 0))
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


func _changed(_index: int = 0) -> void:
	if _updating:
		return
	var target := _target()
	var controller := lockable_controller(target)
	if controller == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	controller.call("configure_lock_state", LOCK_STATES[state.selected])
	update()
