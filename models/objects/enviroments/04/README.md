# Group 04 shared atlas

Seven cardboard/painted-wood assets share one UV layout, three texture maps and
two immutable ORMMaterial3D resources (opaque and double-sided). Scene filenames,
nodes, transforms, default stages and all fragment identities remain unchanged.
The staged GLB addon still imports every damage stage.

| Surface | Treatment |
| --- | --- |
| Light/brown cardboard | Two representative original 512px fibre textures, resized to 496px inside padded cells; subtle fibre normals and roughness variation around the original 0.82 |
| Dark interior | Near-uniform original texture becomes a solid tile; original noise was at most one RGB byte, without readable markings |
| Ivory / two flat cardboard colours | Original linear glTF colours converted to sRGB atlas pixels; original roughness 0.78 / 0.65 retained |
| Olive painted wood | Original linear paint colour and roughness 0.56 retained; no invented metallic response or wood-grain repaint |

Albedo is 1024²; normal and ORM are 512². All maps use mipmaps and VRAM
compression. Eight-pixel albedo gutters become four-pixel gutters in the smaller
maps. ORM channels are neutral AO / roughness / metallic (zero throughout).

The old nine extracted PNGs and their nine import profiles are removed. Every
GLB remains useful: different boxes, crate sizes and authored damage geometry
are not duplicate files. The original files remain in Git history.

UV rework is required for a conventional atlas: original repeat UVs outside
0–1 are split at integer boundaries. Cardboard triangles gain 268 subdivisions
across all damage stages (+2.0% total triangles), without changing the surface.
The exceptionally repeated dark interior of `04_cardboard_boxes_1` maps to a
constant patch, avoiding thousands of unnecessary subdivisions. Constant-colour
crate surfaces receive UVs/tangents without geometrical changes.

Rebuild from the unmodified directory at the `source_ref` in `atlas_layout.json`:

```sh
git archive a48e5a49028b0871852f4418eeb8eb2670671ea2 models/objects/enviroments/04 | tar -x -C /tmp/group04-source
python models/objects/enviroments/04/scripts/build_unified_pack.py --inputs /tmp/group04-source/models/objects/enviroments/04 --output /tmp/group04-output
python tools/check_group04_atlas.py --compare-ref a48e5a49028b0871852f4418eeb8eb2670671ea2
```

Create the temporary source/output directories first. Authoring uses the same
numpy/Pillow/scipy dependencies as group 01; no new runtime dependency is added.
`unified_validation.json` records sizes, triangle counts and tile assignments.
Geometry validation independently checks every mesh's positions, normals, area
and subdivision vertices, as well as scene/node identity.

The atlas reduces compatible surfaces inside each mesh; it does not batch
separate objects or independently simulated fragments. See
`docs/qa/group04_atlas.md` for measured budgets and validation limitations.
