extends RefCounted
## Shadow quality presets for the video settings. Level 2 (High) equals the
## authored defaults (2048 atlas, 64 m) so a fresh install looks exactly as before.
##
## Only the atlas size and the range change at runtime. Switching the directional
## split mode, the soft-shadow filter or a light's shadow flag makes the renderer
## recompile the scene shaders (measured at 4-56 s each with the software renderer),
## which froze the menu on every slider step. "Off" therefore shrinks the sun's
## range to half a metre instead of disabling the light's shadow.

const WALL_BASE_SHADOW := preload("res://game/presentation/office_floor/public/wall_base_shadow.gd")
const DEFAULT_LEVEL := 2
const OFF_DISTANCE := 0.5
const LEVELS: Array[Dictionary] = [
	{"atlas": 1024, "distance": 32.0},
	{"atlas": 2048, "distance": 48.0},
	{"atlas": 2048, "distance": 80.0},
	{"atlas": 4096, "distance": 80.0},
]


static var _applied_atlas := -1


static func level_count() -> int:
	return LEVELS.size()


## Applies the on/off switch and the quality level to the running game.
static func apply(tree: SceneTree, enabled: bool, level: int) -> void:
	var preset := LEVELS[clampi(level, 0, LEVELS.size() - 1)]
	# Resizing an atlas reallocates it, and this runs on every settings change, so only do it when the size differs.
	if _applied_atlas != int(preset.atlas):
		_applied_atlas = int(preset.atlas)
		RenderingServer.directional_shadow_atlas_set_size(_applied_atlas, true)
	if tree == null:
		return
	if tree.root.positional_shadow_atlas_size != int(preset.atlas):
		tree.root.positional_shadow_atlas_size = int(preset.atlas)
	# Walls bake a contact strip on the floor only while real shadows are off.
	WALL_BASE_SHADOW.set_shadows_allowed(tree, enabled)
	var scene := tree.current_scene
	if scene == null:
		return
	var overhead := scene.get_node_or_null("GlobalOverheadLight") as DirectionalLight3D
	if overhead != null:
		overhead.directional_shadow_max_distance = float(preset.distance) if enabled else OFF_DISTANCE
	var lighting := scene.get_node_or_null("PlanningLighting")
	if lighting != null and lighting.has_method("set_shadows_allowed"):
		lighting.call("set_shadows_allowed", enabled)
	var wall := scene.get_node_or_null("DisplayWall")
	if wall != null and wall.has_method("set_shadows_allowed"):
		wall.call("set_shadows_allowed", enabled)
