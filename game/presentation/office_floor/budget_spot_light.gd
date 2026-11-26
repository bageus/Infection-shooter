extends SpotLight3D
## Directional light of a prop (floodlight, operating lamp). It joins the lamp budget
## like budget_omni_light.gd and casts a shadow only when the lamp budget grants it.

const BUDGET_FADE_SECONDS := 0.25

var _wanted := true
var _local_enabled := false
var _budget_lit := true
var _full_energy := 0.0
var _fade := 0.0
var _budget_shadow := false


static func create(color: Color, energy: float, light_range: float, angle: float, aim: Transform3D) -> SpotLight3D:
	var light := (load("res://game/presentation/office_floor/budget_spot_light.gd") as GDScript).new() as SpotLight3D
	light.name = "BudgetLight"
	light.light_color = color
	light.light_energy = energy
	light.set("_full_energy", energy)
	light.spot_range = light_range
	light.spot_angle = angle
	light.spot_attenuation = 1.2
	light.shadow_enabled = false
	light.transform = aim
	light.visible = false
	return light


func _enter_tree() -> void:
	add_to_group("budget_lights")


## Fades the light in or out when the budget changes, so a lamp never pops on or off.
func _process(delta: float) -> void:
	_fade = move_toward(_fade, _target(), delta / BUDGET_FADE_SECONDS)
	light_energy = _full_energy * _fade
	visible = _fade > 0.0
	_sync_shadow()
	set_process(_fade != _target())


## The prop decides whether it glows (lamp on).
func set_wanted(wanted: bool) -> void:
	_wanted = wanted
	_apply()


func is_wanted() -> bool:
	return _wanted


func get_budget_fade() -> float:
	return _fade


func set_local_lighting_enabled(enabled: bool) -> void:
	_local_enabled = enabled
	_apply()


func get_light_cost() -> int:
	return 1


func get_light_radius() -> float:
	return spot_range


func set_budget_lit(lit: bool, shadow: bool) -> void:
	_budget_lit = lit
	_budget_shadow = shadow
	_apply()


func _target() -> float:
	return 1.0 if _wanted and _local_enabled and _budget_lit else 0.0


## Switching lighting off applies at once; only a budget change fades.
func _apply() -> void:
	if not (_wanted and _local_enabled):
		_fade = 0.0
		light_energy = 0.0
		visible = false
	_sync_shadow()
	set_process(_fade != _target() or _fade > 0.0)


## Shadows follow the budget's grant, and only once the light is fully faded in (no popped shadow).
func _sync_shadow() -> void:
	shadow_enabled = _budget_shadow and _fade >= 1.0
	# Same caster rule as planner lights: walls only, unless the high shadow setting asks for every object.
	shadow_caster_mask = 0xFFFFF if is_inside_tree() and get_tree().get_meta(&"lamp_all_casters", false) else (1 << 19)
