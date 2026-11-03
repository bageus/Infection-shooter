extends SceneTree
## Checkpoint maps in the level chain, saved progress, the main menu Continue button and the checkpoint caption.

const LEVEL_CHAIN := preload("res://game/bootstrap/app/level_chain.gd")
const CHECKPOINT := preload("res://game/bootstrap/app/checkpoint_progress.gd")
const CAPTION := preload("res://game/bootstrap/app/checkpoint_notice.gd")
const FRONT := preload("res://game/bootstrap/app/menu/front_end.tscn")
const CHAIN_PATH := "user://level_chain.json"
var failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + what)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_clear()
	var chain: RefCounted = LEVEL_CHAIN.new()
	for map_name in ["tutorial_lvl", "level_a", "level_b"]:
		chain.add_map(map_name)
	chain.set_checkpoint(0, true)
	_check(chain.is_checkpoint(0) and not chain.is_checkpoint(1), "Only the flagged map is a checkpoint")
	_check(chain.name_after("tutorial_lvl") == "level_a" and chain.name_after("level_b") == "", "name_after gives the next map or nothing")
	_check(chain.save(CHAIN_PATH) == OK, "chain saves")
	var reloaded: RefCounted = LEVEL_CHAIN.new()
	reloaded.load_file(CHAIN_PATH)
	_check(reloaded.is_checkpoint(0) and not reloaded.is_checkpoint(2), "The checkpoint flag survives a reload")
	_check(reloaded.name_after("missing") == "", "An unknown map has no next map")

	_check(CHECKPOINT.resume_map() == "", "No checkpoint passed, nothing to continue")
	CHECKPOINT.on_completed("level_a")
	_check(CHECKPOINT.resume_map() == "" and CHECKPOINT.passed_map() == "", "Finishing a plain map saves nothing")
	CHECKPOINT.on_completed("tutorial_lvl")
	_check(CHECKPOINT.passed_map() == "tutorial_lvl" and CHECKPOINT.resume_map() == "level_a", "Passing the checkpoint continues from the next map")
	chain.set_checkpoint(1, true)
	chain.save(CHAIN_PATH)
	CHECKPOINT.on_completed("level_a")
	_check(CHECKPOINT.resume_map() == "level_b", "A further checkpoint moves progress forward")
	CHECKPOINT.on_completed("tutorial_lvl")
	_check(CHECKPOINT.resume_map() == "level_b", "Replaying an earlier checkpoint does not move progress back")
	_check(CHECKPOINT.map_file("level_b").ends_with("level_b.json"), "The continue map resolves to its saved file")
	chain.set_checkpoint(2, true)
	chain.save(CHAIN_PATH)
	CHECKPOINT.on_completed("level_b")
	_check(CHECKPOINT.resume_map() == "", "No Continue after the last map of the chain")

	chain.set_checkpoint(0, true)
	CHECKPOINT.save_passed("tutorial_lvl")
	var frontend := FRONT.instantiate()
	root.add_child(frontend)
	current_scene = frontend
	await process_frame
	var menu: Control = frontend.get_node("Menu")
	_check(not menu.get("buttons")[1].disabled, "Continue is enabled once a checkpoint is passed")
	_check(menu.get("buttons")[1].tooltip_text == "", "An enabled Continue has no no-save tooltip")
	frontend.queue_free()
	await process_frame

	var caption: CanvasLayer = CAPTION.new()
	caption.caption = "Checkpoint"
	root.add_child(caption)
	await process_frame
	var label := caption.get_node_or_null("CheckpointCaption") as Label
	_check(label != null and label.text == "Checkpoint", "The caption reads Checkpoint")
	caption.queue_free()
	await process_frame

	_clear()
	if failures > 0:
		push_error("Checkpoint tests failed: %d failure(s)." % failures)
		quit(1)
		return
	print("Checkpoint tests passed.")
	quit(0)


func _clear() -> void:
	DirAccess.remove_absolute(CHAIN_PATH)
	DirAccess.remove_absolute(CHECKPOINT.PATH)
