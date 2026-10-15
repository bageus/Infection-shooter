extends RefCounted
## Tracks per-level ampules and previews antidote without changing live state.
const TREE := preload("res://game/features/infection/domain/mutation_tree.gd")
var level_id := ""
var collected := false
var completed: Dictionary = {}


func begin_level(id: String) -> void:
	if id != level_id:
		level_id = id
		collected = false


func record_collection() -> void:
	collected = true


func complete_level(id: String) -> int:
	if id.is_empty() or id != level_id or completed.has(id):
		return 0
	completed[id] = true
	return 0 if collected else 1


static func antidote_preview(domain, tree) -> Dictionary:
	var can_use: bool = not domain.defeated and domain.mutation > domain.MUTATION_MIN
	var after := maxf(0.0, domain.mutation - domain.ANTIDOTE_REDUCTION) if can_use else float(domain.mutation)
	var projected := TREE.new()
	projected.learned = tree.learned.duplicate()
	projected.locked = tree.locked.duplicate()
	projected.peak_mutation = maxf(tree.peak_mutation, domain.mutation)
	projected.reconcile(after)
	var forgotten: Array[String] = []
	var dormant: Array[String] = []
	for id: String in tree.learned:
		if not projected.learned.has(id):
			forgotten.append(id)
		elif tree.is_active(id, domain.mutation, domain.critical_threshold) and not projected.is_active(id, after, domain.critical_threshold):
			dormant.append(id)
	forgotten.sort()
	dormant.sort()
	return {"version":1, "can_use":can_use, "before":domain.mutation, "after":after,
		"forgotten":forgotten, "dormant":dormant, "points_after":projected.points(after),
		"emergency":domain.is_control_lost() or domain.is_escalated()}
