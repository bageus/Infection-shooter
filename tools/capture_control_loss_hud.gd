extends SceneTree
## Captures the two-stage loss-of-control HUD: first loss label, antidote flash after
## recovery, and the green veil of the second loss. Run under xvfb with a real renderer.

const HUD := preload("res://game/presentation/prototype_hud/public/prototype_hud.tscn")
const PLAYER := preload("res://game/features/player/public/player.tscn")
const OUT_DIR := "res://docs/qa/control_loss"

var _shots := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var player := PLAYER.instantiate() as Node3D
	player.name = "Player"
	stage.add_child(player)
	player.set("antidotes", 2)
	var hud := HUD.instantiate()
	hud.set("player_path", NodePath("../Player"))
	stage.add_child(hud)
	var runtime := player.get_node("InfectionRuntime")
	await _frames(3)

	runtime.call("absorb_mutagen", 6.2)
	await _frames(40)
	await _shot("01_first_loss")

	await _wait_until_control_returns(runtime)
	await _wait_for_flash_on_phase(hud)
	await _shot("02_antidote_flash")

	await _frames(70)
	runtime.call("absorb_mutagen", 1.0)
	await _frames(90)
	await _shot("03_second_loss_veil")

	print("Control loss HUD captures written: %d" % _shots)
	quit(0)


func _wait_until_control_returns(runtime: Node) -> void:
	var guard := 0
	while bool(runtime.call("is_control_lost")) and guard < 600:
		await process_frame
		guard += 1


# The antidote blinks in the first half of its one-second flash; wait for a bright frame.
func _wait_for_flash_on_phase(hud: Node) -> void:
	var guard := 0
	while float(hud.get("_antidote_flash_remaining")) < 0.8 and guard < 600:
		await process_frame
		guard += 1


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	image.save_png(path)
	_shots += 1
	print("saved ", path)
