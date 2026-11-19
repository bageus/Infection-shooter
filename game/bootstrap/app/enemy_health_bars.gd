extends Control
## Settings: a small health bar above each live enemy in the hero's room. One node draws every bar in screen space,
## and nothing runs while the setting is off.
const ALIVE_GROUP := &"infected_alive"
## Bars sit this far above the top of each enemy's collision capsule, which matches the authored
## model top for hunger, brute, colossus and titan (measured in headless rest pose).
const BAR_MARGIN := 0.3
const BAR_SIZE := Vector2(40.0, 5.0)
## The bar width follows max health on a log scale: LOW_HEALTH (hunger) gets BAR_SIZE.x, HIGH_HEALTH (horde) gets MAX_BAR_WIDTH.
const MAX_BAR_WIDTH := 220.0
const LOW_HEALTH := 45.0
const HIGH_HEALTH := 2700.0
## Bars past this distance are too small to read and cost a projection each, so they are skipped.
const MAX_DISTANCE := 40.0
## shortcut: a fixed 0.6 m reach past a fogged footprint, not measured from the fog shader; upgrade if bars still float over fog
const COVER_MARGIN := 0.6
const SHADER := preload("res://game/bootstrap/app/enemy_health_bar.gdshader")

var camera: Camera3D


func setup(view: Camera3D) -> void:
	camera = view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	material = ShaderMaterial.new()
	material.shader = SHADER
	set_enabled(false)


func set_enabled(value: bool) -> void:
	visible = value
	set_process(value)
	if not value:
		queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	var hero := get_tree().get_first_node_in_group("player") as Node3D
	var hero_rooms := rooms_at(get_tree(), hero.global_position) if hero != null else []
	for enemy in get_tree().get_nodes_in_group(ALIVE_GROUP):
		var body := enemy as Node3D
		# A body hidden by a closed room's cover (or by anything else) must not leave its bar floating over the fog.
		if body == null or not body.is_inside_tree() or not body.is_visible_in_tree():
			continue
		if hero != null and not same_room(hero_rooms, rooms_at(get_tree(), body.global_position)):
			continue
		if covered_by_other_room(get_tree(), body.global_position, hero_rooms):
			continue
		var max_hp := float(body.get("max_health"))
		var hp := float(body.get("health"))
		if max_hp <= 0.0 or hp <= 0.0:
			continue
		var point := body.global_position + Vector3.UP * _bar_height(body)
		var distance := point.distance_to(camera.global_position)
		if camera.is_position_behind(point) or distance > MAX_DISTANCE:
			continue
		var bar := Vector2(bar_width(max_hp), BAR_SIZE.y)
		var origin := camera.unproject_position(point) - bar * 0.5
		# NaN, or the huge coordinates of a point grazing the camera plane, make the quad untriangulatable.
		if not (origin.is_finite() and is_finite(hp / max_hp)) or not Rect2(Vector2.ZERO, get_viewport_rect().size).grow(bar.x).intersects(Rect2(origin, bar)):
			continue
		_draw_bar(Rect2(origin, bar), clampf(hp / max_hp, 0.0, 1.0))


## A covered room's fog darkens the screen around its enemies, and the bar is drawn in screen space on top of it.
## A point near a fogged zone the hero is not in counts as covered (the margin takes in the body the fog hides).
static func covered_by_other_room(tree: SceneTree, point: Vector3, hero_rooms: Array) -> bool:
	for zone: Node in tree.get_nodes_in_group("darkness_zone"):
		var overlay := zone.get("overlay") as MeshInstance3D
		if overlay == null or not overlay.visible or float(zone.call("_edge_distance", point)) > COVER_MARGIN:
			continue
		var id: int = zone.get("room_id")
		if not hero_rooms.has(id if id > 0 else -zone.get_instance_id()):
			return true
	return false


## Darkness zones covering a point: a room is one id however many zones it has, a lone zone counts as its own room.
static func rooms_at(tree: SceneTree, point: Vector3) -> Array:
	var rooms := []
	for zone: Node in tree.get_nodes_in_group("darkness_zone"):
		if bool(zone.call("_edge_distance", point) <= 0.0):
			var id: int = zone.get("room_id")
			rooms.append(id if id > 0 else -zone.get_instance_id())
	return rooms


## Outside every zone counts as one open area; otherwise the two must share a room.
static func same_room(first: Array, second: Array) -> bool:
	if first.is_empty() or second.is_empty():
		return first.is_empty() and second.is_empty()
	return first.any(func(room: int) -> bool: return second.has(room))


static func bar_width(max_hp: float) -> float:
	var t := clampf(log(maxf(max_hp, 1.0) / LOW_HEALTH) / log(HIGH_HEALTH / LOW_HEALTH), 0.0, 1.0)
	return lerpf(BAR_SIZE.x, MAX_BAR_WIDTH, t)


## One quad per bar; the shader reads the health fraction from the vertex colour.
func _draw_bar(rect: Rect2, fraction: float) -> void:
	var points := PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var tint := Color(fraction, 0.0, 0.0, 1.0)
	draw_polygon(points, PackedColorArray([tint, tint, tint, tint]), uvs)


## Each enemy type has its own capsule, so the bar follows the type instead of a fixed height.
static func _bar_height(body: Node3D) -> float:
	var capsule := _capsule(body)
	if capsule == null:
		return 1.0 + BAR_MARGIN
	# Root-to-feet distance: the collision capsule may sit off-centre (titan, colossus).
	var shape := body.find_child("CollisionShape3D", false, false) as CollisionShape3D
	return capsule.height * 0.5 - shape.position.y + BAR_MARGIN


static func _capsule(body: Node3D) -> CapsuleShape3D:
	var shape := body.find_child("CollisionShape3D", false, false) as CollisionShape3D
	return shape.shape as CapsuleShape3D if shape != null else null
