// Copyright Epic Games, Inc. All Rights Reserved.

#include "Traffic/RoamLaneGraph.h"

#include "Data/RoamRoadNetwork.h"

namespace
{
	float DefaultSpeedLimitKmh(ERoamRoadClass RoadClass)
	{
		switch (RoadClass)
		{
		case ERoamRoadClass::Highway: return 120.0f;
		case ERoamRoadClass::Regional: return 80.0f;
		case ERoamRoadClass::Mountain: return 60.0f;
		case ERoamRoadClass::Village: return 40.0f;
		default: return 40.0f;
		}
	}

	FVector HorizontalRight(const FVector& Tangent)
	{
		const FVector T2 = FVector(Tangent.X, Tangent.Y, 0.0).GetSafeNormal();
		return FVector(-T2.Y, T2.X, 0.0); // UE: +Y is right of +X
	}
}

void FRoamLane::Sample(float S, FVector& OutPos, FVector& OutDir) const
{
	if (Points.Num() < 2)
	{
		OutPos = Points.Num() == 1 ? Points[0] : FVector::ZeroVector;
		OutDir = FVector::ForwardVector;
		return;
	}
	const float Clamped = FMath::Clamp(S, 0.0f, LengthCm);
	const int32 I = FMath::Clamp(static_cast<int32>(Clamped / StepCm), 0, Points.Num() - 2);
	const float D0 = static_cast<float>(I) * StepCm;
	const float D1 = FMath::Min(static_cast<float>(I + 1) * StepCm, LengthCm);
	const float Alpha = D1 > D0 ? FMath::Clamp((Clamped - D0) / (D1 - D0), 0.0f, 1.0f) : 0.0f;
	OutPos = FMath::Lerp(Points[I], Points[I + 1], static_cast<double>(Alpha));
	OutDir = FMath::Lerp(Dirs[I], Dirs[I + 1], static_cast<double>(Alpha)).GetSafeNormal();
}

float FRoamLane::CurvatureAt(float S) const
{
	if (CurvaturePerCm.Num() == 0)
	{
		return 0.0f;
	}
	const int32 I = FMath::Clamp(FMath::RoundToInt(S / StepCm), 0, CurvaturePerCm.Num() - 1);
	return CurvaturePerCm[I];
}

FIntPoint FRoamLaneGraph::CellOf(const FVector& P)
{
	return FIntPoint(FMath::FloorToInt(static_cast<float>(P.X) / CellSizeCm), FMath::FloorToInt(static_cast<float>(P.Y) / CellSizeCm));
}

void FRoamLaneGraph::Reset()
{
	Lanes.Reset();
	JunctionPos.Reset();
	JunctionRadius.Reset();
	JunctionControl.Reset();
	Cells.Reset();
	TotalLaneLengthCm = 0.0f;
}

void FRoamLaneGraph::Build(const URoamRoadNetwork& Network, float StepCm)
{
	Reset();
	StepCm = FMath::Max(StepCm, 100.0f);

	for (const FRoamJunction& J : Network.Junctions)
	{
		JunctionPos.Add(J.Position);
		JunctionRadius.Add(J.RadiusCm);
		JunctionControl.Add(J.Control);
	}

	// Key = RoadIndex * 2 + (atRoadStart ? 1 : 0): lanes that LEAVE the junction through that road end.
	TMap<int32, TArray<int32>> LeavingByEnd;

	for (int32 RoadIndex = 0; RoadIndex < Network.Roads.Num(); ++RoadIndex)
	{
		const FRoamRoad& Road = Network.Roads[RoadIndex];
		if (Road.Samples.Num() < 2 || Road.LengthCm < 1000.0f)
		{
			continue;
		}
		const int32 StartJ = Network.FindJunctionIndex(Road.StartJunction);
		const int32 EndJ = Network.FindJunctionIndex(Road.EndJunction);

		const int32 NumDirections = Road.bOneWay ? 1 : 2;
		for (int32 Dir = 0; Dir < NumDirections; ++Dir)
		{
			const bool bForward = (Dir == 0);
			const int32 NumLanes = bForward ? Road.LanesForward : Road.LanesBackward;
			for (int32 K = 1; K <= NumLanes; ++K)
			{
				FRoamLane Lane;
				Lane.RoadIndex = RoadIndex;
				Lane.bForward = bForward;
				Lane.LaneIndex = bForward ? K : -K;
				Lane.RoadClass = Road.RoadClass;
				Lane.Surface = Road.Surface;
				Lane.LengthCm = Road.LengthCm;
				Lane.StepCm = StepCm;
				Lane.LanesInDirection = FMath::Max(NumLanes, 1);
				const float Limit = Road.SpeedLimitKmh > 1.0f ? Road.SpeedLimitKmh : DefaultSpeedLimitKmh(Road.RoadClass);
				Lane.SpeedLimitMs = Limit / 3.6f;
				Lane.StartJunction = bForward ? StartJ : EndJ;
				Lane.EndJunction = bForward ? EndJ : StartJ;
				Lane.ArmKey = RoadIndex * 2 + (bForward ? 1 : 0);
				const float R0 = Lane.StartJunction != INDEX_NONE ? Network.Junctions[Lane.StartJunction].RadiusCm : 0.0f;
				const float R1 = Lane.EndJunction != INDEX_NONE ? Network.Junctions[Lane.EndJunction].RadiusCm : 0.0f;
				Lane.BlendStartCm = FMath::Min(R0, Lane.LengthCm * 0.45f);
				Lane.BlendEndCm = FMath::Min(R1, Lane.LengthCm * 0.45f);

				// arrival arm priority
				if (Lane.EndJunction != INDEX_NONE)
				{
					const bool bArrivesAtRoadStart = !bForward;
					for (const FRoamJunctionArm& Arm : Network.Junctions[Lane.EndJunction].Arms)
					{
						if (Arm.RoadId == Road.RoadId && Arm.bAtRoadStart == bArrivesAtRoadStart)
						{
							Lane.EndArmPriority = Arm.Priority;
							break;
						}
					}
				}

				const float Offset = Network.LaneOffsetCm(Road, Lane.LaneIndex);
				const int32 NumPoints = FMath::Max(2, FMath::CeilToInt(Lane.LengthCm / StepCm) + 1);
				Lane.Points.SetNumUninitialized(NumPoints);
				Lane.Dirs.SetNumUninitialized(NumPoints);
				for (int32 i = 0; i < NumPoints; ++i)
				{
					const float D = FMath::Min(static_cast<float>(i) * StepCm, Lane.LengthCm);
					const float RoadS = bForward ? D : Lane.LengthCm - D;
					const FRoamRoadSample Sample = URoamRoadNetwork::SampleRoad(Road, RoadS);
					Lane.Points[i] = Sample.Position + HorizontalRight(Sample.Tangent) * Offset;
					Lane.Dirs[i] = (bForward ? Sample.Tangent : -Sample.Tangent).GetSafeNormal();
				}
				Lane.CurvaturePerCm.SetNumZeroed(NumPoints);
				for (int32 i = 0; i < NumPoints; ++i)
				{
					const int32 A = FMath::Max(i - 1, 0);
					const int32 B = FMath::Min(i + 1, NumPoints - 1);
					const FVector DA = FVector(Lane.Dirs[A].X, Lane.Dirs[A].Y, 0.0).GetSafeNormal();
					const FVector DB = FVector(Lane.Dirs[B].X, Lane.Dirs[B].Y, 0.0).GetSafeNormal();
					const float Angle = FMath::Acos(FMath::Clamp(static_cast<float>(FVector::DotProduct(DA, DB)), -1.0f, 1.0f));
					const float Dist = FMath::Max(static_cast<float>(FVector::Dist2D(Lane.Points[A], Lane.Points[B])), 1.0f);
					Lane.CurvaturePerCm[i] = FMath::Min(Angle / Dist, 1.0f / 1500.0f);
				}

				TotalLaneLengthCm += Lane.LengthCm;
				const int32 LaneId = Lanes.Add(MoveTemp(Lane));
				// lanes leave through the road start (forward) or the road end (backward)
				const int32 EndKey = RoadIndex * 2 + (bForward ? 1 : 0);
				LeavingByEnd.FindOrAdd(EndKey).Add(LaneId);
			}
		}
	}

	// successors through the end junction
	for (int32 LaneId = 0; LaneId < Lanes.Num(); ++LaneId)
	{
		FRoamLane& A = Lanes[LaneId];
		if (A.EndJunction == INDEX_NONE)
		{
			continue;
		}
		const bool bArrivesAtRoadStart = !A.bForward;
		const FVector DirA = FVector(A.Dirs.Last().X, A.Dirs.Last().Y, 0.0).GetSafeNormal();
		const FVector RightA(-DirA.Y, DirA.X, 0.0);
		// two passes: the first applies lane discipline on multi-lane roads (outer lane never crosses to the far side), the second
		// is the fallback when that leaves no way on
		for (int32 Pass = 0; Pass < 2 && A.Successors.Num() == 0; ++Pass)
		{
			for (const FRoamJunctionArm& Arm : Network.Junctions[A.EndJunction].Arms)
			{
				const int32 ArmRoad = Network.FindRoadIndex(Arm.RoadId);
				if (ArmRoad == INDEX_NONE)
				{
					continue;
				}
				if (ArmRoad == A.RoadIndex && Arm.bAtRoadStart == bArrivesAtRoadStart)
				{
					continue; // U-turn onto the opposite carriageway of the same road end
				}
				const TArray<int32>* Leaving = LeavingByEnd.Find(ArmRoad * 2 + (Arm.bAtRoadStart ? 1 : 0));
				if (!Leaving || Leaving->Num() == 0)
				{
					continue;
				}
				const int32 Pick = FMath::Clamp(FMath::Abs(A.LaneIndex) - 1, 0, Leaving->Num() - 1);
				const int32 BId = (*Leaving)[Pick];
				const FRoamLane& B = Lanes[BId];
				const FVector DirB = FVector(B.Dirs[0].X, B.Dirs[0].Y, 0.0).GetSafeNormal();
				const float Dot = static_cast<float>(FVector::DotProduct(DirA, DirB));
				const float Angle = FMath::Acos(FMath::Clamp(Dot, -1.0f, 1.0f));
				if (Pass == 0 && A.LanesInDirection > 1 && Angle > 0.4f)
				{
					const bool bRightTurn = FVector::DotProduct(DirB, RightA) > 0.0;
					const bool bOuterRight = FMath::Abs(A.LaneIndex) == 1;
					const bool bOuterLeft = FMath::Abs(A.LaneIndex) == A.LanesInDirection;
					if ((bRightTurn && !bOuterRight) || (!bRightTurn && !bOuterLeft))
					{
						continue;
					}
				}
				A.Successors.Add(BId);
				A.SuccessorTurnRad.Add(Angle);
				A.SuccessorWeight.Add(Dot > 0.85f ? 4.0f : (Dot < -0.7f ? 0.3f : 1.5f));
			}
		}
	}

	// spatial hash
	for (int32 LaneId = 0; LaneId < Lanes.Num(); ++LaneId)
	{
		const FRoamLane& L = Lanes[LaneId];
		for (int32 i = 0; i < L.Points.Num(); ++i)
		{
			FCellEntry Entry;
			Entry.Lane = LaneId;
			Entry.Point = i;
			Cells.FindOrAdd(CellOf(L.Points[i])).Add(Entry);
		}
	}
}

void FRoamLaneGraph::ForEachPointInRadius(const FVector& Center, float RadiusCm, TFunctionRef<void(int32, int32, const FVector&)> Visitor) const
{
	const FIntPoint Lo = CellOf(Center - FVector(RadiusCm, RadiusCm, 0.0));
	const FIntPoint Hi = CellOf(Center + FVector(RadiusCm, RadiusCm, 0.0));
	const double R2 = static_cast<double>(RadiusCm) * RadiusCm;
	for (int32 Y = Lo.Y; Y <= Hi.Y; ++Y)
	{
		for (int32 X = Lo.X; X <= Hi.X; ++X)
		{
			const TArray<FCellEntry>* Cell = Cells.Find(FIntPoint(X, Y));
			if (!Cell)
			{
				continue;
			}
			for (const FCellEntry& E : *Cell)
			{
				const FVector& P = Lanes[E.Lane].Points[E.Point];
				if (FVector::DistSquared2D(P, Center) <= R2)
				{
					Visitor(E.Lane, E.Point, P);
				}
			}
		}
	}
}

int32 FRoamLaneGraph::FindNearestLane(const FVector& Location, float MaxDistanceCm, float* OutS, float* OutDistanceCm) const
{
	int32 Best = INDEX_NONE;
	double BestD2 = static_cast<double>(MaxDistanceCm) * MaxDistanceCm;
	int32 BestPoint = 0;
	ForEachPointInRadius(Location, MaxDistanceCm, [&](int32 Lane, int32 Point, const FVector& P)
	{
		const double D2 = FVector::DistSquared2D(P, Location);
		if (D2 < BestD2)
		{
			BestD2 = D2;
			Best = Lane;
			BestPoint = Point;
		}
	});
	if (Best != INDEX_NONE)
	{
		if (OutS)
		{
			*OutS = FMath::Min(static_cast<float>(BestPoint) * Lanes[Best].StepCm, Lanes[Best].LengthCm);
		}
		if (OutDistanceCm)
		{
			*OutDistanceCm = static_cast<float>(FMath::Sqrt(BestD2));
		}
	}
	return Best;
}
