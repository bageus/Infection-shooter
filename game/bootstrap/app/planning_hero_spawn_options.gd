extends Node
## Planner panel for the hero spawn, shown with the Player Spawn palette entry: automatic carry
## from the linked mission, or a manual loadout (weapon slots, ammo, health, threshold, items).

const HERO := preload("res://game/bootstrap/app/planning_hero_spawn.gd")

var session: Variant
var objects: Variant
var panel: PanelContainer
var _mode: OptionButton
var _manual: VBoxContainer
var _slots: Array[OptionButton] = []
var _ammo: Array[SpinBox] = []
var _health: SpinBox
var _threshold: SpinBox
var _antidotes: SpinBox
var _gas_mask: CheckBox
var _armor: CheckBox
var _key: CheckBox
var _updating := false


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = PanelContainer.new()
	panel.name = "HeroSpawn"
	panel.custom_minimum_size.x = 300
	panel.hide()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Точка спавна героя"
	column.add_child(title)
	_mode = OptionButton.new()
	_mode.add_item("Автоматически", 0)
	_mode.add_item("Вручную", 1)
	_mode.item_selected.connect(func(_index: int) -> void: _changed())
	column.add_child(_mode)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 300
	hint.text = "Автоматически: прогресс переносится из связанной миссии. Вручную: задаются значения ниже."
	column.add_child(hint)
	_manual = VBoxContainer.new()
	_manual.add_theme_constant_override("separation", 4)
	column.add_child(_manual)
	for slot in HERO.SLOT_COUNT:
		var option := OptionButton.new()
		option.add_item("Пусто", -1)
		for weapon in HERO.WEAPON_NAMES.size():
			option.add_item(HERO.WEAPON_NAMES[weapon], weapon)
		option.item_selected.connect(func(_index: int) -> void: _changed())
		_slots.append(option)
		_manual.add_child(_row("Слот %d" % (slot + 1), option))
	for weapon in HERO.WEAPON_NAMES.size():
		var ammo := _spin(0, HERO.MAX_AMMO, 1)
		_ammo.append(ammo)
		var label: String = HERO.WEAPON_NAMES[weapon] + (" (общий с АК)" if weapon == HERO.SHARED_RESERVE_WEAPON else "")
		ammo.editable = weapon != HERO.SHARED_RESERVE_WEAPON
		_manual.add_child(_row("Патроны: " + label, ammo))
	_health = _spin(1, HERO.MAX_HEALTH, 1)
	_manual.add_child(_row("Здоровье", _health))
	_threshold = _spin(HERO.MIN_THRESHOLD, HERO.MAX_THRESHOLD, 1)
	_manual.add_child(_row("Порог мутагена", _threshold))
	_antidotes = _spin(0, HERO.MAX_ANTIDOTES, 1)
	_manual.add_child(_row("Антидоты", _antidotes))
	_gas_mask = _check("Противогаз")
	_armor = _check("Бронежилет")
	_key = _check("Ключ от пожарной лестницы")
	_manual.add_child(_gas_mask)
	_manual.add_child(_armor)
	_manual.add_child(_key)
	session.ui.add_child(panel)


func contains_point(screen_position: Vector2) -> bool:
	return panel != null and panel.is_visible_in_tree() and panel.get_global_rect().has_point(screen_position)


## Shows the panel while the Player Spawn is the selected palette entry, with its saved settings.
func update() -> void:
	if panel == null:
		return
	panel.visible = objects._selected_kind() == "player"
	if not panel.visible:
		return
	var hero: Dictionary = objects.hero_spawn
	_updating = true
	_mode.select(1 if hero.mode == "manual" else 0)
	for slot in HERO.SLOT_COUNT:
		_slots[slot].select(_slots[slot].get_item_index(hero.slots[slot]))
	for weapon in HERO.WEAPON_NAMES.size():
		_ammo[weapon].value = hero.ammo[weapon]
	_health.value = hero.health
	_threshold.value = hero.threshold
	_antidotes.value = hero.antidotes
	_gas_mask.button_pressed = hero.gas_mask
	_armor.button_pressed = hero.armor
	_key.button_pressed = hero.key
	_manual.visible = hero.mode == "manual"
	_updating = false


func _changed() -> void:
	if _updating:
		return
	var hero := HERO.defaults()
	hero.mode = "manual" if _mode.selected == 1 else "auto"
	for slot in HERO.SLOT_COUNT:
		hero.slots[slot] = _slots[slot].get_item_id(_slots[slot].selected)
	for weapon in HERO.WEAPON_NAMES.size():
		hero.ammo[weapon] = int(_ammo[weapon].value)
	hero.health = _health.value
	hero.threshold = _threshold.value
	hero.antidotes = int(_antidotes.value)
	hero.gas_mask = _gas_mask.button_pressed
	hero.armor = _armor.button_pressed
	hero.key = _key.button_pressed
	objects.hero_spawn = HERO.sanitize(hero)
	update()


func _row(caption: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size.x = 120
	row.add_child(control)
	return row


func _spin(low: float, high: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value_changed.connect(func(_value: float) -> void: _changed())
	return spin


func _check(caption: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = caption
	box.toggled.connect(func(_on: bool) -> void: _changed())
	return box
