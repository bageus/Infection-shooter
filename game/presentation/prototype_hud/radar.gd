extends Control

const PALETTE := preload("res://game/presentation/prototype_hud/hud_palette.gd")

@export var player_path: NodePath
@export var enemies_path: NodePath
@export var camera_rig_path: NodePath
@export var world_radius: float = 18.0

var player: Node3D
var enemies: Node
var camera_rig: Node3D
const REFRESH_SECONDS := .05
var _refresh_remaining := 0.0
var _background: RadarBackground

class RadarBackground:
	extends Control
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.42
		draw_circle(center, radius, PALETTE.TRACK)
		draw_arc(center, radius, 0.0, TAU, 72, PALETTE.BORDER, 1.0, true)
		draw_arc(center, radius * 0.63, 0.0, TAU, 72, PALETTE.BORDER_DIM, 1.0, true)
		draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), PALETTE.BORDER_DIM, 1.0)
		draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), PALETTE.BORDER_DIM, 1.0)



func _ready() -> void:
	_background = RadarBackground.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.show_behind_parent = true
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)
	player = get_node(player_path)
	enemies = get_node(enemies_path)
	camera_rig = get_node(camera_rig_path)
	queue_redraw()


func _on_resized() -> void:
	_background.queue_redraw()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_refresh_remaining = 0.0
		return
	_refresh_remaining -= delta
	if _refresh_remaining <= 0.0:
		_refresh_remaining = REFRESH_SECONDS
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.42

	# Marks keep their proportions as the radar is resized (authored at 230 px).
	var scale_factor := clampf(radius / 96.0, 0.5, 1.0)
	var heading := Vector2(0, -11) * scale_factor
	var left := Vector2(-6, 7) * scale_factor
	var right := Vector2(6, 7) * scale_factor
	draw_colored_polygon(PackedVector2Array([center + heading, center + left, center + right]), PALETTE.INK)

	_draw_enemies(center, radius, scale_factor)


func _draw_enemies(center: Vector2, radius: float, scale_factor: float) -> void:
	for enemy in enemies.get_children():
		if _is_radar_target(enemy):
			_draw_blip(center, radius, enemy.global_position, PALETTE.WARNING, 3.5 * scale_factor)


func _is_radar_target(enemy: Node) -> bool:
	# Infected owns alive membership, removing it before retained corpse effects.
	# Scene visibility is intentional hiding; being outside the camera is not.
	return enemy is Node3D and enemy.is_in_group(&"infected_alive") \
		and not enemy.is_queued_for_deletion() and enemy.is_visible_in_tree()


func _draw_blip(center: Vector2, radius: float, world_position: Vector3, color: Color, blip_radius: float) -> void:
	var point := _to_radar(world_position, radius)
	var edge := radius - blip_radius - 2.0
	if point.length() > edge:
		point = point.normalized() * edge
	draw_circle(center + point, blip_radius, color)


# Radar is camera-relative: up is the view direction, so turning the camera turns the blips.
func _to_radar(world_position: Vector3, radius: float) -> Vector2:
	var local := camera_rig.global_basis.inverse() * (world_position - player.global_position)
	return Vector2(local.x, local.z) / world_radius * radius
