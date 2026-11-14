extends Node
## Planner panel: destruction level of a dead infected (how many limbs are already torn off).
## Works on the selected corpse, or on the palette preview until it is placed.

var session: Variant
var objects: Variant
var panel: VBoxContainer
var level: OptionButton
var _updating := false
# What the next placed corpse starts with (kept between placements).
var default_level := 0


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "CorpseOptions"
	var title := Label.new()
	title.text = "ТЕЛО"
	panel.add_child(title)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Разрушение"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	level = OptionButton.new()
	level.item_selected.connect(_changed)
	row.add_child(level)
	panel.add_child(row)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func applies_to(target: Node3D) -> bool:
	return target != null and target.has_method("level_count") and target.has_method("configure_decor_pose")


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func update() -> void:
	var target := _target()
	panel.visible = applies_to(target)
	if not panel.visible:
		return
	_updating = true
	var count := int(target.call("level_count"))
	if level.item_count != count:
		level.clear()
		for index in count:
			level.add_item("Целое" if index == 0 else "Уровень %d" % index)
	level.select(clampi(int(target.get("destruction")), 0, count - 1))
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


## A freshly created corpse starts with the level last chosen in the panel.
func configure_new(target: Node3D) -> void:
	if applies_to(target) and default_level > 0:
		var config: Dictionary = target.call("get_decor_pose")
		config["destruction"] = mini(default_level, int(target.call("level_count")) - 1)
		target.call("configure_decor_pose", config)


func _changed(_index: int = 0) -> void:
	var target := _target()
	if _updating or not applies_to(target):
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	var config: Dictionary = target.call("get_decor_pose")
	config["destruction"] = level.selected
	target.call("configure_decor_pose", config)
	if objects.selected == null:
		default_level = level.selected
	update()
