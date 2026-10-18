// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/SRoamDebugMenu.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamGameInstance.h"
#include "Data/RoamCarCatalog.h"
#include "Data/RoamCarDefinition.h"
#include "Data/RoamWorldDefinition.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "Save/RoamSaveSubsystem.h"
#include "Traffic/RoamTrafficSubsystem.h"
#include "Vehicle/RoamVehicle.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SWrapBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Text/STextBlock.h"
#include "World/RoamTimeWeatherSubsystem.h"

#define LOCTEXT_NAMESPACE "RoamDebugMenu"

namespace
{
	URoamTimeWeatherSubsystem* GetTimeWeather(const UGameInstance* GI)
	{
		UWorld* World = RoamMenus::GetWorld(GI);
		return World ? World->GetSubsystem<URoamTimeWeatherSubsystem>() : nullptr;
	}

	URoamTrafficSubsystem* GetTraffic(const UGameInstance* GI)
	{
		UWorld* World = RoamMenus::GetWorld(GI);
		return World ? World->GetSubsystem<URoamTrafficSubsystem>() : nullptr;
	}

	bool UseMph(const UGameInstance* GI)
	{
		const URoamSaveSubsystem* Save = GI ? GI->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		return Save && Save->GetSettings().bUseMph;
	}
}

// ======================================================================================================================
// SRoamDebugOverlay
// ======================================================================================================================

void SRoamDebugOverlay::Construct(const FArguments& InArgs)
{
	GameInstance = InArgs._GameInstance;
	State = InArgs._State.IsValid() ? InArgs._State : MakeShared<FRoamDebugOverlayState>();
	using namespace RoamMenus;

	ChildSlot
	.HAlign(HAlign_Right)
	.VAlign(VAlign_Top)
	.Padding(0.0f, 24.0f, 28.0f, 0.0f)
	[
		SNew(SBorder)
		.BorderImage(Style::PillBrush())
		.BorderBackgroundColor(FLinearColor(0.03f, 0.04f, 0.06f, 0.72f))
		.Padding(FMargin(18.0f, 10.0f))
		.Visibility_Lambda([this]() -> EVisibility
		{
			return (State->bFps || State->bCoordinates || State->bSpeed) ? EVisibility::HitTestInvisible : EVisibility::Collapsed;
		})
		[
			SNew(SVerticalBox)
			+ SVerticalBox::Slot().AutoHeight()
			[
				SNew(STextBlock).Font(Style::Font(40, true)).ColorAndOpacity(Style::Orange()).Justification(ETextJustify::Right)
				.Visibility_Lambda([this]() { return State->bSpeed ? EVisibility::Visible : EVisibility::Collapsed; })
				.Text_Lambda([this]() -> FText
				{
					const ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(GetWorld(GameInstance.Get()));
					return FText::FromString(FormatSpeed(Vehicle ? Vehicle->GetTelemetry().SpeedKmh : 0.0f, UseMph(GameInstance.Get())));
				})
			]
			+ SVerticalBox::Slot().AutoHeight()
			[
				SNew(STextBlock).Font(Style::Font(22, true)).ColorAndOpacity(Style::Chalk()).Justification(ETextJustify::Right)
				.Visibility_Lambda([this]() { return State->bFps ? EVisibility::Visible : EVisibility::Collapsed; })
				.Text_Lambda([this]() -> FText
				{
					return FText::FromString(FString::Printf(TEXT("%.0f FPS   %.1f ms"), SmoothedFps, 1000.0f / FMath::Max(SmoothedFps, 1.0f)));
				})
			]
			+ SVerticalBox::Slot().AutoHeight()
			[
				SNew(STextBlock).Font(Style::Font(20)).ColorAndOpacity(Style::Dim()).Justification(ETextJustify::Right)
				.Visibility_Lambda([this]() { return State->bCoordinates ? EVisibility::Visible : EVisibility::Collapsed; })
				.Text_Lambda([this]() -> FText
				{
					const ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(GetWorld(GameInstance.Get()));
					const FVector P = Vehicle ? Vehicle->GetActorLocation() : FVector::ZeroVector;
					return FText::FromString(FString::Printf(TEXT("X %.0f   Y %.0f   Z %.0f  m"), P.X / 100.0, P.Y / 100.0, P.Z / 100.0));
				})
			]
		]
	];
}

void SRoamDebugOverlay::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SCompoundWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	if (InDeltaTime > 0.0001f)
	{
		SmoothedFps = FMath::Lerp(SmoothedFps, 1.0f / InDeltaTime, 0.08f);
	}
}

// ======================================================================================================================
// SRoamDebugMenu
// ======================================================================================================================

ARoamVehicle* SRoamDebugMenu::GetVehicle() const
{
	return ARoamVehicle::GetPlayerVehicle(RoamMenus::GetWorld(GameInstance.Get()));
}

void SRoamDebugMenu::Exec(const FString& CommandLine) const
{
	if (URoamConsoleSubsystem* Console = GameInstance.IsValid() ? GameInstance->GetSubsystem<URoamConsoleSubsystem>() : nullptr)
	{
		Console->Execute(CommandLine);
	}
}

TSharedRef<SWidget> SRoamDebugMenu::MakeToggle(const FText& Label, TFunction<bool()> IsOn, TFunction<void()> Toggle) const
{
	using namespace RoamMenus;
	return MakeButton(
		TAttribute<FText>::CreateLambda([Label, IsOn]() -> FText { return FText::Format(INVTEXT("{0}  {1}"), Label, IsOn() ? INVTEXT("ON") : INVTEXT("OFF")); }),
		FOnClicked::CreateLambda([Toggle]() { Toggle(); return FReply::Handled(); }),
		TAttribute<FSlateColor>::CreateLambda([IsOn]() -> FSlateColor
		{
			return IsOn() ? FSlateColor(FLinearColor(0.05f, 0.55f, 0.52f, 1.0f)) : FSlateColor(Style::GlassLight());
		}),
		false, 17);
}

TSharedRef<SWidget> SRoamDebugMenu::MakeActionButton(const FText& Label, TFunction<void()> Action, const FSlateColor& Tint) const
{
	return RoamMenus::MakeButton(Label, FOnClicked::CreateLambda([Action]() { Action(); return FReply::Handled(); }), Tint, false, 17);
}

TSharedRef<SWidget> SRoamDebugMenu::MakeSection(const FText& Title, const TSharedRef<SWidget>& Content) const
{
	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 14.0f, 0.0f, 8.0f)[RoamMenus::MakeSectionTitle(Title, 19)]
		+ SVerticalBox::Slot().AutoHeight()[Content];
}

TSharedRef<SWidget> SRoamDebugMenu::MakeTelemetry() const
{
	using namespace RoamMenus;
	const auto Telemetry = [this]() -> FRoamVehicleTelemetry
	{
		const ARoamVehicle* Vehicle = GetVehicle();
		return Vehicle ? Vehicle->GetTelemetry() : FRoamVehicleTelemetry();
	};
	const auto Row = [](TAttribute<FText> Text) -> TSharedRef<SWidget>
	{
		return SNew(STextBlock).Text(Text).Font(Style::Font(17, true)).ColorAndOpacity(Style::Chalk());
	};

	TSharedRef<SVerticalBox> Box = SNew(SVerticalBox);
	Box->AddSlot().AutoHeight().Padding(0.0f, 2.0f)
	[
		Row(TAttribute<FText>::CreateLambda([this, Telemetry]() -> FText
		{
			const FRoamVehicleTelemetry T = Telemetry();
			const FString Gear = T.Gear < 0 ? TEXT("R") : (T.Gear == 0 ? TEXT("N") : FString::FromInt(T.Gear));
			return FText::FromString(FString::Printf(TEXT("RPM %5.0f    GEAR %s    %s"), T.RPM, *Gear, *FormatSpeed(T.SpeedKmh, UseMph(GameInstance.Get()))));
		}))
	];
	Box->AddSlot().AutoHeight().Padding(0.0f, 2.0f)
	[
		Row(TAttribute<FText>::CreateLambda([Telemetry]() -> FText
		{
			const FRoamVehicleTelemetry T = Telemetry();
			return FText::FromString(FString::Printf(TEXT("SURFACE %s    WET %.2f    %s"), *Roam::EnumToString(T.Surface), T.SurfaceWetness, T.bAirborne ? TEXT("AIRBORNE") : TEXT("grounded")));
		}))
	];
	Box->AddSlot().AutoHeight().Padding(0.0f, 2.0f)
	[
		Row(TAttribute<FText>::CreateLambda([Telemetry]() -> FText
		{
			const FRoamVehicleTelemetry T = Telemetry();
			return FText::FromString(FString::Printf(TEXT("G   long %+.2f    lat %+.2f    vert %.2f"), T.LongG, T.LatG, T.VertG));
		}))
	];
	Box->AddSlot().AutoHeight().Padding(0.0f, 2.0f)
	[
		Row(TAttribute<FText>::CreateLambda([Telemetry]() -> FText
		{
			const FRoamVehicleTelemetry T = Telemetry();
			return FText::FromString(FString::Printf(TEXT("ASSISTS   TCS %s   STM %s   ABS %s   boost %.2f"), T.bTCSActive ? TEXT("*") : TEXT("-"),
				T.bSTMActive ? TEXT("*") : TEXT("-"), T.bABSActive ? TEXT("*") : TEXT("-"), T.Boost01));
		}))
	];
	static const TCHAR* WheelNames[4] = { TEXT("FL"), TEXT("FR"), TEXT("RL"), TEXT("RR") };
	Box->AddSlot().AutoHeight().Padding(0.0f, 8.0f, 0.0f, 2.0f)
	[
		SNew(STextBlock).Text(LOCTEXT("SlipTitle", "WHEEL SLIP  (ratio, angle)")).Font(Style::Font(15, true)).ColorAndOpacity(Style::Dim())
	];
	for (int32 Wheel = 0; Wheel < 4; ++Wheel)
	{
		Box->AddSlot().AutoHeight().Padding(0.0f, 2.0f)
		[
			MakeStatBar(FText::FromString(WheelNames[Wheel]),
				TAttribute<float>::CreateLambda([Telemetry, Wheel]() { return FMath::Clamp(FMath::Abs(Telemetry().WheelSlipRatio[Wheel]), 0.0f, 1.0f); }), 0.0f,
				Style::Orange(),
				TAttribute<FText>::CreateLambda([Telemetry, Wheel]() -> FText
				{
					const FRoamVehicleTelemetry T = Telemetry();
					return FText::FromString(FString::Printf(TEXT("%+.2f %+.0f"), T.WheelSlipRatio[Wheel], T.WheelSlipAngleDeg[Wheel]));
				}), 44.0f, 17)
		];
	}
	return Box;
}

void SRoamDebugMenu::Construct(const FArguments& InArgs)
{
	GameInstance = InArgs._GameInstance;
	OverlayState = InArgs._OverlayState.IsValid() ? InArgs._OverlayState : MakeShared<FRoamDebugOverlayState>();
	using namespace RoamMenus;

	// ---- time & weather ----
	TSharedRef<SVerticalBox> TimeWeather = SNew(SVerticalBox);
	TimeWeather->AddSlot().AutoHeight().Padding(0.0f, 2.0f)
	[
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
		[
			SNew(SBox).WidthOverride(110.0f)
			[
				SNew(STextBlock).Font(Style::Font(19, true)).ColorAndOpacity(Style::Orange())
				.Text_Lambda([this]() -> FText
				{
					const URoamTimeWeatherSubsystem* TW = GetTimeWeather(GameInstance.Get());
					return FText::FromString(FormatClockHour(TW ? TW->GetGameHour() : 0.0f));
				})
			]
		]
		+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
		[
			SNew(SSlider)
			.Style(Style::Slider())
			.IsFocusable(false)
			.StepSize(1.0f / 96.0f)
			.SliderBarColor(FLinearColor::White)
			.SliderHandleColor(Style::Orange())
			.Value_Lambda([this]() -> float
			{
				const URoamTimeWeatherSubsystem* TW = GetTimeWeather(GameInstance.Get());
				return TW ? FMath::Clamp(TW->GetGameHour() / 24.0f, 0.0f, 1.0f) : 0.0f;
			})
			.OnValueChanged_Lambda([this](float Value)
			{
				if (URoamTimeWeatherSubsystem* TW = GetTimeWeather(GameInstance.Get()))
				{
					TW->SetGameHour(Value * 24.0f);
				}
			})
		]
	];
	{
		TSharedRef<SHorizontalBox> Quick = SNew(SHorizontalBox);
		struct FQuick { const TCHAR* Label; float Hour; };
		static const FQuick Presets[4] = { { TEXT("DAWN"), 6.0f }, { TEXT("NOON"), 12.0f }, { TEXT("SUNSET"), 18.5f }, { TEXT("NIGHT"), 23.0f } };
		for (const FQuick& Preset : Presets)
		{
			const float Hour = Preset.Hour;
			Quick->AddSlot().FillWidth(1.0f).Padding(0.0f, 0.0f, 6.0f, 0.0f)
			[
				MakeActionButton(FText::FromString(Preset.Label), [this, Hour]()
				{
					if (URoamTimeWeatherSubsystem* TW = GetTimeWeather(GameInstance.Get())) { TW->SetGameHour(Hour); }
				}, FSlateColor(Style::GlassLight()))
			];
		}
		TimeWeather->AddSlot().AutoHeight().Padding(0.0f, 6.0f)[Quick];
	}
	{
		TSharedRef<SHorizontalBox> Weathers = SNew(SHorizontalBox);
		for (ERoamWeather Weather : TEnumRange<ERoamWeather>())
		{
			Weathers->AddSlot().FillWidth(1.0f).Padding(0.0f, 0.0f, 6.0f, 0.0f)
			[
				MakeButton(FText::FromString(Roam::EnumToString(Weather).ToUpper()),
					FOnClicked::CreateLambda([this, Weather]()
					{
						if (URoamTimeWeatherSubsystem* TW = GetTimeWeather(GameInstance.Get())) { TW->SetWeather(Weather, 6.0f); }
						return FReply::Handled();
					}),
					TAttribute<FSlateColor>::CreateLambda([this, Weather]() -> FSlateColor
					{
						const URoamTimeWeatherSubsystem* TW = GetTimeWeather(GameInstance.Get());
						return (TW && TW->GetWeather() == Weather) ? FSlateColor(FLinearColor(0.05f, 0.55f, 0.52f, 1.0f)) : FSlateColor(Style::GlassLight());
					}),
					false, 14)
			];
		}
		TimeWeather->AddSlot().AutoHeight().Padding(0.0f, 2.0f)[Weathers];
	}

	// ---- traffic ----
	const TSharedRef<SWidget> Traffic =
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
		[
			SNew(SBox).WidthOverride(110.0f)
			[
				SNew(STextBlock).Font(Style::Font(19, true)).ColorAndOpacity(Style::Orange())
				.Text_Lambda([this]() -> FText
				{
					const URoamTrafficSubsystem* T = GetTraffic(GameInstance.Get());
					return FText::FromString(FString::Printf(TEXT("%.0f %%"), (T ? T->GetDensity() : 0.0f) * 100.0f));
				})
			]
		]
		+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
		[
			SNew(SSlider)
			.Style(Style::Slider())
			.IsFocusable(false)
			.StepSize(0.05f)
			.SliderBarColor(FLinearColor::White)
			.SliderHandleColor(Style::Orange())
			.Value_Lambda([this]() -> float
			{
				const URoamTrafficSubsystem* T = GetTraffic(GameInstance.Get());
				return T ? T->GetDensity() : 0.0f;
			})
			.OnValueChanged_Lambda([this](float Value)
			{
				if (URoamTrafficSubsystem* T = GetTraffic(GameInstance.Get())) { T->SetDensity(Value); }
			})
		];

	// ---- assists ----
	TSharedRef<SWrapBox> Assists = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(6.0f, 6.0f));
	for (ERoamAssist Assist : TEnumRange<ERoamAssist>())
	{
		Assists->AddSlot()
		[
			SNew(SBox).WidthOverride(158.0f)
			[
				MakeToggle(FText::FromString(Roam::AssistToShortName(Assist)),
					[this, Assist]() { const ARoamVehicle* V = GetVehicle(); return V && V->GetAssists().Get(Assist); },
					[this, Assist]() { if (ARoamVehicle* V = GetVehicle()) { V->SetAssist(Assist, !V->GetAssists().Get(Assist)); } })
			]
		];
	}

	// ---- overlays ----
	const TSharedRef<FRoamDebugOverlayState> Overlay = OverlayState.ToSharedRef();
	const TSharedRef<SWidget> Overlays =
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 6.0f, 0.0f)[MakeToggle(LOCTEXT("OvFps", "FPS"), [Overlay]() { return Overlay->bFps; }, [Overlay]() { Overlay->bFps = !Overlay->bFps; })]
		+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 6.0f, 0.0f)[MakeToggle(LOCTEXT("OvXyz", "XYZ"), [Overlay]() { return Overlay->bCoordinates; }, [Overlay]() { Overlay->bCoordinates = !Overlay->bCoordinates; })]
		+ SHorizontalBox::Slot().FillWidth(1.0f)[MakeToggle(LOCTEXT("OvSpeed", "SPEED"), [Overlay]() { return Overlay->bSpeed; }, [Overlay]() { Overlay->bSpeed = !Overlay->bSpeed; })];

	// ---- car tools ----
	const TSharedRef<SWidget> Tools =
		SNew(SHorizontalBox)
		+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 6.0f, 0.0f)
		[
			MakeActionButton(LOCTEXT("Repair", "REPAIR"), [this]() { if (ARoamVehicle* V = GetVehicle()) { V->Repair(); } }, FSlateColor(FLinearColor(0.10f, 0.50f, 0.28f, 1.0f)))
		]
		+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 6.0f, 0.0f)
		[
			MakeActionButton(LOCTEXT("Flip", "FLIP UPRIGHT"), [this]() { if (ARoamVehicle* V = GetVehicle()) { V->FlipUpright(); } }, FSlateColor(Style::GlassLight()))
		]
		+ SHorizontalBox::Slot().FillWidth(1.0f)
		[
			MakeActionButton(LOCTEXT("ResetRoad", "RESET TO ROAD"), [this]() { if (ARoamVehicle* V = GetVehicle()) { V->ResetToRoad(); } }, FSlateColor(Style::GlassLight()))
		];

	ChildSlot
	.HAlign(HAlign_Left)
	.VAlign(VAlign_Fill)
	.Padding(22.0f)
	[
		SNew(SBox).WidthOverride(580.0f)
		[
			SNew(SBorder)
			.BorderImage(Style::PanelBrush())
			.BorderBackgroundColor(FLinearColor(0.03f, 0.04f, 0.06f, 0.90f))
			.Padding(FMargin(22.0f, 16.0f, 12.0f, 16.0f))
			[
				SNew(SVerticalBox)
				+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 10.0f, 4.0f)
				[
					SNew(SHorizontalBox)
					+ SHorizontalBox::Slot().FillWidth(1.0f)[MakeSectionTitle(LOCTEXT("DebugTitle", "DEBUG / BENCHMARK"), 26)]
					+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
					[
						SNew(STextBlock).Text(LOCTEXT("DebugKey", "F2 close")).Font(Style::Font(16)).ColorAndOpacity(Style::Dim())
					]
				]
				+ SVerticalBox::Slot().FillHeight(1.0f)
				[
					SNew(SScrollBox)
					.Orientation(Orient_Vertical)
					.ScrollBarVisibility(EVisibility::Visible)
					+ SScrollBox::Slot().Padding(0.0f, 0.0f, 12.0f, 0.0f)
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecTeleport", "TELEPORT"), SAssignNew(TeleportBox, SVerticalBox))]
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecCars", "SPAWN CAR"), SAssignNew(CarBox, SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(6.0f, 6.0f)))]
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecTime", "TIME & WEATHER"), TimeWeather)]
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecTraffic", "TRAFFIC DENSITY"), Traffic)]
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecAssists", "ASSISTS"), Assists)]
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecOverlay", "OVERLAYS"), Overlays)]
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecTools", "CAR"), Tools)]
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecTelemetry", "TELEMETRY"), MakeTelemetry())]
						+ SVerticalBox::Slot().AutoHeight()[MakeSection(LOCTEXT("SecPois", "POINTS OF INTEREST"), SAssignNew(PoiBox, SVerticalBox))]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 14.0f, 0.0f, 0.0f)
						[
							SNew(STextBlock).AutoWrapText(true).Font(Style::Font(14)).ColorAndOpacity(Style::Dim())
							.Text(LOCTEXT("DebugNote", "Mouse driven: this menu never takes keyboard focus, so the car stays drivable while it is open."))
						]
					]
				]
			]
		]
	];
}

void SRoamDebugMenu::OnOpened()
{
	RebuildTeleports();
	RebuildCars();
}

void SRoamDebugMenu::RebuildTeleports()
{
	using namespace RoamMenus;
	if (!TeleportBox.IsValid())
	{
		return;
	}
	TeleportBox->ClearChildren();
	URoamGameInstance* Game = Cast<URoamGameInstance>(GameInstance.Get());
	const URoamWorldDefinition* Definition = Game ? Game->GetWorldDefinition() : nullptr;
	if (!Definition)
	{
		TeleportBox->AddSlot().AutoHeight()
		[
			SNew(STextBlock).AutoWrapText(true).Font(Style::Font(16)).ColorAndOpacity(Style::Danger())
			.Text(LOCTEXT("NoWorld", "No world definition configured: `tp` has no targets (Project Settings > Game > Roamline)."))
		];
		return;
	}

	if (PoiBox.IsValid())
	{
		PoiBox->ClearChildren();
	}
	const auto AddGroup = [this](const TSharedPtr<SVerticalBox>& Target, const FText& Title, const TArray<TPair<FString, FString>>& Items)
	{
		if (Items.IsEmpty() || !Target.IsValid())
		{
			return;
		}
		TSharedRef<SWrapBox> Wrap = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(6.0f, 6.0f));
		for (const TPair<FString, FString>& Item : Items)
		{
			const FString Id = Item.Key;
			Wrap->AddSlot()
			[
				MakeActionButton(FText::FromString(Item.Value), [this, Id]() { Exec(FString::Printf(TEXT("tp \"%s\""), *Id)); }, FSlateColor(RoamMenus::Style::GlassLight()))
			];
		}
		if (!Title.IsEmpty())
		{
			Target->AddSlot().AutoHeight().Padding(0.0f, 4.0f, 0.0f, 2.0f)
			[
				SNew(STextBlock).Text(Title).Font(RoamMenus::Style::Font(15, true)).ColorAndOpacity(RoamMenus::Style::Dim())
			];
		}
		Target->AddSlot().AutoHeight()[Wrap];
	};

	// The world definition may hold several rectangles of one named region: one button per display name (`tp` resolves a name to the first).
	TArray<TPair<FString, FString>> Regions;
	for (const FRoamRegionDef& Region : Definition->Regions)
	{
		const FString Name = Region.DisplayName.ToString();
		if (!Regions.ContainsByPredicate([&Name](const TPair<FString, FString>& Existing) { return Existing.Value == Name; }))
		{
			Regions.Emplace(Region.RegionId.ToString(), Name);
		}
	}
	TArray<TPair<FString, FString>> RoadStarts;
	TArray<TPair<FString, FString>> Others;
	for (const FRoamPoiDef& Poi : Definition->Pois)
	{
		if (!Poi.bTeleportTarget)
		{
			continue;
		}
		(Poi.Type == ERoamPoiType::RoadStart ? RoadStarts : Others).Emplace(Poi.PoiId.ToString(), Poi.DisplayName.ToString());
	}
	AddGroup(TeleportBox, LOCTEXT("Regions", "Regions"), Regions);
	AddGroup(TeleportBox, LOCTEXT("RoadStarts", "Long-road starts (benchmark)"), RoadStarts);
	AddGroup(PoiBox, FText::GetEmpty(), Others);
	if (Regions.IsEmpty() && RoadStarts.IsEmpty() && Others.IsEmpty())
	{
		TeleportBox->AddSlot().AutoHeight()
		[
			SNew(STextBlock).Font(Style::Font(16)).ColorAndOpacity(Style::Dim()).Text(LOCTEXT("NoTargets", "The world definition has no regions or points of interest."))
		];
	}
}

void SRoamDebugMenu::RebuildCars()
{
	using namespace RoamMenus;
	if (!CarBox.IsValid())
	{
		return;
	}
	CarBox->ClearChildren();
	URoamGameInstance* Game = Cast<URoamGameInstance>(GameInstance.Get());
	URoamCarCatalog* Catalog = Game ? Game->GetCarCatalog() : nullptr;
	TArray<URoamCarDefinition*> Cars;
	if (Catalog)
	{
		Catalog->LoadAll(Cars);
	}
	if (Cars.IsEmpty())
	{
		CarBox->AddSlot()
		[
			SNew(STextBlock).Font(Style::Font(16)).ColorAndOpacity(Style::Danger()).Text(LOCTEXT("NoCars", "No car catalog configured."))
		];
		return;
	}
	for (int32 i = 0; i < Cars.Num(); ++i)
	{
		const URoamCarDefinition* Car = Cars[i];
		const int32 Number = i + 1;
		const FString Label = FString::Printf(TEXT("%d  %s"), Number, Car ? *Car->DisplayName.ToString() : TEXT("?"));
		CarBox->AddSlot()
		[
			SNew(SBox).WidthOverride(176.0f)
			[
				MakeActionButton(FText::FromString(Label), [this, Number]() { Exec(FString::Printf(TEXT("car %d"), Number)); }, FSlateColor(Style::GlassLight()))
			]
		];
	}
}

#undef LOCTEXT_NAMESPACE
