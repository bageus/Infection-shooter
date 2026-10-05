extends RigidBody3D
const IMPACT_SOUND := preload("res://game/presentation/office_floor/impact_sound_watcher.gd")

const BALANCE = preload("res://game/features/combat/public/projectile_balance.gd")
var repeated_electronic_particles := true


func configure_damage_particles(enabled: bool) -> void:
	repeated_electronic_particles = enabled


const SPARKS = preload("res://game/presentation/office_floor/electric_sparks.gd")
const BLAST = preload("res://game/presentation/office_floor/blast_effect.gd")
const DAMAGE = preload("res://game/presentation/office_floor/environment_damage.gd")
const DEBRIS = preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const MAX_MODEL_PIECES := 12
const MAX_PIECE_SIZE := 1.0
const CRUMBLE_CHUNKS := 9

@export var max_health := 110.0
@export var bullet_impulse := 1.8
@export var character_push_impulse := 2.8
@export var breakable := true
@export var max_linear_speed := 7.0
@export var max_angular_speed := 8.0

var _health := 110.0
var _extinguisher_triggered := false

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts


func _damage_category() -> String:
	var label := (name + " " + get_parent().name).to_lower()
	for token in ["computer", "desktop", "phone", "monitor", "printer", "lamp", "keyboard"]:
		if token in label:
			return "tech"
	return "large"


func get_projectile_material(_shape_index: int = -1) -> String:
	return "tech" if _damage_category() == "tech" else "wood"

func _ready() -> void:
	_health = max_health
	add_to_group("physical_props")
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	collision_layer = 1
	collision_mask = 3
	can_sleep = true
	IMPACT_SOUND.watch(self)

func push_from_character(character_position: Vector3, movement: Vector3) -> void:
	if movement.length_squared() < 0.01:
		return
	var direction := movement.normalized()
	var offset := global_position - character_position
	offset.y = 0.0
	if offset.length_squared() > 0.001:
		direction = (direction * 0.7 + offset.normalized() * 0.3).normalized()
	sleeping = false
	apply_central_impulse(direction * character_push_impulse)

func take_projectile_hit(damage: float, hit_position: Vector3, _hit_normal: Vector3, direction: Vector3, weapon_name: String) -> bool:
	if "extinguisher" in (name + get_parent().name).to_lower():
		if not _extinguisher_triggered:
			_extinguisher_triggered = true
			BLAST.smoke(self, hit_position)
			apply_torque_impulse(Vector3(1, 4, 1))
			apply_central_impulse((direction.normalized() + Vector3.UP) * 1.5)
			get_tree().create_timer(0.55).timeout.connect(_rupture_extinguisher.bind(hit_position))
		return true
	if _damage_category() == "tech" and (_health >= max_health or repeated_electronic_particles):
		SPARKS.spawn(self, hit_position)
	var multiplier := 1.1 if weapon_name == "SHOTGUN" else (0.7 if weapon_name == "UZI" else 1.0)
	# Shotgun pellets each deliver a separate hit; share a modest kick across
	# the spread instead of applying a full pistol-sized impulse eight times.
	var impulse := minf(bullet_impulse * 0.22, mass * 0.12) if weapon_name == "SHOTGUN" else bullet_impulse * multiplier
	sleeping = false
	if mass >= 5.0:
		apply_central_impulse((direction.normalized() + Vector3.UP * 0.1).normalized() * minf(impulse, mass * 0.12))
	else:
		apply_impulse((direction.normalized() + Vector3.UP * (0.3 if weapon_name == "SHOTGUN" else 0.0)).normalized() * impulse, hit_position - global_position)
	_health -= BALANCE.object_damage(maxf(damage, 0.0), weapon_name, _damage_category()) * multiplier
	if breakable and _health <= 0.0:
		_break_physical_prop(hit_position, direction)
	return true

func _rupture_extinguisher(hit_position: Vector3) -> void:
	if is_queued_for_deletion():
		return
	BLAST.detonate(self, hit_position)
	queue_free()


func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	sleeping = false
	apply_impulse(direction.normalized() * character_push_impulse, hit_position - global_position)
	_health -= maxf(damage, 0.0)
	if breakable and _health <= 0.0:
		_break_physical_prop(hit_position, direction)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if state.linear_velocity.length() > max_linear_speed:
		state.linear_velocity = state.linear_velocity.normalized() * max_linear_speed
	if state.angular_velocity.length() > max_angular_speed:
		state.angular_velocity = state.angular_velocity.normalized() * max_angular_speed


func _break_physical_prop(hit_position: Vector3, direction: Vector3) -> void:
	if not is_instance_valid(effects_root):
		queue_free()
		return
	if is_queued_for_deletion():
		return
	if _damage_category() == "tech":
		SPARKS.spawn(self, hit_position, true)
	var root := get_parent()
	var visual := get_node_or_null("Visual")
	if visual == null and root != null:
		visual = root.get_node_or_null("Visual")
	var bounds := AABB()
	var tint := Color(0.42, 0.34, 0.26)
	var spawned := 0
	if visual != null:
		var found := false
		for node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			var mesh_bounds: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = mesh_bounds if not found else bounds.merge(mesh_bounds)
			if not found:
				var material := mesh.get_active_material(0) as BaseMaterial3D
				if material != null:
					tint = material.albedo_color
			found = true
			# Whole-cabinet sized meshes would leave a ghost object lying around.
			if spawned < MAX_MODEL_PIECES and mesh_bounds.size.length() <= MAX_PIECE_SIZE:
				if DAMAGE.spawn_piece(self, mesh, null, 0, spawned, direction, hit_position) != null:
					spawned += 1
	if bounds.size.length_squared() < 0.0001:
		bounds = AABB(global_position - Vector3(0.25, 0.25, 0.25), Vector3(0.5, 0.5, 0.5))
	DEBRIS.spawn_chunks(self, bounds, tint, CRUMBLE_CHUNKS if spawned < 3 else 4, direction, hit_position)
	DEBRIS.dust_puff(self, bounds.get_center() - Vector3(0.0, bounds.size.y * 0.2, 0.0), bounds.size.length())
	queue_free()
