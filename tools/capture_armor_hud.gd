extends SceneTree

# Renders the combat HUD with and without armor: godot --path . --script tools/capture_armor_hud.gd -- <out_dir>
const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const UI_TRANSLATIONS := preload("res://game/core/localization/public/ui_translations.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	UI_TRANSLATIONS.apply_language("ru")
	var out_dir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
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

	player.set("health", 72.0)
	player.set("armor", 0.0)
	hud.call("_update_vitals")
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("armor_hud_none.png"))

	player.set("armor", 45.0)
	hud.call("_update_vitals")
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("armor_hud_armored.png"))
	print("Armor HUD captures written to %s" % out_dir)
	quit(0)
