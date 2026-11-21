# BZ_MAP_MAG

Windows x64 terrain editor for Battlezone Combat Commander. The first working slice opens a native map package, renders its TER in 2D and 3D, edits the same heightfield in either view, and exports a validated native snapshot. The compatibility baseline is public BZCC 2.0.185.

## Run

Open `BZ_MAP_MAG.exe` from a desktop build, or run the project with Godot 4.7.2. Supply an absolute BZN path or use **Open**.

```powershell
$godot = 'V:/__STORE_V/_SOFT/Godot/4.7.2-stable/Godot_v4.7.2-stable_win64.exe'
$map = (Resolve-Path 'map_references/Brave Lil Toaster/braveliltoaster.bzn').Path
& $godot --path app -- $map
```

- Paint with left drag in either view. The **Terrain Brush** dock has preset buttons for width, shape and pressure. **Pick** samples a paint height straight from the terrain. Click **Hotkeys** or press F1 for the VRV-style shortcuts. **Solid**, **Wire**, **Top** and **Orbit** control the main 3D view.
- The **Terrain Brush** also paints native vertex **Color** from a `#RRGGBB` value and **Tile** IDs from the TRN's slots 0–15. Tile lane 0 is the base. Lanes 1–3 retain their current coverage and alpha. Both paint modes support undo and native export.
- **Shape Terrain** previews a slope plane around the last terrain cursor. Set the anchor height and grades along X and Z, then apply the plane. The same dialog can mirror one half of the heightfield across either axis. Each applied shape is one undoable edit.
- Pick a named path to display it in both views. **New Path** starts at the last terrain cursor. Use **Move Points** to drag, Shift+click to append, or Delete to remove the selected point. **Edit Path** changes the label, type and point order and offers **Remove Path** for supported binary tables. Creation and removal use the same undo history as point edits. The editor checks known mission references before removing a source path.
- **Objects**, **Texture**, **Color** and **Water** display the installed game's meshes, terrain materials, vertex colors and decoded water layers. Object and texture preview use the local VRV mesh adapter. Rings in the 2D map mark scrap pools.
- **Move Object** selects placements in either view. Drag to move at the object's existing height above the terrain, hold Shift to snap to the 2 m grid, or press Esc to cancel. `[` and `]` rotate ±15° with Shift for 1°, Ctrl+D duplicates the selection with a fresh native sequence and label, and Delete removes it. The status shows ODF, team, position and heading. Save the placements in BZMAG or export their native BZN.
- **Edit Water** opens the water toolbox for maps with a WAT: pick one of the eight native layers, set its elevation within ±100000 m with **Apply Elevation**, and paint or erase coverage with left drag while the dialog is open (Shift erases) using a meter-based brush radius. Every stroke and elevation change is one undo step, saves into BZMAG and exports the WAT in place with re-import verification.
- Under **Layers / Nodes**, add and reorder up to eight procedural layers and set their opacity. Wire **Slope** through **Slope Mask** into **Blend Color** with **Existing Color** and a **Color Ramp**. Wire **Height** through **Threshold** and the **Mask** port of **Tile Select** to choose between two base tile IDs. **Preview** evaluates around the last cursor or map center. Its channel selector shows the selected output in both views. **Bake to Terrain** commits all outputs as one undoable edit. **Keep Layers** saves the graph settings for **Save Project**.
- **Save Project** writes a new `.bzmag` snapshot that references the source files and their SHA-256 revisions. Keep those source files available. Ctrl+O, Ctrl+S, Ctrl+Z and Ctrl+Y cover open, save, undo and redo.
- On Windows, **New Map** takes a blank BZN without a TER, a flat v5 TER template that matches the TRN size, origin and height, and a destination parent folder. It opens a new copy after validation. To check a blank map in BZCC, use **Setup** to start Playtest in the engine editor without mission scripts.
- **Export Native** writes a fresh folder, validates the saved files by re-opening them, and keeps the map's original filename. **Playtest** or **F5** launches the current edits with a temporary snapshot. The editor finds the game in Steam libraries. **Setup** has native folder pickers for the game and optional VRV checkout. Keep Steam running. A normal game exit removes the temporary runtime and returns control to the editor.
- **Setup** can link a JSON asset profile to the current project, for example `{"folders":["map-assets","D:/MyMod/Data"]}`. Relative entries start at the profile file. Playtest checks the mission DLL and the same-stem Lua script for Lua missions before launching. The linked folders follow the map snapshot in search order.

## Verify and build

```powershell
./tools/Test-Terrain.ps1 -Godot $godot
./tools/Test-Terrain.ps1 -Godot $godot -WithGpu
./tools/Build-ObjectPreview.ps1 -VrvSource 'path/to/vrv'
./tools/Test-ObjectPreview.ps1 -Godot $godot -Game 'path/to/BZ2R' -WithGpu
./tools/Build-Desktop.ps1 -Godot $godot -WindowsReleaseTemplate 'path/to/windows_release_x86_64.exe'
./tools/Clean-Build.ps1 -Apply
```

Use the release template matching your Godot version. Keep the executable, pack and adjacent tools folder together. The portable build includes the local native preview adapter when it has been compiled. Game meshes and textures stay in the installed game or mod directories. Cleanup keeps the newest generated desktop and QA runs, skips in-use runtimes, and unlinks junctions before removing stale game copies.

- [Architecture and snapshot rules](docs/ARCHITECTURE.md)
- [Compatibility matrix](docs/COMPATIBILITY_MATRIX.md)
- [Formats and dependencies](docs/FORMAT_RESEARCH.md)
- [Editor parity](docs/EDITOR_PARITY.md)
- [Engine limitations](docs/ENGINE_LIMITATIONS.md)
- [Reference inventory](docs/REFERENCE_INVENTORY.md)
- [Reproduction and measurements](docs/EVIDENCE.md)
