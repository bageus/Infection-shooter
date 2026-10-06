extends SceneTree
## Stun stars over a stunned infected and the green tint of a poisoned one:
## both appear with the status, end with it, and leave the corpse on death.

const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var enemy := HUNGER.instantiate() as Node3D
	root.add_child(enemy)
	await process_frame
	var fx: Node = enemy.get("status_fx")
	_expect(fx != null, "Every infected carries its status presentation.")
	_expect(not fx.call("is_showing_stun") and not fx.call("is_showing_poison"), "A healthy infected shows nothing.")
	_expect(not fx.is_processing(), "The status node is idle while nothing shows.")
	enemy.call("apply_blast_stun", 0.4, 1.0)
	_expect(fx.call("is_showing_stun"), "A stunned infected gets circling stars.")
	var stars := enemy.find_child("Flipbook", false, false) as Node3D
	_expect(stars != null and stars.global_position.y > enemy.global_position.y + 1.0, "The stars circle above the head.")
	enemy.call("apply_mutation_poison", 0.5, 0.0)
	_expect(fx.call("is_showing_poison"), "A poisoned infected takes a green tint.")
	var tinted := 0
	for mesh in enemy.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).material_overlay != null:
			tinted += 1
	_expect(tinted > 0, "The tint lies over the body meshes.")
	await create_timer(0.8).timeout
	_expect(not fx.call("is_showing_stun"), "The stars go when the stun ends.")
	_expect(not fx.call("is_showing_poison"), "The tint goes when the poison ends.")
	for mesh in enemy.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).material_overlay != null:
			failures += 1
			push_error("A mesh kept the poison tint: " + str(mesh.name))
	enemy.call("apply_blast_stun", 5.0, 1.0)
	enemy.call("apply_mutation_poison", 5.0, 0.0)
	enemy.call("take_damage", 9999.0)
	await process_frame
	_expect(not fx.call("is_showing_stun") and not fx.call("is_showing_poison"), "Death clears stars and tint.")
	enemy.queue_free()
	await process_frame
	print("Status fx tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
