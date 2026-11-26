extends RefCounted
## Map mode switch of the constructor: "campaign" (default) or "web" (arena with coins and endless waves).
## A map saves it as map_mode_v1; a map without the key restores "campaign", so old maps are unchanged.
const KEY := "map_mode_v1"
const MODES: Array[String] = ["campaign", "web"]
const LABELS: Array[String] = ["Кампания", "Веб (арена)"]
const DEFAULT := "campaign"

static var current := DEFAULT

var controls: Node
var picker: OptionButton


static func valid(raw: Variant) -> bool:
	return raw is String and raw in MODES


static func is_web() -> bool:
	return current == "web"


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	picker = OptionButton.new()
	picker.name = "MapMode"
	picker.tooltip_text = "Режим карты: кампания или веб-арена (монеты, бесконечные волны, орда)."
	for label in LABELS:
		picker.add_item(label)
	picker.select(MODES.find(current))
	picker.item_selected.connect(func(index: int) -> void: current = MODES[index])
	var box: Node = controls.session.ui.get_node("Panel/VBox")
	box.add_child(picker)
	box.move_child(picker, 0)


static func capture(_session: Variant) -> String:
	return current


static func restore(session: Variant, raw: Variant) -> void:
	current = raw if valid(raw) else DEFAULT
	var panel: Variant = session.get("controls") if session is Object else null
	if panel != null and panel.map_mode.picker != null:
		panel.map_mode.picker.select(MODES.find(current))
