extends RefCounted
## Authored alternatives per species/action, shared immutable configuration.
## The catalogue and combination report are generated from these same records.

const PROFILES := {
	&"growl_hunger": {
		&"idle": [0.65, [&"hunger_idle", &"growl_hunger"]],
		&"voice": [1.0, [&"hunger_voice", &"growl_hunger"]],
		&"fours": [1.0, [&"hunger_fours_voice", &"hunger_voice"]],
		&"idle_scream": [1.0, [&"hunger_voice"]],
		&"alert": [1.0, [&"hunger_alert"]],
		&"attack": [0.5, [&"hunger_attack", &"growl_hunger"]],
		&"pain": [0.35, [&"growl_hunger"]],
		&"agony": [1.0, [&"hunger_agony"]],
		&"feeding": [1.0, [&"hunger_feeding"]],
		&"death": [1.0, [&"hunger_death"]],
	},
	&"growl_revenant": {
		&"idle": [0.65, [&"revenant_idle"]],
		&"voice": [1.0, [&"revenant_voice", &"growl_revenant"]],
		&"attack": [0.5, [&"revenant_attack", &"growl_revenant"]],
		&"pain": [0.35, [&"growl_revenant"]],
		&"death": [1.0, [&"revenant_death"]],
	},
	&"growl_brute": {
		&"idle": [0.65, [&"brute_idle"]],
		&"voice": [1.0, [&"brute_voice", &"growl_brute"]],
		&"alert": [1.0, [&"brute_alert"]],
		&"attack": [0.5, [&"brute_attack", &"growl_brute"]],
		&"pain": [0.35, [&"brute_pain"]],
		&"death": [1.0, [&"brute_death"]],
	},
	&"growl_colossus": {
		&"idle": [0.65, [&"colossus_idle"]],
		&"voice": [1.0, [&"colossus_voice", &"growl_colossus"]],
		&"attack": [0.5, [&"colossus_attack"]],
		&"pain": [0.35, [&"growl_colossus"]],
		&"death": [1.0, [&"heavy_death"]],
	},
	&"growl_titan": {
		&"idle": [0.65, [&"titan_idle"]],
		&"voice": [1.0, [&"growl_titan"]],
		&"attack": [0.5, [&"titan_attack"]],
		&"pain": [0.35, [&"growl_titan"]],
		&"death": [1.0, [&"heavy_death"]],
	},
	&"growl_horde": {
		&"idle": [0.65, [&"horde_idle"]],
		&"voice": [1.0, [&"growl_horde"]],
		&"attack": [0.5, [&"growl_horde"]],
		&"pain": [0.35, [&"growl_horde"]],
	},
}


static func event_for(species: StringName, action: StringName, roll: float = -1.0) -> StringName:
	var profile: Dictionary = PROFILES.get(species, {})
	if not profile.has(action):
		return &""
	var spec: Array = profile[action]
	if (randf() if roll < 0.0 else roll) >= float(spec[0]):
		return &""
	var events: Array = spec[1]
	return events[randi_range(0, events.size() - 1)]
