# Verification record

Paths under `build/` and terrain suite output directories are local artifacts. The terrain suite prints its temporary output directory on the first line. Tests ran on Windows 10 Pro, Ryzen 7 5800X, NVIDIA RTX 3060, Godot 4.7.2 official `ed1daf0bf`. Runtime target was the Steam public Windows x64 BZCC 2.0.185 executable.

## Automated workflow

```powershell
$godotRoot = 'V:/__STORE_V/_SOFT/Godot/4.7.2-stable'
$godot = "$godotRoot/Godot_v4.7.2-stable_win64.exe"
$vrv = 'V:/___VAC/__K/__CODE/_MISC/_BZDECOMP/vrv'
$game = 'V:/__STORE_V/_SOFT/Steam/steamapps/common/BZ2R'
$run = (./tools/Test-Terrain.ps1 -Godot $godot)[0]
./tools/Test-Terrain.ps1 -Godot $godot -WithGpu
g++ -O2 -std=c++17 -static-libgcc -static-libstdc++ -I "$vrv/src/shared" tools/terrain_oracle.cpp -o build/terrain_oracle.exe
./build/terrain_oracle.exe 'map_references/Brave Lil Toaster/braveliltoaster.TER' "$run/terrain-edit/braveliltoaster.TER"
./build/terrain_oracle.exe 'map_references/Brave Lil Toaster/braveliltoaster.TER' "$run/material-graph/braveliltoaster.TER" --graph
./tools/Test-BznTools.ps1 -Dotnet 'path/to/dotnet.exe'
./tools/Test-BznObjectMove.ps1 -Parser 'build/<BZNTools run>/out/BZNParser.dll' -Source 'map_references/Brave Lil Toaster/braveliltoaster.bzn' -Export "$run/object-move/braveliltoaster.bzn" -Index 15
```

The internal suite rejects truncated TER, unsupported versions, bad bounds, and nonfinite heights. It checks exact no-op export, changed-source and destination collision handling, shared 2D/3D projection, 3D input, native path overlays, all three brush modes, undo/redo, project save/reopen, and edited TER reimport. Graph coverage includes port validation, cycles, deterministic two-layer output, preview isolation, undoable bake, and graph export/reimport. The suite also checks actual Verdana on the editor, node window and file dialog in Windows.

The independent VRV C++ codec verified 1,747 changed samples, a change from 100 m to 124 m at world (0, 0), and identical non-height layers. BZNTools built from a local source copy with Microsoft SDK 8.0.428. The library read both BZN files, but the writer emitted only the recognized prefix.

The material graph export from Brave changed 12,842 heights, 12,125 RGB samples and 13 base tile IDs in the independent VRV decoder. The decoder verified identical alpha, draw masks, point flags and overlay tile IDs. The editor suite verified that unedited block bytes and all companion hashes match. The GPU run at 640 × 540 checked the evaluated RGB and base tile colors in a 2D texture and the corresponding 3D mesh vertices.

The original SAIPEN suite records used the non-Git fingerprint. A before/after comparison using the installed engine's exact file-selection rules found 104 new files from one passing run, all under that run's `build/test-*` directory. Source and Godot metadata hashes matched, and the fingerprint excluded SAIPEN records. After moving outputs to the temporary directory, all 2,613 measured paths and hashes matched. With Git, the declared suite compares the content of tracked and nonignored source files before and after execution. The tests verify linked fixture hashes separately.

| BZN | Read entities / paths | Source bytes | Serialized bytes | Exact prefix |
|---|---:|---:|---:|---:|
| Brave Lil Toaster 1196 | 76 / 23 | 31,795 | 23,764 | 23,764 |
| Blank 1192 | 1 / 23 | 10,708 | 2,677 | 2,677 |

## Playtest on 2.0.185

```powershell
./tools/Start-Playtest.ps1 -Game $game -VrvSource $vrv -Mission "$run/terrain-edit/braveliltoaster.bzn"
./tools/Start-Playtest.ps1 -Game $game -VrvSource $vrv -Mission "$run/graph-bake/braveliltoaster.bzn"
./tools/Start-Playtest.ps1 -Game $game -VrvSource $vrv -Mission "$run/material-graph/braveliltoaster.bzn"
$flat = ./tools/New-FlatTerrainSnapshot.ps1 -Mission 'map_references/blank_map1/duel_map_27_autosave_01.bzn' -VrvTemplate "$vrv/mod/Data/Templates/vrv_new_blank.ter"
./tools/Start-Playtest.ps1 -Game $game -VrvSource $vrv -Mission $flat -KeepBznLayout -WithoutMissionScript -StartInEditor
```

The exported height edit and graph bake were tested in separate BZCC sessions with mission scripts enabled. Both loaded terrain at 2048 × 2048 m at (-1024, -1024), loaded `braveliltoaster.bzn`, entered MISSION / RUN, and later logged normal shutdown. The game used a resource stream that put only the Playtest snapshot ahead of stock and VSR assets. Its copied TER hashes matched the respective editor exports. The converter removed exactly one `ejectRatio` field in each BZN working copy with a separate restoration proof. The chosen converted BZN hash was `1ad84f9e0a0dde381c978fa4666e4e18c0647079d7a10e9c2c2613fb1b2cb450`. Multi-client gameplay and mission objectives were outside this run.

| File | SHA-256 |
|---|---|
| Brave source TER | `fc0577c372f1f196e6bfa6582d4b569add26ac8d9fa05a24acad101118901a9f82` |
| Terrain brush export and game snapshot TER | `d5b58426d4b6c4795c92ed15319687d0ba5263938db055bafdad481010714a00` |
| Graph bake export and game snapshot TER | `f6b0687306ae98a3c408ac26cfb9877056c877d3d2c018bbb8039be5816a8748` |
| Flat blank TER | `f264a6351f75bbf181230da05cb11ab3cde9d5ae99319bb4463a36cf3ae81ed2` |

The blank TRN and VRV template share a 2048 m square and nominal 100 m height. The copied 1192 BZN loaded in BZCC with `/startedit /noscript` and entered MISSION / RUN. Source files remained unchanged.

Engine log identifiers on this machine are `01.12.42.9156` (brush), `01.24.24.750` (graph), and `01.28.18.5640` (blank), all on 2026-11-21. The app's Playtest action was also exercised using `res://tests/playtest_session.gd`. It generated an isolated snapshot, started the helper and confirmed the launched process. Its game log `01.31.11.7984` records MISSION / RUN and normal shutdown.

The 2026-11-21 log `08.24.58.9406` records the mixed material graph export loading with VSR's `Strategy02.dll`, entering MISSION / RUN and shutting down normally. The private runtime TER matched the exported SHA-256 `ed5f391e49981a635d6c565100191038f5cc94cbdc32d13a8f3361c979a37782`. The helper removed the private game directory after exit.

The object workflow moved Brave entity 15, `morock03`, in a private export. BZNTools independently found one translation change across 76 entities. The editor byte comparison verified the orientation, IDs and opaque suffix. The independent asset test confirmed that loading native models after an edit uses the saved position and responds to Undo. The 2026-11-21 BZCC log `08.33.39.750` records the object export entering MISSION / RUN and exiting normally. BZNTools reads the untouched-layout export. VRV's 185 adapter removed one Craft field from the runtime copy, and restoring that field reproduced the original export SHA-256 `2df4daf2896b8e0a88e21c680942fbf1e531b85f226625a9c9545299bd04875e`.

## Object rotation, duplication and removal

The object-tools suite additions run against Brave in the same terrain suite (`Test-Terrain.ps1`, `FAILURES: 0`): the `]` and Shift+`[` hotkeys rotate the selection in exact float math about the engine's world up axis, undo steps re-apply each rotation independently, Ctrl+D appends a full record copy with a fresh sequence, a labeled template gains a `_2` label, Delete removes an ordered base or appended record, every edit survives the BZMAG project round trip, and the zero-edit export is byte-identical to the source BZN. The count record, the rebuilt spawn headers and the insert boundary before the path count are covered by the export re-import assertion for each object's class, label, sequence and transform.

Independent probes: the public `bzn_compat.py` inspect reads the duplicate export as 77 entities and refuses a contradictory count declaration; the patch representation keeps the 8031-byte trailer and the 23-path table intact.

Engine playtests on 2026-11-21 with the standard conversion profile: the byte-identity export (`09.08.43`) and the `-14°` rotation export (`09.12.14`) both enter COCKPIT and MISSION / RUN with zero corruption lines. Control runs show the loader's limits: raw unconverted Brave reports the known `SAVEGAME CORRUPT AT OFFSET 411` (GBD_PUBLIC185_PORT), and the counted duplicate save aborts at the loader's spawner record with `SAVEGAME CORRUPT AT OFFSET 20976` and returns to the shell. Position, orientation and identity are therefore engine-verified; count-changing edits stay editor- and converter-verified with that limitation recorded in ENGINE_LIMITATIONS.md.

## Initial engine spike

In-process Godot loads and displays 2048 m Brave in about 1.2 s and 4096 m Workshop BZTC Total Coop `coop_bztcbd01` in 4.3 s on this machine. These are observed headless client startup measurements with OS caching uncontrolled.

| Data | 48 m dirty brush, median / max | Godot static memory, final / peak | Wall time including 10 strokes and 10 undos |
|---|---:|---:|---:|
| 2048 m Brave | 5.6 / 21.8 ms | 66.8 / 68.1 MiB | 3.32 s |
| 4096 m BZTC Total Coop | 4.9 / 18.7 ms | 147.9 / 160.5 MiB | 8.80 s |

The graphics-backed automated test measured 15.6 ms for a single brush and CPU-side dirty view update and 704 ms for transactional edited export on Brave. Frame pacing, GPU timing and true cold startup still need controlled sampling. Run the benchmark by passing an absolute BZN path to `--script res://tests/benchmark.gd` after `--`.

The external VRV C++ decoder read Brave in 23.6 ms. A separate run read both files and verified all layers in 58.2 ms wall time. Its compiled executable is 2.54 MB. That gives a useful validation backend if a separate terrain worker becomes necessary. The BZN .NET probe took about 401 ms end-to-end for both fixtures, including managed startup, type hints, parse and write. Probe deployment files totaled 1.56 MB, associated runtime directory files 73.6 MB. These measurements exercise different format operations. The in-process GDScript implementation already meets the measured brush latency goal without a worker protocol or .NET runtime dependency.

The Godot CLI builds the PCK from application files only. Windows x64 packaging uses the matching release template. [Godot command line](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) · [.NET 8 SDK reference](https://dotnet.microsoft.com/en-us/download/dotnet/8.0).

## Steam discovery and existing path edits

```powershell
./tools/Find-Bzcc.ps1
./tools/Test-Playtest.ps1 -Godot $godot -Mission "$run/path-edit/braveliltoaster.bzn"
./tools/Clean-Build.ps1 -Apply
```

With an empty test settings file, Playtest detected the Steam installation on V: and started the game process in 1,500 ms. The app exported the current map into a short `%TEMP%\bzm` directory. The BZCC log records the edited map entering MISSION / RUN. A normal exit removed the temporary runtime and map, and the editor reported that editing was ready. The standalone Steam lookup also found the game through a test libraryfolders entry in a separate Steam root.

The native path regression checks UI drag, rename, movement, duplicate name rejection, project round-trip and shared undo/redo. Its game-tested snapshot adds a point and changes `11Patrol1` to a loop. A comparison asserts exact bytes before the point record and after the edited route. The preserved bytes include the unknown BZN trailer. This run proves engine acceptance of the structure. It leaves route behavior and map-author intent to a mission-specific test.

The GPU test checks that button presets and the VRV shortcut bindings affect the same brush state shown in both views. It also checks path overlay updates, the native folder picker configuration and 3D view mode commands. The reference for the new workspace is the large terrain view, compact tool buttons and side map shown in the supplied BZCC screenshots, with the project's own Golden Default controls and Verdana.

## Native visual assets

```powershell
./tools/Build-ObjectPreview.ps1 -VrvSource $vrv
./tools/Test-ObjectPreview.ps1 -Godot $godot -Game $game -WithGpu
```

The GPU test opens the native map, enables Objects and Texture through the editor actions, and renders 76 object models, eight scrap pool instances and 16 terrain texture slots. Eight distinct object materials resolved native diffuse textures. The object scanner's count agrees with the independently parsed BZN. The screenshot and run log are under `build/object-preview`. The helper compiles locally from the installed VRV source and reads installed assets in place.

The local Workshop scan found 972 WAT v5 samples with the same 2,416-byte overhead followed by one byte per terrain block. The Brave terrain test verifies matching bounds, 222 layer-1 tiles and an encoded elevation of 135 m. WAT byte preservation remains covered by native export tests. The current water surface is an editor preview of that first layer.

## Water coverage and elevation editing

The suite's `test_water_tools` now edits the native WAT v5 alongside the terrain. Brave carries one layer and 222 mask blocks at elevation 135 m; the codec measures the same 64 × 64 block grid as the shipped `braveliltoaster.WAT` (6,512 bytes = 2,416 + 64 × 64).

- Coverage painting works in block units: the brush covers any block whose 32 m region intersects the radius disc, so the view-centre press at sample (512, 512) — the shared corner of four blocks — paints exactly those four blocks (222 → 226), and a 1 m dab at a block centre paints exactly one block. Undo and redo return and re-apply the whole stroke as one history record.
- The Edit Water dialog applies a layer elevation through the document history (135 m → 150.5 m on layer 0, recorded as one undo step; 90 m on layer 2 to place water in a second layer that previously carried no coverage). Invalid layers (index ≥ 8 or negative), non-finite heights and elevations beyond ±100000 m load model failures, and project loaders reject out-of-range keys with `Invalid project water layer.`
- BZMAG round-trip keeps both edited elevation keys and every coverage bit: the saved `waterEdits` record reopens with identical effective cover dictionaries.
- Native export patches the WAT in place: only mask bits and layer-height floats change, the file keeps exactly 6,512 bytes, and the written file matches `Water.encode(document-water-bytes, edits, heights)` byte for byte. Re-importing the export decodes the edited layers (221 blocks at 150.5 m after erasing one source block, plus one block at 90 m for layer 2) equal to the document's effective layers, and the exported height floats survive the 32-bit encode because the tested values are step-aligned (the earlier 150.25 m dialog value snapped to 150.3 m through the 0.1 m spin step, which reproduced the 32-bit rounding gap and is why the suite uses 150.5 m).
- The full headless suite including the new water workflow prints `FAILURES: 0`.
