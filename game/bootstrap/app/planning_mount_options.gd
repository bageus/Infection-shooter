extends Node
## Pipes and ducts: hug a wall, or stand apart from it.

const WALL_MOUNT := preload("res://game/presentation/office_floor/public/wall_mount_models.gd")
var session: Variant
var objects: Variant
var panel: VBoxContainer
var mount: OptionButton
var _updating := false
var default_attached := true


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "MountOptions"
	var title := Label.new()
	title.text = "КРЕПЛЕНИЕ"
	panel.add_child(title)
	mount = OptionButton.new()
	mount.add_item("У стены")
	mount.add_item("Отдельно")
	mount.item_selected.connect(_changed)
	panel.add_child(mount)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func applies_to(target: Node3D) -> bool:
	return target != null and target.has_method("is_wall_mounted") and WALL_MOUNT.is_adjustable(str(target.get("model_path")))


func update() -> void:
	var target := _target()
	panel.visible = applies_to(target)
	if not panel.visible:
		return
	_updating = true
	mount.select(0 if bool(target.call("is_wall_mounted")) else 1)
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


# A new piece takes the last choice made for a new piece.
func configure_new(target: Node3D) -> void:
	if applies_to(target):
		target.call("configure_wall_mount", default_attached)


func _changed(index: int) -> void:
	if _updating:
		return
	var target := _target()
	if target == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	else:
		default_attached = index == 0
	target.call("configure_wall_mount", index == 0)
	update()
