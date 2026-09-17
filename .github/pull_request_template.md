## Purpose

Describe the player-visible or technical outcome.

## Godot impact

- Modules changed:
- State owners changed:
- Scenes/resources changed:
- Public APIs changed:
- Save/network formats changed:
- Autoloads changed:

## Architecture checklist

- [ ] I read `AGENTS.md` and `docs/ARCHITECTURE.md`.
- [ ] Every new module has a valid `module.json`.
- [ ] Cross-module `res://` references are declared and target `public/`.
- [ ] No mutable state gained a second owner.
- [ ] No gameplay Autoload, global signal bus, service locator, root lookup, or dependency cycle was added.
- [ ] Shared Resources remain immutable definitions.
- [ ] Save/network/public format changes are versioned and migrated.
- [ ] Architecture changes include an approved ADR.
- [ ] `python tools/validate_architecture.py` passes.
- [ ] Godot headless import and relevant tests pass.

## Validation evidence

List exact commands and results.

## Risks and rollback

Describe remaining risks and how the change can be reverted.
