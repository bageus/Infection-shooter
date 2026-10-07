extends RefCounted
## Intrusive ID FIFO: retirement/removal never shifts or scans mark arrays.
var first := -1
var _last := -1
var _links: Dictionary = {}

func append(id: int) -> void:
	_links[id] = {"before": _last, "after": -1}
	if _last >= 0:
		_links[_last]["after"] = id
	else:
		first = id
	_last = id

func remove(id: int) -> void:
	if not _links.has(id):
		return
	var link: Dictionary = _links[id]
	if link["before"] >= 0:
		_links[link["before"]]["after"] = link["after"]
	else:
		first = link["after"]
	if link["after"] >= 0:
		_links[link["after"]]["before"] = link["before"]
	else:
		_last = link["before"]
	_links.erase(id)
