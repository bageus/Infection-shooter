extends Control

const BRANCHES := [
	"Biomass", "Neural Storm", "Toxic Mutation", "Predator Form",
	"Arsenal", "Predator", "Biomass", "Adaptation", "Neural System", "Metabolism"
]
const DESIGN_SIZE := Vector2(1200, 800)
const TRUNK_Y := 370.0
const HYBRID_PARENTS := [[4, 5], [5, 6], [6, 7], [7, 8], [8, 9]]
const LIT := Color(0.3, 0.95, 0.1, 1.0)
const LABEL_MAX_WIDTH := 170.0
const LABEL_GAP := 8.0
var progress: Array[int] = []
var hybrids: Array[bool] = []
var thresholds: Array[float] = []
var branch_open: Array[bool] = []
var mutation := 0.0


func _ready() -> void:
	size = DESIGN_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS


func configure_progression(values: Array[float], amount: float, opened: Array[bool]) -> void:
	thresholds = values.duplicate()
	branch_open = opened.duplicate()
	mutation = amount
	queue_redraw()


func set_mutation(amount: float) -> void:
	mutation = amount
	queue_redraw()


func _threshold_x(value: float) -> float:
	return 130.0 + clampf((value - 25.0) / 75.0, 0.0, 1.0) * 960.0


func branch_origin(index: int) -> Vector2:
	# Equal unlock requirements do not require a shared visual junction.
	return Vector2(1060.0 if index == 9 else _threshold_x(thresholds[index]), TRUNK_Y)


func skill_position(branch_index: int, rank: int) -> Vector2:
	var origin := branch_origin(branch_index)
	var step := 34.0 if branch_index >= 8 else 64.0
	return Vector2(origin.x + rank * step, 290.0 - rank * 85.0 if branch_index < 4 else 450.0 + rank * 85.0)


# Branch titles are centred over the branch's own circles and never wider
# than the gap to the neighbouring branch titles.
func label_rect(index: int) -> Rect2:
	var center := _branch_center_x(index)
	var group := range(0, 4) if index < 4 else range(4, BRANCHES.size())
	var width := LABEL_MAX_WIDTH
	for other in group:
		if other != index:
			width = minf(width, absf(_branch_center_x(other) - center) - LABEL_GAP)
	var x := clampf(center - width * 0.5, 0.0, DESIGN_SIZE.x - width)
	return Rect2(x, 42.0 if index < 4 else 730.0, width, 0.0)


func _branch_center_x(index: int) -> float:
	return (skill_position(index, 0).x + skill_position(index, 2).x) * 0.5


func hybrid_position(index: int) -> Vector2:
	var parents: Array = HYBRID_PARENTS[index]
	return (skill_position(parents[0], 2) + skill_position(parents[1], 2)) * 0.5 + Vector2(0, 56)


func set_progress(new_progress: Array[int], new_hybrids: Array[bool]) -> void:
	progress = new_progress.duplicate()
	hybrids = new_hybrids.duplicate()
	queue_redraw()


func _draw() -> void:
	if thresholds.size() != BRANCHES.size():
		return
	var dim := Color(0.39, 0.4, 0.38, 0.95)
	var limit := trunk_available_x()
	if limit > 90.0:
		draw_line(Vector2(90, TRUNK_Y), Vector2(limit, TRUNK_Y), dim, 9.0, true)
		draw_line(Vector2(90, TRUNK_Y), Vector2(limit, TRUNK_Y), LIT, 6.0, true)
	for index in BRANCHES.size():
		var opened := index < branch_open.size() and branch_open[index]
		var shade := dim if opened else Color(0.16, 0.18, 0.19, 0.9)
		var start := branch_origin(index)
		for rank in range(3):
			var end := skill_position(index, rank)
			draw_line(start, end, shade, 6.0, true)
			if opened and index < progress.size() and progress[index] >= rank:
				draw_line(start, end, LIT, 4.0, true)
			start = end
	for index in HYBRID_PARENTS.size():
		var shade := LIT if index < hybrids.size() and hybrids[index] else Color(0.39, 0.4, 0.38, 0.35)
		for parent in HYBRID_PARENTS[index]:
			_dotted(skill_position(parent, 2), hybrid_position(index), shade)


func _dotted(start: Vector2, finish: Vector2, shade: Color) -> void:
	var steps := maxi(1, roundi(start.distance_to(finish) / 15.0))
	for i in steps + 1:
		draw_circle(start.lerp(finish, float(i) / float(steps)), 1.5, shade)


func trunk_available_x() -> float:
	# A connector appears whole only when its destination branch opens.
	var limit := 90.0
	for index in mini(thresholds.size(), BRANCHES.size()):
		if index < branch_open.size() and branch_open[index]:
			limit = maxf(limit, branch_origin(index).x)
	return limit
