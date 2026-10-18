// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Data/RoamCarCatalog.h"
#include "Data/RoamCarDefinition.h"
#include "UObject/StrongObjectPtr.h"

#define ROAM_CAR_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

namespace
{
	/** A car resembling the "hot hatch FWD" row of Docs/Tech/FH5_cars_assists.md 3.6. */
	URoamCarDefinition* MakeHatch(FName Id = TEXT("test_hatch"))
	{
		URoamCarDefinition* Car = NewObject<URoamCarDefinition>(GetTransientPackage());
		Car->CarId = Id;
		Car->DisplayName = FText::FromString(TEXT("Test Hatch"));
		Car->MassKg = 1200.0f;
		Car->Engine.IdleRPM = 900.0f;
		Car->Engine.RedlineRPM = 7000.0f;
		Car->Engine.RevLimiterRPM = 7200.0f;
		Car->Engine.TorqueCurve = FRoamEngineSpec::BuildSyntheticTorqueCurve(105.0f, 900.0f, 7000.0f);
		Car->Gearbox.ForwardRatios = { 3.6f, 2.2f, 1.5f, 1.12f, 0.9f, 0.76f };
		Car->Gearbox.FinalDrive = 4.0f;
		Car->Gearbox.Efficiency = 0.90f;
		Car->Drivetrain.Layout = ERoamDrivetrain::FWD;
		Car->TireFront.PeakFriction = 1.0f;
		Car->TireRear.PeakFriction = 1.0f;
		Car->Aero.CdA = 0.72f;
		Car->Aero.ClAFront = 0.0f;
		Car->Aero.ClARear = 0.0f;
		Car->Brakes.PeakDecelerationG = 1.0f;
		Car->HandlingFactor = 1.0f;
		Car->Geometry.WheelFL.RadiusCm = 31.0f;
		Car->Geometry.WheelFR.RadiusCm = 31.0f;
		Car->Geometry.WheelRL.RadiusCm = 31.0f;
		Car->Geometry.WheelRR.RadiusCm = 31.0f;
		Car->Geometry.WheelFL.CenterCm = FVector(126.0, -77.0, 31.0);
		Car->Geometry.WheelFR.CenterCm = FVector(126.0, 77.0, 31.0);
		Car->Geometry.WheelRL.CenterCm = FVector(-126.0, -77.0, 31.0);
		Car->Geometry.WheelRR.CenterCm = FVector(-126.0, 77.0, 31.0);
		return Car;
	}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamCarClassBandsTest, "Roam.CarDefinition.ClassBands", ROAM_CAR_TEST_FLAGS)
bool FRoamCarClassBandsTest::RunTest(const FString& Parameters)
{
	using namespace Roam;
	struct FCase { int32 PerfIndex; ERoamCarClass Class; const TCHAR* Label; };
	const FCase Cases[] =
	{
		{ 100, ERoamCarClass::D, TEXT("D") }, { 500, ERoamCarClass::D, TEXT("D") }, { 501, ERoamCarClass::C, TEXT("C") }, { 600, ERoamCarClass::C, TEXT("C") },
		{ 601, ERoamCarClass::B, TEXT("B") }, { 700, ERoamCarClass::B, TEXT("B") }, { 701, ERoamCarClass::A, TEXT("A") }, { 800, ERoamCarClass::A, TEXT("A") },
		{ 801, ERoamCarClass::S1, TEXT("S1") }, { 900, ERoamCarClass::S1, TEXT("S1") }, { 901, ERoamCarClass::S2, TEXT("S2") }, { 998, ERoamCarClass::S2, TEXT("S2") },
		{ 999, ERoamCarClass::X, TEXT("X") },
	};
	for (const FCase& Case : Cases)
	{
		const ERoamCarClass Got = ClassFromPerformanceIndex(Case.PerfIndex);
		TestEqual(*FString::Printf(TEXT("class of PI %d"), Case.PerfIndex), Got, Case.Class);
		TestEqual(*FString::Printf(TEXT("label of PI %d"), Case.PerfIndex), ClassToLabel(Got), FString(Case.Label));
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamCarTorqueCurveTest, "Roam.CarDefinition.TorqueCurve", ROAM_CAR_TEST_FLAGS)
bool FRoamCarTorqueCurveTest::RunTest(const FString& Parameters)
{
	FRoamEngineSpec Engine;
	Engine.IdleRPM = 900.0f;
	Engine.RedlineRPM = 7000.0f;
	Engine.RevLimiterRPM = 7200.0f;
	Engine.TorqueCurve = FRoamEngineSpec::BuildSyntheticTorqueCurve(150.0f, 900.0f, 7000.0f);
	TestEqual(TEXT("sample count"), Engine.TorqueCurve.Num(), 24);

	float PeakPowerRPM = 0.0f;
	const float PeakPower = Engine.GetPeakPowerKw(&PeakPowerRPM);
	TestNearlyEqual(TEXT("peak power matches the request"), PeakPower, 150.0f, 3.0f);
	TestTrue(TEXT("peak power in the upper rev range"), PeakPowerRPM > 4500.0f && PeakPowerRPM <= 7000.0f);
	TestTrue(TEXT("peak torque is lower in rpm than peak power"), [&]() { float TqRPM = 0.0f; Engine.GetPeakTorqueNm(&TqRPM); return TqRPM < PeakPowerRPM; }());

	TestNearlyEqual(TEXT("no torque above the rev limiter"), Engine.GetTorqueNm(7500.0f), 0.0f, 0.0001f);
	TestNearlyEqual(TEXT("no torque at standstill"), Engine.GetTorqueNm(0.0f), 0.0f, 0.0001f);
	TestTrue(TEXT("torque at 4000 rpm is positive"), Engine.GetTorqueNm(4000.0f) > 100.0f);

	// interpolation is continuous
	const float A = Engine.GetTorqueNm(3999.0f);
	const float B = Engine.GetTorqueNm(4001.0f);
	TestTrue(TEXT("continuous curve"), FMath::Abs(A - B) < 2.0f);

	// gearbox ratios
	FRoamGearboxSpec Gearbox;
	Gearbox.ForwardRatios = { 3.0f, 2.0f };
	Gearbox.FinalDrive = 4.0f;
	Gearbox.ReverseRatio = 3.5f;
	TestNearlyEqual(TEXT("1st overall"), Gearbox.GetTotalRatio(1), 12.0f, 0.001f);
	TestNearlyEqual(TEXT("2nd overall"), Gearbox.GetTotalRatio(2), 8.0f, 0.001f);
	TestNearlyEqual(TEXT("reverse overall"), Gearbox.GetTotalRatio(-1), 14.0f, 0.001f);
	TestNearlyEqual(TEXT("neutral"), Gearbox.GetTotalRatio(0), 0.0f, 0.001f);
	TestNearlyEqual(TEXT("out of range gear"), Gearbox.GetTotalRatio(3), 0.0f, 0.001f);

	// steering lock reduces with speed
	FRoamSteeringSpec Steering;
	TestNearlyEqual(TEXT("full lock at standstill"), Steering.GetLockFraction(0.0f), 1.0f, 0.001f);
	TestTrue(TEXT("lock decreases with speed"), Steering.GetLockFraction(150.0f) < Steering.GetLockFraction(50.0f));
	TestNearlyEqual(TEXT("lock clamps beyond the last sample"), Steering.GetLockFraction(900.0f), 0.15f, 0.001f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamCarPerformanceTest, "Roam.CarDefinition.PerformanceIndex", ROAM_CAR_TEST_FLAGS)
bool FRoamCarPerformanceTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamCarDefinition> Hatch(MakeHatch());
	const FRoamPerformanceRules Rules;
	const FRoamCarPerformance Base = Hatch->ComputePerformance(Rules);

	AddInfo(FString::Printf(TEXT("hatch: 0-60 %.2f s, 0-100 %.2f s, vmax %.0f km/h, latG %.2f, brake %.1f m, offroad %.2f, score %.3f, PI %d (%s)"),
		Base.Time0To60Kmh, Base.Time0To100Kmh, Base.TopSpeedKmh, Base.LateralG, Base.BrakeDistance100M, Base.Offroad01, Base.Score, Base.PerformanceIndex, *Roam::ClassToLabel(Base.CarClass)));

	// physically plausible numbers for 105 kW / 1200 kg
	TestTrue(TEXT("0-100 km/h between 6 and 11 s"), Base.Time0To100Kmh > 6.0f && Base.Time0To100Kmh < 11.0f);
	TestTrue(TEXT("0-60 km/h is shorter than 0-100"), Base.Time0To60Kmh < Base.Time0To100Kmh && Base.Time0To60Kmh > 2.0f);
	TestTrue(TEXT("top speed between 170 and 260 km/h"), Base.TopSpeedKmh > 170.0f && Base.TopSpeedKmh < 260.0f);
	TestNearlyEqual(TEXT("lateral grip equals tyre mu at 100 km/h without downforce"), Base.LateralG, 1.0f, 0.02f);
	TestTrue(TEXT("braking distance 33..45 m"), Base.BrakeDistance100M > 33.0f && Base.BrakeDistance100M < 45.0f);
	TestTrue(TEXT("PI in range"), Base.PerformanceIndex >= 100 && Base.PerformanceIndex <= 999);
	TestTrue(TEXT("a 105 kW hatch is a D or C class car"), Base.CarClass == ERoamCarClass::D || Base.CarClass == ERoamCarClass::C);
	TestEqual(TEXT("class matches the PI"), Base.CarClass, Roam::ClassFromPerformanceIndex(Base.PerformanceIndex));
	TestEqual(TEXT("cached PI equals the computed one"), Hatch->GetPerformanceIndex(), Base.PerformanceIndex);
	TestTrue(TEXT("class label text"), Hatch->GetClassLabel().Contains(FString::FromInt(Base.PerformanceIndex)));

	// determinism
	const FRoamCarPerformance Again = Hatch->ComputePerformance(Rules);
	TestEqual(TEXT("deterministic PI"), Again.PerformanceIndex, Base.PerformanceIndex);
	TestNearlyEqual(TEXT("deterministic 0-100"), Again.Time0To100Kmh, Base.Time0To100Kmh, 0.0001f);

	// more power -> faster, higher PI
	TStrongObjectPtr<URoamCarDefinition> Strong(MakeHatch(TEXT("test_strong")));
	Strong->Engine.TorqueCurve = FRoamEngineSpec::BuildSyntheticTorqueCurve(300.0f, 900.0f, 7000.0f);
	Strong->TireFront.PeakFriction = Strong->TireRear.PeakFriction = 1.2f; // keep it traction-capable
	const FRoamCarPerformance StrongPerf = Strong->ComputePerformance(Rules);
	TestTrue(TEXT("300 kW car accelerates faster"), StrongPerf.Time0To100Kmh < Base.Time0To100Kmh);
	TestTrue(TEXT("300 kW car is faster"), StrongPerf.TopSpeedKmh > Base.TopSpeedKmh);
	TestTrue(TEXT("300 kW car has the higher PI"), StrongPerf.PerformanceIndex > Base.PerformanceIndex);

	// heavier -> slower
	TStrongObjectPtr<URoamCarDefinition> Heavy(MakeHatch(TEXT("test_heavy")));
	Heavy->MassKg = 2000.0f;
	const FRoamCarPerformance HeavyPerf = Heavy->ComputePerformance(Rules);
	TestTrue(TEXT("heavier car is slower to 100"), HeavyPerf.Time0To100Kmh > Base.Time0To100Kmh);
	TestTrue(TEXT("heavier car has the lower PI"), HeavyPerf.PerformanceIndex < Base.PerformanceIndex);

	// downforce raises lateral grip
	TStrongObjectPtr<URoamCarDefinition> Wing(MakeHatch(TEXT("test_wing")));
	Wing->Aero.ClARear = 1.0f;
	TestTrue(TEXT("downforce raises lateral g"), Wing->ComputePerformance(Rules).LateralG > Base.LateralG);

	// AWD launches better than FWD with the same engine
	TStrongObjectPtr<URoamCarDefinition> Awd(MakeHatch(TEXT("test_awd")));
	Awd->Engine.TorqueCurve = FRoamEngineSpec::BuildSyntheticTorqueCurve(300.0f, 900.0f, 7000.0f);
	Awd->Drivetrain.Layout = ERoamDrivetrain::AWD;
	Strong->Drivetrain.Layout = ERoamDrivetrain::FWD;
	TestTrue(TEXT("AWD 0-100 is not slower than FWD with 300 kW"), Awd->ComputePerformance(Rules).Time0To100Kmh <= Strong->ComputePerformance(Rules).Time0To100Kmh + 0.001f);

	// rally tyres raise the off-road rating and nothing else breaks
	TStrongObjectPtr<URoamCarDefinition> Rally(MakeHatch(TEXT("test_rally")));
	Rally->TireFront.SurfaceBias.Add(ERoamSurface::Dirt, 1.3f);
	Rally->TireFront.SurfaceBias.Add(ERoamSurface::Gravel, 1.3f);
	Rally->TireRear.SurfaceBias = Rally->TireFront.SurfaceBias;
	TestTrue(TEXT("loose-surface tyres raise the off-road rating"), Rally->ComputePerformance(Rules).Offroad01 > Base.Offroad01);

	// custom rules: ratings are bounded 0..10
	for (float Rating : { Base.RatingSpeed, Base.RatingHandling, Base.RatingAcceleration, Base.RatingLaunch, Base.RatingBraking, Base.RatingOffroad })
	{
		TestTrue(TEXT("rating within 0..10"), Rating >= 0.0f && Rating <= 10.0f);
	}

	// a degenerate definition does not crash or divide by zero
	TStrongObjectPtr<URoamCarDefinition> Empty(NewObject<URoamCarDefinition>(GetTransientPackage()));
	const FRoamCarPerformance EmptyPerf = Empty->ComputePerformance(Rules);
	TestEqual(TEXT("no engine -> minimum PI"), EmptyPerf.PerformanceIndex, 100 + FMath::RoundToInt(899.0f * FMath::Pow(EmptyPerf.Score, Rules.Gamma)));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamCarValidateTest, "Roam.CarDefinition.Validate", ROAM_CAR_TEST_FLAGS)
bool FRoamCarValidateTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamCarDefinition> Good(MakeHatch());
	TArray<FString> Problems;
	const bool bGood = Good->Validate(Problems);
	for (const FString& Problem : Problems)
	{
		AddError(Problem);
	}
	TestTrue(TEXT("a complete car validates"), bGood);

	TStrongObjectPtr<URoamCarDefinition> Bad(NewObject<URoamCarDefinition>(GetTransientPackage()));
	Problems.Reset();
	TestFalse(TEXT("an empty car fails validation"), Bad->Validate(Problems));
	TestTrue(TEXT("several problems found"), Problems.Num() >= 2);

	// wheel sign convention: left wheels must have negative Y
	TStrongObjectPtr<URoamCarDefinition> Mirrored(MakeHatch(TEXT("test_mirror")));
	Mirrored->Geometry.WheelFL.CenterCm.Y = 77.0;
	Problems.Reset();
	TestFalse(TEXT("wrong handedness is detected"), Mirrored->Validate(Problems));

	// derived values
	TStrongObjectPtr<URoamCarDefinition> Car(MakeHatch());
	Car->CenterOfMassCm = FVector(26.0, 0.0, 45.0); // 26 cm in front of the middle of a 260 cm wheelbase
	Car->Geometry.WheelbaseCm = 260.0f;
	TestNearlyEqual(TEXT("front weight fraction"), Car->GetFrontWeightFraction(), 0.6f, 0.001f);
	const FVector Inertia = Car->GetEstimatedInertia();
	TestTrue(TEXT("estimated inertia is positive and yaw > roll"), Inertia.X > 0.0 && Inertia.Z > Inertia.X);
	Car->InertiaKgM2 = FVector(500.0, 1800.0, 2000.0);
	TestTrue(TEXT("explicit inertia wins"), Car->GetEstimatedInertia().Equals(FVector(500.0, 1800.0, 2000.0)));
	TestEqual(TEXT("primary asset id uses the car id"), Car->GetPrimaryAssetId().PrimaryAssetName, FName(TEXT("test_hatch")));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamCarCatalogTest, "Roam.CarDefinition.Catalog", ROAM_CAR_TEST_FLAGS)
bool FRoamCarCatalogTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamCarCatalog> Catalog(NewObject<URoamCarCatalog>(GetTransientPackage()));
	const TCHAR* Names[3] = { TEXT("Pulse"), TEXT("Cadence"), TEXT("Thunderline") };
	const TCHAR* Ids[3] = { TEXT("car01_hatch_pulse"), TEXT("car02_sedan_cadence"), TEXT("car03_muscle_thunderline") };
	TArray<TStrongObjectPtr<URoamCarDefinition>> Keep;
	for (int32 i = 0; i < 3; ++i)
	{
		URoamCarDefinition* Car = MakeHatch(Ids[i]);
		Car->DisplayName = FText::FromString(Names[i]);
		Keep.Emplace(Car);
		Catalog->Cars.Add(TSoftObjectPtr<URoamCarDefinition>(Car));
	}
	TestEqual(TEXT("catalog size"), Catalog->GetNumCars(), 3);

	FString Error;
	int32 Index = INDEX_NONE;
	URoamCarDefinition* Found = Catalog->ResolveCar(TEXT("2"), &Error, &Index);
	TestNotNull(TEXT("1-based index resolves"), Found);
	TestEqual(TEXT("index result"), Index, 1);
	TestEqual(TEXT("exact id"), Catalog->ResolveCar(TEXT("car03_muscle_thunderline")), Keep[2].Get());
	TestEqual(TEXT("display name, case-insensitive"), Catalog->ResolveCar(TEXT("pulse")), Keep[0].Get());
	TestEqual(TEXT("unique substring of the id"), Catalog->ResolveCar(TEXT("sedan")), Keep[1].Get());
	TestNull(TEXT("ambiguous prefix fails"), Catalog->ResolveCar(TEXT("car0"), &Error));
	TestTrue(TEXT("ambiguity message"), Error.Contains(TEXT("ambiguous")));
	TestNull(TEXT("unknown name fails"), Catalog->ResolveCar(TEXT("zzz"), &Error));
	TestNull(TEXT("index 0 fails"), Catalog->ResolveCar(TEXT("0"), &Error));
	TestNull(TEXT("index above the size fails"), Catalog->ResolveCar(TEXT("4"), &Error));
	TestEqual(TEXT("IndexOfCar"), Catalog->IndexOfCar(TEXT("car02_sedan_cadence")), 1);
	TestEqual(TEXT("FindCarById"), Catalog->FindCarById(TEXT("car01_hatch_pulse")), Keep[0].Get());
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
