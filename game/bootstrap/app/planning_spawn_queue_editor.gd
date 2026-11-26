extends VBoxContainer
## Settings of one spawn point's queues inside the wave panel: pick a queue, edit
## the infected it spawns, how it spawns and what starts it. Edits are applied to a
## working copy of the point config and reported through `changed`.

signal changed(config: Dictionary)

const SPAWN_CONFIG := preload("res://game/features/spawning/public/spawn_config.gd")
const MAP_MODE := preload("res://game/bootstrap/app/planning_map_mode.gd")

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
var loot_option: OptionButton
var loot_chance_row: HBoxContainer
var loot_chance_spin: SpinBox
var web_box: VBoxContainer
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
	loot_option = _option_row("Лут врагов дыры", SPAWN_CONFIG.LOOT_LABELS)
	loot_chance_spin = _spin_row("Выпадение, %", 0.0, 100.0, 5.0)
	loot_chance_row = loot_chance_spin.get_parent()
	web_box = VBoxContainer.new()
	add_child(web_box)


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
	var loot: Dictionary = _config["loot"]
	loot_option.select(maxi(SPAWN_CONFIG.LOOT_MODES.find(str(loot["mode"])), 0))
	loot_chance_spin.set_value_no_signal(float(loot["chance"]))
	loot_chance_row.visible = str(loot["mode"]) == "manual"
	_load_web()
	_updating = false


## Web map: wave growth, new kinds and the Horde hole role (spawn_config "web").
func _load_web() -> void:
	for child in web_box.get_children():
		web_box.remove_child(child)
		child.queue_free()
	web_box.visible = MAP_MODE.is_web()
	if not web_box.visible:
		return
	if not _config.has("web"):
		_config["web"] = SPAWN_CONFIG.default_web()
	var web: Dictionary = _config["web"]
	var title := Label.new()
	title.text = "ВЕБ: волны"
	web_box.add_child(title)
	var role := OptionButton.new()
	for label in SPAWN_CONFIG.WEB_ROLE_LABELS:
		role.add_item(label)
	role.select(maxi(SPAWN_CONFIG.WEB_ROLES.find(str(web["role"])), 0))
	role.item_selected.connect(func(index: int) -> void: _web_set("role", SPAWN_CONFIG.WEB_ROLES[index]))
	web_box.add_child(role)
	if str(web["role"]) == "boss":
		_web_spin("Появится в волне №", "boss_wave", 1, SPAWN_CONFIG.WAVE_MAX, 1)
		return
	_web_spin("Прибавка врагов за волну", "add", 0, SPAWN_CONFIG.COUNT_MAX, 1)
	_web_spin("Мин. врагов в волне", "min", 1, SPAWN_CONFIG.COUNT_MAX, 1)
	_web_spin("Макс. врагов в волне", "max", 1, SPAWN_CONFIG.COUNT_MAX, 1)
	_web_spin("Рост живучести за волну, %", "health_step", 0.0, 50.0, 1.0)
	_web_spin("Рост урона за волну, %", "damage_step", 0.0, 50.0, 1.0)
	var unlocks: Array = web["unlocks"]
	for index in unlocks.size():
		_unlock_rows(index, unlocks[index])
	var add := _button(web_box, "+ Новый тип врага", func() -> void:
		web["unlocks"].append(SPAWN_CONFIG.default_unlock())
		_commit())
	add.disabled = unlocks.size() >= SPAWN_CONFIG.WEB_UNLOCKS_MAX


func _web_spin(text: String, key: String, low: float, high: float, step: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := _spin(low, high, step)
	spin.set_value_no_signal(float(_config["web"][key]))
	spin.value_changed.connect(func(value: float) -> void: _web_set(key, value))
	row.add_child(spin)
	web_box.add_child(row)


func _web_set(key: String, value: Variant) -> void:
	if not _updating:
		_config["web"][key] = value
		_commit()


## One new kind: which enemy, from which wave, % replaced at start, more per wave, the cap.
func _unlock_rows(index: int, unlock: Dictionary) -> void:
	var head := HBoxContainer.new()
	var kind := OptionButton.new()
	kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in SPAWN_CONFIG.ENEMY_LABELS:
		kind.add_item(label)
	kind.select(maxi(SPAWN_CONFIG.ENEMIES.find(str(unlock["enemy"])), 0))
	kind.item_selected.connect(func(selected: int) -> void: _unlock_set(index, "enemy", SPAWN_CONFIG.ENEMIES[selected]))
	head.add_child(kind)
	_button(head, "×", func() -> void:
		_config["web"]["unlocks"].remove_at(index)
		_commit())
	web_box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	for caption in ["С волны", "Замена %", "+за волну", "Макс."]:
		var label := Label.new()
		label.text = caption
		grid.add_child(label)
	for key: String in ["from_wave", "share", "step", "cap"]:
		var spin := _spin(1 if key == "from_wave" else 0, 100 if key == "share" else SPAWN_CONFIG.COUNT_MAX, 1)
		spin.set_value_no_signal(float(unlock[key]))
		spin.value_changed.connect(func(value: float) -> void: _unlock_set(index, key, value))
		grid.add_child(spin)
	web_box.add_child(grid)


func _unlock_set(index: int, key: String, value: Variant) -> void:
	if not _updating:
		_config["web"]["unlocks"][index][key] = value
		_commit()


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
		if str(entries[index]["enemy"]) in SPAWN_CONFIG.SKIN_ENEMIES:
			entries_box.add_child(_skin_box(index, entries[index]))
	add_entry_button.disabled = entries.size() >= SPAWN_CONFIG.ENTRIES_MAX


func _queue() -> Dictionary:
	return _config["queues"][current]


func _entry_kind(selected: int, index: int) -> void:
	_queue()["enemies"][index]["enemy"] = SPAWN_CONFIG.ENEMIES[selected]
	_commit()


## Costume shares of one entry: a percent per skin, the auto split until one of them is set.
func _skin_box(index: int, entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var shares: Dictionary = SPAWN_CONFIG.skin_shares(entry.get("skins", {}))
	var grid := GridContainer.new()
	grid.columns = SPAWN_CONFIG.SKINS.size()
	for skin_index in SPAWN_CONFIG.SKINS.size():
		var label := Label.new()
		label.text = SPAWN_CONFIG.SKIN_SHORT_LABELS[skin_index]
		label.tooltip_text = SPAWN_CONFIG.SKIN_LABELS[skin_index]
		grid.add_child(label)
	for skin_index in SPAWN_CONFIG.SKINS.size():
		var skin: String = SPAWN_CONFIG.SKINS[skin_index]
		var share := _spin(0, 100, 1)
		share.set_value_no_signal(float(shares[skin]))
		share.tooltip_text = SPAWN_CONFIG.SKIN_LABELS[skin_index]
		share.value_changed.connect(_entry_skin.bind(index, skin))
		grid.add_child(share)
	box.add_child(grid)
	_button(box, "Скины: авто", _entry_skin_auto.bind(index))
	return box


func _entry_skin(value: float, index: int, skin: String) -> void:
	var entry: Dictionary = _queue()["enemies"][index]
	entry["skins"] = SPAWN_CONFIG.with_skin_share(entry.get("skins", {}), skin, value)
	_commit()


func _entry_skin_auto(index: int) -> void:
	_queue()["enemies"][index].erase("skins")
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
	_config["loot"] = {"mode": SPAWN_CONFIG.LOOT_MODES[loot_option.selected], "chance": loot_chance_spin.value}
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
