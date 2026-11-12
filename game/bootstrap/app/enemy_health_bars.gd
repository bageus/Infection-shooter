extends Control
## Settings: a small health bar above each live enemy. One node draws every bar in screen space,
## and nothing runs while the setting is off.
const ALIVE_GROUP := &"infected_alive"
## Height above an enemy's origin, roughly over the head of the authored infected.
const BAR_HEIGHT := 2.1
const BAR_SIZE := Vector2(40.0, 5.0)
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
	for enemy in get_tree().get_nodes_in_group(ALIVE_GROUP):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var max_hp := float(body.get("max_health"))
		var hp := float(body.get("health"))
		if max_hp <= 0.0 or hp <= 0.0:
			continue
		var point := body.global_position + Vector3.UP * BAR_HEIGHT
		if camera.is_position_behind(point) or point.distance_to(camera.global_position) > MAX_DISTANCE:
			continue
		var origin := camera.unproject_position(point) - BAR_SIZE * 0.5
		draw_rect(Rect2(origin - Vector2.ONE, BAR_SIZE + Vector2(2.0, 2.0)), BACK_COLOR)
		draw_rect(Rect2(origin, Vector2(BAR_SIZE.x * clampf(hp / max_hp, 0.0, 1.0), BAR_SIZE.y)), FILL_COLOR)
