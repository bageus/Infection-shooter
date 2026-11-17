extends Node
## Shared character animation playback (ADR-0001, ADR-0014, ADR-0015).

# Public animation_events_v1: emitted when an attack/death one-shot ends.
signal one_shot_finished(state: StringName)
# Public animation_events_v1 addition (ADR-0018): a procedural-gait foot landed.
signal footstep(side: int, speed: float)

const MODEL_PROBE := preload("res://game/features/character_animation/animation_model_probe.gd")
const POSE := preload("res://game/features/character_animation/procedural_pose.gd")
const HIT_REACTION := preload("res://game/features/character_animation/hit_reaction.gd")
const CLIP_LOOKUP := preload("res://game/features/character_animation/clip_lookup.gd")
const OVERLAY := preload("res://game/features/character_animation/clip_overlay.gd")
const LEG_OVERLAY := preload("res://game/features/character_animation/leg_overlay.gd")
const STANCE_FEET := preload("res://game/features/character_animation/stance_feet.gd")
const CLIP_FOOTSTEPS := preload("res://game/features/character_animation/clip_footsteps.gd")
const CLIP_TUNING := preload("res://game/features/character_animation/clip_tuning.gd")
const STRIKE_POSE := preload("res://game/features/character_animation/strike_pose.gd")
const ENEMY_VARIANTS := preload("res://game/features/character_animation/enemy_variants.gd")
const ENEMY_BLENDS := preload("res://game/features/character_animation/public/enemy_blends.gd")
const HERO_CLIPS := preload("res://game/features/character_animation/hero_body_clips.gd")
const STATE_ATTACK := &"attack"
const STATE_DEATH := &"death"
# Directional deaths (ADR-0034) fall back to the plain death clip.
const DEATH_STATES := [&"death", &"death_forward", &"death_back", &"death_right", &"death_left"]
const LOCOMOTION_TOKENS := {
	&"idle": ["idle", "stand"],
	&"walk": ["walk", "locomotion"],
	&"run": ["run", "sprint", "jog"],
}
const LOOPING_TOKENS := ["idle", "stand", "walk", "locomotion", "run", "sprint", "jog"]
const NON_LOOPING_TOKENS := ["attack", "death", "hit", "aim", "slam", "summon", "throw"]
const ONE_SHOT_TOKENS := {
	&"attack": ["attackleft", "attackright", "attack"],
	&"attack_left": ["attackleft", "attack"],
	&"attack_right": ["attackright", "attack"],
	&"death": ["death", "dead"],
	&"death_forward": ["deathforward", "death", "dead"],
	&"death_back": ["deathback", "death", "dead"],
	&"death_right": ["deathside", "death", "dead"], &"death_left": ["deathside2", "death", "dead"], # DeathSide falls to its right
	&"slam": ["slam"], &"summon": ["summon"], &"throw": ["throw"],
	&"attack_crawl": ["crawlattack"],
}
# A strike lands this many seconds into a clip that names its strike_time.
const STRIKE_WINDUP := 0.35
const MAX_ATTACK_SPEED := 2.2
const FLINCH_SECONDS := 0.16
const MOVING_ATTACKS := [&"attack", &"attack_left", &"attack_right", &"attack_crawl"]
# A crawler that strikes while still dragging itself keeps this cycle on its legs.
const CRAWL_LEGS := "Crawl"
const STATE_ATTACK_CRAWL := &"attack_crawl"

@export var character_path: NodePath = NodePath("..")
@export var model_path: NodePath = NodePath("Body")
## Optional clip set that replaces the model's own clips (ADR-0016).
@export var animation_library: AnimationLibrary
@export var run_speed_threshold := 6.8
## A running character keeps the run clip down to this share of the threshold,
## so speed wobble around it does not flicker between walk and run.
@export_range(0.5, 1.0) var run_exit_ratio := 0.85
## Clips merged into the model's own default library (same names win), so a
## rebuilt model keeps authored extras such as the Mixamo set (ADR-0045).
@export var extra_clips: AnimationLibrary
## Emit `footstep` from the baked Walk_*/Run_* cycles (the player's model has no leg motion modifiers).
@export var clip_footsteps := false
## Set by the player while its feet step it round on the spot: a walking pace for the cycle and footsteps.
var turn_step_speed := 0.0
## Idle foot turn and knee nudge for authored enemy clips; the player's baked clips already stand right.
@export var stance_feet := true
## Clip played for a dodge roll when there are no leg clips.
@export var dodge_clip := &"Running_Dive_Roll"
## Playback speed is scaled by speed / reference while moving; 0 disables it.
@export var walk_reference_speed := 0.0
@export var run_reference_speed := 0.0
## Scales locomotion cycle playback on top of the speed-matched rate (1.2 = 20 % faster).
@export var locomotion_speed_multiplier := 1.0
## Player leg cycles only; upper-body playback and dodge duration remain authored.
@export var leg_playback_multiplier := 1.0:
	set(value):
		leg_playback_multiplier = clampf(value, 0.5, 2.0) if is_finite(value) else 1.0
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
var step_state := preload("res://game/features/character_animation/animation_step.gd").new() # Far characters pose less often.
var defer_setup := false
var _prepared := false
var character: CharacterBody3D
var animation_player: AnimationPlayer
var hit_reaction: SkeletonModifier3D
var overlay: SkeletonModifier3D
var strike: SkeletonModifier3D
## Whole-body clip (all but the arms) over the playing clip: the hero's kick and turns on the spot.
var body_clip: SkeletonModifier3D
var leg_overlay: SkeletonModifier3D
var ragdoll: PhysicalBoneSimulator3D # the dead hero's ragdoll after his fall backward, else null
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
var _legs_phase := -1.0 # position of the leg clip the one-shot took over from (-1: none), handed to the leg overlay once
var _step_phase := -1.0
var _variants := ENEMY_VARIANTS.new(self)


# Public animation_selection_v1: optional presentation-only selector.
func configure_clip_selector(selector: Callable) -> void:
	var changed := _clip_selector != selector
	_clip_selector = selector
	if animation_player != null and selector.is_valid():
		if changed:
			_configure_looping_clips()
		if _one_shot.is_empty():
			_play_selected_clip()


# Public animation_events_v1: plays a non-looping attack, death or a skeletal
# special (slam, summon). Returns the duration in seconds, or 0.0 when nothing
# could be played. Death is final.
func play_one_shot(state: StringName) -> float:
	prepare_visual()
	if _dead or not ONE_SHOT_TOKENS.has(state):
		return 0.0
	if animation_player == null and state in [&"slam", &"summon", &"throw"]:
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
		animation_player.play(clip, _blend(clip, 0.08, false))
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
	_legs_phase = animation_player.current_animation_position if animation_player.current_animation == String(leg_clip) else -1.0
	_current = String(clip_name)
	animation_player.speed_scale = speed
	animation_player.play(clip_name, _blend(String(clip_name), blend, false))
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
		overlay = HERO_CLIPS.attach(animation_player, OVERLAY, "ClipOverlay")
		if overlay == null:
			return false
	overlay.call("play", animation_player.get_animation(clip_name))
	return true


# animation_events_v1 (ADR-0066): procedural melee strike, &"kick" (rear left leg), &"punch" (left arm) or &"inject" (left hand stabs the left thigh); returns its duration, 0.0 if impossible.
func play_strike(kind: StringName) -> float:
	prepare_visual()
	if _dead or animation_player == null:
		return 0.0
	if kind == &"kick" and HERO_CLIPS.has_kick(self):
		return HERO_CLIPS.play(self, HERO_CLIPS.KICK, HERO_CLIPS.KICK_SPEED, kind)
	if strike == null:
		strike = HERO_CLIPS.attach(animation_player, STRIKE_POSE, "StrikePose")
		if strike == null:
			return 0.0
	return float(strike.call("start", kind))


# Public animation_events_v1 addition (ADR-0066): true while a strike pose plays.
func is_striking() -> bool: return (strike != null and bool(strike.call("is_playing"))) or HERO_CLIPS.is_kicking(self)


# ADR-0070: seconds from the start of a strike to its impact (the kick clip's foot moment), `fallback` otherwise.
func strike_impact_time(kind: StringName, fallback: float) -> float: return HERO_CLIPS.impact_time(self, kind, fallback)

func play_turn(side: StringName) -> bool: return not _dead and HERO_CLIPS.turn(self, side)

func is_body_clip_playing() -> bool: return HERO_CLIPS.running(self) # ADR-0070: the hero's turn or kick clip plays

# ADR-0070: one random death clip plays once and holds its last pose; returns its length, 0.0 without clips or when dead.
func play_death_clip() -> float:
	prepare_visual()
	var clip := HERO_CLIPS.pick_death(self) if animation_player != null else &""
	if _dead or clip == &"":
		return 0.0
	for modifier: SkeletonModifier3D in [body_clip, strike, leg_overlay]:
		if modifier != null:
			modifier.call("stop")
	var length := play_named_one_shot(clip, 0.15)
	_one_shot = &"death"
	_dead = true
	if clip == HERO_CLIPS.RAGDOLL_AFTER and is_inside_tree(): # the fall backward ends in a ragdoll
		get_tree().create_timer(length).timeout.connect(HERO_CLIPS.release_ragdoll.bind(self))
	return length


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
	var strike_time := float(animation.get_meta("strike_time", 0.0))
	return clampf(strike_time / STRIKE_WINDUP, 1.0, MAX_ATTACK_SPEED) if strike_time > 0.0 else 1.0


# Public animation_events_v1 addition (ADR-0044): plays the dodge roll for
# `duration` seconds toward a world-space direction, relative to the body.
# Returns false without leg clips. The roll turns the whole body along the dodge.
func play_dodge(world_direction: Vector3, duration: float, held_weapon: StringName = &"") -> bool:
	CLIP_TUNING.hold_weapon(animation_player, dodge_clip, held_weapon, duration)
	return _play_dodge_clip(world_direction, duration)


# Baked dodge: the body turns along the dodge and the whole-body roll clip is squeezed into `duration`.
func _play_dodge_clip(world_direction: Vector3, duration: float) -> bool:
	if body_clip != null:
		body_clip.call("stop") # a roll cancels a turn or kick in progress
	var direction := Vector3(world_direction.x, 0.0, world_direction.z)
	if _dead or direction.length_squared() < 0.0001 or _target == null or play_named_one_shot(dodge_clip, 0.06, clip_length(dodge_clip) / maxf(duration, 0.05)) <= 0.0:
		return false
	_target.global_rotation = Vector3(0.0, atan2(direction.x, direction.z), 0.0)
	return true


# Public animation_events_v1 addition (ADR-0044): true while a dodge clip plays.
func is_dodging() -> bool:
	return _one_shot == dodge_clip


# Public animation_events_v1 addition: stops a one-shot clip early (a cancelled reload) and returns to locomotion.
func cancel_one_shot(clip_name: StringName) -> void:
	if _one_shot != clip_name or _dead:
		return
	_one_shot = &""
	_transition_legs = ""
	_current = ""


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


func is_active() -> bool: return _active_requested

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
		_attach_hit_reaction(model)
		if stance_feet:
			STANCE_FEET.attach(model, animation_player)
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
		if step_state.step > 1: step_state.advance(animation_player, delta, get_instance_id())
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


func _process_skeletal(real_speed: float) -> void:
	var speed := maxf(real_speed, turn_step_speed)
	_apply_flinch_overlay()
	if clip_footsteps: _emit_clip_steps(speed)
	_transition_legs = CLIP_TUNING.follow_selector(self)
	_update_attack_legs(speed)
	if not _one_shot.is_empty() or _dead:
		return
	if _variants.stop_transition(speed, get_process_delta_time()):
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


func _emit_clip_steps(speed: float) -> void:
	var clip := animation_player.current_animation
	var length := animation_player.current_animation_length
	if speed <= 0.15 or not _one_shot.is_empty() or length <= 0.0 or not animation_player.is_playing():
		_step_phase = -1.0
		return
	var phase := animation_player.current_animation_position / length
	var side := CLIP_FOOTSTEPS.step_side(clip.get_slice("_", 0), phase if _step_phase < 0.0 else _step_phase, phase)
	_step_phase = phase
	if side >= 0:
		footstep.emit(side, speed)


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
	var requested: StringName = _variants.variant(StringName(_clip_selector.call()))
	if animation_player.has_animation(requested):
		_play_clip(String(requested))
		# Cycles that name the ground speed they are paced for follow the actual speed.
		var reference := float(animation_player.get_animation(requested).get_meta("ref_speed", 0.0))
		var wanted := (clampf(speed / reference, 0.5, 2.4) if reference > 0.0 and speed > 0.15 else 1.0) * locomotion_speed_multiplier
		# The walking-animation setting paces the player's baked cycles (idle stays at its own pace).
		if clip_footsteps and speed > 0.15:
			wanted *= leg_playback_multiplier
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
	if _one_shot == STATE_ATTACK_CRAWL and animation_player.has_animation(CRAWL_LEGS):
		clip = CRAWL_LEGS
	var wanted := (_one_shot in MOVING_ATTACKS or not _transition_legs.is_empty()) and not _dead and not clip.is_empty()
	if leg_overlay == null and wanted and speed > 0.15:
		leg_overlay = LEG_OVERLAY.attach(animation_player.get_parent())
	if leg_overlay != null:
		leg_overlay.call("drive", animation_player.get_animation(clip) if wanted else null, CLIP_TUNING.leg_rate(self, clip, state, speed), speed > 0.15, _legs_phase)
		_legs_phase = -1.0


func _locomotion_scale(state: StringName, speed: float) -> float:
	var reference := run_reference_speed if state == &"run" else walk_reference_speed
	return clampf(speed / reference, 0.5, 1.6) * locomotion_speed_multiplier if state != &"idle" and reference > 0.0 else 1.0


func _play_locomotion(state: StringName, speed: float) -> void:
	var clip: String = _locomotion.get(state, "") if state == &"run" else String(_variants.variant(StringName(_locomotion.get(state, ""))))
	if clip.is_empty():
		_hold_rest_pose()
		return
	_play_clip(clip)
	var own: float = ENEMY_VARIANTS.own_rate(animation_player.get_animation(clip), speed)
	var wanted := own * locomotion_speed_multiplier if own > 0.0 else _locomotion_scale(state, speed)
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


func _blend(clip: String, base: float, after_one_shot: bool) -> float:
	return ENEMY_BLENDS.seconds(clip, base, after_one_shot) if extra_clips != null else base


func _play_clip(actual: String) -> void:
	if _current == actual:
		return
	animation_player.play(actual, _blend(actual, 0.12, _current.is_empty()))
	_current = actual


func _index_animations() -> void:
	_animations.clear()
	for animation_name in animation_player.get_animation_list():
		var normalized := str(animation_name).to_lower().replace(" ", "_").replace("-", "_")
		_animations[normalized] = str(animation_name)
	if clip_footsteps:
		CLIP_TUNING.apply(animation_player, dodge_clip)
	for state: StringName in LOCOMOTION_TOKENS:
		_locomotion[state] = CLIP_LOOKUP.find(_animations, NON_LOOPING_TOKENS, LOCOMOTION_TOKENS[state])
	_variants.index()


func _pick_one_shot_clip(state: StringName) -> String:
	_attack_side = not _attack_side if state == STATE_ATTACK else _attack_side
	return ENEMY_VARIANTS.pick(_animations, state, ONE_SHOT_TOKENS[state], NON_LOOPING_TOKENS, _attack_side)


func _configure_looping_clips() -> void:
	if _loops_configured:
		return
	_loops_configured = true
	HERO_CLIPS.loop_clips(animation_player, LOOPING_TOKENS, NON_LOOPING_TOKENS)
	if animation_player.get_animation_list().size() > 0:
		_index_animations()


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
	HERO_CLIPS.merge_clips(animation_player, extra_clips)
