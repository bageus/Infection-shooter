extends SceneTree

const BADGE := preload("res://game/core/world_badge/public/world_badge.gd")
const ICON := preload("res://assets/interface/icon/locked_door.png")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var key := BADGE.key("G", 0.8)
	stage.add_child(key)
	await process_frame
	var viewport := key.find_children("*", "SubViewport", false, false)[0] as SubViewport
	var sprite := key.find_children("*", "Sprite3D", false, false)[0] as Sprite3D
	_expect(is_equal_approx(key.position.y, 0.8), "Badge floats at the requested height.")
	_expect(sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED and sprite.no_depth_test, "Badge faces the camera and stays above walls.")
	_expect(sprite.texture == viewport.get_texture(), "Sprite shows the drawn face.")
	_expect(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and key.is_processing(), "Visible key cap keeps animating.")
	_expect(key.get("face").get("label") == "G", "Key cap shows its label.")
	var peak := 0.0
	for step in 40:
		key.call("_process", 0.02)
		peak = maxf(peak, float(key.call("press_amount")))
	_expect(peak > 0.9, "Key cap goes all the way down during a press.")
	key.set("_time", BADGE.PRESS_TIME + 0.1)
	key.call("_process", 0.0)
	_expect(is_zero_approx(float(key.call("press_amount"))), "Key cap rests between presses.")
	key.call("set_label", "F")
	_expect(key.get("face").get("label") == "F", "Rebinding updates the label.")
	key.visible = false
	_expect(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not key.is_processing(), "Hidden key cap stops rendering.")
	key.visible = true
	_expect(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Shown key cap renders again.")
	stage.visible = false
	_expect(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hiding a parent stops the badge too.")
	stage.visible = true
	var icon := BADGE.icon(ICON, Rect2(), Color("dcae4a"), 2.5)
	stage.add_child(icon)
	await process_frame
	var icon_viewport := icon.find_children("*", "SubViewport", false, false)[0] as SubViewport
	_expect(not icon.is_processing(), "Static icon badge does not animate.")
	_expect(icon_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Static icon badge renders once, not every frame.")
	var rects := icon.find_children("*", "TextureRect", true, false)
	_expect(rects.size() == 1 and (rects[0] as TextureRect).texture == ICON, "Icon badge shows its texture.")
	stage.queue_free()
	await process_frame
	print("World badge tests: %d failures" % failures)
	quit(failures)


func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
