extends SceneTree

const ICONS := preload("res://game/presentation/prototype_hud/weapon_icon_regions.gd")
const PALETTE := preload("res://game/presentation/prototype_hud/hud_palette.gd")
const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")

class TestMission:
	extends Node3D
	var dropped := -1
	func drop_weapon_pickup(index: int, _position: Vector3) -> bool:
		dropped = index
		return true
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
			_check_crop_pixels(icon, crop)
		_expect(ICONS.ARTWORK_BOUNDS[5].end.y < ICONS.ARTWORK_BOUNDS[0].position.y, "Launcher comes from the upper row, not the syringe cell.")
	_expect(ATLAS.get_image().get_data() == original, "Shared source texture is unchanged.")
	var stage := TestMission.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as Node3D
	player.name = "Player"
	stage.add_child(player)
	player.call("configure_weapon_drop", Callable(stage, "drop_weapon_pickup"))
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
	_test_cached_updates(hud, player)
	_test_key_buttons(hud, player)
	_test_key_cell(hud, player)
	stage.queue_free()
	await process_frame
	print("Weapon icon tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _test_key_buttons(hud: Node, player: Node) -> void:
	var second := hud.get_node("WeaponPanel/Slot2/KeyHint") as Button
	second.pressed.emit()
	_expect(int(player.call("get_current_weapon_index")) == 1, "Clicking the framed number switches its slot.")
	var selected := second.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(selected.bg_color.is_equal_approx(PALETTE.ACCENT), "Selected key badge is filled with the menu accent.")
	_expect(second.get_theme_color("font_color").is_equal_approx(PALETTE.INK), "Selected digit uses the menu ink colour.")
	for index in range(1, 4):
		var frame := hud.get_node("WeaponPanel/Slot%d" % index) as Panel
		var slot_key := frame.get_node("KeyHint") as Button
		var icon := frame.get_node("Icon") as TextureRect
		_expect(slot_key.position.x + slot_key.size.x <= icon.position.x, "Each key badge remains to the left of its artwork.")
		_expect(slot_key.text == str(index), "Slot keys never show a weapon-name abbreviation behind the icon.")
	_expect(not (hud.get_node("WeaponPanel/WeaponName") as Label).visible, "The weapon name cannot render behind the artwork.")
	player.call("absorb_mutagen", 2.0)
	var before: int = player.get("antidotes")
	var key := hud.get_node("AntidotePanel/KeyHint") as Button
	key.pressed.emit()
	_expect(int(player.get("antidotes")) == before - 1, "Clicking the F badge uses the linked antidote command.")
	var count := hud.get_node("AntidotePanel/AntidoteCount") as Label
	_expect(count.text == str(before - 1), "Antidote count is only a number in its own cell.")
	_expect(count.position.x > key.position.x + key.size.x and count.position.y < key.position.y, "Count is at the upper right and the F badge is at the left.")
	var isolated := Image.create(24, 12, false, Image.FORMAT_RGBA8)
	isolated.fill(Color.TRANSPARENT)
	isolated.fill_rect(Rect2i(2, 2, 10, 8), Color.WHITE)
	isolated.fill_rect(Rect2i(18, 4, 4, 4), Color.WHITE)
	ICONS._keep_largest_component(isolated)
	_expect(isolated.get_pixel(4, 4).a == 1.0 and isolated.get_pixel(19, 5).a == 0.0, "An overlapping neighbour is removed while the main artwork remains.")


func _test_key_cell(hud: Node, player: Node) -> void:
	var cell := hud.get_node("KeyPanel") as Panel
	hud.call("_update_vitals")
	_expect(not cell.visible, "Key cell stays hidden until the emergency key is picked up.")
	player.call("acquire_emergency_key")
	hud.call("_update_vitals")
	_expect(cell.visible, "Key cell appears once the emergency key is held.")
	var antidote := hud.get_node("AntidotePanel") as Panel
	_expect(cell.position.y == antidote.position.y and cell.size == antidote.size, "Key cell matches the antidote cell row and size.")
	_expect(cell.position.x >= antidote.position.x + antidote.size.x, "Key cell sits beside the antidote cell without overlap.")
	_expect(cell.get_theme_stylebox("panel") == antidote.get_theme_stylebox("panel"), "Key cell shares the HUD item frame.")


func _check_crop_pixels(icon: Image, crop: Image) -> void:
	var visible := 0
	var faithful := true
	for y in icon.get_height():
		for x in icon.get_width():
			var pixel := icon.get_pixel(x, y)
			if pixel.a > 0.12:
				visible += 1
				faithful = faithful and pixel.is_equal_approx(crop.get_pixel(x, y))
	_expect(visible > 1000 and visible < icon.get_width() * icon.get_height() * 0.85 and faithful, "Visible artwork retains the atlas pixels; only neighbouring artwork is discarded.")


func _test_cached_updates(hud: Node, player: Node) -> void:
	hud.call("_update_vitals")
	var vitals: Array = hud.get("_vital_snapshot")
	hud.call("_update_vitals")
	_expect(hud.get("_vital_snapshot") == vitals, "Idle vitals retain their last presented state")
	player.set("health", float(player.get("health")) - 5.0)
	hud.call("_update_vitals")
	_expect((hud.get("hp_bar") as ProgressBar).value == player.get("health"), "Health change is presented immediately")
	player.set("max_health", float(player.get("max_health")) + 20.0)
	hud.call("_update_vitals")
	_expect((hud.get("hp_bar") as ProgressBar).max_value == player.get("max_health"), "Changing maximum health updates the range")
	var weapon: Node = player.call("get_current_weapon")
	weapon.set("_magazine_ammo", 0)
	hud.call("_update_weapon")
	_expect((hud.get("magazine") as Label).text == "0", "Ammo depletion updates the cached HUD")
	_expect((hud.get("reload_label") as Label).text in ["RELOAD [R]", "NO AMMO", "RELOADING"], "Empty magazine preserves reload feedback")
	weapon.set("_magazine_ammo", 1)
	hud.call("_update_weapon")
	_expect((hud.get("magazine") as Label).text == "1", "Ammo recovery clears the empty presentation")
