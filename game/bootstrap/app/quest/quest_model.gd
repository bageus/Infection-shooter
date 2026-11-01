extends RefCounted
## Quest list of one map: pure data, no nodes. The list order is the order of play; each quest starts
## after the previous one is complete. Stored in the map file under KEY.

const KEY := "quests_v1"
const MAX_QUESTS := 64
const MAX_TARGETS := 16
const MAX_TEXT := 400

const TYPES: Array[String] = ["find", "kill", "destroy", "pickup", "message", "lesson"]
const TYPE_LABELS := {
	"find": "Найти объект/предмет/врага", "kill": "Убить врага", "destroy": "Разрушить",
	"pickup": "Подобрать", "message": "Показать сообщение", "lesson": "Запустить обучение",
}
# Trigger: what starts the quest. "previous" means right after the earlier quest is complete.
const TRIGGERS: Array[String] = ["previous", "time", "steps", "reach"]
const TRIGGER_LABELS := {
	"previous": "Выполнено предыдущее задание", "time": "Время (секунды)",
	"steps": "Шаги (количество)", "reach": "Достижение цели или места",
}
# Completion: when the quest counts as done.
const COMPLETIONS: Array[String] = ["reach", "destroy", "collect", "steps"]
const COMPLETION_LABELS := {
	"reach": "Приблизился вплотную к цели", "destroy": "Уничтожить цель",
	"collect": "Собрана цель", "steps": "Пройдено шагов",
}
# Lesson id (tutorial director) and its label, in the order of the picker.
const LESSONS: Array[Array] = [
	["move", "Базовое обучение: ходить"], ["look", "Базовое обучение: управление камерой"],
	["roll", "Базовое обучение: перекат"], ["sprint", "Базовое обучение: ускорение"],
	["shoot", "Базовое обучение: выстрел"], ["mutation_scale", "Базовое обучение: мутации"],
	["active_skill", "Продвинутое обучение: мутации активные"], ["passive_skill", "Продвинутое обучение: мутации пассивные"],
	["gas_mask", "Базовое обучение: противогаз"], ["antidote", "Базовое обучение: антидот"],
	["crates", "Базовое обучение: разрушение ящиков в ближнем бою"], ["dna", "Базовое обучение: ДНК"],
	["armor", "Базовое обучение: броня"],
]
const DEFAULT_COMPLETION := {
	"find": "reach", "kill": "destroy", "destroy": "destroy", "pickup": "collect", "message": "", "lesson": "",
}
const PRESETS := {
	"find": "Найдите цель", "kill": "Убейте врага", "destroy": "Разрушьте цель",
	"pickup": "Подберите предмет", "message": "Сообщение",
}


static func lesson_ids() -> Array[String]:
	var ids: Array[String] = []
	for lesson in LESSONS:
		ids.append(str(lesson[0]))
	return ids


## A new quest of this type; the description starts as the preset and stays editable.
static func make(type: String, lesson: String = "") -> Dictionary:
	if not type in TYPES:
		type = "find"
	if type == "lesson" and not lesson in lesson_ids():
		lesson = str(LESSONS[0][0])
	return {
		"type": type, "lesson": lesson if type == "lesson" else "",
		"trigger": {"kind": "previous", "value": 0.0, "target": "", "point": []},
		"targets": [], "complete": {"kind": DEFAULT_COMPLETION[type], "value": 0.0},
		"delay": 0.0, "text": preset_text(type, lesson),
	}


static func preset_text(type: String, lesson: String = "") -> String:
	if type == "lesson":
		for entry in LESSONS:
			if entry[0] == lesson:
				return str(entry[1])
		return ""
	return str(PRESETS.get(type, ""))


static func lesson_label(lesson: String) -> String:
	return preset_text("lesson", lesson)


## The quest as it will be saved: unknown values fall back to the defaults, numbers are clamped.
static func normalize(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var type := str(source.get("type", "find"))
	var quest := make(type, str(source.get("lesson", "")))
	type = str(quest.type)
	var trigger: Dictionary = source.get("trigger", {}) if source.get("trigger") is Dictionary else {}
	var kind := str(trigger.get("kind", "previous"))
	quest.trigger = {
		"kind": kind if kind in TRIGGERS else "previous",
		"value": clampf(float(trigger.get("value", 0.0)), 0.0, 100000.0),
		"target": str(trigger.get("target", "")).left(80),
		"point": _point(trigger.get("point", [])),
	}
	var targets: Array[String] = []
	if source.get("targets") is Array:
		for id: Variant in source.targets:
			var text := str(id).left(80)
			if not text.is_empty() and not text in targets and targets.size() < MAX_TARGETS:
				targets.append(text)
	quest.targets = targets
	var complete: Dictionary = source.get("complete", {}) if source.get("complete") is Dictionary else {}
	var done := str(complete.get("kind", quest.complete.kind))
	quest.complete = {"kind": done if done in COMPLETIONS or done.is_empty() else str(quest.complete.kind),
			"value": clampf(float(complete.get("value", 0.0)), 0.0, 100000.0)}
	quest.delay = clampf(float(source.get("delay", 0.0)), 0.0, 3600.0)
	quest.text = str(source.get("text", quest.text)).left(MAX_TEXT)
	return quest


static func normalize_list(raw: Variant) -> Array:
	var list: Array = []
	if raw is Array:
		for entry: Variant in raw:
			if list.size() < MAX_QUESTS:
				list.append(normalize(entry))
	return list


## Error text for a stored list, "" when it is acceptable (the validator of the map file).
static func error(raw: Variant) -> String:
	if not raw is Array:
		return "invalid " + KEY
	if (raw as Array).size() > MAX_QUESTS:
		return "too many quests"
	for entry: Variant in raw:
		if not entry is Dictionary or not str(entry.get("type", "")) in TYPES:
			return "invalid quest"
	return ""


static func _point(raw: Variant) -> Array:
	if raw is Array and (raw as Array).size() == 2 and (raw[0] is float or raw[0] is int) and (raw[1] is float or raw[1] is int):
		return [float(raw[0]), float(raw[1])]
	return []
