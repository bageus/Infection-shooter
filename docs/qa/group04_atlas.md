# Group 04 atlas validation

Baseline: `a48e5a49028b0871852f4418eeb8eb2670671ea2`, Godot 4.7.2.

| Metric | Before | After |
| --- | ---: | ---: |
| Models / authored mesh nodes | 7 / 427 | 7 / 427 |
| Extracted texture files | 9 | 3 shared maps |
| Imported material definitions | 16 per-model definitions | 2 shared resources |
| Mesh surfaces, all stages | 484 | 427 |
| Mesh surfaces, seven intact objects | 16 | 7 |
| Triangles, all stages | 13,184 | 13,452 |
| GLB bytes | 1,416,924 | 1,867,672 |
| PNG bytes | 1,127,272 | 443,352 |
| GLB + PNG bytes | 2,544,196 | 2,311,024 (−9.2%) |
| Texture image GPU payload, mipmaps included | 1.500 MiB | 1.167 MiB (−22.2%) |

GPU measurements use `Texture2D.get_image().get_data_size()` on all nine old
compressed `.ctex` resources and the three new shared maps. This excludes driver
allocation overhead, mesh buffers, framebuffers and transient CPU decode buffers.
The GLB increase comes from crate UVs/tangents and repeat-boundary subdivision;
it is included in the total size comparison. Mesh-node count and physics objects
are unchanged. Surface reduction is not a claim of 57 fewer draws every frame:
many surfaces belong to hidden damage stages, and different objects still draw
separately. No FPS improvement has been measured.

## Changes and deletion decision

All seven GLBs are retained. Different box shapes and both crate sizes have
distinct geometry and usable break stages. Only the nine extracted legacy PNGs
and their nine `.import` files are deleted. Source files are recoverable from the
recorded Git revision. New resources are three padded atlases, two materials,
and a post-import script within the existing staged importer; no new addon.

The fibre images have three near-uniform colour families and no printing.
Light and brown families retain representative originals. Dark interior noise
is replaced with a constant patch (maximum original difference approximately
one RGB byte). Original single-colour material factors are converted from linear
glTF colours to sRGB pixels. Olive paint remains nonmetallic, roughness 0.56.
Cardboard fibre normals are subtle; roughness varies ±0.02 around original 0.82.
Uniform patches retain their original roughness. Neutral AO avoids baked light.

UV rework, rather than geometry redesign, was necessary. UV repeat boundaries
gain 268 triangles (+2.0% across all stages). The builder carries barycentric
positions/normals; an independent checker compares all meshes against Git source
and checks area, boundary bounds and every subdivision vertex. A thin cardboard
face initially lost by an inappropriate UV-area threshold was detected by that
comparison and fixed; the final comparison passes. Excessive dark-interior UVs
of `04_cardboard_boxes_1` become constant UVs, avoiding mesh explosion.

## Executed validation

- PASS: `check_group04_atlas.py --compare-ref a48e5a49028b0871852f4418eeb8eb2670671ea2`, including all scenes/nodes, positions/normals, live buffers and bounded atlas UVs.
- PASS: Godot `run_group04_asset_tests`, seven imported palette models, 427 stage nodes, shared material/texture allocation, GPU budget, cardboard primary breakage and crate secondary fragmentation.
- PASS: `run_debris_tests`, `run_prop_weight_tests` (actual box pushing), `run_group01_asset_tests`.
- PASS: `validate_project`, `validate_scene_resources`, `check_import_files`, dedup audit, seven texture-validator unit tests and ten texture-dedup unit tests.
- Godot editor import executed. The first full import of the untouched baseline emitted missing-image errors outside group 04; final incremental import and focused group-04 execution contain no ERROR/SCRIPT ERROR.

GitHub CI run `38064618775` at `d12ef99` also passes the explicit
`Group 04 atlas and destruction` step. Its overall Import fails on missing
external images in the baseline; native planner jobs likewise stop at Import.
Architecture run `38064454683` confirms the missing-phone resource-path failure.

## Existing main failures

The untouched baseline has 315 static texture audit errors, predominantly missing
external textures in groups 02/03/05. `check_resource_paths` also reports three
missing phone models: `05_phone_a_base.glb`, `05_phone_a_base_hang.glb`,
`05_phone_b.glb`. The shared staged-GLB suite reports three damaged-server-rack
texture failures in group 03. These files are outside this change; tests and
checks remain enabled. A full-project green result cannot be claimed on this baseline.

Native visual acceptance in Compatibility/Forward+ and actual-game FPS remain
pending. Shared resources are immutable; no save DTO, public API, dependency,
state owner, scene filename or architecture exception changes.
