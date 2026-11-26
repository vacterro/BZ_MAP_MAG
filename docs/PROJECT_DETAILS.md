# BZ_MAP_MAG — Technical guide

[Back to project overview](../README.md)

Commands and repository paths below are relative to the repository root unless stated otherwise. Detailed evidence is retained from the previous README; dated results are historical, not a fresh test run.

---

# BZ_MAP_MAG

**v0.0.1**

Windows x64 terrain editor for Battlezone Combat Commander. The first working slice opens a native map package, renders its TER in 2D and 3D, edits the same heightfield in either view, and exports a validated native snapshot. The compatibility baseline is public BZCC 2.0.185.

## Run

Double-click `BZ_MAP_MAG.exe` or `BZ_MAP_MAG.cmd` in the repository root (drag-and-drop a `.bzn`/`.bzmag` onto `BZ_MAP_MAG.cmd`, pass `--dev` to launch directly from `app/` via Godot 4.7.2, or rebuild the root binary with `./tools/Build-Desktop.ps1 -Godot $godot -ToRoot`). You can also run the project directly with Godot 4.7.2:

```powershell
$godot = 'V:/__STORE_V/_SOFT/Godot/4.7.2-stable/Godot_v4.7.2-stable_win64.exe'
$map = (Resolve-Path 'map_references/Brave Lil Toaster/braveliltoaster.bzn').Path
& $godot --path app -- $map
```

- **Unified docked DCC workspace (`app/ui/`, `app/editor.gd`)**: Cinema 4D / Photoshop-style 5-region shell with a single-row MenuBar + frequent actions + **Workspace Presets** (`Default`, `Sculpting`, `Mission`, `Object Placement`, `Nodes`, `Fullscreen Viewport`) + live `Find tool…` launcher; a **Left Dock** (`Scene` | `Layers` | `Assets` | `Tools`); a **Center Workspace** (`3D+2D` | `3D` | `2D` | `Nodes` | `New Map` | `Settings`); a **Right Attributes Inspector** with **Pin** lock and collapsible sections; and a compact **Status Bar** with collapsible **Log** drawer. All 11 editing tools (`Terrain Brush`, `Slope Studio`, `Shape Terrain`, `Water`, `Environment`, `Sound Point`, `Path Inspector`, `Mission & Path`, `Object Browser`, `Node Studio`, `New Map`, `Target Profile`, `Setup`) run inside the docked shell with zero modal editing popups obstructing the 3D/2D viewport. Layout splits, tab state, and presets persist in `user://editor.cfg` (`[workspace]`) with viewport clamping and **View → Reset Layout**.
- Paint with left drag in either view. The **Terrain Brush** inspector (Right Dock) has preset buttons for width, shape and pressure. **Pick** samples a paint height straight from the terrain. Click **Hotkeys** or press F1 for the VRV-style shortcuts. **Solid**, **Wire**, **Top** and **Orbit** control the main 3D view. **Fly** or F toggles the free-flight camera: W/S flies forward and back, A/D strafes, Q/E rises and sinks, right drag looks around.
- The **Terrain Brush** also paints native vertex **Color** from a `#RRGGBB` value and **Tile** IDs from the TRN's slots 0–15. Tile lane 0 is the base. Lanes 1–3 retain their current coverage and alpha. Both paint modes support undo and native export. **Mirror X** and **Mirror Z** land every dab on the opposite half in the same stroke and undo step.
- **Slope Studio** and **Shape Terrain** dock into the Right Attributes Inspector while keeping the 3D/2D viewport unobstructed: preview exact-angle ramps, profiles, height/slope masks, batch fans/mirrors, slope planes, VRV Smooth/Rough/Relief, or half-map mirrors around the terrain cursor, then apply as one undoable edit.
- Pick a named path in the **Scene** tree or viewport to inspect it in the Right Attributes Inspector. **New Path** starts at the last terrain cursor. Use **Move Points** to drag, Shift+click to append, or Delete to remove the selected point. **Edit Path** changes the label, type and point order and offers **Remove Path** for supported binary tables. Creation and removal use the same undo history as point edits. The editor checks known mission references before removing a source path.
- **Objects**, **Object Browser** (docked in the Left **Assets** tab with details in the Right Attributes Inspector for continuous placement), **Texture**, **Color**, **Water** and **Environment** display and author the active mod environment's meshes, ODFs, terrain materials, vertex colors, decoded water layers and native `.SKY` atmosphere. **Object Browser** indexes loose and `DOCP` v2 `.pak` ODFs scoped strictly to the active `ModProfile`, shows provenance, transitive dependencies and separated verification tiers (`binaryMatch`, `engineLoad`, `gameplayBehavior`), and distinguishes 13 `VERIFIED_NEW_CLASS` native builders (`pspwn_1`, `uepool01`, `npscrx`, `morock03`, `ibpgen`, `iblite`, `morock01`, `mopalm02`, `ibsbay`, `ibtcen`, `ibtrain`, `ibwseg`, `ibwstr`), `TEMPLATE_CLONE_ONLY` in-map classes, and `PREVIEW_ONLY_UNSUPPORTED` ODFs. Object and texture preview use the local VRV mesh adapter. Rings in the 2D map mark biometal pools.
- **Environment** docks the **Sky, Fog & Environment Studio** (`app/tools/environment_studio.gd`, `app/formats/sky_env.gd`) into the Right Inspector with writable `1YKS` controls on top and a collapsible read-only `.SKY`/`.TRN` inspector below: decodes binary `.SKY` chunks (`_YKS` v65536) and `.TRN` sections, gates native writes strictly to verified `sky-v1-7068` layouts (`WRITABLE_SKY1` / `RUNTIME_VERIFIED`; unknown/variant `.SKY` layouts stay `READABLE_SKY` read-only without blocking terrain editing), edits the 8 runtime-verified `1YKS` float groups (`fogColor`, `fogStart < fogEnd`, `visibilityRange`, `sunPeriod`, `sunAngle`, `sunColor`, `ambientColor`) with Houdini Value Ladder controls, Undo/Redo, BZMAG persistence, surgical byte preservation of all other chunks, and an opt-in **Approximate Editor Preview** in the 3D view.
- **Move Object** selects placements in either view or from the Left **Scene** tree (double-click to focus the camera). Drag to move at the object's existing height above the terrain, hold Shift to snap to the 2 m grid, or press Esc to cancel. `[` and `]` rotate ±15° with Shift for 1°, Ctrl+D duplicates the selection with a fresh native sequence and label, and Delete removes unreferenced placements. The Right **Object Attributes** inspector edits transform (X/Y/Z/Yaw via Value Ladder) and labels inline, and objects labeled with VRV sound points (`vrvsnd:…`) open in the docked **Sound Point** inspector. Save the placements in BZMAG or export their native BZN.
- **Edit Water** docks the water toolbox in the Right Inspector for maps with a WAT and activates explicit water-paint mode: pick one of the eight native layers, set its elevation within ±100000 m with **Apply Elevation**, and paint or erase coverage with left drag while active (Shift erases) using a meter-based brush radius. Every stroke and elevation change is one undo step, saves into BZMAG and exports the WAT in place with re-import verification.
- The **Layers** dock (Left) stays synced with `MapDocument.layers` and the full-canvas **Nodes** center workspace (`app/nodes/node_studio.gd`, with selected node properties in the Right Inspector): add, reorder, toggle, and adjust opacity for up to eight procedural layers. Wire **Slope** through **Slope Mask** into **Blend Color** with **Existing Color** and a **Color Ramp**. Wire **Height** through **Threshold** and the **Mask** port of **Tile Select** to choose between two base tile IDs. **Preview** evaluates around the last cursor or map center and shows the selected output in both views. **Bake to Terrain** commits all outputs as one undoable edit. **Keep Layers** saves the graph settings for **Save Project**.
- **Save Project** writes a new `.bzmag` snapshot that references the source files and their SHA-256 revisions. Keep those source files available. Ctrl+O, Ctrl+S, Ctrl+Z and Ctrl+Y cover open, save, undo and redo. While you edit, the editor writes a rolling three-slot transactional autosave under `user://autosaves` (configurable in the **Settings** workspace page, outside the source map folder) every three minutes without clearing the unsaved marker, and **Recover…** opens any verified slot.
- **New Map** opens as an embedded center workspace page to create Stock-first native TER v5 maps (`128–4096 m`) directly without requiring VRV/VSR templates, separating Engine, Mod (`stock`, `vsr`, `vrv`, Steam Workshop mods), Mission (`blank`, `strategy`, `instant`, `mpi`, `duel`, `lua`, `custom-dll`), and Format profiles. **Target Profile** docks in the Right Inspector to switch editing environments non-destructively and run dry-run conversion analysis (`bzmag.compatibility-result/1`) with real missing ODF, transitive dependency, and DLL SHA-256 checks.
- **Export Native** writes a fresh folder, validates the saved files by re-opening them, and keeps the map's original filename. **Playtest** or **F5** runs the unified compatibility validator (`bzmag.compatibility-result/1`) before launching the current edits. Stock Combat Commander 2.0.185 1192 maps launch natively without needing a VRV checkout (even if an optional VRV path is empty or stale), including verified 1192/1196 object-count edits (template clones, unreferenced removals, and verified native new-class placements). Verified 1196 maps require the VRV converter checkout (`tools/bzn_compat.py`) selected in **Settings**. Keep Steam running. A normal game exit removes the temporary runtime and returns control to the editor.
- **Settings** (embedded center workspace page) configures Steam/BZCC paths, optional VRV converter checkout, autosave root, theme (`goldendefault`, `vintagedark`, `vintageclassic`, `nord`), UI scale, and can link a JSON asset profile to the current project, for example `{"folders":["map-assets","D:/MyMod/Data"]}`. Relative entries start at the profile file. Playtest checks the mission DLL and the same-stem Lua script for Lua missions before launching. The linked folders follow the map snapshot in search order.

## Verify and build

```powershell
./tools/Test-Acceptance.ps1 -Level RELEASE -Godot $godot -Game 'path/to/BZ2R' -VrvSource 'path/to/vrv'
./tools/Test-Terrain.ps1 -Godot $godot
./tools/Test-Terrain.ps1 -Godot $godot -WithGpu
./tools/Build-ObjectPreview.ps1 -VrvSource 'path/to/vrv'
./tools/Test-ObjectPreview.ps1 -Godot $godot -Game 'path/to/BZ2R' -WithGpu
./tools/Build-Desktop.ps1 -Godot $godot -ToRoot -RequireClean
./tools/Build-Desktop.ps1 -Godot $godot -WindowsReleaseTemplate 'path/to/windows_release_x86_64.exe'
./tools/Clean-Build.ps1 -Apply
```

Use the release template matching your Godot version. Keep the executable, pack and adjacent tools folder together. The portable build includes the local native preview adapter when it has been compiled. Game meshes and textures stay in the installed game or mod directories. Cleanup removes every generated run folder by default — keep the newest few with `-Keep N` instead — skips in-use runtimes, unlinks junctions before removing game copies, and preserves the compiled `object-preview` adapter and `terrain_oracle.exe`. Session agents follow the standing hygiene rules in `AGENTS.md`.

- [Architecture and snapshot rules](ARCHITECTURE.md)
- [Compatibility matrix](COMPATIBILITY_MATRIX.md)
- [Formats and dependencies](FORMAT_RESEARCH.md)
- [Editor parity](EDITOR_PARITY.md)
- [Engine limitations](ENGINE_LIMITATIONS.md)
- [Reference inventory](REFERENCE_INVENTORY.md)
- [Reproduction and measurements](EVIDENCE.md)
