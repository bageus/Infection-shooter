extends Node
## Shared character animation playback (ADR-0001, ADR-0014, ADR-0015).
##
## Skeletal models use their AnimationPlayer clips; models without clips use a
## small procedural pose backend on a visual pivot. Presentation only: the
## driver never changes gameplay state and never searches for other modules.

# Public animation_events_v1: emitted when an attack/death one-shot ends.
signal one_shot_finished(state: StringName)

const POSE := preload("res://game/features/character_animation/procedural_pose.gd")
const STATE_ATTACK := &"attack"
const STATE_DEATH := &"death"
const LOCOMOTION_TOKENS := {
	&"idle": ["idle", "stand"],
	&"walk": ["walk", "locomotion"],
	&"run": ["run", "sprint", "jog"],
}
const LOOPING_TOKENS := ["idle", "stand", "walk", "locomotion", "run", "sprint", "jog"]
const NON_LOOPING_TOKENS := ["attack", "death", "hit", "aim"]
const ONE_SHOT_TOKENS := {
	&"attack": ["attackleft", "attackright", "attack"],
	&"death": ["death", "dead"],
}
const FLINCH_SECONDS := 0.16

@export var character_path: NodePath = NodePath("..")
@export var model_path: NodePath = NodePath("Body")
@export var run_speed_threshold := 6.8
## Playback speed is scaled by speed / reference while moving; 0 disables it.
@export var walk_reference_speed := 0.0
@export var run_reference_speed := 0.0
## Visual pivot animated procedurally when the model has no AnimationPlayer.
@export var procedural_target_path: NodePath = NodePath("Body/Visual")
@export var procedural_bob_height := 0.06
@export var procedural_sway_degrees := 4.0
@export var procedural_lean_degrees := 8.0
@export var procedural_stride_hz := 2.2
@export var procedural_attack_seconds := 0.55
@export var procedural_attack_lunge := 0.28
@export var procedural_death_seconds := 1.2

var character: CharacterBody3D
var animation_player: AnimationPlayer
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


# Public animation_selection_v1: optional presentation-only selector.
func configure_clip_selector(selector: Callable) -> void:
	var changed := _clip_selector != selector
	_clip_selector = selector
	if animation_player != null and selector.is_valid():
		if changed:
			_configure_looping_clips()
		_play_selected_clip()


# Public animation_events_v1: plays a non-looping attack or death. Returns the
# duration in seconds, or 0.0 when nothing could be played. Death is final.
func play_one_shot(state: StringName) -> float:
	if _dead or (state != STATE_ATTACK and state != STATE_DEATH):
		return 0.0
	var length := 0.0
	if animation_player != null:
		var clip := _pick_one_shot_clip(state)
		if clip.is_empty():
			return 0.0
		_current = clip
		animation_player.speed_scale = 1.0
		animation_player.play(clip, 0.08)
		length = animation_player.get_animation(clip).length
	elif _target != null:
		length = procedural_death_seconds if state == STATE_DEATH else procedural_attack_seconds
	else:
		return 0.0
	_one_shot = state
	_one_shot_elapsed = 0.0
	_one_shot_length = length
	_dead = state == STATE_DEATH
	return length


# Public animation_events_v1: short additive flinch on the visual pivot.
func notify_hit() -> void:
	if _target == null or _dead:
		return
	if animation_player != null and _flinch_elapsed < 0.0:
		# Skeletal visuals may be rotated by their owner; capture the pose now.
		_rest = _target.transform
	_flinch_elapsed = 0.0


# Public animation_events_v1: pause animation work for far or hidden characters.
func set_active(active: bool) -> void:
	set_process(active)
	if animation_player != null:
		animation_player.active = active


func _ready() -> void:
	character = get_parent() as CharacterBody3D
	if character == null:
		character = get_node_or_null(character_path) as CharacterBody3D
	var model: Node = null
	if character != null:
		model = character.get_node_or_null(model_path)
	if model == null:
		return
	animation_player = _find_animation_player(model)
	if animation_player != null:
		_index_animations()
		_configure_looping_clips()
		_target = model as Node3D
		_pose.feet = Vector3(0.0, _feet_height(model), 0.0)
		_play_locomotion(&"idle", 0.0)
		return
	_target = character.get_node_or_null(procedural_target_path) as Node3D
	if _target == null:
		_target = model as Node3D
	if _target == null:
		return
	_rest = _target.transform
	_pose.feet = Vector3(0.0, _feet_height(_target), 0.0)
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
	if finished == STATE_ATTACK:
		_current = ""
	one_shot_finished.emit(finished)


func _process_skeletal(speed: float) -> void:
	_apply_flinch_overlay()
	if not _one_shot.is_empty() or _dead:
		return
	if _play_selected_clip():
		return
	if speed > run_speed_threshold or (speed > 0.15 and _locomotion.get(&"walk", "").is_empty()):
		_play_locomotion(&"run", speed)
	elif speed > 0.15:
		_play_locomotion(&"walk", speed)
	else:
		_play_locomotion(&"idle", speed)


func _process_procedural(speed: float, delta: float) -> void:
	var pose := Transform3D.IDENTITY
	if _one_shot == STATE_DEATH or (_dead and _one_shot.is_empty()):
		pose = _pose.death(1.0 if _one_shot.is_empty() else _one_shot_elapsed / _one_shot_length)
	elif _one_shot == STATE_ATTACK:
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


func _play_selected_clip() -> bool:
	if not _clip_selector.is_valid():
		return false
	var requested := StringName(_clip_selector.call())
	if animation_player.has_animation(requested):
		_play_clip(String(requested))
		return true
	if not requested.is_empty() and not _missing_clips.has(requested):
		_missing_clips[requested] = true
		push_warning("Character animation clip unavailable: %s" % requested)
	return false


func _play_locomotion(state: StringName, speed: float) -> void:
	var clip: String = _locomotion.get(state, "")
	if clip.is_empty():
		_hold_rest_pose()
		return
	_play_clip(clip)
	var reference := run_reference_speed if state == &"run" else walk_reference_speed
	var wanted := 1.0
	if state != &"idle" and reference > 0.0:
		wanted = clampf(speed / reference, 0.5, 1.6)
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
		_locomotion[state] = _find_clip(LOCOMOTION_TOKENS[state])


func _pick_one_shot_clip(state: StringName) -> String:
	if state == STATE_ATTACK:
		var sides: Array[String] = []
		for token in ["attackleft", "attackright"]:
			var side := _find_clip([token])
			if not side.is_empty():
				sides.append(side)
		if not sides.is_empty():
			_attack_side = not _attack_side
			return sides[int(_attack_side) % sides.size()]
	return _find_clip(ONE_SHOT_TOKENS[state])


# Exact normalized match first, then the shortest clip containing the token.
func _find_clip(tokens: Array) -> String:
	for token: String in tokens:
		for normalized: String in _animations:
			var squashed := normalized.replace("_", "")
			if squashed == token and not _is_excluded(normalized, token):
				return _animations[normalized]
		var best := ""
		var best_length := 9999
		for normalized: String in _animations:
			var squashed := normalized.replace("_", "")
			if token in squashed and not _is_excluded(normalized, token) and normalized.length() < best_length:
				best = _animations[normalized]
				best_length = normalized.length()
		if not best.is_empty():
			return best
	return ""


func _is_excluded(normalized: String, token: String) -> bool:
	for blocked in NON_LOOPING_TOKENS:
		if blocked in normalized and blocked not in token:
			return true
	return false


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


func _feet_height(node: Node) -> float:
	var lowest := INF
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mesh_node in meshes:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh != null:
			var offset := 0.0 if mesh_instance == node else mesh_instance.position.y
			lowest = minf(lowest, mesh_instance.get_aabb().position.y + offset)
	return 0.0 if lowest == INF else lowest


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
