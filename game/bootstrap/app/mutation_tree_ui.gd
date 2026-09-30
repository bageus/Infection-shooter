extends CanvasLayer

const TREE_CANVAS := preload("res://game/bootstrap/app/mutation_tree_canvas.gd")

var runtime: Node
var panel: PanelContainer
var points_label: Label
var content: Control
var hotbar: HBoxContainer
var _last_skill_tier := -1
var _previous_pause := false


func configure(infection: Node) -> void:
	runtime = infection
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 12
	panel.offset_right = -12
	panel.offset_top = 12
	panel.offset_bottom = -12
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.015, 0.028, 0.045, 0.97)
	background.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", background)
	var layout := VBoxContainer.new()
	panel.add_child(layout)
	var title := HBoxContainer.new()
	layout.add_child(title)
	points_label = Label.new()
	points_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	points_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_child(points_label)
	var close := Button.new()
	close.text = "Close [Esc / M]"
	close.pressed.connect(close_tree)
	title.add_child(close)
	content = Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	layout.add_child(content)
	content.resized.connect(_fit_tree)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Click a circle to unlock a skill. Hover for details. Lock a learned skill to keep it when mutation drops."
	layout.add_child(hint)
	panel.hide()
	var bar_panel := PanelContainer.new()
	bar_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar_panel.offset_left = 18
	bar_panel.offset_right = 492
	bar_panel.offset_top = -216
	bar_panel.offset_bottom = -164
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.005, 0.035, 0.065, 0.95)
	frame.border_color = Color(0.02, 0.72, 0.98)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(12)
	bar_panel.add_theme_stylebox_override("panel", frame)
	root.add_child(bar_panel)
	var bar_scroll := ScrollContainer.new()
	bar_scroll.custom_minimum_size = Vector2(466, 46)
	bar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bar_panel.add_child(bar_scroll)
	hotbar = HBoxContainer.new()
	bar_scroll.add_child(hotbar)
	runtime.connect("tree_changed", _refresh)
	runtime.connect("mutation_changed", _on_mutation_changed)
	runtime.connect("skill_available", _on_new_skill_available)
	_refresh()


func _on_new_skill_available() -> void:
	if visible and not get_tree().paused:
		open_tree()


func _on_mutation_changed(amount: float, _limit: float) -> void:
	if panel.visible:
		points_label.text = "MUTATION %d%%    Points: %d    Stability: %d%%" % [roundi(amount), runtime.call("mutation_points"), roundi(runtime.call("get_critical_threshold"))]
		if content.get_child_count() > 0:
			content.get_child(0).call("set_mutation", amount)
	var tier := floori((amount - 25.0) / 5.0)
	if tier != _last_skill_tier:
		_last_skill_tier = tier
		_refresh()


func _input(event: InputEvent) -> void:
	if is_tree_open() and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F or event.physical_keycode == KEY_F):
		var player := runtime.get_parent()
		if player != null and player.has_method("use_antidote") and bool(player.call("use_antidote")):
			get_viewport().set_input_as_handled()
		return
	if is_tree_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_tree()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
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
	if panel.visible == value:
		return
	if value:
		_previous_pause = get_tree().paused
		get_tree().paused = true
	else:
		get_tree().paused = _previous_pause
	panel.visible = value
	hotbar.get_parent().get_parent().visible = not value
	if runtime != null and runtime.get_parent() != null:
		runtime.get_parent().set("_mutation_menu_open", value)
	_refresh()
	if value:
		_fit_tree.call_deferred()


func _fit_tree() -> void:
	if content == null or content.get_child_count() == 0:
		return
	var canvas := content.get_child(0) as Control
	var design_size: Vector2 = TREE_CANVAS.DESIGN_SIZE
	var factor := minf(content.size.x / design_size.x, content.size.y / design_size.y)
	canvas.scale = Vector2.ONE * factor
	canvas.position = Vector2(0.0, maxf(0.0, (content.size.y - design_size.y * factor) * 0.5))


func _refresh() -> void:
	if runtime == null or content == null:
		return
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	for child in hotbar.get_children():
		hotbar.remove_child(child)
		child.queue_free()
	points_label.text = "MUTATION %d%%    Points: %d    Stability: %d%%" % [roundi(runtime.call("get_mutation")), runtime.call("mutation_points"), roundi(runtime.call("get_critical_threshold"))]
	var skills: Array = runtime.call("skill_catalog")
	var canvas := TREE_CANVAS.new() as Control
	content.add_child(canvas)
	_fit_tree.call_deferred()
	var thresholds: Array[float] = []
	var opened: Array[bool] = []
	for branch_index in TREE_CANVAS.BRANCHES.size():
		for row in skills:
			if int(row[3]) == 0 and str(row[2]) == TREE_CANVAS.BRANCHES[branch_index] and (skills.find(row) < 12) == (branch_index < 4):
				var requirement: Dictionary = runtime.call("skill_requirements", str(row[0]))
				thresholds.append(float(requirement["mutation"]))
				opened.append(bool(requirement["branch_open"]))
	canvas.call("configure_progression", thresholds, float(runtime.call("get_mutation")), opened)
	_add_section_labels(canvas)
	var progress: Array[int] = []
	for branch_index in TREE_CANVAS.BRANCHES.size():
		var branch: String = TREE_CANVAS.BRANCHES[branch_index]
		var group_is_active := branch_index < 4
		var furthest := -1
		var requirements: Dictionary = {}
		for row in skills:
			if int(row[3]) == 3 or str(row[2]) != branch or (skills.find(row) < 12) != group_is_active:
				continue
			requirements = runtime.call("skill_requirements", str(row[0]))
			var rank := int(row[3])
			_add_skill(canvas, row, canvas.call("skill_position", branch_index, rank))
			if bool(requirements["path_reached"]):
				furthest = maxi(furthest, rank)
		var label := Label.new()
		label.text = branch.to_upper()
		label.modulate.a = 1.0 if bool(requirements["branch_open"]) else 0.35
		label.position = canvas.call("label_position", branch_index)
		label.add_theme_font_size_override("font_size", 14)
		var gate := Label.new()
		gate.text = "S%d · Stability %d%%%s" % [requirements["stage"], roundi(requirements["stability"]), " · Locked" if not requirements["branch_open"] else ""]
		gate.add_theme_font_size_override("font_size", 11)
		gate.position = label.position + Vector2(0, 20)
		canvas.add_child(gate)
		canvas.add_child(label)
		progress.append(furthest)
	var hybrid_index := 0
	var hybrids: Array[bool] = []
	for row in skills:
		if int(row[3]) != 3:
			continue
		_add_skill(canvas, row, canvas.call("hybrid_position", hybrid_index))
		hybrids.append(bool(runtime.call("skill_requirements", str(row[0]))["path_reached"]))
		hybrid_index += 1
	canvas.call("set_progress", progress, hybrids)
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
	var requirements: Dictionary = runtime.call("skill_requirements", skill_id)
	var level: float = requirements["mutation"]
	var learned: bool = runtime.call("skill_learned", skill_id)
	var enabled: bool = runtime.call("has_skill", skill_id)
	var available: bool = runtime.call("can_upgrade_skill", skill_id)
	var button := Button.new()
	button.text = str(row[4])
	button.position = center - Vector2(22, 22)
	button.custom_minimum_size = Vector2(44, 44)
	button.size = Vector2(44, 44)
	button.tooltip_text = "%s\n%s\nRequires %d%% mutation · %d%% stability\n%s%s" % [row[1], row[5], roundi(level), roundi(requirements["stability"]), "Branch open" if requirements["branch_open"] else "Collect DNA to open this branch", " · Learned" if learned else ""]
	button.disabled = not available
	button.modulate = Color.WHITE if bool(requirements["branch_open"]) else Color(0.35, 0.35, 0.35, 1.0)
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.45, 0.06) if enabled else (Color(0.21, 0.36, 0.12) if available else Color(0.22, 0.25, 0.28))
	style.border_color = Color(0.3, 0.95, 0.1) if enabled or available else Color(0.42, 0.53, 0.58)
	if available:
		style.shadow_color = Color(0.3, 0.95, 0.1, 0.36)
		style.shadow_size = 8
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.pressed.connect(func() -> void: runtime.call("upgrade_skill", skill_id))
	canvas.add_child(button)
	if learned:
		var lock := Button.new()
		lock.text = "L" if runtime.call("skill_locked", skill_id) else "+"
		lock.tooltip_text = "Locked: kept when mutation drops" if runtime.call("skill_locked", skill_id) else "Lock skill against mutation loss"
		lock.position = center + Vector2(35, -12)
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



func _add_section_labels(canvas: Control) -> void:
	for entry in [["ACTIVE", 185.0], ["PASSIVE", 490.0], ["HYBRID", 650.0]]:
		var label := Label.new()
		label.text = str(entry[0])
		label.position = Vector2(4, float(entry[1]))
		label.add_theme_font_size_override("font_size", 13)
		label.modulate = Color(0.72, 0.8, 0.86)
		canvas.add_child(label)
