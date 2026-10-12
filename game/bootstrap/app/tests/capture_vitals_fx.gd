extends SceneTree

# Renders the real mission at 1280x720 with the vitals screen effects:
# a healthy baseline, mutagen smoke near the threshold, low-health blood,
# and both together. Output: /tmp/vitals_previews/*.png

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const OUT := "/tmp/vitals_previews/"


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
	await _shot("baseline")
	var player := game.get_node("Gameplay/Player")
	var domain: Object = player.get_node("InfectionRuntime").get("_domain")
	# Review fixtures only: set the meters directly.
	domain.set("mutation", 28.0)
	await _settle()
	await _shot("mutagen_smoke")
	domain.set("mutation", 0.0)
	player.set("health", player.get("max_health") * 0.18)
	await _settle()
	await _shot("low_health_blood")
	domain.set("mutation", 28.0)
	await _settle()
	await _shot("both")
	game.free()
	await process_frame
	quit()


# Software rendering is slow: jump the fade forward instead of waiting for it.
func _settle() -> void:
	var fx: Node = root.find_child("VitalsScreenFx", true, false)
	var player := current_scene.get_node("Gameplay/Player")
	var infection: Node = player.get_node("InfectionRuntime")
	for i in 4:
		fx.call("update", 1.0, infection.call("get_mutation"), infection.call("get_critical_threshold"), false, player.get("health"), player.get("max_health"))
	for i in 3:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
