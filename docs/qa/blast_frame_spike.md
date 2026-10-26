# Grenade frame spike (26.10.2026)

Report: after a grenade in a crowded corner the game froze (F3: 5 FPS, process 76 ms) and stayed slow.

## Cause
Reproduced on the real `base_office_layout` (3250 props), High destruction quality, grenade at the densest spot
(`tools/bench_blast_spike.gd`, headless, physics paused after the blast so only script/scene work is timed):

- every prop in the radius built its pieces in the same frame (`call_deferred("_apply_damage")`), about 400 pieces;
- `fragment_runtime._compact` rebuilt the whole piece FIFO on every registration once it passed 256 entries:
  a full pass per piece (about 78 ms for 400 pieces) and every rebuilt record lost its birth time, so fresh pieces
  were no longer spared by the budget.

## Change
- `destruction_budget.gd`: breakups (`_apply_damage`, cabinet splits, table part breaks) run oldest first, about
  5 ms per frame, at least one per frame. Glass shatter stays deferred.
- `fragment_runtime._compact` drops tombstones only when they outnumber live entries and keeps birth times.
- Pieces that are chips (largest edge <= 0.4 m) or sheets (thinner than 5 cm) cast no shadow.

## Measured (3 runs each, same machine, headless)
| | before | after |
|---|---|---|
| explode() synchronous | 40-44 ms | 29-38 ms |
| worst frame after the blast | 163-188 ms | 46-62 ms |
| two worst frames in a row | 134+163, 188+180 ms | 46+32, 62+49, 49+31 ms |
| 60 frames after the blast, total | 720-781 ms | 526-619 ms |
| `_register_budget` for 400 pieces | 78 ms | below 5 ms |

Not measured: real GPU, native Windows/Web. Draw-call counts from the software renderer were not stable enough to
quote. Tests: `run_destruction_budget_tests` (new), `run_blast_break_tests` and `run_debris_floor_tests` now wait for the budget.
