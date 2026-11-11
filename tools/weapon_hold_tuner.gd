extends Node3D
## Live tuner for how the player holds long guns (scale, hand point, forend reach).
## Open tools/weapon_hold_tuner.tscn in the Godot editor and press F6. Move the sliders,
## then copy the line at the bottom into LONG_GUN / FOREND_REACH in
## game/features/player/player_equipment_pose.gd.
const PLAYER := preload("res://game/features/player/public/player.tscn")
const GUNS := {2: "SHOTGUN", 3: "GRENADE LAUNCHER", 4: "AK", 5: "M4", 6: "SNIPER RIFLE"}
const VIEWS := {"Right": Vector3(1, 0, 0), "Top": Vector3(0, 1, 0), "Bottom": Vector3(0, -1, 0), "Front": Vector3(0, 0, 1), "Back": Vector3(0, 0, -1), "3/4": Vector3(.7, .3, .7)}
var _actor: Node3D
var _camera: Camera3D
var _pose: SkeletonModifier3D
var _view := "Right"
var _name := "AK"
var _sliders := {}
var _readout: TextEdit
var _loading := false
var _base := {}   # weapon name -> {"Grip_R": Vector3, "Grip_L": Vector3} authored positions in the weapon's own units
var _shift := {}  # weapon name -> {"Grip_R": Vector3, "Grip_L": Vector3} slider offsets


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.82, .84, .86)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.75, .75, .78)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)
	_actor = PLAYER.instantiate()
	add_child(_actor)
	_actor.set_physics_process(false)
	_actor.call("configure_weapon_drop", func(_i: int, _p: Vector3) -> bool: return true)
	_pose = _actor.get_node("WeaponMount").equipment_pose
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.4
	add_child(_camera)
	_camera.current = true
	_build_ui()
	_pick(4)


func _process(_delta: float) -> void:
	# Aims like in play: the cursor point turns the body, then the mount aims the torso.
	var point := _actor.global_position + Vector3(1.5, 1.2, -4.0)
	var flat := point - _actor.global_position
	flat.y = 0.0
	_actor.set("_aim_point", point)
	_actor.get_node("AimPivot").look_at(_actor.get_node("AimPivot").global_position + flat.normalized(), Vector3.UP)
	_actor.get_node("Body").global_rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
	_actor.get_node("WeaponMount").call("aim_at", point)
	_apply_markers()
	var center := _actor.global_position + Vector3(0, .8, 0)
	_camera.look_at_from_position(center + VIEWS[_view] * 4.0, center, Vector3(0, 0, -1) if _view in ["Top", "Bottom"] else Vector3.UP)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 600)
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 340
	scroll.add_child(box)
	var guns := OptionButton.new()
	for index in GUNS:
		guns.add_item(GUNS[index], index)
	guns.select(2)
	guns.item_selected.connect(func(i: int) -> void: _pick(guns.get_item_id(i)))
	box.add_child(guns)
	var views := HBoxContainer.new()
	for view in VIEWS:
		var button := Button.new()
		button.text = view
		button.pressed.connect(func() -> void: _view = view)
		views.add_child(button)
	box.add_child(views)
	_add_slider(box, "Размер оружия", "scale", .3, 1.6, .01)
	_add_slider(box, "Рука: вбок (минус = правее)", "x", -.7, .3, .005)
	_add_slider(box, "Рука: высота", "y", -.1, 1.0, .005)
	_add_slider(box, "Рука: вперёд от груди", "z", -.3, 1.0, .005)
	_add_slider(box, "Правая рука дальше по стволу", "reach", -.5, 1.0, .005)
	_add_slider(box, "Точка рукояти Grip_R: вперёд по стволу", "r_x", -.4, .4, .005)
	_add_slider(box, "Точка рукояти Grip_R: вниз", "r_y", -.4, .4, .005)
	_add_slider(box, "Точка рукояти Grip_R: вбок", "r_z", -.2, .2, .005)
	_add_slider(box, "Точка цевья Grip_L: вперёд по стволу", "l_x", -.4, .4, .005)
	_add_slider(box, "Точка цевья Grip_L: вниз", "l_y", -.4, .4, .005)
	_add_slider(box, "Точка цевья Grip_L: вбок", "l_z", -.2, .2, .005)
	_readout = TextEdit.new()
	_readout.custom_minimum_size.y = 150
	_readout.editable = false
	_readout.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_readout)
	var copy := Button.new()
	copy.text = "Скопировать строки"
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(_readout.text))
	box.add_child(copy)


func _add_slider(box: Control, title: String, key: String, low: float, high: float, step: float) -> void:
	var label := Label.new()
	label.text = title
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value_changed.connect(func(_v: float) -> void: _apply())
	box.add_child(slider)
	_sliders[key] = slider


func _pick(index: int) -> void:
	_actor.call("pickup_weapon", index)
	_name = GUNS[index]
	var spec: Array = _pose.call("_spec", _name)
	_loading = true
	_sliders["scale"].value = spec[0]
	_sliders["x"].value = spec[1].x
	_sliders["y"].value = spec[1].y
	_sliders["z"].value = spec[1].z
	_sliders["reach"].value = spec[2]
	var shift: Dictionary = _shift.get(_name, {"Grip_R": Vector3.ZERO, "Grip_L": Vector3.ZERO})
	for key in ["r", "l"]:
		var v: Vector3 = shift["Grip_R" if key == "r" else "Grip_L"]
		_sliders[key + "_x"].value = v.x
		_sliders[key + "_y"].value = v.y
		_sliders[key + "_z"].value = v.z
	_loading = false
	_apply()


func _apply() -> void:
	if _loading:
		return
	var point := Vector3(_sliders["x"].value, _sliders["y"].value, _sliders["z"].value)
	_pose.tuning[_name] = [_sliders["scale"].value, point, _sliders["reach"].value]
	_shift[_name] = {"Grip_R": Vector3(_sliders["r_x"].value, _sliders["r_y"].value, _sliders["r_z"].value), "Grip_L": Vector3(_sliders["l_x"].value, _sliders["l_y"].value, _sliders["l_z"].value)}
	var moved: Dictionary = _shift[_name]
	_readout.text = 'В таблицу LONG_GUN:\n"%s": [%.2f, Vector3(%.3f, %.3f, %.3f)],\n\nВ FOREND_REACH:\n"%s": %.3f' % [_name, _sliders["scale"].value, point.x, point.y, point.z, _name, _sliders["reach"].value]
	_readout.text += "\n\nТочки (сдвиг от нынешних, в единицах оружия), пришли это мне:\n%s: Grip_R %s, Grip_L %s" % [_name, moved["Grip_R"], moved["Grip_L"]]


## Moves the live grip markers by the slider offsets and draws them: red Grip_R (rear hand), blue Grip_L (forend).
func _apply_markers() -> void:
	var weapon := _actor.get_node("WeaponMount").get("_active") as Node3D
	if weapon == null or not _shift.has(_name):
		return
	for marker_name in ["Grip_R", "Grip_L"]:
		var marker := weapon.find_child(marker_name, true, false) as Node3D
		if marker == null:
			continue
		var base: Dictionary = _base.get(_name, {})
		if not base.has(marker_name):
			base[marker_name] = weapon.to_local(marker.global_position)
			_base[_name] = base
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = .02
			sphere.height = .04
			var material := StandardMaterial3D.new()
			material.albedo_color = Color.RED if marker_name == "Grip_R" else Color.BLUE
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.no_depth_test = true
			sphere.material = material
			ball.mesh = sphere
			ball.scale = Vector3.ONE / weapon.scale.x
			marker.add_child(ball)
		var offset: Vector3 = _shift[_name][marker_name]
		marker.global_position = weapon.to_global(base[marker_name] + Vector3(offset.x, offset.y, offset.z))
