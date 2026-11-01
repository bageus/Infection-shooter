extends RefCounted
## Bridges the map file and the QuestBook node that lives under the main scene.

const KEY := "quests_v1"
const BOOK_NAME := "QuestBook"


static func book(session: Variant) -> Node:
	var host: Variant = session.get("host") if session is Node else null
	return (host as Node).get_node_or_null(BOOK_NAME) if host is Node else null


static func capture(session: Variant) -> Array:
	var quest_book := book(session)
	return quest_book.call("capture") if quest_book != null else []


## A map without quests restores an empty list.
static func restore(session: Variant, raw: Variant) -> void:
	var quest_book := book(session)
	if quest_book != null:
		quest_book.call("restore", raw)


## Adds the list to a map record when there is one.
static func add_to(session: Variant, data: Dictionary) -> void:
	var quests := capture(session)
	if not quests.is_empty():
		data[KEY] = quests
