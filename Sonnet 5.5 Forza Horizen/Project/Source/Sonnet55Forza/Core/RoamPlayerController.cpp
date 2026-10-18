// Copyright Epic Games, Inc. All Rights Reserved.

#include "Core/RoamPlayerController.h"

#include "Core/RoamLog.h"
#include "Core/RoamSettings.h"
#include "Engine/LocalPlayer.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "EnhancedPlayerInput.h"
#include "InputAction.h"
#include "InputMappingContext.h"
#include "InputModifiers.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUISubsystem.h"
#include "Vehicle/RoamCameraRig.h"
#include "Vehicle/RoamVehicle.h"

ARoamPlayerController::ARoamPlayerController()
{
	bShowMouseCursor = false;
	bEnableClickEvents = false;
	bEnableMouseOverEvents = false;
}

ARoamVehicle* ARoamPlayerController::GetRoamVehicle() const
{
	return Cast<ARoamVehicle>(GetPawn());
}

UInputAction* ARoamPlayerController::GetInputAction(ERoamInputAction Action) const
{
	const TObjectPtr<UInputAction>* Found = Actions.Find(Action);
	return Found ? Found->Get() : nullptr;
}

UInputAction* ARoamPlayerController::MakeAction(ERoamInputAction Id, const TCHAR* Name, bool bAxis, bool bTriggerWhenPaused)
{
	UInputAction* Action = NewObject<UInputAction>(this, FName(Name));
	Action->ValueType = bAxis ? EInputActionValueType::Axis1D : EInputActionValueType::Boolean;
	Action->bTriggerWhenPaused = bTriggerWhenPaused;
	Actions.Add(Id, Action);
	return Action;
}

void ARoamPlayerController::EnsureInputAssets()
{
	if (GameplayContext && SystemContext)
	{
		return;
	}

	GameplayContext = NewObject<UInputMappingContext>(this, TEXT("IMC_RoamGameplay"));
	SystemContext = NewObject<UInputMappingContext>(this, TEXT("IMC_RoamSystem"));

	// ---- actions ---------------------------------------------------------------------------------------------------
	UInputAction* Throttle = MakeAction(ERoamInputAction::Throttle, TEXT("IA_Throttle"), true, false);
	UInputAction* Brake = MakeAction(ERoamInputAction::Brake, TEXT("IA_Brake"), true, false);
	UInputAction* Steer = MakeAction(ERoamInputAction::Steer, TEXT("IA_Steer"), true, false);
	UInputAction* Handbrake = MakeAction(ERoamInputAction::Handbrake, TEXT("IA_Handbrake"), false, false);
	UInputAction* ShiftUp = MakeAction(ERoamInputAction::ShiftUp, TEXT("IA_ShiftUp"), false, false);
	UInputAction* ShiftDown = MakeAction(ERoamInputAction::ShiftDown, TEXT("IA_ShiftDown"), false, false);
	UInputAction* CycleCamera = MakeAction(ERoamInputAction::CycleCamera, TEXT("IA_CycleCamera"), false, false);
	UInputAction* LookX = MakeAction(ERoamInputAction::LookX, TEXT("IA_LookX"), true, false);
	UInputAction* LookY = MakeAction(ERoamInputAction::LookY, TEXT("IA_LookY"), true, false);
	UInputAction* ResetVehicle = MakeAction(ERoamInputAction::ResetVehicle, TEXT("IA_ResetVehicle"), false, false);
	UInputAction* ToggleConsole = MakeAction(ERoamInputAction::ToggleConsole, TEXT("IA_ToggleConsole"), false, true);
	UInputAction* ToggleGarage = MakeAction(ERoamInputAction::ToggleGarage, TEXT("IA_ToggleGarage"), false, true);
	UInputAction* ToggleDebugMenu = MakeAction(ERoamInputAction::ToggleDebugMenu, TEXT("IA_ToggleDebugMenu"), false, true);
	UInputAction* ToggleMap = MakeAction(ERoamInputAction::ToggleMap, TEXT("IA_ToggleMap"), false, true);
	UInputAction* PhotoMode = MakeAction(ERoamInputAction::PhotoMode, TEXT("IA_PhotoMode"), false, true);
	UInputAction* Pause = MakeAction(ERoamInputAction::Pause, TEXT("IA_Pause"), false, true);

	const auto Negate = [this](FEnhancedActionKeyMapping& Mapping)
	{
		Mapping.Modifiers.Add(NewObject<UInputModifierNegate>(this));
	};
	const auto DeadZone = [this](FEnhancedActionKeyMapping& Mapping, float Lower)
	{
		UInputModifierDeadZone* Modifier = NewObject<UInputModifierDeadZone>(this);
		Modifier->LowerThreshold = Lower;
		Modifier->Type = EDeadZoneType::Axial;
		Mapping.Modifiers.Add(Modifier);
	};
	const auto Scale = [this](FEnhancedActionKeyMapping& Mapping, float Scalar, bool bByDeltaTime)
	{
		UInputModifierScalar* Modifier = NewObject<UInputModifierScalar>(this);
		Modifier->Scalar = FVector(Scalar, Scalar, Scalar);
		if (bByDeltaTime)
		{
			Mapping.Modifiers.Add(NewObject<UInputModifierScaleByDeltaTime>(this));
		}
		Mapping.Modifiers.Add(Modifier);
	};

	// ---- gameplay context (driving) -----------------------------------------------------------------------------------
	UInputMappingContext* G = GameplayContext;
	G->MapKey(Throttle, EKeys::W);
	G->MapKey(Throttle, EKeys::Up);
	G->MapKey(Throttle, EKeys::Gamepad_RightTriggerAxis);
	G->MapKey(Brake, EKeys::S);
	G->MapKey(Brake, EKeys::Down);
	G->MapKey(Brake, EKeys::Gamepad_LeftTriggerAxis);

	G->MapKey(Steer, EKeys::D);
	G->MapKey(Steer, EKeys::Right);
	Negate(G->MapKey(Steer, EKeys::A));
	Negate(G->MapKey(Steer, EKeys::Left));
	DeadZone(G->MapKey(Steer, EKeys::Gamepad_LeftX), 0.10f);

	G->MapKey(Handbrake, EKeys::SpaceBar);
	G->MapKey(Handbrake, EKeys::Gamepad_FaceButton_Right);
	G->MapKey(ShiftUp, EKeys::E);
	G->MapKey(ShiftUp, EKeys::Gamepad_RightShoulder);
	G->MapKey(ShiftDown, EKeys::Q);
	G->MapKey(ShiftDown, EKeys::Gamepad_LeftShoulder);
	G->MapKey(CycleCamera, EKeys::C);
	G->MapKey(CycleCamera, EKeys::Gamepad_RightThumbstick);
	G->MapKey(ResetVehicle, EKeys::R);
	G->MapKey(ResetVehicle, EKeys::Gamepad_FaceButton_Top);

	// Look: both devices produce DEGREES PER FRAME (mouse: counts * deg/count, stick: deflection * deg/s * dt).
	Scale(G->MapKey(LookX, EKeys::MouseX), MouseLookDegPerCount / 0.07f, false); // MouseX axis is already scaled by 0.07 in DefaultInput.ini
	Scale(G->MapKey(LookY, EKeys::MouseY), MouseLookDegPerCount / 0.07f, false);
	{
		FEnhancedActionKeyMapping& StickX = G->MapKey(LookX, EKeys::Gamepad_RightX);
		DeadZone(StickX, 0.15f);
		Scale(StickX, StickLookDegPerSec, true);
		FEnhancedActionKeyMapping& StickY = G->MapKey(LookY, EKeys::Gamepad_RightY);
		DeadZone(StickY, 0.15f);
		Scale(StickY, StickLookDegPerSec, true);
	}

	// ---- system context (always on) ------------------------------------------------------------------------------------
	UInputMappingContext* S = SystemContext;
	S->MapKey(ToggleConsole, EKeys::Tilde);
	S->MapKey(ToggleGarage, EKeys::F1);
	S->MapKey(ToggleGarage, EKeys::Tab);
	S->MapKey(ToggleDebugMenu, EKeys::F2);
	S->MapKey(ToggleMap, EKeys::M);
	S->MapKey(ToggleMap, EKeys::Gamepad_Special_Left);
	S->MapKey(PhotoMode, EKeys::P);
	S->MapKey(PhotoMode, EKeys::Gamepad_DPad_Up);
	S->MapKey(Pause, EKeys::Escape);
	S->MapKey(Pause, EKeys::Gamepad_Special_Right);
}

void ARoamPlayerController::RegisterMappingContexts()
{
	if (bContextsRegistered || !IsLocalPlayerController())
	{
		return;
	}
	EnsureInputAssets();
	if (UEnhancedInputLocalPlayerSubsystem* Subsystem = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(GetLocalPlayer()))
	{
		Subsystem->AddMappingContext(SystemContext, 10);
		if (bGameplayInputEnabled)
		{
			Subsystem->AddMappingContext(GameplayContext, 0);
		}
		bContextsRegistered = true;
	}
}

void ARoamPlayerController::UnregisterMappingContexts()
{
	if (!bContextsRegistered)
	{
		return;
	}
	if (UEnhancedInputLocalPlayerSubsystem* Subsystem = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(GetLocalPlayer()))
	{
		Subsystem->RemoveMappingContext(SystemContext);
		Subsystem->RemoveMappingContext(GameplayContext);
	}
	bContextsRegistered = false;
}

void ARoamPlayerController::BeginPlay()
{
	Super::BeginPlay();
	RegisterMappingContexts();
}

void ARoamPlayerController::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	UnregisterMappingContexts();
	Super::EndPlay(EndPlayReason);
}

void ARoamPlayerController::BindDigital(UEnhancedInputComponent* Component, ERoamInputAction Action, void (ARoamPlayerController::*Handler)())
{
	if (UInputAction* InputAction = GetInputAction(Action))
	{
		Component->BindAction(InputAction, ETriggerEvent::Started, this, Handler);
	}
}

void ARoamPlayerController::SetupInputComponent()
{
	Super::SetupInputComponent();
	EnsureInputAssets();

	UEnhancedInputComponent* Component = Cast<UEnhancedInputComponent>(InputComponent);
	if (!Component)
	{
		UE_LOG(LogRoam, Error, TEXT("ARoamPlayerController: input component is not an UEnhancedInputComponent - check DefaultInput.ini DefaultInputComponentClass"));
		return;
	}
	BindDigital(Component, ERoamInputAction::ShiftUp, &ARoamPlayerController::HandleShiftUp);
	BindDigital(Component, ERoamInputAction::ShiftDown, &ARoamPlayerController::HandleShiftDown);
	BindDigital(Component, ERoamInputAction::CycleCamera, &ARoamPlayerController::HandleCycleCamera);
	BindDigital(Component, ERoamInputAction::ResetVehicle, &ARoamPlayerController::HandleResetVehicle);
	BindDigital(Component, ERoamInputAction::ToggleConsole, &ARoamPlayerController::HandleToggleConsole);
	BindDigital(Component, ERoamInputAction::ToggleGarage, &ARoamPlayerController::HandleToggleGarage);
	BindDigital(Component, ERoamInputAction::ToggleDebugMenu, &ARoamPlayerController::HandleToggleDebugMenu);
	BindDigital(Component, ERoamInputAction::ToggleMap, &ARoamPlayerController::HandleToggleMap);
	BindDigital(Component, ERoamInputAction::PhotoMode, &ARoamPlayerController::HandlePhotoMode);
	BindDigital(Component, ERoamInputAction::Pause, &ARoamPlayerController::HandlePause);
}

void ARoamPlayerController::HandleDigital(ERoamInputAction Action)
{
	OnActionTriggered.Broadcast(Action);
	switch (Action)
	{
	case ERoamInputAction::ShiftUp:         OnShiftUp(); break;
	case ERoamInputAction::ShiftDown:       OnShiftDown(); break;
	case ERoamInputAction::CycleCamera:     OnCycleCamera(); break;
	case ERoamInputAction::ResetVehicle:    OnResetVehicle(); break;
	case ERoamInputAction::ToggleConsole:   OnToggleConsole(); break;
	case ERoamInputAction::ToggleGarage:    OnToggleGarage(); break;
	case ERoamInputAction::ToggleDebugMenu: OnToggleDebugMenu(); break;
	case ERoamInputAction::ToggleMap:       OnToggleMap(); break;
	case ERoamInputAction::PhotoMode:       OnPhotoMode(); break;
	case ERoamInputAction::Pause:           OnPause(); break;
	default: break;
	}
}

void ARoamPlayerController::SetGameplayInputEnabled(bool bEnabled)
{
	if (bGameplayInputEnabled == bEnabled)
	{
		return;
	}
	bGameplayInputEnabled = bEnabled;
	if (bContextsRegistered)
	{
		if (UEnhancedInputLocalPlayerSubsystem* Subsystem = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(GetLocalPlayer()))
		{
			if (bEnabled)
			{
				Subsystem->AddMappingContext(GameplayContext, 0);
			}
			else
			{
				Subsystem->RemoveMappingContext(GameplayContext);
			}
		}
	}
	if (!bEnabled)
	{
		if (ARoamVehicle* Vehicle = GetRoamVehicle())
		{
			Vehicle->SetThrottle(0.0f);
			Vehicle->SetBrake(0.0f);
			Vehicle->SetSteer(0.0f);
			Vehicle->SetHandbrake(0.0f);
		}
	}
}

void ARoamPlayerController::PlayerTick(float DeltaTime)
{
	Super::PlayerTick(DeltaTime);

	ARoamVehicle* Vehicle = GetRoamVehicle();
	const UEnhancedPlayerInput* EnhancedInput = Cast<UEnhancedPlayerInput>(PlayerInput);
	if (!Vehicle || Vehicle->IsAIControlled() || !EnhancedInput || !bGameplayInputEnabled || DeltaTime <= 0.0f)
	{
		return;
	}

	const auto AxisValue = [this, EnhancedInput](ERoamInputAction Id) -> float
	{
		const UInputAction* Action = GetInputAction(Id);
		return Action ? EnhancedInput->GetActionValue(Action).Get<float>() : 0.0f;
	};
	const auto BoolValue = [this, EnhancedInput](ERoamInputAction Id) -> bool
	{
		const UInputAction* Action = GetInputAction(Id);
		return Action ? EnhancedInput->GetActionValue(Action).Get<bool>() : false;
	};

	Vehicle->SetThrottle(AxisValue(ERoamInputAction::Throttle));
	Vehicle->SetBrake(AxisValue(ERoamInputAction::Brake));
	Vehicle->SetSteer(AxisValue(ERoamInputAction::Steer));
	Vehicle->SetHandbrake(BoolValue(ERoamInputAction::Handbrake) ? 1.0f : 0.0f);

	// Look: mouse look only while the right mouse button is held (otherwise the mouse is free for menus); the stick always works.
	const bool bStickActive = FMath::Abs(GetInputAnalogKeyState(EKeys::Gamepad_RightX)) > 0.15f || FMath::Abs(GetInputAnalogKeyState(EKeys::Gamepad_RightY)) > 0.15f;
	if ((IsInputKeyDown(EKeys::RightMouseButton) || bStickActive) && Vehicle->CameraRig)
	{
		const URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this);
		const float Sensitivity = Save ? Save->GetSettings().LookSensitivity : 1.0f;
		const float InvertY = (Save && Save->GetSettings().bInvertLookY) ? -1.0f : 1.0f;
		Vehicle->CameraRig->AddLookInput(AxisValue(ERoamInputAction::LookX) * Sensitivity, AxisValue(ERoamInputAction::LookY) * Sensitivity * InvertY);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Default hooks
// ------------------------------------------------------------------------------------------------------------------

void ARoamPlayerController::OnShiftUp()
{
	if (ARoamVehicle* Vehicle = GetRoamVehicle())
	{
		Vehicle->ShiftUp();
	}
}

void ARoamPlayerController::OnShiftDown()
{
	if (ARoamVehicle* Vehicle = GetRoamVehicle())
	{
		Vehicle->ShiftDown();
	}
}

void ARoamPlayerController::OnCycleCamera()
{
	if (ARoamVehicle* Vehicle = GetRoamVehicle())
	{
		Vehicle->CycleCameraMode();
	}
}

void ARoamPlayerController::OnResetVehicle()
{
	if (ARoamVehicle* Vehicle = GetRoamVehicle())
	{
		Vehicle->ResetToRoad();
	}
}

void ARoamPlayerController::OnToggleConsole()
{
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this)) { UI->ToggleConsole(); }
}

void ARoamPlayerController::OnToggleGarage()
{
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this)) { UI->ToggleGarage(); }
}

void ARoamPlayerController::OnToggleDebugMenu()
{
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this)) { UI->ToggleDebugMenu(); }
}

void ARoamPlayerController::OnToggleMap()
{
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this)) { UI->ToggleMap(); }
}

void ARoamPlayerController::OnPhotoMode()
{
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this)) { UI->TogglePhotoMode(); }
}

void ARoamPlayerController::OnPause()
{
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this))
	{
		// Escape first closes an open panel; with nothing open it opens the pause menu.
		if (UI->IsAnyPanelOpen())
		{
			UI->CloseAllPanels();
		}
		else
		{
			UI->TogglePauseMenu();
		}
	}
}
