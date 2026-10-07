extends Node
## Sounds of one infected (ADR-0018): footsteps paced by distance walked,
## one call-out scream when it first spots the player, then growls while
## hunting (more often when charging), pain on hits, attack swings and blows,
## dismemberment and death. Presentation only.

const SFX := preload("res://game/core/audio/public/sound_events.gd")

## The call-out when an infected first spots the player: a rasping scream,
## a roar for the heavy ones. Growls and wheezes take over afterwards.
const SCREAMS := {
	&"growl_brute": &"roar_heavy",
	&"growl_titan": &"roar_heavy",
	&"growl_colossus": &"roar_heavy",
	&"growl_horde": &"roar_heavy",
}
## One call-out speaks for a group that spots the player together: others
## within this window count as having heard it and stay with growls.
const CALL_OUT_WINDOW_MS := 2500
static var _last_call_out_ms := -100000

var body: CharacterBody3D
var scream_sound: StringName = &"scream_zombie"
var spotted := false
var step_sound: StringName = &"step_light"
var growl_sound: StringName = &"growl_zombie"
var voice_pitch := 1.0
var step_pitch := 1.0
var step_length := 0.85
var _walked := 0.0
var _last_position := Vector3.ZERO
var _growl_wait := 0.0
var _pain_wait := 0.0


func setup(owner_body: CharacterBody3D, size: float) -> void:
	body = owner_body
	step_sound = owner_body.get("step_sound")
	growl_sound = owner_body.get("growl_sound")
	voice_pitch = float(owner_body.get("voice_pitch"))
	step_pitch = float(owner_body.get("step_pitch"))
	step_length = 0.85 * size
	scream_sound = SCREAMS.get(growl_sound, &"scream_zombie")
	_last_position = owner_body.global_position
	_growl_wait = randf_range(1.0, 4.0)


# Called every simulated tick while alive.
func tick(delta: float, charging: bool, near_target: bool) -> void:
	_pain_wait = maxf(0.0, _pain_wait - delta)
	var moved := body.global_position - _last_position
	_last_position = body.global_position
	moved.y = 0.0
	if body.is_on_floor() and moved.length() < 1.0:
		_walked += moved.length()
		if _walked >= step_length:
			_walked = 0.0
			SFX.play(body, step_sound, body.global_position, 1.5 if charging else -2.0, step_pitch)
	if near_target and not spotted:
		spotted = true
		_call_out()
		return
	_growl_wait -= delta
	if _growl_wait <= 0.0 and near_target:
		growl()
		_growl_wait = randf_range(2.2, 4.5) if charging else randf_range(5.0, 9.0)


func _call_out() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_call_out_ms < CALL_OUT_WINDOW_MS:
		return
	_last_call_out_ms = now
	scream()
	_growl_wait = maxf(_growl_wait, 2.5)


func growl(volume_offset := 0.0) -> void:
	SFX.play(body, growl_sound, Vector3.INF, volume_offset, voice_pitch)


func scream(volume_offset := 0.0) -> void:
	SFX.play(body, scream_sound, Vector3.INF, volume_offset, voice_pitch)


func hit(position: Vector3) -> void:
	SFX.play(body.get_parent(), &"flesh_hit", position)
	if _pain_wait <= 0.0 and randf() < 0.35:
		_pain_wait = 1.4
		growl(-3.0)


func attack_started() -> void:
	SFX.play(body, &"attack_swing", Vector3.INF, 0.0, 1.0 / maxf(step_pitch, 0.5))
	if randf() < 0.5:
		growl(-1.0)


func attack_landed(bite: bool) -> void:
	SFX.play(body, &"attack_bite" if bite else &"attack_hit", Vector3.INF, 0.0, step_pitch)


func severed(position: Vector3) -> void:
	SFX.play(body.get_parent(), &"dismember", position)


func died() -> void:
	SFX.play(body, &"enemy_death", Vector3.INF, 0.0, voice_pitch)


func play(event: StringName, volume_offset := 0.0) -> void:
	SFX.play(body, event, Vector3.INF, volume_offset)
