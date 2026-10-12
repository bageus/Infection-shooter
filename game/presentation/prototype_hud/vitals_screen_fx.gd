extends Control
## Full-screen edge feedback for the two vital meters.
##
## Mutagen near the loss-of-control threshold: green smoke rises from the bottom
## edge and pulses faster with a low rising pressure drone. Low health: blood
## streaks run from the top edge and heavy breathing gets louder. Both fade out
## smoothly when the value recovers. One shader rect, no extra viewports.

const SHADER := preload("res://game/presentation/prototype_hud/vitals_screen_fx.gdshader")
const BREATHING := preload("res://assets/audio/vitals/heavy_breathing.ogg")
const PRESSURE := preload("res://assets/audio/vitals/mutagen_pressure.ogg")

const SMOKE_START_RATIO := 0.4
const BLOOD_START_HEALTH := 0.6
const BLOOD_FULL_HEALTH := 0.15
const BREATH_START_HEALTH := 0.5
const SILENT_DB := -60.0
const BREATHING_LOUD_DB := -4.0
const PRESSURE_LOUD_DB := -9.0
const FADE_IN_SPEED := 1.6
const FADE_OUT_SPEED := 0.8
const AUDIO_THRESHOLD := 0.02

var smoke := 0.0
var blood := 0.0

var _material: ShaderMaterial
var _rect: ColorRect
var _breathing: AudioStreamPlayer
var _pressure: AudioStreamPlayer
var _phase := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)
	_breathing = _make_player(BREATHING)
	_pressure = _make_player(PRESSURE)
	resized.connect(_update_aspect)
	_update_aspect()


## Mutagen pressure 0..1: rises from SMOKE_START_RATIO of the critical threshold
## and stays full while control is lost.
static func smoke_target(mutation: float, critical: float, control_lost: bool) -> float:
	if control_lost:
		return 1.0
	if critical <= 0.0:
		return 0.0
	return smoothstep(SMOKE_START_RATIO, 1.0, mutation / critical)


## Missing health 0..1: zero above BLOOD_START_HEALTH, full below BLOOD_FULL_HEALTH.
static func blood_target(health: float, max_health: float) -> float:
	if max_health <= 0.0:
		return 0.0
	return 1.0 - smoothstep(BLOOD_FULL_HEALTH, BLOOD_START_HEALTH, health / max_health)


static func breathing_target(health: float, max_health: float) -> float:
	if max_health <= 0.0:
		return 0.0
	return 1.0 - smoothstep(BLOOD_FULL_HEALTH, BREATH_START_HEALTH, health / max_health)


func update(delta: float, mutation: float, critical: float, control_lost: bool, health: float, max_health: float) -> void:
	var smoke_goal := smoke_target(mutation, critical, control_lost)
	var blood_goal := blood_target(health, max_health)
	smoke = move_toward(smoke, smoke_goal, delta * (FADE_IN_SPEED if smoke_goal > smoke else FADE_OUT_SPEED))
	blood = move_toward(blood, blood_goal, delta * (FADE_IN_SPEED if blood_goal > blood else FADE_OUT_SPEED))
	# The pulse speeds up as the threshold gets closer.
	_phase += delta * lerpf(1.2, 4.5, smoke)
	var pulse := 1.0 - 0.22 * smoke * (0.5 + 0.5 * sin(_phase))
	_rect.visible = smoke > 0.002 or blood > 0.002
	if _rect.visible:
		_material.set_shader_parameter("smoke", smoke)
		_material.set_shader_parameter("blood", blood)
		_material.set_shader_parameter("pulse", pulse)
	_update_audio(smoke, breathing_target(health, max_health))


func _update_audio(smoke_level: float, breathing_level: float) -> void:
	_set_loop_level(_pressure, smoke_level, PRESSURE_LOUD_DB, 1.0 + 0.15 * smoke_level)
	_set_loop_level(_breathing, breathing_level, BREATHING_LOUD_DB, 0.92 + 0.2 * breathing_level)


func _set_loop_level(player: AudioStreamPlayer, level: float, loud_db: float, pitch: float) -> void:
	if level <= AUDIO_THRESHOLD:
		if player.playing:
			player.stop()
		return
	player.volume_db = lerpf(SILENT_DB, loud_db, sqrt(level))
	player.pitch_scale = pitch
	if not player.playing:
		player.play()


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"UI" if AudioServer.get_bus_index(&"UI") >= 0 else &"Master"
	player.volume_db = SILENT_DB
	add_child(player)
	return player


func _update_aspect() -> void:
	if _material != null and size.y > 0.0:
		_material.set_shader_parameter("aspect", size.x / size.y)
