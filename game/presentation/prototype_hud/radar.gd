extends Control

@export var player_path: NodePath
@export var enemies_path: NodePath
@export var source_path: NodePath
@export var world_radius: float = 18.0

var player: Node3D
var enemies: Node
var source: Node3D


func _ready() -> void:
	player = get_node(player_path)
	enemies = get_node(enemies_path)
	source = get_node(source_path)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	draw_circle(center, radius + 8.0, Color(0.0, 0.18, 0.28, 0.92))
	draw_circle(center, radius, Color(0.008, 0.055, 0.09, 0.96))
	draw_arc(center, radius, 0.0, TAU, 72, Color(0.08, 0.85, 1.0, 1.0), 2.0)
	draw_arc(center, radius * 0.63, 0.0, TAU, 72, Color(0.07, 0.25, 0.34, 0.9), 1.0)
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), Color(0.08, 0.32, 0.42, 0.8), 1.0)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), Color(0.08, 0.32, 0.42, 0.8), 1.0)

	var heading := Vector2(0, -12)
	var left := Vector2(-7, 7)
	var right := Vector2(7, 7)
	draw_colored_polygon(PackedVector2Array([center + heading, center + left, center + right]), Color(0.08, 0.92, 1.0, 1.0))

	for enemy in enemies.get_children():
		if enemy is Node3D:
			_draw_blip(center, radius, enemy.global_position, Color(1.0, 0.1, 0.08, 1.0), 4.0)
	if source != null:
		_draw_blip(center, radius, source.global_position, Color(0.28, 1.0, 0.08, 1.0), 6.0)


func _draw_blip(center: Vector2, radius: float, world_position: Vector3, color: Color, blip_radius: float) -> void:
	var delta := world_position - player.global_position
	var point := Vector2(delta.x, delta.z) / world_radius * radius
	if point.length() > radius - 6.0:
		point = point.normalized() * (radius - 6.0)
	draw_circle(center + point, blip_radius, color)
