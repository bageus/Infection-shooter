extends VBoxContainer
## Settings of one spawn point's queues inside the wave panel: pick a queue, edit
## the infected it spawns, how it spawns and what starts it. Edits are applied to a
## working copy of the point config and reported through `changed`.

signal changed(config: Dictionary)

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")

var queue_option: OptionButton
var add_queue_button: Button
var remove_queue_button: Button
var entries_box: VBoxContainer
var add_entry_button: Button
var interval_spin: SpinBox
var rule_option: OptionButton
var batch_row: HBoxContainer
var batch_label: Label
var batch_spin: SpinBox
var start_row: HBoxContainer
var start_option: OptionButton
var delay_row: HBoxContainer
var delay_spin: SpinBox
var trigger_row: HBoxContainer
var trigger_option: OptionButton
var health_spin: SpinBox
var damage_spin: SpinBox
var current := 0
var _config := SPAWN_CONFIG.defaults()
var _updating := false


func _init() -> void:
	var picker := HBoxContainer.new()
	add_child(picker)
	queue_option = OptionButton.new()
	queue_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_option.item_selected.connect(_select_queue)
	picker.add_child(queue_option)
	add_queue_button = _button(picker, "+", _add_queue)
	remove_queue_button = _button(picker, "−", _remove_queue)
	entries_box = VBoxContainer.new()
	add_child(entries_box)
	add_entry_button = _button(self, "+ Монстр", _add_entry)
	interval_spin = _spin_row("Интервал, сек", SPAWN_CONFIG.INTERVAL_MIN, SPAWN_CONFIG.INTERVAL_MAX, 0.1)
	rule_option = _option_row("Правило", SPAWN_CONFIG.RULE_LABELS)
	batch_row = HBoxContainer.new()
	add_child(batch_row)
	batch_label = Label.new()
	batch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	batch_row.add_child(batch_label)
	batch_spin = _spin(1, SPAWN_CONFIG.BATCH_MAX, 1)
	batch_spin.value_changed.connect(_read_settings)
	batch_row.add_child(batch_spin)
	start_option = _option_row("Старт очереди", SPAWN_CONFIG.START_LABELS)
	start_row = start_option.get_parent()
	delay_spin = _spin_row("Задержка, сек", 0.0, SPAWN_CONFIG.DELAY_MAX, 0.5)
	delay_row = delay_spin.get_parent()
	trigger_option = _option_row("Запуск", SPAWN_CONFIG.TRIGGER_LABELS)
	trigger_row = trigger_option.get_parent()
	health_spin = _spin_row("Живучесть, %", SPAWN_CONFIG.STAT_MIN, SPAWN_CONFIG.STAT_MAX, 5.0)
	damage_spin = _spin_row("Урон, %", SPAWN_CONFIG.STAT_MIN, SPAWN_CONFIG.STAT_MAX, 5.0)


func config() -> Dictionary:
	return _config.duplicate(true)


## Shows `new_config`; `queue_index` keeps the queue being edited when it still exists.
func load_config(new_config: Dictionary, queue_index: int = -1) -> void:
	_config = SPAWN_CONFIG.sanitize(new_config)
	var queues: Array = _config["queues"]
	current = clampi(current if queue_index < 0 else queue_index, 0, queues.size() - 1)
	_updating = true
	queue_option.clear()
	for index in queues.size():
		queue_option.add_item("Очередь %d: %s" % [index + 1, SPAWN_CONFIG.queue_summary(queues[index])])
	queue_option.select(current)
	add_queue_button.disabled = queues.size() >= SPAWN_CONFIG.QUEUES_MAX
	remove_queue_button.disabled = queues.size() <= 1
	var queue: Dictionary = queues[current]
	_load_entries(queue)
	interval_spin.set_value_no_signal(float(queue["interval"]))
	rule_option.select(maxi(SPAWN_CONFIG.RULES.find(str(queue["rule"])), 0))
	batch_spin.set_value_no_signal(float(queue["batch"]))
	batch_row.visible = str(queue["rule"]) != "stream"
	batch_label.text = "Размер пачки" if str(queue["rule"]) == "burst" else "Держать рядом, не более"
	var timed := current > 0 and str(queue["start"]) == "time"
	start_row.visible = current > 0
	start_option.select(maxi(SPAWN_CONFIG.STARTS.find(str(queue["start"])), 0))
	delay_row.visible = timed
	trigger_row.visible = not timed
	delay_spin.set_value_no_signal(float(queue["delay"]))
	trigger_option.select(maxi(SPAWN_CONFIG.TRIGGERS.find(str(queue["trigger"])), 0))
	health_spin.set_value_no_signal(float(queue["health"]))
	damage_spin.set_value_no_signal(float(queue["damage"]))
	_updating = false


func _load_entries(queue: Dictionary) -> void:
	for child in entries_box.get_children():
		entries_box.remove_child(child)
		child.queue_free()
	var entries: Array = queue["enemies"]
	for index in entries.size():
		var row := HBoxContainer.new()
		var kind := OptionButton.new()
		kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for label in SPAWN_CONFIG.ENEMY_LABELS:
			kind.add_item(label)
		kind.select(maxi(SPAWN_CONFIG.ENEMIES.find(str(entries[index]["enemy"])), 0))
		kind.item_selected.connect(_entry_kind.bind(index))
		row.add_child(kind)
		var count := _spin(1, SPAWN_CONFIG.COUNT_MAX, 1)
		count.set_value_no_signal(float(entries[index]["count"]))
		count.value_changed.connect(_entry_count.bind(index))
		row.add_child(count)
		var remove := _button(row, "×", _remove_entry.bind(index))
		remove.disabled = entries.size() <= 1
		entries_box.add_child(row)
	add_entry_button.disabled = entries.size() >= SPAWN_CONFIG.ENTRIES_MAX


func _queue() -> Dictionary:
	return _config["queues"][current]


func _entry_kind(selected: int, index: int) -> void:
	_queue()["enemies"][index]["enemy"] = SPAWN_CONFIG.ENEMIES[selected]
	_commit()


func _entry_count(value: float, index: int) -> void:
	_queue()["enemies"][index]["count"] = int(value)
	_commit()


func _add_entry() -> void:
	var entries: Array = _queue()["enemies"]
	var used: Array = entries.map(func(entry: Dictionary) -> String: return str(entry["enemy"]))
	var kind: String = SPAWN_CONFIG.ENEMIES.filter(func(id: String) -> bool: return not used.has(id)).front() if used.size() < SPAWN_CONFIG.ENEMIES.size() else "hunger"
	entries.append({"enemy": kind, "count": 5})
	_commit()


func _remove_entry(index: int) -> void:
	_queue()["enemies"].remove_at(index)
	_commit()


func _add_queue() -> void:
	var queue := SPAWN_CONFIG.default_queue()
	queue["start"] = "time"
	_config["queues"].append(queue)
	current = _config["queues"].size() - 1
	_commit()


func _remove_queue() -> void:
	_config["queues"].remove_at(current)
	current = maxi(current - 1, 0)
	_commit()


func _select_queue(index: int) -> void:
	if not _updating:
		load_config(_config, index)


func _read_settings(_value: Variant = null) -> void:
	if _updating:
		return
	var queue := _queue()
	queue["interval"] = interval_spin.value
	queue["rule"] = SPAWN_CONFIG.RULES[rule_option.selected]
	queue["batch"] = int(batch_spin.value)
	queue["start"] = SPAWN_CONFIG.STARTS[start_option.selected] if current > 0 else "trigger"
	queue["delay"] = delay_spin.value
	queue["trigger"] = SPAWN_CONFIG.TRIGGERS[trigger_option.selected]
	queue["health"] = health_spin.value
	queue["damage"] = damage_spin.value
	_commit()


func _commit() -> void:
	if _updating:
		return
	_config = SPAWN_CONFIG.sanitize(_config)
	changed.emit(config())
	load_config(_config)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _option_row(text: String, labels: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 170
	for entry in labels:
		option.add_item(entry)
	option.item_selected.connect(_read_settings)
	row.add_child(option)
	add_child(row)
	return option


func _spin_row(text: String, low: float, high: float, step: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := _spin(low, high, step)
	spin.value_changed.connect(_read_settings)
	row.add_child(spin)
	add_child(row)
	return spin


func _spin(low: float, high: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	return spin
