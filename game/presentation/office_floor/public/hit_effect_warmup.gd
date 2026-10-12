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
	for atlas: Dictionary in [ATLASES.ELECTRIC_SPARK, ATLASES.TORN_PAPER, ATLASES.EXTINGUISHER_SPRAY, ATLASES.GRENADE_EXPLOSION]:
		if ATLASES.available(atlas):
			FLIPBOOK.spawn(self, atlas, point, 0.5, {})
	var droplet := MeshInstance3D.new()
	droplet.mesh = WATER._droplet_mesh()
	droplet.position = point
	droplet.scale = Vector3.ONE * 0.05
	add_child(droplet)
	effect_count = get_child_count()


func _process(_delta: float) -> void:
	_frames_left -= 1
	if _frames_left <= 0:
		_viewport.queue_free()
