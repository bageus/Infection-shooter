# Plate fruit (plate_fruit_v1)

Planner: selecting or placing `09_fruit_plate_2` opens a "ТАРЕЛКА" panel with a fruit switch (off by default), a count 1-5 and "Другая раскладка". Fruit models are the existing `09_fruit_apple/orange/banana(_b).glb`; at most one banana per plate.

- Layout: `PlateFruit.layout(count, seed)` is deterministic; the seed is stored in the optional `fruit` record of the map object, so a saved map restores the same plate.
- One object: the fruit is a `Fruit` child of the plate visual, so it shares the plate body and gets its own collision boxes through the normal prop geometry.
- Hit: the first damaging hit either breaks the plate (plate and fruit become loose fragments, glass_break sound) or flips it (impulse plus torque) while the fruit scatters as loose fragments. Later hits behave as for any loose prop.
- Plates without fruit (all existing maps) are unchanged. The platter `09_fruit_plate.glb` is not covered.

Tests: `game/presentation/office_floor/tests/run_plate_fruit_tests.gd`, `run_planner_object_settings_tests.gd` (panel, live edit, save/reload).
Open: visual check in the real planner UI and a shooting pass in a mission.
