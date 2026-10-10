# Shelf, glass, loading and mutagen repairs — 2026-10-10

Combined with `placement_templates_weapons.md` in the owner-requested draft PR.

## Behavior

- Six shelf models use welded mesh board geometry rather than one solid outer AABB. Thin boards and planar frame faces become merged/pruned box colliders. Workstation profiles match the measured support surfaces.
- Glass collection respects authored visibility within Visual, including when its pending mission ancestor is hidden. Breaking registered panes hides their visuals and disables collision.
- Mission loading keeps the tree paused and loading overlay up while actual shared materials are rendered in small batches. Rendering completion is awaited on native renderers before gameplay resumes; headless exercises ordering and cleanup.
- Mutagen collision and rendered particles occupy 0.5–2 metres above stable support, including clouds spawned on elevated enemy pivots. Shader clipping and feathering use actual world positions.
- Priority queue parent indexing uses integer shift, resolving the screenshot warning.

## Validation

Godot 4.7.2 clean/final import and project architecture/workflow/resource/import gates passed. Three Python workstation tests passed. Focused shelf/glass/loading, mission loading, shader warmup, mutagen cloud, previous placement/templates/weapons, glass crack, and destruction wiring suites passed. Destruction audit: 230 catalog models / 98 staged models / zero failures.

The new shelf suite physically raycasts every configured level with rotation/scale, settles actual book props for 120 physics ticks, bounds compound shape count, breaks glass in a mission initially hidden, verifies material deduplication/cleanup while paused, and checks the cloud floor offset and height band. It is included in Runtime CI.

No public API, DTO, module dependency or state-owner changes. The private geometry helper keeps collision reconstruction separate from prop lifecycle. Existing large files retain their existing responsibility; warmup is delegated to a private bootstrap helper.

## Remaining acceptance

Native GPU texture arrival and Windows/Web visual acceptance need target-renderer review; local headless tests cannot prove GPU appearance. The screenshot allocator `mem is null` at prop contact was not reproduced, so this patch does not claim to resolve it. CI native renderer regressions remain the publication checks.
