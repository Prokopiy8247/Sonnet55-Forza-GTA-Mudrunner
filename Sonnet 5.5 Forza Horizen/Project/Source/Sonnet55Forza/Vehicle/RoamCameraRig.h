// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Camera/CameraComponent.h"
#include "Core/RoamTypes.h"
#include "RoamCameraRig.generated.h"

class ARoamVehicle;
class URoamCarDefinition;

DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnCameraModeChanged, ERoamCameraMode /*Old*/, ERoamCameraMode /*New*/);

/**
 * The vehicle's camera: chase, hood, cockpit, bumper, free look and (photo) modes with speed dependent FOV/distance, camera
 * collision against the world and shake (Docs/ARCHITECTURE.md section 3 "camera", prompt section 5).
 *
 * It is a UCameraComponent attached to the vehicle body; the possessing player controller finds it automatically as the view
 * target camera. Chase/free-look run in WORLD space (absolute location/rotation) so the body's pitch/roll does not shake the view.
 *
 * ---- OWNER: camera/audio agent ----------------------------------------------------------------------------------------------
 * The skeleton implements a simple but working chase camera (smoothed follow behind the car, FOV widening with speed) and fixed
 * anchors for the in-car modes, so the placeholder car can be driven and screenshots are meaningful. The owner replaces
 * UpdateChase/UpdateFixed with the polished versions (collision probes on RoamCollision::TraceCamera, impact and speed shake,
 * smooth blends between modes, look-behind, free look orbit). The public API below is the contract used by the controller, UI,
 * photo mode and console.
 */
UCLASS(ClassGroup = (Roam), meta = (BlueprintSpawnableComponent))
class SONNET55FORZA_API URoamCameraRig : public UCameraComponent
{
	GENERATED_BODY()

public:
	URoamCameraRig();

	//~ Begin UActorComponent
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;
	//~ End

	/** Switches the mode (blends over ModeBlendSeconds). Photo mode is entered by the photo-mode system, not by cycling. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Camera")
	void SetCameraMode(ERoamCameraMode NewMode);

	UFUNCTION(BlueprintCallable, Category = "Roam|Camera")
	ERoamCameraMode GetCameraMode() const { return Mode; }

	/** Chase -> Hood -> Cockpit -> Bumper -> Chase (FreeLook and Photo are skipped). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Camera")
	void CycleCameraMode();

	/** Reads the camera anchors (hood/cockpit/bumper) and size of the car. nullptr resets to the placeholder anchors. */
	void ApplyCarDefinition(const URoamCarDefinition* Definition);

	/** Jump to the ideal position without smoothing (after a teleport / car switch / mode change at spawn). */
	void SnapToVehicle();

	/** Right stick / mouse look: yaw/pitch deltas in degrees (free look and chase orbit). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Camera")
	void AddLookInput(float YawDelta, float PitchDelta);

	/** Impact feedback: adds shake of the given strength (0..1) that decays on its own. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Camera")
	void AddImpactShake(float Strength);

	/** Called by the vehicle each frame with the latest telemetry (speed FOV, shake from speed and road roughness). */
	void UpdateFromTelemetry(const struct FRoamVehicleTelemetry& Telemetry);

	/** Base horizontal FOV in degrees for the chase mode (widens with speed up to FovSpeedBoost). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Chase")
	float ChaseBaseFov = 78.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Chase")
	float FovSpeedBoost = 18.0f;
	/** Speed (km/h) at which the full FOV boost is reached. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Chase")
	float FovFullBoostKmh = 250.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Chase")
	float ChaseDistanceCm = 620.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Chase")
	float ChaseHeightCm = 200.0f;
	/** Extra distance at full speed. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Chase")
	float ChaseDistanceSpeedGainCm = 160.0f;
	/** Positional / rotational follow speed (higher = stiffer). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Chase")
	float FollowLocationSpeed = 9.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Chase")
	float FollowRotationSpeed = 5.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Modes")
	float InCarFov = 85.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera|Modes")
	float ModeBlendSeconds = 0.35f;

	FRoamOnCameraModeChanged OnModeChanged;

private:
	void UpdateChase(float DeltaTime);
	void UpdateFixed(float DeltaTime);
	ARoamVehicle* GetVehicle() const;

	ERoamCameraMode Mode = ERoamCameraMode::Chase;

	// anchors (car space, cm)
	FVector HoodAnchor = FVector(45.0f, 0.0f, 125.0f);
	FVector CockpitAnchor = FVector(-5.0f, -35.0f, 118.0f);
	FVector BumperAnchor = FVector(215.0f, 0.0f, 45.0f);

	float LookYaw = 0.0f;
	float LookPitch = 0.0f;
	float ShakeStrength = 0.0f;
	float SpeedKmh = 0.0f;
	FVector SmoothedLocation = FVector::ZeroVector;
	FRotator SmoothedRotation = FRotator::ZeroRotator;
	float SmoothedYaw = 0.0f;
	bool bNeedsSnap = true;
};
