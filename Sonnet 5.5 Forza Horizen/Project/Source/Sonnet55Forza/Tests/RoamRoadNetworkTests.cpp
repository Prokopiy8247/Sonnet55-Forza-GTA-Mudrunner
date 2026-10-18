// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Data/RoamRoadNetwork.h"
#include "Math/RandomStream.h"
#include "UObject/StrongObjectPtr.h"

#define ROAM_ROAD_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

namespace
{
	/** Brute-force reference for FindNearest: distance to the closest point of any segment of any road. */
	float BruteForceNearestDistance(const URoamRoadNetwork& Network, const FVector& Location)
	{
		float Best = TNumericLimits<float>::Max();
		for (const FRoamRoad& Road : Network.Roads)
		{
			for (int32 i = 0; i + 1 < Road.Samples.Num(); ++i)
			{
				const FVector Closest = FMath::ClosestPointOnSegment(Location, Road.Samples[i].Position, Road.Samples[i + 1].Position);
				Best = FMath::Min(Best, static_cast<float>(FVector::Dist(Location, Closest)));
			}
		}
		return Best;
	}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamRoadNetworkBuildTest, "Roam.RoadNetwork.SyntheticNetwork", ROAM_ROAD_TEST_FLAGS)
bool FRoamRoadNetworkBuildTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamRoadNetwork> Network(URoamRoadNetwork::BuildGeneratedForTests(GetTransientPackage(), 3, 100000.0f, 500.0f));
	TestNotNull(TEXT("network created"), Network.Get());
	if (!Network)
	{
		return false;
	}

	TArray<FString> Problems;
	TestTrue(TEXT("synthetic network validates"), Network->Validate(Problems));
	for (const FString& Problem : Problems)
	{
		AddError(Problem);
	}

	TestEqual(TEXT("13 roads (6 horizontal, 6 vertical, 1 diagonal)"), Network->GetNumRoads(), 13);
	TestEqual(TEXT("9 junctions"), Network->Junctions.Num(), 9);
	TestNearlyEqual(TEXT("total length"), Network->GetTotalLengthCm(), 1200000.0f + 2.0f * 100000.0f * 1.41421356f, 5.0f);
	TestTrue(TEXT("index built"), Network->IsIndexBuilt());

	const FRoamRoad* Highway = Network->FindRoad(TEXT("H_1_0"));
	TestNotNull(TEXT("highway road exists"), Highway);
	if (Highway)
	{
		TestEqual(TEXT("middle row is a highway"), Highway->RoadClass, ERoamRoadClass::Highway);
		TestEqual(TEXT("two lanes per direction"), Highway->LanesForward, 2);
		TestNearlyEqual(TEXT("road length"), Highway->LengthCm, 100000.0f, 1.0f);
		TestNearlyEqual(TEXT("last sample S equals the length"), Highway->Samples.Last().S, Highway->LengthCm, 0.01f);
	}
	TestEqual(TEXT("road index lookup"), Network->FindRoadIndex(TEXT("D_diag")), 12);
	TestEqual(TEXT("unknown road"), Network->FindRoadIndex(TEXT("nope")), static_cast<int32>(INDEX_NONE));

	// a malformed network is rejected
	TStrongObjectPtr<URoamRoadNetwork> Broken(NewObject<URoamRoadNetwork>(GetTransientPackage()));
	FRoamRoad Road;
	Road.RoadId = TEXT("A");
	Road.StartJunction = TEXT("missing");
	Broken->Roads.Add(Road);
	Problems.Reset();
	TestFalse(TEXT("broken network fails validation"), Broken->Validate(Problems));
	TestTrue(TEXT("problems reported"), Problems.Num() >= 2);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamRoadNearestTest, "Roam.RoadNetwork.Nearest", ROAM_ROAD_TEST_FLAGS)
bool FRoamRoadNearestTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamRoadNetwork> Network(URoamRoadNetwork::BuildGeneratedForTests(GetTransientPackage(), 3, 100000.0f, 500.0f));

	// 3 m to the right of the middle-row highway, half way along H_1_0 (x from -100000 to 0, y = 0)
	FRoamRoadHit Hit;
	TestTrue(TEXT("hit found"), Network->FindNearestRoad(FVector(-50000.0, 300.0, 0.0), Hit));
	TestEqual(TEXT("closest road"), Hit.RoadId, FName(TEXT("H_1_0")));
	TestNearlyEqual(TEXT("S"), Hit.S, 50000.0f, 1.0f);
	TestNearlyEqual(TEXT("distance"), Hit.DistanceCm, 300.0f, 0.1f);
	TestNearlyEqual(TEXT("lateral is positive on the right-hand side"), Hit.LateralCm, 300.0f, 0.1f);
	TestTrue(TEXT("tangent points along +X"), Hit.Tangent.Equals(FVector::ForwardVector, 0.001));
	TestTrue(TEXT("right vector points to +Y"), Hit.Right.Equals(FVector::RightVector, 0.001));
	TestEqual(TEXT("surface"), Hit.Surface, ERoamSurface::Asphalt);
	TestNearlyEqual(TEXT("speed limit"), Hit.SpeedLimitKmh, 120.0f, 0.01f);
	// ... and 3 m to the left gives a negative lateral offset
	TestTrue(TEXT("left hit found"), Network->FindNearestRoad(FVector(-50000.0, -300.0, 0.0), Hit));
	TestNearlyEqual(TEXT("lateral negative on the left"), Hit.LateralCm, -300.0f, 0.1f);

	// class mask: only highways within a short range of a corner where only regional/dirt roads meet
	const FVector Corner(-100000.0, -100000.0, 0.0);
	TestFalse(TEXT("highway-only query near a regional corner finds nothing within 20 km"),
		Network->FindNearestRoad(Corner + FVector(500.0, 500.0, 0.0), Hit, 1 << static_cast<int32>(ERoamRoadClass::Highway), 20000.0f));
	TestTrue(TEXT("any-class query finds a road"), Network->FindNearestRoad(Corner + FVector(500.0, 500.0, 0.0), Hit));
	TestFalse(TEXT("out of range finds nothing"), Network->FindNearestRoad(FVector(5000000.0, 5000000.0, 0.0), Hit, 0xFF, 1000.0f));

	// vertical filter: a bridge over the road must not match
	FRoamRoadQuery Query;
	Query.Location = FVector(-50000.0, 0.0, 2000.0);
	Query.MaxVerticalCm = 500.0f;
	Query.MaxDistanceCm = 100000.0f;
	TestFalse(TEXT("road 20 m below is ignored when MaxVerticalCm is 5 m"), Network->FindNearest(Query, Hit));
	Query.MaxVerticalCm = 0.0f;
	TestTrue(TEXT("same query without the filter matches"), Network->FindNearest(Query, Hit));

	// heading and preferred road disambiguate crossing roads at the centre junction
	Query = FRoamRoadQuery();
	Query.Location = FVector(0.0, 0.0, 0.0); // J_1_1: highway row crosses a regional column
	Query.Heading = FVector::ForwardVector;
	TestTrue(TEXT("junction query"), Network->FindNearest(Query, Hit));
	TestEqual(TEXT("travelling along X prefers the highway"), Hit.RoadClass, ERoamRoadClass::Highway);
	Query.Heading = FVector::RightVector;
	TestTrue(TEXT("junction query 2"), Network->FindNearest(Query, Hit));
	TestEqual(TEXT("travelling along Y prefers the regional column"), Hit.RoadClass, ERoamRoadClass::Regional);

	// sampling by distance
	FRoamRoadHit Sample;
	TestTrue(TEXT("sample ok"), Network->SamplePosition(TEXT("H_1_0"), 25000.0f, Sample));
	TestTrue(TEXT("sample position"), Sample.Position.Equals(FVector(-75000.0, 0.0, 0.0), 1.0));
	TestTrue(TEXT("clamped sample start"), Network->SamplePosition(TEXT("H_1_0"), -500.0f, Sample) && Sample.Position.Equals(FVector(-100000.0, 0.0, 0.0), 1.0));
	TestTrue(TEXT("clamped sample end"), Network->SamplePosition(TEXT("H_1_0"), 9.0e9f, Sample) && Sample.Position.Equals(FVector(0.0, 0.0, 0.0), 1.0));
	TestFalse(TEXT("unknown road"), Network->SamplePosition(TEXT("nope"), 0.0f, Sample));

	// the incremental windowed search agrees with the global one
	FRoamRoadHit Global;
	FRoamRoadHit Windowed;
	const FVector P(-60000.0, 450.0, 0.0);
	Network->FindNearestRoad(P, Global);
	TestTrue(TEXT("windowed search"), Network->FindNearestOnRoad(Global.RoadIndex, P, 41000.0f, 5000.0f, Windowed));
	TestNearlyEqual(TEXT("windowed S"), Windowed.S, Global.S, 1.0f);

	// banking: positive bank lowers the right side
	FRoamRoad Banked;
	Banked.RoadId = TEXT("banked");
	for (int32 i = 0; i < 3; ++i)
	{
		FRoamRoadSample S;
		S.Position = FVector(i * 1000.0, 0.0, 0.0);
		S.Tangent = FVector::ForwardVector;
		S.BankDeg = 10.0f;
		Banked.Samples.Add(S);
	}
	TStrongObjectPtr<URoamRoadNetwork> BankNetwork(NewObject<URoamRoadNetwork>(GetTransientPackage()));
	BankNetwork->Roads.Add(Banked);
	BankNetwork->BuildSpatialIndex();
	TestTrue(TEXT("banked sample"), BankNetwork->SamplePosition(TEXT("banked"), 1000.0f, Sample));
	TestTrue(TEXT("positive bank lowers the right side"), Sample.Right.Z < -0.1);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamRoadGridTest, "Roam.RoadNetwork.GridMatchesBruteForce", ROAM_ROAD_TEST_FLAGS)
bool FRoamRoadGridTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamRoadNetwork> Network(URoamRoadNetwork::BuildGeneratedForTests(GetTransientPackage(), 4, 80000.0f, 400.0f));
	FRandomStream Random(2024);
	int32 Mismatches = 0;
	for (int32 i = 0; i < 400; ++i)
	{
		const FVector P(Random.FRandRange(-250000.0f, 250000.0f), Random.FRandRange(-250000.0f, 250000.0f), Random.FRandRange(-500.0f, 500.0f));
		FRoamRoadQuery Query;
		Query.Location = P;
		Query.MaxDistanceCm = 1.0e7f;
		FRoamRoadHit Hit;
		if (!Network->FindNearest(Query, Hit))
		{
			++Mismatches;
			continue;
		}
		const float Reference = BruteForceNearestDistance(*Network, P);
		if (!FMath::IsNearlyEqual(Hit.DistanceCm, Reference, 1.0f))
		{
			++Mismatches;
			AddError(FString::Printf(TEXT("point %s: grid %.1f vs brute force %.1f"), *P.ToString(), Hit.DistanceCm, Reference));
		}
	}
	TestEqual(TEXT("grid search equals brute force for 400 random points"), Mismatches, 0);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamRoadLaneTest, "Roam.RoadNetwork.Lanes", ROAM_ROAD_TEST_FLAGS)
bool FRoamRoadLaneTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamRoadNetwork> Network(URoamRoadNetwork::BuildGeneratedForTests(GetTransientPackage(), 3, 100000.0f, 500.0f));
	const FRoamRoad* Highway = Network->FindRoad(TEXT("H_1_0"));
	if (!TestNotNull(TEXT("highway"), Highway))
	{
		return false;
	}
	// 350 cm lanes, right-hand traffic: forward lanes on the right, backward lanes on the left
	TestNearlyEqual(TEXT("lane +1 offset"), Network->LaneOffsetCm(*Highway, 1), 175.0f, 0.01f);
	TestNearlyEqual(TEXT("lane +2 offset"), Network->LaneOffsetCm(*Highway, 2), 525.0f, 0.01f);
	TestNearlyEqual(TEXT("lane -1 offset"), Network->LaneOffsetCm(*Highway, -1), -175.0f, 0.01f);
	TestNearlyEqual(TEXT("lane 0 is the centreline"), Network->LaneOffsetCm(*Highway, 0), 0.0f, 0.01f);

	FRoamRoadHit Hit;
	Network->FindNearestRoad(FVector(-50000.0, 400.0, 0.0), Hit);
	TestEqual(TEXT("closest lane to +400 cm is the outer forward lane"), Network->FindClosestLane(Hit), 2);
	Network->FindNearestRoad(FVector(-50000.0, -100.0, 0.0), Hit);
	TestEqual(TEXT("closest lane to -100 cm is the inner backward lane"), Network->FindClosestLane(Hit), -1);

	Network->SamplePosition(TEXT("H_1_0"), 50000.0f, Hit);
	TestTrue(TEXT("lane position"), Network->GetLanePosition(Hit, 1).Equals(FVector(-50000.0, 175.0, 0.0), 0.5));
	TestTrue(TEXT("forward lane direction"), URoamRoadNetwork::GetLaneDirection(Hit, 1).Equals(FVector::ForwardVector, 0.001));
	TestTrue(TEXT("backward lane direction"), URoamRoadNetwork::GetLaneDirection(Hit, -1).Equals(-FVector::ForwardVector, 0.001));

	// left-hand traffic mirrors the lanes
	Network->bRightHandTraffic = false;
	TestNearlyEqual(TEXT("LHT lane +1 offset"), Network->LaneOffsetCm(*Highway, 1), -175.0f, 0.01f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamRoadRouteTest, "Roam.RoadNetwork.Route", ROAM_ROAD_TEST_FLAGS)
bool FRoamRoadRouteTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamRoadNetwork> Network(URoamRoadNetwork::BuildGeneratedForTests(GetTransientPackage(), 3, 100000.0f, 500.0f));

	// From 3 m beside the south-west corner to 3 m beside the north-east corner (points chosen ON one specific road each, so
	// the nearest-road projection has no ties). Roads are class weighted: the cheapest route goes back to the corner, up the
	// regional column, along the highway row and up the east column - longer than the cheapest-LENGTH route (394 m) but cheaper
	// by weight, which proves the router optimises cost and not metres.
	const FVector Start(-97000.0, -100000.0, 0.0);
	const FVector End(97000.0, 100000.0, 0.0);
	FRoamRoute Route;
	TestTrue(TEXT("corner to corner route"), Network->FindRoute(Start, End, Route));
	TestTrue(TEXT("route valid"), Route.bValid);
	TestNearlyEqual(TEXT("route length (3 + 100 + 200 + 100 + 3 m)"), Route.LengthCm, 406000.0f, 5.0f);
	TestNearlyEqual(TEXT("route cost uses the class weights"), Route.Cost, 457500.0f, 50.0f);
	TArray<FName> Roads;
	for (const FRoamRouteLeg& Leg : Route.Legs)
	{
		Roads.Add(Leg.RoadId);
	}
	TestTrue(TEXT("uses the highway row"), Roads.Contains(TEXT("H_1_0")) && Roads.Contains(TEXT("H_1_1")));
	TestFalse(TEXT("does not take the slow dirt diagonal"), Roads.Contains(TEXT("D_diag")));
	TestEqual(TEXT("first leg is on the start road"), Route.Legs[0].RoadId, FName(TEXT("H_0_0")));
	TestEqual(TEXT("last leg is on the end road"), Route.Legs.Last().RoadId, FName(TEXT("H_2_1")));

	// polyline
	TArray<FVector> Points;
	Network->BuildRoutePolyline(Route, 1000.0f, Points);
	TestTrue(TEXT("polyline has points"), Points.Num() > 300);
	if (Points.Num() > 2)
	{
		TestTrue(TEXT("polyline starts at the start"), FVector::Dist(Points[0], Start) < 1.0);
		TestTrue(TEXT("polyline ends at the end"), FVector::Dist(Points.Last(), End) < 1.0);
		float PolyLength = 0.0f;
		for (int32 i = 1; i < Points.Num(); ++i)
		{
			PolyLength += static_cast<float>(FVector::Dist(Points[i - 1], Points[i]));
		}
		TestNearlyEqual(TEXT("polyline length equals route length"), PolyLength, Route.LengthCm, 50.0f);
	}

	// two points on the same road
	FRoamRoadHit A;
	FRoamRoadHit B;
	Network->SamplePosition(TEXT("H_1_0"), 10000.0f, A);
	Network->SamplePosition(TEXT("H_1_0"), 40000.0f, B);
	FRoamRoute Short;
	TestTrue(TEXT("same-road route"), Network->FindRouteBetween(A, B, Short));
	TestEqual(TEXT("single leg"), Short.Legs.Num(), 1);
	TestNearlyEqual(TEXT("30 m... 300 m length"), Short.LengthCm, 30000.0f, 1.0f);
	FRoamRoute Backwards;
	TestTrue(TEXT("same-road route against the road direction"), Network->FindRouteBetween(B, A, Backwards));
	TestNearlyEqual(TEXT("reverse length"), Backwards.LengthCm, 30000.0f, 1.0f);
	TestTrue(TEXT("leg runs against S"), Backwards.Legs.Num() == 1 && Backwards.Legs[0].ToS < Backwards.Legs[0].FromS);

	// shortcut: from the first to the last junction the dirt diagonal is NOT cheaper (weighted), but a nearby pair on it is
	FRoamRoadHit DiagStart;
	FRoamRoadHit DiagEnd;
	Network->SamplePosition(TEXT("D_diag"), 20000.0f, DiagStart);
	Network->SamplePosition(TEXT("D_diag"), 120000.0f, DiagEnd);
	FRoamRoute OnDirt;
	TestTrue(TEXT("route along the diagonal"), Network->FindRouteBetween(DiagStart, DiagEnd, OnDirt));
	TestNearlyEqual(TEXT("100 m along the dirt road"), OnDirt.LengthCm, 100000.0f, 1.0f);

	// unreachable target
	TStrongObjectPtr<URoamRoadNetwork> Islands(NewObject<URoamRoadNetwork>(GetTransientPackage()));
	for (int32 Island = 0; Island < 2; ++Island)
	{
		FRoamRoad Road;
		Road.RoadId = Island == 0 ? FName(TEXT("island_a")) : FName(TEXT("island_b"));
		for (int32 i = 0; i < 3; ++i)
		{
			FRoamRoadSample S;
			S.Position = FVector(i * 1000.0, Island * 500000.0, 0.0);
			Road.Samples.Add(S);
		}
		Islands->Roads.Add(Road);
	}
	Islands->BuildSpatialIndex();
	FRoamRoute None;
	TestFalse(TEXT("disconnected roads have no route"), Islands->FindRoute(FVector(0.0, 0.0, 0.0), FVector(0.0, 500000.0, 0.0), None));
	TestFalse(TEXT("route flag stays false"), None.bValid);
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
