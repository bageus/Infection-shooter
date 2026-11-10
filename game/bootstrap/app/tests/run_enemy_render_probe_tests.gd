extends SceneTree
## F5 enemy render probe: each mode switches off one more part of enemy rendering and mode 0 restores it exactly.
const PROBE := preload("res://game/bootstrap/app/enemy_render_probe.gd")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var enemy := Node3D.new()
	enemy.add_to_group("infected")
	var particles := GPUParticles3D.new()
	var mesh := MeshInstance3D.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	enemy.add_child(particles)
	enemy.add_child(mesh)
	var fogged := Node3D.new()
	fogged.add_to_group("infected")
	fogged.visible = false
	root.add_child(enemy)
	root.add_child(fogged)
	await process_frame
	PROBE.apply(self.get_root().get_tree(), 1)
	_expect(not particles.visible and enemy.visible, "Mode 1 hides particles only")
	PROBE.apply(self.get_root().get_tree(), 2)
	_expect(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and enemy.visible, "Mode 2 also drops shadows")
	PROBE.apply(self.get_root().get_tree(), 3)
	_expect(not enemy.visible, "Mode 3 hides the enemy models")
	PROBE.apply(self.get_root().get_tree(), 0)
	_expect(particles.visible and enemy.visible, "Mode 0 shows everything again")
	_expect(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "Mode 0 restores the original shadow setting")
	_expect(not fogged.visible, "Enemies hidden by other systems stay hidden")
	print("Enemy render probe tests: %d failure(s)." % failures)
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
