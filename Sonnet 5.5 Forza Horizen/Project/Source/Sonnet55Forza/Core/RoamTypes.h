// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/EngineTypes.h"
#include "RoamTypes.generated.h"

enum EPhysicalSurface : int;

/**
 * RoamTypes.h - shared enums and plain data structs of "Roamline: Open Roads" (Docs/ARCHITECTURE.md section 2).
 *
 * This header is a CONTRACT between all subsystems. Adding fields is fine (always with a default value); renaming or
 * re-ordering existing members is not, because several agents compile against it in parallel.
 *
 * UNITS (whole project):  Unreal units for positions/lengths = centimetres, angles = degrees, mass = kg, force = N,
 * torque = Nm, speeds: *Kmh / *Ms suffixes are explicit, a bare "Velocity" is cm/s (engine convention).
 * AXES: UE world axes. Vehicle local space: +X forward, +Y right, +Z up (so the LEFT wheels have negative Y).
 */

// ------------------------------------------------------------------------------------------------------------------
// Enums
// ------------------------------------------------------------------------------------------------------------------

/**
 * Driving surface. Wet asphalt is Asphalt + wetness (URoamTimeWeatherSubsystem), not a separate value.
 * The numeric order is a CONTRACT: Asphalt..Mud map 1:1 to the engine physical surface types SurfaceType1..SurfaceType8
 * (see Roam::PhysicalSurfaceFromSurface and the [/Script/Engine.PhysicsSettings] PhysicalSurfaces list in DefaultEngine.ini).
 */
UENUM(BlueprintType)
enum class ERoamSurface : uint8
{
	Asphalt = 0,
	Concrete,
	Dirt,
	Gravel,
	Grass,
	Sand,
	Snow,
	Mud,
	Count UMETA(Hidden)
};
ENUM_RANGE_BY_COUNT(ERoamSurface, ERoamSurface::Count);

UENUM(BlueprintType)
enum class ERoamWeather : uint8
{
	Clear = 0,
	Cloudy,
	Rain,
	Fog,
	Storm,
	Count UMETA(Hidden)
};
ENUM_RANGE_BY_COUNT(ERoamWeather, ERoamWeather::Count);

UENUM(BlueprintType)
enum class ERoamDrivetrain : uint8
{
	FWD = 0,
	RWD,
	AWD
};

/** Performance class bands (thresholds on the Performance Index, see Roam::ClassFromPerformanceIndex). */
UENUM(BlueprintType)
enum class ERoamCarClass : uint8
{
	D = 0,
	C,
	B,
	A,
	S1,
	S2,
	X
};

UENUM(BlueprintType)
enum class ERoamPaintFinish : uint8
{
	Gloss = 0,
	Matte,
	Metallic
};

UENUM(BlueprintType)
enum class ERoamRoadClass : uint8
{
	Highway = 0,
	Regional,
	Mountain,
	Dirt,
	Shortcut,
	Village,
	Count UMETA(Hidden)
};
ENUM_RANGE_BY_COUNT(ERoamRoadClass, ERoamRoadClass::Count);

UENUM(BlueprintType)
enum class ERoamCameraMode : uint8
{
	Chase = 0,
	Hood,
	Cockpit,
	Bumper,
	FreeLook,
	Photo,
	Count UMETA(Hidden)
};
ENUM_RANGE_BY_COUNT(ERoamCameraMode, ERoamCameraMode::Count);

/** Wheel index convention used by every per-wheel array in the project (telemetry, geometry, visuals). */
UENUM(BlueprintType)
enum class ERoamWheel : uint8
{
	FrontLeft = 0,
	FrontRight,
	RearLeft,
	RearRight,
	Count UMETA(Hidden)
};

/** Driving assists that can be toggled at runtime (console `assist <name> on|off`, debug menu, garage). */
UENUM(BlueprintType)
enum class ERoamAssist : uint8
{
	TractionControl = 0,
	StabilityControl,
	ABS,
	SteeringAssist,
	AutomaticGearbox,
	DrivingLine,
	Count UMETA(Hidden)
};
ENUM_RANGE_BY_COUNT(ERoamAssist, ERoamAssist::Count);

/** Upgrade categories of the garage (mirrors the six FH-style categories, see Docs/Tech/FH5_cars_assists.md). */
UENUM(BlueprintType)
enum class ERoamUpgradeCategory : uint8
{
	Conversion = 0,
	Engine,
	PlatformHandling,
	TiresRims,
	AeroAppearance,
	Drivetrain
};

/** Presentation channel of a HUD notification (layout and timings: Docs/Tech/FH5_activities.md section 7). */
UENUM(BlueprintType)
enum class ERoamNotifyKind : uint8
{
	Toast = 0,   // small, top area, 2-3 s
	Banner,      // big, upper third, ~3.5 s
	ResultCard   // centre card with stars (activity results)
};

// ------------------------------------------------------------------------------------------------------------------
// Free helpers (implemented in Core/RoamTypes.cpp)
// ------------------------------------------------------------------------------------------------------------------

namespace Roam
{
	constexpr int32 NumWheels = 4;

	/** cm/s -> km/h and back. */
	FORCEINLINE float CmsToKmh(float CmPerSec) { return CmPerSec * 0.036f; }
	FORCEINLINE float KmhToCms(float Kmh) { return Kmh / 0.036f; }
	FORCEINLINE float MsToKmh(float MetersPerSec) { return MetersPerSec * 3.6f; }
	FORCEINLINE float KmhToMs(float Kmh) { return Kmh / 3.6f; }
	FORCEINLINE float KmhToMph(float Kmh) { return Kmh * 0.621371f; }

	/** Enum <-> text (case-insensitive parse, accepts the C++ name or the numeric value). Works for every UENUM above. */
	template <typename TEnum>
	FString EnumToString(TEnum Value)
	{
		const UEnum* Enum = StaticEnum<TEnum>();
		return Enum ? Enum->GetNameStringByValue(static_cast<int64>(Value)) : FString();
	}

	template <typename TEnum>
	bool ParseEnum(const FString& Text, TEnum& OutValue)
	{
		const UEnum* Enum = StaticEnum<TEnum>();
		if (!Enum)
		{
			return false;
		}
		const FString Trimmed = Text.TrimStartAndEnd();
		for (int32 i = 0; i < Enum->NumEnums() - 1; ++i) // the last entry is the auto-generated _MAX
		{
			const FString Name = Enum->GetNameStringByIndex(i);
			if (Name == TEXT("Count")) // hidden terminator entry of the ENUM_RANGE_BY_COUNT enums
			{
				continue;
			}
			if (Name.Equals(Trimmed, ESearchCase::IgnoreCase)
				|| Enum->GetDisplayNameTextByIndex(i).ToString().Equals(Trimmed, ESearchCase::IgnoreCase))
			{
				OutValue = static_cast<TEnum>(Enum->GetValueByIndex(i));
				return true;
			}
		}
		return false;
	}

	/** Surface <-> engine physical surface (SurfaceType1..8). SurfaceType_Default and unknown values map to Asphalt. */
	SONNET55FORZA_API ERoamSurface SurfaceFromPhysicalSurface(EPhysicalSurface PhysicalSurface);
	SONNET55FORZA_API EPhysicalSurface PhysicalSurfaceFromSurface(ERoamSurface Surface);

	/**
	 * World grip multiplier of a surface for a road wetness (0 = dry, 0.7 = wet, 1 = soaked), relative to DRY ASPHALT = 1.0.
	 * Piecewise-linear between the knots {0 dry, 0.7 wet, 1.0 soaked}. This is the single source of truth: the time/weather
	 * subsystem returns it for the current wetness and the PI estimator uses the dry column. Values (dry / wet / soaked):
	 * Asphalt 1.00/0.72/0.62, Concrete 0.97/0.70/0.60, Dirt 0.78/0.55/0.45, Gravel 0.70/0.56/0.50, Grass 0.60/0.44/0.38,
	 * Sand 0.55/0.58/0.52 (damp sand is firmer), Snow 0.35/0.34/0.32, Mud 0.45/0.42/0.36.
	 */
	SONNET55FORZA_API float SurfaceGripMultiplier(ERoamSurface Surface, float Wetness01);

	/** Rolling-resistance multiplier of a surface relative to asphalt (asphalt 1, concrete 1, gravel 2, dirt 3.5, snow 4, grass 7, mud 8, sand 10). */
	SONNET55FORZA_API float SurfaceRollingResistanceFactor(ERoamSurface Surface);

	/** Performance class bands: D <= 500, C 501-600, B 601-700, A 701-800, S1 801-900, S2 901-998, X >= 999. */
	SONNET55FORZA_API ERoamCarClass ClassFromPerformanceIndex(int32 PerformanceIndex);
	SONNET55FORZA_API FString ClassToLabel(ERoamCarClass Class);
	/** Own UI palette (not copied from any game): D #4FC3F7, C #FFD54F, B #FF9F43, A #FF5C5C, S1 #B36BFF, S2 #3F7BFF, X #3DDC84. */
	SONNET55FORZA_API FLinearColor ClassColor(ERoamCarClass Class);

	/** Parses user text ("tcs", "traction", "stability", "stm", "abs", "steer", "auto", "line"...) to an assist. */
	SONNET55FORZA_API bool ParseAssistName(const FString& Text, ERoamAssist& OutAssist);
	/** Short HUD/console label: "TCS", "STM", "ABS", "STEER", "AUTO", "LINE". */
	SONNET55FORZA_API FString AssistToShortName(ERoamAssist Assist);
}

// ------------------------------------------------------------------------------------------------------------------
// Settings / assists
// ------------------------------------------------------------------------------------------------------------------

/** Runtime assist switches of the player's car (stored in the profile; the car definition only supplies defaults). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamAssistSettings
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Assists")
	bool bTractionControl = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Assists")
	bool bStabilityControl = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Assists")
	bool bABS = true;

	/** Steering assist strength 0 (raw input) .. 1 (strong counter-steer and smoothing). 0.5 = "Normal". */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Assists", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float SteeringAssist = 0.5f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Assists")
	bool bAutomaticGearbox = true;

	/** Suggested racing/braking line on the road. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Assists")
	bool bDrivingLine = false;

	/** Boolean view of an assist (SteeringAssist counts as "on" when > 0). */
	bool Get(ERoamAssist Assist) const;
	/** Boolean setter (SteeringAssist: on = 0.5, off = 0). */
	void Set(ERoamAssist Assist, bool bEnabled);
};

/** Per-player options persisted in the profile. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamPlayerSettings
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	FRoamAssistSettings Assists;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	bool bUseMph = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	bool bHudVisible = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	bool bShowMinimap = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	bool bShowSpeedometer = true;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	bool bShowFps = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	bool bShowNotifications = true;

	/** Default hold time of toasts/banners (the FH-style accessibility "notification duration"). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings", meta = (ClampMin = "1.0", ClampMax = "10.0"))
	float NotificationSeconds = 4.0f;

	/** 0..1 multiplier of all traffic densities (console `traffic <0..1>`). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float TrafficDensity = 0.6f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float MasterVolume = 1.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float EngineVolume = 1.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	ERoamCameraMode DefaultCameraMode = ERoamCameraMode::Chase;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings", meta = (ClampMin = "0.1", ClampMax = "5.0"))
	float LookSensitivity = 1.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Settings")
	bool bInvertLookY = false;
};

// ------------------------------------------------------------------------------------------------------------------
// Car-related value types
// ------------------------------------------------------------------------------------------------------------------

/** Paint scheme of a car. Master material parameters are set by ARoamVehicle::SetPaint (Vehicle owner). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamPaint
{
	GENERATED_BODY()

	/** Body paint (Blender material slot "M_Paint"). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Paint")
	FLinearColor Primary = FLinearColor(0.65f, 0.04f, 0.04f, 1.0f);

	/** Accent paint (Blender material slot "M_Paint2": roof, stripes). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Paint")
	FLinearColor Secondary = FLinearColor(0.02f, 0.02f, 0.02f, 1.0f);

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Paint")
	ERoamPaintFinish Finish = ERoamPaintFinish::Gloss;

	/** 0 = no stripes; 1..N preset stripe masks. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Paint")
	int32 StripeStyle = 0;

	/** Rim style index (set of rim meshes/materials). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Paint")
	int32 WheelStyle = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Paint")
	FLinearColor WheelColor = FLinearColor(0.78f, 0.78f, 0.80f, 1.0f);
};

/**
 * Player tuning (reduced FH-style set, mapping in Docs/Tech/FH5_cars_assists.md section 3.7). A value of exactly -1 in
 * the "stock" fields means "use the car definition's value" so a default-constructed FRoamTuning changes nothing.
 */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamTuning
{
	GENERATED_BODY()

	// Tyres
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Tyres", meta = (ClampMin = "18.0", ClampMax = "45.0"))
	float TirePressureFrontPsi = 32.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Tyres", meta = (ClampMin = "18.0", ClampMax = "45.0"))
	float TirePressureRearPsi = 31.0f;

	// Gearing
	/** Multiplies the final drive ratio (0.8 .. 1.25). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Gearing", meta = (ClampMin = "0.7", ClampMax = "1.4"))
	float FinalDriveMultiplier = 1.0f;
	/** -1 .. +1: re-spaces the intermediate gears around fixed 1st and top gear. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Gearing", meta = (ClampMin = "-1.0", ClampMax = "1.0"))
	float GearSpacing = 0.0f;

	// Alignment
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Alignment")
	float CamberFrontDeg = -1.2f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Alignment")
	float CamberRearDeg = -0.8f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Alignment")
	float ToeFrontDeg = 0.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Alignment")
	float ToeRearDeg = 0.1f;

	// Anti-roll bars, springs, damping (0..100 index / x-stock scales)
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Suspension", meta = (ClampMin = "0.0", ClampMax = "100.0"))
	float AntiRollFront = 30.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Suspension", meta = (ClampMin = "0.0", ClampMax = "100.0"))
	float AntiRollRear = 30.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Suspension", meta = (ClampMin = "0.5", ClampMax = "1.6"))
	float SpringFrontScale = 1.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Suspension", meta = (ClampMin = "0.5", ClampMax = "1.6"))
	float SpringRearScale = 1.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Suspension", meta = (ClampMin = "0.5", ClampMax = "1.6"))
	float DampingFrontScale = 1.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Suspension", meta = (ClampMin = "0.5", ClampMax = "1.6"))
	float DampingRearScale = 1.0f;
	/** Ride height change in cm versus stock (negative = lower). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Suspension", meta = (ClampMin = "-6.0", ClampMax = "8.0"))
	float RideHeightOffsetCm = 0.0f;

	// Aero (0..1 of the installed maximum)
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Aero", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float AeroFrontLevel = 1.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Aero", meta = (ClampMin = "0.0", ClampMax = "1.0"))
	float AeroRearLevel = 1.0f;

	// Brakes. -1 = car default.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Brakes")
	float BrakeBalanceFrontPercent = -1.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Brakes", meta = (ClampMin = "0.6", ClampMax = "1.4"))
	float BrakePressureScale = 1.0f;

	// Differential. -1 = car default.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Differential")
	float DiffAccelLock = -1.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Differential")
	float DiffDecelLock = -1.0f;
	/** AWD only: rear torque share in percent. -1 = car default. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Tuning|Differential")
	float CenterSplitRearPercent = -1.0f;
};

/** Everything the game persists about the player (Save/RoamSaveGame wraps one of these). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamProfile
{
	GENERATED_BODY()

	/** Current car (FRoamCarDefinition::CarId); NAME_None = use the default car. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	FName CarId;

	/** Paint per car so switching cars keeps each car's colours. The entry for CarId equals Paint. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	FRoamPaint Paint;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	TMap<FName, FRoamPaint> PaintByCar;

	/** Installed upgrade tier per slot id ("Engine.Tune" -> 2). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	TMap<FName, int32> Upgrades;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	FRoamTuning Tuning;

	/** Where the player was when the profile was saved. Only valid if bHasLastTransform. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	FTransform LastTransform;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	bool bHasLastTransform = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	float GameHour = 10.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	ERoamWeather Weather = ERoamWeather::Clear;

	/** Best values per activity id (units depend on the activity: km/h, points, metres, seconds). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	TMap<FName, float> PersonalBests;

	/** Best star count per activity id (never decreases). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	TMap<FName, int32> ActivityStars;

	/** Ids of collectibles / discoveries already found. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	TSet<FName> Collected;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	int64 TotalXp = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	int64 Credits = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, SaveGame, Category = "Profile")
	FRoamPlayerSettings Settings;
};

// ------------------------------------------------------------------------------------------------------------------
// Vehicle telemetry
// ------------------------------------------------------------------------------------------------------------------

/**
 * Per-frame vehicle state for UI, audio, FX, activities and automated tests. Filled by URoamVehicleMovement, read through
 * ARoamVehicle::GetTelemetry(). Wheel arrays use ERoamWheel order (FL, FR, RL, RR).
 * The first block is the binding list of Docs/ARCHITECTURE.md section 2; the "additions" block was added by the skeleton
 * because UI/activities/FX need it (drift angle, airborne state, impact detection ...).
 */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamVehicleTelemetry
{
	GENERATED_BODY()

	// ---- ARCHITECTURE section 2 -----------------------------------------------------------------------------------
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float SpeedKmh = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float SpeedMs = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float RPM = 0.0f;
	/** RPM / redline, 0..1 (can exceed 1 on the limiter). */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float NormRPM = 0.0f;
	/** -1 = reverse, 0 = neutral, 1..N forward gears. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	int32 Gear = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float Throttle = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float Brake = 0.0f;
	/** -1 (left) .. +1 (right). */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float Steer = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float Handbrake = 0.0f;
	/** Surface under the front-left wheel / dominant surface (the owner of the tyre model decides). */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	ERoamSurface Surface = ERoamSurface::Asphalt;

	// Per-wheel arrays are plain C++ members, NOT UPROPERTYs: UHT rejects static arrays (and bool arrays) in Blueprint-visible structs.
	// Index with ERoamWheel / Roam::NumWheels. Blueprint users read single wheels through the vehicle's helper functions.

	/** Longitudinal slip ratio per wheel (0 = rolling, +1 = full wheelspin, -1 = locked). */
	float WheelSlipRatio[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	/** Slip angle per wheel in degrees. */
	float WheelSlipAngleDeg[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	/** Vertical load per wheel in Newton. */
	float WheelLoadN[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	bool WheelOnGround[4] = { true, true, true, true };

	/** Body accelerations in g, vehicle space: longitudinal (+ = accelerating), lateral (+ = to the right), vertical. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float LongG = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float LatG = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float VertG = 1.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float YawRateDeg = 0.0f;

	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bTCSActive = false;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bSTMActive = false;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bABSActive = false;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bTurbo = false;
	/** Turbo boost 0..1 of the car's maximum. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float Boost01 = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bRedline = false;
	/** Distance driven in this car since it was spawned/reset, km. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float DistanceKm = 0.0f;

	// ---- additions by the skeleton ----------------------------------------------------------------------------------
	/** World velocity of the body in cm/s. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	FVector VelocityCmS = FVector::ZeroVector;
	/** Body axes in world space. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	FVector ForwardAxis = FVector::ForwardVector;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	FVector UpAxis = FVector::UpVector;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	int32 NumWheelsOnGround = 4;
	/** True while (almost) no wheel touches the ground. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bAirborne = false;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float AirTimeSec = 0.0f;
	/** Angle between velocity and heading in degrees (drift detection); 0 when rolling straight. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float BodySlipAngleDeg = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float PitchDeg = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float RollDeg = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bReversing = false;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bShifting = false;
	/** Road wetness under the car 0..1 (copied from URoamTimeWeatherSubsystem for convenience). */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float SurfaceWetness = 0.0f;
	/** Steering angle of the front road wheels in degrees (+ = right). */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float FrontWheelAngleDeg = 0.0f;
	/** Impact strength of the most recent collision (m/s of velocity change) and when it happened (world seconds). */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float LastImpactSpeedMs = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	double LastImpactWorldTime = -1000.0;

	// --- added by vehicle-physics ---
	// Per-wheel data for the visuals / FX agents (plain arrays like the ones above, index = ERoamWheel: FL, FR, RL, RR).
	/** Wheel spin speed in rad/s, positive = rolling forward. */
	float WheelAngVelRadS[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	/** Hub offset from its rest position in cm along the body's up axis: positive = compressed (wheel moves up into the body). */
	float WheelTravelCm[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	/** Road-wheel steering angle in degrees (+ = right) and camber in degrees. */
	float WheelSteerDeg[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	float WheelCamberDeg[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	/** Normalised combined slip of the tyre: 1 = at the grip peak, > 1 = sliding (skid marks / smoke start around 1.3). */
	float WheelSlideNorm[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	/** Surface under each wheel. */
	ERoamSurface WheelSurface[4] = { ERoamSurface::Asphalt, ERoamSurface::Asphalt, ERoamSurface::Asphalt, ERoamSurface::Asphalt };
	/** Brake lights: brake pedal, handbrake or strong automatic braking. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bBrakeLightsOn = false;
	/** Crankshaft torque in Nm (negative = engine braking) and the clutch state. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float EngineTorqueNm = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	bool bClutchSlipping = false;
	/** Steering added by the steering assist (counter-steer), degrees at the road wheels. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float SteerAssistDeg = 0.0f;
	/** Sum of the aerodynamic downforce in N. */
	UPROPERTY(BlueprintReadOnly, Category = "Telemetry")
	float DownforceN = 0.0f;
};

// ------------------------------------------------------------------------------------------------------------------
// Road network value types (the asset itself: Data/RoamRoadNetwork.h)
// ------------------------------------------------------------------------------------------------------------------

/** Flags of a road sample / section. */
UENUM(meta = (Bitflags, UseEnumValuesAsMaskValuesInEditor = "true"))
enum class ERoamRoadSection : uint8
{
	None = 0,
	Bridge = 1 << 0,
	Tunnel = 1 << 1,
	Junction = 1 << 2,   // inside a junction pad
	Guardrail = 1 << 3
};
ENUM_CLASS_FLAGS(ERoamRoadSection);

UENUM(BlueprintType)
enum class ERoamJunctionControl : uint8
{
	None = 0,     // priority junction without markings
	GiveWay,      // minor arms yield
	Stop,         // all-way / minor arms stop
	Roundabout
};

/**
 * One centreline sample of a road. Positions in UE cm (world), generated by the world builder from roads.json
 * (which stores metres; the importer converts). Samples are ~5 m apart.
 */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamRoadSample
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	FVector Position = FVector::ZeroVector;

	/** Unit tangent in the direction of increasing S. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	FVector Tangent = FVector::ForwardVector;

	/** Banking in degrees, positive = the right side of the road is lower (turning right). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	float BankDeg = 0.0f;

	/** Full carriageway width in cm (all lanes, without shoulders). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	float WidthCm = 700.0f;

	/** Cumulative distance along the road in cm. Always recomputed by URoamRoadNetwork::BuildSpatialIndex. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	float S = 0.0f;

	/** ERoamRoadSection bit flags. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road", meta = (Bitmask, BitmaskEnum = "/Script/Sonnet55Forza.ERoamRoadSection"))
	uint8 Flags = 0;
};

/** A drivable road (polyline of samples). Roads are split at junctions: a road starts and ends at a junction or a dead end. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamRoad
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	FName RoadId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	ERoamRoadClass RoadClass = ERoamRoadClass::Regional;

	/** Default drivable surface (Asphalt for paved classes, Gravel/Dirt for DIRT/SHORTCUT). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	ERoamSurface Surface = ERoamSurface::Asphalt;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	float SpeedLimitKmh = 80.0f;

	/** Lanes in the direction of increasing S (right side with right-hand traffic) and against it. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	int32 LanesForward = 1;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	int32 LanesBackward = 1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	float LaneWidthCm = 340.0f;

	/** Only LanesForward is used by traffic. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	bool bOneWay = false;

	/** Junction ids at S = 0 and S = Length. NAME_None = dead end. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	FName StartJunction;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	FName EndJunction;

	/** Region id (FRoamRegionDef::RegionId) of the road's midpoint, optional. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	FName RegionId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Road")
	TArray<FRoamRoadSample> Samples;

	/** Total length in cm. Recomputed by URoamRoadNetwork::BuildSpatialIndex. */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Road")
	float LengthCm = 0.0f;

	/** Total carriageway width = (LanesForward + LanesBackward) * LaneWidthCm (nominal). */
	float GetNominalWidthCm() const { return float(LanesForward + (bOneWay ? 0 : LanesBackward)) * LaneWidthCm; }
};

/** One road end attached to a junction. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamJunctionArm
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Junction")
	FName RoadId;

	/** True if the arm is the road's S = 0 end, false for its S = Length end. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Junction")
	bool bAtRoadStart = true;

	/** Right of way: higher wins. Used by traffic for yielding. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Junction")
	int32 Priority = 0;
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamJunction
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Junction")
	FName JunctionId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Junction")
	FVector Position = FVector::ZeroVector;

	/** Radius of the junction pad in cm. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Junction")
	float RadiusCm = 1500.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Junction")
	ERoamJunctionControl Control = ERoamJunctionControl::None;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Junction")
	TArray<FRoamJunctionArm> Arms;
};

/** Result of a road query. All lengths in cm. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamRoadHit
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	bool bValid = false;

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	FName RoadId;

	/** Index into URoamRoadNetwork::Roads. */
	UPROPERTY(BlueprintReadOnly, Category = "Road")
	int32 RoadIndex = INDEX_NONE;

	/** Distance along the road from its start (cm). */
	UPROPERTY(BlueprintReadOnly, Category = "Road")
	float S = 0.0f;

	/** Closest point on the centreline. */
	UPROPERTY(BlueprintReadOnly, Category = "Road")
	FVector Position = FVector::ZeroVector;

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	FVector Tangent = FVector::ForwardVector;

	/** Unit vector pointing to the right-hand side of the road (banking included). */
	UPROPERTY(BlueprintReadOnly, Category = "Road")
	FVector Right = FVector::RightVector;

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	ERoamSurface Surface = ERoamSurface::Asphalt;

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	ERoamRoadClass RoadClass = ERoamRoadClass::Regional;

	/** 3D distance from the query location to Position. */
	UPROPERTY(BlueprintReadOnly, Category = "Road")
	float DistanceCm = 0.0f;

	/** Signed lateral offset of the query location from the centreline, + = right of the road direction. */
	UPROPERTY(BlueprintReadOnly, Category = "Road")
	float LateralCm = 0.0f;

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	float WidthCm = 0.0f;

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	float SpeedLimitKmh = 0.0f;

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	float BankDeg = 0.0f;

	UPROPERTY(BlueprintReadOnly, Category = "Road")
	uint8 Flags = 0;
};

/** Parameters of URoamRoadNetwork::FindNearest. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamRoadQuery
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Query")
	FVector Location = FVector::ZeroVector;

	/** Bit mask of ERoamRoadClass values that may match (bit index = enum value). 0xFF = all. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Query")
	int32 ClassMask = 0xFF;

	/** Search radius in cm. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Query")
	float MaxDistanceCm = 50000.0f;

	/** If non-zero, candidates whose vertical distance exceeds this are ignored (bridge over road). 0 = off. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Query")
	float MaxVerticalCm = 0.0f;

	/** Optional heading (world direction): roads running against it are penalised, to pick the road a car is travelling on. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Query")
	FVector Heading = FVector::ZeroVector;

	/** Prefer this road when two candidates are within ~1 m of each other (hysteresis for continuous tracking). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Query")
	FName PreferRoadId;
};

/** One leg of a route: drive along road RoadIndex from FromS to ToS (ToS < FromS means against the road direction). */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamRouteLeg
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Route")
	int32 RoadIndex = INDEX_NONE;
	UPROPERTY(BlueprintReadOnly, Category = "Route")
	FName RoadId;
	UPROPERTY(BlueprintReadOnly, Category = "Route")
	float FromS = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Route")
	float ToS = 0.0f;
	/** Junction entered at the end of this leg (NAME_None for the last leg). */
	UPROPERTY(BlueprintReadOnly, Category = "Route")
	FName EndJunction;
};

USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamRoute
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Route")
	bool bValid = false;
	UPROPERTY(BlueprintReadOnly, Category = "Route")
	float LengthCm = 0.0f;
	/** A* cost (length weighted by road class). */
	UPROPERTY(BlueprintReadOnly, Category = "Route")
	float Cost = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Route")
	TArray<FRoamRouteLeg> Legs;
};

// ------------------------------------------------------------------------------------------------------------------
// Notifications
// ------------------------------------------------------------------------------------------------------------------

/** A HUD notification (URoamUISubsystem::PushNotification). Presentation by the UI owner. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamNotification
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Notification")
	ERoamNotifyKind Kind = ERoamNotifyKind::Toast;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Notification")
	FText Title;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Notification")
	FText Body;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Notification")
	FLinearColor Color = FLinearColor(0.133f, 0.827f, 0.933f, 1.0f); // Beacon Cyan

	/** Display time in seconds. <= 0 means "use the player's NotificationSeconds setting". */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Notification")
	float Seconds = 0.0f;

	/** ResultCard only: 0..3 stars, big value text and "NEW BEST" tag. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Notification")
	int32 Stars = 0;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Notification")
	FText Value;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Notification")
	bool bNewBest = false;

	/** Assigned by the UI subsystem. */
	UPROPERTY(BlueprintReadOnly, Category = "Notification")
	int32 Id = 0;
	/** World/real time (FPlatformTime::Seconds) at which the notification was pushed. */
	UPROPERTY(BlueprintReadOnly, Category = "Notification")
	double PushTime = 0.0;
};
