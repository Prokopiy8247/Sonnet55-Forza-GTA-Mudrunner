// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamVehicle.h"

#include "Activities/RoamActivitySubsystem.h"
#include "Components/StaticMeshComponent.h"
#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamCollision.h"
#include "Core/RoamGameInstance.h"
#include "Core/RoamGameMode.h"
#include "Core/RoamLog.h"
#include "Data/RoamCarCatalog.h"
#include "Data/RoamCarDefinition.h"
#include "Data/RoamRoadNetwork.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Kismet/GameplayStatics.h"
#include "Save/RoamSaveSubsystem.h"
#include "UObject/ConstructorHelpers.h"
#include "Vehicle/RoamCameraRig.h"
#include "Vehicle/RoamEngineSynth.h"
#include "Vehicle/RoamVehicleBody.h"
#include "Vehicle/RoamVehicleFX.h"
#include "Vehicle/RoamVehicleMovement.h"
#include "Vehicle/RoamVehicleVisuals.h"
#include "World/RoamTimeWeatherSubsystem.h"

ARoamVehicle::ARoamVehicle()
{
	// No actor tick: the movement component and the visuals component tick, nothing else needs to (Docs/ARCHITECTURE.md section 8).
	PrimaryActorTick.bCanEverTick = false;
	bReplicates = false;
	// The camera rig follows the car, the control rotation must not turn it.
	bUseControllerRotationPitch = false;
	bUseControllerRotationYaw = false;
	bUseControllerRotationRoll = false;

	static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeMesh(TEXT("/Engine/BasicShapes/Cube.Cube"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderMesh(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));

	// ---- body (root) -----------------------------------------------------------------------------------------------
	Body = CreateDefaultSubobject<URoamVehicleBody>(TEXT("Body"));
	SetRootComponent(Body);
	Body->SetMobility(EComponentMobility::Movable);
	Body->SetCollisionProfileName(RoamCollision::ProfileVehicle);
	Body->SetGenerateOverlapEvents(false);
	Body->SetCanEverAffectNavigation(false);
	Body->bReceivesDecals = false;

	// ---- placeholder look (hidden as soon as the Body gets a real mesh) --------------------------------------------
	PlaceholderBody = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderBody"));
	PlaceholderBody->SetupAttachment(Body);
	PlaceholderBody->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	PlaceholderBody->SetGenerateOverlapEvents(false);
	PlaceholderBody->SetCanEverAffectNavigation(false);
	PlaceholderBody->CastShadow = true;
	if (CubeMesh.Succeeded())
	{
		PlaceholderBody->SetStaticMesh(CubeMesh.Object);
	}

	// ---- visual parts ----------------------------------------------------------------------------------------------
	GlassMesh = CreateVisualMesh(TEXT("GlassMesh"), Body);
	InteriorMesh = CreateVisualMesh(TEXT("InteriorMesh"), Body);
	SteeringWheelMesh = CreateVisualMesh(TEXT("SteeringWheelMesh"), Body);
	static const TCHAR* WheelNames[4] = { TEXT("Wheel_FL"), TEXT("Wheel_FR"), TEXT("Wheel_RL"), TEXT("Wheel_RR") };
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		UStaticMeshComponent* Wheel = CreateVisualMesh(WheelNames[i], Body);
		if (CylinderMesh.Succeeded())
		{
			Wheel->SetStaticMesh(CylinderMesh.Object); // stand-in until the Blender wheel is applied
		}
		WheelMeshes.Add(Wheel);
	}

	// ---- behaviour components --------------------------------------------------------------------------------------
	VehicleMovement = CreateDefaultSubobject<URoamVehicleMovement>(TEXT("VehicleMovement"));
	Visuals = CreateDefaultSubobject<URoamVehicleVisuals>(TEXT("Visuals"));
	VehicleFX = CreateDefaultSubobject<URoamVehicleFX>(TEXT("VehicleFX"));

	CameraRig = CreateDefaultSubobject<URoamCameraRig>(TEXT("CameraRig"));
	CameraRig->SetupAttachment(Body);

	EngineSynth = CreateDefaultSubobject<URoamEngineSynth>(TEXT("EngineSynth"));
	EngineSynth->SetupAttachment(Body);
	EngineSynth->bAutoActivate = false;
}

UStaticMeshComponent* ARoamVehicle::CreateVisualMesh(const FName Name, UStaticMeshComponent* Parent)
{
	UStaticMeshComponent* Component = CreateDefaultSubobject<UStaticMeshComponent>(Name);
	Component->SetupAttachment(Parent);
	Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Component->SetGenerateOverlapEvents(false);
	Component->SetCanEverAffectNavigation(false);
	Component->bReceivesDecals = false;
	return Component;
}

void ARoamVehicle::PostInitializeComponents()
{
	Super::PostInitializeComponents();
}

void ARoamVehicle::BeginPlay()
{
	Super::BeginPlay();
	bBegunPlay = true;

	URoamCarDefinition* Definition = CarDefinition ? CarDefinition.Get() : InitialCarDefinition.Get();
	if (!Definition)
	{
		// Vehicles spawned without a definition (editor-placed, tests) use the first car of the catalog if there is one.
		if (const URoamGameInstance* GameInstance = URoamGameInstance::Get(this))
		{
			if (URoamCarCatalog* Catalog = const_cast<URoamGameInstance*>(GameInstance)->GetCarCatalog())
			{
				Definition = Catalog->GetCarByIndex(0);
			}
		}
	}
	ApplyCarDefinition(Definition);
	ApplyProfileSettings();

	if (EngineSynth)
	{
		EngineSynth->StartIfAudible();
	}
	UE_LOG(LogRoam, Display, TEXT("ROAM_VEHICLE_READY car=%s class=%s placeholder=%d"), *GetCarId().ToString(), *GetClass()->GetName(), CarDefinition ? 0 : 1);
}

void ARoamVehicle::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (EngineSynth)
	{
		EngineSynth->Stop();
	}
	Super::EndPlay(EndPlayReason);
}

void ARoamVehicle::PossessedBy(AController* NewController)
{
	Super::PossessedBy(NewController);
	if (EngineSynth)
	{
		EngineSynth->SetMuted(bAIControlled);
	}
}

void ARoamVehicle::UnPossessed()
{
	// Release the pedals when the player leaves the car so it does not keep driving on the last input.
	SetThrottle(0.0f);
	SetBrake(0.0f);
	SetSteer(0.0f);
	SetHandbrake(0.0f);
	Super::UnPossessed();
}

void ARoamVehicle::ApplyProfileSettings()
{
	URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this);
	if (!Save)
	{
		return;
	}
	const FRoamProfile& Profile = Save->GetProfile();
	SetAssists(Profile.Settings.Assists);
	// A car the player never painted starts in the car's own default paint (first suggested paint), not in the profile-wide default.
	if (CarDefinition && CarDefinition->SuggestedPaints.Num() > 0 && !Profile.PaintByCar.Contains(GetCarId()))
	{
		SetPaint(CarDefinition->SuggestedPaints[0]);
	}
	else
	{
		SetPaint(Save->GetPaintForCar(GetCarId()));
	}
	SetTuning(Profile.Tuning);
	SetUpgrades(Profile.Upgrades);
}

// ------------------------------------------------------------------------------------------------------------------
// Car selection
// ------------------------------------------------------------------------------------------------------------------

void ARoamVehicle::ApplyCarDefinition(URoamCarDefinition* Definition)
{
	CarDefinition = Definition;
	InitialCarDefinition = Definition;

	if (Visuals)
	{
		Visuals->ApplyCarDefinition(Definition);
	}
	if (CameraRig)
	{
		CameraRig->ApplyCarDefinition(Definition);
	}
	if (VehicleMovement)
	{
		VehicleMovement->InitFromDefinition(Definition);
		if (Definition)
		{
			// Car defaults for the assists (the profile overrides them in ApplyProfileSettings on the player's car).
			FRoamAssistSettings Defaults;
			Defaults.bTractionControl = Definition->AssistDefaults.bTractionControl;
			Defaults.bStabilityControl = Definition->AssistDefaults.bStabilityControl;
			Defaults.bABS = Definition->AssistDefaults.bABS;
			Defaults.SteeringAssist = Definition->AssistDefaults.SteeringAssist;
			Defaults.bAutomaticGearbox = Definition->Gearbox.ForwardRatios.Num() > 0;
			if (!bBegunPlay)
			{
				VehicleMovement->SetAssists(Defaults);
			}
		}
	}
	if (EngineSynth && Definition)
	{
		EngineSynth->ApplySoundSpec(Definition->Sound, Definition->Engine.IdleRPM, Definition->Engine.RedlineRPM);
	}
	if (bBegunPlay)
	{
		UE_LOG(LogRoam, Display, TEXT("ROAM_CAR_APPLIED %s"), Definition ? *Definition->ToDebugString() : TEXT("<placeholder>"));
	}
	OnCarApplied.Broadcast(this);
}

FName ARoamVehicle::GetCarId() const
{
	return CarDefinition ? CarDefinition->CarId : NAME_None;
}

void ARoamVehicle::SetPaint(const FRoamPaint& NewPaint)
{
	Paint = NewPaint;
	if (Visuals)
	{
		Visuals->SetPaint(NewPaint);
	}
}

void ARoamVehicle::SetTuning(const FRoamTuning& NewTuning)
{
	if (VehicleMovement)
	{
		VehicleMovement->SetTuning(NewTuning);
	}
}

const FRoamTuning& ARoamVehicle::GetTuning() const
{
	static const FRoamTuning DefaultTuning;
	return VehicleMovement ? VehicleMovement->GetTuning() : DefaultTuning;
}

void ARoamVehicle::SetUpgrades(const TMap<FName, int32>& NewUpgrades)
{
	if (VehicleMovement)
	{
		VehicleMovement->SetUpgrades(NewUpgrades);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Telemetry / inputs
// ------------------------------------------------------------------------------------------------------------------

const FRoamVehicleTelemetry& ARoamVehicle::GetTelemetry() const
{
	static const FRoamVehicleTelemetry Empty;
	return VehicleMovement ? VehicleMovement->GetTelemetry() : Empty;
}

float ARoamVehicle::GetSpeedKmh() const
{
	return GetTelemetry().SpeedKmh;
}

void ARoamVehicle::SetThrottle(float Value) { if (VehicleMovement) { VehicleMovement->SetThrottleInput(Value); } }
void ARoamVehicle::SetBrake(float Value) { if (VehicleMovement) { VehicleMovement->SetBrakeInput(Value); } }
void ARoamVehicle::SetSteer(float Value) { if (VehicleMovement) { VehicleMovement->SetSteerInput(Value); } }
void ARoamVehicle::SetHandbrake(float Value) { if (VehicleMovement) { VehicleMovement->SetHandbrakeInput(Value); } }
void ARoamVehicle::ShiftUp() { if (VehicleMovement) { VehicleMovement->ShiftUp(); } }
void ARoamVehicle::ShiftDown() { if (VehicleMovement) { VehicleMovement->ShiftDown(); } }

void ARoamVehicle::SetAIControlled(bool bInAIControlled)
{
	bAIControlled = bInAIControlled;
	if (VehicleMovement)
	{
		VehicleMovement->bFilterInputs = !bInAIControlled;
	}
	if (EngineSynth)
	{
		EngineSynth->SetMuted(bInAIControlled);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Assists
// ------------------------------------------------------------------------------------------------------------------

void ARoamVehicle::SetAssist(ERoamAssist Assist, bool bEnabled)
{
	if (VehicleMovement)
	{
		VehicleMovement->SetAssist(Assist, bEnabled);
	}
	if (URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this))
	{
		if (GetController() && GetController()->IsLocalPlayerController())
		{
			Save->GetSettings().Assists.Set(Assist, bEnabled);
			Save->MarkDirty();
		}
	}
}

bool ARoamVehicle::SetAssistByName(const FString& AssistName, bool bEnabled)
{
	ERoamAssist Assist;
	if (!Roam::ParseAssistName(AssistName, Assist))
	{
		return false;
	}
	SetAssist(Assist, bEnabled);
	return true;
}

void ARoamVehicle::SetAssists(const FRoamAssistSettings& NewAssists)
{
	if (VehicleMovement)
	{
		VehicleMovement->SetAssists(NewAssists);
	}
}

const FRoamAssistSettings& ARoamVehicle::GetAssists() const
{
	static const FRoamAssistSettings Defaults;
	return VehicleMovement ? VehicleMovement->GetAssists() : Defaults;
}

// ------------------------------------------------------------------------------------------------------------------
// Camera
// ------------------------------------------------------------------------------------------------------------------

void ARoamVehicle::SetCameraMode(ERoamCameraMode Mode)
{
	if (CameraRig)
	{
		CameraRig->SetCameraMode(Mode);
	}
}

ERoamCameraMode ARoamVehicle::GetCameraMode() const
{
	return CameraRig ? CameraRig->GetCameraMode() : ERoamCameraMode::Chase;
}

void ARoamVehicle::CycleCameraMode()
{
	if (CameraRig)
	{
		CameraRig->CycleCameraMode();
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Recovery
// ------------------------------------------------------------------------------------------------------------------

bool ARoamVehicle::ResetToRoad()
{
	URoamRoadNetwork* Network = nullptr;
	if (URoamGameInstance* GameInstance = URoamGameInstance::Get(this))
	{
		Network = GameInstance->GetRoadNetwork();
	}
	if (Network && Network->GetNumRoads() > 0)
	{
		FRoamRoadQuery Query;
		Query.Location = GetActorLocation();
		Query.Heading = GetActorForwardVector();
		Query.MaxDistanceCm = 500000.0f;
		FRoamRoadHit Hit;
		if (Network->FindNearest(Query, Hit))
		{
			const int32 Lane = Network->FindClosestLane(Hit);
			const FVector Position = Network->GetLanePosition(Hit, Lane) + FVector(0.0f, 0.0f, 40.0f);
			const FVector Direction = URoamRoadNetwork::GetLaneDirection(Hit, Lane);
			const FRotator Rotation = FRotationMatrix::MakeFromXZ(Direction, FVector::UpVector).Rotator();
			TeleportVehicle(FTransform(FRotator(0.0f, Rotation.Yaw, 0.0f), Position), false);
			UE_LOG(LogRoam, Display, TEXT("ROAM_RESET_TO_ROAD road=%s s=%.0f lane=%d"), *Hit.RoadId.ToString(), Hit.S, Lane);
			return true;
		}
	}
	FlipUpright();
	return false;
}

void ARoamVehicle::FlipUpright()
{
	FRotator Rotation = GetActorRotation();
	Rotation.Pitch = 0.0f;
	Rotation.Roll = 0.0f;
	FVector Location = GetActorLocation();
	Location.Z += 50.0f;
	TeleportVehicle(FTransform(Rotation, Location), false);
}

void ARoamVehicle::TeleportVehicle(const FTransform& NewTransform, bool bKeepSpeed)
{
	const float PreviousSpeedCmS = GetTelemetry().SpeedMs * 100.0f;
	FTransform Target = NewTransform;
	ARoamGameMode::SnapOffMedian(this, Target);   // never put the car on top of a highway median barrier (teleports to road-centre POIs)
	SetActorTransform(Target, false, nullptr, ETeleportType::TeleportPhysics);
	if (Body && Body->IsSimulatingPhysics())
	{
		Body->SetPhysicsLinearVelocity(FVector::ZeroVector);
		Body->SetPhysicsAngularVelocityInDegrees(FVector::ZeroVector);
	}
	if (VehicleMovement)
	{
		VehicleMovement->ResetState(false);
		VehicleMovement->NotifyTeleported();
		if (bKeepSpeed)
		{
			// Placeholder model keeps its own forward speed; the physics owner sets the body velocity here.
			VehicleMovement->RestoreForwardSpeed(PreviousSpeedCmS);
		}
	}
	if (CameraRig)
	{
		CameraRig->SnapToVehicle();
	}
	if (VehicleFX)
	{
		VehicleFX->NotifyTeleported();
	}
	if (URoamActivitySubsystem* Activities = URoamActivitySubsystem::Get(this))
	{
		Activities->NotifyVehicleTeleported(this);
	}
	OnRecovered.Broadcast(this);
}

void ARoamVehicle::Repair()
{
	// OWNER: vehicle-visuals (damage states). Nothing to repair in the skeleton.
}

void ARoamVehicle::SetHeadlightsOverride(bool bOverride, bool bOn)
{
	if (Visuals)
	{
		Visuals->SetHeadlightsOverride(bOverride, bOn);
	}
}

void ARoamVehicle::SoundHorn(bool bPressed)
{
	// OWNER: camera/audio agent - horn one-shot/loop on the engine synth or a dedicated audio component.
	(void)bPressed;
}

void ARoamVehicle::PublishTelemetry(float DeltaTime)
{
	const FRoamVehicleTelemetry& Telemetry = GetTelemetry();
	if (CameraRig)
	{
		CameraRig->UpdateFromTelemetry(Telemetry);
	}
	if (EngineSynth)
	{
		EngineSynth->SetEngineState(Telemetry.RPM, Telemetry.Throttle, Telemetry.Boost01);
	}
	if (VehicleFX)
	{
		VehicleFX->UpdateFromTelemetry(Telemetry, DeltaTime);
	}
}

ARoamVehicle* ARoamVehicle::GetPlayerVehicle(const UObject* WorldContext)
{
	return Cast<ARoamVehicle>(UGameplayStatics::GetPlayerPawn(WorldContext, 0));
}

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("drive", "drive <throttle 0..1> [steer -1..1] [brake 0..1] | drive off", "Hold scripted inputs on the player car (AI-controlled mode, for tests and screenshots).", "debug",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		if (Ctx.NumArgs() == 0 || Ctx.Arg(0).Equals(TEXT("off"), ESearchCase::IgnoreCase))
		{
			Vehicle->SetThrottle(0.0f);
			Vehicle->SetBrake(0.0f);
			Vehicle->SetSteer(0.0f);
			Vehicle->SetAIControlled(false);
			return TEXT("scripted inputs released");
		}
		float Throttle = 0.0f;
		float Steer = 0.0f;
		float Brake = 0.0f;
		if (!Ctx.GetFloat(0, Throttle))
		{
			return Ctx.Fail(TEXT("usage: drive <throttle 0..1> [steer -1..1] [brake 0..1] | drive off"));
		}
		Ctx.GetFloat(1, Steer);
		Ctx.GetFloat(2, Brake);
		Vehicle->SetAIControlled(true);
		Vehicle->SetThrottle(Throttle);
		Vehicle->SetSteer(Steer);
		Vehicle->SetBrake(Brake);
		return FString::Printf(TEXT("driving: throttle %.2f steer %.2f brake %.2f"), Throttle, Steer, Brake);
	});
