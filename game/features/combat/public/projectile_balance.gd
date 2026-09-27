extends RefCounted

# Tunable rules shared by projectile hits and destructible presentation objects.
static func distance_multiplier(weapon: String, distance: float, max_range: float) -> float:
	var full_damage_distance := 4.0
	var minimum := 0.18
	if weapon == "SHOTGUN":
		full_damage_distance = 2.0
		minimum = 0.08
	elif weapon == "UZI":
		full_damage_distance = 3.0
		minimum = 0.2
	var fraction := clampf((distance - full_damage_distance) / maxf(max_range - full_damage_distance, 0.01), 0.0, 1.0)
	return lerpf(1.0, minimum, fraction)


static func projectile_energy(weapon: String) -> float:
	match weapon:
		"PISTOL": return 19.0
		"UZI": return 38.0
		"SHOTGUN": return 32.0
	return 24.0


static func material_cost(material: String) -> float:
	match material:
		"glass": return 8.0
		"light": return 12.0
		"tech": return 17.0
		"wood": return 24.0
		"metal": return 55.0
	return INF # Concrete, structural frames and unknown geometry stop shots.


static func object_damage(amount: float, weapon: String, category: String) -> float:
	if weapon == "PISTOL" and category != "small" and category != "tech":
		return 0.0
	if weapon == "SHOTGUN":
		return amount * 0.75
	if weapon == "UZI":
		return amount * 0.9
	return amount
