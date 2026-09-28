extends Control

const BRANCHES := [
	"Biomass", "Neural Storm", "Toxic Mutation", "Predator Form",
	"Arsenal", "Predator", "Biomass", "Adaptation", "Neural System", "Metabolism"
]
const TRUNK_Y := 450.0
const TRUNK_START := 1240.0
const TRUNK_END := 90.0
const HYBRID_PARENTS := [[4, 5], [5, 6], [6, 7], [7, 8], [8, 9], [9, 4]]

var progress: Array[int] = []
var hybrids: Array[bool] = []


func _ready() -> void:
	custom_minimum_size = Vector2(1280, 900)
	mouse_filter = Control.MOUSE_FILTER_PASS


func branch_x(branch_index: int) -> float:
	return 160.0 + float(branch_index) * 270.0 if branch_index < 4 else 140.0 + float(branch_index - 4) * 200.0


func skill_position(branch_index: int, rank: int) -> Vector2:
	var y := 365.0 - float(rank) * 94.0 if branch_index < 4 else 535.0 + float(rank) * 94.0
	return Vector2(branch_x(branch_index), y)


func hybrid_position(index: int) -> Vector2:
	return Vector2(250.0 + float(index) * 190.0, 820.0)


func set_progress(new_progress: Array[int], new_hybrids: Array[bool]) -> void:
	progress = new_progress.duplicate()
	hybrids = new_hybrids.duplicate()
	queue_redraw()


func _draw() -> void:
	var dim := Color(0.28, 0.35, 0.42, 0.9)
	var lit := Color(0.29, 0.88, 0.67, 0.95)
	draw_line(Vector2(TRUNK_END, TRUNK_Y), Vector2(TRUNK_START, TRUNK_Y), dim, 10.0, true)
	var leftmost := TRUNK_START
	for index in BRANCHES.size():
		var x := branch_x(index)
		var end := skill_position(index, 2)
		draw_line(Vector2(x, TRUNK_Y), end, dim, 9.0, true)
		if index < progress.size() and progress[index] >= 0:
			leftmost = minf(leftmost, x)
			draw_line(Vector2(x, TRUNK_Y), skill_position(index, progress[index]), lit, 7.0, true)
	if leftmost < TRUNK_START:
		draw_line(Vector2(TRUNK_START, TRUNK_Y), Vector2(leftmost, TRUNK_Y), lit, 7.0, true)
	for index in HYBRID_PARENTS.size():
		var pair: Array = HYBRID_PARENTS[index]
		var hybrid := hybrid_position(index)
		var shade := lit if index < hybrids.size() and hybrids[index] else Color(0.36, 0.46, 0.53, 0.7)
		_dotted(skill_position(pair[0], 2) + Vector2(0, 28), hybrid - Vector2(0, 28), shade)
		if index == 5:
			# The last hybrid connects the first and last passive branches.
			_dotted(skill_position(pair[1], 2) + Vector2(0, 28), Vector2(branch_x(pair[1]), 870), shade)
			_dotted(Vector2(branch_x(pair[1]), 870), Vector2(hybrid.x, 870), shade)
			_dotted(Vector2(hybrid.x, 870), hybrid + Vector2(0, 28), shade)
		else:
			_dotted(skill_position(pair[1], 2) + Vector2(0, 28), hybrid - Vector2(0, 28), shade)


func _dotted(start: Vector2, finish: Vector2, shade: Color) -> void:
	var length := start.distance_to(finish)
	var steps := maxi(1, roundi(length / 13.0))
	for i in steps + 1:
		draw_circle(start.lerp(finish, float(i) / float(steps)), 2.5, shade)
