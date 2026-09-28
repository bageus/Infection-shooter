extends VBoxContainer

signal zone_changed(zone_name: String, required: bool, angle: float, category: String)

const ZONE_RULES := preload("res://game/bootstrap/app/desk_setup_zone_rules.gd")

var name_edit: LineEdit
var type_select: OptionButton
var category_select: OptionButton
var angle_spin: SpinBox
var _syncing := false


func _ready() -> void:
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Zone name"
	name_edit.text_changed.connect(_changed)
	add_child(name_edit)
	var type_row := HBoxContainer.new()
	add_child(type_row)
	var type_label := Label.new()
	type_label.text = "Type"
	type_row.add_child(type_label)
	type_select = OptionButton.new()
	type_select.add_item("Required", 0)
	type_select.add_item("Optional", 1)
	type_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_select.item_selected.connect(_changed)
	type_row.add_child(type_select)
	var category_row := HBoxContainer.new()
	add_child(category_row)
	var category_label := Label.new()
	category_label.text = "Object"
	category_row.add_child(category_label)
	category_select = OptionButton.new()
	for category in ZONE_RULES.CATEGORIES:
		category_select.add_item(category)
	category_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_select.item_selected.connect(_changed)
	category_row.add_child(category_select)
	var angle_row := HBoxContainer.new()
	add_child(angle_row)
	var angle_label := Label.new()
	angle_label.text = "Direction"
	angle_row.add_child(angle_label)
	angle_spin = SpinBox.new()
	angle_spin.min_value = -180
	angle_spin.max_value = 180
	angle_spin.step = 5
	angle_spin.suffix = "°"
	angle_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	angle_spin.value_changed.connect(_changed)
	angle_row.add_child(angle_spin)
	var minus := Button.new()
	minus.text = "-15°"
	minus.pressed.connect(_turn.bind(-15.0))
	angle_row.add_child(minus)
	var plus := Button.new()
	plus.text = "+15°"
	plus.pressed.connect(_turn.bind(15.0))
	angle_row.add_child(plus)


func display(zone: Dictionary) -> void:
	_syncing = true
	name_edit.text = str(zone.get("name", ""))
	type_select.select(0 if bool(zone.get("required", true)) else 1)
	var category_index := ZONE_RULES.CATEGORIES.find(str(zone.get("category", "Other")))
	category_select.select(maxi(category_index, 0))
	angle_spin.set_value_no_signal(float(zone.get("angle", 0.0)))
	_syncing = false


func editing_text() -> bool:
	return name_edit.has_focus() or angle_spin.get_line_edit().has_focus()


func _turn(amount: float) -> void:
	angle_spin.value = wrapf(angle_spin.value + amount, -180.0, 180.0)


func turn_by(amount: float) -> void:
	_turn(amount)


func _changed(_value: Variant) -> void:
	if not _syncing:
		zone_changed.emit(name_edit.text.strip_edges(), type_select.get_selected_id() == 0, angle_spin.value, category_select.get_item_text(category_select.selected))
