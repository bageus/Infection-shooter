extends SceneTree
## The support hand fetches an invisible magazine from the vest and feeds it to the weapon.
const PLAYER := preload("res://game/features/player/public/player.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _run() -> void:
	var actor := PLAYER.instantiate() as CharacterBody3D
	root.add_child(actor)
	actor.set_physics_process(false)
	var effects := Node3D.new()
	root.add_child(effects)
	actor.call("configure_world", effects, null)
	await process_frame
	var pose: Node = actor.get_node("WeaponMount").get("reload_pose")
	_check(pose != null, "Reload pose modifier is mounted")
	var skeleton: Skeleton3D = actor.get_node("WeaponMount").get("skeleton")
	var hand := skeleton.find_bone("LeftHand")
	for index in [0, 2, 4]:
		actor.call("select_weapon_slot", index)
		var gun: Node3D = actor.call("get_current_weapon")
		gun.call("add_magazine_ammo", -100)
		gun.set("_magazine_ammo", 0)
		gun.call("start_reload")
		_check(gun.call("is_reloading"), "Weapon %d starts reloading" % index)
		var total: float = gun.get("reload_time")
		for step in [.27, .72]:
			for frame in 30:
				gun.set("_reload_remaining", total * (1.0 - step))
				await process_frame
			var target: Vector3 = pose.get("pouch_target") if step < .5 else pose.get("feed_target")
			var reached: float = pose.get("hand_position").distance_to(target)
			_check(reached < .08, "Weapon %d left hand within 8 cm of %s (%.3f)" % [index, "pouch" if step < .5 else "weapon", reached])
		var pouch: Vector3 = pose.get("pouch_target")
		var feed: Vector3 = pose.get("feed_target")
		_check(pouch.distance_to(feed) > .1, "Weapon %d: pouch and weapon are apart" % index)
		gun.call("cancel_reload")
		for frame in 30:
			await process_frame
		_check(float(pose.get("weight")) == 0.0, "Weapon %d: reload pose fades out after the reload" % index)
	actor.queue_free()
	effects.queue_free()
	await process_frame
	print("Reload pose tests: %d failures" % failures)
	quit(1 if failures else 0)
