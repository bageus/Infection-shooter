# Menu and runtime debug acceptance

## Automated checks
Godot 4.7.2: all 35 headless suites passed, with the four repaired suites rerun; final menu/settings/debug/audio/mutation suites and cold-cache debug/main smoke also passed. Project/resource/import/workstation/glass/scene-access gates passed. Initial CI 37365943743 succeeded including Compatibility and Vulkan Forward+ pixel tests; final-head CI must also pass. Runtime CI also captures all four settings tabs in RU/EN at 130% and the company page. Compatibility and Forward+ run occlusion pixel checks and runtime debug movement checks.

## Manual acceptance
1. Main: no patient/quarantine captions; disabled Continue has small No save beside it. Company heading is centred; review the proposed military-contractor history.
2. Settings: General (language/test cloud), Controls (22 editable bindings), Video (brightness/scale/occlusion/fullscreen), Audio (volume/sound). Scroll controls at 130%; reset restores defaults; changing language keeps the active tab. Settings have no hover sound except the audio toggle.
3. Assign movement to I and mutation tree to RMB; verify gameplay and restart persistence. Duplicate assignments are rejected; Escape cancels capture without closing settings.
4. Start with hole mode saved, test cloud off; walk behind walls/columns for 60 seconds. F3 shows mutation zero unless exposed in combat, control lost false and stable material counts. Compare CPU frame times/FPS against silhouettes on the same route.
5. Enable the clearly labelled test cloud and enter spawn: mutation may legitimately cause loss of control. Disable it: further absorption stops. Antidote/control ampule and normal timed recovery still work.
6. Reimport on the target machine after updating; four cooler bottles should load with no missing water texture. Fire a gun: smoke loads from textures/gun_fog/gun_fog.png. Red beanbag uses the same existing couches atlas alias.

## Limits
Headless does not prove shader pixels, target-device FPS or Windows/Web behavior. GPU CI uses software-rendered Linux. PR #25 has overlapping hole-cache files; check merge resolution if both PRs are applied.

Visual review of the initial CI images confirmed four RU/EN pages at 130%, scrollable controls, fixed action buttons, the small no-save caption and centred company heading. Old master-volume/brightness captions were corrected after this review.
