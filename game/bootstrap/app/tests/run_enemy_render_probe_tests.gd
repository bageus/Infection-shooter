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
	var blood := Node3D.new()
	blood.set_meta("blood_effect", true)
	var lamp := OmniLight3D.new()
	var smoke := GPUParticles3D.new()
	for n: Node3D in [blood, lamp, smoke]:
		root.add_child(n)
	PROBE.apply_world(self.get_root().get_tree(), 4)
	_expect(not blood.visible and lamp.visible and smoke.visible, "Mode 4 hides blood only")
	PROBE.apply_world(self.get_root().get_tree(), 5)
	_expect(not lamp.visible and smoke.visible, "Mode 5 also switches lights off")
	PROBE.apply_world(self.get_root().get_tree(), 6)
	_expect(not smoke.visible, "Mode 6 also hides particles")
	PROBE.apply_world(self.get_root().get_tree(), 7)
	_expect(enemy.process_mode == Node.PROCESS_MODE_DISABLED and not root.disable_3d, "Mode 7 freezes enemies")
	PROBE.apply_world(self.get_root().get_tree(), 8)
	_expect(root.disable_3d, "Mode 8 stops drawing 3D")
	PROBE.apply_world(self.get_root().get_tree(), 0)
	_expect(enemy.process_mode == Node.PROCESS_MODE_INHERIT and not root.disable_3d, "Mode 0 unfreezes and draws 3D")
	_expect(blood.visible and lamp.visible and smoke.visible, "Mode 0 restores the scene")
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
