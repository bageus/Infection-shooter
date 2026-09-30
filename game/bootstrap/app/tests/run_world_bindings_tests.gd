extends SceneTree

const MAIN := preload("res://game/bootstrap/app/main.tscn")
const ENEMY := preload("res://game/features/infected/public/infected_capsule.tscn")
const DOOR := "res://game/presentation/office_floor/public/structural/elevator_door.tscn"
const DEVICE := "res://models/objects/enviroments/05/05_PC_destructible.glb"
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var decoy := Node3D.new()
	root.add_child(decoy)
	current_scene = decoy # The actual mission must never discover this unrelated root.
	var stage := MAIN.instantiate()
	root.add_child(stage)
	await process_frame
	var player := stage.get_node("Gameplay/Player") as Node3D
	player.set_physics_process(false)
	var container := stage.get("mission_objects") as Node3D
	var pool := stage.get("impact_pool") as Node
	_check(container != null and pool != null, "Bootstrap owns explicit mission collaborators")
	var pistol := player.call("get_current_weapon") as Node3D
	_check(bool(pistol.call("try_fire_at", Vector3(0, 0, -10))), "Configured pistol fires")
	var bullet: Node3D
	for child in container.get_children():
		if child.has_method("setup_projectile"):
			bullet = child as Node3D
	_check(bullet != null, "Bullet goes into the injected container")
	if bullet != null:
		bullet.set_physics_process(false)
		bullet.call("_spawn_impact_decal", null, Vector3.UP, Vector3.UP)
		_check(pool.get("_marks").size() > 0, "Impact uses the injected budget")
	var launcher := player.get_node("AimPivot/GrenadeLauncher") as Node3D
	_check(bool(launcher.call("try_fire_at", Vector3(0, 0, -8))), "Configured launcher fires")
	for child in container.get_children():
		if child.has_method("_explode_at"):
			child.set_physics_process(false)
			child.call("_explode_at", Vector3(0, 1, -8), Vector3.UP, null)
	_check(bool(player.call("pickup_weapon", 3)), "Injected drop command allows weapon replacement")
	player.call("configure_weapon_drop", func(_index: int, _at: Vector3) -> bool: return false)
	_check(not bool(player.call("pickup_weapon", 0)), "Failed drop rejects replacement")
	_check(int(player.call("get_weapon_in_slot", 0)) == 3, "Failed command preserves the slot")
	stage.call("bind_world_object", player)
	await _exercise_factory(stage, player, container, pool)
	_check(decoy.get_child_count() == 0, "No projectile, drop, effect or budget leaks to current_scene")
	stage.queue_free()
	decoy.queue_free()
	await process_frame
	# The audio mixer releases the explosion playback asynchronously after tree removal.
	await create_timer(0.15).timeout
	print("World bindings tests: %d failures" % _failures)
	quit(_failures)


func _exercise_factory(stage: Node, player: Node3D, container: Node3D, pool: Node) -> void:
	var planner: Node = stage.get("planning_mode")
	var door := planner.call("_instantiate_asset", DOOR) as Node3D
	stage.add_child(door)
	var controller := door.get_node("DoorController")
	_check(controller.get("_player") == player, "Factory binds the structural root's local door target")
	var prop := planner.call("_instantiate_asset", DEVICE) as Node3D
	stage.add_child(prop)
	_check(prop.get("effects_root") == container and prop.get("impact_pool") == pool, "New catalog prop receives the same dependencies")
	prop.call("take_projectile_hit", 10000.0, Vector3.UP, Vector3.UP, Vector3.FORWARD, "GRENADE")
	await process_frame
	var fragment: Node3D
	for child in container.get_children():
		if str(child.name).begins_with("Fragment_"):
			fragment = child as Node3D
	_check(fragment != null, "Damaged catalog prop spawns debris in its injected container")
	prop.queue_free()
	await process_frame
	_check(is_instance_valid(fragment), "World debris survives removal of its source")
	var enemy := ENEMY.instantiate() as Node3D
	stage.get_node("Gameplay/Enemies").add_child(enemy)
	_check(enemy.get("effects_root") == container, "Dynamically added enemy is wired")
	seed(7)
	# Exercise real drops across several deaths, without asserting a particular item type.
	var before := container.get_child_count()
	for index in 12:
		var victim := ENEMY.instantiate() as Node3D
		stage.call("bind_world_object", victim)
		stage.add_child(victim)
		victim.call("take_damage", 10000.0)
	_check(container.get_child_count() > before, "Enemy drops use the injected container")
	await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
