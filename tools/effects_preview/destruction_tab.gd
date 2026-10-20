extends VBoxContainer
## "Разрушение объектов" tab of the effects preview: pick an object and drag the
## stage slider to see what it turns into. A stage is rebuilt from scratch by
## shooting a fresh game prop that many times, so the page shows the real
## variants, fragments and floor debris, not a mock-up. Each object has its own
## number of stages: dents, a power-off screen, large parts, small fragments.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const FLOOR := preload("res://game/presentation/office_floor/public/base_floor_renderer.gd")
const SPOT := Vector3(14.0, 0.0, 0.0)
const MODELS := {
	"Стул простой": "res://models/objects/enviroments/06/06_simple_chair.glb",
	"Офисное кресло": "res://models/objects/enviroments/06/06_office_chair.glb",
	"Конференц-кресло": "res://models/objects/enviroments/06/06_conference_chair.glb",
	"Рабочий стол": "res://models/objects/enviroments/08/08_office_desk_2.glb",
	"Стол с перегородкой": "res://models/objects/enviroments/08/08_divider_full_H_desk.glb",
	"Квадратный стол": "res://models/objects/enviroments/07/07_table_square.glb",
	"Круглый стол": "res://models/objects/enviroments/07/07_round_dining_table.glb",
	"Журнальный столик": "res://models/objects/enviroments/07/07_coffee_table.glb",
	"Деревянная перегородка": "res://models/objects/enviroments/01/01_wood_slat_partition_destructible.glb",
	"Шкаф для папок": "res://models/objects/enviroments/03/03_file_cabinet_largest.glb",
	"Книжный шкаф": "res://models/objects/enviroments/03/03_book_case.glb",
	"Металлический шкафчик": "res://models/objects/enviroments/03/03_locker_tall_dented.glb",
	"Серверная стойка": "res://models/objects/enviroments/03/03_server_rack.glb",
	"Монитор": "res://models/objects/enviroments/05/05_monitor_destructible.glb",
	"Ноутбук": "res://models/objects/enviroments/05/05_laptop_close_destructible.glb",
	"Системный блок": "res://models/objects/enviroments/05/05_PC_destructible.glb",
	"Принтер": "res://models/objects/enviroments/05/05_printer_destructible.glb",
	"Телевизор на стене": "res://models/objects/enviroments/05/05_wall_TV_frameless_destructible.glb",
	"Кулер для воды": "res://models/objects/enviroments/02/02_water_cooler_destructible.glb",
	"Кофемашина": "res://models/objects/enviroments/02/02_coffee_machine_destructible.glb",
	"Торговый автомат": "res://models/objects/enviroments/02/02_vending_automat_1_dented.glb",
	"Холодильник": "res://models/objects/enviroments/02/02_frige_dented.glb",
	"Картонные коробки": "res://models/objects/enviroments/04/04_cardboard_boxes.glb",
	"Деревянный ящик": "res://models/objects/enviroments/04/04_crate_large_broken.glb",
	"Диван": "res://models/objects/enviroments/10/10_couch_red_destructible.glb",
	"Растение": "res://models/objects/enviroments/11/11_plant_large.glb",
}

var _host: Node3D
var _focus: Callable
var _spot: Node3D
var _floor: Node3D
var _prop: Node3D
var _picker: OptionButton
var _slider: HSlider
var _label: Label
var _blast: CheckButton
var _build := 0


## `host` receives the 3D stage; `focus` is called with (point, distance) to aim the camera.
func setup(host: Node3D, focus: Callable) -> void:
	_host = host
	_focus = focus
	_picker = OptionButton.new()
	for title: String in MODELS:
		_picker.add_item(title)
	_picker.item_selected.connect(func(_index: int) -> void: _show(0))
	add_child(_picker)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 250
	add_child(_label)
	_slider = HSlider.new()
	_slider.step = 1.0
	_slider.custom_minimum_size.x = 250
	_slider.value_changed.connect(func(value: float) -> void: _show(int(value)))
	add_child(_slider)
	_blast = CheckButton.new()
	_blast.text = "Взрыв гранаты"
	_blast.toggled.connect(func(_on: bool) -> void: _show(int(_slider.value)))
	add_child(_blast)
	var clear := Button.new()
	clear.text = "Убрать следы"
	clear.pressed.connect(_clear_floor)
	add_child(clear)
	visibility_changed.connect(_on_visibility)


func _on_visibility() -> void:
	if visible:
		_show(int(_slider.value))
	else:
		_clean()


func _clear_floor() -> void:
	if is_instance_valid(_floor):
		_floor.call("clear_glass_debris")


func _clean() -> void:
	_build += 1
	if is_instance_valid(_spot):
		_spot.queue_free()
	_spot = null


## Rebuilds the stage: a fresh prop shot `stage` times, then waits for the pieces to settle.
func _show(stage: int) -> void:
	_clean()
	var build := _build
	_spot = Node3D.new()
	_spot.position = SPOT
	_host.add_child(_spot)
	_floor = FLOOR.new()
	_floor.set("floor_size", Vector2(12.0, 12.0))
	_spot.add_child(_floor)
	_prop = PROP.instantiate()
	_prop.set("model_path", MODELS[_picker.get_item_text(_picker.selected)])
	_spot.add_child(_prop)
	_prop.call("configure_world", _spot, Node.new())
	_prop.call("configure_glass_debris", _floor)
	await _host.get_tree().process_frame
	if build != _build:
		return
	_prop.set("freeze", true)
	var variants: Array = _prop.get("_variants")
	var groups: Array = _prop.get("_stages")
	var steps := _steps(variants, groups, bool(_prop.get("_damage").collapses))
	_slider.set_block_signals(true)
	_slider.max_value = steps.size()
	_slider.value = clampi(stage, 0, steps.size())
	_slider.set_block_signals(false)
	var shown := int(_slider.value)
	_label.text = "Стадия %d из %d\n%s" % [shown, steps.size(), "Целый" if shown == 0 else steps[shown - 1][0]]
	var bounds := _bounds(_prop)
	_focus.call(SPOT + Vector3(0.0, bounds.size.y * 0.4, 0.0), maxf(bounds.size.length(), 1.2) * 1.5)
	var hit_at := SPOT + Vector3(0.0, bounds.size.y * 0.5, 0.0)
	var direction := Vector3(0.3, 0.0, -1.0).normalized()
	for step in shown:
		match steps[step][1]:
			"shot":
				_prop.call("take_projectile_hit", 9999.0, hit_at, Vector3.UP, direction, "RIFLE")
			"blast":
				_prop.call("take_projectile_hit", 9999.0, hit_at, Vector3.UP, direction, "GRENADE")
			"pieces":
				for piece: Node in _spot.get_children():
					if piece is RigidBody3D and piece.get("piece_name") != null:
						_prop.call("hit_environment_fragment", piece, hit_at, direction)
		for _wait in 4:
			await _host.get_tree().process_frame
		if build != _build:
			return


## [title, how] for every stage after the intact one: a shot, a grenade, or breaking all loose pieces.
func _steps(variants: Array, groups: Array, collapses: bool) -> Array:
	var steps := []
	var broken := not groups.is_empty() or collapses
	if _blast.button_pressed and broken:
		steps.append(["Взрыв гранаты: " + (str(groups[0].name) if not groups.is_empty() else "по частям"), "blast"])
	else:
		for node: Node in variants:
			steps.append([str(node.name), "shot"])
		if broken:
			steps.append(["Разрушен: " + (str(groups[0].name) if not groups.is_empty() else "по частям"), "shot"])
	for index in range(1, groups.size()):
		steps.append(["Дробление: " + str(groups[index].name), "pieces"])
	return steps


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var item := mesh as MeshInstance3D
		if item.mesh == null or not item.is_visible_in_tree():
			continue
		var area := item.global_transform * item.get_aabb()
		box = area if first else box.merge(area)
		first = false
	return box
