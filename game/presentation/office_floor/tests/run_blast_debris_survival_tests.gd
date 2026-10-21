extends SceneTree
## A blast over a cluster of wooden props and printers must leave their debris visible:
## the fragment budget may not shrink fresh pieces of the objects the blast just broke.

const PROP := preload("res://game/presentation/office_floor/public/props/environment_prop.tscn")
const BLAST := preload("res://game/presentation/office_floor/blast_effect.gd")
const DEBRIS := preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const FRAGMENT := preload("res://game/presentation/office_floor/environment_fragment.gd")
const MODELS := "res://models/objects/enviroments/"
const CLUSTER := ["07/07_table_circular", "01/01_wood_slat_partition_destructible", "08/08_divider_full_H_desk", "08/08_divider_full_U_desk", "07/07_table_circular", "05/05_printer_destructible", "08/08_office_desk_2", "05/05_printer_destructible"]
const BLAST_RADIUS := 5.5
const OBSERVE_SECONDS := 1.0

var failures := 0
var spawned := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
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
	effects.child_entered_tree.connect(func(node: Node) -> void: spawned += int(node.get_script() == FRAGMENT))
	for index in CLUSTER.size():
		var prop := PROP.instantiate() as RigidBody3D
		prop.set("model_path", MODELS + CLUSTER[index] + ".glb")
		prop.collision_mask = 3
		stage.add_child(prop)
		prop.global_position = Vector3(1.4 + 1.1 * (index % 4), 0.05, 1.3 * (index / 4))
		prop.call("configure_world", effects, null)
	for i in 10:
		await physics_frame
	var host := Node3D.new()
	stage.add_child(host)
	BLAST.detonate(host, Vector3(0, 0.4, 0), BLAST_RADIUS, false)
	await create_timer(OBSERVE_SECONDS).timeout
	var live := 0
	for piece in get_nodes_in_group(FRAGMENT.GROUP):
		live += int(not DEBRIS.is_fading(piece))
	_check(spawned > FRAGMENT.MAX_FRAGMENTS, "A cluster blast makes more pieces than the idle budget (%d)" % spawned)
	_check(live == spawned, "Every fresh blast piece is still visible (%d of %d)" % [live, spawned])
	stage.queue_free()
	await process_frame
	print("Blast debris survival tests: %d failure(s)." % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + label)
	print(("PASS: " if condition else "FAIL: ") + label)
