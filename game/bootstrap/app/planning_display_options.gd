extends Node

var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var power: OptionButton
var content: OptionButton
var reroll: Button
var range_slider: HSlider
var angle_slider: HSlider
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
	range_slider = _slider("Дальность", 1.0, 12.0, 0.5)
	angle_slider = _slider("Угол", 10.0, 80.0, 1.0)
	range_slider.value_changed.connect(_shape_changed)
	angle_slider.value_changed.connect(_shape_changed)
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


func _slider(label_text: String, low: float, high: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	panel.add_child(row)
	return slider


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func applies_to(target: Node3D) -> bool:
	return target != null and target.has_method("has_display") and target.call("has_display")


func _is_lamp(target: Node3D) -> bool:
	return target.has_method("is_lamp") and target.call("is_lamp")


func update() -> void:
	var target := _target()
	var applicable := applies_to(target)
	panel.visible = applicable
	if not applicable:
		return
	_updating = true
	var config: Dictionary = target.call("get_display_config")
	var lamp := _is_lamp(target)
	var suffix := "" if objects.selected != null else " | размещение"
	title.text = ("ЛАМПА" if lamp else "ДИСПЛЕЙ") + suffix
	# A lamp is simply on or off; screens also have the random "auto" state and content.
	power.set_item_disabled(2, lamp)
	power.select(1 if str(config["power"]) == "off" else (0 if lamp else ["on", "off", "auto"].find(str(config["power"]))))
	content.get_parent().visible = not lamp
	reroll.visible = not lamp
	content.select(1 if str(config["content"]) == "dynamic" else 0)
	content.disabled = "wall_TV" in str(target.get("model_path"))
	content.tooltip_text = "На телевизорах всегда динамическая заставка" if content.disabled else ""
	# Only directional lamps (floodlight, operating lamp) have a range and a cone angle.
	var directional := config.has("range")
	range_slider.get_parent().visible = directional
	angle_slider.get_parent().visible = directional
	range_slider.value = float(config.get("range", 0.0))
	angle_slider.value = float(config.get("angle", 0.0))
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
	if config.has("range"):
		config["range"] = range_slider.value
		config["angle"] = angle_slider.value
	target.call("configure_display", config)
	if objects.selected == null:
		defaults = {"power": config["power"], "content": config["content"]}
	update()


func _shape_changed(_value: float) -> void:
	_changed(0)


func _reroll() -> void:
	var target := _target()
	if target == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	var config: Dictionary = target.call("get_display_config")
	config["seed"] = randi_range(1, 2147483646)
	target.call("configure_display", config)
