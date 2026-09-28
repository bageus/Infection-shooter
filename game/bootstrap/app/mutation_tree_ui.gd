extends CanvasLayer

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
	panel.offset_left = -470
	panel.offset_right = 470
	panel.offset_top = -260
	panel.offset_bottom = 230
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
	close.text = "Закрыть  [M]"
	close.pressed.connect(func() -> void: _set_open(false))
	title.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scroll)
	content = VBoxContainer.new()
	scroll.add_child(content)
	var hint := Label.new()
	hint.text = "Нажмите на кружок для прокачки. Замок справа сохраняет навык при снижении мутации."
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
		points_label.text = "МУТАЦИИ  %d%%    Очки: %d" % [roundi(amount), runtime.call("mutation_points")]
	var tier := floori((amount - 25.0) / 15.0)
	if tier != _last_skill_tier:
		_last_skill_tier = tier
		_refresh()


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
	points_label.text = "МУТАЦИИ  %d%%    Очки: %d" % [roundi(runtime.call("get_mutation")), runtime.call("mutation_points")]
	var skills: Array = runtime.call("skill_catalog")
	for category in ["active", "passive"]:
		var heading := Label.new()
		heading.text = "АКТИВНЫЕ  ↑" if category == "active" else "ПАССИВНЫЕ  ↓"
		content.add_child(heading)
		var columns := HBoxContainer.new()
		content.add_child(columns)
		var branches := ["Биомасса", "Нейрошторм", "Токсичная мутация", "Хищная форма"] if category == "active" else ["Арсенал", "Хищник", "Биомасса", "Адаптация", "Нейросистема", "Метаболизм", "Гибриды"]
		for branch in branches:
			var column := VBoxContainer.new()
			column.custom_minimum_size.x = 152
			columns.add_child(column)
			var branch_label := Label.new()
			branch_label.text = branch
			column.add_child(branch_label)
			for row in skills:
				if (category == "active") != (skills.find(row) < 12):
					continue
				if (int(row[3]) == 3 and branch == "Гибриды") or (int(row[3]) < 3 and row[2] == branch):
					_add_skill(column, row)
	var open := Button.new()
	open.text = "Мутации [M]"
	open.pressed.connect(open_tree)
	hotbar.add_child(open)
	var active_skills := _equipped()
	for index in active_skills.size():
		var row: Array = []
		for entry in skills:
			if entry[0] == active_skills[index]: row = entry
		var button := Button.new()
		button.text = "%s %s" % [str(index + 4) if index < 4 else "•", row[1]]
		button.tooltip_text = str(row[5])
		var skill_id: String = active_skills[index]
		button.pressed.connect(func() -> void: runtime.call("cast_skill", skill_id))
		hotbar.add_child(button)


func _add_skill(column: VBoxContainer, row: Array) -> void:
	var skill_id := str(row[0])
	var level: float = 25.0 + float(row[3]) * 15.0
	var learned: bool = runtime.call("skill_learned", skill_id)
	var enabled: bool = runtime.call("has_skill", skill_id)
	var horizontal := HBoxContainer.new()
	column.add_child(horizontal)
	var button := Button.new()
	button.text = ("●" if enabled else "◌") + str(row[4]) + " " + str(row[1])
	button.tooltip_text = "%s  |  Нужно %d%% мутации" % [row[5], roundi(level)]
	button.disabled = learned or float(runtime.call("get_mutation")) < level or int(runtime.call("mutation_points")) < 1
	button.custom_minimum_size.x = 126
	button.pressed.connect(func() -> void: runtime.call("upgrade_skill", skill_id))
	horizontal.add_child(button)
	if learned:
		var lock := Button.new()
		lock.text = "🔒" if runtime.call("skill_locked", skill_id) else "🔓"
		lock.tooltip_text = "Сохранить при снижении мутации" if not runtime.call("skill_locked", skill_id) else "Не сохранять"
		lock.pressed.connect(func() -> void: runtime.call("toggle_skill_lock", skill_id))
		horizontal.add_child(lock)


func _equipped() -> Array[String]:
	var result: Array[String] = []
	for row in runtime.call("skill_catalog").slice(0, 12):
		if runtime.call("has_skill", str(row[0])):
			result.append(str(row[0]))
	return result
