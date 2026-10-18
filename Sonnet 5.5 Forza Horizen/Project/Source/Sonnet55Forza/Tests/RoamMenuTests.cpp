// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Data/RoamCarDefinition.h"
#include "UI/RoamMenus.h"

#define ROAM_MENU_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

namespace
{
	TArray<FString> TestCommands()
	{
		return { TEXT("car"), TEXT("cars"), TEXT("camera"), TEXT("clear"), TEXT("time"), TEXT("timescale"), TEXT("tp"), TEXT("weather"), TEXT("wetness") };
	}

	void TestArguments(const FString& Command, int32 ArgIndex, TArray<FString>& Out)
	{
		if (Command == TEXT("weather") && ArgIndex == 0)
		{
			Out = { TEXT("clear"), TEXT("cloudy"), TEXT("rain"), TEXT("fog"), TEXT("storm") };
		}
		else if (Command == TEXT("tp") && ArgIndex == 0)
		{
			Out = { TEXT("Harbor"), TEXT("highlands"), TEXT("Harbor") };
		}
	}
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamMenuAutocompleteTest, "Roam.Menus.Autocomplete", ROAM_MENU_TEST_FLAGS)
bool FRoamMenuAutocompleteTest::RunTest(const FString& Parameters)
{
	using namespace RoamMenus;
	const TArray<FString> Commands = TestCommands();

	{ // unique command prefix: completed and followed by a space
		const FAutocompleteResult R = Autocomplete(TEXT("wea"), Commands, TestArguments);
		TestEqual(TEXT("unique command"), R.Completed, FString(TEXT("weather ")));
		TestEqual(TEXT("one match"), R.Matches.Num(), 1);
		TestFalse(TEXT("not ambiguous"), R.bAmbiguous);
		TestEqual(TEXT("token index 0"), R.TokenIndex, 0);
	}
	{ // ambiguous: extended to the longest common prefix, all matches listed (sorted)
		const FAutocompleteResult R = Autocomplete(TEXT("c"), Commands, TestArguments);
		TestEqual(TEXT("4 matches"), R.Matches.Num(), 4);
		TestTrue(TEXT("ambiguous"), R.bAmbiguous);
		TestEqual(TEXT("no common extension"), R.Completed, FString(TEXT("c")));
		TestEqual(TEXT("sorted"), R.Matches[0], FString(TEXT("camera")));
		const FAutocompleteResult R2 = Autocomplete(TEXT("t"), Commands, TestArguments);
		TestEqual(TEXT("time/timescale/tp"), R2.Matches.Num(), 3);
		const FAutocompleteResult R3 = Autocomplete(TEXT("ti"), Commands, TestArguments);
		TestEqual(TEXT("common prefix 'time'"), R3.Completed, FString(TEXT("time")));
	}
	{ // case-insensitive
		const FAutocompleteResult R = Autocomplete(TEXT("WEA"), Commands, TestArguments);
		TestEqual(TEXT("case-insensitive"), R.Completed, FString(TEXT("weather ")));
	}
	{ // arguments come from the provider
		const FAutocompleteResult R = Autocomplete(TEXT("weather r"), Commands, TestArguments);
		TestEqual(TEXT("argument completed"), R.Completed, FString(TEXT("weather rain ")));
		TestEqual(TEXT("token index 1"), R.TokenIndex, 1);
		const FAutocompleteResult All = Autocomplete(TEXT("weather "), Commands, TestArguments);
		TestEqual(TEXT("all arguments listed"), All.Matches.Num(), 5);
		const FAutocompleteResult Dup = Autocomplete(TEXT("tp h"), Commands, TestArguments);
		TestEqual(TEXT("duplicates removed, case-insensitive prefix"), Dup.Matches.Num(), 2);
		const FAutocompleteResult Unknown = Autocomplete(TEXT("nosuch x"), Commands, TestArguments);
		TestEqual(TEXT("unknown command: unchanged"), Unknown.Completed, FString(TEXT("nosuch x")));
		TestEqual(TEXT("no matches"), Unknown.Matches.Num(), 0);
	}
	{ // empty input lists every command
		const FAutocompleteResult R = Autocomplete(FString(), Commands, TestArguments);
		TestEqual(TEXT("all commands"), R.Matches.Num(), Commands.Num());
	}
	{ // session: Tab cycles through the matches, Shift+Tab goes backwards
		FAutocompleteSession Session;
		FString Text = Session.Complete(TEXT("c"), Commands, TestArguments);
		TestEqual(TEXT("first press does not extend"), Text, FString(TEXT("c")));
		Text = Session.Complete(Text, Commands, TestArguments);
		TestEqual(TEXT("second press: first match"), Text, FString(TEXT("camera")));
		Text = Session.Complete(Text, Commands, TestArguments);
		TestEqual(TEXT("third press: next match"), Text, FString(TEXT("car")));
		Text = Session.Complete(Text, Commands, TestArguments, true);
		TestEqual(TEXT("shift+tab: back"), Text, FString(TEXT("camera")));
		Text = Session.Complete(Text, Commands, TestArguments, true);
		TestEqual(TEXT("shift+tab wraps"), Text, FString(TEXT("clear")));
		// editing the text starts a new completion
		Text = Session.Complete(TEXT("tim"), Commands, TestArguments);
		TestEqual(TEXT("new input"), Text, FString(TEXT("time")));
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamMenuHistoryTest, "Roam.Menus.History", ROAM_MENU_TEST_FLAGS)
bool FRoamMenuHistoryTest::RunTest(const FString& Parameters)
{
	using namespace RoamMenus;
	const TArray<FString> History = { TEXT("help"), TEXT("time 18"), TEXT("weather rain") };
	FHistoryCursor Cursor;
	FString Out;

	TestFalse(TEXT("empty history"), FHistoryCursor().Older(TArray<FString>(), TEXT("x"), Out));
	TestFalse(TEXT("newer without browsing"), Cursor.Newer(History, Out));

	TestTrue(TEXT("up"), Cursor.Older(History, TEXT("draft"), Out));
	TestEqual(TEXT("newest first"), Out, FString(TEXT("weather rain")));
	TestTrue(TEXT("browsing"), Cursor.IsBrowsing());
	TestTrue(TEXT("up"), Cursor.Older(History, Out, Out));
	TestEqual(TEXT("older"), Out, FString(TEXT("time 18")));
	TestTrue(TEXT("up"), Cursor.Older(History, Out, Out));
	TestEqual(TEXT("oldest"), Out, FString(TEXT("help")));
	TestTrue(TEXT("up at the top"), Cursor.Older(History, Out, Out));
	TestEqual(TEXT("stays at the oldest"), Out, FString(TEXT("help")));

	TestTrue(TEXT("down"), Cursor.Newer(History, Out));
	TestEqual(TEXT("newer"), Out, FString(TEXT("time 18")));
	TestTrue(TEXT("down"), Cursor.Newer(History, Out));
	TestEqual(TEXT("newest"), Out, FString(TEXT("weather rain")));
	TestTrue(TEXT("down past the newest"), Cursor.Newer(History, Out));
	TestEqual(TEXT("the draft comes back"), Out, FString(TEXT("draft")));
	TestFalse(TEXT("no longer browsing"), Cursor.IsBrowsing());

	// the history shrinking while browsing must not read out of range
	TestTrue(TEXT("restart"), Cursor.Older(History, TEXT("d2"), Out));
	const TArray<FString> Short = { TEXT("only") };
	TestTrue(TEXT("down on a shorter history"), Cursor.Newer(Short, Out));
	TestEqual(TEXT("draft restored"), Out, FString(TEXT("d2")));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamMenuStatsTest, "Roam.Menus.Stats", ROAM_MENU_TEST_FLAGS)
bool FRoamMenuStatsTest::RunTest(const FString& Parameters)
{
	using namespace RoamMenus;
	TestNearlyEqual(TEXT("5/10"), NormalizeRating(5.0f), 0.5f);
	TestNearlyEqual(TEXT("clamped high"), NormalizeRating(14.0f), 1.0f);
	TestNearlyEqual(TEXT("clamped low"), NormalizeRating(-3.0f), 0.0f);
	TestNearlyEqual(TEXT("NaN"), NormalizeRating(NAN), 0.0f);

	FRoamCarPerformance Performance;
	Performance.RatingSpeed = 10.0f;
	Performance.RatingHandling = 7.5f;
	Performance.RatingAcceleration = 5.0f;
	Performance.RatingLaunch = 2.5f;
	Performance.RatingBraking = 0.0f;
	Performance.RatingOffroad = 12.0f;
	const FStatValues Stats = MakeStatValues(Performance);
	TestNearlyEqual(TEXT("speed"), Stats[EStat::Speed], 1.0f);
	TestNearlyEqual(TEXT("handling"), Stats[EStat::Handling], 0.75f);
	TestNearlyEqual(TEXT("acceleration"), Stats[EStat::Acceleration], 0.5f);
	TestNearlyEqual(TEXT("launch"), Stats[EStat::Launch], 0.25f);
	TestNearlyEqual(TEXT("braking"), Stats[EStat::Braking], 0.0f);
	TestNearlyEqual(TEXT("offroad clamped"), Stats[EStat::Offroad], 1.0f);

	// upgrade deltas: stock changes nothing, every tier adds, the sum is clamped by ApplyDelta
	const FStatValues Stock = UpgradeDelta(ERoamUpgradeCategory::Engine, 0);
	const FStatValues Tier1 = UpgradeDelta(ERoamUpgradeCategory::Engine, 1);
	const FStatValues Tier3 = UpgradeDelta(ERoamUpgradeCategory::Engine, 3);
	for (int32 i = 0; i < NumStats; ++i)
	{
		TestNearlyEqual(TEXT("stock delta is zero"), Stock.V[i], 0.0f);
		TestTrue(TEXT("deltas never negative"), Tier3.V[i] >= 0.0f);
		TestNearlyEqual(TEXT("linear in the tier"), Tier3.V[i], Tier1.V[i] * 3.0f, 1e-5f);
	}
	TestTrue(TEXT("engine adds speed"), Tier1[EStat::Speed] > 0.0f);
	TestNearlyEqual(TEXT("engine does not add braking"), Tier1[EStat::Braking], 0.0f);
	TestNearlyEqual(TEXT("tier is clamped to 5"), UpgradeDelta(ERoamUpgradeCategory::Engine, 99)[EStat::Speed], UpgradeDelta(ERoamUpgradeCategory::Engine, 5)[EStat::Speed]);

	TArray<FRoamUpgradeSlot> Slots;
	BuildDefaultUpgradeSlots(Slots);
	TestEqual(TEXT("one default slot per category"), Slots.Num(), 6);
	TMap<FName, int32> Installed;
	TestNearlyEqual(TEXT("nothing installed"), TotalUpgradeDelta(Slots, Installed)[EStat::Speed], 0.0f);
	Installed.Add(Slots[1].SlotId, 2);
	Installed.Add(Slots[5].SlotId, 99); // clamped to the slot's MaxTier (3)
	const FStatValues Total = TotalUpgradeDelta(Slots, Installed);
	const float Expected = UpgradeDelta(ERoamUpgradeCategory::Engine, 2)[EStat::Speed] + UpgradeDelta(ERoamUpgradeCategory::Drivetrain, 3)[EStat::Speed];
	TestNearlyEqual(TEXT("sum with clamped tier"), Total[EStat::Speed], Expected, 1e-5f);

	FStatValues Near;
	Near[EStat::Speed] = 0.97f;
	const FStatValues Applied = ApplyDelta(Near, Total);
	TestTrue(TEXT("ApplyDelta clamps to 1"), Applied[EStat::Speed] <= 1.0f);
	TestTrue(TEXT("delta text"), FormatDelta(Tier1).Contains(TEXT("SPD")));
	TestTrue(TEXT("no delta, no text"), FormatDelta(Stock).IsEmpty());
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamMenuFormatTest, "Roam.Menus.Format", ROAM_MENU_TEST_FLAGS)
bool FRoamMenuFormatTest::RunTest(const FString& Parameters)
{
	using namespace RoamMenus;
	TestEqual(TEXT("13.5"), FormatClockHour(13.5f), FString(TEXT("13:30")));
	TestEqual(TEXT("0"), FormatClockHour(0.0f), FString(TEXT("00:00")));
	TestEqual(TEXT("wrap 25.25"), FormatClockHour(25.25f), FString(TEXT("01:15")));
	TestEqual(TEXT("negative"), FormatClockHour(-1.0f), FString(TEXT("23:00")));
	TestEqual(TEXT("rounds up to the next hour"), FormatClockHour(23.999f), FString(TEXT("00:00")));
	TestEqual(TEXT("km/h"), FormatSpeed(100.0f, false), FString(TEXT("100 km/h")));
	TestEqual(TEXT("mph"), FormatSpeed(100.0f, true), FString(TEXT("62 mph")));
	TestEqual(TEXT("power"), FormatPower(100.0f), FString(TEXT("100 kW / 134 hp")));
	TestEqual(TEXT("AWD"), DrivetrainLabel(ERoamDrivetrain::AWD), FString(TEXT("AWD")));
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
