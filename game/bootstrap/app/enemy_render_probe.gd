extends RefCounted
## F5 debug probe: switches off parts of the enemy rendering one step at a time (particles, shadows, models), so the
## frame time shown by F3 says what the enemies cost on this GPU. Simulation keeps running; mode 0 restores everything.
const NAMES := ["normal", "enemy particles off", "+ enemy shadows off", "+ enemy models hidden"]
const HIDDEN := &"probe_hidden"
const SHADOW := &"probe_shadow"


## Applies `mode` to every living enemy; call again for new spawns.
static func apply(tree: SceneTree, mode: int) -> void:
	for enemy: Node in tree.get_nodes_in_group("infected"):
		_walk(enemy, mode)
		if enemy is Node3D:
			_hide(enemy as Node3D, mode >= 3)


static func _walk(node: Node, mode: int) -> void:
	for child in node.get_children():
		if child is GPUParticles3D:
			_hide(child as Node3D, mode >= 1)
		elif child is GeometryInstance3D:
			var mesh := child as GeometryInstance3D
			if mode >= 2 and not mesh.has_meta(SHADOW):
				mesh.set_meta(SHADOW, mesh.cast_shadow)
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif mode < 2 and mesh.has_meta(SHADOW):
				mesh.cast_shadow = mesh.get_meta(SHADOW)
				mesh.remove_meta(SHADOW)
		_walk(child, mode)


# Only nodes this probe hid are shown again, so enemies hidden by fog rooms stay hidden.
static func _hide(node: Node3D, hidden: bool) -> void:
	if hidden and node.visible:
		node.set_meta(HIDDEN, true)
		node.visible = false
	elif not hidden and node.has_meta(HIDDEN):
		node.visible = true
		node.remove_meta(HIDDEN)
