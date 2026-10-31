extends Node3D
## Armor vest as a planner item: it hovers like a weapon pickup, glows with the same highlight,
## and the player collects it by walking through it, which refills the armor bar.

const BEACON := preload("res://game/features/pickups/public/pickup_beacon.gd")
const GLOW := Color(0.75, 0.85, 1.0)
const CLOTH := Color(0.2, 0.24, 0.18)
const PLATE := Color(0.42, 0.45, 0.48)
const HOVER := 0.3
const COLLECT_DISTANCE := 1.35

var _base_y := 0.0
var _elapsed := 0.0
var _runtime_active := false
var _art: Node3D


func _ready() -> void:
	add_to_group("armor_pickups")
	add_to_group("occlusion_items")
	_art = Node3D.new()
	add_child(_art)
	var cloth := _material(CLOTH, 0.0)
	var plate := _material(PLATE, 0.6)
	_add_box(cloth, Vector3(0.34, 0.4, 0.12), Vector3.ZERO)
	_add_box(plate, Vector3(0.26, 0.28, 0.02), Vector3(0.0, 0.02, 0.07))
	_add_box(plate, Vector3(0.26, 0.28, 0.02), Vector3(0.0, 0.02, -0.07))
	for side in [-1.0, 1.0]:
		_add_box(cloth, Vector3(0.08, 0.1, 0.12), Vector3(side * 0.16, 0.2, 0.0))
	add_child(BEACON.make(GLOW, 0.8, 0.0, 0.45))


# Spawners call this on every drop; the vest hovers from the spot it is given.
# shortcut: no floor raycast, a vest dropped over a ledge hangs at the kill height; upgrade to PickupItem-style settling if that shows up.
func settle_on_floor() -> void:
	pass


func _process(delta: float) -> void:
	if not _runtime_active:
		# The mission layout moves the pickup after _ready: hover above its final floor spot.
		_base_y = global_position.y + HOVER
		_runtime_active = true
	_elapsed += delta
	global_position.y = _base_y + sin(_elapsed * 1.6) * 0.07
	_art.rotation.y += delta * 0.55
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.global_position.distance_to(global_position) <= COLLECT_DISTANCE and player.has_method("pickup_armor"):
		player.call("pickup_armor")
		queue_free()


func _add_box(material: Material, size: Vector3, offset: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.add_child(instance)


func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.7 - metallic * 0.4
	return material
