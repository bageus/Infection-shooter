# Copilot instructions for Godot

This is a Godot 4.x GDScript modular-monolith project.

Before changing files, read:

1. `/AI_START_HERE.md`
2. `/AGENTS.md`
3. `/GAME_SPEC.md`
4. `/docs/WORKING_AGREEMENT.md`
5. `/PROJECT_STATE.md`
6. `/ACTIVE_TASK.md`
7. architecture, manifests, and ADRs

Never bypass module boundaries. Cross-module `res://` references must be declared and must target the dependency's `public/` directory.

Do not add gameplay Autoloads, global signal buses, service locators, absolute `/root/` lookups, dynamic cross-module paths, or mutable shared Resources.

Scenes compose Nodes; domain rules remain independently testable. External code may use a public scene root API but must not rely on its child layout.

Before completion run:

```bash
python tools/validate_game_spec.py
python tools/validate_workflow_state.py
python tools/validate_architecture.py
godot --headless --path . --editor --quit
```

If the request conflicts with architecture, propose an ADR and wait for explicit approval.
