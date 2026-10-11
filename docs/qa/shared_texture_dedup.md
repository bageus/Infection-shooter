# Shared model textures — 2026-10-09

T002 asset packaging increment requested by the owner after the project audit.

## Change

645 byte-identical PNG/JPG copies and their 645 import descriptors were removed.
917 embedded images in 159 GLB models now reference existing shared images by
relative URI. Matching requires identical SHA-256 bytes and effective Godot import
parameters; compression, normal-map processing and roughness dependencies are
preserved. No image was resized or re-encoded. 14 raw copies with different import
profiles remain deliberately; 14 embedded images lacking an unambiguous existing
tracked extraction remain embedded. Previously deleted authoring assets were not
restored. Direct resource references, UIDs and normal dependencies were migrated.

The source tree saves approximately 1266.68 MiB (1.24 GiB): 505.44 MiB in raw
images and 761.24 MiB in embedded payloads. Git history is unchanged, so this does
not shrink existing historical objects. The local rebuilt Godot cache decreased
from approximately 991 to 536 MiB. FPS and GPU-memory improvements are unmeasured.

Horde keeps its existing GLB path; its largest geometry buffer view is stored in
Horde_geometry.bin. This lossless external buffer keeps each upload below the
connector's 16 MiB request limit. Imported scene, geometry and image payloads are
identical. The migration reader supports external geometry buffers and validates
lengths. Display profiles were rebuilt only to refresh source hashes; their screen
geometry is unchanged.

## Protection and validation

`tools/deduplicate_model_textures.py` offers inspection, `--apply` and `--check`.
Architecture and Mission CI run `--check` and the migration's 10 regression tests.
Tests cover image bytes, material/scene fields, accessor and sparse index remaps,
shared views, import-profile differences, ignored authoring sources, URI escaping,
invalid headers and external geometry buffers. Runtime model tests additionally
assert that two bookcase models share the same normal Texture2D instance.

Local Godot 4.7.2 headless validation:

- All 257 model semantic fingerprints match the pre-migration snapshot.
- Static and imported catalog audit: 257 models, 184 textured, zero errors.
- Project, resource paths, import descriptors and display-source gates pass.
- 10 migration Python tests and 12 existing Python tests pass.
- 12 runtime suites pass: staged GLB, display, debris, surface decor, hit effects,
  enemy animation, dismemberment, group 01 assets, world surface, world bindings,
  display planner and layout bake.
- Cold editor import and main scene 180-frame smoke pass without script errors.

No public API, gameplay, save/network DTO, module dependency or state ownership
changed. Asset storage and test expectations for canonical texture paths changed;
there are no architectural exceptions. Native visual acceptance remains manual.

Rollback: revert this commit to restore original embedded payloads and raw copies.
