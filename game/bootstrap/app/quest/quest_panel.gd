extends Node
## Planner tab "Конструктор заданий": the ordered quest list of the map (add, reorder, remove) and,
## for the quest picked in the list, its parameters (quest_params.gd). Only the picked quest's markers show.

const MODEL := preload("res://game/bootstrap/app/quest/quest_model.gd")
const BOOK := preload("res://game/bootstrap/app/quest/quest_book.gd")
const STORE := preload("res://game/bootstrap/app/quest/quest_store.gd")
const PARAMS := preload("res://game/bootstrap/app/quest/quest_params.gd")

var session: Variant
var book: Node
var tab: VBoxContainer
var type_picker: OptionButton
var lesson_picker: OptionButton
var list: ItemList
var params: Node
var _updating := false


func setup(context: Variant) -> void:
	session = context
	book = STORE.book(session)
	if book != null:
		book.changed.connect(refresh)


func build_tab() -> Control:
	tab = VBoxContainer.new()
	tab.name = "Конструктор заданий"
	var title := Label.new()
	title.text = "Задания идут по порядку: следующее начинается после завершения предыдущего."
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(title)
	type_picker = OptionButton.new()
	type_picker.name = "QuestType"
	for type in MODEL.TYPES:
		type_picker.add_item(MODEL.TYPE_LABELS[type])
	type_picker.item_selected.connect(func(_i: int) -> void: lesson_picker.visible = _type() == "lesson")
	tab.add_child(type_picker)
	lesson_picker = OptionButton.new()
	lesson_picker.name = "QuestLesson"
	for lesson in MODEL.LESSONS:
		lesson_picker.add_item(str(lesson[1]))
	lesson_picker.hide()
	tab.add_child(lesson_picker)
	tab.add_child(_button("AddQuest", "Добавить задание", _add))
	list = ItemList.new()
	list.name = "QuestList"
	list.custom_minimum_size.y = 150
	list.item_selected.connect(_picked)
	tab.add_child(list)
	var row := HBoxContainer.new()
	row.name = "QuestButtons"
	tab.add_child(row)
	row.add_child(_button("QuestUp", "Вверх", func() -> void: _move(-1)))
	row.add_child(_button("QuestDown", "Вниз", func() -> void: _move(1)))
	row.add_child(_button("RemoveQuest", "Удалить", _remove))
	params = PARAMS.new()
	add_child(params)
	params.setup(session, book)
	tab.add_child(params.build())
	tab.visibility_changed.connect(_sync_markers)
	refresh()
	return tab


func _button(node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(action)
	return button


func _type() -> String:
	return MODEL.TYPES[maxi(type_picker.selected, 0)]


func _add() -> void:
	if book == null:
		return
	var lesson: String = str(MODEL.LESSONS[maxi(lesson_picker.selected, 0)][0])
	var index: int = book.add(_type(), lesson)
	if index >= 0:
		book.selected = index
		refresh()


func _move(step: int) -> void:
	if book != null and book.selected >= 0:
		book.move(book.selected, step)


func _remove() -> void:
	if book != null and book.selected >= 0:
		book.remove(book.selected)


func _picked(index: int) -> void:
	if _updating:
		return
	book.selected = index
	params.show_quest(index)
	_sync_markers()


## Rebuilds the list from the book (the book changed: add, move, remove or a map was loaded).
func refresh() -> void:
	if list == null or book == null:
		return
	_updating = true
	list.clear()
	for i in book.quests.size():
		list.add_item("%d. %s" % [i + 1, label_of(book.quests[i])])
	if book.selected >= 0 and book.selected < book.quests.size():
		list.select(book.selected)
	_updating = false
	params.show_quest(book.selected)
	_sync_markers()


static func label_of(quest: Dictionary) -> String:
	if str(quest.type) == "lesson":
		return "Обучение: " + MODEL.lesson_label(str(quest.lesson))
	return str(MODEL.TYPE_LABELS[quest.type])


## Markers of the picked quest only (its targets, trigger object and trigger place); none otherwise.
func _sync_markers() -> void:
	if tab == null or not tab.is_inside_tree():
		return
	var shown: Array = []
	if tab.is_visible_in_tree() and book.selected >= 0 and book.selected < book.quests.size():
		shown = params.marker_nodes(book.quests[book.selected])
	BOOK.show_markers(tab.get_tree(), shown)
	params.show_point(not shown.is_empty() or (tab.is_visible_in_tree() and book.selected >= 0))
