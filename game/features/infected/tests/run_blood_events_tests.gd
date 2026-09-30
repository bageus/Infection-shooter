extends SceneTree

const ENEMY := preload("res://game/features/infected/infected_capsule.gd")

class FakeCloud:
	extends Area3D
	signal depleted
	func activate() -> void:
		pass

var failures := 0
var hit_count := 0
var wound_count := 0
var trail_count := 0
var drag_count := 0
var death_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var enemy := ENEMY.new() as CharacterBody3D
	var body := Node3D.new()
	body.name = "Body"
	enemy.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = CapsuleShape3D.new()
	enemy.add_child(shape)
	var cloud := FakeCloud.new()
	cloud.name = "DeathCloud"
	enemy.add_child(cloud)
	stage.add_child(enemy)
	enemy.connect("projectile_blood", _on_hit)
	enemy.connect("blood_wounded", _on_wound)
	enemy.connect("wounded_moved", _on_trail)
	enemy.connect("body_dragged", _on_drag)
	enemy.connect("blood_death", _on_death)
	enemy.call("take_projectile_damage", 10.0, Vector3.UP, Vector3.FORWARD, "UZI")
	_expect(is_equal_approx(float(enemy.get("health")), 40.0), "Blood events preserve projectile damage.")
	_expect(hit_count == 1 and wound_count == 1, "A valid hit emits a splatter and one first-wound event.")
	enemy.call("take_projectile_damage", 0.0, Vector3.UP, Vector3.FORWARD, "UZI")
	_expect(hit_count == 1, "Zero damage does not emit a hit effect.")
	enemy.position.x = 0.3
	enemy.call("_track_blood_motion")
	_expect(trail_count == 0, "Short movement does not produce drops.")
	enemy.position.x = 0.65
	enemy.call("_track_blood_motion")
	_expect(trail_count == 1, "Accumulated movement above 0.6m produces one drops group.")
	for i in range(20):
		enemy.call("_track_blood_motion")
	_expect(trail_count == 1, "Standing still produces no additional drops.")
	enemy.call("take_damage", 100.0)
	enemy.call("take_damage", 100.0)
	_expect(death_count == 1 and is_zero_approx(float(enemy.get("health"))), "Repeated lethal damage emits one death without changing health rules.")
	enemy.position.x += 0.4
	enemy.call("_track_blood_motion")
	_expect(drag_count == 1, "Actual dead-body movement emits a short smear segment.")
	stage.queue_free()
	print("Infected blood event tests: %d failure(s)." % failures)
	quit(failures)


func _on_hit(_position: Vector3, _direction: Vector3, _weapon: String, excluded: Array[RID], _id: int) -> void:
	hit_count += 1
	_expect(excluded.size() == 1, "Hit carries a RID exclusion rather than a captured enemy node.")


func _on_wound(_position: Vector3, _excluded: Array[RID]) -> void:
	wound_count += 1


func _on_trail(_previous: Vector3, _current: Vector3, _excluded: Array[RID]) -> void:
	trail_count += 1


func _on_drag(_previous: Vector3, _current: Vector3, _excluded: Array[RID]) -> void:
	drag_count += 1


func _on_death(_position: Vector3, _excluded: Array[RID], _id: int) -> void:
	death_count += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
