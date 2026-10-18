# FH5 reference: cars, classes, PI, upgrades, tuning, paint, driving assists

Research notes for the original game in this folder (UE 5.8, module `Sonnet55Forza`, 10 Blender-authored cars, 4x4 km world).
Forza Horizon 5 is used ONLY as a structure / mechanics / feature-scope reference. Nothing here is copied; everything is paraphrased.
Date of research: 2026-10-16.

Confidence tags used below:
- [V] read directly in a fetched page, or verified in the local UE 5.8 source (`W:\Unreal Engine 5\UE_5.8\Engine\Plugins\Experimental\ChaosVehiclesPlugin` and `...\Source\Runtime\Experimental\ChaosVehicles`).
- [S] only seen in a web-search result summary (the page itself was blocked, 403/redirect, or truncated). Treat as probable.
- [K] general knowledge, not verified in this session. Treat as a hint.
- Community/fan guides frequently disagree with each other (e.g. tire pressure ranges). Numbers from them are starting points, not truth.

Pages that could not be read (403 / redirect to a generic forum index / paywall truncation): support.forza.net articles, forums.forza.net threads, windowscentral guides, simracingsetup, forza.fandom.com, techraptor, dotesports, gamerjournalist. I did not try to bypass any of that.

---------------------------------------------------------------------------------------------------

## 1. What FH5 actually does (reference, paraphrased)

### 1.1 Car roster structure
- Size: the launch roster was announced in stages (about 426 in the first reveal, then 491+, and a later tally of ~505 regular cars + 18 "Forza Edition" + 5 "Welcome Pack" tuned variants = ~528). More cars arrive via seasonal playlists. [S: pcgamer, racinggames.gg]
- The official confirmed-car list is a flat list sorted alphabetically by manufacturer (Acura ... Zenvo), each row = model year + maker + model; within a maker, cars run oldest to newest. [V: forza.net confirmed-car-list]
- Eras covered: 1920s-30s classics, post-war and 60s-70s muscle, 80s-90s rally/performance, 2000s-2010s Japanese performance, current hypercars and EVs. Body/role groupings visible in the list: sedans, sports cars, hypercars, trucks/SUVs/off-road (Bronco, Wrangler, trophy trucks), drift builds, rally-raid, gymkhana. [V]
- Every car has a rarity tier (Common / Rare / Epic / Legendary). The tier mostly drives Wheelspin drop odds and collection value, not performance. [S] A "Car Collection" screen tracks owned cars per manufacturer and pays rewards at set counts. [V]
- Per-car stat row used by community tables: Year, Maker, Model, Rarity, Value (credits), SPD, HDL, ACC, LAU, BRK, OFF, PI. [S]
- Special variants: 13 "Forza Edition" cars (bold in the list), 5 Welcome Pack cars with a preset tune. [V]

### 1.2 Performance classes and PI
Class table (FH-series scale; PI is per-game, not comparable to Motorsport): [S: windowscentral snippet; same table on a fan wiki page, V for that wiki]

| Class | PI range |
|---|---|
| D | 100-500 |
| C | 501-600 |
| B | 601-700 |
| A | 701-800 |
| S1 | 801-900 |
| S2 | 901-998 |
| X | 999 (cap) |

- D is the widest bucket, all others span about 100 points. [S]
- Official definition (older support article, seen only through a search snippet): PI is a single number derived from the best lap time on a synthetic, mathematically generated test track that is meant to represent all tracks of that game; faster lap = higher PI; it does not guarantee equal performance on every route or surface; every game version has its own scale. [S]
- PI is NOT a sum of per-part costs. It is recomputed from the car's resulting performance, which is why swapping a rear wing can lower PI, heavier rims lower PI, and "free" same-weight swaps exist. [V: hackernoon guide]
- Six sub-ratings on a 0.0-10.0 scale: Speed, Handling, Acceleration, Launch, Braking, Offroad (Offroad is the FH5 addition). Example from a community table: a long-tail Le Mans prototype racer at S1/856 shows 8.2 / 5.9 / 7.2 / 7.1 / 4.9 / 4.0. [S: dexerto] Note the stats are relative to the game's roster, not physical units.
- X-class cars are not allowed in online play or Rivals (one guide). [V: hackernoon, single source]
- Event gating: races/activities declare a class (or a PI max); players bring a car of that class. [K]

### 1.3 Upgrade structure (the garage "Upgrade & Tuning" flow)
Six categories in the custom-upgrade menu: **Conversion, Engine, Platform and Handling, Tires and Rims, Aero and Appearance, Drivetrain**. [V/S: hackernoon, windowscentral, sirusgaming snippets]

| Category | Typical contents |
|---|---|
| Conversion | drivetrain swap (RWD/FWD/AWD), engine swap, aspiration swap, body kit, overlanding kits |
| Engine | intake, exhaust, cams, valves, displacement, pistons, flywheel, oil/cooling, fuel, turbo/supercharger options |
| Platform and Handling | brakes, springs and dampers (street/sport/race/rally/drift/offroad), front and rear anti-roll bars, chassis reinforcement/roll cage, weight reduction |
| Tires and Rims | compound (street / sport / semi-slick / slick / rally / snow / offroad), tire width, rim style and size, track width (spacers) |
| Aero and Appearance | front bumper/splitter, rear wing, side skirts, hood; "adjustable" aero parts make downforce tunable |
| Drivetrain | clutch, transmission (stock/street/sport/race), driveline, differential |

Key mechanics worth copying:
- **Tier ladder per part**: Stock -> Street -> Sport -> Race (some categories add Rally / Drift / Offroad branches).
- **Tuning is gated by parts**: [S, one guide]
  - Race brakes unlock all brake tuning.
  - Race / rally / drift springs-and-dampers unlock alignment, springs and dampers.
  - Race front / rear anti-roll bars unlock each bar separately.
  - Sport transmission unlocks only final drive; any race transmission unlocks all gearing.
  - Installing a differential part unlocks differential tuning.
  - Tire pressure needs no part. Aero tuning needs adjustable aero parts (the guide did not state it explicitly).
  - The tuning UI greys locked rows and shows an "unlock" hint. [V: gamepretty]
- **Auto Upgrade** button: one click raises the car to the next class with a part set chosen by the game; recommended only for beginners. [S]
- **Build order advice (for PI budgeting)**: conversion -> aero -> tires/rims -> drivetrain -> platform/handling -> engine last, because the engine can soak up leftover PI. [V: hackernoon]
- **PI trims**: rims (lighter = more PI, heavier = less), flywheel, driveline, clutch are used as final fine-tuning; intake/exhaust are cheap power; cams and forced induction cost a lot of PI. Brakes, clutch, adjustable aero are good "spare PI" sinks. [V: gamepretty, hackernoon]
- Roll cages/weight reduction: "all in or skip"; a cage adds weight, so add one chassis reinforcement per class step. [V]
- Tire guidance: AWD benefits less from compound; RWD/FWD benefit from one compound step; slicks hurt road racing less than they hurt loose-surface racing but are rarely worth the PI; wider front tires reduce understeer, wider rears add grip. [V]
- Drivetrain swaps: RWD can become AWD; FWD can become AWD or RWD; AWD can become RWD or FWD. [V]

### 1.4 Tuning screens (FH5 groups and what they do)
Groups and settings (names as players know them):

| Group | Settings (front/rear where it applies) | What it does |
|---|---|---|
| Tires | pressure F/R | grip vs. heat vs. response; higher = sharper but less grip, lower = more grip/heat; off-road tires want far lower pressure |
| Gearing | final drive, each gear ratio, gear graph | stretch or squeeze the powerband; final drive scales all gears together |
| Alignment | camber F/R, toe F/R, caster (front) | camber = cornering grip vs. straight-line grip and tire temp; toe-out = turn-in, toe-in = stability; caster = stability vs. steering effort and camber gain |
| Anti-roll bars | F/R stiffness | roll stiffness distribution; stiffer front = more understeer, stiffer rear = more oversteer |
| Springs | spring rate F/R, ride height F/R | weight transfer, body motion; heavier end needs stiffer springs |
| Damping | rebound F/R, bump F/R | how fast the spring moves; bump ~50-70% of rebound is the rule of thumb |
| Aero | front downforce, rear downforce | grip at speed vs. drag |
| Brakes | balance, pressure | brake bias (FH shows it as a front/rear slider; one guide notes the displayed direction is counter-intuitive), overall force |
| Differential | accel and decel lock (front/rear), center balance (AWD) | power distribution across axles and between wheels; drift builds go to high lock |

Rules of thumb from guides (conflicting, take as starting points):
- Tire pressure: 26-35 psi common for road, front a few psi above rear [V gamepretty]; 30-34 [V hackernoon]; another guide says 20-25 road, 10-15 rally, <10 cross-country, drift front 25-30 / rear minimum [V diamondlobby]. Lesson: pressure is surface dependent, defaults must be per car, don't hard-code one optimum.
- Camber: negative on road, stock/race values often too aggressive. Toe: tiny values only (about 0.1 degree steps). Caster: about 4-7 degrees. [V]
- Springs/ARBs: halfway between soft and stiff for road; AWD/FWD: soften front, stiffen rear; RWD leave mostly alone. [V]
- Damping: rebound near stock, bump about half to 70% of rebound. [V]
- Ride height: as low as possible without bottoming; rally 1-2 inches higher. [V]
- Brakes: one build uses ~55% balance / ~105% pressure; drift wants fully front-biased. [V]
- Differential: RWD rear accel ~50-90 (60 typical road), decel 0-20; AWD center ~70-75% rear for road, ~70-80% for drag; drift both max. [V]
- Telemetry targets: suspension travel stays within about 20-80% of range; tire inner/outer temps within roughly 10-15 F of each other, never more than ~20 F. [V]
- Community "Quick Tune" / shared tunes exist for beginners. [S]

### 1.5 Paint, finish, livery
- Paint menu offers Normal colors, Manufacturer colors and Special colors; special groups include single tone, two-tone, iridescent, carbon, metal, camo, wood. [S: forza forums via search]
- Finish types discussed by players: gloss, matte, metallic flake, pearl/iridescent, chrome (location of chrome in the FH5 menu not confirmed). [S]
- Livery editor is layer based (vinyl shapes, decals, group saving). A single global "vinyl material" slider switches vinyls between matte and gloss; it is global, not per layer. Vinyls themselves cannot be metallic/pearl directly; players mask chrome-like textures. Large saved vinyl-group libraries load slowly. No official layer cap found. [S]
- Wheels/rims have their own style + color; rim weight is also a PI trim. [K for paint, V for weight]

### 1.6 Difficulty and driving assists
Settings submenu structure in FH5 (Accessibility shortcut on the start screen -> Difficulty, and a separate HUD and Gameplay submenu). Items are dropdowns, toggles and sliders. [V: caniplaythat deep dive]

| Setting | Options | Notes |
|---|---|---|
| Drivatar difficulty | tiered from "Tourist" (easiest) up to hardest ("Unbeatable" in some guides) | AI strength; names vary by source [S] |
| Driving assists preset | named presets that fill in the individual items below | official older article lists six presets Super Easy / Easy / Medium / Hard / Professional / Veteran [S] |
| Braking | auto-braking vs. manual; older article: Assisted / ABS On / ABS Off | |
| Steering | assisted vs. manual; older article: Super Easy / Assisted / Normal / Simulation | |
| Traction control | on/off (older: Super Easy / On / Off) | cuts power to prevent wheelspin |
| Stability control | on/off (older: Super Easy / On / Off) | limits slides/spin in corners |
| Shifting | automatic / manual (the clutch variant exists in the game [K]) | |
| Driving line | off / always (full) / braking only | suggested racing line drawn on the road |
| Damage and tire wear | cosmetic vs. simulation | |
| Rewind | enabled / disabled | optional, on by default |

- Higher difficulty = bonus credits. The menu shows the multiplier. Example from a tips article: recommended assists + Average Drivatar gave +25% credits; TC off raised it to +35%; manual shifting reached +50%. [S: gamesradar]
- HUD and Gameplay submenu: speedometer analog/digital, units SI/US, camera view, cockpit camera options, toggles for minimap, skill/score popups, lap time and position, wrong-way warning, name tags. [V]
- Game speed slider for accessibility (offline only; physics preserved). [S]

---------------------------------------------------------------------------------------------------

## 2. What UE 5.8 Chaos Vehicles gives us (verified in local engine source)

Paths: `Engine\Plugins\Experimental\ChaosVehiclesPlugin\Source\ChaosVehicles\Public\ChaosWheeledVehicleMovementComponent.h`, `ChaosVehicleMovementComponent.h`, `ChaosVehicleWheel.h`, core in `Engine\Source\Runtime\Experimental\ChaosVehicles\ChaosVehiclesCore`.

Facts [V]:
1. The plugin is "Experimental" and `EnabledByDefault: false`. The project `.uproject` does not list it yet -> add `{"Name":"ChaosVehiclesPlugin","Enabled":true}` and add `"ChaosVehicles"` to `PublicDependencyModuleNames` in `Sonnet55Forza.Build.cs`. (Epic's setup page says PhysX must stay disabled; leave the physics engine setting at its Chaos default.)
2. Classes: `AWheeledVehiclePawn`, `UChaosWheeledVehicleMovementComponent`, `UChaosVehicleWheel` (per-wheel config), `UVehicleAnimationInstance` (anim BP base with Wheel Controller node), `FWheelStatus` (per-wheel runtime state incl. `PhysMaterial`, `bABSActivated`, `SlipAngle`, `bIsSlipping`, `DriveTorque`, `BrakeTorque`, `NormalizedSuspensionLength`).
3. Engine: `FVehicleEngineConfig` = `TorqueCurve` (RPM -> torque, normalized by its own max), `MaxTorque` (Nm), `MaxRPM`, `EngineIdleRPM`, `EngineBrakeEffect`, `EngineRevUpMOI`, `EngineRevDownRate`. Curve is sampled at 20 points between 0 and MaxRPM. Defaults are tiny (MaxTorque 300, MaxRPM 4500) - always override.
4. Transmission: `FVehicleTransmissionConfig` = `bUseAutomaticGears`, `bUseAutoReverse`, `FinalRatio` (3.08), `ForwardGearRatios[]`, `ReverseGearRatios[]`, `ChangeUpRPM`, `ChangeDownRPM`, `GearChangeTime`, `TransmissionEfficiency`. Auto shifting is purely RPM-threshold based. Runtime: `SetUseAutomaticGears`, `SetTargetGear`, `SetChangeUpInput/SetChangeDownInput`, `GetCurrentGear`, `GetForwardSpeedMPH`.
5. Differential: only the drive layout enum `EVehicleDifferential { Undefined, AllWheelDrive, FrontWheelDrive, RearWheelDrive }` plus `FrontRearSplit` (0..1, 4WD only, `SetDifferentialFrontRearSplit` at runtime). There is NO LSD, no accel/decel lock, no preload.
6. Steering: `FVehicleSteeringConfig` = `SteeringType` (SingleAngle / AngleRatio / Ackermann), `AngleRatio`, `SteeringCurve` whose X axis is forward speed in **MPH** (not km/h). Input shaping via `FVehicleInputRateConfig` (RiseRate, FallRate, InputCurveFunction) for throttle/brake/steering.
7. Per wheel (`UChaosVehicleWheel`): `WheelRadius`, `WheelWidth`, `WheelMass`, `CorneringStiffness`, `FrictionForceMultiplier`, `SideSlipModifier` (0..1 grip kept while skidding), `SlipThreshold`, `SkidThreshold`, `LateralSlipGraph` (curve), `MaxSteerAngle`, `bAffectedBySteering/Brake/Handbrake/Engine`, `bABSEnabled`, `bTractionControlEnabled`, `MaxWheelspinRotation`, `MaxBrakeTorque`, `MaxHandBrakeTorque`, suspension: `SuspensionAxis`, `SuspensionMaxRaise`, `SuspensionMaxDrop`, `SpringRate` (default 250), `SpringPreload`, `SuspensionDampingRatio` (0..1, default 0.5, ONE value - no bump/rebound split), `WheelLoadRatio`, `RollbarScaling` (anti-roll effect 0..1, default 0.15), `SuspensionSmoothing` (0..10).
8. Vehicle level (`UChaosVehicleMovementComponent`): `Mass` (default 1500), `bEnableCenterOfMassOverride/CenterOfMassOverride`, `ChassisWidth` (cm, 180), `ChassisHeight` (cm, 140), `DragCoefficient` (0.3), `DownforceCoefficient` (0.3), `InertiaTensorScale`, optional arcade helpers (`TorqueControl`, `TargetRotationControl`, `StabilizeControl`).
   Aero formula in `AerodynamicsSystem.h`: drag = 0.5 * Area * Cd * rho * v^2, downforce = 0.5 * Area * Cl * rho * v^2, Area = ChassisWidth * ChassisHeight. So CdA_target = Cd * Area; to hit a data-driven CdA in m^2, set `Cd = CdA / (W_m * H_m)`. Downforce is ONE lump for the whole car (no front/rear split).
9. Surface grip: the sim reads `UPhysicalMaterial::Friction` from the hit under each wheel and multiplies by the wheel friction multiplier. Surfaces (asphalt/dirt/gravel/grass/sand/wet) = physical materials with different Friction. `GetWheelState(i).PhysMaterial` tells you what each wheel is on (use it for HUD surface icon, tire squeal, dust).
10. ABS / TC are crude on/off flags per wheel. In `WheelSystem.cpp` they clamp the applied brake (ABS) or drive (TC) force to "available grip * 0.98" - an idealised controller. So ABS On braking is very efficient; ABS Off must be modelled as the wheel really locking (it does). `FWheelStatus.bABSActivated` is exposed for a HUD flash; there is no equivalent exposed flag for TC.
11. There is NO stability control, NO camber/toe/caster, NO tire pressure/temperature/wear, NO per-axle downforce, NO bump/rebound split, NO LSD in Chaos. Everything below that is "project-owned" must be written in C++ on top.
12. Runtime setters available (all `BlueprintCallable`, execute on the physics thread safely): `SetMaxEngineTorque`, `SetDragCoefficient`, `SetDownforceCoefficient`, `SetDifferentialFrontRearSplit`, `SetTractionControlEnabled(i)`, `SetABSEnabled(i)`, `SetAffectedByBrake/Handbrake/Steering/Engine(i)`, `SetWheelRadius`, `SetWheelFrictionMultiplier`, `SetWheelSlipGraphMultiplier`, `SetWheelMaxBrakeTorque`, `SetWheelHandbrakeTorque`, `SetWheelMaxSteerAngle`, `SetTorqueCombineMethod(i)`, `SetDriveTorque(i)`, `SetBrakeTorque(i)`, `SetSuspensionParams(Rate, Damping, Preload, MaxRaise, MaxDrop, i)`.
13. **Pitfall - config baked at physics-state creation**: `SetupVehicle()` builds engine, transmission, differential and steering sims from `EngineSetup`, `TransmissionSetup`, `DifferentialSetup`, `SteeringSetup` on the component, and builds wheels from `WheelSetups[i].WheelClass->GetDefaultObject()`. There is no public "reload transmission" call. Consequences:
    - Changing gear ratios, final drive, torque curve, redline, differential layout, steering config -> set the properties on the component and call `RecreatePhysicsState()` (cheap while the car sits in the garage), or destroy and respawn the pawn. Do it when leaving the tuning menu, never per frame.
    - Per-car wheel values (grip, spring, damping, brake torque) should be applied with the runtime setters after spawn, because the wheel class CDO is shared by every car using that class.
    - Spawn with deferred construction (`SpawnActorDeferred`), call `ApplyCarSpec()` to fill the component, then `FinishSpawning`.
14. Snapshot API: `GetSnapshot()` / `SetSnapshot(FWheeledSnaphotData)` stores transform, linear/angular velocity, selected gear, engine RPM, wheel snapshots -> the natural basis for **Rewind**.
15. Unit warnings: UE units are cm; `SpringRate` is an engine-specific scale (tooltip says N/m, the default 250 behaves like a soft ~N/cm value). Derive stock rate empirically: pick desired static sag (about 6-9 cm for road cars) and tune `SpringRate` until measured sag matches, then store the number in car data; do not trust a textbook N/m number. [verify with a test in the editor]

---------------------------------------------------------------------------------------------------

## 3. Proposed data-driven design for this project

Design goals: one source of truth per concept; the same pipeline drives physics, UI stat bars, PI/class, save files; everything balanced via data (no recompile); everything can be generated by code (no hand-authored editor assets needed).

### 3.1 Asset layout
- `UCarData : UPrimaryDataAsset` - 10 instances, PrimaryAssetType `Car`, id = `CarId`. (Code-generated at startup if missing, or created with a Python/editor-utility script. Primary type lets the Asset Manager list them for the garage.)
- `UCarRulesData : UPrimaryDataAsset` - ONE instance: PI weights, normalisation ranges, class thresholds, assist bonuses. Change balance without recompiling.
- `UDataTable` with row struct `FCarUpgradeRow : FTableRowBase` - one CSV (about 40 rows) imported once; easiest to generate and diff.
- `UDataTable` `FPaintFinishRow` (3 rows) and `FRimStyleRow`.
- `UGarageSaveGame : USaveGame` - `TMap<FName, FCarBuild> Builds`, `FName CurrentCar`, `FAssistSettings Assists`.
- Runtime: `AGarageVehicle : AWheeledVehiclePawn` (one C++ class for all cars; loads mesh, anim BP, wheel bones from `UCarData`; Blender naming convention is already `Body`, `Wheel_FL/FR/RL/RR` in the master prompt).

### 3.2 Enums and small structs (C++ sketch)
```cpp
UENUM(BlueprintType) enum class ECarClass : uint8 { D, C, B, A, S1, S2, X };
UENUM(BlueprintType) enum class EDrivetrain : uint8 { FWD, RWD, AWD };
UENUM(BlueprintType) enum class ECarBody : uint8 { HotHatch, Sedan, Muscle, Coupe, GrandTourer, Supercar, Rally, OffroadSUV, Pickup, Roadster };
UENUM(BlueprintType) enum class ECarRarity : uint8 { Common, Rare, Epic, Legendary };   // display only
UENUM(BlueprintType) enum class EUpgradeCategory : uint8 { Conversion, Engine, PlatformHandling, TiresRims, AeroAppearance, Drivetrain };
UENUM(BlueprintType) enum class EPaintFinish : uint8 { Gloss, Matte, Metallic };
UENUM(BlueprintType) enum class ESurface : uint8 { Asphalt, Dirt, Gravel, Grass, Sand, Wet };
```
Tuning-unlock tags as `FGameplayTag`-free `FName`s: `Tune.Tires`, `Tune.FinalDrive`, `Tune.Gearing`, `Tune.Alignment`, `Tune.Springs`, `Tune.Damping`, `Tune.ARB`, `Tune.Aero`, `Tune.Brakes`, `Tune.Diff`.

### 3.3 Car data asset (stock spec)
```cpp
USTRUCT(BlueprintType) struct FCarSpec            // the *effective* physical spec; stock spec lives in UCarData, upgrades/tuning produce a derived copy
{
  // identity of drivetrain
  EDrivetrain Drivetrain;
  // mass / geometry
  float MassKg, WheelbaseCm, TrackFrontCm, TrackRearCm, CgHeightCm; FVector CenterOfMassCm;
  float ChassisWidthCm, ChassisHeightCm;                 // used for aero area
  float CdA_m2, ClA_FrontM2, ClA_RearM2;                 // drag area, downforce area (m^2)
  // engine
  TObjectPtr<UCurveFloat> TorqueCurve;                   // x = rpm, y = Nm (un-normalised is fine)
  float PeakPowerKw;                                     // optional; used to derive MaxTorque
  float MaxTorqueNm, RedlineRpm, IdleRpm, EngineBrake, RevUpMOI, RevDownRate;
  // gearbox
  TArray<float> ForwardRatios; float FinalDrive; TArray<float> ReverseRatios;
  float ShiftTimeSec, ChangeUpRpm, ChangeDownRpm, DriveEfficiency;
  float DiffAccelLock01, DiffDecelLock01, CenterSplitRear01;   // AWD only for split
  // tires (per axle)
  float WheelRadiusCm[2], WheelWidthCm[2], WheelMassKg[2];
  float GripMu[2];                                       // peak friction on asphalt
  float LooseSurfaceMul[2];                              // grip fraction kept on dirt/gravel/sand (0.55 street .. 0.95 offroad)
  float CorneringStiffness[2];
  // suspension (per axle)
  float SpringRate[2], DampingRatio[2], RollbarScaling[2], TravelRaiseCm[2], TravelDropCm[2], RideHeightCm, SuspensionQuality; // quality 0.8..1.1 (body-roll proxy used by the PI estimator)
  // brakes
  float BrakeG;                                          // peak braking capacity in g; wheel torque derived from it
  float BrakeBiasFront01;
  // steering
  float MaxSteerDeg; FRichCurve SteeringVsSpeedMph;      // x axis in MPH because Chaos wants MPH
};

UCLASS(BlueprintType) class UCarData : public UPrimaryDataAsset
{
  FName CarId; FText DisplayName; FString FictionalMaker; int32 Year;
  ECarBody Body; ECarRarity Rarity; int32 PriceCr;
  TSoftObjectPtr<USkeletalMesh> BodyMesh; TSoftClassPtr<UAnimInstance> AnimClass;
  TArray<FName> WheelBones;                              // Wheel_FL, Wheel_FR, Wheel_RL, Wheel_RR
  FCarSpec Stock;
  FTuneRanges TuneRanges;                                // per-setting min/stock/max for this car (see 3.7)
  TArray<FName> AvailableUpgradeIds;                     // which rows of the upgrade table apply (e.g. no AWD swap for the vintage roadster)
  FName EngineSoundProfile;                              // id of the procedural/MetaSound profile
  TArray<FLinearColor> SuggestedPaints;
  ECarClass StockClassHint; int32 StockPIHint;           // debug check only, computed value is authoritative
};
```
Derived (not stored): `FCarPerformance` (measured/estimated metrics), `FCarRatings` (0-10 bars), `PI`, `ECarClass`.

### 3.4 Upgrade definitions (data-table rows)
One installed part per **slot**; a part belongs to a category; stat deltas are *modifiers on the spec*, not on the PI.
```cpp
USTRUCT() struct FCarUpgradeRow : public FTableRowBase
{
  FName UpgradeId;               // "Eng_Sport"
  EUpgradeCategory Category;
  FName Slot;                    // "Engine.Tune", "Platform.Brakes", ... only one per slot
  int32 Tier;                    // 0 stock, 1 street, 2 sport, 3 race
  FText DisplayName; int32 PriceCr; FText Description;
  // modifiers (identity values shown in brackets)
  float MassDeltaKg=0, MassMul=1, WheelMassDeltaKg=0;
  float TorqueMul=1, RedlineDeltaRpm=0, RevUpMOIMul=1, ShiftTimeMul=1, DriveEfficiencyAdd=0;
  float FinalDriveMul=1;
  float GripMul=1, LooseSurfaceMulMul=1, CorneringStiffMul=1;
  float BrakeGMul=1;
  float SpringMul=1, DampingMul=1, RollbarMul=1, TravelMul=1, RideHeightDeltaCm=0, SuspensionQualityAdd=0;
  float CdAMul=1, ClAFrontAdd=0, ClARearAdd=0;
  EDrivetrain DrivetrainOverride;    bool bOverrideDrivetrain=false;
  TArray<FName> UnlocksTuning;       // "Tune.Alignment","Tune.Springs","Tune.Damping"
  TArray<FName> RequiresUpgrades;    // e.g. turbo requires Eng_Sport
  TArray<FName> ConflictsWith;
  FName VisualId;                    // optional: wing mesh / splitter socket
};
```
Evaluation order: start from `Stock` -> apply installed rows in a fixed category order (Conversion, Aero, Tires/Rims, Drivetrain, Platform, Engine - the order FH guides recommend, which also makes drivetrain overrides resolve first) -> apply tuning -> result `FCarSpec Effective`.

**Seed upgrade table (about 14 slots, 38 options).** Values are starting numbers calibrated against the PI prototype in 3.5.

| Slot | Options (tier: effect) | Unlocks tuning |
|---|---|---|
| Conversion.Drivetrain | AWD swap (+60 kg, DrivetrainOverride AWD, drive weight fraction ~0.95); RWD swap (FWD cars) (+25 kg) | `Tune.Diff` center split on AWD |
| Engine.Tune | Street TorqueMul 1.08 / redline +300; Sport 1.18 / +500; Race 1.32 / +800 | - |
| Engine.Induction | Turbo TorqueMul 1.12 (requires Eng Sport, +25 kg, shifts torque peak higher); Supercharger 1.09, flatter curve | - |
| Engine.Flywheel | Sport RevUpMOI x0.8 (-6 kg); Race x0.65 (-10 kg) | - |
| Drivetrain.Transmission | Sport ShiftTime x0.7, efficiency +0.02; Race ShiftTime x0.45, efficiency +0.03 | Sport: `Tune.FinalDrive`; Race: `Tune.FinalDrive` + `Tune.Gearing` |
| Drivetrain.Differential | Sport lock 0.4/0.1; Race 0.7/0.2; Rally 0.5/0.3 split-biased; Drift 0.9/0.9 | `Tune.Diff` |
| Platform.Brakes | Sport BrakeG x1.12; Race x1.30 (+5 kg) | Race: `Tune.Brakes` |
| Platform.Suspension | Sport quality +0.04, SpringMul 1.15; Race quality +0.08, SpringMul 1.35, ride -2 cm; Rally travel x1.6, ride +4 cm, LooseSurfaceMul x1.1 | Race/Rally: `Tune.Alignment`, `Tune.Springs`, `Tune.Damping`, `Tune.RideHeight` |
| Platform.AntiRoll | Race bars RollbarMul 1.5 | `Tune.ARB` |
| Platform.Weight | Sport MassMul 0.97; Race 0.93; Extreme 0.88 (cost rises steeply) | - |
| Tires.Compound | Street GripMul 1.00; Sport 1.06 (Loose x0.9); Semi-slick 1.12 (Loose x0.6); Rally 0.97 (Loose x1.25); Offroad 0.92 (Loose x1.35) | `Tune.Tires` always available |
| Tires.Rims | Sport WheelMass -1.0 kg/wheel; Race -2.0 kg/wheel; cosmetic RimStyleId is free | - |
| Aero.Front | Splitter (adjustable): ClAFront +0.10 | `Tune.AeroFront` |
| Aero.Rear | Wing (adjustable): ClARear +0.20, CdA +0.04; Race wing: +0.45 / +0.09 | `Tune.AeroRear` |

Notes:
- PI is NOT stored per part (see 1.2). Cost effects (e.g. wing lowers a slow car's PI) emerge from the formula.
- "Auto Upgrade to class X": greedy search that adds the best marginal PI-per-credit part until the next class threshold is reached, skipping parts that conflict; cheap to implement because PI evaluation is analytic (3.5).
- Measured PI deltas from the prototype on the stock hot hatch (stock PI 587): engine street/sport/race +14/+26/+40, weight sport/race/extreme +4/+9/+15, tires sport/semi/slick +14/+27/+42, suspension sport/race +7/+15, aero rear wing about -1 (slow car, no benefit), AWD swap about -4 on a car that was not traction-limited. That is the intended FH-like behaviour: tires and engine cost most PI.
- Brakes need their own capacity (`BrakeG`) separate from tire grip, otherwise upgrades do nothing when the tire is the limit. Decel = min(tire grip g + aero, BrakeG).

### 3.5 Performance estimator, stats and PI (concrete formula)
Compute from the *effective spec*, in C++, deterministic, about 1 ms: a fixed-step longitudinal sim + closed-form lateral/braking estimates. (I prototyped this in Python in the scratchpad - `pi_proto.py`; port it as `UCarBuildLibrary::EvaluatePerformance`.)

Constants: rho = 1.2 kg/m^3, g = 9.81, Crr = 0.013, drivetrain efficiency 0.90 (use `DriveEfficiency`), dt = 5 ms, shift pause = `ShiftTimeSec`, upshift at 0.97 * redline.
Engine: torque(rpm) = Tpk * shape(rpm/redline); shape = max(0.35, 1 - 1.35 (x - 0.62)^2) in the prototype; in the game use the car's real `TorqueCurve` normalised so that max(T*omega) = PeakPowerKw.
Longitudinal: F = min( T*gear*final*eff / Rw , mu * (m*g*driveWeightFraction + 0.5*rho*ClA*v^2) ); a = (F - 0.5*rho*CdA*v^2 - Crr*m*g)/m. `driveWeightFraction`: FWD 0.55, RWD 0.50-0.62, AWD 0.95.
Metrics:
- `t60` = time 0-60 km/h, `t100` = time 0-100 km/h, `vmax` = settled speed at 90 s.
- `latG` = mu * suspensionQuality * (m*g + 0.5*rho*ClA*(27.8 m/s)^2) / (m*g)   (lateral grip at 100 km/h).
- `brakeDist` = v^2 / (2 * muBrake * g) from 100 km/h, muBrake = min(mu*1.02, BrakeG) * (1 + 0.5*downforce/(m*g)).
- `offroad01` = LooseSurfaceMul(avg) * (0.6 + 0.4 * travel factor) * (AWD ? 1.1 : 1.0), clamped 0..1 (the prototype uses a hand-set number per car; derive properly later).

Normalisation and ratings (0..10 bars = 10 * norm): norm(x) = clamp((x - a)/(b - a), 0, 1).

| Rating | Metric | a (0 points) | b (10 points) | Weight in PI |
|---|---|---|---|---|
| Speed | vmax km/h | 110 | 360 | 0.22 |
| Handling | latG | 0.55 | 1.70 | 0.26 |
| Acceleration | t100 s | 12.0 | 2.3 | 0.22 |
| Launch | t60 s | 5.0 | 1.4 | 0.07 |
| Braking | brakeDist m | 62 | 26 | 0.13 |
| Offroad | offroad01 | 0 | 1 | 0.10 |

**PI = round( 100 + 899 * Score^0.72 )**, Score = sum(weight * norm), clamped to 100..999. gamma 0.72 lifts the low end so the roster spreads across D..S2 instead of bunching at the bottom. Exposed in `UCarRulesData` (weights, a/b ranges, gamma).

Class thresholds (identical to FH5 so players recognise them; upper bound inclusive):

| Class | D | C | B | A | S1 | S2 | X |
|---|---|---|---|---|---|---|---|
| PI | <=500 | 501-600 | 601-700 | 701-800 | 801-900 | 901-998 | 999 |

Suggested badge colours (own palette, not FH's): D #4FC3F7, C #FFD54F, B #FF9F43, A #FF5C5C, S1 #B36BFF, S2 #3F7BFF, X #3DDC84. Show as a rounded chip "A 743".

Optional: add a **drive-test calibrator** (the master prompt already requires 0-100, top speed, braking and skidpad automated tests). Store the measured numbers next to the estimator output in `DEVELOPMENT.md`; if the physics sim drifts more than about 10% from the estimator, correct via a per-car `GripCalibration` and `PowerCalibration` constant in `UCarData` so UI numbers stay honest.

### 3.6 Seed roster for the 10 cars (prototype output)
Inputs (all fictional, rounded; gears are forward ratios, `final` is the final drive):

| car | mass kg | kW | redline | gears | final | wheel r m | tire mu | drive wt frac | CdA m2 | ClA m2 | susp q | brake mu | offroad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| hot_hatch_FWD | 1200 | 105 | 7000 | 3.6 2.2 1.5 1.12 0.9 0.76 | 4.0 | 0.31 | 1.00 | 0.55 | 0.72 | 0.0 | 1.00 | 1.00 | 0.35 |
| sedan_FWD | 1400 | 105 | 6200 | 3.5 1.95 1.3 0.95 0.75 0.62 | 3.9 | 0.32 | 0.95 | 0.55 | 0.70 | 0.0 | 0.95 | 0.95 | 0.30 |
| muscle_RWD | 1650 | 300 | 6400 | 2.6 1.7 1.3 1.0 0.8 0.65 | 3.55 | 0.34 | 1.00 | 0.60 | 0.78 | 0.0 | 0.92 | 1.00 | 0.20 |
| sports_coupe_RWD | 1330 | 215 | 7400 | 3.6 2.3 1.65 1.28 1.0 0.8 | 3.7 | 0.33 | 1.12 | 0.62 | 0.64 | 0.1 | 1.05 | 1.15 | 0.25 |
| grand_tourer_FR | 1700 | 420 | 6800 | 3.2 2.1 1.5 1.2 1.0 0.8 0.65 | 3.3 | 0.34 | 1.18 | 0.60 | 0.74 | 0.3 | 1.00 | 1.20 | 0.20 |
| supercar_AWD | 1500 | 520 | 8400 | 3.5 2.4 1.8 1.45 1.17 0.95 0.78 | 3.5 | 0.34 | 1.40 | 0.95 | 0.66 | 0.55 | 1.10 | 1.40 | 0.20 |
| rally_AWD | 1250 | 190 | 7000 | 3.5 2.3 1.7 1.3 1.05 0.88 | 4.2 | 0.32 | 1.00 | 0.95 | 0.75 | 0.0 | 1.00 | 1.05 | 0.95 |
| offroad_SUV | 2100 | 200 | 6000 | 3.8 2.2 1.5 1.0 0.8 0.65 | 3.9 | 0.38 | 0.90 | 0.95 | 1.05 | 0.0 | 0.85 | 0.90 | 0.85 |
| pickup_RWD | 2250 | 290 | 5800 | 4.1 2.4 1.5 1.0 0.8 0.65 | 3.7 | 0.38 | 0.90 | 0.50 | 1.15 | 0.0 | 0.82 | 0.90 | 0.55 |
| vintage_roadster_RWD | 950 | 60 | 5600 | 3.3 2.0 1.4 1.0 | 4.1 | 0.30 | 0.80 | 0.55 | 0.62 | 0.0 | 0.90 | 0.75 | 0.20 |

Outputs of the estimator with the PI rules above:

| car | 0-60 s | 0-100 s | vmax km/h | lat g | 100-0 m | PI | class | SPD | HDL | ACC | LAU | BRK | OFF |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| hot_hatch_FWD | 3.67 | 7.81 | 209 | 1.00 | 39.3 | 587 | C | 4.0 | 3.9 | 4.3 | 3.7 | 6.3 | 3.5 |
| sedan_FWD | 4.08 | 8.92 | 205 | 0.90 | 41.4 | 527 | C | 3.8 | 3.1 | 3.2 | 2.5 | 5.7 | 3.0 |
| muscle_RWD | 2.91 | 5.23 | 287 | 0.92 | 39.3 | 674 | B | 7.1 | 3.2 | 7.0 | 5.8 | 6.3 | 2.0 |
| sports_coupe_RWD | 2.50 | 4.74 | 278 | 1.18 | 34.4 | 743 | A | 6.7 | 5.5 | 7.5 | 6.9 | 7.7 | 2.5 |
| grand_tourer_FR | 2.45 | 4.35 | 329 | 1.19 | 32.6 | 785 | A | 8.7 | 5.6 | 7.9 | 7.1 | 8.2 | 2.0 |
| supercar_AWD | 1.34 | 2.54 | 375 | 1.57 | 27.9 | 918 | S2 | 10.0 | 8.8 | 9.8 | 10.0 | 9.5 | 2.0 |
| rally_AWD | 2.19 | 4.49 | 228 | 1.00 | 38.6 | 730 | A | 4.7 | 3.9 | 7.7 | 7.8 | 6.5 | 9.5 |
| offroad_SUV | 3.26 | 7.01 | 224 | 0.77 | 43.7 | 604 | B | 4.6 | 1.9 | 5.1 | 4.8 | 5.1 | 8.5 |
| pickup_RWD | 4.18 | 7.34 | 252 | 0.74 | 43.7 | 573 | C | 5.7 | 1.6 | 4.8 | 2.3 | 5.1 | 5.5 |
| vintage_roadster_RWD | 4.63 | 10.29 | 154 | 0.72 | 52.4 | 360 | D | 1.8 | 1.5 | 1.8 | 1.0 | 2.7 | 2.0 |

Caveats: this is an unvalidated seed. Supercar vmax 375 is higher than a realistic ~340; raise its CdA or lower its kW once real physics numbers exist. S1 is empty on purpose: upgrades should carry the GT (785) and coupe (743) into S1, and the supercar toward X (999) only with a full race build. The SUV/pickup lack the low-end performance of the others so they land in B/C via the Offroad weight, which is exactly the FH5 "Offroad rating" purpose.

### 3.7 Reduced tuning set
Stored as actual values (not 0..1) in the save, clamped to a per-car `FTuneRange {Min, Stock, Max}`; the stock value is the default; sliders in the UI are stepped (e.g. 0.1 deg, 0.5 psi). Tuning rows are *hidden or greyed* until the unlock tag is present (1.3).

| Group | Setting | Unit | Min | Default (typical) | Max | Unlock tag | Mapping onto Chaos / project code |
|---|---|---|---|---|---|---|---|
| Tires | Pressure front | psi | 22 | 32 | 42 | always | wheel `FrictionForceMultiplier` *= `1 - 0.0012*(p - pOpt)^2` (floor 0.88); `CorneringStiffness` *= `1 + 0.012*(p - pOpt)`; pOpt is per surface (asphalt 31, gravel 24, sand 18); re-evaluate when the wheel's `PhysMaterial` changes |
| Tires | Pressure rear | psi | 22 | 31 | 42 | always | same |
| Gearing | Final drive | ratio mult | 0.80 | 1.00 | 1.25 | `Tune.FinalDrive` | `TransmissionSetup.FinalRatio = stock * mult` then `RecreatePhysicsState()` |
| Gearing | Gear spacing | -1..1 | -1 | 0 | 1 | `Tune.Gearing` | re-space `ForwardGearRatios` geometrically between 1st and top, keep 1st and top fixed; recreate |
| Alignment | Camber front | deg | -4.0 | -1.2 | +1.0 | `Tune.Alignment` | cosmetic wheel roll (anim BP) + grip scalar `f(c) = 1 - 0.0085*(c - cOpt)^2`, cOpt about -2.5 front / -1.8 rear, normalised to f(stock); straight-line (brake/accel) grip *= `1 - 0.01*abs(c)` |
| Alignment | Camber rear | deg | -3.5 | -0.8 | +1.0 | `Tune.Alignment` | same |
| Alignment | Toe front | deg | -1.0 (out) | 0.0 | +1.0 (in) | `Tune.Alignment` | steering response gain `1 + 0.18*toeOut`, high-speed yaw stability `1 - 0.15*toeOut` (scales `SteeringCurve` and a small yaw-damping torque) |
| Alignment | Toe rear | deg | -1.0 | +0.1 | +1.0 | `Tune.Alignment` | rear `SideSlipModifier` += `0.1*toeIn` (toe-in = stable, toe-out = loose) |
| ARB | Front / Rear | index 0-100 | 0 | 30 | 100 | `Tune.ARB` | per-wheel `RollbarScaling = lerp(0.03, 0.45, idx/100)` |
| Springs | Front / Rear rate | x stock | 0.6 | 1.0 | 1.5 | `Tune.Springs` | `SetSuspensionParams(Rate, ...)` |
| Springs | Ride height | cm vs stock | -3 (-0 on rally) | 0 | +3 (+6 rally) | `Tune.RideHeight` | shift `SuspensionMaxDrop`/`MaxRaise` + `CenterOfMassOverride.Z`; optionally offset body in anim BP; lower = lower CG (more `latG`) but less landing clearance (bottoming) |
| Damping | Front / Rear | x stock | 0.6 | 1.0 | 1.5 | `Tune.Damping` | `SuspensionDampingRatio` (single value; do NOT build separate bump/rebound UI - Chaos has none) |
| Aero | Front / Rear downforce | 0..1 of installed | 0 | 1 | 1 | `Tune.AeroFront/Rear` | own force: `F = 0.5*rho*(ClA_axle*level)*v^2` applied with `AddForceAtLocation` at each axle; drag scales by `1 + 0.25*level_total`. Do not use the single lump `DownforceCoefficient` when axle balance matters |
| Brakes | Balance (front %) | % | 40 | stock (52-58) | 70 | `Tune.Brakes` | per-wheel `SetWheelMaxBrakeTorque`: total = `m*g*R*BrakeG*pressure`; front = total*bias/2 each axle wheel, rear = total*(1-bias)/2 |
| Brakes | Pressure | % | 70 | 100 | 130 | `Tune.Brakes` | same |
| Differential | Accel lock (RWD/FWD driven axle) | 0-100 | 0 | stock | 100 | `Tune.Diff` | MVP: modifies a stability/understeer scalar; stretch: real LSD via `SetDriveTorque` + `ETorqueCombineMethod::Override` using wheel-speed difference |
| Differential | Decel lock | 0-100 | 0 | stock | 100 | `Tune.Diff` | stretch only |
| Differential | Center split (AWD, rear %) | % | 30 | stock (65-75) | 90 | `Tune.Diff` | `SetDifferentialFrontRearSplit(rear/100)` (real, runtime) |

Skipped from FH5: caster (no useful mapping), separate bump/rebound (Chaos has one damping ratio), per-gear ratio sliders (replaced with final drive + one spacing slider), tire compound width, track width. Add a "Reset to stock" button and a "Quick tune: Balanced / Grip / Drift" preset trio (just three FCarTuning dictionaries per drivetrain).

### 3.8 Paint, finishes, livery
```cpp
USTRUCT(BlueprintType) struct FCarPaint {
  FLinearColor Primary = (0.55,0.05,0.05); FLinearColor Secondary;   // stripe / second tone
  EPaintFinish Finish = Gloss; uint8 StripeStyle;                    // 0 none .. N preset stripe masks
  FLinearColor RimColor; FName RimStyleId; EPaintFinish RimFinish;
  FLinearColor CaliperColor; float WindowTint01;
};
```
Blender convention: separate material slots `Paint_Body`, `Paint_Secondary`, `Rim`, `Caliper`, `Glass`, `Trim`. At runtime create one `UMaterialInstanceDynamic` per slot from `M_CarPaint_Master`.

Finish table (starting parameters for the master material):

| Finish | BaseColor | Metallic | Roughness | Clear coat | Flake | Notes |
|---|---|---|---|---|---|---|
| Gloss | Primary | 0.0 | 0.45 | 1.0 / coat roughness 0.03 | 0 | classic wet look |
| Matte | Primary * 0.95 | 0.0 | 0.80 | 0.0 | 0 | add slight sheen at grazing angles |
| Metallic | Primary | 0.85 | 0.35 | 1.0 / coat roughness 0.04 | 0.6 (procedural sparkle normal, tiling ~80 m^-1) | flake colour = brighter Primary |

- The project has `r.Substrate=True` in `Config\DefaultEngine.ini`. Author the master material once with the node set that matches Substrate (a coat layer over a metal/dielectric slab), or use the legacy Clear Coat shading model and rely on automatic conversion [K, verify in editor]. Either way expose scalar params `Finish` (0/1/2) or the explicit scalars (Metallic, Roughness, ClearCoat, FlakeIntensity) so the C++ side only sets named parameters.
- Livery: stripes only (3-6 preset masks) as a texture-array index; full vinyl editing is SKIPPED.
- Persist `FCarPaint` per car in the save; console command from the master prompt: `paint <colour>` sets Primary, plus `finish <gloss|matte|metallic>`.

### 3.9 Assists schema and implementation on Chaos
```cpp
UENUM() enum class EBrakeAssist : uint8 { Assisted, AbsOn, AbsOff };
UENUM() enum class ESteerAssist : uint8 { Assisted, Normal, Simulation };
UENUM() enum class EGearMode : uint8 { Automatic, Manual /*, ManualClutch (stretch)*/ };
UENUM() enum class EDrivingLine : uint8 { Off, BrakingOnly, Full };
USTRUCT() struct FAssistSettings {
  EBrakeAssist Braking = AbsOn; ESteerAssist Steering = Assisted;
  bool bTractionControl = true; bool bStability = true;
  EGearMode Gearbox = Automatic; EDrivingLine Line = BrakingOnly; bool bRewind = true;
  bool bDamageCosmeticOnly = true;
};
```
Presets (bundles like FH's difficulty presets): **Casual** (Assisted/Assisted/TC on/SC on/Auto/Line Full/Rewind), **Standard** (ABS on/Assisted/TC on/SC on/Auto/Braking only/Rewind), **Pro** (ABS on/Normal/TC off/SC on/Manual/Braking only/Rewind), **Simulation** (ABS off/Simulation/TC off/SC off/Manual/Off/no Rewind). Show the active preset name as "Custom" once an individual item is changed.
Reward multiplier (for activity payouts, mirrors FH's credit bonus): table in `UCarRulesData`, e.g. TC off +10%, SC off +10%, ABS off +5%, Manual +15%, Steering Simulation +10%, Line off +5%, Rewind off +10%, additive, shown in the settings screen as "Reward x1.35".

Implementation:
- **ABS**: per wheel `SetABSEnabled(i, Braking != AbsOff)`. "Assisted" braking = ABS on + project-owned auto-brake that uses the braking-line profile (below) to apply brake when speed exceeds the profile; mark as stretch.
- **Traction control**: `SetTractionControlEnabled(i, bTractionControl)` (straight-line). Stronger variant: project code reduces throttle by `clamp(k*(slipRatio - 0.2), 0, 0.6)` when any driven `FWheelStatus.bIsSlipping`.
- **Stability control (project-owned)**, run each fixed physics substep (use the async callback or the pawn's `Tick` at 60+ Hz and per-wheel `SetBrakeTorque` with `ETorqueCombineMethod::Additive`):
  ```
  r_meas   = body yaw rate (rad/s)
  delta    = steering angle (rad) = SteerInput * speedCurve(v) * MaxSteerDeg
  r_target = v * delta / (L * (1 + (v / v_char)^2))      // L = wheelbase m, v_char ~ 25..35 m/s per car
  err      = r_meas - r_target
  if |err| > 0.12 rad/s AND |rear slip angle| > 5 deg:
      if sign(err) == sign(r_target): oversteer -> brake the outside front wheel  T = k1*(|err|-0.12)*MaxBrakeTorque
      else if |r_meas| < 0.6*|r_target|:  understeer -> brake the inside rear wheel, gentler (k2 = 0.5*k1)
      throttle scale = 1 - clamp(1.5*|err|, 0, 0.6)
  ```
  Disable while handbrake is held; disable above a large steering input rate if "Simulation".
- **Steering assist**: speed-sensitive lock is already data (`SteeringCurve` in MPH). `Assisted` adds a counter-steer term `delta_out = delta_in + Kcs*(r_target - r_meas)/r_max` (Kcs about 0.35) and stronger input smoothing (steering `RiseRate` about 2.5, `FallRate` about 6); `Normal` = smoothing only (RiseRate 5, FallRate 8); `Simulation` = raw input, low-speed rate limit only. Gamepad vs keyboard: keyboard users need the smoothing even in Normal.
- **Transmission**: `Automatic` -> `SetUseAutomaticGears(true)` with `ChangeUpRPM` about 0.93 * redline, `ChangeDownRPM` about 0.40 * redline from data; `Manual` -> `SetUseAutomaticGears(false)` + `SetChangeUpInput/SetChangeDownInput` (bind to shoulder buttons / E / Q), allow `SetTargetGear`. Auto-downshift on full brake in Assisted mode is a project-owned nicety. Clutch/ManualClutch: SKIP.
- **Driving line / braking line** (project-owned, needs the road spline from the world team):
  1. Sample the player's route ahead (next 250-350 m) from the road spline at 5 m spacing; curvature k_i from three points.
  2. Corner speed `v_i = min(vmaxRoad, sqrt(aLat * g / k_i))` with `aLat` = car's `latG * 0.85` (a safety margin that the Assist level can scale: Full 0.80, Braking-only 0.85).
  3. Backward pass: `v_i = min(v_i, sqrt(v_{i+1}^2 + 2*aBrake*ds))`, `aBrake` = `BrakeG * 0.8 * g`.
  4. Colour per segment from `current speed vs profile`: cruise (neutral), lift (profile < speed + 5 m/s), brake (profile < speed - 3 m/s). Render as a ribbon mesh/Niagara ribbon or decal strip; `Full` shows all colours, `BrakingOnly` shows only the red brake segments, `Off` shows nothing.
  5. The spline must be the actual drivable lane (right-hand lane for traffic roads), otherwise the line contradicts traffic.
- **Rewind** (stretch): ring buffer of `GetSnapshot()` at 10 Hz for 20 s plus world-time-scale 0 for traffic; hold button plays back at 2x with `SetSnapshot`; on release resume with a 0.5 s control lock; keep traffic as non-rewound but spawn-safe (teleport the player away from overlaps).
- **Damage/tire wear**: SKIP wear; damage = cosmetic only (optional crumple decals), no performance penalty. Prompt allows "damage as a bonus".

HUD / menu presentation (reproducing the FH5 pattern in our own style):
- Settings > Difficulty page = list of dropdown/toggle rows (Preset, Braking, Steering, Traction, Stability, Gearbox, Driving line, Rewind, Damage) + a footer line "Reward multiplier x1.35".
- HUD: small assist strip near the speedometer with three icons (TCS, ABS, STM), dim when the assist is off or idle, bright amber flash while it is actively intervening (ABS from `FWheelStatus.bABSActivated`; TC and STM from our own flags). Gear indicator shows `A` or `M`. Active surface icon (asphalt/gravel/dirt/sand/wet) from `PhysMaterial`.
- Garage screen: stat bars (6 bars out of 10 + PI chip), a "preview" mode where hovering an upgrade shows green/red delta bars and the PI change before buying.

---------------------------------------------------------------------------------------------------

## 4. Decisions table (ADOPT / ADAPT / SKIP)

| Feature | Decision | Reason |
|---|---|---|
| Alphabetical, year-maker-model roster list with rarity badge | ADAPT | 10 fictional cars; keep rarity as a display tag only |
| Car Collection screen / manufacturer reward counts | SKIP | no collection loop for 10 cars |
| Wheelspin / rarity-driven acquisition | SKIP | cars are selectable via console/garage |
| Classes D C B A S1 S2 X with FH thresholds | ADOPT | familiar scale, easy to explain in a video; thresholds in data |
| PI as one number recomputed from resulting performance | ADOPT | avoids per-part PI tables; gives FH-like trade-offs |
| Six sub-ratings (Speed, Handling, Acceleration, Launch, Braking, Offroad) | ADOPT | direct UI stat bars; Offroad suits the rally/SUV cars |
| PI from simulated lap on synthetic track | ADAPT | replace with analytic estimator + weighted score (section 3.5) |
| 6 upgrade categories | ADOPT | mirrors garage flow; ~14 slots total |
| Tier ladder Stock/Street/Sport/Race + Rally/Drift/Offroad branches | ADAPT | Stock/Street/Sport/Race, plus Rally and Offroad where relevant; Drift SKIP |
| Engine swaps, aspiration swaps, body kits, overlanding kits | SKIP | needs extra meshes and sounds |
| Drivetrain swap (AWD/RWD) | ADAPT | only AWD swap for FWD/RWD cars, simple spec override |
| Parts gate tuning screens | ADOPT | cheap, gives upgrades a purpose |
| Auto Upgrade | ADAPT | greedy PI-per-credit solver using the analytic PI |
| Tuning groups (tires, gearing, alignment, ARB, springs, damping, aero, brakes, diff) | ADAPT | reduced set of ~18 sliders (3.7); caster and bump/rebound dropped |
| Camber/toe as physics | ADAPT | Chaos has none; approximate with grip scalars + cosmetic wheel lean |
| Tire pressure with temps and wear | ADAPT | pressure only, surface-dependent optimum, no temp/wear |
| Per-gear ratio editing | SKIP | final drive + one spacing slider is enough |
| Differential accel/decel LSD | ADAPT | AWD center split is real; LSD locks as stretch |
| Telemetry overlay while tuning | ADAPT | reuse debug menu telemetry (RPM, slip, surface), not tire temps |
| Paint finishes gloss/matte/metallic | ADOPT | per prompt; 3-row data table |
| Special paint families (camo, wood, carbon) | SKIP | not needed |
| Layer-based livery/vinyl editor, sharing | SKIP | far beyond scope; stripes only |
| Rim style + colour | ADAPT | 3-4 procedural/Blender rim styles |
| Difficulty presets + individual assists | ADAPT | 4 presets, 8 individual toggles |
| ABS, TC, SC, steering assist | ADAPT | ABS/TC via Chaos flags; SC and steering assist project-owned |
| Credit bonus for fewer assists | ADAPT | reward multiplier on activities |
| Driving line with braking zones | ADAPT | spline-based speed profile (3.9) |
| Rewind | ADAPT | stretch; Chaos snapshot API makes it feasible |
| Drivatar AI difficulty | SKIP | no AI racers beyond traffic and simple event rivals |
| Manual with clutch | SKIP | auto/manual only |
| Damage and tire wear simulation | SKIP | cosmetic damage only, optional |
| Accessibility game-speed slider | SKIP | nice-to-have, not core |

---------------------------------------------------------------------------------------------------

## 5. Pitfalls and open questions

1. **Chaos config is baked at physics-state creation** (point 13 in section 2). Tuning sliders that touch gearing or engine/diff layout need `RecreatePhysicsState()` or a respawn. Plan the garage flow so these apply when leaving the tuning screen.
2. **Wheel class CDO is shared**. Never edit the wheel BP defaults per car. Use the runtime setters after spawn; apply them again after `RecreatePhysicsState()` or `ResetVehicle()`.
3. `SteeringCurve` is in MPH; `GetForwardSpeedMPH()` exists. HUD km/h conversion belongs to the UI, not the physics.
4. ABS/TC in Chaos are idealised; expect braking distances much shorter with ABS on than with it off. Tune `BrakeG` and the PI estimator with ABS ON as the reference, ABS OFF as a penalty.
5. **No stability control, camber, toe, LSD, bump/rebound, per-axle downforce, tire temperature in Chaos.** Everything in the "ADAPT" rows above is project code; budget time for it or drop to the minimum (tire pressure, ARB, springs, damping, brake bias, final drive, center split).
6. The estimator must stay close to the live physics or the UI lies. Add the automated drive tests to a CI-style console command (`cartest <id>`), print estimator vs measured, and calibrate per car.
7. PI exploits: because PI is derived from the same stats, a pure power build with no brakes can exceed a class limit; keep the weights (handling 0.26 + braking 0.13) high enough to punish it.
8. Substrate is enabled in the project (`r.Substrate=True`). The car-paint master material and clear-coat nodes must match; test early, because paint finish is a visible quality signal in the garage screen.
9. SpringRate units are not documented; calibrate empirically (section 2, point 15) and keep the value in car data.
10. Source quality: most FH5 tuning numbers come from fan guides which contradict each other (tire pressure 20-25 psi vs 26-35 psi vs 30-34 psi). The official Forza support pages were not reachable. Do not claim FH5 numbers as facts in docs or videos; our numbers are our own tuning.
11. Class names, the six rating names and PI thresholds are common vocabulary; do not reuse FH5 artwork, UI layout copies or the exact Forza Edition naming. Keep the game's own name, fictional makers, and no Forza/Playground/Microsoft branding anywhere.
12. Open: does 5.8's `AWheeledVehiclePawn` expose a cleaner way to re-apply `TransmissionSetup` after edits? None found in the headers; if the lead finds one in the editor, prefer it over `RecreatePhysicsState()`.
13. Open: whether the 4x4 km map has paved + gravel + sand surfaces at the same time; if sand is absent, drop `ESurface::Sand` and the associated tire-pressure optimum.

---------------------------------------------------------------------------------------------------

## 6. Sources actually used

FH5 / Forza (official and near-official):
- https://forza.net/news/forza-horizon-5-confirmed-car-list (read; roster structure, Forza Edition, Welcome Pack, rarity/collection)
- https://caniplaythat.com/2021/11/04/forza-horizon-5-accessibility-menu-deep-dive/ (read; difficulty and HUD menu structure)
- https://support.forza.net/hc/en-us/articles/360005363194-Difficulty-Assists-and-Drivatars (search summary only; page 403)
- https://support.forza.net/hc/en-us/articles/360005372033-FH3-Performance-Index-and-Classes (search summary only; page 403)
- https://support.forza.net/hc/en-us/articles/4409280058259-Forza-Horizon-5-Accessibility-Support (search summary only; page 403)

Guides / community (read unless noted):
- https://hackernoon.com/forza-horizon-5-cars-guide-how-to-build-and-tune-for-optimal-road-race-performance (upgrade order, PI management, tuning values)
- https://gamepretty.com/forza-horizon-5-build-tuning-tips/ (PI management, tuning table, telemetry targets)
- https://diamondlobby.com/forza-horizon-5/best-tuning-setups-for-forza-horizon-5/ (per-discipline tuning rules)
- https://forzahorizoncar.com/en/wiki/guides/tuning.html (class table; fan wiki)
- https://racinggames.gg/forza/forza-horizon-5-how-to-change-difficulty/ (assist list, credit multiplier concept)
- https://www.windowscentral.com/forza-horizon-5-upgrading-guide (search summary; class table, categories; page truncated)
- https://www.gamesradar.com/forza-horizon-5-tips (search summary; credit bonus percentages; page truncated)
- https://www.pcgamer.com/forza-horizon-5-car-list (search summary; car counts)
- https://racinggames.gg/forza/forza-horizon-5-how-many-cars-will-there-be/ (search summary; car counts)
- https://forums.forza.net threads on PI ratings, paint types, vinyl material, tuning guides (search summaries only; pages redirect to a generic index)

Unreal Engine:
- https://dev.epicgames.com/documentation/unreal-engine/how-to-set-up-vehicles-in-unreal-engine (read; required assets/steps for Chaos wheeled vehicles)
- https://dev.epicgames.com/documentation/en-us/unreal-engine/data-assets-in-unreal-engine (read; UDataAsset / UPrimaryDataAsset)
- Local engine source read: `Engine\Plugins\Experimental\ChaosVehiclesPlugin\ChaosVehiclesPlugin.uplugin`, `Source\ChaosVehicles\Public\ChaosWheeledVehicleMovementComponent.h`, `ChaosVehicleMovementComponent.h`, `ChaosVehicleWheel.h`, `Private\ChaosWheeledVehicleMovementComponent.cpp`, `Private\ChaosVehicleMovementComponent.cpp`, and `Source\Runtime\Experimental\ChaosVehicles\ChaosVehiclesCore\Public\WheelSystem.h`, `AerodynamicsSystem.h`, `Private\WheelSystem.cpp`.
- Project files read: `Claude_Sonnet_5.5_Unreal_Forza_BlenderMCP_Prompt.md` (sections 5-8), `Config\DefaultEngine.ini` (Substrate), `Sonnet55Forza.Build.cs`, `Sonnet55Forza.uproject`.

Scratch work (outside the project): `pi_proto.py` in the session scratchpad (Python PI/performance prototype that produced the tables in 3.5-3.6).
