# ADR-0066: Melee key kicks or jabs

Status: accepted

The melee key (C) now plays a procedural strike over the player's clips
(`character_animation/strike_pose.gd`, driver `play_strike`/`is_striking`): a
rear-leg (left) front kick baked from the "Standing Melee Attack Kick" capture
(`kick_clip_data.gd`, mirrored because the hero stands with the right foot forward and the
capture kicks with the right foot from a left-foot-forward stance): knee chambered,
sole driven forward, hips turning and travelling behind it, torso following the
capture while the arms keep their pose, or a left-hand jab when an enemy's surface is within 2 m.
`features.player/player_melee.gd` owns timing and effect. The strike lands
0.27 s (kick) or 0.14 s (jab) after the press. A kick breaks loot crates at once
and throws other loose rigid bodies away from the character (speed capped by
mass); a jab deals 17 damage to the enemy in front. A hidden 2 s cooldown starts
at the press. No new module dependency, owner, DTO or save data.
