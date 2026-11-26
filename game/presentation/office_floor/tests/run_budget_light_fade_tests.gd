extends SceneTree
## Desk lamps and floodlights fade with the lamp budget like ceiling lamps do, so they never pop.

const OMNI := preload("res://game/presentation/office_floor/budget_omni_light.gd")
const SPOT := preload("res://game/presentation/office_floor/budget_spot_light.gd")
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_fade(OMNI.new() as OmniLight3D, "Desk light")
	_test_fade(SPOT.new() as SpotLight3D, "Floodlight")
	print("Budget light fade tests: %d failure(s)." % _failures)
	quit(0 if _failures == 0 else 1)


func _test_fade(light: Light3D, label: String) -> void:
	light.set("_full_energy", 1.0)
	light.set_process(false)
	root.add_child(light)
	light.call("set_local_lighting_enabled", true)
	light.call("set_budget_lit", true, false)
	light.call("_process", 0.1)
	_check(light.visible and light.light_energy > 0.0 and light.light_energy < 1.0, "%s fades in gradually" % label)
	light.call("_process", 1.0)
	_check(is_equal_approx(light.light_energy, 1.0), "%s ends at full energy" % label)
	light.call("set_budget_lit", false, false)
	_check(light.visible and light.light_energy == 1.0, "%s keeps shining at the start of its fade-out" % label)
	light.call("_process", 0.1)
	_check(light.light_energy > 0.0 and light.light_energy < 1.0, "%s fade-out is gradual" % label)
	light.call("_process", 1.0)
	_check(not light.visible and is_zero_approx(light.light_energy), "%s ends dark after fade-out" % label)
	light.free()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + message)
