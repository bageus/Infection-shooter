extends Node
## The quest list of the map being edited or played. Saved with the map (quest_model.KEY).

const MODEL := preload("res://game/bootstrap/app/quest/quest_model.gd")
const TARGET := preload("res://game/presentation/office_floor/public/tutorial_target.gd")
const ID_META := &"planning_object_id"

signal changed

var quests: Array = []
var selected := -1 # quest shown in the editor: only its markers are visible


func capture() -> Array:
	return quests.duplicate(true)


## A map without the list restores an empty one, so a previous map's quests never carry over.
func restore(raw: Variant) -> void:
	quests = MODEL.normalize_list(raw)
	selected = -1
	changed.emit()


func add(type: String, lesson: String = "") -> int:
	if quests.size() >= MODEL.MAX_QUESTS:
		return -1
	quests.append(MODEL.make(type, lesson))
	changed.emit()
	return quests.size() - 1


func remove(index: int) -> void:
	if index < 0 or index >= quests.size():
		return
	quests.remove_at(index)
	selected = clampi(selected, -1, quests.size() - 1)
	changed.emit()


func move(index: int, step: int) -> void:
	var target := index + step
	if index < 0 or index >= quests.size() or target < 0 or target >= quests.size():
		return
	var quest: Dictionary = quests[index]
	quests[index] = quests[target]
	quests[target] = quest
	if selected == index:
		selected = target
	elif selected == target:
		selected = index
	changed.emit()


## Replaces one quest with its normalized version after an edit.
func update(index: int, quest: Dictionary) -> void:
	if index >= 0 and index < quests.size():
		quests[index] = MODEL.normalize(quest)
		changed.emit()


## 1-based numbers of the quests that use this object as a target or trigger.
func quests_using(object_id: String) -> Array[int]:
	var found: Array[int] = []
	if object_id.is_empty():
		return found
	for i in quests.size():
		var quest: Dictionary = quests[i]
		if object_id in quest.targets or str(quest.trigger.target) == object_id:
			found.append(i + 1)
	return found


## The object of this id inside the scene tree, or null.
static func find_object(tree: SceneTree, object_id: String) -> Node3D:
	if object_id.is_empty():
		return null
	for node: Node in tree.root.find_children("*", "Node3D", true, false):
		if str(node.get_meta(ID_META, "")) == object_id:
			return node as Node3D
	return null


## An object that can be a target gets an id the first time it is used.
static func ensure_id(node: Node) -> String:
	var id := str(node.get_meta(ID_META, ""))
	if id.is_empty():
		id = "object_%d" % Time.get_ticks_usec()
		node.set_meta(ID_META, id)
	return id


## Only the markers of these objects are shown; every other target marker is hidden.
static func show_markers(tree: SceneTree, nodes: Array) -> void:
	for node in tree.get_nodes_in_group(TARGET.GROUP):
		node.set_meta(&"planning_tutorial_revealed", node in nodes)
