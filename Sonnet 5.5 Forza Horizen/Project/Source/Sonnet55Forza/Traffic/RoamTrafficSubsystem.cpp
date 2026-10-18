// Copyright Epic Games, Inc. All Rights Reserved.

#include "Traffic/RoamTrafficSubsystem.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamGameInstance.h"
#include "Core/RoamLog.h"
#include "Data/RoamRoadNetwork.h"
#include "Data/RoamTrafficCatalog.h"
#include "DrawDebugHelpers.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "Misc/PackageName.h"
#include "Save/RoamSaveSubsystem.h"
#include "World/RoamTimeWeatherSubsystem.h"

URoamTrafficSubsystem* URoamTrafficSubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	return World ? World->GetSubsystem<URoamTrafficSubsystem>() : nullptr;
}

bool URoamTrafficSubsystem::DoesSupportWorldType(const EWorldType::Type WorldType) const
{
	return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}

void URoamTrafficSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	if (const UGameInstance* GameInstance = GetWorld() ? GetWorld()->GetGameInstance() : nullptr)
	{
		if (const URoamSaveSubsystem* Save = GameInstance->GetSubsystem<URoamSaveSubsystem>())
		{
			Density = Save->GetSettings().TrafficDensity;
		}
	}
	RoamTraffic::BuildDefaultVehicleTypes(VehicleTypes);
	LoadCatalogTypes();
	ResolveMissingMeshes();
	UE_LOG(LogRoamTraffic, Log, TEXT("Traffic subsystem initialised, density %.2f, %d vehicle types"), Density, VehicleTypes.Num());
}

void URoamTrafficSubsystem::Deinitialize()
{
	ClearAll();
	Sim.Reset();
	FreePool.Reset();
	ActorOfAgent.Reset();
	Super::Deinitialize();
}

void URoamTrafficSubsystem::LoadCatalogTypes()
{
	const URoamTrafficCatalog* Catalog = LoadObject<URoamTrafficCatalog>(nullptr, TEXT("/Game/Forza/Data/DA_TrafficVehicles.DA_TrafficVehicles"), nullptr, LOAD_NoWarn | LOAD_Quiet);
	if (!Catalog || Catalog->Vehicles.Num() == 0)
	{
		UE_LOG(LogRoamTraffic, Log, TEXT("Traffic: DA_TrafficVehicles not found - using the built-in vehicle types"));
		return;
	}
	TArray<FRoamTrafficVehicleSpec> Specs;
	for (const FRoamTrafficVehicleDef& Def : Catalog->Vehicles)
	{
		FRoamTrafficVehicleSpec S = Def.Spec;
		S.TypeId = Def.TypeId;
		if (S.GlassMesh.IsNull())
		{
			S.GlassMesh = Def.GlassMesh;
		}
		S.Wheels.Reset();
		for (const FRoamTrafficWheelDef& W : Def.Wheels)
		{
			FRoamTrafficWheelSlot Slot;
			Slot.Mesh = W.Mesh;
			Slot.CentreCm = W.CenterCm;
			Slot.RadiusCm = W.RadiusCm;
			Slot.bSteering = W.bSteering;
			S.Wheels.Add(Slot);
		}
		S.PaintVariants = Def.PaintVariants;
		Specs.Add(S);
	}
	VehicleTypes = MoveTemp(Specs);
	UE_LOG(LogRoamTraffic, Log, TEXT("Traffic: %d vehicle types from DA_TrafficVehicles"), VehicleTypes.Num());
}

void URoamTrafficSubsystem::ResolveMissingMeshes()
{
	// The meshes are imported by the cars pipeline under /Game/Forza/Traffic/<id>/; a path without an asset becomes null so the
	// actor falls back to its engine-shape placeholder instead of logging load failures per activation.
	auto Check = [](TSoftObjectPtr<UStaticMesh>& Soft)
	{
		if (!Soft.IsNull() && !FPackageName::DoesPackageExist(Soft.ToSoftObjectPath().GetLongPackageName()))
		{
			Soft.Reset();
		}
	};
	for (FRoamTrafficVehicleSpec& Spec : VehicleTypes)
	{
		Check(Spec.BodyMesh);
		Check(Spec.GlassMesh);
		Check(Spec.WheelMesh);
		for (TSoftObjectPtr<UStaticMesh>& Wheel : Spec.PerWheelMeshes)
		{
			Check(Wheel);
		}
		for (FRoamTrafficWheelSlot& Slot : Spec.Wheels)
		{
			Check(Slot.Mesh);
		}
	}
}

// ---- network / sim setup ------------------------------------------------------------------------------------------------------

void URoamTrafficSubsystem::SetRoadNetworkOverride(URoamRoadNetwork* Network)
{
	NetworkOverride = Network;
	ClearAll();
	Sim.Reset();
	NetworkRetryTimer = 0.0f;
}

void URoamTrafficSubsystem::UseSyntheticNetwork()
{
	if (!SyntheticNetwork)
	{
		SyntheticNetwork = URoamRoadNetwork::BuildGeneratedForTests(this, 3, 100000.0f, 500.0f);
	}
	SetRoadNetworkOverride(SyntheticNetwork);
}

bool URoamTrafficSubsystem::EnsureSim(float DeltaTime)
{
	if (Sim.IsValid() && Sim->IsReady())
	{
		return true;
	}
	NetworkRetryTimer -= DeltaTime;
	if (NetworkRetryTimer > 0.0f)
	{
		return false;
	}
	NetworkRetryTimer = 5.0f;

	URoamRoadNetwork* Network = NetworkOverride;
	if (!Network)
	{
		if (URoamGameInstance* GameInstance = Cast<URoamGameInstance>(GetWorld()->GetGameInstance()))
		{
			Network = GameInstance->GetRoadNetwork();
		}
	}
	if (!Network && GetWorld()->GetMapName().Contains(TEXT("Test")))
	{
		if (!SyntheticNetwork)
		{
			SyntheticNetwork = URoamRoadNetwork::BuildGeneratedForTests(this, 3, 100000.0f, 500.0f);
		}
		Network = SyntheticNetwork;
		UE_LOG(LogRoamTraffic, Log, TEXT("No road network asset: traffic uses the synthetic test network on %s"), *GetWorld()->GetMapName());
	}
	if (!Network || Network->Roads.Num() == 0)
	{
		if (!bLoggedNoNetwork)
		{
			bLoggedNoNetwork = true;
			UE_LOG(LogRoamTraffic, Log, TEXT("Traffic idle: no road network available yet"));
		}
		return false;
	}
	BuildSim(Network);
	return IsSimReady();
}

void URoamTrafficSubsystem::BuildSim(URoamRoadNetwork* Network)
{
	if (!Network->IsIndexBuilt())
	{
		Network->BuildSpatialIndex();
	}
	Sim = MakeUnique<FRoamTrafficSim>();
	Sim->Init(*Network, VehicleTypes, 4711);
	bNeedInitialFill = true;
	UE_LOG(LogRoamTraffic, Log, TEXT("Traffic lane graph: %d lanes, %.1f km of lane, %d roads"), Sim->GetGraph().Lanes.Num(),
		Sim->GetGraph().TotalLaneLengthCm / 100000.0f, Network->Roads.Num());
}

// ---- control ---------------------------------------------------------------------------------------------------------------------

void URoamTrafficSubsystem::SetDensity(float Density01)
{
	Density = FMath::Clamp(Density01, 0.0f, 1.0f);
	Stats.Density = Density;
}

void URoamTrafficSubsystem::SetEnabled(bool bNewEnabled)
{
	if (bNewEnabled && !bEnabled)
	{
		bNeedInitialFill = true;
	}
	bEnabled = bNewEnabled;
}

void URoamTrafficSubsystem::ClearAll()
{
	if (Sim.IsValid())
	{
		Sim->Clear();
		DrainRemoved();
	}
	for (const TPair<int32, ARoamTrafficVehicle*>& Pair : ActorOfAgent)
	{
		if (Pair.Value)
		{
			Pair.Value->Deactivate();
			FreePool.Add(Pair.Value);
		}
	}
	ActorOfAgent.Reset();
	for (ARoamTrafficVehicle* Show : ShowcaseActors)
	{
		if (IsValid(Show))
		{
			Show->Deactivate();
			FreePool.Add(Show);
		}
	}
	ShowcaseActors.Reset();
	BodyHitAgents.Reset();
	bNeedInitialFill = true;
	Stats.NumAgents = 0;
	Stats.NumPhysicsActors = 0;
	Stats.NumKinematicActors = 0;
}

void URoamTrafficSubsystem::SpawnShowcase()
{
	UWorld* World = GetWorld();
	const APlayerController* PC = World ? World->GetFirstPlayerController() : nullptr;
	const APawn* Pawn = PC ? PC->GetPawn() : nullptr;
	if (!Pawn)
	{
		return;
	}
	const FVector Origin = Pawn->GetActorLocation();
	FVector Forward = Pawn->GetActorForwardVector();
	Forward.Z = 0.0;
	Forward = Forward.GetSafeNormal();
	const FVector Side = FVector::CrossProduct(FVector::UpVector, Forward);
	FCollisionQueryParams Query(SCENE_QUERY_STAT(RoamTrafficShowcase), false, Pawn);
	for (int32 i = 0; i < VehicleTypes.Num(); ++i)
	{
		ARoamTrafficVehicle* Vehicle = AcquireActor();
		if (!Vehicle)
		{
			break;
		}
		const FVector Ahead = Origin + Forward * (1800.0 + 1400.0 * i) + Side * 700.0;
		FHitResult Hit;
		FVector Ground = Ahead;
		if (World->LineTraceSingleByChannel(Hit, Ahead + FVector(0, 0, 20000), Ahead - FVector(0, 0, 20000), ECC_Visibility, Query))
		{
			Ground = Hit.ImpactPoint;
		}
		Vehicle->ActivateAt(FTransform(Forward.Rotation(), Ground), VehicleTypes[i], 9000 + i);
		Vehicle->SetSimLOD(ERoamTrafficLOD::Kinematic);
		Vehicle->SetBrakeLights(i % 2 == 0);
		Vehicle->SetHeadlights(true);
		Vehicle->TickVisuals(0.0f);
		ShowcaseActors.Add(Vehicle);
	}
	UE_LOG(LogRoamTraffic, Log, TEXT("Traffic showcase: %d vehicles"), ShowcaseActors.Num());
}

FString URoamTrafficSubsystem::SpawnBlocker(float AheadMetres, int32 TypeIndex)
{
	UWorld* World = GetWorld();
	const APlayerController* PC = World ? World->GetFirstPlayerController() : nullptr;
	const APawn* Pawn = PC ? PC->GetPawn() : nullptr;
	if (!Pawn || !Sim.IsValid() || !Sim->IsReady())
	{
		return TEXT("traffic ram: needs a player and a running traffic simulation (traffic 1)");
	}
	float S = 0.0f, Dist = 0.0f;
	const int32 LaneId = Sim->GetGraph().FindNearestLane(Pawn->GetActorLocation(), 2500.0f, &S, &Dist);
	if (LaneId == INDEX_NONE)
	{
		return TEXT("traffic ram: no lane within 25 m of the player");
	}
	const FRoamLane& Lane = Sim->GetGraph().Lanes[LaneId];
	FVector Pos, Dir;
	Lane.Sample(S, Pos, Dir);
	if (FVector::DotProduct(Dir.GetSafeNormal2D(), Pawn->GetActorForwardVector().GetSafeNormal2D()) < 0.3)
	{
		return TEXT("traffic ram: the nearest lane runs against the player's heading");
	}
	const int32 Type = FMath::Clamp(TypeIndex, 0, VehicleTypes.Num() - 1);
	const int32 Id = Sim->SpawnAgent(LaneId, S + AheadMetres * 100.0f, Type, 0.0f);
	const int32 Index = Id == INDEX_NONE ? INDEX_NONE : Sim->FindAgentIndex(Id);
	if (Index == INDEX_NONE)
	{
		return TEXT("traffic ram: the lane has no room for a blocker there");
	}
	FRoamTrafficAgent& Agent = Sim->Agents[Index];
	Agent.V = 0.0f;
	Agent.MaxSpeedMs = 0.05f;
	Agent.AMax = 0.0f;
	return FString::Printf(TEXT("traffic ram: stopped %s %.0f m ahead on lane %d (agent %d)"), *VehicleTypes[Type].TypeId.ToString(), AheadMetres, LaneId, Id);
}

FString URoamTrafficSubsystem::RunSelfCheck()
{
	UWorld* World = GetWorld();
	const URoamGameInstance* GameInstance = World ? Cast<URoamGameInstance>(World->GetGameInstance()) : nullptr;
	URoamRoadNetwork* Network = NetworkOverride ? NetworkOverride.Get() : (GameInstance ? const_cast<URoamGameInstance*>(GameInstance)->GetRoadNetwork() : nullptr);
	if (!Sim.IsValid() || !Network)
	{
		return TEXT("traffic check: no simulation / road network yet");
	}
	int32 Total = 0, RightSide = 0, WrongSide = 0, OffRoad = 0, Floating = 0, Buried = 0, NoGround = 0, WithActor = 0;
	float WorstWrongCm = 0.0f, MaxGapCm = 0.0f, MaxBuryCm = 0.0f;
	FCollisionQueryParams Query(SCENE_QUERY_STAT(RoamTrafficCheck), false);
	for (const FRoamTrafficAgent& A : Sim->Agents)
	{
		if (A.State != ERoamTrafficAgentState::Driving)
		{
			continue;
		}
		++Total;
		FRoamRoadHit Hit;
		if (!Network->FindNearestRoad(A.Pos, Hit, 0xFF, 4000.0f) || !Hit.bValid)
		{
			++OffRoad;
			continue;
		}
		const float Along = static_cast<float>(FVector::DotProduct(A.Dir.GetSafeNormal2D(), Hit.Tangent.GetSafeNormal2D()));
		const float Lateral = static_cast<float>(FVector::DotProduct(A.Pos - Hit.Position, Hit.Right));
		// right-hand traffic: with the road direction the car must be right of the centreline, against it left of the centreline
		const bool bOk = (Along >= 0.0f) ? (Lateral > -30.0f) : (Lateral < 30.0f);
		if (bOk)
		{
			++RightSide;
		}
		else
		{
			++WrongSide;
			WorstWrongCm = FMath::Max(WorstWrongCm, FMath::Abs(Lateral));
		}
		FHitResult Ground;
		if (World->LineTraceSingleByChannel(Ground, A.Pos + FVector(0, 0, 400), A.Pos - FVector(0, 0, 1500), ECC_Visibility, Query))
		{
			const float Gap = static_cast<float>(A.Pos.Z - Ground.ImpactPoint.Z);
			if (Gap > 60.0f)
			{
				++Floating;
				MaxGapCm = FMath::Max(MaxGapCm, Gap);
			}
			else if (Gap < -60.0f)
			{
				++Buried;
				MaxBuryCm = FMath::Max(MaxBuryCm, -Gap);
			}
		}
		else
		{
			++NoGround;
		}
	}
	for (const TPair<int32, ARoamTrafficVehicle*>& Pair : ActorOfAgent)
	{
		if (Pair.Value && Pair.Value->IsActiveInTraffic())
		{
			++WithActor;
		}
	}
	return FString::Printf(TEXT("traffic check: %d driving agents (%d with actors): right side %d, wrong side %d (worst %.0f cm), off road %d, floating>60cm %d (max %.0f), buried>60cm %d (max %.0f), no ground %d"),
		Total, WithActor, RightSide, WrongSide, WorstWrongCm, OffRoad, Floating, MaxGapCm, Buried, MaxBuryCm, NoGround);
}

int32 URoamTrafficSubsystem::SuppressArea(const FVector& Center, float RadiusCm, float Seconds)
{
	FSuppression Suppression;
	Suppression.Handle = NextSuppressionHandle++;
	Suppression.Center = Center;
	Suppression.RadiusCm = RadiusCm;
	Suppression.ExpireWorldTime = (Seconds > 0.0f && GetWorld()) ? GetWorld()->GetTimeSeconds() + Seconds : 0.0;
	Suppressions.Add(Suppression);
	return Suppression.Handle;
}

void URoamTrafficSubsystem::ReleaseSuppression(int32 Handle)
{
	Suppressions.RemoveAll([Handle](const FSuppression& S) { return S.Handle == Handle; });
}

bool URoamTrafficSubsystem::IsSuppressed(const FVector& Location) const
{
	for (const FSuppression& S : Suppressions)
	{
		if (FVector::DistSquared(S.Center, Location) <= FMath::Square(static_cast<double>(S.RadiusCm)))
		{
			return true;
		}
	}
	return false;
}

void URoamTrafficSubsystem::ExpireSuppressions()
{
	if (Suppressions.Num() == 0 || !GetWorld())
	{
		return;
	}
	const double Now = GetWorld()->GetTimeSeconds();
	Suppressions.RemoveAll([Now](const FSuppression& S) { return S.ExpireWorldTime > 0.0 && Now >= S.ExpireWorldTime; });
}

void URoamTrafficSubsystem::RegisterVehicleType(const FRoamTrafficVehicleSpec& Spec)
{
	const int32 Existing = VehicleTypes.IndexOfByPredicate([&Spec](const FRoamTrafficVehicleSpec& S) { return S.TypeId == Spec.TypeId; });
	if (Existing != INDEX_NONE)
	{
		VehicleTypes[Existing] = Spec;
	}
	else
	{
		VehicleTypes.Add(Spec);
	}
	if (Sim.IsValid())
	{
		Sim->SetTypes(VehicleTypes);
	}
}

FRoamTrafficStats URoamTrafficSubsystem::GetStats() const
{
	FRoamTrafficStats Result = Stats;
	Result.Density = Density;
	return Result;
}

void URoamTrafficSubsystem::GetAgentLocations(TArray<FVector>& OutLocations) const
{
	OutLocations.Reset();
	if (Sim.IsValid())
	{
		for (const FRoamTrafficAgent& A : Sim->Agents)
		{
			OutLocations.Add(A.Pos);
		}
	}
}

// ---- actors / pool -------------------------------------------------------------------------------------------------------------

ARoamTrafficVehicle* URoamTrafficSubsystem::AcquireActor()
{
	while (FreePool.Num() > 0)
	{
		ARoamTrafficVehicle* Vehicle = FreePool.Pop();
		if (IsValid(Vehicle))
		{
			return Vehicle;
		}
	}
	if (PoolActors.Num() >= RoamTraffic::MaxVisibleAgents + 8 || !GetWorld())
	{
		return nullptr;
	}
	FActorSpawnParameters Params;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	Params.ObjectFlags |= RF_Transient;
	ARoamTrafficVehicle* Vehicle = GetWorld()->SpawnActor<ARoamTrafficVehicle>(ARoamTrafficVehicle::StaticClass(), FTransform(FVector(0.0, 0.0, -500000.0)), Params);
	if (Vehicle)
	{
		Vehicle->OnBodyHit.AddUObject(this, &URoamTrafficSubsystem::OnVehicleBodyHit);
		PoolActors.Add(Vehicle);
	}
	return Vehicle;
}

ARoamTrafficVehicle* URoamTrafficSubsystem::FindOrAcquireActor(int32 AgentIndex)
{
	if (!Sim.IsValid() || !Sim->Agents.IsValidIndex(AgentIndex))
	{
		return nullptr;
	}
	const FRoamTrafficAgent& A = Sim->Agents[AgentIndex];
	if (ARoamTrafficVehicle** Found = ActorOfAgent.Find(A.Id))
	{
		return *Found;
	}
	ARoamTrafficVehicle* Vehicle = AcquireActor();
	if (Vehicle && VehicleTypes.IsValidIndex(A.TypeIndex))
	{
		const FQuat Rot = FRotationMatrix::MakeFromXZ(A.Dir, FVector::UpVector).ToQuat();
		Vehicle->ActivateAt(FTransform(Rot, A.Pos), VehicleTypes[A.TypeIndex], A.Id);
		ActorOfAgent.Add(A.Id, Vehicle);
	}
	return Vehicle;
}

void URoamTrafficSubsystem::ReleaseActor(int32 AgentId)
{
	ARoamTrafficVehicle* Vehicle = nullptr;
	if (ActorOfAgent.RemoveAndCopyValue(AgentId, Vehicle) && Vehicle)
	{
		Vehicle->Deactivate();
		FreePool.Add(Vehicle);
	}
}

void URoamTrafficSubsystem::DrainRemoved()
{
	if (!Sim.IsValid())
	{
		return;
	}
	for (const int32 Id : Sim->RemovedIds)
	{
		ReleaseActor(Id);
	}
	Sim->RemovedIds.Reset();
}

void URoamTrafficSubsystem::OnVehicleBodyHit(ARoamTrafficVehicle* Vehicle, AActor* Other, const FVector& NormalImpulse)
{
	if (Vehicle && Other && Other == PlayerActor.Get())
	{
		BodyHitAgents.AddUnique(Vehicle->GetAgentId());
	}
}

// ---- per-frame ---------------------------------------------------------------------------------------------------------------------

bool URoamTrafficSubsystem::GatherPlayer(float DeltaTime)
{
	UWorld* World = GetWorld();
	APlayerController* PC = World ? World->GetFirstPlayerController() : nullptr;
	if (!PC)
	{
		Player.bValid = false;
		return false;
	}
	FVector ViewLoc;
	FRotator ViewRot;
	PC->GetPlayerViewPoint(ViewLoc, ViewRot);
	ViewLocation = ViewLoc;
	ViewForward = ViewRot.Vector();

	APawn* Pawn = PC->GetPawn();
	PlayerActor = Pawn;
	const FVector Loc = Pawn ? Pawn->GetActorLocation() : ViewLoc;
	bool bTeleported = false;
	Player.PrevVelocity = Player.Velocity;
	if (bHasLastPlayerLocation && DeltaTime > KINDA_SMALL_NUMBER)
	{
		const FVector Delta = Loc - LastPlayerLocation;
		if (Delta.SizeSquared() > 20000.0 * 20000.0)
		{
			bTeleported = true;
			Player.Velocity = FVector::ZeroVector;
			Player.PrevVelocity = FVector::ZeroVector;
		}
		else
		{
			Player.Velocity = Delta / DeltaTime;
		}
	}
	LastPlayerLocation = Loc;
	bHasLastPlayerLocation = true;
	Player.bValid = true;
	Player.Location = Loc;
	Player.Forward = Pawn ? Pawn->GetActorForwardVector() : ViewForward;
	return bTeleported;
}

void URoamTrafficSubsystem::RemoveOutOfView()
{
	// density 0 / traffic off: agents leave once nobody can see them
	for (int32 i = Sim->Agents.Num() - 1; i >= 0; --i)
	{
		const FRoamTrafficAgent& A = Sim->Agents[i];
		const FVector ToAgent = A.Pos - ViewLocation;
		const double D = ToAgent.Size();
		const bool bInFront = D > 1.0 && FVector::DotProduct(ToAgent / D, ViewForward) > 0.3;
		if (D > RoamTraffic::VisibleRingCm || (D > 8000.0 && !bInFront))
		{
			Sim->RemoveAgentAt(i);
		}
	}
	DrainRemoved();
}

void URoamTrafficSubsystem::HandleContacts()
{
	if (!Player.bValid || Sim->Agents.Num() == 0)
	{
		BodyHitAgents.Reset();
		return;
	}
	TArray<FRoamTrafficContact> Contacts;
	Sim->CollectPlayerContacts(Player, Contacts);
	// hits reported by the physics callback that the geometric test did not see (box approximation)
	for (const int32 AgentId : BodyHitAgents)
	{
		const int32 Index = Sim->FindAgentIndex(AgentId);
		if (Index != INDEX_NONE && Sim->Agents[Index].State == ERoamTrafficAgentState::Driving
			&& !Contacts.ContainsByPredicate([Index](const FRoamTrafficContact& C) { return C.AgentIndex == Index; }))
		{
			FRoamTrafficContact C;
			if (Sim->MakeCollisionContact(Index, Player, C))
			{
				Contacts.Add(C);
			}
		}
	}
	BodyHitAgents.Reset();

	for (const FRoamTrafficContact& C : Contacts)
	{
		if (!Sim->Agents.IsValidIndex(C.AgentIndex) || Sim->Agents[C.AgentIndex].State != ERoamTrafficAgentState::Driving)
		{
			continue;
		}
		ARoamTrafficVehicle* Vehicle = FindOrAcquireActor(C.AgentIndex);
		if (C.bCollision)
		{
			Sim->ApplyHit(C.AgentIndex);
			if (Vehicle)
			{
				Vehicle->SetSimLOD(ERoamTrafficLOD::Physics);
				Vehicle->EnablePhysicsReaction(C.AgentVelocityAfterCms, C.YawKickDegS);
				Vehicle->Horn();
			}
			UE_LOG(LogRoamTraffic, Log, TEXT("ROAM_TRAFFIC_HIT agent %d, impact %.1f m/s"), Sim->Agents[C.AgentIndex].Id, C.ImpactSpeedMs);
			OnCollision.Broadcast(Vehicle, PlayerActor.Get(), C.ImpactSpeedMs);
		}
		else
		{
			Sim->Agents[C.AgentIndex].NearMissCooldown = 4.0f;
			OnNearMiss.Broadcast(Vehicle, C.GapCm, C.ClosingKmh);
		}
	}
}

void URoamTrafficSubsystem::SyncActors(float DeltaTime)
{
	TArray<FRoamTrafficAgent>& Agents = Sim->Agents;
	const FVector Up = FVector::UpVector;
	TArray<TPair<double, int32>> Candidates;
	TArray<int32> ToRemove;

	for (int32 i = 0; i < Agents.Num(); ++i)
	{
		FRoamTrafficAgent& A = Agents[i];
		const double D = Player.bValid ? FVector::Dist(A.Pos, Player.Location) : 1.0e9;
		ARoamTrafficVehicle** Found = ActorOfAgent.Find(A.Id);
		ARoamTrafficVehicle* Vehicle = Found ? *Found : nullptr;

		if (!Vehicle)
		{
			if (A.bWantsHorn)
			{
				A.bWantsHorn = false;
			}
			if (A.State == ERoamTrafficAgentState::Driving && D < RoamTraffic::VisibleRingCm - 2000.0)
			{
				Candidates.Add(TPair<double, int32>(D, i));
			}
			else if (A.State != ERoamTrafficAgentState::Driving && D > RoamTraffic::VisibleRingCm)
			{
				ToRemove.Add(A.Id); // a wreck nobody can see any more
			}
			continue;
		}

		if (A.State == ERoamTrafficAgentState::Driving)
		{
			if (D > RoamTraffic::VisibleRingCm + 2000.0)
			{
				ReleaseActor(A.Id);
				continue;
			}
			const FQuat Rot = FRotationMatrix::MakeFromXZ(A.Dir, Up).ToQuat();
			Vehicle->SetKinematicTarget(FTransform(Rot, A.Pos), A.Dir * A.V);
			Vehicle->SetBrakeLights(A.bBraking);
			Vehicle->SetHeadlights(bNight);
			const bool bPhysicsRing = Vehicle->GetSimLOD() == ERoamTrafficLOD::Physics ? D < RoamTraffic::PhysicsRingCm + 1000.0 : D < RoamTraffic::PhysicsRingCm;
			const ERoamTrafficLOD Want = bPhysicsRing ? ERoamTrafficLOD::Physics : ERoamTrafficLOD::Kinematic;
			if (Vehicle->GetSimLOD() != Want)
			{
				Vehicle->SetSimLOD(Want);
			}
			if (A.bWantsHorn)
			{
				A.bWantsHorn = false;
				Vehicle->Horn();
			}
		}
		else
		{
			A.Pos = Vehicle->GetActorLocation();
			A.Dir = Vehicle->GetActorForwardVector();
			if (D > RoamTraffic::VisibleRingCm + 2000.0)
			{
				ToRemove.Add(A.Id);
				continue;
			}
			if (A.State == ERoamTrafficAgentState::Hit && A.StateTime >= RoamTraffic::PhysicsReactionSeconds)
			{
				// the wreck has settled: it becomes a stopped obstacle; followers only wait for it if it still stands in their lane
				const FRoamLane& L = Sim->GetGraph().Lanes[A.Lane];
				FVector LanePos, LaneDir;
				L.Sample(A.S, LanePos, LaneDir);
				const FVector Dir2 = FVector(LaneDir.X, LaneDir.Y, 0.0).GetSafeNormal();
				const FVector Rel = A.Pos - LanePos;
				const float Along = static_cast<float>(Rel.X * Dir2.X + Rel.Y * Dir2.Y);
				const float Lat = static_cast<float>(-Rel.X * Dir2.Y + Rel.Y * Dir2.X);
				const bool bBlocks = FMath::Abs(Lat) < 230.0f;
				A.S = FMath::Clamp(A.S + Along, 0.0f, L.LengthCm);
				Sim->SettleAgent(i, bBlocks);
				Vehicle->SettleAsObstacle();
			}
			else if (A.State == ERoamTrafficAgentState::Obstacle)
			{
				const FVector ToAgent = A.Pos - ViewLocation;
				const double Dv = ToAgent.Size();
				const bool bInView = Dv < 1.0 || FVector::DotProduct(ToAgent / Dv, ViewForward) > 0.35;
				if (A.StateTime > 120.0f || (A.StateTime > 30.0f && D > 10000.0 && !bInView))
				{
					ToRemove.Add(A.Id);
				}
			}
		}
		Vehicle->TickVisuals(DeltaTime);
	}

	// activate actors for agents that entered the visible ring (nearest first, a few per frame to avoid hitches)
	Candidates.Sort([](const TPair<double, int32>& X, const TPair<double, int32>& Y) { return X.Key < Y.Key; });
	int32 Activated = 0;
	for (const TPair<double, int32>& C : Candidates)
	{
		if (ActorOfAgent.Num() >= RoamTraffic::MaxVisibleAgents || Activated >= 4)
		{
			break;
		}
		FindOrAcquireActor(C.Value);
		if (ARoamTrafficVehicle** Found = ActorOfAgent.Find(Agents[C.Value].Id))
		{
			const bool bPhysicsRing = C.Key < RoamTraffic::PhysicsRingCm;
			(*Found)->SetSimLOD(bPhysicsRing ? ERoamTrafficLOD::Physics : ERoamTrafficLOD::Kinematic);
			++Activated;
		}
	}

	for (const int32 Id : ToRemove)
	{
		const int32 Index = Sim->FindAgentIndex(Id);
		if (Index != INDEX_NONE)
		{
			Sim->RemoveAgentAt(Index);
		}
	}
	DrainRemoved();
}

void URoamTrafficSubsystem::DrawDebug() const
{
	UWorld* World = GetWorld();
	if (!World || !Sim.IsValid())
	{
		return;
	}
	for (const FRoamTrafficAgent& A : Sim->Agents)
	{
		if (Player.bValid && FVector::DistSquared(A.Pos, Player.Location) > FMath::Square(static_cast<double>(RoamTraffic::VisibleRingCm)))
		{
			continue;
		}
		const FColor Colour = A.State == ERoamTrafficAgentState::Driving ? (A.bBraking ? FColor::Yellow : FColor::Green) : FColor::Red;
		const FQuat Rot = FRotationMatrix::MakeFromXZ(A.Dir, FVector::UpVector).ToQuat();
		DrawDebugBox(World, A.Pos + FVector(0.0, 0.0, 90.0), FVector(A.LengthCm * 0.5f, A.WidthCm * 0.5f, 90.0f), Rot, Colour, false, 0.0f, 0, 3.0f);
		if (A.HoldJunction != INDEX_NONE && Sim->GetGraph().JunctionPos.IsValidIndex(A.HoldJunction))
		{
			DrawDebugLine(World, A.Pos + FVector(0.0, 0.0, 120.0), Sim->GetGraph().JunctionPos[A.HoldJunction] + FVector(0.0, 0.0, 120.0), FColor::Cyan, false, 0.0f, 0, 2.0f);
		}
	}
}

void URoamTrafficSubsystem::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	ExpireSuppressions();
	UWorld* World = GetWorld();
	if (!World || DeltaTime <= 0.0f || !EnsureSim(DeltaTime))
	{
		return;
	}

	const bool bTeleported = GatherPlayer(DeltaTime);
	if (bTeleported)
	{
		ClearAll();
	}

	// environment: fewer cars at night, slower in the wet, headlights in the dark
	DayFactor = 1.0f;
	SpeedScale = 1.0f;
	bNight = false;
	if (const URoamTimeWeatherSubsystem* TimeWeather = World->GetSubsystem<URoamTimeWeatherSubsystem>())
	{
		bNight = TimeWeather->IsNight();
		DayFactor = FMath::Lerp(RoamTraffic::NightDensityFactor, 1.0f, FMath::SmoothStep(0.0f, 0.4f, TimeWeather->GetDaylight01()));
		SpeedScale = TimeWeather->IsRoadWet() ? 0.88f : 1.0f;
	}

	const bool bActive = bEnabled && Density > 0.0f;
	if (bActive && Player.bValid)
	{
		SpawnTimer -= DeltaTime;
		if (SpawnTimer <= 0.0f || bNeedInitialFill)
		{
			SpawnTimer = 0.3f;
			Sim->SpawnAround(Player.Location, Density, DayFactor, bNeedInitialFill, bNeedInitialFill ? 120 : 3,
				[this](const FVector& P) { return IsSuppressed(P); });
			bNeedInitialFill = false;
		}
	}

	if (Sim->Agents.Num() > 0)
	{
		const int32 Steps = FMath::Clamp(FMath::CeilToInt(DeltaTime / 0.05f), 1, 4);
		const float SimStepDt = DeltaTime / static_cast<float>(Steps);
		for (int32 s = 0; s < Steps; ++s)
		{
			Sim->Step(SimStepDt, Player, SpeedScale);
		}
		if (Player.bValid)
		{
			Sim->RemoveFarAgents(Player.Location, RoamTraffic::DataRingCm);
			DrainRemoved();
		}
		if (!bActive)
		{
			RemoveOutOfView();
		}
		HandleContacts();
		SyncActors(DeltaTime);
	}

	if (bDebugDraw)
	{
		DrawDebug();
	}

	Stats.NumAgents = Sim->Agents.Num();
	Stats.NumSpawnedTotal = Sim->NumSpawnedTotal;
	Stats.NumDespawnedTotal = Sim->NumRemovedTotal;
	Stats.NumPooledActors = PoolActors.Num();
	Stats.NumPhysicsActors = 0;
	Stats.NumKinematicActors = 0;
	for (const TPair<int32, ARoamTrafficVehicle*>& Pair : ActorOfAgent)
	{
		if (Pair.Value && (Pair.Value->IsInPhysicsReaction() || Pair.Value->IsSettledObstacle() || Pair.Value->GetSimLOD() == ERoamTrafficLOD::Physics))
		{
			++Stats.NumPhysicsActors;
		}
		else
		{
			++Stats.NumKinematicActors;
		}
	}
}

// ---- console ---------------------------------------------------------------------------------------------------------------------

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("traffic", "traffic [0..1|on|off|debug [on|off]|clear|synth|stats]", "Show or set the traffic density (0 = none, 1 = maximum); debug draws the agents; clear removes them; synth uses the synthetic test road network.", "traffic",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamTrafficSubsystem* Traffic = Ctx.World ? Ctx.World->GetSubsystem<URoamTrafficSubsystem>() : nullptr;
		if (!Traffic)
		{
			return Ctx.Fail(TEXT("no traffic system (no game world)"));
		}
		if (Ctx.NumArgs() > 0)
		{
			const FString& Sub = Ctx.Args[0];
			bool bOn = true;
			float Density = 0.0f;
			if (Sub.Equals(TEXT("debug"), ESearchCase::IgnoreCase))
			{
				bool bDebug = !Traffic->IsDebugDraw();
				if (Ctx.NumArgs() > 1)
				{
					Ctx.GetBool(1, bDebug);
				}
				Traffic->SetDebugDraw(bDebug);
			}
			else if (Sub.Equals(TEXT("clear"), ESearchCase::IgnoreCase))
			{
				Traffic->ClearAll();
			}
			else if (Sub.Equals(TEXT("ram"), ESearchCase::IgnoreCase))
			{
				float Ahead = 80.0f;
				int32 Type = 0;
				Ctx.GetFloat(1, Ahead);
				Ctx.GetInt(2, Type);
				return Traffic->SpawnBlocker(Ahead, Type);
			}
			else if (Sub.Equals(TEXT("check"), ESearchCase::IgnoreCase))
			{
				return Traffic->RunSelfCheck();
			}
			else if (Sub.Equals(TEXT("showcase"), ESearchCase::IgnoreCase))
			{
				Traffic->SpawnShowcase();
			}
			else if (Sub.Equals(TEXT("synth"), ESearchCase::IgnoreCase))
			{
				Traffic->UseSyntheticNetwork();
			}
			else if (Sub.Equals(TEXT("stats"), ESearchCase::IgnoreCase))
			{
				// falls through to the status line below
			}
			else if (Ctx.GetFloat(0, Density))
			{
				Traffic->SetDensity(Density);
				Traffic->SetEnabled(Traffic->GetDensity() > 0.0f);
				if (URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr)
				{
					Save->GetSettings().TrafficDensity = Traffic->GetDensity();
					Save->MarkDirty();
				}
			}
			else if (Ctx.GetBool(0, bOn))
			{
				Traffic->SetEnabled(bOn);
			}
			else
			{
				return Ctx.Fail(TEXT("usage: traffic [0..1|on|off|debug [on|off]|clear|synth|stats]"));
			}
		}
		const FRoamTrafficStats Stats = Traffic->GetStats();
		return FString::Printf(TEXT("traffic %s%s, density %.2f, agents %d (physics %d, kinematic %d), pool %d, spawned %d, despawned %d"),
			Traffic->IsEnabled() ? TEXT("on") : TEXT("off"), Traffic->IsSimReady() ? TEXT("") : TEXT(" (no road network yet)"), Stats.Density,
			Stats.NumAgents, Stats.NumPhysicsActors, Stats.NumKinematicActors, Stats.NumPooledActors, Stats.NumSpawnedTotal, Stats.NumDespawnedTotal);
	});
