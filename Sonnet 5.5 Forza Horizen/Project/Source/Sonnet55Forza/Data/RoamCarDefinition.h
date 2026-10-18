// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Core/RoamTypes.h"
#include "RoamCarDefinition.generated.h"

class UStaticMesh;

/**
 * Data definition of one drivable car (Docs/ARCHITECTURE.md section 3, Docs/CAR_ROSTER.md). One URoamCarDefinition asset per
 * car, collected in URoamCarCatalog. Everything the physics, audio, camera, UI and PI formula need is data here - there are
 * NO per-car constants in code.
 *
 * Authoring path: the Blender export sidecar JSON (Docs/BLENDER_CONTRACT.md section 5) gives the geometry block (wheel centres,
 * radius, width, camera and light anchors); the editor module's data-asset factory converts it to UE space:
 *     UE.x = blender.x * 100,  UE.y = -blender.y * 100,  UE.z = blender.z * 100
 * (Blender +Y is the car's LEFT, UE +Y is RIGHT, so the front-left wheel has a NEGATIVE Y in this asset).
 * Units here: centimetres for geometry, SI (kg, N, Nm, m^2) for physics, degrees for angles, km/h for speeds.
 */

/** One sample of a curve (engine torque, steering-vs-speed ...). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamTorquePoint
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Curve")
	float RPM = 0.0f;

	/** Crankshaft torque at wide-open throttle in Nm (for turbo engines: at FULL boost). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Curve")
	float TorqueNm = 0.0f;
};

/** Geometry of one wheel (centre of the axle in car space, UE cm). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamWheelGeometry
{
	GENERATED_BODY()

	/** Wheel (axle) centre relative to the car origin (ground under the middle of the wheelbase) when the car rests on its tyres. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	FVector CenterCm = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	float RadiusCm = 33.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	float WidthCm = 22.0f;
};

/** Everything measured on the Blender model. All values are in UE car space (+X forward, +Y right, +Z up), cm. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamCarGeometry
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	float LengthCm = 420.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	float WidthCm = 180.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	float HeightCm = 140.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	float WheelbaseCm = 260.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	float TrackFrontCm = 155.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	float TrackRearCm = 155.0f;
	/** Clearance between the flat underbody and the ground at rest. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	float RideHeightCm = 12.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	FRoamWheelGeometry WheelFL;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	FRoamWheelGeometry WheelFR;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	FRoamWheelGeometry WheelRL;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	FRoamWheelGeometry WheelRR;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Steering")
	FVector SteeringWheelCenterCm = FVector(8.0f, -35.0f, 85.0f);
	/** Rotation axis of the steering wheel (unit vector, car space). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Steering")
	FVector SteeringWheelAxis = FVector(0.94f, 0.0f, 0.34f);

	// Camera anchors
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Cameras")
	FVector CameraHoodCm = FVector(45.0f, 0.0f, 125.0f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Cameras")
	FVector CameraCockpitCm = FVector(-5.0f, -35.0f, 118.0f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Cameras")
	FVector CameraBumperCm = FVector(215.0f, 0.0f, 45.0f);

	// Light / exhaust anchors
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Lights")
	FVector HeadLightLCm = FVector(205.0f, -60.0f, 65.0f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Lights")
	FVector HeadLightRCm = FVector(205.0f, 60.0f, 65.0f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Lights")
	FVector TailLightLCm = FVector(-205.0f, -60.0f, 85.0f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Lights")
	FVector TailLightRCm = FVector(-205.0f, 60.0f, 85.0f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Lights")
	FVector ReverseLightCm = FVector(-208.0f, 0.0f, 75.0f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Lights")
	FVector ExhaustLCm = FVector(-210.0f, -45.0f, 30.0f);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry|Lights")
	FVector ExhaustRCm = FVector(-210.0f, 45.0f, 30.0f);

	/** Default layout of a generic 4.2 m hatch (used by the placeholder car): wheel centres at the corners of the wheelbase/track. */
	FRoamCarGeometry()
	{
		WheelFL.CenterCm = FVector(130.0, -77.0, 33.0);
		WheelFR.CenterCm = FVector(130.0, 77.0, 33.0);
		WheelRL.CenterCm = FVector(-130.0, -77.0, 33.0);
		WheelRR.CenterCm = FVector(-130.0, 77.0, 33.0);
	}

	/** Wheel by ERoamWheel index (FL, FR, RL, RR). */
	const FRoamWheelGeometry& GetWheel(int32 WheelIndex) const;
	FRoamWheelGeometry& GetWheel(int32 WheelIndex);
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamEngineSpec
{
	GENERATED_BODY()

	/** Wide-open-throttle torque curve, sorted by RPM. Evaluate with GetTorqueNm. Build with BuildSyntheticTorqueCurve when no dyno data exists. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine")
	TArray<FRoamTorquePoint> TorqueCurve;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine")
	float IdleRPM = 900.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine")
	float RedlineRPM = 6800.0f;
	/** Hard rev limiter (fuel cut) above the redline. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine")
	float RevLimiterRPM = 7000.0f;
	/** Rotational inertia of crank + flywheel + clutch in kg*m^2 (rev-up speed). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine")
	float InertiaKgM2 = 0.18f;
	/** Engine-braking torque at the redline with the throttle closed (Nm, positive number); scales linearly with RPM. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine")
	float EngineBrakeNm = 55.0f;
	/** Time constant of the throttle response (s). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine")
	float ThrottleResponseSec = 0.08f;

	// Forced induction
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine|Turbo")
	bool bTurbo = false;
	/** Peak boost in bar (display and audio only). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine|Turbo", meta = (EditCondition = "bTurbo"))
	float MaxBoostBar = 0.0f;
	/** RPM at which the turbo reaches full boost under load. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine|Turbo", meta = (EditCondition = "bTurbo"))
	float TurboFullBoostRPM = 3200.0f;
	/** Spool time constant (s). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine|Turbo", meta = (EditCondition = "bTurbo"))
	float TurboSpoolTimeSec = 0.6f;
	/** Fraction of TorqueCurve available with zero boost (turbo lag): 0.65 means 35 % of torque is missing until the turbo spools. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Engine|Turbo", meta = (EditCondition = "bTurbo", ClampMin = "0.2", ClampMax = "1.0"))
	float TurboLagTorqueFraction = 0.7f;

	/** Linear interpolation of the torque curve; 0 below idle*0.5 (stalled) and a smooth cut above the rev limiter. */
	float GetTorqueNm(float RPM) const;
	/** Peak mechanical power (kW) and the RPM where it occurs. */
	float GetPeakPowerKw(float* OutRPM = nullptr) const;
	float GetPeakTorqueNm(float* OutRPM = nullptr) const;
	/** Power in kW at an RPM. */
	float GetPowerKw(float RPM) const;

	/**
	 * Builds a plausible torque curve: shape(x) = max(0.35, 1 - 1.35*(x - 0.62)^2), x = rpm / redline (the shape used by
	 * the PI prototype in Docs/Tech/FH5_cars_assists.md 3.5), scaled so that the peak of T*omega equals PeakPowerKw.
	 */
	static TArray<FRoamTorquePoint> BuildSyntheticTorqueCurve(float PeakPowerKw, float IdleRPM, float RedlineRPM, int32 NumSamples = 24);
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamGearboxSpec
{
	GENERATED_BODY()

	/** Forward gear ratios (index 0 = 1st gear). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gearbox")
	TArray<float> ForwardRatios = { 3.6f, 2.2f, 1.5f, 1.12f, 0.9f, 0.76f };

	/** Reverse gear ratio (positive number). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gearbox")
	float ReverseRatio = 3.4f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gearbox")
	float FinalDrive = 4.0f;

	/** Automatic upshift point as a fraction of the redline (0.96). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gearbox")
	float UpshiftRpmFraction = 0.96f;
	/** Automatic downshift point as a fraction of the redline (0.45). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gearbox")
	float DownshiftRpmFraction = 0.45f;

	/** Torque interruption during a gear change in seconds. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gearbox")
	float ShiftTimeSec = 0.25f;

	/** Mechanical efficiency of gearbox + driveline (0..1). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Gearbox")
	float Efficiency = 0.90f;

	/** Total overall ratio (gear * final) for a gear number (1..N, -1 = reverse). 0 for neutral/invalid. */
	float GetTotalRatio(int32 Gear) const;
	int32 GetNumForwardGears() const { return ForwardRatios.Num(); }
};

UENUM(BlueprintType)
enum class ERoamDiffType : uint8
{
	Open = 0,
	LimitedSlip,
	Locked
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamDrivetrainSpec
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain")
	ERoamDrivetrain Layout = ERoamDrivetrain::RWD;

	/** AWD only: share of engine torque sent to the REAR axle, 0..1. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float RearTorqueShare = 0.6f;

	/** Differential of the driven axle(s). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain")
	ERoamDiffType FrontDiff = ERoamDiffType::Open;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain")
	ERoamDiffType RearDiff = ERoamDiffType::LimitedSlip;
	/** Centre differential (AWD). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain")
	ERoamDiffType CenterDiff = ERoamDiffType::LimitedSlip;

	/** Lock percentage 0..1 under power (accel) and off throttle (decel), per axle. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float FrontLockAccel = 0.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float FrontLockDecel = 0.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float RearLockAccel = 0.3f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float RearLockDecel = 0.1f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float CenterLock = 0.3f;

	/** LSD preload torque in Nm. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Drivetrain")
	float PreloadNm = 30.0f;
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamBrakeSpec
{
	GENERATED_BODY()

	/** Peak braking deceleration the brakes can produce on perfect tyres, in g. Wheel torque is derived from it. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Brakes", meta = (ClampMin = "0.3", ClampMax = "2.5"))
	float PeakDecelerationG = 1.05f;

	/** Share of the braking force on the FRONT axle, 0..1. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Brakes", meta = (ClampMin = "0.3", ClampMax = "0.85"))
	float BiasFront = 0.6f;

	/** Rear-wheel handbrake torque in Nm (per wheel). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Brakes")
	float HandbrakeTorqueNm = 3500.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Brakes")
	bool bHasABS = true;

	/** Slip ratio above which the ABS releases brake pressure. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Brakes")
	float ABSSlipRatio = 0.14f;
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamSuspensionAxleSpec
{
	GENERATED_BODY()

	/** Spring rate at the wheel in N/m (per wheel). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float SpringRateNPerM = 38000.0f;

	/** Damping in N*s/m for compression (bump) and extension (rebound), at the wheel. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float BumpDampingNsPerM = 2600.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float ReboundDampingNsPerM = 3600.0f;

	/** Travel from the rest position: up (towards the body) and down (droop), cm. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float TravelUpCm = 9.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float TravelDownCm = 9.0f;

	/** Anti-roll bar stiffness as an equivalent N/m of differential wheel travel. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float AntiRollNPerM = 18000.0f;

	/** Progressive bump-stop spring rate when the travel limit is reached (N/m). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float BumpStopNPerM = 200000.0f;

	/** Camber change in degrees per metre of wheel travel (negative = gains negative camber in bump). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float CamberGainDegPerM = -8.0f;

	/** Static alignment at stock tune (the tuning menu offsets these). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float StaticCamberDeg = -1.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Suspension")
	float StaticToeDeg = 0.0f;
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamTireSpec
{
	GENERATED_BODY()

	/** Nominal tyre width in mm (visual and contact patch scale). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre")
	float WidthMm = 215.0f;

	/** Peak friction coefficient on DRY ASPHALT at the nominal load, street compound ~1.0, sport ~1.1, slick ~1.4. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre", meta = (ClampMin = "0.2", ClampMax = "2.5"))
	float PeakFriction = 1.05f;

	/** Friction at full slide divided by the peak (0.8..0.95). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre", meta = (ClampMin = "0.5", ClampMax = "1.0"))
	float SlideFrictionRatio = 0.88f;

	/** mu = PeakFriction * (Fz / NominalLoadN)^(-LoadSensitivity); 0 = grip scales perfectly with load. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre", meta = (ClampMin = "0.0", ClampMax = "0.5"))
	float LoadSensitivity = 0.15f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre")
	float NominalLoadN = 4000.0f;

	/** Slip ratio and slip angle (degrees) at which the friction curve peaks. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre")
	float PeakSlipRatio = 0.12f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre")
	float PeakSlipAngleDeg = 8.0f;

	/** Rolling resistance coefficient on asphalt (multiplied by the surface's rolling-resistance factor). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre")
	float RollingResistance = 0.013f;

	/**
	 * Relative suitability of this compound for a surface, ON TOP of the world's base surface grip
	 * (URoamTimeWeatherSubsystem::GetGripMultiplier already contains dirt 0.78, gravel 0.7, grass 0.6, sand 0.55, wet ...).
	 * 1 = baseline street tyre; a rally tyre uses ~1.2 on Dirt/Gravel. Missing surfaces default to 1.
	 * Effective peak mu = PeakFriction * SurfaceBias[surface] * GripMultiplier(surface) * load sensitivity term.
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre")
	TMap<ERoamSurface, float> SurfaceBias;

	/** How well the compound keeps its grip in the wet (1 = street tyre, slick 0.85, rally 1.05). Applied on top of the wet grip table. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Tyre")
	float WetGripBias = 1.0f;

	float GetSurfaceBias(ERoamSurface Surface) const;
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamAeroSpec
{
	GENERATED_BODY()

	/** Drag area Cd*A in m^2. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Aero")
	float CdA = 0.68f;

	/** Downforce areas Cl*A in m^2 per axle (positive = downforce). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Aero")
	float ClAFront = 0.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Aero")
	float ClARear = 0.0f;

	/** Ground effect: extra downforce factor that grows as the ride height drops (0 = none). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Aero")
	float GroundEffect = 0.0f;

	/** Active rear wing: extra ClARear above the deploy speed. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Aero")
	bool bActiveWing = false;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Aero", meta = (EditCondition = "bActiveWing"))
	float ActiveWingExtraClA = 0.3f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Aero", meta = (EditCondition = "bActiveWing"))
	float ActiveWingDeployKmh = 120.0f;
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamSteeringSpec
{
	GENERATED_BODY()

	/** Maximum road-wheel steering angle at standstill in degrees. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Steering")
	float MaxSteerAngleDeg = 34.0f;

	/** Steering lock as a fraction of MaxSteerAngleDeg versus speed in km/h (X = km/h, Y = 0..1). Linear interpolation, clamped. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Steering")
	TArray<FVector2D> SpeedReduction = { FVector2D(0.0, 1.0), FVector2D(60.0, 0.75), FVector2D(120.0, 0.42), FVector2D(200.0, 0.24), FVector2D(300.0, 0.15) };

	/** Maximum rate of change of the road-wheel angle in deg/s. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Steering")
	float SteerRateDegPerSec = 260.0f;

	/** Steering-wheel to road-wheel ratio (visual rotation of the steering wheel = road angle * ratio). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Steering")
	float SteeringRatio = 14.0f;

	/** Ackermann geometry share 0..1 (0 = parallel steering). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Steering")
	float Ackermann = 0.7f;

	/** Evaluates SpeedReduction at a speed (km/h). */
	float GetLockFraction(float SpeedKmh) const;
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamAssistDefaults
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Assists")
	bool bTractionControl = true;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Assists")
	bool bStabilityControl = true;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Assists")
	bool bABS = true;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Assists", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float SteeringAssist = 0.5f;
	/** Intervention strength of TCS / stability control (0..1) - the controllers' gains scale with it. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Assists", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float TCSStrength = 0.5f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Assists", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float STMStrength = 0.5f;
};

/** Parameters of the procedural engine sound (Vehicle/RoamEngineSynth). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamSoundSpec
{
	GENERATED_BODY()

	/** Name of the sound character preset the audio owner implements ("inline4", "v8", "flat6", "rotary" ...). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	FName Profile = TEXT("inline4");

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound", meta = (ClampMin = "1", ClampMax = "16"))
	int32 Cylinders = 4;

	/** Pitch multiplier on the firing frequency (fires/s = RPM/60 * Cylinders/2 for a four-stroke). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	float PitchScale = 1.0f;

	/** Relative amplitudes of the harmonics of the firing frequency (index 0 = fundamental). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	TArray<float> HarmonicMix = { 1.0f, 0.55f, 0.35f, 0.22f, 0.12f, 0.08f };

	/** Noise (intake/exhaust roar) 0..1. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	float NoiseAmount = 0.25f;

	/** Share of the sound that depends on engine load (throttle) versus overrun. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	float LoadDependence = 0.6f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	bool bTurboWhine = false;
	/** Turbo whine frequency range in Hz (spool 0 .. full). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	FVector2D TurboWhineHz = FVector2D(1800.0, 6500.0);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	float BlowOffVolume = 0.0f;

	/** Exhaust crackle on lift-off, 0..1. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	float ExhaustCrackle = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	float Volume = 1.0f;
};

/** A slot of the upgrade garage. Concrete upgrades are data (URoamUpgradeDefinition, owner: garage UI agent). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamUpgradeSlot
{
	GENERATED_BODY()

	/** "Engine.Tune", "Platform.Brakes", "Tires.Compound" ... */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Upgrade")
	FName SlotId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Upgrade")
	ERoamUpgradeCategory Category = ERoamUpgradeCategory::Engine;

	/** Highest installable tier (0 = stock). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Upgrade")
	int32 MaxTier = 3;

	/** Price in credits of each tier above stock (index 0 = tier 1). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Upgrade")
	TArray<int32> TierPriceCredits;
};

/** Result of the PI estimator (URoamCarDefinition::ComputePerformance). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamCarPerformance
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float Time0To60Kmh = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float Time0To100Kmh = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float TopSpeedKmh = 0.0f;
	/** Lateral grip at 100 km/h in g. */
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float LateralG = 0.0f;
	/** 100 -> 0 km/h braking distance in metres. */
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float BrakeDistance100M = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float Offroad01 = 0.0f;

	/** The six garage bars, 0..10. */
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float RatingSpeed = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float RatingHandling = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float RatingAcceleration = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float RatingLaunch = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float RatingBraking = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float RatingOffroad = 0.0f;

	/** Weighted normalised score 0..1 before the gamma curve. */
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	float Score = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	int32 PerformanceIndex = 100;
	UPROPERTY(BlueprintReadOnly, Category = "Performance")
	ERoamCarClass CarClass = ERoamCarClass::D;
};

/** Weights and normalisation ranges of the PI formula (data-tunable, defaults documented in ComputePerformance). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamPerformanceRules
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	float Gamma = 0.72f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	float WeightSpeed = 0.22f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	float WeightHandling = 0.26f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	float WeightAcceleration = 0.22f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	float WeightLaunch = 0.07f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	float WeightBraking = 0.13f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	float WeightOffroad = 0.10f;

	/** (a, b) = values that map to 0 and 10 points. Acceleration/launch/braking use "lower is better" ranges (a > b). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	FVector2D RangeSpeedKmh = FVector2D(110.0, 360.0);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	FVector2D RangeLateralG = FVector2D(0.55, 1.70);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	FVector2D RangeTime0To100 = FVector2D(12.0, 2.3);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	FVector2D RangeTime0To60 = FVector2D(5.0, 1.4);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "PI")
	FVector2D RangeBrakeDistance = FVector2D(62.0, 26.0);
};

/**
 * One car. See the file comment for units. Properties are grouped like Docs/ARCHITECTURE.md section 3.
 */
UCLASS(BlueprintType)
class SONNET55FORZA_API URoamCarDefinition : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	// ---- identity ---------------------------------------------------------------------------------------------------
	/** Stable id, equals the Blender asset id: "car01_hatch_pulse". Used by saves, console and catalog lookup. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	FName CarId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	FText DisplayName;

	/** Fictional maker (no real manufacturers). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	FString Maker;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	int32 Year = 2024;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity", meta = (MultiLine = "true"))
	FText Description;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	int32 PriceCredits = 20000;

	/** Short silhouette tag shown in the garage ("Hot hatch", "Muscle", "Rally"...). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	FText BodyType;

	/** Free-form tags: "drift", "offroad", "classic" ... (also used by activities, e.g. drift-capable hint). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	TArray<FName> Tags;

	// ---- meshes -----------------------------------------------------------------------------------------------------
	/** Imported Blender parts (one static mesh per part, pivot rules in Docs/BLENDER_CONTRACT.md section 3). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> BodyMesh;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> GlassMesh;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> InteriorMesh;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> SteeringWheelMesh;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> WheelMeshFL;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> WheelMeshFR;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> WheelMeshRL;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> WheelMeshRR;

	// ---- geometry ---------------------------------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Geometry")
	FRoamCarGeometry Geometry;

	// ---- mass -------------------------------------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Mass", meta = (ClampMin = "300.0"))
	float MassKg = 1300.0f;

	/** Centre of mass relative to the car origin (cm): x forward, y right, z up. Typically slightly forward of centre, ~45 cm high. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Mass")
	FVector CenterOfMassCm = FVector(0.0f, 0.0f, 45.0f);

	/** Principal moments of inertia (roll, pitch, yaw) in kg*m^2; all zero = estimate with GetEstimatedInertia(). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Mass")
	FVector InertiaKgM2 = FVector::ZeroVector;

	// ---- powertrain / chassis ---------------------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Powertrain")
	FRoamEngineSpec Engine;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Powertrain")
	FRoamGearboxSpec Gearbox;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Powertrain")
	FRoamDrivetrainSpec Drivetrain;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis")
	FRoamBrakeSpec Brakes;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis")
	FRoamSuspensionAxleSpec SuspensionFront;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis")
	FRoamSuspensionAxleSpec SuspensionRear;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis")
	FRoamTireSpec TireFront;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis")
	FRoamTireSpec TireRear;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis")
	FRoamAeroSpec Aero;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis")
	FRoamSteeringSpec Steering;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis")
	FRoamAssistDefaults AssistDefaults;

	/**
	 * Chassis quality factor used ONLY by the PI estimator (body roll, camber, damping quality that the analytic estimate cannot
	 * see): 0.8 (soft, tall) .. 1.1 (stiff, low). Calibrate against the automated drive tests.
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chassis", meta = (ClampMin = "0.6", ClampMax = "1.3"))
	float HandlingFactor = 1.0f;

	// ---- audio / garage ---------------------------------------------------------------------------------------------
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Sound")
	FRoamSoundSpec Sound;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Garage")
	TArray<FRoamUpgradeSlot> UpgradeSlots;

	/** Paints offered in the garage; the first entry is the default paint. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Garage")
	TArray<FRoamPaint> SuggestedPaints;

	// ---- derived values ---------------------------------------------------------------------------------------------
	/**
	 * Analytic performance estimate (deterministic, ~1 ms). FORMULA (Docs/Tech/FH5_cars_assists.md 3.5):
	 *   Longitudinal sim, dt = 5 ms, 90 s: thrust F = min( T(rpm)*ratio*Efficiency / Rw , mu * (m*g*DriveFrac + 0.5*rho*ClA*v^2) ),
	 *   a = (F - 0.5*rho*CdA*v^2 - Crr*m*g)/m, upshift at UpshiftRpmFraction*redline, ShiftTimeSec pause per shift,
	 *   launch RPM = max(rpm, 65 % of the peak-torque RPM) (clutch slip). DriveFrac: FWD 0.55, RWD 0.58, AWD 0.95.
	 *   rho = 1.2, g = 9.81, Crr = tyre RollingResistance. mu = mean peak friction of front and rear tyre.
	 *   Metrics: t60, t100, vmax (speed after 90 s), latG = mu*HandlingFactor*(m g + 0.5 rho ClA 27.8^2)/(m g),
	 *   brake distance 100->0 = v^2 / (2 g muBrake), muBrake = min(1.02 mu, PeakDecelerationG) * (1 + 0.5*downforce/(m g)),
	 *   offroad01 = clamp(clamp((looseGrip - 0.5)/0.4, 0, 1) * (0.6 + 0.4*travel) * (AWD ? 1.1 : 1), 0, 1) where looseGrip =
	 *   mean over {Dirt, Gravel, Sand} of base-surface-grip * tyre SurfaceBias and travel = clamp(mean total travel / 25 cm, 0, 1).
	 *   Normalised ratings n(x) = clamp((x - a)/(b - a), 0, 1) with the ranges of FRoamPerformanceRules, Score = sum(weight * n),
	 *   PI = round(100 + 899 * Score^Gamma) clamped to 100..999, class from Roam::ClassFromPerformanceIndex.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|Car")
	FRoamCarPerformance ComputePerformance(const FRoamPerformanceRules& Rules) const;

	/** ComputePerformance with default rules, cached (recomputed after edits). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Car")
	int32 GetPerformanceIndex() const;

	UFUNCTION(BlueprintCallable, Category = "Roam|Car")
	ERoamCarClass GetCarClass() const;

	/** "A 743" style chip text. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Car")
	FString GetClassLabel() const;

	/** Box-model inertia from mass and dimensions if InertiaKgM2 is zero, otherwise InertiaKgM2. */
	FVector GetEstimatedInertia() const;

	/** Front axle weight share 0..1 derived from the centre of mass x offset and the wheelbase. */
	float GetFrontWeightFraction() const;

	/** Peak mechanical power in kW (from the torque curve). */
	float GetPeakPowerKw() const { return Engine.GetPeakPowerKw(); }

	/** Mean tyre peak friction (front/rear). */
	float GetMeanPeakFriction() const { return 0.5f * (TireFront.PeakFriction + TireRear.PeakFriction); }

	/** Checks that a definition is usable by the physics (positive mass, torque curve, gears, wheel radii). Fills OutProblems. */
	bool Validate(TArray<FString>& OutProblems) const;

	/** Display string for logs: "car01_hatch_pulse (Pulse) C 587". */
	FString ToDebugString() const;

	//~ Begin UObject / UPrimaryDataAsset
	virtual FPrimaryAssetId GetPrimaryAssetId() const override;
	virtual void PostLoad() override;
#if WITH_EDITOR
	virtual void PostEditChangeProperty(FPropertyChangedEvent& PropertyChangedEvent) override;
#endif
	//~ End

	/** Primary asset type used by the asset manager / catalog ("RoamCar"). */
	static const FPrimaryAssetType& GetPrimaryAssetTypeName();

private:
	mutable int32 CachedPerformanceIndex = 0;
};
