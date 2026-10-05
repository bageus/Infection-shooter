extends RefCounted

const SHAPES := ["point", "linear", "rectangle"]
const LABELS := ["Точечный", "Длинный узкий", "Прямоугольный"]
var controls: Node
var default_visible: CheckButton
var selected_panel: VBoxContainer
var selected_shape: OptionButton
var selected_visible: CheckButton
var _updating := false


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	var panel: Control = controls.session.ui.get_node("Panel")
	panel.add_theme_stylebox_override("panel", panel.get_theme_stylebox("panel", "PanelContainer"))
	default_visible = CheckButton.new()
	default_visible.text = "Виден в игре"
	default_visible.button_pressed = true
	default_visible.tooltip_text = "Видимость корпуса новых светильников. Свет настраивается отдельно."
	controls.light_defaults.add_child(default_visible)
	default_visible.toggled.connect(_on_default_visibility_changed)
	selected_panel = VBoxContainer.new()
	selected_panel.name = "SelectedFixture"
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Форма"
	row.add_child(label)
	selected_shape = OptionButton.new()
	for title: String in LABELS:
		selected_shape.add_item(title)
	row.add_child(selected_shape)
	selected_panel.add_child(row)
	selected_visible = CheckButton.new()
	selected_visible.text = "Виден в игре"
	selected_visible.tooltip_text = "Скрывается только корпус; источник света продолжает работать."
	selected_panel.add_child(selected_visible)
	var help := Label.new()
	help.text = "Размер: + / −; оси: X/Z, C/V"
	help.add_theme_font_size_override("font_size", 14)
	selected_panel.add_child(help)
	var box: Node = controls.session.ui.get_node("Panel/VBox")
	box.add_child(selected_panel)
	box.move_child(selected_panel, controls.light_defaults.get_index() + 1)
	selected_panel.hide()
	selected_shape.item_selected.connect(_on_shape_changed)
	selected_visible.toggled.connect(_on_visibility_changed)


func configure_new_asset(node: Node3D, entry: Dictionary) -> void:
	if str(entry.get("kind", "")) == "light" and node.has_method("configure_fixture"):
		node.call("configure_fixture", str(entry.get("fixture_shape", "point")), default_visible.button_pressed)


func update_selection(node: Node3D) -> void:
	selected_panel.visible = node != null and node.has_method("get_fixture_config")
	if not selected_panel.visible:
		return
	var config: Dictionary = node.call("get_fixture_config")
	_updating = true
	selected_shape.select(maxi(SHAPES.find(str(config["shape"])), 0))
	selected_visible.set_pressed_no_signal(bool(config["visible_in_game"]))
	_updating = false


func _on_default_visibility_changed(_enabled: bool) -> void:
	if controls.objects._selected_kind() == "light":
		controls.objects._rebuild_preview()


func _on_shape_changed(_index: int) -> void:
	_apply_selected()


func _on_visibility_changed(_enabled: bool) -> void:
	_apply_selected()


func _apply_selected() -> void:
	var node: Node3D = controls.objects.selected
	if _updating or node == null or not node.has_method("configure_fixture"):
		return
	var config: Dictionary = node.call("get_fixture_config")
	var shape: String = SHAPES[selected_shape.selected]
	var shown := selected_visible.button_pressed
	if str(config["shape"]) == shape and bool(config["visible_in_game"]) == shown:
		return
	controls.session.edit_history.call("record_transform", node)
	node.call("configure_fixture", shape, shown)
	controls.session.geometry._clear_selection_highlight()
	controls.session.geometry._show_selection_highlight(node)
	controls.status.text = "СВЕТИЛЬНИК | " + LABELS[selected_shape.selected] + (" | виден в игре" if shown else " | скрыт в игре")
