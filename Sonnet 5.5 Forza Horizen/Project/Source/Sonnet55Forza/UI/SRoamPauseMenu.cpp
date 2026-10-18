// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/SRoamPauseMenu.h"

#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/PlayerController.h"
#include "InputCoreTypes.h"
#include "Kismet/KismetSystemLibrary.h"
#include "Misc/App.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUISubsystem.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScaleBox.h"
#include "Widgets/Layout/SSpacer.h"
#include "Widgets/Layout/SWidgetSwitcher.h"
#include "Widgets/Layout/SWrapBox.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Text/STextBlock.h"

#define LOCTEXT_NAMESPACE "RoamPauseMenu"

URoamSaveSubsystem* SRoamPauseMenu::GetSave() const
{
	return GameInstance.IsValid() ? GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
}

FRoamPlayerSettings* SRoamPauseMenu::GetSettings() const
{
	URoamSaveSubsystem* Save = GetSave();
	return Save ? &Save->GetSettings() : nullptr;
}

void SRoamPauseMenu::Construct(const FArguments& InArgs)
{
	GameInstance = InArgs._GameInstance;
	OnCloseRequested = InArgs._OnCloseRequested;
	using namespace RoamMenus;

	if (const FRoamPlayerSettings* Settings = GetSettings())
	{
		FApp::SetVolumeMultiplier(Settings->MasterVolume); // the stored master volume becomes effective as soon as the menus exist
	}

	ChildSlot
	[
		SNew(SBorder)
		.BorderImage(Style::FlatBrush())
		.BorderBackgroundColor(FLinearColor(0.0f, 0.0f, 0.0f, 0.66f))
		.Padding(0.0f)
		[
			SNew(SScaleBox)
			.Stretch(EStretch::ScaleToFit)
			[
				SNew(SBox).WidthOverride(700.0f).HeightOverride(780.0f)
				[
					SNew(SBorder)
					.BorderImage(Style::PanelBrush())
					.BorderBackgroundColor(Style::Glass())
					.Padding(FMargin(48.0f, 40.0f))
					[
						SNew(SVerticalBox)
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 6.0f)
						[
							MakeSectionTitle(LOCTEXT("PausedTitle", "PAUSED"), 48)
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 28.0f)
						[
							SNew(STextBlock).Text(LOCTEXT("GameName", "ROAMLINE: OPEN ROADS")).Font(Style::Font(20, true)).ColorAndOpacity(Style::Teal())
						]
						+ SVerticalBox::Slot().FillHeight(1.0f)
						[
							SNew(SWidgetSwitcher)
							.WidgetIndex_Lambda([this]() -> int32 { return static_cast<int32>(Page); })
							+ SWidgetSwitcher::Slot()[BuildMainPage()]
							+ SWidgetSwitcher::Slot()[BuildSettingsPage()]
						]
						+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 10.0f, 0.0f, 0.0f)
						[
							SNew(STextBlock).Font(Style::Font(17)).ColorAndOpacity(Style::Dim())
							.Text(LOCTEXT("PauseHint", "Esc or B: back / resume    Up, Down, Enter or mouse: choose"))
						]
					]
				]
			]
		]
	];
}

void SRoamPauseMenu::OnOpened()
{
	Page = EPage::Main;
	bQuitArmed = false;
	StatusText.Reset();
}

TSharedPtr<SWidget> SRoamPauseMenu::GetFocusWidget() const
{
	return (Page == EPage::Settings && SettingsFocus.IsValid()) ? SettingsFocus : (ResumeButton.IsValid() ? ResumeButton : ConstCastSharedRef<SWidget>(AsShared()));
}

void SRoamPauseMenu::SetPage(EPage NewPage)
{
	Page = NewPage;
	bQuitArmed = false;
	if (const TSharedPtr<SWidget> Target = GetFocusWidget())
	{
		FSlateApplication::Get().SetKeyboardFocus(Target, EFocusCause::SetDirectly);
	}
}

FReply SRoamPauseMenu::OnPreviewKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent)
{
	const FKey Key = InKeyEvent.GetKey();
	if (Key == EKeys::Escape || Key == EKeys::Gamepad_FaceButton_Right || Key == EKeys::Gamepad_Special_Right)
	{
		if (Page == EPage::Settings)
		{
			SetPage(EPage::Main);
		}
		else
		{
			OnCloseRequested.ExecuteIfBound();
		}
		return FReply::Handled();
	}
	return FReply::Unhandled();
}

void SRoamPauseMenu::DoSave()
{
	URoamSaveSubsystem* Save = GetSave();
	const bool bOk = Save && Save->SaveProfile(true);
	StatusText = bOk ? TEXT("Game saved.") : TEXT("Saving failed - see the log.");
	if (URoamUISubsystem* UI = GameInstance.IsValid() ? GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr)
	{
		UI->PushNotification(LOCTEXT("SaveTitle", "SAVE"), FText::FromString(StatusText), bOk ? RoamMenus::Style::Good() : RoamMenus::Style::Danger());
	}
}

void SRoamPauseMenu::DoQuit()
{
	if (!bQuitArmed)
	{
		bQuitArmed = true;
		return;
	}
	if (URoamSaveSubsystem* Save = GetSave())
	{
		Save->SaveProfile(true);
	}
	UWorld* World = RoamMenus::GetWorld(GameInstance.Get());
	UKismetSystemLibrary::QuitGame(World, World ? World->GetFirstPlayerController() : nullptr, EQuitPreference::Quit, false);
}

TSharedRef<SWidget> SRoamPauseMenu::BuildMainPage()
{
	using namespace RoamMenus;
	const auto Big = [](const TAttribute<FText>& Label, FOnClicked OnClicked, const FLinearColor& Tint, TSharedPtr<SWidget>* Out) -> TSharedRef<SWidget>
	{
		return MakeButton(Label, OnClicked, FSlateColor(Tint), true, 28, true, Out);
	};
	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 5.0f)
		[
			SNew(SBox).HeightOverride(78.0f)
			[
				Big(LOCTEXT("Resume", "RESUME"), FOnClicked::CreateLambda([this]() { OnCloseRequested.ExecuteIfBound(); return FReply::Handled(); }),
					FLinearColor(0.95f, 0.40f, 0.08f, 1.0f), &ResumeButton)
			]
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 5.0f)
		[
			SNew(SBox).HeightOverride(78.0f)
			[
				Big(LOCTEXT("Settings", "SETTINGS"), FOnClicked::CreateLambda([this]() { SetPage(EPage::Settings); return FReply::Handled(); }), Style::GlassLight(), nullptr)
			]
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 5.0f)
		[
			SNew(SBox).HeightOverride(78.0f)
			[
				Big(LOCTEXT("Save", "SAVE"), FOnClicked::CreateLambda([this]() { DoSave(); return FReply::Handled(); }), Style::GlassLight(), nullptr)
			]
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 5.0f)
		[
			SNew(SBox).HeightOverride(78.0f)
			[
				Big(TAttribute<FText>::CreateLambda([this]() -> FText { return bQuitArmed ? LOCTEXT("QuitConfirm", "CLICK AGAIN TO QUIT") : LOCTEXT("Quit", "QUIT"); }),
					FOnClicked::CreateLambda([this]() { DoQuit(); return FReply::Handled(); }), FLinearColor(0.62f, 0.14f, 0.14f, 1.0f), nullptr)
			]
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 18.0f, 0.0f, 0.0f)
		[
			SNew(STextBlock).Font(Style::Font(20, true)).ColorAndOpacity(Style::Good())
			.Text_Lambda([this]() { return FText::FromString(StatusText); })
		];
}

TSharedRef<SWidget> SRoamPauseMenu::MakeSettingToggle(const FText& Label, TFunction<bool*(FRoamPlayerSettings&)> Field, TSharedPtr<SWidget>* OutButton)
{
	using namespace RoamMenus;
	const auto IsOn = [this, Field]() -> bool
	{
		FRoamPlayerSettings* S = GetSettings();
		const bool* Value = S ? Field(*S) : nullptr;
		return Value && *Value;
	};
	return MakeButton(
		TAttribute<FText>::CreateLambda([Label, IsOn]() -> FText { return FText::Format(INVTEXT("{0}   {1}"), Label, IsOn() ? INVTEXT("ON") : INVTEXT("OFF")); }),
		FOnClicked::CreateLambda([this, Field]()
		{
			if (FRoamPlayerSettings* S = GetSettings())
			{
				bool* Value = Field(*S);
				*Value = !*Value;
				GetSave()->MarkDirty();
			}
			return FReply::Handled();
		}),
		TAttribute<FSlateColor>::CreateLambda([IsOn]() -> FSlateColor
		{
			return IsOn() ? FSlateColor(FLinearColor(0.05f, 0.55f, 0.52f, 1.0f)) : FSlateColor(Style::GlassLight());
		}),
		true, 21, true, OutButton);
}

TSharedRef<SWidget> SRoamPauseMenu::BuildSettingsPage()
{
	using namespace RoamMenus;
	const auto UnitButton = [this](const FText& Label, bool bMph, TSharedPtr<SWidget>* Out) -> TSharedRef<SWidget>
	{
		return MakeButton(Label,
			FOnClicked::CreateLambda([this, bMph]()
			{
				if (FRoamPlayerSettings* S = GetSettings()) { S->bUseMph = bMph; GetSave()->MarkDirty(); }
				return FReply::Handled();
			}),
			TAttribute<FSlateColor>::CreateLambda([this, bMph]() -> FSlateColor
			{
				const FRoamPlayerSettings* S = GetSettings();
				return (S && S->bUseMph == bMph) ? FSlateColor(Style::Orange()) : FSlateColor(Style::GlassLight());
			}),
			true, 22, true, Out);
	};
	const auto Toggle = [this](const FText& Label, TFunction<bool*(FRoamPlayerSettings&)> Field) -> TSharedRef<SWidget>
	{
		return SNew(SBox).Padding(FMargin(0.0f, 3.0f))[MakeSettingToggle(Label, Field)];
	};

	return SNew(SVerticalBox)
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 8.0f)[MakeSectionTitle(LOCTEXT("SecUnits", "SPEED UNIT"), 22)]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 22.0f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.0f).Padding(0.0f, 0.0f, 8.0f, 0.0f)[UnitButton(LOCTEXT("Kmh", "KM/H"), false, &SettingsFocus)]
			+ SHorizontalBox::Slot().FillWidth(1.0f)[UnitButton(LOCTEXT("Mph", "MPH"), true, nullptr)]
		]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 8.0f)[MakeSectionTitle(LOCTEXT("SecHud", "HUD"), 22)]
		+ SVerticalBox::Slot().AutoHeight()[Toggle(LOCTEXT("HudAll", "HUD"), [](FRoamPlayerSettings& S) { return &S.bHudVisible; })]
		+ SVerticalBox::Slot().AutoHeight()[Toggle(LOCTEXT("HudMap", "MINIMAP"), [](FRoamPlayerSettings& S) { return &S.bShowMinimap; })]
		+ SVerticalBox::Slot().AutoHeight()[Toggle(LOCTEXT("HudSpeed", "SPEEDOMETER"), [](FRoamPlayerSettings& S) { return &S.bShowSpeedometer; })]
		+ SVerticalBox::Slot().AutoHeight()[Toggle(LOCTEXT("HudFps", "FPS COUNTER"), [](FRoamPlayerSettings& S) { return &S.bShowFps; })]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 22.0f)[Toggle(LOCTEXT("HudNotes", "NOTIFICATIONS"), [](FRoamPlayerSettings& S) { return &S.bShowNotifications; })]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 8.0f)[MakeSectionTitle(LOCTEXT("SecVolume", "MASTER VOLUME"), 22)]
		+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 22.0f)
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
			[
				SNew(SSlider)
				.Style(Style::Slider())
				.StepSize(0.05f)
				.SliderBarColor(FLinearColor::White)
				.SliderHandleColor(Style::Orange())
				.Value_Lambda([this]() -> float { const FRoamPlayerSettings* S = GetSettings(); return S ? S->MasterVolume : 1.0f; })
				.OnValueChanged_Lambda([this](float Value)
				{
					if (FRoamPlayerSettings* S = GetSettings())
					{
						S->MasterVolume = FMath::Clamp(Value, 0.0f, 1.0f);
						GetSave()->MarkDirty();
						FApp::SetVolumeMultiplier(S->MasterVolume);
					}
				})
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(16.0f, 0.0f, 0.0f, 0.0f)
			[
				SNew(SBox).WidthOverride(80.0f)
				[
					SNew(STextBlock).Font(Style::Font(24, true)).ColorAndOpacity(Style::Chalk()).Justification(ETextJustify::Right)
					.Text_Lambda([this]() -> FText { const FRoamPlayerSettings* S = GetSettings(); return FText::FromString(FString::Printf(TEXT("%d %%"), FMath::RoundToInt((S ? S->MasterVolume : 1.0f) * 100.0f))); })
				]
			]
		]
		+ SVerticalBox::Slot().FillHeight(1.0f)[SNew(SSpacer)]
		+ SVerticalBox::Slot().AutoHeight()
		[
			SNew(SBox).HeightOverride(70.0f)
			[
				MakeButton(LOCTEXT("Back", "BACK"), FOnClicked::CreateLambda([this]() { SetPage(EPage::Main); return FReply::Handled(); }), FSlateColor(Style::GlassLight()), true, 26)
			]
		];
}

#undef LOCTEXT_NAMESPACE
