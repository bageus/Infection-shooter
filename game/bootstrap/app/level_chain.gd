extends RefCounted
## Ordered list of saved maps forming a level chain. Map N links only to N-1 and N+1.
## Each map has two entry points: slot 0 leads to the previous map, slot 1 to the next one.
## An entry is "none", a "ceiling" (stairs up) or a "floor" (stairs down), placed at x/z.

const VERSION := 1
const PATH := "user://level_chain.json"
const TYPES: Array[String] = ["none", "ceiling", "floor"]
const SLOT_COUNT := 2
## Player height beyond which the stairs count as climbed (ceiling) or descended (floor).
const CLIMB_HEIGHT := 2.4
## Horizontal reach of an entry point around its x/z.
const ENTRY_RADIUS := 4.5

var maps: Array[Dictionary] = []


static func empty_entry() -> Dictionary:
	return {"type": "none", "x": 0.0, "z": 0.0, "placed": false}


static func _clean_entry(raw: Variant) -> Dictionary:
	var entry := empty_entry()
	if raw is Dictionary:
		var kind := str(raw.get("type", "none"))
		entry["type"] = kind if kind in TYPES else "none"
		entry["x"] = float(raw.get("x", 0.0))
		entry["z"] = float(raw.get("z", 0.0))
		entry["placed"] = bool(raw.get("placed", false))
	return entry


func names() -> Array[String]:
	var result: Array[String] = []
	for item in maps:
		result.append(str(item.name))
	return result


func index_of(map_name: String) -> int:
	for i in maps.size():
		if maps[i].name == map_name:
			return i
	return -1


func add_map(map_name: String) -> bool:
	if map_name.is_empty() or index_of(map_name) >= 0:
		return false
	maps.append({"name": map_name, "entries": [empty_entry(), empty_entry()]})
	return true


func remove_map(index: int) -> void:
	if index >= 0 and index < maps.size():
		maps.remove_at(index)


func move_map(index: int, direction: int) -> int:
	var target := index + direction
	if index < 0 or index >= maps.size() or target < 0 or target >= maps.size():
		return index
	var item: Dictionary = maps[index]
	maps[index] = maps[target]
	maps[target] = item
	return target


func entry(index: int, slot: int) -> Dictionary:
	return maps[index].entries[slot]


func set_entry_type(index: int, slot: int, kind: String) -> void:
	if kind in TYPES:
		maps[index].entries[slot]["type"] = kind


func place_entry(index: int, slot: int, x: float, z: float) -> void:
	var item: Dictionary = maps[index].entries[slot]
	item["x"] = x
	item["z"] = z
	item["placed"] = true


## Neighbour reached through the slot: slot 0 is the previous map, slot 1 the next one. "" if none.
func neighbour(index: int, slot: int) -> String:
	var target := index - 1 if slot == 0 else index + 1
	return str(maps[target].name) if index >= 0 and target >= 0 and target < maps.size() else ""


## True when the entry can be used: it has a stairs type, a position and a neighbour map.
func is_active(index: int, slot: int) -> bool:
	var item := entry(index, slot)
	return item.type != "none" and item.placed and not neighbour(index, slot).is_empty()


## Entry the player used at (position, height), or -1.
func triggered_slot(index: int, x: float, z: float, height: float) -> int:
	if index < 0 or index >= maps.size():
		return -1
	for slot in SLOT_COUNT:
		if not is_active(index, slot):
			continue
		var item := entry(index, slot)
		var climbed: bool = height > CLIMB_HEIGHT if item.type == "ceiling" else height < -CLIMB_HEIGHT
		if climbed and Vector2(x - float(item.x), z - float(item.z)).length() <= ENTRY_RADIUS:
			return slot
	return -1


## Where the player appears in the neighbour map after leaving through `slot`:
## the neighbour's entry that leads back, or {} when that entry is unusable.
func arrival(index: int, slot: int) -> Dictionary:
	var target := index - 1 if slot == 0 else index + 1
	var back := 1 if slot == 0 else 0
	if target < 0 or target >= maps.size() or not is_active(target, back):
		return {}
	var item := entry(target, back)
	return {"x": float(item.x), "z": float(item.z)}


func to_dict() -> Dictionary:
	return {"version": VERSION, "maps": maps.duplicate(true)}


func load_dict(data: Variant) -> void:
	maps.clear()
	if not data is Dictionary or not data.get("maps") is Array:
		return
	for raw in data["maps"]:
		if not raw is Dictionary or str(raw.get("name", "")).is_empty() or index_of(str(raw.name)) >= 0:
			continue
		var entries: Array = raw.get("entries", []) if raw.get("entries") is Array else []
		maps.append({"name": str(raw.name),
			"entries": [_clean_entry(entries[0] if entries.size() > 0 else null), _clean_entry(entries[1] if entries.size() > 1 else null)]})


func save(path: String = PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


func load_file(path: String = PATH) -> void:
	maps.clear()
	if FileAccess.file_exists(path):
		load_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
