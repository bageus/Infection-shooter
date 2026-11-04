extends RefCounted
## Darkness rooms a door switches when it opens (and darkens again when it closes).
## Kept as metas on the door controller, so interactive_door.gd does not grow. A door with no
## list switches no zones. Auto fills the list from the zones the door leads into.

const ROOMS_META := &"darkness_rooms"
const AUTO_META := &"darkness_auto"


static func rooms(door: Node) -> Array:
	return Array(door.get_meta(ROOMS_META, []))


static func is_auto(door: Node) -> bool:
	return bool(door.get_meta(AUTO_META, false))


static func set_rooms(door: Node, ids: Array, auto := false) -> void:
	var unique: Array = []
	for id: Variant in ids:
		if int(id) > 0 and not unique.has(int(id)):
			unique.append(int(id))
	unique.sort()
	door.set_meta(ROOMS_META, unique)
	door.set_meta(AUTO_META, auto)


## Room ids of the darkness zones this door leads into, from the door's geometry.
static func detect(door: Node3D, inside: Node) -> Array:
	var found: Array = []
	for zone: Node in inside.get_tree().get_nodes_in_group("darkness_zone"):
		var id := int(zone.get("room_id"))
		if id > 0 and not zone.get("permanent") and not found.has(id) and bool(zone.call("door_leads_here", door)):
			found.append(id)
	found.sort()
	return found


## Saved form, or an empty dictionary when the door keeps the default (no list, not auto).
static func to_record(door: Node) -> Dictionary:
	if rooms(door).is_empty() and not is_auto(door):
		return {}
	return {"rooms": rooms(door), "auto": is_auto(door)}


static func from_record(door: Node, record: Dictionary) -> void:
	set_rooms(door, record.get("rooms", []), bool(record.get("auto", false)))


static func is_valid_record(record: Variant) -> bool:
	if not record is Dictionary:
		return false
	var ids: Variant = record.get("rooms", [])
	if not ids is Array or not record.get("auto", false) is bool:
		return false
	for id: Variant in ids:
		if not (id is int or id is float) or int(id) <= 0:
			return false
	return true
