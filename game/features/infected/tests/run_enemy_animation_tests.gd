extends SceneTree
## Runtime checks for enemy animation: skeletal clips, procedural fallback,
## hit-frame attack timing, death animation and far-enemy pausing.

const ZOMBIE := preload("res://game/features/infected/public/infected_capsule.tscn")
const MUTANT := preload("res://game/features/infected/public/mutant_level2.tscn")
const HUNGER := preload("res://game/features/infected/public/infected_hunger.tscn")
const ALL_NEW := [
	"res://game/features/infected/public/infected_hunger.tscn",
	"res://game/features/infected/public/infected_revenant.tscn",
	"res://game/features/infected/public/infected_brute.tscn",
	"res://game/features/infected/public/infected_titan.tscn",
	"res://game/features/infected/public/infected_colossus.tscn",
	"res://game/features/infected/public/infected_horde.tscn",
]

class FakeTarget:
	extends Node3D
	var damage_taken := 0.0
	func take_damage(amount: float, _kind: String = "physical") -> void:
		damage_taken += amount

var failures := 0
var _finished: Array[StringName] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	await _test_skeletal_locomotion(stage, ZOMBIE, "Zombie", 4.5)
	await _test_skeletal_locomotion(stage, MUTANT, "Mutant", 5.1)
	await _test_skeletal_one_shots(stage)
	await _test_procedural(stage)
	await _test_all_new_enemies_load(stage)
	await _test_attack_lands_on_hit_frame(stage)
	await _test_attack_misses_when_target_leaves(stage)
	await _test_death_animation_then_sink(stage)
	await _test_far_enemy_pauses_animation(stage)
	stage.queue_free()
	await process_frame
	print("Enemy animation tests: %d failure(s)." % failures)
	quit(failures)


func _spawn(stage: Node3D, scene: PackedScene) -> CharacterBody3D:
	var enemy := scene.instantiate() as CharacterBody3D
	stage.add_child(enemy)
	await process_frame
	return enemy


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _test_skeletal_locomotion(stage: Node3D, scene: PackedScene, label: String, run_speed: float) -> void:
	var enemy := await _spawn(stage, scene)
	var driver := enemy.get_node("AnimationDriver")
	var player := driver.get("animation_player") as AnimationPlayer
	_expect(player != null, label + " has a skeletal AnimationPlayer.")
	for clip in ["Walk", "Run"]:
		_expect(player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, label + " " + clip + " loops (imported clips do not).")
	for clip in ["AttackLeft", "AttackRight", "Death"]:
		_expect(player.get_animation(clip).loop_mode == Animation.LOOP_NONE, label + " " + clip + " stays one-shot.")
	await _frames(3)
	_expect(not player.is_playing(), label + " standing still holds a rest pose, not a stale clip.")
	_expect(player.current_animation != "AttackLeft", label + " does not stand in the first alphabetical clip.")
	enemy.velocity = Vector3(0, 0, run_speed)
	await _frames(3)
	_expect(player.current_animation == "Run", label + " chasing speed selects Run (was unreachable at threshold 6.8).")
	_expect(absf(player.speed_scale - 1.0) < 0.05, label + " Run playback matches chase speed.")
	enemy.velocity = Vector3(0, 0, 1.5)
	await _frames(3)
	_expect(player.current_animation == "Walk", label + " slow movement selects Walk.")
	_expect(player.speed_scale < 1.0, label + " Walk playback is scaled down to the slower speed.")
	enemy.velocity = Vector3.ZERO
	await _frames(3)
	_expect(not player.is_playing(), label + " returns to the rest pose when stopping.")
	enemy.queue_free()
	await process_frame


func _test_skeletal_one_shots(stage: Node3D) -> void:
	var enemy := await _spawn(stage, ZOMBIE)
	var driver := enemy.get_node("AnimationDriver")
	var player := driver.get("animation_player") as AnimationPlayer
	_finished.clear()
	driver.connect("one_shot_finished", func(state: StringName) -> void: _finished.append(state))
	var first := float(driver.call("play_one_shot", &"attack"))
	_expect(is_equal_approx(first, 0.9), "Attack returns the clip length (0.9s).")
	var first_clip := player.current_animation
	_expect(first_clip in ["AttackLeft", "AttackRight"], "Attack plays an attack clip.")
	await create_timer(1.0).timeout
	_expect(_finished.has(&"attack"), "Attack reports completion.")
	driver.call("play_one_shot", &"attack")
	_expect(player.current_animation != first_clip, "Consecutive attacks alternate left and right.")
	await create_timer(1.0).timeout
	var death := float(driver.call("play_one_shot", &"death"))
	_expect(is_equal_approx(death, 1.8), "Death returns the clip length (1.8s).")
	_expect(player.current_animation == "Death", "Death plays the Death clip.")
	_expect(float(driver.call("play_one_shot", &"attack")) == 0.0, "Death is final: no attack afterwards.")
	enemy.velocity = Vector3(0, 0, 4.5)
	await create_timer(2.1).timeout
	_expect(player.assigned_animation == "Death", "Locomotion never overrides a finished death pose.")
	_expect(_finished.has(&"death"), "Death reports completion.")
	enemy.queue_free()
	await process_frame


func _test_procedural(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	var driver := enemy.get_node("AnimationDriver")
	var visual := enemy.get_node("Body/Visual") as Node3D
	_expect(driver.get("animation_player") == null, "Static-mesh enemy has no AnimationPlayer.")
	var rest := visual.transform
	enemy.velocity = Vector3(0, 0, 5.4)
	await create_timer(0.4).timeout
	_expect(visual.rotation.x > 0.05, "Moving static-mesh enemy leans forward procedurally.")
	_expect(not visual.transform.is_equal_approx(rest), "Moving static-mesh enemy animates its pivot.")
	enemy.velocity = Vector3.ZERO
	await create_timer(0.2).timeout
	_expect(absf(visual.rotation.x) < 0.02, "Standing static-mesh enemy returns upright.")
	var attack := float(driver.call("play_one_shot", &"attack"))
	_expect(is_equal_approx(attack, 0.45), "Procedural attack uses its configured duration.")
	await create_timer(0.27).timeout
	_expect(visual.position.z > 0.05, "Procedural attack lunges forward at the strike.")
	await create_timer(0.4).timeout
	driver.call("notify_hit")
	await create_timer(0.07).timeout
	_expect(not visual.transform.is_equal_approx(rest), "A hit flinches the visual.")
	await create_timer(0.3).timeout
	var death := float(driver.call("play_one_shot", &"death"))
	_expect(is_equal_approx(death, 1.1), "Procedural death uses its configured duration.")
	await create_timer(1.4).timeout
	_expect(visual.rotation.x < -1.4, "Procedural death topples the visual onto its back.")
	_expect(float(driver.call("play_one_shot", &"attack")) == 0.0, "Procedural death is final.")
	enemy.queue_free()
	await process_frame


func _test_all_new_enemies_load(stage: Node3D) -> void:
	for path: String in ALL_NEW:
		var scene := load(path) as PackedScene
		_expect(scene != null, "Enemy scene loads: " + path.get_file())
		if scene == null:
			continue
		var enemy := await _spawn(stage, scene)
		var visual := enemy.get_node_or_null("Body/Visual") as MeshInstance3D
		_expect(visual != null and visual.mesh != null and visual.mesh.get_surface_count() == 1, path.get_file() + " has its lightweight mesh.")
		if visual != null and visual.mesh != null:
			var triangles: int = (visual.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
			_expect(triangles <= 10000, "%s stays within the crowd budget (%d triangles)." % [path.get_file(), triangles])
		_expect(visual.get_surface_override_material(0) != null, path.get_file() + " keeps its material.")
		_expect(enemy.is_in_group("infected"), path.get_file() + " is an infected enemy.")
		enemy.queue_free()
		await process_frame


func _test_attack_lands_on_hit_frame(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, 1.0)
	enemy.call("set_target", target)
	await physics_frame
	await physics_frame
	_expect(target.damage_taken == 0.0, "Damage is not instant: the blow lands on the hit frame.")
	await create_timer(0.45).timeout
	_expect(is_equal_approx(target.damage_taken, 12.0), "The blow lands once after the wind-up (got %s)." % target.damage_taken)
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_attack_misses_when_target_leaves(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(0, 0, 1.0)
	enemy.call("set_target", target)
	await physics_frame
	await physics_frame
	target.global_position = enemy.global_position + Vector3(0, 0, 4.0)
	await create_timer(0.35).timeout
	_expect(target.damage_taken == 0.0, "The blow misses when the target left reach during the wind-up.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _test_death_animation_then_sink(stage: Node3D) -> void:
	var enemy := await _spawn(stage, HUNGER)
	enemy.set("death_linger_seconds", 0.1)
	var body := enemy.get_node("Body") as Node3D
	var start_y := body.position.y
	enemy.call("take_damage", 1000.0)
	await create_timer(0.5).timeout
	_expect(body.visible, "The corpse stays visible while the death animation plays.")
	await create_timer(0.8).timeout
	_expect(body.visible and body.position.y < start_y, "The corpse sinks after the animation.")
	await create_timer(1.2).timeout
	_expect(not body.visible, "The corpse is hidden after sinking.")
	enemy.queue_free()
	await process_frame


func _test_far_enemy_pauses_animation(stage: Node3D) -> void:
	var enemy := await _spawn(stage, ZOMBIE)
	var target := FakeTarget.new()
	stage.add_child(target)
	target.global_position = enemy.global_position + Vector3(60, 0, 0)
	enemy.call("set_target", target)
	var player := enemy.get_node("AnimationDriver").get("animation_player") as AnimationPlayer
	await physics_frame
	await physics_frame
	_expect(not player.active, "Far enemies stop animating.")
	target.global_position = enemy.global_position + Vector3(6, 0, 0)
	await physics_frame
	await physics_frame
	_expect(player.active, "Enemies animate again when the player approaches.")
	enemy.queue_free()
	target.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
