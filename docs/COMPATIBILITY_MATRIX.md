# Compatibility matrix

**NATIVE** means checked through public BZCC. **BAKED** means an editor operation is materialized into a supported native format. **EDITOR_ONLY** means BZMAG state only. **EXPERIMENTAL** means evidence is incomplete. **UNSUPPORTED** means unavailable in the indicated profile.

| Surface | Profile and status | Evidence or boundary |
|---|---|---|
| BZN 1192 binary map | NATIVE for the completed blank snapshot, script behavior EXPERIMENTAL | Original BZN and 23 paths were kept. After adding a matching flat TER to a copy, 2.0.185 reached MISSION / RUN with the mission script disabled. VRV's layout converter rejects version 1192. |
| BZN 1196 late binary layout | UNSUPPORTED on unconverted public 2.0.185 | VRV found an extra Craft field in Brave. Header number is insufficient. The editor's normal export preserves the original BZN bytes. |
| BZN 1196 public layout | NATIVE for adapted Brave on 2.0.185 | VRV converted one Craft record in a private snapshot. The game entered MISSION / RUN with original script selection enabled. |
| BZN 1197 binary map | BAKED existing path edits, engine compatibility EXPERIMENTAL | Two VSR fixtures match the independent BZNTools path counts. A Terrace 2 export reimports with the changed label and all other BZN bytes intact. |
| BZN 1200 | EXPERIMENTAL in BZMAP | The available Bolt sample uses text. Its paths remain opaque to the binary editor. |
| TER v5 heights | NATIVE on the verified 2.0.185 case | Signed bounds, float heights, 2 m samples. Modified Brave loaded in-game. Independent decoder confirmed affected samples. |
| Brush and graph terrain | BAKED | Raise/lower, flatten, smoothing and procedural output change TER heights. BZCC loaded both a brush export and a graph-baked export. |
| TER RGB, alphas, flags, tiles | BAKED RGB and tile IDs, NATIVE preservation of other channels | Color and tile edits reimport through the native codec. Tests compare the pre-paint bytes of every unaffected lane. Preview uses all 16 textures on Brave. |
| TRN / INF / DES | NATIVE passthrough for verified package | TRN and INF text read into metadata. Verbatim export. DES remains opaque. |
| WAT / SKY / DDS | NATIVE passthrough; WAT layer preview EXPERIMENTAL | Snapshot carries exact bytes. The game reports loading the original SKY. The editor decodes active WAT mask bits and elevations on verified-shaped v5 files, and decodes DDS for supported material formats. |
| Map objects, scrap and pools | NATIVE placement read and preservation, EDITOR_ONLY static preview | Brave resolves 76 actual meshes including eight pools. Object writes, animated poses and complete asset loading parity remain open. |
| Named AI paths | NATIVE point edits on verified 2.0.185 profile, BAKED whole-path edits in verified tables | The game loaded Brave with an inserted patrol point and loop type. Whole-path creation and removal reimport with stable existing IDs and unchanged surrounding bytes. BZMAP checks known BZN references and local mission text files. Dynamic mission code requires a playtest. |
| Photoshop-style layers / graph | EDITOR_ONLY authoring, BAKED height, RGB and base tile ID outputs | Layer parameters, typed links and order in BZMAG. Preview is temporary. One bake applies all connected outputs to TER. |
| Volumetric cuts, caves and true terrain overhangs | UNSUPPORTED by TER heightfield | Supported terrain has one sample height per X/Z. Prop workflows need separate proof. |
| Newer BZCC executables | EXPERIMENTAL | No newer executable was run in this cycle. |

See the [engine run and hashes](EVIDENCE.md).
