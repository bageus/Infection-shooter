extends Control

const BRANCHES := [
	"Biomass", "Neural Storm", "Toxic Mutation", "Predator Form",
	"Arsenal", "Predator", "Biomass", "Adaptation", "Neural System", "Metabolism"
]
const ROW_HEIGHT := 70.0
const TRUNK_X := 1150.0
const ROOT := Vector2(1240, 400)
const SKILL_X := [1030.0, 790.0, 550.0]

var progress: Array[int] = []


func _ready() -> void:
	custom_minimum_size = Vector2(1280, 850)
	mouse_filter = Control.MOUSE_FILTER_PASS


func skill_position(branch_index: int, rank: int) -> Vector2:
	return Vector2(SKILL_X[rank], 75.0 + ROW_HEIGHT * branch_index + (22.0 if branch_index >= 4 else 0.0))


func set_progress(new_progress: Array[int]) -> void:
	progress = new_progress.duplicate()
	queue_redraw()


func _draw() -> void:
	var inactive := Color(0.26, 0.33, 0.40, 0.85)
	var active := Color(0.29, 0.88, 0.67, 0.95)
	draw_line(ROOT, Vector2(TRUNK_X, ROOT.y), inactive, 9.0, true)
	draw_line(Vector2(TRUNK_X, 75), Vector2(TRUNK_X, 727), inactive, 9.0, true)
	if progress.has(0) or progress.has(1) or progress.has(2):
		draw_line(ROOT, Vector2(TRUNK_X, ROOT.y), active, 7.0, true)
	for branch_index in BRANCHES.size():
		var y := skill_position(branch_index, 0).y
		draw_line(Vector2(TRUNK_X, y), Vector2(SKILL_X[2], y), inactive, 9.0, true)
		if branch_index < progress.size() and progress[branch_index] >= 0:
			draw_line(Vector2(TRUNK_X, ROOT.y), Vector2(TRUNK_X, y), active, 7.0, true)
			draw_line(Vector2(TRUNK_X, y), skill_position(branch_index, progress[branch_index]), active, 7.0, true)
	# Hybrid skills have two prerequisites each; they share a separate lane.
	draw_line(Vector2(TRUNK_X, 805), Vector2(260, 805), inactive, 7.0, true)
