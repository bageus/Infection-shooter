extends Node
## Player-side sound (ADR-0018): the audio listener sits with the player
## (not the high top-down camera) and turns with the view; footsteps follow
## the procedural gait; item sounds play on the player.

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const LISTENER_HEIGHT := 1.3

var _player: Node3D
var listener: AudioListener3D


func configure(player: Node3D, view_yaw: Node3D, animation_driver: Node) -> void:
	_player = player
	listener = AudioListener3D.new()
	listener.name = "Ears"
	listener.position = Vector3(0.0, LISTENER_HEIGHT, 0.0)
	view_yaw.add_child(listener)
	listener.make_current()
	if animation_driver != null and animation_driver.has_signal("footstep"):
		animation_driver.connect("footstep", _on_footstep)


func play(event: StringName, volume_offset_db := 0.0) -> void:
	if is_instance_valid(_player):
		SFX.play(_player, event, Vector3.INF, volume_offset_db)


func _on_footstep(_side: int, speed: float) -> void:
	if not is_instance_valid(_player) or not (_player as CharacterBody3D).is_on_floor():
		return
	# Sprinting lands harder than walking.
	SFX.play(_player, &"step_player", _player.global_position, lerpf(-3.0, 2.0, clampf((speed - 3.0) / 6.0, 0.0, 1.0)))
