extends Node

@export var local_lights_enabled := false:
	set(value):
		local_lights_enabled = value
		if is_inside_tree():
			_apply_local_lights()
		if is_instance_valid(_local_toggle):
			_local_toggle.set_pressed_no_signal(value)

var _local_toggle: CheckButton
var _scene_tree: SceneTree
var world_environment: WorldEnvironment
var _saved_energy := 0.0
var _saved_source := Environment.AMBIENT_SOURCE_DISABLED
var _saved_color := Color.WHITE
var _saved_reflected := Environment.REFLECTION_SOURCE_DISABLED
var _game_lights_only := false
var _planning := false
var _game_lighting := true
# Compatibility renders only a fixed number of lights per frame and silently drops
# the rest, so only the lamps nearest to the camera are lit (and shadowed).
const MAX_LIGHTS := 28
## Every lit lamp casts a shadow, but only walls cast it (shadow_caster_mask), so the pass stays
## cheap and the light stops at walls without touching the lamp angle.
const MAX_SHADOW_LIGHTS := MAX_LIGHTS
## Visual layer carrying wall meshes for lamp shadows; must match planner_light.WALL_CASTER_LAYER.
const WALL_CASTER_LAYER := 1 << 19
const REFRESH_SECONDS := 0.15
## A lamp is lit while its light sphere (grown by a margin) touches the view, so a lamp
## switches on before it appears: ENTER_MARGIN covers a fast camera turn over one refresh,
## the larger LEAVE_MARGIN keeps a lit lamp on until it is clearly gone (hysteresis).
const ENTER_MARGIN := 6.0
const LEAVE_MARGIN := 9.0
## Lamps in view but past the budget get a flat additive pool on the floor instead.
## The pool matches the lamp's floor footprint (radius) and brightness (strength); the constants are fallbacks.
const POOL_RADIUS := 2.5
const POOL_STRENGTH := 0.5
const POOL_HEIGHT := 0.03
var _pool: MultiMeshInstance3D
var shadows_allowed := true
var _refresh_left := 0.0
var _shadow_owners := {}
## Lamps lit-eligible last refresh (margin included), and those whose light touches the view itself.
var _near_view := {}
var _in_view := {}
var _cached_lamps: Array[Node] = []
var _positions := PackedVector3Array()
var _radii: Array[float] = []
var _costs := PackedInt32Array()
var _cached_view: Array = []
var _cached_shadows := false
var _budget_valid := false
var _settling := false


func setup(environment_node: WorldEnvironment, selector: OptionButton = null, local_toggle: CheckButton = null) -> void:
	if world_environment == environment_node:
		return
	if _planning:
		_restore_ambient()
	_local_toggle = local_toggle
	if _local_toggle != null:
		_local_toggle.set_pressed_no_signal(local_lights_enabled)
		_local_toggle.toggled.connect(set_local_lights_enabled)
	_scene_tree = get_tree()
	if not _scene_tree.node_added.is_connected(_on_node_added):
		_scene_tree.node_added.connect(_on_node_added)
	_apply_local_lights()
	world_environment = environment_node
	_planning = false
	if world_environment != null and world_environment.environment != null:
		# Editor illumination must never mutate the shared scene resource.
		world_environment.environment = world_environment.environment.duplicate() as Environment
		_capture_ambient()
	if selector != null:
		selector.select(0 if _game_lighting else 1)
		selector.item_selected.connect(_on_preview_selected)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_SECONDS
		var view := _view_state(get_viewport().get_camera_3d()) if local_lights_enabled else []
		if local_lights_enabled and view != _cached_view:
			_cached_view = view
			# During camera motion ranking already runs; capture once after it stops.
			refresh_light_budget(false)
		elif _budget_changed():
			refresh_light_budget()


## Poll only budget inputs; avoid ranking, frustum construction and lamp writes at rest.
func _budget_changed() -> bool:
	if not local_lights_enabled:
		return false
	if not _budget_valid or _settling or shadows_allowed != _cached_shadows:
		return true
	var lamps := get_tree().get_nodes_in_group("budget_lights")
	if lamps != _cached_lamps:
		return true
	for index in lamps.size():
		var lamp := lamps[index]
		if not lamp is Node3D or not lamp.has_method("set_budget_lit"):
			if _costs[index] != -1:
				return true
			continue
		if (lamp as Node3D).global_position != _positions[index] \
			or _light_radius(lamp) != _radii[index] or int(lamp.call("get_light_cost")) != _costs[index]:
			return true
	return false


func _remember_inputs(lamps: Array[Node]) -> void:
	_cached_lamps = lamps
	_positions.resize(lamps.size())
	_radii.resize(lamps.size())
	_costs.resize(lamps.size())
	for index in lamps.size():
		var lamp := lamps[index]
		_costs[index] = -1
		if lamp is Node3D and lamp.has_method("set_budget_lit"):
			_positions[index] = (lamp as Node3D).global_position
			_radii[index] = _light_radius(lamp)
			_costs[index] = int(lamp.call("get_light_cost"))


func _view_state(camera: Camera3D) -> Array:
	return [] if camera == null else [camera.get_instance_id(), camera.global_transform,
		camera.get_camera_transform(), camera.get_camera_projection()]


func set_shadows_allowed(allowed: bool) -> void:
	shadows_allowed = allowed
	refresh_light_budget()


## Ground point the camera looks at; lamps are ranked by distance to it.
func get_light_focus() -> Vector3:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return Vector3.ZERO
	var focus := camera.global_position
	var forward := -camera.global_transform.basis.z
	if forward.y < -0.05:
		focus += forward * (camera.global_position.y / -forward.y)
	return focus


## Lights the lamps nearest to the camera focus first until the budget is spent;
## the nearest few also cast shadows so light does not pass through walls and columns.
func refresh_light_budget(capture_inputs: bool = true) -> void:
	var tree := get_tree()
	if tree == null or not local_lights_enabled:
		if _pool != null:
			_pool.visible = false
		return
	var focus := get_light_focus()
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	var frustum: Array = camera.get_frustum() if camera != null else []
	var lamps: Array[Node] = tree.get_nodes_in_group("budget_lights")
	var ranked: Array[Dictionary] = []
	var near_view := {}
	var in_view := {}
	for lamp in lamps:
		if lamp is Node3D and lamp.is_inside_tree() and lamp.has_method("set_budget_lit"):
			var id := lamp.get_instance_id()
			var at := (lamp as Node3D).global_position
			var reach := _light_radius(lamp)
			var margin := LEAVE_MARGIN if _near_view.has(id) else ENTER_MARGIN
			if not frustum.is_empty() and not sphere_in_view(frustum, at, reach + margin):
				lamp.call("set_budget_lit", false, false)
				continue
			near_view[id] = true
			var seen := frustum.is_empty() or sphere_in_view(frustum, at, reach)
			if seen:
				in_view[id] = true
			var offset: Vector3 = at - focus
			offset.y = 0.0
			# Lamps on screen come first; the focus distance only orders them past the budget.
			ranked.append({"node": lamp, "seen": seen, "rank": offset.length_squared() + (0.0 if seen else 1.0e9)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rank < b.rank)
	var used := 0
	var shadowed := 0
	var owners := {}
	var unlit: Array[Node] = []
	for entry in ranked:
		var lamp: Node = entry.node
		var cost: int = lamp.call("get_light_cost")
		var lit := used + cost <= MAX_LIGHTS
		var shadow: bool = lit and shadows_allowed and shadowed + cost <= MAX_SHADOW_LIGHTS
		if lit:
			used += cost
		elif entry.seen:
			unlit.append(lamp)
		if shadow:
			shadowed += cost
			owners[lamp.get_instance_id()] = true
		lamp.call("set_budget_lit", lit, shadow)
	_near_view = near_view
	_in_view = in_view
	_settling = _shadow_owners != owners
	_shadow_owners = owners
	_cached_shadows = shadows_allowed
	_budget_valid = capture_inputs
	if capture_inputs:
		_cached_view = _view_state(camera)
		_remember_inputs(lamps)
	_update_pools(unlit)


## Draws one flat light pool per in-view lamp that the budget left dark.
func _update_pools(unlit: Array[Node]) -> void:
	if _pool == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color.WHITE)
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		# A quadratic-like fall-off reaches zero gently, so the pool leaves no rim next to a lit lamp.
		gradient.add_point(0.5, Color(1.0, 1.0, 1.0, 0.25))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_texture = texture
		material.vertex_color_use_as_albedo = true
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * 2.0
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = quad
		_pool = MultiMeshInstance3D.new()
		_pool.multimesh = multimesh
		_pool.material_override = material
		add_child(_pool)
	var floor_turn := Basis(Vector3.RIGHT, -PI * 0.5)
	_pool.multimesh.instance_count = unlit.size()
	for index in unlit.size():
		var lamp := unlit[index] as Node3D
		var at := lamp.global_position
		var footprint: Vector2 = lamp.call("get_pool_footprint") if lamp.has_method("get_pool_footprint") \
			else Vector2(POOL_RADIUS, POOL_STRENGTH)
		_pool.multimesh.set_instance_transform(index, Transform3D(floor_turn.scaled(Vector3.ONE * footprint.x), Vector3(at.x, POOL_HEIGHT, at.z)))
		var color: Color = lamp.get("light_color")
		_pool.multimesh.set_instance_color(index, color * footprint.y)
	_pool.visible = local_lights_enabled


func _light_radius(lamp: Node) -> float:
	return float(lamp.call("get_light_radius")) if lamp.has_method("get_light_radius") else INF


## True when a sphere touches the volume bounded by the camera frustum planes.
static func sphere_in_view(frustum: Array, center: Vector3, radius: float) -> bool:
	for plane in frustum:
		if plane.distance_to(center) > radius:
			return false
	return true


func set_local_lights_enabled(enabled: bool) -> void:
	local_lights_enabled = enabled


func _apply_local_lights() -> void:
	for lamp: Node in get_tree().get_nodes_in_group("budget_lights"):
		_on_node_added(lamp)
	for wall: Node in get_tree().get_nodes_in_group("camera_occluder"):
		_on_node_added(wall)
	refresh_light_budget()


func _on_node_added(node: Node) -> void:
	# Late map loads and planner duplicates obey the same application setting.
	if node.is_in_group("budget_lights") and node.has_method("set_local_lighting_enabled"):
		node.call("set_local_lighting_enabled", local_lights_enabled)
	# Meshes are instanced under the wall after it enters the tree, so tag them a frame later.
	if node.is_in_group("camera_occluder") and node is Node3D:
		_tag_wall_casters.call_deferred(node)


## Solid walls and columns cast lamp shadows; glass and anything breakable lets light through.
func _tag_wall_casters(wall) -> void:
	# Untyped: a wall freed before this deferred call must fail the validity check, not argument conversion.
	if not is_instance_valid(wall) or _has_glass(wall):
		return
	for mesh in wall.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).layers |= WALL_CASTER_LAYER
		# A one-sided wall must still shadow a lamp standing behind its back face.
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


func _has_glass(node: Node) -> bool:
	return node.is_in_group("infected_breakable_glass") or node.get_children().any(_has_glass)


func set_planning_mode(enabled: bool) -> void:
	if world_environment == null or world_environment.environment == null or enabled == _planning:
		return
	if enabled:
		_capture_ambient()
	_planning = enabled
	_apply_preview()


func _on_preview_selected(index: int) -> void:
	set_game_lighting(index == 0)


func set_game_lighting(enabled: bool) -> void:
	_game_lighting = enabled
	if _planning:
		_apply_preview()


func set_game_lights_only(enabled: bool) -> void:
	_game_lights_only = enabled
	_apply_preview()


func _capture_ambient() -> void:
	if _game_lights_only:
		return
	var environment := world_environment.environment
	_saved_source = environment.ambient_light_source
	_saved_color = environment.ambient_light_color
	_saved_energy = environment.ambient_light_energy
	_saved_reflected = environment.reflected_light_source


func _apply_preview() -> void:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	_restore_ambient()
	if _game_lights_only:
		var environment := world_environment.environment
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		environment.ambient_light_energy = 0.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	elif _planning and not _game_lighting:
		var environment := world_environment.environment
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.62, 0.68, 0.78, 1.0)
		environment.ambient_light_energy = 0.38


func _restore_ambient() -> void:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	var environment := world_environment.environment
	environment.ambient_light_source = _saved_source
	environment.ambient_light_color = _saved_color
	environment.ambient_light_energy = _saved_energy
	environment.reflected_light_source = _saved_reflected


func _exit_tree() -> void:
	if _scene_tree != null and _scene_tree.node_added.is_connected(_on_node_added):
		_scene_tree.node_added.disconnect(_on_node_added)
	if _planning:
		_restore_ambient()
