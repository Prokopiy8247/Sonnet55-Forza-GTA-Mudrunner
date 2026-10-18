// Copyright Epic Games, Inc. All Rights Reserved.

#include "Core/RoamHUD.h"

#include "Core/RoamLog.h"
#include "Core/RoamSettings.h"
#include "Core/RoamTypes.h"
#include "Data/RoamCarDefinition.h"
#include "Camera/PlayerCameraManager.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/Font.h"
#include "Engine/World.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUISubsystem.h"
#include "Vehicle/RoamVehicle.h"
#include "World/RoamTimeWeatherSubsystem.h"

ARoamHUD::ARoamHUD()
{
	PrimaryActorTick.bCanEverTick = false;
}

void ARoamHUD::BeginPlay()
{
	Super::BeginPlay();
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this))
	{
		UI->OnHUDReady(this);
	}
}

void ARoamHUD::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this))
	{
		UI->OnHUDEndPlay(this);
	}
	Super::EndPlay(EndPlayReason);
}

void ARoamHUD::DrawLine(const FString& Text, float& InOutY, const FLinearColor& Color, float Scale)
{
	if (!Canvas)
	{
		return;
	}
	UFont* Font = GEngine ? GEngine->GetMediumFont() : nullptr;
	if (!Font)
	{
		return;
	}
	const float X = 0.04f * Canvas->SizeX;
	// Shadow for readability, then the text.
	DrawText(Text, FLinearColor(0.0f, 0.0f, 0.0f, 0.8f), X + 2.0f, InOutY + 2.0f, Font, Scale);
	DrawText(Text, Color, X, InOutY, Font, Scale);
	InOutY += 22.0f * Scale;
}

void ARoamHUD::DrawHUD()
{
	Super::DrawHUD();
	if (!Canvas || !GetDefault<URoamSettings>()->bShowHudShellDebugText)
	{
		return;
	}

	const FLinearColor Chalk(0.945f, 0.957f, 0.965f, 1.0f);
	const FLinearColor Cyan(0.133f, 0.827f, 0.933f, 1.0f);
	const FLinearColor Amber(1.0f, 0.698f, 0.141f, 1.0f);

	float Y = 0.05f * Canvas->SizeY;
	DrawLine(TEXT("ROAMLINE: OPEN ROADS   [skeleton HUD shell]"), Y, Cyan, 1.2f);

	const ARoamVehicle* Vehicle = Cast<ARoamVehicle>(GetOwningPawn());
	if (Vehicle)
	{
		const FRoamVehicleTelemetry& T = Vehicle->GetTelemetry();
		const URoamCarDefinition* Definition = Vehicle->GetCarDefinition();
		const URoamSaveSubsystem* Save = URoamSaveSubsystem::Get(this);
		const bool bMph = Save && Save->GetSettings().bUseMph;
		DrawLine(FString::Printf(TEXT("CAR  %s"), Definition ? *Definition->ToDebugString() : TEXT("placeholder (no car data configured)")), Y, Chalk);
		DrawLine(FString::Printf(TEXT("%3.0f %s    GEAR %s    %4.0f RPM    %s    %s"),
			bMph ? Roam::KmhToMph(T.SpeedKmh) : T.SpeedKmh, bMph ? TEXT("mph") : TEXT("km/h"),
			T.Gear < 0 ? TEXT("R") : (T.Gear == 0 ? TEXT("N") : *FString::FromInt(T.Gear)), T.RPM, *Roam::EnumToString(T.Surface),
			*Roam::EnumToString(Vehicle->GetCameraMode())), Y, Amber, 1.4f);
		DrawLine(FString::Printf(TEXT("throttle %.2f  brake %.2f  steer %+.2f  odo %.2f km  %s"), T.Throttle, T.Brake, T.Steer, T.DistanceKm, T.bAirborne ? TEXT("AIRBORNE") : TEXT("")), Y, Chalk, 0.9f);
	}
	else
	{
		DrawLine(TEXT("no vehicle possessed"), Y, FLinearColor::Red);
	}

	if (const APlayerCameraManager* CameraManager = PlayerOwner ? PlayerOwner->PlayerCameraManager.Get() : nullptr)
	{
		const FVector CameraLocation = CameraManager->GetCameraLocation();
		const FRotator CameraRotation = CameraManager->GetCameraRotation();
		const AActor* ViewTarget = CameraManager->GetViewTarget();
		DrawLine(FString::Printf(TEXT("camera (%.0f, %.0f, %.0f) pitch %.1f yaw %.1f fov %.1f  target %s"), CameraLocation.X, CameraLocation.Y, CameraLocation.Z,
			CameraRotation.Pitch, CameraRotation.Yaw, CameraManager->GetFOVAngle(), ViewTarget ? *ViewTarget->GetName() : TEXT("<none>")), Y, Chalk, 0.8f);
	}

	if (const URoamTimeWeatherSubsystem* TimeWeather = GetWorld() ? GetWorld()->GetSubsystem<URoamTimeWeatherSubsystem>() : nullptr)
	{
		DrawLine(FString::Printf(TEXT("%s   %s   wet %.2f   grip(asphalt) %.2f"), *TimeWeather->GetTimeString(), *Roam::EnumToString(TimeWeather->GetWeather()),
			TimeWeather->GetWetness(), TimeWeather->GetGripMultiplier(ERoamSurface::Asphalt)), Y, Chalk, 0.9f);
	}

	if (URoamUISubsystem* UI = URoamUISubsystem::Get(this))
	{
		for (const FRoamNotification& Notification : UI->GetActiveNotifications())
		{
			DrawLine(FString::Printf(TEXT("[!] %s  %s"), *Notification.Title.ToString(), *Notification.Body.ToString()), Y, Notification.Color, 1.0f);
		}
	}
}
