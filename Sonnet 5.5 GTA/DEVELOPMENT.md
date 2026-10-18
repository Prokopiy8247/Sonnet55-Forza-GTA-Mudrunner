# DEVELOPMENT — Halcyon Bay (Sonnet5.5GTA)

Original missionless GTA-style compact open-world sandbox. **Godot 4.7.2 stable** + **Blender 5.2.2 LTS driven through MCP**.
Built autonomously by Claude Sonnet 5.5 (benchmark run `run-20261016T184257-0149c506`).

## Verified environment
| item | value |
|---|---|
| Godot | 4.7.2.stable.official.ed1daf0bf — `W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` |
| Renderer | Forward+ (RenderingDevice), driver `d3d12` on Windows, Jolt Physics (`3d/physics_engine`) |
| GPU / CPU | NVIDIA GeForce RTX 5070, AMD Ryzen 7 5700X3D (16 threads), 64 GB RAM |
| Git | 2.51.1 (local repo, milestone commits by the lead) |
| Blender MCP server | `blender-godot` (`uvx mcp-for-blender --port 9890`, declared in `.mcp.json`); tool namespace `mcp__blender-godot__*` |
| Blender endpoint | `localhost:9890` (listener process PID 25068), add-on protocol v13, add-on 1.8, Blender **5.2.2 LTS** |
| Master file (verified via `bpy.data.filepath`) | `W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta\GodotSonnet5.5GTA.blend` |
| Start state of the .blend | default Cube / Camera / Light only (SHA-256 of the pre-session backup `6C3A4D30…7ED6`, `backups/GodotSonnet5.5GTA.pre-session-20261016T184657.blend`) |
| Project settings changes | `filesystem/import/blender/enabled=false` (Godot must never launch its own Blender; assets arrive as exported GLB), autoloads, physics-layer names |

Other Blender instances run on this machine for other projects; this project only ever talks to the process that owns port 9890 and verified that its open file is the master above.

## Run
```
W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --path "W:\YouTube\Claude Sonnet 5.5\GTA\godot-sonnet-5.5gta"
```
(or open the folder in the Godot editor and press F5). The game launches directly into free roam. Debug/benchmark menu: **F1**.

## Tooling for developers / agents
`tools\gd.ps1` (Godot wrapper: `import`, `check`, `run`, `exec`, `shot`, `script`), `tools\blender\gta_lib.py` (shared Blender helper library), `gta/tests/validate_scripts.gd`, `gta/tests/glb_probe.gd`, `gta/code/debug/dev_harness.gd` (command-line QA options). See `docs/ARCHITECTURE.md`.

## Architecture
See `docs/ARCHITECTURE.md` (contracts, ownership, asset conventions) and `docs/api/*.md` (per-module API). Systems are booted by `gta/code/core/main.gd` in a fixed order; autoloads `Events`, `Game`, `Sfx`, `SaveSystem`.

## Blender asset workflow
`GodotSonnet5.5GTA.blend` (master, edited live through MCP) → procedural bpy/bmesh asset scripts using `tools/blender/gta_lib.py` → visual QA with `look` → `export_glb()` to `gta/generated/models/<category>/<id>.glb` → `tools\gd.ps1 import` → `glb_probe` check → Godot scenes/materials. The master `.blend` is never loaded at runtime.

## Known limitations
(filled in at the end of the run — see `SONNET_5.5_FINAL_REPORT.md`)

## Known limitations (final)
See `FEATURE_MATRIX.md` and `SONNET_5.5_FINAL_REPORT.md`. In short: no dedicated performance pass or full end-to-end play-test after the last wave (done on request to save usage); trains, gamepad, most races and first-person arms are not implemented; audio was verified numerically only; per-car/per-ped draw-call cost is high; arrest outcomes are probabilistic with live traffic.

## Developer tooling added during the run
`tools\gd.ps1` (import/check/run/exec/shot/script with a cross-process lock), `tools\blender\gta_lib.py` + ~157 idempotent builder scripts, `tools\usage_report.py` (transcript token accounting), `gta/tests/validate_scripts.gd` and `glb_probe.gd`, DevHarness command-line options (`gta/code/debug/dev_harness.gd`).
