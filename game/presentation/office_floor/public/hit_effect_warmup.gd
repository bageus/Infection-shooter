extends Node3D
## Plays every prop-hit effect (sparks, smoke, torn paper, dust, flipbooks, water
## droplets) once in a hidden 4x4 viewport at mission start. The sprite sheets are
## decoded, and the particle and material pipelines compile, here instead of
## as a freeze on the first shot at a monitor, extinguisher, paper stack or pipe.
const SPARKS := preload("res://game/presentation/office_floor/electric_sparks.gd")
const BLAST := preload("res://game/presentation/office_floor/blast_effect.gd")
const PAPER := preload("res://game/presentation/office_floor/paper_shreds.gd")
const DEBRIS := preload("res://game/presentation/office_floor/debris_lifecycle.gd")
const WATER := preload("res://game/presentation/office_floor/water_spray_view.gd")
const EXTINGUISHER_FX := preload("res://game/presentation/office_floor/extinguisher_hit_fx.tscn")
const EXTINGUISHER_BURST := preload("res://game/presentation/office_floor/extinguisher_burst.tscn")
const SFX_EVENTS: Array[StringName] = [&"extinguisher_spray", &"extinguisher_burst", &"extinguisher_fall", &"hit_metal", &"hit_wood", &"hit_paper",
		&"hit_electronics", &"hit_glass", &"glass_break", &"fall_wood", &"fall_metal", &"fall_light", &"fall_tech", &"fall_debris", &"break_wood", &"break_furniture", &"break_cardboard", &"break_metal",
		&"break_electronics", &"break_lamp", &"weapon_switch"]
const AUDIO_WARMUP := preload("res://game/presentation/office_floor/audio_warmup.gd")
const FLIPBOOK := preload("res://game/core/vfx/public/sprite_flipbook.gd")
const ATLASES := preload("res://game/core/vfx/public/effect_atlases.gd")
const FRAMES := 4
const DISTANCE := 2.0

var effects_root: Node3D = self
var effect_count := 0
var _frames_left := FRAMES
var _viewport: SubViewport


func setup(parent: Node) -> void:
	_viewport = SubViewport.new()
	_viewport.name = "HitEffectWarmup"
	_viewport.size = Vector2i(4, 4)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera := Camera3D.new()
	camera.current = true
	_viewport.add_child(camera)
	name = "HitEffects"
	_viewport.add_child(self)
	parent.add_child(_viewport)
	var point := Vector3(0.0, 0.0, -DISTANCE)
	var direction := Vector3.UP
	SPARKS.short_circuit(self, point, Vector3.BACK)
	SPARKS.spawn(self, point, true)
	BLAST.smoke(self, point)
	PAPER.tear(self, point, direction)
	DEBRIS.dust_puff(self, point, 1.0)
	for atlas: Dictionary in [ATLASES.ELECTRIC_SPARK, ATLASES.TORN_PAPER, ATLASES.EXTINGUISHER_SPRAY]:
		if ATLASES.available(atlas):
			FLIPBOOK.spawn(self, atlas, point, 0.5, {})
	_warm_extinguisher(point)
	var droplet := MeshInstance3D.new()
	droplet.mesh = WATER._droplet_mesh()
	droplet.position = point
	droplet.scale = Vector3.ONE * 0.05
	add_child(droplet)
	effect_count = get_child_count()
	var audio := AUDIO_WARMUP.new()
	# Keep streams on the mission, beyond the four-frame visual viewport.
	parent.add_child(audio)
	audio.start(SFX_EVENTS)


# The first shot at an extinguisher streams its powder jet and mist, and the
# rupture blows the burst scene; both compile particle and powder shaders on
# first use, so they run here too (silent), and their sounds, with those of other props, are loaded ahead.
func _warm_extinguisher(point: Vector3) -> void:
	var jet := EXTINGUISHER_FX.instantiate() as Node3D
	add_child(jet)
	jet.position = point
	for emitter_path in ["Nozzle/Jet", "Nozzle/Mist"]:
		(jet.get_node(emitter_path) as GPUParticles3D).emitting = true
	var burst := EXTINGUISHER_BURST.instantiate() as Node3D
	burst.set("muted", true)
	burst.call("configure_world", self, null)
	add_child(burst)
	burst.position = point
	burst.call("start", 1.0, 1.0, 24)


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left <= 0:
		_viewport.queue_free()
