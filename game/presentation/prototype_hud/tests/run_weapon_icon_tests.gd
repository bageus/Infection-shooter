extends SceneTree

const ICONS := preload("res://game/presentation/prototype_hud/weapon_icon_regions.gd")
const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")

class TestMission:
	extends Node3D
	var dropped := -1
	func drop_weapon_pickup(index: int, _position: Vector3) -> void:
		dropped = index
const ATLAS := preload("res://assets/icon_interface.png")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var image := ATLAS.get_image()
	if image.is_compressed():
		image.decompress()
	var original := image.get_data()
	var icons := ICONS.extract(ATLAS)
	_expect(icons.size() == 6, "Real atlas extracts six separate icons despite connected halos.")
	if icons.size() == 6:
		for index in range(6):
			var bounds: Rect2 = ICONS.ARTWORK_BOUNDS[index]
			_expect(icons[index].get_width() == int(bounds.size.x) and icons[index].get_height() == int(bounds.size.y), "Visible artwork bounds preserve native aspect.")
			var crop := image.get_region(Rect2i(bounds))
			var icon := icons[index].get_image()
			_expect(icon.get_pixel(20, 20).is_equal_approx(crop.get_pixel(20, 20)), "Each semantic icon uses its authored atlas region.")
		_expect(ICONS.ARTWORK_BOUNDS[5].end.y < ICONS.ARTWORK_BOUNDS[0].position.y, "Launcher comes from the upper row, not the syringe cell.")
	_expect(ATLAS.get_image().get_data() == original, "Shared source texture is unchanged.")
	var stage := TestMission.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as Node3D
	player.name = "Player"
	stage.add_child(player)
	var hud := HUD.instantiate()
	hud.set("player_path", NodePath("../Player"))
	stage.add_child(hud)
	_expect(hud.get("weapon_icon_cells") == PackedInt32Array([1, 2, 3, 5]), "Player weapon IDs select pistol, uzi, shotgun and launcher.")
	_expect(bool(player.call("pickup_weapon", 3)), "Launcher can replace the active slot.")
	hud.call("_update_weapon")
	var main_icon := hud.get_node("WeaponPanel/WeaponIcon") as TextureRect
	var slot_icon := hud.get_node("WeaponPanel/Slot1/Icon") as TextureRect
	_expect(main_icon.texture == slot_icon.texture, "Held launcher and its slot share the launcher icon.")
	_expect(main_icon.texture.get_size() == ICONS.ARTWORK_BOUNDS[5].size, "Picking up the launcher selects the actual upper-row image.")
	_expect(stage.dropped == 0, "Replacing the pistol drops the correct weapon ID.")
	_expect(bool(player.call("pickup_weapon", 0)), "Dropped pistol can replace the launcher again.")
	hud.call("_update_weapon")
	_expect(main_icon.texture.get_size() == ICONS.ARTWORK_BOUNDS[1].size, "Returning to pistol restores its own icon.")
	stage.queue_free()
	await process_frame
	print("Weapon icon tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
