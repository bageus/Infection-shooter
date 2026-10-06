extends Control

const PALETTE := preload("res://game/presentation/prototype_hud/hud_palette.gd")

@export var player_path: NodePath
@export var enemies_path: NodePath
@export var world_radius: float = 18.0

var player: Node3D
var enemies: Node
const REFRESH_SECONDS := .05
var _refresh_remaining := 0.0
var _background: RadarBackground

class RadarBackground:
	extends Control
	var frame := StyleBoxFlat.new()
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.42
		draw_style_box(frame, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(0, 0, 3, size.y), PALETTE.ACCENT)
		draw_circle(center, radius, PALETTE.TRACK)
		draw_arc(center, radius, 0.0, TAU, 72, PALETTE.BORDER, 1.0, true)
		draw_arc(center, radius * 0.63, 0.0, TAU, 72, PALETTE.BORDER_DIM, 1.0, true)
		draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), PALETTE.BORDER_DIM, 1.0)
		draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), PALETTE.BORDER_DIM, 1.0)



func _ready() -> void:
	_background = RadarBackground.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.show_behind_parent = true
	_background.frame.bg_color = PALETTE.PANEL
	_background.frame.border_color = PALETTE.BORDER
	_background.frame.set_border_width_all(1)
	_background.frame.shadow_color = Color(0, 0, 0, 0.35)
	_background.frame.shadow_size = 8
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)
	player = get_node(player_path)
	enemies = get_node(enemies_path)
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

	var heading := Vector2(0, -11)
	var left := Vector2(-6, 7)
	var right := Vector2(6, 7)
	draw_colored_polygon(PackedVector2Array([center + heading, center + left, center + right]), PALETTE.INK)

	for enemy in enemies.get_children():
		if enemy is Node3D:
			_draw_blip(center, radius, enemy.global_position, PALETTE.WARNING, 3.5)


func _draw_blip(center: Vector2, radius: float, world_position: Vector3, color: Color, blip_radius: float) -> void:
	var delta := world_position - player.global_position
	var point := Vector2(delta.x, delta.z) / world_radius * radius
	if point.length() > radius - 6.0:
		point = point.normalized() * (radius - 6.0)
	draw_circle(center + point, blip_radius, color)
