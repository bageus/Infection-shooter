extends RefCounted
## A chain of clips for the animation page: each is played after the one before, cross-faded the way the
## game does it (enemy_blends.gd) and at the game's attack speed, so a transition can be judged by eye.

const BLENDS := preload("res://game/features/character_animation/public/enemy_blends.gd")
const HOLD := 2.0 # seconds a looping clip plays in a chain (at least one cycle)
const STRIKE_WINDUP := 0.35 # the game's wind-up: an attack plays faster when its strike lands later
const LOOP_TOKENS := ["idle", "walk", "run"]
const BASE_BLEND := 0.12
## Chains the game really plays. A clip ending in * takes the first clip with that prefix; clips the enemy lacks are skipped.
const PRESETS := {
	"Idle → бег → Idle": ["Idle", "Run", "Idle"],
	"Ходьба → переход → Idle": ["Walk", "Transition", "Idle"],
	"Брожение → переход → Idle": ["WalkWander", "Transition", "Idle"],
	"Бег → удары → бег": ["Run", "AttackLeft*", "AttackRight*", "Run"],
	"Idle → удар → Idle": ["Idle", "AttackLeft*", "Idle"],
	"Поворот на месте": ["Idle", "TurnLeft*", "TurnRight*", "Idle"],
	"Реакция на дробовик": ["Idle", "HitReaction", "Idle"],
	"Выход из дыры": ["Climb", "Idle", "Run"],
	"Idle → смерть вбок": ["Idle", "DeathSide"],
	"Бег → смерть вперёд": ["Run", "DeathForward"],
	"Отброс → смерть назад": ["Run", "DeathBack"],
}

var entries: Array[String] = []
var playing := false
var current := -1
var _elapsed := 0.0
var _duration := 0.0
var _after_one_shot := false


## The clips of a preset that `available` has, in order.
static func preset_clips(preset: String, available: PackedStringArray) -> Array[String]:
	var sorted := Array(available)
	sorted.sort()
	var result: Array[String] = []
	for wanted: String in PRESETS.get(preset, []):
		var found := ""
		for clip: String in sorted:
			if clip == wanted or (wanted.ends_with("*") and clip.begins_with(wanted.trim_suffix("*"))):
				found = clip
				break
		if not found.is_empty():
			result.append(found)
	return result


static func is_looping(clip: String) -> bool:
	var lower := clip.to_lower()
	for token: String in LOOP_TOKENS:
		if lower.begins_with(token):
			return true
	return false


## Playback speed the game uses for a clip: attacks that strike late are sped up.
static func speed_of(animation: Animation) -> float:
	var strike := float(animation.get_meta("strike_time", 0.0))
	return clampf(strike / STRIKE_WINDUP, 1.0, 2.2) if strike > 0.0 else 1.0


## Seconds a clip takes in a chain: a looping one holds, a one-shot plays through.
static func seconds_of(clip: String, animation: Animation) -> float:
	return maxf(HOLD, animation.length) if is_looping(clip) else animation.length / speed_of(animation)


func start(player: AnimationPlayer) -> void:
	playing = not entries.is_empty() and player != null
	current = -1
	_after_one_shot = false
	if playing:
		_play_next(player)


## Playback speed to return to after a pause: the playing clip's own.
func resume_speed(player: AnimationPlayer) -> float:
	return speed_of(player.get_animation(entries[current])) if playing and current >= 0 else 1.0


func stop() -> void:
	playing = false
	current = -1


## Advances the chain; `paused` freezes its clock; at the end it restarts when `repeat`, else stops
## (a death holds its last pose).
func step(delta: float, player: AnimationPlayer, paused: bool, repeat: bool) -> void:
	if not playing or player == null or paused:
		return
	_elapsed += delta
	if _elapsed < _duration:
		return
	if current + 1 < entries.size():
		_play_next(player)
	elif repeat:
		_after_one_shot = true
		current = -1
		_play_next(player)
	else:
		playing = false


func _play_next(player: AnimationPlayer) -> void:
	if current >= 0:
		_after_one_shot = not is_looping(entries[current])
	current += 1
	var clip := entries[current]
	var animation := player.get_animation(clip)
	animation.loop_mode = Animation.LOOP_LINEAR if is_looping(clip) else Animation.LOOP_NONE
	player.play(clip, BLENDS.seconds(clip, BASE_BLEND, _after_one_shot))
	player.speed_scale = speed_of(animation)
	_elapsed = 0.0
	_duration = seconds_of(clip, animation)
