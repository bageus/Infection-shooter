extends CanvasLayer
## Scene-local paused confirmation; player retains authority over stock/use.
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
var dialog: ConfirmationDialog
var _player: Node
var _previous_pause := false


func configure(player: Node) -> void:
	_player = player
	layer = 140
	process_mode = Node.PROCESS_MODE_ALWAYS
	dialog = ConfirmationDialog.new()
	dialog.dialog_autowrap = true
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dialog)
	dialog.confirmed.connect(_confirm)
	dialog.canceled.connect(_cancel)
	_player.connect("antidote_confirmation_requested", _show)


func _show(preview: Dictionary) -> void:
	if dialog.visible:
		return
	_previous_pause = get_tree().paused
	get_tree().paused = true
	dialog.title = TEXT.t("antidoteConfirmTitle")
	dialog.get_ok_button().text = TEXT.t("antidoteUse")
	dialog.get_cancel_button().text = TEXT.t("antidoteCancel")
	dialog.dialog_text = TEXT.t("antidotePreview") % [roundi(preview.before), roundi(preview.after),
		_names(preview.forgotten), _names(preview.dormant), preview.points_after]
	dialog.popup_centered(Vector2i(mini(640, int(get_viewport().get_visible_rect().size.x) - 32), 300))


func _names(ids: Array) -> String:
	var names: Array[String] = []
	for id in ids:
		names.append(TEXT.skill_name(str(id)))
	return ", ".join(names) if not names.is_empty() else TEXT.t("antidoteNone")


func is_open() -> bool:
	return dialog != null and dialog.visible


func _confirm() -> void:
	_player.call("confirm_antidote")
	dialog.hide()
	get_tree().paused = _previous_pause


func _cancel() -> void:
	_player.call("cancel_antidote")
	dialog.hide()
	get_tree().paused = _previous_pause


func _exit_tree() -> void:
	if is_open():
		get_tree().paused = _previous_pause
