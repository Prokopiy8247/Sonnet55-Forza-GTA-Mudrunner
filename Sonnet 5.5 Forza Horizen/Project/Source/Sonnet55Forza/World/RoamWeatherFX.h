// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "RoamWeatherFX.generated.h"

class UMaterialInstanceDynamic;

/**
 * Lightweight camera-attached rain: a pool of thin camera-facing streak quads (engine Plane mesh) in ONE instanced static mesh
 * component. No particles, no per-drop state: every drop is a pure function of (seed, time, camera position) wrapped into a
 * box around the camera, so the cost is a transform update of the active instances per frame (about 0.2 ms for 1500 drops).
 * Streaks are stretched along the drop velocity relative to the camera (so they lengthen when the car drives fast), widened with
 * distance to stay visible, and faded out near the edges of the box so nothing pops.
 *
 * Material: /Game/Forza/Materials/M_Roam_Rain_Streak when it exists (vector parameter "Color", alpha = opacity), otherwise the
 * engine's unlit translucent debug material. Both paths degrade gracefully (no material = no rain, never an error).
 * The streak colour is multiplied by the current exposure (1.2 * 2^EV100) so the streaks keep their look from noon to night.
 */
UCLASS(ClassGroup = (Roam), meta = (BlueprintSpawnableComponent))
class SONNET55FORZA_API URoamRainFXComponent : public UInstancedStaticMeshComponent
{
	GENERATED_BODY()

public:
	URoamRainFXComponent(const FObjectInitializer& ObjectInitializer);

	/** Maximum number of streaks (all visible at rain intensity 1). */
	UPROPERTY(EditAnywhere, Category = "Rain", meta = (ClampMin = "0", ClampMax = "6000"))
	int32 PoolSize = 2200;

	/** Half extent (cm) of the wrapped box around the camera in X and Y. */
	UPROPERTY(EditAnywhere, Category = "Rain", meta = (ClampMin = "200"))
	float BoxHalfExtentXY = 1800.0f;

	/** Height (cm) of the box; 35 percent of it is below the camera, 65 percent above. */
	UPROPERTY(EditAnywhere, Category = "Rain", meta = (ClampMin = "200"))
	float BoxHeight = 1400.0f;

	/** Streak length = relative speed * this (seconds), clamped to MinStreakLength..MaxStreakLength (cm). */
	UPROPERTY(EditAnywhere, Category = "Rain")
	float ShutterSeconds = 0.045f;
	UPROPERTY(EditAnywhere, Category = "Rain")
	float MinStreakLength = 22.0f;
	UPROPERTY(EditAnywhere, Category = "Rain")
	float MaxStreakLength = 240.0f;

	/** Loads the mesh/material and builds the instance pool. Returns false when no usable material exists (rain stays off). */
	bool InitFX();
	bool IsReady() const { return bReady; }

	/**
	 * Per-frame update. WindMs: wind velocity in cm/s. ExposureEV100: the centre of the current exposure bracket (colour scaling).
	 * Daylight01 dims the streaks at night. FallSpeed in cm/s.
	 */
	void UpdateRain(float Intensity01, const FVector& CameraLocation, const FVector& CameraVelocity, const FVector& WindCmPerSec,
		float ExposureEV100, float Daylight01, float FallSpeed, float DeltaSeconds);

	/** Number of streaks currently drawn (stats / tests). */
	int32 GetActiveCount() const { return ActiveCount; }

private:
	void ApplyMaterialColor(float Intensity01, float ExposureEV100, float Daylight01);

	UPROPERTY(Transient)
	TObjectPtr<UMaterialInstanceDynamic> StreakMID;

	TArray<FVector3f> Seeds;
	TArray<float> SpeedMuls;
	TArray<FTransform> Scratch;
	double Clock = 0.0;
	int32 ActiveCount = 0;
	int32 WrittenCount = 0;
	bool bReady = false;
	float LastColorKey = -1.0f;
};
