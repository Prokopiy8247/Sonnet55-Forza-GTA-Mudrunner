// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "Core/RoamTypes.h"
#include "Traffic/RoamTrafficVehicle.h"
#include "RoamTrafficCatalog.generated.h"

class UStaticMesh;

/**
 * Data of the civilian vehicles (Docs/CAR_ROSTER.md traffic01..06), authored by Tools/ue/cars_data.py from the Blender export
 * sidecar JSON (Exports/Traffic/<id>/<id>.json) and the imported meshes (/Game/Forza/Traffic/<id>/). It is the data asset
 * /Game/Forza/Data/DA_TrafficVehicles. The traffic subsystem registers `Spec` of every entry with
 * URoamTrafficSubsystem::RegisterVehicleType; the extra parts (glass, interior, all wheels - buses and lorries have 6-10) are used
 * by ARoamTrafficVehicle when it builds its component set.
 *
 * Geometry units: centimetres in UE car space (+X forward, +Y right, +Z up, origin = ground under the middle of the wheelbase),
 * i.e. UE.x = blender.x * 100, UE.y = -blender.y * 100, UE.z = blender.z * 100 (so LEFT wheels have NEGATIVE Y).
 */

/** One wheel of a traffic vehicle (variable count per vehicle type). The mesh pivot is the axle centre, axle along local Y. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamTrafficWheelDef
{
	GENERATED_BODY()

	/** Blender part name, e.g. "traffic04_bus_Wheel_3". */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	FName PartName;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	TSoftObjectPtr<UStaticMesh> Mesh;

	/** Axle centre relative to the vehicle origin (cm, UE axes). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	FVector CenterCm = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	float RadiusCm = 30.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	float WidthCm = 20.0f;

	/** 0 = front axle, increasing towards the rear. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	int32 AxleIndex = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	bool bSteering = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	bool bDriven = false;

	/** True for wheels on the vehicle's left side (negative UE Y). Dual wheels share the side of their partner. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Wheel")
	bool bLeftSide = false;
};

/** Complete description of one traffic vehicle type. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamTrafficVehicleDef
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	FName TypeId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Identity")
	FText DisplayName;

	/** The registry entry for URoamTrafficSubsystem (BodyMesh set, WheelMesh = first wheel mesh, sizes and IDM numbers filled). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Spec")
	FRoamTrafficVehicleSpec Spec;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> GlassMesh;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TSoftObjectPtr<UStaticMesh> InteriorMesh;

	/** Every wheel (4 for cars and vans, 6 for the coach, 10 for the lorry). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Meshes")
	TArray<FRoamTrafficWheelDef> Wheels;

	// Anchors (cm, UE car space). Zero vector = not exported for this vehicle.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Anchors")
	FVector CameraBumperCm = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Anchors")
	FVector CameraCockpitCm = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Anchors")
	FVector HeadLightLCm = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Anchors")
	FVector HeadLightRCm = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Anchors")
	FVector TailLightLCm = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Anchors")
	FVector TailLightRCm = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Anchors")
	FVector ReverseLightCm = FVector::ZeroVector;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Anchors")
	TArray<FVector> ExhaustCm;

	/** Paint variants (primary = M_Paint, secondary = M_Paint2) the spawner picks from at random. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Appearance")
	TArray<FRoamPaint> PaintVariants;

	/** Typical cruise speed range in km/h (JSON `traffic.cruise_speed_kmh`). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Behaviour")
	FVector2D CruiseSpeedKmh = FVector2D(50.0, 110.0);

	/** Number of axles (for the lorry's 3 axles, the coach's 2 ...). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Behaviour")
	int32 NumAxles = 2;

	/** Wheelbase between the first and the last axle in cm. */
	float GetWheelbaseCm() const { return Spec.WheelbaseCm; }
};

/** The set of civilian vehicle types. One asset: /Game/Forza/Data/DA_TrafficVehicles. */
UCLASS(BlueprintType)
class SONNET55FORZA_API URoamTrafficCatalog : public UDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	TArray<FRoamTrafficVehicleDef> Vehicles;

	UFUNCTION(BlueprintCallable, Category = "Roam|Traffic")
	int32 GetNumVehicles() const { return Vehicles.Num(); }

	/** Entry by TypeId or nullptr. */
	const FRoamTrafficVehicleDef* FindByTypeId(FName TypeId) const;

	/** Copies the registry specs of all entries (what URoamTrafficSubsystem::RegisterVehicleType wants). */
	void GetSpecs(TArray<FRoamTrafficVehicleSpec>& OutSpecs) const;

	/** Problems: missing meshes, no wheels, duplicate ids, non-positive sizes. */
	bool Validate(TArray<FString>& OutProblems) const;
};
