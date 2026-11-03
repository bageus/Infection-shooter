extends RefCounted
## Decides, from plain numbers, when a quest may start and when it is complete. The runner
## gathers the numbers (distances, counts) from the scene; nothing here touches nodes.

const NEAR := 2.0 # metres that count as "right next to" a target
const STEP_METERS := 0.8


## `context`: {"idle": seconds since the previous quest ended, "steps": steps since then,
## "reach": distance to the trigger target or point, INF when there is none, "mutation_gain": meter rise
## since the previous quest ended, "menu_open" and "control_lost": the player's state now, "trigger_collected": the trigger object was taken
## or destroyed}.
static func trigger_ready(quest: Dictionary, context: Dictionary) -> bool:
	var trigger: Dictionary = quest.trigger
	match str(trigger.kind):
		"time":
			return float(context.get("idle", 0.0)) >= float(trigger.value)
		"steps":
			return float(context.get("steps", 0.0)) >= float(trigger.value)
		"reach":
			return float(context.get("reach", INF)) <= NEAR
		"mutation_rise":
			return float(context.get("mutation_gain", 0.0)) >= float(trigger.value)
		"menu_open":
			return bool(context.get("menu_open", false))
		"control_lost":
			return bool(context.get("control_lost", false))
		"collect":
			return bool(context.get("trigger_collected", false))
	return true


## `context`: {"distances": [metres to each live target], "gone": [bool per target: destroyed, killed or taken],
## "steps": steps since the quest began, "lesson_done": bool}.
static func complete(quest: Dictionary, context: Dictionary) -> bool:
	var type := str(quest.type)
	if type == "message":
		return true
	if type == "lesson":
		return bool(context.get("lesson_done", false))
	if type == "leave":
		return bool(context.get("left_level", false))
	var distances: Array = context.get("distances", [])
	var gone: Array = context.get("gone", [])
	match str(quest.complete.kind):
		"reach":
			return distances.is_empty() or distances.all(func(d: float) -> bool: return d <= NEAR)
		"destroy", "collect":
			return gone.all(func(g: bool) -> bool: return g)
		"steps":
			return float(context.get("steps", 0.0)) >= float(quest.complete.value)
	return true
