extends Node
## Floor material of the location: grey tile (default), worn concrete, wood, carpet or white lab tile. A map setting saved as floor_type_v1.
const TYPES: Array[String] = ["tile", "concrete", "wood", "carpet", "lab_tile"]
const LABELS: Array[String] = ["Плитка", "Бетон (матовый, с потёртостями)", "Паркет (имитация дерева)", "Ковролин", "Белая лабораторная плитка"]
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
var paint_check: CheckBox


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


## Painted areas, a map setting saved as floor_areas_v1: [column, row, type] per 2 m cell.
static func valid_areas(raw: Variant) -> bool:
	if not raw is Array:
		return false
	for area: Variant in raw:
		if not area is Array or area.size() != 3 or not valid(area[2]):
			return false
		for coordinate: Variant in area.slice(0, 2):
			if not (coordinate is int or coordinate is float) or float(coordinate) != floorf(float(coordinate)):
				return false
	return true


## Writes the floor settings of a layout record; areas are left out when no cell is painted.
static func capture_into(session_context: Variant, data: Dictionary) -> void:
	data["floor_type_v1"] = capture(session_context)
	data["floor_tile_step_v1"] = capture_tile(session_context)
	var areas := capture_areas(session_context)
	if not areas.is_empty():
		data["floor_areas_v1"] = areas


static func capture_areas(session_context: Variant) -> Array:
	var floor_view := _floor(session_context)
	return floor_view.call("get_floor_areas") if floor_view != null else []


static func restore_areas(session_context: Variant, raw: Variant) -> void:
	var floor_view := _floor(session_context)
	if floor_view != null:
		floor_view.call("set_floor_areas", raw if valid_areas(raw) else [])


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
	picker.item_selected.connect(func(index: int) -> void:
		if not painting():
			restore(session, TYPES[index]))
	panel.add_child(picker)
	paint_check = CheckBox.new()
	paint_check.text = "Кисть: красить участки выбранным типом (ЛКМ по полу)"
	panel.add_child(paint_check)
	var clear_areas := Button.new()
	clear_areas.text = "Убрать все покрашенные участки"
	clear_areas.pressed.connect(func() -> void: restore_areas(session, []))
	panel.add_child(clear_areas)
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


## True while the Floor panel is open with the brush on: left clicks then paint cells instead of selecting.
func painting() -> bool:
	return panel != null and panel.visible and paint_check.button_pressed


## Paints the picked type on the floor cell under the cursor; the floor plane is at the floor's height.
func paint_at(screen_pos: Vector2) -> void:
	var floor_view := _floor(session)
	var camera: Camera3D = session.camera
	if floor_view == null or camera == null:
		return
	var hit: Variant = Plane(Vector3.UP, floor_view.global_position.y).intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return
	var local: Vector3 = floor_view.to_local(hit)
	floor_view.call("paint_floor_cell", Vector2(local.x, local.z), TYPES[picker.selected])


func show_group() -> void:
	controls.light_defaults.hide()
	controls.objects._reset_selection()
	controls.catalog.active_catalog = []
	controls._rebuild_palette()
	picker.select(maxi(TYPES.find(capture(session)), 0))
	tile_step.set_value_no_signal(capture_tile(session))
	panel.show()
	controls.status.text = "STRUCTURE Floor | choose the floor type of this level"
