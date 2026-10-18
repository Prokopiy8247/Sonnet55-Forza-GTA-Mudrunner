// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Data/RoamRoadNetwork.h"
#include "UI/RoamUIStyle.h"
#include "UObject/Package.h"
#include "UI/SRoamMinimap.h"

#define ROAM_UI_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

using namespace RoamUI;

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamUILayoutTest, "Roam.UI.LayoutAndUnits", ROAM_UI_TEST_FLAGS)
bool FRoamUILayoutTest::RunTest(const FString& Parameters)
{
	// safe area: 5 percent per side at 1080p and at 4K
	const Logic::FSafeArea Safe = Logic::ComputeSafeArea(FVector2f(1920.0f, 1080.0f));
	TestEqual(TEXT("safe left"), Safe.Left, 96.0f);
	TestEqual(TEXT("safe right"), Safe.Right, 96.0f);
	TestEqual(TEXT("safe top"), Safe.Top, 54.0f);
	TestEqual(TEXT("safe bottom"), Safe.Bottom, 54.0f);
	const Logic::FSafeArea Safe4K = Logic::ComputeSafeArea(FVector2f(3840.0f, 2160.0f));
	TestEqual(TEXT("safe 4k left"), Safe4K.Left, 192.0f);

	// units
	TestEqual(TEXT("100 km/h in mph"), Logic::SpeedValue(100.0f, true), 62);
	TestEqual(TEXT("100 km/h"), Logic::SpeedValue(100.0f, false), 100);
	TestEqual(TEXT("negative clamps"), Logic::SpeedValue(-5.0f, false), 0);
	TestEqual(TEXT("clamp 999"), Logic::SpeedValue(5000.0f, false), 999);
	TestEqual(TEXT("unit km/h"), FString(Logic::UnitLabel(false)), FString(TEXT("KM/H")));
	TestEqual(TEXT("unit mph"), FString(Logic::UnitLabel(true)), FString(TEXT("MPH")));
	TestEqual(TEXT("gear R"), Logic::GearText(-1), FString(TEXT("R")));
	TestEqual(TEXT("gear N"), Logic::GearText(0), FString(TEXT("N")));
	TestEqual(TEXT("gear 6"), Logic::GearText(6), FString(TEXT("6")));
	TestEqual(TEXT("leading zeros 7"), Logic::LeadingZeroCells(7), 2);
	TestEqual(TEXT("leading zeros 42"), Logic::LeadingZeroCells(42), 1);
	TestEqual(TEXT("leading zeros 250"), Logic::LeadingZeroCells(250), 0);
	TestEqual(TEXT("leading zeros 0"), Logic::LeadingZeroCells(0), 2);

	// timer
	TestEqual(TEXT("timer 83.45"), Logic::FormatTimer(83.45f), FString(TEXT("01:23.45")));
	TestEqual(TEXT("timer zero"), Logic::FormatTimer(-1.0f), FString(TEXT("00:00.00")));
	TestEqual(TEXT("timer long"), Logic::FormatTimer(4500.0f), FString(TEXT("75:00.00")));

	// tach
	TestEqual(TEXT("tach idle off"), Logic::TachLitSegments(0.0f), 0);
	TestEqual(TEXT("tach half"), Logic::TachLitSegments(0.5f), 24);
	TestEqual(TEXT("tach full"), Logic::TachLitSegments(1.0f), 48);
	TestEqual(TEXT("tach over limiter"), Logic::TachLitSegments(1.07f), 48);
	TestEqual(TEXT("tach tiny"), Logic::TachLitSegments(0.01f), 1);
	TestTrue(TEXT("zone normal"), Logic::TachZoneOf(10) == Logic::ETachZone::Normal);
	TestTrue(TEXT("zone warn"), Logic::TachZoneOf(40) == Logic::ETachZone::Warn);
	TestTrue(TEXT("zone redline"), Logic::TachZoneOf(47) == Logic::ETachZone::Redline);
	TestNearlyEqual(TEXT("first segment angle"), Logic::TachSegmentAngleDeg(0, 48, 150.0f, 240.0f), 152.5f, 0.01f);
	TestNearlyEqual(TEXT("last segment angle"), Logic::TachSegmentAngleDeg(47, 48, 150.0f, 240.0f), 387.5f, 0.01f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamUIMinimapMathTest, "Roam.UI.MinimapMath", ROAM_UI_TEST_FLAGS)
bool FRoamUIMinimapMathTest::RunTest(const FString& Parameters)
{
	// view radius
	TestNearlyEqual(TEXT("radius standing"), Logic::MinimapViewRadiusM(0.0f), 350.0f, 0.01f);
	TestNearlyEqual(TEXT("radius full"), Logic::MinimapViewRadiusM(200.0f), 900.0f, 0.01f);
	TestNearlyEqual(TEXT("radius above full"), Logic::MinimapViewRadiusM(400.0f), 900.0f, 0.01f);
	TestTrue(TEXT("radius monotonic"), Logic::MinimapViewRadiusM(60.0f) < Logic::MinimapViewRadiusM(120.0f));

	// heading-up transform: 100 m ahead is straight up, 100 m to the right is straight right, for any heading
	for (const float Yaw : { 0.0f, 37.0f, 90.0f, 180.0f, -123.0f })
	{
		float S = 0.0f;
		float C = 1.0f;
		FMath::SinCos(&S, &C, FMath::DegreesToRadians(Yaw));
		const FVector2f Forward(C * 100.0f, S * 100.0f); // (north, east) of a point 100 m ahead
		const FVector2f RightVec(-S * 100.0f, C * 100.0f); // 100 m to the right of the car
		const FVector2f A = Logic::WorldDeltaToMapOffset(Forward, Yaw);
		const FVector2f B = Logic::WorldDeltaToMapOffset(RightVec, Yaw);
		TestNearlyEqual(*FString::Printf(TEXT("ahead x yaw %.0f"), Yaw), A.X, 0.0f, 0.01f);
		TestNearlyEqual(*FString::Printf(TEXT("ahead y yaw %.0f"), Yaw), A.Y, -100.0f, 0.01f);
		TestNearlyEqual(*FString::Printf(TEXT("right x yaw %.0f"), Yaw), B.X, 100.0f, 0.01f);
		TestNearlyEqual(*FString::Printf(TEXT("right y yaw %.0f"), Yaw), B.Y, 0.0f, 0.01f);
	}
	// north marker: car facing east -> north is on the left of the map
	const FVector2f North = Logic::NorthOnMap(90.0f);
	TestNearlyEqual(TEXT("north when facing east x"), North.X, -1.0f, 0.001f);
	TestNearlyEqual(TEXT("north when facing east y"), North.Y, 0.0f, 0.001f);

	// circle clipping
	float T0 = 0.0f;
	float T1 = 0.0f;
	TestTrue(TEXT("inside segment"), Logic::ClipSegmentToCircle(FVector2f(-10.0f, 0.0f), FVector2f(10.0f, 0.0f), 100.0f, T0, T1));
	TestNearlyEqual(TEXT("inside t0"), T0, 0.0f);
	TestNearlyEqual(TEXT("inside t1"), T1, 1.0f);
	TestTrue(TEXT("leaving segment"), Logic::ClipSegmentToCircle(FVector2f(0.0f, 0.0f), FVector2f(200.0f, 0.0f), 100.0f, T0, T1));
	TestNearlyEqual(TEXT("leaving t1"), T1, 0.5f, 0.001f);
	TestTrue(TEXT("chord through circle"), Logic::ClipSegmentToCircle(FVector2f(-200.0f, 0.0f), FVector2f(200.0f, 0.0f), 100.0f, T0, T1));
	TestNearlyEqual(TEXT("chord t0"), T0, 0.25f, 0.001f);
	TestNearlyEqual(TEXT("chord t1"), T1, 0.75f, 0.001f);
	TestFalse(TEXT("outside segment"), Logic::ClipSegmentToCircle(FVector2f(-200.0f, 150.0f), FVector2f(200.0f, 150.0f), 100.0f, T0, T1));
	bool bClamped = false;
	const FVector2f Rim = Logic::ClampToCircle(FVector2f(300.0f, 400.0f), 100.0f, &bClamped);
	TestTrue(TEXT("clamped"), bClamped);
	TestNearlyEqual(TEXT("rim x"), Rim.X, 60.0f, 0.01f);
	TestNearlyEqual(TEXT("rim y"), Rim.Y, 80.0f, 0.01f);

	// polyline simplification: a straight line collapses to its end points, a corner is kept
	TArray<FVector2f> Line;
	for (int32 i = 0; i <= 20; ++i)
	{
		Line.Add(FVector2f(static_cast<float>(i) * 5.0f, 0.0f));
	}
	TArray<FVector2f> Simplified;
	Logic::SimplifyPolyline(Line, 2.5f, Simplified);
	TestEqual(TEXT("straight line collapses"), Simplified.Num(), 2);
	TArray<FVector2f> Corner;
	for (int32 i = 0; i <= 10; ++i)
	{
		Corner.Add(FVector2f(static_cast<float>(i) * 5.0f, 0.0f));
	}
	for (int32 i = 1; i <= 10; ++i)
	{
		Corner.Add(FVector2f(50.0f, static_cast<float>(i) * 5.0f));
	}
	Logic::SimplifyPolyline(Corner, 2.5f, Simplified);
	TestEqual(TEXT("corner keeps three points"), Simplified.Num(), 3);
	TestNearlyEqual(TEXT("corner point x"), Simplified[1].X, 50.0f);
	TestNearlyEqual(TEXT("corner point y"), Simplified[1].Y, 0.0f);

	// wrong way
	TestTrue(TEXT("one-way against traffic"), Logic::IsWrongWay(-0.9f, 0.0f, true, 80.0f));
	TestFalse(TEXT("slow is never wrong way"), Logic::IsWrongWay(-0.9f, 0.0f, true, 10.0f));
	TestFalse(TEXT("right lane along tangent"), Logic::IsWrongWay(0.95f, 170.0f, false, 80.0f));
	TestTrue(TEXT("left lane along tangent"), Logic::IsWrongWay(0.95f, -170.0f, false, 80.0f));
	TestFalse(TEXT("left lane against tangent is the correct lane"), Logic::IsWrongWay(-0.95f, -170.0f, false, 80.0f));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamUIMinimapCacheTest, "Roam.UI.MinimapCache", ROAM_UI_TEST_FLAGS)
bool FRoamUIMinimapCacheTest::RunTest(const FString& Parameters)
{
	URoamRoadNetwork* Network = URoamRoadNetwork::BuildGeneratedForTests(GetTransientPackage(), 3, 100000.0f, 500.0f);
	if (!TestNotNull(TEXT("generated network"), Network))
	{
		return false;
	}
	FRoamMinimapCache Cache;
	TestTrue(TEXT("first build"), Cache.Build(Network));
	TestTrue(TEXT("cache built"), Cache.IsBuilt());
	TestTrue(TEXT("one polyline per road"), Cache.GetPolylines().Num() > 0 && Cache.GetPolylines().Num() <= Network->Roads.Num());
	TestTrue(TEXT("simplified"), Cache.GetPoints().Num() < Cache.GetNumSourceSamples());
	TestFalse(TEXT("second build is a no-op"), Cache.Build(Network));

	// back-to-front class order, ranges inside the point array
	int32 PrevOrder = -1;
	for (const FRoamMinimapCache::FPolyline& Line : Cache.GetPolylines())
	{
		const int32 Order = FRoamMinimapCache::DrawOrder(Line.Class);
		TestTrue(TEXT("draw order is non-decreasing"), Order >= PrevOrder);
		PrevOrder = Order;
		TestTrue(TEXT("range inside points"), Line.FirstPoint >= 0 && Line.FirstPoint + Line.NumPoints <= Cache.GetPoints().Num() && Line.NumPoints >= 2);
		TestTrue(TEXT("bounds ordered"), Line.BoundsMin.X <= Line.BoundsMax.X && Line.BoundsMin.Y <= Line.BoundsMax.Y);
	}
	Cache.Clear();
	TestFalse(TEXT("cleared"), Cache.IsBuilt());
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamUINotificationQueueTest, "Roam.UI.NotificationQueue", ROAM_UI_TEST_FLAGS)
bool FRoamUINotificationQueueTest::RunTest(const FString& Parameters)
{
	Logic::FNotificationChannel Toasts(Layout::MaxToasts, 4);
	const auto Make = [](const TCHAR* Title, float Seconds)
	{
		FRoamNotification N;
		N.Title = FText::FromString(Title);
		N.Seconds = Seconds;
		return N;
	};

	double Now = 100.0;
	Toasts.Push(Make(TEXT("A"), 4.0f), Now);
	Toasts.Push(Make(TEXT("B"), 4.0f), Now);
	Toasts.Push(Make(TEXT("C"), 4.0f), Now);
	Toasts.Push(Make(TEXT("D"), 4.0f), Now);
	TestEqual(TEXT("three visible"), Toasts.GetVisible().Num(), 3);
	TestEqual(TEXT("one waiting"), Toasts.GetNumPending(), 1);
	TestEqual(TEXT("order preserved"), Toasts.GetVisible()[0].Data.Title.ToString(), FString(TEXT("A")));

	// still the same slot occupants shortly before the lifetime ends
	Now += 4.4;
	Toasts.Update(Now);
	TestEqual(TEXT("still three"), Toasts.GetVisible().Num(), 3);
	TestEqual(TEXT("still one waiting"), Toasts.GetNumPending(), 1);

	// after in + hold + out (0.25 + 4 + 0.3) the first three leave and D takes a slot; its hold starts when it appears
	Now += 0.2;
	Toasts.Update(Now);
	TestEqual(TEXT("only D remains"), Toasts.GetVisible().Num(), 1);
	TestEqual(TEXT("D visible"), Toasts.GetVisible()[0].Data.Title.ToString(), FString(TEXT("D")));
	TestEqual(TEXT("queue empty"), Toasts.GetNumPending(), 0);
	TestNearlyEqual(TEXT("D age starts at zero"), Logic::FNotificationChannel::AgeOf(Toasts.GetVisible()[0], Now), 0.0f, 0.001f);

	// pending overflow drops the oldest waiting entries
	Logic::FNotificationChannel Single(1, 2);
	Single.Push(Make(TEXT("1"), 1.0f), Now);
	Single.Push(Make(TEXT("2"), 1.0f), Now);
	Single.Push(Make(TEXT("3"), 1.0f), Now);
	Single.Push(Make(TEXT("4"), 1.0f), Now);
	TestEqual(TEXT("single slot"), Single.GetVisible().Num(), 1);
	TestEqual(TEXT("pending capped"), Single.GetNumPending(), 2);
	Single.Clear();
	TestEqual(TEXT("cleared visible"), Single.GetVisible().Num(), 0);
	TestEqual(TEXT("cleared pending"), Single.GetNumPending(), 0);

	// phases: region popup 350 ms in, 2.8 s hold, 400 ms out
	TestFalse(TEXT("popup before"), Logic::RegionPopupPhase(-0.1f).bVisible);
	TestNearlyEqual(TEXT("popup half way in"), Logic::RegionPopupPhase(0.175f).Alpha, 0.5f, 0.001f);
	TestNearlyEqual(TEXT("popup hold alpha"), Logic::RegionPopupPhase(2.0f).Alpha, 1.0f);
	TestNearlyEqual(TEXT("popup hold slide"), Logic::RegionPopupPhase(2.0f).Slide, 1.0f);
	TestTrue(TEXT("popup fading out"), Logic::RegionPopupPhase(0.35f + 2.8f + 0.2f).Alpha < 1.0f);
	TestFalse(TEXT("popup finished"), Logic::RegionPopupPhase(0.35f + 2.8f + 0.4f + 0.01f).bVisible);
	TestNearlyEqual(TEXT("notification hold alpha"), Logic::NotificationPhase(2.0f, 4.0f).Alpha, 1.0f);
	TestFalse(TEXT("notification finished"), Logic::NotificationPhase(0.25f + 4.0f + 0.3f + 0.01f, 4.0f).bVisible);
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
