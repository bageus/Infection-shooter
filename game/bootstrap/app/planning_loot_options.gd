extends Node
## Planner panel: loot of crates and infected, plus infected toughness, damage and death mutagen cloud.
## Works on the selected object, or on the palette preview until it is placed.

const CONFIG := preload("res://game/features/pickups/public/loot_config.gd")
const DEATH_CLOUD := preload("res://game/features/infected/public/death_cloud_settings.gd")
const CLOUD_TIME_LABELS := ["Нет", "Авто", "Вручную"]
const MODE_LABELS := ["Пусто", "Вручную", "Авто"]
const ITEM_LABELS := {
	"ammo_automate": "Патроны АК/M4", "ammo_sniper": "Патроны снайпер", "ammo_minigun": "Патроны миниган",
	"ammo_grenade": "Патроны гранатомёт",
	"ammo_pistol": "Патроны пистолет", "ammo_uzi": "Патроны UZI", "ammo_shotgun": "Патроны дробовик",
	"medkit": "Аптечка", "antidote": "Антидот", "dna": "ДНК",
}

var session: Variant
var objects: Variant
var panel: VBoxContainer
var title: Label
var mode: OptionButton
var items_box: GridContainer
var item_spins: Dictionary = {}
var auto_note: Label
var stats_box: VBoxContainer
var health: SpinBox
var damage: SpinBox
var cloud_on: CheckBox
var cloud_time: OptionButton
var cloud_seconds: SpinBox
var cloud_seconds_row: Control
var cloud_absorb: CheckBox
var cloud_units: SpinBox
var cloud_units_row: Control
var cloud_radius: SpinBox
var _updating := false
# What the next placed crate / infected starts with (kept between placements).
var loot_defaults: Dictionary = {}
var stats_defaults: Dictionary = {}
var cloud_defaults: Dictionary = {}


func setup(context: Variant, planner_objects: Variant) -> void:
	session = context
	objects = planner_objects
	panel = VBoxContainer.new()
	panel.name = "LootOptions"
	title = Label.new()
	panel.add_child(title)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Содержимое"
	row.add_child(label)
	mode = OptionButton.new()
	mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text: String in MODE_LABELS:
		mode.add_item(text)
	mode.item_selected.connect(_changed)
	row.add_child(mode)
	panel.add_child(row)
	items_box = GridContainer.new()
	items_box.columns = 2
	for id in CONFIG.item_ids():
		var caption := Label.new()
		var weapon := CONFIG.weapon_index(id)
		caption.text = ITEM_LABELS[id] if weapon < 0 else "Оружие: " + CONFIG.WEAPON_NAMES[weapon]
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		items_box.add_child(caption)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = CONFIG.MAX_COUNT
		spin.step = 1
		spin.value_changed.connect(_changed)
		items_box.add_child(spin)
		item_spins[id] = spin
	panel.add_child(items_box)
	auto_note = Label.new()
	auto_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto_note.custom_minimum_size.x = 220
	panel.add_child(auto_note)
	stats_box = VBoxContainer.new()
	health = _stat_row("Живучесть, %")
	damage = _stat_row("Урон, %")
	_cloud_rows()
	panel.add_child(stats_box)
	var box: Node = session.ui.get_node("Panel/VBox")
	box.add_child(panel)
	box.move_child(panel, session.ui.get_node("Panel/VBox/Palette").get_index() + 1)
	panel.hide()


func _stat_row(text: String) -> SpinBox:
	var spin := _spin(CONFIG.STAT_MIN, CONFIG.STAT_MAX, 5, 100, "%")
	_row(text, spin)
	return spin


func _spin(low: float, high: float, step: float, value: float, suffix: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.suffix = suffix
	spin.value_changed.connect(_changed)
	return spin


func _row(text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	stats_box.add_child(row)
	return row


# Death mutagen cloud of an infected: forms or not, ends by time and/or after absorption.
func _cloud_rows() -> void:
	cloud_on = CheckBox.new()
	cloud_on.text = "Облако мутагена после смерти"
	cloud_on.toggled.connect(_changed)
	stats_box.add_child(cloud_on)
	cloud_time = OptionButton.new()
	for text: String in CLOUD_TIME_LABELS:
		cloud_time.add_item(text)
	cloud_time.item_selected.connect(_changed)
	_row("Время жизни", cloud_time)
	cloud_seconds = _spin(DEATH_CLOUD.SECONDS_MIN, DEATH_CLOUD.SECONDS_MAX, 1, 14, " с")
	cloud_seconds_row = _row("Длительность, с", cloud_seconds)
	cloud_absorb = CheckBox.new()
	cloud_absorb.text = "Гаснет после всасывания"
	cloud_absorb.toggled.connect(_changed)
	stats_box.add_child(cloud_absorb)
	cloud_units = _spin(DEATH_CLOUD.UNITS_MIN, DEATH_CLOUD.UNITS_MAX, 1, 10, "")
	cloud_units_row = _row("Мутаген, ед.", cloud_units)
	cloud_radius = _spin(DEATH_CLOUD.RADIUS_MIN, DEATH_CLOUD.RADIUS_MAX, 0.05, DEATH_CLOUD.RADIUS_DEFAULT, " м")
	_row("Радиус облака", cloud_radius)


func _target() -> Node3D:
	return objects.selected if objects.selected != null else objects.preview


func _has_loot(target: Node3D) -> bool:
	return target != null and target.has_method("configure_loot") and (not target.has_method("has_loot") or bool(target.call("has_loot")))


func _has_stats(target: Node3D) -> bool:
	return target != null and target.has_method("configure_stats")


func applies_to(target: Node3D) -> bool:
	return _has_loot(target) or _has_stats(target)


func update() -> void:
	var target := _target()
	var loot := _has_loot(target)
	var stats := _has_stats(target)
	panel.visible = loot or stats
	if not panel.visible:
		return
	_updating = true
	var suffix := "" if objects.selected != null else " | размещение"
	title.text = ("ВРАГ" if stats else "ЯЩИК") + suffix
	var config: Dictionary = target.call("get_loot_config")
	mode.select(maxi(CONFIG.MODES.find(str(config["mode"])), 0))
	for id: String in item_spins:
		(item_spins[id] as SpinBox).set_value_no_signal(float((config["items"] as Dictionary).get(id, 0)))
	var manual: bool = str(config["mode"]) == "manual"
	items_box.visible = manual
	auto_note.visible = not manual
	auto_note.text = _note(str(config["mode"]), stats)
	stats_box.visible = stats
	if stats:
		var values: Dictionary = target.call("get_enemy_stats")
		health.set_value_no_signal(float(values["health"]))
		damage.set_value_no_signal(float(values["damage"]))
		var death: Dictionary = target.call("get_death_cloud_config")
		cloud_on.set_pressed_no_signal(bool(death["enabled"]))
		cloud_time.select(DEATH_CLOUD.TIME_MODES.find(str(death["time"])))
		cloud_seconds.set_value_no_signal(float(death["seconds"]))
		cloud_absorb.set_pressed_no_signal(bool(death["absorb"]))
		cloud_units.set_value_no_signal(float(death["units"]))
		cloud_radius.set_value_no_signal(float(death["radius"]))
		cloud_seconds_row.visible = str(death["time"]) == "manual"
		cloud_units_row.visible = bool(death["absorb"])
	_updating = false


func _note(mode_name: String, enemy: bool) -> String:
	if mode_name == "empty":
		return "Ничего не выпадает."
	if enemy:
		return "Случайная добыча как раньше: аптечки, патроны, иногда антидот."
	return "Случайный набор из патронов, аптечек, антидота и ДНК; большой ящик содержит больше."


func hide() -> void:
	if panel != null:
		panel.hide()


## A freshly created object starts with the options last chosen in the panel.
func configure_new(target: Node3D) -> void:
	if _has_loot(target) and not loot_defaults.is_empty():
		target.call("configure_loot", loot_defaults)
	if _has_stats(target) and not stats_defaults.is_empty():
		target.call("configure_stats", stats_defaults)
	if _has_stats(target) and not cloud_defaults.is_empty():
		target.call("configure_death_cloud", cloud_defaults)


func _read_config() -> Dictionary:
	var items := {}
	for id: String in item_spins:
		var count := int((item_spins[id] as SpinBox).value)
		if count > 0:
			items[id] = count
	return {"mode": CONFIG.MODES[mode.selected], "items": items}


func _read_cloud() -> Dictionary:
	return {"enabled": cloud_on.button_pressed, "time": DEATH_CLOUD.TIME_MODES[cloud_time.selected], "seconds": cloud_seconds.value,
		"absorb": cloud_absorb.button_pressed, "units": cloud_units.value, "radius": cloud_radius.value}


func _changed(_value: Variant = null) -> void:
	if _updating:
		return
	var target := _target()
	if target == null:
		return
	if objects.selected != null:
		session.edit_history.call("record_transform", target)
	var config := _read_config()
	if _has_loot(target):
		target.call("configure_loot", config)
		if objects.selected == null:
			loot_defaults = config
	if _has_stats(target):
		var stats := {"health": health.value, "damage": damage.value}
		target.call("configure_stats", stats)
		if objects.selected == null:
			stats_defaults = stats
		var death := _read_cloud()
		target.call("configure_death_cloud", death)
		if objects.selected == null:
			cloud_defaults = death
	update()
