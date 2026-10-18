extends Node
## Planner panel for plates: a fruit switch, a count of 1-5 and a new random layout.
## Works on the selected plate, or on the palette preview until it is placed.

var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var enabled: CheckBox
var count: SpinBox
var reroll: Button
var _updating := false
# What the next placed plate starts with (kept between placements).
var defaults := {"enabled": false, "count": 3}


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "FruitOptions"
	title = Label.new()
	panel.add_child(title)
	enabled = CheckBox.new()
	enabled.text = "Фрукты на тарелке"
	enabled.toggled.connect(_changed)
	panel.add_child(enabled)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Количество"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	count = SpinBox.new()
	count.min_value = 1
	count.max_value = 5
	count.step = 1
	count.value = 3
	count.value_changed.connect(_changed)
	row.add_child(count)
	panel.add_child(row)
	reroll = Button.new()
	reroll.text = "Другая раскладка"
	reroll.pressed.connect(_reroll)
	panel.add_child(reroll)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func applies_to(target: Node3D) -> bool:
	return target != null and target.has_method("has_fruit") and target.call("has_fruit")


func update() -> void:
	var target := _target()
	panel.visible = applies_to(target)
	if not panel.visible:
		return
	_updating = true
	var config: Dictionary = target.call("get_fruit_config")
	title.text = "ТАРЕЛКА" + ("" if objects.selected != null else " | размещение")
	enabled.set_pressed_no_signal(bool(config["enabled"]))
	count.set_value_no_signal(float(config["count"]))
	count.editable = bool(config["enabled"])
	reroll.disabled = not bool(config["enabled"])
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


## A freshly created plate starts with the options last chosen in the panel.
func configure_new(target: Node3D) -> void:
	if applies_to(target) and bool(defaults["enabled"]):
		target.call("configure_fruit", defaults)


func _apply(config: Dictionary) -> void:
	var target := _target()
	if target == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	target.call("configure_fruit", config)
	if objects.selected == null:
		defaults = {"enabled": config["enabled"], "count": config["count"]}
	update()


func _changed(_value: Variant = null) -> void:
	if _updating or _target() == null:
		return
	var config: Dictionary = _target().call("get_fruit_config")
	config["enabled"] = enabled.button_pressed
	config["count"] = int(count.value)
	_apply(config)


func _reroll() -> void:
	if _target() == null:
		return
	var config: Dictionary = _target().call("get_fruit_config")
	config["seed"] = randi_range(1, 2147483646)
	_apply(config)
