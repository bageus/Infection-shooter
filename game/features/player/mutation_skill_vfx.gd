extends Node
## Procedural mutation skill presentation: casts and buffs, the Predator Dash
## speed trail, and
## the body overlay for Bone Armor, Hardened Tissue and Berserk (aura and red
## mask eyes). Gameplay stays in mutation_skill_effects.gd, which reports here.

const DASH_TRAIL := preload("res://game/features/player/dash_trail.gd")
const RANGE_DOME := preload("res://game/features/player/range_dome.gd")
const PROCEDURAL := preload("res://game/features/player/skill_fx/procedural_skill_fx.gd")
## Range dome colours per skill area.
const BLOOD_RANGE := Color(0.85, 0.08, 0.1)
const STORM_RANGE := Color(0.25, 0.65, 1.0)
const ACID_RANGE := Color(0.35, 0.95, 0.2)
const SPORE_RANGE := Color(0.75, 0.9, 0.2)
const BLADE_RANGE := Color(0.5, 0.95, 1.0)
const SKIN_SHADER := preload("res://game/features/player/mutation_skin.gdshader")
const AURA_SHADER := preload("res://game/features/player/berserk_aura.gdshader")
const EYES_SHADER := preload("res://game/features/player/berserk_eyes.gdshader")
# Eye glows in front of the head bone, in metres: forward, up, half spacing.
const EYE_OFFSET := Vector3(0.12, 0.03, 0.045)
const EYE_SIZE := 0.13
const SHIELD_COOLDOWN := 0.6
const OVERLAY_FADE_SPEED := 3.0
const STRIKE_LENGTH := 2.6
const STRIKE_BACK := 0.8
const STRIKE_SHARDS := 6
const STRIKE_COLOR := Color(1.0, 0.4, 0.14)

var player: Node3D
var effects_root: Node3D
var _loops := {}
var _domes := {}
var _skin: ShaderMaterial
var _aura: ShaderMaterial
var _eyes: ShaderMaterial
var _eye_mount: Node3D
var _skin_meshes: Array[MeshInstance3D] = []
var _targets := {"metal": 0.0, "bone": 0.0, "eyes": 0.0}
var _values := {"metal": 0.0, "bone": 0.0, "eyes": 0.0}
var _shield_ready := 0.0


func setup(host: Node3D) -> void:
	name = "SkillVfx"
	player = host
	_build_skin()
	_build_eyes()
	set_process(false)


func configure_world(container: Node3D) -> void:
	effects_root = container


# --- Casts -------------------------------------------------------------------

## Blood Burst: spikes thrown out around the player.
func spike_burst(center: Vector3, radius: float) -> void:
	RANGE_DOME.spawn(_world(), center, radius, BLOOD_RANGE, 0.6)
	PROCEDURAL.spike_burst(_world(), center, radius)

## Retaliation: a stunning electric ring.
func electric_pulse(center: Vector3, radius: float) -> void:
	RANGE_DOME.spawn(_world(), center, radius, STORM_RANGE, 0.5)
	PROCEDURAL.electric_pulse(_world(), center, radius)

## Discharge: one lightning link from each point to the next.
func chain_lightning(points: Array[Vector3]) -> void:
	PROCEDURAL.chain_lightning(_world(), points)

## Acid Spit: a pool of acid lying for `seconds`.
func acid_pool(center: Vector3, radius: float, seconds: float) -> Node3D:
	RANGE_DOME.spawn(_world(), center, radius, ACID_RANGE, seconds)
	return PROCEDURAL.acid_pool(_world(), center, radius, seconds)

## Spore Cocoon: the cocoon swells for `fuse` seconds, then bursts.
func spore_cocoon(center: Vector3, radius: float, fuse: float) -> void:
	# The dome marks where the spores will land for the fuse and the burst.
	RANGE_DOME.spawn(_world(), center, radius, SPORE_RANGE, fuse + 0.5)
	PROCEDURAL.spore_cocoon(_world(), center, radius, fuse)


## Claws: a slash on the struck enemy.
func claw_slash(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	var height := 1.1 * (enemy.get_node("Body") as Node3D).scale.y if enemy.has_node("Body") else 1.1
	PROCEDURAL.claw_slash(_world(), enemy.global_position + Vector3.UP * height)

## Temporary armor gained or soaking a hit: the shield dome flashes once.
func energy_shield() -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now < _shield_ready:
		return
	_shield_ready = now + SHIELD_COOLDOWN
	PROCEDURAL.energy_shield(player, player.global_position)

## Second Heart: a beating heart above the player for a while.
func heartbeat(seconds: float = 2.4) -> void:
	PROCEDURAL.heartbeat(player, player.global_position + Vector3.UP * 2.5, seconds)

## Predator Dash: speed streaks behind the body for the dash.
func dash_trail(seconds: float) -> void:
	DASH_TRAIL.start(_world(), player, seconds)


# --- Buffs -------------------------------------------------------------------

func buff_started(skill_id: String) -> void:
	match skill_id:
		"storm_pulse":
			_loop(skill_id, 4.0, STORM_RANGE)
		"bone_blades":
			_loop(skill_id, 1.7, BLADE_RANGE)
		"berserk":
			_targets["eyes"] = 1.0
			_set_aura(true)
			set_process(true)


func buff_ended(skill_id: String) -> void:
	if _loops.has(skill_id):
		var loop: WeakRef = _loops[skill_id]
		_loops.erase(skill_id)
		_stop(loop, 0.35)
	if _domes.has(skill_id):
		var dome: WeakRef = _domes[skill_id]
		_domes.erase(skill_id)
		_stop(dome, 0.35)
	if skill_id == "berserk":
		_targets["eyes"] = 0.0
		set_process(true)


## Passive body changes follow the mutation tree.
func set_passives(bone_armor: bool, hardened: bool) -> void:
	_targets["bone"] = 1.0 if bone_armor else 0.0
	_targets["metal"] = 1.0 if hardened else 0.0
	set_process(true)


func overlay_value(key: String) -> float:
	return float(_values.get(key, 0.0))


func aura_visible() -> bool:
	return _aura != null and _skin != null and _skin.next_pass == _aura


func has_loop(skill_id: String) -> bool:
	return _loops.has(skill_id) and (_loops[skill_id] as WeakRef).get_ref() != null


func has_range_dome(skill_id: String) -> bool:
	return _domes.has(skill_id) and (_domes[skill_id] as WeakRef).get_ref() != null


func _process(delta: float) -> void:
	if _skin == null:
		set_process(false)
		return
	var settled := true
	for key: String in _values:
		var value := move_toward(float(_values[key]), float(_targets[key]), delta * OVERLAY_FADE_SPEED)
		_values[key] = value
		settled = settled and is_equal_approx(value, float(_targets[key]))
	_skin.set_shader_parameter(&"metal", float(_values["metal"]))
	_skin.set_shader_parameter(&"bone", float(_values["bone"]))
	var rage := float(_values["eyes"])
	if _aura != null:
		_aura.set_shader_parameter(&"intensity", rage)
	if _eyes != null:
		_eyes.set_shader_parameter(&"intensity", rage)
		_eye_mount.visible = rage > 0.001
	if is_zero_approx(float(_values["eyes"])) and float(_targets["eyes"]) == 0.0:
		_set_aura(false)
	_apply_overlay()
	if settled:
		set_process(false)


# --- Helpers -----------------------------------------------------------------

func _world() -> Node:
	return effects_root if is_instance_valid(effects_root) else player.get_parent()


func _loop(skill_id: String, radius: float, range_tint: Color) -> void:
	if has_loop(skill_id):
		return
	var node := PROCEDURAL.storm_field(player, player.global_position, radius) if skill_id == "storm_pulse" else PROCEDURAL.blade_orbit(player, player.global_position, radius)
	if node != null:
		_loops[skill_id] = weakref(node)
	var dome: MeshInstance3D = null if has_range_dome(skill_id) else RANGE_DOME.spawn(player, player.global_position, radius, range_tint)
	if dome != null:
		_domes[skill_id] = weakref(dome)


func _stop(node_ref: WeakRef, fade: float) -> void:
	var node := node_ref.get_ref() as Node
	if is_instance_valid(node):
		node.call("stop", fade)


func _build_skin() -> void:
	var body := player.get_node_or_null("Body") as Node3D
	if body == null:
		return
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var source := mesh.get_active_material(0) as BaseMaterial3D
		if source == null or source.albedo_texture == null:
			continue
		if _skin == null:
			_skin = ShaderMaterial.new()
			_skin.shader = SKIN_SHADER
			_skin.set_shader_parameter(&"base_albedo", source.albedo_texture)
		_skin_meshes.append(mesh)


# The overlay is attached only while something shows: no extra pass otherwise.
func _apply_overlay() -> void:
	if _skin == null:
		return
	var showing := false
	for key: String in _values:
		showing = showing or float(_values[key]) > 0.001 or float(_targets[key]) > 0.0
	for mesh in _skin_meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _skin if showing else null


# Two soft red glows riding the head bone just in front of the mask.
func _build_eyes() -> void:
	var body := player.get_node_or_null("Body") as Node3D
	if body == null:
		return
	var skeletons := body.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var head := skeleton.find_bone("Head")
	if head < 0:
		return
	var mount := BoneAttachment3D.new()
	mount.name = "BerserkEyes"
	mount.bone_name = "Head"
	skeleton.add_child(mount)
	_eye_mount = mount
	mount.visible = false
	_eyes = ShaderMaterial.new()
	_eyes.shader = EYES_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * EYE_SIZE
	# Offsets are in metres; the skeleton may be scaled. Model +Z is its face.
	var unit := 1.0 / maxf(skeleton.global_basis.get_scale().x, 0.0001)
	var rest := skeleton.get_bone_global_rest(head)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = quad
		eye.material_override = _eyes
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.scale = Vector3.ONE * unit
		var point := rest.origin + Vector3(EYE_OFFSET.z * side, EYE_OFFSET.y, EYE_OFFSET.x) * unit
		eye.position = rest.affine_inverse() * point
		eye.set_instance_shader_parameter(&"phase", side * 1.7)
		mount.add_child(eye)


func eyes_visible() -> bool:
	return is_instance_valid(_eye_mount) and _eye_mount.visible


func _set_aura(enabled: bool) -> void:
	if _skin == null:
		return
	if enabled and _aura == null:
		_aura = ShaderMaterial.new()
		_aura.shader = AURA_SHADER
	_skin.next_pass = _aura if enabled else null


func active_aura(id: String, radius: float, duration: float) -> void:
	var color := STORM_RANGE if id == "storm_pulse" else BLOOD_RANGE
	var dome := RANGE_DOME.spawn(player, player.global_position, radius, color, duration)
	_domes[id] = weakref(dome)
	if id == "storm_pulse":
		var field := PROCEDURAL.storm_field(player, player.global_position, radius)
		if field != null:
			_loops[id] = weakref(field)


## Power Strike: an orange-red fist starts behind the player, speeds forward,
## shatters on arrival and lights the floor it reached. Local -Z is forward.
func power_strike(center: Vector3, direction: Vector3) -> void:
	var fx := Node3D.new()
	fx.name = "PowerStrikeFx"
	_world().add_child(fx)
	fx.global_position = center + Vector3.UP * 0.05
	fx.look_at(center + direction, Vector3.UP)
	var floor_zone := ImmediateMesh.new()
	floor_zone.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-0.5, 0.03, 0.2), Vector3(0.5, 0.03, 0.2), Vector3(1.5, 0.03, -STRIKE_LENGTH), Vector3(-0.5, 0.03, 0.2), Vector3(1.5, 0.03, -STRIKE_LENGTH), Vector3(-1.5, 0.03, -STRIKE_LENGTH)]:
		floor_zone.surface_add_vertex(point)
	floor_zone.surface_end()
	var zone := _strike_part(floor_zone, _strike_material(0.5))
	fx.add_child(zone)
	var fist := Node3D.new()
	fist.position = Vector3(0, 0.9, STRIKE_BACK)
	fx.add_child(fist)
	var glow := _strike_material(0.6)
	# Offset in metres from the fist, then blob radius. Trail blobs sit behind.
	for blob in [[Vector3.ZERO, 0.4], [Vector3(0.25, 0.1, -0.3), 0.3], [Vector3(-0.25, -0.1, -0.25), 0.32], [Vector3(0.1, -0.2, -0.5), 0.26], [Vector3(-0.1, 0.2, -0.6), 0.24], [Vector3(0, 0, 0.5), 0.26], [Vector3(0, 0, 0.9), 0.18]]:
		var mesh := SphereMesh.new()
		mesh.radius = blob[1]
		mesh.height = blob[1] * 2.0
		fist.add_child(_strike_part(mesh, glow, blob[0]))
	var lunge := fx.create_tween()
	lunge.tween_property(fist, "position", Vector3(0, 0.9, -STRIKE_LENGTH - STRIKE_BACK), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	lunge.tween_property(glow, "albedo_color:a", 0.0, 0.08)
	lunge.tween_callback(fist.queue_free)
	lunge.tween_callback(_strike_shatter.bind(fx))
	var floor_fade := fx.create_tween()
	floor_fade.tween_interval(0.2)
	floor_fade.tween_property(zone.material_override, "albedo_color:a", 0.0, 0.6)
	var cleanup := fx.create_tween()
	cleanup.tween_interval(1.0)
	cleanup.tween_callback(fx.queue_free)


func _strike_shatter(fx: Node3D) -> void:
	for i in STRIKE_SHARDS:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * randf_range(0.08, 0.14)
		var material := _strike_material(0.9)
		var shard := _strike_part(mesh, material, Vector3(0, 0.9, -STRIKE_LENGTH))
		fx.add_child(shard)
		var landing := Vector3(randf_range(-0.7, 0.7), 0.05, -STRIKE_LENGTH + randf_range(-0.6, 0.3))
		var tween := shard.create_tween()
		tween.tween_property(shard, "position", landing, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(material, "albedo_color:a", 0.0, 0.2)
		tween.tween_callback(shard.queue_free)
	for i in 3:
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		var material := _strike_material(0.35, Color(1.0, 0.55, 0.25))
		var puff := _strike_part(mesh, material, Vector3(randf_range(-0.4, 0.4), 0.3, -STRIKE_LENGTH + randf_range(-0.3, 0.1)))
		fx.add_child(puff)
		var tween := puff.create_tween()
		tween.tween_property(puff, "scale", Vector3.ONE * 2.5, 0.35)
		tween.parallel().tween_property(material, "albedo_color:a", 0.0, 0.35)
		tween.tween_callback(puff.queue_free)


func _strike_part(mesh: Mesh, material: StandardMaterial3D, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


func _strike_material(alpha: float, color: Color = STRIKE_COLOR) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color, alpha)
	return material
