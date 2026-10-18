// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Data/RoamRoadNetwork.h"
#include "Traffic/RoamLaneGraph.h"
#include "Traffic/RoamTrafficSim.h"
#include "UObject/StrongObjectPtr.h"

#define ROAM_TRAFFIC_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

namespace
{
	int32 FindLaneId(const FRoamLaneGraph& Graph, const URoamRoadNetwork& Network, const TCHAR* RoadId, int32 LaneIndex)
	{
		const int32 RoadIndex = Network.FindRoadIndex(FName(RoadId));
		for (int32 i = 0; i < Graph.Lanes.Num(); ++i)
		{
			if (Graph.Lanes[i].RoadIndex == RoadIndex && Graph.Lanes[i].LaneIndex == LaneIndex)
			{
				return i;
			}
		}
		return INDEX_NONE;
	}

	/** Same-lane pairs must never overlap longitudinally (the IDM hard clamp keeps >= 30 cm). */
	int32 CountSameLaneOverlaps(const FRoamTrafficSim& Sim)
	{
		int32 Count = 0;
		for (int32 i = 0; i < Sim.Agents.Num(); ++i)
		{
			for (int32 j = i + 1; j < Sim.Agents.Num(); ++j)
			{
				const FRoamTrafficAgent& A = Sim.Agents[i];
				const FRoamTrafficAgent& B = Sim.Agents[j];
				if (A.Lane == B.Lane && FMath::Abs(A.S - B.S) < (A.LengthCm + B.LengthCm) * 0.5f - 5.0f)
				{
					++Count;
				}
			}
		}
		return Count;
	}

	struct FTrafficTestWorld
	{
		TStrongObjectPtr<URoamRoadNetwork> Network;
		TArray<FRoamTrafficVehicleSpec> Types;
		FRoamTrafficSim Sim;

		FTrafficTestWorld()
		{
			Network.Reset(URoamRoadNetwork::BuildGeneratedForTests(GetTransientPackage(), 3, 100000.0f, 500.0f));
			RoamTraffic::BuildDefaultVehicleTypes(Types);
			Sim.Init(*Network, Types, 99);
		}
	};
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTrafficLaneGraphTest, "Roam.Traffic.LaneGraph", ROAM_TRAFFIC_TEST_FLAGS)
bool FRoamTrafficLaneGraphTest::RunTest(const FString& Parameters)
{
	FTrafficTestWorld W;
	const FRoamLaneGraph& Graph = W.Sim.GetGraph();
	TestTrue(TEXT("graph is built"), W.Sim.IsReady());

	int32 ExpectedLanes = 0;
	for (const FRoamRoad& Road : W.Network->Roads)
	{
		ExpectedLanes += Road.LanesForward + (Road.bOneWay ? 0 : Road.LanesBackward);
	}
	TestEqual(TEXT("one directed lane per road lane"), Graph.Lanes.Num(), ExpectedLanes);

	const int32 Fwd = FindLaneId(Graph, *W.Network, TEXT("H_1_0"), 1);
	const int32 Bwd = FindLaneId(Graph, *W.Network, TEXT("H_1_0"), -1);
	TestTrue(TEXT("forward and backward lane of H_1_0 exist"), Fwd != INDEX_NONE && Bwd != INDEX_NONE);
	if (Fwd == INDEX_NONE || Bwd == INDEX_NONE)
	{
		return false;
	}
	const FRoamLane& F = Graph.Lanes[Fwd];
	const FRoamLane& B = Graph.Lanes[Bwd];
	FVector FP, FD, BP, BD;
	F.Sample(F.LengthCm * 0.5f, FP, FD);
	B.Sample(B.LengthCm * 0.5f, BP, BD);
	// the road runs along +X at y = 0: forward lanes on the right (+Y), oncoming on the left (-Y) = right-hand traffic
	TestTrue(TEXT("forward lane lies on the right of the centreline"), FP.Y > 100.0);
	TestTrue(TEXT("oncoming lane lies on the left"), BP.Y < -100.0);
	TestTrue(TEXT("forward lane travels along +X, oncoming against it"), FD.X > 0.99 && BD.X < -0.99);
	TestNearlyEqual(TEXT("lane length equals the road length"), F.LengthCm, 100000.0f, 1.0f);

	TestTrue(TEXT("lane ends at a junction"), F.EndJunction != INDEX_NONE);
	if (F.EndJunction != INDEX_NONE)
	{
		// every arm but the one the lane came in on (no U-turn); the outer right lane of a two-lane road may not turn left
		TestEqual(TEXT("successors = arms - 2 (no left turn from the outer right lane)"), F.Successors.Num(), W.Network->Junctions[F.EndJunction].Arms.Num() - 2);
		const int32 LeftLane = FindLaneId(Graph, *W.Network, TEXT("H_1_0"), 2);
		if (LeftLane != INDEX_NONE)
		{
			TestEqual(TEXT("the left lane goes straight or left"), Graph.Lanes[LeftLane].Successors.Num(), W.Network->Junctions[F.EndJunction].Arms.Num() - 2);
		}
		TestFalse(TEXT("no successor on the same road"), F.Successors.ContainsByPredicate([&](int32 Id) { return Graph.Lanes[Id].RoadIndex == F.RoadIndex; }));
		float MaxWeight = 0.0f;
		float StraightWeight = 0.0f;
		for (int32 i = 0; i < F.Successors.Num(); ++i)
		{
			MaxWeight = FMath::Max(MaxWeight, F.SuccessorWeight[i]);
			if (F.SuccessorTurnRad[i] < 0.1f)
			{
				StraightWeight = F.SuccessorWeight[i];
			}
		}
		TestTrue(TEXT("going straight is the most likely choice"), StraightWeight >= MaxWeight && StraightWeight > 0.0f);
	}

	// the same-lane overlap helper and the spawn pass need the density table
	TestEqual(TEXT("highway density per km"), RoamTraffic::BaseDensityPerKm(ERoamRoadClass::Highway), 3.5f);
	TestEqual(TEXT("regional density per km"), RoamTraffic::BaseDensityPerKm(ERoamRoadClass::Regional), 2.5f);
	TestEqual(TEXT("mountain density per km"), RoamTraffic::BaseDensityPerKm(ERoamRoadClass::Mountain), 1.2f);
	TestEqual(TEXT("dirt density per km"), RoamTraffic::BaseDensityPerKm(ERoamRoadClass::Dirt), 0.4f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTrafficIdmTest, "Roam.Traffic.Idm", ROAM_TRAFFIC_TEST_FLAGS)
bool FRoamTrafficIdmTest::RunTest(const FString& Parameters)
{
	using namespace RoamTraffic;
	TestNearlyEqual(TEXT("free road from standstill accelerates at a_max"), IdmAcceleration(0.0f, 30.0f, 1.0e6f, 0.0f, 2.0f, 3.0f, 1.5f, 2.5f), 2.0f, 0.01f);
	TestNearlyEqual(TEXT("no acceleration at the desired speed"), IdmAcceleration(30.0f, 30.0f, 1.0e6f, 0.0f, 2.0f, 3.0f, 1.5f, 2.5f), 0.0f, 0.02f);
	const float V = 15.0f;
	const float EquilibriumGap = (2.5f + V * 1.5f) / FMath::Sqrt(1.0f - FMath::Pow(V / 30.0f, 4.0f));
	TestNearlyEqual(TEXT("steady following gap gives zero acceleration"), IdmAcceleration(V, 30.0f, EquilibriumGap, 0.0f, 2.0f, 3.0f, 1.5f, 2.5f), 0.0f, 0.01f);
	TestTrue(TEXT("closing fast on a standing obstacle brakes hard"), IdmAcceleration(20.0f, 30.0f, 20.0f, 20.0f, 2.0f, 3.0f, 1.5f, 2.5f) < -3.0f);
	TestTrue(TEXT("smaller gap brakes harder"), IdmAcceleration(15.0f, 30.0f, 10.0f, 0.0f, 2.0f, 3.0f, 1.5f, 2.5f) < IdmAcceleration(15.0f, 30.0f, 30.0f, 0.0f, 2.0f, 3.0f, 1.5f, 2.5f));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTrafficFollowingTest, "Roam.Traffic.CarFollowing", ROAM_TRAFFIC_TEST_FLAGS)
bool FRoamTrafficFollowingTest::RunTest(const FString& Parameters)
{
	FTrafficTestWorld W;
	const int32 Lane = FindLaneId(W.Sim.GetGraph(), *W.Network, TEXT("H_1_0"), 1);
	if (!TestTrue(TEXT("test lane"), Lane != INDEX_NONE))
	{
		return false;
	}
	const FRoamLane& L = W.Sim.GetGraph().Lanes[Lane];
	const FRoamTrafficPlayer NoPlayer;

	// free flow: one car accelerates to about the limit and stays below it
	const int32 SoloId = W.Sim.SpawnAgent(Lane, 2000.0f, 0, 0.5f);
	for (int32 i = 0; i < 400; ++i) // 20 s
	{
		W.Sim.Step(0.05f, NoPlayer, 1.0f);
	}
	int32 Solo = W.Sim.FindAgentIndex(SoloId);
	if (!TestTrue(TEXT("solo car alive"), Solo != INDEX_NONE))
	{
		return false;
	}
	const float SoloMs = W.Sim.Agents[Solo].V * 0.01f;
	const float VMax = FMath::Min(L.SpeedLimitMs * 1.04f, W.Types[0].MaxSpeedKmh / 3.6f) + 0.5f;
	TestTrue(TEXT("free-flow speed stays within the limit"), SoloMs <= VMax);
	TestTrue(TEXT("free-flow car reaches a sensible speed"), SoloMs > 8.0f);
	W.Sim.Clear();

	// a stopped car 400 m ahead: the follower must stop behind it without touching it
	const int32 LeaderId = W.Sim.SpawnAgent(Lane, 50000.0f, 1, 0.0f);
	W.Sim.SettleAgent(W.Sim.FindAgentIndex(LeaderId), true);
	const int32 FollowerId = W.Sim.SpawnAgent(Lane, 10000.0f, 0, 0.9f);
	float MinGapCm = TNumericLimits<float>::Max();
	for (int32 i = 0; i < 1600; ++i) // 80 s
	{
		W.Sim.Step(0.05f, NoPlayer, 1.0f);
		const int32 Li = W.Sim.FindAgentIndex(LeaderId);
		const int32 Fi = W.Sim.FindAgentIndex(FollowerId);
		if (Li == INDEX_NONE || Fi == INDEX_NONE)
		{
			AddError(TEXT("agent vanished"));
			return false;
		}
		const float Gap = (W.Sim.Agents[Li].S - W.Sim.Agents[Li].LengthCm * 0.5f) - (W.Sim.Agents[Fi].S + W.Sim.Agents[Fi].LengthCm * 0.5f);
		MinGapCm = FMath::Min(MinGapCm, Gap);
	}
	const FRoamTrafficAgent& Follower = W.Sim.Agents[W.Sim.FindAgentIndex(FollowerId)];
	TestTrue(TEXT("follower never touches the stopped car"), MinGapCm > 0.0f);
	TestTrue(TEXT("follower came to a stop"), Follower.V < 20.0f);
	const float FinalGapM = (W.Sim.Agents[W.Sim.FindAgentIndex(LeaderId)].S - W.Sim.Agents[W.Sim.FindAgentIndex(LeaderId)].LengthCm * 0.5f - Follower.S - Follower.LengthCm * 0.5f) * 0.01f;
	TestTrue(TEXT("standstill gap is at least the minimum gap"), FinalGapM > 1.5f && FinalGapM < 12.0f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTrafficPlayerTest, "Roam.Traffic.Player", ROAM_TRAFFIC_TEST_FLAGS)
bool FRoamTrafficPlayerTest::RunTest(const FString& Parameters)
{
	FTrafficTestWorld W;
	const int32 Lane = FindLaneId(W.Sim.GetGraph(), *W.Network, TEXT("H_1_0"), 1);
	if (!TestTrue(TEXT("test lane"), Lane != INDEX_NONE))
	{
		return false;
	}
	const FRoamLane& L = W.Sim.GetGraph().Lanes[Lane];

	// a stationary player in the lane: the car stops short of it and honks
	FRoamTrafficPlayer Player;
	Player.bValid = true;
	FVector P, D;
	L.Sample(60000.0f, P, D);
	Player.Location = P + FVector(0.0, 0.0, 50.0);
	Player.Forward = D;
	const int32 Id = W.Sim.SpawnAgent(Lane, 15000.0f, 0, 0.9f);
	bool bHonked = false;
	for (int32 i = 0; i < 1200; ++i)
	{
		W.Sim.Step(0.05f, Player, 1.0f);
		const int32 Index = W.Sim.FindAgentIndex(Id);
		if (Index == INDEX_NONE)
		{
			AddError(TEXT("agent vanished"));
			return false;
		}
		bHonked |= W.Sim.Agents[Index].bWantsHorn;
		const FRoamTrafficAgent& A = W.Sim.Agents[Index];
		TestTrue(TEXT("never drives into the player"), A.S + A.LengthCm * 0.5f < 60000.0f - Player.HalfLengthCm);
	}
	const FRoamTrafficAgent& A = W.Sim.Agents[W.Sim.FindAgentIndex(Id)];
	TestTrue(TEXT("stopped behind the player"), A.V < 20.0f);
	TestTrue(TEXT("honked at the blocking player"), bHonked);

	// hit detection: the player drives into the back of a slower car
	W.Sim.Clear();
	const int32 HitId = W.Sim.SpawnAgent(Lane, 30000.0f, 0, 0.5f);
	const FRoamTrafficAgent& Target = W.Sim.Agents[W.Sim.FindAgentIndex(HitId)];
	FRoamTrafficPlayer Rammer;
	Rammer.bValid = true;
	Rammer.Forward = Target.Dir;
	Rammer.Location = Target.Pos - Target.Dir * 380.0;
	Rammer.Velocity = Target.Dir * 3000.0;
	Rammer.PrevVelocity = Rammer.Velocity;
	TArray<FRoamTrafficContact> Contacts;
	W.Sim.CollectPlayerContacts(Rammer, Contacts);
	if (TestEqual(TEXT("one contact"), Contacts.Num(), 1))
	{
		TestTrue(TEXT("it is a collision"), Contacts[0].bCollision);
		TestTrue(TEXT("the hit car is pushed forward"), FVector::DotProduct(Contacts[0].AgentVelocityAfterCms, Target.Dir) > Target.V);
		TestTrue(TEXT("impact speed is the closing speed"), Contacts[0].ImpactSpeedMs > 10.0f);
	}
	// a gentle touch (closing speed below 8 km/h) does not trigger the reaction
	Rammer.Velocity = Target.Dir * (Target.V + 100.0f);
	Rammer.PrevVelocity = Rammer.Velocity;
	W.Sim.CollectPlayerContacts(Rammer, Contacts);
	TestEqual(TEXT("slow touch is no collision"), Contacts.Num(), 0);
	// reaction state machine
	const int32 HitIndex = W.Sim.FindAgentIndex(HitId);
	W.Sim.ApplyHit(HitIndex);
	TestTrue(TEXT("agent is in the hit state"), W.Sim.Agents[HitIndex].State == ERoamTrafficAgentState::Hit);
	W.Sim.SettleAgent(HitIndex, true);
	TestTrue(TEXT("agent became an obstacle"), W.Sim.Agents[HitIndex].State == ERoamTrafficAgentState::Obstacle);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTrafficJunctionTest, "Roam.Traffic.Junction", ROAM_TRAFFIC_TEST_FLAGS)
bool FRoamTrafficJunctionTest::RunTest(const FString& Parameters)
{
	FTrafficTestWorld W;
	const FRoamLaneGraph& Graph = W.Sim.GetGraph();
	const int32 LaneA = FindLaneId(Graph, *W.Network, TEXT("H_1_0"), 1); // from the west into the centre junction
	const int32 LaneB = FindLaneId(Graph, *W.Network, TEXT("V_1_0"), 1); // from the south into the same junction
	if (!TestTrue(TEXT("both approach lanes exist"), LaneA != INDEX_NONE && LaneB != INDEX_NONE))
	{
		return false;
	}
	const FRoamTrafficPlayer NoPlayer;
	TestEqual(TEXT("both lanes end at the same junction"), Graph.Lanes[LaneA].EndJunction, Graph.Lanes[LaneB].EndJunction);

	// four rounds with different arrival offsets: the cars arrive nearly together and must never hold conflicting tokens
	const float Offsets[4] = { 0.0f, 400.0f, -900.0f, 1800.0f };
	for (const float Offset : Offsets)
	{
		W.Sim.Clear();
		const int32 IdA = W.Sim.SpawnAgent(LaneA, Graph.Lanes[LaneA].LengthCm - 14000.0f, 0, 0.9f);
		const int32 IdB = W.Sim.SpawnAgent(LaneB, Graph.Lanes[LaneB].LengthCm - 14000.0f + Offset, 5, 0.9f);
		bool bPassedA = false;
		bool bPassedB = false;
		int32 MaxConflicts = 0;
		for (int32 i = 0; i < 1000; ++i) // 50 s
		{
			W.Sim.Step(0.05f, NoPlayer, 1.0f);
			MaxConflicts = FMath::Max(MaxConflicts, W.Sim.CountConflictingClaims());
			const int32 Ia = W.Sim.FindAgentIndex(IdA);
			const int32 Ib = W.Sim.FindAgentIndex(IdB);
			if (Ia != INDEX_NONE && W.Sim.Agents[Ia].Lane != LaneA)
			{
				bPassedA = true;
			}
			if (Ib != INDEX_NONE && W.Sim.Agents[Ib].Lane != LaneB)
			{
				bPassedB = true;
			}
		}
		TestEqual(*FString::Printf(TEXT("no conflicting junction claims (offset %.0f)"), Offset), MaxConflicts, 0);
		TestTrue(*FString::Printf(TEXT("car A crossed the junction (offset %.0f)"), Offset), bPassedA);
		TestTrue(*FString::Printf(TEXT("car B crossed the junction (offset %.0f)"), Offset), bPassedB);
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTrafficSpawnTest, "Roam.Traffic.SpawnAndRun", ROAM_TRAFFIC_TEST_FLAGS)
bool FRoamTrafficSpawnTest::RunTest(const FString& Parameters)
{
	FTrafficTestWorld W;
	const FRoamTrafficPlayer NoPlayer;
	const auto NoSuppression = [](const FVector&) { return false; };

	const int32 Initial = W.Sim.SpawnAround(FVector::ZeroVector, 1.0f, 1.0f, true, 200, NoSuppression);
	TestTrue(TEXT("initial fill spawns traffic"), Initial > 5 && Initial <= RoamTraffic::MaxAgents);
	for (const FRoamTrafficAgent& A : W.Sim.Agents)
	{
		const double D = FVector::Dist2D(A.Pos, FVector::ZeroVector);
		TestTrue(TEXT("initial agents lie between 200 m and 900 m"), D >= 19900.0 && D <= 90500.0);
	}
	TestEqual(TEXT("no overlaps after spawning"), CountSameLaneOverlaps(W.Sim), 0);

	// suppression: nothing spawns inside a suppressed sphere
	W.Sim.Clear();
	const auto SuppressAll = [](const FVector&) { return true; };
	TestEqual(TEXT("suppressed area stays empty"), W.Sim.SpawnAround(FVector::ZeroVector, 1.0f, 1.0f, true, 200, SuppressAll), 0);

	// density 0 and night factor
	TestEqual(TEXT("density 0 spawns nothing"), W.Sim.SpawnAround(FVector::ZeroVector, 0.0f, 1.0f, true, 200, NoSuppression), 0);
	const int32 Day = W.Sim.SpawnAround(FVector::ZeroVector, 1.0f, 1.0f, true, 200, NoSuppression);
	W.Sim.Clear();
	const int32 Night = W.Sim.SpawnAround(FVector::ZeroVector, 1.0f, RoamTraffic::NightDensityFactor, true, 200, NoSuppression);
	TestTrue(TEXT("night traffic is thinner"), Night < Day);
	W.Sim.Clear();

	// two minutes of simulation with the steady-state spawn ring and the player parked at the origin
	W.Sim.SpawnAround(FVector::ZeroVector, 1.0f, 1.0f, true, 200, NoSuppression);
	int32 MaxConflicts = 0;
	int32 Overlaps = 0;
	int32 MaxAgents = 0;
	float SpawnTimer = 0.0f;
	for (int32 i = 0; i < 2400; ++i)
	{
		W.Sim.Step(0.05f, NoPlayer, 1.0f);
		SpawnTimer += 0.05f;
		if (SpawnTimer >= 0.3f)
		{
			SpawnTimer = 0.0f;
			W.Sim.SpawnAround(FVector::ZeroVector, 1.0f, 1.0f, false, 3, NoSuppression);
			W.Sim.RemoveFarAgents(FVector::ZeroVector, RoamTraffic::DataRingCm);
		}
		MaxConflicts = FMath::Max(MaxConflicts, W.Sim.CountConflictingClaims());
		Overlaps += CountSameLaneOverlaps(W.Sim);
		MaxAgents = FMath::Max(MaxAgents, W.Sim.Agents.Num());
		for (const FRoamTrafficAgent& A : W.Sim.Agents)
		{
			if (!A.Pos.ContainsNaN() && FMath::IsFinite(A.V) && A.V >= 0.0f && A.V < 6000.0f)
			{
				continue;
			}
			AddError(TEXT("agent state is not finite / has an invalid speed"));
			return false;
		}
	}
	TestEqual(TEXT("no conflicting junction claims in two minutes"), MaxConflicts, 0);
	TestEqual(TEXT("no same-lane overlaps in two minutes"), Overlaps, 0);
	TestTrue(TEXT("agent count stays bounded"), MaxAgents <= RoamTraffic::MaxAgents);
	TestTrue(TEXT("traffic is still there after two minutes"), W.Sim.Agents.Num() > 0);
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
