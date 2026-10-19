extends Control

const BRANCHES := [
	"Biomass", "Neural Storm", "Might", "Predator Form",
	"Arsenal", "Predator", "Biomass", "Adaptation", "Neural System", "Metabolism"
]
const DESIGN_SIZE := Vector2(1200, 800)
const TRUNK_Y := 370.0
# Visual column per branch index, left to right: active Might, Biomass, Predator Form, Neural Storm; then passive.
const COLUMNS := [1, 3, 0, 2, 0, 1, 2, 3, 4, 5]
const COLUMN_X0 := 120.0
const COLUMN_PITCH := 160.0
# Active columns are wider so a mirrored alternative fits between neighbours.
const ACTIVE_X0 := 40.0
const ACTIVE_PITCH := 292.0
# One circle per rank: 110 px across and 85 px up or down, about 38 degrees from the trunk.
const RANK_STEP := Vector2(110.0, 85.0)
const HYBRID_PARENTS := [[4, 5], [5, 6], [6, 7], [7, 8], [8, 9]]
const LIT := Color(0.3, 0.95, 0.1, 1.0)
const LABEL_MAX_WIDTH := 170.0
const LABEL_GAP := 8.0
var alternatives: Array[bool] = []
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


func branch_origin(index: int) -> Vector2:
	# Every branch owns one column of equal width, so neighbouring branches never share circles.
	if index < 4:
		return Vector2(ACTIVE_X0 + COLUMNS[index] * ACTIVE_PITCH, TRUNK_Y)
	return Vector2(COLUMN_X0 + COLUMNS[index] * COLUMN_PITCH, TRUNK_Y)


func _row_y(branch_index: int, rank: int) -> float:
	return TRUNK_Y - 50.0 - RANK_STEP.y * rank if branch_index < 4 else TRUNK_Y + 80.0 + RANK_STEP.y * rank


func skill_position(branch_index: int, rank: int, alternative: bool = false) -> Vector2:
	var origin := branch_origin(branch_index)
	if alternative:
		# Mirrors the main stem across the level-2 node, so both level-3 stems have equal length.
		return Vector2(origin.x, _row_y(branch_index, rank))
	return Vector2(origin.x + rank * RANK_STEP.x, _row_y(branch_index, rank))


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
	return Rect2(x, 64.0 if index < 4 else 730.0, width, 0.0)


func _branch_center_x(index: int) -> float:
	return (skill_position(index, 0).x + skill_position(index, 2).x) * 0.5


# Hybrids sit between the two titles they combine, so they read as belonging to neither.
func hybrid_position(index: int) -> Vector2:
	var parents: Array = HYBRID_PARENTS[index]
	var x := (_branch_center_x(parents[0]) + _branch_center_x(parents[1])) * 0.5
	return Vector2(x, skill_position(parents[0], 2).y + 72.0)


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
			var selected_alternative := index < alternatives.size() and alternatives[index]
			draw_line(start, end, shade, 6.0, true)
			if opened and index < progress.size() and progress[index] >= rank and not (index < 4 and rank == 2 and selected_alternative):
				draw_line(start, end, LIT, 3.0, true)
			if index < 4 and rank == 2:
				var alternate := skill_position(index, rank, true)
				draw_line(start, alternate, shade, 6.0, true)
				if opened and selected_alternative and index < progress.size() and progress[index] >= rank:
					draw_line(start, alternate, LIT, 3.0, true)
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
