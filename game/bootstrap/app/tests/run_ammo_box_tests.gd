extends SceneTree
## Ammo boxes for AK/M4, sniper and minigun use the shared supply size and reach their weapons.

const PISTOL_BOX := preload("res://game/features/pickups/public/ammo_pistol_pickup.tscn")
const AUTOMATE_BOX := preload("res://game/features/pickups/public/ammo_automate_pickup.tscn")
const SNIPER_BOX := preload("res://game/features/pickups/public/ammo_sniper_pickup.tscn")
const MINIGUN_BOX := preload("res://game/features/pickups/public/ammo_minigun_pickup.tscn")
const WEAPON_SCENES := {
	"AK": preload("res://game/features/combat/public/ak_rifle.tscn"),
	"M4": preload("res://game/features/combat/public/m4_rifle.tscn"),
	"SNIPER RIFLE": preload("res://game/features/combat/public/sniper_rifle.tscn"),
	"MINIGUN": preload("res://game/features/combat/public/minigun.tscn"),
}
var failures := 0


## Stands in for the player: takes ammo for the named weapons only, up to a cap.
class Collector extends Node3D:
	var accepts: Array[String] = []
	var room := 1000
	var received: Array[String] = []

	func add_ammo_for_weapon(weapon_name: String, amount: int) -> int:
		if not accepts.has(weapon_name) or room <= 0:
			return 0
		var gained := mini(amount, room)
		room -= gained
		received.append("%s:%d" % [weapon_name, gained])
		return gained


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_visual_size_matches_supply_boxes()
	_test_weapon_names_match_weapon_scenes()
	_test_automate_box_feeds_ak_or_m4()
	_test_sniper_and_minigun_boxes_feed_their_weapon()
	_test_ak_and_m4_share_one_reserve()
	_test_full_weapon_refuses_box()
	print("Ammo box tests: %d failure(s)." % failures)
	quit(failures)


func _test_visual_size_matches_supply_boxes() -> void:
	var reference := _spawn(PISTOL_BOX)
	var reference_size := _visual_size(reference)
	var reference_volume := reference_size.x * reference_size.y * reference_size.z
	for scene: PackedScene in [AUTOMATE_BOX, SNIPER_BOX, MINIGUN_BOX]:
		var box := _spawn(scene)
		var size := _visual_size(box)
		print("Ammo box %s size %s (pistol box %s)" % [box.name, size, reference_size])
		_expect(absf(size.x * size.y * size.z / reference_volume - 1.0) < 0.005, "Ammo box %s has the regular box volume." % box.name)
		box.queue_free()
	reference.queue_free()


func _test_weapon_names_match_weapon_scenes() -> void:
	for weapon_name: String in WEAPON_SCENES:
		var weapon := (WEAPON_SCENES[weapon_name] as PackedScene).instantiate()
		_expect(str(weapon.get("weapon_name")) == weapon_name, "Weapon scene reports the name %s used by its ammo box." % weapon_name)
		weapon.free()


func _test_automate_box_feeds_ak_or_m4() -> void:
	var box := _spawn(AUTOMATE_BOX)
	var collector := Collector.new()
	collector.accepts = ["M4"]
	root.add_child(collector)
	box.emit_signal("body_entered", collector)
	_expect(collector.received == ["M4:30"], "Automate box gives 30 rounds to an M4.")
	_expect(not is_instance_valid(box) or box.is_queued_for_deletion(), "Automate box is collected by an M4.")
	collector.queue_free()


func _test_sniper_and_minigun_boxes_feed_their_weapon() -> void:
	var sniper := _spawn(SNIPER_BOX)
	var minigun := _spawn(MINIGUN_BOX)
	var collector := Collector.new()
	collector.accepts = ["SNIPER RIFLE", "MINIGUN"]
	root.add_child(collector)
	sniper.emit_signal("body_entered", collector)
	minigun.emit_signal("body_entered", collector)
	_expect(collector.received == ["SNIPER RIFLE:8", "MINIGUN:100"], "Sniper and minigun boxes reach their weapons.")
	collector.queue_free()


func _test_ak_and_m4_share_one_reserve() -> void:
	var ak := (WEAPON_SCENES["AK"] as PackedScene).instantiate() as Node3D
	var m4 := (WEAPON_SCENES["M4"] as PackedScene).instantiate() as Node3D
	root.add_child(ak)
	root.add_child(m4)
	m4.call("share_reserve_with", ak)
	var before := int(ak.call("get_reserve_ammo"))
	m4.call("add_reserve_ammo", 30)
	_expect(int(ak.call("get_reserve_ammo")) == before + 30, "An M4 pickup refills the AK reserve.")
	_expect(m4.call("get_reserve_ammo") == ak.call("get_reserve_ammo"), "AK and M4 report one reserve.")
	ak.queue_free()
	m4.queue_free()


func _test_full_weapon_refuses_box() -> void:
	var box := _spawn(MINIGUN_BOX)
	var collector := Collector.new()
	collector.accepts = ["MINIGUN"]
	collector.room = 0
	root.add_child(collector)
	box.emit_signal("body_entered", collector)
	_expect(collector.received.is_empty(), "A full minigun takes no ammo from the box.")
	_expect(is_instance_valid(box) and not box.is_queued_for_deletion(), "A refused box stays on the floor.")
	collector.queue_free()
	box.queue_free()


func _spawn(scene: PackedScene) -> Area3D:
	var box := scene.instantiate() as Area3D
	root.add_child(box)
	return box


func _visual_size(box: Node) -> Vector3:
	var visual := box.get_node("Visual") as Node3D
	var bounds := AABB()
	var found := false
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh as MeshInstance3D
		var local := visual.global_transform.affine_inverse() * (mesh_instance.global_transform * mesh_instance.get_aabb())
		bounds = bounds.merge(local) if found else local
		found = true
	return bounds.size * visual.scale


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
