// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "Core/RoamTypes.h"
#include "RoamVehicleFX.generated.h"

/**
 * Visual and audible effects that react to the vehicle state: tyre smoke and dust per surface, wheel spray in the wet, brake
 * glow, sparks and debris on impacts, skid marks, exhaust flames and the one-shot sounds (tyre squeal per surface, wind, suspension
 * thumps, impacts). Fed with telemetry by ARoamVehicle every frame; Niagara systems are created by script/code and pooled.
 *
 * ---- OWNER: effects agent ---------------------------------------------------------------------------------------------------
 * Skeleton: no-op. The owner fills UpdateFromTelemetry and the Notify* functions and may add Niagara/audio components to the
 * vehicle in OnRegister. Budget: no per-wheel tick of its own, spawn rates scale with telemetry, systems are deactivated when
 * the vehicle is far from the camera.
 */
UCLASS(ClassGroup = (Roam), meta = (BlueprintSpawnableComponent))
class SONNET55FORZA_API URoamVehicleFX : public UActorComponent
{
	GENERATED_BODY()

public:
	URoamVehicleFX();

	/** Master switch (traffic cars far away, photo mode). */
	UFUNCTION(BlueprintCallable, Category = "Roam|FX")
	void SetFXEnabled(bool bEnabled) { bFXEnabled = bEnabled; }
	UFUNCTION(BlueprintCallable, Category = "Roam|FX")
	bool IsFXEnabled() const { return bFXEnabled; }

	/** Per-frame update from ARoamVehicle (OWNER: effects). */
	void UpdateFromTelemetry(const FRoamVehicleTelemetry& Telemetry, float DeltaTime);

	/** A collision happened: world location/normal of the contact and strength = velocity change in m/s (OWNER: effects). */
	void NotifyImpact(const FVector& Location, const FVector& Normal, float StrengthMs);

	/** The car was reset/teleported: clear trails and pending effects (OWNER: effects). */
	void NotifyTeleported();

private:
	bool bFXEnabled = true;
};
