// Copyright Epic Games, Inc. All Rights Reserved.

#include "Data/RoamRoadNetwork.h"

#include "Core/RoamLog.h"

namespace
{
	/** Right-hand side vector of a road at a tangent and banking angle (positive bank = right side lower). */
	FVector ComputeRight(const FVector& Tangent, float BankDeg)
	{
		FVector Right = FVector::CrossProduct(FVector::UpVector, Tangent);
		if (!Right.Normalize())
		{
			Right = FVector::RightVector;
		}
		if (!FMath::IsNearlyZero(BankDeg))
		{
			Right = Right.RotateAngleAxis(-BankDeg, Tangent); // positive bank lowers the right side
		}
		return Right;
	}

	/** Finds i such that Samples[i].S <= S <= Samples[i+1].S (clamped); returns segment index and the interpolation alpha. */
	int32 FindSegmentByS(const FRoamRoad& Road, float S, float& OutAlpha)
	{
		const int32 NumSamples = Road.Samples.Num();
		if (NumSamples < 2)
		{
			OutAlpha = 0.0f;
			return INDEX_NONE;
		}
		const float Clamped = FMath::Clamp(S, 0.0f, Road.Samples.Last().S);
		int32 Low = 0;
		int32 High = NumSamples - 1;
		while (High - Low > 1)
		{
			const int32 Mid = (Low + High) / 2;
			if (Road.Samples[Mid].S <= Clamped)
			{
				Low = Mid;
			}
			else
			{
				High = Mid;
			}
		}
		const float S0 = Road.Samples[Low].S;
		const float S1 = Road.Samples[Low + 1].S;
		OutAlpha = (S1 > S0) ? FMath::Clamp((Clamped - S0) / (S1 - S0), 0.0f, 1.0f) : 0.0f;
		return Low;
	}

	FRoamRouteLeg MakeLeg(const TArray<FRoamRoad>& Roads, int32 RoadIndex, float FromS, float ToS)
	{
		FRoamRouteLeg Leg;
		Leg.RoadIndex = RoadIndex;
		Leg.RoadId = Roads[RoadIndex].RoadId;
		Leg.FromS = FromS;
		Leg.ToS = ToS;
		return Leg;
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------------------------------------------------------

void URoamRoadNetwork::PostLoad()
{
	Super::PostLoad();
	BuildSpatialIndex();
}

#if WITH_EDITOR
void URoamRoadNetwork::PostEditChangeProperty(FPropertyChangedEvent& PropertyChangedEvent)
{
	Super::PostEditChangeProperty(PropertyChangedEvent);
	BuildSpatialIndex();
}
#endif

FIntPoint URoamRoadNetwork::CellOf(const FVector& Location) const
{
	const float Cell = FMath::Max(GridCellSizeCm, 1000.0f);
	return FIntPoint(FMath::FloorToInt(Location.X / Cell), FMath::FloorToInt(Location.Y / Cell));
}

void URoamRoadNetwork::BuildSpatialIndex()
{
	bIndexBuilt = false;
	RoadIndexById.Reset();
	JunctionIndexById.Reset();
	Grid.Reset();
	Adjacency.Reset();

	// Roads: lengths, tangents, lookup, grid.
	for (int32 RoadIdx = 0; RoadIdx < Roads.Num(); ++RoadIdx)
	{
		FRoamRoad& Road = Roads[RoadIdx];
		if (!Road.RoadId.IsNone())
		{
			if (RoadIndexById.Contains(Road.RoadId))
			{
				UE_LOG(LogRoamWorld, Warning, TEXT("RoadNetwork: duplicate road id %s"), *Road.RoadId.ToString());
			}
			RoadIndexById.Add(Road.RoadId, RoadIdx);
		}

		const int32 NumSamples = Road.Samples.Num();
		Road.LengthCm = 0.0f;
		if (NumSamples < 2)
		{
			continue;
		}
		float Cumulative = 0.0f;
		Road.Samples[0].S = 0.0f;
		for (int32 i = 1; i < NumSamples; ++i)
		{
			Cumulative += static_cast<float>(FVector::Dist(Road.Samples[i - 1].Position, Road.Samples[i].Position));
			Road.Samples[i].S = Cumulative;
		}
		Road.LengthCm = Cumulative;
		for (int32 i = 0; i < NumSamples; ++i)
		{
			FRoamRoadSample& Sample = Road.Samples[i];
			if (!Sample.Tangent.Normalize())
			{
				const FVector& Prev = Road.Samples[FMath::Max(i - 1, 0)].Position;
				const FVector& Next = Road.Samples[FMath::Min(i + 1, NumSamples - 1)].Position;
				Sample.Tangent = (Next - Prev).GetSafeNormal();
				if (Sample.Tangent.IsNearlyZero())
				{
					Sample.Tangent = FVector::ForwardVector;
				}
			}
		}

		for (int32 Seg = 0; Seg < NumSamples - 1; ++Seg)
		{
			const FVector& A = Road.Samples[Seg].Position;
			const FVector& B = Road.Samples[Seg + 1].Position;
			const FIntPoint CellA = CellOf(A);
			const FIntPoint CellB = CellOf(B);
			const FIntPoint Min(FMath::Min(CellA.X, CellB.X), FMath::Min(CellA.Y, CellB.Y));
			const FIntPoint Max(FMath::Max(CellA.X, CellB.X), FMath::Max(CellA.Y, CellB.Y));
			for (int32 Y = Min.Y; Y <= Max.Y; ++Y)
			{
				for (int32 X = Min.X; X <= Max.X; ++X)
				{
					Grid.FindOrAdd(FIntPoint(X, Y)).Add({ RoadIdx, Seg });
				}
			}
		}
	}

	// Junctions: lookup + adjacency (graph edges are whole roads).
	for (int32 JunctionIdx = 0; JunctionIdx < Junctions.Num(); ++JunctionIdx)
	{
		if (!Junctions[JunctionIdx].JunctionId.IsNone())
		{
			JunctionIndexById.Add(Junctions[JunctionIdx].JunctionId, JunctionIdx);
		}
	}
	Adjacency.SetNum(Junctions.Num());
	for (int32 RoadIdx = 0; RoadIdx < Roads.Num(); ++RoadIdx)
	{
		const FRoamRoad& Road = Roads[RoadIdx];
		const int32* StartJ = JunctionIndexById.Find(Road.StartJunction);
		const int32* EndJ = JunctionIndexById.Find(Road.EndJunction);
		if (!StartJ || !EndJ || Road.LengthCm <= 0.0f)
		{
			continue;
		}
		const float Cost = Road.LengthCm * GetRouteCostFactor(Road.RoadClass);
		Adjacency[*StartJ].Add({ *EndJ, RoadIdx, true, Road.LengthCm, Cost });
		if (!Road.bOneWay)
		{
			Adjacency[*EndJ].Add({ *StartJ, RoadIdx, false, Road.LengthCm, Cost });
		}
	}

	bIndexBuilt = true;
}

// ------------------------------------------------------------------------------------------------------------------
// Lookup
// ------------------------------------------------------------------------------------------------------------------

int32 URoamRoadNetwork::FindRoadIndex(FName RoadId) const
{
	const int32* Found = RoadIndexById.Find(RoadId);
	if (Found)
	{
		return *Found;
	}
	// Index not built (asset edited in code without BuildSpatialIndex): linear fallback.
	return Roads.IndexOfByPredicate([RoadId](const FRoamRoad& R) { return R.RoadId == RoadId; });
}

int32 URoamRoadNetwork::FindJunctionIndex(FName JunctionId) const
{
	const int32* Found = JunctionIndexById.Find(JunctionId);
	if (Found)
	{
		return *Found;
	}
	return Junctions.IndexOfByPredicate([JunctionId](const FRoamJunction& J) { return J.JunctionId == JunctionId; });
}

const FRoamRoad* URoamRoadNetwork::FindRoad(FName RoadId) const
{
	const int32 Index = FindRoadIndex(RoadId);
	return Roads.IsValidIndex(Index) ? &Roads[Index] : nullptr;
}

const FRoamJunction* URoamRoadNetwork::FindJunction(FName JunctionId) const
{
	const int32 Index = FindJunctionIndex(JunctionId);
	return Junctions.IsValidIndex(Index) ? &Junctions[Index] : nullptr;
}

float URoamRoadNetwork::GetTotalLengthCm() const
{
	float Total = 0.0f;
	for (const FRoamRoad& Road : Roads)
	{
		Total += Road.LengthCm;
	}
	return Total;
}

// ------------------------------------------------------------------------------------------------------------------
// Queries
// ------------------------------------------------------------------------------------------------------------------

void URoamRoadNetwork::FillHit(int32 RoadIndex, int32 SegmentIndex, float Alpha, const FVector& QueryLocation, FRoamRoadHit& OutHit) const
{
	const FRoamRoad& Road = Roads[RoadIndex];
	const FRoamRoadSample& A = Road.Samples[SegmentIndex];
	const FRoamRoadSample& B = Road.Samples[SegmentIndex + 1];

	OutHit.bValid = true;
	OutHit.RoadId = Road.RoadId;
	OutHit.RoadIndex = RoadIndex;
	OutHit.S = FMath::Lerp(A.S, B.S, Alpha);
	OutHit.Position = FMath::Lerp(A.Position, B.Position, static_cast<double>(Alpha));
	FVector Tangent = FMath::Lerp(A.Tangent, B.Tangent, static_cast<double>(Alpha)).GetSafeNormal();
	if (Tangent.IsNearlyZero())
	{
		Tangent = (B.Position - A.Position).GetSafeNormal();
	}
	OutHit.Tangent = Tangent;
	OutHit.BankDeg = FMath::Lerp(A.BankDeg, B.BankDeg, Alpha);
	OutHit.Right = ComputeRight(Tangent, OutHit.BankDeg);
	OutHit.Surface = Road.Surface;
	OutHit.RoadClass = Road.RoadClass;
	OutHit.WidthCm = FMath::Lerp(A.WidthCm, B.WidthCm, Alpha);
	OutHit.SpeedLimitKmh = Road.SpeedLimitKmh;
	OutHit.Flags = (Alpha < 0.5f) ? A.Flags : B.Flags;
	OutHit.DistanceCm = static_cast<float>(FVector::Dist(QueryLocation, OutHit.Position));
	OutHit.LateralCm = static_cast<float>(FVector::DotProduct(QueryLocation - OutHit.Position, OutHit.Right));
}

void URoamRoadNetwork::TestSegment(int32 RoadIndex, int32 SegmentIndex, const FRoamRoadQuery& Query, float& InOutBestScore, FRoamRoadHit& OutHit, bool& bFound) const
{
	const FRoamRoad& Road = Roads[RoadIndex];
	if (((Query.ClassMask >> static_cast<int32>(Road.RoadClass)) & 1) == 0)
	{
		return;
	}
	const FVector& A = Road.Samples[SegmentIndex].Position;
	const FVector& B = Road.Samples[SegmentIndex + 1].Position;
	const FVector AB = B - A;
	const double LenSq = AB.SizeSquared();
	const double T = (LenSq > UE_DOUBLE_SMALL_NUMBER) ? FMath::Clamp(FVector::DotProduct(Query.Location - A, AB) / LenSq, 0.0, 1.0) : 0.0;
	const FVector Closest = A + AB * T;

	if (Query.MaxVerticalCm > 0.0f && FMath::Abs(Query.Location.Z - Closest.Z) > Query.MaxVerticalCm)
	{
		return;
	}
	const float Distance = static_cast<float>(FVector::Dist(Query.Location, Closest));
	if (Distance > Query.MaxDistanceCm)
	{
		return;
	}

	float Score = Distance;
	if (!Query.Heading.IsNearlyZero())
	{
		// Penalise roads that cross the direction of travel (junction approaches, overpasses): up to 3 m.
		const FVector SegDir = AB.GetSafeNormal();
		Score += 300.0f * (1.0f - FMath::Abs(static_cast<float>(FVector::DotProduct(SegDir, Query.Heading.GetSafeNormal()))));
	}
	if (!Query.PreferRoadId.IsNone() && Road.RoadId == Query.PreferRoadId)
	{
		Score -= 100.0f;
	}
	if (!bFound || Score < InOutBestScore)
	{
		InOutBestScore = Score;
		bFound = true;
		FillHit(RoadIndex, SegmentIndex, static_cast<float>(T), Query.Location, OutHit);
	}
}

bool URoamRoadNetwork::FindNearest(const FRoamRoadQuery& Query, FRoamRoadHit& OutHit) const
{
	OutHit = FRoamRoadHit();
	if (Roads.Num() == 0)
	{
		return false;
	}
	if (!bIndexBuilt)
	{
		const_cast<URoamRoadNetwork*>(this)->BuildSpatialIndex();
	}

	const float Cell = FMath::Max(GridCellSizeCm, 1000.0f);
	const FIntPoint Centre = CellOf(Query.Location);
	const int32 MaxRing = FMath::CeilToInt(Query.MaxDistanceCm / Cell) + 1;

	bool bFound = false;
	float BestScore = TNumericLimits<float>::Max();
	for (int32 Ring = 0; Ring <= MaxRing; ++Ring)
	{
		for (int32 DY = -Ring; DY <= Ring; ++DY)
		{
			for (int32 DX = -Ring; DX <= Ring; ++DX)
			{
				if (FMath::Max(FMath::Abs(DX), FMath::Abs(DY)) != Ring)
				{
					continue;
				}
				if (const TArray<FGridEntry>* Entries = Grid.Find(FIntPoint(Centre.X + DX, Centre.Y + DY)))
				{
					for (const FGridEntry& Entry : *Entries)
					{
						TestSegment(Entry.RoadIndex, Entry.SegmentIndex, Query, BestScore, OutHit, bFound);
					}
				}
			}
		}
		// Anything in an unvisited ring is at least Ring * Cell away, so the best score cannot improve any more.
		if (bFound && BestScore <= static_cast<float>(Ring) * Cell)
		{
			break;
		}
	}
	return bFound;
}

bool URoamRoadNetwork::FindNearestRoad(FVector Location, FRoamRoadHit& OutHit, int32 ClassMask, float MaxDistanceCm) const
{
	FRoamRoadQuery Query;
	Query.Location = Location;
	Query.ClassMask = ClassMask;
	Query.MaxDistanceCm = MaxDistanceCm;
	return FindNearest(Query, OutHit);
}

bool URoamRoadNetwork::FindNearestOnRoad(int32 RoadIndex, const FVector& Location, float HintS, float WindowCm, FRoamRoadHit& OutHit) const
{
	OutHit = FRoamRoadHit();
	if (!Roads.IsValidIndex(RoadIndex) || Roads[RoadIndex].Samples.Num() < 2)
	{
		return false;
	}
	const FRoamRoad& Road = Roads[RoadIndex];
	int32 FirstSeg = 0;
	int32 LastSeg = Road.Samples.Num() - 2;
	if (HintS >= 0.0f && WindowCm > 0.0f)
	{
		float Alpha = 0.0f;
		FirstSeg = FMath::Max(0, FindSegmentByS(Road, HintS - WindowCm, Alpha));
		LastSeg = FMath::Min(LastSeg, FindSegmentByS(Road, HintS + WindowCm, Alpha));
	}

	FRoamRoadQuery Query;
	Query.Location = Location;
	Query.MaxDistanceCm = TNumericLimits<float>::Max();
	bool bFound = false;
	float BestScore = TNumericLimits<float>::Max();
	for (int32 Seg = FirstSeg; Seg <= LastSeg; ++Seg)
	{
		TestSegment(RoadIndex, Seg, Query, BestScore, OutHit, bFound);
	}
	return bFound;
}

bool URoamRoadNetwork::SamplePositionByIndex(int32 RoadIndex, float S, FRoamRoadHit& OutHit) const
{
	OutHit = FRoamRoadHit();
	if (!Roads.IsValidIndex(RoadIndex))
	{
		return false;
	}
	float Alpha = 0.0f;
	const int32 Seg = FindSegmentByS(Roads[RoadIndex], S, Alpha);
	if (Seg == INDEX_NONE)
	{
		return false;
	}
	const FRoamRoad& Road = Roads[RoadIndex];
	const FVector Position = FMath::Lerp(Road.Samples[Seg].Position, Road.Samples[Seg + 1].Position, static_cast<double>(Alpha));
	FillHit(RoadIndex, Seg, Alpha, Position, OutHit);
	return true;
}

bool URoamRoadNetwork::SamplePosition(FName RoadId, float S, FRoamRoadHit& OutHit) const
{
	return SamplePositionByIndex(FindRoadIndex(RoadId), S, OutHit);
}

FRoamRoadSample URoamRoadNetwork::SampleRoad(const FRoamRoad& Road, float S)
{
	FRoamRoadSample Out;
	float Alpha = 0.0f;
	const int32 Seg = FindSegmentByS(Road, S, Alpha);
	if (Seg == INDEX_NONE)
	{
		return Out;
	}
	const FRoamRoadSample& A = Road.Samples[Seg];
	const FRoamRoadSample& B = Road.Samples[Seg + 1];
	Out.Position = FMath::Lerp(A.Position, B.Position, static_cast<double>(Alpha));
	Out.Tangent = FMath::Lerp(A.Tangent, B.Tangent, static_cast<double>(Alpha)).GetSafeNormal();
	Out.BankDeg = FMath::Lerp(A.BankDeg, B.BankDeg, Alpha);
	Out.WidthCm = FMath::Lerp(A.WidthCm, B.WidthCm, Alpha);
	Out.S = FMath::Lerp(A.S, B.S, Alpha);
	Out.Flags = (Alpha < 0.5f) ? A.Flags : B.Flags;
	return Out;
}

float URoamRoadNetwork::LaneOffsetCm(const FRoamRoad& Road, int32 LaneIndex) const
{
	if (LaneIndex == 0)
	{
		return 0.0f;
	}
	if (Road.bOneWay)
	{
		// Lanes 1..N centred on the road, increasing to the right.
		return (static_cast<float>(FMath::Abs(LaneIndex)) - 0.5f - 0.5f * static_cast<float>(Road.LanesForward)) * Road.LaneWidthCm;
	}
	const float Side = (LaneIndex > 0 ? 1.0f : -1.0f) * (bRightHandTraffic ? 1.0f : -1.0f);
	return Side * (static_cast<float>(FMath::Abs(LaneIndex)) - 0.5f) * Road.LaneWidthCm;
}

FVector URoamRoadNetwork::GetLanePosition(const FRoamRoadHit& Hit, int32 LaneIndex) const
{
	if (!Hit.bValid || !Roads.IsValidIndex(Hit.RoadIndex))
	{
		return Hit.Position;
	}
	return Hit.Position + Hit.Right * LaneOffsetCm(Roads[Hit.RoadIndex], LaneIndex);
}

FVector URoamRoadNetwork::GetLaneDirection(const FRoamRoadHit& Hit, int32 LaneIndex)
{
	return LaneIndex < 0 ? -Hit.Tangent : Hit.Tangent;
}

int32 URoamRoadNetwork::FindClosestLane(const FRoamRoadHit& Hit) const
{
	if (!Hit.bValid || !Roads.IsValidIndex(Hit.RoadIndex))
	{
		return 0;
	}
	const FRoamRoad& Road = Roads[Hit.RoadIndex];
	int32 Best = 0;
	float BestDistance = TNumericLimits<float>::Max();
	for (int32 Lane = -(Road.bOneWay ? 0 : Road.LanesBackward); Lane <= Road.LanesForward; ++Lane)
	{
		if (Lane == 0)
		{
			continue;
		}
		const float Distance = FMath::Abs(LaneOffsetCm(Road, Lane) - Hit.LateralCm);
		if (Distance < BestDistance)
		{
			BestDistance = Distance;
			Best = Lane;
		}
	}
	return Best;
}

// ------------------------------------------------------------------------------------------------------------------
// Routing
// ------------------------------------------------------------------------------------------------------------------

float URoamRoadNetwork::GetRouteCostFactor(ERoamRoadClass RoadClass)
{
	switch (RoadClass)
	{
	case ERoamRoadClass::Highway:  return 1.0f;
	case ERoamRoadClass::Regional: return 1.25f;
	case ERoamRoadClass::Mountain: return 1.8f;
	case ERoamRoadClass::Dirt:     return 2.5f;
	case ERoamRoadClass::Shortcut: return 2.5f;
	case ERoamRoadClass::Village:  return 1.4f;
	default: break;
	}
	return 1.5f;
}

bool URoamRoadNetwork::FindRoute(const FVector& From, const FVector& To, FRoamRoute& OutRoute) const
{
	OutRoute = FRoamRoute();
	FRoamRoadHit A;
	FRoamRoadHit B;
	if (!FindNearestRoad(From, A, 0xFF, TNumericLimits<float>::Max()) || !FindNearestRoad(To, B, 0xFF, TNumericLimits<float>::Max()))
	{
		return false;
	}
	return FindRouteBetween(A, B, OutRoute);
}

bool URoamRoadNetwork::FindRouteBetween(const FRoamRoadHit& From, const FRoamRoadHit& To, FRoamRoute& OutRoute) const
{
	OutRoute = FRoamRoute();
	if (!Roads.IsValidIndex(From.RoadIndex) || !Roads.IsValidIndex(To.RoadIndex))
	{
		return false;
	}
	if (!bIndexBuilt)
	{
		const_cast<URoamRoadNetwork*>(this)->BuildSpatialIndex();
	}

	const int32 NumJ = Junctions.Num();
	const int32 StartNode = NumJ;
	const int32 EndNode = NumJ + 1;
	const FRoamRoad& RoadA = Roads[From.RoadIndex];
	const FRoamRoad& RoadB = Roads[To.RoadIndex];
	const float FactorA = GetRouteCostFactor(RoadA.RoadClass);
	const float FactorB = GetRouteCostFactor(RoadB.RoadClass);
	const int32 AStartJ = JunctionIndexById.Contains(RoadA.StartJunction) ? JunctionIndexById[RoadA.StartJunction] : INDEX_NONE;
	const int32 AEndJ = JunctionIndexById.Contains(RoadA.EndJunction) ? JunctionIndexById[RoadA.EndJunction] : INDEX_NONE;
	const int32 BStartJ = JunctionIndexById.Contains(RoadB.StartJunction) ? JunctionIndexById[RoadB.StartJunction] : INDEX_NONE;
	const int32 BEndJ = JunctionIndexById.Contains(RoadB.EndJunction) ? JunctionIndexById[RoadB.EndJunction] : INDEX_NONE;

	// Candidate 1: stay on the same road.
	bool bHaveDirect = false;
	float DirectCost = 0.0f;
	FRoamRouteLeg DirectLeg;
	if (From.RoadIndex == To.RoadIndex && (!RoadA.bOneWay || To.S >= From.S))
	{
		bHaveDirect = true;
		DirectCost = FMath::Abs(To.S - From.S) * FactorA;
		DirectLeg = MakeLeg(Roads, From.RoadIndex, From.S, To.S);
	}

	// Candidate 2: A* over junctions with the two points as virtual nodes.
	const int32 NumNodes = NumJ + 2;
	TArray<float> G;
	G.Init(TNumericLimits<float>::Max(), NumNodes);
	TArray<int32> Parent;
	Parent.Init(INDEX_NONE, NumNodes);
	TArray<FRoamRouteLeg> ParentLeg;
	ParentLeg.SetNum(NumNodes);
	TArray<uint8> Closed;
	Closed.Init(0, NumNodes);

	const auto NodePosition = [&](int32 Node) -> FVector
	{
		if (Node < NumJ) { return Junctions[Node].Position; }
		return Node == StartNode ? From.Position : To.Position;
	};

	// Generates all outgoing edges of a node: Fn(ToNode, Leg, Cost).
	const auto ForEachEdge = [&](int32 Node, auto&& Fn)
	{
		if (Node == StartNode)
		{
			if (AStartJ != INDEX_NONE && !RoadA.bOneWay)
			{
				Fn(AStartJ, MakeLeg(Roads, From.RoadIndex, From.S, 0.0f), From.S * FactorA);
			}
			if (AEndJ != INDEX_NONE)
			{
				Fn(AEndJ, MakeLeg(Roads, From.RoadIndex, From.S, RoadA.LengthCm), (RoadA.LengthCm - From.S) * FactorA);
			}
		}
		else if (Node < NumJ)
		{
			for (const FJunctionEdge& Edge : Adjacency[Node])
			{
				const FRoamRoad& Road = Roads[Edge.RoadIndex];
				Fn(Edge.ToJunction, MakeLeg(Roads, Edge.RoadIndex, Edge.bForward ? 0.0f : Road.LengthCm, Edge.bForward ? Road.LengthCm : 0.0f), Edge.Cost);
			}
			if (Node == BStartJ)
			{
				Fn(EndNode, MakeLeg(Roads, To.RoadIndex, 0.0f, To.S), To.S * FactorB);
			}
			if (Node == BEndJ && !RoadB.bOneWay)
			{
				Fn(EndNode, MakeLeg(Roads, To.RoadIndex, RoadB.LengthCm, To.S), (RoadB.LengthCm - To.S) * FactorB);
			}
		}
	};

	G[StartNode] = 0.0f;
	const FVector TargetPosition = To.Position;
	while (true)
	{
		// Open node with the lowest f = g + h (linear scan: the junction graph has a few hundred nodes at most).
		int32 Current = INDEX_NONE;
		float BestF = TNumericLimits<float>::Max();
		for (int32 Node = 0; Node < NumNodes; ++Node)
		{
			if (Closed[Node] || G[Node] == TNumericLimits<float>::Max())
			{
				continue;
			}
			const float F = G[Node] + static_cast<float>(FVector::Dist(NodePosition(Node), TargetPosition));
			if (F < BestF)
			{
				BestF = F;
				Current = Node;
			}
		}
		if (Current == INDEX_NONE || Current == EndNode)
		{
			break;
		}
		Closed[Current] = 1;
		ForEachEdge(Current, [&](int32 ToNode, const FRoamRouteLeg& Leg, float Cost)
		{
			if (Closed[ToNode])
			{
				return;
			}
			const float Tentative = G[Current] + Cost;
			if (Tentative < G[ToNode])
			{
				G[ToNode] = Tentative;
				Parent[ToNode] = Current;
				ParentLeg[ToNode] = Leg;
			}
		});
	}

	const bool bHavePath = G[EndNode] != TNumericLimits<float>::Max();
	if (!bHavePath && !bHaveDirect)
	{
		return false;
	}

	if (bHaveDirect && (!bHavePath || DirectCost <= G[EndNode]))
	{
		OutRoute.bValid = true;
		OutRoute.Cost = DirectCost;
		OutRoute.LengthCm = FMath::Abs(DirectLeg.ToS - DirectLeg.FromS);
		OutRoute.Legs.Add(DirectLeg);
		return true;
	}

	// Walk back from the end node.
	TArray<FRoamRouteLeg> Reversed;
	for (int32 Node = EndNode; Node != StartNode && Node != INDEX_NONE; Node = Parent[Node])
	{
		FRoamRouteLeg Leg = ParentLeg[Node];
		if (Node < NumJ)
		{
			Leg.EndJunction = Junctions[Node].JunctionId;
		}
		Reversed.Add(Leg);
	}
	for (int32 i = Reversed.Num() - 1; i >= 0; --i)
	{
		OutRoute.Legs.Add(Reversed[i]);
		OutRoute.LengthCm += FMath::Abs(Reversed[i].ToS - Reversed[i].FromS);
	}
	OutRoute.Cost = G[EndNode];
	OutRoute.bValid = OutRoute.Legs.Num() > 0;
	return OutRoute.bValid;
}

void URoamRoadNetwork::BuildRoutePolyline(const FRoamRoute& Route, float SpacingCm, TArray<FVector>& OutPoints) const
{
	OutPoints.Reset();
	const float Spacing = FMath::Max(SpacingCm, 50.0f);
	for (const FRoamRouteLeg& Leg : Route.Legs)
	{
		if (!Roads.IsValidIndex(Leg.RoadIndex))
		{
			continue;
		}
		const FRoamRoad& Road = Roads[Leg.RoadIndex];
		const float Length = FMath::Abs(Leg.ToS - Leg.FromS);
		const float Dir = (Leg.ToS >= Leg.FromS) ? 1.0f : -1.0f;
		const auto AddPoint = [&](float Distance)
		{
			const FVector P = SampleRoad(Road, Leg.FromS + Dir * Distance).Position;
			if (OutPoints.Num() == 0 || FVector::DistSquared(OutPoints.Last(), P) > 1.0)
			{
				OutPoints.Add(P);
			}
		};
		for (float D = 0.0f; D < Length; D += Spacing)
		{
			AddPoint(D);
		}
		AddPoint(Length);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Validation and synthetic network
// ------------------------------------------------------------------------------------------------------------------

bool URoamRoadNetwork::Validate(TArray<FString>& OutProblems) const
{
	const int32 Before = OutProblems.Num();
	TSet<FName> RoadIds;
	for (const FRoamRoad& Road : Roads)
	{
		if (Road.RoadId.IsNone())
		{
			OutProblems.Add(TEXT("road without id"));
		}
		else if (RoadIds.Contains(Road.RoadId))
		{
			OutProblems.Add(FString::Printf(TEXT("duplicate road id %s"), *Road.RoadId.ToString()));
		}
		RoadIds.Add(Road.RoadId);
		if (Road.Samples.Num() < 2)
		{
			OutProblems.Add(FString::Printf(TEXT("road %s has < 2 samples"), *Road.RoadId.ToString()));
		}
		if (!Road.StartJunction.IsNone() && FindJunctionIndex(Road.StartJunction) == INDEX_NONE)
		{
			OutProblems.Add(FString::Printf(TEXT("road %s start junction %s missing"), *Road.RoadId.ToString(), *Road.StartJunction.ToString()));
		}
		if (!Road.EndJunction.IsNone() && FindJunctionIndex(Road.EndJunction) == INDEX_NONE)
		{
			OutProblems.Add(FString::Printf(TEXT("road %s end junction %s missing"), *Road.RoadId.ToString(), *Road.EndJunction.ToString()));
		}
	}
	TSet<FName> JunctionIds;
	for (const FRoamJunction& Junction : Junctions)
	{
		if (JunctionIds.Contains(Junction.JunctionId))
		{
			OutProblems.Add(FString::Printf(TEXT("duplicate junction id %s"), *Junction.JunctionId.ToString()));
		}
		JunctionIds.Add(Junction.JunctionId);
		for (const FRoamJunctionArm& Arm : Junction.Arms)
		{
			if (!RoadIds.Contains(Arm.RoadId))
			{
				OutProblems.Add(FString::Printf(TEXT("junction %s arm references unknown road %s"), *Junction.JunctionId.ToString(), *Arm.RoadId.ToString()));
			}
		}
	}
	return OutProblems.Num() == Before;
}

URoamRoadNetwork* URoamRoadNetwork::BuildGeneratedForTests(UObject* Outer, int32 JunctionsPerSide, float SpacingCm, float SampleSpacingCm)
{
	const int32 N = FMath::Clamp(JunctionsPerSide, 2, 16);
	URoamRoadNetwork* Network = NewObject<URoamRoadNetwork>(Outer ? Outer : GetTransientPackage());

	const float Offset = 0.5f * SpacingCm * static_cast<float>(N - 1);
	const auto JunctionName = [](int32 Col, int32 Row) { return FName(*FString::Printf(TEXT("J_%d_%d"), Col, Row)); };

	for (int32 Row = 0; Row < N; ++Row)
	{
		for (int32 Col = 0; Col < N; ++Col)
		{
			FRoamJunction Junction;
			Junction.JunctionId = JunctionName(Col, Row);
			Junction.Position = FVector(Col * SpacingCm - Offset, Row * SpacingCm - Offset, 0.0);
			Junction.Control = ERoamJunctionControl::GiveWay;
			Network->Junctions.Add(Junction);
		}
	}

	const auto AddRoad = [&](FName Id, ERoamRoadClass Class, ERoamSurface Surface, float Limit, int32 Lanes, FName StartJ, FName EndJ, const FVector& A, const FVector& B)
	{
		FRoamRoad Road;
		Road.RoadId = Id;
		Road.RoadClass = Class;
		Road.Surface = Surface;
		Road.SpeedLimitKmh = Limit;
		Road.LanesForward = Lanes;
		Road.LanesBackward = Lanes;
		Road.LaneWidthCm = 350.0f;
		Road.StartJunction = StartJ;
		Road.EndJunction = EndJ;
		const float Length = static_cast<float>(FVector::Dist(A, B));
		const int32 NumSamples = FMath::Max(2, FMath::CeilToInt(Length / FMath::Max(SampleSpacingCm, 50.0f)) + 1);
		for (int32 i = 0; i < NumSamples; ++i)
		{
			FRoamRoadSample Sample;
			Sample.Position = FMath::Lerp(A, B, static_cast<double>(i) / static_cast<double>(NumSamples - 1));
			Sample.Tangent = (B - A).GetSafeNormal();
			Sample.WidthCm = Road.LaneWidthCm * static_cast<float>(Lanes * 2);
			Road.Samples.Add(Sample);
		}
		Network->Roads.Add(Road);

		for (FRoamJunction& Junction : Network->Junctions)
		{
			FRoamJunctionArm Arm;
			Arm.RoadId = Id;
			if (Junction.JunctionId == StartJ)
			{
				Arm.bAtRoadStart = true;
				Junction.Arms.Add(Arm);
			}
			if (Junction.JunctionId == EndJ)
			{
				Arm.bAtRoadStart = false;
				Junction.Arms.Add(Arm);
			}
		}
	};

	const int32 MiddleRow = N / 2;
	for (int32 Row = 0; Row < N; ++Row)
	{
		for (int32 Col = 0; Col + 1 < N; ++Col)
		{
			const FName A = JunctionName(Col, Row);
			const FName B = JunctionName(Col + 1, Row);
			const bool bHighway = (Row == MiddleRow);
			AddRoad(FName(*FString::Printf(TEXT("H_%d_%d"), Row, Col)), bHighway ? ERoamRoadClass::Highway : ERoamRoadClass::Regional, ERoamSurface::Asphalt,
				bHighway ? 120.0f : 80.0f, bHighway ? 2 : 1, A, B, Network->Junctions[Row * N + Col].Position, Network->Junctions[Row * N + Col + 1].Position);
		}
	}
	for (int32 Col = 0; Col < N; ++Col)
	{
		for (int32 Row = 0; Row + 1 < N; ++Row)
		{
			AddRoad(FName(*FString::Printf(TEXT("V_%d_%d"), Col, Row)), ERoamRoadClass::Regional, ERoamSurface::Asphalt, 80.0f, 1,
				JunctionName(Col, Row), JunctionName(Col, Row + 1), Network->Junctions[Row * N + Col].Position, Network->Junctions[(Row + 1) * N + Col].Position);
		}
	}
	AddRoad(TEXT("D_diag"), ERoamRoadClass::Dirt, ERoamSurface::Gravel, 50.0f, 1, JunctionName(0, 0), JunctionName(N - 1, N - 1),
		Network->Junctions[0].Position, Network->Junctions[N * N - 1].Position);

	Network->BuildSpatialIndex();
	return Network;
}
