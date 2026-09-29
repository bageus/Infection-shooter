extends StaticBody3D

const BALANCE = preload("res://game/features/combat/public/projectile_balance.gd")
const DAMAGE = preload("res://game/presentation/office_floor/environment_damage.gd")

@export var health_per_cubic_meter := 65.0
@export var minimum_health := 135.0
var _health := 135.0
var _broken := false

func _ready() -> void:
	call_deferred("_initialize_health")

func _initialize_health() -> void:
	var root: Node3D = get_parent() as Node3D
	var bounds := AABB()
	var found := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_transform: Transform3D = root.global_transform.affine_inverse() * mesh_instance.global_transform
		var aabb: AABB = local_transform * mesh_instance.get_aabb()
		bounds = aabb if not found else bounds.merge(aabb)
		found = true
	var volume := maxf(bounds.size.x * bounds.size.y * bounds.size.z, 0.25)
	_health = maxf(minimum_health, minf(volume * health_per_cubic_meter, 300.0))

func take_projectile_hit(damage: float, hit_position: Vector3, _hit_normal: Vector3, direction: Vector3, weapon_name: String) -> bool:
	if _broken:
		return false
	var multiplier := 1.35 if weapon_name == "SHOTGUN" else 1.0
	_health -= BALANCE.object_damage(maxf(damage, 0.0), weapon_name, _damage_category()) * multiplier
	if _health <= 0.0:
		_break(hit_position, direction, weapon_name == "GRENADE")
	return true


func _damage_category() -> String:
	var label := get_parent().name.to_lower()
	for token in ["computer", "desktop", "phone", "monitor", "printer", "lamp", "keyboard"]:
		if token in label:
			return "tech"
	return "large"


func get_projectile_material(_shape_index: int = -1) -> String:
	return "tech" if _damage_category() == "tech" else "wood"

func take_melee_hit(damage: float, hit_position: Vector3, direction: Vector3) -> void:
	if _broken:
		return
	if bool(get_parent().get_meta("planning_wall_mount", false)):
		return
	_health -= maxf(damage, 0.0)
	if _health <= 0.0:
		_break(hit_position, direction)

func _break(hit_position: Vector3, direction: Vector3, blast: bool = false) -> void:
	if _broken:
		return
	_broken = true
	var root := get_parent()
	if root != null:
		if bool(root.get_meta("planning_wall_mount", false)):
			var visual := root.get_node_or_null("Visual")
			if visual != null:
				var index := 0
				for child in visual.find_children("*", "MeshInstance3D", true, false):
					if index >= 16:
						break
					var mesh := child as MeshInstance3D
					if mesh != null and mesh.is_visible_in_tree() and mesh.mesh != null:
						DAMAGE.spawn_piece(self, mesh, null, 0, index, direction, hit_position, blast)
						index += 1
		root.queue_free()

func add_blood_decal(decal: Node) -> void:
	if decal != null:
		decal.reparent(get_parent(), true)
