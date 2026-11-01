extends Node
## Shared character animation playback (ADR-0001, ADR-0014, ADR-0015).

# Public animation_events_v1: emitted when an attack/death one-shot ends.
signal one_shot_finished(state: StringName)
# Public animation_events_v1 addition (ADR-0018): a procedural-gait foot landed.
signal footstep(side: int, speed: float)

const MODEL_PROBE := preload("res://game/features/character_animation/animation_model_probe.gd")
const POSE := preload("res://game/features/character_animation/procedural_pose.gd")
const GAIT := preload("res://game/features/character_animation/procedural_gait.gd")
const HIT_REACTION := preload("res://game/features/character_animation/hit_reaction.gd")
const LEG_MOTION := preload("res://game/features/character_animation/leg_clip_motion.gd")
const CLIP_LOOKUP := preload("res://game/features/character_animation/clip_lookup.gd")
const OVERLAY := preload("res://game/features/character_animation/clip_overlay.gd")
const LEG_OVERLAY := preload("res://game/features/character_animation/leg_overlay.gd")
const STRIKE_POSE := preload("res://game/features/character_animation/strike_pose.gd")
const DODGE_ROLL := 0
const DODGE_STRAFE := 1
const STATE_ATTACK := &"attack"
const STATE_DEATH := &"death"
# Directional deaths (ADR-0034) fall back to the plain death clip.
const DEATH_STATES := [&"death", &"death_forward", &"death_back"]
const LOCOMOTION_TOKENS := {
	&"idle": ["idle", "stand"],
	&"walk": ["walk", "locomotion"],
	&"run": ["run", "sprint", "jog"],
}
const LOOPING_TOKENS := ["idle", "stand", "walk", "locomotion", "run", "sprint", "jog"]
const NON_LOOPING_TOKENS := ["attack", "death", "hit", "aim", "slam", "summon"]
const ONE_SHOT_TOKENS := {
	&"attack": ["attackleft", "attackright", "attack"],
	&"attack_left": ["attackleft", "attack"],
	&"attack_right": ["attackright", "attack"],
	&"death": ["death", "dead"],
	&"death_forward": ["deathforward", "death", "dead"],
	&"death_back": ["deathback", "death", "dead"],
	&"slam": ["slam"],
	&"summon": ["summon"],
	&"attack_crawl": ["crawlattack"],
}
# A strike lands this many seconds into a clip that names its strike_time.
const STRIKE_WINDUP := 0.35
const MAX_ATTACK_SPEED := 2.2
const FLINCH_SECONDS := 0.16
const MOVING_ATTACKS := [&"attack", &"attack_left", &"attack_right"]

@export var character_path: NodePath = NodePath("..")
@export var model_path: NodePath = NodePath("Body")
## Optional clip set that replaces the model's own clips (ADR-0016).
@export var animation_library: AnimationLibrary
@export var run_speed_threshold := 6.8
## A running character keeps the run clip down to this share of the threshold,
## so speed wobble around it does not flicker between walk and run.
@export_range(0.5, 1.0) var run_exit_ratio := 0.85
## Rebuild the legs with a speed-synchronised gait over the playing clip
## (for authored upper-body clips whose leg motion limps or slides).
@export var procedural_gait := false
## Retargeted hips-and-legs clips (run in eight directions, dodge roll and
## strafe jumps, ADR-0044); they replace the procedural gait and leave the arms
## and the weapon hold to the upper-body clips.
@export var leg_clips: AnimationLibrary
## Clips merged into the model's own default library (same names win), so a
## rebuilt model keeps authored extras such as the Mixamo set (ADR-0045).
@export var extra_clips: AnimationLibrary
## Playback speed is scaled by speed / reference while moving; 0 disables it.
@export var walk_reference_speed := 0.0
@export var run_reference_speed := 0.0
## Scales locomotion cycle playback on top of the speed-matched rate (1.2 = 20 % faster).
@export var locomotion_speed_multiplier := 1.0
## Player leg cycles only; upper-body playback and dodge duration remain authored.
@export var leg_playback_multiplier := 1.0:
	set(value):
		leg_playback_multiplier = clampf(value, 0.5, 2.0) if is_finite(value) else 1.0
		if legs != null:
			legs.set("playback_multiplier", leg_playback_multiplier)
## Visual pivot animated procedurally when the model has no AnimationPlayer.
@export var procedural_target_path: NodePath = NodePath("Body/Visual")
@export var procedural_bob_height := 0.06
@export var procedural_sway_degrees := 4.0
@export var procedural_lean_degrees := 8.0
@export var procedural_stride_hz := 2.2
@export var procedural_attack_seconds := 0.55
@export var procedural_attack_lunge := 0.28
@export var procedural_death_seconds := 1.2

var _active_requested := true
var defer_setup := false
var _prepared := false
var character: CharacterBody3D
var animation_player: AnimationPlayer
var gait: SkeletonModifier3D
var legs: SkeletonModifier3D
## Which dodge clips play_dodge uses: DODGE_ROLL (dive roll) or DODGE_STRAFE (strafe jump).
var dodge_style := DODGE_ROLL
var hit_reaction: SkeletonModifier3D
var overlay: SkeletonModifier3D
var strike: SkeletonModifier3D
var leg_overlay: SkeletonModifier3D
var _current := ""
var _animations: Dictionary = {}
var _locomotion: Dictionary = {}
var _clip_selector: Callable
var _missing_clips: Dictionary = {}
var _loops_configured := false
var _pose := POSE.new()
var _target: Node3D
var _rest := Transform3D.IDENTITY
var _phase := 0.0
var _time := 0.0
var _one_shot: StringName = &""
var _one_shot_elapsed := 0.0
var _one_shot_length := 0.0
var _dead := false
var _flinch_elapsed := -1.0
var _overlay_applied := false
var _attack_side := false
var _transition_legs := ""


# Public animation_selection_v1: optional presentation-only selector.
func configure_clip_selector(selector: Callable) -> void:
	var changed := _clip_selector != selector
	_clip_selector = selector
	if animation_player != null and selector.is_valid():
		if changed:
			_configure_looping_clips()
		_play_selected_clip()


# Public animation_events_v1: plays a non-looping attack, death or a skeletal
# special (slam, summon). Returns the duration in seconds, or 0.0 when nothing
# could be played. Death is final.
func play_one_shot(state: StringName) -> float:
	prepare_visual()
	if _dead or not ONE_SHOT_TOKENS.has(state):
		return 0.0
	if animation_player == null and state in [&"slam", &"summon"]:
		return 0.0
	var length := 0.0
	if animation_player != null:
		var clip := _pick_one_shot_clip(state)
		if clip.is_empty():
			return 0.0
		_current = clip
		var animation := animation_player.get_animation(clip)
		var scale := _strike_speed(animation)
		animation_player.speed_scale = scale
		animation_player.play(clip, 0.08)
		length = animation.length / scale
	elif _target != null:
		length = procedural_death_seconds if state in DEATH_STATES else procedural_attack_seconds
	else:
		return 0.0
	_one_shot = state
	_transition_legs = ""
	_one_shot_elapsed = 0.0
	_one_shot_length = length
	_dead = state in DEATH_STATES
	if _dead and leg_overlay != null:
		leg_overlay.call("stop")
	_pose.death_forward = state == &"death_forward"
	return length


# Public animation_events_v1 addition (ADR-0045): plays a clip by name once and
# emits one_shot_finished(name) when done; the character keeps its place. Returns
# the duration in seconds, 0.0 when the clip does not exist or the character is dead.
# With `leg_clip`, a moving character keeps that locomotion clip on its legs while
# the clip plays (posture changes on the run, ADR-0045).
func play_named_one_shot(clip_name: StringName, blend: float = 0.12, speed: float = 1.0, leg_clip: StringName = &"") -> float:
	if _dead or animation_player == null or not animation_player.has_animation(clip_name):
		return 0.0
	var animation := animation_player.get_animation(clip_name)
	_current = String(clip_name)
	animation_player.speed_scale = speed
	animation_player.play(clip_name, blend)
	_one_shot = clip_name
	_transition_legs = String(leg_clip) if animation_player.has_animation(leg_clip) else ""
	_one_shot_elapsed = 0.0
	_one_shot_length = animation.length / speed
	return _one_shot_length


# Public animation_events_v1 addition (ADR-0045): flinches the upper body with a
# clip (the legs keep their motion). False without that clip.
func play_overlay(clip_name: StringName) -> bool:
	if _dead or animation_player == null or not animation_player.has_animation(clip_name):
		return false
	if overlay == null:
		var skeletons := animation_player.get_parent().find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return false
		overlay = OVERLAY.new()
		overlay.name = "ClipOverlay"
		(skeletons[0] as Node).add_child(overlay)
	overlay.call("play", animation_player.get_animation(clip_name))
	return true


# Public animation_events_v1 addition (ADR-0066): a procedural melee strike,
# &"kick" (rear left leg) or &"punch" (left arm), over the playing clips. Returns
# its duration, 0.0 for an unknown kind, a dead body or a skeleton without the bones.
func play_strike(kind: StringName) -> float:
	prepare_visual()
	if _dead or animation_player == null:
		return 0.0
	if strike == null:
		var skeletons := animation_player.get_parent().find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return 0.0
		strike = STRIKE_POSE.new()
		strike.name = "StrikePose"
		(skeletons[0] as Node).add_child(strike)
	return float(strike.call("start", kind))


# Public animation_events_v1 addition (ADR-0066): true while a strike pose plays.
func is_striking() -> bool:
	return strike != null and bool(strike.call("is_playing"))


# Public animation_events_v1 addition (ADR-0045): length of a clip, 0.0 if unknown.
func clip_length(clip_name: StringName) -> float:
	return animation_player.get_animation(clip_name).length if animation_player != null and animation_player.has_animation(clip_name) else 0.0


# Public animation_events_v1 addition (ADR-0045): a clip's metadata (turn_yaw, yaw_curve, strike_time).
func clip_meta(clip_name: StringName, key: StringName, default: Variant = null) -> Variant:
	if animation_player == null or not animation_player.has_animation(clip_name):
		return default
	return animation_player.get_animation(clip_name).get_meta(key, default)


# Plays faster when the clip's strike lands later than the wind-up allows.
func _strike_speed(animation: Animation) -> float:
	var strike := float(animation.get_meta("strike_time", 0.0))
	return clampf(strike / STRIKE_WINDUP, 1.0, MAX_ATTACK_SPEED) if strike > 0.0 else 1.0


# Public animation_events_v1 addition (ADR-0044): plays the dodge clip for
# `duration` seconds toward a world-space direction, relative to the body.
# Returns false without leg clips. The roll turns the whole body along the
# dodge; the strafe jump keeps facing forward and jumps to the nearer side.
func play_dodge(world_direction: Vector3, duration: float) -> bool:
	if legs == null or _dead:
		return false
	var skeleton := legs.get_skeleton()
	var local := skeleton.global_basis.inverse() * Vector3(world_direction.x, 0.0, world_direction.z)
	if local.length_squared() < 0.0001:
		return false
	var heading := atan2(local.x, local.z)
	if dodge_style == DODGE_STRAFE:
		var side := PI * 0.5 if heading >= 0.0 else -PI * 0.5
		return bool(legs.call("start_dodge", "Dodge_Strafe_Left" if side > 0.0 else "Dodge_Strafe_Right", duration, heading - side))
	return bool(legs.call("start_dodge", "Dodge_Roll", duration, heading))


# Public animation_events_v1 addition (ADR-0044): true while a dodge clip plays.
func is_dodging() -> bool:
	return legs != null and bool(legs.call("is_dodging"))


# Public animation_events_v1: hit reaction. Skeletal models twist and rock the
# torso away from where the shot landed (hit_reaction_v1, ADR-0040); without a
# point and direction it rocks back. Models without a spine flinch as a whole.
func notify_hit(world_point: Vector3 = Vector3.ZERO, world_direction: Vector3 = Vector3.ZERO, strength: float = 1.0) -> void:
	if _target == null or _dead:
		return
	if hit_reaction != null:
		hit_reaction.call("push", world_point, world_direction, strength)
		return
	if animation_player != null and _flinch_elapsed < 0.0:
		# Skeletal visuals may be rotated by their owner; capture the pose now.
		_rest = _target.transform
	_flinch_elapsed = 0.0


# Public animation_events_v1: pause animation work for far or hidden characters.
func set_active(active: bool) -> void:
	_active_requested = active
	set_process(active and _prepared)
	if animation_player != null:
		animation_player.active = active
	if hit_reaction != null:
		hit_reaction.active = active
	# A paused (ragdolled or far) character must not keep stepping or flinching.
	if overlay != null:
		overlay.active = active
	if leg_overlay != null:
		leg_overlay.active = active
	if legs != null:
		legs.active = active
	if gait != null:
		gait.active = active


func _ready() -> void:
	if not defer_setup:
		prepare_visual()
	else:
		set_process(false)


func prepare_visual() -> void:
	if _prepared:
		return
	_prepared = true
	set_process(_active_requested)
	character = get_parent() as CharacterBody3D
	if character == null:
		character = get_node_or_null(character_path) as CharacterBody3D
	var model: Node = null
	if character != null:
		model = character.get_node_or_null(model_path)
	if model == null:
		return
	animation_player = MODEL_PROBE.find_animation_player(model)
	if animation_player != null:
		animation_player.active = _active_requested
		_apply_animation_library()
		_index_animations()
		_configure_looping_clips()
		_target = model as Node3D
		_pose.feet = Vector3(0.0, MODEL_PROBE.feet_height(model), 0.0)
		if leg_clips != null:
			_attach_legs(model)
		elif procedural_gait:
			_attach_gait(model)
		_attach_hit_reaction(model)
		set_active(_active_requested)
		_play_locomotion(&"idle", 0.0)
		return
	_target = character.get_node_or_null(procedural_target_path) as Node3D
	if _target == null:
		_target = model as Node3D
	if _target == null:
		return
	_rest = _target.transform
	_pose.feet = Vector3(0.0, MODEL_PROBE.feet_height(_target), 0.0)
	_pose.bob_height = procedural_bob_height
	_pose.sway_degrees = procedural_sway_degrees
	_pose.lean_degrees = procedural_lean_degrees
	_pose.stride_hz = procedural_stride_hz
	_pose.attack_duration = procedural_attack_seconds
	_pose.attack_lunge = procedural_attack_lunge
	_pose.death_duration = procedural_death_seconds


func _process(delta: float) -> void:
	if character == null:
		return
	_time += delta
	_advance_one_shot(delta)
	if _flinch_elapsed >= 0.0:
		_flinch_elapsed += delta
		if _flinch_elapsed >= FLINCH_SECONDS:
			_flinch_elapsed = -1.0
	var speed := Vector2(character.velocity.x, character.velocity.z).length()
	if animation_player != null:
		_process_skeletal(speed)
	elif _target != null:
		_process_procedural(speed, delta)


func _advance_one_shot(delta: float) -> void:
	if _one_shot.is_empty():
		return
	_one_shot_elapsed += delta
	if _one_shot_elapsed < _one_shot_length:
		return
	var finished := _one_shot
	_one_shot = &""
	_transition_legs = ""
	if finished not in DEATH_STATES:
		_current = ""
	one_shot_finished.emit(finished)


func _process_skeletal(speed: float) -> void:
	_apply_flinch_overlay()
	_update_attack_legs(speed)
	if not _one_shot.is_empty() or _dead:
		return
	if _play_selected_clip(speed):
		return
	var run_floor := run_speed_threshold * (run_exit_ratio if _current == _locomotion.get(&"run", "") else 1.0)
	if speed > run_floor or (speed > 0.15 and _locomotion.get(&"walk", "").is_empty()):
		_play_locomotion(&"run", speed)
	elif speed > 0.15:
		_play_locomotion(&"walk", speed)
	else:
		_play_locomotion(&"idle", speed)


func _process_procedural(speed: float, delta: float) -> void:
	var pose := Transform3D.IDENTITY
	if _dead:
		pose = _pose.death(1.0 if _one_shot.is_empty() else _one_shot_elapsed / _one_shot_length)
	elif not _one_shot.is_empty():
		pose = _pose.attack(_one_shot_elapsed / _one_shot_length)
	else:
		var reference := maxf(run_speed_threshold if run_reference_speed <= 0.0 else run_reference_speed, 0.1)
		_phase += delta * procedural_stride_hz * clampf(speed / reference, 0.0, 1.4)
		pose = _pose.locomotion(speed / reference, _phase, _time)
	if _flinch_elapsed >= 0.0:
		pose = pose * _pose.flinch(_flinch_elapsed, FLINCH_SECONDS)
	_target.transform = _rest * pose


func _apply_flinch_overlay() -> void:
	if _target == null:
		return
	if _flinch_elapsed >= 0.0:
		_target.transform = _rest * _pose.flinch(_flinch_elapsed, FLINCH_SECONDS)
		_overlay_applied = true
	elif _overlay_applied:
		_target.transform = _rest
		_overlay_applied = false


func _play_selected_clip(speed: float = 0.0) -> bool:
	if not _clip_selector.is_valid():
		return false
	var requested := StringName(_clip_selector.call())
	if animation_player.has_animation(requested):
		_play_clip(String(requested))
		# Cycles that name the ground speed they are paced for follow the actual speed.
		var reference := float(animation_player.get_animation(requested).get_meta("ref_speed", 0.0))
		var wanted := (clampf(speed / reference, 0.5, 1.8) if reference > 0.0 and speed > 0.15 else 1.0) * locomotion_speed_multiplier
		if not is_equal_approx(animation_player.speed_scale, wanted):
			animation_player.speed_scale = wanted
		return true
	if not requested.is_empty() and not _missing_clips.has(requested):
		_missing_clips[requested] = true
		push_warning("Character animation clip unavailable: %s" % requested)
	return false


# A moving attacker (or one changing posture on the run) keeps its legs on a
# locomotion cycle; the one-shot clip owns the rest.
func _update_attack_legs(speed: float) -> void:
	var state := &"run" if speed > run_speed_threshold or _locomotion.get(&"walk", "").is_empty() else &"walk"
	var clip: String = _transition_legs if not _transition_legs.is_empty() else _locomotion.get(state, "")
	var wanted := (_one_shot in MOVING_ATTACKS or not _transition_legs.is_empty()) and not _dead and leg_clips == null and not clip.is_empty()
	if leg_overlay == null and wanted and speed > 0.15:
		leg_overlay = LEG_OVERLAY.attach(animation_player.get_parent())
	if leg_overlay != null:
		leg_overlay.call("drive", animation_player.get_animation(clip) if wanted else null, _locomotion_scale(state if _transition_legs.is_empty() else &"run", speed), speed > 0.15)


func _locomotion_scale(state: StringName, speed: float) -> float:
	var reference := run_reference_speed if state == &"run" else walk_reference_speed
	return clampf(speed / reference, 0.5, 1.6) * locomotion_speed_multiplier if state != &"idle" and reference > 0.0 else 1.0


func _play_locomotion(state: StringName, speed: float) -> void:
	var clip: String = _locomotion.get(state, "")
	if clip.is_empty():
		_hold_rest_pose()
		return
	_play_clip(clip)
	var wanted := _locomotion_scale(state, speed)
	if not is_equal_approx(animation_player.speed_scale, wanted):
		animation_player.speed_scale = wanted


# Models without an idle clip stand on the first frame of their walk clip.
func _hold_rest_pose() -> void:
	if _current == "__rest":
		return
	var source: String = _locomotion.get(&"walk", "")
	if source.is_empty():
		var list := animation_player.get_animation_list()
		if list.is_empty():
			return
		source = list[0]
	animation_player.speed_scale = 1.0
	animation_player.play(source)
	animation_player.seek(0.0, true)
	animation_player.pause()
	_current = "__rest"


func _play_clip(actual: String) -> void:
	if _current == actual:
		return
	_current = actual
	animation_player.play(actual, 0.12)


func _index_animations() -> void:
	_animations.clear()
	for animation_name in animation_player.get_animation_list():
		var normalized := str(animation_name).to_lower().replace(" ", "_").replace("-", "_")
		_animations[normalized] = str(animation_name)
	for state: StringName in LOCOMOTION_TOKENS:
		_locomotion[state] = CLIP_LOOKUP.find(_animations, NON_LOOPING_TOKENS, LOCOMOTION_TOKENS[state])


func _pick_one_shot_clip(state: StringName) -> String:
	if state == STATE_ATTACK:
		var sides: Array[String] = []
		for token in ["attackleft", "attackright"]:
			var side := CLIP_LOOKUP.variant(_animations, token)
			if not side.is_empty():
				sides.append(side)
		if not sides.is_empty():
			_attack_side = not _attack_side
			return sides[int(_attack_side) % sides.size()]
	if state in [&"attack_left", &"attack_right"]:
		var variant := CLIP_LOOKUP.variant(_animations, String(ONE_SHOT_TOKENS[state][0]))
		if not variant.is_empty():
			return variant
	return CLIP_LOOKUP.find(_animations, NON_LOOPING_TOKENS, ONE_SHOT_TOKENS[state])


func _configure_looping_clips() -> void:
	if _loops_configured:
		return
	_loops_configured = true
	# Configure instance-owned copies once; never mutate imported shared resources.
	for library_name in animation_player.get_animation_library_list():
		var library := animation_player.get_animation_library(library_name).duplicate(false) as AnimationLibrary
		for clip_name in library.get_animation_list():
			if not _should_loop(String(clip_name)):
				continue
			var animation := library.get_animation(clip_name).duplicate(false) as Animation
			animation.loop_mode = Animation.LOOP_LINEAR
			library.remove_animation(clip_name)
			library.add_animation(clip_name, animation)
		animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(library_name, library)
	if animation_player.get_animation_list().size() > 0:
		_index_animations()


func _should_loop(clip_name: String) -> bool:
	var lower := clip_name.to_lower()
	for blocked in NON_LOOPING_TOKENS:
		if blocked in lower:
			return false
	for token in LOOPING_TOKENS:
		if token in lower:
			return true
	return false


func _attach_gait(model: Node) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	gait = GAIT.new()
	gait.name = "ProceduralGait"
	gait.character = character
	gait.connect("stepped", func(side: int, speed: float) -> void: footstep.emit(side, speed))
	(skeletons[0] as Node).add_child(gait)


func _attach_legs(model: Node) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	legs = LEG_MOTION.new()
	legs.name = "LegClips"
	legs.character = character
	legs.clips = leg_clips
	legs.set("playback_multiplier", leg_playback_multiplier)
	legs.connect("stepped", func(side: int, speed: float) -> void: footstep.emit(side, speed))
	(skeletons[0] as Node).add_child(legs)


func _attach_hit_reaction(model: Node) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var reaction := HIT_REACTION.new()
	reaction.name = "HitReaction"
	if not reaction.setup(skeletons[0] as Skeleton3D):
		reaction.free()
		return
	(skeletons[0] as Node).add_child(reaction)
	hit_reaction = reaction


func _apply_animation_library() -> void:
	if animation_library != null:
		for library_name in animation_player.get_animation_library_list():
			animation_player.remove_animation_library(library_name)
		animation_player.add_animation_library(&"", animation_library)
	if extra_clips == null or not animation_player.has_animation_library(&""):
		return
	var merged := animation_player.get_animation_library(&"").duplicate(false) as AnimationLibrary
	for clip_name in extra_clips.get_animation_list():
		if merged.has_animation(clip_name):
			merged.remove_animation(clip_name)
		merged.add_animation(clip_name, extra_clips.get_animation(clip_name))
	animation_player.remove_animation_library(&"")
	animation_player.add_animation_library(&"", merged)
