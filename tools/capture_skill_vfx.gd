extends SceneTree
## Renders the mutation skill effects from the game camera for visual review.
##
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --script res://tools/capture_skill_vfx.gd -- <out_dir>
##
## Writes one <out_dir>/<shot>.png per effect (player in the middle, a few
## infected around), plus close-ups of the body overlays.

const PLAYER := preload("res://game/features/player/public/player.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const SIZE := Vector2i(640, 480)
const GAME_EYE := Vector3(10, 12, 10) * 0.45

var _out_dir := "/tmp/skill_vfx"
var _stage: Node3D
var _player: CharacterBody3D
var _vfx: Node
var _enemies: Array[Node3D] = []
var _view: SubViewport
var _camera: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out_dir = args[0]
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_build_stage()
	await _wait(0.6)
	_vfx = _player.get("mutation_effects").get("vfx")
	_vfx.call("configure_world", _stage)
	var center := _player.global_position

	_vfx.call("buff_started", "storm_pulse")
	await _shot("storm_pulse_field", 0.5)
	_vfx.call("buff_ended", "storm_pulse")
	_vfx.call("buff_started", "bone_blades")
	await _shot("bone_blades_orbit", 0.5)
	_vfx.call("buff_ended", "bone_blades")
	await _wait(0.5)

	_vfx.call("spike_burst", center, 4.0)
	await _shot("blood_burst_spikes", 0.22)
	await _wait(0.4)
	_vfx.call("electric_pulse", center, 3.0)
	await _shot("retaliation_pulse", 0.2)
	await _wait(0.4)
	var chain: Array[Vector3] = [center]
	for enemy in _enemies:
		chain.append(enemy.global_position)
	_vfx.call("chain_lightning", chain)
	await _shot("discharge_chain", 0.2)
	await _wait(0.4)
	_vfx.call("acid_pool", center + Vector3(2.5, 0, -1.0), 2.2, 3.0)
	await _shot("acid_spit_pool", 0.3)
	_vfx.call("spore_cocoon", center + Vector3(-2.5, 0, 1.0), 3.0, 2.0)
	await _shot("spore_cocoon_swell", 1.2)
	await _shot("spore_cocoon_burst", 1.0)
	await _wait(1.5)
	_vfx.call("claw_slash", _enemies[0])
	await _shot("claws_slash", 0.12)
	_vfx.call("energy_shield")
	await _shot("armor_shield", 0.15)
	await _wait(0.4)
	_vfx.call("heartbeat", 1.0)
	await _shot("second_heart", 0.3)
	await _wait(1.0)
	for enemy in _enemies:
		enemy.call("apply_blast_stun", 3.0, 1.0)
		enemy.call("apply_mutation_poison", 3.0, 0.0)
	await _shot("enemies_stunned_poisoned", 0.4)
	await _wait(3.2)

	_vfx.call("buff_started", "berserk")
	await _shot("berserk_aura", 0.8)
	await _close_up("berserk_eyes_close", 1.2, 2.2)
	await _face("berserk_mask_front")
	_vfx.call("buff_ended", "berserk")
	_vfx.call("set_passives", true, false)
	await _close_up("bone_armor_close", 1.1, 2.6)
	_vfx.call("set_passives", false, true)
	await _close_up("hardened_tissue_close", 1.1, 2.6)
	_vfx.call("set_passives", false, false)
	await _wait(0.6)

	_camera.look_at_from_position(center + Vector3(4, 5, 1), center + Vector3(0, 0.8, -2.6), Vector3.UP)
	_player.get_node("AimPivot").global_rotation = Vector3.ZERO
	_vfx.call("dash_trail", 0.4)
	var dash := _player.create_tween()
	dash.tween_property(_player, "global_position", center + Vector3(0, 0, -5.2), 0.4)
	await _shot("predator_dash_trail", 0.3)
	quit(0)


func _build_stage() -> void:
	_stage = Node3D.new()
	root.add_child(_stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.32, 0.33, 0.35)
	plane.material = floor_material
	floor_mesh.mesh = plane
	floor_body.add_child(floor_mesh)
	_stage.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.1
	_stage.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.08, 0.08, 0.09)
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment.environment.ambient_light_energy = 0.7
	_stage.add_child(environment)
	_player = PLAYER.instantiate() as CharacterBody3D
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_stage.add_child(_player)
	_player.set_physics_process(false)
	for offset in [Vector3(1.6, 0, 1.2), Vector3(3.4, 0, -0.6), Vector3(1.0, 0, -3.0)]:
		var enemy := HUNGER.instantiate() as Node3D
		_stage.add_child(enemy)
		enemy.global_position = offset
		enemy.look_at(Vector3.ZERO, Vector3.UP, true)
		_enemies.append(enemy)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_stage.add_child(_camera)
	_camera.look_at_from_position(GAME_EYE, Vector3(0, 0.6, 0), Vector3.UP)
	_camera.make_current()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(label: String, delay: float) -> void:
	await _wait(delay)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out_dir.path_join(label + ".png"))


func _close_up(label: String, height: float, distance: float) -> void:
	var target := _player.global_position + Vector3.UP * height
	var eye := target + Vector3(0.35, 0.45, -1.0).normalized() * distance
	var saved := _camera.global_transform
	_camera.look_at_from_position(eye, target, Vector3.UP)
	await _shot(label, 0.6)
	_camera.global_transform = saved


# Level with the face: the mask lenses are only visible from the front.
func _face(label: String) -> void:
	var skeleton := _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
	var saved := _camera.global_transform
	_camera.look_at_from_position(head + Vector3(0.15, 0.1, -0.9), head, Vector3.UP)
	await _shot(label, 0.3)
	_camera.global_transform = saved
