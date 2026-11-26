extends CanvasLayer
## "+N" button right of the HUD's antidote icon; H does the same. Hidden unless active medkit use is on.
const MEDKITS := preload("res://game/bootstrap/app/web_medkits.gd")
const ICONS := preload("res://game/bootstrap/app/menu/web_shop_icons.gd")

var main: Node
var button: Button


func setup(owner_main: Node) -> void:
	main = owner_main
	layer = 50
	button = Button.new()
	button.name = "MedkitButton"
	button.icon = ICONS.texture("health")
	button.expand_icon = true
	button.custom_minimum_size = Vector2(64, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "H"
	button.pressed.connect(func() -> void: MEDKITS.use(main))
	add_child(button)


func _process(_delta: float) -> void:
	var on := bool(main.get_meta(&"active_medkits", false)) and int(main.get_meta(MEDKITS.META, 0)) > 0
	button.visible = on
	if not on:
		return
	button.text = str(int(main.get_meta(MEDKITS.META)))
	var hud: Node = main.get_node_or_null("PrototypeHUD")
	if hud != null and hud.get("antidote_panel") != null:
		var rect: Rect2 = hud.antidote_panel.get_global_rect()
		button.position = Vector2(rect.end.x + 8.0, rect.position.y)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H \
			and bool(main.get_meta(&"active_medkits", false)):
		MEDKITS.use(main)
