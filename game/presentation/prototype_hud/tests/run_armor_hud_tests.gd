extends SceneTree

const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const UI_TRANSLATIONS := preload("res://game/core/localization/public/ui_translations.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	UI_TRANSLATIONS.apply_language("ru")
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as Node3D
	player.name = "Player"
	stage.add_child(player)
	var hud := HUD.instantiate()
	hud.set("player_path", NodePath("../Player"))
	stage.add_child(hud)
	await process_frame

	var armor_bar := hud.get_node("HealthPanel/ArmorBar") as ProgressBar
	var armor_value := hud.get_node("HealthPanel/ArmorValue") as Label
	var health_bar := hud.get_node("HealthPanel/HealthBar") as ProgressBar

	player.set("armor", 0.0)
	hud.call("_update_vitals")
	_expect(not armor_bar.visible and not armor_value.visible, "Armor strip is hidden without armor.")
	_expect(armor_bar.position.y + armor_bar.size.y <= health_bar.position.y, "Armor strip sits directly above the health bar.")

	player.set("armor", 40.0)
	hud.call("_update_vitals")
	_expect(armor_bar.visible and armor_value.visible, "Armor strip appears while armor is held.")
	_expect(is_equal_approx(armor_bar.value, 40.0) and is_equal_approx(armor_bar.max_value, float(player.get("max_armor"))), "Armor strip shows armor against its maximum.")
	_expect(armor_value.text == "БРОНЯ 40", "Armor value is labelled in the current language.")
	_expect(is_equal_approx(health_bar.value, float(player.get("health"))), "Health bar is unaffected by armor.")

	player.set("armor", 0.0)
	hud.call("_update_vitals")
	_expect(not armor_bar.visible and not armor_value.visible, "Armor strip hides again once armor is gone.")

	stage.queue_free()
	await process_frame
	print("Armor HUD tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
