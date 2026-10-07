extends RefCounted
## Temporary overhead view; the planner remains the camera state owner.
var controls: Node
var button: CheckButton
var active := false
var _normal_transform := Transform3D.IDENTITY
var _normal_projection := Camera3D.PROJECTION_PERSPECTIVE
var _normal_size := 1.0
var _top_origin := Vector3.ZERO


func setup(owner_controls: Node) -> void:
	controls = owner_controls
	button = CheckButton.new()
	button.name = "LightTopView"
	button.text = "Вид сверху"
	button.tooltip_text = "Расставьте светильники сверху, затем выключите для точной настройки. Колесо — масштаб."
	var box: Node = controls.session.ui.get_node("Panel/VBox")
	box.add_child(button)
	box.move_child(button, box.get_node("Tabs").get_index() + 1)
	button.hide()
	button.toggled.connect(set_enabled)


func update_catalog() -> void:
	button.visible = controls.catalog.active_catalog == controls.catalog.lighting_catalog
	if not button.visible:
		set_enabled(false)


func set_enabled(enabled: bool) -> void:
	enabled = enabled and controls.session.active
	button.set_pressed_no_signal(enabled)
	if active == enabled:
		return
	var camera: Camera3D = controls.session.camera
	if enabled:
		_normal_transform = camera.global_transform
		_normal_projection = camera.projection
		_normal_size = camera.size
		var center := camera.get_viewport().get_visible_rect().size * 0.5
		var focus: Variant = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(center), camera.project_ray_normal(center))
		var point: Vector3 = focus if focus != null else camera.global_position
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 30.0
		camera.global_position = Vector3(point.x, 24.0, point.z)
		camera.global_rotation = Vector3(-PI * 0.5, controls.session.planning_yaw, 0.0)
		_top_origin = camera.global_position
	else:
		var shift := camera.global_position - _top_origin
		shift.y = 0.0
		camera.projection = _normal_projection
		camera.size = _normal_size
		camera.global_transform = _normal_transform
		camera.global_position += shift
	active = enabled
	controls.session.camera_height = camera.global_position.y
	controls.session.camera_anchor = camera.global_position


func forward() -> Vector3:
	var yaw: float = controls.session.planning_yaw
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func zoom(amount: float) -> void:
	var camera: Camera3D = controls.session.camera
	camera.size = clampf(camera.size + amount, 4.0, 120.0)
