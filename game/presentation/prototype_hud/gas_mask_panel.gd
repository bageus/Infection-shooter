extends Panel
## Gas mask slot beside the antidote: bright while the mask is off, dimmed while worn,
## with a sweep that shows the cooldown before it can be taken off or put on again.

const COOLDOWN_SECONDS := 60.0
const ICON_COLOR := Color(0.8863, 0.8745, 0.8314, 1.0)
const WORN_ALPHA := 0.32
const SWEEP_COLOR := Color(0.0, 0.0, 0.0, 0.55)

var _worn := false
var _cooldown := 0.0


func set_state(worn: bool, cooldown_remaining: float) -> void:
	if worn == _worn and is_equal_approx(cooldown_remaining, _cooldown):
		return
	_worn = worn
	_cooldown = cooldown_remaining
	queue_redraw()


func _draw() -> void:
	var center := size * Vector2(0.5, 0.46)
	var radius := minf(size.x, size.y) * 0.22
	var color := ICON_COLOR
	color.a = WORN_ALPHA if _worn else 1.0
	# Face piece, two lenses, and the filter canister hanging below the chin.
	draw_arc(center, radius, 0.0, TAU, 40, color, 2.5, true)
	draw_circle(center + Vector2(-radius * 0.38, -radius * 0.12), radius * 0.16, color)
	draw_circle(center + Vector2(radius * 0.38, -radius * 0.12), radius * 0.16, color)
	draw_line(center + Vector2(0.0, radius), center + Vector2(0.0, radius + 9.0), color, 3.0, true)
	draw_rect(Rect2(center + Vector2(-radius * 0.45, radius + 9.0), Vector2(radius * 0.9, 9.0)), color)
	if _cooldown > 0.0:
		var fraction := clampf(_cooldown / COOLDOWN_SECONDS, 0.0, 1.0)
		var start := -PI * 0.5
		var points := PackedVector2Array([center])
		var steps := 24
		for index in range(steps + 1):
			var angle := start - TAU * fraction * float(index) / float(steps)
			points.append(center + Vector2(cos(angle), sin(angle)) * minf(size.x, size.y) * 0.5)
		draw_colored_polygon(points, SWEEP_COLOR)
