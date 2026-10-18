// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/SRoamGarageMenu.h"

#include "Core/RoamGameInstance.h"
#include "Core/RoamGameMode.h"
#include "Data/RoamCarCatalog.h"
#include "Engine/GameInstance.h"
#include "Framework/Application/SlateApplication.h"
#include "InputCoreTypes.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUISubsystem.h"
#include "Vehicle/RoamVehicle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScaleBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SSpacer.h"
#include "Widgets/Layout/SWidgetSwitcher.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/SOverlay.h"
#include "Widgets/Text/STextBlock.h"

#define LOCTEXT_NAMESPACE "RoamGarage"

namespace
{
	struct FSwatch
	{
		const TCHAR* Name;
		uint8 R;
		uint8 G;
		uint8 B;
	};
	const FSwatch GSwatches[12] =
	{
		{ TEXT("Ember"), 240, 110, 20 }, { TEXT("Signal"), 205, 25, 35 }, { TEXT("Rose"), 235, 100, 160 }, { TEXT("Orchid"), 110, 45, 175 },
		{ TEXT("Cobalt"), 30, 75, 205 }, { TEXT("Lagoon"), 20, 155, 150 }, { TEXT("Pine"), 30, 120, 62 }, { TEXT("Lime"), 130, 220, 40 },
		{ TEXT("Sunburst"), 240, 200, 25 }, { TEXT("Glacier"), 238, 240, 244 }, { TEXT("Graphite"), 62, 66, 74 }, { TEXT("Midnight"), 14, 20, 42 },
	};

	FText CategoryLabel(ERoamUpgradeCategory Category)
	{
		switch (Category)
		{
		case ERoamUpgradeCategory::Conversion: return LOCTEXT("CatConversion", "CONVERSION");
		case ERoamUpgradeCategory::Engine: return LOCTEXT("CatEngine", "ENGINE");
		case ERoamUpgradeCategory::PlatformHandling: return LOCTEXT("CatPlatform", "PLATFORM & HANDLING");
		case ERoamUpgradeCategory::TiresRims: return LOCTEXT("CatTires", "TIRES & RIMS");
		case ERoamUpgradeCategory::AeroAppearance: return LOCTEXT("CatAero", "AERO & APPEARANCE");
		case ERoamUpgradeCategory::Drivetrain: return LOCTEXT("CatDrivetrain", "DRIVETRAIN");
		default: return FText::GetEmpty();
		}
	}

	FLinearColor StatColor(RoamMenus::EStat Stat)
	{
		switch (Stat)
		{
		case RoamMenus::EStat::Speed: return FLinearColor(1.0f, 0.46f, 0.12f, 1.0f);
		case RoamMenus::EStat::Handling: return FLinearColor(0.10f, 0.80f, 0.76f, 1.0f);
		case RoamMenus::EStat::Acceleration: return FLinearColor(1.0f, 0.78f, 0.20f, 1.0f);
		case RoamMenus::EStat::Launch: return FLinearColor(0.93f, 0.42f, 0.62f, 1.0f);
		case RoamMenus::EStat::Braking: return FLinearColor(0.45f, 0.62f, 1.0f, 1.0f);
		default: return FLinearColor(0.62f, 0.86f, 0.32f, 1.0f);
		}
	}
}

// ======================================================================================================================
// Construction
// ======================================================================================================================

void SRoamGarageMenu::Construct(const FArguments& InArgs)
{
	GameInstance = InArgs._GameInstance;
	OnCloseRequested = InArgs._OnCloseRequested;
	OnToggleConsole = InArgs._OnToggleConsole;
	OnToggleDebug = InArgs._OnToggleDebug;
	using namespace RoamMenus;

	const auto TabButton = [this](const FText& Label, ETab ForTab) -> TSharedRef<SWidget>
	{
		return MakeButton(Label, FOnClicked::CreateLambda([this, ForTab]() { SetTab(ForTab); return FReply::Handled(); }),
			TAttribute<FSlateColor>::CreateLambda([this, ForTab]() -> FSlateColor { return Tab == ForTab ? FSlateColor(Style::Orange()) : FSlateColor(Style::GlassLight()); }),
			false, 21);
	};

	ChildSlot
	[
		SNew(SBorder)
		.BorderImage(Style::FlatBrush())
		.BorderBackgroundColor(FLinearColor(0.0f, 0.0f, 0.0f, 0.62f))
		.Padding(0.0f)
		[
			SNew(SScaleBox)
			.Stretch(EStretch::ScaleToFit)
			[
				SNew(SBox).WidthOverride(1640.0f).HeightOverride(940.0f)
				[
					SNew(SBorder)
					.BorderImage(Style::PanelBrush())
					.BorderBackgroundColor(Style::Glass())
					.Padding(FMargin(36.0f, 26.0f))
					[
						SNew(SVerticalBox)
						// ---- header ----
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 16.0f)
						[
							SNew(SHorizontalBox)
							+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.0f, 0.0f, 40.0f, 0.0f)
							[
								MakeSectionTitle(LOCTEXT("GarageTitle", "GARAGE"), 38)
							]
							+ SHorizontalBox::Slot().AutoWidth().Padding(0.0f, 0.0f, 8.0f, 0.0f)[TabButton(LOCTEXT("TabCars", "CARS"), ETab::Cars)]
							+ SHorizontalBox::Slot().AutoWidth().Padding(0.0f, 0.0f, 8.0f, 0.0f)[TabButton(LOCTEXT("TabPaint", "PAINT"), ETab::Paint)]
							+ SHorizontalBox::Slot().AutoWidth().Padding(0.0f, 0.0f, 8.0f, 0.0f)[TabButton(LOCTEXT("TabUpgrades", "UPGRADES"), ETab::Upgrades)]
							+ SHorizontalBox::Slot().FillWidth(1.0f)[SNew(SSpacer)]
							+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
							[
								SNew(STextBlock)
								.Font(Style::Font(20, true))
								.ColorAndOpacity(Style::Dim())
								.Text_Lambda([this]() -> FText
								{
									const URoamCarDefinition* Def = GetCurrentDefinition();
									return FText::Format(LOCTEXT("Driving", "DRIVING  {0}"), Def ? Def->DisplayName : LOCTEXT("PlaceholderCar", "placeholder car"));
								})
							]
						]
						// ---- content ----
						+ SVerticalBox::Slot().FillHeight(1.0f)
						[
							SAssignNew(Switcher, SWidgetSwitcher)
							.WidgetIndex_Lambda([this]() -> int32 { return static_cast<int32>(Tab); })
							+ SWidgetSwitcher::Slot()[BuildCarsTab()]
							+ SWidgetSwitcher::Slot()[BuildPaintTab()]
							+ SWidgetSwitcher::Slot()[BuildUpgradesTab()]
						]
						// ---- footer ----
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 14.0f, 0.0f, 0.0f)
						[
							SNew(SHorizontalBox)
							+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
							[
								SNew(STextBlock)
								.Font(Style::Font(17))
								.ColorAndOpacity(Style::Dim())
								.Text_Lambda([this]() -> FText
								{
									switch (Tab)
									{
									case ETab::Cars: return LOCTEXT("HintCars", "Up/Down browse    Enter or click twice: select    Q/E or LB/RB: tabs    Esc, Tab, F1 or B: close");
									case ETab::Paint: return LOCTEXT("HintPaint", "Mouse, arrows and Enter    Q/E or LB/RB: tabs    Esc, Tab, F1 or B: close");
									default: return LOCTEXT("HintUpgrades", "Mouse, arrows and Enter    Q/E or LB/RB: tabs    Esc, Tab, F1 or B: close");
									}
								})
							]
							+ SHorizontalBox::Slot().AutoWidth()
							[
								SNew(SBox).WidthOverride(200.0f)
								[
									MakeButton(LOCTEXT("Close", "CLOSE"), FOnClicked::CreateLambda([this]() { OnCloseRequested.ExecuteIfBound(); return FReply::Handled(); }),
										FSlateColor(Style::GlassLight()), true, 21)
								]
							]
						]
					]
				]
			]
		]
	];
}

// ======================================================================================================================
// Data
// ======================================================================================================================

ARoamVehicle* SRoamGarageMenu::GetVehicle() const
{
	return ARoamVehicle::GetPlayerVehicle(RoamMenus::GetWorld(GameInstance.Get()));
}

URoamCarDefinition* SRoamGarageMenu::GetCurrentDefinition() const
{
	const ARoamVehicle* Vehicle = GetVehicle();
	return Vehicle ? Vehicle->GetCarDefinition() : nullptr;
}

SRoamGarageMenu::FCarEntry SRoamGarageMenu::MakeEntry(URoamCarDefinition* Definition)
{
	FCarEntry Entry;
	if (!Definition)
	{
		return Entry;
	}
	if (const FCarEntry* Cached = EntryCache.Find(Definition->CarId))
	{
		Entry = *Cached;
	}
	else
	{
		Entry.CarId = Definition->CarId;
		Entry.Performance = Definition->ComputePerformance(FRoamPerformanceRules());
		Entry.Stats = RoamMenus::MakeStatValues(Entry.Performance);
		EntryCache.Add(Definition->CarId, Entry);
	}
	Entry.Definition = Definition;
	Entry.Name = Definition->DisplayName.IsEmpty() ? Definition->CarId.ToString() : Definition->DisplayName.ToString();
	return Entry;
}

bool SRoamGarageMenu::IsCurrent(int32 Index) const
{
	const ARoamVehicle* Vehicle = GetVehicle();
	return Vehicle && Entries.IsValidIndex(Index) && Vehicle->GetCarId() == Entries[Index].CarId;
}

void SRoamGarageMenu::OnOpened()
{
	Tab = ETab::Cars;
	PaintTarget = EPaintTarget::Body;
	RebuildCars();
	RebuildUpgrades();
}

void SRoamGarageMenu::RebuildCars()
{
	Entries.Reset();
	URoamGameInstance* Game = Cast<URoamGameInstance>(GameInstance.Get());
	if (URoamCarCatalog* Catalog = Game ? Game->GetCarCatalog() : nullptr)
	{
		TArray<URoamCarDefinition*> Cars;
		Catalog->LoadAll(Cars);
		for (URoamCarDefinition* Definition : Cars)
		{
			if (Definition)
			{
				Entries.Add(MakeEntry(Definition));
			}
		}
	}
	if (Entries.IsEmpty())
	{
		if (URoamCarDefinition* Definition = GetCurrentDefinition())
		{
			Entries.Add(MakeEntry(Definition));
		}
	}
	PreviewIndex = 0;
	for (int32 i = 0; i < Entries.Num(); ++i)
	{
		if (IsCurrent(i))
		{
			PreviewIndex = i;
		}
	}
	if (CarRows.IsValid())
	{
		CarRows->ClearChildren();
		if (Entries.IsEmpty())
		{
			CarRows->AddSlot().AutoHeight().Padding(8.0f)
			[
				SNew(STextBlock).AutoWrapText(true).Font(RoamMenus::Style::Font(20)).ColorAndOpacity(RoamMenus::Style::Danger())
				.Text(LOCTEXT("NoCatalog", "No cars: the car catalog is empty or not configured (Project Settings > Game > Roamline > Car Catalog)."))
			];
		}
		for (int32 i = 0; i < Entries.Num(); ++i)
		{
			CarRows->AddSlot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 6.0f)[BuildCarRow(i)];
		}
	}
}

void SRoamGarageMenu::SetPreview(int32 Index)
{
	if (Entries.Num() > 0)
	{
		PreviewIndex = (Index % Entries.Num() + Entries.Num()) % Entries.Num();
	}
}

void SRoamGarageMenu::SelectCar(int32 Index)
{
	if (!Entries.IsValidIndex(Index) || IsCurrent(Index))
	{
		return;
	}
	URoamCarDefinition* Definition = Entries[Index].Definition.Get();
	if (!Definition)
	{
		RebuildCars();
		if (!Entries.IsValidIndex(Index) || !(Definition = Entries[Index].Definition.Get()))
		{
			return;
		}
	}
	UWorld* World = RoamMenus::GetWorld(GameInstance.Get());
	if (ARoamGameMode* GameMode = ARoamGameMode::Get(World))
	{
		GameMode->SpawnPlayerCarAtCurrent(Definition->CarId);
	}
	if (URoamUISubsystem* UI = GameInstance.IsValid() ? GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr)
	{
		UI->PushNotification(LOCTEXT("CarSwitchTitle", "CAR SELECTED"), Definition->DisplayName, RoamMenus::Style::Orange());
	}
	RebuildUpgrades();
}

// ======================================================================================================================
// Tabs
// ======================================================================================================================

void SRoamGarageMenu::SetTab(ETab NewTab)
{
	Tab = NewTab;
	if (const TSharedPtr<SWidget> Target = GetFocusWidget())
	{
		FSlateApplication::Get().SetKeyboardFocus(Target, EFocusCause::SetDirectly);
	}
}

bool SRoamGarageMenu::SetTabByName(const FString& Name)
{
	if (Name.Equals(TEXT("cars"), ESearchCase::IgnoreCase)) { SetTab(ETab::Cars); return true; }
	if (Name.Equals(TEXT("paint"), ESearchCase::IgnoreCase)) { SetTab(ETab::Paint); return true; }
	if (Name.Equals(TEXT("upgrades"), ESearchCase::IgnoreCase)) { SetTab(ETab::Upgrades); return true; }
	return false;
}

void SRoamGarageMenu::StepTab(int32 Direction)
{
	SetTab(static_cast<ETab>((static_cast<int32>(Tab) + Direction + 3) % 3));
}

TSharedPtr<SWidget> SRoamGarageMenu::GetFocusWidget() const
{
	if (Tab == ETab::Paint && PaintFocus.IsValid())
	{
		return PaintFocus;
	}
	if (Tab == ETab::Upgrades && UpgradeFocus.IsValid())
	{
		return UpgradeFocus;
	}
	return ConstCastSharedRef<SWidget>(AsShared());
}

FReply SRoamGarageMenu::OnPreviewKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent)
{
	const FKey Key = InKeyEvent.GetKey();
	if (Key == EKeys::Escape || Key == EKeys::F1 || Key == EKeys::Tab || Key == EKeys::Gamepad_FaceButton_Right)
	{
		OnCloseRequested.ExecuteIfBound();
		return FReply::Handled();
	}
	if (Key == EKeys::Tilde)
	{
		OnToggleConsole.ExecuteIfBound();
		return FReply::Handled();
	}
	if (Key == EKeys::F2)
	{
		OnToggleDebug.ExecuteIfBound();
		return FReply::Handled();
	}
	if (Key == EKeys::Q || Key == EKeys::Gamepad_LeftShoulder)
	{
		StepTab(-1);
		return FReply::Handled();
	}
	if (Key == EKeys::E || Key == EKeys::Gamepad_RightShoulder)
	{
		StepTab(1);
		return FReply::Handled();
	}
	if (Tab == ETab::Cars)
	{
		if (Key == EKeys::Up || Key == EKeys::Gamepad_DPad_Up || Key == EKeys::Gamepad_LeftStick_Up)
		{
			SetPreview(PreviewIndex - 1);
			return FReply::Handled();
		}
		if (Key == EKeys::Down || Key == EKeys::Gamepad_DPad_Down || Key == EKeys::Gamepad_LeftStick_Down)
		{
			SetPreview(PreviewIndex + 1);
			return FReply::Handled();
		}
		if (Key == EKeys::Enter || Key == EKeys::SpaceBar || Key == EKeys::Gamepad_FaceButton_Bottom)
		{
			SelectCar(PreviewIndex);
			return FReply::Handled();
		}
	}
	return FReply::Unhandled();
}

TAttribute<FText> SRoamGarageMenu::PreviewText(TFunction<FString(const FCarEntry&, const URoamCarDefinition&)> Fn) const
{
	return TAttribute<FText>::CreateLambda([this, Fn]() -> FText
	{
		const FCarEntry* Entry = GetPreview();
		const URoamCarDefinition* Definition = Entry ? Entry->Definition.Get() : nullptr;
		return (Entry && Definition) ? FText::FromString(Fn(*Entry, *Definition)) : FText::GetEmpty();
	});
}

TSharedRef<SWidget> SRoamGarageMenu::BuildCarRow(int32 Index)
{
	using namespace RoamMenus;
	const FCarEntry& Entry = Entries[Index];
	return SNew(SButton)
		.ButtonStyle(Style::Button())
		.IsFocusable(false)
		.ContentPadding(FMargin(16.0f, 11.0f))
		.ButtonColorAndOpacity_Lambda([this, Index]() -> FSlateColor
		{
			return PreviewIndex == Index ? FSlateColor(FLinearColor(0.95f, 0.40f, 0.08f, 1.0f)) : FSlateColor(Style::GlassLight());
		})
		.OnClicked_Lambda([this, Index]() -> FReply
		{
			if (PreviewIndex == Index)
			{
				SelectCar(Index);
			}
			else
			{
				SetPreview(Index);
			}
			return FReply::Handled();
		})
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(SBox).WidthOverride(40.0f)
				[
					SNew(STextBlock).Text(FText::FromString(FString::Printf(TEXT("%02d"), Index + 1))).Font(Style::Font(18, true)).ColorAndOpacity(Style::Dim())
				]
			]
			+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
			[
				SNew(STextBlock).Text(FText::FromString(Entry.Name)).Font(Style::Font(23, true)).ColorAndOpacity(Style::Chalk())
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.0f, 0.0f, 14.0f, 0.0f)
			[
				SNew(SBorder)
				.BorderImage(Style::PillBrush())
				.BorderBackgroundColor(Style::Teal())
				.Padding(FMargin(9.0f, 2.0f))
				.Visibility_Lambda([this, Index]() { return IsCurrent(Index) ? EVisibility::HitTestInvisible : EVisibility::Collapsed; })
				[
					SNew(STextBlock).Font(Style::Font(14, true)).ColorAndOpacity(FLinearColor(0.02f, 0.05f, 0.06f, 1.0f)).Text(LOCTEXT("DrivingTag", "DRIVING"))
				]
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				MakeClassBadge(Entry.Performance.CarClass, Entry.Performance.PerformanceIndex, 19)
			]
		];
}

TSharedRef<SWidget> SRoamGarageMenu::BuildCarsTab()
{
	using namespace RoamMenus;
	const auto PreviewFloat = [this](EStat Stat) -> TAttribute<float>
	{
		return TAttribute<float>::CreateLambda([this, Stat]() -> float
		{
			const FCarEntry* Entry = GetPreview();
			return Entry ? Entry->Stats[Stat] : 0.0f;
		});
	};

	TSharedRef<SVerticalBox> Stats = SNew(SVerticalBox);
	for (int32 i = 0; i < NumStats; ++i)
	{
		const EStat Stat = static_cast<EStat>(i);
		Stats->AddSlot().AutoHeight().Padding(0.0f, 5.0f)
		[
			MakeStatBar(FText::FromString(StatLabel(Stat)), PreviewFloat(Stat), 0.0f, StatColor(Stat),
				TAttribute<FText>::CreateLambda([this, Stat]() -> FText
				{
					const FCarEntry* Entry = GetPreview();
					return FText::FromString(FString::Printf(TEXT("%.1f"), Entry ? Entry->Stats[Stat] * 10.0f : 0.0f));
				}), 190.0f, 21)
		];
	}

	return SNew(SHorizontalBox)
		// ---- car list ----
		+ SHorizontalBox::Slot().AutoWidth().Padding(0.0f, 0.0f, 28.0f, 0.0f)
		[
			SNew(SBox).WidthOverride(610.0f)
			[
				SNew(SScrollBox)
				.Orientation(Orient_Vertical)
				.ScrollBarVisibility(EVisibility::Collapsed)
				+ SScrollBox::Slot()
				[
					SAssignNew(CarRows, SVerticalBox)
				]
			]
		]
		// ---- details ----
		+ SHorizontalBox::Slot().FillWidth(1.0f)
		[
			SNew(SBorder)
			.BorderImage(Style::PillBrush())
			.BorderBackgroundColor(FLinearColor(0.02f, 0.03f, 0.045f, 0.75f))
			.Padding(FMargin(30.0f, 22.0f))
			[
				SNew(SVerticalBox)
				+ SVerticalBox::Slot().AutoHeight()
				[
					SNew(SHorizontalBox)
					+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
					[
						SNew(STextBlock).Font(Style::Font(40, true)).ColorAndOpacity(Style::Chalk())
						.Text(PreviewText([](const FCarEntry& E, const URoamCarDefinition&) { return E.Name; }))
					]
					+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
					[
						MakeClassBadge(
							TAttribute<ERoamCarClass>::CreateLambda([this]() { const FCarEntry* E = GetPreview(); return E ? E->Performance.CarClass : ERoamCarClass::D; }),
							TAttribute<int32>::CreateLambda([this]() { const FCarEntry* E = GetPreview(); return E ? E->Performance.PerformanceIndex : 100; }), 28)
					]
				]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 4.0f, 0.0f, 10.0f)
				[
					SNew(STextBlock).Font(Style::Font(20)).ColorAndOpacity(Style::Dim())
					.Text(PreviewText([](const FCarEntry&, const URoamCarDefinition& D)
					{
						return FString::Printf(TEXT("%s  -  %d  -  %s"), *D.Maker, D.Year, *D.BodyType.ToString());
					}))
				]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 12.0f)
				[
					SNew(STextBlock).Font(Style::Font(18)).ColorAndOpacity(FLinearColor(0.80f, 0.84f, 0.88f, 1.0f)).AutoWrapText(true)
					.Text(PreviewText([](const FCarEntry&, const URoamCarDefinition& D) { return D.Description.ToString(); }))
				]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 4.0f)
				[
					Stats
				]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 18.0f, 0.0f, 0.0f)
				[
					SNew(SHorizontalBox)
					+ SHorizontalBox::Slot().FillWidth(1.0f)
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 2.0f)
						[
							SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Chalk())
							.Text(PreviewText([](const FCarEntry&, const URoamCarDefinition& D)
							{
								return FString::Printf(TEXT("POWER   %s"), *FormatPower(D.GetPeakPowerKw()));
							}))
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 2.0f)
						[
							SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Chalk())
							.Text(PreviewText([](const FCarEntry&, const URoamCarDefinition& D)
							{
								return FString::Printf(TEXT("TORQUE   %.0f Nm"), D.Engine.GetPeakTorqueNm());
							}))
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 2.0f)
						[
							SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Chalk())
							.Text(PreviewText([](const FCarEntry&, const URoamCarDefinition& D)
							{
								return FString::Printf(TEXT("MASS   %.0f kg   -   %s"), D.MassKg, *DrivetrainLabel(D.Drivetrain.Layout));
							}))
						]
					]
					+ SHorizontalBox::Slot().FillWidth(1.0f)
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 2.0f)
						[
							SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Chalk())
							.Text(PreviewText([](const FCarEntry& E, const URoamCarDefinition&)
							{
								return FString::Printf(TEXT("0-100 km/h   %.1f s"), E.Performance.Time0To100Kmh);
							}))
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 2.0f)
						[
							SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Chalk())
							.Text(PreviewText([](const FCarEntry& E, const URoamCarDefinition&)
							{
								return FString::Printf(TEXT("TOP SPEED   %.0f km/h"), E.Performance.TopSpeedKmh);
							}))
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 2.0f)
						[
							SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Chalk())
							.Text(PreviewText([](const FCarEntry& E, const URoamCarDefinition&)
							{
								return FString::Printf(TEXT("GRIP   %.2f g   -   100-0 in %.0f m"), E.Performance.LateralG, E.Performance.BrakeDistance100M);
							}))
						]
					]
				]
				+ SVerticalBox::Slot().FillHeight(1.0f)[SNew(SSpacer)]
				+ SVerticalBox::Slot().AutoHeight()
				[
					MakeButton(
						TAttribute<FText>::CreateLambda([this]() -> FText { return IsCurrent(PreviewIndex) ? LOCTEXT("Current", "CURRENTLY DRIVING") : LOCTEXT("Select", "SELECT CAR"); }),
						FOnClicked::CreateLambda([this]() { SelectCar(PreviewIndex); return FReply::Handled(); }),
						FSlateColor(FLinearColor(0.95f, 0.40f, 0.08f, 1.0f)), true, 26,
						TAttribute<bool>::CreateLambda([this]() { return Entries.IsValidIndex(PreviewIndex) && !IsCurrent(PreviewIndex); }))
				]
			]
		];
}

// ======================================================================================================================
// Paint
// ======================================================================================================================

FRoamPaint SRoamGarageMenu::GetPaint() const
{
	const ARoamVehicle* Vehicle = GetVehicle();
	return Vehicle ? Vehicle->GetPaint() : FRoamPaint();
}

void SRoamGarageMenu::ApplyPaint(const FRoamPaint& NewPaint)
{
	if (ARoamVehicle* Vehicle = GetVehicle())
	{
		Vehicle->SetPaint(NewPaint);
		if (URoamSaveSubsystem* Save = GameInstance.IsValid() ? GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr)
		{
			Save->SetPaintForCar(Vehicle->GetCarId(), NewPaint);
		}
	}
}

FLinearColor SRoamGarageMenu::GetTargetColor() const
{
	const FRoamPaint Paint = GetPaint();
	switch (PaintTarget)
	{
	case EPaintTarget::Accent: return Paint.Secondary;
	case EPaintTarget::Wheels: return Paint.WheelColor;
	default: return Paint.Primary;
	}
}

void SRoamGarageMenu::SetTargetColor(const FLinearColor& Color)
{
	FRoamPaint Paint = GetPaint();
	switch (PaintTarget)
	{
	case EPaintTarget::Accent: Paint.Secondary = Color; break;
	case EPaintTarget::Wheels: Paint.WheelColor = Color; break;
	default: Paint.Primary = Color; break;
	}
	ApplyPaint(Paint);
}

float SRoamGarageMenu::GetChannel(int32 Channel) const
{
	const FColor Color = GetTargetColor().ToFColor(true);
	return static_cast<float>(Channel == 0 ? Color.R : (Channel == 1 ? Color.G : Color.B)) / 255.0f;
}

void SRoamGarageMenu::SetChannel(int32 Channel, float Value01)
{
	FColor Color = GetTargetColor().ToFColor(true);
	const uint8 Byte = static_cast<uint8>(FMath::Clamp(FMath::RoundToInt(Value01 * 255.0f), 0, 255));
	(Channel == 0 ? Color.R : (Channel == 1 ? Color.G : Color.B)) = Byte;
	SetTargetColor(FLinearColor::FromSRGBColor(Color));
}

TSharedRef<SWidget> SRoamGarageMenu::BuildPaintTab()
{
	using namespace RoamMenus;

	const auto ActiveTint = [](TFunction<bool()> IsActive) -> TAttribute<FSlateColor>
	{
		return TAttribute<FSlateColor>::CreateLambda([IsActive]() -> FSlateColor { return IsActive() ? FSlateColor(Style::Orange()) : FSlateColor(Style::GlassLight()); });
	};
	const auto TargetButton = [this, ActiveTint](const FText& Label, EPaintTarget Target, TSharedPtr<SWidget>* OutButton) -> TSharedRef<SWidget>
	{
		return MakeButton(Label, FOnClicked::CreateLambda([this, Target]() { PaintTarget = Target; return FReply::Handled(); }),
			ActiveTint([this, Target]() { return PaintTarget == Target; }), true, 21, true, OutButton);
	};
	const auto FinishButton = [this, ActiveTint](const FText& Label, ERoamPaintFinish Finish) -> TSharedRef<SWidget>
	{
		return MakeButton(Label, FOnClicked::CreateLambda([this, Finish]() { FRoamPaint P = GetPaint(); P.Finish = Finish; ApplyPaint(P); return FReply::Handled(); }),
			ActiveTint([this, Finish]() { return GetPaint().Finish == Finish; }), true, 21);
	};
	// "<  STYLE n  >" selector for an integer in 0..Max.
	const auto Stepper = [this](const FText& Title, TFunction<int32()> Get, TFunction<void(int32)> Set, int32 Max) -> TSharedRef<SWidget>
	{
		return SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
			[
				SNew(STextBlock).Text(Title).Font(Style::Font(20, true)).ColorAndOpacity(Style::Chalk())
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				SNew(SBox).WidthOverride(64.0f)
				[
					MakeButton(INVTEXT("<"), FOnClicked::CreateLambda([Get, Set, Max]() { Set(FMath::Clamp(Get() - 1, 0, Max)); return FReply::Handled(); }), FSlateColor(Style::GlassLight()), true, 22)
				]
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(8.0f, 0.0f)
			[
				SNew(SBox).WidthOverride(110.0f)
				[
					SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Orange()).Justification(ETextJustify::Center)
					.Text_Lambda([Get]() -> FText { return Get() == 0 ? INVTEXT("STOCK") : FText::FromString(FString::Printf(TEXT("STYLE %d"), Get())); })
				]
			]
			+ SHorizontalBox::Slot().AutoWidth()
			[
				SNew(SBox).WidthOverride(64.0f)
				[
					MakeButton(INVTEXT(">"), FOnClicked::CreateLambda([Get, Set, Max]() { Set(FMath::Clamp(Get() + 1, 0, Max)); return FReply::Handled(); }), FSlateColor(Style::GlassLight()), true, 22)
				]
			];
	};

	// presets: two rows of six
	TSharedRef<SVerticalBox> Presets = SNew(SVerticalBox);
	for (int32 Row = 0; Row < 2; ++Row)
	{
		TSharedRef<SHorizontalBox> RowBox = SNew(SHorizontalBox);
		for (int32 Col = 0; Col < 6; ++Col)
		{
			const FSwatch& Swatch = GSwatches[Row * 6 + Col];
			const FLinearColor Color = FLinearColor::FromSRGBColor(FColor(Swatch.R, Swatch.G, Swatch.B));
			RowBox->AddSlot().AutoWidth().Padding(0.0f, 0.0f, 8.0f, 8.0f)
			[
				SNew(SBox).WidthOverride(92.0f).HeightOverride(58.0f)
				[
					MakeButton(INVTEXT(""), FOnClicked::CreateLambda([this, Color]() { SetTargetColor(Color); return FReply::Handled(); }), FSlateColor(Color), true, 12)
				]
			];
		}
		Presets->AddSlot().AutoHeight()[RowBox];
	}

	// RGB sliders
	TSharedRef<SVerticalBox> Sliders = SNew(SVerticalBox);
	static const TCHAR* ChannelNames[3] = { TEXT("R"), TEXT("G"), TEXT("B") };
	static const FLinearColor ChannelColors[3] = { FLinearColor(1.0f, 0.35f, 0.30f, 1.0f), FLinearColor(0.35f, 0.9f, 0.45f, 1.0f), FLinearColor(0.40f, 0.60f, 1.0f, 1.0f) };
	for (int32 Channel = 0; Channel < 3; ++Channel)
	{
		Sliders->AddSlot().AutoHeight().Padding(0.0f, 7.0f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(SBox).WidthOverride(36.0f)
				[
					SNew(STextBlock).Text(FText::FromString(ChannelNames[Channel])).Font(Style::Font(22, true)).ColorAndOpacity(ChannelColors[Channel])
				]
			]
			+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
			[
				SNew(SSlider)
				.Style(Style::Slider())
				.StepSize(0.01f)
				.SliderBarColor(FLinearColor::White)
				.SliderHandleColor(ChannelColors[Channel])
				.Value_Lambda([this, Channel]() { return GetChannel(Channel); })
				.OnValueChanged_Lambda([this, Channel](float Value) { SetChannel(Channel, Value); })
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(SBox).WidthOverride(64.0f)
				[
					SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Chalk()).Justification(ETextJustify::Right)
					.Text_Lambda([this, Channel]() { return FText::AsNumber(FMath::RoundToInt(GetChannel(Channel) * 255.0f)); })
				]
			]
		];
	}

	return SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 36.0f, 0.0f)
		[
			SNew(SVerticalBox)
			+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 4.0f, 0.0f, 10.0f)[MakeSectionTitle(LOCTEXT("PaintTarget", "PAINT TARGET"), 22)]
			+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 22.0f)
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth().Padding(0.0f, 0.0f, 10.0f, 0.0f)[SNew(SBox).WidthOverride(190.0f)[TargetButton(LOCTEXT("TBody", "BODY"), EPaintTarget::Body, &PaintFocus)]]
				+ SHorizontalBox::Slot().AutoWidth().Padding(0.0f, 0.0f, 10.0f, 0.0f)[SNew(SBox).WidthOverride(190.0f)[TargetButton(LOCTEXT("TAccent", "ACCENT"), EPaintTarget::Accent, nullptr)]]
				+ SHorizontalBox::Slot().AutoWidth()[SNew(SBox).WidthOverride(190.0f)[TargetButton(LOCTEXT("TWheels", "WHEELS"), EPaintTarget::Wheels, nullptr)]]
			]
			+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 10.0f)[MakeSectionTitle(LOCTEXT("Presets", "PRESETS"), 22)]
			+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 18.0f)[Presets]
			+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 6.0f)[MakeSectionTitle(LOCTEXT("Custom", "CUSTOM COLOUR"), 22)]
			+ SVerticalBox::Slot().AutoHeight()[Sliders]
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			SNew(SBox).WidthOverride(560.0f)
			[
				SNew(SVerticalBox)
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 4.0f, 0.0f, 10.0f)[MakeSectionTitle(LOCTEXT("Preview", "COLOUR"), 22)]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 22.0f)
				[
					SNew(SBox).HeightOverride(96.0f)
					[
						SNew(SBorder)
						.BorderImage(Style::PillBrush())
						.BorderBackgroundColor_Lambda([this]() -> FSlateColor { return FSlateColor(GetTargetColor()); })
					]
				]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 10.0f)[MakeSectionTitle(LOCTEXT("Finish", "FINISH"), 22)]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 22.0f)
				[
					SNew(SHorizontalBox)
					+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 8.0f, 0.0f)[FinishButton(LOCTEXT("Gloss", "GLOSS"), ERoamPaintFinish::Gloss)]
					+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 8.0f, 0.0f)[FinishButton(LOCTEXT("Matte", "MATTE"), ERoamPaintFinish::Matte)]
					+ SHorizontalBox::Slot().FillWidth(1.0f)[FinishButton(LOCTEXT("Metallic", "METALLIC"), ERoamPaintFinish::Metallic)]
				]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 10.0f)[MakeSectionTitle(LOCTEXT("Styles", "STYLES"), 22)]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 4.0f)
				[
					Stepper(LOCTEXT("Stripes", "STRIPES"), [this]() { return GetPaint().StripeStyle; },
						[this](int32 V) { FRoamPaint P = GetPaint(); P.StripeStyle = V; ApplyPaint(P); }, 5)
				]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 4.0f)
				[
					Stepper(LOCTEXT("WheelStyle", "WHEEL STYLE"), [this]() { return GetPaint().WheelStyle; },
						[this](int32 V) { FRoamPaint P = GetPaint(); P.WheelStyle = V; ApplyPaint(P); }, 5)
				]
				+ SVerticalBox::Slot().FillHeight(1.0f)[SNew(SSpacer)]
				+ SVerticalBox::Slot().AutoHeight()
				[
					SNew(STextBlock).AutoWrapText(true).Font(Style::Font(16)).ColorAndOpacity(Style::Dim())
					.Text(LOCTEXT("PaintNote", "Paint applies to the car you are driving and is saved per car. Stripe and wheel styles depend on what the car's visuals provide."))
				]
			]
		];
}

// ======================================================================================================================
// Upgrades
// ======================================================================================================================

int32 SRoamGarageMenu::GetTier(FName SlotId) const
{
	const URoamSaveSubsystem* Save = GameInstance.IsValid() ? GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
	if (!Save)
	{
		return 0;
	}
	const int32* Tier = Save->GetProfile().Upgrades.Find(SlotId);
	return Tier ? *Tier : 0;
}

RoamMenus::FStatValues SRoamGarageMenu::GetUpgradeDelta() const
{
	const URoamSaveSubsystem* Save = GameInstance.IsValid() ? GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
	return Save ? RoamMenus::TotalUpgradeDelta(Slots, Save->GetProfile().Upgrades) : RoamMenus::FStatValues();
}

int32 SRoamGarageMenu::EstimatePerformanceIndex() const
{
	const FRoamPerformanceRules Rules;
	const RoamMenus::FStatValues Delta = GetUpgradeDelta();
	const float Weights[RoamMenus::NumStats] = { Rules.WeightSpeed, Rules.WeightHandling, Rules.WeightAcceleration, Rules.WeightLaunch, Rules.WeightBraking, Rules.WeightOffroad };
	float Score = CurrentScore;
	for (int32 i = 0; i < RoamMenus::NumStats; ++i)
	{
		Score += Weights[i] * Delta.V[i];
	}
	return FMath::RoundToInt(100.0f + 899.0f * FMath::Pow(FMath::Clamp(Score, 0.0f, 1.0f), Rules.Gamma));
}

void SRoamGarageMenu::ChangeTier(int32 SlotIndex, int32 Delta)
{
	URoamSaveSubsystem* Save = GameInstance.IsValid() ? GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
	if (!Save || !Slots.IsValidIndex(SlotIndex))
	{
		return;
	}
	const FRoamUpgradeSlot& Slot = Slots[SlotIndex];
	int32& Tier = Save->GetProfile().Upgrades.FindOrAdd(Slot.SlotId);
	Tier = FMath::Clamp(Tier + Delta, 0, FMath::Max(0, Slot.MaxTier));
	Save->MarkDirty();
	if (ARoamVehicle* Vehicle = GetVehicle())
	{
		Vehicle->SetUpgrades(Save->GetProfile().Upgrades);
	}
}

void SRoamGarageMenu::RebuildUpgrades()
{
	using namespace RoamMenus;
	URoamCarDefinition* Definition = GetCurrentDefinition();
	Slots.Reset();
	bDefaultSlots = false;
	if (Definition)
	{
		Slots = Definition->UpgradeSlots;
		const FCarEntry Entry = MakeEntry(Definition);
		CurrentBase = Entry.Stats;
		CurrentScore = Entry.Performance.Score;
	}
	else
	{
		CurrentBase = FStatValues();
		CurrentScore = 0.0f;
	}
	if (Slots.IsEmpty())
	{
		BuildDefaultUpgradeSlots(Slots);
		bDefaultSlots = true;
	}
	if (!UpgradeRows.IsValid())
	{
		return;
	}
	UpgradeRows->ClearChildren();
	UpgradeFocus.Reset();
	for (int32 SlotIndex = 0; SlotIndex < Slots.Num(); ++SlotIndex)
	{
		const FRoamUpgradeSlot Slot = Slots[SlotIndex];
		TSharedPtr<SWidget> PlusButton;
		TSharedRef<SHorizontalBox> Pips = SNew(SHorizontalBox);
		for (int32 Pip = 1; Pip <= FMath::Max(1, Slot.MaxTier); ++Pip)
		{
			Pips->AddSlot().AutoWidth().Padding(0.0f, 0.0f, 6.0f, 0.0f)
			[
				SNew(SBox).WidthOverride(34.0f).HeightOverride(14.0f)
				[
					SNew(SBorder)
					.BorderImage(Style::PillBrush())
					.BorderBackgroundColor_Lambda([this, Slot, Pip]() -> FSlateColor
					{
						return GetTier(Slot.SlotId) >= Pip ? FSlateColor(Style::Orange()) : FSlateColor(FLinearColor(0.2f, 0.23f, 0.29f, 1.0f));
					})
				]
			];
		}
		UpgradeRows->AddSlot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 7.0f)
		[
			SNew(SBorder)
			.BorderImage(Style::PillBrush())
			.BorderBackgroundColor(Style::GlassLight())
			.Padding(FMargin(18.0f, 9.0f))
			[
				SNew(SHorizontalBox)
				+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
				[
					SNew(SBox).WidthOverride(330.0f)
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight()[SNew(STextBlock).Text(CategoryLabel(Slot.Category)).Font(Style::Font(21, true)).ColorAndOpacity(Style::Chalk())]
						+ SVerticalBox::Slot().AutoHeight()[SNew(STextBlock).Text(FText::FromName(Slot.SlotId)).Font(Style::Font(14)).ColorAndOpacity(Style::Dim())]
					]
				]
				+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.0f, 0.0f, 20.0f, 0.0f)[Pips]
				+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
				[
					SNew(STextBlock).Font(Style::Font(15)).ColorAndOpacity(Style::Teal()).AutoWrapText(true)
					.Text_Lambda([this, Slot]() -> FText
					{
						const int32 Tier = GetTier(Slot.SlotId);
						if (Tier >= Slot.MaxTier)
						{
							return LOCTEXT("MaxTier", "MAX TIER INSTALLED");
						}
						FStatValues Next = UpgradeDelta(Slot.Category, Tier + 1);
						const FStatValues Now = UpgradeDelta(Slot.Category, Tier);
						for (int32 i = 0; i < NumStats; ++i) { Next.V[i] -= Now.V[i]; }
						const int32 Price = Slot.TierPriceCredits.IsValidIndex(Tier) ? Slot.TierPriceCredits[Tier] : 0;
						return FText::FromString(FString::Printf(TEXT("next: %s  (%d cr)"), *FormatDelta(Next), Price));
					})
				]
				+ SHorizontalBox::Slot().AutoWidth().Padding(0.0f, 0.0f, 8.0f, 0.0f)
				[
					SNew(SBox).WidthOverride(70.0f)
					[
						MakeButton(INVTEXT("-"), FOnClicked::CreateLambda([this, SlotIndex]() { ChangeTier(SlotIndex, -1); return FReply::Handled(); }),
							FSlateColor(FLinearColor(0.2f, 0.23f, 0.3f, 1.0f)), true, 24,
							TAttribute<bool>::CreateLambda([this, Slot]() { return GetTier(Slot.SlotId) > 0; }))
					]
				]
				+ SHorizontalBox::Slot().AutoWidth()
				[
					SNew(SBox).WidthOverride(70.0f)
					[
						MakeButton(INVTEXT("+"), FOnClicked::CreateLambda([this, SlotIndex]() { ChangeTier(SlotIndex, 1); return FReply::Handled(); }),
							FSlateColor(Style::Teal()), true, 24,
							TAttribute<bool>::CreateLambda([this, Slot]() { return GetTier(Slot.SlotId) < Slot.MaxTier; }), &PlusButton)
					]
				]
			]
		];
		if (!UpgradeFocus.IsValid())
		{
			UpgradeFocus = PlusButton;
		}
	}
}

TSharedRef<SWidget> SRoamGarageMenu::BuildUpgradesTab()
{
	using namespace RoamMenus;
	TSharedRef<SVerticalBox> Bars = SNew(SVerticalBox);
	for (int32 i = 0; i < NumStats; ++i)
	{
		const EStat Stat = static_cast<EStat>(i);
		Bars->AddSlot().AutoHeight().Padding(0.0f, 5.0f)
		[
			MakeStatBar(FText::FromString(StatLabel(Stat)),
				TAttribute<float>::CreateLambda([this, Stat]() { return CurrentBase[Stat]; }),
				TAttribute<float>::CreateLambda([this, Stat]() { return GetUpgradeDelta()[Stat]; }),
				StatColor(Stat),
				TAttribute<FText>::CreateLambda([this, Stat]() -> FText
				{
					const float Value = ApplyDelta(CurrentBase, GetUpgradeDelta())[Stat];
					return FText::FromString(FString::Printf(TEXT("%.1f"), Value * 10.0f));
				}), 190.0f, 21)
		];
	}

	return SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 32.0f, 0.0f)
		[
			SNew(SVerticalBox)
			+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 2.0f, 0.0f, 12.0f)[MakeSectionTitle(LOCTEXT("UpgradeSlots", "UPGRADE SLOTS"), 22)]
			+ SVerticalBox::Slot().FillHeight(1.0f)
			[
				SNew(SScrollBox)
				.Orientation(Orient_Vertical)
				.ScrollBarVisibility(EVisibility::Collapsed)
				+ SScrollBox::Slot()
				[
					SAssignNew(UpgradeRows, SVerticalBox)
				]
			]
		]
		+ SHorizontalBox::Slot().AutoWidth()
		[
			SNew(SBox).WidthOverride(520.0f)
			[
				SNew(SVerticalBox)
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 2.0f, 0.0f, 12.0f)[MakeSectionTitle(LOCTEXT("Result", "RESULT"), 22)]
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 10.0f)
				[
					SNew(STextBlock).Font(Style::Font(28, true)).ColorAndOpacity(Style::Chalk())
					.Text_Lambda([this]() -> FText
					{
						const URoamCarDefinition* Definition = GetCurrentDefinition();
						const int32 Base = Definition ? Definition->GetPerformanceIndex() : 100;
						return FText::FromString(FString::Printf(TEXT("PI  %d  >  %d"), Base, EstimatePerformanceIndex()));
					})
				]
				+ SVerticalBox::Slot().AutoHeight()[Bars]
				+ SVerticalBox::Slot().FillHeight(1.0f)[SNew(SSpacer)]
				+ SVerticalBox::Slot().AutoHeight()
				[
					SNew(STextBlock).AutoWrapText(true).Font(Style::Font(16)).ColorAndOpacity(Style::Dim())
					.Text(LOCTEXT("UpgradeNote",
						"Tiers are saved in your profile and handed to the vehicle. The stat deltas are a data-only preview: the physics model applies them "
						"once its upgrade hook is implemented. Credits are not charged yet."))
				]
			]
		];
}

#undef LOCTEXT_NAMESPACE
