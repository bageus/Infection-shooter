extends SceneTree

# Renders the combat HUD over the real mission at 1280x720 for visual review:
# a fresh start, a later state with the emergency key, mutation and an
# empty magazine, then learned skills with a cooldown and a passive firing.
# Output: /tmp/hud_previews/*.png

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const OUT := "/tmp/hud_previews/"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var game := MAIN.instantiate()
	root.add_child(game)
	current_scene = game
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "hud_start.png")
	var player := game.get_node("Gameplay/Player")
	player.call("acquire_emergency_key")
	player.call("absorb_mutagen", 4.0)
	player.set("health", player.get("max_health") * 0.42)
	var weapon: Node = player.call("get_current_weapon")
	weapon.set("_magazine_ammo", 0)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "hud_key.png")
	await _capture_skills(game, player)
	game.free()
	await process_frame
	quit()


func _capture_skills(game: Node, player: Node) -> void:
	var runtime: Node = player.get_node("InfectionRuntime")
	# Review fixture only: jump to a late-game mutation state.
	var domain: Object = runtime.get("_domain")
	domain.set("mutation", 70.0)
	domain.set("critical_threshold", 95.0)
	for skill_id in ["acid_spit", "blood_burst", "discharge", "predator_dash", "spore_cocoon", "muscle_memory", "combat_reflex", "hypertrophy", "regeneration"]:
		runtime.call("upgrade_skill", skill_id)
	var ui: Node = game.get("mutation_tree_ui")
	ui.call("close_tree")
	ui.call("_refresh")
	runtime.call("cast_skill", "blood_burst")
	runtime.call("_physics_process", 4.0)
	for i in 20:
		await process_frame
	# Software rendering is slow; fire the passives right before the shot.
	runtime.call("report_passive", "hypertrophy", 0.0)
	runtime.call("report_passive", "regeneration", 6.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "hud_skills.png")
