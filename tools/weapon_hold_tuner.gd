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
var _yaw := PI * .5
var _pitch := 0.0
var _distance := 4.5
var _focus := Vector3(0, .8, 0)
var _arm_offsets: SkeletonModifier3D
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
	_camera.fov = 30.0
	add_child(_camera)
	_camera.current = true
	_arm_offsets = _actor.get_node("WeaponMount").arm_offsets
	_pose.manual_arms = true
	_pose.hand_offset = {"Right": Vector3.ZERO, "Left": Vector3.ZERO}
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
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.look_at_from_position(_actor.global_position + _focus + offset * _distance, _actor.global_position + _focus, Vector3.UP)


## Orbit like Blender or the Godot editor: right or middle mouse turns, Shift + middle (or right) pans, wheel zooms.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		if Input.is_key_pressed(KEY_SHIFT):
			var right := _camera.global_basis.x
			var up := _camera.global_basis.y
			_focus += (-right * event.relative.x + up * event.relative.y) * _distance * .0015
		else:
			_yaw -= event.relative.x * .008
			_pitch = clampf(_pitch + event.relative.y * .008, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(.8, _distance * .9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(12.0, _distance * 1.1)


func _set_view(view: String) -> void:
	var direction: Vector3 = VIEWS[view].normalized()
	_yaw = atan2(direction.x, direction.z)
	_pitch = clampf(asin(direction.y), -1.5, 1.5)


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
		button.pressed.connect(func() -> void: _set_view(view))
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
	_add_arm_sliders(box)
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
	var tuning: Dictionary = _pose.ARM_TUNING.get(_name, {})
	for side in ["Right", "Left"]:
		for joint in ARM_BONES:
			var turn: Vector3 = tuning.get("bones", {}).get(side + ARM_BONES[joint], Vector3.ZERO)
			_sliders["%s_%s_x" % [side, joint]].value = turn.x
			_sliders["%s_%s_y" % [side, joint]].value = turn.y
			_sliders["%s_%s_z" % [side, joint]].value = turn.z
		var move: Vector3 = tuning.get("hands", {}).get(side, Vector3.ZERO)
		_sliders["%s_move_x" % side].value = move.x
		_sliders["%s_move_y" % side].value = move.y
		_sliders["%s_move_z" % side].value = move.z
	_loading = false
	_apply()


func _apply() -> void:
	if _loading:
		return
	var point := Vector3(_sliders["x"].value, _sliders["y"].value, _sliders["z"].value)
	_pose.tuning[_name] = [_sliders["scale"].value, point, _sliders["reach"].value]
	_shift[_name] = {"Grip_R": Vector3(_sliders["r_x"].value, _sliders["r_y"].value, _sliders["r_z"].value), "Grip_L": Vector3(_sliders["l_x"].value, _sliders["l_y"].value, _sliders["l_z"].value)}
	for side in ["Right", "Left"]:
		for joint in ARM_BONES:
			_arm_offsets.offsets[side + ARM_BONES[joint]] = Vector3(_sliders["%s_%s_x" % [side, joint]].value, _sliders["%s_%s_y" % [side, joint]].value, _sliders["%s_%s_z" % [side, joint]].value)
		_pose.hand_offset[side] = Vector3(_sliders["%s_move_x" % side].value, _sliders["%s_move_y" % side].value, _sliders["%s_move_z" % side].value)
	var moved: Dictionary = _shift[_name]
	_readout.text = 'В таблицу LONG_GUN:\n"%s": [%.2f, Vector3(%.3f, %.3f, %.3f)],\n\nВ FOREND_REACH:\n"%s": %.3f' % [_name, _sliders["scale"].value, point.x, point.y, point.z, _name, _sliders["reach"].value]
	_readout.text += "\n\nРуки (пришли и это):\n" + _arm_text()
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


const ARM_BONES := {"Shoulder": "Arm", "Elbow": "ForeArm", "Wrist": "Hand"}


func _add_arm_sliders(box: Control) -> void:
	for side in ["Right", "Left"]:
		var side_title := "правая" if side == "Right" else "левая"
		for joint in ARM_BONES:
			for axis in ["x", "y", "z"]:
				_add_slider(box, "%s рука, %s: поворот %s (градусы)" % [side_title.capitalize(), joint, axis.to_upper()], "%s_%s_%s" % [side, joint, axis], -90.0, 90.0, 1.0)
		for axis in ["x", "y", "z"]:
			_add_slider(box, "%s кисть: сдвиг %s (метры)" % [side_title.capitalize(), axis.to_upper()], "%s_move_%s" % [side, axis], -.3, .3, .005)
	for key in _sliders:
		if key.begins_with("Right_") or key.begins_with("Left_"):
			_sliders[key].set_value_no_signal(0.0)
	var reset := Button.new()
	reset.text = "Сбросить руки"
	reset.pressed.connect(func() -> void:
		for key in _sliders:
			if key.begins_with("Right_") or key.begins_with("Left_"):
				_sliders[key].value = 0.0)
	box.add_child(reset)


func _arm_text() -> String:
	var lines := PackedStringArray()
	for side in ["Right", "Left"]:
		for joint in ARM_BONES:
			var turn: Vector3 = _arm_offsets.offsets.get(side + ARM_BONES[joint], Vector3.ZERO)
			if not turn.is_zero_approx():
				lines.append("%s %s: %s" % [side, joint, turn])
		var move: Vector3 = _pose.hand_offset.get(side, Vector3.ZERO)
		if not move.is_zero_approx():
			lines.append("%s кисть сдвиг: %s" % [side, move])
	return "\n".join(lines) if not lines.is_empty() else "(руки не трогал)"
