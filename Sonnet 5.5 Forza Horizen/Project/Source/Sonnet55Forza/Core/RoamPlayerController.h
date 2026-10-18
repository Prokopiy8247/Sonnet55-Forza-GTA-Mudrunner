// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "RoamPlayerController.generated.h"

class ARoamVehicle;
class UInputAction;
class UInputMappingContext;

/** Logical input actions of the game. The enhanced-input assets for them are created at RUNTIME (no editor assets, Docs/ARCHITECTURE.md section 1). */
UENUM(BlueprintType)
enum class ERoamInputAction : uint8
{
	Throttle = 0,
	Brake,
	Steer,
	Handbrake,
	ShiftUp,
	ShiftDown,
	CycleCamera,
	LookX,
	LookY,
	ResetVehicle,
	ToggleConsole,
	ToggleGarage,
	ToggleDebugMenu,
	ToggleMap,
	PhotoMode,
	Pause,
	Count UMETA(Hidden)
};

DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnInputAction, ERoamInputAction /*Action*/);

/**
 * Player controller of Roamline: Enhanced Input set up in C++, driving input for the possessed ARoamVehicle, UI toggles.
 *
 * DEFAULT BINDINGS (keyboard+mouse / gamepad):
 *   Throttle   W, Up                / right trigger         Brake      S, Down            / left trigger
 *   Steer      A, D, Left, Right    / left stick X          Handbrake  Space              / B (face right)
 *   ShiftUp    E                    / right shoulder        ShiftDown  Q                  / left shoulder
 *   CycleCamera C                   / right stick click     ResetVehicle R                / Y (face top)
 *   LookX/LookY mouse (hold right button) / right stick
 *   ToggleConsole  ` (tilde)                                ToggleGarage   F1, Tab        / -
 *   ToggleDebugMenu F2                                      ToggleMap      M              / View (special left)
 *   PhotoMode  P                    / D-pad up              Pause          Esc            / Menu (special right)
 *
 * Two mapping contexts: "Gameplay" (driving, can be switched off while a menu or the console has input focus) and "System" (the
 * UI toggles, always active, also while the game is paused). Axis input is polled every frame from the enhanced player input, digital
 * actions call the virtual On... hooks and broadcast OnActionTriggered. Other agents hook in by overriding a hook in a subclass,
 * binding OnActionTriggered, or (simplest) acting inside the default hook's target subsystem.
 *
 * ---- OWNER of the rest: UI agent (menus), camera agent (photo mode) ----------------------------------------------------------
 * The UI/photo owners fill the targets of OnToggle... (URoamUISubsystem panels); this class stays input-only.
 */
UCLASS()
class SONNET55FORZA_API ARoamPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	ARoamPlayerController();

	//~ Begin AActor / AController / APlayerController
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void SetupInputComponent() override;
	virtual void PlayerTick(float DeltaTime) override;
	//~ End

	/** The possessed vehicle (nullptr if the pawn is something else). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Input")
	ARoamVehicle* GetRoamVehicle() const;

	/**
	 * Enables/disables the Gameplay mapping context (driving input). The UI subsystem turns it off while the console, garage, map,
	 * pause menu or photo mode has the input; pedals are released so the car does not keep accelerating.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|Input")
	void SetGameplayInputEnabled(bool bEnabled);
	UFUNCTION(BlueprintCallable, Category = "Roam|Input")
	bool IsGameplayInputEnabled() const { return bGameplayInputEnabled; }

	UInputAction* GetInputAction(ERoamInputAction Action) const;
	UInputMappingContext* GetGameplayContext() const { return GameplayContext; }
	UInputMappingContext* GetSystemContext() const { return SystemContext; }

	/** Broadcast for every digital action (Started). */
	FRoamOnInputAction OnActionTriggered;

	// ---- overridable hooks for the digital actions -----------------------------------------------------------------
	virtual void OnShiftUp();
	virtual void OnShiftDown();
	virtual void OnCycleCamera();
	virtual void OnResetVehicle();
	virtual void OnToggleConsole();
	virtual void OnToggleGarage();
	virtual void OnToggleDebugMenu();
	virtual void OnToggleMap();
	virtual void OnPhotoMode();
	virtual void OnPause();

	/** Degrees per second of free-look at full right-stick deflection. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Input")
	float StickLookDegPerSec = 140.0f;

	/** Degrees per mouse count while the right mouse button is held. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Input")
	float MouseLookDegPerCount = 0.12f;

protected:
	/** Creates the UInputAction objects and both mapping contexts (idempotent). */
	void EnsureInputAssets();
	void RegisterMappingContexts();
	void UnregisterMappingContexts();

private:
	UInputAction* MakeAction(ERoamInputAction Id, const TCHAR* Name, bool bAxis, bool bTriggerWhenPaused);
	void BindDigital(class UEnhancedInputComponent* Component, ERoamInputAction Action, void (ARoamPlayerController::*Handler)());
	void HandleDigital(ERoamInputAction Action);
	void HandleShiftUp() { HandleDigital(ERoamInputAction::ShiftUp); }
	void HandleShiftDown() { HandleDigital(ERoamInputAction::ShiftDown); }
	void HandleCycleCamera() { HandleDigital(ERoamInputAction::CycleCamera); }
	void HandleResetVehicle() { HandleDigital(ERoamInputAction::ResetVehicle); }
	void HandleToggleConsole() { HandleDigital(ERoamInputAction::ToggleConsole); }
	void HandleToggleGarage() { HandleDigital(ERoamInputAction::ToggleGarage); }
	void HandleToggleDebugMenu() { HandleDigital(ERoamInputAction::ToggleDebugMenu); }
	void HandleToggleMap() { HandleDigital(ERoamInputAction::ToggleMap); }
	void HandlePhotoMode() { HandleDigital(ERoamInputAction::PhotoMode); }
	void HandlePause() { HandleDigital(ERoamInputAction::Pause); }

	UPROPERTY(Transient)
	TMap<ERoamInputAction, TObjectPtr<UInputAction>> Actions;

	UPROPERTY(Transient)
	TObjectPtr<UInputMappingContext> GameplayContext;

	UPROPERTY(Transient)
	TObjectPtr<UInputMappingContext> SystemContext;

	bool bGameplayInputEnabled = true;
	bool bContextsRegistered = false;
};
