# B: phone tests of the Metal camera view

- **Made:** 25 Nov 2026 by Claude, from Amadeus's screenshots. Labels: **verified** = in the screenshots · **inferred** = reasoned, not measured.

## Run 1: Metal mode (`-scanRenderer metal`), Debug, from Xcode (Amadeus, night of 24–25 Nov)

| Moment | Memory | CPU | FPS | Energy |
|---|---|---|---|---|
| Camera opens | 612.2 MB | 147% | 60 | High |
| Subject tapped | 689.7 MB | 168% | 60 | High |
| Later (labelled "camera tapped"; CPU 0%, an AirDrop happened at the same time) | 560.2 MB | 0% | 59 | Very High |

- The memgraph could not be exported: the debug session ended first (Amadeus).
- The view: dashed outlines draw in Metal mode, and the tags sit on the items (screenshot "The view").

## Compared with "Part 1" (A branch, ARView mode, Debug; investigate/docs note §2e)

| Moment | ARView (A, Part 1) | Metal (B, run 1) |
|---|---|---|
| Camera opens | 490 MB | **612 MB** |
| Scanning | 631–646 MB | **690 MB** |
| FPS while scanning | 55–60 (one dip to 19 at the first light) | 59–60 |

> [!WARNING]
> Open: Metal mode used **more** memory in this run, not less. Not explained yet. Needed: a memgraph **during** the scan in Metal mode, and the same walk in ARView mode **on the same B build** (no launch argument), so the two runs differ only in the renderer.

## Recording 25 Nov 13:44 (Metal mode, as far as Claude can tell)

- 16 frames read: smooth view; tags on the items; the subject box (bottle on a table) is much wider than the bottle, because the column (10 cm radius, from the room floor + 3 cm to 3 m) includes the table top. Not a B problem: both renderers draw `viewModel.outlineBoxes`.
- The spray bottle (camera stand-in) gave "Not enough LiDAR points": clear plastic is hard for LiDAR (expected).
- Full explanation, the A vs B differences and the diagnosis steps: main folder `investigate/docs/scan-renderer-decision_2026-11-25.md`.
