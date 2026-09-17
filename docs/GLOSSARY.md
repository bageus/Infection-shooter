# Project Glossary

Use one stable term for each game concept. AI agents must consult this file before introducing synonyms in code or documentation.

## Rules

- Add a term when it has project-specific meaning.
- Prefer player-facing language unless a technical distinction is required.
- Give IDs stable `snake_case` forms.
- Rename through an explicit migration; do not leave mixed terminology.

## Terms

| Term | Stable ID | Meaning | Not the same as |
|---|---|---|---|
| Phase | phase | Major development stage numbered 0–8 | Milestone or task |
| Milestone | milestone | Measurable outcome inside a phase | Calendar deadline |
| Task | task | One small verifiable unit of work | Broad feature idea |
| Module | module | Architecture boundary with one coherent capability | Folder chosen only for organization |

Add game-specific terms during discovery.
