extends RefCounted

# Builds the hover-card content for one mutation-tree circle from runtime state.

const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const CARD := preload("res://game/bootstrap/app/mutation_skill_card.gd")
const STYLE := preload("res://game/bootstrap/app/menu/menu_style.gd")
const LIT := Color(0.3, 0.95, 0.1)


static func describe(runtime: Node, row: Array, skills: Array) -> Dictionary:
	var requirements: Dictionary = runtime.call("skill_requirements", str(row[0]))
	var learned: bool = runtime.call("skill_learned", str(row[0]))
	var enabled: bool = runtime.call("has_skill", str(row[0]))
	var available: bool = runtime.call("can_upgrade_skill", str(row[0]))
	var rank := int(row[3])
	var info := {"title": TEXT.skill_name(str(row[0])), "body": TEXT.description(str(row[0])), "rows": [], "status_color": STYLE.MUTED}
	if rank == 3:
		info["kind"] = TEXT.t("mutationHybridBonus") + " · " + TEXT.branch(str(row[2]))
		info["body"] = TEXT.description(str(row[0])) + "\n" + TEXT.t("mutationHybridHint")
		for branch in str(row[2]).split(" + "):
			var last := _branch_row(runtime, skills, branch, false, 2)
			var complete := not last.is_empty() and bool(runtime.call("skill_learned", str(last[0])))
			info["rows"].append([TEXT.branch(branch), TEXT.t("mutationComplete") if complete else TEXT.t("mutationIncomplete"), complete])
		info["status"] = TEXT.t("mutationEnabled") if enabled else TEXT.t("mutationInactive")
		info["status_color"] = LIT if enabled else STYLE.MUTED
		return info
	var active_group := bool(requirements.get("active", false))
	info["kind"] = TEXT.t("mutationSkillKind") % [TEXT.t("mutationActiveSkill") if active_group else TEXT.t("mutationPassiveSkill"), TEXT.branch(str(row[2])), requirements["stage"]]
	if active_group:
		info["rows"].append([TEXT.t("mutationRecovery"), "%ds" % int(requirements.get("cooldown", 5)), true])
	var mutation := float(runtime.call("get_mutation"))
	var stability := float(runtime.call("get_critical_threshold"))
	info["rows"].append([TEXT.t("mutationAmount"), "%d%% / %d%%" % [roundi(mutation), roundi(requirements["mutation"])], mutation >= float(requirements["mutation"])])
	info["rows"].append([TEXT.t("mutationControlThreshold"), "%d%% / %d%%" % [roundi(stability), roundi(requirements["stability"])], bool(requirements["branch_open"])])
	if rank > 0:
		var previous := _branch_row(runtime, skills, str(row[2]), active_group, rank - 1)
		if not previous.is_empty():
			info["rows"].append([TEXT.t("mutationPrevious") + TEXT.skill_name(str(previous[0])), TEXT.t("mutationLearned") if runtime.call("skill_learned", str(previous[0])) else TEXT.t("mutationMissing"), runtime.call("skill_learned", str(previous[0]))])
	if learned:
		info["status"] = (TEXT.t("mutationLearned") if enabled else TEXT.t("mutationDormantHint")) + (" · " + TEXT.t("mutationLocked") if runtime.call("skill_locked", str(row[0])) else "")
		info["status_color"] = LIT if enabled else Color("d9a441")
	elif available:
		info["status"] = TEXT.t("mutationClickLearn")
		info["status_color"] = LIT
	else:
		var points: int = runtime.call("mutation_points")
		info["rows"].append([TEXT.t("mutationPoints"), str(points), points > 0])
		info["status"] = TEXT.t("mutationBranchLockedHint") if not requirements["branch_open"] else TEXT.t("mutationUnavailable")
		info["status_color"] = CARD.BAD
	return info


## Card content for a skill id, for places that name a skill without its tree circle.
static func for_skill(runtime: Node, skill_id: String) -> Dictionary:
	var skills: Array = runtime.call("skill_catalog")
	for row in skills:
		if str(row[0]) == skill_id:
			return describe(runtime, row, skills)
	return {}


static func _branch_row(runtime: Node, skills: Array, branch: String, active_group: bool, rank: int) -> Array:
	for row in skills:
		if str(row[2]) == branch and int(row[3]) == rank and bool(runtime.call("skill_requirements", str(row[0])).get("active", false)) == active_group:
			return row
	return []
