export const meta = {
  name: 'blender-prop-art',
  description: 'Sequentially model, review and export the log trailer, cargo, nature props, rocks and structures through the verified Blender MCP',
  phases: [
    { title: 'Trailer', detail: 'log trailer + cargo props' },
    { title: 'Nature', detail: 'trees, bush, reeds' },
    { title: 'Rocks', detail: 'rocks, signs, anchor post, fences' },
    { title: 'Structures', detail: 'cabin, garage, fuel station, watchtower, bridges, tent' },
  ],
}

const PROJECT = 'W:\\YouTube\\Claude Sonnet 5.5\\MudRunner\\UnitySonnet5.5MudRunner'

const BUILD_RESULT = {
  type: 'object',
  properties: {
    assets: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, fbxPath: { type: 'string' }, triangles: { type: 'number' }, exported: { type: 'boolean' } }, required: ['name', 'fbxPath', 'exported'] } },
    knownIssues: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['assets', 'knownIssues'],
}

const REVIEW = {
  type: 'object',
  properties: {
    approved: { type: 'boolean' },
    perAsset: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, score: { type: 'number' }, ok: { type: 'boolean' } }, required: ['name', 'score', 'ok'] } },
    defects: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string', enum: ['blocker', 'major', 'minor'] }, asset: { type: 'string' }, problem: { type: 'string' }, fix: { type: 'string' } }, required: ['severity', 'asset', 'problem', 'fix'] } },
    summary: { type: 'string' },
  },
  required: ['approved', 'perAsset', 'defects', 'summary'],
}

const TOOLS_NOTE = `TOOLS: the Blender tools are deferred. Load them first with ToolSearch query "select:mcp__blender-mudrunner-unity__execute_blender_code,mcp__blender-mudrunner-unity__look,mcp__blender-mudrunner-unity__get_scene_info,mcp__blender-mudrunner-unity__get_addon_status". Use ONLY the server mcp__blender-mudrunner-unity (localhost:9891; master file ${PROJECT}\\UnitySonnet5.5Mudrunner.blend). NEVER call search_assets, import_asset or generate_3d (forbidden: no external assets). Do not run Unity. The only files you may create/modify: Tools\\blender_helpers.py (extend, keep signatures), BlenderExports\\_scratch\\*, Assets\\Game\\Art\\** (via FBX export), and the Blender master file. Pass a short user_prompt to Blender tools such as "Model <asset> for the Unity MudRunner project".
Image budget: look with max_size 640-900, a few meaningful views per asset (3/4 view + one other + wireframe once). Several assets per batch: model each one fully, look, fix, export, then the next.
FIRST read ${PROJECT}\\Docs\\ART_SPEC.md completely (binding contract: axes, names, materials, export recipe, QA gate, props rules section 5) and ${PROJECT}\\Tools\\blender_helpers.py (reuse it via exec(open(path, encoding="utf-8").read()); extend if needed). The three vehicles already exist in the master file (collections Veh_*): do not touch them; hide them while you work.`

const BATCHES = {
  Trailer: {
    folderNote: 'Trailers go to Assets/Game/Art/Trailers/<Name>/<Name>.fbx, cargo to Assets/Game/Art/Cargo/<Name>/<Name>.fbx.',
    assets: `
1. LogTrailer (ART_SPEC 4.3): two-axle drawbar log trailer, ~6.5 m long, deck height ~1.1 m, wheels like the Utility (r 0.54, w 0.375, hub z 0.54), axles at y = -1.2 and -2.4 in the UNITY sense given as front=-Y in Blender (the drawbar points to -Y, i.e. the trailer's front is -Y; wheels near the rear, i.e. at Blender y = +1.2 and +2.4 measured from the origin which sits at the trailer's centre of its 6.2 m deck - keep the origin on the ground under deck centre; matching the physics definition: axle positions Unity z = -1.2 and -2.4 mean Blender y = +1.2 and +2.4), track 1.9, leaf springs (Leaf_Front_L/R, Leaf_Rear_L/R) with Mount empties not required for leafs, shock absorbers optional, mud flaps, 4 pairs of log stakes at Unity z = -3.1,-1.2,0.7,2.2, drawbar with an eye at Unity (0, 0.65, 3.7) (empty Anchor_Hitch_Front), CargoOrigin empty on the deck centre, COL_ proxies (deck, drawbar). Wheels named Wheel_FL/FR/RL/RR as in the spec (F = the axle nearer the drawbar). Rust/old-timber look with MR_PaintSecondary frame and MR_Wood planks.
2. Log_Long: straight pine log 5.0 m x radius 0.22 with bark (MR_Bark), cut ends (MR_LogEnd), slight taper and a few branch stubs; pivot at its centre; COL_ capsule-like box.
3. Log_Short: 2.2 m x r 0.2, same style.
4. Barrel: steel fuel barrel 0.58 m diameter x 0.9 m high with rolling rings, bung caps, MR_PaintSecondary/MR_Hazard stripe, MR_Rust patches; origin at the base centre.
5. Crate: wooden slat crate 0.9 x 0.7 x 1.0 m with corner posts and rope handles (MR_Wood); origin at the base centre.
6. Stump: tree stump r 0.45 x 0.6 m with roots flaring into the ground and a cut top with rings (MR_Bark/MR_LogEnd), COL_ proxy; origin at base.`,
  },
  Nature: {
    folderNote: 'Nature props go to Assets/Game/Art/Props_Nature/<Name>/<Name>.fbx.',
    assets: `
1. Spruce_A: tall spruce ~14 m: slightly irregular trunk, 14-18 whorls of branches getting shorter toward the top, needle masses as clumped cards/blobs with MR_Foliage; <= 6k tris; LOD1, LOD2, Spruce_A_Billboard quad.
2. Spruce_B: medium ~10 m (different silhouette/branching).
3. Spruce_C: young ~5 m, denser/lower branches.
4. Birch: ~9 m, white-grey trunk (use MR_Bark light variation via vertex colour or separate material MR_LogEnd for the pale bark), drooping leaf clusters (MR_Foliage), LODs.
5. DeadTree: bleached dead tree ~7 m with broken branches (MR_Bark).
6. Bush: 1.2 m shrub, leaf clusters.
7. ReedClump: 1.6 m clump of reed blades with seed heads (cross cards allowed), for bog edges; double-sided blades OK (MR_Foliage).
Trunk collision: COL_<Name> capsule/box proxy for trees (trunk only), none for bush/reeds.`,
  },
  Rocks: {
    folderNote: 'Rocks/signs go to Assets/Game/Art/Props_Nature/<Name>/ (rocks) and Assets/Game/Art/Props_Structures/<Name>/ (signs, post, fence, barrier).',
    assets: `
1. Rock_S 0.5 m, Rock_M 1.2 m, Rock_L 2.5 m boulder, Rock_Slab (3.0 x 0.6 x 2.0 flat slab): believable weathered rock: displaced/noise-sculpted faceted mesh (bmesh subdivision + noise displacement + planar cuts), flat base on the ground, moss patches via MR_Moss on top faces, MR_Rock main; 600-3000 tris; each with COL_ convex-ish hull (<= 24 verts box-like proxy) and LOD1.
2. Post_Anchor: heavy timber winch-anchor post 0.3 x 0.3 x 1.6 m (MR_Wood) with an iron ring (MR_MetalDark), concrete footing; COL_ proxy.
3. Sign_Arrow: wooden route sign on a post with a pointed arrow board (MR_Wood + MR_Hazard), 2.2 m high.
4. Sign_Warn: triangular warning sign on a post (MR_Hazard/MR_PlasticBlack) 2.2 m.
5. Fence_Section: 3.0 m timber rail fence section with two posts, weathered.
6. Barrier: concrete road barrier 2.0 x 0.5 x 0.8 m.`,
  },
  Structures: {
    folderNote: 'Structures go to Assets/Game/Art/Props_Structures/<Name>/<Name>.fbx.',
    assets: `
1. Cabin: log cabin 7 x 5 m, 3.3 m eaves, stacked round logs with notched corners, porch with posts, stone chimney (MR_Rock/MR_Concrete), door, two windows (MR_Glass), pitched shingle roof (MR_RoofMetal/MR_Wood), exterior detail (woodpile, step); <= 20k tris; COL_ walls/roof boxes; interior not needed; LOD1.
2. Garage: base-camp workshop/garage 14 x 9 m, 5 m high, corrugated metal walls/roof (MR_RoofMetal, MR_MetalDark), a big roll-up door opening (open arch is fine: vehicles park inside the apron area, leave the front open as a bay), a side office annex, signage board blank, lamp posts; COL_ proxies leaving the bay open; <= 20k tris.
3. FuelStation: two pumps (0.5 x 0.4 x 1.5 m with hoses and nozzle holders), a canopy roof on 4 posts (7 x 5 m, 4.2 m clearance), a 2.5 m storage tank on a steel stand, barrels; <= 12k tris; COL_ for posts/pumps/tank (not the canopy underside).
4. Watchtower: 8 m timber watchtower: four legs with cross braces, platform with railing and a small roofed cabin, ladder; <= 10k tris; COL_ legs.
5. Bridge_Intact: 10 m wooden plank bridge, 3.6 m wide deck on log stringers with timber railings and cribbed abutments; planks as separate objects named Plank_01..Plank_NN (so planks can be removed/broken in Unity), curb logs; COL_Deck box + railings.
6. Bridge_Broken: same footprint (10 m) but with 5 of the planks missing and one stringer cracked and sagging, two railing posts leaning; keep plank naming; COL_Deck_Left / COL_Deck_Right pieces only where planks exist.
7. Tent: canvas ridge tent 3 x 2.4 x 1.8 m (MR_Canvas) with guy ropes and pegs.`,
  },
}

function buildPrompt(key) {
  const b = BATCHES[key]
  return `${TOOLS_NOTE}

YOUR TASK: model the following assets in Blender and export each for Unity exactly per ART_SPEC.md (sections 1,2,3,5,6). ${b.folderNote} Each asset has its own collection (Trl_/Cargo_/Nat_/Str_ prefix under the proper MUDRUNNER_UNITY child), a root empty named like the asset, collision proxies in MUDRUNNER_UNITY/Collision, UVs, MR_* materials only, LOD1/LOD2 per section 5 where listed, origin at the base centre on the ground (z=0). Vehicles' front convention does not matter for static props but all other axis/scale rules do. Quality bar: believable, detailed, readable-from-distance game props (silhouette first, then detail, no primitives-with-a-material look).
ASSETS:${b.assets}
Process per asset: build (several execute_blender_code calls), look (quick multi-angle), fix, validate numbers (dimensions, tris, UVs, names), save master .blend (bpy.ops.wm.save_mainfile()), export FBX (temp-file-then-move recipe). Return the structured result for ALL assets of the batch (honest known issues).`
}

function reviewPrompt(key, build) {
  const b = BATCHES[key]
  return `${TOOLS_NOTE}

YOU ARE AN INDEPENDENT ART DIRECTOR / TECHNICAL QA with fresh eyes. Do NOT modify the scene (read-only: look, get_scene_info, read-only execute_blender_code). Inspect every asset of this batch (modeller report: ${JSON.stringify(build)}). The brief was:${b.assets}
Check against ART_SPEC.md: names, hierarchy/root empty, origin at base centre, applied transforms, scale/dimensions vs brief, UVs on every mesh, materials only from the MR_ list, no default names, tri counts, LOD objects where listed, collision proxies, FBX files exist at Assets/Game/Art/... (os.path.getsize). Judge the VISUAL quality honestly from several angles (3/4 view, side, top for each asset; one wireframe): silhouette, believability, detail, no placeholder-ish primitives. Score each asset 0-10 (ok = score >= 7 and no blocker). approved = true only if every asset is ok. List concrete defects with severity, asset name and a specific fix.`
}

function fixPrompt(key, verdict, build) {
  return `${TOOLS_NOTE}

YOUR TASK: fix the assets of batch "${key}" (already modelled; prior export: ${JSON.stringify(build)}) according to this independent review, re-validate, save the master .blend and re-export the FBX files you changed (same paths, temp-file-then-move). Fix every blocker and major defect and as many minor ones as reasonable; look again after changes. REVIEW: ${JSON.stringify(verdict)}
Return the structured build result for all assets of the batch.`
}

const results = {}
for (const key of ['Trailer', 'Nature', 'Rocks', 'Structures']) {
  phase(key)
  let build = await agent(buildPrompt(key), { label: `build:${key}`, phase: key, schema: BUILD_RESULT })
  let verdict = null
  let round = 0
  while (build && round < 2) {
    verdict = await agent(reviewPrompt(key, build), { label: `review:${key}#${round}`, phase: key, schema: REVIEW })
    if (!verdict) break
    log(`${key} review ${round}: approved=${verdict.approved} defects=${verdict.defects.length}`)
    if (verdict.approved) break
    build = await agent(fixPrompt(key, verdict, build), { label: `fix:${key}#${round}`, phase: key, schema: BUILD_RESULT })
    round++
  }
  results[key] = { build, finalVerdict: verdict, fixRounds: round }
}
return results
