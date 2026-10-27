extends RefCounted
## Planner-only panel composition after all widget owners have connected their signals.
var right: Control
var right_content: Control
var right_tabs: TabContainer
var main: VBoxContainer
var constructor: VBoxContainer
var collapse: Button
var selection: PanelContainer
var center: VBoxContainer
var help_scroll: ScrollContainer
var selected_name: Label
var collapsed := false
var _controls: Node


func setup(controls: Node) -> void:
	_controls = controls
	var ui: Control = controls.session.ui
	var left := ui.get_node("Panel") as ScrollContainer
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	left.add_theme_stylebox_override("panel", _style())
	var box := left.get_node("VBox")
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var old_tabs := box.get_node("Tabs")
	var tabs := GridContainer.new()
	tabs.name = "Tabs"
	tabs.columns = 3
	box.remove_child(old_tabs)
	box.add_child(tabs)
	box.move_child(tabs, 0)
	var palette_group := ButtonGroup.new()
	for button: Button in old_tabs.get_children():
		button.reparent(tabs)
		button.toggle_mode = true
		button.button_group = palette_group
		button.button_pressed = button.name == &"Structure"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	old_tabs.queue_free()
	controls.palette.custom_minimum_size.x = 0
	controls.palette.fixed_column_width = 0
	controls.palette.clip_contents = true
	right = ui.get_node("RightPanel")
	right.offset_top = 8
	right.offset_left = -368
	right.offset_right = -8
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	right.add_theme_stylebox_override("panel", _style())
	var right_box := right.get_node("VBox")
	right_box.custom_minimum_size.x = 0
	right_content = VBoxContainer.new()
	right_content.name = "Content"
	right_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(right_content)
	right_box.reparent(right_content)
	_build_right_tabs(right_box, box)
	# The restore handle stays outside the hidden content and works without a world click.
	collapse = Button.new()
	collapse.name = "TogglePlanningHUD"
	collapse.text = "›"
	collapse.tooltip_text = "Скрыть / показать правое меню"
	collapse.custom_minimum_size = Vector2(28, 36)
	ui.add_child(collapse)
	collapse.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	collapse.offset_left = -400
	collapse.offset_right = -372
	collapse.offset_top = 8
	collapse.offset_bottom = 44
	collapse.pressed.connect(toggle_right)
	_build_center(controls, ui, box)


func _build_center(controls: Node, ui: Control, box: Node) -> void:
	# Wave settings share the palette scroll instead of covering the center HUD.
	var waves: Control = controls.spawn_options.panel
	waves.reparent(box)
	box.move_child(waves, controls.palette.get_index())
	waves.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	waves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center = VBoxContainer.new()
	center.name = "PlanningCenterHUD"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_theme_constant_override("separation", 4)
	ui.add_child(center)
	controls.planning_toolbar.reparent(center)
	var actions: Node = controls.undo_button.get_parent()
	controls.help_button.reparent(actions)
	for action: Button in [controls.undo_button, controls.duplicate_button]:
		action.clip_text = true
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.add_theme_font_size_override("font_size", 14)
	selection = PanelContainer.new()
	selection.name = "SelectedObjectHUD"
	center.add_child(selection)
	selection.add_theme_stylebox_override("panel", _style())
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	selection.add_child(info)
	selected_name = Label.new()
	selected_name.name = "ObjectName"
	selected_name.max_lines_visible = 1
	selected_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selected_name.clip_text = true
	selected_name.add_theme_font_size_override("font_size", 12)
	info.add_child(selected_name)
	controls.status.reparent(info)
	controls.status.custom_minimum_size = Vector2.ZERO
	controls.status.clip_text = true
	controls.status.max_lines_visible = 1
	controls.status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	controls.status.autowrap_mode = TextServer.AUTOWRAP_OFF
	controls.status.add_theme_font_size_override("font_size", 12)
	controls.status.mouse_entered.connect(_status_tooltip)
	help_scroll = ScrollContainer.new()
	help_scroll.name = "PlanningHelpScroll"
	help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(help_scroll)
	var help_panel := ui.get_node("HelpPanel") as Control
	help_panel.reparent(help_scroll)
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	help_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_panel.visibility_changed.connect(func() -> void: help_scroll.visible = help_panel.visible)
	help_scroll.hide()
	ui.resized.connect(_resize_center)
	_resize_center()
	controls.planning_toolbar.visibility_changed.connect(_toolbar_visibility_changed)
	update_selection(controls)


func _build_right_tabs(right_box: Node, left_box: Node) -> void:
	right_tabs = TabContainer.new()
	right_tabs.name = "PlanningTabs"
	right_content.add_child(right_tabs)
	main = VBoxContainer.new()
	main.name = "Основная"
	right_tabs.add_child(main)
	constructor = VBoxContainer.new()
	constructor.name = "Конструктор"
	right_tabs.add_child(constructor)
	right_tabs.add_child(_controls.group_templates.build_tab())
	for child in right_box.get_children():
		child.reparent(main if child.name in [&"MapManager", &"Save"] else constructor)
	right_box.queue_free()
	var floor_row: Control = _controls.floor_size.build_row()
	main.add_child(floor_row)
	main.move_child(floor_row, 0)
	for node_name in ["LightingPreview", "LocalLights", "FogOfWarToggle", "AutoFireAlarms", "AutoLightSwitches", "SurfaceDecalSettings", "LightTopView", "Clear", "Close"]:
		var child := left_box.get_node(node_name) as Control
		child.reparent(main)
		child.show()
	# Long names never determine the panel width; the complete value is in its tooltip.
	var maps := main.get_node("MapManager/Maps") as OptionButton
	maps.fit_to_longest_item = false
	maps.clip_text = true
	maps.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for child in main.get_children():
		if child is Button:
			child.clip_text = true
			child.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _toolbar_visibility_changed() -> void:
	selection.visible = _controls.planning_toolbar.visible
	collapse.visible = selection.visible
	right.visible = selection.visible and not collapsed


func toggle_right() -> void:
	collapsed = not collapsed
	right.visible = not collapsed
	collapse.text = "›" if right.visible else "‹"
	collapse.offset_left = -400 if right.visible else -36
	collapse.offset_right = -372 if right.visible else -8
	_resize_center()


func contains_point(point: Vector2) -> bool:
	for control: Control in [right, collapse, selection, _controls.help_button, help_scroll]:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return true
	return false


func _resize_center() -> void:
	var ui: Control = _controls.session.ui
	var left: Control = ui.get_node("Panel")
	var start := left.position.x + left.size.x + 8
	var end := ui.size.x + collapse.offset_left - 8
	var width := minf(400, maxf(1, end - start))
	center.position = Vector2(start + (end - start - width) * .5, 8)
	center.size.x = width
	help_scroll.custom_minimum_size.y = maxf(40, ui.size.y - 108)


func _status_tooltip() -> void:
	_controls.status.tooltip_text = _controls.status.text


func update_selection(controls: Node) -> void:
	if selected_name == null:
		return
	var target: Node3D = controls.objects.selected
	if not is_instance_valid(target):
		selected_name.text = "Объект не выбран"
		selected_name.tooltip_text = ""
		return
	var path := str(target.get_meta("planning_scene_path", target.scene_file_path))
	var title := path.get_file().get_basename()
	if target.has_method("get_blood_config"):
		title = str(target.call("get_blood_config").texture)
	elif target.get("model_path") is String and not str(target.get("model_path")).is_empty():
		title = str(target.get("model_path")).get_file().get_basename()
	if title.is_empty():
		title = str(target.name)
	selected_name.text = "Выбран: " + title
	selected_name.tooltip_text = path + "\n" + str(target.name)


func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.005, 0.025, 0.045, 0.94)
	style.border_color = Color(0.02, 0.72, 0.98, 0.8)
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	return style
