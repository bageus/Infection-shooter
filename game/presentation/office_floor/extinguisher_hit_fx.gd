extends Node3D

const BURST := preload("res://game/presentation/office_floor/extinguisher_burst.tscn")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const POWDER_SHADER := preload("res://game/core/vfx/public/smoke_puff.gdshader")

signal ruptured(location: Vector3)

@export_range(0.1, 12.0, 0.1) var spray_seconds := 3.2
@export_range(0.2, 15.0, 0.1) var rupture_delay := 3.6
@export_range(0.0, 5.0, 0.05) var bullet_impulse := 0.85
@export_range(0.0, 8.0, 0.1) var recoil_force := 2.4
@export_range(0.0, 12.0, 0.1) var spin_speed := 5.5
@export_range(0.5, 12.0, 0.1) var topple_speed := 4.5
@export_range(1.0, 60.0, 0.5) var spin_acceleration := 24.0
@export_range(1, 300, 1) var jet_count := 80
@export_range(1, 300, 1) var mist_count := 45
@export_range(0.1, 4.0, 0.1) var jet_lifetime := 0.34
@export_range(0.1, 5.0, 0.1) var mist_lifetime := 1.1
@export_range(0.5, 8.0, 0.1) var cloud_radius := 3.0
@export_range(1.0, 8.0, 0.1) var cloud_lifetime := 3.6
@export_range(1, 250, 1) var burst_count := 110
## Length of the powder jet from the extinguisher sheet, metres.
@export_range(0.2, 4.0, 0.05) var jet_sheet_size := 1.5

@onready var _nozzle: Marker3D = $Nozzle
@onready var _jet: GPUParticles3D = $Nozzle/Jet
@onready var _mist: GPUParticles3D = $Nozzle/Mist

var _body: RigidBody3D
var _active := false
var _elapsed := 0.0
var _anchor := Vector3.ZERO
var _long_axis := Vector3.UP
var _fall_direction := Vector3.FORWARD
var _spray_sound: AudioStreamPlayer3D
var _landed := false
var _jet_sheet: Node3D

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts


func _ready() -> void:
	_configure_emitter(_jet, jet_count, jet_lifetime, 8.0, 11.0, 10.0, 0.12, 0.55)
	_configure_emitter(_mist, mist_count, mist_lifetime, 2.0, 4.0, 34.0, 0.32, 0.42)
	set_physics_process(false)


func configure(body: RigidBody3D, meshes: Array[MeshInstance3D]) -> void:
	_body = body
	var bounds := AABB()
	var found := false
	for mesh in meshes:
		if not is_instance_valid(mesh) or not mesh.is_visible_in_tree():
			continue
		var local: AABB = body.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(local) if found else local
		found = true
	if found:
		# Derive the cylinder axis from the imported model, including its root transform.
		_long_axis = Vector3.UP
		if bounds.size.x > bounds.size.y and bounds.size.x > bounds.size.z:
			_long_axis = Vector3.RIGHT
		elif bounds.size.z > bounds.size.y:
			_long_axis = Vector3.BACK
		_nozzle.position = bounds.get_center() + Vector3(0.0, bounds.size.y * 0.42, bounds.size.z * 0.38)


func start(hit_point: Vector3, bullet_direction: Vector3) -> void:
	if _active or _body == null:
		return
	_active = true
	_elapsed = 0.0
	_anchor = _body.global_position
	_body.freeze = false
	_body.sleeping = false
	var direction := bullet_direction.normalized() if bullet_direction.length_squared() > 0.0001 else _body.global_basis.z
	_fall_direction = _body.get_meta("planning_wall_normal", direction)
	_fall_direction.y = 0.0
	if _fall_direction.length_squared() < 0.0001:
		_fall_direction = _body.global_basis.z
		_fall_direction.y = 0.0
	if _fall_direction.length_squared() < 0.0001:
		_fall_direction = Vector3.FORWARD
	_fall_direction = _fall_direction.normalized()
	var axis := (_body.global_basis * _long_axis).normalized()
	if axis.y < 0.0:
		_long_axis = -_long_axis
		axis = -axis
	_body.apply_impulse(direction * bullet_impulse, (hit_point - _body.global_position).limit_length(0.35))
	_body.angular_velocity = axis.cross(_fall_direction) * topple_speed + axis * spin_speed * 0.35
	# With the sheet jet on the nozzle the particle jet would double it up;
	# a thinner mist still drifts off the stream.
	var sheet := ATLASES.available(ATLASES.EXTINGUISHER_SPRAY)
	_jet.emitting = not sheet
	_mist.emitting = true
	_mist.amount_ratio = 0.35 if sheet else 1.0
	_landed = false
	_spray_sound = SFX.play(_nozzle, &"extinguisher_spray")
	_start_jet_sheet()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= rupture_delay:
		_rupture()
		return
	var pressure := 1.0 - clampf(_elapsed / maxf(spray_seconds, 0.01), 0.0, 1.0) * 0.48
	_drive_motion(pressure, delta)
	_check_landing()
	if _elapsed >= spray_seconds:
		_jet.emitting = false
		_mist.emitting = false
		_stop_spray_sound()
		_stop_jet_sheet(0.35)
		return
	_jet.amount_ratio = pressure
	_mist.amount_ratio = pressure * (0.35 if is_instance_valid(_jet_sheet) else 1.0)
	_steer_jet_sheet(pressure)
	var recoil := _nozzle.global_basis.z.normalized() * recoil_force * pressure
	_body.apply_force(recoil, _nozzle.global_position - _body.global_position)


func _drive_motion(pressure: float, delta: float) -> void:
	var axis := (_body.global_basis * _long_axis).normalized()
	# Physics topples the cylinder, then rolls it about its own horizontal axis.
	var tipping := axis.cross(_fall_direction) * topple_speed
	var target_spin := axis * spin_speed * pressure + tipping
	_body.angular_velocity = _body.angular_velocity.move_toward(target_spin, spin_acceleration * delta)
	var displacement := _body.global_position - _anchor
	displacement.y = 0.0 # Never pull a falling cylinder back up to its wall mount.
	if displacement.length() > 0.45:
		_body.apply_central_force(-displacement.normalized() * 8.0 * (displacement.length() - 0.45))
	_body.linear_velocity = _body.linear_velocity.limit_length(2.2)


# The toppled cylinder hits the floor once: heavy hollow clang and a short roll.
func _check_landing() -> void:
	if _landed:
		return
	var axis := (_body.global_basis * _long_axis).normalized()
	if absf(axis.y) < 0.45:
		_landed = true
		SFX.play(effects_root if is_instance_valid(effects_root) else _body, &"canister_drop", _body.global_position)


func _stop_spray_sound() -> void:
	if is_instance_valid(_spray_sound):
		_spray_sound.queue_free()
	_spray_sound = null


# The sheet's powder jet grows out of the nozzle (frames 0-5), then keeps
# swirling (frames 3-5) while it sprays. It stays on the nozzle, follows the
# spinning cylinder and weakens with the pressure.
func _start_jet_sheet() -> void:
	var atlas: Dictionary = ATLASES.EXTINGUISHER_SPRAY
	var range_frames: Vector2i = atlas["spray_frames"]
	_jet_sheet = FLIPBOOK.spawn(_nozzle, atlas, _nozzle.global_position, jet_sheet_size, {
		"first_frame": range_frames.x, "last_frame": range_frames.y, "loop_from": int(atlas["spray_loop_from"]),
		"axis": -_nozzle.global_basis.z, "atlas_angle": float(atlas["jet_angle"]), "opacity": 0.92,
	})


func _steer_jet_sheet(pressure: float) -> void:
	if not is_instance_valid(_jet_sheet):
		return
	_jet_sheet.call("set_axis", -_nozzle.global_basis.z)
	_jet_sheet.call("set_opacity", 0.92 * pressure)
	_jet_sheet.scale = Vector3.ONE * jet_sheet_size * lerpf(0.65, 1.0, pressure)


func _stop_jet_sheet(fade: float) -> void:
	if is_instance_valid(_jet_sheet):
		_jet_sheet.call("stop", fade)
	_jet_sheet = null


func _rupture() -> void:
	set_physics_process(false)
	_jet.emitting = false
	_mist.emitting = false
	_stop_spray_sound()
	_stop_jet_sheet(0.08)
	var location := _body.global_position
	var world := effects_root
	if not is_instance_valid(world):
		return
	var burst := BURST.instantiate() as Node3D
	burst.call("configure_world", effects_root, impact_pool)
	world.add_child(burst)
	burst.global_position = location
	burst.call("start", cloud_radius, cloud_lifetime, burst_count)
	reparent(world, true)
	get_tree().create_timer(maxf(jet_lifetime, mist_lifetime) + 0.4).timeout.connect(queue_free)
	ruptured.emit(location)


func _configure_emitter(emitter: GPUParticles3D, amount: int, lifetime: float,
		min_velocity: float, max_velocity: float, spread: float, size: float, opacity: float) -> void:
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = false
	emitter.local_coords = false
	emitter.emitting = false
	emitter.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	emitter.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3.ONE * 12.0)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	motion.direction = Vector3(0, 0, -1)
	motion.spread = spread
	motion.initial_velocity_min = min_velocity
	motion.initial_velocity_max = max_velocity
	motion.gravity = Vector3(0, -0.2, 0)
	emitter.process_material = motion
	var particle := QuadMesh.new()
	particle.size = Vector2.ONE * size
	# Soft powder puffs (the sheet draws the jet itself).
	var material := ShaderMaterial.new()
	material.shader = POWDER_SHADER
	material.set_shader_parameter("smoke_color", Color(0.93, 0.94, 0.95))
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("growth", 2.6 if emitter == _mist else 1.6)
	particle.material = material
	emitter.draw_pass_1 = particle
