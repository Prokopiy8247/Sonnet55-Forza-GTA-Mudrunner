// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/RoamMenus.h"

#include "Brushes/SlateColorBrush.h"
#include "Brushes/SlateNoResource.h"
#include "Brushes/SlateRoundedBoxBrush.h"
#include "Console/RoamConsoleSubsystem.h"
#include "Containers/Ticker.h"
#include "Core/RoamHUD.h"
#include "Core/RoamLog.h"
#include "Data/RoamCarDefinition.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/PlayerController.h"
#include "Kismet/KismetSystemLibrary.h"
#include "Misc/CoreDelegates.h"
#include "Styling/CoreStyle.h"
#include "UI/RoamUISubsystem.h"
#include "UI/SRoamConsole.h"
#include "UI/SRoamDebugMenu.h"
#include "UI/SRoamGarageMenu.h"
#include "UI/SRoamPauseMenu.h"
#include "Vehicle/RoamVehicle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Notifications/SProgressBar.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SOverlay.h"
#include "Widgets/Text/STextBlock.h"

#define LOCTEXT_NAMESPACE "RoamMenus"

// ======================================================================================================================
// Pure logic
// ======================================================================================================================

namespace RoamMenus
{
	int32 SplitForCompletion(const FString& Input, FString& OutPrefix, FString& OutToken, FString& OutCommand)
	{
		int32 LastSpace = INDEX_NONE;
		for (int32 i = Input.Len() - 1; i >= 0; --i)
		{
			if (FChar::IsWhitespace(Input[i]))
			{
				LastSpace = i;
				break;
			}
		}
		OutPrefix = LastSpace == INDEX_NONE ? FString() : Input.Left(LastSpace + 1);
		OutToken = Input.Mid(LastSpace + 1);
		TArray<FString> Words;
		OutPrefix.ParseIntoArrayWS(Words);
		OutCommand = Words.Num() > 0 ? Words[0].ToLower() : FString();
		return Words.Num();
	}

	FAutocompleteResult Autocomplete(const FString& Input, const TArray<FString>& CommandNames, FArgumentProvider ArgProvider)
	{
		FAutocompleteResult Result;
		Result.Completed = Input;
		FString Token;
		FString Command;
		Result.TokenIndex = SplitForCompletion(Input, Result.Prefix, Token, Command);

		TArray<FString> Options;
		if (Result.TokenIndex == 0)
		{
			Options = CommandNames;
		}
		else
		{
			ArgProvider(Command, Result.TokenIndex - 1, Options);
		}
		for (const FString& Option : Options)
		{
			// FString::StartsWith("") is false, an empty token must match everything.
			if ((Token.IsEmpty() || Option.StartsWith(Token, ESearchCase::IgnoreCase))
				&& !Result.Matches.ContainsByPredicate([&Option](const FString& Existing) { return Existing.Equals(Option, ESearchCase::IgnoreCase); }))
			{
				Result.Matches.Add(Option);
			}
		}
		Result.Matches.Sort([](const FString& A, const FString& B) { return A.Compare(B, ESearchCase::IgnoreCase) < 0; });

		if (Result.Matches.Num() == 1)
		{
			Result.Completed = Result.Prefix + Result.Matches[0] + TEXT(" ");
		}
		else if (Result.Matches.Num() > 1)
		{
			Result.bAmbiguous = true;
			FString Common = Result.Matches[0];
			for (int32 i = 1; i < Result.Matches.Num(); ++i)
			{
				int32 Keep = 0;
				const int32 MaxKeep = FMath::Min(Common.Len(), Result.Matches[i].Len());
				while (Keep < MaxKeep && FChar::ToLower(Common[Keep]) == FChar::ToLower(Result.Matches[i][Keep]))
				{
					++Keep;
				}
				Common = Common.Left(Keep);
			}
			if (Common.Len() > Token.Len())
			{
				Result.Completed = Result.Prefix + Common;
			}
		}
		return Result;
	}

	FString FAutocompleteSession::Complete(const FString& Current, const TArray<FString>& CommandNames, FArgumentProvider ArgProvider, bool bBackward)
	{
		if (Matches.Num() > 1 && Current == LastOutput)
		{
			const int32 Num = Matches.Num();
			if (CycleIndex == INDEX_NONE)
			{
				CycleIndex = bBackward ? Num - 1 : 0;
			}
			else
			{
				CycleIndex = (CycleIndex + (bBackward ? -1 : 1) + Num) % Num;
			}
			LastOutput = Prefix + Matches[CycleIndex];
			return LastOutput;
		}
		const FAutocompleteResult Result = Autocomplete(Current, CommandNames, ArgProvider);
		Prefix = Result.Prefix;
		Matches = Result.Matches;
		CycleIndex = INDEX_NONE;
		LastOutput = Result.Completed;
		return LastOutput;
	}

	void FAutocompleteSession::Reset()
	{
		LastOutput.Reset();
		Prefix.Reset();
		Matches.Reset();
		CycleIndex = INDEX_NONE;
	}

	bool FHistoryCursor::Older(const TArray<FString>& History, const FString& CurrentText, FString& OutText)
	{
		if (History.Num() == 0)
		{
			return false;
		}
		if (Index == INDEX_NONE)
		{
			Draft = CurrentText;
			Index = History.Num() - 1;
		}
		else if (Index > 0)
		{
			--Index;
		}
		Index = FMath::Clamp(Index, 0, History.Num() - 1);
		OutText = History[Index];
		return true;
	}

	bool FHistoryCursor::Newer(const TArray<FString>& History, FString& OutText)
	{
		if (Index == INDEX_NONE)
		{
			return false;
		}
		++Index;
		if (Index >= History.Num())
		{
			Index = INDEX_NONE;
			OutText = Draft;
			Draft.Reset();
		}
		else
		{
			OutText = History[Index];
		}
		return true;
	}

	void FHistoryCursor::Reset()
	{
		Index = INDEX_NONE;
		Draft.Reset();
	}

	const TCHAR* StatLabel(EStat Stat)
	{
		switch (Stat)
		{
		case EStat::Speed: return TEXT("SPEED");
		case EStat::Handling: return TEXT("HANDLING");
		case EStat::Acceleration: return TEXT("ACCELERATION");
		case EStat::Launch: return TEXT("LAUNCH");
		case EStat::Braking: return TEXT("BRAKING");
		case EStat::Offroad: return TEXT("OFFROAD");
		default: return TEXT("");
		}
	}

	float NormalizeRating(float Rating0To10)
	{
		if (!FMath::IsFinite(Rating0To10))
		{
			return 0.0f;
		}
		return FMath::Clamp(Rating0To10 / 10.0f, 0.0f, 1.0f);
	}

	FStatValues MakeStatValues(const FRoamCarPerformance& Performance)
	{
		FStatValues Out;
		Out[EStat::Speed] = NormalizeRating(Performance.RatingSpeed);
		Out[EStat::Handling] = NormalizeRating(Performance.RatingHandling);
		Out[EStat::Acceleration] = NormalizeRating(Performance.RatingAcceleration);
		Out[EStat::Launch] = NormalizeRating(Performance.RatingLaunch);
		Out[EStat::Braking] = NormalizeRating(Performance.RatingBraking);
		Out[EStat::Offroad] = NormalizeRating(Performance.RatingOffroad);
		return Out;
	}

	FStatValues UpgradeDelta(ERoamUpgradeCategory Category, int32 Tier)
	{
		// Per-tier gains in normalised units (0.05 = half a rating point on the 0..10 scale). Data-only: the vehicle physics owner
		// decides what an installed tier really does; the garage uses this table to preview the effect.
		FStatValues PerTier;
		switch (Category)
		{
		case ERoamUpgradeCategory::Conversion:
			PerTier[EStat::Launch] = 0.030f; PerTier[EStat::Offroad] = 0.040f; PerTier[EStat::Handling] = 0.010f;
			break;
		case ERoamUpgradeCategory::Engine:
			PerTier[EStat::Speed] = 0.045f; PerTier[EStat::Acceleration] = 0.050f; PerTier[EStat::Launch] = 0.020f;
			break;
		case ERoamUpgradeCategory::PlatformHandling:
			PerTier[EStat::Handling] = 0.050f; PerTier[EStat::Braking] = 0.030f; PerTier[EStat::Offroad] = 0.010f;
			break;
		case ERoamUpgradeCategory::TiresRims:
			PerTier[EStat::Handling] = 0.030f; PerTier[EStat::Launch] = 0.040f; PerTier[EStat::Braking] = 0.040f; PerTier[EStat::Offroad] = 0.020f;
			break;
		case ERoamUpgradeCategory::AeroAppearance:
			PerTier[EStat::Speed] = 0.020f; PerTier[EStat::Handling] = 0.030f; PerTier[EStat::Braking] = 0.010f;
			break;
		case ERoamUpgradeCategory::Drivetrain:
			PerTier[EStat::Acceleration] = 0.030f; PerTier[EStat::Launch] = 0.050f; PerTier[EStat::Speed] = 0.010f;
			break;
		default:
			break;
		}
		const float Scale = static_cast<float>(FMath::Clamp(Tier, 0, 5));
		FStatValues Out;
		for (int32 i = 0; i < NumStats; ++i)
		{
			Out.V[i] = PerTier.V[i] * Scale;
		}
		return Out;
	}

	FStatValues TotalUpgradeDelta(const TArray<FRoamUpgradeSlot>& Slots, const TMap<FName, int32>& Upgrades)
	{
		FStatValues Total;
		for (const FRoamUpgradeSlot& Slot : Slots)
		{
			const int32* Installed = Upgrades.Find(Slot.SlotId);
			const int32 Tier = FMath::Clamp(Installed ? *Installed : 0, 0, FMath::Max(0, Slot.MaxTier));
			const FStatValues Delta = UpgradeDelta(Slot.Category, Tier);
			for (int32 i = 0; i < NumStats; ++i)
			{
				Total.V[i] += Delta.V[i];
			}
		}
		return Total;
	}

	FStatValues ApplyDelta(const FStatValues& Base, const FStatValues& Delta)
	{
		FStatValues Out;
		for (int32 i = 0; i < NumStats; ++i)
		{
			Out.V[i] = FMath::Clamp(Base.V[i] + Delta.V[i], 0.0f, 1.0f);
		}
		return Out;
	}

	void BuildDefaultUpgradeSlots(TArray<FRoamUpgradeSlot>& OutSlots)
	{
		struct FDefault { const TCHAR* Id; ERoamUpgradeCategory Category; int32 Price; };
		static const FDefault Defaults[] =
		{
			{ TEXT("Conversion.Kit"), ERoamUpgradeCategory::Conversion, 3000 },
			{ TEXT("Engine.Tune"), ERoamUpgradeCategory::Engine, 4000 },
			{ TEXT("PlatformHandling.Chassis"), ERoamUpgradeCategory::PlatformHandling, 3500 },
			{ TEXT("TiresRims.Set"), ERoamUpgradeCategory::TiresRims, 2500 },
			{ TEXT("AeroAppearance.Kit"), ERoamUpgradeCategory::AeroAppearance, 2000 },
			{ TEXT("Drivetrain.Pack"), ERoamUpgradeCategory::Drivetrain, 3200 },
		};
		OutSlots.Reset();
		for (const FDefault& Entry : Defaults)
		{
			FRoamUpgradeSlot Slot;
			Slot.SlotId = Entry.Id;
			Slot.Category = Entry.Category;
			Slot.MaxTier = 3;
			Slot.TierPriceCredits = { Entry.Price, Entry.Price * 2, Entry.Price * 4 };
			OutSlots.Add(Slot);
		}
	}

	FString FormatDelta(const FStatValues& Delta)
	{
		static const TCHAR* Short[NumStats] = { TEXT("SPD"), TEXT("HND"), TEXT("ACC"), TEXT("LCH"), TEXT("BRK"), TEXT("OFF") };
		FString Out;
		for (int32 i = 0; i < NumStats; ++i)
		{
			const float Points = Delta.V[i] * 10.0f;
			if (FMath::Abs(Points) >= 0.05f)
			{
				Out += FString::Printf(TEXT("%s%+.1f %s"), Out.IsEmpty() ? TEXT("") : TEXT("   "), Points, Short[i]);
			}
		}
		return Out;
	}

	FString FormatClockHour(float Hour)
	{
		float H = FMath::Fmod(Hour, 24.0f);
		if (H < 0.0f)
		{
			H += 24.0f;
		}
		const int32 TotalMinutes = FMath::RoundToInt(H * 60.0f) % (24 * 60);
		return FString::Printf(TEXT("%02d:%02d"), TotalMinutes / 60, TotalMinutes % 60);
	}

	float KwToHp(float Kw)
	{
		return Kw * 1.34102f;
	}

	FString FormatPower(float Kw)
	{
		return FString::Printf(TEXT("%.0f kW / %.0f hp"), Kw, KwToHp(Kw));
	}

	FString FormatSpeed(float Kmh, bool bMph)
	{
		return bMph ? FString::Printf(TEXT("%d mph"), FMath::RoundToInt(Roam::KmhToMph(Kmh))) : FString::Printf(TEXT("%d km/h"), FMath::RoundToInt(Kmh));
	}

	FString DrivetrainLabel(ERoamDrivetrain Drivetrain)
	{
		switch (Drivetrain)
		{
		case ERoamDrivetrain::FWD: return TEXT("FWD");
		case ERoamDrivetrain::RWD: return TEXT("RWD");
		default: return TEXT("AWD");
		}
	}

	UWorld* GetWorld(const UGameInstance* GameInstance)
	{
		return GameInstance ? GameInstance->GetWorld() : nullptr;
	}
}

// ======================================================================================================================
// Look and widget builders
// ======================================================================================================================

namespace
{
	struct FStyleData
	{
		FSlateRoundedBoxBrush Panel{ FLinearColor::White, 16.0f, FLinearColor(1.0f, 1.0f, 1.0f, 0.09f), 1.5f };
		FSlateRoundedBoxBrush Pill{ FLinearColor::White, 9.0f, FLinearColor::Transparent, 0.0f };
		FSlateRoundedBoxBrush Ring{ FLinearColor::Transparent, 12.0f, FLinearColor::White, 3.0f };
		FSlateRoundedBoxBrush BarBack{ FLinearColor(0.0f, 0.0f, 0.0f, 0.45f), 4.0f, FLinearColor::Transparent, 0.0f };
		FSlateRoundedBoxBrush BarFill{ FLinearColor::White, 4.0f, FLinearColor::Transparent, 0.0f };
		FSlateRoundedBoxBrush Thumb{ FLinearColor::White, 9.0f, FLinearColor::Transparent, 0.0f, FVector2f(18.0f, 18.0f) };
		FSlateColorBrush Flat{ FLinearColor::White };
		FButtonStyle Button;
		FSliderStyle Slider;
		FProgressBarStyle Bar;
		FProgressBarStyle BarOverlay;
		FSlateNoResource NoBrush;

		FStyleData()
		{
			BarOverlay = FProgressBarStyle()
				.SetBackgroundImage(NoBrush)
				.SetFillImage(BarFill)
				.SetMarqueeImage(BarFill)
				.SetEnableFillAnimation(false);
			Button = FButtonStyle()
				.SetNormal(FSlateRoundedBoxBrush(FLinearColor(0.84f, 0.84f, 0.84f, 1.0f), 9.0f, FLinearColor::Transparent, 0.0f))
				.SetHovered(FSlateRoundedBoxBrush(FLinearColor(1.0f, 1.0f, 1.0f, 1.0f), 9.0f, FLinearColor::Transparent, 0.0f))
				.SetPressed(FSlateRoundedBoxBrush(FLinearColor(0.62f, 0.62f, 0.62f, 1.0f), 9.0f, FLinearColor::Transparent, 0.0f))
				.SetDisabled(FSlateRoundedBoxBrush(FLinearColor(0.35f, 0.35f, 0.35f, 0.55f), 9.0f, FLinearColor::Transparent, 0.0f))
				.SetNormalPadding(FMargin(0.0f))
				.SetPressedPadding(FMargin(0.0f, 1.0f, 0.0f, -1.0f));
			Slider = FSliderStyle()
				.SetNormalBarImage(BarBack)
				.SetHoveredBarImage(BarBack)
				.SetDisabledBarImage(BarBack)
				.SetNormalThumbImage(Thumb)
				.SetHoveredThumbImage(Thumb)
				.SetDisabledThumbImage(Thumb)
				.SetBarThickness(7.0f);
			Bar = FProgressBarStyle()
				.SetBackgroundImage(BarBack)
				.SetFillImage(BarFill)
				.SetMarqueeImage(BarFill)
				.SetEnableFillAnimation(false);
		}
	};

	const FStyleData& StyleData()
	{
		static FStyleData Data;
		return Data;
	}
}

namespace RoamMenus
{
	namespace Style
	{
		FLinearColor Glass() { return FLinearColor(0.030f, 0.040f, 0.060f, 0.92f); }
		FLinearColor GlassLight() { return FLinearColor(0.115f, 0.135f, 0.175f, 0.95f); }
		FLinearColor Orange() { return FLinearColor(1.0f, 0.42f, 0.08f, 1.0f); }
		FLinearColor Teal() { return FLinearColor(0.06f, 0.78f, 0.74f, 1.0f); }
		FLinearColor Chalk() { return FLinearColor(0.95f, 0.96f, 0.97f, 1.0f); }
		FLinearColor Dim() { return FLinearColor(0.62f, 0.67f, 0.73f, 1.0f); }
		FLinearColor Danger() { return FLinearColor(1.0f, 0.34f, 0.32f, 1.0f); }
		FLinearColor Good() { return FLinearColor(0.35f, 0.88f, 0.52f, 1.0f); }

		FSlateFontInfo Font(int32 Size, bool bBold)
		{
			return FCoreStyle::GetDefaultFontStyle(bBold ? "Bold" : "Regular", Size);
		}
		const FSlateBrush* PanelBrush() { return &StyleData().Panel; }
		const FSlateBrush* PillBrush() { return &StyleData().Pill; }
		const FSlateBrush* FlatBrush() { return &StyleData().Flat; }
		const FButtonStyle* Button() { return &StyleData().Button; }
		const FSliderStyle* Slider() { return &StyleData().Slider; }
		const FProgressBarStyle* Bar() { return &StyleData().Bar; }
	}

	TSharedRef<SWidget> MakeButton(const TAttribute<FText>& Label, FOnClicked OnClicked, const TAttribute<FSlateColor>& Tint, bool bFocusable,
		int32 FontSize, const TAttribute<bool>& bEnabled, TSharedPtr<SWidget>* OutButton)
	{
		TSharedPtr<SButton> Button;
		const TSharedRef<TWeakPtr<SButton>> WeakHolder = MakeShared<TWeakPtr<SButton>>();
		TSharedRef<SWidget> Outer =
			SNew(SBorder)
			.BorderImage(&StyleData().Ring)
			.Padding(2.0f)
			.BorderBackgroundColor_Lambda([WeakHolder]() -> FSlateColor
			{
				const TSharedPtr<SButton> Pinned = WeakHolder->Pin();
				return (Pinned.IsValid() && Pinned->HasKeyboardFocus()) ? FSlateColor(Style::Teal()) : FSlateColor(FLinearColor::Transparent);
			})
			[
				SAssignNew(Button, SButton)
				.ButtonStyle(Style::Button())
				.ContentPadding(FMargin(16.0f, 8.0f))
				.ButtonColorAndOpacity(Tint)
				.IsFocusable(bFocusable)
				.IsEnabled(bEnabled)
				.OnClicked(OnClicked)
				.HAlign(HAlign_Center)
				.VAlign(VAlign_Center)
				[
					SNew(STextBlock)
					.Text(Label)
					.Font(Style::Font(FontSize, true))
					.ColorAndOpacity(Style::Chalk())
					.Justification(ETextJustify::Center)
				]
			];
		*WeakHolder = Button;
		if (OutButton)
		{
			*OutButton = Button;
		}
		return Outer;
	}

	TSharedRef<SWidget> MakeSectionTitle(const FText& Title, int32 FontSize)
	{
		return SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Fill).Padding(0.0f, 2.0f, 10.0f, 2.0f)
			[
				SNew(SBox).WidthOverride(5.0f)
				[
					SNew(SBorder).BorderImage(Style::FlatBrush()).BorderBackgroundColor(Style::Orange())
				]
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(STextBlock).Text(Title).Font(Style::Font(FontSize, true)).ColorAndOpacity(Style::Chalk())
			];
	}

	TSharedRef<SWidget> MakeStatBar(const FText& Label, const TAttribute<float>& Value01, const TAttribute<float>& Delta01, const FLinearColor& Color,
		const TAttribute<FText>& ValueText, float LabelWidth, int32 FontSize)
	{
		return SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(SBox).WidthOverride(LabelWidth)
				[
					SNew(STextBlock).Text(Label).Font(Style::Font(FontSize - 3, true)).ColorAndOpacity(Style::Dim())
				]
			]
			+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center).Padding(4.0f, 0.0f)
			[
				SNew(SBox).HeightOverride(12.0f)
				[
					SNew(SOverlay)
					+ SOverlay::Slot()
					[
						SNew(SProgressBar)
						.Style(Style::Bar())
						.BorderPadding(FVector2D(0.0f, 0.0f))
						.FillColorAndOpacity(FLinearColor(1.0f, 1.0f, 1.0f, 0.55f))
						.Percent_Lambda([Value01, Delta01]() -> TOptional<float> { return FMath::Clamp(Value01.Get(0.0f) + Delta01.Get(0.0f), 0.0f, 1.0f); })
					]
					+ SOverlay::Slot()
					[
						SNew(SProgressBar)
						.Style(&StyleData().BarOverlay)
						.BorderPadding(FVector2D(0.0f, 0.0f))
						.FillColorAndOpacity(Color)
						.Percent_Lambda([Value01]() -> TOptional<float> { return FMath::Clamp(Value01.Get(0.0f), 0.0f, 1.0f); })
					]
				]
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(SBox).WidthOverride(78.0f)
				[
					SNew(STextBlock).Text(ValueText).Font(Style::Font(FontSize - 2, true)).ColorAndOpacity(Style::Chalk()).Justification(ETextJustify::Right)
				]
			];
	}

	TSharedRef<SWidget> MakeClassBadge(const TAttribute<ERoamCarClass>& Class, const TAttribute<int32>& PerformanceIndex, int32 FontSize)
	{
		return SNew(SBorder)
			.BorderImage(Style::PillBrush())
			.Padding(FMargin(11.0f, 3.0f))
			.BorderBackgroundColor_Lambda([Class]() -> FSlateColor { return FSlateColor(Roam::ClassColor(Class.Get(ERoamCarClass::D))); })
			[
				SNew(STextBlock)
				.Font(Style::Font(FontSize, true))
				.ColorAndOpacity(FLinearColor(0.02f, 0.03f, 0.05f, 1.0f))
				.Text_Lambda([Class, PerformanceIndex]() -> FText
				{
					return FText::FromString(FString::Printf(TEXT("%s %d"), *Roam::ClassToLabel(Class.Get(ERoamCarClass::D)), PerformanceIndex.Get(100)));
				})
			];
	}
}

// ======================================================================================================================
// Registration / wiring
// ======================================================================================================================

namespace
{
	struct FMenuScreens
	{
		TWeakObjectPtr<URoamUISubsystem> UI;
		TWeakObjectPtr<ARoamHUD> HUD;
		TSharedPtr<SRoamConsole> Console;
		TSharedPtr<SRoamConsoleHint> Hint;
		TSharedPtr<SRoamGarageMenu> Garage;
		TSharedPtr<SRoamDebugMenu> Debug;
		TSharedPtr<SRoamDebugOverlay> Overlay;
		TSharedPtr<SRoamPauseMenu> Pause;
		FDelegateHandle PanelHandle;
	};

	TSharedPtr<FMenuScreens> GScreens;
	FTSTicker::FDelegateHandle GFocusTicker;

	void ApplyFocus()
	{
		if (!GScreens.IsValid() || !FSlateApplication::IsInitialized())
		{
			return;
		}
		URoamUISubsystem* UI = GScreens->UI.Get();
		if (!UI)
		{
			return;
		}
		TSharedPtr<SWidget> Target;
		if (UI->IsPanelOpen(ERoamUIPanel::Console) && GScreens->Console.IsValid())
		{
			Target = GScreens->Console->GetFocusWidget();
		}
		else if (UI->IsPanelOpen(ERoamUIPanel::PauseMenu) && GScreens->Pause.IsValid())
		{
			Target = GScreens->Pause->GetFocusWidget();
		}
		else if (UI->IsPanelOpen(ERoamUIPanel::Garage) && GScreens->Garage.IsValid())
		{
			Target = GScreens->Garage->GetFocusWidget();
		}
		if (Target.IsValid())
		{
			FSlateApplication::Get().SetKeyboardFocus(Target, EFocusCause::SetDirectly);
		}
		else
		{
			// Nothing modal is open (the debug menu never takes focus): the game viewport drives the car again.
			FSlateApplication::Get().SetAllUserFocusToGameViewport();
		}
	}

	/** Focus is set one short tick after the panel became visible: Slate cannot focus a widget that was collapsed a moment ago. */
	void ScheduleFocus()
	{
		FTSTicker::GetCoreTicker().RemoveTicker(GFocusTicker);
		GFocusTicker = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([](float) -> bool
		{
			ApplyFocus();
			return false;
		}), 0.04f);
	}

	void HandlePanelChanged(ERoamUIPanel Panel, bool bOpen)
	{
		if (!GScreens.IsValid())
		{
			return;
		}
		FMenuScreens& S = *GScreens;
		switch (Panel)
		{
		case ERoamUIPanel::Console:
			if (S.Console.IsValid())
			{
				S.Console->SetVisibility(bOpen ? EVisibility::Visible : EVisibility::Collapsed);
				if (bOpen) { S.Console->OnOpened(); }
			}
			break;
		case ERoamUIPanel::Garage:
			if (S.Garage.IsValid())
			{
				S.Garage->SetVisibility(bOpen ? EVisibility::Visible : EVisibility::Collapsed);
				if (bOpen) { S.Garage->OnOpened(); }
			}
			break;
		case ERoamUIPanel::DebugMenu:
			if (S.Debug.IsValid())
			{
				S.Debug->SetVisibility(bOpen ? EVisibility::SelfHitTestInvisible : EVisibility::Collapsed);
				if (bOpen) { S.Debug->OnOpened(); }
			}
			break;
		case ERoamUIPanel::PauseMenu:
			if (S.Pause.IsValid())
			{
				S.Pause->SetVisibility(bOpen ? EVisibility::Visible : EVisibility::Collapsed);
				if (bOpen) { S.Pause->OnOpened(); }
			}
			break;
		default:
			break;
		}
		if (S.Hint.IsValid())
		{
			if (const URoamUISubsystem* UI = S.UI.Get())
			{
				S.Hint->SetSuppressed(UI->IsAnyPanelOpen());
			}
		}
		ScheduleFocus();
	}

	bool TickEnsureRegistered(float)
	{
		if (!GEngine || IsRunningCommandlet())
		{
			return true;
		}
		for (const FWorldContext& Context : GEngine->GetWorldContexts())
		{
			if (Context.WorldType != EWorldType::Game && Context.WorldType != EWorldType::PIE)
			{
				continue;
			}
			URoamUISubsystem* UI = Context.OwningGameInstance ? Context.OwningGameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
			if (UI && UI->GetHUD())
			{
				RoamRegisterMenuScreens(UI);
			}
		}
		return true;
	}

	void InstallEnsureTicker()
	{
		if (IsRunningCommandlet() || IsRunningDedicatedServer())
		{
			return;
		}
		FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&TickEnsureRegistered), 0.5f);
		FCoreDelegates::OnEnginePreExit.AddLambda([]() { RoamUnregisterMenuScreens(nullptr); });
	}

	struct FMenuAutoHook
	{
		FMenuAutoHook()
		{
			FCoreDelegates::GetOnPostEngineInit().AddStatic(&InstallEnsureTicker);
		}
	};
	FMenuAutoHook GMenuAutoHook;
}

void RoamUnregisterMenuScreens(URoamUISubsystem* UI)
{
	if (!GScreens.IsValid())
	{
		return;
	}
	URoamUISubsystem* Owner = GScreens->UI.Get();
	if (UI && Owner && UI != Owner)
	{
		return;
	}
	if (Owner)
	{
		Owner->OnPanelChanged.Remove(GScreens->PanelHandle);
		if (GScreens->Console.IsValid()) { Owner->RemoveViewportWidget(GScreens->Console.ToSharedRef()); }
		if (GScreens->Hint.IsValid()) { Owner->RemoveViewportWidget(GScreens->Hint.ToSharedRef()); }
		if (GScreens->Garage.IsValid()) { Owner->RemoveViewportWidget(GScreens->Garage.ToSharedRef()); }
		if (GScreens->Debug.IsValid()) { Owner->RemoveViewportWidget(GScreens->Debug.ToSharedRef()); }
		if (GScreens->Overlay.IsValid()) { Owner->RemoveViewportWidget(GScreens->Overlay.ToSharedRef()); }
		if (GScreens->Pause.IsValid()) { Owner->RemoveViewportWidget(GScreens->Pause.ToSharedRef()); }
	}
	FTSTicker::GetCoreTicker().RemoveTicker(GFocusTicker);
	GScreens.Reset();
}

void RoamRegisterMenuScreens(URoamUISubsystem* UI)
{
	if (!UI || !GEngine || !GEngine->GameViewport || !FSlateApplication::IsInitialized())
	{
		return;
	}
	ARoamHUD* HUD = UI->GetHUD();
	if (GScreens.IsValid() && GScreens->UI.Get() == UI && GScreens->HUD.Get() == HUD && HUD != nullptr)
	{
		return; // already registered for this HUD
	}
	RoamUnregisterMenuScreens(nullptr);

	UGameInstance* GameInstance = UI->GetGameInstance();
	URoamConsoleSubsystem* Console = GameInstance ? GameInstance->GetSubsystem<URoamConsoleSubsystem>() : nullptr;
	const TWeakObjectPtr<URoamUISubsystem> WeakUI(UI);
	const TWeakObjectPtr<UGameInstance> WeakGI(GameInstance);

	const TSharedRef<FMenuScreens> S = MakeShared<FMenuScreens>();
	S->UI = UI;
	S->HUD = HUD;
	const TSharedRef<FRoamDebugOverlayState> OverlayState = MakeShared<FRoamDebugOverlayState>();

	const auto MakeCloser = [WeakUI](ERoamUIPanel Panel)
	{
		return FSimpleDelegate::CreateLambda([WeakUI, Panel]()
		{
			if (URoamUISubsystem* Pinned = WeakUI.Get())
			{
				Pinned->SetPanelOpen(Panel, false);
			}
		});
	};
	const auto MakeToggler = [WeakUI](ERoamUIPanel Panel)
	{
		return FSimpleDelegate::CreateLambda([WeakUI, Panel]()
		{
			if (URoamUISubsystem* Pinned = WeakUI.Get())
			{
				Pinned->TogglePanel(Panel);
			}
		});
	};

	S->Hint = SNew(SRoamConsoleHint);
	S->Overlay = SNew(SRoamDebugOverlay).GameInstance(WeakGI).State(OverlayState);
	S->Debug = SNew(SRoamDebugMenu).GameInstance(WeakGI).OverlayState(OverlayState);
	S->Garage = SNew(SRoamGarageMenu).GameInstance(WeakGI)
		.OnCloseRequested(MakeCloser(ERoamUIPanel::Garage))
		.OnToggleConsole(MakeToggler(ERoamUIPanel::Console))
		.OnToggleDebug(MakeToggler(ERoamUIPanel::DebugMenu));
	S->Pause = SNew(SRoamPauseMenu).GameInstance(WeakGI).OnCloseRequested(MakeCloser(ERoamUIPanel::PauseMenu));
	S->Console = SNew(SRoamConsole).Console(Console).OnCloseRequested(MakeCloser(ERoamUIPanel::Console));

	S->Hint->SetVisibility(EVisibility::HitTestInvisible);
	S->Overlay->SetVisibility(EVisibility::HitTestInvisible);
	S->Debug->SetVisibility(EVisibility::Collapsed);
	S->Garage->SetVisibility(EVisibility::Collapsed);
	S->Pause->SetVisibility(EVisibility::Collapsed);
	S->Console->SetVisibility(EVisibility::Collapsed);

	UI->AddViewportWidget(S->Overlay.ToSharedRef(), 640);
	UI->AddViewportWidget(S->Hint.ToSharedRef(), 650);
	UI->AddViewportWidget(S->Debug.ToSharedRef(), 700);
	UI->AddViewportWidget(S->Garage.ToSharedRef(), 800);
	UI->AddViewportWidget(S->Pause.ToSharedRef(), 900);
	UI->AddViewportWidget(S->Console.ToSharedRef(), 1000);

	S->PanelHandle = UI->OnPanelChanged.AddStatic(&HandlePanelChanged);
	GScreens = S;

	// Apply the current state (panels opened before the widgets existed).
	for (ERoamUIPanel Panel : TEnumRange<ERoamUIPanel>())
	{
		if (UI->IsPanelOpen(Panel))
		{
			HandlePanelChanged(Panel, true);
		}
	}
	UE_LOG(LogRoamUI, Display, TEXT("ROAM_MENUS_READY console garage debug pause (hud=%s)"), HUD ? *HUD->GetName() : TEXT("<none>"));
}

// ======================================================================================================================
// Console commands owned by the menus
// ======================================================================================================================

static FRoamConsoleAutoRegistrar GRoamMenuCmdRepair(TEXT("repair"), TEXT("repair"), TEXT("Repair the car (damage and visuals)."),
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		Vehicle->Repair();
		return TEXT("car repaired");
	}, TEXT("car"));

static FRoamConsoleAutoRegistrar GRoamMenuCmdGarageTab(TEXT("garage.tab"), TEXT("garage.tab <cars|paint|upgrades>"), TEXT("Switch the garage tab (for automated screenshots; open the garage with `ui garage on`)."),
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		if (!GScreens.IsValid() || !GScreens->Garage.IsValid())
		{
			return Ctx.Fail(TEXT("the menu screens are not created yet (no HUD)"));
		}
		if (!Ctx.HasArg(0) || !GScreens->Garage->SetTabByName(Ctx.Arg(0)))
		{
			return Ctx.Fail(TEXT("usage: garage.tab <cars|paint|upgrades>"));
		}
		return FString::Printf(TEXT("garage tab -> %s"), *Ctx.Arg(0));
	}, TEXT("ui"));

static FRoamConsoleAutoRegistrar GRoamMenuCmdQuit(TEXT("quit"), TEXT("quit"), TEXT("Save the profile and quit the game."),
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		if (Ctx.World)
		{
			UKismetSystemLibrary::QuitGame(Ctx.World, Ctx.PlayerController, EQuitPreference::Quit, false);
		}
		return TEXT("quitting ...");
	}, TEXT("general"));

#undef LOCTEXT_NAMESPACE
