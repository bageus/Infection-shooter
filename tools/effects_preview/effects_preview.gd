extends Node3D
## Effects preview: play every skill effect on a bare stage, with no mission,
## menus or tests. Open effects_preview.tscn in the editor and press F6, or run
##   godot --path . res://tools/effects_preview/effects_preview.tscn
## Buttons cast an effect; "Loop" repeats the last one; the slider slows time.
## The player is a stand-in capsule, so only the skill effects are real.

const VFX := preload("res://game/features/player/mutation_skill_vfx.gd")
const CAMERA_STATE := preload("res://game/features/player/shooting_camera_state.gd")
const HIT_STOP := preload("res://game/features/player/skill_fx/hit_stop.gd")
const QUALITY := preload("res://game/core/vfx/public/effects_quality.gd")
const EYE := Vector3(10, 12, 10) * 0.45
const TARGETS := [Vector3(1.6, 0, 1.2), Vector3(3.4, 0, -0.6), Vector3(1.0, 0, -3.0)]

class Stand extends Node3D:
	## What the skill effects ask of the player.
	var _roll_direction := Vector3.FORWARD
	var camera_state := CAMERA_STATE.new()
	func camera_kick(amount: float) -> void: camera_state.kick(amount)

var _player: Stand
var _vfx: Node
var _camera: Camera3D
var _enemies: Array[Node3D] = []
var _casts := {}
var _last := ""
var _loop: CheckButton
var _timer := 0.0


func _ready() -> void:
	_build_stage()
	_vfx = VFX.new()
	_player.add_child(_vfx)
	_vfx.setup(_player)
	_vfx.configure_world(self)
	_casts = {
		"Рывок": _dash, "Мощный удар": _strike, "Кровавый выброс": _blood,
		"Ретализация": _pulse, "Разряд": _discharge, "Кислотный плевок": _acid,
		"Споровый кокон": _cocoon, "Когти": _claws, "Щит": _shield, "Сердце": _heart,
	}
	_build_ui()


func _process(delta: float) -> void:
	var zoom := _player.camera_state.tick(delta)
	_camera.position = EYE.normalized() * EYE.length() * (1.0 + zoom) + Vector3(0, 0.6, 0)
	_camera.look_at(Vector3(0, 0.6, 0), Vector3.UP)
	if _loop.button_pressed and _last != "":
		_timer -= delta / maxf(Engine.time_scale, 0.01)
		if _timer <= 0.0:
			_cast(_last)


func _cast(name: String) -> void:
	_last = name
	_timer = 2.2
	_player.position = Vector3.ZERO
	(_casts[name] as Callable).call()


func _dash() -> void:
	_player.set("_roll_direction", Vector3.FORWARD)
	_vfx.dash_trail(0.4)
	create_tween().tween_property(_player, "position", Vector3(0, 0, -5.2), 0.4)


func _strike() -> void:
	_vfx.power_strike(Vector3.ZERO, Vector3.FORWARD)
	_vfx.heavy_hit()


func _blood() -> void: _vfx.spike_burst(Vector3.ZERO, 2.4)
func _pulse() -> void: _vfx.electric_pulse(Vector3.ZERO, 3.0)
func _acid() -> void: _vfx.acid_pool(Vector3(2, 0, 0), 1.7, 2.0)
func _cocoon() -> void: _vfx.spore_cocoon(Vector3(-2, 0, 0), 3.0, 1.0)
func _claws() -> void: _vfx.claw_slash(_enemies[0])
func _shield() -> void: _vfx.energy_shield()
func _heart() -> void: _vfx.heartbeat()


func _discharge() -> void:
	var points: Array[Vector3] = [Vector3.ZERO]
	for enemy in _enemies:
		points.append(enemy.global_position)
	_vfx.chain_lightning(points)


func _build_stage() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.33, 0.35)
	plane.material = material
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.08, 0.09)
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	_player = Stand.new()
	_player.name = "Player"
	_player.add_child(_capsule(Color(0.2, 0.35, 0.6)))
	add_child(_player)
	for point: Vector3 in TARGETS:
		var enemy := Node3D.new()
		enemy.add_child(_capsule(Color(0.8, 0.75, 0.7)))
		add_child(enemy)
		enemy.position = point
		_enemies.append(enemy)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	add_child(_camera)
	_camera.make_current()


func _capsule(color: Color) -> MeshInstance3D:
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.7
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	body.mesh = mesh
	body.position.y = 0.85
	return body


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var quality := OptionButton.new()
	for item in ["Качество: низкое", "Качество: среднее", "Качество: высокое"]:
		quality.add_item(item)
	quality.selected = QUALITY.level
	quality.item_selected.connect(func(index: int) -> void: QUALITY.set_level(index))
	panel.add_child(quality)
	for name: String in _casts:
		var button := Button.new()
		button.text = name
		button.pressed.connect(_cast.bind(name))
		panel.add_child(button)
	_loop = CheckButton.new()
	_loop.text = "Повтор"
	panel.add_child(_loop)
	var slow := HSlider.new()
	slow.min_value = 0.1
	slow.max_value = 1.0
	slow.step = 0.05
	slow.value = 1.0
	slow.custom_minimum_size.x = 160
	slow.value_changed.connect(func(value: float) -> void: Engine.time_scale = value)
	var label := Label.new()
	label.text = "Скорость времени"
	panel.add_child(label)
	panel.add_child(slow)
