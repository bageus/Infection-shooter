extends Control
## Settings: a small health bar above each live enemy. One node draws every bar in screen space,
## and nothing runs while the setting is off.
const ALIVE_GROUP := &"infected_alive"
## Bars sit this far above the top of each enemy's collision capsule, which matches the authored
## model top for hunger, brute, colossus and titan (measured in headless rest pose).
const BAR_MARGIN := 0.3
const BAR_SIZE := Vector2(40.0, 5.0)
## Big enemies get a wider bar up to this many pixels, scaled to their collision width.
const MAX_BAR_WIDTH := 220.0
## Bars past this distance are too small to read and cost a projection each, so they are skipped.
const MAX_DISTANCE := 40.0
const BACK_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const FILL_COLOR := Color(0.86, 0.22, 0.22, 0.95)

var camera: Camera3D


func setup(view: Camera3D) -> void:
	camera = view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	var pixels_per_tan := size.y * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
	for enemy in get_tree().get_nodes_in_group(ALIVE_GROUP):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var max_hp := float(body.get("max_health"))
		var hp := float(body.get("health"))
		if max_hp <= 0.0 or hp <= 0.0:
			continue
		var point := body.global_position + Vector3.UP * _bar_height(body)
		var distance := point.distance_to(camera.global_position)
		if camera.is_position_behind(point) or distance > MAX_DISTANCE:
			continue
		# Pixels per metre at this distance, so the bar matches the enemy's width on screen.
		var pixels := clampf(_body_width(body) * pixels_per_tan / distance, BAR_SIZE.x, MAX_BAR_WIDTH)
		var bar := Vector2(pixels, BAR_SIZE.y)
		var origin := camera.unproject_position(point) - bar * 0.5
		draw_rect(Rect2(origin - Vector2.ONE, bar + Vector2(2.0, 2.0)), BACK_COLOR)
		draw_rect(Rect2(origin, Vector2(bar.x * clampf(hp / max_hp, 0.0, 1.0), bar.y)), FILL_COLOR)


## Each enemy type has its own capsule, so the bar follows the type instead of a fixed height.
static func _bar_height(body: Node3D) -> float:
	var capsule := _capsule(body)
	return (capsule.height * 0.5 if capsule != null else 1.0) + BAR_MARGIN


## Width of the enemy's collision capsule in metres (the horde's is wide, so its bar is too).
static func _body_width(body: Node3D) -> float:
	var capsule := _capsule(body)
	return capsule.radius * 2.0 if capsule != null else 1.0


static func _capsule(body: Node3D) -> CapsuleShape3D:
	var shape := body.find_child("CollisionShape3D", false, false) as CollisionShape3D
	return shape.shape as CapsuleShape3D if shape != null else null
