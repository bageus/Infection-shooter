extends Node

var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var power: OptionButton
var content: OptionButton
var reroll: Button
var _updating := false
var defaults := {"power": "auto", "content": "static"}


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "DisplayOptions"
	title = Label.new()
	panel.add_child(title)
	power = _choice("Питание", ["Включён", "Выключен", "Авто (случайно)"])
	content = _choice("Изображение", ["Статическое", "Динамическое"])
	power.item_selected.connect(_changed)
	content.item_selected.connect(_changed)
	reroll = Button.new()
	reroll.text = "Другое случайное изображение"
	reroll.pressed.connect(_reroll)
	panel.add_child(reroll)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func _choice(label_text: String, labels: Array) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: String in labels:
		choice.add_item(item)
	row.add_child(choice)
	panel.add_child(row)
	return choice


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func update() -> void:
	var target := _target()
	var applicable: bool = target != null and target.has_method("has_display") and target.call("has_display")
	panel.visible = applicable
	if not applicable:
		return
	_updating = true
	var config: Dictionary = target.call("get_display_config")
	title.text = "ДИСПЛЕЙ" if objects.selected != null else "ДИСПЛЕЙ | размещение"
	power.select(["on", "off", "auto"].find(str(config["power"])))
	content.select(1 if str(config["content"]) == "dynamic" else 0)
	content.disabled = "wall_TV" in str(target.get("model_path"))
	content.tooltip_text = "На телевизорах всегда динамическая заставка" if content.disabled else ""
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


func configure_new(target: Node3D) -> void:
	if target.has_method("has_display") and target.call("has_display"):
		if objects.preview != null and objects.preview != target and objects.preview.has_method("has_display") and objects.preview.call("has_display"):
			target.call("configure_display", objects.preview.call("get_display_config"))
		else:
			target.call("configure_display", defaults)


func _changed(_index: int) -> void:
	if _updating:
		return
	var target := _target()
	if target == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	var config: Dictionary = target.call("get_display_config")
	config["power"] = ["on", "off", "auto"][power.selected]
	config["content"] = "dynamic" if content.selected == 1 else "static"
	target.call("configure_display", config)
	if objects.selected == null:
		defaults = {"power": config["power"], "content": config["content"]}
	update()


func _reroll() -> void:
	var target := _target()
	if target == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	var config: Dictionary = target.call("get_display_config")
	config["seed"] = randi_range(1, 2147483646)
	target.call("configure_display", config)
