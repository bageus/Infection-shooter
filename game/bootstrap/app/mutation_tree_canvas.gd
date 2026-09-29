extends Control

const BRANCHES := [
	"Biomass", "Neural Storm", "Toxic Mutation", "Predator Form",
	"Arsenal", "Predator", "Biomass", "Adaptation", "Neural System", "Metabolism"
]
const TRUNK_Y := 420.0
const HYBRID_PARENTS := [[4, 5], [5, 6], [6, 7], [7, 8], [8, 9], [9, 4]]

var progress: Array[int] = []
var hybrids: Array[bool] = []
var thresholds: Array[float] = []
var mutation := 0.0


func _ready() -> void:
	size = Vector2(1280, 900)
	mouse_filter = Control.MOUSE_FILTER_PASS


func configure_progression(values: Array[float], amount: float) -> void:
	thresholds = values.duplicate()
	mutation = amount
	queue_redraw()


func set_mutation(amount: float) -> void:
	mutation = amount
	queue_redraw()


func _threshold_x(value: float) -> float:
	return 100.0 + clampf((value - 25.0) / 75.0, 0.0, 1.0) * 1100.0


func branch_origin(index: int) -> Vector2:
	return Vector2(_threshold_x(thresholds[index]), TRUNK_Y)


func skill_position(branch_index: int, rank: int) -> Vector2:
	var x := _threshold_x(thresholds[branch_index] + float(rank) * 5.0)
	var y := 330.0 - rank * 85.0 if branch_index < 4 else 510.0 + rank * 75.0
	# The final stage opens two passive branches, with distinct parallel lanes.
	if branch_index == 8:
		x = _threshold_x(thresholds[branch_index]) + rank * 40.0
		y = 500.0 + rank * 60.0
	elif branch_index == 9:
		x = 1140.0 + rank * 35.0
		y = 540.0 + rank * 70.0
	return Vector2(x, y)


func label_position(index: int) -> Vector2:
	var center := skill_position(index, 0)
	var x := clampf(center.x - 78.0, 12.0, 1100.0)
	return Vector2(x, 95.0 if index < 4 else (745.0 if index == 9 else 705.0))


func hybrid_position(index: int) -> Vector2:
	return Vector2(145.0 + index * 195.0, 835.0)


func set_progress(new_progress: Array[int], new_hybrids: Array[bool]) -> void:
	progress = new_progress.duplicate()
	hybrids = new_hybrids.duplicate()
	queue_redraw()


func _draw() -> void:
	if thresholds.size() != BRANCHES.size():
		return
	var dim := Color(0.28, 0.35, 0.42, 0.9)
	var lit := Color(0.29, 0.88, 0.67, 0.95)
	draw_line(Vector2(60, TRUNK_Y), Vector2(1200, TRUNK_Y), dim, 9.0, true)
	if mutation >= 25.0:
		draw_line(Vector2(60, TRUNK_Y), Vector2(_threshold_x(mutation), TRUNK_Y), lit, 6.0, true)
	for index in BRANCHES.size():
		var start := branch_origin(index)
		for rank in range(3):
			var end := skill_position(index, rank)
			draw_line(start, end, dim, 6.0, true)
			if index < progress.size() and progress[index] >= rank:
				draw_line(start, end, lit, 4.0, true)
			start = end
	for index in HYBRID_PARENTS.size():
		var shade := lit if index < hybrids.size() and hybrids[index] else Color(0.36, 0.46, 0.53, 0.22)
		for parent in HYBRID_PARENTS[index]:
			_dotted(skill_position(parent, 2), hybrid_position(index), shade)
	var font := ThemeDB.fallback_font
	for level in [25, 40, 55, 70, 85, 100]:
		var x := _threshold_x(level)
		draw_line(Vector2(x, TRUNK_Y - 8), Vector2(x, TRUNK_Y + 8), Color.WHITE, 1.0)
		draw_string(font, Vector2(x - 10, TRUNK_Y + 30), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.65, 0.75, 0.79))


func _dotted(start: Vector2, finish: Vector2, shade: Color) -> void:
	var steps := maxi(1, roundi(start.distance_to(finish) / 15.0))
	for i in steps + 1:
		draw_circle(start.lerp(finish, float(i) / float(steps)), 1.5, shade)
