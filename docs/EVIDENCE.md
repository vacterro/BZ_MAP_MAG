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

## Fly camera, rolling autosave and live symmetric brush

The suite's `test_fly_autosave_symmetry` covers the three remaining VRV-parity workflow features on Brave:

- Fly mode: the Fly button (or the F hotkey) arms free flight. W moves the camera along the exact look heading (`center + heading * distance * 0.6 * dt`), A/D strafe along the view right vector, Q/E rise and sink at half that rate, and the camera position clamps to the terrain bounds and 500 m below/3000 m above the terrain height range. The top view disables flight, arming flight from the top view returns the camera to perspective, and F toggles cleanly off.
- Rolling autosave: `autosave_now` refuses a clean document, writes `<map>-autosave-1.bzmag` next to the source on the first change, shifts the previous snapshot to slot 2 on the next write (verified by reopening both slots and comparing their edit counts), and keeps exactly three files — the fourth write removes the oldest and no slot 4 appears. An autosave never clears the unsaved marker, and the timer walks only while no brush, water stroke or drag is active.
- Live symmetric brush: Mirror X repeats a raise dab at the reflected sample (100 → 923 on a 1,024-sample axis); both halves rise and one undo restores both exactly. The headroom between the two deltas stays within one native 0.1 m height granularity step, which the suite asserts explicitly. Turning the toggle off stops mirroring immediately.
- The suite's full headless run again prints `FAILURES: 0`.

## Water edit engine acceptance (2026-11-21 09:46 playtest)

A Brave export with only water edits — layer 0 elevation 135 m → 150.5 m, block 2080 added and source block 1419 erased, WAT still exactly 6,512 bytes — ran through the normal Playtest pipeline (`Start-Playtest`, 1196→185 `bzn_compat` conversion reporting 76 objects and schema 185). The game log records `[Main] Entering run code [MISSION]` and `[Mission] Entering run code [RUN]` with **zero** `SAVEGAME CORRUPT` lines, and the session ended with `System shutdown normally`. Water coverage and elevation edits therefore carry the same in-engine MISSION / RUN acceptance as terrain, path and object transform exports. Unlike BZN object-count edits, the WAT patch changes no BZN structure, so the public 185 loader limitation documented above does not apply.

## VRV sound point inspection

VRV serializes sound points as ordinary BZN objects of `vrv_sndpoint` whose label carries `vrvsnd:<sound>:<volume>:<range>:<interval>:<jitter>:<pitch>:<near>` (VRV `src/shared/SoundPoints.h`; sliders 0-100/10-2000/0-600/0-100/25-200/0-90, safe file names of 1-48 letters/digits/_-. with a playable extension). BZ_MAP_MAG now parses those labels: the suite's `test_sound_point_labels` checks the seven settings round out of a well-formed label, rejects spaces, `.mp3`, six-field labels, non-integer settings, ordinary object labels and empty labels, and verifies the move-object status renders the sound and its range while ordinary labels keep their plain rendering. Sound placement and playback stay VRV-managed as documented. Full suite again prints `FAILURES: 0`.

## BZN layout registry and Playtest adapter isolation (T-10, 2026-11-21)

The BZN save layout is now a registry, not a version-number comparison. `app/formats/bzn_layouts.gd` records the four verified layouts (binary-1192, binary-1196, binary-1197, text-1200) with header fingerprint, framing, boundary discovery rules, invariants, per-capability statuses (READ, INSPECT_PATHS, EDIT_PATH_POINTS, EDIT_PATH_STRUCTURE, INSPECT_OBJECTS, EDIT_OBJECT_TRANSFORM, EDIT_OBJECT_COUNT, ENGINE_PLAYTEST, CONVERT_TO_185), tested engines, adapter compatibility, fixtures and evidence pointers:

- The path codec and object codec consult the registry instead of private version lists, and `map_package.open` refuses any BZN whose layout is unrecognized or lacks path-inspection capability (a text-1200 package with full companions is now refused with the registry reason instead of silently opening with an empty path table).
- The 2.0.185 launch routes are fixed in one place: 1192 launches natively, 1196 converts through the verified VRV `bzn_compat` adapter, everything else (1197, 1200, unknown versions) is refused before any asset stage runs. A raw VRV-less 1196 launch and the `-KeepBznLayout` bypass are both hard refusals now; the converted output re-inspects with schema `185` before the game starts.
- Read-only fixture copies of the VSR 1197 maps and the text 1200 Bolt save live under `map_references/vsr_1197/` and `map_references/stbolt_1200_text/` (byte-identical to the VSR workshop originals; the originals are untouched).
- Object count edits (duplicate/remove) now carry an explicit EDITOR_ONLY warning in the editor status lines, export and playtest reports, citing the verified 185 `SAVEGAME CORRUPT` limitation, while transform-only operations keep their engine-verified status.

Verification on this revision:

- `res://tests/bzn_layout_profiles.gd` (run headless through `tools/Test-BznLayouts.ps1`) prints `FAILURES: 0`: positive recognition of all five fixtures, refusal of malformed/truncated/blank samples, a renumbered Brave header classified by header shape but still refused for objects by capability, an unregistered 1199 header refused outright, every recorded capability status asserted (including 1192 EDIT_OBJECT_COUNT EDITOR_ONLY and 1197 object UNSUPPORTED), playtest routes pinned (1192 native, 1196 convert, 1197/1200/unknown refuse), codec gates cross-checked against the independent BZNTools counts (Brave 23 paths / 76 objects), package-level refusal of the text-1200 and spoofed-1199 packages, the verified 1197 package still opening for path editing, and all fixtures byte-identical after the run. Suite log: `V:/_TEMP_/bzmag-layout-<guid>/godot.log` (kept in the newest run dir).
- The full suite (`tools/Test-Terrain.ps1`) now chains the layout test: terrain workflow `FAILURES: 0` followed by layout `FAILURES: 0` (headless run log `V:/_TEMP_/bzmag-terrain-e4ba552bffb6418f91d9a2f3d6354e51/godot.log`).
- `Start-Playtest.ps1 -ValidateOnly` classification probes against the installed 2.0.185 game: `LaunchRoute: native / BznVersion: 1192` for the blank package; `LaunchRoute: convert / BznVersion: 1196` for Brave with VRV; hard refusals for the 1197 Terrace package ("no verified 2.0.185 launch route"), Brave without VRV ("needs the verified VRV conversion adapter"), and Brave with `-KeepBznLayout` ("requires a confirmed native 2.0.185 layout (version 1192)").

## Transactional autosave store (P0, 2026-11-21)

Autosaves no longer write beside the source map. `app/core/autosave_store.gd` publishes immutable `slot-<sequence>-<UTC>-<nonce>.bzmag` files under `<configurable root>/<map-stem>-<16-hex digest of the normalized source path>/` (default root `user://autosaves`, per-user configurable in Setup, so same-named maps in different folders never collide). A publish is: write staged record → full `Document.open` verification against the unchanged sources → atomic rename to its own unique slot name → prune older slots beyond the keep count. The old delete-then-shift rotation — which could destroy the last good copy before writing the new one — is gone; there is no multi-rename window at all.

Editor integration: `autosave_now` routes through the store, the status names the published slot explicitly ("the source map folder is never touched"), a **Recover…** dialog lists a project's slots (oldest first, only files matching the verified naming rule), and the Setup dialog carries the autosave root field persisted in `user://editor.cfg`.

Acceptance (headless, `tools/Test-AutosaveStore.ps1`, chained into the suite, `FAILURES: 0`):

- Failure injection at every real checkpoint of the protocol — write failure, corrupted staged record (caught by the genuine project re-open), verification failure, atomic publish failure, crash before publication, prune failure — each refuses the publish with a reason and leaves the newest confirmed good copy intact and re-openable with every edit.
- An injected crash leaves one abandoned `stage-` file; the next publish sweeps stale stages and interrupted `.bzmag-` staging folders and succeeds.
- A blocked/unusable autosave root reports "Could not create the autosave folder" without touching any slot.
- A mutated source (TRN revision change on a scratch package copy) refuses the autosave with "Source changed or disappeared"; restoring the revision resumes autosaves.
- Read-only source files (Windows `attrib +r`) do not block autosaving, because the store never writes the map folder.
- Two same-stem packages in different directories publish and recover through separate project identities.
- Old-style `<map>-autosave-N.bzmag`, and a misnamed `slot-0000000000-not-a-real-slot.bzmag` in the project folder, are ignored by the store and stay byte-identical.
- A fresh store instance after a simulated restart finds and re-opens the newest slot with the exact current edit count; the manifest (schema 2) records source path, revision digest and saved time.
- Every package member of the scratch copy is byte-identical to the recorded start snapshot after the whole matrix.

The suite's workflow test now asserts the same properties through the editor path: clean documents do not autosave, the map source folder carries no autosave files, the newest slot reopens with every edit, three slots survive rolling keeps, and the unsaved marker stays. Full suite chain prints three `FAILURES: 0` blocks (workflow, BZN layout, autosave), with the two documented engine error lines (`Parse JSON failed` for the injected corrupt record, `Could not create directory` for the injected blocked root) expected inside the autosave stage.

## Cleanup semantics, process ownership and evidence retention (P0, 2026-11-21)

Three hygiene fixes, each verified live on this machine:

- **`-Keep N` contract fixed.** `tools/Clean-Build.ps1` previously deleted *all* folders of the `BZMAG`, `bzn-185` and `sdk` groups even with `-Keep N`, contradicting its documented semantics through a hidden branch. The contract is now uniform and tested against three synthetic `asset-test-<guid>` folders with distinct mtimes: dry-run `-Keep 2` listed only the oldest, `-Apply` removed exactly that one and left the two newest, `-Keep 0 -Apply` removed the rest, a repeated `-Apply` was a no-op, and `build/object-preview/` plus `build/terrain_oracle.exe` stayed untouched. The 0..5 range remains an explicit documented cap.

- **Ownership-aware process stopping.** `tools/Stop-OwnedProcesses.ps1` replaces the old "stop stray battlezone2 / headless Godot by name" rule. Ownership is proven by location: the executable runs from inside the repository, or a known tooling process (`powershell/pwsh/cmd/python/py/dotnet/msbuild/cl/bash/sh/Godot*/battlezone2`) carries a repository path in its command line (either slash form, with or without a trailing separator). The tool excludes its own ancestry, lists PID + name + creation time + evidence as a dry run, and re-verifies each PID immediately before stopping (PID-reuse safety). Verified with two live probe workers whose command lines referenced the repo: dry run listed both and stopped nothing; `-Apply` stopped exactly the two with full reporting; unrelated user sessions (Steam Battlezone, other Godot projects, editors) can never match.

- **Ownership-verified temp evidence pruning.** `tools/Clean-TempEvidence.ps1` replaces the wildcard deletions under `V:/_TEMP_/`. It considers only `bzmag-terrain-<guid>`, `bzmag-layout-<guid>`, `bzmag-autosave-<guid>` suite groups (classified PASS/FAIL from their `FAILURES: <n>` log lines) plus one-off probes that prove ownership by convention (`water-…`, `bzm-<guid>`, `native-route-probe`, `bzn-conv-probe`) or by an internal workspace marker (fixture names, `res://tests/`, `BZ_MAP_MAG` text). Per group the newest PASS, the newest FAIL, `-Keep N` extra newest runs and fresh (<24 h) UNKNOWN runs are always retained; live-referenced folders are skipped; dry-run is the default. Verified live: the first dry run exposed that the transient `*-limit-probe` folders in `V:/_TEMP_/` belong to **other** workspaces (audapack, fastprompter, limisaw) — they are reported as `KEEP unverified ownership` and were never removed. `-Apply` then removed exactly six older suite runs (659 MiB), kept every retention-protected folder, and a repeated `-Apply` was a no-op.

`AGENTS.md` now documents the uniform keep contract, the new tools, and the "never kill by name, never touch anything outside the repository" rule.

## Advanced Slope Studio acceptance (T-11 vertical slice, 2026-11-21)

The sculptor builds on the existing MapDocument/terrain command pipeline — no second terrain document. `app/core/slope_shapes.gd` evaluates deterministic heightfield shapes in world metres on the native 2 m grid: exact-angle ramps compute `h = start_height + horizontal_distance * tan(angle)`, and the profile presets cover flat, rounded, soft, terrace (quantized levels), cliff edge, plateau, berm, ridge, valley, trench and excavation, each with a core/falloff lateral blend into the existing surface (smooth cosine crest for berm/valley, flat core plus smoothstep walls for the rest and for ramps). Height-range and existing-slope masks restrict which samples may move; batch arrangement spreads linear rows, radial fans and mirror X/Z copies with a configurable symmetry origin, all evaluated against the pre-batch heights so overlap resolution is deterministic. The Slope Studio dialog (next to Shape Terrain) previews through the shared dirty-region pipeline and commits as exactly one undo step.

Suite-driven acceptance on the real Brave map (`res://tests/terrain_workflow.gd` `test_slope_studio`, triple-`FAILURES: 0` run, log /v/_TEMP_/bzmag-terrain-bbb2696fbc17436b9d2a90f9fb306050/godot.log): the studio opens at the terrain cursor in world metres and reads the current height; the 15-degree 32 m wide ramp over a 200 m span previews and the end sample measures 100 m + 200 m × tan 15° ≈ 153.6 m within one height granularity step (float32 storage and grid discretization accounted); the profile is linear at mid-span; widening the falloff places the lateral edge exactly halfway between the original surface and the ramp; the terrace profile quantizes to the expected level; apply commits exactly one new undo entry; undo restores the byte-exact pre-ramp heights and redo re-applies them exactly; a linear batch of two with mirror X adds a near-complete copy of the shapes (only the falloff tails overlap); a height mask excluding every sample refuses the shape with an explanation; the project round-trips through BZMAG with identical heights; the native export re-imports, and a fresh `--heights-only` mode of the independent VRV oracle (`tools/terrain_oracle.cpp`, recompiled this session) confirms that only the counted height samples changed with every non-height layer byte-identical. Unapplied previews still block export, and cancelling a preview never touches the committed document.
