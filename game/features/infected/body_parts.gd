extends Node
## Destructible body parts of an infected or a corpse decoration (ADR-0017).
##
## Owns per-part durability, bullet wounds painted on the skin (rest-space
## wound shader), severing (bone collapse, stump, falling piece, bleeding) and
## the bullet-only hit volumes that keep a corpse shootable. Gameplay effects
## of a lost part (death, slower walk, one-armed attacks) belong to the owner.

signal part_severed(part: StringName, piece: RigidBody3D)

const MESH := preload("res://game/features/infected/body_part_mesh.gd")
const MODIFIER := preload("res://game/features/infected/dismember_modifier.gd")
const SEVERED := preload("res://game/features/infected/severed_part.gd")
const HITBOX := preload("res://game/features/infected/body_part_hitbox.gd")
const FX := preload("res://game/features/infected/blood_drip_fx.gd")
const MAX_WOUNDS := 16
const TORSO := &"torso"
const HUMANOID_PARTS := {
	&"head": {"bones": ["Head"], "share": 0.6},
	&"arm_l": {"bones": ["L_UpperArm", "L_Forearm", "L_Hand"], "share": 0.7},
	&"arm_r": {"bones": ["R_UpperArm", "R_Forearm", "R_Hand"], "share": 0.7},
	&"leg_l": {"bones": ["L_Thigh", "L_Shin", "L_Foot", "L_Toe"], "share": 0.8},
	&"leg_r": {"bones": ["R_Thigh", "R_Shin", "R_Foot", "R_Toe"], "share": 0.8},
	&"torso": {"bones": ["Hips", "Spine", "Chest", "Neck", "L_Shoulder", "R_Shoulder"], "share": 0.0},
}
const TENTACLES := 8

var enabled := false
var owner_body: Node3D
var skeleton: Skeleton3D
var world_scale := 1.0
var parts: Dictionary = {}
var _entries: Array = []
var _data: Dictionary = {}
var _wounds := PackedVector4Array()
var _wound_cursor := 0
var _modifier: SkeletonModifier3D
var _hitboxes: Dictionary = {}
var _cap_material: StandardMaterial3D


# strength: durability budget (usually the owner's max health scaled by size).
func setup(body_owner: Node3D, visual_root: Node3D, strength: float) -> bool:
	owner_body = body_owner
	var skeletons := visual_root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return false
	skeleton = skeletons[0] as Skeleton3D
	for node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.mesh is ArrayMesh:
			continue
		if mesh_instance.has_meta("body_part_cap"):
			continue
		var originals: Array = []
		for surface in mesh_instance.mesh.get_surface_count():
			originals.append(mesh_instance.get_active_material(surface))
		var data := MESH.prepare(mesh_instance, skeleton)
		if data.is_empty():
			continue
		var materials: Array = []
		for surface in mesh_instance.mesh.get_surface_count():
			var material := MESH.wound_material(originals[surface] if surface < originals.size() else null)
			mesh_instance.set_surface_override_material(surface, material)
			materials.append(material)
		_entries.append({"instance": mesh_instance, "data": data, "materials": materials})
	if _entries.is_empty():
		return false
	_data = _entries[0].data
	_wounds.resize(MAX_WOUNDS)
	_build_parts(strength)
	_modifier = MODIFIER.new()
	_modifier.name = "Dismember"
	skeleton.add_child(_modifier)
	world_scale = skeleton.global_basis.get_scale().x
	enabled = not parts.is_empty()
	return enabled


func _build_parts(strength: float) -> void:
	var definitions := {}
	if skeleton.find_bone("T0_A") >= 0:
		for index in TENTACLES:
			definitions[StringName("tentacle_%d" % index)] = {"bones": ["T%d_A" % index, "T%d_B" % index], "share": 0.3}
		definitions[TORSO] = {"bones": ["Hips", "Body", "Crown"], "share": 0.0}
	else:
		definitions = HUMANOID_PARTS
	for part: StringName in definitions:
		var definition: Dictionary = definitions[part]
		var bones := PackedInt32Array()
		for bone_name: String in definition.bones:
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				bones.append(bone)
		if bones.is_empty():
			continue
		var segments: Array = []
		for index in bones.size():
			var bone := bones[index]
			var child: Variant = null
			if index + 1 < bones.size() and skeleton.get_bone_parent(bones[index + 1]) == bone:
				child = MESH.joint(_data, bones[index + 1], skeleton)
			elif part == TORSO:
				child = _torso_child_joint(bone)
			var stats := MESH.bone_stats(_data, bone, child, skeleton)
			segments.append({"bone": bone, "start": stats.start, "end": stats.end, "radius": stats.radius})
		var durability := strength * float(definition.share)
		parts[part] = {
			"bones": bones, "segments": segments, "max_hp": durability, "hp": durability,
			"severable": part != TORSO, "severed": false,
		}


func _torso_child_joint(bone: int) -> Variant:
	for child in skeleton.get_bone_children(bone):
		var part_name := skeleton.get_bone_name(child)
		if part_name in ["Spine", "Chest", "Neck", "Head", "Body", "Crown", "L_UpperArm", "R_UpperArm"]:
			return MESH.joint(_data, child, skeleton)
	return null


func is_severed(part: StringName) -> bool:
	return parts.has(part) and bool(parts[part].severed)


func remaining(prefix: String) -> int:
	var count := 0
	for part: StringName in parts:
		if String(part).begins_with(prefix) and not bool(parts[part].severed):
			count += 1
	return count


func part_ratio(part: StringName) -> float:
	if not parts.has(part) or float(parts[part].max_hp) <= 0.0:
		return 1.0
	return float(parts[part].hp) / float(parts[part].max_hp)


func severable_parts() -> Array[StringName]:
	var result: Array[StringName] = []
	for part: StringName in parts:
		if bool(parts[part].severable) and not bool(parts[part].severed):
			result.append(part)
	return result


# Body part a bullet travelling along `direction` through `hit_position` struck.
func pick_part(hit_position: Vector3, direction: Vector3) -> StringName:
	if not enabled:
		return TORSO
	var ray := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var origin := hit_position - ray * 4.0
	var best: StringName = TORSO
	var best_score := 2.6
	for part: StringName in parts:
		if bool(parts[part].severed):
			continue
		for segment: Dictionary in parts[part].segments:
			var a := _world(segment.bone, segment.start)
			var b := _world(segment.bone, segment.end)
			var score := MESH.ray_segment_distance(origin, ray, a, b) / maxf(float(segment.radius) * world_scale, 0.02)
			if part == TORSO:
				score *= 1.15
			if score < best_score:
				best_score = score
				best = part
	return best


# Paints a bullet wound on `part` where the shot entered the skin.
func wound(part: StringName, hit_position: Vector3, direction: Vector3, world_radius: float) -> void:
	if not enabled or not parts.has(part):
		return
	var ray := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var origin := hit_position - ray * 4.0
	var chosen: Dictionary = {}
	var best := INF
	for segment: Dictionary in parts[part].segments:
		var distance := MESH.ray_segment_distance(origin, ray, _world(segment.bone, segment.start), _world(segment.bone, segment.end))
		if distance < best:
			best = distance
			chosen = segment
	if chosen.is_empty():
		return
	var a := _world(chosen.bone, chosen.start)
	var b := _world(chosen.bone, chosen.end)
	var closest := a
	var nearest := INF
	for step in 9:
		var point := a.lerp(b, float(step) / 8.0)
		var along := maxf(0.0, (point - origin).dot(ray))
		var distance := point.distance_to(origin + ray * along)
		if distance < nearest:
			nearest = distance
			closest = point
	var entry := closest - ray * float(chosen.radius) * world_scale * 0.9
	add_rest_wound(_to_rest(chosen.bone, entry), world_radius / maxf(world_scale, 0.01))


func add_rest_wound(rest_position: Vector3, rest_radius: float) -> void:
	if not enabled:
		return
	_wounds[_wound_cursor] = Vector4(rest_position.x, rest_position.y, rest_position.z, rest_radius)
	_wound_cursor = (_wound_cursor + 1) % MAX_WOUNDS
	_push_wounds()


func _push_wounds() -> void:
	for entry: Dictionary in _entries:
		for material: ShaderMaterial in entry.materials:
			material.set_shader_parameter("wounds", _wounds)


# Returns true when this damage severs the part.
func damage_part(part: StringName, amount: float) -> bool:
	if not enabled or not parts.has(part) or not bool(parts[part].severable) or bool(parts[part].severed):
		return false
	parts[part].hp = float(parts[part].hp) - maxf(amount, 0.0)
	return float(parts[part].hp) <= 0.0


# Collapses the part on the body, leaves a bleeding stump and (optionally)
# throws the part away as a physics piece. Returns the piece or null.
func sever(part: StringName, direction: Vector3, spawn_piece := true) -> RigidBody3D:
	if not enabled or not parts.has(part) or bool(parts[part].severed) or not bool(parts[part].severable):
		return null
	var info: Dictionary = parts[part]
	info.severed = true
	info.hp = 0.0
	var root: int = info.bones[0]
	var root_segment: Dictionary = info.segments[0]
	var joint_world := _world(root, root_segment.start)
	var piece: RigidBody3D = null
	if spawn_piece:
		piece = _spawn_piece(part, info, joint_world, direction)
	_modifier.severed.append(root)
	add_rest_wound(root_segment.start, float(root_segment.radius) * 1.35)
	_add_stump(root, joint_world, float(root_segment.radius), spawn_piece)
	_remove_hitboxes(part)
	part_severed.emit(part, piece)
	return piece


func _spawn_piece(part: StringName, info: Dictionary, joint_world: Vector3, direction: Vector3) -> RigidBody3D:
	var entry: Dictionary = _entries[0]
	var materials: Array = []
	for material: ShaderMaterial in entry.materials:
		var copy := material.duplicate() as ShaderMaterial
		var piece_wounds := _wounds.duplicate()
		var root_segment: Dictionary = info.segments[0]
		piece_wounds[_wound_cursor] = Vector4(root_segment.start.x, root_segment.start.y, root_segment.start.z, float(root_segment.radius) * 1.25)
		copy.set_shader_parameter("wounds", piece_wounds)
		materials.append(copy)
	var built := MESH.build_piece(entry.data, info.bones, skeleton, materials)
	if built.is_empty():
		return null
	var piece := SEVERED.new()
	piece.name = "Severed_" + String(part)
	piece.part_name = part
	var visual := MeshInstance3D.new()
	visual.mesh = built.mesh
	piece.add_child(visual)
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = built.points
	shape.shape = hull
	piece.add_child(shape)
	var bounds := AABB(built.points[0], Vector3.ZERO)
	for point in built.points:
		bounds = bounds.expand(point)
	piece.mass = clampf(bounds.size.x * bounds.size.y * bounds.size.z * 120.0, 0.3, 25.0)
	var cap_offset: Vector3 = joint_world - built.center
	_attach_cap(piece, cap_offset, float(info.segments[0].radius) * world_scale, cap_offset)
	var parent := _piece_parent()
	if parent == null:
		piece.free()
		return null
	piece.transform = Transform3D(Basis.IDENTITY, parent.global_transform.affine_inverse() * built.center)
	parent.add_child(piece)
	var push := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
	var inherited := Vector3.ZERO
	if owner_body is CharacterBody3D:
		inherited = (owner_body as CharacterBody3D).velocity * 0.6
	piece.linear_velocity = inherited + push * randf_range(2.2, 3.6) + Vector3.UP * randf_range(1.2, 2.4) + cap_offset.normalized() * -0.6
	piece.angular_velocity = Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7))
	piece.start_bleeding(cap_offset, cap_offset.normalized(), 0.8)
	return piece


func _piece_parent() -> Node3D:
	var parent := owner_body.get_parent() as Node3D
	return parent if parent != null else owner_body


func _add_stump(root: int, joint_world: Vector3, rest_radius: float, bleed: bool) -> void:
	var parent_bone := skeleton.get_bone_parent(root)
	if parent_bone < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "Stump_" + skeleton.get_bone_name(root)
	attachment.bone_idx = parent_bone
	skeleton.add_child(attachment)
	var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(parent_bone)
	var local := bone_world.affine_inverse() * joint_world
	var holder := Node3D.new()
	holder.position = local
	attachment.add_child(holder)
	var outward := local.normalized() if local.length_squared() > 0.0001 else Vector3.UP
	_attach_cap(holder, Vector3.ZERO, rest_radius, outward)
	if bleed:
		FX.bleed(holder, Vector3.ZERO, outward, 3.5, 1.0)


# A flattened wet disc closing the cut, its flat side facing along `axis`.
func _attach_cap(parent: Node3D, offset: Vector3, radius: float, axis: Vector3) -> void:
	if _cap_material == null:
		_cap_material = StandardMaterial3D.new()
		_cap_material.albedo_color = Color(0.3, 0.02, 0.02)
		_cap_material.roughness = 0.25
	var cap := MeshInstance3D.new()
	cap.set_meta("body_part_cap", true)
	var sphere := SphereMesh.new()
	sphere.radius = maxf(radius * 0.6, 0.012)
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.material = _cap_material
	cap.mesh = sphere
	var up := axis.normalized() if axis.length_squared() > 0.0001 else Vector3.UP
	cap.transform = Transform3D(Basis(Quaternion(Vector3.UP, up)) * Basis.from_scale(Vector3(1.0, 0.4, 1.0)), offset)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(cap)


# Bullet-only volumes on every remaining part so a corpse stays shootable.
func enable_corpse_hitboxes() -> void:
	if not enabled:
		return
	for part: StringName in parts:
		if bool(parts[part].severed) or _hitboxes.has(part):
			continue
		var nodes: Array = []
		for segment: Dictionary in parts[part].segments:
			var bone: int = segment.bone
			var attachment := BoneAttachment3D.new()
			attachment.name = "Hitbox_" + skeleton.get_bone_name(bone)
			attachment.bone_idx = bone
			skeleton.add_child(attachment)
			var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			var to_local := bone_world.affine_inverse()
			var start: Vector3 = to_local * _world(bone, segment.start)
			var finish: Vector3 = to_local * _world(bone, segment.end)
			var hitbox := HITBOX.new()
			hitbox.parts = self
			hitbox.part = part
			var shape_node := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			var span := start.distance_to(finish)
			capsule.radius = maxf(float(segment.radius), 0.03)
			capsule.height = span + capsule.radius * 2.0
			shape_node.shape = capsule
			var axis := (finish - start).normalized() if span > 0.001 else Vector3.UP
			shape_node.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), (start + finish) * 0.5)
			hitbox.add_child(shape_node)
			attachment.add_child(hitbox)
			nodes.append(attachment)
		_hitboxes[part] = nodes


func remove_corpse_hitboxes() -> void:
	for part: StringName in _hitboxes.keys():
		_remove_hitboxes(part)


func _remove_hitboxes(part: StringName) -> void:
	for node: Node in _hitboxes.get(part, []):
		if is_instance_valid(node):
			node.queue_free()
	_hitboxes.erase(part)


# Called by corpse hit volumes.
func hit_corpse(part: StringName, damage: float, hit_position: Vector3, direction: Vector3, weapon: String) -> void:
	wound(part, hit_position, direction, wound_radius(weapon))
	if owner_body != null and owner_body.has_method("on_corpse_part_hit"):
		owner_body.call("on_corpse_part_hit", part, damage, hit_position, direction, weapon)
	FX.spray(_piece_parent(), hit_position, direction, 12, 0.9)
	if damage_part(part, damage):
		sever(part, direction)


static func wound_radius(weapon: String) -> float:
	match weapon:
		"SHOTGUN":
			return 0.045
		"UZI":
			return 0.04
		"GRENADE":
			return 0.12
	return 0.055


func _world(bone: int, rest_point: Vector3) -> Vector3:
	var bind: Transform3D = (_data.binds as Dictionary).get(bone, skeleton.get_bone_global_rest(bone).affine_inverse())
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone) * bind * rest_point


func _to_rest(bone: int, world_point: Vector3) -> Vector3:
	var bind: Transform3D = (_data.binds as Dictionary).get(bone, skeleton.get_bone_global_rest(bone).affine_inverse())
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone) * bind).affine_inverse() * world_point
