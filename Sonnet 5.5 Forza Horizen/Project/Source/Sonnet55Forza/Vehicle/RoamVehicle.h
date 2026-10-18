// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "Core/RoamTypes.h"
#include "RoamVehicle.generated.h"

class UMaterialInstanceDynamic;
class UStaticMeshComponent;
class URoamCameraRig;
class URoamCarDefinition;
class URoamEngineSynth;
class URoamVehicleFX;
class URoamVehicleMovement;
class URoamVehicleVisuals;

class ARoamVehicle;
DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnCarApplied, ARoamVehicle* /*Vehicle*/);
DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnVehicleImpact, ARoamVehicle* /*Vehicle*/, float /*ImpactSpeedMs*/);
DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnVehicleRecovered, ARoamVehicle* /*Vehicle*/);

/**
 * The drivable car (Docs/ARCHITECTURE.md sections 3 and 4). One class for all ten garage cars: the car-specific data comes
 * from a URoamCarDefinition applied with ApplyCarDefinition(); the pawn itself has no per-car code.
 *
 * COMPONENT LAYOUT (created in the constructor so every agent can rely on it):
 *   Body              UStaticMeshComponent  ROOT. Pivot = car origin (ground under the middle of the wheelbase, Docs/BLENDER_CONTRACT.md).
 *                     Simple collision from the Blender UCX hulls, profile "RoamVehicle". Physics body once the model is ready.
 *   PlaceholderBody   engine cube scaled to the car's size, visible only while the Body has no mesh (skeleton stand-in).
 *   GlassMesh / InteriorMesh / SteeringWheelMesh   attached to Body.
 *   WheelMeshes[0..3] FL, FR, RL, RR (ERoamWheel order), visual only, positioned from suspension state.
 *   VehicleMovement   URoamVehicleMovement  inputs, simulation, telemetry.
 *   Visuals           URoamVehicleVisuals   paint, lights, wheel/steering-wheel animation.
 *   CameraRig         URoamCameraRig        chase/hood/cockpit/bumper/free-look camera.
 *   EngineSynth       URoamEngineSynth      procedural engine sound.
 *   VehicleFX         URoamVehicleFX        smoke, dust, sparks, skid marks.
 *
 * Every function marked "OWNER:" is a stub with a final signature: the owning agent fills the body, nobody changes the signature.
 */
UCLASS(Blueprintable)
class SONNET55FORZA_API ARoamVehicle : public APawn
{
	GENERATED_BODY()

public:
	ARoamVehicle();

	//~ Begin AActor / APawn
	virtual void PostInitializeComponents() override;
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void PossessedBy(AController* NewController) override;
	virtual void UnPossessed() override;
	//~ End

	// ---- components ------------------------------------------------------------------------------------------------
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<UStaticMeshComponent> Body;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<UStaticMeshComponent> PlaceholderBody;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<UStaticMeshComponent> GlassMesh;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<UStaticMeshComponent> InteriorMesh;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<UStaticMeshComponent> SteeringWheelMesh;

	/** FL, FR, RL, RR. */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TArray<TObjectPtr<UStaticMeshComponent>> WheelMeshes;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<URoamVehicleMovement> VehicleMovement;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<URoamVehicleVisuals> Visuals;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<URoamCameraRig> CameraRig;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<URoamEngineSynth> EngineSynth;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Vehicle|Components")
	TObjectPtr<URoamVehicleFX> VehicleFX;

	// ---- car selection ---------------------------------------------------------------------------------------------
	/**
	 * Definition applied in BeginPlay when none was applied yet. Set it on a deferred-spawned actor
	 * (ARoamGameMode::SpawnPlayerCar does) before FinishSpawning.
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, meta = (ExposeOnSpawn = "true"), Category = "Vehicle")
	TObjectPtr<URoamCarDefinition> InitialCarDefinition;

	/**
	 * Applies a car: meshes, wheel/camera/light anchors, mass/engine/gearbox/tyres in the movement component, sound profile.
	 * Works on a live vehicle (garage swap) - the transform is kept, velocity is reset. nullptr falls back to the placeholder look.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	void ApplyCarDefinition(URoamCarDefinition* Definition);

	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	URoamCarDefinition* GetCarDefinition() const { return CarDefinition; }

	/** CarId of the applied definition or NAME_None. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	FName GetCarId() const;

	// ---- paint / tuning / upgrades ---------------------------------------------------------------------------------
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	void SetPaint(const FRoamPaint& NewPaint);
	const FRoamPaint& GetPaint() const { return Paint; }

	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	void SetTuning(const FRoamTuning& NewTuning);
	const FRoamTuning& GetTuning() const;
	void SetUpgrades(const TMap<FName, int32>& NewUpgrades);

	// ---- telemetry -------------------------------------------------------------------------------------------------
	/** Filled every frame by the movement component. Valid even before BeginPlay (zeroed). */
	const FRoamVehicleTelemetry& GetTelemetry() const;

	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	float GetSpeedKmh() const;

	// ---- driver inputs (ARoamPlayerController, AI and tests call these) --------------------------------------------
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Input")
	void SetThrottle(float Value);
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Input")
	void SetBrake(float Value);
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Input")
	void SetSteer(float Value);
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Input")
	void SetHandbrake(float Value);
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Input")
	void ShiftUp();
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Input")
	void ShiftDown();

	/**
	 * AI / scripted-test mode: input filtering is switched off (raw values are used), the player controller does not feed the
	 * vehicle (ARoamPlayerController checks IsAIControlled) and the engine synth is muted. Automated drive tests use it.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Input")
	void SetAIControlled(bool bInAIControlled);
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Input")
	bool IsAIControlled() const { return bAIControlled; }

	// ---- assists ---------------------------------------------------------------------------------------------------
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Assists")
	void SetAssist(ERoamAssist Assist, bool bEnabled);
	/** Name based variant for the console: "tcs", "abs", "stm", "steer", "auto", "line". Returns false for unknown names. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Assists")
	bool SetAssistByName(const FString& AssistName, bool bEnabled);
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Assists")
	void SetAssists(const FRoamAssistSettings& NewAssists);
	const FRoamAssistSettings& GetAssists() const;

	// ---- camera ----------------------------------------------------------------------------------------------------
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Camera")
	void SetCameraMode(ERoamCameraMode Mode);
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Camera")
	ERoamCameraMode GetCameraMode() const;
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle|Camera")
	void CycleCameraMode();

	// ---- recovery / teleport ---------------------------------------------------------------------------------------
	/**
	 * Puts the car on the nearest road point (URoamRoadNetwork), facing the lane direction it was closest to, upright, speed zero.
	 * Without a road network (test map) it re-uprights the car at its current position. Returns true if a road was used.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	bool ResetToRoad();

	/** Rolls the car upright at its current position (small lift to clear the ground), keeps heading. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	void FlipUpright();

	/** Moves the car, optionally keeping its speed along the new heading, and informs systems that track continuity (activities, traffic, camera). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	void TeleportVehicle(const FTransform& NewTransform, bool bKeepSpeed = false);

	/** Clears damage (visual deformation states are an OWNER: vehicle-visuals stretch goal). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	void Repair();

	// ---- lights / horn ---------------------------------------------------------------------------------------------
	/** Headlights follow the time-of-day/visibility signal of URoamTimeWeatherSubsystem unless overridden. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	void SetHeadlightsOverride(bool bOverride, bool bOn);
	UFUNCTION(BlueprintCallable, Category = "Roam|Vehicle")
	void SoundHorn(bool bPressed);

	// ---- events ----------------------------------------------------------------------------------------------------
	/** Broadcast after ApplyCarDefinition finished (UI refresh, FX re-init). */
	FRoamOnCarApplied OnCarApplied;
	/** Broadcast by the physics model for hard impacts (owner: vehicle physics). */
	FRoamOnVehicleImpact OnImpact;
	/** Broadcast after ResetToRoad / FlipUpright / TeleportVehicle. */
	FRoamOnVehicleRecovered OnRecovered;

	/**
	 * Called by URoamVehicleMovement at the end of its tick once the telemetry of this frame is final: forwards it to the camera
	 * rig, the engine synth and the FX component. (The visuals component reads the telemetry in its own tick.)
	 */
	void PublishTelemetry(float DeltaTime);

	/** Returns the player-controlled vehicle of a world (first local player pawn) or nullptr. */
	static ARoamVehicle* GetPlayerVehicle(const UObject* WorldContext);

protected:
	/** Creates the wheel/steering/glass/interior mesh components. */
	UStaticMeshComponent* CreateVisualMesh(const FName Name, UStaticMeshComponent* Parent);

	/** Pulls the profile (paint, tuning, assists, upgrades) of this car out of the save subsystem. */
	void ApplyProfileSettings();

private:
	UPROPERTY(Transient)
	TObjectPtr<URoamCarDefinition> CarDefinition;

	UPROPERTY(Transient)
	FRoamPaint Paint;

	bool bAIControlled = false;
	bool bBegunPlay = false;
};
