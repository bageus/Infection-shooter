extends RefCounted
## Bridges the map file and the nodes under the main scene: the QuestBook (quests of this map) and the
## level chain (which map follows which; every map file carries the whole structure).

const KEY := "quests_v1"
const CHAIN_KEY := "level_chain_v1"
const BOOK_NAME := "QuestBook"


static func book(session: Variant) -> Node:
	var host: Variant = session.get("host") if session is Node else null
	return (host as Node).get_node_or_null(BOOK_NAME) if host is Node else null


static func _chain(session: Variant) -> RefCounted:
	var host: Variant = session.get("host") if session is Node else null
	var entries: Node = (host as Node).get_node_or_null("LevelEntries") if host is Node else null
	return entries.get("chain") if entries != null else null


## Adds the quest list and the chain structure to a map record.
static func add_to(session: Variant, data: Dictionary) -> void:
	var quest_book := book(session)
	if quest_book != null and not quest_book.call("capture").is_empty():
		data[KEY] = quest_book.call("capture")
	var chain := _chain(session)
	if chain != null and not chain.maps.is_empty():
		data[CHAIN_KEY] = chain.to_dict()


## Copies the quest and chain parts of a map file into the staged load.
static func stage(data: Dictionary, prepared: Dictionary) -> void:
	prepared[KEY] = data.get(KEY, [])
	prepared[CHAIN_KEY] = data.get(CHAIN_KEY, {})


## A map without quests restores an empty list. The map's chain is adopted only when this machine has none,
## so loading a map never overwrites the chain the player built.
static func restore(session: Variant, prepared: Dictionary) -> void:
	var quest_book := book(session)
	if quest_book != null:
		quest_book.call("restore", prepared.get(KEY, []))
	var chain := _chain(session)
	var saved: Variant = prepared.get(CHAIN_KEY, {})
	if chain != null and chain.maps.is_empty() and saved is Dictionary and not saved.is_empty():
		chain.load_dict(saved)
		chain.save()
