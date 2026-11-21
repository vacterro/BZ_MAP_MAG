# Agent notes (BZ_MAP_MAG)

Vibe loads this file automatically at every session start in this project, and other
agent CLIs discover `AGENTS.md` the same way. It records the working rules that are
expensive to re-derive between sessions. Keep it short and factual.

## Workspace hygiene — every session

Generated playtest/export/QA folders pile up into gigabytes of useless by-products.
Clean them as part of finishing any session, and opportunistically during long ones:

1. Prune `build/`:
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/Clean-Build.ps1 -Apply`
   Uniform keep contract, no hidden per-group exceptions: `-Keep 0` removes **every**
   generated run folder (`BZMAG-*`, `test-*`, `desktop-*`, `asset-test-*`,
   `path-profiles-*`, `flat-*`, `ui-bridge-*`, `bzn-185-*`, `bzn-probe-*`, `sdk-*`);
   `-Keep N` (0–5) keeps the newest N of each group and removes older ones. Without
   `-Apply` it is a dry run. The tool skips in-use runtimes and unlinks junctions
   before recursing. It never touches `build/object-preview/` or
   `build/terrain_oracle.exe` (compiled local tools). A repeated run is a no-op.
2. Prune suite output under `V:/_TEMP_/` with
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/Clean-TempEvidence.ps1`
   (dry run by default, `-Apply` to remove). A deletion requires a matching
   `.bzmag-run.json` and the run name plus its exact `godot.log` SHA-256 on the
   same line in `docs/EVIDENCE.md`. Keep the newest PASS and FAIL in each suite
   group plus `-Keep N` extra runs. Keep incomplete, unmarked, linked or
   live-referenced folders. Never match temp folders by broad wildcards.
3. Before finishing, stop stray processes the session started — **never by name and
   never anything outside this repository**. Use
   `powershell -NoProfile -ExecutionPolicy Bypass -File tools/Stop-OwnedProcesses.ps1`
   (dry run by default). Apply with `-Apply -RunToken <private-run-name>` for
   a specific child you started. The record must match the PID, creation time,
   executable, run token and repository path at the point of stopping. Prefer a
   normal Battlezone exit and verify `System shutdown normally` in its log.
4. Never delete: `build/object-preview/` (compiled VRV mesh adapter),
   `build/terrain_oracle.exe` (reference TER decoder), `tools/`, `map_references/`,
   the installed game, or the VRV checkout. A `desktop-<hash>` export is reproducible
   via `Build-Desktop.ps1` and may be pruned. Suite evidence under `V:/_TEMP_/` is
   pruned only through `Clean-TempEvidence.ps1`, and only after its content is
   recorded in `docs/EVIDENCE.md`.

## Commands and fixed paths

- Godot executable: `V:/__STORE_V/_SOFT/Godot/4.7.2-stable/Godot_v4.7.2-stable_win64.exe`
- Test suite (~3–6 min, success ends in three chained `FAILURES: 0` blocks:
  terrain workflow, BZN layout profiles, autosave failure injection):
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools/Test-Terrain.ps1 -Godot '<godot>'`
  The workflow log goes to `V:/_TEMP_/bzmag-terrain-<guid>/godot.log`, the chained
  stages to `bzmag-layout-<guid>/` and `bzmag-autosave-<guid>/`. A stuck headless run
  can be killed with `tools/Stop-OwnedProcesses.ps1 -Apply -RunToken <private-run-name>`; parse errors abort
  before any checks.
- Playtest (Steam must be running; **never pass `-KeepBznLayout`** — it is now a
  hard refusal for anything but the verified native 1192 layout; the launcher
  only runs 1192 natively or 1196 through the verified `bzn_compat` conversion
  and aborts every other version with an explanation instead of launching):
  `powershell -File tools/Start-Playtest.ps1 -Godot <godot> -Game <BZ2R> -VrvSource <vrv> -Mission <bzn>`
  `-ValidateOnly` prints the classified launch route without launching.
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
