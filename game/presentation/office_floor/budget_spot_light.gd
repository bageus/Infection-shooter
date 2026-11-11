extends SpotLight3D
## Directional light of a prop (floodlight, operating lamp). It joins the lamp budget
## like budget_omni_light.gd and never casts a shadow.

var _wanted := true
var _local_enabled := false
var _budget_lit := true


static func create(color: Color, energy: float, light_range: float, angle: float, aim: Transform3D) -> SpotLight3D:
	var light := (load("res://game/presentation/office_floor/budget_spot_light.gd") as GDScript).new() as SpotLight3D
	light.name = "BudgetLight"
	light.light_color = color
	light.light_energy = energy
	light.spot_range = light_range
	light.spot_angle = angle
	light.spot_attenuation = 1.2
	light.shadow_enabled = false
	light.transform = aim
	light.visible = false
	return light


func _enter_tree() -> void:
	add_to_group("budget_lights")


## The prop decides whether it glows (lamp on).
func set_wanted(wanted: bool) -> void:
	_wanted = wanted
	_apply()


func is_wanted() -> bool:
	return _wanted


func set_local_lighting_enabled(enabled: bool) -> void:
	_local_enabled = enabled
	_apply()


func get_light_cost() -> int:
	return 1


func get_light_radius() -> float:
	return spot_range


func set_budget_lit(lit: bool, _shadow: bool) -> void:
	_budget_lit = lit
	_apply()


func _apply() -> void:
	visible = _wanted and _local_enabled and _budget_lit
