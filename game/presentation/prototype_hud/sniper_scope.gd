extends Control
## A scene-local magnified view of the actual world under the aim cursor.
const MASK := preload("res://game/presentation/prototype_hud/sniper_scope.gdshader")
const DIAMETER := 224
var view: SubViewport
var camera: Camera3D
var magnification := 2.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	view = SubViewport.new()
	view.size = Vector2i(DIAMETER, DIAMETER)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.handle_input_locally = false
	view.gui_disable_input = true
	add_child(view)
	camera = Camera3D.new()
	view.add_child(camera)
	camera.current = true
	var image := TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = view.get_texture()
	image.position = Vector2.ONE * (-DIAMETER * .5)
	image.size = Vector2.ONE * DIAMETER
	var material := ShaderMaterial.new()
	material.shader = MASK
	image.material = material
	add_child(image)
	# The reticle draws above its image, never under the viewport texture.
	var reticle := Control.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reticle)
	reticle.draw.connect(_draw_reticle.bind(reticle))
	reticle.queue_redraw()
	hide()


func update_view(state: Dictionary) -> void:
	var source := state.get("camera") as Camera3D
	magnification = float(state.get("magnification", 0.0))
	visible = magnification > 1.0 and is_instance_valid(source) and source.is_inside_tree()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible and is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not visible:
		return
	view.world_3d = source.get_world_3d()
	camera.global_transform = source.global_transform
	camera.cull_mask = source.cull_mask
	camera.near = source.near
	camera.far = source.far
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(source.fov) * .5) / magnification))
	var target: Vector3 = state.get("target", Vector3.INF)
	if target.is_finite() and camera.global_position.distance_squared_to(target) > .01:
		camera.look_at(target, source.global_basis.y)


func _draw_reticle(canvas: Control) -> void:
	var radius := DIAMETER * .5
	canvas.draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 96, Color(.05, .06, .07), 5.0, true)
	canvas.draw_arc(Vector2.ZERO, radius - 6.0, 0.0, TAU, 96, Color(.7, .75, .78), 1.0, true)
	var ink := Color(.04, .05, .06)
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		canvas.draw_line(-axis * (radius - 8), axis * (radius - 8), ink, 1.2, true)
		for distance in [24.0, 48.0, 72.0]:
			var perpendicular := Vector2(-axis.y, axis.x)
			for sign_value in [-1.0, 1.0]:
				var center: Vector2 = axis * distance * sign_value
				canvas.draw_line(center - perpendicular * 4, center + perpendicular * 4, ink, 1.2, true)
	canvas.draw_circle(Vector2.ZERO, 2.0, Color(.85, .12, .1))
