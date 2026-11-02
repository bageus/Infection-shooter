extends Node
## Planner panel: marks any object, item or enemy as a quest target. Shows which quests use it.
## Works on the selected object, or on the palette preview until it is placed.

const QUESTS := preload("res://game/bootstrap/app/quest/quest_store.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")

var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var enabled: CheckBox
var links: Label
var _updating := false
# What the next placed object starts with (kept between placements).
var default_enabled := false


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "TargetOptions"
	title = Label.new()
	panel.add_child(title)
	enabled = CheckBox.new()
	enabled.text = "Цель (маркер и стрелка)"
	enabled.toggled.connect(_changed)
	panel.add_child(enabled)
	links = Label.new()
	links.name = "QuestLinks"
	panel.add_child(links)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func applies_to(target: Node3D) -> bool:
	return TARGET.applies_to(target)


func update() -> void:
	var target := _target()
	panel.visible = applies_to(target)
	if not panel.visible:
		return
	_updating = true
	title.text = "ЦЕЛЬ: " + _kind_label(TARGET.kind_of(target)) + ("" if objects.selected != null else " | размещение")
	enabled.set_pressed_no_signal(TARGET.is_target(target))
	var users: Array[int] = []
	var quest_book := QUESTS.book(session)
	if quest_book != null:
		users = quest_book.call("quests_using", str(target.get_meta(&"planning_object_id", "")))
	links.text = "Привязана к заданию: " + ", ".join(users.map(func(n: int) -> String: return "№%d" % n)) if not users.is_empty() else "Не привязана к заданию"
	_updating = false


func hide() -> void:
	if panel != null:
		panel.hide()


## A freshly created object starts with the switch last chosen in the panel.
func configure_new(target: Node3D) -> void:
	if applies_to(target) and default_enabled:
		TARGET.configure(target, true)


func _kind_label(kind: String) -> String:
	return {"bottle": "бутылка", "crate": "ящик", "extinguisher": "огнетушитель", "door": "дверь", "object": "объект"}.get(kind, "")


func _changed(_value: Variant = null) -> void:
	var target := _target()
	if _updating or target == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	else:
		default_enabled = enabled.button_pressed
	TARGET.configure(target, enabled.button_pressed)
	update()
