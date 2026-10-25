extends RefCounted
## Presentation-only authored model families; unknown solid metal/ceramic gets no invented debris.


static func is_screen(model: String) -> bool:
	var label := model.to_lower()
	return has_any(label, ["monitor", "wall_tv", "television", "laptop", "display"])


static func for_model(model: String, event: String) -> Array[String]:
	var label := model.to_lower()
	if event == "shatter" and (has_any(label, ["painting", "09_fruit_", "09_glass", "09_mug"])):
		return _shattered(label)
	if event == "screen":
		if is_screen(label):
			return _mix(["plastic", "glass", "paper"], [5, 5, 2])
		return []
	if "extinguisher" in label:
		if event == "rupture":
			return _mix(["extinguisher", "plastic"], [3, 1])
		return []
	if is_screen(label):
		return _mix(["plastic", "glass", "paper"], [6, 4, 2])
	if "cardboard" in label:
		return _mix(["cardboard", "paper", "wood", "plastic"], [8, 2, 1, 1])
	if has_any(label, ["book_case", "bookshelf", "bookcase"]):
		return _mix(["wood", "paper", "plastic"], [7, 4, 1])
	if has_any(label, ["09_book", "paper", "notepad", "office_file", "file_binder", "document", "envelope", "newspaper", "magazine", "letter"]):
		return _mix(["paper"], [10])
	if has_any(label, ["crate", "wood_box"]):
		return _mix(["wood", "cardboard", "paper", "plastic"], [6, 3, 2, 1])
	if has_any(label, ["sofa", "couch", "armchair", "office_chair", "conference_chair", "beanbag", "upholster"]):
		return _mix(["fabric", "plastic", "wood", "paper"], [6, 3, 2, 1])
	if has_any(label, ["table", "office_desk", "reception", "workstation"]) or ("_desk" in label and "05_" not in label):
		return _mix(["wood", "paper", "plastic", "fabric", "extinguisher"], [6, 3, 1, 1, 1])
	if has_any(label, ["partition", "divider", "board_stand"]):
		return _mix(["wood", "paper", "fabric", "plastic"], [5, 3, 3, 1])
	if has_any(label, ["file_cabinet", "drawer_cabinet"]):
		return _mix(["wood", "paper", "plastic"], [6, 3, 1])
	if has_any(label, ["locker"]):
		return _mix(["paper", "plastic", "wood"], [8, 3, 1])
	if has_any(label, ["wood", "simple_chair", "shelf", "capboard", "cupboard"]):
		return _mix(["wood", "paper", "plastic"], [8, 3, 1])
	if has_any(label, ["09_pen_", "09_pencil", "09_marker", "stapler", "05_", "plastic", "keyboard", "printer", "computer", "phone", "trash_bin", "pencil_holder", "water_cooler", "coffee_machine", "microwave", "kittle", "vending", "arcade"]):
		return _mix(["plastic", "paper", "wood", "fabric"], [8, 2, 1, 1])
	return []


## Fragile items: paintings leave paper, cardboard and wood; fruit leaves plastic; plates and glassware leave glass and plastic.
static func _shattered(label: String) -> Array[String]:
	if "painting" in label:
		return _mix(["paper", "cardboard", "wood"], [4, 3, 3])
	if label.begins_with("09_fruit_") and "plate" not in label:
		return _mix(["plastic"], [3])
	return _mix(["glass", "plastic"], [6, 3])


static func has_any(label: String, tokens: Array) -> bool:
	for token: String in tokens:
		if token in label:
			return true
	return false


static func _mix(kinds: Array, amounts: Array) -> Array[String]:
	var result: Array[String] = []
	for index in kinds.size():
		for count in int(amounts[index]):
			result.append(str(kinds[index]))
	return result
