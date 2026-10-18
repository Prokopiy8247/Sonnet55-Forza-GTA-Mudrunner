// Copyright Epic Games, Inc. All Rights Reserved.

#include "Traffic/RoamTrafficSim.h"

#include "Data/RoamRoadNetwork.h"
#include "Engine/StaticMesh.h"

namespace RoamTraffic
{
	float IdmAcceleration(float VMs, float V0Ms, float GapM, float ClosingMs, float AMaxMs2, float BComfortMs2, float HeadwaySec, float MinGapM)
	{
		const float Ratio = VMs / FMath::Max(V0Ms, 0.1f);
		const float Free = 1.0f - FMath::Square(FMath::Square(Ratio));
		const float SStar = MinGapM + FMath::Max(0.0f, VMs * HeadwaySec + VMs * ClosingMs / (2.0f * FMath::Sqrt(AMaxMs2 * BComfortMs2)));
		const float Gap = FMath::Max(GapM, 0.05f);
		return AMaxMs2 * (Free - FMath::Square(SStar / Gap));
	}

	float BaseDensityPerKm(ERoamRoadClass RoadClass)
	{
		switch (RoadClass)
		{
		case ERoamRoadClass::Highway: return 3.5f;
		case ERoamRoadClass::Regional: return 2.5f;
		case ERoamRoadClass::Village: return 2.0f;
		case ERoamRoadClass::Mountain: return 1.2f;
		case ERoamRoadClass::Dirt:
		case ERoamRoadClass::Shortcut: return 0.4f;
		default: return 1.0f;
		}
	}

	bool OverlapOrientedBoxes2D(const FVector& CenterA, const FVector& DirA, float HalfLenA, float HalfWidA,
		const FVector& CenterB, const FVector& DirB, float HalfLenB, float HalfWidB, float MarginCm)
	{
		const FVector2D FA = FVector2D(DirA.X, DirA.Y).GetSafeNormal();
		const FVector2D RA(-FA.Y, FA.X);
		const FVector2D FB = FVector2D(DirB.X, DirB.Y).GetSafeNormal();
		const FVector2D RB(-FB.Y, FB.X);
		const FVector2D D(CenterB.X - CenterA.X, CenterB.Y - CenterA.Y);
		const float LA = HalfLenA + MarginCm;
		const float WA = HalfWidA + MarginCm;
		const FVector2D Axes[4] = { FA, RA, FB, RB };
		for (const FVector2D& Axis : Axes)
		{
			const float RadiusA = LA * FMath::Abs(static_cast<float>(FVector2D::DotProduct(Axis, FA))) + WA * FMath::Abs(static_cast<float>(FVector2D::DotProduct(Axis, RA)));
			const float RadiusB = HalfLenB * FMath::Abs(static_cast<float>(FVector2D::DotProduct(Axis, FB))) + HalfWidB * FMath::Abs(static_cast<float>(FVector2D::DotProduct(Axis, RB)));
			if (FMath::Abs(static_cast<float>(FVector2D::DotProduct(Axis, D))) > RadiusA + RadiusB)
			{
				return false;
			}
		}
		return true;
	}

	void BuildDefaultVehicleTypes(TArray<FRoamTrafficVehicleSpec>& Out)
	{
		Out.Reset();
		auto Add = [&Out](const TCHAR* Id, float L, float W, float H, float Wheelbase, float WheelR, float Track, float Mass,
			float MaxKmh, float Accel, float Decel, float Headway, float MinGap, float Weight, std::initializer_list<ERoamRoadClass> Allowed)
		{
			FRoamTrafficVehicleSpec S;
			S.TypeId = FName(Id);
			const FString Base = FString::Printf(TEXT("/Game/Forza/Traffic/%s/SM_%s"), Id, Id);
			S.BodyMesh = TSoftObjectPtr<UStaticMesh>(FSoftObjectPath(Base + TEXT("_Body.SM_") + Id + TEXT("_Body")));
			S.GlassMesh = TSoftObjectPtr<UStaticMesh>(FSoftObjectPath(Base + TEXT("_Glass.SM_") + Id + TEXT("_Glass")));
			static const TCHAR* Suffix[4] = { TEXT("FL"), TEXT("FR"), TEXT("RL"), TEXT("RR") };
			for (const TCHAR* W2 : Suffix)
			{
				S.PerWheelMeshes.Add(TSoftObjectPtr<UStaticMesh>(FSoftObjectPath(Base + TEXT("_Wheel_") + W2 + TEXT(".SM_") + Id + TEXT("_Wheel_") + W2)));
			}
			S.LengthCm = L; S.WidthCm = W; S.HeightCm = H; S.WheelbaseCm = Wheelbase; S.WheelRadiusCm = WheelR; S.TrackCm = Track; S.MassKg = Mass;
			S.MaxSpeedKmh = MaxKmh; S.AccelerationMs2 = Accel; S.ComfortDecelMs2 = Decel; S.TimeHeadwaySec = Headway; S.MinGapM = MinGap; S.SpawnWeight = Weight;
			S.AllowedRoadClasses = TArray<ERoamRoadClass>(Allowed);
			Out.Add(S);
		};
		//   id                    L    W    H   wb   r    track mass  vmax acc  dec  T    s0   weight  allowed classes (empty = all)
		Add(TEXT("traffic01_compact"), 410, 176, 148, 255, 31, 150, 1150, 130, 2.0f, 3.0f, 1.3f, 2.5f, 3.0f, {});
		Add(TEXT("traffic02_van"),     540, 205, 205, 340, 34, 170, 2200, 115, 1.6f, 3.0f, 1.5f, 3.0f, 1.4f, { ERoamRoadClass::Highway, ERoamRoadClass::Regional, ERoamRoadClass::Village, ERoamRoadClass::Mountain });
		Add(TEXT("traffic03_lorry"),   820, 250, 340, 480, 50, 200, 9000, 90,  1.0f, 2.5f, 1.9f, 4.0f, 0.8f, { ERoamRoadClass::Highway, ERoamRoadClass::Regional, ERoamRoadClass::Village });
		Add(TEXT("traffic04_bus"),    1200, 255, 330, 600, 50, 205, 12000, 90,  1.0f, 2.5f, 1.8f, 4.5f, 0.4f, { ERoamRoadClass::Highway, ERoamRoadClass::Regional, ERoamRoadClass::Village });
		Add(TEXT("traffic05_tractor"), 450, 220, 270, 260, 55, 170, 5000, 40,  0.8f, 2.0f, 2.0f, 3.5f, 1.2f, { ERoamRoadClass::Dirt, ERoamRoadClass::Shortcut, ERoamRoadClass::Village });
		Add(TEXT("traffic06_pickup"),  530, 200, 185, 320, 38, 170, 2100, 120, 1.8f, 3.0f, 1.5f, 3.0f, 1.6f, {});
	}
}

namespace
{
	void BezierPose(const FVector& P0, const FVector& D0, const FVector& P3, const FVector& D3, float T, FVector& OutPos, FVector& OutDir)
	{
		const double K = FVector::Dist(P0, P3) * 0.4;
		const FVector P1 = P0 + D0 * K;
		const FVector P2 = P3 - D3 * K;
		const double U = 1.0 - T;
		OutPos = P0 * (U * U * U) + P1 * (3.0 * U * U * T) + P2 * (3.0 * U * T * T) + P3 * (T * T * T);
		const FVector Deriv = (P1 - P0) * (3.0 * U * U) + (P2 - P1) * (6.0 * U * T) + (P3 - P2) * (3.0 * T * T);
		OutDir = Deriv.GetSafeNormal();
		if (OutDir.IsNearlyZero())
		{
			OutDir = D0;
		}
	}

	void BlendPose(const FRoamLane& From, const FRoamLane& To, float DistAlongConnector, FVector& OutPos, FVector& OutDir)
	{
		const float EntryS = From.LengthCm - From.BlendEndCm;
		FVector P0, D0, P3, D3;
		From.Sample(EntryS, P0, D0);
		To.Sample(To.BlendStartCm, P3, D3);
		const float Total = From.BlendEndCm + To.BlendStartCm;
		BezierPose(P0, D0, P3, D3, FMath::Clamp(DistAlongConnector / FMath::Max(Total, 1.0f), 0.0f, 1.0f), OutPos, OutDir);
	}
}

void FRoamTrafficSim::Init(const URoamRoadNetwork& Network, const TArray<FRoamTrafficVehicleSpec>& InTypes, int32 Seed)
{
	Clear();
	Graph.Build(Network);
	Types = InTypes;
	Rand.Initialize(Seed);
	Claims.Reset();
	Waiters.Reset();
	PrevWaiters.Reset();
	Time = 0.0;
}

void FRoamTrafficSim::Clear()
{
	for (const FRoamTrafficAgent& A : Agents)
	{
		RemovedIds.Add(A.Id);
	}
	NumRemovedTotal += Agents.Num();
	Agents.Reset();
	Claims.Reset();
	Waiters.Reset();
	PrevWaiters.Reset();
}

int32 FRoamTrafficSim::FindAgentIndex(int32 Id) const
{
	return Agents.IndexOfByPredicate([Id](const FRoamTrafficAgent& A) { return A.Id == Id; });
}

void FRoamTrafficSim::RemoveAgentAt(int32 Index)
{
	if (!Agents.IsValidIndex(Index))
	{
		return;
	}
	ReleaseClaim(Agents[Index]);
	RemovedIds.Add(Agents[Index].Id);
	++NumRemovedTotal;
	Agents.RemoveAtSwap(Index, EAllowShrinking::No);
}

int32 FRoamTrafficSim::RemoveFarAgents(const FVector& Center, float MaxDistanceCm)
{
	int32 Removed = 0;
	const double Max2 = static_cast<double>(MaxDistanceCm) * MaxDistanceCm;
	for (int32 i = Agents.Num() - 1; i >= 0; --i)
	{
		if (FVector::DistSquared2D(Agents[i].Pos, Center) > Max2)
		{
			RemoveAgentAt(i);
			++Removed;
		}
	}
	return Removed;
}

int32 FRoamTrafficSim::PickType(ERoamRoadClass RoadClass)
{
	float Total = 0.0f;
	for (const FRoamTrafficVehicleSpec& T : Types)
	{
		if (T.AllowedRoadClasses.Num() == 0 || T.AllowedRoadClasses.Contains(RoadClass))
		{
			Total += T.SpawnWeight;
		}
	}
	if (Total <= 0.0f)
	{
		return INDEX_NONE;
	}
	float Pick = Rand.FRand() * Total;
	for (int32 i = 0; i < Types.Num(); ++i)
	{
		const FRoamTrafficVehicleSpec& T = Types[i];
		if (T.AllowedRoadClasses.Num() == 0 || T.AllowedRoadClasses.Contains(RoadClass))
		{
			Pick -= T.SpawnWeight;
			if (Pick <= 0.0f)
			{
				return i;
			}
		}
	}
	return INDEX_NONE;
}

void FRoamTrafficSim::ChooseNextLane(FRoamTrafficAgent& A)
{
	A.NextLane = INDEX_NONE;
	const FRoamLane& L = Graph.Lanes[A.Lane];
	if (L.Successors.Num() == 0)
	{
		return;
	}
	float Total = 0.0f;
	for (const float W : L.SuccessorWeight)
	{
		Total += W;
	}
	float Pick = Rand.FRand() * Total;
	for (int32 i = 0; i < L.Successors.Num(); ++i)
	{
		Pick -= L.SuccessorWeight[i];
		if (Pick <= 0.0f)
		{
			A.NextLane = L.Successors[i];
			return;
		}
	}
	A.NextLane = L.Successors.Last();
}

int32 FRoamTrafficSim::SpawnAgent(int32 LaneId, float S, int32 TypeIndex, float SpeedFraction)
{
	if (!Graph.Lanes.IsValidIndex(LaneId) || !Types.IsValidIndex(TypeIndex))
	{
		return INDEX_NONE;
	}
	const FRoamLane& L = Graph.Lanes[LaneId];
	const FRoamTrafficVehicleSpec& T = Types[TypeIndex];
	FRoamTrafficAgent A;
	A.Id = NextAgentId++;
	A.TypeIndex = TypeIndex;
	A.Lane = LaneId;
	A.S = FMath::Clamp(S, 0.0f, L.LengthCm);
	A.LengthCm = T.LengthCm;
	A.WidthCm = T.WidthCm;
	A.MaxSpeedMs = T.MaxSpeedKmh / 3.6f;
	A.DesiredFactor = Rand.FRandRange(0.88f, 1.04f);
	A.AMax = T.AccelerationMs2 * Rand.FRandRange(0.9f, 1.1f);
	A.BComfort = T.ComfortDecelMs2;
	A.Headway = FMath::Clamp(T.TimeHeadwaySec * Rand.FRandRange(0.9f, 1.15f), 1.3f, 2.0f);
	A.MinGapM = FMath::Clamp(T.MinGapM * Rand.FRandRange(0.9f, 1.3f), 2.5f, 5.0f);
	A.V = FMath::Min(L.SpeedLimitMs, A.MaxSpeedMs) * SpeedFraction * 100.0f;
	ChooseNextLane(A);
	ComputePose(A, A.Pos, A.Dir);
	A.PrevYawRad = FMath::Atan2(static_cast<float>(A.Dir.Y), static_cast<float>(A.Dir.X));
	Agents.Add(A);
	++NumSpawnedTotal;
	return A.Id;
}

int32 FRoamTrafficSim::SpawnAround(const FVector& Center, float Density01, float TimeOfDayFactor, bool bInitialFill, int32 MaxNew, TFunctionRef<bool(const FVector&)> IsSuppressed)
{
	if (!IsReady() || Density01 <= 0.0f || Types.Num() == 0 || Agents.Num() >= RoamTraffic::MaxAgents)
	{
		return 0;
	}
	const float RingMin = bInitialFill ? 20000.0f : RoamTraffic::SpawnMinCm;
	const float RingMax = bInitialFill ? RoamTraffic::DataRingCm : RoamTraffic::SpawnMaxCm;
	const float AnnulusMin = bInitialFill ? RingMin : RoamTraffic::VisibleRingCm;

	Candidates.Reset();
	float CumWeight = 0.0f;
	float Expected = 0.0f;
	Graph.ForEachPointInRadius(Center, RoamTraffic::DataRingCm, [&](int32 LaneId, int32 Point, const FVector& P)
	{
		const float D = static_cast<float>(FVector::Dist2D(P, Center));
		if (D < AnnulusMin)
		{
			return;
		}
		const FRoamLane& L = Graph.Lanes[LaneId];
		const float Rate = RoamTraffic::BaseDensityPerKm(L.RoadClass) / static_cast<float>(L.LanesInDirection) * Density01 * TimeOfDayFactor;
		Expected += Rate * L.StepCm * 1.0e-5f;
		if (D >= RingMin && D <= RingMax)
		{
			CumWeight += Rate;
			FSpawnCandidate C;
			C.Lane = LaneId;
			C.Point = Point;
			C.CumWeight = CumWeight;
			Candidates.Add(C);
		}
	});

	int32 Current = 0;
	for (const FRoamTrafficAgent& A : Agents)
	{
		const float D = static_cast<float>(FVector::Dist2D(A.Pos, Center));
		if (D >= AnnulusMin && D <= RoamTraffic::DataRingCm)
		{
			++Current;
		}
	}
	const float Deficit = Expected - static_cast<float>(Current);
	if (Deficit <= 0.0f || Candidates.Num() == 0)
	{
		return 0;
	}
	int32 ToSpawn = FMath::FloorToInt(Deficit) + (Rand.FRand() < (Deficit - FMath::FloorToFloat(Deficit)) ? 1 : 0);
	ToSpawn = FMath::Min3(ToSpawn, MaxNew, RoamTraffic::MaxAgents - Agents.Num());

	int32 Spawned = 0;
	for (int32 Attempt = 0; Attempt < ToSpawn * 8 && Spawned < ToSpawn; ++Attempt)
	{
		const float Pick = Rand.FRand() * CumWeight;
		int32 Lo = 0;
		int32 Hi = Candidates.Num() - 1;
		while (Lo < Hi)
		{
			const int32 Mid = (Lo + Hi) / 2;
			if (Candidates[Mid].CumWeight < Pick)
			{
				Lo = Mid + 1;
			}
			else
			{
				Hi = Mid;
			}
		}
		const FSpawnCandidate& C = Candidates[Lo];
		const FRoamLane& L = Graph.Lanes[C.Lane];
		const float S = FMath::Min(static_cast<float>(C.Point) * L.StepCm, L.LengthCm);
		if (S < L.BlendStartCm + 800.0f || S > L.LengthCm - L.BlendEndCm - 1500.0f)
		{
			continue;
		}
		FVector P, D;
		L.Sample(S, P, D);
		if (IsSuppressed(P))
		{
			continue;
		}
		bool bFree = true;
		for (const FRoamTrafficAgent& O : Agents)
		{
			if (O.Lane == C.Lane && FMath::Abs(O.S - S) < 4500.0f)
			{
				bFree = false;
				break;
			}
		}
		if (!bFree)
		{
			continue;
		}
		const int32 Type = PickType(L.RoadClass);
		if (Type != INDEX_NONE && SpawnAgent(C.Lane, S, Type, Rand.FRandRange(0.7f, 0.95f)) != INDEX_NONE)
		{
			++Spawned;
		}
	}
	return Spawned;
}

void FRoamTrafficSim::ComputePose(const FRoamTrafficAgent& A, FVector& OutPos, FVector& OutDir) const
{
	const FRoamLane& L = Graph.Lanes[A.Lane];
	if (A.PrevLane != INDEX_NONE && A.S < L.BlendStartCm)
	{
		const FRoamLane& P = Graph.Lanes[A.PrevLane];
		if (P.BlendEndCm + L.BlendStartCm > 100.0f)
		{
			BlendPose(P, L, P.BlendEndCm + A.S, OutPos, OutDir);
			return;
		}
	}
	else if (A.NextLane != INDEX_NONE && A.S > L.LengthCm - L.BlendEndCm)
	{
		const FRoamLane& N = Graph.Lanes[A.NextLane];
		if (L.BlendEndCm + N.BlendStartCm > 100.0f)
		{
			BlendPose(L, N, A.S - (L.LengthCm - L.BlendEndCm), OutPos, OutDir);
			return;
		}
	}
	L.Sample(A.S, OutPos, OutDir);
}

bool FRoamTrafficSim::Compatible(const FClaim& A, const FClaim& B)
{
	if (A.ArmKey == B.ArmKey)
	{
		return true; // same approach: platoon
	}
	const bool bStraightA = FVector::DotProduct(A.Arrive, A.Exit) > 0.85;
	const bool bStraightB = FVector::DotProduct(B.Arrive, B.Exit) > 0.85;
	return bStraightA && bStraightB && FVector::DotProduct(A.Arrive, B.Arrive) < -0.85; // opposing straight flows
}

FRoamTrafficSim::FClaim FRoamTrafficSim::MakeClaim(const FRoamTrafficAgent& A, const FRoamLane& L) const
{
	FClaim C;
	C.Junction = L.EndJunction;
	C.AgentId = A.Id;
	C.ArmKey = L.ArmKey;
	C.Priority = L.EndArmPriority;
	C.Wait = A.WaitTime;
	C.Arrive = FVector(L.Dirs.Last().X, L.Dirs.Last().Y, 0.0).GetSafeNormal();
	C.Exit = C.Arrive;
	if (A.NextLane != INDEX_NONE)
	{
		const FVector& D = Graph.Lanes[A.NextLane].Dirs[0];
		C.Exit = FVector(D.X, D.Y, 0.0).GetSafeNormal();
	}
	return C;
}

bool FRoamTrafficSim::TryAcquire(FRoamTrafficAgent& A, float GapLineCm, const FRoamLane& L, const FRoamTrafficPlayer& Player)
{
	const int32 J = L.EndJunction;
	if (Graph.JunctionControl[J] == ERoamJunctionControl::Stop && !(A.V < 40.0f && GapLineCm < 700.0f && A.StopTimer > 1.0f))
	{
		return false;
	}
	FClaim Mine = MakeClaim(A, L);
	Mine.Eta = GapLineCm / FMath::Max(A.V, 200.0f);
	for (const FClaim& H : Claims)
	{
		if (H.Junction == J && H.AgentId != A.Id && !Compatible(H, Mine))
		{
			return false;
		}
	}
	if (Player.bValid && A.WaitTime < 15.0f && FVector::Dist2D(Player.Location, Graph.JunctionPos[J]) < Graph.JunctionRadius[J] + 300.0f)
	{
		return false; // the player is crossing
	}
	for (const FClaim& W : PrevWaiters)
	{
		if (W.Junction != J || W.AgentId == A.Id || Compatible(W, Mine))
		{
			continue;
		}
		if (W.Priority > Mine.Priority)
		{
			return false;
		}
		if (W.Priority == Mine.Priority)
		{
			const float DWait = W.Wait - Mine.Wait;
			if (DWait > 0.5f)
			{
				return false;
			}
			if (DWait >= -0.5f && (W.Eta < Mine.Eta - 0.3f || (FMath::Abs(W.Eta - Mine.Eta) <= 0.3f && W.AgentId < Mine.AgentId)))
			{
				return false;
			}
		}
	}
	Mine.AcquireTime = Time;
	Claims.Add(Mine);
	A.HoldJunction = J;
	A.HoldApproachLane = A.Lane;
	A.HoldTime = 0.0f;
	return true;
}

void FRoamTrafficSim::ReleaseClaim(FRoamTrafficAgent& A)
{
	if (A.HoldJunction != INDEX_NONE)
	{
		const int32 Id = A.Id;
		Claims.RemoveAll([Id](const FClaim& C) { return C.AgentId == Id; });
		A.HoldJunction = INDEX_NONE;
		A.HoldApproachLane = INDEX_NONE;
	}
}

int32 FRoamTrafficSim::CountConflictingClaims() const
{
	int32 Count = 0;
	for (int32 i = 0; i < Claims.Num(); ++i)
	{
		for (int32 j = i + 1; j < Claims.Num(); ++j)
		{
			if (Claims[i].Junction == Claims[j].Junction && Claims[i].AgentId != Claims[j].AgentId && !Compatible(Claims[i], Claims[j]))
			{
				++Count;
			}
		}
	}
	return Count;
}

void FRoamTrafficSim::Step(float DtIn, const FRoamTrafficPlayer& Player, float SpeedScale)
{
	const float Dt = FMath::Clamp(DtIn, 0.0f, 0.1f);
	if (Dt <= 0.0f)
	{
		return;
	}
	Time += Dt;
	const int32 N = Agents.Num();
	if (N == 0)
	{
		return;
	}

	Order.SetNumUninitialized(N);
	for (int32 i = 0; i < N; ++i)
	{
		Order[i] = i;
	}
	Order.Sort([this](int32 X, int32 Y)
	{
		const FRoamTrafficAgent& AX = Agents[X];
		const FRoamTrafficAgent& AY = Agents[Y];
		return AX.Lane != AY.Lane ? AX.Lane < AY.Lane : AX.S < AY.S;
	});
	OrderPos.SetNumUninitialized(N);
	LaneFirst.Reset();
	for (int32 P = 0; P < N; ++P)
	{
		OrderPos[Order[P]] = P;
		if (P == 0 || Agents[Order[P - 1]].Lane != Agents[Order[P]].Lane)
		{
			LaneFirst.Add(Agents[Order[P]].Lane, P);
		}
	}
	Swap(Waiters, PrevWaiters);
	Waiters.Reset();

	for (int32 i = 0; i < N; ++i)
	{
		FRoamTrafficAgent& A = Agents[i];
		A.Age += Dt;
		A.StateTime += Dt;
		A.HornCooldown = FMath::Max(0.0f, A.HornCooldown - Dt);
		A.NearMissCooldown = FMath::Max(0.0f, A.NearMissCooldown - Dt);
		if (A.State != ERoamTrafficAgentState::Driving)
		{
			A.V = 0.0f;
			A.Accel = 0.0f;
			ReleaseClaim(A);
			continue;
		}
		StepDriving(i, Dt, Player, SpeedScale);
	}
}

void FRoamTrafficSim::StepDriving(int32 Index, float Dt, const FRoamTrafficPlayer& Player, float SpeedScale)
{
	FRoamTrafficAgent& A = Agents[Index];
	const FRoamLane& L = Graph.Lanes[A.Lane];
	const float HalfLen = A.LengthCm * 0.5f;
	const float VMs = A.V * 0.01f;
	const int32 N = Agents.Num();

	// ---- desired speed: limit, vehicle, curvature ahead, junction turn -----------------------------------------------------
	float V0 = FMath::Min(L.SpeedLimitMs * A.DesiredFactor * SpeedScale, A.MaxSpeedMs);
	const float LatAcc = (L.Surface == ERoamSurface::Asphalt ? 3.0f : 2.0f) * (SpeedScale < 1.0f ? 0.8f : 1.0f);
	const float LookCm = FMath::Clamp(VMs * VMs / (2.0f * A.BComfort) * 100.0f + 3000.0f, 3000.0f, 15000.0f);
	for (float D = 0.0f; D <= LookCm; D += L.StepCm)
	{
		const float Sx = A.S + D;
		if (Sx > L.LengthCm)
		{
			break;
		}
		const float KappaPerM = L.CurvatureAt(Sx) * 100.0f;
		if (KappaPerM > 0.002f)
		{
			const float VCurve = FMath::Sqrt(LatAcc / KappaPerM);
			V0 = FMath::Min(V0, FMath::Sqrt(VCurve * VCurve + 2.0f * A.BComfort * D * 0.01f));
		}
	}
	if (A.NextLane != INDEX_NONE)
	{
		const int32 SuccIdx = L.Successors.Find(A.NextLane);
		if (SuccIdx != INDEX_NONE && L.SuccessorTurnRad[SuccIdx] > 0.3f)
		{
			const float VTurn = FMath::Lerp(V0, 5.5f, FMath::Clamp((L.SuccessorTurnRad[SuccIdx] - 0.3f) / 1.2f, 0.0f, 1.0f));
			const float D = FMath::Max(0.0f, L.LengthCm - A.S - L.BlendEndCm) * 0.01f;
			V0 = FMath::Min(V0, FMath::Sqrt(VTurn * VTurn + 2.0f * A.BComfort * D));
		}
	}

	// ---- constraints: leader (same lane / next lane), player, stop line, dead end -------------------------------------------
	float Acc = RoamTraffic::IdmAcceleration(VMs, V0, 1.0e6f, 0.0f, A.AMax, A.BComfort, A.Headway, A.MinGapM);
	float MinGapCm = 1.0e9f;
	float HardGapCm = 1.0e9f;
	float HardLeaderV = 0.0f;
	bool bPlayerBinding = false;
	auto Consider = [&](float GapCm, float LeaderVCms, bool bReal, bool bPlayer)
	{
		const float A2 = RoamTraffic::IdmAcceleration(VMs, V0, GapCm * 0.01f, VMs - LeaderVCms * 0.01f, A.AMax, A.BComfort, A.Headway, A.MinGapM);
		if (A2 < Acc)
		{
			Acc = A2;
			bPlayerBinding = bPlayer;
		}
		MinGapCm = FMath::Min(MinGapCm, GapCm);
		if (bReal && GapCm < HardGapCm)
		{
			HardGapCm = GapCm;
			HardLeaderV = LeaderVCms;
		}
	};

	const int32 P = OrderPos[Index];
	for (int32 Q = P + 1; Q < N; ++Q)
	{
		const FRoamTrafficAgent& B = Agents[Order[Q]];
		if (B.Lane != A.Lane)
		{
			break;
		}
		if (B.bBlocksLane)
		{
			Consider((B.S - B.LengthCm * 0.5f) - (A.S + HalfLen), B.V, true, false);
			break;
		}
	}
	if (MinGapCm > 1.0e8f && A.NextLane != INDEX_NONE)
	{
		if (const int32* First = LaneFirst.Find(A.NextLane))
		{
			for (int32 Q = *First; Q < N; ++Q)
			{
				const FRoamTrafficAgent& B = Agents[Order[Q]];
				if (B.Lane != A.NextLane)
				{
					break;
				}
				if (B.bBlocksLane)
				{
					Consider((L.LengthCm - A.S - HalfLen) + (B.S - B.LengthCm * 0.5f), B.V, true, false);
					break;
				}
			}
		}
	}
	if (Player.bValid)
	{
		const FVector Dir2 = FVector(A.Dir.X, A.Dir.Y, 0.0).GetSafeNormal();
		const FVector Rel = Player.Location - A.Pos;
		const float Along = static_cast<float>(Rel.X * Dir2.X + Rel.Y * Dir2.Y);
		const float Lat = static_cast<float>(-Rel.X * Dir2.Y + Rel.Y * Dir2.X);
		if (Along > 0.0f && Along < 10000.0f + HalfLen && FMath::Abs(Lat) < A.WidthCm * 0.5f + Player.HalfWidthCm + 60.0f && FMath::Abs(Rel.Z) < 300.0)
		{
			const float VPlayer = static_cast<float>(Player.Velocity.X * Dir2.X + Player.Velocity.Y * Dir2.Y);
			Consider(Along - HalfLen - Player.HalfLengthCm, VPlayer, true, true);
		}
	}

	if (L.EndJunction == INDEX_NONE)
	{
		Consider((L.LengthCm - 300.0f) - (A.S + HalfLen), 0.0f, false, false); // dead end
	}
	else
	{
		const float StopOffset = FMath::Min(L.BlendEndCm + 150.0f, L.LengthCm * 0.45f);
		const float GapLine = (L.LengthCm - StopOffset) - (A.S + HalfLen);
		if (A.HoldJunction != L.EndJunction && GapLine < FMath::Max(3500.0f, A.V * 6.0f))
		{
			if (A.V < 30.0f && GapLine < 700.0f)
			{
				A.StopTimer += Dt;
			}
			else if (A.V >= 30.0f)
			{
				A.StopTimer = 0.0f;
			}
			bool bGranted = false;
			if (GapLine < -150.0f)
			{
				// already past the line (spawned / released late): claim without waiting so others see the vehicle
				FClaim Forced = MakeClaim(A, L);
				Forced.AcquireTime = Time;
				Claims.Add(Forced);
				A.HoldJunction = L.EndJunction;
				A.HoldApproachLane = A.Lane;
				A.HoldTime = 0.0f;
				bGranted = true;
			}
			else
			{
				bGranted = TryAcquire(A, GapLine, L, Player);
			}
			if (!bGranted)
			{
				FClaim W = MakeClaim(A, L);
				W.Eta = GapLine / FMath::Max(A.V, 200.0f);
				Waiters.Add(W);
				Consider(GapLine, 0.0f, false, false);
				if (A.V < 40.0f)
				{
					A.WaitTime += Dt;
				}
			}
		}
	}

	// ---- integrate --------------------------------------------------------------------------------------------------------
	Acc = FMath::Clamp(Acc, -9.0f, A.AMax);
	A.Accel = Acc;
	float NewV = A.V + Acc * 100.0f * Dt;
	float Ds;
	if (NewV < 0.0f)
	{
		Ds = A.V * A.V / (2.0f * FMath::Max(FMath::Abs(Acc) * 100.0f, 1.0f));
		NewV = 0.0f;
	}
	else
	{
		Ds = (A.V + NewV) * 0.5f * Dt;
	}
	if (HardGapCm < 1.0e8f)
	{
		const float MaxDs = FMath::Max(0.0f, HardGapCm - 30.0f);
		if (Ds > MaxDs)
		{
			Ds = MaxDs;
			NewV = FMath::Min(NewV, FMath::Max(HardLeaderV, 0.0f));
		}
	}
	A.S += Ds;
	A.V = NewV;
	A.bBraking = Acc < -0.8f || (A.V < 50.0f && MinGapCm < 1500.0f);

	// horn at a player who blocks the lane
	if (bPlayerBinding && A.V < 50.0f && MinGapCm < 1200.0f)
	{
		A.BlockedByPlayerTime += Dt;
		if (A.BlockedByPlayerTime > 2.0f && A.HornCooldown <= 0.0f)
		{
			A.bWantsHorn = true;
			A.HornCooldown = 8.0f;
		}
	}
	else
	{
		A.BlockedByPlayerTime = 0.0f;
	}

	// ---- lane transitions ---------------------------------------------------------------------------------------------------
	for (int32 Guard = 0; Guard < 4; ++Guard)
	{
		const FRoamLane& Cur = Graph.Lanes[A.Lane];
		if (A.S < Cur.LengthCm)
		{
			break;
		}
		if (A.NextLane == INDEX_NONE)
		{
			A.S = Cur.LengthCm - 1.0f;
			A.V = 0.0f;
			break;
		}
		A.S -= Cur.LengthCm;
		A.PrevLane = A.Lane;
		A.Lane = A.NextLane;
		ChooseNextLane(A);
	}
	if (A.PrevLane != INDEX_NONE && A.S > Graph.Lanes[A.Lane].BlendStartCm + HalfLen)
	{
		A.PrevLane = INDEX_NONE;
	}

	// ---- token release --------------------------------------------------------------------------------------------------------
	if (A.HoldJunction != INDEX_NONE)
	{
		A.HoldTime += Dt;
		if ((A.Lane != A.HoldApproachLane && A.PrevLane == INDEX_NONE) || A.HoldTime > 30.0f)
		{
			ReleaseClaim(A);
			A.WaitTime = 0.0f;
			A.StopTimer = 0.0f;
		}
	}

	// ---- pose ----------------------------------------------------------------------------------------------------------------
	ComputePose(A, A.Pos, A.Dir);
	const float Yaw = FMath::Atan2(static_cast<float>(A.Dir.Y), static_cast<float>(A.Dir.X));
	A.YawRateRad = FMath::Lerp(A.YawRateRad, FMath::FindDeltaAngleRadians(A.PrevYawRad, Yaw) / Dt, 0.3f);
	A.PrevYawRad = Yaw;
}

bool FRoamTrafficSim::MakeCollisionContact(int32 AgentIndex, const FRoamTrafficPlayer& Player, FRoamTrafficContact& Out) const
{
	if (!Agents.IsValidIndex(AgentIndex))
	{
		return false;
	}
	const FRoamTrafficAgent& A = Agents[AgentIndex];
	const FVector& PlayerVel = Player.Velocity.SizeSquared2D() >= Player.PrevVelocity.SizeSquared2D() ? Player.Velocity : Player.PrevVelocity;
	const FVector AgentVel = A.Dir * A.V;
	const float RelSpeed = static_cast<float>(FMath::Max((Player.Velocity - AgentVel).Size2D(), (Player.PrevVelocity - AgentVel).Size2D()));
	if (RelSpeed <= RoamTraffic::HitSpeedThresholdCms)
	{
		return false;
	}
	const FVector Rel = A.Pos - Player.Location;
	const float Mp = Player.MassKg;
	const float Ma = Types.IsValidIndex(A.TypeIndex) ? Types[A.TypeIndex].MassKg : 1200.0f;
	const float E = 0.25f;
	FVector VNew = (PlayerVel * (Mp * (1.0f + E)) + AgentVel * (Ma - E * Mp)) / (Ma + Mp);
	if (VNew.Size() > 4000.0)
	{
		VNew = VNew.GetSafeNormal() * 4000.0;
	}
	VNew.Z = FMath::Clamp(RelSpeed * 0.08f, 0.0f, 250.0f);
	Out.AgentIndex = AgentIndex;
	Out.bCollision = true;
	Out.ClosingKmh = RelSpeed * 0.036f;
	Out.ImpactSpeedMs = RelSpeed * 0.01f;
	Out.AgentVelocityAfterCms = VNew;
	const float Cross = static_cast<float>(Rel.X * PlayerVel.Y - Rel.Y * PlayerVel.X);
	Out.YawKickDegS = FMath::Clamp(Cross / static_cast<float>(Rel.SizeSquared2D() + 1.0) * 57.3f * 0.35f, -200.0f, 200.0f);
	return true;
}

void FRoamTrafficSim::CollectPlayerContacts(const FRoamTrafficPlayer& Player, TArray<FRoamTrafficContact>& Out) const
{
	Out.Reset();
	if (!Player.bValid)
	{
		return;
	}
	const FVector PlayerDir = FVector(Player.Forward.X, Player.Forward.Y, 0.0).GetSafeNormal();
	const FVector& PlayerVel = Player.Velocity.SizeSquared2D() >= Player.PrevVelocity.SizeSquared2D() ? Player.Velocity : Player.PrevVelocity;
	for (int32 i = 0; i < Agents.Num(); ++i)
	{
		const FRoamTrafficAgent& A = Agents[i];
		if (A.State != ERoamTrafficAgentState::Driving)
		{
			continue;
		}
		const FVector Rel = A.Pos - Player.Location;
		if (Rel.SizeSquared2D() > 3000.0 * 3000.0 || FMath::Abs(Rel.Z) > 300.0)
		{
			continue;
		}
		const FVector AgentVel = A.Dir * A.V;
		const float RelSpeed = static_cast<float>(FMath::Max((Player.Velocity - AgentVel).Size2D(), (Player.PrevVelocity - AgentVel).Size2D()));
		const float HalfLen = A.LengthCm * 0.5f;
		const float HalfWid = A.WidthCm * 0.5f;
		FRoamTrafficContact C;
		C.AgentIndex = i;
		C.ClosingKmh = RelSpeed * 0.036f;
		if (RoamTraffic::OverlapOrientedBoxes2D(A.Pos, A.Dir, HalfLen, HalfWid, Player.Location, PlayerDir, Player.HalfLengthCm, Player.HalfWidthCm, 40.0f))
		{
			if (MakeCollisionContact(i, Player, C))
			{
				Out.Add(C);
			}
			continue;
		}
		if (A.NearMissCooldown > 0.0f || C.ClosingKmh < 40.0f)
		{
			continue;
		}
		static const float Margins[4] = { 30.0f, 60.0f, 100.0f, 150.0f };
		for (const float M : Margins)
		{
			if (RoamTraffic::OverlapOrientedBoxes2D(A.Pos, A.Dir, HalfLen, HalfWid, Player.Location, PlayerDir, Player.HalfLengthCm, Player.HalfWidthCm, M + 40.0f))
			{
				C.GapCm = M;
				Out.Add(C);
				break;
			}
		}
	}
}

void FRoamTrafficSim::ApplyHit(int32 AgentIndex)
{
	if (!Agents.IsValidIndex(AgentIndex))
	{
		return;
	}
	FRoamTrafficAgent& A = Agents[AgentIndex];
	A.State = ERoamTrafficAgentState::Hit;
	A.StateTime = 0.0f;
	A.V = 0.0f;
	A.Accel = 0.0f;
	A.bBraking = false;
	ReleaseClaim(A);
}

void FRoamTrafficSim::SettleAgent(int32 AgentIndex, bool bBlocksLane)
{
	if (!Agents.IsValidIndex(AgentIndex))
	{
		return;
	}
	FRoamTrafficAgent& A = Agents[AgentIndex];
	A.State = ERoamTrafficAgentState::Obstacle;
	A.StateTime = 0.0f;
	A.bBlocksLane = bBlocksLane;
}
