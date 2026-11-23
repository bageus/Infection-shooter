extends Node
## Planner panel for a floor flare: whether it ignites when the player comes close.
## Works on the selected flare, or on the palette preview until it is placed.

var session: Variant
var objects: Variant
var panel: VBoxContainer
var enabled: CheckBox
var _updating := false
# What the next placed flare starts with (kept between placements).
var default_enabled := true


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "FlareOptions"
	enabled = CheckBox.new()
	enabled.text = "Загорается при подходе"
	enabled.tooltip_text = "Выкл: фаер остаётся темным на всю миссию."
	enabled.toggled.connect(_changed)
	panel.add_child(enabled)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func applies_to(target: Node3D) -> bool:
	return target != null and target.has_method("is_flare_enabled")


func update() -> void:
	var target := _target()
	panel.visible = applies_to(target)
	if not panel.visible:
		return
	_updating = true
	enabled.set_pressed_no_signal(bool(target.call("is_flare_enabled")))
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


## A freshly placed flare starts with the switch last chosen in the panel.
func configure_new(target: Node3D) -> void:
	if applies_to(target):
		target.call("set_flare_enabled", default_enabled)


func _changed(_value: Variant = null) -> void:
	var target := _target()
	if _updating or target == null:
		return
	if objects.selected != null:
		if bool(target.call("is_flare_enabled")) == enabled.button_pressed:
			return
		session.edit_history.call("record_transform", target)
	else:
		default_enabled = enabled.button_pressed
	target.call("set_flare_enabled", enabled.button_pressed)
