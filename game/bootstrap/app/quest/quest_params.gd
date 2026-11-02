extends Node
## Parameter editor of one quest: trigger, targets, completion, delay and description.

const MODEL := preload("res://game/bootstrap/app/quest/quest_model.gd")
const BOOK := preload("res://game/bootstrap/app/quest/quest_book.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const POINT_NAME := "QuestPlaceMarker"

var session: Variant
var book: Node
var box: VBoxContainer
var trigger_kind: OptionButton
var trigger_value: SpinBox
var trigger_target: OptionButton
var trigger_place: Button
var target_picker: OptionButton
var target_list: ItemList
var done_kind: OptionButton
var done_value: SpinBox
var delay: SpinBox
var text_edit: TextEdit
var index := -1
var _candidates: Array[Node3D] = []
var _updating := false
var _point_node: Node3D


func setup(context: Variant, quest_book: Node) -> void:
	session = context
	book = quest_book


func build() -> Control:
	box = VBoxContainer.new()
	box.name = "QuestParams"
	box.add_child(_label("Параметры задания"))
	box.add_child(_label("Триггер"))
	trigger_kind = _picker("TriggerKind", MODEL.TRIGGERS, MODEL.TRIGGER_LABELS)
	trigger_kind.item_selected.connect(func(i: int) -> void: _edit("trigger", "kind", MODEL.TRIGGERS[i]))
	trigger_value = _spin("TriggerValue", 0.0, 100000.0, 1.0)
	trigger_value.value_changed.connect(func(v: float) -> void: _edit("trigger", "value", v))
	trigger_target = OptionButton.new()
	trigger_target.name = "TriggerTarget"
	trigger_target.item_selected.connect(_trigger_target_picked)
	trigger_place = Button.new()
	trigger_place.name = "TriggerPlace"
	trigger_place.text = "Поставить маркер места в центре камеры"
	trigger_place.pressed.connect(_place_marker)
	for control in [trigger_kind, trigger_value, trigger_target, trigger_place]:
		box.add_child(control)
	box.add_child(_label("Цели (объекты, помеченные как «Цель»)"))
	target_picker = OptionButton.new()
	target_picker.name = "TargetPicker"
	box.add_child(target_picker)
	var row := HBoxContainer.new()
	row.name = "TargetButtons"
	box.add_child(row)
	row.add_child(_button("AddTarget", "Добавить цель", _add_target))
	row.add_child(_button("RemoveTarget", "Удалить цель", _remove_target))
	target_list = ItemList.new()
	target_list.name = "TargetList"
	target_list.custom_minimum_size.y = 70
	box.add_child(target_list)
	box.add_child(_label("Выполнение"))
	done_kind = _picker("DoneKind", MODEL.COMPLETIONS, MODEL.COMPLETION_LABELS)
	done_kind.item_selected.connect(func(i: int) -> void: _edit("complete", "kind", MODEL.COMPLETIONS[i]))
	done_value = _spin("DoneValue", 0.0, 100000.0, 1.0)
	done_value.value_changed.connect(func(v: float) -> void: _edit("complete", "value", v))
	box.add_child(done_kind)
	box.add_child(done_value)
	box.add_child(_label("Задержка срабатывания, секунды"))
	delay = _spin("Delay", 0.0, 3600.0, 0.5)
	delay.value_changed.connect(func(v: float) -> void: _set_field("delay", v))
	box.add_child(delay)
	box.add_child(_label("Описание"))
	text_edit = TextEdit.new()
	text_edit.name = "QuestText"
	text_edit.custom_minimum_size.y = 70
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.text_changed.connect(func() -> void: _set_field("text", text_edit.text.left(MODEL.MAX_TEXT)))
	box.add_child(text_edit)
	box.hide()
	return box


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(action)
	return button


func _picker(node_name: String, ids: Array, labels: Dictionary) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = node_name
	for id in ids:
		picker.add_item(str(labels[id]))
	return picker


func _spin(node_name: String, low: float, high: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = node_name
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	return spin


func _quest() -> Dictionary:
	return book.quests[index] if book != null and index >= 0 and index < book.quests.size() else {}


## Shows the parameters of quest `new_index`; -1 hides the editor.
func show_quest(new_index: int) -> void:
	index = new_index
	var quest := _quest()
	box.visible = not quest.is_empty()
	if quest.is_empty():
		_point_marker(quest)
		return
	_updating = true
	_refresh_candidates()
	trigger_kind.select(MODEL.TRIGGERS.find(quest.trigger.kind))
	trigger_value.value = quest.trigger.value
	done_kind.select(maxi(MODEL.COMPLETIONS.find(quest.complete.kind), 0))
	done_value.value = quest.complete.value
	delay.value = quest.delay
	text_edit.text = quest.text
	target_list.clear()
	for id: String in quest.targets:
		target_list.add_item(_name_of(id))
	_updating = false
	_update_visibility()
	_point_marker(quest)


func _update_visibility() -> void:
	var quest := _quest()
	var kind: String = quest.trigger.kind
	var is_lesson: bool = quest.type == "lesson"
	var is_message: bool = quest.type == "message"
	trigger_value.visible = kind == "time" or kind == "steps"
	trigger_target.visible = kind == "reach"
	trigger_place.visible = kind == "reach"
	var has_targets := not is_lesson and not is_message
	target_picker.visible = has_targets
	target_list.visible = has_targets
	done_kind.visible = has_targets
	done_value.visible = has_targets and quest.complete.kind == "steps"


func _refresh_candidates() -> void:
	_candidates.clear()
	target_picker.clear()
	trigger_target.clear()
	trigger_target.add_item("— объект не выбран —")
	if not target_picker.is_inside_tree():
		return
	for node: Node in target_picker.get_tree().get_nodes_in_group(TARGET.GROUP):
		if node is Node3D:
			BOOK.ensure_id(node) # targets flagged before quests existed have no id yet
			_candidates.append(node)
			target_picker.add_item(_describe(node))
			trigger_target.add_item(_describe(node))
	var current: String = _quest().trigger.target
	for i in _candidates.size():
		if str(_candidates[i].get_meta(BOOK.ID_META)) == current:
			trigger_target.select(i + 1)


func _describe(node: Node3D) -> String:
	var file := str(node.get_meta(&"planning_scene_path", node.name)).get_file().get_basename()
	return "%s (%.0f; %.0f)" % [file, node.global_position.x, node.global_position.z]


func _name_of(id: String) -> String:
	var node := BOOK.find_object(target_picker.get_tree(), id)
	return _describe(node) if node != null else "(объект не найден) " + id


func _edit(section: String, key: String, value: Variant) -> void:
	var quest := _quest()
	if _updating or quest.is_empty():
		return
	quest[section][key] = value
	_update_visibility()


func _set_field(key: String, value: Variant) -> void:
	var quest := _quest()
	if not _updating and not quest.is_empty():
		quest[key] = value


func _trigger_target_picked(item: int) -> void:
	_edit("trigger", "target", str(_candidates[item - 1].get_meta(BOOK.ID_META)) if item > 0 else "")
	_point_marker(_quest())


func _add_target() -> void:
	var quest := _quest()
	if quest.is_empty() or target_picker.selected < 0 or target_picker.selected >= _candidates.size():
		return
	var id := str(_candidates[target_picker.selected].get_meta(BOOK.ID_META))
	if not id in quest.targets and quest.targets.size() < MODEL.MAX_TARGETS:
		quest.targets.append(id)
		show_quest(index)
		_sync()


func _remove_target() -> void:
	var quest := _quest()
	var picked := target_list.get_selected_items()
	if quest.is_empty() or picked.is_empty():
		return
	quest.targets.remove_at(picked[0])
	show_quest(index)
	_sync()


func _sync() -> void:
	BOOK.show_markers(box.get_tree(), marker_nodes(_quest()))


## The place marker is a flat target ring standing at the trigger point of the quest.
func _place_marker() -> void:
	var rig: Variant = session.get("camera_rig") if session != null else null
	if _quest().is_empty() or not rig is Node3D:
		return
	var at: Vector3 = (rig as Node3D).global_position
	_edit("trigger", "point", [at.x, at.z])
	_edit("trigger", "target", "")
	trigger_target.select(0)
	_point_marker(_quest())


func _point_marker(quest: Dictionary) -> void:
	if is_instance_valid(_point_node):
		_point_node.free()
	_point_node = null
	if quest.is_empty() or quest.trigger.kind != "reach" or (quest.trigger.point as Array).size() != 2 or not box.is_inside_tree():
		return
	var point: Array = quest.trigger.point
	_point_node = Node3D.new()
	_point_node.name = POINT_NAME
	box.get_tree().root.add_child(_point_node)
	_point_node.global_position = Vector3(float(point[0]), 0.0, float(point[1]))
	_point_node.add_child(TARGET.new_marker())
	_point_node.set_meta(&"planning_tutorial_revealed", true) # the panel hides it again when the tab closes


func is_candidate_list_current() -> bool:
	return target_picker.is_inside_tree() and _candidates.size() == target_picker.get_tree().get_nodes_in_group(TARGET.GROUP).size()


func show_point(shown: bool) -> void:
	if is_instance_valid(_point_node):
		_point_node.set_meta(&"planning_tutorial_revealed", shown)


## Objects whose markers show while this quest is picked.
func marker_nodes(quest: Dictionary) -> Array:
	var nodes: Array = []
	if quest.is_empty() or box == null or not box.is_inside_tree():
		return nodes
	for id: String in quest.targets:
		var node := BOOK.find_object(box.get_tree(), id)
		if node != null:
			nodes.append(node)
	var trigger := BOOK.find_object(box.get_tree(), str(quest.trigger.target))
	if trigger != null:
		nodes.append(trigger)
	return nodes
