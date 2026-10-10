extends RefCounted
## Stable binary min-heap for frontier cells and waiting route slices.
var entries: Array[Dictionary] = []
var _serial := 0


func push(entry: Dictionary, score: float) -> void:
	entry = entry.duplicate()
	entry["score"] = score
	entry["serial"] = _serial
	_serial += 1
	entries.append(entry)
	var index := entries.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if not _before(entries[index], entries[parent]):
			break
		var swap := entries[parent]
		entries[parent] = entries[index]
		entries[index] = swap
		index = parent


func pop() -> Dictionary:
	if entries.is_empty():
		return {}
	var first := entries[0]
	var last := entries.pop_back() as Dictionary
	if entries.is_empty():
		return first
	entries[0] = last
	var index := 0
	while index * 2 + 1 < entries.size():
		var child := index * 2 + 1
		if child + 1 < entries.size() and _before(entries[child + 1], entries[child]):
			child += 1
		if not _before(entries[child], entries[index]):
			break
		var swap := entries[index]
		entries[index] = entries[child]
		entries[child] = swap
		index = child
	return first


func _before(a: Dictionary, b: Dictionary) -> bool:
	return float(a.score) < float(b.score) or (a.score == b.score and int(a.serial) < int(b.serial))
