extends RefCounted
## What losing limbs does to an infected (split out of infected_capsule.gd).

const BODY_PARTS := preload("res://game/features/infected/body_parts.gd")


## Heavy blasts tear at one or two random limbs.
static func blast(actor: CharacterBody3D, parts: Node, amount: float, last_hit: Vector3) -> void:
	var candidates: Array[StringName] = parts.severable_parts()
	candidates.shuffle()
	for part in candidates.slice(0, 2):
		if parts.damage_part(part, amount * 0.8):
			var away := actor.global_position - (last_hit if last_hit != Vector3.ZERO else actor.global_position + Vector3.DOWN)
			parts.sever(part, away.normalized() + Vector3.UP)
			if actor.is_dead():
				return


## Consequences of a lost part: a head or (for small infected) a leg kills, the last arm halves the blows.
static func lost(actor: CharacterBody3D, parts: Node, part: StringName) -> void:
	var part_label := BODY_PARTS.limb_of(part)
	if part == &"head":
		actor.call("_die")
	elif part_label == "leg":
		var legs: int = parts.remaining("leg")
		if bool(actor.get("limb_loss_kills")) or legs == 0:
			actor.call("_die")
		else:
			actor.set("_mobility", minf(float(actor.get("_mobility")), 0.45))
	elif part_label == "arm" and parts.remaining("arm") == 0:
		actor.set("_attack_scale", 0.5)
