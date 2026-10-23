extends SceneTree
## After a grenade the slats of a wooden partition must fall to the floor and come to rest,
## not hang tilted on each other so the broken partition still looks standing.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BLAST := preload("res://game/presentation/office_floor/blast_effect.gd")
const FRAGMENT := preload("res://game/presentation/office_floor/environment_fragment.gd")
const MODEL := "res://models/objects/enviroments/01/01_wood_slat_partition_destructible.glb"
# Physics frames, not wall time: a slow CI runner simulates fewer steps per second but the same steps per frame.
const SETTLE_FRAMES := 900
const CHECK_EVERY := 60
# A slat standing or leaning higher than this above the floor after the settle time is "hanging".
const MAX_REST_TOP := 0.45

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(7) # Impulses and tumble use randf; a fixed seed makes every run identical.
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 2
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(60, 0.2, 60)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	floor_body.position.y = -0.1
	var effects := Node3D.new()
	stage.add_child(effects)
	var prop := PROP.instantiate() as RigidBody3D
	prop.set("model_path", MODEL)
	prop.collision_mask = 3
	stage.add_child(prop)
	prop.global_position = Vector3(0, 0.05, 0)
	prop.call("configure_world", effects, null)
	for i in 10:
		await physics_frame
	var host := Node3D.new()
	stage.add_child(host)
	BLAST.detonate(host, Vector3(0, 0.4, 1.0), 5.5, false)
	var pieces := get_nodes_in_group(FRAGMENT.GROUP)
	var hanging := 0
	var highest := 0.0
	for frame in SETTLE_FRAMES:
		await physics_frame
		if frame % CHECK_EVERY != CHECK_EVERY - 1:
			continue
		pieces = get_nodes_in_group(FRAGMENT.GROUP)
		hanging = 0
		highest = 0.0
		for piece in pieces:
			var top := _top(piece as RigidBody3D)
			highest = maxf(highest, top)
			hanging += int(top > MAX_REST_TOP)
		if hanging == 0 and pieces.size() > 5:
			break
	print("pieces=%d hanging=%d highest_top=%.2f" % [pieces.size(), hanging, highest])
	_check(pieces.size() > 5, "The partition broke into pieces")
	_check(hanging == 0, "No slat hangs above %.2f m after %d physics frames (%d hanging)" % [MAX_REST_TOP, SETTLE_FRAMES, hanging])
	stage.queue_free()
	await process_frame
	print("Partition blast tests: %d failure(s)." % failures)
	quit(failures)


func _top(body: RigidBody3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var half := ((child as CollisionShape3D).shape as BoxShape3D).size * 0.5
			var b := body.global_basis
			return body.global_position.y + absf(b.x.y) * half.x + absf(b.y.y) * half.y + absf(b.z.y) * half.z
	return body.global_position.y


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)

