# Display QA

Godot 4.7.2 headless display and planner suites passed: nine authored GLB screen profiles, static 16 cells, three dynamic sequences, original frame timing, stable auto power, distinct dual-monitor content, television grouping/splitting, forward spotlight cone, damage, duplicate/delete/undo and layout v8 roundtrip. Pixel checks are executed in CI with Compatibility and Vulkan Forward+.

Target Windows/Web acceptance: select each screen model, change on/off/auto and static/dynamic; confirm texture is restricted to the screen, housing untouched and glow subtle only in front. Combine adjacent equal-scale frameless televisions into a rectangle; rotate/separate a panel and check regrouping. Test mixed power states. Play all GIF loops. Rotation source final frame is damaged and holds the previous frame for 50 ms; originals are preserved. Runtime atlases consume about 84 MiB uncompressed.
