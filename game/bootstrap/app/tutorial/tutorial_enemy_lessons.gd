extends RefCounted
## Enemy, blast and spawn hole lessons for the quest constructor. Each is one click step: the enemy's live idle model
## (tutorial_enemy_preview.gd) with a title and a short text. Titles and texts are translation keys (translations.json, ru and en),
## so the lesson follows the menu language. Texts describe what to expect, without stat numbers.

const PREVIEW := preload("res://game/bootstrap/app/tutorial/tutorial_enemy_preview.gd")
const TEXT := preload("res://game/bootstrap/app/mutation_text.gd")
const SCENE_DIR := "res://game/features/infected/public/"

const DATA := {
	"enemy_infected": {"scene": SCENE_DIR + "infected_capsule.tscn", "title_key": "tutEnemyInfectedTitle", "text_key": "tutEnemyInfected"},
	"enemy_hunger": {"scene": SCENE_DIR + "infected_hunger.tscn", "title_key": "tutEnemyHungerTitle", "text_key": "tutEnemyHunger"},
	"enemy_revenant": {"scene": SCENE_DIR + "infected_revenant.tscn", "title_key": "tutEnemyRevenantTitle", "text_key": "tutEnemyRevenant"},
	"enemy_brute": {"scene": SCENE_DIR + "infected_brute.tscn", "title_key": "tutEnemyBruteTitle", "text_key": "tutEnemyBrute"},
	"enemy_titan": {"scene": SCENE_DIR + "infected_titan.tscn", "title_key": "tutEnemyTitanTitle", "text_key": "tutEnemyTitan"},
	"enemy_colossus": {"scene": SCENE_DIR + "infected_colossus.tscn", "title_key": "tutEnemyColossusTitle", "text_key": "tutEnemyColossus"},
	"enemy_horde": {"scene": SCENE_DIR + "infected_horde.tscn", "title_key": "tutEnemyHordeTitle", "text_key": "tutEnemyHorde"},
	"blast_extinguisher": {"title_key": "tutBlastExtinguisherTitle", "text_key": "tutBlastExtinguisher"},
	"spawn_hole": {"title_key": "tutSpawnHoleTitle", "text_key": "tutSpawnHole"},
}


static func ids() -> Array[String]:
	var result: Array[String] = []
	for lesson in DATA:
		result.append(str(lesson))
	return result


static func has(lesson: String) -> bool:
	return DATA.has(lesson)


## The one step of an enemy, blast or spawn hole lesson. Enemies get a live preview of their idle model.
static func step(lesson: String) -> Dictionary:
	var entry: Dictionary = DATA[lesson]
	var result := {"title": TEXT.t(str(entry.title_key)), "text": TEXT.t(str(entry.text_key)), "targets": [], "mode": "click"}
	if entry.has("scene"):
		result["preview"] = str(entry.scene)
	return result
