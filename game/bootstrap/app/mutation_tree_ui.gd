extends CanvasLayer

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const TREE_CANVAS := preload("res://game/bootstrap/app/mutation_tree_canvas.gd")
const SKILL_CARD := preload("res://game/bootstrap/app/mutation_skill_card.gd")
const SKILL_INFO := preload("res://game/bootstrap/app/mutation_skill_info.gd")
const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
const SKILL_ICONS := preload("res://game/bootstrap/app/mutation_skill_icons.gd")
const SKILL_BAR := preload("res://game/bootstrap/app/mutation_skill_bar.gd")
const LIT := Color(0.3, 0.95, 0.1)
const CIRCLE := 66.0
const CIRCLE_ICON := 42

var runtime: Node
var window: Control
var panel: PanelContainer
var card: PanelContainer
var points_label: Label
var mutation_value: Label
var stability_value: Label
var hint_label: Label
var content: Control
var skill_bar: SKILL_BAR
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
	window = Control.new()
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.theme = STYLE.make_theme(1.0)
	root.add_child(window)
	var dim := ColorRect.new()
	dim.color = Color("080b0fd9")
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = 20
	panel.offset_bottom = -20
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(panel)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("151a1cf5")
	background.border_color = Color("646760")
	background.set_border_width_all(1)
	background.set_content_margin_all(22)
	background.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", background)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)
	layout.add_child(_build_header())
	layout.add_child(_divider())
	content = Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.clip_contents = true
	layout.add_child(content)
	content.resized.connect(_fit_tree)
	layout.add_child(_divider())
	layout.add_child(_build_footer())
	card = SKILL_CARD.new()
	window.add_child(card)
	window.hide()
	_build_hotbar(root)
	runtime.connect("tree_changed", _refresh)
	runtime.connect("mutation_changed", _on_mutation_changed)
	runtime.connect("skill_available", _on_new_skill_available)
	runtime.connect("control_loss_changed", _on_control_loss_changed)
	_refresh()


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 28)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var caption := STYLE.label("SKILL TREE", 11)
	caption.add_theme_color_override("font_color", STYLE.MUTED)
	titles.add_child(caption)
	titles.add_child(STYLE.label("MUTATIONS", 34, true))
	mutation_value = _stat(header, "MUTATION")
	points_label = _stat(header, "POINTS")
	stability_value = _stat(header, "STABILITY")
	# Menu theme look without STYLE.button's focus-follows-hover, which would
	# let Space close the tree while the player is reading it.
	var close := Button.new()
	close.text = "CLOSE  [ESC]"
	close.custom_minimum_size.y = 48
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_tree)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.mouse_entered.connect(_play_ui_sound.bind(&"menu_hover"))
	header.add_child(close)
	return header


func _stat(header: HBoxContainer, caption: String) -> Label:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(block)
	var name_label := STYLE.label(caption, 10)
	name_label.add_theme_color_override("font_color", STYLE.MUTED)
	block.add_child(name_label)
	var value := STYLE.label("", 22, true)
	block.add_child(value)
	return value


func _build_footer() -> HBoxContainer:
	var footer := HBoxContainer.new()
	hint_label = STYLE.label("━━   Click a circle to unlock a skill. Lock a learned skill to keep it when mutation drops.", 11)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.add_theme_color_override("font_color", STYLE.MUTED)
	footer.add_child(hint_label)
	return footer


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0.64, 0.64, 0.61, 0.32)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _build_hotbar(root: Control) -> void:
	skill_bar = SKILL_BAR.new()
	root.add_child(skill_bar)
	skill_bar.configure(runtime, open_tree)


func _on_new_skill_available() -> void:
	if visible and not get_tree().paused and not runtime.call("is_control_lost") and not runtime.call("is_defeated"):
		open_tree()


func _on_mutation_changed(amount: float, _limit: float) -> void:
	if window.visible:
		_update_stats(amount)
		if content.get_child_count() > 0:
			content.get_child(0).call("set_mutation", amount)
	var tier := floori((amount - 25.0) / 5.0)
	if tier != _last_skill_tier:
		_last_skill_tier = tier
		_refresh()


func _input(event: InputEvent) -> void:
	if is_tree_open() and event.is_action_pressed("antidote") and not event.is_echo():
		var player := runtime.get_parent()
		if player != null and player.has_method("use_antidote") and bool(player.call("use_antidote")):
			get_viewport().set_input_as_handled()
		return
	if is_tree_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_tree()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		if event.is_action_pressed("mutation_tree"):
			_set_open(not window.visible)
			get_viewport().set_input_as_handled()
		else:
			var skills: Array[String] = _equipped()
			for index in range(4):
				if event.is_action_pressed("skill_" + str(index + 1)):
					if index < skills.size():
						runtime.call("cast_skill", skills[index])
					get_viewport().set_input_as_handled()
					break


func open_tree() -> void:
	_set_open(true)


func close_tree() -> void:
	_set_open(false)


func is_tree_open() -> bool:
	return window != null and window.visible


func _set_open(value: bool) -> void:
	if value and (runtime.call("is_control_lost") or runtime.call("is_defeated")):
		return
	if window.visible == value:
		return
	if value:
		_previous_pause = get_tree().paused
		get_tree().paused = true
	else:
		get_tree().paused = _previous_pause
	window.visible = value
	card.dismiss()
	skill_bar.visible = not value
	if runtime != null and runtime.get_parent() != null:
		runtime.get_parent().set("_mutation_menu_open", value)
	_refresh()
	if value:
		_fit_tree.call_deferred()


func _update_stats(amount: float) -> void:
	mutation_value.text = "%d%%" % roundi(amount)
	var points: int = runtime.call("mutation_points")
	points_label.text = str(points)
	points_label.add_theme_color_override("font_color", LIT if points > 0 else STYLE.INK)
	stability_value.text = "%d%%" % roundi(runtime.call("get_critical_threshold"))


func _fit_tree() -> void:
	if content == null or content.get_child_count() == 0:
		return
	var canvas := content.get_child(0) as Control
	var design_size: Vector2 = TREE_CANVAS.DESIGN_SIZE
	var factor := minf(content.size.x / design_size.x, content.size.y / design_size.y)
	canvas.scale = Vector2.ONE * factor
	canvas.position = ((content.size - design_size * factor) * 0.5).max(Vector2.ZERO)


func _refresh() -> void:
	if runtime == null or content == null:
		return
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_update_stats(float(runtime.call("get_mutation")))
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
			_add_skill(canvas, row, canvas.call("skill_position", branch_index, rank), skills)
			if bool(requirements["path_reached"]):
				furthest = maxi(furthest, rank)
		_add_branch_label(canvas, branch_index, requirements)
		progress.append(furthest)
	var hybrid_index := 0
	var hybrids: Array[bool] = []
	for row in skills:
		if int(row[3]) != 3:
			continue
		_add_skill(canvas, row, canvas.call("hybrid_position", hybrid_index), skills)
		hybrids.append(bool(runtime.call("has_skill", str(row[0]))))
		hybrid_index += 1
	canvas.call("set_progress", progress, hybrids)
	_fill_hotbar()
	_restore_card()


func _add_branch_label(canvas: Control, branch_index: int, requirements: Dictionary) -> void:
	var opened := bool(requirements["branch_open"])
	var label := STYLE.label(str(TREE_CANVAS.BRANCHES[branch_index]).to_upper(), 14, true)
	label.modulate.a = 1.0 if opened else 0.4
	var area: Rect2 = canvas.call("label_rect", branch_index)
	var gate := STYLE.label("S%d · STABILITY %d%%%s" % [requirements["stage"], roundi(requirements["stability"]), " · LOCKED" if not opened else ""], 10)
	gate.add_theme_color_override("font_color", STYLE.MUTED if opened else Color("8a6a62"))
	for line: Label in [label, gate]:
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = area.size.x
		line.size.x = area.size.x
	label.position = area.position
	gate.position = area.position + Vector2(0, 19)
	canvas.add_child(gate)
	canvas.add_child(label)


func _fill_hotbar() -> void:
	var active_skills := _equipped()
	var keys: Array[String] = []
	for index in active_skills.size():
		keys.append(_binding_label("skill_%d" % (index + 1)) if index < 4 else "")
	skill_bar.rebuild(active_skills, keys, _binding_label("mutation_tree"))


func _add_skill(canvas: Control, row: Array, center: Vector2, skills: Array) -> void:
	var skill_id := str(row[0])
	var requirements: Dictionary = runtime.call("skill_requirements", skill_id)
	var learned: bool = runtime.call("skill_learned", skill_id)
	var enabled: bool = runtime.call("has_skill", skill_id)
	var available: bool = runtime.call("can_upgrade_skill", skill_id)
	var button := Button.new()
	if not _set_icon(button, skill_id, CIRCLE_ICON):
		button.text = str(row[4])
	button.position = center - Vector2.ONE * CIRCLE * 0.5
	button.custom_minimum_size = Vector2.ONE * CIRCLE
	button.size = Vector2.ONE * CIRCLE
	button.set_meta("skill_id", skill_id)
	button.set_meta("card_info", SKILL_INFO.describe(runtime, row, skills))
	button.disabled = not available
	button.modulate = Color.WHITE if bool(requirements["branch_open"]) else Color(0.4, 0.4, 0.4, 1.0)
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	if enabled:
		style.bg_color = Color(0.16, 0.45, 0.06)
		style.border_color = LIT
	elif learned:
		style.bg_color = Color(0.13, 0.2, 0.1)
		style.border_color = Color(0.3, 0.55, 0.16)
	elif available:
		style.bg_color = Color(0.13, 0.19, 0.12)
		style.border_color = LIT
		style.shadow_color = Color(0.3, 0.95, 0.1, 0.36)
		style.shadow_size = 8
	else:
		style.bg_color = Color("1c2225")
		style.border_color = Color("646760")
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(CIRCLE * 0.5))
	style.set_content_margin_all((CIRCLE - CIRCLE_ICON) * 0.5)
	var hover := style.duplicate() as StyleBoxFlat
	hover.border_color = STYLE.INK
	for state in ["normal", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_disabled_color", STYLE.MUTED)
	button.mouse_entered.connect(_skill_hover.bind(button))
	button.mouse_entered.connect(_show_card.bind(button))
	button.mouse_exited.connect(card.dismiss.bind(skill_id))
	button.pressed.connect(_upgrade_skill.bind(skill_id))
	canvas.add_child(button)
	if learned and int(row[3]) != 3:
		_add_lock(canvas, row, center)


func _set_icon(button: Button, skill_id: String, icon_size: int) -> bool:
	var icon := SKILL_ICONS.for_skill(skill_id)
	if icon == null:
		return false
	button.icon = icon
	# Circles fit the icon inside their margins; labelled buttons cap its width.
	button.expand_icon = button.text.is_empty()
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER if button.expand_icon else HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", icon_size)
	button.add_theme_color_override("icon_disabled_color", STYLE.MUTED)
	# ~200 px glyphs shrink to ~42 px; mipmaps keep the white strokes clean.
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return true


func _add_lock(canvas: Control, row: Array, center: Vector2) -> void:
	var skill_id := str(row[0])
	var locked: bool = runtime.call("skill_locked", skill_id)
	var lock := Button.new()
	lock.text = "L" if locked else "+"
	lock.position = center + Vector2(CIRCLE * 0.5 + 8.0, -12)
	lock.custom_minimum_size = Vector2(24, 24)
	lock.size = Vector2(24, 24)
	lock.focus_mode = Control.FOCUS_NONE
	lock.add_theme_font_size_override("font_size", 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("74262b") if locked else Color("23292c")
	style.border_color = SKILL_CARD.ACCENT if locked else Color("8a8b84")
	# The canvas is scaled to fit; 1 px borders lose sides at fractional scales.
	style.set_border_width_all(2)
	style.set_content_margin_all(0)
	var hover := style.duplicate() as StyleBoxFlat
	hover.border_color = STYLE.INK
	for state in ["normal", "pressed", "disabled"]:
		lock.add_theme_stylebox_override(state, style)
	lock.add_theme_stylebox_override("hover", hover)
	var lock_id := "lock:" + skill_id
	lock.set_meta("lock_skill_id", skill_id)
	lock.set_meta("skill_id", lock_id)
	lock.set_meta("card_info", {
		"kind": "Skill lock", "title": str(row[1]),
		"body": "Locked: kept when mutation drops." if locked else "Lock skill against mutation loss. A locked skill stays learned when mutation drops.",
		"status": "Click to unlock" if locked else "Click to lock", "status_color": STYLE.MUTED})
	lock.mouse_entered.connect(_skill_hover.bind(lock))
	lock.mouse_entered.connect(_show_card.bind(lock))
	lock.mouse_exited.connect(card.dismiss.bind(lock_id))
	lock.pressed.connect(_toggle_skill_lock.bind(skill_id))
	canvas.add_child(lock)


func _show_card(button: Control) -> void:
	if not is_tree_open() or not button.is_inside_tree():
		return
	var info: Dictionary = button.get_meta("card_info", {})
	card.present(str(button.get_meta("skill_id")), info, button.get_global_rect(), window.get_global_rect().grow(-12))


func _restore_card() -> void:
	# Buying or locking rebuilds the circles under a still-hovering cursor.
	if not card.visible:
		return
	for button in content.find_children("*", "Button", true, false):
		if not button.is_queued_for_deletion() and button.get_meta("skill_id", "") == card.anchor_id:
			_show_card.call_deferred(button)
			return
	card.dismiss()


func _equipped() -> Array[String]:
	var result: Array[String] = []
	for row in runtime.call("skill_catalog").slice(0, 12):
		if runtime.call("has_skill", str(row[0])):
			result.append(str(row[0]))
	return result


func _add_section_labels(canvas: Control) -> void:
	for entry in [["ACTIVE", 185.0], ["PASSIVE", 490.0], ["HYBRID", 664.0]]:
		var marker := ColorRect.new()
		marker.color = SKILL_CARD.ACCENT
		marker.position = Vector2(4, float(entry[1]) + 7.0)
		marker.size = Vector2(14, 3)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(marker)
		var label := STYLE.label(str(entry[0]), 12)
		label.position = Vector2(24, float(entry[1]))
		label.add_theme_color_override("font_color", STYLE.MUTED)
		canvas.add_child(label)


func _on_control_loss_changed(active: bool) -> void:
	if active and is_tree_open():
		close_tree()


func _play_ui_sound(event: StringName) -> void:
	# The persistent layer outlives buttons rebuilt by tree_changed.
	SFX.play_ui(self, event)


func _skill_hover(button: BaseButton) -> void:
	if not button.disabled:
		_play_ui_sound(&"mutation_hover")


func _upgrade_skill(skill_id: String) -> void:
	if not runtime.call("can_upgrade_skill", skill_id):
		return
	_play_ui_sound(&"mutation_click")
	runtime.call("upgrade_skill", skill_id)


func _toggle_skill_lock(skill_id: String) -> void:
	var was_locked: bool = runtime.call("skill_locked", skill_id)
	runtime.call("toggle_skill_lock", skill_id)
	var locked: bool = runtime.call("skill_locked", skill_id)
	if locked != was_locked:
		_play_ui_sound(&"mutation_lock" if locked else &"mutation_unlock")


func _binding_label(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "?"
	var event: InputEvent = events[0]
	if event is InputEventMouseButton:
		return ["LMB", "RMB", "MMB"][event.button_index - 1]
	if event is InputEventKey:
		return OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
	return event.as_text()
