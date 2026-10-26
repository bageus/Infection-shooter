extends RefCounted
## Finite save-time diffuse lighting for floor biomass, including structural shadows.
const GRID := 33
const METERS := 8.0
var lamps: Array[Dictionary] = []
var ambient := Color(0.25, 0.25, 0.25)
var world: World3D
var tree: SceneTree
var alive: Callable


func configure(host: Node3D, check: Callable) -> void:
	world = host.get_world_3d()
	tree = host.get_tree()
	alive = check
	var controller := host.get_node_or_null("PlanningLighting")
	var environment: WorldEnvironment = controller.get("world_environment") if controller != null else null
	if environment != null and environment.environment != null:
		var env := environment.environment
		ambient = env.ambient_light_color * env.ambient_light_energy
		if bool(controller.get("_planning")):
			ambient = (controller.get("_saved_color") as Color) * float(controller.get("_saved_energy"))
		if bool(controller.get("_game_lights_only")): ambient = Color(0, 0, 0)
	for node: Node in host.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light.is_visible_in_tree() and light.light_energy > 0.0:
			lamps.append({"directional": true, "direction": -light.global_basis.z.normalized(), "color": light.light_color, "energy": light.light_energy})
	if controller == null or not bool(controller.get("local_lights_enabled")): return
	for fixture: Node in tree.get_nodes_in_group("budget_lights"):
		if not host.is_ancestor_of(fixture): continue
		var spots := fixture.find_children("*", "SpotLight3D", true, false)
		# Match planner_light's authored split, independent of runtime fade/flicker.
		var share := 1.0 if spots.size() <= 1 else 0.7 / float(spots.size())
		for node: Node in spots:
			var light := node as SpotLight3D
			var energy := float(fixture.call("get_authored_energy")) * float(fixture.get("energy_multiplier")) * share if fixture.has_method("get_authored_energy") else light.light_energy
			lamps.append({"position": light.global_position, "direction": -light.global_basis.z.normalized(), "color": light.light_color, "energy": energy, "range": light.spot_range, "angle": cos(deg_to_rad(light.spot_angle)), "cone": light.spot_angle_attenuation, "attenuation": light.spot_attenuation})


func sample(cell: Vector2i, height: float) -> Image:
	var image := Image.create(GRID, GRID, false, Image.FORMAT_RGB8)
	var nearby: Array[Dictionary] = []
	var center := Vector3((cell.x + 0.5) * METERS, height, (cell.y + 0.5) * METERS)
	for lamp in lamps:
		if lamp.get("directional", false) or center.distance_to(lamp.position) < float(lamp.range) + METERS: nearby.append(lamp)
	for z in GRID:
		for x in GRID:
			var point := Vector3((cell.x + float(x) / (GRID - 1)) * METERS, height + 0.025, (cell.y + float(z) / (GRID - 1)) * METERS)
			var color := ambient
			for lamp in nearby:
				var contribution := diffuse(lamp, point)
				var target: Vector3 = point - (lamp.direction as Vector3) * 100.0 if lamp.get("directional", false) else lamp.position
				# Structural occlusion belongs to saved pixels, not dynamic shadow settings.
				if contribution.get_luminance() > 0.001 and not _blocked(point, target): color += contribution
			image.set_pixel(x, z, Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0), clampf(color.b, 0.0, 1.0)))
		await tree.process_frame
		if not alive.call(): return null
	return image


static func diffuse(lamp: Dictionary, point: Vector3) -> Color:
	if lamp.get("directional", false): return (lamp.color as Color) * float(lamp.energy) * maxf(-(lamp.direction as Vector3).y, 0.0)
	var offset: Vector3 = point - lamp.position
	var distance := offset.length()
	if distance >= float(lamp.range) or distance < 0.001: return Color(0, 0, 0)
	var direction := offset / distance
	var cone := direction.dot(lamp.direction)
	if cone <= float(lamp.angle): return Color(0, 0, 0)
	var angular := pow(clampf((cone - float(lamp.angle)) / maxf(1.0 - float(lamp.angle), 0.001), 0.0, 1.0), maxf(float(lamp.cone), 0.01))
	var attenuation := pow(maxf(1.0 - distance / float(lamp.range), 0.0), float(lamp.attenuation))
	return (lamp.color as Color) * float(lamp.energy) * attenuation * angular * maxf(-direction.y, 0.0)


func _blocked(point: Vector3, target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point, target, 7)
	var excluded: Array[RID] = []
	for attempt in 32:
		query.exclude = excluded
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty(): return false
		var node := hit.collider as Node
		while node != null:
			if node.is_in_group("camera_occluder"): return true
			node = node.get_parent()
		excluded.append(hit.rid)
	return true
