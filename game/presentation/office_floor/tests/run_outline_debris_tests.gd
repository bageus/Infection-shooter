extends SceneTree
## Breaking an outlined crate must not turn the yellow occlusion outline mesh into a debris fragment.
const DAMAGE := preload("res://game/presentation/office_floor/environment_damage.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var host_script := GDScript.new()
	host_script.source_code = "extends Node3D\nvar effects_root: Node3D\n"
	host_script.reload()
	var host := Node3D.new()
	host.set_script(host_script)
	host.effects_root = scene
	scene.add_child(host)
	var plain := MeshInstance3D.new()
	plain.mesh = BoxMesh.new()
	host.add_child(plain)
	var rim := MeshInstance3D.new()
	rim.mesh = BoxMesh.new()
	rim.set_meta("occlusion_copy", true)
	plain.add_child(rim)
	_check(DAMAGE.spawn_piece(host, rim, host, 0, 0, Vector3.FORWARD, Vector3.ZERO) == null, "the outline mesh never becomes debris")
	_check(DAMAGE.spawn_piece(host, plain, host, 0, 0, Vector3.FORWARD, Vector3.ZERO) != null, "an ordinary mesh still becomes debris")
	print("Outline debris tests: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
