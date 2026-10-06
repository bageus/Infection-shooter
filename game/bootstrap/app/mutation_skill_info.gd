extends RefCounted

# Builds the hover-card content for one mutation-tree circle from runtime state.

const CARD := preload("res://game/bootstrap/app/mutation_skill_card.gd")
const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
const LIT := Color(0.3, 0.95, 0.1)


static func describe(runtime: Node, row: Array, skills: Array) -> Dictionary:
	var requirements: Dictionary = runtime.call("skill_requirements", str(row[0]))
	var learned: bool = runtime.call("skill_learned", str(row[0]))
	var enabled: bool = runtime.call("has_skill", str(row[0]))
	var available: bool = runtime.call("can_upgrade_skill", str(row[0]))
	var rank := int(row[3])
	var info := {"title": str(row[1]), "body": str(row[5]), "rows": [], "status_color": STYLE.MUTED}
	if rank == 3:
		info["kind"] = "Hybrid bonus  ·  " + str(row[2])
		info["body"] = "%s\nAutomatic bonus: learn all three circles in both linked passive branches." % row[5]
		for branch in str(row[2]).split(" + "):
			var last := _branch_row(skills, branch, false, 2)
			var complete := not last.is_empty() and bool(runtime.call("skill_learned", str(last[0])))
			info["rows"].append(["%s branch" % branch, "complete" if complete else "incomplete", complete])
		info["status"] = "Active" if enabled else "Inactive"
		info["status_color"] = LIT if enabled else STYLE.MUTED
		return info
	var active_group := skills.find(row) < 12
	info["kind"] = "%s skill  ·  %s  ·  Stage %d" % ["Active" if active_group else "Passive", row[2], requirements["stage"]]
	var mutation := float(runtime.call("get_mutation"))
	var stability := float(runtime.call("get_critical_threshold"))
	info["rows"].append(["Mutation", "%d%% / %d%%" % [roundi(mutation), roundi(requirements["mutation"])], mutation >= float(requirements["mutation"])])
	info["rows"].append(["Stability", "%d%% / %d%%" % [roundi(stability), roundi(requirements["stability"])], bool(requirements["branch_open"])])
	if rank > 0:
		var previous := _branch_row(skills, str(row[2]), active_group, rank - 1)
		if not previous.is_empty():
			info["rows"].append(["Previous: " + str(previous[1]), "learned" if runtime.call("skill_learned", str(previous[0])) else "missing", runtime.call("skill_learned", str(previous[0]))])
	if learned:
		info["status"] = ("Learned" if enabled else "Learned  ·  dormant until requirements return") + ("  ·  locked" if runtime.call("skill_locked", str(row[0])) else "")
		info["status_color"] = LIT if enabled else Color("d9a441")
	elif available:
		info["status"] = "Click to learn"
		info["status_color"] = LIT
	else:
		var points: int = runtime.call("mutation_points")
		info["rows"].append(["Mutation points", str(points), points > 0])
		info["status"] = "Branch locked  ·  raise stability" if not requirements["branch_open"] else "Not available yet"
		info["status_color"] = CARD.BAD
	return info


static func _branch_row(skills: Array, branch: String, active_group: bool, rank: int) -> Array:
	for row in skills:
		if str(row[2]) == branch and int(row[3]) == rank and (skills.find(row) < 12) == active_group:
			return row
	return []
