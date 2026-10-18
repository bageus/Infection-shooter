extends Node
## Planner UI for new stamps, with an atlas preview and authored map persistence.
const MAP_SETTINGS := preload("res://game/bootstrap/app/planning_surface_decals.gd")
const CONFIG := preload("res://game/presentation/office_floor/public/surface_decal_config.gd")
const LABELS := ["Стекло: трещины", "Стены: повреждения", "Стены: потёртости", "Пол: повреждения", "Пол: потёртости", "Мусор на полу", "Следы попаданий"]
var session: Node
var popup: PopupPanel
var kinds: OptionButton
var opacity: SpinBox
var size: SpinBox
var preview: TextureRect
var _loading := false

func setup(context: Node) -> void:
	session = context
	var button := Button.new()
	button.name = "SurfaceDecalSettings"
	button.text = "Следы поверхностей…"
	session.ui.get_node("Panel/VBox").add_child(button)
	popup = PopupPanel.new()
	popup.name = "SurfaceDecalOptions"
	add_child(popup)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	popup.add_child(box)
	kinds = OptionButton.new()
	for label: String in LABELS: kinds.add_item(label)
	box.add_child(kinds)
	opacity = _number(box, "Непрозрачность, %", 0, 100, 1)
	size = _number(box, "Масштаб", 0.25, 2, 0.05)
	var area := CenterContainer.new()
	area.custom_minimum_size = Vector2(128, 128)
	box.add_child(area)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	area.add_child(preview)
	var hint := Label.new()
	hint.text = "Для новых следов. Сохраняется с картой.\nСлои: повреждения → потёртости → мусор."
	box.add_child(hint)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(popup.hide)
	box.add_child(close)
	button.pressed.connect(func() -> void: _select(); popup.popup_centered())
	kinds.item_selected.connect(func(_index: int) -> void: _select())
	opacity.value_changed.connect(_changed)
	size.value_changed.connect(_changed)

func _number(parent: Node, title: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	row.add_child(input)
	return input

func _select() -> void:
	_loading = true
	var kind: String = CONFIG.KINDS[kinds.selected]
	var settings := CONFIG.normalized(MAP_SETTINGS.capture(session))
	opacity.value = float(settings[kind].opacity) * 100.0
	size.value = float(settings[kind].size)
	var floor_view := MAP_SETTINGS.floor_for(session)
	if floor_view != null: preview.texture = floor_view.call("get_decal_preview", kind)
	_refresh_preview()
	_loading = false

func _changed(_value: float) -> void:
	if _loading: return
	var settings := CONFIG.normalized(MAP_SETTINGS.capture(session))
	settings[CONFIG.KINDS[kinds.selected]] = {"opacity": opacity.value / 100.0, "size": size.value}
	MAP_SETTINGS.restore(session, settings)
	_refresh_preview()

func _refresh_preview() -> void:
	preview.modulate.a = opacity.value / 100.0
	preview.custom_minimum_size = Vector2.ONE * 64.0 * size.value
