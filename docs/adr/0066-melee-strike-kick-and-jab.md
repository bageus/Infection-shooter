# ADR-0066: Melee key kicks or jabs

Status: accepted

The melee key (C) now plays a procedural strike over the player's clips
(`character_animation/strike_pose.gd`, driver `play_strike`/`is_striking`): a
right-leg kick forward, or a left-hand jab when an enemy's surface is within 2 m.
`features.player/player_melee.gd` owns timing and effect. The strike lands
0.24 s (kick) or 0.14 s (jab) after the press. A kick breaks loot crates at once
and throws other loose rigid bodies away from the character (speed capped by
mass); a jab deals 17 damage to the enemy in front. A hidden 2 s cooldown starts
at the press. No new module dependency, owner, DTO or save data.
