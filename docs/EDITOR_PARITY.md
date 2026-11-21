# Editor parity baseline

Original reflects the supplied CFG and `EditorReadMe.txt`. VRV reflects local implementation files where available. Control names describe the reference and do not establish identical behavior on 2.0.185.

| Area | Reference | BZ_MAP_MAG |
|---|---|---|
| Height | Original `bzeditor_height.cfg`, VRV `vrv_editor_keys.cfg` | IMPLEMENTED Raise, Lower, Blend, Paint, Spray and Pick. Four brush shapes, six widths and four pressures with buttons and VRV shortcuts. Brush response and fill parity remain open. |
| Navigation | Original camera and schematic views, VRV overhead reference screenshots | IMPLEMENTED 3D-first resizable workspace with height controls and 2D map, solid/wireframe, overhead/orbit, pan, zoom, focus and synchronized cursors. Dedicated fly mode pending. |
| Terrain colors/textures | Original color and tile tools, VRV selectable mirrored layers | IMPLEMENTED native RGB and tile slot painting with undo, saved project state and TER export. Alpha and draw masks pass through. Texture repeat is approximate. |
| Water/Sky/Fog | `bzeditor_water.cfg`, environment CFG, VRV separate lighting/fog page | IMPLEMENTED experimental multi-layer water plane and coverage for matching WAT v5 maps. Water editing and sky/fog tools remain pending. |
| Save/Undo | Engine save, VRV `EditorSaveHost.cpp` and `EditorTerrain.h` rolling terrain autosaves | IMPLEMENTED fixed source revisions, brush and bake undo/redo, project snapshots and transactional native export. Autosave and merge pending. |
| Mirror | `EditorTerrain.h`, `TerrainShape.h`, `EditorBrush.h`, `ObjectSymmetry.h` | IMPLEMENTED directional X/Z heightfield mirroring with exact source samples and undo. VRV-style live symmetric brush, paths and objects remain separate. |
| Shape | VRV smooth/rough/relief with grain, softness, contrast, preserve symmetry | IMPLEMENTED cursor-anchored slope planes with world grades, preview and undo, plus regional Smooth and noise layers. |
| Paths | Original path CFG, VRV `EditorPathHost.cpp` and `EditorPath.h` | IMPLEMENTED rename and type changes, drag/edit/append/remove/reorder points, and whole-path creation/removal for verified binary tables. The operations share undo and BZN export. Dynamic mission rules require a map-specific playtest. |
| Objects and mission | Original object CFG, VRV object/preset generators | IMPLEMENTED native BZN position and orientation editing and static model preview. Both views support selection, drag, grid snapping and cancel. `[` / `]` rotate ±15° (Shift 1°), Ctrl+D duplicates the selected record into the stream with a fresh sequence and label, Delete removes it. All share undo, BZMAG save and re-import-verified native export. Insertion of classes not yet present in the map and mission tools remain pending. |
| Sounds | VRV `SoundPoints.h`, `SoundPointsHost.cpp`, `vrv_sndpoint.odf` | VRV serializes a hidden ObjectSpawn whose label holds volume/range/interval/jitter/pitch/near. Playback is VRV-managed. BZMAP sound inspection/loading and placement pending. |
| Layers and nodes | BZMAP extension | IMPLEMENTED up to eight ordered layers, enable/opacity, typed height/delta/RGB/tile ports, channel previews, one undoable bake and a project round-trip. |
| UI theme | Wintage Golden Default and 21 tokens | IMPLEMENTED Windows Verdana and golden bevels. Theme selection, wider layout presets and shortcut remapping pending. |
