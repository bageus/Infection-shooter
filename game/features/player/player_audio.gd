extends Node
## Player-side sound (ADR-0018): the audio listener sits with the player
## (not the high top-down camera) and turns with the view; footsteps follow
## the procedural gait; item sounds play on the player. Mutation skills get a
## cast sound, and lasting ones a bed that runs for the effect (ADR-0018).

const SFX := preload("res://game/core/audio/public/sound_events.gd")
const LISTENER_HEIGHT := 1.3

## skill -> [cast event, lasting event or &"", lasting event follows the player]
const SKILL_SOUNDS := {
	"blood_burst": [&"skill_blood_burst", &"", true],
	"parasite": [&"skill_parasite", &"", true],
	"living_harvest": [&"skill_living_harvest", &"", true],
	"discharge": [&"skill_discharge", &"", true],
	"overload": [&"skill_overload", &"", true],
	"storm_pulse": [&"skill_storm_pulse", &"skill_storm_field", true],
	"acid_spit": [&"skill_acid_spit", &"acid_sizzle", false],
	"spore_cocoon": [&"skill_spore_cocoon", &"", false],
	"epidemic": [&"skill_epidemic", &"", true],
	"predator_dash": [&"skill_predator_dash", &"", true],
	"bone_blades": [&"skill_bone_blades", &"bone_blades_whirl", true],
	"berserk": [&"skill_berserk", &"", true],
}
## Passives that fire at one clear moment.
const PASSIVE_SOUNDS := {"second_heart": &"skill_second_heart", "retaliation": &"skill_retaliation"}
## Matches the spore release delay in mutation_skill_effects.gd.
const SPORE_DELAY := 2.0

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


func configure_skills(runtime: Node) -> void:
	if runtime.has_signal("skill_cast"):
		runtime.connect("skill_cast", _on_skill_cast)
	if runtime.has_signal("passive_triggered"):
		runtime.connect("passive_triggered", _on_passive)


func _on_skill_cast(skill_id: String) -> void:
	if not is_instance_valid(_player) or not SKILL_SOUNDS.has(skill_id):
		return
	var spec: Array = SKILL_SOUNDS[skill_id]
	if skill_id == "spore_cocoon":
		# The pod lands at the aim point and bursts there after the delay.
		var where := _target()
		SFX.play(_world(), spec[0], where)
		get_tree().create_timer(SPORE_DELAY).timeout.connect(_burst_spores.bind(where))
		return
	SFX.play(_player, spec[0])
	if spec[1] != &"":
		if spec[2]:
			SFX.play(_player, spec[1])
		else:
			SFX.play(_world(), spec[1], _target())


func _on_passive(skill_id: String, _duration: float) -> void:
	if is_instance_valid(_player) and PASSIVE_SOUNDS.has(skill_id):
		SFX.play(_player, PASSIVE_SOUNDS[skill_id])


func _burst_spores(where: Vector3) -> void:
	if is_instance_valid(_player) and _player.is_inside_tree():
		SFX.play(_world(), &"spore_burst", where)


# Ground-targeted skills land at the aim point and must not follow the player.
func _target() -> Vector3:
	var point: Variant = _player.get("_aim_point")
	return point if point is Vector3 else _player.global_position


func _world() -> Node:
	var root: Variant = _player.get("effects_root")
	return root if root is Node3D and is_instance_valid(root) else _player.get_parent()
