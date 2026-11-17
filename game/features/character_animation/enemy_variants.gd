extends RefCounted
## Enemy extras of the animation driver (ADR-0071): the idle pool (the base idle plus every Idle*
## extra clip, a new pick after 1-3 cycles), the transition played once when an unaware enemy
## stops after a walk, the wander walk, one run clip per body and the death pick.

const CLIP_LOOKUP := preload("res://game/features/character_animation/clip_lookup.gd")
const IDLE_REPEATS := Vector2i(1, 3)
const TRANSITION_CLIP := &"Transition"
const TRANSITION_MIN_MOVE := 0.6
const TRANSITION_COOLDOWN := 8.0
const WANDER_WALK_CLIP := &"WalkWander"
## Share of deaths from standing that fall to the side (the rest fall forward).
const SIDE_DEATH := 0.65

## One-shots that give way to locomotion once the character moves (the stop transition, a turn on the spot).
const INTERRUPTIBLE := [&"Transition", &"TurnLeft", &"TurnLeft2", &"TurnRight", &"TurnRight2"]
const INTERRUPT_SPEED := 0.3

var pool: Array[String] = []
var _driver: Node
var _idle_clip := ""
var _idle_until := 0.0
var _run_pick := -1
var _moving_time := 0.0
var _transition_ready := 0.0


func _init(driver: Node) -> void:
	_driver = driver


## Rebuilds the pool and picks the run clip among Run and the RunZombie / RunForward extras.
func index() -> void:
	pool.clear()
	var extra: AnimationLibrary = _driver.get("extra_clips")
	var player: AnimationPlayer = _driver.get("animation_player")
	var locomotion: Dictionary = _driver.get("_locomotion")
	if extra == null:
		return
	var idle: String = locomotion.get(&"idle", "")
	var runs: Array[String] = []
	if not String(locomotion.get(&"run", "")).is_empty():
		runs.append(locomotion[&"run"])
	for clip_name in extra.get_animation_list():
		var text := String(clip_name)
		if text.begins_with("Idle") and text != idle and player.has_animation(clip_name):
			pool.append(text)
		elif text in ["RunZombie", "RunForward"] and player.has_animation(clip_name):
			runs.append(text)
	if not pool.is_empty() and not idle.is_empty():
		pool.append(idle)
	if runs.size() > 1:
		if _run_pick < 0:
			_run_pick = randi() % runs.size()
		locomotion[&"run"] = runs[_run_pick % runs.size()]


## The base idle becomes a pool clip; an unaware enemy's stalking walk becomes the wander walk.
func variant(requested: StringName) -> StringName:
	if requested.is_empty():
		return requested
	var locomotion: Dictionary = _driver.get("_locomotion")
	var player: AnimationPlayer = _driver.get("animation_player")
	if not pool.is_empty() and String(requested) == String(locomotion.get(&"idle", "")):
		if not pool.has(_driver.get("_current")) or float(_driver.get("_time")) >= _idle_until:
			_idle_clip = pool[randi() % pool.size()]
			_idle_until = float(_driver.get("_time")) + player.get_animation(_idle_clip).length * randi_range(IDLE_REPEATS.x, IDLE_REPEATS.y)
		return StringName(_idle_clip)
	if String(requested) == String(locomotion.get(&"walk", "")) and player.has_animation(WANDER_WALK_CLIP) and not chasing():
		return WANDER_WALK_CLIP
	return requested


func chasing() -> bool:
	var character: Node = _driver.get("character")
	return character != null and character.has_method("is_alerted") and bool(character.call("is_alerted"))


func interrupts(one_shot: StringName, speed: float) -> bool:
	return speed > INTERRUPT_SPEED and one_shot in INTERRUPTIBLE


## Standing still after a walk or run, out of a fight, plays the transition into idle once.
func stop_transition(speed: float, delta: float) -> bool:
	var current: String = _driver.get("_current")
	if speed > 0.3:
		_moving_time = _moving_time + delta if current.begins_with("Walk") or current.begins_with("Run") else 0.0
		return false
	var moved := _moving_time
	_moving_time = 0.0
	var player: AnimationPlayer = _driver.get("animation_player")
	if speed > 0.15 or moved < TRANSITION_MIN_MOVE or float(_driver.get("_time")) < _transition_ready or chasing() or not player.has_animation(TRANSITION_CLIP):
		return false
	_transition_ready = float(_driver.get("_time")) + TRANSITION_COOLDOWN
	return float(_driver.call("play_named_one_shot", TRANSITION_CLIP, 0.2)) > 0.0


## Playback rate of a clip that names its own ground speed (own_pace), 0.0 for any other clip.
static func own_rate(animation: Animation, speed: float) -> float:
	var own := float(animation.get_meta("ref_speed", 0.0)) if bool(animation.get_meta("own_pace", false)) else 0.0
	return clampf(speed / own, 0.5, 2.4) if own > 0.0 and speed > 0.15 else 0.0


## The clip of a one-shot state: attacks pick a random numbered variant per side (alternating the
## side), a death from standing mostly falls to the side.
static func pick(animations: Dictionary, state: StringName, tokens: Array, blocked: Array, flip: bool) -> String:
	if state == &"attack":
		var sides: Array[String] = []
		for token in ["attackleft", "attackright"]:
			var side := CLIP_LOOKUP.variant(animations, token)
			if not side.is_empty():
				sides.append(side)
		if not sides.is_empty():
			return sides[int(flip) % sides.size()]
	if state in [&"attack_left", &"attack_right"]:
		var found := CLIP_LOOKUP.variant(animations, String(tokens[0]))
		if not found.is_empty():
			return found
	if state == &"death":
		var side := CLIP_LOOKUP.variant(animations, "deathside")
		if not side.is_empty() and randf() < SIDE_DEATH:
			return side
	return CLIP_LOOKUP.find(animations, blocked, tokens)
