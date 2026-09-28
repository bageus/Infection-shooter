extends CanvasLayer

const TREE_CANVAS := preload("res://game/bootstrap/app/mutation_tree_canvas.gd")

var runtime: Node
var panel: PanelContainer
var points_label: Label
var content: VBoxContainer
var hotbar: HBoxContainer
var _last_skill_tier := -1


func configure(infection: Node) -> void:
	runtime = infection
	layer = 120
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -320
	panel.offset_bottom = 320
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := HBoxContainer.new()
	layout.add_child(title)
	points_label = Label.new()
	points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(points_label)
	var close := Button.new()
	close.text = "Close [Esc / M]"
	close.pressed.connect(close_tree)
	title.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scroll)
	content = VBoxContainer.new()
	scroll.add_child(content)
	var hint := Label.new()
	hint.text = "Click a circle to unlock a skill. Hover for details. Lock a learned skill to keep it when mutation drops."
	layout.add_child(hint)
	panel.hide()
	var bar_panel := PanelContainer.new()
	bar_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar_panel.position = Vector2(12, -76)
	root.add_child(bar_panel)
	var bar_scroll := ScrollContainer.new()
	bar_scroll.custom_minimum_size = Vector2(640, 58)
	bar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bar_panel.add_child(bar_scroll)
	hotbar = HBoxContainer.new()
	bar_scroll.add_child(hotbar)
	runtime.connect("tree_changed", _refresh)
	runtime.connect("mutation_changed", _on_mutation_changed)
	_refresh()


func _on_mutation_changed(amount: float, _limit: float) -> void:
	if panel.visible:
		points_label.text = "MUTATION %d%%    Points: %d" % [roundi(amount), runtime.call("mutation_points")]
	var tier := floori((amount - 25.0) / 15.0)
	if tier != _last_skill_tier:
		_last_skill_tier = tier
		_refresh()


func _input(event: InputEvent) -> void:
	if is_tree_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_tree()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			_set_open(not panel.visible)
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_4 and event.keycode <= KEY_7:
			var skills: Array[String] = _equipped()
			var index: int = int(event.keycode) - int(KEY_4)
			if index < skills.size():
				runtime.call("cast_skill", skills[index])
				get_viewport().set_input_as_handled()


func open_tree() -> void:
	_set_open(true)


func close_tree() -> void:
	_set_open(false)


func is_tree_open() -> bool:
	return panel != null and panel.visible


func _set_open(value: bool) -> void:
	panel.visible = value
	if runtime != null and runtime.get_parent() != null:
		runtime.get_parent().set("_mutation_menu_open", value)
	_refresh()


func _refresh() -> void:
	if runtime == null or content == null:
		return
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	for child in hotbar.get_children():
		hotbar.remove_child(child)
		child.queue_free()
	points_label.text = "MUTATION %d%%    Points: %d" % [roundi(runtime.call("get_mutation")), runtime.call("mutation_points")]
	var skills: Array = runtime.call("skill_catalog")
	var canvas := TREE_CANVAS.new() as Control
	content.add_child(canvas)
	var progress: Array[int] = []
	for branch_index in TREE_CANVAS.BRANCHES.size():
		var branch: String = TREE_CANVAS.BRANCHES[branch_index]
		var group_is_active := branch_index < 4
		var furthest := -1
		var center: Vector2 = canvas.call("skill_position", branch_index, 0)
		for row in skills:
			if int(row[3]) == 3 or str(row[2]) != branch or (skills.find(row) < 12) != group_is_active:
				continue
			var rank := int(row[3])
			_add_skill(canvas, row, canvas.call("skill_position", branch_index, rank))
			if bool(runtime.call("skill_learned", str(row[0]))):
				furthest = maxi(furthest, rank)
		var label := Label.new()
		label.text = branch.to_upper() + ("  ·  ACTIVE" if group_is_active else "  ·  PASSIVE")
		label.position = Vector2(20, center.y - 13)
		canvas.add_child(label)
		progress.append(furthest)
	canvas.call("set_progress", progress)
	var hybrid_label := Label.new()
	hybrid_label.text = "HYBRID SKILLS  ·  TWO BRANCHES REQUIRED"
	hybrid_label.position = Vector2(20, 790)
	canvas.add_child(hybrid_label)
	var hybrid_index := 0
	for row in skills:
		if int(row[3]) != 3:
			continue
		_add_skill(canvas, row, Vector2(1060 - hybrid_index * 150, 805))
		hybrid_index += 1
	var open := Button.new()
	open.text = "Mutations [M]"
	open.pressed.connect(open_tree)
	hotbar.add_child(open)
	var active_skills := _equipped()
	for index in active_skills.size():
		var row: Array = []
		for entry in skills:
			if entry[0] == active_skills[index]:
				row = entry
		if row.is_empty():
			continue
		var button := Button.new()
		button.text = "%s %s" % [str(index + 4) if index < 4 else "•", row[1]]
		button.tooltip_text = "%s\n%s" % [row[1], row[5]]
		var skill_id: String = active_skills[index]
		button.pressed.connect(func() -> void: runtime.call("cast_skill", skill_id))
		hotbar.add_child(button)


func _add_skill(canvas: Control, row: Array, center: Vector2) -> void:
	var skill_id := str(row[0])
	var level: float = 25.0 + float(row[3]) * 15.0
	var learned: bool = runtime.call("skill_learned", skill_id)
	var enabled: bool = runtime.call("has_skill", skill_id)
	var button := Button.new()
	button.text = str(row[4])
	button.position = center - Vector2(22, 22)
	button.custom_minimum_size = Vector2(44, 44)
	button.size = Vector2(44, 44)
	button.tooltip_text = "%s\n%s\nRequires %d%% mutation%s" % [row[1], row[5], roundi(level), " · Learned" if learned else ""]
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.57, 0.43) if enabled else (Color(0.29, 0.43, 0.48) if learned else Color(0.15, 0.20, 0.26))
	style.border_color = Color(0.59, 0.98, 0.79) if enabled else Color(0.42, 0.53, 0.58)
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.pressed.connect(func() -> void: runtime.call("upgrade_skill", skill_id))
	canvas.add_child(button)
	if learned:
		var lock := Button.new()
		lock.text = "L" if runtime.call("skill_locked", skill_id) else "+"
		lock.tooltip_text = "Locked: kept when mutation drops" if runtime.call("skill_locked", skill_id) else "Lock skill against mutation loss"
		lock.position = center + Vector2(18, 11)
		lock.custom_minimum_size = Vector2(24, 24)
		lock.size = Vector2(24, 24)
		lock.pressed.connect(func() -> void: runtime.call("toggle_skill_lock", skill_id))
		canvas.add_child(lock)


func _equipped() -> Array[String]:
	var result: Array[String] = []
	for row in runtime.call("skill_catalog").slice(0, 12):
		if runtime.call("has_skill", str(row[0])):
			result.append(str(row[0]))
	return result
