## Purpose

Describe the user-visible or technical outcome.

## Modules and ownership

- Modules changed:
- State owners changed:
- Public APIs changed:

## Architecture checklist

- [ ] I read `AGENTS.md` and `docs/ARCHITECTURE.md`.
- [ ] Every new module has a valid `module.json`.
- [ ] Dependencies are declared and use public APIs only.
- [ ] No mutable state gained a second owner.
- [ ] No global state, service locator, global event bus, or dependency cycle was added.
- [ ] Save/network/public format changes are versioned and migrated.
- [ ] Architecture changes include an approved ADR.
- [ ] `python tools/validate_architecture.py` passes.
- [ ] Relevant tests and builds pass.

## Validation evidence

List exact commands and results.

## Risks and rollback

Describe remaining risks and how the change can be reverted.
