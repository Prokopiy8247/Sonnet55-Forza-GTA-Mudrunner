// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Activities/RoamActivityLogic.h"
#include "Activities/RoamActivitySubsystem.h"
#include "Components/StaticMeshComponent.h"
#include "Core/RoamCollision.h"
#include "Core/RoamTypes.h"
#include "Data/RoamRoadNetwork.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/Level.h"
#include "Engine/World.h"
#include "GameFramework/WorldSettings.h"
#include "Kismet/GameplayStatics.h"
#include "Save/RoamSaveGame.h"
#include "Save/RoamSaveSubsystem.h"
#include "UObject/StrongObjectPtr.h"
#include "Vehicle/RoamVehicle.h"
#include "Vehicle/RoamVehicleMovement.h"

#define ROAM_ACT_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

namespace
{
	FRoamGate MakeTestGate(const FVector& Center, const FVector& Forward = FVector::ForwardVector, float HalfWidth = 800.0f)
	{
		FRoamGate Gate;
		Gate.Center = Center;
		Gate.Forward = Forward;
		Gate.HalfWidthCm = HalfWidth;
		Gate.HalfHeightCm = 450.0f;
		return Gate;
	}

	FRoamActivitySample MakeTestSample(double Time, const FVector& Position, float SpeedKmh, const FVector& Heading = FVector::ForwardVector, int32 WheelsOnGround = 4, const FVector& Travel = FVector::ForwardVector)
	{
		FRoamActivitySample Sample;
		Sample.Time = Time;
		Sample.Position = Position;
		Sample.VelocityCmS = Travel.GetSafeNormal() * Roam::KmhToCms(SpeedKmh);
		Sample.Forward = Heading.GetSafeNormal();
		Sample.WheelsOnGround = WheelsOnGround;
		return Sample;
	}

	/** A game instance + world that ticks subsystems (the way the game does), cleaned up on scope exit. */
	struct FActivityTestWorld
	{
		UGameInstance* GameInstance = nullptr;
		UWorld* World = nullptr;

		bool Create()
		{
			if (!GEngine)
			{
				return false;
			}
			GameInstance = NewObject<UGameInstance>(GEngine);
			GameInstance->AddToRoot();
			GameInstance->InitializeStandalone();
			World = GameInstance->GetWorld();
			if (!World)
			{
				return false;
			}
			World->InitializeActorsForPlay(FURL());
			if (ULevel* Level = World->PersistentLevel)
			{
				Level->bIsVisible = true; // a bare CreateWorld level is not "added to the world", so its actors would not tick
			}
			World->BeginPlay();
			// No game mode in this bare world, so nothing else marks it as begun: actors spawned later would never BeginPlay or tick.
			if (AWorldSettings* Settings = World->GetWorldSettings())
			{
				Settings->NotifyBeginPlay();
				Settings->NotifyMatchStarted();
			}
			return true;
		}

		~FActivityTestWorld()
		{
			if (World)
			{
				World->DestroyWorld(false);
				if (GEngine)
				{
					GEngine->DestroyWorldContext(World);
				}
			}
			if (GameInstance)
			{
				GameInstance->Shutdown();
				GameInstance->RemoveFromRoot();
			}
		}
	};
}

// ------------------------------------------------------------------------------------------------------------------
// Pure logic
// ------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamActivityGateTest, "Roam.Activity.GateCrossing", ROAM_ACT_TEST_FLAGS)
bool FRoamActivityGateTest::RunTest(const FString& Parameters)
{
	const FRoamGate Gate = MakeTestGate(FVector(1000.0, 0.0, 150.0), FVector::ForwardVector, 600.0f);
	RoamActivity::FGateCrossing X;

	TestTrue(TEXT("forward crossing"), RoamActivity::SegmentCrossesGate(Gate, FVector(900.0, 0.0, 0.0), FVector(1100.0, 0.0, 0.0), X));
	TestNearlyEqual(TEXT("sub-frame alpha"), X.Alpha, 0.5f, 1.0e-4f);
	TestTrue(TEXT("flagged forward"), X.bForward);

	TestFalse(TEXT("reverse is ignored"), RoamActivity::SegmentCrossesGate(Gate, FVector(1100.0, 0.0, 0.0), FVector(900.0, 0.0, 0.0), X));
	TestTrue(TEXT("reverse accepted on request"), RoamActivity::SegmentCrossesGate(Gate, FVector(1100.0, 0.0, 0.0), FVector(900.0, 0.0, 0.0), X, true));
	TestFalse(TEXT("reverse flagged"), X.bForward);

	TestFalse(TEXT("outside the gate width"), RoamActivity::SegmentCrossesGate(Gate, FVector(900.0, 700.0, 0.0), FVector(1100.0, 700.0, 0.0), X));
	TestFalse(TEXT("above the gate"), RoamActivity::SegmentCrossesGate(Gate, FVector(900.0, 0.0, 1500.0), FVector(1100.0, 0.0, 1500.0), X));
	TestTrue(TEXT("fast car does not tunnel (50 m in one step)"), RoamActivity::SegmentCrossesGate(Gate, FVector(-2000.0, 0.0, 0.0), FVector(3000.0, 0.0, 0.0), X));

	TestFalse(TEXT("starting exactly on the plane is not a new crossing"), RoamActivity::SegmentCrossesGate(Gate, FVector(1000.0, 0.0, 0.0), FVector(1100.0, 0.0, 0.0), X));
	TestTrue(TEXT("ending exactly on the plane is the crossing"), RoamActivity::SegmentCrossesGate(Gate, FVector(900.0, 0.0, 0.0), FVector(1000.0, 0.0, 0.0), X));

	TestTrue(TEXT("lateral crossing"), RoamActivity::SegmentCrossesGate(Gate, FVector(900.0, 300.0, 0.0), FVector(1100.0, 300.0, 0.0), X));
	TestNearlyEqual(TEXT("right of the gate direction is positive"), X.LateralCm, 300.0f, 0.01f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamActivityThresholdTest, "Roam.Activity.StarsAndThresholds", ROAM_ACT_TEST_FLAGS)
bool FRoamActivityThresholdTest::RunTest(const FString& Parameters)
{
	const FVector Trap = RoamActivity::SpeedTrapThresholds(220.0f);
	TestEqual(TEXT("trap 1 star"), static_cast<int32>(Trap.X), 60);
	TestEqual(TEXT("trap 2 stars"), static_cast<int32>(Trap.Y), 150);
	TestEqual(TEXT("trap 3 stars"), static_cast<int32>(Trap.Z), 220);

	const FVector Zone = RoamActivity::SpeedZoneThresholds(115.0f);
	TestEqual(TEXT("zone 1 star"), static_cast<int32>(Zone.X), 45);
	TestEqual(TEXT("zone 2 stars"), static_cast<int32>(Zone.Y), 85);

	const FVector Jump = RoamActivity::JumpThresholds(100.0f);
	TestEqual(TEXT("jump 1 star"), static_cast<int32>(Jump.X), 20);
	TestEqual(TEXT("jump 2 stars"), static_cast<int32>(Jump.Y), 55);

	const FVector Drift = RoamActivity::DriftThresholds(68580.0f);
	TestEqual(TEXT("drift 3 stars rounds to 2500"), static_cast<int32>(Drift.Z), 67500);
	TestTrue(TEXT("drift 1 star about 8%"), Drift.X >= 5000.0 && Drift.X <= 6000.0);
	TestTrue(TEXT("drift 2 stars about 53%"), Drift.Y >= 35500.0 && Drift.Y <= 36500.0);

	TestEqual(TEXT("below the first threshold"), RoamActivity::StarsForValue(Trap, 59.0f, false), 0);
	TestEqual(TEXT("one star"), RoamActivity::StarsForValue(Trap, 60.0f, false), 1);
	TestEqual(TEXT("two stars"), RoamActivity::StarsForValue(Trap, 150.0f, false), 2);
	TestEqual(TEXT("three stars"), RoamActivity::StarsForValue(Trap, 250.0f, false), 3);

	const FVector Times(150.0, 130.0, 115.0);
	TestEqual(TEXT("time: fast"), RoamActivity::StarsForValue(Times, 114.0f, true), 3);
	TestEqual(TEXT("time: silver"), RoamActivity::StarsForValue(Times, 120.0f, true), 2);
	TestEqual(TEXT("time: bronze"), RoamActivity::StarsForValue(Times, 140.0f, true), 1);
	TestEqual(TEXT("time: too slow"), RoamActivity::StarsForValue(Times, 160.0f, true), 0);

	TestEqual(TEXT("first clear with 3 stars"), RoamActivity::XpForStarImprovement(0, 3, 100), 550);
	TestEqual(TEXT("improvement 2 -> 3"), RoamActivity::XpForStarImprovement(2, 3, 100), 250);
	TestEqual(TEXT("no farming"), RoamActivity::XpForStarImprovement(3, 3, 100), 0);
	TestEqual(TEXT("time format"), RoamActivity::FormatTime(75.5f), FString(TEXT("1:15.50")));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamActivityDriftTrackerTest, "Roam.Activity.DriftScore", ROAM_ACT_TEST_FLAGS)
bool FRoamActivityDriftTrackerTest::RunTest(const FString& Parameters)
{
	const float Dt = 1.0f / 60.0f;

	// 12 s at 80 km/h and 30 degrees: base 1200 pts/s, multiplier x1..x5 (+1 per 2 s), 0.35 s entry hold -> about 45,900.
	RoamActivity::FDriftTracker Tracker;
	for (int32 i = 0; i < 720; ++i)
	{
		Tracker.Step(Dt, 80.0f, 30.0f, true);
	}
	TestEqual(TEXT("multiplier reached x5"), Tracker.Multiplier, 5);
	TestTrue(FString::Printf(TEXT("12 s drift score %.0f in 44000..47500"), Tracker.GetTotal()), Tracker.GetTotal() > 44000.0f && Tracker.GetTotal() < 47500.0f);
	const float Live = Tracker.GetTotal();
	Tracker.LoseChain();
	TestEqual(TEXT("crash loses the live chain"), Tracker.GetTotal(), 0.0f);
	TestTrue(TEXT("live chain was positive"), Live > 0.0f);

	// Entry gates: slip below 12 degrees or speed below 30 km/h never scores.
	Tracker.Reset();
	for (int32 i = 0; i < 300; ++i)
	{
		Tracker.Step(Dt, 80.0f, 10.0f, true);
		Tracker.Step(Dt, 25.0f, 40.0f, true);
	}
	TestEqual(TEXT("below the entry thresholds nothing scores"), Tracker.GetTotal(), 0.0f);

	// A 0.5 s gap keeps the chain (S-bend flick), a 1.0 s gap banks it.
	Tracker.Reset();
	for (int32 i = 0; i < 180; ++i) { Tracker.Step(Dt, 70.0f, 30.0f, true); }
	for (int32 i = 0; i < 30; ++i) { Tracker.Step(Dt, 70.0f, 0.0f, true); }
	TestTrue(TEXT("chain survives a short gap"), Tracker.bDrifting);
	TestEqual(TEXT("nothing banked yet"), Tracker.ZoneScore, 0.0f);
	for (int32 i = 0; i < 180; ++i) { Tracker.Step(Dt, 70.0f, 30.0f, true); }
	for (int32 i = 0; i < 60; ++i) { Tracker.Step(Dt, 70.0f, 0.0f, true); }
	TestFalse(TEXT("long gap ends the chain"), Tracker.bDrifting);
	TestTrue(TEXT("long gap banks the chain"), Tracker.ZoneScore > 1000.0f);
	const float Banked = Tracker.ZoneScore;
	for (int32 i = 0; i < 240; ++i) { Tracker.Step(Dt, 70.0f, 30.0f, true); }
	Tracker.LoseChain();
	TestEqual(TEXT("banked chains survive a crash"), Tracker.GetTotal(), Banked);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamActivityPlacementTest, "Roam.Activity.Placement", ROAM_ACT_TEST_FLAGS)
bool FRoamActivityPlacementTest::RunTest(const FString& Parameters)
{
	// 1) the synthetic grid network: flat, so no jumps; everything else is placed.
	TStrongObjectPtr<URoamRoadNetwork> Network(URoamRoadNetwork::BuildGeneratedForTests(GetTransientPackage(), 3, 100000.0f, 500.0f));
	TArray<FRoamActivityDef> Defs;
	RoamActivity::GenerateDefaultActivityDefs(*Network, nullptr, RoamActivity::FPlacementOptions(), Defs);

	int32 Counts[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
	TSet<FName> Ids;
	for (const FRoamActivityDef& Def : Defs)
	{
		Counts[FMath::Clamp(static_cast<int32>(Def.Type), 0, 7)]++;
		TestFalse(FString::Printf(TEXT("unique id %s"), *Def.ActivityId.ToString()), Ids.Contains(Def.ActivityId));
		Ids.Add(Def.ActivityId);
		TestTrue(FString::Printf(TEXT("%s has gates"), *Def.ActivityId.ToString()), Def.Gates.Num() >= 1);
		TestFalse(FString::Printf(TEXT("%s has a road"), *Def.ActivityId.ToString()), Def.RoadId.IsNone());
		if (Def.Type != ERoamActivityType::Collectible && Def.Type != ERoamActivityType::PhotoSpot)
		{
			const FVector T = Def.StarThresholds;
			const bool bOrdered = Def.bLowerIsBetter ? (T.X >= T.Y && T.Y >= T.Z && T.Z > 0.0) : (T.X <= T.Y && T.Y <= T.Z && T.Z > 0.0);
			TestTrue(FString::Printf(TEXT("%s thresholds ordered (%.1f %.1f %.1f)"), *Def.ActivityId.ToString(), T.X, T.Y, T.Z), bOrdered);
		}
		for (const FRoamGate& Gate : Def.Gates)
		{
			TestTrue(TEXT("gate normal is a unit vector"), FMath::IsNearlyEqual(Gate.Forward.Size(), 1.0, 1.0e-3));
		}
	}
	TestEqual(TEXT("12 speed traps"), Counts[static_cast<int32>(ERoamActivityType::SpeedTrap)], 12);
	TestTrue(TEXT("speed zones placed"), Counts[static_cast<int32>(ERoamActivityType::SpeedZone)] >= 3);
	TestTrue(TEXT("drift zones placed"), Counts[static_cast<int32>(ERoamActivityType::DriftZone)] >= 2);
	TestEqual(TEXT("no jumps on a flat network"), Counts[static_cast<int32>(ERoamActivityType::DangerSign)], 0);
	TestTrue(TEXT("races placed"), Counts[static_cast<int32>(ERoamActivityType::CheckpointRace)] >= 4);
	TestEqual(TEXT("one time trial"), Counts[static_cast<int32>(ERoamActivityType::TimeTrial)], 1);
	TestTrue(TEXT("collectibles and photo spots placed"), Counts[static_cast<int32>(ERoamActivityType::Collectible)] >= 1 && Counts[static_cast<int32>(ERoamActivityType::PhotoSpot)] >= 1);

	TArray<FRoamActivityDef> Again;
	RoamActivity::GenerateDefaultActivityDefs(*Network, nullptr, RoamActivity::FPlacementOptions(), Again);
	TestEqual(TEXT("generation is deterministic"), Again.Num(), Defs.Num());

	// 2) a straight road with a crest gets a jump.
	TStrongObjectPtr<URoamRoadNetwork> Crest(NewObject<URoamRoadNetwork>(GetTransientPackage()));
	FRoamRoad& Road = Crest->Roads.AddDefaulted_GetRef();
	Road.RoadId = TEXT("CREST_ROAD");
	Road.RoadClass = ERoamRoadClass::Regional;
	for (float X = 0.0f; X <= 300000.0f; X += 500.0f)
	{
		FRoamRoadSample& Sample = Road.Samples.AddDefaulted_GetRef();
		const float Normalised = (X - 150000.0f) / 6000.0f;
		Sample.Position = FVector(X, 0.0f, 600.0f * FMath::Exp(-Normalised * Normalised));
		Sample.WidthCm = 700.0f;
	}
	Crest->BuildSpatialIndex();
	TArray<FRoamActivityDef> CrestDefs;
	RoamActivity::GenerateDefaultActivityDefs(*Crest, nullptr, RoamActivity::FPlacementOptions(), CrestDefs);
	int32 Jumps = 0;
	for (const FRoamActivityDef& Def : CrestDefs)
	{
		if (Def.Type == ERoamActivityType::DangerSign)
		{
			++Jumps;
			TestTrue(TEXT("jump gate sits before the crest"), Def.Gates[0].Center.X < 150000.0 && Def.Gates[0].Center.X > 130000.0);
			TestTrue(TEXT("jump distance thresholds are sane"), Def.StarThresholds.Z >= 40.0 && Def.StarThresholds.Z <= 250.0);
		}
	}
	TestTrue(TEXT("a straight crest gets a danger sign"), Jumps >= 1);
	return true;
}

// ------------------------------------------------------------------------------------------------------------------
// Subsystem driven with synthetic samples (exact, frame-rate independent expectations)
// ------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamActivitySubsystemSamplesTest, "Roam.Activity.SubsystemSamples", ROAM_ACT_TEST_FLAGS)
bool FRoamActivitySubsystemSamplesTest::RunTest(const FString& Parameters)
{
	FActivityTestWorld Fixture;
	if (!TestTrue(TEXT("test world created"), Fixture.Create()))
	{
		return false;
	}
	URoamActivitySubsystem* Activities = Fixture.World->GetSubsystem<URoamActivitySubsystem>();
	URoamSaveSubsystem* Save = Fixture.GameInstance->GetSubsystem<URoamSaveSubsystem>();
	if (!TestNotNull(TEXT("activity subsystem"), Activities) || !TestNotNull(TEXT("save subsystem"), Save))
	{
		return false;
	}
	Activities->bAutoSaveOnResult = false;

	// ---- speed trap: speed interpolated at the exact crossing -----------------------------------------------------------
	{
		FRoamActivityDef Trap;
		Trap.ActivityId = TEXT("test_trap");
		Trap.Type = ERoamActivityType::SpeedTrap;
		Trap.Gates.Add(MakeTestGate(FVector(1000.0, 0.0, 150.0)));
		Trap.StarThresholds = FVector(50.0, 100.0, 150.0);
		Activities->RegisterActivity(Trap);

		Activities->ProcessSample(MakeTestSample(0.00, FVector(900.0, 0.0, 0.0), 100.0f));
		Activities->ProcessSample(MakeTestSample(0.02, FVector(1100.0, 0.0, 0.0), 120.0f));
		const FRoamActivityResult& Result = Activities->GetLastResult();
		TestEqual(TEXT("trap result id"), Result.ActivityId, FName(TEXT("test_trap")));
		TestNearlyEqual(TEXT("trap speed interpolated at the crossing (110 km/h)"), Result.Value, 110.0f, 0.05f);
		TestEqual(TEXT("trap stars"), Result.Stars, 2);
		TestTrue(TEXT("first result is a best"), Result.bNewBest);
		TestTrue(TEXT("xp awarded"), Result.XpAwarded > 0);
		TestEqual(TEXT("state is Result"), Activities->GetActivityState(Trap.ActivityId), ERoamActivityState::Result);
		float Best = 0.0f;
		TestTrue(TEXT("personal best stored"), Save->GetPersonalBest(Trap.ActivityId, Best));
		TestNearlyEqual(TEXT("personal best value"), Best, 110.0f, 0.05f);
		TestEqual(TEXT("stars stored"), Activities->GetStars(Trap.ActivityId), 2);
	}

	// ---- speed zone: average speed over the stretch ---------------------------------------------------------------------
	{
		FRoamActivityDef Zone;
		Zone.ActivityId = TEXT("test_zone");
		Zone.Type = ERoamActivityType::SpeedZone;
		const double Base = 100000.0;
		Zone.Gates.Add(MakeTestGate(FVector(Base, 0.0, 150.0)));
		Zone.Gates.Add(MakeTestGate(FVector(Base + 10000.0, 0.0, 150.0)));
		Zone.StarThresholds = FVector(40.0, 80.0, 110.0);
		Activities->RegisterActivity(Zone);
		int32 ActiveEvents = 0;
		const FDelegateHandle Handle = Activities->OnActivityActive.AddLambda([&ActiveEvents](FName, bool, const FBox&) { ++ActiveEvents; });

		const double Dt = 1.0 / 30.0;
		const float Speed = 100.0f;
		const double V = Roam::KmhToCms(Speed);
		for (int32 i = 0; i < 400; ++i)
		{
			Activities->ProcessSample(MakeTestSample(10.0 + i * Dt, FVector(Base - 500.0 + V * i * Dt, 0.0, 0.0), Speed));
		}
		Activities->OnActivityActive.Remove(Handle);
		const FRoamActivityResult& Result = Activities->GetLastResult();
		TestEqual(TEXT("zone result id"), Result.ActivityId, FName(TEXT("test_zone")));
		TestNearlyEqual(TEXT("zone average speed"), Result.Value, 100.0f, 0.5f);
		TestEqual(TEXT("zone stars"), Result.Stars, 2);
		TestEqual(TEXT("zone broadcast active + inactive"), ActiveEvents, 2);
		TestTrue(TEXT("no attempt left running"), Activities->GetActiveActivityId().IsNone());
	}

	// ---- road race: sub-frame checkpoint timing, personal best only improves --------------------------------------------
	{
		FRoamActivityDef Race;
		Race.ActivityId = TEXT("test_race");
		Race.Type = ERoamActivityType::CheckpointRace;
		const double Base = 200000.0;
		for (int32 g = 0; g < 4; ++g)
		{
			Race.Gates.Add(MakeTestGate(FVector(Base + 5000.0 * g, 0.0, 150.0)));
		}
		Race.StarThresholds = FVector(10.0, 8.0, 5.5);
		Race.bLowerIsBetter = true;
		Activities->RegisterActivity(Race);

		const double Dt = 1.0 / 30.0;
		const auto Drive = [&](double StartTime, float SpeedMs)
		{
			const double V = SpeedMs * 100.0;
			for (int32 i = 0; i < 400; ++i)
			{
				Activities->ProcessSample(MakeTestSample(StartTime + i * Dt, FVector(Base - 317.0 + V * i * Dt, 0.0, 0.0), Roam::MsToKmh(SpeedMs)));
			}
		};
		Drive(100.0, 30.0f);
		FRoamActivityResult Result = Activities->GetLastResult();
		TestEqual(TEXT("race result id"), Result.ActivityId, FName(TEXT("test_race")));
		TestNearlyEqual(TEXT("150 m at 30 m/s takes 5.00 s"), Result.Value, 5.0f, 0.02f);
		TestEqual(TEXT("race 3 stars"), Result.Stars, 3);
		TestTrue(TEXT("race first result is a best"), Result.bNewBest);

		Drive(200.0, 25.0f);
		Result = Activities->GetLastResult();
		TestNearlyEqual(TEXT("150 m at 25 m/s takes 6.00 s"), Result.Value, 6.0f, 0.02f);
		TestFalse(TEXT("slower run is not a best"), Result.bNewBest);
		TestNearlyEqual(TEXT("delta to best"), Result.DeltaToBest, 1.0f, 0.03f);
		float Best = 0.0f;
		TestTrue(TEXT("race best stored"), Save->GetPersonalBest(Race.ActivityId, Best));
		TestNearlyEqual(TEXT("best stays the faster run"), Best, 5.0f, 0.02f);
		TestEqual(TEXT("stars never decrease"), Activities->GetStars(Race.ActivityId), 3);
	}

	// ---- drift zone: score from slip angle x speed with multiplier ------------------------------------------------------
	{
		FRoamActivityDef Drift;
		Drift.ActivityId = TEXT("test_drift");
		Drift.Type = ERoamActivityType::DriftZone;
		const double Base = 300000.0;
		Drift.Gates.Add(MakeTestGate(FVector(Base, 0.0, 150.0)));
		Drift.Gates.Add(MakeTestGate(FVector(Base + 20000.0, 0.0, 150.0)));
		Drift.StarThresholds = FVector(5000.0, 15000.0, 40000.0);
		Activities->RegisterActivity(Drift);

		const double Dt = 1.0 / 60.0;
		const float Speed = 80.0f;
		const double V = Roam::KmhToCms(Speed);
		const FVector Heading(FMath::Cos(FMath::DegreesToRadians(30.0)), FMath::Sin(FMath::DegreesToRadians(30.0)), 0.0);
		for (int32 i = 0; i < 700; ++i)
		{
			Activities->ProcessSample(MakeTestSample(300.0 + i * Dt, FVector(Base - 500.0 + V * i * Dt, 0.0, 0.0), Speed, Heading));
		}
		const FRoamActivityResult& Result = Activities->GetLastResult();
		TestEqual(TEXT("drift result id"), Result.ActivityId, FName(TEXT("test_drift")));
		TestTrue(FString::Printf(TEXT("drift zone score %.0f in 26000..30000"), Result.Value), Result.Value > 26000.0f && Result.Value < 30000.0f);
		TestEqual(TEXT("drift stars"), Result.Stars, 2);
	}

	// ---- danger sign: flight distance from takeoff to landing -----------------------------------------------------------
	{
		FRoamActivityDef Jump;
		Jump.ActivityId = TEXT("test_jump");
		Jump.Type = ERoamActivityType::DangerSign;
		const double Base = 400000.0;
		Jump.Gates.Add(MakeTestGate(FVector(Base, 0.0, 150.0)));
		Jump.StarThresholds = FVector(10.0, 25.0, 40.0);
		Activities->RegisterActivity(Jump);

		const double Dt = 1.0 / 60.0;
		const float Speed = 100.0f;
		const double V = Roam::KmhToCms(Speed);
		for (int32 i = 0; i <= 260; ++i)
		{
			const bool bAir = i >= 31 && i <= 119; // takeoff after sample 30, landing at sample 120 (1.5 s of flight)
			Activities->ProcessSample(MakeTestSample(500.0 + i * Dt, FVector(Base - 1000.0 + V * i * Dt, 0.0, bAir ? 200.0 : 0.0), Speed, FVector::ForwardVector, bAir ? 0 : 4));
		}
		const FRoamActivityResult& Result = Activities->GetLastResult();
		TestEqual(TEXT("jump result id"), Result.ActivityId, FName(TEXT("test_jump")));
		TestNearlyEqual(TEXT("jump distance = 1.5 s x 27.78 m/s"), Result.Value, 41.67f, 0.2f);
		TestEqual(TEXT("jump stars"), Result.Stars, 3);
	}

	// ---- a teleport cancels the running attempt ------------------------------------------------------------------------
	{
		FRoamActivityDef Zone;
		Zone.ActivityId = TEXT("test_cancel");
		Zone.Type = ERoamActivityType::SpeedZone;
		Zone.Gates.Add(MakeTestGate(FVector(50000.0, 0.0, 150.0)));
		Zone.Gates.Add(MakeTestGate(FVector(60000.0, 0.0, 150.0)));
		Zone.StarThresholds = FVector(40.0, 80.0, 110.0);
		Activities->RegisterActivity(Zone);
		Activities->ProcessSample(MakeTestSample(900.0, FVector(49900.0, 0.0, 0.0), 100.0f));
		Activities->ProcessSample(MakeTestSample(900.1, FVector(50100.0, 0.0, 0.0), 100.0f));
		TestEqual(TEXT("zone is active"), Activities->GetActiveActivityId(), Zone.ActivityId);
		Activities->ProcessSample(MakeTestSample(900.2, FVector(80000.0, 0.0, 0.0), 100.0f)); // 300 m in 0.1 s = teleport
		TestTrue(TEXT("teleport cancels the attempt"), Activities->GetActiveActivityId().IsNone());
		TestFalse(TEXT("cancelled attempt reports no completion"), Activities->GetLastResult().bCompleted);
	}

	// ---- persistence of the personal bests through the save game ---------------------------------------------------------
	{
		TStrongObjectPtr<URoamSaveGame> SaveObject(NewObject<URoamSaveGame>(GetTransientPackage()));
		SaveObject->Profile = Save->GetProfile();
		TArray<uint8> Bytes;
		TestTrue(TEXT("profile serialises"), UGameplayStatics::SaveGameToMemory(SaveObject.Get(), Bytes));
		URoamSaveGame* Loaded = Cast<URoamSaveGame>(UGameplayStatics::LoadGameFromMemory(Bytes));
		TStrongObjectPtr<URoamSaveGame> Keep(Loaded);
		if (TestNotNull(TEXT("profile loads"), Loaded))
		{
			const float* TrapBest = Loaded->Profile.PersonalBests.Find(TEXT("test_trap"));
			const float* RaceBest = Loaded->Profile.PersonalBests.Find(TEXT("test_race"));
			TestTrue(TEXT("trap best survives a save/load round trip"), TrapBest && FMath::IsNearlyEqual(*TrapBest, 110.0f, 0.05f));
			TestTrue(TEXT("race best survives a save/load round trip"), RaceBest && FMath::IsNearlyEqual(*RaceBest, 5.0f, 0.02f));
			const int32* RaceStars = Loaded->Profile.ActivityStars.Find(TEXT("test_race"));
			TestTrue(TEXT("stars survive a save/load round trip"), RaceStars && *RaceStars == 3);
			TestTrue(TEXT("xp survives a save/load round trip"), Loaded->Profile.TotalXp > 0);
		}
	}
	return true;
}

// ------------------------------------------------------------------------------------------------------------------
// A real vehicle (scripted AI input) driving through a speed trap in a ticking world
// ------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamActivityDriveThroughTrapTest, "Roam.Activity.DriveThroughSpeedTrap", ROAM_ACT_TEST_FLAGS)
bool FRoamActivityDriveThroughTrapTest::RunTest(const FString& Parameters)
{
	FActivityTestWorld Fixture;
	if (!TestTrue(TEXT("test world created"), Fixture.Create()))
	{
		return false;
	}
	UWorld* World = Fixture.World;

	// Ground: a long thin slab on the project's world-static profile so the wheel traces hit it.
	AStaticMeshActor* Floor = World->SpawnActor<AStaticMeshActor>(FVector(30000.0, 0.0, -50.0), FRotator::ZeroRotator);
	if (!TestNotNull(TEXT("floor actor"), Floor))
	{
		return false;
	}
	UStaticMeshComponent* FloorMesh = Floor->GetStaticMeshComponent();
	FloorMesh->SetMobility(EComponentMobility::Movable);
	FloorMesh->SetStaticMesh(LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube")));
	Floor->SetActorScale3D(FVector(1000.0, 40.0, 1.0));
	FloorMesh->SetCollisionProfileName(RoamCollision::ProfileWorldStatic);

	ARoamVehicle* Car = World->SpawnActor<ARoamVehicle>(ARoamVehicle::StaticClass(), FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 30.0)));
	if (!TestNotNull(TEXT("vehicle"), Car))
	{
		return false;
	}
	Car->SetAIControlled(true);
	// this bare test world steps the car by hand with the kinematic model (the physics model needs the frame counter and Roam_Wheel ground:
	// see Tests/RoamVehiclePhysicsTests.cpp for the physics drive tests)
	Car->VehicleMovement->SetSimMode(ERoamVehicleSimMode::KinematicPlaceholder);

	URoamActivitySubsystem* Activities = World->GetSubsystem<URoamActivitySubsystem>();
	URoamSaveSubsystem* Save = Fixture.GameInstance->GetSubsystem<URoamSaveSubsystem>();
	if (!TestNotNull(TEXT("activity subsystem"), Activities) || !TestNotNull(TEXT("save subsystem"), Save))
	{
		return false;
	}
	Activities->bAutoSaveOnResult = false;
	Activities->SetTrackedVehicle(Car);

	FRoamActivityDef Trap;
	Trap.ActivityId = TEXT("drive_trap");
	Trap.Type = ERoamActivityType::SpeedTrap;
	Trap.Gates.Add(MakeTestGate(FVector(15000.0, 0.0, 150.0), FVector::ForwardVector, 1200.0f));
	Trap.StarThresholds = FVector(5.0, 15.0, 40.0);
	Activities->RegisterActivity(Trap);

	Car->SetThrottle(1.0f);
	// A bare CreateWorld() world runs FTickableGameObject (the activity subsystem) every frame but only gives actor components their
	// very first tick, so the car's movement component is stepped by hand; the sampling, gate and save paths under test are the real ones.
	const float Dt = 1.0f / 60.0f;
	int32 Ticks = 0;
	for (; Ticks < 3600 && Activities->GetLastResult().ActivityId.IsNone(); ++Ticks)
	{
		Car->VehicleMovement->TickComponent(Dt, LEVELTICK_All, nullptr);
		World->Tick(LEVELTICK_All, Dt);
	}
	const FRoamActivityResult& Result = Activities->GetLastResult();
	AddInfo(FString::Printf(TEXT("car drove %d ticks (world t=%.2f s, begun=%d), trap result id=%s value=%.1f km/h stars=%d, car pos=(%.0f, %.0f, %.0f) speed=%.1f km/h throttle=%.2f wheels=%d"), Ticks, World->GetTimeSeconds(), World->HasBegunPlay() ? 1 : 0,
		*Result.ActivityId.ToString(), Result.Value, Result.Stars, Car->GetActorLocation().X, Car->GetActorLocation().Y, Car->GetActorLocation().Z, Car->GetTelemetry().SpeedKmh, Car->GetTelemetry().Throttle, Car->GetTelemetry().NumWheelsOnGround));
	TestEqual(TEXT("the trap produced a result"), Result.ActivityId, Trap.ActivityId);
	TestTrue(TEXT("completed"), Result.bCompleted);
	TestTrue(TEXT("speed is plausible"), Result.Value > 5.0f && Result.Value < 400.0f);
	TestTrue(TEXT("at least one star"), Result.Stars >= 1);
	float Best = 0.0f;
	TestTrue(TEXT("personal best persisted in the profile"), Save->GetPersonalBest(Trap.ActivityId, Best));
	TestNearlyEqual(TEXT("persisted best equals the result"), Best, Result.Value, 0.05f);
	TestTrue(TEXT("profile is marked for saving"), Save->IsDirty());

	Car->Destroy();
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
