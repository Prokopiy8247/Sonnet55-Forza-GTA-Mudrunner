# FH5 road events and activities -> our activity system (research + designs)

Scope: reference notes for an ORIGINAL game (UE 5.8, 4x4 km, 40-60 km of road, 10 Blender cars, code/procedural-generated world).
Forza Horizon 5 is used only as a mechanics/structure reference. Everything below is written in my own words.

Evidence tags used throughout:
- [F] fact read on a page I actually fetched (URL in Sources).
- [S] fact seen only in a web-search result summary (weaker; verify before relying on it).
- [D] number derived by me from [F] data (calculation shown).
- [E] verified by reading the local UE 5.8 engine source/headers in `W:\Unreal Engine 5\UE_5.8`.
- [X] our design decision (not from FH5; no source documents it).

Honest gap statement: none of the sources I could reach document FH5's exact HUD wording, banner timings or XP-per-star payouts,
and Playground does not publish drift/skill point formulas. All HUD text/timings and all formulas in sections 3-6 are therefore [X]
(informed by the FH5 structure below). Where FH5 numbers exist they are used to calibrate star ratios.

---------------------------------------------------------------------------------------------------

## 1. What FH5 does (facts)

### 1.1 Event categories and unlocking
- Five event families: Road racing, Dirt racing, Cross-country, PR Stunts, Street racing. The map groups them under Outposts named
  Apex (road), Wilds (dirt), Baja (cross-country), Rush (PR Stunts) and the Street Scene series. [S: techraptor race-types summary]
- Outposts are unlocked by earning Accolades (completing events); unlocking any one outpost makes every feature playable. [F: forza.net first-drive]
- PR Stunts as a whole unlock after one scripted "Expedition" (Canyon Expedition builds the Horizon Rush outpost). The very first stunt of each type
  is available from the start of the game; the rest appear after that. Expeditions cannot be replayed; what they unlock is permanent. [F: guides4gamers, mapmaster; S: search]
- Showcase events are one-off spectacle races (e.g. the opening one races a cargo plane through varied terrain while clearing checkpoints; rivals include planes, boats, trains, a monster truck). [F: forza.net first-drive]
- Cross-country/Baja events are checkpoint races over open terrain (checkpoints, not a fixed track). [F: forza.net first-drive mentions "clearing checkpoints"; S for the rest]
- Difficulty: AI ("Drivatar") difficulty and assist settings change the credit payout, not XP: harder AI + fewer assists = larger credit bonus. XP is reported to follow event length and finishing position. [S: racinggames.gg, Steam thread - community level evidence, no exact percentages found]
- Rivals = ghost time trials against recordings of other players' best laps; ghosts are non-collidable; there were long-running problems with bogus times on Rivals/PR Stunt leaderboards. [S: ludo.guide, quartertothree, forza.net community update]

### 1.2 PR Stunts - the five types (all are "just drive through it", nothing to press) [F unless noted]
Per stunt: up to 3 stars, replayable at any time to raise the star count; the map icon shows the target values on hover. [F mapmaster; S racinggames.gg]
Aggregate meta-goal: one Gold trophy needs 294 PR-Stunt stars in the base map. [F mapmaster]

| Type | What is measured | Trigger | Fail / validity rules |
|---|---|---|---|
| Speed Trap | speed at the instant of crossing a single beam (peak speed, nothing else) | drive through the gate, any direction | none documented; one seasonal challenge reportedly did not register on tuned/painted cars (trigger robustness lesson) [F gtplanet] |
| Speed Zone | AVERAGE speed over a marked road stretch (not top speed); a GTPlanet note says the game averages the car's speed rather than computing it from time between the points | cross either end gate and drive toward the opposite one (timing starts at whichever gate you enter through; wrong direction does not count), cross the far gate | must stay on the road [S] |
| Drift Zone | drift score accumulated inside the marked section (angle x speed x duration; long continuous drift beats several short ones) | evaluation starts when you drive onto the section from EITHER side | staying on road not confirmed; hitting flags/walls ends the combo (community guides, FH6/FH5 mix) |
| Danger Sign | flight distance of a jump from a special ramp | hit the ramp | landing must be clean: hitting a tree or ending upside down fails, a bad landing scores nothing [F guides4gamers; S racinggames.gg] |
| Trailblazer | remaining countdown time at the finish gate of an off-road sprint | countdown starts when you cross the start gate; any route | none; 3-star = remaining seconds above a per-sprint value [F mapmaster] |

Star thresholds from the data I could extract (units converted by me where noted):

Speed Trap (35 Mexico traps; 3 tiers on guides4gamers, mph in source):
- 3-star targets across the base map: 105-270 mph (169-434 km/h); 1-star 30-90 mph; 2-star 70-175 mph. [F]
- Sample rows (1/2/3 star, mph): Arid Hills 55/155/225; Autopista 75/175/240; Baja California 35/100/140; Drag Strip 65/150/205;
  East Resort 90/130/200; Federal Highway 65/170/270; Horizon Baja 35/70/110; Mountainside 30/95/135; Pyramid of the Sun 30/110/165; Tulum 80/130/170. [F]
- [D] Ratio to the 3-star value over those 10 rows: 1-star median 0.28 (range 0.18-0.47), 2-star median 0.69 (range 0.63-0.77).

Speed Zone (26 Mexico zones, average mph):
- 3-star targets 70-260 mph; 1-star 30-100; 2-star 60-190. Samples: Airfield 100/125/150; Camino del Cielo 50/100/135; Carretera 45/110/150; Cordillera 30/80/110; Rocky Hills 35/60/70; El Gancho 30/60/75; Trebol 100/190/260. [F]
- [D] Ratios over 12 rows: 1-star median 0.38, 2-star median 0.74.

Drift Zone (20 Mexico zones, points):
- 3-star 30,000 (Giro Encorvado) to 500,000 (Cara Este); most between 50,000 and 190,000. Samples 1/2/3: Arbolada 10k/55k/110k; Costera 5k/40k/70k;
  East Coast 10k/70k/130k; Giro Encorvado 2.5k/15k/30k; Las Curvas 5k/30k/60k; Las Dunas 15k/75k/150k; Cara Este 50k/250k/500k. [F]
- [D] Ratios over 10 rows: 1-star = 0.07-0.10 of 3-star, 2-star = 0.50-0.58.

Danger Sign (24 Mexico signs, feet in source):
- 3-star distances 300-1,750 ft (91-533 m); samples 1/2/3: Broadwalk 100/200/300; Hotel 100/250/450; Cannonball 100/400/600; Basejump 250/800/1650;
  Runway 100/850/1750; Salto de Rio 300/360/420; San Juan Jump 250/300/380; Metal Bird 200/370/400; Mountain Top 500/1000/1650. [F]
- [D] Ratios over the 24 rows: 1-star median about 0.2, 2-star median about 0.55 (huge spread; some signs are nearly flat 0.7/0.86).
- Tips from the same pages: full throttle through the ramp, no steering at the lip, nitro/slipstream for short run-ups; narrow ramps with an angle requirement are the hardest. [F/S]

Trailblazer (13 sprints, remaining seconds for 3 stars): 15-35 s depending on the sprint; one finale sprint has no star target. Route is free; high clearance AWD recommended. [F mapmaster]

Seasonal PR Stunts: every weekly series adds a few stunts of each type; each one pays 2 festival points + a reward, daily challenges pay 1 point; some challenges are cumulative (e.g. total speed across several traps, total jump distance, total drift skills). [F gtplanet; F forza.net Community-Choice, High-Performance]
Car/class restrictions exist only in the expansion map (Hot Wheels Park) and seasonal variants - we SKIP that.

### 1.3 Collectibles and discoveries
- Bonus boards (wooden boards): drive into them to smash. Two kinds: XP boards (single payout of 1,000 / 3,000 / 5,000 XP; about 100/75/25 split in Mexico) and Fast Travel boards (50 in Mexico; fast travel base cost 10,000 credits, each board removes 200 credits, 50 boards = free). 255 XP boards across all three maps; a trophy counts "250 in Mexico" (counts differ by source). [F mapmaster XP Board, Fast Travel Board; S for trophy]
  - 1,000 XP = drive through; 3,000 XP = needs a detour (inside a barn, under a bridge, ramps up a temple); 5,000 XP = specific vehicle/angle/speed, usually a launch off a hill or ramp. [F mapmaster]
  - Map markers only appear when you are nearby; collected ones stay on the map but turn grey. Reported audible cue when close (turn the radio off). Paid DLC shows all. [S techraptor/racinggames]
- Barn Finds: 14 hidden vintage cars. A rumor unlocks (mostly randomly with progress, four by specific accolades); the map icon appears; on arrival a search circle appears; you search by minimap; driving up to the barn triggers a cutscene; the car is damaged and a restoration timer runs at a house (can be skipped for credits); later you can gift cars into barns for other players. [F dexerto]
- Treasure chests: weekly orange search circle on the map tied to a clue; drive into the chest to smash it; chests hide on trucks/under bridges. [S racinggames.gg]
- Photo Challenges: take a photo of a given car at a given spot (some ignore the spot or ask for a time of day); done in photo mode; reward = seasonal points/cosmetics. [S racinggames.gg, gfinity]
- Horizon Arcade and EventLab are multiplayer/UGC modes - out of scope. [F wikipedia]

### 1.4 Skill chain ("Skills") - FH5's combo scoring [mostly F, numbers conflict between guides]
- Basic skills: Air, Burnout, Clean Racing, Drafting, Drift, E-Drift (handbrake), J Turn, Near Miss, One Eighty, Pass, Speed, Trading Paint, Two Wheels, Wreckage. [F insider-gaming]
- Combo skills fire when two basics hit together or in quick succession: Lucky Escape (Drift + Near Miss), Stuntman (Air + Near Miss), Showoff (Drift + Pass), Sideswipe (Drift + Wreck), Slingshot (Draft then Pass), Daredevil (3 near misses quickly), Kangaroo (3 airs quickly), Triple Pass, Threading the Needle, Barrel Roll (>=270 deg air rotation), Crash Landing (Air + Wreckage), Wrecking Ball. Ultimate Skill Chain = 20,000 points before the multiplier starts. [F insider-gaming]
- Chaining different skills builds the multiplier faster; a long gap resets it; a collision ends the chain (some car perks let it survive two). Base cap reported as x5 (search snippet), car perks raise to x7-x8; banking = stop driving / wait a few seconds; a banked chain pays skill points toward car mastery (guides say max 10 skill points per bank, ~500,000 chain points cap or ~63,000 with an x8 car). [F gamerant, inverse; S gamesradar] - the guides disagree on exact thresholds, treat as "mechanic confirmed, numbers unreliable".
- Skill songs on the radio reportedly double the cap (x5 -> x10). [S]

---------------------------------------------------------------------------------------------------

## 2. Architecture for our version (applies to every activity) [X unless tagged]

### 2.1 Units and engine facts [E]
- `UChaosVehicleMovementComponent::GetForwardSpeed()` returns CENTIMETRES PER SECOND (the engine implements `GetForwardSpeedMPH()` as `Chaos::CmSToMPH(GetForwardSpeed())`).
  km/h = cm/s x 0.036. It is signed (negative when reversing) - use magnitude of world velocity for traps/zones.
- Public member `FVehicleState VehicleState` on the movement component exposes `NumWheelsOnGround`, `bAllWheelsOnGround`, `bVehicleInAir`, `VehicleUpAxis`,
  `VehicleForwardAxis`, `VehicleWorldVelocity`, `VehicleLocalVelocity`, `ForwardSpeed`. Per-wheel: `UChaosWheeledVehicleMovementComponent::GetWheelState(int)` -> `FWheelStatus`
  with `SlipAngle`, `bIsSlipping`, `SlipMagnitude`, `bIsSkidding`, `SkidMagnitude`, `bInContact` (wheel-level, async from the physics thread, one-frame latency).
- IMPORTANT project finding: in UE 5.8 Chaos Vehicles lives in `Engine/Plugins/Experimental/ChaosVehiclesPlugin` (module `ChaosVehicles`, `EnabledByDefault: false`, experimental).
  The current `Sonnet55Forza.uproject` does NOT enable it and `Sonnet55Forza.Build.cs` does not reference it. If the driving model uses Chaos, add
  `{ "Name": "ChaosVehiclesPlugin", "Enabled": true }` to the .uproject and `"ChaosVehicles"` to `PublicDependencyModuleNames`. To keep the activity system independent of the physics choice,
  all activities read a small interface (below) instead of Chaos types.
- `USplineComponent` in 5.8 has `GetSplineLength`, `FindInputKeyClosestToWorldLocation`, `GetDistanceAlongSplineAtSplineInputKey`, `GetDistanceAlongSplineAtSplinePoint`, `GetInputKeyValueAtDistanceAlongSpline`
  (all verified in `SplineComponent.h`). `FindInputKeyClosestToWorldLocation` scans the whole spline - fine for occasional use, too slow per-frame on a 23 km route; see 2.4.
- `UTickableWorldSubsystem` (also `FTickableGameObject`) requires you to override `GetStatId()` (pure virtual) or the module will not link/compile; use `RETURN_QUICK_DECLARE_CYCLE_STAT`.
  `UWorldSubsystem::DoesSupportWorldType` should return true for Game/PIE only.
- `SaveGameToSlot`/`AsyncSaveGameToSlot` (UGameplayStatics) is the supported path: sync is fine for small data/paused UI, use async when saving during play (Epic "saving and loading your game").

### 2.2 Module layout (new C++ in module `Sonnet55Forza`, or a sibling module `ForzaActivities`)
- `IActivityVehicleSource` (interface implemented by the player pawn or a `UActivityTelemetryComponent` on every car):
  `GetWorldVelocityCmS()`, `GetForwardAxis()`, `GetUpAxis()`, `GetNumWheelsOnGround()`, `IsAirborne()`, `GetSpeedKmh()`, `GetCarId()`. A Chaos implementation reads `VehicleState`; a custom raycast vehicle implements it differently.
- `UActivitySubsystem : UTickableWorldSubsystem` - owns ALL activity logic and state. Data-driven; no per-activity actor tick.
- `UActivityDatabase` (UDataAsset or DataTable rows `FActivityRow`) - id, type, region, route/gate geometry in world space, thresholds, rewards. Generated by the same Python/C++ tool that lays the roads (gate positions come from road spline sample points).
- Visual props (speed camera pole, flags, hazard chevrons, ramp, start arches, billboards) are ordinary World Partition actors/ISMs placed by the generator. They are NOT required for logic, so a streamed-out prop can never break an activity.
- `UActivitySaveGame : USaveGame` - `int32 Version; TMap<FName,FActivityRecord> Records; TSet<FName> Collected; TMap<FName,FCarBest> PerCarBest; int64 TotalXp;`
- `FActivityNotification` struct + `FOnActivityNotification` multicast delegate. The HUD module only listens to this (see section 7); activities never touch widgets.
- Console (ties into the mandatory console): `act.list`, `act.tp <id> [kmh]` (teleport 450 m before the activity facing it and set the car's velocity - lets the agent test without driving),
  `act.debug 0|1` (DrawDebug gates/zones), `act.reset <id|all>`, `act.stars` (print totals), `act.cheat <id>` (award 3 stars).

### 2.3 Triggering without tunnelling [X, important]
At 270 km/h (75 m/s) a car moves 1.25 m per 60 fps frame and 2.5 m per 30 fps frame; thin overlap boxes miss it (and FH5's own trap needs "driving through a beam").
Do NOT use overlap volumes for gates. Use a segment-versus-plane test in the subsystem tick:

```
struct FGate { FVector Center; FVector Forward; FVector Right; float HalfWidth; float HalfHeight; };
bool CrossGate(const FGate& G, FVector P0, FVector P1, bool bBothDirections, float& OutAlpha, float& OutLateral)
{
    const float D0 = FVector::DotProduct(P0 - G.Center, G.Forward);
    const float D1 = FVector::DotProduct(P1 - G.Center, G.Forward);
    const bool bFwd  = (D0 <= 0.f && D1 > 0.f);
    const bool bBack = (D0 >= 0.f && D1 < 0.f);
    if (!(bFwd || (bBothDirections && bBack))) return false;
    OutAlpha = D0 / (D0 - D1);                              // sub-frame crossing time
    const FVector Hit = FMath::Lerp(P0, P1, OutAlpha);
    OutLateral = FVector::DotProduct(Hit - G.Center, G.Right);
    const float Vert = FVector::DotProduct(Hit - G.Center, FVector::UpVector);
    return FMath::Abs(OutLateral) <= G.HalfWidth && FMath::Abs(Vert) <= G.HalfHeight;   // HalfHeight ~ 4 m: rejects roads stacked on bridges/tunnels
}
```
Speed at the gate = `FMath::Lerp(PrevSpeed, CurrSpeed, OutAlpha)`; time at the gate = `Lerp(PrevTime, CurrTime, OutAlpha)` (sub-frame accurate splits).
Use the car's centre-of-mass position (not actor origin of a mesh that changes with body kit/paint). Keep `PrevPos` per tick; if `|CurrPos-PrevPos| > MaxCredibleSpeed*dt + 5 m` (teleport, respawn, `tp`, garage switch) discard the pair and cancel any active attempt.
Lesson from FH5 [F gtplanet]: one seasonal trap objective reportedly failed to register on tuned/painted cars; triggers must depend only on the possessed pawn's position/velocity, never on car identity, mesh bounds or livery.

Relevance culling: keep gates in a coarse grid (e.g. 500 m cells). Each tick only test activities whose bounds are within 800 m of the player (typically < 10). Cost is negligible, no actors ticking.

### 2.4 Route progress (zones, sprints, time trial) [X]
Do not call `FindInputKeyClosestToWorldLocation` every frame on a 23 km spline. At build time sample every route into `TArray<FVector> Pts` at 5 m spacing with cumulative distance `S[i]`.
At runtime keep `HintIndex` and search a window of +-40 samples around it (monotone progress), giving O(80) per tick and a stable `Progress(m)` plus `Lateral(m)` offset. Re-seed with a full search only after a teleport.
Use `GetDistanceAlongSplineAtSplineInputKey` at build time to fill `S[]`.

### 2.5 State machine (shared)
`Idle -> Armed (player within 800 m and moving the right way) -> Active -> Evaluating -> Result (card) -> Cooldown`
- Cooldown/re-arm: gate-type stunts re-arm after the player is > 80 m away from the gate or 3.0 s later, whichever is later; sprints/races re-arm after 120 m past the finish.
- Cancel conditions for every Active attempt: car switched (garage/console `car`), `respawn`/`tp`/`reset`, photo mode opened (timers FREEZE rather than cancel - use `UWorld::GetTimeSeconds()` which stops on pause, never real time), pawn destroyed.
  Cancel banner: "ACTIVITY CANCELLED" 2.0 s, no result, no stars.
- One active timed activity at a time; the passive ones (speed trap crossing, billboards) may still trigger. Priority: Race/TimeTrial > Sprint > Zone > Jump.
- Traffic integration: while a Drift Zone, Speed Zone, Danger Sign or Sprint is Active, publish `OnActivityActive(Id, Bounds)` so the traffic system suppresses spawns inside `Bounds` expanded by 150 m (unfair crashes are the top cause of frustration in these events).

### 2.6 Persistence and personal-best handling [X, modelled on FH5 "replay to improve"]
```
USTRUCT() struct FActivityRecord {
  float BestValue;   // km/h, avg km/h, points, metres, seconds (lower is better for time types)
  uint8 BestStars;   // 0..3, never decreases
  uint8 BestMedal;   // time types: 0 none,1 bronze,2 silver,3 gold,4 author
  int32 Attempts;    // counts completed attempts, not fails
  float LastValue;
  int64 FirstClearedUnix;
};
```
- A result is a NEW BEST when it beats `BestValue` by more than epsilon (0.5 km/h, 1 pt, 0.1 m, 0.01 s). Stars only ever go up. Show delta ("+12 km/h").
- Per-car bests (`PerCarBest[CarId]`) are tracked for time types only; stars use absolute thresholds like FH5.
- Save asynchronously at result time (`AsyncSaveGameToSlot("ActivityProgress",0)`); flush on level end/quit. Missing/corrupt save = default state, never crash. Version field for migration.
- Menu shows "STUNT STARS 41 / 96" (FH5 equivalent: the 294-star trophy).

---------------------------------------------------------------------------------------------------

## 3. Star-threshold generation (so every activity has a sane, achievable target) [D+X]

FH5 hand-tunes every sign. We have ~80 activities generated procedurally, so thresholds must be computed from road geometry, then rounded.

### 3.1 Ratio set (derived from the FH5 samples in section 1.2)
| Type | 1-star | 2-star | 3-star | Rounding |
|---|---|---|---|---|
| Speed trap | 0.28 x V3 | 0.69 x V3 | V3 | 5 km/h |
| Speed zone (avg) | 0.38 x V3 | 0.74 x V3 | V3 | 5 km/h |
| Drift zone | 0.08 x S3 | 0.53 x S3 | S3 | 2,500 pts |
| Danger sign (m) | 0.20 x D3 | 0.55 x D3 | D3 | 5 m |
| Sprint remaining time | 0.0 s left (finish) | 0.5 x T3 | T3 | 1 s |

### 3.2 Route speed profile (shared utility `FRouteSpeedProfile`)
Used for speed-zone V3, race time allowances, time-trial medals, AI target speeds.
```
ds = 5 m
kappa_i   = |heading_{i+1} - heading_{i-1}| / (2 ds)        // 3-sample smoothing
vlim_i    = min(Vcap_class, sqrt(a_lat / max(kappa_i, 1e-4)))   // a_lat: tarmac 7.5 m/s^2, gravel 5.0, dirt 4.5
forward:  v_i = min(vlim_i, sqrt(v_{i-1}^2 + 2*a(v_{i-1})*ds))       a(v) = a0*(1-(v/Vcap)^2) - g*grade ; a0 = 6.5 m/s^2
backward: v_i = min(v_i, sqrt(v_{i+1}^2 + 2*a_brake*ds))              a_brake = 9 m/s^2 (tarmac), 6 (dirt)
T_profile = sum(ds / v_i)
AvgSpeed  = L / T_profile
```
Vcap by road class (km/h): highway 230, valley/coastal 170, mountain 130, gravel 120, dirt track 100.
Reference car = top car of the roster (so 3 stars is reachable by the best car and 1-2 stars by the weakest).

### 3.3 Per-type derivation
- Speed trap: choose a gate at the end of a straight with run-up `Lrun` metres (curvature < 1/800 m^-1). `Vreach = min(Vcap, sqrt(v0^2 + 2*4.0*Lrun))` with `v0 = 100 km/h`; `V3 = 0.96*Vreach`. Example: Lrun = 1,200 m, Vcap 230: sqrt(27.8^2 + 9600) = 101.8 m/s = 366 km/h, so Vreach = 230 -> V3 = 220, V2 = 150, V1 = 60.
  Short run-up example: Lrun = 350 m, Vcap 170: sqrt(27.8^2 + 2800)=59.9 m/s = 216 -> capped 170 -> V3 = 165 (with 0.96 rounding), V2 = 115, V1 = 45.
- Speed zone: `V3 = 0.92 * AvgSpeed(zone)` from the profile (best car, perfect line is ~1.0). Zone length 800-2,500 m. Example: 1,600 m valley stretch with AvgSpeed 125 km/h -> V3 = 0.92*125 = 115, V2 = 0.74*115 = 85, V1 = 0.38*115 = 45 (all rounded to 5).
- Drift zone: see 4.3 (`S3 = RoundTo(2500, 0.6 * Rate_nom * (5*Tdrift - 20))`).
- Danger sign: see 4.4 (ballistic range).
- Time trial/race: medal multipliers on `T_profile` (see 4.6/4.5).

---------------------------------------------------------------------------------------------------

## 4. Activity designs

Common conventions: all speeds km/h (mph via setting), distances m, HUD per section 7, XP per section 6.

### 4.1 Speed trap (ADOPT)
- World: roadside gantry/camera pole on one side + a faint ground line; gate plane across the full road width + 2 m each side (`HalfWidth = roadHalfWidth + 2 m`, `HalfHeight = 4 m`).
  Place on straights, never inside tunnels/bridges or within 200 m of a junction. Count: ~10 on a 50 km network (1 per 5 km), 4 on highways, 3 valley, 2 coastal, 1 mountain.
- Trigger: segment-plane crossing (2.3), both directions allowed (FH5 allows either direction [F]). Airborne crossings are ignored (`NumWheelsOnGround == 0`).
- Value: `speedKmh = Lerp(prev,curr,alpha)` of horizontal world speed magnitude x 0.036.
- Stars: thresholds from 3.1/3.3. Zero stars is possible ("TOO SLOW").
- Immediately produce the result (no Active state). Camera flash: full-screen white overlay 0.10 s fade + shutter SFX (pure presentation).
- Cooldown: see 2.5. Same gate scoring a second pass counts as a new attempt (replay-to-improve).

### 4.2 Speed zone (ADOPT)
- World: start gate and end gate with banners + roadside flags every 120 m; zone length 800-2,500 m on a single road without junctions.
- Start: crossing the start gate from either end (direction = whichever gate crossed first, FH5 requires correct direction [F]). Active window = progress `s in [0, L]` along the zone polyline.
- Live: `liveAvg = (s_now - s_start) / t_elapsed` (km/h). Displayed continuously.
- Final: `avg = L / T` where `T` is sub-frame gate-to-gate time. I deliberately use L/T instead of integrating sampled speed: it matches how a viewer thinks about it and cannot be inflated by weaving.
  (FH5 reportedly averages the car's speed [F gtplanet]; for straight zones both agree within about 1%.)
- Fail conditions: lateral offset > `roadHalfWidth + 4 m` for > 1.0 s ("LEFT THE ROAD"); reverse direction after start ("WRONG WAY"); speed < 10 km/h for > 2.5 s ("STOPPED"); collision with traffic does not fail (it just costs speed).
- Worked example (V1/V2/V3 = 45/85/115): a driver averaging 99 km/h scores 2 stars; a 1.6 km zone at 115 km/h average takes 50.1 s.

### 4.3 Drift zone (ADAPT - FH5 formula is unpublished, so our own)
Zone: a winding road section 350-1,500 m long, ideally with 4+ corners and a mix of left/right; yellow-black flags on the apexes. Evaluation starts when the player crosses either end gate (FH5 allows both ends [F]).

Per physics tick (use a fixed accumulator at 60 Hz for frame-rate independence), `dt` seconds:
```
V      = horizontal velocity (m/s), Speed = |V|
beta   = acos( dot(V/Speed, ForwardXY) ) in degrees   // body slip angle; > 90 => reversing => ignore
candidate = Grounded(>=3 wheels) && SpeedKmh >= 30 && beta in [12, 80]  (enter)  /  beta >= 8 (keep: hysteresis)
if candidate for >= 0.35 s -> drifting = true
if !candidate for > 0.8 s  -> chain ends (0.8 s "transition window" lets S-bend flicks keep the chain; no points earned inside the window)
rate   = 0.5 * min(SpeedKmh, 140) * min(beta, 60)        // base points per second; v=80,b=30 -> 1200/s
mult   = min(5, 1 + floor(chainDriftTime / 2.0))          // x1..x5, +1 per 2 s of continuous chain
chainScore += rate * mult * dt
```
- Chain end (timeout >0.8 s): bank `chainScore` into `zoneScore`. Leaving the zone with a live chain banks it.
- Crash (impact deceleration > 7 m/s within 0.2 s, or any hit with a tagged static obstacle, or wheels off the road > 1.0 s): the LIVE chain is lost (zero points), banked chains are kept. Mirrors the FH5 "hit a flag/wall and the combo resets" behaviour from community guides.
- Cone/flag clipping: allowed and ignored.
- Score at exit = `zoneScore` (+ live chain). Stars via 3.1.
- Threshold generation: nominal drift speed `v_nom = 60-70 km/h`, nominal angle 30 deg, `Rate_nom = 0.5*v_nom*30` (= 900 at 60 km/h); drift time `Tdrift = 0.7 * L / v_nom_ms`; ideal single chain score `Ideal(T) = Rate_nom*(5*T - 20)` for T >= 8 s (1 + 2 + 3 + 4 ramp = 20 s-equivalents, then x5);
  `S3 = RoundTo(2500, 0.6*Ideal)`. Example: 700 m zone at 60 km/h -> Tdrift = 29.4 s, Ideal = 900*(147-20) = 114,300 -> S3 = 70,000, S2 = 37,500, S1 = 5,000 (identical to FH5's Costera 5k/40k/70k, a useful sanity check).
  Typical good run: 12 s continuous drift at 80 km/h, 30 deg (base 1200/s): 2400 + 4800 + 7200 + 9600 + 12000 + 12000 = 48,000 points, i.e. a solid 2 stars on that 70k-class zone.
- Tuning knobs exposed as CVars: `act.drift.minSpeedKmh`, `act.drift.minAngle`, `act.drift.rateScale`, `act.drift.multStepSec`, `act.drift.transitionSec`.
- Pitfall: cars with strong stability assist never exceed beta 12 deg; zone only works if the handling model allows a drift with throttle/handbrake. Test with at least the 3 RWD cars; mark drift-capable cars in the garage ("DRIFT" tag) and show a hint at the zone entrance for other cars.

### 4.4 Danger sign / jump (ADOPT, with careful ramp engineering)
- World geometry (generated; collision must be simple convex/box, >= 50 cm thick; never Nanite-only collision):
  approach straight >= 250 m; ramp width 8-10 m; lip angle 12-18 deg; lip height >= 1.2 m; transition radius >= 40 m (avoids bottoming out the chassis); guide cones/chevrons; landing pad on flat meadow (slope <= 8 deg), width >= 30 m, length >= `D3 + 60 m`, clear of trees/rocks (FH5: hitting a tree fails [F]), no road-surface drop-off.
- Ideal flight distance (for sizing and for D3): `R = (v cos(th) / g) * (v sin(th) + sqrt(v^2 sin^2(th) + 2 g dh))`, `dh` = takeoff height minus landing height, `g = 9.81` (scene gravity -980 cm/s^2 default).
  Example: v = 50 m/s (180 km/h), th = 14 deg, dh = 0 -> R = 119.7 m; `D3 = 0.85*R = 100 m`, D2 = 55 m, D1 = 20 m. FH5's smallest 3-star is 91 m and range 91-533 m [F]; ours 40-250 m on a 4 km map.
- State machine:
  - Arm: player enters the 12 m LaunchBox on the ramp, speed >= 40 km/h.
  - Takeoff: `NumWheelsOnGround == 0` for >= 0.12 s while inside the LaunchBox (+ 6 m beyond the lip). `P_take` = last grounded position.
  - Flight: live distance = |XY(pos) - XY(P_take)| (horizontal; ignores height so cliff-landings are not penalised). Minimum airtime 0.4 s to count; max 12 s or below the kill plane -> fail.
  - Landing: first tick with `NumWheelsOnGround >= 2`. `distance = |XY(P_land) - XY(P_take)|`.
  - Validation window (1.5 s after landing): `UpAxis.Z >= 0.5` at landing and >= 0.7 after 1.0 s; no hit with a component tagged `StuntFail` (trees, rocks, buildings, fences - set via collision profile or ComponentTag) during flight + window; horizontal speed not dropped > 60% within 0.5 s; not rewound/teleported. Any failure -> "CRASH LANDING", no score.
  - Flip: `UpAxis.Z < 0` at any time -> fail "FLIPPED".
- Stars: D1/D2/D3 as above. Score stored = distance in metres.
- Extras (stretch, +presentation only): slow-motion 0.6x while airborne for >1.0 s, chase-cam pull-back, distance marker ring painted on the landing pad.
- Danger: the tunnelling at the lip is real - use a gate-style LaunchBox test (box vs segment) not overlap events.

### 4.5 Checkpoint race (ADAPT: solo countdown sprint first, AI as stretch)
FH5 racing = start line, grid, checkpoints, finishing position vs AI, rewards by position/difficulty. We keep the checkpoint/position structure but ship a solo countdown mode that reads well on video, and treat AI as an optional layer.

Variants (all share one `ARaceDefinition` data type): `RoadRace` (follows a road route, gates every 350-900 m), `DirtSprint` (cross-country gates, wide 30-40 m, free line - this is our adapted Trailblazer: start gate -> finish gate with a countdown, stars on time left), `Loop` (laps; stretch).
- Start flow: drive into the start arch -> prompt "PRESS [E] TO START: <Name>  <km>" (1 s hold optional). Car is placed on the start line (if > 15 m off, snap with fade 0.4 s), input locked 3.0 s for the countdown "3, 2, 1, GO!".
- Checkpoints: `n = clamp(round(L/600), 6, 20)`. Gate `HalfWidth = roadHalfWidth + 3 m` (road) or 18 m (cross-country). Pass in order; a pass requires the plane crossing within `1.5 * HalfWidth`. If the player's progress passes the next gate by > 60 m without crossing: "MISSED CHECKPOINT" banner and a GPS arrow; 3.0 s penalty if the gate is then passed from the correct side after turning back (or auto-accept after 6 s and 8.0 s penalty - pick the simpler in code).
- `RoadRace` countdown mode: start clock `T0 = 1.15 * T_profile(first segment) + 10 s`; each checkpoint adds `bonus_i = 0.85 * (L_i / v_profile_i) + 2.0 s` (tight enough that a clean run gains a little, a sloppy one bleeds). Running out of time = "TIME UP" (event fails, restart prompt). Final result = elapsed time -> medal via 4.6 multipliers.
- `DirtSprint` (Trailblazer-style): single allowance `A = 1.25 * T_profile` with NO checkpoint bonuses; stars = seconds left at the finish gate: finish = 1 star, `>= 0.5*T3` = 2 stars, `>= T3` = 3 stars with `T3 = 0.12 * T_profile` (a 6 km sprint at 90 km/h profile = 240 s -> T3 = 29 s; FH5 uses 15-35 s left for 3 stars [F]). Gates still exist for ordering/UI.
- Position/rank mode (stretch, needs AI): AI uses the route speed profile x difficulty factor 0.80/0.90/0.97/1.03 (Easy/Medium/Hard/Expert) with rubber-banding `k = clamp(1 + gap_m/1500, 0.94, 1.06)` toward the player's gap; payout credit multiplier 1.0/1.15/1.3/1.5 (FH5 pays more credits at harder settings [S]). Positions shown as "3rd / 6". No collision-driven rewind in v1.
- Respawn/rewind: `respawn` or flip -> place at last passed checkpoint (or last road sample), facing route, speed 0; penalty +3.0 s in countdown mode (time deducted), none in free roam.
- Result card: finishing time, best time, medal (bronze/silver/gold per 4.6 multipliers), position if any, XP.
- Cross-country pitfall: gates in open terrain need a visible beam (vertical light column 60 m high, bloom) and compass arrow; with no road to follow, the route polyline is only for UI (distance to next gate) and AI.

### 4.6 Time trial on a 20+ km scenic loop (ADOPT - the flagship activity)
- One closed loop of 20-26 km through every region (valley, climb, switchbacks, coast, bridge, tunnel). Start/finish arch at the first straight. Rolling start: crossing the arch from the correct side starts the clock, no countdown, no prompt (consistent with "start by driving through").
- Timing & validity:
  - Clock = `UWorld::GetTimeSeconds` delta (freezes in pause/photo mode).
  - Sectors every ~2 km (`N = round(L/2000)`), gates at route samples, each stores the split. Passing in order only.
  - Skip protection: if `ProgressMax - Progress > 150 m` for > 6 s -> "WRONG WAY"; > 15 s -> lap invalidated. A jump in progress of more than 250 m without passing the intermediate sector ("shortcut / teleport") invalidates the lap.
  - Respawn (flip) puts the car back at the last sector with +10 s penalty; teleport/car switch cancels the lap.
  - Finish: crossing the arch after all sectors passed -> lap complete. Re-arm 500 m later.
- Medals from `T_profile` (3.2) with car-class factor `f_class` (S 1.00, A 1.08, B 1.18, C 1.30, D/vintage/pickup 1.45):
  `Author <= 1.07*Tp*f`, `Gold <= 1.15*Tp*f`, `Silver <= 1.30*Tp*f`, `Bronze <= 1.50*Tp*f`.
  Example: 23.4 km loop with profile average 122 km/h -> Tp = 11:30; Gold (class S) = 13:13, Silver = 14:57, Bronze = 17:15. Calibrate the multipliers after the first AI/bot lap.
- Splits UX: at each sector compare to the personal-best split: green `-2.1` or red `+3.4`.
- Ghost (stretch): record transform at 10 Hz into a compressed array (~24 bytes/sample -> about 170 KB for 12 min), store the best lap per car; playback by interpolation with a translucent non-colliding mesh (same Blender body mesh + wheel meshes, material parameter for opacity). Do not support online leaderboards (FH5 had integrity problems [S]).
- Pitfall: a 12-20 minute run needs a robust "pause = freeze" and a quit-to-resume decision; simply invalidate the lap when the app loses the vehicle for > 5 s.

### 4.7 Collectibles, discoveries, photo spots (ADAPT, small)
- Billboards (adapted bonus boards): breakable wooden boards in three XP tiers 200/500/1000 (scaled-down from FH5's 1,000/3,000/5,000 [F]); count ~40 (28 / 9 / 3). Tier 1 beside the road; tier 2 needs a short detour or a hidden shortcut; tier 3 needs a ramp/hill launch (place near a Danger Sign or natural crest). One-time; stays on the map grey afterward (FH5 behaviour [S]).
  Trigger via segment-vs-OBB test in the subsystem (no overlap volume), requires speed >= 20 km/h; visual break = hide mesh + spawn 2-4 pooled plank physics bodies (lifetime 6 s) + Niagara splinters.
  Discovery pattern: map icon only within 250 m; faint sparkle glint visible to 150 m; optional audio "tick" when within 60 m (the audible cue players reported [S]).
- Barn finds (3, ADAPT): off-road hidden barns, 100-300 m from a track; rumor step replaced by proximity: within 600 m a "?" ring (r = 250 m) appears on the map; drive to the door (12 m) -> banner + patina paint finish unlock + 1,000 XP. Do NOT gate cars behind barn finds (the brief wants all 10 cars selectable).
- Treasure caches (stretch): same as billboards but a map search circle radius 200-300 m instead of a precise marker (FH5 chests [S]).
- Photo spots (8, ADAPT FH5 photo challenges): scenic overlook pins with a target landmark. Completion check on photo-mode capture: player within 60 m of the spot AND landmark centre inside the camera frustum (project with `ProjectWorldLocationToScreen`, 10-90% viewport) AND unoccluded (one line trace) AND car body inside the frame; optional golden-hour requirement (`TimeOfDay` in a range) for 3 of the 8. Reward 250 XP + "PHOTO SPOT 3/8". Data is a landmark point + radius, so no actors required.

---------------------------------------------------------------------------------------------------

## 5. Optional unified skill chain ("Flow chain") (ADAPT, stretch)
FH5's chain is why driving between events stays rewarding. A reduced version, independent of events:

| Skill | Condition | Base points |
|---|---|---|
| Drift | beta >= 12 deg, >= 30 km/h (same detector as 4.3) | `0.5*min(v,140)*min(beta,60)` per s |
| Air | all wheels off ground >= 0.5 s | `150 * airSeconds` (cap 1,500) |
| Near miss | pass traffic within 1.2 m lateral at >= 70 km/h, once per vehicle | 250 |
| Speed | above 150 km/h | `8` per s per 10 km/h above 120 |
| Wreckage | break a billboard/cone/fence | 100 each |

- Multiplier `m = min(5, 1 + number of distinct skill types hit in this chain)` (variety raises it, as in FH5; cap x5 as in the base game). 
- Chain timer 3.0 s since the last scored skill (drift renews it while active); at expiry the chain is banked into `TotalSkillScore`. A hard collision (decel > 7 m/s in 0.2 s) loses the live chain.
- Combo toasts (1.2 s, +bonus 300-800): LUCKY ESCAPE (drift + near miss within 1 s), STUNTMAN (air + near miss), DAREDEVIL (3 near misses in 4 s), KANGAROO (3 airs in 6 s).
- XP = banked points / 100.

---------------------------------------------------------------------------------------------------

## 6. XP and rewards (simple, [X])
FH5 documented payouts: bonus boards 1,000/3,000/5,000 XP, fast-travel boards -200 credits each from 10,000 [F]; PR stunts in seasons pay festival points (not XP) [F]. Ours:

| Source | Formula |
|---|---|
| PR stunt (trap/zone/drift/sign/sprint) | pays only star improvements: `XP[stars_new] - XP[stars_old]` with `XP = {0,100,250,500}`; +50 first clear bonus |
| Race / time trial | `XP = round(km * 80 * medalMult)`, medalMult bronze 1.0, silver 1.25, gold 1.5, author 1.75; credits = XP x 2 |
| Billboard / barn / photo | 200 / 500 / 1000 ; 1,000 ; 250 |
| Skill chain | banked points / 100 |
Anti-farming: repeating the same star count pays 0; "NEW BEST" is still shown. Credits/XP are a stretch goal (economy is optional in the brief) - still compute and show XP; store `TotalXp`.

---------------------------------------------------------------------------------------------------

## 7. HUD notification spec (all [X]; FH5 text/timings were not available)

Channel layout (1080p reference, scale with DPI):
- TOAST: top-centre under the compass, 520x64 px; fade-in 0.15 s, hold 2.2 s, fade-out 0.15 s (total 2.5 s). 2-deep queue; identical-activity toasts coalesce. Used for discovery, collectibles, combos, sector splits.
- BANNER: upper third (y = 24%), 760x96; slide-in 0.2 s, hold 3.1 s, slide-out 0.2 s (total 3.5 s). Event start/finish and failures (red).
- RESULT CARD: centre, 640x280; slide-up 0.25 s; value count-up 0.6 s ease-out; star 1 at t = 0.9 s, star 2 at 1.25 s, star 3 at 1.6 s (each pops scale 1.4 -> 1.0 in 0.2 s, SFX pitch +2 semitones per star); "NEW BEST" tag at 2.0 s; XP line counts up from 2.3 s over 0.5 s; hold to 5.0 s total, then 0.3 s fade; Enter/A dismisses after 1.0 s.
- LIVE METER: persistent while Active, top-centre (replaces the toast slot), 360x56; updates every frame; 3 star pips light as thresholds are crossed with a 0.1 s flash.
- COUNTDOWN: centre, "3" "2" "1" 1.0 s each (scale 1.6 -> 1.0 each), "GO!" 0.8 s.
Priority: result > banner > toast. Suppress discovery toasts while any timed activity is Active and for 5 min per activity after showing once. Failures never use a result card.

Text (units follow the player setting; `{}` = value):

| Moment | Channel | Text | Duration |
|---|---|---|---|
| Approach (first time within 500 m) | TOAST | `SPEED TRAP  ·  3 STARS AT {V3} km/h` / `SPEED ZONE  ·  AVG {V3} km/h` / `DRIFT ZONE  ·  {S3} PTS` / `DANGER SIGN  ·  {D3} m` | 2.5 s |
| Speed trap result | CARD | `SPEED TRAP` / `{v} km/h` / `BEST {b} km/h` / stars | 5.0 s |
| Speed trap 0 stars | TOAST (red) | `TOO SLOW  ·  {V1} km/h NEEDED` | 2.5 s |
| Zone start | TOAST | `SPEED ZONE  ·  KEEP YOUR AVERAGE UP` | 2.0 s |
| Zone live | METER | `AVG {a} km/h   ★★☆   NEXT {t} km/h`, progress bar L | live |
| Zone result | CARD | `SPEED ZONE` / `AVG {a} km/h` | 5.0 s |
| Zone fail | BANNER (red) | `LEFT THE ROAD` / `WRONG WAY` / `STOPPED` | 2.5 s |
| Drift live | METER | `DRIFT  {chain}  x{m}` + timer ring for the 0.8 s window; `ZONE {zoneScore}` | live |
| Drift result | CARD | `DRIFT ZONE` / `{S} PTS` | 5.0 s |
| Drift chain lost | TOAST (red) | `DRIFT LOST` | 1.5 s |
| Jump armed | TOAST | `DANGER SIGN  ·  FULL THROTTLE` | 2.0 s |
| Jump flight | METER | `DISTANCE {d} m` | live |
| Jump result | CARD | `DANGER SIGN` / `{d} m` | 5.0 s |
| Jump fail | BANNER (red) | `CRASH LANDING` / `FLIPPED` + sub `LAND ON ALL FOUR WHEELS` | 2.5 s |
| NEW BEST | CARD tag | `NEW BEST  +{delta}` (green) | with card |
| Race announce | BANNER | `ROAD RACE  ·  {Name}  {km} km` | 3.5 s |
| Checkpoint | TOAST | `CHECKPOINT {i}/{n}   +{bonus} s` (countdown) or split delta | 1.8 s |
| Missed gate | BANNER (red) | `MISSED CHECKPOINT` | 2.5 s |
| Race result | CARD | `FINISH` / `{mm:ss.t}` / medal | 5.0 s |
| Time trial start | BANNER | `TIME TRIAL  ·  {Name}  {km} km   BEST {mm:ss}` | 3.5 s |
| Sector | TOAST | `SECTOR {i}/{n}   {mm:ss.t}   {±s}` green/red | 2.5 s |
| Time trial result | CARD | `LAP {mm:ss.t}` / medal / best / XP | 5.0 s |
| Billboard | TOAST | `BILLBOARD SMASHED  +{xp} XP   ({c}/{N})` | 2.5 s |
| Barn | BANNER | `BARN FIND  ·  PATINA PAINT UNLOCKED` | 3.5 s |
| Photo spot | TOAST | `PHOTO SPOT  +250 XP   ({c}/{N})` | 2.5 s |
| Combo | TOAST | `LUCKY ESCAPE  +500` | 1.2 s |

Implementation hints: `FActivityNotification { Channel, Text, SubText, Color, Duration, Stars, Value, bNewBest }`. Drive animation from a single `float Age` per entry in the HUD tick (C++ `AHUD::DrawHUD` with Canvas, or Slate); avoid blueprint-authored UMG dependencies because the whole project is generated by code/Python.
Map: icon hover/legend should print the threshold line shown in the "Approach" row (FH5 shows target values on hover [S]); use colour-coded icons by type and a gold ring when 3-starred.

---------------------------------------------------------------------------------------------------

## 8. Placement plan for the 4x4 km, 40-60 km network [X]

| Activity | Count | Rule |
|---|---|---|
| Speed trap | 10 | straights with run-up >= 600 m, 1 per ~5 km of road, never in junctions/tunnels |
| Speed zone | 6 | 1-2.5 km single road, vary class (valley 3, mountain 1, coastal 2) |
| Drift zone | 5 | mountain switchbacks and valley S-bends, 350-1,500 m |
| Danger sign | 5 | off-road jump pads next to a road (so the ramp is reachable by a turn-off), 40-250 m 3-star |
| Dirt sprint / road race | 6 | 3-12 km, at least one cross-country and one gravel |
| Time trial | 1 (+1 short 4 km) | the 20+ km loop |
| Billboards | 40 | 28/9/3 tiers |
| Barn finds | 3 | hidden, off-road |
| Photo spots | 8 | overlooks |
Total about 80 discoverable items; stars: 10+6+5+5+6 = 32 stunts x 3 = 96 stars.
Spacing: any two gates >= 300 m apart (no overlapping banners); none within 200 m of a village centre; none in tunnels; avoid steep roads for traps/zones (grade <= 6%). Register the same ids in the console `tp <poi>` list and on the minimap.

---------------------------------------------------------------------------------------------------

## 9. Verification plan (agent can self-test without driving)
1. `act.tp <id> <kmh>` teleports the car 450 m before the gate and sets velocity; check log lines `Activity <id> result=<value> stars=<n>`.
2. Table tests for each activity at thresholds minus/plus 1 unit (V1-1, V1, V2, V3, V3+10).
3. Negative cases: reverse through a gate, `tp` mid-zone (must cancel), car switch mid-sprint, flip on landing, tree hit on landing, photo mode pause for 30 s (timer must not advance), speed trap airborne.
4. Save/load: complete an activity, quit PIE, restart, confirm records and Collected set; delete the save file -> clean defaults.
5. Performance: `stat game` with the subsystem tick under 0.05 ms when idle; no per-actor tick on props.
6. Log all failures to `LogActivities` (category defined in the module).

---------------------------------------------------------------------------------------------------

## 10. Decisions summary
| Feature | Decision | One-line reason |
|---|---|---|
| Speed traps | ADOPT | simple gate-plane test, great video payoff, star ratios derived from FH5 data |
| Speed zones | ADOPT | L/T average with gates; reuses route speed profile |
| Drift zones | ADAPT | FH5 formula unpublished; own angle x speed x chain-multiplier model, calibrated against FH5 point ranges |
| Danger signs | ADAPT | need hand-engineered ramps+landing pads; distances scaled to 40-250 m |
| Trailblazers | ADAPT | folded into the dirt/cross-country countdown sprint |
| Checkpoint races (road/dirt/cross-country) | ADAPT | solo countdown + checkpoints first, AI position racing only as stretch |
| Time trial / Rivals ghosts | ADAPT | one 20+ km loop with sector splits and a local-only ghost; no online boards |
| Bonus boards | ADAPT | 40 billboards in 3 tiers, subsystem-tested |
| Barn finds | ADAPT | 3 hidden barns, cosmetic reward (cars stay unlocked) |
| Treasure chests | ADAPT | stretch: reuse billboards with a search circle |
| Photo challenges | ADAPT | photo spots validated by frustum + trace on capture |
| Skill chain / combos | ADAPT | reduced Flow chain, stretch |
| Outposts/expedition gating, festival playlist, seasonal rotation | SKIP | no campaign, one session |
| Fast-travel discount boards | SKIP | no fast travel economy; use `tp` console |
| Showcase events, Horizon Arcade, EventLab | SKIP | multiplayer/UGC/spectacle scope |
| Car-class restricted stunts (Hot Wheels Park) | SKIP | not needed with 10 free cars |
| Drivatar/online leaderboards | SKIP | local bests only |

## 11. Pitfalls and open questions
- Source disagreement: FH5 board counts (250 vs 255 vs 200 in Mexico), barn finds (14 vs 15), skill chain caps (x5 vs x8) - mechanic confirmed, numbers unreliable. No source for FH5 HUD strings/timings or XP-per-star.
- guides4gamers gives 3 tiers; mapmaster lists only 3-star values; thresholds were converted from mph/ft by me only where marked [D].
- Chaos Vehicles is an experimental plugin in this 5.8 install and is not enabled in the .uproject yet.
- `UTickableWorldSubsystem` needs `GetStatId`; forgetting it is a compile error.
- Drift detection depends on handling; confirm drift-capable cars exist before promising drift zones.
- Ramps are physics-fragile: validate them with `act.tp` runs for the lowest and highest car before shipping a sign.
- Gravity scale changes (arcade feel) alter jump ranges; recompute D3 from the actual scene gravity if you change it.
- Open: whether the garage adds a car change at the start gate of races (decide in the vehicle/garage task); whether traffic suppression API exists (agree on `OnActivityActive`).

## Sources actually used
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Speed%20Trap
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Speed%20Zone
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Drift%20Zone
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Danger%20Sign
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Trailblazer
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/XP%20Board
- https://mapmaster.io/games/forza-horizon-5-playstation/guides/Fast%20Travel%20Board
- https://guides4gamers.com/forza-horizon-5/pois/speed-traps/
- https://guides4gamers.com/forza-horizon-5/pois/speed-zones/
- https://guides4gamers.com/forza-horizon-5/pois/drift-zones/
- https://guides4gamers.com/forza-horizon-5/pois/danger-signs/
- https://www.gtplanet.net/forza-horizon-5-season-change-20220310/
- https://forza.net/news/forza-horizon-5-first-drive
- https://forza.net/news/forza-horizon-5-high-performance
- https://forza.net/news/forza-horizon-5-Community-Choice
- https://insider-gaming.com/every-skill-in-forza-horizon-5-how-to-earn-an-ultimate-skill-chain/
- https://gamerant.com/forza-horizon-5-get-skill-points-how-car-mastery-perks/
- https://www.inverse.com/gaming/forza-horizon-5-best-skill-point-cars
- https://steamcommunity.com/app/1551360/discussions/0/3181237058698815348
- https://www.dexerto.com/gaming/forza-horizon-5-barn-finds-explained-everything-you-need-to-know-1680127/
- https://racinggames.gg/forza/forza-horizon-5-treasure-map-guide
- https://en.wikipedia.org/wiki/Forza_Horizon_5
- Search-result summaries only (not fully read): racinggames.gg (PR stunt/bonus board/photo challenge/difficulty articles), techraptor.net race-types and bonus-boards guides (HTTP 403 on fetch), ludo.guide Rivals, gfinityesports photo challenges, quartertothree thread, gamesradar car mastery.
- Epic docs (via search): https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/ChaosVehicles/UChaosVehicleMovementComponent , https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/ChaosVehicles/FVehicleState , https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UGameplayStatics/SaveGameToSlot , https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UWorldSubsystem , https://dev.epicgames.com/documentation/unreal-engine/saving-and-loading-your-game-in-unreal-engine
- Local engine source (read-only): `W:\Unreal Engine 5\UE_5.8\Engine\Plugins\Experimental\ChaosVehiclesPlugin\Source\ChaosVehicles\{Public,Private}\ChaosVehicleMovementComponent.{h,cpp}`, `ChaosWheeledVehicleMovementComponent.h`, `ChaosVehiclesPlugin.uplugin`; `Engine\Source\Runtime\Engine\Classes\Components\SplineComponent.h`; `Engine\Source\Runtime\Engine\Public\Subsystems\WorldSubsystem.h`.
