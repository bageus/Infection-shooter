# Copilot repository instructions

Before generating or changing code, read and follow:

1. `/AGENTS.md`
2. `/docs/ARCHITECTURE.md`
3. `/architecture/policy.json`
4. relevant `module.json` manifests and ADRs

Do not invent exceptions. Do not access module internals, create cyclic dependencies, add global mutable state, or mix gameplay logic with UI or concrete infrastructure.

For every new module, create a manifest from `/templates/module.json`. Declare dependencies before using them.

Before presenting work as complete, run:

```bash
python tools/validate_architecture.py
```

If a requested change conflicts with the architecture, explain the conflict and propose an ADR; do not silently bypass the rule.
