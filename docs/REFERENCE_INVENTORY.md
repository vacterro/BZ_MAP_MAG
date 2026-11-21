# Reference inventory

All seven configured Windows reference roots were available on 2026-11-21.

| Root or input | Evidence used |
|---|---|
| `V:/__STORE_V/_SOFT/Steam/steamapps/common/BZ2R` | Public 2.0.185 executable and stock resources. Executable SHA-256 `2319fb1cbb3a1d35e8d3ffddb501f8b9518db1c9ebab893d34d7024d8535f426`. |
| `V:/___VAC/__K/__CODE/_MISC/_BZDECOMP/vrv` | Source at e4ed71d. `TerrainFile.h`, `TerrainShape.h`, `EditorTerrain.h`, `EditorBrush.h`, `EditorPath.h`, `EditorPathHost.cpp`, `EditorSaveHost.cpp`, `SoundPoints.h`, `MapCreator.h`, and `tools/bzn_compat.py`. |
| VRV `BATTLEZONE/DOCS` | Local `CMDLINE.md`, `ADVANCED_MAP_MAKING.md`. `/config`, standalone mission argument, `/startedit`, `/noscript`. |
| `V:/__STORE_V/_SOFT/Steam/steamapps/workshop/content/624970` | 97 item directories on this machine. Workshop BZTC Total Coop fixture inspected read-only for 4096 m benchmark. |
| `V:/___VAC/_BATTLEZONE` and `__ARCHIVE/BZFORUM_SITE_CLONE` | Available working archive and offline forum mirror. |
| Mirror's `BZ2_ENGINE_KNOWLEDGE` | Inventoried modules including BZMapTools, BZNTools, Lua API and stock AI plans. |
| `V:/___VAC/__K/__CODE/_TAMPERMONKEY/_WIN95THEME/Wintage` | `themes/goldendefault.json`, the shipped source of the 21 palette tokens. Local SAIPEN `UI.md` defines Verdana, non-AA and bevel rules. |
| Workspace `BZNTools/` | HEAD 7ee7de243a89115248294093931ac2b0186608d3, remote `https://github.com/vacterro/BZNTools`, MIT. Clean index and worktree here despite the archive observation. Checked-out files show LF in index and CRLF in working copy with `core.autocrlf=true`. Built a copy under ignored `build/`. |
| Workspace `map_references/` | Brave complete terrain fixture and blank missing-TER fixture. |
| Workspace `editor_orig/`, `Editor_vrv/`, `mapping1.txt`, `screenshots/` | Editor configuration, paths and visual parity inputs. The 26 supplied screenshots include the overhead relief, terrain tools and path guide. |
| Workspace `_TerrainEditor/`, `_TerrainEditor2/` | Compiled references kept as-is. No execution. |

The outer workspace currently has no Git metadata. The local graph CLI was discoverable, but its coordinated `list_projects` call refused the inherited Windows DACL on `C:/Users` and the stdio fallback did not initialize. Source files and executable/reference runs supplied evidence for the claims here.

[In-game editor discussion](https://steamcommunity.com/app/624970/discussions/0/1694914735997179510/) · [Battlezone Scrap Field research](https://github.com/BattlezoneScrapField) · [Modding guides](https://battlezone.fandom.com/wiki/ModdingGuides).
