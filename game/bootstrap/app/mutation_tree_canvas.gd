extends Control

const BRANCHES := [
	"Biomass", "Neural Storm", "Toxic Mutation", "Predator Form",
	"Arsenal", "Predator", "Biomass", "Adaptation", "Neural System", "Metabolism"
]
const TRUNK_Y := 450.0
const TRUNK_START := 80.0
const BRANCH_START := 190.0
const BRANCH_JOIN := 360.0
const HYBRID_PARENTS := [[4, 5], [5, 6], [6, 7], [7, 8], [8, 9], [9, 4]]

var progress: Array[int] = []
var hybrids: Array[bool] = []


func _ready() -> void:
	size = Vector2(1280, 900)
	mouse_filter = Control.MOUSE_FILTER_PASS


func skill_position(branch_index: int, rank: int) -> Vector2:
	return Vector2(475.0 + float(rank) * 225.0, 76.0 + float(branch_index) * 80.0)


func hybrid_position(index: int) -> Vector2:
	return Vector2(1150.0, 480.0 + float(index) * 70.0)


func set_progress(new_progress: Array[int], new_hybrids: Array[bool]) -> void:
	progress = new_progress.duplicate()
	hybrids = new_hybrids.duplicate()
	queue_redraw()


func _draw() -> void:
	var dim := Color(0.28, 0.35, 0.42, 0.9)
	var lit := Color(0.29, 0.88, 0.67, 0.95)
	draw_line(Vector2(TRUNK_START, TRUNK_Y), Vector2(BRANCH_START, TRUNK_Y), dim, 10.0, true)
	var lit_trunk := false
	for index in BRANCHES.size():
		var y := skill_position(index, 0).y
		var fork := Vector2(BRANCH_START, TRUNK_Y)
		var join := Vector2(BRANCH_JOIN, y)
		var end := skill_position(index, 2)
		draw_line(fork, join, dim, 8.0, true)
		draw_line(join, end, dim, 8.0, true)
		if index < progress.size() and progress[index] >= 0:
			lit_trunk = true
			draw_line(fork, join, lit, 6.0, true)
			draw_line(join, skill_position(index, progress[index]), lit, 6.0, true)
	if lit_trunk:
		draw_line(Vector2(TRUNK_START, TRUNK_Y), Vector2(BRANCH_START, TRUNK_Y), lit, 7.0, true)
	for index in HYBRID_PARENTS.size():
		var pair: Array = HYBRID_PARENTS[index]
		var hybrid := hybrid_position(index)
		var shade := lit if index < hybrids.size() and hybrids[index] else Color(0.36, 0.46, 0.53, 0.7)
		_dotted(skill_position(pair[0], 2) + Vector2(25, 0), hybrid - Vector2(25, 0), shade)
		_dotted(skill_position(pair[1], 2) + Vector2(25, 0), hybrid - Vector2(25, 0), shade)


func _dotted(start: Vector2, finish: Vector2, shade: Color) -> void:
	var length := start.distance_to(finish)
	var steps := maxi(1, roundi(length / 13.0))
	for i in steps + 1:
		draw_circle(start.lerp(finish, float(i) / float(steps)), 2.5, shade)
