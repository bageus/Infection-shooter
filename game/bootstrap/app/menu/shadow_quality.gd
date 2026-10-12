extends RefCounted
## Shadow quality presets for the video settings. Level 2 (High) equals the
## authored defaults (2048 atlas, soft low, 64 m, two splits) so a fresh install
## looks exactly as before; lower levels shrink the atlas, filter and distance.

const DEFAULT_LEVEL := 2
const LEVELS: Array[Dictionary] = [
	{"atlas": 1024, "filter": RenderingServer.SHADOW_QUALITY_HARD, "distance": 32.0, "mode": DirectionalLight3D.SHADOW_ORTHOGONAL},
	{"atlas": 2048, "filter": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "distance": 48.0, "mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS},
	{"atlas": 2048, "filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "distance": 64.0, "mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS},
	{"atlas": 4096, "filter": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "distance": 64.0, "mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS},
]


static func level_count() -> int:
	return LEVELS.size()


## Applies the on/off switch and the quality level to the running game.
static func apply(tree: SceneTree, enabled: bool, level: int) -> void:
	var preset := LEVELS[clampi(level, 0, LEVELS.size() - 1)]
	RenderingServer.directional_shadow_atlas_set_size(int(preset.atlas), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(preset.filter))
	RenderingServer.positional_soft_shadow_filter_set_quality(int(preset.filter))
	if tree == null:
		return
	tree.root.positional_shadow_atlas_size = int(preset.atlas)
	var scene := tree.current_scene
	if scene == null:
		return
	var overhead := scene.get_node_or_null("GlobalOverheadLight") as DirectionalLight3D
	if overhead != null:
		overhead.shadow_enabled = enabled
		overhead.directional_shadow_mode = preset.mode
		overhead.directional_shadow_max_distance = float(preset.distance)
	var lighting := scene.get_node_or_null("PlanningLighting")
	if lighting != null and lighting.has_method("set_shadows_allowed"):
		lighting.call("set_shadows_allowed", enabled)
	var wall := scene.get_node_or_null("DisplayWall")
	if wall != null and wall.has_method("set_shadows_allowed"):
		wall.call("set_shadows_allowed", enabled)
