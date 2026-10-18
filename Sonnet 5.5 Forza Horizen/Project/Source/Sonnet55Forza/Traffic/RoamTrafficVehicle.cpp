// Copyright Epic Games, Inc. All Rights Reserved.

#include "Traffic/RoamTrafficVehicle.h"

#include "Components/StaticMeshComponent.h"
#include "Core/RoamCollision.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Materials/MaterialInterface.h"
#include "UObject/ConstructorHelpers.h"

namespace
{
	constexpr float WheelThicknessCm = 25.0f;
	const FName ColorParam(TEXT("Color"));
}

ARoamTrafficVehicle::ARoamTrafficVehicle()
{
	// Driven by the traffic subsystem's batch update, never by its own tick.
	PrimaryActorTick.bCanEverTick = false;
	bReplicates = false;

	static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeFinder(TEXT("/Engine/BasicShapes/Cube.Cube"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderFinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	PlaceholderCube = CubeFinder.Object;
	PlaceholderCylinder = CylinderFinder.Object;

	Body = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Body"));
	SetRootComponent(Body);
	Body->SetMobility(EComponentMobility::Movable);
	Body->SetCollisionProfileName(RoamCollision::ProfileTraffic);
	Body->SetGenerateOverlapEvents(false);
	Body->SetCanEverAffectNavigation(false);
	Body->SetNotifyRigidBodyCollision(true);
	Body->SetCastShadow(true);

	Glass = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("Glass"));
	Glass->SetupAttachment(Body);
	Glass->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Glass->SetGenerateOverlapEvents(false);
	Glass->SetCanEverAffectNavigation(false);

	static const TCHAR* WheelNames[4] = { TEXT("Wheel_FL"), TEXT("Wheel_FR"), TEXT("Wheel_RL"), TEXT("Wheel_RR") };
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		UStaticMeshComponent* Wheel = CreateDefaultSubobject<UStaticMeshComponent>(WheelNames[i]);
		Wheel->SetupAttachment(Body);
		Wheel->SetUsingAbsoluteScale(true);
		Wheel->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Wheel->SetGenerateOverlapEvents(false);
		Wheel->SetCanEverAffectNavigation(false);
		WheelMeshes.Add(Wheel);
	}

	static const TCHAR* LampNames[2] = { TEXT("TailLamp_L"), TEXT("TailLamp_R") };
	for (int32 i = 0; i < 2; ++i)
	{
		UStaticMeshComponent* Lamp = CreateDefaultSubobject<UStaticMeshComponent>(LampNames[i]);
		Lamp->SetupAttachment(Body);
		Lamp->SetUsingAbsoluteScale(true);
		Lamp->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Lamp->SetGenerateOverlapEvents(false);
		Lamp->SetCanEverAffectNavigation(false);
		Lamp->SetCastShadow(false);
		TailLamps.Add(Lamp);
	}

	SetActorHiddenInGame(true);
}

void ARoamTrafficVehicle::PostInitializeComponents()
{
	Super::PostInitializeComponents();
	if (Body)
	{
		Body->OnComponentHit.AddDynamic(this, &ARoamTrafficVehicle::HandleBodyHit);
	}
}

void ARoamTrafficVehicle::HandleBodyHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit)
{
	if (bActiveInTraffic && !bPhysicsReaction && OtherActor && OtherActor != this)
	{
		OnBodyHit.Broadcast(this, OtherActor, NormalImpulse);
	}
}

UStaticMesh* ARoamTrafficVehicle::LoadSoftMesh(const TSoftObjectPtr<UStaticMesh>& Soft)
{
	if (Soft.IsNull())
	{
		return nullptr;
	}
	if (UStaticMesh* Loaded = Soft.Get())
	{
		return Loaded;
	}
	// The registry checks existence up front (RegisterVehicleType callers clear missing paths), so this only loads real assets.
	return Soft.LoadSynchronous();
}

UStaticMeshComponent* ARoamTrafficVehicle::GetWheelComponent(int32 Index)
{
	if (Index < WheelMeshes.Num())
	{
		return WheelMeshes[Index];
	}
	const int32 Extra = Index - WheelMeshes.Num();
	while (ExtraWheelMeshes.Num() <= Extra)
	{
		UStaticMeshComponent* Wheel = NewObject<UStaticMeshComponent>(this, NAME_None, RF_Transient);
		Wheel->SetMobility(EComponentMobility::Movable);
		Wheel->SetUsingAbsoluteScale(true);
		Wheel->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		Wheel->SetGenerateOverlapEvents(false);
		Wheel->SetCanEverAffectNavigation(false);
		Wheel->SetupAttachment(Body);
		Wheel->RegisterComponent();
		Wheel->AttachToComponent(Body, FAttachmentTransformRules::KeepRelativeTransform);
		ExtraWheelMeshes.Add(Wheel);
	}
	return ExtraWheelMeshes[Extra];
}

void ARoamTrafficVehicle::BuildRealMeshMaterials(const FRoamPaint* Paint)
{
	UStaticMesh* Mesh = Body->GetStaticMesh();
	if (RealMidsMesh.Get() != Mesh)
	{
		RealMidsMesh = Mesh;
		PaintMIDs.Reset();
		Paint2MIDs.Reset();
		HeadMIDs.Reset();
		TailMIDs.Reset();
		IndicatorMIDs.Reset();
		LampHeadLevel = LampTailLevel = LampIndicatorLevel = -1.0f;
		const TArray<FName> SlotNames = Body->GetMaterialSlotNames();
		for (int32 Slot = 0; Slot < Body->GetNumMaterials(); ++Slot)
		{
			const FName SlotName = SlotNames.IsValidIndex(Slot) ? SlotNames[Slot] : NAME_None;
			TArray<TObjectPtr<UMaterialInstanceDynamic>>* Target = nullptr;
			if (SlotName == TEXT("M_Paint")) { Target = &PaintMIDs; }
			else if (SlotName == TEXT("M_Paint2")) { Target = &Paint2MIDs; }
			else if (SlotName == TEXT("M_Headlight")) { Target = &HeadMIDs; }
			else if (SlotName == TEXT("M_Taillight")) { Target = &TailMIDs; }
			else if (SlotName == TEXT("M_Indicator")) { Target = &IndicatorMIDs; }
			if (Target)
			{
				if (UMaterialInstanceDynamic* Mid = Body->CreateDynamicMaterialInstance(Slot, Body->GetMaterial(Slot)))
				{
					Target->Add(Mid);
				}
			}
		}
	}
	if (Paint)
	{
		for (UMaterialInstanceDynamic* Mid : PaintMIDs)
		{
			if (Mid)
			{
				Mid->SetVectorParameterValue(TEXT("PrimaryColor"), Paint->Primary);
				Mid->SetVectorParameterValue(TEXT("StripeColor"), Paint->Secondary);
			}
		}
		for (UMaterialInstanceDynamic* Mid : Paint2MIDs)
		{
			if (Mid)
			{
				Mid->SetVectorParameterValue(TEXT("PrimaryColor"), Paint->Secondary);
			}
		}
	}
}

void ARoamTrafficVehicle::SetLampIntensities(float Head, float Tail, float Indicator)
{
	const auto Apply = [](float& Last, float Value, const TArray<TObjectPtr<UMaterialInstanceDynamic>>& Mids)
	{
		if (Last < 0.0f || !FMath::IsNearlyEqual(Last, Value, 0.001f))
		{
			Last = Value;
			for (UMaterialInstanceDynamic* Mid : Mids)
			{
				if (Mid)
				{
					Mid->SetScalarParameterValue(TEXT("Intensity"), Value);
				}
			}
		}
	};
	Apply(LampHeadLevel, Head, HeadMIDs);
	Apply(LampTailLevel, Tail, TailMIDs);
	Apply(LampIndicatorLevel, Indicator, IndicatorMIDs);
}

void ARoamTrafficVehicle::ApplySpec()
{
	UStaticMesh* RealBody = LoadSoftMesh(Spec.BodyMesh);
	bPlaceholderBody = (RealBody == nullptr);
	UStaticMesh* BodyShape = bPlaceholderBody ? PlaceholderCube.Get() : RealBody;
	if (Body->GetStaticMesh() != BodyShape)
	{
		Body->SetStaticMesh(BodyShape);
		BodyMID = nullptr;
	}
	if (bPlaceholderBody)
	{
		BodyScale = FVector(Spec.LengthCm, Spec.WidthCm, Spec.HeightCm) * 0.01;
		GroundOffsetCm = Spec.HeightCm * 0.5f + Spec.WheelRadiusCm * 0.6f;
		if (!BodyMID)
		{
			BodyMID = Body->CreateAndSetMaterialInstanceDynamic(0);
		}
		if (BodyMID)
		{
			// a stable colour per vehicle id, desaturated so the traffic reads as civilian cars
			const uint32 Hash = GetTypeHash(AgentId) * 2654435761u;
			const FLinearColor Colour = FLinearColor::MakeFromHSV8(static_cast<uint8>(Hash & 0xFF), static_cast<uint8>(60 + ((Hash >> 8) & 0x3F)), static_cast<uint8>(150 + ((Hash >> 16) & 0x5F)));
			BodyMID->SetVectorParameterValue(ColorParam, Colour);
		}
	}
	else
	{
		BodyScale = FVector::OneVector;
		GroundOffsetCm = 0.0f;
	}
	Body->SetMassOverrideInKg(NAME_None, Spec.MassKg, true);
	Body->SetLinearDamping(0.1f);
	Body->SetAngularDamping(0.3f);

	// glass
	UStaticMesh* GlassShape = bPlaceholderBody ? nullptr : LoadSoftMesh(Spec.GlassMesh);
	if (Glass->GetStaticMesh() != GlassShape)
	{
		Glass->SetStaticMesh(GlassShape);
	}
	Glass->SetVisibility(GlassShape != nullptr);

	// wheels: ground-space centres, then converted to the body's (possibly scaled) space. Specs with their own wheel list (lorry 10, coach 6)
	// place every wheel at its real axle; the others compute the classic four from wheelbase and track.
	const bool bCustomWheels = Spec.Wheels.Num() > 0;
	const int32 NumSlots = bCustomWheels ? Spec.Wheels.Num() : Roam::NumWheels;
	bWheelPlaceholder.SetNum(NumSlots);
	bWheelSteers.SetNum(NumSlots);
	WheelCentreGround.SetNum(NumSlots);
	const float HalfWb = Spec.WheelbaseCm * 0.5f;
	const float HalfTrack = Spec.TrackCm * 0.5f;
	const FVector Classic[4] = {
		FVector(HalfWb, -HalfTrack, Spec.WheelRadiusCm), FVector(HalfWb, HalfTrack, Spec.WheelRadiusCm),
		FVector(-HalfWb, -HalfTrack, Spec.WheelRadiusCm), FVector(-HalfWb, HalfTrack, Spec.WheelRadiusCm) };
	for (int32 i = 0; i < NumSlots; ++i)
	{
		UStaticMeshComponent* Wheel = GetWheelComponent(i);
		const FVector Centre = bCustomWheels ? Spec.Wheels[i].CentreCm : Classic[i];
		const float WheelRadius = bCustomWheels ? Spec.Wheels[i].RadiusCm : Spec.WheelRadiusCm;
		WheelCentreGround[i] = Centre;
		bWheelSteers[i] = bCustomWheels ? Spec.Wheels[i].bSteering : (i < 2);
		UStaticMesh* RealWheel = nullptr;
		if (bCustomWheels)
		{
			RealWheel = LoadSoftMesh(Spec.Wheels[i].Mesh);
		}
		else
		{
			RealWheel = Spec.PerWheelMeshes.IsValidIndex(i) ? LoadSoftMesh(Spec.PerWheelMeshes[i]) : nullptr;
		}
		if (!RealWheel)
		{
			RealWheel = LoadSoftMesh(Spec.WheelMesh);
		}
		bWheelPlaceholder[i] = (RealWheel == nullptr);
		UStaticMesh* WheelShape = RealWheel ? RealWheel : PlaceholderCylinder.Get();
		if (Wheel->GetStaticMesh() != WheelShape)
		{
			Wheel->SetStaticMesh(WheelShape);
		}
		Wheel->SetWorldScale3D(FVector::OneVector); // absolute scale: set the final scale directly
		Wheel->SetRelativeScale3D(bWheelPlaceholder[i] ? FVector(WheelRadius * 0.02, WheelRadius * 0.02, WheelThicknessCm * 0.01) : FVector::OneVector);
		const FVector Local = (Centre - FVector(0.0, 0.0, GroundOffsetCm)) / BodyScale;
		Wheel->SetRelativeLocation(Local);
		Wheel->SetVisibility(true);
	}
	for (int32 i = NumSlots; i < WheelMeshes.Num() + ExtraWheelMeshes.Num(); ++i)
	{
		GetWheelComponent(i)->SetVisibility(false); // a pooled actor that carried a lorry before
	}

	// real-mesh materials: paint variant + emissive lamps
	if (!bPlaceholderBody)
	{
		const FRoamPaint* Paint = nullptr;
		if (Spec.PaintVariants.Num() > 0)
		{
			const uint32 Pick = (GetTypeHash(AgentId) * 2654435761u) % static_cast<uint32>(Spec.PaintVariants.Num());
			Paint = &Spec.PaintVariants[static_cast<int32>(Pick)];
		}
		BuildRealMeshMaterials(Paint);
	}

	// lamps (placeholder only)
	for (int32 i = 0; i < TailLamps.Num(); ++i)
	{
		UStaticMeshComponent* Lamp = TailLamps[i];
		Lamp->SetVisibility(bPlaceholderBody);
		if (bPlaceholderBody)
		{
			if (Lamp->GetStaticMesh() != PlaceholderCube)
			{
				Lamp->SetStaticMesh(PlaceholderCube);
			}
			const float Side = (i == 0) ? -1.0f : 1.0f;
			const FVector Ground(-Spec.LengthCm * 0.5f + 3.0f, Side * (Spec.WidthCm * 0.5f - 24.0f), GroundOffsetCm + Spec.HeightCm * 0.2f);
			Lamp->SetRelativeLocation((Ground - FVector(0.0, 0.0, GroundOffsetCm)) / BodyScale);
			Lamp->SetRelativeScale3D(FVector(0.06, 0.28, 0.1));
			if (LampMIDs.Num() <= i)
			{
				LampMIDs.SetNum(i + 1);
			}
			if (!LampMIDs[i] || Lamp->GetMaterial(0) != LampMIDs[i])
			{
				LampMIDs[i] = Lamp->CreateAndSetMaterialInstanceDynamic(0);
			}
		}
	}
	LastLampState = -1;
}

void ARoamTrafficVehicle::ActivateAt(const FTransform& Transform, const FRoamTrafficVehicleSpec& InSpec, int32 InAgentId)
{
	Spec = InSpec;
	AgentId = InAgentId;
	bActiveInTraffic = true;
	bPhysicsReaction = false;
	bSettled = false;
	bBrakeLights = false;
	bHazardLights = false;
	bHasLastYaw = false;
	WheelAngleDeg = 0.0f;
	SteerDeg = 0.0f;
	LastSpeedCms = 0.0f;
	HornTimer = 0.0f;
	if (Body->IsSimulatingPhysics())
	{
		Body->SetSimulatePhysics(false);
	}
	ApplySpec();
	const FQuat Rot = Transform.GetRotation();
	SetActorTransform(FTransform(Rot, Transform.GetLocation() + Rot.RotateVector(FVector(0.0, 0.0, GroundOffsetCm)), BodyScale), false, nullptr, ETeleportType::TeleportPhysics);
	UpdateWheelPose();
	SetActorHiddenInGame(false);
	SetSimLOD(ERoamTrafficLOD::Physics);
	UpdateLamps();
}

void ARoamTrafficVehicle::Deactivate()
{
	bActiveInTraffic = false;
	bPhysicsReaction = false;
	bSettled = false;
	bBrakeLights = false;
	bHazardLights = false;
	AgentId = INDEX_NONE;
	if (Body->IsSimulatingPhysics())
	{
		Body->SetSimulatePhysics(false);
	}
	Body->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	SetActorHiddenInGame(true);
	SimLOD = ERoamTrafficLOD::Culled;
}

void ARoamTrafficVehicle::SetSimLOD(ERoamTrafficLOD NewLOD)
{
	SimLOD = NewLOD;
	if (bPhysicsReaction || bSettled)
	{
		return; // wrecks keep their collision at every distance
	}
	switch (NewLOD)
	{
	case ERoamTrafficLOD::Physics:
		Body->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
		break;
	case ERoamTrafficLOD::Kinematic:
	case ERoamTrafficLOD::DataOnly:
	case ERoamTrafficLOD::Culled:
	default:
		Body->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		break;
	}
}

void ARoamTrafficVehicle::SetKinematicTarget(const FTransform& Target, const FVector& VelocityCmS)
{
	if (bPhysicsReaction || bSettled)
	{
		return;
	}
	const FQuat Rot = Target.GetRotation();
	SetActorTransform(FTransform(Rot, Target.GetLocation() + Rot.RotateVector(FVector(0.0, 0.0, GroundOffsetCm)), BodyScale), false, nullptr, ETeleportType::None);

	LastSpeedCms = static_cast<float>(VelocityCmS.Size());
	const float YawDeg = static_cast<float>(Rot.Rotator().Yaw);
	const UWorld* World = GetWorld();
	const float Dt = World ? World->GetDeltaSeconds() : 0.0f;
	if (bHasLastYaw && Dt > KINDA_SMALL_NUMBER)
	{
		const float YawRateRad = FMath::DegreesToRadians(FMath::FindDeltaAngleDegrees(LastYawDeg, YawDeg)) / Dt;
		const float TargetSteer = FMath::RadiansToDegrees(FMath::Atan(Spec.WheelbaseCm * YawRateRad / FMath::Max(LastSpeedCms, 150.0f)));
		SteerDeg = FMath::Lerp(SteerDeg, FMath::Clamp(TargetSteer, -32.0f, 32.0f), FMath::Min(1.0f, Dt * 8.0f));
	}
	LastYawDeg = YawDeg;
	bHasLastYaw = true;
}

void ARoamTrafficVehicle::EnablePhysicsReaction(const FVector& InitialVelocityCmS, float YawKickDegS)
{
	bPhysicsReaction = true;
	bSettled = false;
	Body->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	Body->SetSimulatePhysics(true);
	Body->SetPhysicsLinearVelocity(InitialVelocityCmS);
	Body->SetPhysicsAngularVelocityInDegrees(FVector(0.0, 0.0, YawKickDegS));
	LastSpeedCms = static_cast<float>(InitialVelocityCmS.Size());
	SetHazardLights(true);
	SetBrakeLights(false);
}

void ARoamTrafficVehicle::SettleAsObstacle()
{
	if (Body->IsSimulatingPhysics())
	{
		Body->SetSimulatePhysics(false);
	}
	Body->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	bPhysicsReaction = false;
	bSettled = true;
	LastSpeedCms = 0.0f;
	SetHazardLights(true);
}

void ARoamTrafficVehicle::Horn()
{
	HornTimer = 0.8f;
	OnHorn.Broadcast();
}

void ARoamTrafficVehicle::UpdateWheelPose()
{
	for (int32 i = 0; i < bWheelPlaceholder.Num(); ++i)
	{
		const float Steer = bWheelSteers[i] ? SteerDeg : 0.0f;
		FQuat Q = FRotator(-WheelAngleDeg, Steer, 0.0f).Quaternion();
		if (bWheelPlaceholder[i])
		{
			Q = Q * FRotator(0.0f, 0.0f, 90.0f).Quaternion(); // cylinder axis Z -> vehicle Y
		}
		GetWheelComponent(i)->SetRelativeRotation(Q);
	}
}

void ARoamTrafficVehicle::UpdateLamps()
{
	if (!bPlaceholderBody)
	{
		// real meshes: the emissive lamp materials (Intensity 0..1) take over
		const bool bBlink = bHazardLights || HornTimer > 0.0f;
		float BlinkOn = 0.0f;
		if (bBlink)
		{
			const UWorld* World = GetWorld();
			BlinkOn = (FMath::Fmod(World ? World->GetTimeSeconds() : 0.0, 0.8) < 0.4) ? 1.0f : 0.0f;
		}
		SetLampIntensities(bHeadlights ? 1.0f : 0.0f, bBrakeLights ? 1.0f : (bHeadlights ? 0.30f : 0.10f), BlinkOn);
		return;
	}
	if (LampMIDs.Num() == 0)
	{
		return;
	}
	const bool bFlashing = bHazardLights || HornTimer > 0.0f;
	int32 State = 0; // 0 off, 1 brake, 2 hazard on, 3 hazard off
	if (bFlashing)
	{
		const UWorld* World = GetWorld();
		const double T = World ? World->GetTimeSeconds() : 0.0;
		State = (FMath::Fmod(T, 0.8) < 0.4) ? 2 : 3;
	}
	else if (bBrakeLights)
	{
		State = 1;
	}
	if (State == LastLampState)
	{
		return;
	}
	LastLampState = State;
	FLinearColor Colour(0.2f, 0.01f, 0.01f);
	switch (State)
	{
	case 1: Colour = FLinearColor(1.0f, 0.02f, 0.02f); break;
	case 2: Colour = FLinearColor(1.0f, 0.45f, 0.0f); break;
	case 3: Colour = FLinearColor(0.25f, 0.08f, 0.0f); break;
	default: break;
	}
	for (UMaterialInstanceDynamic* MID : LampMIDs)
	{
		if (MID)
		{
			MID->SetVectorParameterValue(ColorParam, Colour);
		}
	}
}

void ARoamTrafficVehicle::TickVisuals(float DeltaTime)
{
	if (!bActiveInTraffic)
	{
		return;
	}
	HornTimer = FMath::Max(0.0f, HornTimer - DeltaTime);
	float SpeedCms = LastSpeedCms;
	if (bPhysicsReaction && Body->IsSimulatingPhysics())
	{
		SpeedCms = static_cast<float>(Body->GetPhysicsLinearVelocity().Size());
		LastSpeedCms = SpeedCms;
	}
	const float Radius = FMath::Max(Spec.WheelRadiusCm, 5.0f);
	WheelAngleDeg = FMath::Fmod(WheelAngleDeg + FMath::RadiansToDegrees(SpeedCms / Radius * DeltaTime), 360.0f);
	if (SpeedCms > 1.0f || bPhysicsReaction)
	{
		UpdateWheelPose();
	}
	UpdateLamps();
}
