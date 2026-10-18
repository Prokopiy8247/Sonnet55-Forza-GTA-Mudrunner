# UE 5.8 vehicle physics and gameplay framework - research notes

Project: Sonnet55Forza (original open-world arcade-sim racer, FH5 used only as a feature-scope reference).
Engine: `W:\Unreal Engine 5\UE_5.8` (read-only reference). Project: `W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza`.
Scope of this file: vehicle physics, Enhanced Input, HUD/UI, procedural audio, Niagara, traffic AI, subsystems / console / SaveGame.
Nothing here was compiled or run (research only). Code snippets are skeletons written against the 5.8 headers that were read.

Verification tags used below:

- [SRC] verified by reading the local UE 5.8 source/headers/config under `W:\Unreal Engine 5\UE_5.8\Engine` (file paths given where it matters)
- [DOC] stated on an official Epic documentation page that was fetched
- [COM] community / third-party page; treat as a lead, not as fact
- [UNV] from memory or inference, not verified; must be smoke-tested before relying on it

---------------------------------------------------------------------------------------------------

## 0. Decisions at a glance

| Topic | Decision | One-line reason |
|---|---|---|
| Vehicle physics | Project-owned raycast/spring vehicle in C++, driven from `AsyncPhysicsTickComponent` on a Chaos rigid body | Chaos Vehicles is Experimental, needs skeletal mesh + physics asset (+ anim BP) assets, simplified tire model, single friction scalar per surface |
| Chaos Vehicles | SKIP as primary, keep as time-boxed fallback spike only | See section 1.2-1.4 for the exact limitations |
| Physics step | `bTickPhysicsAsync=True`, `AsyncFixedTimeStepSize=1/60` (try 1/120), substepping off | Fixed dt is what makes spring/damper + tire forces stable at 70 m/s |
| Scene queries | `LineTraceSingleByObjectType` (static objects) inside the async tick | In the async tick the engine automatically queries physics-thread data (section 1.5.2) |
| Input | Enhanced Input, assets created at runtime with `NewObject`, `BindAction` + polling | No .uasset needed, `DefaultInput.ini` already has the Enhanced classes |
| HUD / menus | Slate (SCompoundWidget / SLeafWidget with custom OnPaint); AHUD canvas for debug text | No Blueprint widgets; full control |
| Minimap | Slate polylines of the road network, optional baked UTexture2D underlay | Render targets / scene capture are too expensive and unnecessary |
| Console | Engine console (backtick) + `IConsoleManager` commands registered from a GameInstance subsystem | Autocomplete + history for free; Slate overlay only for the debug menu |
| Engine audio | `USynthComponent` + `ISoundGenerator` written in C++ (phase-accumulator synth) | No assets, RPM-latency of one audio buffer, spatialisable |
| MetaSounds builder | SKIP for engine sound, optional later for ambience | Works at runtime [DOC] but node/pin names must be discovered by hand |
| Niagara | ADAPT: author assets from Python through the CascadeToNiagaraConverter scripting API; spawn from C++ | Engine ships NO dust/smoke/rain systems; templates expose no user parameters |
| Traffic | Custom lane graph + data-oriented agent array in a `UTickableWorldSubsystem` | ZoneGraph builds editor-only, MassTraffic is not in the engine, Mass has no vehicle logic |
| Subsystems | `UGameInstanceSubsystem` for save/console/settings, `UTickableWorldSubsystem` for traffic/activities/weather | Standard, auto-instanced |
| Save | `USaveGame` + `SaveGameToSlot` / `AsyncSaveGameToSlot`, plain data only | `Saved/SaveGames/<slot>.sav` |

---------------------------------------------------------------------------------------------------

## 1. Vehicle physics

### 1.1 Status of Chaos Vehicles in 5.8

- `Engine\Plugins\Experimental\ChaosVehiclesPlugin\ChaosVehiclesPlugin.uplugin`: `"IsExperimentalVersion": true`, `"EnabledByDefault": false`, category Physics, modules `ChaosVehicles` (Runtime, PreDefault) and `ChaosVehiclesEditor` (UncookedOnly). [SRC]
- It must be enabled in the `.uproject` (`{"Name":"ChaosVehiclesPlugin","Enabled":true}`) and the game module needs `"ChaosVehicles"` plus `SetupModulePhysicsSupport(Target)` (adds PhysicsCore, ChaosCore, Chaos, NNE and the Chaos include path; defined in `Engine\Source\Programs\UnrealBuildTool\Configuration\Rules\ModuleRules.cs` line ~1793). [SRC]
- Core simulation code (wheel/engine/transmission/suspension) lives in `Engine\Source\Runtime\Experimental\ChaosVehicles\ChaosVehiclesCore` (a runtime module, not a plugin). [SRC]
- Sibling plugins in the same folder: `ChaosModularVehicle` (version 0.1, experimental, geometry-collection/cluster-union based; the 5.8 release notes only mention it: "can now be built from a skeletal mesh", ground interaction both ways), `ChaosMover` (character mover, not wheeled), `ChaosRigidPhysicsAsync`. [SRC][DOC 5.8 release notes]
- The 5.8 release notes contain NO entry for classic Chaos Vehicles (only Modular Vehicles), so assume it is unchanged since 5.5-5.7. [DOC]
- Epic's docs still describe it as experimental and list the required assets: skeletal mesh, physics asset, animation blueprint (parent = vehicle anim instance with a Wheel Controller node), vehicle pawn based on `WheeledVehiclePawn`, one wheel class per axle (`ChaosVehicleWheel`), a float curve for engine torque. They also state the plugin does not work with PhysX enabled. [DOC how-to-set-up-vehicles-in-unreal-engine]
- A third-party blog claims 5.7 reworked the tire model to Pacejka and moved the component to the Network Prediction plugin. The 5.8 source does NOT support those claims (see 1.2: friction circle + slip-angle graph; network physics uses `UNetworkPhysicsComponent` / `FNetworkPhysicsData`). Do not rely on that blog. [COM, contradicted by SRC]

### 1.2 How Chaos Vehicles actually works in 5.8 (read from source)

Files: `Engine\Plugins\Experimental\ChaosVehiclesPlugin\Source\ChaosVehicles\{Public,Private}`.

Architecture [SRC]:

- `IChaosVehiclesPlugin::StartupModule` hooks `FPhysicsDelegates::OnPhysSceneInit`; each `FPhysScene` gets an `FChaosVehicleManager`.
- The manager registers one `FChaosVehicleManagerAsyncCallback` (a `Chaos::TSimCallbackObject<Input, Output, ESimCallbackOptions::Presimulate | ESimCallbackOptions::Rewind>`) with `Scene.GetSolver()->CreateAndRegisterSimCallbackObject_External<>()`.
- Game thread, every physics pre-tick: `PreTickGT` per vehicle -> `ParallelUpdateVehicles` (consumes `PopOutputData_External` / `PopFutureOutputData_External`, interpolates between two PT outputs) -> `Update()` + `FinalizeSimCallbackData` fills `FChaosVehicleManagerAsyncInput` obtained from `AsyncCallback->GetProducerInputData_External()`.
- Physics thread, every solver step: `OnPreSimulate_Internal()` -> `PhysicsParallelFor` over vehicles -> `FChaosVehicleAsyncInput::Simulate` -> `UChaosVehicleSimulation::TickVehicle` = `UpdateState` (capture state from `Chaos::FRigidBodyHandle_Internal`: `X() R() V() W() CenterOfMass() M()`), `ApplyInput`, `UpdateSimulation` (aero, aerofoils, thrusters, torque control, then for wheeled: mechanical sim, suspension, steering, wheel friction), `FillOutputState`. Forces are queued in `FDeferredForces` and applied serially afterwards via `RigidHandle->AddForce(F, false)`, `AddTorque`, `SetLinearImpulse` (`DeferredForces.cpp`).
- Suspension traces run from the PT callback with `World->LineTraceSingleByChannel(..., ECC_WorldDynamic, TraceParams, ResponseParams)`; `TraceParams.bReturnPhysicalMaterial = true`, owner pawn ignored, response container = default with `Vehicle = ECR_Ignore` (`WheelTraceCollisionResponses`). Wheel `SweepShape` = `Raycast | Spherecast | Shapecast`, `SweepType` = `SimpleSweep` (default) or `ComplexSweep`. Optional batching via `p.Vehicle.BatchQueries`.
- Suspension forces are applied by Chaos suspension constraints (`FPhysicsInterface::CreateSuspension`, `Solver->SetSuspensionTarget(...)`) - but those constraints are only created inside `UChaosWheeledVehicleMovementComponent::FixupSkeletalMesh()` and only when the updated component is a `USkeletalMeshComponent` with a `UPhysicsAsset` whose bodies match the wheel `BoneName`s (the code also disables the wheel bodies and removes their constraints). With a static mesh no constraint is created and suspension only works if `p.Vehicle.DisableConstraintSuspension=1` is set (a global debug CVar: "basic force based suspension without hardstops"). `CanCreateVehicle()` also refuses to build unless every wheel has a `WheelClass` AND a non-None `BoneName`.
- Tire model (`ChaosVehiclesCore\Private\WheelSystem.cpp`, `FSimpleWheelSim::Simulate`): available grip = `ForceIntoSurface * SurfaceFriction * FrictionMultiplier`; lateral force = lateral slip graph (`LateralSlipGraph`, evaluated in degrees of slip angle) or linear `|alpha| * CorneringStiffness`; both clamped by "force required to bring wheel to rest"; then a friction circle: if `|F| > grip` the force vector is scaled down and multiplied by `SideSlipModifier` (this is the drift/grip-loss knob). Wheel speed `Omega` is simply snapped to `GroundVelocity.X / radius` when in contact (+ `SlipOmega` from excess drive torque), i.e. there is NO real slip-ratio / longitudinal slip curve. ABS and straight-line traction control just clamp brake/drive force to 98 % of grip.
- Surface friction: `PWheel.SetSurfaceFriction(HitResult.PhysMaterial->Friction)` - one scalar, the same `UPhysicalMaterial::Friction` that also drives rigid-body contact friction. No per-surface curves, no wetness.
- Aero: `0.5 * rho * v^2 * Area * Cd` drag along X and `Cdownforce` along Z at the body origin; `DragCoefficient`, `DownforceCoefficient`, `ChassisWidth * ChassisHeight` = area. No aero balance (no pitch moment) other than `Aerofoils`.
- Mechanical sim: engine (`FVehicleEngineConfig`: `TorqueCurve` normalised to 20 samples, `MaxTorque`, `MaxRPM`, `EngineIdleRPM`, `EngineBrakeEffect`, `EngineRevUpMOI`, `EngineRevDownRate`), transmission (`FVehicleTransmissionConfig`: auto/manual, `ForwardGearRatios`, `ReverseGearRatios`, `FinalRatio`, `ChangeUpRPM`, `ChangeDownRPM`, `GearChangeTime`, `TransmissionEfficiency`), differential (`EVehicleDifferential::{AllWheelDrive,FrontWheelDrive,RearWheelDrive}` + `FrontRearSplit`; no LSD parameter in 5.8), steering (`ESteeringType::{SingleAngle,AngleRatio,Ackermann}`, speed curve X axis is MPH).
- Per-wheel defaults (`ChaosVehicleWheel.cpp`): radius 32, width 20, mass 20, `FrictionForceMultiplier=2`, `CorneringStiffness=1000` (x10000 internally), `SideSlipModifier=1`, `MaxWheelspinRotation=30`, `SpringRate=250`, `SpringPreload=50`, `SuspensionMaxRaise/Drop=10`, `SuspensionDampingRatio=0.5`, `WheelLoadRatio=0.5`, `RollbarScaling=0.15`. Units are cm for lengths; spring rate is converted `MToCm`.
- Extras: `TorqueControl`, `TargetRotationControl`, `StabilizeControl` ("ArcadeControl" category, mostly for aircraft/arcade), `Aerofoils`, `Thrusters`, input shaping (`FVehicleInputRateConfig`: rise/fall rate, linear/squared/custom curve), `bReverseAsBrake`, `bThrottleAsBrake`, `bRequiresControllerForInputs` (default TRUE - AI/traffic vehicles must call `SetRequiresControllerForInputs(false)`), own sleeping logic (`SleepThreshold`, `SleepSlopeLimit`, `p.Vehicle.DisableVehicleSleep`), snapshot get/set, replication via `UNetworkPhysicsComponent`.
- `AWheeledVehiclePawn` (abstract) creates `USkeletalMeshComponent` ("VehicleMesh", profile `Vehicle`, `bUseCCD=true`, `bNotifyRigidBodyCollision=true`, `bSimulatePhysics=false` until set) and `UChaosWheeledVehicleMovementComponent` ("VehicleMovementComp"). Override the movement class with `Super(ObjectInitializer.SetDefaultSubobjectClass<UMyMovement>(VehicleMovementComponentName))`.
- Useful extension points (all `virtual` in `UChaosWheeledVehicleSimulation`): `PerformSuspensionTraces`, `ApplySuspensionForces`, `ApplyWheelFrictionForces`, `ProcessMechanicalSimulation`, `ProcessSteering`; the simulation object is created in `UChaosWheeledVehicleMovementComponent::CreatePhysicsVehicle()` (virtual, assigns `VehicleSimulationPT`). A "hybrid" (own friction on top of Chaos engine/transmission) is technically possible, but it keeps all the asset requirements.
- Debug CVars: `p.Vehicle.ShowSuspensionRaycasts`, `ShowWheelForces`, `ShowSuspensionForces`, `ShowCOM`, `ShowRaycastMaterial`, `DisableConstraintSuspension`, `BatchQueries`, `TraceTypeOverride` (1 simple, 2 complex), `SetMaxMPH`, `NextDebugPage` / `PrevDebugPage` commands, `stat ChaosVehicle`. [SRC]

### 1.3 Setting up Chaos Vehicles from C++ (what is possible without Blueprint assets)

Possible in code: pawn class, movement component settings, wheel classes (C++ `UChaosVehicleWheel` subclasses), engine/transmission/diff/steering config, torque curve (`EngineSetup.TorqueCurve.GetRichCurve()->AddKey(Rpm, Value)`), wheel bone names/offsets, input mapping (call `SetThrottleInput`, `SetBrakeInput`, `SetSteeringInput`, `SetHandbrakeInput`, `SetChangeUpInput`... from Enhanced Input handlers).

NOT possible without assets: the `USkeletalMesh` (needs an armature with wheel bones; wheel bone local X forward, Z up per [COM] guidance), its `UPhysicsAsset` (convex chassis body with the mass, sphere/no-collision bodies on wheel bones - [DOC]), and (for visible wheel rotation/suspension) an AnimBP with `AnimNode_WheelController`. Wheel meshes could instead be separate components moved from `UChaosVehicleWheel::GetSuspensionOffset() / GetSteerAngle() / GetRotationAngle()`, which avoids the AnimBP.

Skeleton (compile-untested):

```cpp
// Sonnet55Forza.Build.cs additions:  "ChaosVehicles", plus SetupModulePhysicsSupport(Target);
// .uproject: { "Name": "ChaosVehiclesPlugin", "Enabled": true }

UCLASS()
class UFzFrontWheel : public UChaosVehicleWheel
{
    GENERATED_BODY()
public:
    UFzFrontWheel(const FObjectInitializer& OI) : Super(OI)
    {
        AxleType = EAxleType::Front; WheelRadius = 33.f; WheelWidth = 22.f; WheelMass = 20.f;
        bAffectedBySteering = true; MaxSteerAngle = 35.f; bAffectedByEngine = false;
        FrictionForceMultiplier = 2.f; SpringRate = 250.f; SpringPreload = 0.f; SuspensionDampingRatio = 0.5f;
        SuspensionMaxRaise = 8.f; SuspensionMaxDrop = 10.f; SweepType = ESweepType::SimpleSweep;
    }
};

UCLASS()
class AFzChaosCar : public AWheeledVehiclePawn
{
    GENERATED_BODY()
public:
    AFzChaosCar(const FObjectInitializer& OI) : Super(OI)
    {
        auto* M = CastChecked<UChaosWheeledVehicleMovementComponent>(GetVehicleMovement());
        M->WheelSetups.SetNum(4);
        const TCHAR* Bones[4] = { TEXT("wheel_fl"), TEXT("wheel_fr"), TEXT("wheel_rl"), TEXT("wheel_rr") };
        for (int32 i = 0; i < 4; ++i) { M->WheelSetups[i].WheelClass = (i < 2) ? UFzFrontWheel::StaticClass() : UFzRearWheel::StaticClass();
                                         M->WheelSetups[i].BoneName = Bones[i]; }
        M->Mass = 1400.f; M->EngineSetup.MaxTorque = 450.f; M->EngineSetup.MaxRPM = 7500.f;
        M->DifferentialSetup.DifferentialType = EVehicleDifferential::RearWheelDrive;
        // Mesh + PhysicsAsset are ASSETS: GetMesh()->SetSkeletalMeshAsset(...); GetMesh()->SetPhysicsAsset(...);
        GetMesh()->SetSimulatePhysics(true);
    }
};
```

Static-mesh variant (no skeletal assets): `ObjectInitializer.DoNotCreateDefaultSubobject(VehicleMeshComponentName)`, create a `UStaticMeshComponent` root, `Movement->SetUpdatedComponent(Root)`, give every wheel setup a dummy `BoneName` (for a non-skinned mesh `LocateBoneOffset` just returns `Offset`) and set `p.Vehicle.DisableConstraintSuspension 1`. It runs through the debug path (no suspension hard-stops) - not recommended for a shipping-quality landing/jump behaviour. [SRC, behaviour inferred - UNV until run]

### 1.4 Chaos Vehicles limitations relevant to this project (derived from the source above)

- Needs skeletal mesh + physics asset assets; the Blender pipeline would have to emit armatures and the physics asset would need scripted editing (wheel bodies, mass on chassis).
- Tire model is a friction circle with a lateral slip-angle graph; no slip ratio, no load sensitivity beyond `WheelLoadRatio`, no per-surface slip curves, no wetness. Surface grip = `UPhysicalMaterial::Friction` only.
- Suspension/ground sampling is one ray per wheel per solver step. Distance travelled per step at 250 km/h (69.4 m/s): 2.3 m at 1/30 s, 1.16 m at 1/60 s, 0.58 m at 1/120 s. Any fixed-step tuning must be done with `bTickPhysicsAsync`.
- The PT callback queries `World->LineTraceSingleByChannel` while the engine resolves the thread context to `GTData` for non-frozen-GT callers (see 1.5.2), i.e. the (interpolated) external acceleration structure; it works because roads are static.
- Default sleeping logic and `bRequiresControllerForInputs=true` are traps for AI cars.
- Plugin is flagged Experimental; API/behaviour may change in 5.9; no 5.8 changelog entry.
- Positive: it is real Epic code (engine + transmission + ABS/TC, network prediction, debug draw, input shaping), and `AWheeledVehiclePawn` already sets CCD.

### 1.5 Project-owned raycast/spring vehicle on a Chaos rigid body

#### 1.5.1 Hooks available in 5.8 for per-step forces

| Hook | What it really does in 5.8 | Verdict |
|---|---|---|
| `FBodyInstance::AddCustomPhysics(FCalculateCustomPhysics&)` | In Chaos `FPhysScene_Chaos::AddCustomPhysics_AssumesLocked` just calls the delegate ONCE, immediately, with `MDeltaTime` on the calling (game) thread. It is NOT a per-substep callback any more (`PhysScene_Chaos.cpp` line 1665). | Do not use |
| Sync substepping (`UPhysicsSettings::bSubstepping`, `MaxSubstepDeltaTime=1/60`, `MaxSubsteps=6`) | Solver splits the frame delta into sub-steps, but `OnPreSimulate_Internal` callbacks are "not once per sub-step when sub-stepping is enabled" (`SimCallbackObject.h`); only `PreIntegrate`/`PostIntegrate` options are per sub-step. Still variable dt. | Avoid |
| `UActorComponent::AsyncPhysicsTickComponent(float DeltaTime, float SimTime)` (`bAsyncPhysicsTickEnabled` / `SetAsyncPhysicsTickEnabled(true)`), also `AActor::AsyncPhysicsTickActor` | Registered with `FPhysScene_Chaos::RegisterAsyncPhysicsTickComponent/Actor`; executed by `FAsyncPhysicsTickCallback` (`TSimCallbackObject<..., Presimulate | RunOnFrozenGameThread>`) once per solver step with the PT blocked and the game thread running the callback: "allowed to read and write both Physics Thread and Game Thread data"; warning: "both threads halt and force a full sync". Fixed dt when `bTickPhysicsAsync`. Epic's own helper: `UPhysicsThreadLibrary::AddForce(FBodyInstanceAsyncPhysicsTickHandle, Force, bAccelChange)` (`Physics\Experimental\PhysicsThreadLibrary.h`). | RECOMMENDED for 1 player car (+ few physical traffic cars) |
| Custom `Chaos::TSimCallbackObject<Input, Output, ESimCallbackOptions::Presimulate>` created with `Scene.GetSolver()->CreateAndRegisterSimCallbackObject_External<T>()` (the pattern Chaos Vehicles uses) | Truly runs on the physics thread, inputs marshalled with `GetProducerInputData_External()` / `GetConsumerInput_Internal()`, outputs via `GetProducerOutputData_Internal()` / `PopOutputData_External()`. No UObject access, scene queries get GT-interpolated data (1.5.2), more boilerplate. | Use only if the async-tick sync cost shows up in profiling |
| `Chaos::FPhysicsObject` + `FPhysicsObjectInterface` (`Chaos\PhysicsObjectInterface.h`; read/write interfaces templated on `EThreadContext::{External,Internal}`; handles from `UPrimitiveComponent::GetPhysicsObjectById/ByName`) | Locked-access API used by Mover. | Not needed |
| `UPrimitiveComponent::AddForce / AddForceAtLocation` from normal Tick | Applied once per frame as an external force over the whole (variable/fixed) step; frame-rate coupled | Fine for props, not for tires |

Entry point to the PT handle from the async tick: `FBodyInstanceAsyncPhysicsTickHandle H = Prim->GetBodyInstanceAsyncPhysicsTickHandle(); Chaos::FRigidBodyHandle_Internal* PT = H.operator->();` (`BodyInstance.h` line 336, `PrimitiveComponent.h` line ~2349). The PT handle API (`ParticleHandle.h`): `X() R() V() W() M() InvM() CenterOfMass() ObjectState() AddForce() AddTorque() SetLinearImpulse()`; note `AddForce(F)` does `Acceleration += F * InvM` and `AddTorque(T)` does `AngularAcceleration += WorldInvI * T`, and `FPBDRigidsEvolutionGBF::EndFrame` zeroes both accumulators for all dynamic particles every step - so forces must be re-applied EVERY physics step (which the per-step callback does). [SRC]

Units: Chaos/UE use centimetres, kilograms and seconds, so a force is in kg*cm/s^2 (1 N = 100 of those) and `V()` is cm/s, `W()` is rad/s. Simplest rule: write the sim formulas in SI (metres, N, kg), convert positions/velocities from cm to m on the way in, and multiply the final force vector by 100 before `AddForce`. If the torque is formed as `Cross(P_cm - ComW_cm, F_ue)` it is automatically in the right unit for `AddTorque`. Speed conversion for the HUD: 1 cm/s = 0.036 km/h.

#### 1.5.2 Thread-safety of line traces (important finding)

`Engine\Source\Runtime\Engine\Private\Collision\SceneQuery.cpp`, `GetThreadQueryContext(Solver)`: [SRC]

- If `Solver.IsGameThreadFrozen()` (= fixed-tick / `RunOnFrozenGameThread` callbacks are executing, i.e. inside `AsyncPhysicsTickComponent`) and the caller is on the game thread, the query uses `EThreadQueryContext::PTDataWithGTObjects`: the physics-thread (current step) acceleration structure, with hits converted back to game-thread objects (`UPrimitiveComponent`, `UPhysicalMaterial`). That is exactly what a per-step suspension raycast wants.
- In every other case (including the Chaos Vehicles TSimCallbackObject, which runs on a physics worker thread) the code returns `GTData` with the comment "need a way to know we are on a physics thread task (this isn't supported yet)". Chaos Vehicles therefore queries the GT/interpolated structure from the PT.
- A real PT-side API exists but is marked experimental/internal: `Chaos::Private::FGenericPhysicsInterface_Internal::{SpherecastMulti, GeomSweepMulti, RaycastMulti}` (`Physics\GenericPhysicsInterface.h`, `UE_EXPERIMENTAL(5.6)`, calls `Chaos::EnsureIsInPhysicsThreadContext()`).

Consequence: with the async-tick design, plain `GetWorld()->LineTraceSingleByObjectType(...)` is safe and queries PT data. Do NOT call UObject-touching code from a TSimCallbackObject.

#### 1.5.3 Recommended physics settings

`Config/DefaultEngine.ini` (project currently has none; defaults from `PhysicsSettings.cpp`: `bTickPhysicsAsync=false`, `AsyncFixedTimeStepSize=1/30`, `bSubstepping=false`, `MaxSubstepDeltaTime=1/60`, `MaxSubsteps=6`, `MaxPhysicsDeltaTime=1/30`): [SRC]

```ini
[/Script/Engine.PhysicsSettings]
bTickPhysicsAsync=True
AsyncFixedTimeStepSize=0.016667   ; baseline 60 Hz; try 0.008333 (120 Hz) if there is jitter above ~200 km/h
bSubstepping=False
bSubsteppingAsync=False
MaxPhysicsDeltaTime=0.033333
bDisableCCD=False
+PhysicalSurfaces=(Type=SurfaceType1,Name="Asphalt")
+PhysicalSurfaces=(Type=SurfaceType2,Name="Concrete")
+PhysicalSurfaces=(Type=SurfaceType3,Name="Dirt")
+PhysicalSurfaces=(Type=SurfaceType4,Name="Gravel")
+PhysicalSurfaces=(Type=SurfaceType5,Name="Grass")
+PhysicalSurfaces=(Type=SurfaceType6,Name="Sand")
+PhysicalSurfaces=(Type=SurfaceType7,Name="Rock")
+PhysicalSurfaces=(Type=SurfaceType8,Name="Water")
```

- `AsyncFixedTimeStepSize` is read when the physics scene is created (`FPhysScene_Chaos` ctor passes it to the solver, `PhysScene_Chaos.cpp` line ~549), so it must be in the ini, not changed late. A single body can request a smaller step: `FBodyInstance::bOverrideSolverAsyncDeltaTime` + `SolverAsyncDeltaTime` (solver uses the minimum). [SRC]
- A forum snippet for Chaos Mover uses `AsyncFixedTimeStepSize=0.016667`; the Level Up / dev.to articles argue async physics is what stabilises Chaos suspensions, but their text could not be fetched. [COM]
- Because the async tick forces a GT/PT sync every step, verify cost with `stat unit` / `stat physics` at 60 and 120 Hz before committing to 120.

#### 1.5.4 Surface type from hits

- Make the trace return it: `FCollisionQueryParams::bReturnPhysicalMaterial = true` (default false). Then `Hit.PhysMaterial` (TWeakObjectPtr<UPhysicalMaterial>) and `Hit.PhysMaterial->SurfaceType` (`EPhysicalSurface`, SurfaceType1..62; names come from `UPhysicsSettings::PhysicalSurfaces`). `UPhysicalMaterial::DetermineSurfaceType(PM)` resolves nulls. [SRC]
- Where the material comes from [SRC `CollisionConversions.cpp`, `BodyInstance.cpp`]:
  - Landscape heightfield: per-sample from `ULandscapeLayerInfoObject::PhysMaterial` of the dominant layer (6-bit material index per quad: `QF_PhysicalMaterialMask = 63`, so at most 63 physical materials per landscape component), resolved through `GetMaterialFromInternalFaceIndex` for Heightfield hits.
  - Static meshes, SIMPLE collision: one material per body = `FBodyInstance::GetSimplePhysicalMaterial()` (component `PhysMaterialOverride` -> body setup `PhysMaterial` -> engine default).
  - Static meshes, COMPLEX collision (trace with `bTraceComplex=true` or `CTF_UseComplexAsSimple`): per-material-slot physical materials (`UMaterialInterface` physical material, `GetComplexPhysicalMaterials`), resolved by triangle.
  - Easiest robust rule for generated roads: call `SetPhysMaterialOverride(PM_Asphalt)` on every road/bridge/tunnel mesh component and give every landscape layer info a physical material.
- Create the physical material assets once with Python (`AssetTools.create_asset(name, path, unreal.PhysicalMaterial, unreal.PhysicalMaterialFactoryNew())` - [UNV]) or at runtime with `NewObject<UPhysicalMaterial>(GetTransientPackage())` and set `Friction`, `SurfaceType`. Keep the real tire grip in a table keyed by `EPhysicalSurface` in the car data asset; use `UPhysicalMaterial::Friction` only for body/ground scraping.
- Multiply the table value with a runtime wetness factor (weather subsystem); wetness is not part of the physical material.

#### 1.5.5 Collision channels and responses

- Built-in profile `Vehicle` (object type `Vehicle`, QueryAndPhysics, "blocks Vehicle, WorldStatic and WorldDynamic, other channels default") is in `Engine\Config\BaseEngine.ini` line 3119; `AWheeledVehiclePawn` uses it. [SRC]
- For the wheel probes use object-type queries: `LineTraceSingleByObjectType(Hit, A, B, FCollisionObjectQueryParams(FCollisionObjectQueryParams::AllStaticObjects), Params)` - hits only `WorldStatic` (landscape, roads, rocks, bridges) and ignores `Vehicle`/`PhysicsBody`/`Pawn` objects (traffic, props). Add `ECC_WorldDynamic` via `AddObjectTypesToQuery(ECC_WorldDynamic)` if ramps/platforms are movable. No config change needed. [SRC for the API; behaviour per standard UE semantics]
- 5.8 API note: object-type query masks are now 64 bit (`GetObjectTypesToQuery()` / `SetObjectTypesToQuery(int64)`); the `int32 ObjectTypesToQuery` member and `GetAll...QueryFlag()` are `UE_DEPRECATED(5.8)`. [SRC]
- Ensure roads / terrain / guard rails / bridges use blocking presets (`BlockAll` is `WorldStatic`, QueryAndPhysics); foliage and small props should be `NoCollision` or `OverlapAll` so rays and tires ignore them.
- Vehicle body: simple collision only (a few `UCX_` convex hulls from Blender), `bNotifyRigidBodyCollision=true` for crash audio/damage (`MinDeltaVelocityForHitEvents` in `UPhysicsSettings::ChaosSettings` filters tiny hits), wheels/body visual children `NoCollision`.

#### 1.5.6 Center of mass, inertia, CCD, damping, sleeping

`FBodyInstance` / `UPrimitiveComponent` (all [SRC], `BodyInstance.h`, `PrimitiveComponent.h`):

- Mass: `UPrimitiveComponent::SetMassOverrideInKg(NAME_None, Kg, true)`. COM: `UPrimitiveComponent::SetCenterOfMass(FVector Offset)` = `BodyInstance.COMNudge` (offset relative to the computed COM). Inertia: `BodyInstance.InertiaTensorScale` (X roll, Y pitch, Z yaw), then `BodyInstance.UpdateMassProperties()` if the physics state already exists. Typical: COM 45-55 cm above ground, low; yaw scale 0.85-1.0 for responsive turn-in.
- `bInertiaConditioning` defaults to TRUE in 5.8 (`BodyInstance.cpp` line 392): it inflates inertia of long thin bodies. For cars call `BodyInstance.SetInertiaConditioningEnabled(false)` so `InertiaTensorScale` is the only knob.
- Damping: `SetLinearDamping` default 0.01 (leave ~0, let aero do drag), `SetAngularDamping` small (0.2-1) mostly for airborne stability; `SetPhysicsMaxAngularVelocityInRadians` to cap spin after crashes.
- CCD: `BodyInstance.bUseCCD` default false (Epic's `AWheeledVehiclePawn` sets it true); at 70 m/s a 1/60 s step moves 1.16 m, so enable CCD on the player car and make guard rails / walls at least 30-40 cm thick; keep `UPhysicsSettings::bDisableCCD=false`.
- Solver iterations per body: `SetPositionSolverIterationCount` / `SetVelocitySolverIterationCount` (uint8) if landings jitter.
- Sleeping: parked bodies go to sleep and then ignore forces (PT `ObjectState() == Sleeping`); on input or when speed > threshold call `Prim->WakeRigidBody()` from the game thread (Chaos Vehicles does the same, `WakeAllEnabledRigidBodies`). In the async tick early-out when `ObjectState() != Dynamic`.
- Reset / respawn: `SetActorTransform(..., false, nullptr, ETeleportType::TeleportPhysics)` then `SetPhysicsLinearVelocity(0)` / `SetPhysicsAngularVelocityInRadians(0)`.

#### 1.5.7 Skeleton design (recommended)

Classes (all C++, data-driven):

- `UFzCarSpec : UPrimaryDataAsset` - mass, COM offset, inertia scale, wheel layout (hub local position, radius, width, travel up/down), spring rate/damper/bump-stop/anti-roll per axle, engine torque curve (`FRuntimeFloatCurve` rpm -> Nm), idle/redline, gear ratios, final drive, shift RPMs, drivetrain (FWD/RWD/AWD + front split), brake torque + bias, handbrake, steering lock + speed curve, tire params per `EPhysicalSurface` (peak mu, peak slip angle, falloff, rolling resistance), aero (Cd*A, Cl*A, balance), assist defaults, audio profile (cylinders, harmonic mix, turbo), UI stats/class label.
- `AFzVehicle : APawn` - root `UStaticMeshComponent* Chassis` (simulate physics, `Vehicle` profile, hull collision, mass/COM set in constructor/`OnConstruction`), visual body/wheel children (NoCollision), camera rig (`USpringArmComponent` + cameras), lights, `UFzVehicleSim* Sim`, `UFzEngineSynth* EngineAudio`, FX components.
- `UFzVehicleSim : UActorComponent` - the sim; ticks in `AsyncPhysicsTickComponent` (physics) and `TickComponent` (visuals, camera, HUD data, FX, audio parameters).

Core of the async tick (compile-untested; headers: `PhysicsEngine/BodyInstance.h`, `PhysicsProxy/SingleParticlePhysicsProxy.h`, `Chaos/ParticleHandle.h`, `Chaos/Particle/ParticleUtilities.h`, `CollisionQueryParams.h`):

```cpp
UFzVehicleSim::UFzVehicleSim()
{
    PrimaryComponentTick.bCanEverTick = true;
    PrimaryComponentTick.TickGroup = TG_PrePhysics;   // input -> sim struct; visuals read telemetry
    SetAsyncPhysicsTickEnabled(true);                   // flag only; registered when the component registers
}

void UFzVehicleSim::AsyncPhysicsTickComponent(float Dt, float SimTime)
{
    Super::AsyncPhysicsTickComponent(Dt, SimTime);
    if (!Body || !Spec) return;
    FBodyInstanceAsyncPhysicsTickHandle H = Body->GetBodyInstanceAsyncPhysicsTickHandle();
    if (!H) return;
    Chaos::FRigidBodyHandle_Internal* PT = H.operator->();
    if (PT->ObjectState() != Chaos::EObjectStateType::Dynamic) return;

    const FTransform TM(PT->R(), PT->X());
    const FVector ComW  = Chaos::FParticleUtilitiesGT::GetCoMWorldPosition(PT);
    const FVector V     = PT->V();            // cm/s
    const FVector Wrad  = PT->W();            // rad/s
    const FVector Up = TM.GetUnitAxis(EAxis::Z), Fwd = TM.GetUnitAxis(EAxis::X), Right = TM.GetUnitAxis(EAxis::Y);

    FCollisionQueryParams Q(SCENE_QUERY_STAT(FzWheelProbe), /*bTraceComplex*/ false, GetOwner());
    Q.bReturnPhysicalMaterial = true;
    const FCollisionObjectQueryParams Statics(FCollisionObjectQueryParams::AllStaticObjects);

    for (int32 i = 0; i < Wheels.Num(); ++i)
    {
        FFzWheel& W = Wheels[i]; const FFzWheelSpec& S = Spec->Wheels[i];
        const FVector Top = TM.TransformPosition(S.HubRest + FVector(0, 0, S.TravelUp));
        FHitResult Hit;
        const bool bHit = GetWorld()->LineTraceSingleByObjectType(Hit, Top, Top - Up * (S.TravelUp + S.TravelDown + S.Radius), Statics, Q);
        // 1) suspension: length = Hit.Distance - S.Radius; compression rate from previous length / Dt;
        //    Fz = k*x + c*xdot (+ progressive bump stop near limits) + anti-roll; clamp >= 0; apply along Up (or hit normal blend)
        // 2) contact velocity: Vc = V + Cross(Wrad, Hit.ImpactPoint - ComW)
        // 3) surface: EPhysicalSurface Surf = UPhysicalMaterial::DetermineSurfaceType(Hit.PhysMaterial.Get()); mu = Spec->Tire[Surf] * Weather.Wetness...
        // 4) tire forces (below) -> world force F at Hit.ImpactPoint
        AddForceAt(PT, ComW, F, Hit.ImpactPoint);
    }
    // aero drag/downforce at ComW, rolling resistance, engine/gearbox update, air stabilisation torque when no wheel grounded
}

static FORCEINLINE void AddForceAt(Chaos::FRigidBodyHandle_Internal* PT, const FVector& ComW, const FVector& F, const FVector& P)
{
    PT->AddForce(F);                                        // Acceleration += F / m  (cleared every step by the evolution)
    PT->AddTorque(FVector::CrossProduct(P - ComW, F));      // AngularAcceleration += WorldInvI * T
}
```

Model summary for the sim (so the first iteration is sane):

- Suspension: spring-damper per wheel along body up, bump-stops (progressive), per-axle anti-roll force `kARB * (compL - compR)` added/subtracted; weight transfer then emerges from the per-wheel loads. Damping ratio 0.5-0.7 sports, 0.35-0.5 off-road [COM ranges]. Keep spring forces >= 0.
- Tire: per wheel, longitudinal slip ratio `kappa = (omega*R - vx)/max(|vx|, eps)` with wheel `omega` integrated from drive torque - brake torque - Fx*R; lateral slip angle `alpha = atan2(vy, max(|vx|, eps))`; `Fx = mu*Fz*f(kappa)`, `Fy = mu*Fz*g(alpha)` with a Pacejka-lite `D*sin(C*atan(B*s))` or brush curve per surface; combine with a friction ellipse (scale the pair so `sqrt((Fx/mux)^2 + (Fy/muy)^2) <= Fz`); regularise below ~2 m/s (blend toward viscous damping) to avoid standstill jitter; load sensitivity `mu = mu0*(1 - ks*(Fz/Fz0 - 1))`. Apply at the contact point projected onto the ground plane (hit normal).
- Engine / gearbox / diff: `rpm = |wheel_omega_avg| * gear * final * 60/(2*pi)` with idle floor and rev-limiter cut; wheel torque = `T(rpm)*throttle*gear*final*eff`; open / simple LSD by splitting torque with a lock factor; AWD front split; engine braking; auto shift by RPM + load; shift time.
- Steering: lock reduces with speed (curve in km/h, e.g. 1.0 at 0, ~0.45 at 100 km/h, ~0.2 at 250 km/h), plus a steering-assist yaw-rate target and counter-steer help; Ackermann geometry optional.
- Aero: `F = 0.5*rho*v^2*A*C` along -velocity for drag, along -Up for downforce; split front/rear for balance.
- Assists: TC (reduce drive torque on wheel slip), ABS (release brake torque at slip), stability control (yaw error -> differential braking), launch control; each toggle read from `UFzAssistSettings` (console `assist <name> on|off`).
- Air control: low angular damping + gentle torque toward velocity-aligned attitude so jump landings are stable; progressive bump-stops cover compression.
- Telemetry struct written in the async tick (speed, rpm, gear, per-wheel slip/surface/load, G-forces, airborne) and read by the same thread's `TickComponent` -> HUD, audio, FX, skid marks, activity scoring (drift angle).

Fixed-step determinism for automated tests: with `bTickPhysicsAsync` the same inputs per step give repeatable 0-100 / braking / skidpad numbers; drive tests inject `FFzInput` from a script (console command `fz.test <name>`), write results to `Saved/Logs` and `DEVELOPMENT.md`.

#### 1.5.8 Camera / transform interpolation

In async mode the game-thread transform of the chassis is interpolated between solver results, so visual follow cameras should tick in `TG_PostPhysics` and read `GetComponentTransform()`; sim code inside the async tick must read the PT handle (`X()/R()/V()/W()`) and never the component transform. [SRC for interpolation design, behaviour UNV until run]

### 1.6 Recommendation

Build the project-owned vehicle (section 1.5). Reasons: no skeletal-mesh/physics-asset/AnimBP asset requirement (cars are plain Blender static meshes with separate wheels and `UCX_` hulls), tire/surface/weather/assist behaviour fully under our control and data-driven per car, no dependence on an Experimental plugin, the same component can run player and nearby traffic, and the async tick gives fixed-dt stability plus PT-correct scene queries. Cost: we write ~1000 lines of sim and must tune it; budget the first day for 0-100 / skidpad / 250 km/h tests. Keep one optional half-day Chaos Vehicles spike (section 1.3 skeleton) only if the first prototype misbehaves.

---------------------------------------------------------------------------------------------------

## 2. Enhanced Input from C++

Facts [SRC unless tagged]:

- Plugin `EnhancedInput` is `EnabledByDefault: true`; module `EnhancedInput` (already in `Sonnet55Forza.Build.cs`). Project `Config/DefaultInput.ini` already sets `DefaultPlayerInputClass=/Script/EnhancedInput.EnhancedPlayerInput` and `DefaultInputComponentClass=/Script/EnhancedInput.EnhancedInputComponent`.
- Headers: `InputAction.h` (`UInputAction::ValueType = EInputActionValueType::{Boolean,Axis1D,Axis2D,Axis3D}`, `bConsumeInput`, `Triggers`, `Modifiers`), `InputMappingContext.h`, `InputModifiers.h`, `InputTriggers.h`, `EnhancedInputComponent.h`, `EnhancedInputSubsystems.h`.
- 5.7 change: `UInputMappingContext::Mappings` is deprecated/redirected to `DefaultKeyMappings.Mappings`; use `MapKey()` / `GetMappings()`; `MapKey(const UInputAction*, FKey)` returns `FEnhancedActionKeyMapping&` (has `Modifiers`, `Triggers` arrays). Doc comment says Map/Unmap are meant for config screens, but they work at runtime to build a context in code.
- Modifiers available: `UInputModifierDeadZone` (`LowerThreshold`, `UpperThreshold`, `Type`), `UInputModifierNegate`, `UInputModifierScalar`, `UInputModifierSwizzleAxis`, `UInputModifierSmooth`, `UInputModifierResponseCurveExponential/User`, `ScaleByDeltaTime`, `ToWorldSpace`, `FOVScaling`. Triggers: Down, Pressed, Released, Hold, HoldAndRelease, Tap, RepeatedTap, Pulse, ChordAction, ChordBlocker.
- Binding: `UEnhancedInputComponent::BindAction(Action, ETriggerEvent, Object, &Class::Func)` (callback signatures with `const FInputActionValue&` or `const FInputActionInstance&`), `BindActionValueLambda`, `BindActionInstanceLambda`, `BindDebugKey` (dev builds), `GetBoundActionValue(Action)`. Legacy `BindAxis/BindKey` are `= delete`d unless `ENHANCED_INPUT_ALLOW_LEGACY_BINDING=1`.
- PITFALL: `BindActionValue(Action)` returns a reference into `TArray<FEnhancedInputActionValueBinding> EnhancedActionValueBindings` (a plain TArray, `EnhancedInputComponent.h` line 384). Binding another action can reallocate the array and dangle a cached reference. Poll with `EIC->GetBoundActionValue(Action)` (after one `BindActionValue(Action)` per action) or handle Triggered + Completed events.
- ETriggerEvent semantics [DOC]: Started, Ongoing, Triggered, Completed, Canceled. For continuous analog vehicle input prefer polling the value every tick (it reads 0 after release) instead of relying on Triggered (does not fire when the value is zero).
- Add the context: `ULocalPlayer* LP = GetLocalPlayer(); LP->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>()->AddMappingContext(IMC, Priority)`; `RemoveMappingContext`; use a second higher-priority context for menus/photo mode and `FModifyContextOptions` to ignore lower contexts. 5.8 release notes: Enhanced Input and Common Input/UI are merged ("Unified Input System"), no breaking change was seen in the headers. [DOC][SRC]
- Keep created objects alive: store `UInputAction*` / `UInputMappingContext*` in `UPROPERTY()` members of the PlayerController (they are plain UObjects created with `NewObject<>(this)`; no asset needed).

Skeleton:

```cpp
void AFzPlayerController::BuildInput()
{
    auto MakeAction = [this](const TCHAR* Name, EInputActionValueType T) {
        UInputAction* A = NewObject<UInputAction>(this, Name); A->ValueType = T; return A; };
    IA_Steer = MakeAction(TEXT("IA_Steer"), EInputActionValueType::Axis1D);
    IA_Throttle = MakeAction(TEXT("IA_Throttle"), EInputActionValueType::Axis1D);
    IA_Brake = MakeAction(TEXT("IA_Brake"), EInputActionValueType::Axis1D);
    IA_Handbrake = MakeAction(TEXT("IA_Handbrake"), EInputActionValueType::Boolean);
    IA_ShiftUp/Down, IA_Camera, IA_Look (Axis2D), IA_Horn, IA_Lights, IA_Reset, IA_Garage, IA_Photo ...

    IMC_Driving = NewObject<UInputMappingContext>(this, TEXT("IMC_Driving"));
    IMC_Driving->MapKey(IA_Steer, EKeys::D);
    IMC_Driving->MapKey(IA_Steer, EKeys::A).Modifiers.Add(NewObject<UInputModifierNegate>(this));
    UInputModifierDeadZone* DZ = NewObject<UInputModifierDeadZone>(this); DZ->LowerThreshold = 0.12f;
    IMC_Driving->MapKey(IA_Steer, EKeys::Gamepad_LeftX).Modifiers.Add(DZ);
    IMC_Driving->MapKey(IA_Throttle, EKeys::W);  IMC_Driving->MapKey(IA_Throttle, EKeys::Gamepad_RightTriggerAxis);
    IMC_Driving->MapKey(IA_Brake, EKeys::S);     IMC_Driving->MapKey(IA_Brake, EKeys::Gamepad_LeftTriggerAxis);
    IMC_Driving->MapKey(IA_Handbrake, EKeys::SpaceBar); IMC_Driving->MapKey(IA_Handbrake, EKeys::Gamepad_FaceButton_Right);
}
void AFzPlayerController::SetupInputComponent()
{
    Super::SetupInputComponent();
    BuildInput();
    if (auto* EIC = Cast<UEnhancedInputComponent>(InputComponent))
    {
        for (UInputAction* A : { IA_Steer.Get(), IA_Throttle.Get(), IA_Brake.Get() }) EIC->BindActionValue(A);
        EIC->BindAction(IA_Handbrake, ETriggerEvent::Started,   this, &ThisClass::OnHandbrake, true);
        EIC->BindAction(IA_Handbrake, ETriggerEvent::Completed, this, &ThisClass::OnHandbrake, false);
        EIC->BindAction(IA_Garage, ETriggerEvent::Started, this, &ThisClass::ToggleGarage);
    }
}
void AFzPlayerController::BeginPlay() { Super::BeginPlay();
    if (ULocalPlayer* LP = GetLocalPlayer()) if (auto* Sub = LP->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>()) Sub->AddMappingContext(IMC_Driving, 0); }
void AFzPlayerController::PlayerTick(float Dt) { Super::PlayerTick(Dt);
    if (auto* EIC = Cast<UEnhancedInputComponent>(InputComponent)) if (AFzVehicle* V = Cast<AFzVehicle>(GetPawn()))
        V->Sim->Input = { EIC->GetBoundActionValue(IA_Throttle).Get<float>(), EIC->GetBoundActionValue(IA_Brake).Get<float>(), EIC->GetBoundActionValue(IA_Steer).Get<float>(), bHandbrake }; }
```

Notes: keyboard throttle/brake/steer need rise/fall smoothing in the sim (Chaos uses 100-250 ms; [COM] numbers: gamepad deadzone 0.10-0.15, exponent 1.5-2.0). Console key `Tilde` is bound by the engine console (`BaseInput.ini` `+ConsoleKeys=Tilde`) - do not map it. `IA_*` objects can be re-mapped at runtime (settings menu) by editing contexts and calling `UEnhancedInputLibrary::RequestRebuildControlMappingsForContext`.

---------------------------------------------------------------------------------------------------

## 3. HUD, minimap, console and garage menu from C++ (no Blueprint assets)

### 3.1 Options compared

| Approach | Pros | Cons | Use for |
|---|---|---|---|
| `AHUD::DrawHUD()` with `UCanvas` / `DrawText`, `DrawRect`, `DrawLine`, `DrawTexture`, `DrawMaterial` (`Classes/GameFramework/HUD.h`) | 10 lines, zero setup, works in -game | Immediate mode, no layout/input widgets, bitmap font scaling is crude | Debug/benchmark overlay (FPS, coordinates, telemetry), on-screen console hint |
| Slate (`SCompoundWidget`, `SLeafWidget` with `OnPaint`) added by `GEngine->GameViewport->AddViewportWidgetContent(Widget, ZOrder)` | Full control, resolution independent with `FSlateLayoutTransform`, no assets, widgets for lists/text boxes (`SListView`, `STileView`, `SEditableTextBox`, `SScrollBox`, `SButton`, `SProgressBar`) | More verbose C++ | Production HUD, garage, debug menu, notifications |
| UMG from C++ (`UUserWidget` subclass, `WidgetTree->ConstructWidget<UCanvasPanel>()`, `CreateWidget<>`) | Layout widgets as UObjects, animations/material brushes are easier | Native `UUserWidget` without a Blueprint class works (`Initialize()` creates the `WidgetTree` when null and runs `InitializeNativeClassData()`, `UserWidget.cpp` line 135) but you build every widget in code anyway | Only if you want UMG-only features (UWidgetAnimation, `URichTextBlock` styles) |
| Scene capture / render target minimap | Looks like a real map | Per-frame full scene render with Lumen/Nanite is expensive at 60 fps | NOT recommended; at most a one-time baked terrain tint |

Recommendation: Slate for everything player-facing, plus the `AHUD` canvas for debug text. Add `"Slate", "SlateCore"` to the module (and `"UMG"` only if used).

Slate facts [SRC]:
- Draw API (`SlateCore/Public/Rendering/DrawElementTypes.h`): `FSlateDrawElement::MakeBox`, `MakeRotatedBox(ElementList, Layer, PaintGeometry, Brush, ESlateDrawEffect, Angle, RotationPoint, RotationSpace, Tint)`, `MakeLines(ElementList, Layer, PaintGeometry, TArray<FVector2f/FVector2d> Points, Effects, Tint, bAntialias, Thickness)` (also per-point colours), `MakeSpline`, `MakeText(..., FString/FText, FSlateFontInfo, ...)`.
- Paint geometry in 5.x: `AllottedGeometry.ToPaintGeometry()` and `ToPaintGeometry(FVector2f LocalSize, FSlateLayoutTransform(Offset[, Scale]))`; the older `(Offset, Size, Scale)` overloads are `UE_DEPRECATED(5.2)`.
- Fonts: `FCoreStyle::GetDefaultFontStyle("Bold"|"Regular"|"Light"|"Italic", Size)`; engine ships `Engine/Content/Slate/Fonts/Roboto-*.ttf` so it works in -game. Brushes: `FSlateColorBrush`, `FSlateRoundedBoxBrush`, `FSlateBoxBrush`, `FSlateDynamicImageBrush`, or `FSlateBrush::SetResourceObject(UTexture2D*)`.
- Clipping: `OutDrawElements.PushClip(FSlateClippingZone(AllottedGeometry))` / `PopClip()` for the square minimap.
- Invalidation: `Slate.EnableGlobalInvalidation` defaults to false (`SlateCoreClasses.cpp`), so custom `OnPaint` widgets repaint each frame; if it is ever turned on call `ForceVolatile(true)` on dynamic widgets.
- Keep HUD widgets `EVisibility::SelfHitTestInvisible`/`HitTestInvisible` so they never swallow mouse input; menus use `APlayerController::SetInputMode(FInputModeUIOnly().SetWidgetToFocus(Widget))` / `FInputModeGameAndUI`, `SetShowMouseCursor(true)`, and a higher-priority Enhanced Input context.

HUD pattern:

```cpp
class SFzHud : public SLeafWidget
{
public:
    SLATE_BEGIN_ARGS(SFzHud) {} SLATE_END_ARGS()
    void Construct(const FArguments&) {}
    virtual FVector2D ComputeDesiredSize(float) const override { return FVector2D(1920, 1080); }
    virtual int32 OnPaint(const FPaintArgs&, const FGeometry& G, const FSlateRect&, FSlateWindowElementList& Out,
                          int32 Layer, const FWidgetStyle&, bool) const override
    {
        // tachometer arc: TArray<FVector2f> Pts; ... FSlateDrawElement::MakeLines(Out, Layer, G.ToPaintGeometry(), Pts, ESlateDrawEffect::None, Col, true, 4.f);
        // speed text:     FSlateDrawElement::MakeText(Out, Layer + 1, G.ToPaintGeometry(FVector2f(200, 60), FSlateLayoutTransform(FVector2f(X, Y))), SpeedStr, FCoreStyle::GetDefaultFontStyle("Bold", 56), ESlateDrawEffect::None, FLinearColor::White);
        return Layer + 2;
    }
};
// AFzHUD::BeginPlay: HudWidget = SNew(SFzHud); GEngine->GameViewport->AddViewportWidgetContent(HudWidget.ToSharedRef(), 10);
// EndPlay: GEngine->GameViewport->RemoveViewportWidgetContent(HudWidget.ToSharedRef());
```
Data flow: the widget holds a `TWeakObjectPtr<AFzVehicle>` / pointer to the telemetry struct (read on game thread; Slate paint is on the game thread unless the Slate render thread cache is used).

### 3.2 Minimap

- Data: the road generator already owns polylines. Store per road class `TArray<FVector2f>` in world XY (cm) in a `UFzMapSubsystem` (`UWorldSubsystem`). 60 km of road at 25 m sampling is ~2400 points per class - trivial.
- Draw: in the minimap widget `OnPaint`, transform points: `p = Rot(-heading) * (world - player) * scale`, cull by the square, batch into one `MakeLines` per road class (width/colour per class, outline pass first). Player arrow = 3-point polyline in the centre; waypoint / event icons via `MakeBox`/`MakeText`. Zoom with speed.
- Optional underlay: generate a `UTexture2D::CreateTransient(W,H,PF_B8G8R8A8)` once (terrain height tint, water, roads) with `Mip.BulkData.Lock(LOCK_READ_WRITE)` + `UpdateResource()`, draw with `MakeRotatedBox`. [UNV for the 5.8 `GetPlatformData()` access pattern]
- GPS route: A* over the road graph (also needed for traffic), draw the polyline on the minimap and optionally as an in-world ribbon.
- Full map (stretch): same widget with bigger scale, pan and zoom, region labels.

### 3.3 Console

- The engine console (class `UConsole`, default key Tilde via `BaseInput.ini` `+ConsoleKeys=Tilde`) exists in Development builds (-game runs). Its autocomplete list is built from `IConsoleManager::ForEachConsoleObjectThatStartsWith` plus `UConsoleSettings::ManualAutoCompleteList` (`Console.cpp` lines 182-220), `UFUNCTION(Exec)` methods on `APlayerController`, possessed `APawn`, `AHUD`, `AGameModeBase`, `UCheatManager`, `UGameInstance` are executable but not auto-listed unless added to `ManualAutoCompleteList`. [SRC]
- Therefore: register ALL project commands once through `IConsoleManager` (section 7) and ADOPT the engine console for the "toggle with backtick" requirement; add an on-screen hint ("~ console   F1 garage   F2 debug") drawn from `AHUD`.
- If a custom Slate console is wanted (nicer for recorded videos): `SEditableTextBox` + `SScrollBox` log, submit through `GEngine->Exec(World, *Cmd, *GLog)` or `PC->ConsoleCommand(Cmd)`, and remove Tilde from the engine console in `DefaultInput.ini` (`-ConsoleKeys=Tilde` / add another key) to avoid two consoles opening. The Slate text box eats keys, so close it from `OnPreviewKeyDown`.

### 3.4 Garage / car-select menu and benchmark menu

- Showroom approach: spawn the selected car on a turntable actor and move the view target to a showroom `ACameraActor` (`SetViewTargetWithBlend`) while a translucent Slate overlay draws the list (`SListView<TSharedPtr<FFzCarEntry>>` or `STileView`) and stat bars (custom `OnPaint` or `SProgressBar`). No render target needed.
- Debug/benchmark menu: Slate vertical list of buttons/sliders/checkboxes (`SButton`, `SCheckBox`, `SSlider`, `SSpinBox`, `SComboBox`) calling the same console commands (`tp`, `time`, `weather`, `traffic`, `car`, `assist`). Keep it on a separate toggle key and mapping context so normal free-roam is untouched.

---------------------------------------------------------------------------------------------------

## 4. Project-owned procedural engine audio

### 4.1 Options

| Option | Facts | Verdict |
|---|---|---|
| `USynthComponent` + `ISoundGenerator` (C++) | `Engine\Source\Runtime\AudioMixer\Public\Components\SynthComponent.h`; `USynthComponent` is a `USceneComponent` (abstract, `bAutoActivate=false`, `bAllowSpatialization`, `AttenuationSettings` / `AttenuationOverrides`, `SoundClass`, `SoundSubmix`, `SynthCommand(TFunction<void()>)` for render-thread parameter changes). New style: override `CreateSoundGenerator(const FSoundGeneratorInitParams&)` returning an `ISoundGeneratorPtr`; the generator implements `OnGenerateAudio(float* Out, int32 NumSamples)` (interleaved), `GetNumChannels()`, optional `GetDesiredNumSamplesToRenderPerCallback()` (default 1024), `OnBeginGenerate/OnEndGenerate`. The old `USynthComponent::OnGenerateAudio` path is "soon to be deprecated". Reference implementation: `Plugins\Runtime\Synthesis\Source\Synthesis\Classes\SynthComponents\SynthComponentToneGenerator.h`. Module deps: `AudioMixer`, `SignalProcessing`, `AudioExtensions`. | ADOPT |
| `USoundWaveProcedural` (`QueueAudio`, `OnSoundWaveProceduralUnderflow`) | Game-thread fed push model, latency and underflow handling needed, harder to modulate per buffer | SKIP |
| MetaSounds Builder API (C++) | `UMetaSoundBuilderSubsystem::CreateSourceBuilder(Name, OnPlayOut, OnFinishedIn, AudioOutIns, Result, Format, bIsOneShot)`, `UMetaSoundBuilderBase::AddNodeByClassName(FMetasoundFrontendClassName, Result, MajorVersion=1)`, `AddGraphInputNode(Name, DataType, Default, Result)`, `ConnectNodes`, `ConnectNodeOutputToGraphOutput`, `SetNodeInputDefault`, `BuildNewMetaSound(NameBase)` -> transient `UMetaSoundSource`; official docs say the builder API works in Blueprint or C++ "in the Editor and at runtime" (runtime = MetaSound Builder Subsystem). Standard node class names are `{"UE", "<Node>", "Audio"}` e.g. `Sine`, `Saw`, `Square`, `Noise` (`MetasoundOscillatorNodes.cpp` uses `StandardNodes::Namespace="UE"`, `AudioVariant="Audio"`). Parameter drive: `UAudioComponent::SetFloatParameter("RPM", v)` [UNV]. Modules `MetasoundEngine`, `MetasoundFrontend`. 5.8 adds experimental node configuration/templates. Pin names and node versions must be discovered by reading node sources. | Optional later (ambience), not for the engine |
| `AudioMotorSim` plugin (Experimental) | Compositional motor model that outputs RPM/throttle/boost parameters to an output; no synthesis by itself | SKIP |
| `MotoSynth` plugin (Experimental, "Not supported") | Granular engine synth, needs a recorded engine loop analysed into a `UMotoSynthSource` asset | SKIP (no copyrighted/recorded audio allowed anyway) |

### 4.2 Design of `UFzEngineSynth : USynthComponent`

- Constructor: `NumChannels = 1` (mono so the audio mixer spatialises it) for traffic/external, `2` for the player cockpit/chase mix; `bAllowSpatialization = true`; `PreferredBufferLength = 512` (lower latency than the default 1024; the project's `DefaultEngine.ini` sets `AudioCallbackBufferFrameSize=1024`, 48 kHz, i.e. 21 ms per callback - consider 512); 5.8 makes WASAPI the default Windows backend [DOC release notes].
- `Init(int32& SampleRate)` stores the rate; `CreateSoundGenerator` returns `MakeShared<FFzEngineGenerator, ESPMode::ThreadSafe>(...)`; `Start()` after `RegisterComponent()` (it initialises on demand).
- Parameters (RPM, load/throttle, speed, boost, per-wheel slip/surface for tires, wind) are written from the game thread into `std::atomic<float>` fields of the generator (or posted with `SynthCommand`) and smoothed per buffer (linear ramp from last to target) to avoid zipper noise.
- Engine tone (per cylinder count N, four-stroke): firing frequency `f = RPM/60 * N/2`. Synthesize with a phase accumulator at `f`; waveform = band-limited pulse/saw (PolyBLEP) or a sum of the first 8-16 harmonics with amplitudes from a per-car table (data asset: harmonic weights, "growl" noise amount, intake/exhaust resonant frequencies); add a second slightly detuned bank for lumpy idle (random per-cycle jitter 1-3 %); low-pass cutoff rises with load (one-pole or `Audio::FBiquadFilter`); exhaust resonance as a 2-pole band-pass at 90-200 Hz scaled with RPM; intake noise = white/pink noise (`Audio::FWhiteNoise`, `Audio::FPinkNoise`, `SignalProcessing\Public\DSP\Noise.h`) through a band-pass whose gain follows throttle; on throttle lift add decaying random "crackle" bursts; rev limiter = periodic gain notch at 12-20 Hz; turbo = whistle sine whose pitch follows boost + blow-off = filtered noise burst on lift-off; gear shifts = brief torque dip + thump transient.
- Same generator also renders event one-shots via a lock-free queue (`TMpscQueue`/`TQueue<..., EQueueMode::Spsc>`): shift clunk, horn (harmonic stack + slight vibrato), impacts (noise burst + damped sines), suspension thumps.
- Tire squeal / road noise / wind are separate lightweight generators (or extra voices) per car: squeal = band-pass noise whose centre (1.2-3 kHz) and Q follow slip, amplitude by slip excess; surface timbre (gravel = crackly noise, dirt = low rumble); wind = pink noise through LPF with cutoff and gain ~ speed^2.
- Doppler for traffic: pitch factor `c/(c - v_closing)` applied to the generator's RPM-derived frequency from the game thread; only the nearest ~4-6 traffic cars get a synth, farther cars play nothing or a cheap pass-by event.
- DSP primitives available in `SignalProcessing`: `Audio::FOsc`, `FSineOsc`, `FWaveShaper`, `FBiquadFilter`, `FStateVariableFilter`, `FLadderFilter`, `FEnvelope`, `FEnvelopeFollower`, `FExponentialEase`, `FWhiteNoise`, `FPinkNoise`, `Audio::FAlignedFloatBuffer`. (The old `Audio::FBiquad` is deprecated since 5.5.)
- Cost target: <= 0.3 ms per voice on the audio render thread; player car ~3 voices, traffic ~4 voices.

Skeleton (compile-untested):

```cpp
class FFzEngineGenerator : public ISoundGenerator
{
public:
    FFzEngineGenerator(int32 InRate, int32 InChannels) : Rate(InRate), NumCh(InChannels) {}
    virtual int32 GetNumChannels() const override { return NumCh; }
    virtual int32 GetDesiredNumSamplesToRenderPerCallback() const override { return 512; }
    virtual int32 OnGenerateAudio(float* Out, int32 NumSamples) override
    {
        const int32 Frames = NumSamples / NumCh;
        const float Rpm0 = RpmSm, Rpm1 = Rpm.load(std::memory_order_relaxed);   // ramp across the buffer
        for (int32 i = 0; i < Frames; ++i)
        {
            const float Rpm = FMath::Lerp(Rpm0, Rpm1, float(i) / Frames);
            const float F = Rpm / 60.f * Cylinders * 0.5f;
            Phase += F / Rate; Phase -= FMath::FloorToFloat(Phase);
            float S = 0.f; for (int32 h = 1; h <= 12; ++h) S += Harm[h] * FMath::Sin(2 * PI * h * Phase);   // or PolyBLEP saw
            S = S * Gain + Noise.Generate() * IntakeGain;
            S = Lpf.Process(S);
            for (int32 c = 0; c < NumCh; ++c) *Out++ = S;
        }
        RpmSm = Rpm1; return NumSamples;
    }
    std::atomic<float> Rpm{900.f}, Load{0.f}, Boost{0.f};
    // ...
};
UCLASS() class UFzEngineSynth : public USynthComponent {
    GENERATED_BODY()
    virtual ISoundGeneratorPtr CreateSoundGenerator(const FSoundGeneratorInitParams& P) override
    { Gen = MakeShared<FFzEngineGenerator, ESPMode::ThreadSafe>(P.SampleRate, P.NumChannels); return Gen; }
    TSharedPtr<FFzEngineGenerator, ESPMode::ThreadSafe> Gen;
};
```

---------------------------------------------------------------------------------------------------

## 5. Niagara and FX

Facts [SRC]:

- Runtime API (module `Niagara`, headers `NiagaraFunctionLibrary.h`, `NiagaraComponent.h`, `NiagaraSystem.h`): `UNiagaraFunctionLibrary::SpawnSystemAtLocation(World, System, Loc, Rot, Scale, bAutoDestroy, bAutoActivate, ENCPoolMethod PoolingMethod, bPreCullCheck)`, `SpawnSystemAttached(System, AttachTo, Socket, Loc, Rot, Scale, LocationType, bAutoDestroy, PoolingMethod, bAutoActivate, bPreCullCheck)`, `SpawnSystemAtLocationWithParams(FFXSystemSpawnParameters)`. On the component: `SetVariableFloat/Int/Bool/Vec2/Vec3/Vec4/LinearColor/Quat/Position/Material/StaticMesh/Texture/Object/Actor(FName, value)` and the older `SetNiagaraVariable*(FString, ...)`, `SetAsset`, `SetAutoDestroy`. Variable names must match exposed `User.` parameters.
- Cascade: the runtime classes still exist (`Engine\Classes\Particles`) and the `Cascade` editor plugin is "legacy"; a `CascadeToNiagaraConverter` plugin (Beta, disabled by default) exists. Engine content contains no Cascade FX worth using. SKIP Cascade.
- Engine-provided FX content: searching the whole engine Content/Plugins trees finds NO dust, smoke, rain, splash or spray Niagara systems. What exists: Niagara templates under `/Niagara/DefaultAssets/Templates/...` - systems `DirectionalBurst`, `DirectionalBurstLightweight`, `FountainLightweight`, `RadialBurst`, `SimpleExplosion`, `MinimalLightweight`, `AttributeReaderTrails`; emitters `BlowingParticles`, `ConfettiBurst`, `DirectionalBurst`, `DynamicBeam`, `Fountain`, `HangingParticulates`, `LocationBasedRibbon`, `Minimal`, `OmnidirectionalBurst`, `RecycleParticlesInView`, `SimpleSpriteBurst`, `SingleLoopingParticle`, `StaticBeam`, `UpwardMeshBurst`; default sprite materials (`/Niagara/DefaultAssets/DefaultSpriteMaterial`, `M_DepthFade_SpriteSimple`); plus `/Niagara/Modules/...` and `/Niagara/DynamicInputs/...` building blocks. Scanning the name tables of five templates (DirectionalBurstLightweight, FountainLightweight, RadialBurst, HangingParticulates, BlowingParticles) found no exposed `User.*` parameters, so they are probably not tunable at runtime. The `NiagaraFluids` plugin has smoke/fire grid-fluid materials, but grid fluids are a heavy technique and not a drop-in tire-smoke effect. `Engine\Content\StarterContent` only contains Textures. `FeaturePacks\TP_VehicleAdvBP.upack` is a 118 KB file that is not a zip (not inspected further), so it was not used as a content source.

### 5.1 Authoring Niagara systems without the editor UI (important finding)

`Engine\Plugins\FX\CascadeToNiagaraConverter` (Beta, `EnabledByDefault:false`, editor-time) ships a Python-callable API that edits the Niagara stack programmatically, and its own Python scripts (`Content\Python\*.py`, `Paths.py`) demonstrate it. Classes: `unreal.FXConverterUtilitiesLibrary`, `NiagaraSystemConversionContext` (`add_empty_emitter(name)`, `add_template_emitter(name, template)`, `set_warmup_time`, `finalize()`), `NiagaraEmitterConversionContext` (`find_or_add_module_script(name, CreateScriptContextArgs, ScriptExecutionCategory)`, `set_parameter_directly("Particles.X", input, category)`, `add_renderer(name, renderer_props)`, `set_sim_target`, `set_local_space`, `set_renderer_binding`), `NiagaraScriptConversionContext.set_parameter(name, input)`, input builders `create_script_input_float/vector/linear_color/int/bool/dynamic/linked_parameter(...)`, enum `ScriptExecutionCategory.{EMITTER_SPAWN, EMITTER_UPDATE, PARTICLE_SPAWN, PARTICLE_UPDATE}`. Verified module asset paths (from `Paths.py`): `/Niagara/Modules/Emitter/SpawnRate.SpawnRate`, `.../Emitter/SpawnBurst_Instantaneous`, `.../Emitter/SpawnPerUnit`, `/Niagara/Modules/Spawn/Initialization/V2/InitializeParticle`, `/Niagara/Modules/Spawn/Velocity/AddVelocity`, `/Niagara/Modules/Spawn/Location/V2/ShapeLocation`, `/Niagara/Modules/Update/Forces/{Drag,AccelerationForce}`, `/Niagara/Modules/Update/Color/Color`, `/Niagara/Modules/Update/Size/ScaleSpriteSize`, `/Niagara/Modules/Update/Lifetime/ParticleState`, `/Niagara/Modules/Collision/Collision`, `/Niagara/Modules/Solvers/SolveForcesAndVelocity`, dynamic inputs like `/Niagara/DynamicInputs/UniformRange/V2/RandomRangeFloat`. System asset creation (from `CascadeToNiagaraConverter.py`): `unreal.AssetToolsHelpers.get_asset_tools().create_asset(name, package_path, unreal.NiagaraSystem, unreal.NiagaraSystemFactoryNew())`. Sprite renderer: `r = unreal.NiagaraSpriteRendererProperties(); r.set_editor_property("Material", mat); r.set_editor_property("Alignment", ...); r.set_editor_property("FacingMode", ...); r.set_editor_property("SubImageSize", unreal.Vector2D(8,8)); emitter.add_renderer("Sprite", r)`.

Sketch (Python, run via `UnrealEditor-Cmd -ExecutePythonScript`; [UNV] until executed; plugin `CascadeToNiagaraConverter` must be enabled in the `.uproject` with `"TargetAllowList":["Editor"]`):

```python
import unreal as ue
from unreal import FXConverterUtilitiesLibrary as fx
tools = ue.AssetToolsHelpers.get_asset_tools()
system = tools.create_asset("NS_TireSmoke", "/Game/FX", ue.NiagaraSystem, ue.NiagaraSystemFactoryNew())
ctx = fx.create_system_conversion_context(system)
em = ctx.add_empty_emitter("Smoke")
def mod(path, name, cat):
    return em.find_or_add_module_script(name, ue.CreateScriptContextArgs(fx.create_asset_data(path)), cat)
mod('/Niagara/Modules/Emitter/SpawnPerUnit.SpawnPerUnit', 'SpawnPerUnit', ue.ScriptExecutionCategory.EMITTER_UPDATE)
mod('/Niagara/Modules/Spawn/Initialization/V2/InitializeParticle.InitializeParticle', 'Init', ue.ScriptExecutionCategory.PARTICLE_SPAWN)
mod('/Niagara/Modules/Update/Forces/Drag.Drag', 'Drag', ue.ScriptExecutionCategory.PARTICLE_UPDATE)
mod('/Niagara/Modules/Update/Size/ScaleSpriteSize.ScaleSpriteSize', 'Size', ue.ScriptExecutionCategory.PARTICLE_UPDATE)
mod('/Niagara/Modules/Solvers/SolveForcesAndVelocity.SolveForcesAndVelocity', 'Solve', ue.ScriptExecutionCategory.PARTICLE_UPDATE)
r = ue.NiagaraSpriteRendererProperties(); r.set_editor_property("Material", ue.load_asset('/Game/FX/M_Smoke'))
em.add_renderer("Sprite", r)
ctx.finalize(); ue.EditorAssetLibrary.save_asset('/Game/FX/NS_TireSmoke')
```

OPEN: whether `User.*` parameters can be exposed/linked through this API (`create_script_input_linked_parameter("User.Intensity", ue.NiagaraScriptInputType.FLOAT)` exists, but whether it registers the user parameter on the system is [UNV]). Prototype early. Control knobs that work without user parameters: spawn emitters per wheel and Activate()/Deactivate() them from slip, `SpawnPerUnit` (density proportional to distance moved - ideal for tire smoke and dust trails), `SetWorldScale3D`, `SetCustomTimeDilation`, attach to wheel/body sockets, pool with `ENCPoolMethod`.

### 5.2 Fallback: project-owned CPU particles

If Niagara authoring blocks: a pooled puff system using one `UInstancedStaticMeshComponent` per effect type with a unit sphere or quad mesh (`/Engine/BasicShapes/Sphere`, `/Engine/BasicShapes/Plane`) and a translucent unlit material generated in Python with `unreal.MaterialEditingLibrary` (`create_material_expression`, `connect_material_property`, `recompile_material`); per-instance `PerInstanceCustomData` for age/alpha/colour, `BatchUpdateInstancesTransforms`, 200-500 instances max. Rain: camera-attached streak/curtain mesh with a scrolling material + post-process wetness; splashes from tire-contact spawn. Wetness / puddles via a `UMaterialParameterCollection` set from the weather subsystem (`UWorld::GetParameterCollectionInstance(MPC)->SetScalarParameterValue`). [UNV where noted]

### 5.3 Usage in code (once assets exist)

```cpp
UNiagaraComponent* C = UNiagaraFunctionLibrary::SpawnSystemAttached(TireSmokeSys, WheelMesh, NAME_None, FVector::ZeroVector, FRotator::ZeroRotator,
        EAttachLocation::KeepRelativeOffset, /*bAutoDestroy*/ false, /*bAutoActivate*/ false, ENCPoolMethod::None);
// per tick: slip > threshold ? C->Activate() : C->Deactivate();  C->SetVariableFloat(TEXT("User.Intensity"), Slip) // only if the param exists
```
Surface -> FX mapping table keyed by `EPhysicalSurface` (dust on dirt/gravel/sand, smoke on asphalt, spray when wet).

---------------------------------------------------------------------------------------------------

## 6. Traffic AI

### 6.1 What the engine actually offers (verified locally)

- `MassGameplay` plugin: version 0.4, Experimental, `EnabledByDefault:false`; modules MassCommon, MassActors, MassEQS, MassSpawner, MassSmartObjects, MassSimulation, MassLOD, MassMovement, MassCharacterTrajectory, MassReplication, MassRepresentation, ... 5.8 notes: MassCore module split out, signals into core, new scheduling. `MassAI` plugin (0.4 Experimental): MassNavigation, MassNavMeshNavigation, MassZoneGraphNavigation, MassAIBehavior (path follow tasks, StateTree based), MassCrowd - all human-scale agents (steering/avoidance for pedestrians). [SRC]
- NO `MassTraffic` anywhere under `Engine\Plugins` or `Engine\Source` (searched by name and content). MassTraffic belongs to the City Sample project. A blog claiming it is built into the engine is wrong for this install. [SRC vs COM]
- `ZoneGraph` plugin: lane graph (`UZoneGraphSubsystem`: `FindNearestLane`, `FindOverlappingLanes`, `AdvanceLaneLocation`, `CalculateLocationAlongLane`, `GetLinkedLanes`, `GetLaneLength/Width/Tags`, A* in `ZoneGraphAStar.h`). BUT building the graph is editor-only: `RebuildGraph`, `OnRequestRebuild`, `SpawnMissingZoneGraphData`, `FZoneGraphBuilder` internals are inside `#if WITH_EDITOR`; the baked `AZoneGraphData` must be saved with the level; the subsystem asserts "Zone graph is not meant to update during game tick". Lane profiles/tags come from `UZoneGraphSettings`. Epic staff reportedly said ZoneGraph saw little development since 5.0 [COM]. Mass has no direct link to the physics system and does not support Blueprints [DOC forum post, Epic staff, Aug 2024].
- So Mass/ZoneGraph would cost: enabling 4+ experimental plugins, an editor-time bake of zone shapes + lane profiles, writing fragments/processors for car-following/IDM, representation LOD to actors/ISM, plus our own vehicle controller. Nothing vehicle-related comes for free.

### 6.2 Recommendation: custom lane graph + data-oriented agents

- Lane graph generated by the same code that builds the road splines: for each road, sample the centerline every ~5 m; create 1-2 directed lanes per direction by offsetting (lane width 3.2-3.6 m); store per lane `Points[]`, cumulative `S[]`, curvature-based speed limit `vmax(s)=sqrt(a_lat/kappa)`, speed limit by road class, `Next[]`/`Prev[]` links at junctions with turn priority, surface type. Save in a `UDataAsset`/binary blob next to the world, or rebuild at start from the road definition.
- Agents are plain structs in a `TArray` inside a `UTickableWorldSubsystem` (no UObject per agent): lane id, `S`, speed, desired speed, length, type, state `{Parked, Kinematic, Physical, Wrecked}`, lateral offset, colour/mesh index, lights/horn state. Per-lane sorted index arrays give O(1) leader lookup.
- Longitudinal control: Intelligent Driver Model `a = a0*(1 - (v/v0)^4 - (s*/s)^2)`, `s* = s0 + v*T + v*dv/(2*sqrt(a0*b))`, with `v0 = min(lane limit, curve limit, personality)` and the player (or a stopped wreck) treated as a leader when inside the lane's lateral corridor; brake lights from deceleration. Lateral: follow centerline with smoothed offset; optional overtake later by temporarily switching to the opposite lane when clear for > X m.
- Spawn/despawn: ring 250-700 m ahead/around the player on lanes outside the camera frustum (use camera forward + FOV test), despawn behind/outside ~900 m, pooled actors and ISM slots, density per km by road class and time of day (design starting point: highway 6-10 vehicles/km/direction, country road 2-5, mountain pass 1-3; scale with `traffic <0..1>`).
- Simulation LOD: Near (< 150-200 m, <= ~24 actors): full mesh actor with kinematic body that follows the lane; on contact with the player (or hit by another vehicle) switch the body to dynamic physics (`SetSimulatePhysics(true)`), apply impulse, hand over to a "wreck" state (brake lights/hazards, despawn later out of view). Mid (200-600 m): instanced meshes (one HISM per type), transform updated from lane `S` each tick, no collision. Far: advance `S` at 1-5 Hz or not at all. Use `ParallelFor` over agents (lane data read-only).
- Distinct traffic types (small car, van, lorry, bus, tractor on farm roads, pickup) differ by mesh, length, desired speed, acceleration, colour palette and horn.
- Audio: only nearest 4-6 vehicles run `UFzEngineSynth`; others share a cheap pass-by one-shot.
- Intersections: priority by road class with simple give-way queue (reserve a conflict box; stop at stop line if reserved), no traffic lights needed for rural scope.
- Cost estimate: 50-100 agents of struct math is far below 0.3 ms/frame; the actor count is the budget.

---------------------------------------------------------------------------------------------------

## 7. Subsystems, console commands, SaveGame

### 7.1 Subsystem patterns [SRC][DOC programming-subsystems]

- `UGameInstanceSubsystem` (`Subsystems/GameInstanceSubsystem.h`): lives with `UGameInstance`; access `GetGameInstance()->GetSubsystem<UFzSaveSubsystem>()`; override `Initialize(FSubsystemCollectionBase&)`, `Deinitialize()`, `ShouldCreateSubsystem(UObject* Outer)`. Good for save/settings/console registration/car roster cache/personal bests.
- `UWorldSubsystem` (`Subsystems/WorldSubsystem.h`): lives with the `UWorld`; hooks `PostInitialize()`, `OnWorldBeginPlay(UWorld&)`, `OnWorldEndPlay`, `OnWorldComponentsUpdated`, `DoesSupportWorldType(EWorldType::Type)` (override to return true only for `Game`/`PIE`), `ShouldCreateSubsystem`. `UTickableWorldSubsystem` adds `Tick(float)` and pure-virtual `GetStatId()`:

```cpp
UCLASS() class UFzTrafficSubsystem : public UTickableWorldSubsystem {
    GENERATED_BODY()
    virtual bool DoesSupportWorldType(const EWorldType::Type T) const override { return T == EWorldType::Game || T == EWorldType::PIE; }
    virtual void Tick(float Dt) override;
    virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(UFzTrafficSubsystem, STATGROUP_Tickables); }
};
```
- `ULocalPlayerSubsystem` is the home of the Enhanced Input subsystem; `UEngineSubsystem` for global registries.
- Access from anywhere with a world context: `UGameplayStatics::GetGameInstance(WorldContext)->GetSubsystem<T>()` / `World->GetSubsystem<T>()`.

### 7.2 Console commands [SRC]

- `IConsoleManager::Get().RegisterConsoleCommand(Name, Help, Delegate, Flags)` overloads (`HAL/IConsoleManager.h`): no args, `FConsoleCommandWithArgsDelegate (const TArray<FString>&)`, `FConsoleCommandWithWorldDelegate`, `FConsoleCommandWithWorldAndArgsDelegate (Args, UWorld*)`, `...WithOutputDevice`, `...WithWorldArgsAndOutputDevice`. Returns `IConsoleCommand*`; remove with `UnregisterConsoleObject(Obj/Name)`. Static registration: `FAutoConsoleCommand`, `FAutoConsoleCommandWithWorldAndArgs`, `FAutoConsoleVariableRef(Name, Var, Help, Flags)` / `TAutoConsoleVariable`.
- Pattern: a `UGameInstanceSubsystem` (`UFzConsoleSubsystem`) registers `cars`, `car`, `respawn`, `tp`, `time`, `weather`, `traffic`, `speed`, `fps`, `assist`, `paint`, `reset`, `help`, `fz.test` in `Initialize` (store the `IConsoleCommand*` pointers) and unregisters them in `Deinitialize` (avoids dangling delegates after hot reload / PIE restarts). Commands run on the game thread. Use the `WithWorld` overloads or resolve the world from `GetWorld()` of the subsystem; in PIE the passed `UWorld*` can be the editor world.
- `UFUNCTION(Exec)` alternative: methods on the player controller / pawn / HUD / GameMode / `UCheatManager` (`APlayerController::CheatClass`, `Within=PlayerController`). Cheat manager is non-shipping by default. Exec functions are not shown in autocomplete unless added to `[/Script/Engine.ConsoleSettings] +ManualAutoCompleteList=(Command="car",Desc="...")`.
- Settings that should be CVars (live-tweakable and scalable): `fz.TrafficDensity`, `fz.Assist.TC`, `fz.Physics.Hz` etc. via `FAutoConsoleVariableRef` with `ECVF_Default` (or `ECVF_Cheat`).

### 7.3 SaveGame [SRC][DOC saving-and-loading]

- `UCLASS() class UFzSaveGame : public USaveGame` with plain UPROPERTYs: current car id, paint (colour, finish), upgrades/tuning, world position + rotation, time of day, weather, settings (assists, units, volume), personal bests per activity (FName -> float), discovered POIs. `SaveGameToMemory` serialises every UPROPERTY with `FObjectAndNameAsStringProxyArchive` (object references become strings), so do not store raw UObject pointers; store ids / soft paths / FName / numbers.
- API (`Kismet/GameplayStatics.h`): `CreateSaveGameObject(TSubclassOf<USaveGame>)`, `SaveGameToSlot(Obj, SlotName, UserIndex)` (sync), `AsyncSaveGameToSlot(Obj, Slot, UserIndex, FAsyncSaveGameToSlotDelegate)`, `LoadGameFromSlot(Slot, UserIndex)` (cast the result, may be null), `AsyncLoadGameFromSlot`, `DoesSaveGameExist(Slot, UserIndex)`, `DeleteGameInSlot`. Files: `<Project>/Saved/SaveGames/<Slot>.sav`.
- Autosave on a timer / on exit through `AsyncSaveGameToSlot`; apply defensively on load (clamp values, fall back to defaults when the car id or region no longer exists; dynamic objects such as traffic are never persisted).

---------------------------------------------------------------------------------------------------

## 8. Project changes required (concrete)

`Sonnet55Forza.Build.cs`:
```csharp
PublicDependencyModuleNames.AddRange(new[] { "Core","CoreUObject","Engine","InputCore","EnhancedInput",
    "Slate","SlateCore","Niagara","AudioMixer","SignalProcessing","AudioExtensions" });
PrivateDependencyModuleNames.AddRange(new[] { "Landscape" /* layer info physmat */, "RenderCore","RHI" });
SetupModulePhysicsSupport(Target);   // PhysicsCore, ChaosCore, Chaos, NNE (+ include path for FRigidBodyHandle_Internal)
// optional: "UMG", "MetasoundEngine","MetasoundFrontend","ChaosVehicles"
```
`Sonnet55Forza.uproject` plugins (existing: ModelingToolsEditorMode, PythonScriptPlugin, EditorScriptingUtilities, Niagara, Metasound, PCG, Water): add `CascadeToNiagaraConverter` (Editor only) if the Python Niagara authoring path is used; add `ChaosVehiclesPlugin` only for the fallback spike; ZoneGraph/MassGameplay/MassAI are NOT needed.
`Config/DefaultEngine.ini`: the `[/Script/Engine.PhysicsSettings]` block from 1.5.3; optional `AudioCallbackBufferFrameSize=512` under `[/Script/WindowsTargetPlatform.WindowsTargetSettings]`.
`Config/DefaultInput.ini`: already sets the Enhanced classes; add `-ConsoleKeys=Tilde` only if a custom console replaces the engine one.
Note: `UE_LOGF` (UTF-8 format-string logging) is new in 5.8 and used inside engine code; classic `UE_LOG(Cat, Verbosity, TEXT("..."))` is still fine in project code. [DOC release notes]

---------------------------------------------------------------------------------------------------

## 9. Feature decisions

| Feature | Decision | Reason |
|---|---|---|
| Chaos Vehicles plugin as the main vehicle | SKIP (fallback spike) | Experimental, skeletal-mesh/physics-asset/AnimBP requirement, simplified tire model |
| Project-owned raycast/spring vehicle | ADOPT | Full control, no assets, fits Blender static cars |
| AsyncPhysicsTickComponent + PT handle forces | ADOPT | Fixed dt, PT-correct scene queries, simple threading |
| Custom TSimCallbackObject on physics thread | ADAPT (only if profiling demands) | Cheaper sync but no UObject/scene-query consistency |
| AddCustomPhysics / sync substepping | SKIP | Not per-substep in Chaos |
| Physics settings async 60/120 Hz | ADOPT | Stability at 250+ km/h |
| Object-type wheel probes + PhysMaterial SurfaceType | ADOPT | No config, surface-aware grip |
| CCD + inertia conditioning off + COM nudge | ADOPT | Walls at speed, predictable inertia |
| Enhanced Input built in code | ADOPT | No assets, supports remap |
| Slate HUD / menus | ADOPT | Robust without Blueprint assets |
| AHUD canvas debug overlay | ADOPT | Cheapest telemetry |
| UMG from C++ | SKIP | No benefit over Slate here |
| Slate-polyline minimap | ADOPT | Cheap, crisp, rotating |
| Scene-capture minimap | SKIP | Per-frame cost |
| Engine console + IConsoleManager commands | ADOPT | Autocomplete/history for free |
| Custom Slate console | ADAPT (optional) | Nicer for video, needs key conflict handling |
| USynthComponent + ISoundGenerator engine audio | ADOPT | No assets, low latency |
| MetaSounds builder for engine/ambience | ADAPT (later, optional) | Runtime-capable, high authoring cost |
| MotoSynth / AudioMotorSim | SKIP | Experimental, needs recordings |
| Niagara spawn API from C++ | ADOPT | Standard |
| Python-authored Niagara via CascadeToNiagaraConverter API | ADAPT | Only programmatic route found; verify early |
| Engine Niagara templates as-is | SKIP | No exposed parameters, not dust/smoke |
| Cascade | SKIP | Legacy |
| CPU puff particles via ISM | ADAPT (fallback) | Guaranteed controllable |
| Custom lane-graph traffic | ADOPT | Fits procedural roads, no experimental deps |
| MassGameplay + ZoneGraph traffic | SKIP | Editor-only bake, no vehicle logic, no MassTraffic |
| UGameInstanceSubsystem / UTickableWorldSubsystem | ADOPT | Clean lifetime |
| USaveGame slots | ADOPT | Built in, async |
| ChaosModularVehicle plugin | SKIP | Experimental 0.1, geometry-collection based |

---------------------------------------------------------------------------------------------------

## 10. Pitfalls checklist

1. Forces on the PT handle must be re-applied every step (evolution `EndFrame` zeroes accumulators); a sleeping body ignores them - wake it from the GT.
2. `bTickPhysicsAsync` / `AsyncFixedTimeStepSize` are consumed at physics-scene creation; set them in ini. Async tick forces a PT/GT sync per step - profile at 60 vs 120 Hz.
3. `bReturnPhysicalMaterial` is false by default; without it `Hit.PhysMaterial` is null. Simple vs complex collision changes which material you get; override on the component for generated roads.
4. `bInertiaConditioning` defaults to true and silently changes car inertia.
5. `FBodyInstance::AddCustomPhysics` is not per-substep in Chaos.
6. Do not touch UObjects from a custom `TSimCallbackObject`; do not cache references returned by `UEnhancedInputComponent::BindActionValue`.
7. Chaos Vehicles: wheel `BoneName` must be non-None even for static meshes; `bRequiresControllerForInputs` defaults true; suspension constraints only exist for skeletal meshes; `SteeringCurve` X axis is MPH; units are cm; spring rate is converted with `MToCm`.
8. UE units: cm, forces in kg*cm/s^2; speed conversion 1 cm/s = 0.036 km/h.
9. Engine console key (Tilde) collides with any custom console; the Slate text box swallows the toggle key.
10. Landscape physical-material limit: 63 per component; layers need `ULandscapeLayerInfoObject::PhysMaterial` assets.
11. Fast cars can outrun collision streaming (World Partition): keep a streaming source on the vehicle with enough radius/priority, otherwise the car falls through unloaded terrain.
12. Niagara user parameters must exist on the system for `SetVariable*` to have an effect; engine templates expose none.
13. 5.8 deprecations hit the common snippets: `FCollisionObjectQueryParams::ObjectTypesToQuery` (int32), `FGeometry::ToPaintGeometry(offset,size,scale)` (5.2), `USynthComponent::OnGenerateAudio` (soon), `Audio::FBiquad` (5.5), `FCoreDelegates::OnPostEngineInit` (use getter).
14. Rendering `OnPaint` widgets: if global invalidation is ever enabled, mark dynamic HUD widgets volatile.
15. A blog claiming Pacejka tires / Network Prediction backend in 5.7 and MassTraffic in the engine contradicts the local source - ignore such claims.

---------------------------------------------------------------------------------------------------

## 11. Open questions / things to smoke-test first

1. Does `AsyncPhysicsTickComponent` fire and does the PT handle give consistent `X()/R()` when `bTickPhysicsAsync=true` in a plain `-game` run with this project (and at what GT cost per step at 60/120 Hz)?
2. Does `LineTraceSingleByObjectType` inside the async tick return `PhysMaterial` for Landscape layers and for static meshes with `SetPhysMaterialOverride`?
3. Can `User.*` parameters be exposed from the Python Niagara authoring API (`create_script_input_linked_parameter`)? Does the `CascadeToNiagaraConverter` plugin load headlessly with `UnrealEditor-Cmd`?
4. Is the editor-created `UPhysicalMaterial` Python factory name correct (`PhysicalMaterialFactoryNew`)?
5. `USynthComponent` spatialisation of mono generators and cost per voice at 512-sample buffers.
6. Kinematic traffic body hitting the dynamic player: confirm hit events and the switch to `SetSimulatePhysics(true)`.
7. Optional: time-boxed Chaos Vehicles spike with a Blender-exported armature to compare feel; use `p.Vehicle.*` debug draws.

---------------------------------------------------------------------------------------------------

## 12. Sources

Local (engine 5.8) files read: `Engine\Plugins\Experimental\ChaosVehiclesPlugin\{ChaosVehiclesPlugin.uplugin, Source\ChaosVehicles\Public\*.h, Private\{ChaosVehicleManager,ChaosVehicleManagerAsyncCallback,ChaosVehicleMovementComponent,ChaosWheeledVehicleMovementComponent,ChaosVehicleWheel,DeferredForces,WheeledVehiclePawn,ChaosVehiclesPlugin}.cpp}`; `Engine\Source\Runtime\Experimental\ChaosVehicles\ChaosVehiclesCore\Private\{WheelSystem,AerodynamicsSystem}.cpp`; `Engine\Source\Runtime\Engine\{Classes\PhysicsEngine\{PhysicsSettings,BodyInstance}.h, Classes\Components\{ActorComponent,PrimitiveComponent}.h, Classes\GameFramework\{Actor,InputSettings,HUD}.h, Public\{CollisionQueryParams,PhysicsPublic}.h, Public\Physics\{AsyncPhysicsInputComponent,GenericPhysicsInterface}.h, Public\Physics\Experimental\{PhysicsThreadLibrary,PhysScene_Chaos}.h, Private\PhysicsEngine\{PhysicsSettings,BodyInstance}.cpp, Private\PhysicsEngine\Experimental\PhysScene_Chaos.cpp, Private\Collision\{SceneQuery,SceneQueryLowLevel,CollisionConversions}.cpp, Private\{Actor,GameplayStatics}.cpp, Private\Components\ActorComponent.cpp, Private\UserInterface\{Console,InputSettings}.cpp}`; `Engine\Source\Runtime\Experimental\Chaos\Public\Chaos\{SimCallbackObject,ParticleHandle,PBDRigidsEvolutionGBF,PhysicsObjectInterface}.h`; `Engine\Source\Runtime\PhysicsCore\Public\PhysicalMaterials\PhysicalMaterial.h`; `Engine\Source\Runtime\Landscape\Classes\{LandscapeHeightfieldCollisionComponent,LandscapeLayerInfoObject}.h`; `Engine\Source\Programs\UnrealBuildTool\Configuration\Rules\ModuleRules.cs`; `Engine\Config\{BaseEngine,BaseInput}.ini`; `Engine\Plugins\EnhancedInput\Source\EnhancedInput\Public\*.h`; `Engine\Source\Runtime\AudioMixer\{Public\Components\SynthComponent.h, Private\Components\SynthComponent.cpp}`; `Engine\Source\Runtime\Engine\Classes\Sound\SoundGenerator.h`; `Engine\Plugins\Runtime\Synthesis\...\SynthComponentToneGenerator.h`; `Engine\Source\Runtime\SignalProcessing\Public\DSP\*.h`; `Engine\Plugins\Runtime\Metasound\Source\{MetasoundEngine\Public\{MetasoundBuilderSubsystem,MetasoundBuilderBase}.h, MetasoundStandardNodes\Private\{MetasoundOscillatorNodes,MetasoundStandardNodesNames}.cpp}`; `Engine\Plugins\Experimental\{MotoSynth,MotorSimOutputMotoSynth}`; `Engine\Plugins\Runtime\AudioMotorSim`; `Engine\Plugins\FX\{Niagara,CascadeToNiagaraConverter,Cascade}` (Niagara headers, templates, `CascadeToNiagaraConverter\Content\Python\*.py`, `...\NiagaraStackGraphUtilitiesAdapterLibrary.h`); `Engine\Plugins\Runtime\{MassGameplay,ZoneGraph,ZoneGraphAnnotations}`, `Engine\Plugins\AI\MassAI`; `Engine\Source\Runtime\{UMG\Private\UserWidget.cpp, SlateCore\Public\{Rendering\DrawElementTypes.h,Layout\Geometry.h,Styling\CoreStyle.h}, SlateCore\Private\SlateCoreClasses.cpp, Core\Public\HAL\IConsoleManager.h, Engine\Public\Subsystems\{WorldSubsystem,GameInstanceSubsystem}.h}`; project `Config\{DefaultInput,DefaultEngine}.ini`, `Source\Sonnet55Forza\Sonnet55Forza.Build.cs`, `Sonnet55Forza.uproject`.

Web:
- https://dev.epicgames.com/documentation/en-us/unreal-engine/how-to-set-up-vehicles-in-unreal-engine [DOC]
- https://dev.epicgames.com/documentation/en-us/unreal-engine/unreal-engine-5-8-release-notes [DOC]
- https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine [DOC]
- https://dev.epicgames.com/documentation/en-us/unreal-engine/programming-subsystems-in-unreal-engine [DOC]
- https://dev.epicgames.com/documentation/en-us/unreal-engine/saving-and-loading-your-game-in-unreal-engine [DOC]
- https://dev.epicgames.com/documentation/en-us/unreal-engine/metasounds-reference-guide-in-unreal-engine [DOC]
- https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UActorComponent/SetAsyncPhysicsTickEnabled (search snippet) [DOC]
- https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/UPhysicsSettings (search snippet) [DOC]
- https://dev.epicgames.com/documentation/en-us/unreal-engine/BlueprintAPI/Audio/MetaSound/Builder/BuildNewMetaSound and .../API/Plugins/MetasoundEngine/UMetaSoundBuilderBase/AddNodeByClassName (search snippets) [DOC]
- https://dev.epicgames.com/documentation/unreal-engine/API/PluginIndex/ChaosVehiclesPlugin (search snippet: Experimental folder) [DOC]
- https://dev.epicgames.com/documentation/en-us/unreal-engine/chaos-modular-vehicles-overview (search snippet) [DOC]
- https://forums.unrealengine.com/t/tutorial-legacy-your-first-60-minutes-with-mass/794314?page=3 (Epic staff: Mass has no Blueprint support) [DOC/forum]
- https://forums.unrealengine.com/t/chaosvehicles/1333154 (experimental warning, search snippet) [COM]
- https://www.strayspark.studio/blog/chaos-vehicles-masterclass-shipping-racing-game-2026 [COM, partly contradicted]
- https://www.strayspark.studio/blog/crowd-traffic-simulation-ue5-mass-ai [COM, MassTraffic claim contradicted]
- https://dev.to/fgrenoville/taming-chaos-stable-vehicle-suspensions-with-async-physics-in-ue5-319l (teaser only) [COM]
- https://forums.unrealengine.com/t/chaos-vehicles-c/2630018 (question only, no answers) [COM]
- https://forums.unrealengine.com/t/chaos-mover/2733017 (async step config example, search snippet) [COM]
- https://unrealcommunity.wiki/revisions/6100e80d9c9d1a89e0c2fe1a (Slate HUD pattern, search snippet) [COM]
- https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/NiagaraFunctionLibrary and .../NiagaraEmitterConversionContext pages (search results) [DOC]
