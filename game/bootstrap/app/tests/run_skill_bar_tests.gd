extends SceneTree

const BAR := preload("res://game/bootstrap/app/mutation_skill_bar.gd")
const INFECTION := preload("res://game/features/infection/public/infection_runtime.gd")

var failures := 0
var opened := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var runtime := INFECTION.new()
	root.add_child(runtime)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bar := BAR.new()
	layer.add_child(bar)
	bar.configure(runtime, func() -> void: opened += 1)
	var none: Array[String] = []
	bar.rebuild(none, none, "M")
	await process_frame
	_expect(not bar.has_skills() and bar.get_child(0).visible and bar.open_badge.is_visible_in_tree(), "Tree badge stays visible before any active skill is learned.")
	runtime.absorb_mutagen(6.0)
	_expect(runtime.upgrade_skill("acid_spit"), "Fixture learns an active skill.")
	var skills: Array[String] = ["acid_spit"]
	var keys: Array[String] = ["1"]
	bar.rebuild(skills, keys, "M")
	await process_frame
	var strip := bar.get_child(0) as Control
	_expect(strip.visible and bar.circles.size() == 1, "One learned skill shows one circle.")
	_expect(bar.open_badge.text == "M", "Tree badge shows the bound key like other HUD key badges.")
	bar.open_badge.pressed.emit()
	_expect(opened == 1, "Badge opens the mutation tree.")
	var circle = bar.circles[0]
	_expect(circle.castable and is_zero_approx(circle.ratio), "Ready skill is highlighted with no cooldown sweep.")
	_expect(runtime.cast_skill("acid_spit"), "Skill casts.")
	bar.call("_update_circles", 0.0)
	_expect(not circle.castable and is_equal_approx(circle.ratio, 1.0), "Fresh cast fills the cooldown sweep.")
	runtime.report_skill_effect("acid_spit", 6.0)
	bar.call("_update_circles", 0.0)
	_expect(is_equal_approx(circle.effect_ratio, 1.0) and is_equal_approx(circle.effect_left, 6.0), "A lasting effect shows its full remaining time.")
	runtime.call("_physics_process", 3.0)
	bar.call("_update_circles", 0.0)
	_expect(is_equal_approx(circle.effect_ratio, 0.5) and is_equal_approx(circle.effect_left, 3.0), "Effect sweep drains with its remaining seconds.")
	runtime.report_skill_effect("acid_spit", 5.0)
	_expect(is_equal_approx(runtime.skill_effect_ratio("acid_spit"), 5.0 / 6.0), "Extending a running effect never overfills the sweep.")
	runtime.call("_physics_process", 5.0)
	bar.call("_update_circles", 0.0)
	_expect(is_zero_approx(circle.effect_left), "Effect sweep clears when the effect ends.")
	runtime.report_skill_effect("muscle_memory", 4.0)
	_expect(is_zero_approx(runtime.skill_effect_remaining("muscle_memory")), "Only active skills carry effect timers.")
	bar.call("_update_circles", 0.0)
	_expect(circle.ratio > 0.15 and circle.ratio < 0.25 and not circle.castable, "Cooldown sweep returns after the effect and drains with the remaining cooldown.")
	runtime.call("_physics_process", 5.5)
	bar.call("_update_circles", 0.0)
	_expect(circle.castable and is_zero_approx(circle.ratio), "Skill is highlighted again once recharged.")
	var many: Array[String] = []
	var many_keys: Array[String] = []
	for index in 12:
		many.append("acid_spit")
		many_keys.append("")
	bar.rebuild(many, many_keys, "RMB")
	await process_frame
	_expect(strip.size.x <= BAR.MAX_WIDTH + 0.5, "Strip never grows wider than the vitals panel.")
	var last = bar.circles[11]
	_expect(last.position.x + last.size.x <= strip.size.x, "Every circle fits inside the strip.")
	for circle_item in bar.circles:
		_expect(is_equal_approx(circle_item.size.x, circle_item.size.y), "Circles stay round when shrunk.")
	runtime.upgrade_skill("muscle_memory")
	runtime.report_passive("muscle_memory", 0.0)
	runtime.report_passive("combat_reflex", 4.0)
	_expect(bar.feed_skills() == (["muscle_memory"] as Array[String]), "Learned passive appears in the feed; unlearned reports are ignored.")
	runtime.report_passive("muscle_memory", 0.0)
	_expect(bar.feed_skills().size() == 1, "Repeated triggers refresh one entry instead of stacking.")
	bar.call("_update_feed", BAR.FEED_MIN_TIME + 0.1)
	_expect(bar.feed_skills().is_empty(), "Feed entries expire.")
	layer.queue_free()
	runtime.queue_free()
	await process_frame
	print("Skill bar tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
