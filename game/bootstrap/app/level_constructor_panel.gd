extends RefCounted
## Level constructor widgets in the planner's right-hand HUD: the map list that
## defines the chain and the two entry points of the selected map.

const LEVEL_CHAIN := preload("res://game/bootstrap/app/level_chain.gd")
const TYPE_LABELS: Array[String] = ["None", "Ceiling (stairs up)", "Floor (stairs down)"]

var runtime: Node
var planner: Node
var list: ItemList
var kind_pickers: Array[OptionButton] = []
var place_buttons: Array[Button] = []
var _slot_labels: Array[Label] = []
var _syncing := false


func build(owner_runtime: Node, session: Node) -> void:
	runtime = owner_runtime
	planner = session
	var box: VBoxContainer = session.ui.get_node("RightPanel/VBox")
	var title := Label.new()
	title.text = "LEVEL CONSTRUCTOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	list = ItemList.new()
	list.name = "ChainList"
	list.custom_minimum_size = Vector2(0, 110)
	list.item_selected.connect(_on_selected)
	box.add_child(list)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("ADD MAP", _add_selected_map, "AddMap"))
	row.add_child(_button("REMOVE", _remove_selected, "RemoveMap"))
	row.add_child(_button("UP", _move.bind(-1), "MoveUp"))
	row.add_child(_button("DOWN", _move.bind(1), "MoveDown"))
	for slot in LEVEL_CHAIN.SLOT_COUNT:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
		_slot_labels.append(label)
		var picker := OptionButton.new()
		picker.name = "EntryType%d" % slot
		for text in TYPE_LABELS:
			picker.add_item(text)
		picker.item_selected.connect(_on_kind_picked.bind(slot))
		box.add_child(picker)
		kind_pickers.append(picker)
		var place := _button("PLACE ENTRY %d AT VIEW CENTER" % [slot + 1], _place_entry.bind(slot), "PlaceEntry%d" % slot)
		box.add_child(place)
		place_buttons.append(place)
	box.add_child(_button("PLAY CHAIN FROM MAP 1", _play_chain, "PlayChain"))
	_refresh()


func _button(text: String, action: Callable, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _say(text: String) -> void:
	planner.controls.status.text = text


func _selected() -> int:
	var picked := list.get_selected_items()
	return picked[0] if not picked.is_empty() else -1


func _save() -> void:
	runtime.chain.save()
	runtime.marker_map = "" if _selected() < 0 else str(runtime.chain.maps[_selected()].name)
	runtime.refresh_markers()


func _add_selected_map() -> void:
	var select: OptionButton = planner.storage.map_select
	if select.item_count <= 0:
		_say("NO SAVED MAPS")
		return
	var map_name := select.get_item_text(select.selected)
	if not runtime.chain.add_map(map_name):
		_say("MAP ALREADY IN THE CHAIN")
		return
	_refresh(runtime.chain.maps.size() - 1)
	_save()
	_say("MAP ADDED TO THE CHAIN | " + map_name)


func _remove_selected() -> void:
	runtime.chain.remove_map(_selected())
	_refresh()
	_save()


func _move(direction: int) -> void:
	_refresh(runtime.chain.move_map(_selected(), direction))
	_save()


func _on_selected(_index: int) -> void:
	_refresh(_selected())
	_save()


func _on_kind_picked(option: int, slot: int) -> void:
	if _syncing or _selected() < 0:
		return
	runtime.chain.set_entry_type(_selected(), slot, LEVEL_CHAIN.TYPES[option])
	_refresh(_selected())
	_save()


func _place_entry(slot: int) -> void:
	var index := _selected()
	if index < 0 or runtime.chain.entry(index, slot).type == "none":
		_say("SELECT A MAP AND CHOOSE THE ENTRY TYPE FIRST")
		return
	runtime.chain.place_entry(index, slot, planner.camera_anchor.x, planner.camera_anchor.z)
	_refresh(index)
	_save()
	_say("ENTRY %d PLACED | put it at the foot of the stairs" % [slot + 1])


func _play_chain() -> void:
	if runtime.chain.maps.is_empty():
		_say("THE CHAIN IS EMPTY")
		return
	planner.exit()
	runtime._main.call("travel_to_level", runtime.chain.maps[0].name, {})


func _refresh(select_index: int = -1) -> void:
	_syncing = true
	list.clear()
	for i in runtime.chain.maps.size():
		list.add_item("%d. %s" % [i + 1, runtime.chain.maps[i].name])
	if select_index >= 0 and select_index < list.item_count:
		list.select(select_index)
	var index := _selected()
	for slot in LEVEL_CHAIN.SLOT_COUNT:
		var enabled := index >= 0
		kind_pickers[slot].disabled = not enabled
		place_buttons[slot].disabled = not enabled
		if not enabled:
			_slot_labels[slot].text = "Entry %d: select a map" % [slot + 1]
			continue
		var item: Dictionary = runtime.chain.entry(index, slot)
		var target: String = runtime.chain.neighbour(index, slot)
		var side := "previous" if slot == 0 else "next"
		kind_pickers[slot].select(LEVEL_CHAIN.TYPES.find(item.type))
		_slot_labels[slot].text = "Entry %d -> %s map: %s%s" % [slot + 1, side,
			target if not target.is_empty() else "(none)", "" if item.type == "none" or item.placed else " | not placed"]
	_syncing = false
