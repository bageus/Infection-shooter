extends StaticBody3D

@export var health_per_cubic_meter := 28.0
@export var minimum_health := 35.0
var _health := 35.0
var _broken := false

func _ready() -> void:
	call_deferred("_initialize_health")

func _initialize_health() -> void:
	var root := get_parent()
	var bounds := AABB()
	var found := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_transform := root.global_transform.affine_inverse() * mesh_instance.global_transform
		var aabb := local_transform * mesh_instance.get_aabb()
		bounds = aabb if not found else bounds.merge(aabb)
		found = true
	var volume := maxf(bounds.size.x * bounds.size.y * bounds.size.z, 0.25)
	_health = maxf(minimum_health, volume * health_per_cubic_meter)

func take_projectile_hit(damage: float, _hit_position: Vector3, _hit_normal: Vector3, _direction: Vector3, weapon_name: String) -> bool:
	if _broken:
		return false
	var multiplier := 1.35 if weapon_name == "SHOTGUN" else 1.0
	_health -= maxf(damage, 0.0) * multiplier
	if _health <= 0.0:
		_break()
	return true

func take_melee_hit(damage: float, _hit_position: Vector3, _direction: Vector3) -> void:
	if _broken:
		return
	_health -= maxf(damage, 0.0)
	if _health <= 0.0:
		_break()

func _break() -> void:
	if _broken:
		return
	_broken = true
	var root := get_parent()
	if root != null:
		root.queue_free()

func add_blood_decal(decal: Node) -> void:
	if decal != null:
		decal.reparent(get_parent(), true)
