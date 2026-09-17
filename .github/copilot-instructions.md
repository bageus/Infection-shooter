# Copilot instructions for Godot

This is a Godot 4.x GDScript modular-monolith project.

Before changing files, read:

1. `/AGENTS.md`
2. `/docs/ARCHITECTURE.md`
3. `/architecture/policy.json`
4. relevant `module.json` manifests and ADRs

Never bypass module boundaries. Cross-module `res://` references must be declared and must target the dependency's `public/` directory.

Do not add gameplay Autoloads, global signal buses, service locators, absolute `/root/` lookups, dynamic cross-module paths, or mutable shared Resources.

Scenes compose Nodes; domain rules remain independently testable. External code may use a public scene root API but must not rely on its child layout.

Before completion run:

```bash
python tools/validate_architecture.py
godot --headless --path . --editor --quit
```

If the request conflicts with architecture, propose an ADR and wait for explicit approval.
