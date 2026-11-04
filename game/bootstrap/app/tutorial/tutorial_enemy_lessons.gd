extends RefCounted
## Enemy and blast lessons for the quest constructor. Each is one click step: the enemy's live idle model
## (tutorial_enemy_preview.gd) with its name and a short text. Numbers come from the enemy scene exports and
## from blast_effect.gd (EXTINGUISHER_RADIUS, CREATURE_DAMAGE, STUN_BASE + STUN_FALLOFF); the test checks these, so a changed stat fails it.

const PREVIEW := preload("res://game/bootstrap/app/tutorial/tutorial_enemy_preview.gd")
const SCENE_DIR := "res://game/features/infected/public/"

const DATA := {
	"enemy_infected": {"scene": SCENE_DIR + "infected_capsule.tscn", "name": "Заражённый",
		"text": "Заражённый быстро двигается и атакует, но его достаточно легко уничтожить любым оружием."},
	"enemy_hunger": {"scene": SCENE_DIR + "infected_hunger.tscn", "name": "Голодный",
		"text": "Очень быстрый и часто атакующий: 45 здоровья, 12 урона за удар. Хрупкий, но в упор опасен, когда их много."},
	"enemy_revenant": {"scene": SCENE_DIR + "infected_revenant.tscn", "name": "Ревенант",
		"text": "Средний по прочности: 75 здоровья и скорость 4.6. Бьёт сильнее обычного заражённого: 16 урона за удар, раз в секунду."},
	"enemy_brute": {"scene": SCENE_DIR + "infected_brute.tscn", "name": "Громила",
		"text": "Крепкий: 135 здоровья. Медленнее заражённых, но удар тяжёлый: 24 урона, атакует примерно раз в 1.1 секунды."},
	"enemy_titan": {"scene": SCENE_DIR + "infected_titan.tscn", "name": "Титан",
		"text": "Очень живучий: 260 здоровья. Идёт медленно, но бьёт 38 урона и может ломать преграды на пути."},
	"enemy_colossus": {"scene": SCENE_DIR + "infected_colossus.tscn", "name": "Колосс",
		"text": "Самый прочный и медленный: 420 здоровья. Удар по 50 урона. Поднимает руки и бьёт по полу: ударная волна радиусом 6 м наносит игроку 32 урона."},
	"enemy_horde": {"scene": SCENE_DIR + "infected_horde.tscn", "name": "Орда",
		"text": "150 здоровья, скорость 5.0, удар 14 урона. Призывает подкрепление: примерно раз в 12 секунд, если игрок в 24 м, появляются голодные, ревенанты или громилы."},
	"blast_extinguisher": {"name": "Взрыв огнетушителя",
		"text": "Взрыв огнетушителя наносит небольшой урон и оглушает всех, кто находится в зоне поражения."},
}


static func ids() -> Array[String]:
	var result: Array[String] = []
	for lesson in DATA:
		result.append(str(lesson))
	return result


static func has(lesson: String) -> bool:
	return DATA.has(lesson)


## The one step of an enemy or blast lesson. Enemies get a live preview of their idle model.
static func step(lesson: String) -> Dictionary:
	var entry: Dictionary = DATA[lesson]
	var result := {"title": str(entry.name), "text": str(entry.text), "targets": [], "mode": "click"}
	if entry.has("scene"):
		result["preview"] = str(entry.scene)
	return result
