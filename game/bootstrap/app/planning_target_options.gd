extends Node
## Planner panel: marks a bottle, loot crate, fire extinguisher or door as a tutorial target.
## Works on the selected object, or on the palette preview until it is placed.

const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")

var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var enabled: CheckBox
var _updating := false
# What the next placed object starts with (kept between placements).
var default_enabled := false


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "TargetOptions"
	title = Label.new()
	panel.add_child(title)
	enabled = CheckBox.new()
	enabled.text = "Цель (маркер и стрелка)"
	enabled.toggled.connect(_changed)
	panel.add_child(enabled)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func applies_to(target: Node3D) -> bool:
	return TARGET.applies_to(target)


func update() -> void:
	var target := _target()
	panel.visible = applies_to(target)
	if not panel.visible:
		return
	_updating = true
	title.text = "ЦЕЛЬ: " + _kind_label(TARGET.kind_of(target)) + ("" if objects.selected != null else " | размещение")
	enabled.set_pressed_no_signal(TARGET.is_target(target))
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


## A freshly created object starts with the switch last chosen in the panel.
func configure_new(target: Node3D) -> void:
	if applies_to(target) and default_enabled:
		TARGET.configure(target, true)


func _kind_label(kind: String) -> String:
	return {"bottle": "бутылка", "crate": "ящик", "extinguisher": "огнетушитель", "door": "дверь"}.get(kind, "")


func _changed(_value: Variant = null) -> void:
	var target := _target()
	if _updating or target == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	else:
		default_enabled = enabled.button_pressed
	TARGET.configure(target, enabled.button_pressed)
	update()
