extends RefCounted
## Step order of the first-time mutation training. Pure data: no nodes, no input, no saves.
## Each step names a text key (empty for none), the target ids to light, and how it ends.

const PHASE_SCALE := &"scale"
const PHASE_BRANCHES := &"branches"
const PHASE_LOSS := &"loss"

## The scale training starts once the mutation scale reaches this value.
const SCALE_TRIGGER := 5.0

## Ends on any mouse press or key press; the press is not consumed unless the step blocks the mouse.
const ADVANCE_PRESS := &"press"
## Ends when the player has learned the Power Strike skill.
const ADVANCE_POWER_STRIKE_LEARNED := &"power_strike_learned"

const STEPS := {
	PHASE_SCALE: [
		{"text": "", "targets": ["mutation_bar"], "dim": 0.0, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutScaleThreshold", "targets": ["mutation_bar"], "dim": 0.78, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutScaleAntidote", "targets": ["antidote"], "dim": 0.78, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutScaleSpend", "targets": ["antidote"], "dim": 0.78, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
	],
	PHASE_BRANCHES: [
		{"text": "tutBranches", "targets": ["tree_active", "tree_passive"], "dim": 0.78, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutActive", "targets": ["tree_active"], "dim": 0.78, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutPassive", "targets": ["tree_passive"], "dim": 0.78, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutPickStrike", "targets": ["tree_power_strike"], "dim": 0.78, "blocks": false, "arrow": true, "advance": ADVANCE_POWER_STRIKE_LEARNED},
		{"text": "tutKillStrike", "targets": [], "dim": 0.78, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutPin", "targets": [], "dim": 0.78, "blocks": true, "arrow": false, "advance": ADVANCE_PRESS},
	],
	PHASE_LOSS: [
		{"text": "tutLossAntidote", "targets": ["antidote"], "dim": 0.78, "blocks": false, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutLossEffect", "targets": ["antidote"], "dim": 0.78, "blocks": false, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutLossMask", "targets": ["gas_mask"], "dim": 0.78, "blocks": false, "arrow": false, "advance": ADVANCE_PRESS},
		{"text": "tutLossMaskCooldown", "targets": ["gas_mask"], "dim": 0.78, "blocks": false, "arrow": false, "advance": ADVANCE_PRESS},
	],
}


static func steps(phase: StringName) -> Array:
	return STEPS.get(phase, []).duplicate(true)
