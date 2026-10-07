extends Node
## Presentation of mutation skills on and around the player: the supplied
## FX_skills sheets for casts and buffs, the Predator Dash speed trail, and
## the body overlay for Bone Armor, Hardened Tissue and Berserk (aura and red
## mask eyes). Gameplay stays in mutation_skill_effects.gd, which reports here.

const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const DASH_TRAIL := preload("res://game/features/player/dash_trail.gd")
const RANGE_DOME := preload("res://game/features/player/range_dome.gd")
## The drawn spikes reach past the burst, so they play at this share of it.
const SPIKE_VISUAL_SHARE := 0.55
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
const GROUND_LIFT := 0.05
const SHIELD_COOLDOWN := 0.6
const OVERLAY_FADE_SPEED := 3.0

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
	_ground(ATLASES.SPIKE_BURST, center, radius * SPIKE_VISUAL_SHARE, {"additive": 0.15})
	RANGE_DOME.spawn(_world(), center, radius, BLOOD_RANGE, 0.6)


## Retaliation: a stunning electric ring.
func electric_pulse(center: Vector3, radius: float) -> void:
	_ground(ATLASES.ELECTRIC_PULSE, center, radius, {"additive": 1.0, "brightness": 1.3})
	RANGE_DOME.spawn(_world(), center, radius, STORM_RANGE, 0.5)


## Discharge: one lightning link from each point to the next.
func chain_lightning(points: Array[Vector3]) -> void:
	var atlas := ATLASES.CHAIN_LIGHTNING
	for i in points.size() - 1:
		var from := points[i] + Vector3.UP * 1.0
		var to := points[i + 1] + Vector3.UP * 1.0
		var length := from.distance_to(to)
		if length < 0.2:
			continue
		FLIPBOOK.spawn(_world(), atlas, from, length / float(atlas["reach"]), {
			"additive": 1.0, "brightness": 1.2, "axis": to - from,
			"atlas_angle": float(atlas["jet_angle"]), "speed": 1.0 + i * 0.15,
		})


## Acid Spit: a pool of acid lying for `seconds`.
func acid_pool(center: Vector3, radius: float, seconds: float) -> void:
	var atlas := ATLASES.ACID_PUDDLES
	_ground(atlas, center, radius, {"frame": randi() % int(atlas["frames"]), "lifetime": seconds, "fade_out": 0.8, "opacity": 0.9})
	RANGE_DOME.spawn(_world(), center, radius, ACID_RANGE, seconds)


## Spore Cocoon: the cocoon swells for `fuse` seconds, then bursts.
func spore_cocoon(center: Vector3, radius: float, fuse: float) -> void:
	var atlas := ATLASES.SPORE_COCOON
	var swell := 0.0
	var spans: Array = atlas["durations"]
	for i in int(atlas["fuse_frames"]):
		swell += float(spans[i])
	# The cloud reaches the poison radius; the cocoon itself stays smaller.
	FLIPBOOK.spawn(_world(), atlas, center, ATLASES.size_for_radius(atlas, radius * 0.75), {
		"billboard": true, "speed": swell / maxf(fuse, 0.1), "fade_out": 0.4,
	})
	# The dome marks where the spores will land for the fuse and the burst.
	RANGE_DOME.spawn(_world(), center, radius, SPORE_RANGE, fuse + 0.5)


## Claws: a slash on the struck enemy.
func claw_slash(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	var height := 1.1 * (enemy.get_node("Body") as Node3D).scale.y if enemy.has_node("Body") else 1.1
	FLIPBOOK.spawn(_world(), ATLASES.CLAW_SLASH, enemy.global_position + Vector3.UP * height, 2.0, {
		"additive": 0.6, "brightness": 1.2, "spin": randf_range(-0.5, 0.5),
	})


## Temporary armor gained or soaking a hit: the shield dome flashes once.
func energy_shield() -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now < _shield_ready:
		return
	_shield_ready = now + SHIELD_COOLDOWN
	var atlas := ATLASES.ENERGY_SHIELD
	FLIPBOOK.spawn(player, atlas, player.global_position + Vector3.UP * 0.02, ATLASES.size_for_radius(atlas, 0.95), {
		"additive": 0.7, "fade_out": 0.25, "opacity": 0.8,
	})


## Second Heart: a beating heart above the player for a while.
func heartbeat(seconds: float = 2.4) -> void:
	var heart := FLIPBOOK.spawn(player, ATLASES.HEARTBEAT, player.global_position + Vector3.UP * 2.5, 1.0, {"cycle": true})
	if heart != null:
		get_tree().create_timer(seconds, false).timeout.connect(_stop.bind(weakref(heart), 0.35))


## Predator Dash: speed streaks behind the body for the dash.
func dash_trail(seconds: float) -> void:
	DASH_TRAIL.start(_world(), player, seconds)


# --- Buffs -------------------------------------------------------------------

func buff_started(skill_id: String) -> void:
	match skill_id:
		"storm_pulse":
			_loop(skill_id, ATLASES.ELECTRIC_FIELD, 4.0, {"additive": 1.0, "opacity": 0.85}, STORM_RANGE)
		"bone_blades":
			_loop(skill_id, ATLASES.BLADE_ORBIT, 1.7, {"additive": 0.35}, BLADE_RANGE)
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


func _ground(atlas: Dictionary, center: Vector3, radius: float, options: Dictionary) -> MeshInstance3D:
	var settings := options.duplicate()
	settings["ground"] = true
	return FLIPBOOK.spawn(_world(), atlas, center + Vector3.UP * GROUND_LIFT, ATLASES.size_for_radius(atlas, radius), settings)


# A looping sheet that rides on the player, with its range dome, until the
# buff ends.
func _loop(skill_id: String, atlas: Dictionary, radius: float, options: Dictionary, range_tint: Color) -> void:
	if has_loop(skill_id):
		return
	var settings := options.duplicate()
	settings["ground"] = true
	settings["cycle"] = true
	var node := FLIPBOOK.spawn(player, atlas, player.global_position + Vector3.UP * GROUND_LIFT, ATLASES.size_for_radius(atlas, radius), settings)
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
