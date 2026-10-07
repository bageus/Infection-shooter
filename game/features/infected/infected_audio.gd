extends Node
## Sounds of one infected (ADR-0018): footsteps paced by distance walked,
## growls while hunting (more often when charging), an alert scream when it
## starts charging, occasional screams and distant howls between growls, pain
## on hits, attack swings and blows, dismemberment and death. Presentation only.

const SFX := preload("res://game/core/audio/public/sound_events.gd")

## Each growl family gets a matching scream: shrill for the thin infected,
## roars for the heavy ones. Only the plain infected howl from afar.
const SCREAMS := {
	&"growl_zombie": &"scream_zombie",
	&"growl_hunger": &"scream_shrill",
	&"growl_revenant": &"scream_shrill",
	&"growl_brute": &"roar_heavy",
	&"growl_titan": &"roar_heavy",
	&"growl_colossus": &"roar_heavy",
	&"growl_horde": &"roar_heavy",
}
const HOWLERS := [&"growl_zombie", &"growl_hunger", &"growl_revenant"]
## Seconds an infected keeps quiet after an alert scream.
const ALERT_REST := Vector2(7.0, 12.0)

var body: CharacterBody3D
var scream_sound: StringName = &"scream_zombie"
var _howls := true
var _was_charging := false
var _alert_wait := 0.0
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
	_howls = growl_sound in HOWLERS
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
	_alert_wait = maxf(0.0, _alert_wait - delta)
	if charging and not _was_charging and _alert_wait <= 0.0 and randf() < 0.7:
		scream()
		_alert_wait = randf_range(ALERT_REST.x, ALERT_REST.y)
		_growl_wait = maxf(_growl_wait, 1.5)
	_was_charging = charging
	_growl_wait -= delta
	if _growl_wait <= 0.0 and near_target:
		var roll := randf()
		if charging and roll < 0.25:
			scream(-2.0)
		elif not charging and _howls and roll < 0.15:
			SFX.play(body, &"howl_infected", Vector3.INF, 0.0, voice_pitch * randf_range(0.92, 1.08))
		else:
			growl()
		_growl_wait = randf_range(2.2, 4.5) if charging else randf_range(5.0, 9.0)


func growl(volume_offset := 0.0) -> void:
	SFX.play(body, growl_sound, Vector3.INF, volume_offset, voice_pitch)


func scream(volume_offset := 0.0) -> void:
	SFX.play(body, scream_sound, Vector3.INF, volume_offset, voice_pitch)


func hit(position: Vector3) -> void:
	SFX.play(body.get_parent(), &"flesh_hit", position)
	if _pain_wait <= 0.0 and randf() < 0.35:
		_pain_wait = 1.4
		if randf() < 0.3:
			scream(-4.0)
		else:
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
