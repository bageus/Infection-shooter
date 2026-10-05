# Blast feedback acceptance

Close explosions already call player.apply_blast_stun after damage and a shelter test. This pass adds rendering/audio feedback to that accepted state; radius 5.5 m, damage, cover and existing 3–5 s duration remain unchanged. Strength comes from the existing distance falloff. No new menu setting/map field/dependency.

- Blur: mip LOD up to 1.8, one screen pass active only during stun.
- Ghosts: four directions, up to 14 px at 1280×720, sinusoidal convergence/divergence at 5.5 rad/s; displacement scales with existing proximity intensity.
- Glitch: sparse seven-pixel horizontal bands, updated at 13 Hz, up to six pixels of offset; slight RGB fringe (up to 2.8 px) and at most 8% darkening only inside occasional bands. No flash/exposure increase.
- Recovery: final one second visually fades. Existing tinnitus becomes a restrained 2800/3200 Hz mix, fades in final 0.8 s. Pause/planner/game-over/scene exit cancels both and restores the previous mix.
- Layer -1 distorts the 3D scene before HUD/mutation/menu canvases; does not consume input. Shader phase is driven by scene processing rather than TIME. Dormant overlay is hidden and process disabled.

Public player contract blast_feedback_v1 adds typed blast_stun_started(duration, intensity) and blast_stun_ended facts. Bootstrap only reads them to own temporary visual state, not gameplay. Sound stays under existing Master/mute settings. Source shared models/materials are unchanged; no shaders are added to object materials.

run_blast_feedback_tests validates real near/far/sheltered blast dispatch, repeat hits, actual tone/loop/high frequency, fading, natural expiry, pause/exit and audio recovery. Rendered checks use a static high-contrast 3D fixture, require scene image differences and temporal motion, unchanged HUD pixels and exact recovered baseline. Both Compatibility and real Vulkan Forward+ on software llvmpipe passed. Synthetic screenshots demonstrate shader behavior only; subjective mixing and performance in Windows/browser have not been accepted.

Manual: shoot the grenade launcher at two/three/five metres while surviving, repeat during an existing stun, then test behind a full wall and outside blast range. Observe four ghost directions, recovery, and short ringing; open pause/planner during the effect, change Sound/volume and restart. Verify no residual blur/ringing or stuck master attenuation. Compare in Windows Forward+ and desktop Web Compatibility at native resolution. Record frame time in the populated fight and adjust blur/spread/tone strength only after this review.

Changed files: player_movement.gd lifecycle/tone hooks, player/app manifests, main.gd composition, blast_feedback.gd/.gdshader, run_blast_feedback_tests.gd, runtime CI, ADR-0024, architecture and state/task docs. No architecture exception. Large player script retains gameplay/audio ownership and receives only small lifecycle hooks; all screen implementation is in the separate bootstrap component.
