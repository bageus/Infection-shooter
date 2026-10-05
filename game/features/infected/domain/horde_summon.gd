extends RefCounted
## Health-based escalation; independent of nodes and earlier waves.

enum Tier { HUNGER, REVENANT, BRUTE }


static func tier(health: float, maximum: float) -> Tier:
	var ratio := clampf(health / maxf(maximum, 0.001), 0.0, 1.0)
	if ratio <= 1.0 / 3.0:
		return Tier.BRUTE
	if ratio <= 2.0 / 3.0:
		return Tier.REVENANT
	return Tier.HUNGER
