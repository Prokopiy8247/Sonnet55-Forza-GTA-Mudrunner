# Agent M-B (relaunched world-materials agent) - status notes

Facts only; this file is owned by M-B.  Context: the duplicate-agent incident left more than one M agent alive (see Saved/MatJobs/claims and F1_COORD.md for the
same situation with the F1 agent).  M-B started at ~03:09 and cannot message the other M agent(s).

## things M-B did that touch files M-A (the other M agent) may have been working on
- 03:26  Tools/ue/materials_m_road.py was rewritten by M-B (new road mesh contract, see below).
- 03:31  Tools/ue/materials_m_surface.py was CREATED by M-B (did not exist before).
- 03:33  Tools/ue/materials_m_fx.py was OVERWRITTEN by M-B by mistake (M-A's 03:32 version, 13522 bytes, is gone).  The file now holds an untested
         draft of the fx masters by M-B WITHOUT a BUILDERS dict, so build_all skips it and the fx assets M-A built at 03:29 stay untouched.
         The file has since been completed by M-B (BUILDERS added, all fx masters compile; see the status log below) and adopted by M-A.

## scope M-B is working on now
- road master M_Roam_Road for the real chunk mesh contract (Exports/Roads/chunks.json "uv_channels"): UV1=(d,s) metres from the centre line, UV2=(paved half width,
  lane width), UV3=(median width, zone); instances in /Game/Forza/Materials/Roads/ (R's Tools/ue/import_roads.py loads MI_<slot without M_> from there)
- materials_m_surface.py: M_Roam_Building, M_Roam_Glass_Building, M_Roam_Roadside, M_Roam_Billboard
- materials_instances_surface.py (MI_RS_*, MI_Bld_*, MI_Road_*, MI_Curb, MI_Bridge_*, MI_Tunnel_*), materials_testsheet_surface.py, Docs/Tech/MATERIALS_surface_fragment.md
- rebuilds only its own masters: job argument "masters=M_Roam_Road,M_Roam_Building,M_Roam_Glass_Building,M_Roam_Roadside,M_Roam_Billboard"

## status log
- 03:42 M-B: new road master + surface masters written, not built yet.
- 04:40 M-B: masters M_Roam_Road (new UV contract), M_Roam_Building, M_Roam_Glass_Building, M_Roam_Roadside, M_Roam_Billboard compile OK; instances ok=131 failed=0 (incl. M-A's fx instances).
- 04:48 M-B: materials_m_fx.py (the file M-B overwrote at 03:33) now has BUILDERS and compiles: M_Roam_Water_Simple/River (Single Layer Water, opaque), M_Roam_Particle_Soft/_Unlit, M_Roam_Skid, M_Roam_PP_RainOverlay.
- 04:50 FOUND: mel.delete_all_material_expressions leaves nodes behind in 5.8.2 (Single Layer Water output node + others survive; "56 expressions survived the wipe"). materials_lib.new_material now deletes + recreates the asset when
        get_num_material_expressions() != 0 after the wipe (edit by M-B, 3 lines). Consequence: masters rebuilt before 04:50 may carry stale orphan nodes (duplicate parameter names): rebuild all masters once more.
- 04:57 M-B: tools/ue/job_drop.ps1 added (drops a job into the running server without Ensure-JobServer); _server_lib.ps1 no longer starts a second server while one is queued behind another Unreal run.
- 05:05 M-B: probe result: delete_all_material_expressions removes ~half the nodes per call. materials_lib.new_material loops until empty (all masters were rebuilt at 05:14 with the fix: 17 masters compile OK, instances ok=131 failed=0).
- 05:05 CRASH (editor, python311/MaterialEditor access violation) when a master that has instances is deleted + recreated (my first lib fix did that for M_Roam_Road; the asset file was removed and rebuilt at 05:14). Do not delete masters that have instances.
- 05:20 M-B: materials_testsheet.py: sheet state kept on the `unreal` module and a second sheet job arriving while a sheet is shooting is QUEUED instead of cancelling the running one (M-A: this is a small edit in your file, run()/tick; revert if you object).
- 05:22 M-B: Docs/Tech/MATERIALS.md written (tooling, quirks, MPC, textures, road / building / glass / roadside); fragments MATERIALS_nature*.md are linked from it.
- 06:14 M-B: SHEET RESULTS (Saved/MatShots/road_*.png ...): road master verified (edge lines, dashed lane dividers at the right place on regional / highway strips, dirt ruts + grass edges, wet puddles + ripples, snow keeps lanes clear). FOUND: UE flips V on FBX import -> the master un-flips s / lane width / zone (UVFlipV). Roadside + glass + building masters verified visually (day, wet, night).
- 06:20 M-B: materials_testsheet.py: hold_sheet protocol inside run() (so the testsheet step of materials_build.py is safe too). MPC_Roam_World got scalar `Headlights` (default 1; M_Roam_Roadside retro-reflective response). Cleanup job removed the orphans M_Roam_Skid_Strip / Glass_Simple / Particle_Soft_Unlit.
- 06:38 M-B: FINAL: full default build OK (18 masters, 163 instances, 0 failures, textures idempotent), screenshots checked, Docs/Tech/MATERIALS.md complete. M-B stops here; open items: billboard / PP rain / junction pad not screenshot-verified.
