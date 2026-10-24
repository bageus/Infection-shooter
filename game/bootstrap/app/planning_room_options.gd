extends Node
## Shared palette/selection editor and browser for authored darkness groups.
const GROUPS := preload("res://game/bootstrap/app/planning_darkness_groups.gd")
var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var room: SpinBox
var height: SpinBox
var browser: VBoxContainer
var list: OptionButton
var highlights: Node3D
var _default_height := 2.75
var _default_group := 0
var _updating := false
var _timer := 0.0
var _signature := ""
var _selected_id := 0


static func applies_to(node: Node) -> bool:
	return is_instance_valid(node) and node.has_method("configure_zone") and node.get("room_id") != null


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "RoomOptions"
	title = Label.new()
	panel.add_child(title)
	height = _number("Высота, м", -15, 55, 0.25)
	room = _number("Группа (0 — без группы)", 0, 999999, 1)
	height.value_changed.connect(_height_changed)
	room.value_changed.connect(_group_changed)
	browser = VBoxContainer.new()
	browser.name = "DarknessGroups"
	var label := Label.new()
	label.text = "Группы затемнения на карте"
	browser.add_child(label)
	list = OptionButton.new()
	list.name = "DarknessGroupList"
	list.item_selected.connect(_group_selected)
	browser.add_child(list)
	var box: Node = session.ui.get_node("Panel/VBox")
	for widget in [panel, browser]:
		box.add_child(widget)
		box.move_child(widget, box.get_node("Palette").get_index() + 1)
	highlights = GROUPS.new()
	add_child(highlights)
	session.ui.visibility_changed.connect(update)
	update()


func _number(label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	row.add_child(input)
	panel.add_child(row)
	return input


func update() -> void:
	var selected: Node3D = objects.selected
	var palette: bool = objects.selected_kind in ["darkness", "exploration_darkness"]
	panel.visible = session.active and (applies_to(selected) or (selected == null and palette))
	browser.visible = session.active and (panel.visible or session.catalog.active_catalog == session.catalog.lighting_catalog)
	if panel.visible:
		_updating = true
		title.text = "ЗАТЕМНЕНИЕ | выбранная зона" if applies_to(selected) else "ЗАТЕМНЕНИЕ | новая зона"
		if not height.get_line_edit().has_focus():
			height.set_value_no_signal(selected.global_position.y if applies_to(selected) else _default_height)
		if not room.get_line_edit().has_focus():
			room.set_value_no_signal(int(selected.get("room_id")) if applies_to(selected) else _default_group)
		_updating = false
	_refresh_groups()
	var id := selected.get_instance_id() if applies_to(selected) else 0
	if id != _selected_id:
		_selected_id = id
		if id != 0:
			_select_group(int(selected.get("room_id")))


func hide() -> void:
	panel.hide()
	browser.hide()
	highlights.clear()


func configure_new(node: Node3D, entry: Dictionary) -> void:
	if not applies_to(node) or str(entry.get("kind", "")) not in ["darkness", "exploration_darkness"]:
		return
	node.set("room_id", _default_group)
	node.set("permanent", str(entry.kind) == "darkness")


func apply_default_height(node: Node3D) -> void:
	node.global_position.y = _default_height


func _height_changed(value: float) -> void:
	if _updating:
		return
	var target: Node3D = objects.selected
	if applies_to(target):
		session.edit_history.record_transform(target)
		target.global_position.y = value
	else:
		_default_height = value
		if applies_to(objects.preview):
			apply_default_height(objects.preview)


func _group_changed(value: float) -> void:
	if _updating:
		return
	var target: Node3D = objects.selected
	if applies_to(target):
		session.edit_history.record_transform(target)
		target.set("room_id", int(value))
	else:
		_default_group = int(value)
		if applies_to(objects.preview):
			objects.preview.set("room_id", _default_group)
	_refresh_groups()
	if applies_to(target):
		_select_group(int(value))


func _zones() -> Array[Node3D]:
	var zones: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("darkness_zone"):
		if not node.is_queued_for_deletion() and not node.has_meta("planning_preview") and session.host.is_ancestor_of(node):
			zones.append(node)
	return zones


func _refresh_groups() -> void:
	if not browser.visible:
		highlights.clear()
		return
	var zones := _zones()
	var counts := {}
	for zone in zones:
		var id := int(zone.get("room_id"))
		counts[id] = int(counts.get(id, 0)) + 1
	var ids := counts.keys()
	ids.sort()
	var signature := str(ids) + str(counts)
	if signature != _signature:
		var selected := list.get_selected_id() if list.item_count > 0 else -1
		list.clear()
		list.add_item("Выберите группу для подсветки", -1)
		list.set_item_id(0, -1)
		for id in ids:
			list.add_item(("Без группы" if id == 0 else "Группа %d" % id) + " — %d зон" % counts[id], id)
		list.select(maxi(list.get_item_index(selected), 0))
		_signature = signature
	highlights.refresh(zones, list.get_selected_id())


func _group_selected(_index: int) -> void:
	_refresh_groups()


func _select_group(group: int) -> void:
	list.select(maxi(list.get_item_index(group), 0))
	_refresh_groups()


func _process(delta: float) -> void:
	if not session.active:
		if browser.visible or panel.visible:
			hide()
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		update()
