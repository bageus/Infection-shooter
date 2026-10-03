extends RigidBody3D
## A shot-off head, limb or tentacle (ADR-0017). It tumbles to the floor,
## bleeds for a few seconds, can be shot again and shrinks away later.
## It emits the same blood facts as an infected, so the mission binds it to
## the blood renderer like any enemy added to the enemies container.

signal projectile_blood(position: Vector3, direction: Vector3, weapon: String, excluded: Array[RID], source_id: int)
signal blood_wounded(position: Vector3, excluded: Array[RID])
signal wounded_moved(previous: Vector3, current: Vector3, excluded: Array[RID])
signal body_dragged(previous: Vector3, current: Vector3, excluded: Array[RID])
signal blood_death(position: Vector3, excluded: Array[RID], death_id: int)
signal limb_severed(position: Vector3, direction: Vector3, excluded: Array[RID])

const FX := preload("res://game/features/infected/blood_drip_fx.gd")
const SFX := preload("res://game/core/audio/public/sound_events.gd")
const GROUP := "infected_severed_part"
const HIT_LAYER := 4
const WORLD_MASK := 3
const MAX_PARTS := 28
const BLEED_SECONDS := 4.0

var part_name: StringName = &""
var lifetime := 35.0
var bleeding := true
var blood_drop_distance := 0.45
var _age := 0.0
var _trail_from := Vector3.ZERO
var _trail_length := 0.0
var _stained := false
var _fading := false

static var _surface: PhysicsMaterial


func _ready() -> void:
	collision_layer = HIT_LAYER
	collision_mask = WORLD_MASK
	if _surface == null:
		_surface = PhysicsMaterial.new()
		_surface.friction = 0.9
		_surface.bounce = 0.08
	physics_material_override = _surface
	linear_damp = 0.4
	angular_damp = 1.6
	continuous_cd = true
	can_sleep = true
	for group in ["player", "infected"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject3D:
				add_collision_exception_with(node)
	_trail_from = global_position
	# Decorations never expire and stay outside the debris budget.
	if lifetime < INF:
		add_to_group(GROUP)
		_enforce_budget()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime and not _fading:
		expire()
		return
	if not bleeding or _age > BLEED_SECONDS + 2.0:
		if _stained:
			set_physics_process(_age < lifetime)
		return
	var travelled := global_position.distance_to(_trail_from)
	if _age < BLEED_SECONDS and travelled >= blood_drop_distance:
		wounded_moved.emit(_trail_from, global_position, _exclusions())
		_trail_from = global_position
	if not _stained and _age > 0.35 and linear_velocity.length() < 0.6:
		_stained = true
		blood_wounded.emit(global_position, _exclusions())
		SFX.play(get_parent(), &"body_part_fall", global_position)


func start_bleeding(cut_offset: Vector3, direction: Vector3, strength: float) -> void:
	FX.bleed(self, cut_offset, direction, BLEED_SECONDS * 0.6, strength)


func take_projectile_hit(_damage: float, hit_position: Vector3, _normal: Vector3, direction: Vector3, weapon: String) -> bool:
	if _fading:
		return false
	sleeping = false
	apply_impulse(direction.normalized() * clampf(mass * 1.2, 0.6, 6.0), hit_position - global_position)
	projectile_blood.emit(hit_position, direction, weapon, _exclusions(), get_instance_id())
	FX.spray(get_parent() as Node3D, hit_position, direction, 10, 0.8)
	return true


func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	take_projectile_hit(damage, hit_position, Vector3.ZERO, direction, "MELEE")


func get_projectile_material(_shape_index: int = -1) -> String:
	return "flesh"


func expire(seconds: float = 0.8) -> void:
	if _fading:
		return
	_fading = true
	collision_layer = 0
	var pivot := Node3D.new()
	add_child(pivot)
	for child in get_children():
		if child is VisualInstance3D:
			child.reparent(pivot, true)
	var tween := create_tween()
	tween.tween_property(pivot, "scale", Vector3.ONE * 0.01, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _exclusions() -> Array[RID]:
	var excluded: Array[RID] = [get_rid()]
	return excluded


func _enforce_budget() -> void:
	var live: Array[Node] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		if not node.is_queued_for_deletion() and not bool(node.get("_fading")):
			live.append(node)
	while live.size() > MAX_PARTS:
		(live.pop_front() as Node).call("expire", 0.3)
