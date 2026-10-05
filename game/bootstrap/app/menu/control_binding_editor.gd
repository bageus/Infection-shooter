extends RefCounted
const BINDINGS := preload("res://game/bootstrap/app/menu/control_bindings.gd")
var dialog: Control
var pending := ""
var buttons: Dictionary = {}
var notice: Label


func setup(owner_dialog: Control) -> void:
	dialog = owner_dialog
	dialog.call("_copy", "bindingHint")
	for action in BINDINGS.ACTIONS:
		var button := Button.new()
		button.custom_minimum_size.x = 130
		buttons[action] = button
		button.pressed.connect(begin.bind(action))
		dialog.call("_row", "bind_" + action, button)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.get("layout").add_child(notice)
	refresh()


func refresh() -> void:
	var view: Control = dialog.get("view")
	for action: String in buttons:
		buttons[action].text = view.preferences.bindings.label(action, view.preferences.values.language)


func begin(action: String) -> void:
	cancel()
	pending = action
	buttons[action].text = dialog.view.text("bindingWaiting")
	notice.text = dialog.view.text("bindingHint")


func cancel() -> void:
	pending = ""
	if is_instance_valid(dialog):
		refresh()


func consume(event: InputEvent) -> bool:
	if pending.is_empty():
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			cancel()
			return true
	elif not (event is InputEventMouseButton and event.pressed):
		return true
	var error: String = dialog.view.preferences.bindings.bind(pending, event)
	if not error.is_empty():
		notice.text = dialog.view.text("bindingConflict") + dialog.view.text("bind_" + error) if error in BINDINGS.ACTIONS else dialog.view.text(error)
		return true
	pending = ""
	dialog.view.preferences.bindings.apply()
	notice.text = "" if dialog.view.preferences.save_settings() == OK else dialog.view.text("storeUnavailable")
	refresh()
	return true
