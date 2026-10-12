# Long-gun grip and simple chair (12.10.2026)

## Rifle grip
Lit renders (`tools/capture_long_gun_grip.gd`, six angles, AK / M4 / sniper / minigun) showed the
rear of the AK, M4 and sniper rifle poking through the back of the vest: the rear hand target sat
only 0.07 m in front of the spine, but the stocks reach further behind the hand.
`player_equipment_pose.gd` now places the rear hand 0.19 m forward for AK/M4. The sniper is
0.17 m forward and 0.03 m nearer the centre line; its support-hand error is 0 (it was 0.022 m, too close to the 0.025 m test limit at 0.20 m).
The minigun pose is unchanged. `run_new_weapon_tests.gd` now waits until the Launcher clip has advanced before measuring the hand (the first frames after equipping still show the pistol stance, where the arm cannot reach). Before/after sheets: `weapons_hud_review/long_guns_grip_{before,after}.png`.

## simple chair
The old model had an extra off-centre cushion mesh inside the seat, 576-vertex legs and a fully
metallic steel material with stretched UVs that rendered almost black. `tools/build_simple_chair.py`
rebuilds `06_simple_chair(.glb|_fell.glb)` with the same node tree, node transforms, destruction extras
(Intact + LargeParts scenes), materials slots and bounds: smooth rounded seat, cushion and backrest, 12-sided
tapered legs (65 vertices) and an unstretched brushed-steel UV mapping. Preview:
`tools/capture_chair_preview.gd`; result `weapons_hud_review/simple_chair_after.png`.
