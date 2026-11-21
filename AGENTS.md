# Agent notes (BZ_MAP_MAG)

Vibe loads this file automatically at every session start in this project, and other
agent CLIs discover `AGENTS.md` the same way. It records the working rules that are
expensive to re-derive between sessions. Keep it short and factual.

## Workspace hygiene — every session

Generated playtest/export/QA folders pile up into gigabytes of useless by-products.
Clean them as part of finishing any session, and opportunistically during long ones:

1. Prune `build/`:
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/Clean-Build.ps1 -Apply`
   The default `-Keep 0` removes **every** generated run folder (`BZMAG-*`, `test-*`,
   `desktop-*`, `asset-test-*`, `path-profiles-*`, `flat-*`, `ui-bridge-*`,
   `bzn-185-*`, `bzn-probe-*`, `sdk-*`); `-Keep N` keeps the newest N per group.
   The same command without `-Apply` is a dry run. The tool skips in-use runtimes and
   unlinks junctions before recursing. It never touches `build/object-preview/` or
   `build/terrain_oracle.exe` (compiled local tools).
2. Prune suite output under `V:/_TEMP_/`: keep only the newest `bzmag-terrain-<guid>/`
   (its `godot.log` is the latest suite evidence) and delete older ones plus one-off
   probe/scratch dirs (`water-*`, `*-probe*`, ad-hoc export dirs) once the evidence
   they hold is recorded in `docs/EVIDENCE.md`.
3. Before finishing, stop stray processes the session started: `battlezone2` (game)
   and headless `Godot_v4.7.2-stable_win64` runs. A killed game produces a
   `Battlezone-Crashed *.log` — a normal exit (`System shutdown normally`) is the
   clean pattern.
4. Never delete: `build/object-preview/` (compiled VRV mesh adapter),
   `build/terrain_oracle.exe` (reference TER decoder), `tools/`, `map_references/`,
   the installed game, or the VRV checkout. A `desktop-<hash>` export is reproducible
   via `Build-Desktop.ps1` and may be pruned.

## Commands and fixed paths

- Godot executable: `V:/__STORE_V/_SOFT/Godot/4.7.2-stable/Godot_v4.7.2-stable_win64.exe`
- Test suite (~2–6 min, success prints `FAILURES: 0`):
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools/Test-Terrain.ps1 -Godot '<godot>'`
  Output goes to `V:/_TEMP_/bzmag-terrain-<guid>/godot.log`. A stuck headless run can
  be killed with `Stop-Process`; parse errors abort before any checks.
- Playtest (Steam must be running; **never pass `-KeepBznLayout`** — it skips the
  required 1196→185 `bzn_compat` conversion and produces the false failure
  `SAVEGAME CORRUPT AT OFFSET 411`):
  `powershell -File tools/Start-Playtest.ps1 -Game <BZ2R> -VrvSource <vrv> -Mission <bzn>`
  Success = `[Main] Entering run code [MISSION]` + `[Mission] Entering run code [RUN]`
  and zero `SAVEGAME CORRUPT` lines in the newest log under
  `C:\Users\vac34\Documents\My Games\Battlezone Combat Commissioner\` (session-profile
  subfolders may hold their own logs).
- Game install: `V:/__STORE_V/_SOFT/Steam/steamapps/common/BZ2R`.
- VRV reference source: `V:/___VAC/__K/__CODE/_MISC/_BZDECOMP/vrv`.
- Python probes: use `py -3.11` (plain `python` heredocs can hang in this shell).

## Working rules

- Evidence first: a feature is done only with a suite check (`FAILURES: 0`), a
  byte-level comparison, or an in-game playtest log. Record each proof in
  `docs/EVIDENCE.md` as it is obtained; never promise an untested behavior.
- Unfulfilled reference features stay documented in `docs/EDITOR_PARITY.md` with the
  concrete blocker (and in `docs/ENGINE_LIMITATIONS.md`), not silently dropped.
- Commit in increments (feat and docs separately) with the Mistral Vibe trailer.
- GDScript 4.7 gotchas: typed-inference failures on untyped accessors are parse
  errors — type the variable; `FileAccess.get_file_as_text` does not exist (use
  `get_file_as_string`); SpinBox assigns snap to `step`; heights snap to
  `package.granularity` (0.1 m).
