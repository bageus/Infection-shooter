extends Control

@export var clear_radius := 360.0
@export var feather := 220.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var outer := maxf(size.x, size.y) * 0.85
	draw_circle(center, outer, Color(0.005, 0.01, 0.025, 0.72))
	var steps := 18
	for i in steps:
		var t := float(i) / float(steps - 1)
		var radius := clear_radius + feather * (1.0 - t)
		var alpha := 0.72 * t / float(steps)
		draw_circle(center, radius, Color(0.005, 0.01, 0.025, -alpha))
