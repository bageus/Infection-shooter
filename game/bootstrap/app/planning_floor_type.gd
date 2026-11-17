extends Node
## Floor material of the location: tile (default) or matte worn concrete. A map setting saved as floor_type_v1.
const TYPES: Array[String] = ["tile", "concrete"]
const LABELS: Array[String] = ["Плитка", "Бетон (матовый, с потёртостями)"]
const DEFAULT := "tile"
## Tile edge in metres, a map setting saved as floor_tile_step_v1 (the stock grid is 2 m).
const TILE_KEY := "floor_tile_step_v1"
const TILE_LIMITS := Vector2(1.0, 4.0)
const TILE_DEFAULT := 2.0

var session: Variant
var controls: Node
var panel: VBoxContainer
var picker: OptionButton
var group_button: Button
var tile_step: SpinBox


static func valid(raw: Variant) -> bool:
	return raw is String and raw in TYPES


static func capture(session_context: Variant) -> String:
	var floor_view := _floor(session_context)
	return str(floor_view.get("floor_type")) if floor_view != null else DEFAULT


## A map without the key restores tile, so a previous map's floor never carries over.
static func restore(session_context: Variant, raw: Variant) -> void:
	var floor_view := _floor(session_context)
	if floor_view != null:
		floor_view.call("set_floor_type", raw if valid(raw) else DEFAULT)


static func valid_tile(raw: Variant) -> bool:
	return (raw is float or raw is int) and float(raw) >= TILE_LIMITS.x and float(raw) <= TILE_LIMITS.y


static func capture_tile(session_context: Variant) -> float:
	var floor_view := _floor(session_context)
	return float(floor_view.get("tile_step")) if floor_view != null else TILE_DEFAULT


## A map without the key restores the stock 2 m tile.
static func restore_tile(session_context: Variant, raw: Variant) -> void:
	var floor_view := _floor(session_context)
	if floor_view != null:
		floor_view.call("set_tile_step", float(raw) if valid_tile(raw) else TILE_DEFAULT)


static func _floor(session_context: Variant) -> Node3D:
	var host: Variant = session_context.get("host") if session_context is Node else null
	var floor_view: Node3D = host.get_node_or_null("Floor") as Node3D if host is Node else null
	return floor_view if floor_view != null and floor_view.has_method("set_floor_type") else null


## Adds the Floor group button to the Structure group tabs and its options panel under them.
func setup(context: Variant, controls_node: Node) -> void:
	session = context
	controls = controls_node
	var box: Node = session.ui.get_node("Panel/VBox")
	group_button = Button.new()
	group_button.name = "GFloor"
	group_button.text = "Floor"
	group_button.pressed.connect(show_group)
	box.get_node("GroupTabs").add_child(group_button)
	panel = VBoxContainer.new()
	panel.name = "FloorType"
	var title := Label.new()
	title.text = "Тип пола уровня"
	panel.add_child(title)
	picker = OptionButton.new()
	for label in LABELS:
		picker.add_item(label)
	picker.item_selected.connect(func(index: int) -> void: restore(session, TYPES[index]))
	panel.add_child(picker)
	var tile_title := Label.new()
	tile_title.text = "Размер ячейки плитки, м"
	panel.add_child(tile_title)
	tile_step = SpinBox.new()
	tile_step.min_value = TILE_LIMITS.x
	tile_step.max_value = TILE_LIMITS.y
	tile_step.step = 0.5
	tile_step.value_changed.connect(func(value: float) -> void: restore_tile(session, value))
	panel.add_child(tile_step)
	panel.hide()
	box.add_child(panel)
	box.move_child(panel, controls.palette.get_index())


func show_group() -> void:
	controls.light_defaults.hide()
	controls.objects._reset_selection()
	controls.catalog.active_catalog = []
	controls._rebuild_palette()
	picker.select(maxi(TYPES.find(capture(session)), 0))
	tile_step.set_value_no_signal(capture_tile(session))
	panel.show()
	controls.status.text = "STRUCTURE Floor | choose the floor type of this level"
