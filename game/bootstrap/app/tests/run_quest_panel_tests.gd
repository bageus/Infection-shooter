extends SceneTree
## The planner's "Конструктор карт" / "Конструктор заданий" tabs: add, reorder, edit and remove quests.
const MAIN := preload("res://game/bootstrap/app/main.tscn")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1200, 700)
	var stage := MAIN.instantiate()
	stage.set("defer_layout_loading", true)
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var planner: Node = stage.get("planning_mode")
	planner.enter()
	var layout: RefCounted = planner.controls.hud_layout
	var tabs: TabContainer = layout.right_tabs
	_check(tabs.has_node("Конструктор карт") and not tabs.has_node("Конструктор"), "The constructor tab is renamed to the map constructor")
	_check(tabs.has_node("Конструктор заданий"), "A quest constructor tab exists")
	var tab: Node = tabs.get_node("Конструктор заданий")
	var book: Node = stage.get("quest_book")
	var type_picker: OptionButton = tab.get_node("QuestType")
	_check(type_picker.item_count == 6, "Six quest types can be picked")
	(tab.get_node("QuestLesson") as OptionButton).select(2)
	type_picker.select(5)
	type_picker.item_selected.emit(5)
	_check(tab.get_node("QuestLesson").visible, "Picking a lesson quest shows the lesson list")
	tab.get_node("AddQuest").pressed.emit()
	type_picker.select(0)
	type_picker.item_selected.emit(0)
	tab.get_node("AddQuest").pressed.emit()
	var list: ItemList = tab.get_node("QuestList")
	_check(list.item_count == 2 and book.quests[0].lesson == "roll", "Quests are added to the list in order")
	_check(book.quests[0].text == "Базовое обучение: перекат", "A lesson quest gets its preset text")
	list.select(1)
	list.item_selected.emit(1)
	var params: Node = tab.get_node("QuestParams")
	_check(params.visible, "Picking a quest shows its parameters")
	_check((tab.get_node("QuestParams/Delay") as SpinBox).value == 0.0, "The delay defaults to 0")
	var text: TextEdit = tab.get_node("QuestParams/QuestText")
	_check(text.text == "Найдите цель", "The description is prefilled with the preset")
	text.text = "Моё описание"
	text.text_changed.emit()
	(tab.get_node("QuestParams/TriggerKind") as OptionButton).select(1)
	(tab.get_node("QuestParams/TriggerKind") as OptionButton).item_selected.emit(1)
	(tab.get_node("QuestParams/TriggerValue") as SpinBox).value = 7.0
	_check(book.quests[1].text == "Моё описание" and book.quests[1].trigger.kind == "time" and book.quests[1].trigger.value == 7.0, "Edits go to the quest")
	var prop := PROP.instantiate() as Node3D
	prop.set("model_path", "res://models/objects/enviroments/09/09_mug.glb")
	stage.add_child(prop)
	TARGET.configure(prop, true)
	list.item_selected.emit(1)
	tab.get_node("QuestParams/TargetButtons/AddTarget").pressed.emit()
	_check(book.quests[1].targets.size() == 1 and book.quests_using(book.quests[1].targets[0]) == [2], "A target is added and linked back to the quest")
	tab.get_node("QuestParams/TargetButtons/RemoveTarget").pressed.emit()
	tab.get_node("QuestButtons/QuestUp").pressed.emit()
	_check(book.quests[0].type == "find", "A quest moves up")
	tab.get_node("QuestButtons/RemoveQuest").pressed.emit()
	_check(book.quests.size() == 1 and list.item_count == 1, "A quest is removed")
	prop.free()
	stage.queue_free()
	await process_frame
	if failures == 0:
		print("Quest panel tests passed.")
	else:
		push_error("Quest panel tests failed: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("ok: ", message)
