// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamVehicleVisuals.h"

#include "Components/StaticMeshComponent.h"
#include "Core/RoamLog.h"
#include "Data/RoamCarDefinition.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Materials/Material.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Vehicle/RoamVehicle.h"
#include "Vehicle/RoamVehicleMovement.h"
#include "World/RoamTimeWeatherSubsystem.h"

URoamVehicleVisuals::URoamVehicleVisuals()
{
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.bStartWithTickEnabled = true;
	PrimaryComponentTick.TickGroup = TG_PostPhysics;
}

ARoamVehicle* URoamVehicleVisuals::GetVehicle() const
{
	return Cast<ARoamVehicle>(GetOwner());
}

void URoamVehicleVisuals::BeginPlay()
{
	Super::BeginPlay();
	ApplyPaintToMaterials();
}

void URoamVehicleVisuals::ApplyCarDefinition(URoamCarDefinition* InDefinition)
{
	Definition = InDefinition;
	ARoamVehicle* Vehicle = GetVehicle();
	if (!Vehicle)
	{
		return;
	}

	const FRoamCarGeometry Geometry = Definition ? Definition->Geometry : FRoamCarGeometry();

	// ---- meshes ---------------------------------------------------------------------------------------------------
	UStaticMesh* BodyMesh = Definition ? Definition->BodyMesh.LoadSynchronous() : nullptr;
	if (Definition && !BodyMesh && !Definition->BodyMesh.IsNull())
	{
		UE_LOG(LogRoam, Warning, TEXT("Car %s: body mesh %s does not load, using the placeholder"), *Definition->CarId.ToString(), *Definition->BodyMesh.ToString());
	}
	Vehicle->Body->SetStaticMesh(BodyMesh);
	Vehicle->PlaceholderBody->SetVisibility(BodyMesh == nullptr);

	const auto Assign = [](UStaticMeshComponent* Component, const TSoftObjectPtr<UStaticMesh>& Soft)
	{
		UStaticMesh* Mesh = Soft.IsNull() ? nullptr : Soft.LoadSynchronous();
		Component->SetStaticMesh(Mesh);
		Component->SetVisibility(Mesh != nullptr);
	};
	if (Definition)
	{
		Assign(Vehicle->GlassMesh, Definition->GlassMesh);
		Assign(Vehicle->InteriorMesh, Definition->InteriorMesh);
		Assign(Vehicle->SteeringWheelMesh, Definition->SteeringWheelMesh);
	}
	else
	{
		Vehicle->GlassMesh->SetVisibility(false);
		Vehicle->InteriorMesh->SetVisibility(false);
		Vehicle->SteeringWheelMesh->SetVisibility(false);
	}
	Vehicle->SteeringWheelMesh->SetRelativeLocation(Geometry.SteeringWheelCenterCm);

	// ---- placeholder body: a box roughly the size of the car --------------------------------------------------------
	{
		const float BoxHeight = Geometry.HeightCm * 0.5f;
		const float BottomZ = Geometry.RideHeightCm + 22.0f;
		Vehicle->PlaceholderBody->SetRelativeScale3D(FVector(Geometry.LengthCm / 100.0f, FMath::Min(Geometry.WidthCm, FMath::Max(2.0f * FMath::Abs(Geometry.GetWheel(0).CenterCm.Y) - Geometry.GetWheel(0).WidthCm, 60.0f)) / 100.0f, BoxHeight / 100.0f));
			// ^ narrower than the inner faces of the wheels so the four placeholder wheels stay visible (spin/steer checks on screenshots).
		Vehicle->PlaceholderBody->SetRelativeLocation(FVector(0.0f, 0.0f, BottomZ + BoxHeight * 0.5f));
	}

	// ---- wheels -----------------------------------------------------------------------------------------------------
	const TSoftObjectPtr<UStaticMesh>* WheelSoft[4] = { nullptr, nullptr, nullptr, nullptr };
	if (Definition)
	{
		WheelSoft[0] = &Definition->WheelMeshFL;
		WheelSoft[1] = &Definition->WheelMeshFR;
		WheelSoft[2] = &Definition->WheelMeshRL;
		WheelSoft[3] = &Definition->WheelMeshRR;
	}
	for (int32 i = 0; i < Roam::NumWheels && i < Vehicle->WheelMeshes.Num(); ++i)
	{
		UStaticMeshComponent* Wheel = Vehicle->WheelMeshes[i];
		const FRoamWheelGeometry& WheelGeometry = Geometry.GetWheel(i);
		WheelRadiusCm[i] = FMath::Max(WheelGeometry.RadiusCm, 10.0f);
		Wheel->SetRelativeLocation(WheelGeometry.CenterCm);

		UStaticMesh* WheelMesh = (WheelSoft[i] && !WheelSoft[i]->IsNull()) ? WheelSoft[i]->LoadSynchronous() : nullptr;
		if (WheelMesh)
		{
			Wheel->SetStaticMesh(WheelMesh);
			Wheel->SetRelativeScale3D(FVector::OneVector);
		}
		else
		{
			// Engine cylinder: 100 cm diameter and height along its local Z; the base rotation (roll 90) lays the axle along Y.
			Wheel->SetRelativeScale3D(FVector(WheelRadiusCm[i] * 2.0f / 100.0f, WheelRadiusCm[i] * 2.0f / 100.0f, WheelGeometry.WidthCm / 100.0f));
		}
	}
	RebuildMaterialInstances();
	ApplyPaintToMaterials();
}

void URoamVehicleVisuals::SetPaint(const FRoamPaint& NewPaint)
{
	Paint = NewPaint;
	ApplyPaintToMaterials();
}

namespace
{
	/** Finish presets of Docs/Tech/CARS_IMPORT.md section 4. */
	struct FFinishPreset { float Metallic; float BaseRoughness; float ClearCoat; float ClearCoatRoughness; float FlakeIntensity; float MatteFlatness; };
	FFinishPreset GetFinishPreset(ERoamPaintFinish Finish)
	{
		switch (Finish)
		{
		case ERoamPaintFinish::Matte:    return { 0.0f, 0.80f, 0.0f, 0.035f, 0.0f, 1.0f };
		case ERoamPaintFinish::Metallic: return { 0.85f, 0.33f, 1.0f, 0.035f, 0.65f, 0.0f };
		default:                         return { 0.0f, 0.38f, 1.0f, 0.035f, 0.0f, 0.0f };
		}
	}

	void SetScalarAll(const TArray<TObjectPtr<UMaterialInstanceDynamic>>& Mids, const TCHAR* Name, float Value)
	{
		for (UMaterialInstanceDynamic* Mid : Mids)
		{
			if (Mid)
			{
				Mid->SetScalarParameterValue(Name, Value);
			}
		}
	}

	float ReadScalar(const TArray<TObjectPtr<UMaterialInstanceDynamic>>& Mids, const TCHAR* Name)
	{
		for (UMaterialInstanceDynamic* Mid : Mids)
		{
			float Value = 0.0f;
			if (Mid && Mid->GetScalarParameterValue(FName(Name), Value))
			{
				return Value;
			}
		}
		return -1.0f;
	}
}

void URoamVehicleVisuals::RebuildMaterialInstances()
{
	PaintMaterials.Reset();
	Paint2Materials.Reset();
	HeadMaterials.Reset();
	TailMaterials.Reset();
	ReverseMaterials.Reset();
	IndicatorMaterials.Reset();
	RimMaterials.Reset();
	DiscMaterials.Reset();
	GlassMaterials.Reset();
	HeadLevel = TailLevel = ReverseLevel = IndicatorLevel = -1.0f;   // force the first write
	BrakeHeat = -1.0f;
	WeatherTimer = 10.0f;
	MaterialReport.Reset();

	ARoamVehicle* Vehicle = GetVehicle();
	if (!Vehicle)
	{
		return;
	}
	TArray<UStaticMeshComponent*> Parts;
	Parts.Add(Vehicle->Body);
	Parts.Add(Vehicle->GlassMesh);
	Parts.Add(Vehicle->InteriorMesh);
	Parts.Add(Vehicle->SteeringWheelMesh);
	for (UStaticMeshComponent* Wheel : Vehicle->WheelMeshes)
	{
		Parts.Add(Wheel);
	}

	const UMaterialInterface* DefaultMaterial = UMaterial::GetDefaultMaterial(MD_Surface);
	int32 NumSlots = 0;
	int32 NumGrey = 0;
	FString GreyNames;
	for (UStaticMeshComponent* Part : Parts)
	{
		if (!Part || !Part->GetStaticMesh() || !Part->IsVisible())
		{
			continue;
		}
		const TArray<FName> SlotNames = Part->GetMaterialSlotNames();
		for (int32 Slot = 0; Slot < Part->GetNumMaterials(); ++Slot)
		{
			++NumSlots;
			UMaterialInterface* Material = Part->GetMaterial(Slot);
			const FName SlotName = SlotNames.IsValidIndex(Slot) ? SlotNames[Slot] : NAME_None;
			if (!Material || Material == DefaultMaterial || Material->GetMaterial() == DefaultMaterial)
			{
				++NumGrey;
				GreyNames += FString::Printf(TEXT(" %s:%s"), *Part->GetName(), *SlotName.ToString());
				continue;
			}
			TArray<TObjectPtr<UMaterialInstanceDynamic>>* Target = nullptr;
			if (SlotName == TEXT("M_Paint")) { Target = &PaintMaterials; }
			else if (SlotName == TEXT("M_Paint2")) { Target = &Paint2Materials; }
			else if (SlotName == TEXT("M_Headlight")) { Target = &HeadMaterials; }
			else if (SlotName == TEXT("M_Taillight")) { Target = &TailMaterials; }
			else if (SlotName == TEXT("M_Reverse")) { Target = &ReverseMaterials; }
			else if (SlotName == TEXT("M_Indicator")) { Target = &IndicatorMaterials; }
			else if (SlotName == TEXT("M_Rim")) { Target = &RimMaterials; }
			else if (SlotName == TEXT("M_BrakeDisc")) { Target = &DiscMaterials; }
			else if (SlotName == TEXT("M_Glass")) { Target = &GlassMaterials; }
			if (Target)
			{
				if (UMaterialInstanceDynamic* Mid = Part->CreateDynamicMaterialInstance(Slot, Material))
				{
					Target->Add(Mid);
				}
			}
		}
	}
	MaterialReport = FString::Printf(TEXT("slots=%d grey=%d [%s ] mids paint=%d paint2=%d head=%d tail=%d rev=%d ind=%d rim=%d disc=%d glass=%d"), NumSlots, NumGrey, *GreyNames,
		PaintMaterials.Num(), Paint2Materials.Num(), HeadMaterials.Num(), TailMaterials.Num(), ReverseMaterials.Num(), IndicatorMaterials.Num(), RimMaterials.Num(), DiscMaterials.Num(), GlassMaterials.Num());
	if (NumGrey > 0)
	{
		UE_LOG(LogRoam, Warning, TEXT("ROAM_VISUALS car=%s %s"), Definition ? *Definition->CarId.ToString() : TEXT("<none>"), *MaterialReport);
	}
}

FString URoamVehicleVisuals::DescribeMaterials() const
{
	return MaterialReport;
}

float URoamVehicleVisuals::ReadLampIntensity(const TCHAR* Role) const
{
	const FString R(Role);
	if (R == TEXT("head")) { return ReadScalar(HeadMaterials, TEXT("Intensity")); }
	if (R == TEXT("tail")) { return ReadScalar(TailMaterials, TEXT("Intensity")); }
	if (R == TEXT("reverse")) { return ReadScalar(ReverseMaterials, TEXT("Intensity")); }
	if (R == TEXT("indicator")) { return ReadScalar(IndicatorMaterials, TEXT("Intensity")); }
	if (R == TEXT("disc")) { return ReadScalar(DiscMaterials, TEXT("HeatGlow")); }
	return -1.0f;
}

FLinearColor URoamVehicleVisuals::ReadPrimaryColor(bool bSecondary) const
{
	const TArray<TObjectPtr<UMaterialInstanceDynamic>>& Mids = bSecondary ? Paint2Materials : PaintMaterials;
	for (UMaterialInstanceDynamic* Mid : Mids)
	{
		FLinearColor Color;
		if (Mid && Mid->GetVectorParameterValue(FName(TEXT("PrimaryColor")), Color))
		{
			return Color;
		}
	}
	return FLinearColor(-1.0f, -1.0f, -1.0f, -1.0f);
}

void URoamVehicleVisuals::ApplyPaintToMaterials()
{
	ARoamVehicle* Vehicle = GetVehicle();
	if (!Vehicle || !Vehicle->PlaceholderBody)
	{
		return;
	}
	// Placeholder tint through the engine's BasicShapeMaterial "Color" parameter.
	if (!PlaceholderMaterial)
	{
		if (UMaterialInterface* Base = Vehicle->PlaceholderBody->GetMaterial(0))
		{
			PlaceholderMaterial = UMaterialInstanceDynamic::Create(Base, this);
			Vehicle->PlaceholderBody->SetMaterial(0, PlaceholderMaterial);
		}
	}
	if (PlaceholderMaterial)
	{
		PlaceholderMaterial->SetVectorParameterValue(TEXT("Color"), Paint.Primary);
	}

	// Real cars: the paint contract of Docs/Tech/CARS_IMPORT.md (M_Paint PrimaryColor = FRoamPaint.Primary, StripeColor = Secondary;
	// M_Paint2 PrimaryColor = Secondary; finish presets on both; rims take WheelColor).
	const FFinishPreset Finish = GetFinishPreset(Paint.Finish);
	const auto ApplyFinish = [&Finish](const TArray<TObjectPtr<UMaterialInstanceDynamic>>& Mids)
	{
		SetScalarAll(Mids, TEXT("Metallic"), Finish.Metallic);
		SetScalarAll(Mids, TEXT("BaseRoughness"), Finish.BaseRoughness);
		SetScalarAll(Mids, TEXT("ClearCoat"), Finish.ClearCoat);
		SetScalarAll(Mids, TEXT("ClearCoatRoughness"), Finish.ClearCoatRoughness);
		SetScalarAll(Mids, TEXT("FlakeIntensity"), Finish.FlakeIntensity);
		SetScalarAll(Mids, TEXT("MatteFlatness"), Finish.MatteFlatness);
	};
	for (UMaterialInstanceDynamic* Mid : PaintMaterials)
	{
		if (Mid)
		{
			Mid->SetVectorParameterValue(TEXT("PrimaryColor"), Paint.Primary);
			Mid->SetVectorParameterValue(TEXT("StripeColor"), Paint.Secondary);
			Mid->SetScalarParameterValue(TEXT("StripeStyle"), static_cast<float>(FMath::Clamp(Paint.StripeStyle, 0, 4)));
		}
	}
	for (UMaterialInstanceDynamic* Mid : Paint2Materials)
	{
		if (Mid)
		{
			Mid->SetVectorParameterValue(TEXT("PrimaryColor"), Paint.Secondary);
		}
	}
	ApplyFinish(PaintMaterials);
	ApplyFinish(Paint2Materials);
	for (UMaterialInstanceDynamic* Mid : RimMaterials)
	{
		if (Mid)
		{
			Mid->SetVectorParameterValue(TEXT("BaseColor"), Paint.WheelColor);
		}
	}
}

void URoamVehicleVisuals::SetHeadlightsOverride(bool bOverride, bool bOn)
{
	bHeadlightsOverride = bOverride;
	bHeadlightsOverrideValue = bOn;
}

void URoamVehicleVisuals::UpdateLightStates(const FRoamVehicleTelemetry& Telemetry)
{
	const bool bReversingNow = Telemetry.bReversing || Telemetry.Gear < 0;
	bBrakeLightsOn = Telemetry.bBrakeLightsOn || Telemetry.Handbrake > 0.5f || (Telemetry.Brake > 0.05f && !bReversingNow);
	bReverseLightsOn = bReversingNow;
	if (bHeadlightsOverride)
	{
		bHeadlightsOn = bHeadlightsOverrideValue;
	}
	else if (const UWorld* World = GetWorld())
	{
		const URoamTimeWeatherSubsystem* TimeWeather = World->GetSubsystem<URoamTimeWeatherSubsystem>();
		bHeadlightsOn = TimeWeather ? TimeWeather->ShouldVehicleLightsBeOn() : false;
	}
}

void URoamVehicleVisuals::UpdateLampMaterials(float DeltaTime)
{
	const float HeadTarget = bHeadlightsOn ? 1.0f : 0.0f;
	const float TailTarget = bBrakeLightsOn ? 1.0f : (bHeadlightsOn ? 0.30f : 0.10f);
	const float ReverseTarget = bReverseLightsOn ? 1.0f : 0.0f;
	IndicatorPhase += DeltaTime;
	const float IndicatorTarget = (bHazardLights && FMath::Fmod(IndicatorPhase, 0.8f) < 0.4f) ? 1.0f : 0.0f;

	const auto Step = [DeltaTime](float& Level, float Target, const TArray<TObjectPtr<UMaterialInstanceDynamic>>& Mids)
	{
		const float Old = Level;
		Level = Old < 0.0f ? Target : FMath::FInterpConstantTo(Old, Target, DeltaTime, 14.0f);
		if (Old < 0.0f || FMath::Abs(Level - Old) > 0.002f)
		{
			SetScalarAll(Mids, TEXT("Intensity"), Level);
		}
	};
	Step(HeadLevel, HeadTarget, HeadMaterials);
	Step(TailLevel, TailTarget, TailMaterials);
	Step(ReverseLevel, ReverseTarget, ReverseMaterials);
	Step(IndicatorLevel, IndicatorTarget, IndicatorMaterials);
}

void URoamVehicleVisuals::UpdateWeatherMaterials()
{
	const UWorld* World = GetWorld();
	const URoamTimeWeatherSubsystem* TimeWeather = World ? World->GetSubsystem<URoamTimeWeatherSubsystem>() : nullptr;
	if (!TimeWeather)
	{
		return;
	}
	const float Wetness = TimeWeather->GetWetness();
	const float Rain = TimeWeather->GetRainIntensity();
	const TArray<TObjectPtr<UMaterialInstanceDynamic>>* Groups[] = { &PaintMaterials, &Paint2Materials, &GlassMaterials };
	for (const TArray<TObjectPtr<UMaterialInstanceDynamic>>* Group : Groups)
	{
		SetScalarAll(*Group, TEXT("Wetness"), Wetness);
		SetScalarAll(*Group, TEXT("RainIntensity"), Rain);
	}
}

void URoamVehicleVisuals::UpdateWheelsAndSteeringWheel(const FRoamVehicleTelemetry& Telemetry, float DeltaTime)
{
	ARoamVehicle* Vehicle = GetVehicle();
	if (!Vehicle)
	{
		return;
	}
	const float SignedSpeedCmS = Telemetry.SpeedMs * 100.0f * ((Telemetry.bReversing || Telemetry.Gear < 0) ? -1.0f : 1.0f);
	const bool bPlaceholderWheels = !(Definition && !Definition->WheelMeshFL.IsNull());
	const FQuat BaseRotation = bPlaceholderWheels ? FQuat(FVector::ForwardVector, UE_HALF_PI) : FQuat::Identity; // cylinder axle: Z -> Y
	// With the physics model the real wheel speed and per-wheel steer angles are available (burnouts, wheelspin, Ackermann).
	const URoamVehicleMovement* Movement = Vehicle->VehicleMovement;
	const bool bPhysicsWheels = Movement && Movement->GetSimMode() == ERoamVehicleSimMode::Physics && Movement->IsPhysicsReady();

	for (int32 i = 0; i < Roam::NumWheels && i < Vehicle->WheelMeshes.Num(); ++i)
	{
		const float SpinRateRadS = bPhysicsWheels ? Telemetry.WheelAngVelRadS[i] : SignedSpeedCmS / WheelRadiusCm[i];
		WheelSpinDeg[i] = FMath::Fmod(WheelSpinDeg[i] + FMath::RadiansToDegrees(SpinRateRadS * DeltaTime), 360.0f);
		const float SteerYaw = bPhysicsWheels ? Telemetry.WheelSteerDeg[i] : ((i < 2) ? Telemetry.FrontWheelAngleDeg : 0.0f);
		const FQuat Rotation = FQuat(FRotator(0.0f, SteerYaw, 0.0f)) * FQuat(FVector::RightVector, FMath::DegreesToRadians(WheelSpinDeg[i])) * BaseRotation;
		Vehicle->WheelMeshes[i]->SetRelativeRotation(Rotation);
	}

	if (Vehicle->SteeringWheelMesh && Vehicle->SteeringWheelMesh->GetStaticMesh())
	{
		const FRoamCarGeometry Geometry = Definition ? Definition->Geometry : FRoamCarGeometry();
		const float Ratio = Definition ? Definition->Steering.SteeringRatio : 14.0f;
		const FVector Axis = Geometry.SteeringWheelAxis.GetSafeNormal();
		Vehicle->SteeringWheelMesh->SetRelativeRotation(FQuat(Axis, FMath::DegreesToRadians(Telemetry.FrontWheelAngleDeg * Ratio)));
	}
}

void URoamVehicleVisuals::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	const ARoamVehicle* Vehicle = GetVehicle();
	if (!Vehicle || DeltaTime <= 0.0f)
	{
		return;
	}
	const FRoamVehicleTelemetry& Telemetry = Vehicle->GetTelemetry();
	UpdateLightStates(Telemetry);
	UpdateLampMaterials(DeltaTime);
	UpdateWheelsAndSteeringWheel(Telemetry, DeltaTime);

	// brake disc glow: heavy braking from speed heats the discs, they cool slowly
	if (DiscMaterials.Num() > 0)
	{
		const float Heating = (Telemetry.Brake > 0.6f && Telemetry.SpeedKmh > 80.0f) ? 0.25f : -0.08f;
		const float OldHeat = BrakeHeat < 0.0f ? 0.0f : BrakeHeat;
		BrakeHeat = FMath::Clamp(OldHeat + Heating * DeltaTime, 0.0f, 1.0f);
		if (FMath::Abs(BrakeHeat - OldHeat) > 0.01f || (BrakeHeat == 0.0f) != (OldHeat == 0.0f))
		{
			SetScalarAll(DiscMaterials, TEXT("HeatGlow"), BrakeHeat);
		}
	}

	WeatherTimer += DeltaTime;
	if (WeatherTimer >= 0.5f)
	{
		WeatherTimer = 0.0f;
		UpdateWeatherMaterials();
	}
}
