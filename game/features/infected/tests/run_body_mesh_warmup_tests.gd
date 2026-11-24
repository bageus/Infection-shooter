extends SceneTree
## Warming an enemy kind builds its body geometry before the fight: the holder is gone at once, no enemy is left
## alive, and the next enemy of that kind prepares its body parts from the cache instead of rebuilding them.
const WARMUP := preload("res://game/features/infected/public/body_mesh_warmup.gd")
const PREPARATION := preload("res://game/features/infected/infected_visual_preparation.gd")
const HUNGER := "res://game/features/infected/public/infected_hunger.tscn"
## A cold preparation takes several hundred ms; one from the cache well under 10 ms.
const WARM_LIMIT_MSEC := 100.0
var failures := 0


class Budget extends Node:
	var camera: Camera3D

	func track(_actor: Node) -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	_check(not WARMUP.warm(host, "res://missing/enemy.tscn"), "a missing scene is refused")
	_check(WARMUP.warm(host, HUNGER), "an enemy kind warms")
	_check(host.get_child_count() == 0, "the warm-up scene is freed at once")
	_check(get_nodes_in_group("infected_alive").is_empty(), "no enemy stays alive after the warm-up")
	# A real spawn: the mission's budget defers the body parts, then prepares them from the cache.
	var budget := Budget.new()
	root.add_child(budget)
	var enemy := (load(HUNGER) as PackedScene).instantiate()
	enemy.call("configure_visual_preparation", budget)
	host.add_child(enemy)
	await process_frame
	var started := Time.get_ticks_usec()
	PREPARATION.parts(enemy)
	var msec := (Time.get_ticks_usec() - started) / 1000.0
	_check(msec < WARM_LIMIT_MSEC, "a warmed kind prepares its body parts in %.1f ms (limit %.0f)" % [msec, WARM_LIMIT_MSEC])
	_check(enemy.get("_parts") != null, "the warmed enemy still gets its body parts")
	print("Body mesh warm-up tests: %d failure(s)" % failures)
	quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
