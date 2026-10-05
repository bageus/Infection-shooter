extends StaticBody3D
const SFX := preload("res://game/core/audio/public/sound_events.gd")

const DAMAGE = preload("res://game/presentation/office_floor/environment_damage.gd")
const CRACKS = preload("res://game/presentation/office_floor/glass_crack_marks.gd")

@export var max_health := 28.0
@export var hide_with_glass: PackedStringArray = PackedStringArray()
@export var blinds_pass_through := false
@export var preserve_open_frame := false
@export var unbreakable := false
## Cracked hits a pane takes (random in range) before the next one shatters it.
@export var cracks_before_break := Vector2i(2, 4)
## Shards this close to the hit burst out at once; the rest crumble from
## their own places, later the further they are.
@export var burst_radius := 0.45
@export var crumble_seconds_per_metre := 0.22

var _health := 0.0
var _broken := false
var _cracks_needed := 0
var _crack_marks: Array[Node3D] = []
var _glass_nodes: Array[Node3D] = []
var _blinds: Array[Node3D] = []
var _blinds_rest: Array[Basis] = []
var _player: Node3D
var _player_near_blinds := false
var _sway_strength := 0.0
var _sway_time := 0.0

var effects_root: Node3D
var impact_pool: Node


# Public scene wiring v1; owned by the mission composition.
func configure_world(container: Node3D, impacts: Node) -> void:
	effects_root = container
	impact_pool = impacts

func configure_player(actor: Node3D) -> void:
	_player = actor


func _ready() -> void:
	_health = max_health
	_cracks_needed = randi_range(cracks_before_break.x, cracks_before_break.y)
	_collect_glass(get_parent().get_node_or_null("Visual"))
	if blinds_pass_through:
		_collect_blinds(get_parent().get_node_or_null("Visual"))
	set_physics_process(blinds_pass_through)


func _physics_process(delta: float) -> void:
	if not _broken or _blinds.is_empty():
		return
	var near := false
	var partition := get_parent() as Node3D
	if is_instance_valid(_player) and partition != null:
		var local_player: Vector3 = partition.to_local(_player.global_position)
		near = absf(local_player.x) < 0.85 and absf(local_player.z) < 0.55 and local_player.y > -0.5 and local_player.y < 3.2
	if near and not _player_near_blinds:
		_sway_strength = 0.16
	_player_near_blinds = near
	_sway_time += delta * 8.0
	_sway_strength = move_toward(_sway_strength, 0.0, delta * 0.055)
	for i in _blinds.size():
		if is_instance_valid(_blinds[i]):
			_blinds[i].basis = _blinds_rest[i].rotated(Vector3.RIGHT, sin(_sway_time + float(i) * 0.3) * _sway_strength)


func _collect_blinds(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D and "blinds" in node.name.to_lower() and absf((node as MeshInstance3D).global_basis.determinant()) > 0.000000000001:
		var blind := node as Node3D
		_blinds.append(blind)
		_blinds_rest.append(blind.basis)
	for child in node.get_children():
		_collect_blinds(child)


func take_projectile_hit(_damage: float, hit_position: Vector3, hit_normal: Vector3, _direction: Vector3, _weapon_name: String) -> bool:
	if unbreakable:
		var mark_size := _glass_mark_size(hit_position)
		if mark_size >= 0.08:
			CRACKS.spawn(self, hit_position, hit_normal, mark_size)
		return false
	if _broken:
		return false
	# Bullets crack the pane first; a blast or the hit after the last crack
	# shatters it.
	if _weapon_name != "GRENADE" and _crack_marks.size() < _cracks_needed:
		_add_crack(hit_position, hit_normal)
		return false
	_break_glass(hit_position, _direction)
	return false


func _add_crack(hit_position: Vector3, hit_normal: Vector3) -> void:
	var size := _glass_mark_size(hit_position)
	var mark: Node3D = CRACKS.spawn(self, hit_position, hit_normal, size if size >= 0.12 else 0.4)
	if mark != null:
		_crack_marks.append(mark)


## Cracks shown on the pane (0 once it has shattered).
func crack_count() -> int:
	return _crack_marks.size()


func _glass_mark_size(point: Vector3) -> float:
	var visual := get_parent().get_node_or_null("Visual") as Node3D
	var exterior := get_parent().scene_file_path.get_file() == "window_double.tscn" or (visual != null and visual.scene_file_path.get_file() == "01_window_double.glb")
	for node in _glass_nodes:
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var pane := node as MeshInstance3D
		var local := pane.to_local(point)
		var bounds := pane.get_aabb()
		var edge_x := minf(local.x - bounds.position.x, bounds.end.x - local.x)
		var edge_z := minf(local.z - bounds.position.z, bounds.end.z - local.z)
		if exterior:
			# The central mullion belongs to the frame, even though the pane mesh spans it.
			edge_x = minf(edge_x, absf(local.x) - 0.13)
		var clearance := minf(edge_x * pane.global_basis.x.length(), edge_z * pane.global_basis.z.length())
		if clearance > 0.0:
			return minf(clearance * 0.85, 0.65)
	return 0.0


func get_projectile_material(_shape_index: int = -1) -> String:
	return "glass"


func take_melee_hit(damage: float, hit_position: Vector3, _direction: Vector3) -> void:
	if unbreakable:
		return
	if _broken:
		return
	_health -= maxf(damage, 0.0)
	if _health <= 0.0:
		_break_glass(hit_position, _direction)


func _collect_glass(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D and "glass" in node.name.to_lower() and (node as MeshInstance3D).is_visible_in_tree() and absf((node as MeshInstance3D).global_basis.determinant()) > 0.000000000001:
		_glass_nodes.append(node as Node3D)
	for child in node.get_children():
		_collect_glass(child)


func _break_glass(hit_position: Vector3, direction: Vector3 = Vector3.ZERO) -> void:
	if _broken:
		return
	_broken = true
	SFX.play(self, &"glass_break", hit_position)
	for mark in _crack_marks:
		if is_instance_valid(mark):
			mark.queue_free()
	_crack_marks.clear()
	for glass in _glass_nodes:
		if is_instance_valid(glass):
			glass.visible = false
	for token in hide_with_glass:
		if str(token).to_lower() == "lower_panel":
			_drop_lower_panel(hit_position)
		else:
			_hide_named(get_parent().get_node_or_null("Visual"), str(token).to_lower())
	if preserve_open_frame:
		call_deferred("_replace_frame_collision")
	_disable_collision_recursive(self)
	# Streaming can reactivate deferred shapes; remove the broken pane body
	# from character and projectile collision immediately.
	collision_layer = 0
	collision_mask = 0
	# Only GlassBody is disabled; the surrounding frame keeps its own collision.
	_spawn_fragments(hit_position, direction)


func _replace_frame_collision() -> void:
	var frame_body := get_parent().get_node_or_null("Body") as StaticBody3D
	var visual := get_parent().get_node_or_null("Visual") as Node3D
	var frame := _find_visible_frame(visual)
	if frame_body == null or frame == null:
		return
	var to_body := frame_body.global_transform.affine_inverse()
	var outer: AABB = (to_body * frame.global_transform) * frame.get_aabb()
	# Only the perimeter of the imported frame should obstruct a character.
	# Some frame models have an additional pane collision across the opening.
	for child in frame_body.get_children():
		if child is CollisionShape3D:
			child.queue_free()
	var depth := maxf(outer.size.z, 0.07)
	# Leave enough clear width and height for the player's capsule after the pane
	# breaks. Imported frame meshes can include an invisible full-size infill.
	var side := clampf(outer.size.x * 0.09, 0.08, 0.16)
	var opening_width := maxf(outer.size.x - side * 2.0, 0.1)
	var top := clampf(outer.size.y - 1.95, 0.08, 0.16)
	_add_frame_bar(frame_body, Vector3(side, outer.size.y, depth), Vector3(outer.position.x + side * 0.5, outer.get_center().y, outer.get_center().z))
	_add_frame_bar(frame_body, Vector3(side, outer.size.y, depth), Vector3(outer.end.x - side * 0.5, outer.get_center().y, outer.get_center().z))
	# The visible sill is below a normal step, but CharacterBody3D has no step-up;
	# a collision here would close the passage at foot height again.
	_add_frame_bar(frame_body, Vector3(opening_width, top, depth), Vector3(outer.get_center().x, outer.end.y - top * 0.5, outer.get_center().z))


func _add_frame_bar(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "FrameBar"
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	collision.position = center


func _drop_lower_panel(hit_position: Vector3) -> void:
	var frame: MeshInstance3D = _find_visible_frame(get_parent().get_node_or_null("Visual"))
	if frame == null or frame.mesh.get_surface_count() < 2:
		return
	var panel_mesh := ArrayMesh.new()
	panel_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, frame.mesh.surface_get_arrays(1))
	var panel_material := frame.get_active_material(1)
	if panel_material != null:
		panel_mesh.surface_set_material(0, panel_material)
	var panel := MeshInstance3D.new()
	panel.mesh = panel_mesh
	get_parent().add_child(panel)
	panel.global_transform = frame.global_transform
	DAMAGE.spawn_piece(self, panel, null, 0, 0, Vector3.DOWN, hit_position)
	panel.queue_free()
	var invisible := StandardMaterial3D.new()
	invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invisible.albedo_color = Color(0, 0, 0, 0)
	frame.set_surface_override_material(1, invisible)
	var frame_body := get_parent().get_node_or_null("Body") as StaticBody3D
	if frame_body != null:
		for child in frame_body.get_children():
			if child is CollisionShape3D and child.name == "BreakawayPanel":
				(child as CollisionShape3D).set_deferred("disabled", true)


func _find_visible_frame(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D and "frame" in node.name.to_lower() and (node as MeshInstance3D).is_visible_in_tree() and absf((node as MeshInstance3D).global_basis.determinant()) > 0.000000000001:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_visible_frame(child)
		if found != null:
			return found
	return null


func _disable_collision_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).set_deferred("disabled", true)
	for child in node.get_children():
		_disable_collision_recursive(child)


func _disable_glass_named_collision(body: StaticBody3D) -> void:
	for child in body.get_children():
		if child is CollisionShape3D and ("glass" in child.name.to_lower() or "door" in child.name.to_lower()):
			(child as CollisionShape3D).set_deferred("disabled", true)


func _hide_named(node: Node, token: String) -> void:
	if node == null:
		return
	if node is Node3D and token in node.name.to_lower():
		(node as Node3D).visible = false
	for child in node.get_children():
		_hide_named(child, token)


func _spawn_fragments(hit_position: Vector3, direction: Vector3 = Vector3.ZERO) -> void:
	var visual := get_parent().get_node_or_null("Visual") as Node3D
	var group: Node3D = DAMAGE.find_named(visual, "Glass_Shards") if visual != null else null
	if group != null:
		# Every shard stays in its place in the frame and falls from there.
		var shards: Array[MeshInstance3D] = DAMAGE.reveal_meshes(group)
		group.show()
		var push := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
		var host: WeakRef = weakref(self)
		for index in shards.size():
			var shard := shards[index]
			var center: Vector3 = (shard.global_transform * shard.get_aabb()).get_center()
			var distance := center.distance_to(hit_position)
			if distance <= burst_radius:
				_drop_shard(shard, index, push + Vector3.DOWN * 0.1, hit_position, true)
				continue
			var delay := distance * crumble_seconds_per_metre + randf_range(0.0, 0.12)
			var piece: WeakRef = weakref(shard)
			get_tree().create_timer(delay, false).timeout.connect(func() -> void:
				var pane := host.get_ref() as Node
				var source := piece.get_ref() as MeshInstance3D
				if pane != null and source != null and source.is_visible_in_tree():
					pane.call("_drop_shard", source, index, push * 0.35 + Vector3.DOWN, hit_position, false))
		return
	# Older window models have a pane but no shard geometry.
	for index in 6:
		var source := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.12, 0.025)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.55, 0.84, 0.95, 0.7)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = material
		source.mesh = box
		get_parent().add_child(source)
		source.global_position = hit_position + Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), 0)
		DAMAGE.spawn_piece(self, source, null, 0, index, Vector3.UP, hit_position)
		source.queue_free()


# Turns one shard of the pane into a falling piece at the shard's own place.
func _drop_shard(shard: MeshInstance3D, index: int, direction: Vector3, hit_position: Vector3, burst: bool) -> void:
	DAMAGE.spawn_piece(self, shard, null, 0, index, direction, hit_position, burst)
	shard.hide()
