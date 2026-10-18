// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Core/RoamTypes.h"
#include "Kismet/GameplayStatics.h"
#include "Save/RoamSaveGame.h"
#include "Save/RoamSaveSubsystem.h"
#include "UObject/StrongObjectPtr.h"

#define ROAM_SAVE_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamSaveRoundTripTest, "Roam.Save.RoundTrip", ROAM_SAVE_TEST_FLAGS)
bool FRoamSaveRoundTripTest::RunTest(const FString& Parameters)
{
	TStrongObjectPtr<URoamSaveGame> Original(NewObject<URoamSaveGame>(GetTransientPackage()));
	FRoamProfile& P = Original->Profile;
	P.CarId = TEXT("car05_gt_meridian");
	P.Paint.Primary = FLinearColor(0.1f, 0.2f, 0.3f, 1.0f);
	P.Paint.Finish = ERoamPaintFinish::Metallic;
	P.Paint.StripeStyle = 3;
	FRoamPaint Other;
	Other.Primary = FLinearColor::Green;
	P.PaintByCar.Add(TEXT("car01_hatch_pulse"), Other);
	P.Upgrades.Add(TEXT("Engine.Tune"), 2);
	P.Upgrades.Add(TEXT("Tires.Compound"), 1);
	P.Tuning.TirePressureFrontPsi = 28.5f;
	P.Tuning.FinalDriveMultiplier = 1.1f;
	P.Tuning.BrakeBalanceFrontPercent = 54.0f;
	P.LastTransform = FTransform(FRotator(0.0f, 135.0f, 0.0f), FVector(12345.0, -6789.0, 321.0));
	P.bHasLastTransform = true;
	P.GameHour = 18.75f;
	P.Weather = ERoamWeather::Rain;
	P.PersonalBests.Add(TEXT("trap_01"), 187.5f);
	P.ActivityStars.Add(TEXT("trap_01"), 2);
	P.Collected.Add(TEXT("billboard_07"));
	P.TotalXp = 9876543210LL;
	P.Credits = 4242;
	P.Settings.bUseMph = true;
	P.Settings.TrafficDensity = 0.25f;
	P.Settings.Assists.bTractionControl = false;
	P.Settings.Assists.SteeringAssist = 0.8f;
	P.Settings.DefaultCameraMode = ERoamCameraMode::Hood;

	TArray<uint8> Bytes;
	TestTrue(TEXT("saved to memory"), UGameplayStatics::SaveGameToMemory(Original.Get(), Bytes));
	TestTrue(TEXT("bytes written"), Bytes.Num() > 0);

	URoamSaveGame* Loaded = Cast<URoamSaveGame>(UGameplayStatics::LoadGameFromMemory(Bytes));
	if (!TestNotNull(TEXT("loaded from memory"), Loaded))
	{
		return false;
	}
	TStrongObjectPtr<URoamSaveGame> Keep(Loaded);
	const FRoamProfile& L = Loaded->Profile;

	TestEqual(TEXT("version"), Loaded->Version, URoamSaveGame::CurrentVersion);
	TestEqual(TEXT("car id"), L.CarId, FName(TEXT("car05_gt_meridian")));
	TestTrue(TEXT("paint colour"), L.Paint.Primary.Equals(P.Paint.Primary, 0.0001f));
	TestEqual(TEXT("paint finish"), L.Paint.Finish, ERoamPaintFinish::Metallic);
	TestEqual(TEXT("stripe style"), L.Paint.StripeStyle, 3);
	TestEqual(TEXT("per-car paints"), L.PaintByCar.Num(), 1);
	TestTrue(TEXT("per-car paint colour"), L.PaintByCar.FindRef(TEXT("car01_hatch_pulse")).Primary.Equals(FLinearColor::Green));
	TestEqual(TEXT("upgrade tier"), L.Upgrades.FindRef(TEXT("Engine.Tune")), 2);
	TestEqual(TEXT("upgrade count"), L.Upgrades.Num(), 2);
	TestNearlyEqual(TEXT("tuning tyre pressure"), L.Tuning.TirePressureFrontPsi, 28.5f, 0.0001f);
	TestNearlyEqual(TEXT("tuning final drive"), L.Tuning.FinalDriveMultiplier, 1.1f, 0.0001f);
	TestNearlyEqual(TEXT("tuning brake balance"), L.Tuning.BrakeBalanceFrontPercent, 54.0f, 0.0001f);
	TestTrue(TEXT("transform location"), L.LastTransform.GetLocation().Equals(FVector(12345.0, -6789.0, 321.0), 0.01));
	TestNearlyEqual(TEXT("transform yaw"), static_cast<float>(L.LastTransform.Rotator().Yaw), 135.0f, 0.01f);
	TestTrue(TEXT("has transform flag"), L.bHasLastTransform);
	TestNearlyEqual(TEXT("game hour"), L.GameHour, 18.75f, 0.0001f);
	TestEqual(TEXT("weather"), L.Weather, ERoamWeather::Rain);
	TestNearlyEqual(TEXT("personal best"), L.PersonalBests.FindRef(TEXT("trap_01")), 187.5f, 0.0001f);
	TestEqual(TEXT("stars"), L.ActivityStars.FindRef(TEXT("trap_01")), 2);
	TestTrue(TEXT("collected"), L.Collected.Contains(TEXT("billboard_07")));
	TestTrue(TEXT("64-bit xp survives"), L.TotalXp == 9876543210LL);
	TestTrue(TEXT("credits"), L.Credits == 4242);
	TestTrue(TEXT("setting: units"), L.Settings.bUseMph);
	TestNearlyEqual(TEXT("setting: traffic"), L.Settings.TrafficDensity, 0.25f, 0.0001f);
	TestFalse(TEXT("setting: nested assist flag"), L.Settings.Assists.bTractionControl);
	TestNearlyEqual(TEXT("setting: nested assist strength"), L.Settings.Assists.SteeringAssist, 0.8f, 0.0001f);
	TestEqual(TEXT("setting: camera"), L.Settings.DefaultCameraMode, ERoamCameraMode::Hood);

	// The integrity envelope that protects the engine loader (it asserts on garbage input in 5.8.2).
	TArray<uint8> Envelope;
	URoamSaveSubsystem::PackEnvelope(Bytes, Envelope);
	TArray<uint8> Unpacked;
	TestTrue(TEXT("intact envelope unpacks"), URoamSaveSubsystem::UnpackEnvelope(Envelope, Unpacked));
	TestTrue(TEXT("payload identical"), Unpacked == Bytes);

	TArray<uint8> Truncated = Envelope;
	Truncated.SetNum(Truncated.Num() - 7);
	TestFalse(TEXT("truncated data is rejected"), URoamSaveSubsystem::UnpackEnvelope(Truncated, Unpacked));
	TArray<uint8> Flipped = Envelope;
	Flipped[Flipped.Num() / 2] ^= 0x40;
	TestFalse(TEXT("a flipped bit is rejected by the CRC"), URoamSaveSubsystem::UnpackEnvelope(Flipped, Unpacked));
	TArray<uint8> WrongMagic = Envelope;
	WrongMagic[0] ^= 0xFF;
	TestFalse(TEXT("wrong magic is rejected"), URoamSaveSubsystem::UnpackEnvelope(WrongMagic, Unpacked));
	TArray<uint8> Foreign = { 1, 2, 3, 4, 5, 6, 7, 8 };
	TestFalse(TEXT("foreign bytes are rejected"), URoamSaveSubsystem::UnpackEnvelope(Foreign, Unpacked));
	TestFalse(TEXT("empty input is rejected"), URoamSaveSubsystem::UnpackEnvelope(TArray<uint8>(), Unpacked));
	TestEqual(TEXT("rejected data leaves no payload"), Unpacked.Num(), 0);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamSaveSanitizeTest, "Roam.Save.Sanitize", ROAM_SAVE_TEST_FLAGS)
bool FRoamSaveSanitizeTest::RunTest(const FString& Parameters)
{
	FRoamProfile P;
	P.GameHour = 37.5f;
	P.Weather = static_cast<ERoamWeather>(200);
	P.Settings.NotificationSeconds = 99.0f;
	P.Settings.TrafficDensity = -3.0f;
	P.Settings.MasterVolume = 7.0f;
	P.Settings.DefaultCameraMode = ERoamCameraMode::Photo;
	P.Credits = -5;
	P.ActivityStars.Add(TEXT("a"), 9);
	P.LastTransform = FTransform(FQuat(0.0f, 0.0f, 0.0f, 0.0f)); // not normalised
	P.bHasLastTransform = true;

	URoamSaveSubsystem::SanitizeProfile(P);
	TestTrue(TEXT("hour wrapped"), P.GameHour >= 0.0f && P.GameHour < 24.0f);
	TestEqual(TEXT("invalid weather repaired"), P.Weather, ERoamWeather::Clear);
	TestNearlyEqual(TEXT("notification seconds clamped"), P.Settings.NotificationSeconds, 10.0f, 0.001f);
	TestNearlyEqual(TEXT("traffic clamped"), P.Settings.TrafficDensity, 0.0f, 0.001f);
	TestNearlyEqual(TEXT("volume clamped"), P.Settings.MasterVolume, 1.0f, 0.001f);
	TestEqual(TEXT("photo camera is not a persistent default"), P.Settings.DefaultCameraMode, ERoamCameraMode::Chase);
	TestTrue(TEXT("credits clamped"), P.Credits == 0);
	TestEqual(TEXT("stars clamped"), P.ActivityStars.FindRef(TEXT("a")), 3);
	TestFalse(TEXT("broken transform discarded"), P.bHasLastTransform);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTypesHelpersTest, "Roam.Types.Helpers", ROAM_SAVE_TEST_FLAGS)
bool FRoamTypesHelpersTest::RunTest(const FString& Parameters)
{
	using namespace Roam;

	// surface <-> engine physical surface mapping is a bijection over the 8 surfaces
	for (ERoamSurface Surface : TEnumRange<ERoamSurface>())
	{
		TestEqual(*FString::Printf(TEXT("surface round trip %s"), *EnumToString(Surface)), SurfaceFromPhysicalSurface(PhysicalSurfaceFromSurface(Surface)), Surface);
	}
	TestEqual(TEXT("default physical surface maps to asphalt"), SurfaceFromPhysicalSurface(SurfaceType_Default), ERoamSurface::Asphalt);
	TestEqual(TEXT("SurfaceType3 is dirt"), SurfaceFromPhysicalSurface(SurfaceType3), ERoamSurface::Dirt);
	TestEqual(TEXT("unknown surface type maps to asphalt"), SurfaceFromPhysicalSurface(SurfaceType20), ERoamSurface::Asphalt);

	// enum text
	TestEqual(TEXT("enum to string"), EnumToString(ERoamWeather::Storm), FString(TEXT("Storm")));
	ERoamWeather Weather = ERoamWeather::Clear;
	TestTrue(TEXT("parse is case-insensitive"), ParseEnum(TEXT("rAiN"), Weather));
	TestEqual(TEXT("parsed value"), Weather, ERoamWeather::Rain);
	TestFalse(TEXT("unknown text fails"), ParseEnum(TEXT("blizzard"), Weather));
	TestFalse(TEXT("the hidden Count entry cannot be parsed"), ParseEnum(TEXT("Count"), Weather));

	// assists
	ERoamAssist Assist = ERoamAssist::ABS;
	TestTrue(TEXT("tcs"), ParseAssistName(TEXT("TCS"), Assist) && Assist == ERoamAssist::TractionControl);
	TestTrue(TEXT("stability"), ParseAssistName(TEXT("stability"), Assist) && Assist == ERoamAssist::StabilityControl);
	TestTrue(TEXT("steer"), ParseAssistName(TEXT("steer"), Assist) && Assist == ERoamAssist::SteeringAssist);
	TestFalse(TEXT("unknown assist"), ParseAssistName(TEXT("warp"), Assist));
	FRoamAssistSettings Assists;
	TestTrue(TEXT("default TCS on"), Assists.Get(ERoamAssist::TractionControl));
	Assists.Set(ERoamAssist::TractionControl, false);
	TestFalse(TEXT("TCS switched off"), Assists.Get(ERoamAssist::TractionControl));
	Assists.Set(ERoamAssist::SteeringAssist, false);
	TestNearlyEqual(TEXT("steering assist off = 0"), Assists.SteeringAssist, 0.0f, 0.0001f);

	// units
	TestNearlyEqual(TEXT("100 km/h in cm/s"), KmhToCms(100.0f), 2777.78f, 0.1f);
	TestNearlyEqual(TEXT("cm/s to km/h"), CmsToKmh(2777.78f), 100.0f, 0.01f);
	TestNearlyEqual(TEXT("km/h to mph"), KmhToMph(100.0f), 62.1371f, 0.001f);
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
