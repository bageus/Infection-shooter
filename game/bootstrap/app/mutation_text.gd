extends RefCounted
const BALANCE := preload("res://game/features/infection/public/mutation_balance.gd")
const LOCALIZATION := preload("res://game/core/localization/public/ui_translations.gd")


static func t(key: String) -> String:
	LOCALIZATION.ensure_registered()
	return str(TranslationServer.translate(StringName(key)))


static func skill_name(id: String) -> String:
	return t("mutationSkill_" + id + "_name")


static func description(id: String) -> String:
	var text := t("mutationSkill_" + id + "_description")
	if id.begins_with("discharge"):
		text += "\n" + t("mutationLightningHint")
	elif id.begins_with("power_strike"):
		text += "\n" + t("mutationStrikeHint")
	return text.format(BALANCE.text_values(id, TranslationServer.get_locale()))


static func branch(id: String) -> String:
	var parts: Array[String] = []
	for part in id.split(" + "):
		parts.append(t("mutationBranch_" + part.replace(" ", "_")))
	return " + ".join(parts)


static func label(key: String, size: int, bold := false) -> Label:
	var node := preload("res://game/bootstrap/app/menu/menu_style.gd").label(t(key), size, bold)
	node.set_meta("translation_key", key)
	return node


static func refresh(root: Node) -> void:
	for node in root.find_children("*", "Control", true, false):
		if node.has_meta("translation_key"):
			node.set("text", t(str(node.get_meta("translation_key"))))
