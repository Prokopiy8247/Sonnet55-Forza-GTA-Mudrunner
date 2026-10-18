// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Core/RoamTypes.h"
#include "RoamVehicleVisuals.generated.h"

class ARoamVehicle;
class UMaterialInstanceDynamic;
class URoamCarDefinition;

/**
 * Everything the player SEES of the car except the camera: mesh assignment from the car definition, wheel placement/spin/steer,
 * steering-wheel rotation, paint (primary/secondary colours and gloss/matte/metallic finish through dynamic material instances),
 * and the light states (brake, reverse, headlights, indicators, hazard).
 *
 * The component is owned by ARoamVehicle and manipulates the mesh components the vehicle created. Tick: it ticks once per frame
 * (post-physics) only to animate wheels/steering wheel; nothing else ticks for visuals.
 *
 * ---- OWNER: vehicle-visuals agent ------------------------------------------------------------------------------------------
 * Skeleton behaviour: loads the soft meshes of the definition (if present), places the four wheel components at the geometry
 * wheel centres, spins/steers them from telemetry, tints the placeholder body with the paint colour (engine BasicShapeMaterial
 * "Color" parameter). The owner adds: master paint material with the three finishes, rim styles/colours, stripe masks, light
 * emissive control per material slot, brake-disc glow, suspension-driven wheel offsets (travel, camber), body roll for the
 * kinematic mode, damage states.
 */
UCLASS(ClassGroup = (Roam), meta = (BlueprintSpawnableComponent))
class SONNET55FORZA_API URoamVehicleVisuals : public UActorComponent
{
	GENERATED_BODY()

public:
	URoamVehicleVisuals();

	virtual void BeginPlay() override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

	/** Assigns meshes and positions anchors for a car (nullptr = placeholder look sized by the geometry defaults). */
	void ApplyCarDefinition(URoamCarDefinition* Definition);

	/** Paints the car. Safe to call before ApplyCarDefinition. */
	void SetPaint(const FRoamPaint& NewPaint);

	// ---- lights -----------------------------------------------------------------------------------------------------
	/** Headlights follow URoamTimeWeatherSubsystem::ShouldVehicleLightsBeOn() unless an override is set. */
	void SetHeadlightsOverride(bool bOverride, bool bOn);
	bool AreHeadlightsOn() const { return bHeadlightsOn; }
	bool AreBrakeLightsOn() const { return bBrakeLightsOn; }
	bool AreReverseLightsOn() const { return bReverseLightsOn; }
	void SetHazardLights(bool bOn) { bHazardLights = bOn; }
	bool AreHazardLightsOn() const { return bHazardLights; }

	/** The wheel rotation angles (deg) accumulated by the animation, for FX that needs them. */
	float GetWheelSpinDeg(int32 WheelIndex) const { return WheelIndex >= 0 && WheelIndex < 4 ? WheelSpinDeg[WheelIndex] : 0.0f; }

	// ---- diagnostics (integration tests, `cartest` console command) ----------------------------------------------------
	/** Current emissive intensity written to the lamp materials (smoothed). */
	float GetHeadLightIntensity() const { return HeadLevel; }
	float GetTailLightIntensity() const { return TailLevel; }
	float GetReverseLightIntensity() const { return ReverseLevel; }
	/** One line: number of dynamic instances per role and the slots that still show the engine default (grey) material. */
	FString DescribeMaterials() const;
	/** Reads back PrimaryColor / Intensity of the live dynamic instances (-1 when the role has no instance). */
	float ReadLampIntensity(const TCHAR* Role) const;
	FLinearColor ReadPrimaryColor(bool bSecondary) const;

protected:
	void ApplyPaintToMaterials();
	void RebuildMaterialInstances();
	void UpdateLightStates(const FRoamVehicleTelemetry& Telemetry);
	void UpdateLampMaterials(float DeltaTime);
	void UpdateWeatherMaterials();
	void UpdateWheelsAndSteeringWheel(const FRoamVehicleTelemetry& Telemetry, float DeltaTime);

private:
	ARoamVehicle* GetVehicle() const;

	UPROPERTY(Transient)
	TObjectPtr<URoamCarDefinition> Definition;

	UPROPERTY(Transient)
	TObjectPtr<UMaterialInstanceDynamic> PlaceholderMaterial;

	/** One dynamic instance per mesh component slot that carries the primary paint. */
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> PaintMaterials;

	// Dynamic instances per role (master parameter contract: Docs/Tech/CARS_IMPORT.md section 4).
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> Paint2Materials;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> HeadMaterials;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> TailMaterials;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> ReverseMaterials;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> IndicatorMaterials;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> RimMaterials;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> DiscMaterials;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> GlassMaterials;

	float HeadLevel = 0.0f;
	float TailLevel = 0.0f;
	float ReverseLevel = 0.0f;
	float IndicatorLevel = 0.0f;
	float IndicatorPhase = 0.0f;
	float BrakeHeat = 0.0f;
	float WeatherTimer = 0.0f;
	FString MaterialReport;

	FRoamPaint Paint;
	float WheelSpinDeg[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
	float WheelRadiusCm[4] = { 33.0f, 33.0f, 33.0f, 33.0f };
	bool bHeadlightsOverride = false;
	bool bHeadlightsOverrideValue = false;
	bool bHeadlightsOn = false;
	bool bBrakeLightsOn = false;
	bool bReverseLightsOn = false;
	bool bHazardLights = false;
};
