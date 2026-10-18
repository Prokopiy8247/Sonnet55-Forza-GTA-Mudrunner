// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Styling/SlateColor.h"
#include "Styling/SlateTypes.h"
#include "Framework/SlateDelegates.h"
#include "Input/Reply.h"
#include "Widgets/SWidget.h"

class URoamUISubsystem;
class UGameInstance;
class UWorld;
struct FRoamCarPerformance;
struct FRoamUpgradeSlot;
struct FSlateBrush;

/**
 * Menus (mission B2): in-game console, garage, debug/benchmark menu and pause menu (SRoamConsole, SRoamGarageMenu, SRoamDebugMenu,
 * SRoamPauseMenu). This header holds
 *   1. the single entry point the UI owner calls:  RoamRegisterMenuScreens(URoamUISubsystem*)  (idempotent),
 *   2. the PURE logic of the menus (autocomplete, history cursor, stat normalisation, upgrade deltas, formatting) - unit tested in
 *      Tests/RoamMenuTests.cpp, no Slate and no UObject needed,
 *   3. the shared look (dark glass panels, festival orange + teal accents, engine Roboto font) and small widget builders.
 *
 * Wiring (see RoamMenus.cpp): the widgets are created by RoamRegisterMenuScreens, added with URoamUISubsystem::AddViewportWidget and
 * shown/hidden by listening to URoamUISubsystem::OnPanelChanged (Console, Garage, DebugMenu, PauseMenu). A fallback ticker also calls
 * RoamRegisterMenuScreens as soon as a HUD is ready, so the menus work even before the UI owner adds the call to CreateWidgets().
 */

/** Creates the console / garage / debug / pause widgets for this UI subsystem and hooks them to the panel state. Safe to call repeatedly. */
SONNET55FORZA_API void RoamRegisterMenuScreens(URoamUISubsystem* UI);
/** Removes the hooks and releases the widgets (the viewport widgets themselves are removed by the UI subsystem). */
SONNET55FORZA_API void RoamUnregisterMenuScreens(URoamUISubsystem* UI);

namespace RoamMenus
{
	// =================================================================================================================
	// Pure logic
	// =================================================================================================================

	// ---- autocomplete -------------------------------------------------------------------------------------------------

	/** Fills the valid values for argument ArgIndex (0 = first argument after the command) of Command. May add nothing. */
	using FArgumentProvider = TFunctionRef<void(const FString& Command, int32 ArgIndex, TArray<FString>& OutOptions)>;

	struct FAutocompleteResult
	{
		/** The input text after completion (unchanged if nothing matched). */
		FString Completed;
		/** Everything that matched the token being completed, sorted, unique. */
		TArray<FString> Matches;
		/** Text before the completed token (everything up to and including the last space). */
		FString Prefix;
		/** 0 = the command itself, 1 = first argument, ... */
		int32 TokenIndex = 0;
		bool bAmbiguous = false;
	};

	/**
	 * One Tab press: completes the LAST token of Input. The first token is completed from CommandNames, later tokens from ArgProvider.
	 * Matching is case-insensitive prefix matching; one match is completed and followed by a space, several matches are extended to their
	 * longest common prefix (bAmbiguous = true).
	 */
	SONNET55FORZA_API FAutocompleteResult Autocomplete(const FString& Input, const TArray<FString>& CommandNames, FArgumentProvider ArgProvider);

	/** Splits the input for completion: Prefix = up to and including the last whitespace, Token = rest; returns the 0-based token index. */
	SONNET55FORZA_API int32 SplitForCompletion(const FString& Input, FString& OutPrefix, FString& OutToken, FString& OutCommand);

	/** Tab / Shift+Tab state: the first press completes, further presses (text unchanged) cycle through the matches. */
	class SONNET55FORZA_API FAutocompleteSession
	{
	public:
		FString Complete(const FString& Current, const TArray<FString>& CommandNames, FArgumentProvider ArgProvider, bool bBackward = false);
		const TArray<FString>& GetMatches() const { return Matches; }
		int32 GetCycleIndex() const { return CycleIndex; }
		void Reset();

	private:
		FString LastOutput;
		FString Prefix;
		TArray<FString> Matches;
		int32 CycleIndex = INDEX_NONE;
	};

	// ---- history ------------------------------------------------------------------------------------------------------

	/**
	 * Up/Down browsing of a command history (oldest first, as URoamConsoleSubsystem::GetHistory). The text being typed when browsing
	 * starts is kept as a draft and restored when the user walks past the newest entry.
	 */
	class SONNET55FORZA_API FHistoryCursor
	{
	public:
		/** Up: older entry. Returns false (OutText unchanged) when there is no history. At the oldest entry it stays there. */
		bool Older(const TArray<FString>& History, const FString& CurrentText, FString& OutText);
		/** Down: newer entry, finally the draft. Returns false when not browsing. */
		bool Newer(const TArray<FString>& History, FString& OutText);
		void Reset();
		bool IsBrowsing() const { return Index != INDEX_NONE; }
		int32 GetIndex() const { return Index; }

	private:
		int32 Index = INDEX_NONE;
		FString Draft;
	};

	// ---- stats --------------------------------------------------------------------------------------------------------

	enum class EStat : uint8
	{
		Speed = 0,
		Handling,
		Acceleration,
		Launch,
		Braking,
		Offroad,
		Count
	};
	constexpr int32 NumStats = static_cast<int32>(EStat::Count);

	/** Six normalised (0..1) values in EStat order. */
	struct FStatValues
	{
		float V[NumStats] = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f };
		float& operator[](EStat Stat) { return V[static_cast<int32>(Stat)]; }
		float operator[](EStat Stat) const { return V[static_cast<int32>(Stat)]; }
	};

	SONNET55FORZA_API const TCHAR* StatLabel(EStat Stat);
	/** Car-definition ratings are 0..10 (FRoamCarPerformance::Rating*): returns 0..1, clamped, NaN-safe. */
	SONNET55FORZA_API float NormalizeRating(float Rating0To10);
	SONNET55FORZA_API FStatValues MakeStatValues(const FRoamCarPerformance& Performance);

	/** Data-only upgrade model: stat deltas (in normalised units) of one upgrade category installed at Tier (0 = stock). */
	SONNET55FORZA_API FStatValues UpgradeDelta(ERoamUpgradeCategory Category, int32 Tier);
	/** Sum over all slots of the car for the installed tiers (Upgrades maps SlotId -> tier; tiers are clamped to the slot's MaxTier). */
	SONNET55FORZA_API FStatValues TotalUpgradeDelta(const TArray<FRoamUpgradeSlot>& Slots, const TMap<FName, int32>& Upgrades);
	/** Base + Delta, clamped to 0..1. */
	SONNET55FORZA_API FStatValues ApplyDelta(const FStatValues& Base, const FStatValues& Delta);
	/** Slots used when a car definition has none: one per category, three tiers (so the upgrade tab always has something to show). */
	SONNET55FORZA_API void BuildDefaultUpgradeSlots(TArray<FRoamUpgradeSlot>& OutSlots);
	/** "+0.4 SPD  +0.5 ACC" style summary of a delta in rating points (0..10 scale); empty when nothing changes. */
	SONNET55FORZA_API FString FormatDelta(const FStatValues& Delta);

	// ---- formatting ---------------------------------------------------------------------------------------------------

	/** 13.5 -> "13:30" (wraps into 0..24). */
	SONNET55FORZA_API FString FormatClockHour(float Hour);
	SONNET55FORZA_API float KwToHp(float Kw);
	/** "212 kW / 284 hp". */
	SONNET55FORZA_API FString FormatPower(float Kw);
	/** Speed with unit, e.g. "123 km/h" or "76 mph". */
	SONNET55FORZA_API FString FormatSpeed(float Kmh, bool bMph);
	SONNET55FORZA_API FString DrivetrainLabel(ERoamDrivetrain Drivetrain);

	// =================================================================================================================
	// Look and widget builders (RoamMenus.cpp)
	// =================================================================================================================
	namespace Style
	{
		// Palette (original: dark glass + festival orange + lagoon teal).
		SONNET55FORZA_API FLinearColor Glass();      // panel fill
		SONNET55FORZA_API FLinearColor GlassLight(); // raised rows / buttons
		SONNET55FORZA_API FLinearColor Orange();
		SONNET55FORZA_API FLinearColor Teal();
		SONNET55FORZA_API FLinearColor Chalk();      // primary text
		SONNET55FORZA_API FLinearColor Dim();        // secondary text
		SONNET55FORZA_API FLinearColor Danger();
		SONNET55FORZA_API FLinearColor Good();

		SONNET55FORZA_API FSlateFontInfo Font(int32 Size, bool bBold = false);
		/** Rounded dark glass panel (tinted by the border colour, use FLinearColor::White for the brush's own colour). */
		SONNET55FORZA_API const FSlateBrush* PanelBrush();
		/** Rounded white box for tinting (rows, pills, swatches). */
		SONNET55FORZA_API const FSlateBrush* PillBrush();
		/** Square white box (dividers, accent bars, bar fills). */
		SONNET55FORZA_API const FSlateBrush* FlatBrush();
		SONNET55FORZA_API const FButtonStyle* Button();
		SONNET55FORZA_API const FSliderStyle* Slider();
		SONNET55FORZA_API const FProgressBarStyle* Bar();
	}

	/**
	 * Rounded button with a keyboard/gamepad focus ring. Tint = background colour. bFocusable false keeps the keyboard focus on the game
	 * (used by the debug menu, which must not stop the car from being driven).
	 */
	SONNET55FORZA_API TSharedRef<SWidget> MakeButton(const TAttribute<FText>& Label, FOnClicked OnClicked, const TAttribute<FSlateColor>& Tint,
		bool bFocusable = true, int32 FontSize = 20, const TAttribute<bool>& bEnabled = true, TSharedPtr<SWidget>* OutButton = nullptr);
	/** Small orange-accented section title. */
	SONNET55FORZA_API TSharedRef<SWidget> MakeSectionTitle(const FText& Title, int32 FontSize = 20);
	/** Label + horizontal bar + value text. Delta01 > 0 draws a brighter segment after the base (upgrade preview). */
	SONNET55FORZA_API TSharedRef<SWidget> MakeStatBar(const FText& Label, const TAttribute<float>& Value01, const TAttribute<float>& Delta01,
		const FLinearColor& Color, const TAttribute<FText>& ValueText, float LabelWidth = 160.0f, int32 FontSize = 18);
	/** Coloured class + PI pill ("A 742"). */
	SONNET55FORZA_API TSharedRef<SWidget> MakeClassBadge(const TAttribute<ERoamCarClass>& Class, const TAttribute<int32>& PerformanceIndex, int32 FontSize = 18);

	/** Returns the UI subsystem's game instance world, or null. */
	SONNET55FORZA_API UWorld* GetWorld(const UGameInstance* GameInstance);
}
