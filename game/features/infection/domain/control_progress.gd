extends RefCounted
## Tracks per-level ampules and previews antidote without changing live state.
const TREE := preload("res://game/features/infection/domain/mutation_tree.gd")
var level_id := ""
# Each level holds one control ampule; the set survives the trip to other maps of the chain.
var collected_levels: Dictionary = {}
var completed: Dictionary = {}


func begin_level(id: String) -> void:
	level_id = id


func record_collection() -> void:
	collected_levels[level_id] = true


func collected_here() -> bool:
	return collected_levels.has(level_id)


func complete_level(id: String) -> int:
	if id.is_empty() or id != level_id or completed.has(id):
		return 0
	completed[id] = true
	return 0 if collected_here() else 1


func carry() -> Dictionary:
	return {"collected": collected_levels.duplicate(), "completed": completed.duplicate()}


func restore(data: Dictionary) -> void:
	collected_levels = (data.get("collected", {}) as Dictionary).duplicate()
	completed = (data.get("completed", {}) as Dictionary).duplicate()


static func antidote_preview(domain, tree, effectiveness: float = 1.0) -> Dictionary:
	var can_use: bool = not domain.defeated and domain.mutation > domain.MUTATION_MIN
	var after: float = domain.antidote_result(effectiveness) if can_use else float(domain.mutation)
	var projected := TREE.new()
	projected.learned = tree.learned.duplicate()
	projected.locked = tree.locked.duplicate()
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
