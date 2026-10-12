extends OmniLight3D
## Small omni light of a prop (desk lamp, elevator indicator). It joins the lamp
## budget kept by PlanningLighting, so it respects the lighting setting and the
## renderer's light limit, and it never casts shadows.

var _wanted := true
var _local_enabled := false
var _budget_lit := true


static func create(color: Color, energy: float, light_range: float) -> OmniLight3D:
	var light := (load("res://game/presentation/office_floor/budget_omni_light.gd") as GDScript).new() as OmniLight3D
	light.name = "BudgetLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	light.visible = false
	return light


func _enter_tree() -> void:
	add_to_group("budget_lights")


## The prop decides whether it glows (door open, lamp intact).
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


func set_budget_lit(lit: bool, _shadow: bool) -> void:
	_budget_lit = lit
	_apply()


func _apply() -> void:
	visible = _wanted and _local_enabled and _budget_lit
