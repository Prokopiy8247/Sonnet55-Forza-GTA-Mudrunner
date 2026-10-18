// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/SRoamConsole.h"

#include "Core/RoamGameInstance.h"
#include "Data/RoamCarCatalog.h"
#include "Data/RoamCarDefinition.h"
#include "Data/RoamWorldDefinition.h"
#include "Engine/GameInstance.h"
#include "Framework/Application/SlateApplication.h"
#include "InputCoreTypes.h"
#include "Widgets/Input/SEditableText.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SSpacer.h"
#include "Widgets/SBoxPanel.h"
#include "Widgets/Text/STextBlock.h"

#define LOCTEXT_NAMESPACE "RoamConsoleWidget"

namespace
{
	constexpr int32 MaxLineWidgets = 400;

	/** Valid values of the arguments of the built-in commands (the game state - cars, regions - is read from the data assets). */
	void GatherArgumentOptions(const UGameInstance* GameInstance, const FString& Command, int32 ArgIndex, TArray<FString>& OutOptions)
	{
		const auto AddAll = [&OutOptions](std::initializer_list<const TCHAR*> Values)
		{
			for (const TCHAR* Value : Values)
			{
				OutOptions.Add(Value);
			}
		};
		const URoamGameInstance* Game = Cast<URoamGameInstance>(GameInstance);

		if (ArgIndex == 0)
		{
			if (Command == TEXT("weather")) { AddAll({ TEXT("clear"), TEXT("cloudy"), TEXT("rain"), TEXT("fog"), TEXT("storm"), TEXT("auto") }); }
			else if (Command == TEXT("time")) { AddAll({ TEXT("dawn"), TEXT("noon"), TEXT("sunset"), TEXT("night") }); }
			else if (Command == TEXT("assist")) { AddAll({ TEXT("tcs"), TEXT("stm"), TEXT("abs"), TEXT("steer"), TEXT("auto"), TEXT("line") }); }
			else if (Command == TEXT("camera")) { AddAll({ TEXT("chase"), TEXT("hood"), TEXT("cockpit"), TEXT("bumper"), TEXT("freelook") }); }
			else if (Command == TEXT("ui")) { AddAll({ TEXT("console"), TEXT("garage"), TEXT("debug"), TEXT("map"), TEXT("photo"), TEXT("pause") }); }
			else if (Command == TEXT("traffic")) { AddAll({ TEXT("on"), TEXT("off"), TEXT("debug"), TEXT("clear"), TEXT("synth"), TEXT("stats") }); }
			else if (Command == TEXT("units")) { AddAll({ TEXT("kmh"), TEXT("mph") }); }
			else if (Command == TEXT("fps") || Command == TEXT("speed")) { AddAll({ TEXT("on"), TEXT("off") }); }
			else if (Command == TEXT("paint"))
			{
				AddAll({ TEXT("red"), TEXT("green"), TEXT("blue"), TEXT("yellow"), TEXT("orange"), TEXT("white"), TEXT("black"), TEXT("silver"), TEXT("gray"),
					TEXT("purple"), TEXT("pink"), TEXT("teal"), TEXT("cyan"), TEXT("brown"), TEXT("gold"), TEXT("navy"), TEXT("lime") });
			}
			else if (Command == TEXT("car") && Game)
			{
				if (URoamCarCatalog* Catalog = const_cast<URoamGameInstance*>(Game)->GetCarCatalog())
				{
					TArray<URoamCarDefinition*> Cars;
					Catalog->LoadAll(Cars);
					for (const URoamCarDefinition* Car : Cars)
					{
						if (Car)
						{
							// "car06_super_aether" -> "aether": the last segment is unique and ResolveCar accepts substrings.
							FString Id = Car->CarId.ToString();
							int32 Underscore = INDEX_NONE;
							Id.FindLastChar(TEXT('_'), Underscore);
							OutOptions.Add(Underscore == INDEX_NONE ? Id : Id.Mid(Underscore + 1));
						}
					}
				}
			}
			else if (Command == TEXT("tp") && Game)
			{
				if (const URoamWorldDefinition* World = const_cast<URoamGameInstance*>(Game)->GetWorldDefinition())
				{
					for (const FRoamRegionDef& Region : World->Regions) { OutOptions.Add(Region.RegionId.ToString()); }
					for (const FRoamPoiDef& Poi : World->Pois) { if (Poi.bTeleportTarget) { OutOptions.Add(Poi.PoiId.ToString()); } }
				}
			}
		}
		else if (ArgIndex == 1)
		{
			if (Command == TEXT("assist") || Command == TEXT("ui")) { AddAll({ TEXT("on"), TEXT("off") }); }
			else if (Command == TEXT("paint")) { AddAll({ TEXT("gloss"), TEXT("matte"), TEXT("metallic") }); }
		}
	}
}

// ======================================================================================================================
// SRoamConsole
// ======================================================================================================================

void SRoamConsole::Construct(const FArguments& InArgs)
{
	Console = InArgs._Console;
	OnCloseRequested = InArgs._OnCloseRequested;
	using namespace RoamMenus;

	ChildSlot
	[
		SNew(SBorder)
		.BorderImage(Style::FlatBrush())
		.BorderBackgroundColor(FLinearColor(0.0f, 0.0f, 0.0f, 0.30f))
		.Padding(0.0f)
		[
			SNew(SVerticalBox)
			+ SVerticalBox::Slot().FillHeight(0.54f)
			[
				SNew(SBorder)
				.BorderImage(Style::FlatBrush())
				.BorderBackgroundColor(Style::Glass())
				.Padding(FMargin(56.0f, 22.0f, 56.0f, 18.0f))
				[
					SNew(SVerticalBox)
					// header
					+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 0.0f, 0.0f, 10.0f)
					[
						SNew(SHorizontalBox)
						+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
						[
							SNew(SBox).WidthOverride(6.0f).HeightOverride(30.0f)
							[
								SNew(SBorder).BorderImage(Style::FlatBrush()).BorderBackgroundColor(Style::Orange())
							]
						]
						+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(14.0f, 0.0f, 0.0f, 0.0f)
						[
							SNew(STextBlock).Text(LOCTEXT("Title", "ROAMLINE CONSOLE")).Font(Style::Font(26, true)).ColorAndOpacity(Style::Chalk())
						]
						+ SHorizontalBox::Slot().FillWidth(1.0f)
						[
							SNew(SSpacer)
						]
						+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
						[
							SNew(STextBlock)
							.Text(LOCTEXT("Keys", "Enter run   |   Tab complete   |   Up/Down history   |   PgUp/PgDn scroll   |   Esc or ~ close"))
							.Font(Style::Font(15))
							.ColorAndOpacity(Style::Dim())
						]
					]
					// log
					+ SVerticalBox::Slot().FillHeight(1.0f)
					[
						SAssignNew(LogBox, SScrollBox)
						.Orientation(Orient_Vertical)
						.ScrollBarVisibility(EVisibility::Visible)
					]
					// suggestions / usage
					+ SVerticalBox::Slot().AutoHeight().Padding(0.0f, 8.0f, 0.0f, 6.0f)
					[
						SNew(SBox).MinDesiredHeight(24.0f)
						[
							SAssignNew(SuggestionText, STextBlock)
							.Font(Style::Font(16))
							.ColorAndOpacity(Style::Teal())
							.AutoWrapText(true)
						]
					]
					// input
					+ SVerticalBox::Slot().AutoHeight()
					[
						SNew(SBorder)
						.BorderImage(Style::PillBrush())
						.BorderBackgroundColor(Style::GlassLight())
						.Padding(FMargin(18.0f, 9.0f))
						[
							SNew(SHorizontalBox)
							+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(0.0f, 0.0f, 12.0f, 0.0f)
							[
								SNew(STextBlock).Text(INVTEXT(">")).Font(Style::Font(28, true)).ColorAndOpacity(Style::Orange())
							]
							+ SHorizontalBox::Slot().FillWidth(1.0f).VAlign(VAlign_Center)
							[
								SAssignNew(InputBox, SEditableText)
								.Font(Style::Font(26))
								.ColorAndOpacity(Style::Chalk())
								.HintText(LOCTEXT("Hint", "type a command, e.g. help, cars, time 18, weather rain, tp ..."))
								.ClearKeyboardFocusOnCommit(false)
								.SelectAllTextWhenFocused(false)
								.OnTextChanged(FOnTextChanged::CreateSP(this, &SRoamConsole::HandleTextChanged))
								.OnTextCommitted(FOnTextCommitted::CreateSP(this, &SRoamConsole::HandleTextCommitted))
							]
						]
					]
				]
			]
			+ SVerticalBox::Slot().AutoHeight()
			[
				SNew(SBox).HeightOverride(4.0f)
				[
					SNew(SBorder).BorderImage(Style::FlatBrush()).BorderBackgroundColor(Style::Orange())
				]
			]
			+ SVerticalBox::Slot().FillHeight(0.46f)
			[
				SNew(SSpacer)
			]
		]
	];

	if (URoamConsoleSubsystem* Sub = Console.Get())
	{
		if (Sub->GetNumOutputLines() == 0)
		{
			Sub->Print(TEXT("Roamline console. Type 'help' for the commands; Tab completes, Up/Down browse the history."), ERoamConsoleLineKind::Info);
		}
		for (int32 i = 0; i < Sub->GetNumOutputLines(); ++i)
		{
			AddLine(Sub->GetOutputLine(i));
		}
		LineAddedHandle = Sub->OnLineAdded.AddSP(this, &SRoamConsole::HandleLineAdded);
	}
	PendingScrollFrames = 4;
}

SRoamConsole::~SRoamConsole()
{
	if (URoamConsoleSubsystem* Sub = Console.Get())
	{
		Sub->OnLineAdded.Remove(LineAddedHandle);
	}
}

TSharedPtr<SWidget> SRoamConsole::GetFocusWidget() const
{
	return InputBox;
}

void SRoamConsole::OnOpened()
{
	OpenedTime = FPlatformTime::Seconds();
	SetInputText(FString());
	HistoryCursor.Reset();
	Autocompleter.Reset();
	PendingScrollFrames = 4;
	RefreshSuggestions();
}

void SRoamConsole::AddLine(const FRoamConsoleLine& Line)
{
	using namespace RoamMenus;
	FLinearColor Color = Style::Chalk();
	FString Text = Line.Text;
	switch (Line.Kind)
	{
	case ERoamConsoleLineKind::Input:
		Color = Style::Teal();
		if (!Text.StartsWith(TEXT(">")))
		{
			Text = TEXT("> ") + Text;
		}
		break;
	case ERoamConsoleLineKind::Error:
		Color = Style::Danger();
		break;
	case ERoamConsoleLineKind::Info:
		Color = FLinearColor(1.0f, 0.74f, 0.45f, 1.0f);
		break;
	default:
		break;
	}
	const TSharedRef<SWidget> Row =
		SNew(STextBlock)
		.Text(FText::FromString(Text))
		.Font(Style::Font(19))
		.ColorAndOpacity(Color)
		.AutoWrapText(true)
		.ShadowOffset(FVector2D(1.0f, 1.0f))
		.ShadowColorAndOpacity(FLinearColor(0.0f, 0.0f, 0.0f, 0.55f));
	LogBox->AddSlot().Padding(0.0f, 1.0f)[Row];
	LineWidgets.Add(Row);
	while (LineWidgets.Num() > MaxLineWidgets)
	{
		LogBox->RemoveSlot(LineWidgets[0]);
		LineWidgets.RemoveAt(0);
	}
}

void SRoamConsole::HandleLineAdded(const FRoamConsoleLine& Line)
{
	const bool bWasAtEnd = !LogBox.IsValid() || LogBox->GetScrollOffset() >= LogBox->GetScrollOffsetOfEnd() - 40.0f;
	AddLine(Line);
	if (bWasAtEnd)
	{
		PendingScrollFrames = 4;
	}
}

void SRoamConsole::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SCompoundWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	if (PendingScrollFrames > 0 && LogBox.IsValid())
	{
		LogBox->ScrollToEnd();
		--PendingScrollFrames;
	}
}

FString SRoamConsole::GetInputString() const
{
	return InputBox.IsValid() ? InputBox->GetText().ToString() : FString();
}

void SRoamConsole::SetInputText(const FString& Text)
{
	if (!InputBox.IsValid())
	{
		return;
	}
	bSettingText = true;
	InputBox->SetText(FText::FromString(Text));
	InputBox->GoTo(ETextLocation::EndOfDocument);
	bSettingText = false;
}

void SRoamConsole::HandleTextChanged(const FText& NewText)
{
	if (bSettingText)
	{
		return;
	}
	// The key that opened the console also delivers its character (` or ~, on other keyboard layouts a letter): drop whatever arrives
	// in the first moments after opening, and never type ` or ~.
	FString Text = NewText.ToString();
	if (FPlatformTime::Seconds() - OpenedTime < 0.15 && !Text.IsEmpty())
	{
		SetInputText(FString());
		return;
	}
	if (Text.Contains(TEXT("`")) || Text.Contains(TEXT("~")))
	{
		Text.ReplaceInline(TEXT("`"), TEXT(""));
		Text.ReplaceInline(TEXT("~"), TEXT(""));
		SetInputText(Text);
	}
	RefreshSuggestions();
}

void SRoamConsole::HandleTextCommitted(const FText& NewText, ETextCommit::Type CommitType)
{
	if (CommitType != ETextCommit::OnEnter)
	{
		return;
	}
	const FString Line = NewText.ToString().TrimStartAndEnd();
	SetInputText(FString());
	HistoryCursor.Reset();
	Autocompleter.Reset();
	PendingScrollFrames = 4;
	if (!Line.IsEmpty())
	{
		if (URoamConsoleSubsystem* Sub = Console.Get())
		{
			Sub->Execute(Line);
		}
	}
	RefreshSuggestions();
}

void SRoamConsole::GatherCommandNames(TArray<FString>& OutNames) const
{
	if (const URoamConsoleSubsystem* Sub = Console.Get())
	{
		for (const FName Name : Sub->GetCommandNames())
		{
			OutNames.Add(Name.ToString());
		}
	}
}

void SRoamConsole::DoComplete(bool bBackward)
{
	TArray<FString> Names;
	GatherCommandNames(Names);
	const UGameInstance* GameInstance = Console.IsValid() ? Console->GetGameInstance() : nullptr;
	const FString Result = Autocompleter.Complete(GetInputString(), Names, [GameInstance](const FString& Command, int32 ArgIndex, TArray<FString>& Out)
	{
		GatherArgumentOptions(GameInstance, Command, ArgIndex, Out);
	}, bBackward);
	SetInputText(Result);
	RefreshSuggestions();
}

void SRoamConsole::RefreshSuggestions()
{
	if (!SuggestionText.IsValid())
	{
		return;
	}
	const FString Input = GetInputString();
	FString Out;
	if (!Input.TrimStart().IsEmpty())
	{
		TArray<FString> Names;
		GatherCommandNames(Names);
		const UGameInstance* GameInstance = Console.IsValid() ? Console->GetGameInstance() : nullptr;
		const RoamMenus::FAutocompleteResult Result = RoamMenus::Autocomplete(Input, Names, [GameInstance](const FString& Command, int32 ArgIndex, TArray<FString>& Opts)
		{
			GatherArgumentOptions(GameInstance, Command, ArgIndex, Opts);
		});

		FString Prefix;
		FString Token;
		FString Command;
		const int32 TokenIndex = RoamMenus::SplitForCompletion(Input, Prefix, Token, Command);
		if (TokenIndex >= 1)
		{
			if (const URoamConsoleSubsystem* Sub = Console.Get())
			{
				if (const FRoamConsoleCommand* Found = Sub->FindCommand(FName(*Command)))
				{
					Out = FString::Printf(TEXT("%s   -   %s"), Found->Usage.IsEmpty() ? *Found->Name.ToString() : *Found->Usage, *Found->Help);
				}
			}
		}
		if (!Result.Matches.IsEmpty() && !(Result.Matches.Num() == 1 && Result.Matches[0].Equals(Token, ESearchCase::IgnoreCase)))
		{
			const int32 Shown = FMath::Min(Result.Matches.Num(), 14);
			FString List = Out.IsEmpty() ? FString() : Out + TEXT("\n");
			for (int32 i = 0; i < Shown; ++i)
			{
				List += (i == 0 ? TEXT("") : TEXT("   ")) + Result.Matches[i];
			}
			if (Result.Matches.Num() > Shown)
			{
				List += FString::Printf(TEXT("   (+%d more)"), Result.Matches.Num() - Shown);
			}
			Out = List;
		}
	}
	SuggestionText->SetText(FText::FromString(Out));
}

void SRoamConsole::ScrollLog(float DeltaPixels)
{
	if (LogBox.IsValid())
	{
		LogBox->SetScrollOffset(LogBox->GetScrollOffset() + DeltaPixels);
		PendingScrollFrames = 0;
	}
}

FReply SRoamConsole::OnPreviewKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent)
{
	const FKey Key = InKeyEvent.GetKey();
	if (Key == EKeys::Tilde || Key == EKeys::Escape || Key == EKeys::Gamepad_FaceButton_Right)
	{
		OnCloseRequested.ExecuteIfBound();
		return FReply::Handled();
	}
	if (Key == EKeys::Tab)
	{
		DoComplete(InKeyEvent.IsShiftDown());
		return FReply::Handled();
	}
	if (Key == EKeys::Up || Key == EKeys::Gamepad_DPad_Up)
	{
		if (const URoamConsoleSubsystem* Sub = Console.Get())
		{
			FString Text;
			if (HistoryCursor.Older(Sub->GetHistory(), GetInputString(), Text))
			{
				SetInputText(Text);
				RefreshSuggestions();
			}
		}
		return FReply::Handled();
	}
	if (Key == EKeys::Down || Key == EKeys::Gamepad_DPad_Down)
	{
		if (const URoamConsoleSubsystem* Sub = Console.Get())
		{
			FString Text;
			if (HistoryCursor.Newer(Sub->GetHistory(), Text))
			{
				SetInputText(Text);
				RefreshSuggestions();
			}
		}
		return FReply::Handled();
	}
	if (Key == EKeys::PageUp)
	{
		ScrollLog(-360.0f);
		return FReply::Handled();
	}
	if (Key == EKeys::PageDown)
	{
		ScrollLog(360.0f);
		return FReply::Handled();
	}
	return FReply::Unhandled();
}

FReply SRoamConsole::OnMouseButtonDown(const FGeometry& MyGeometry, const FPointerEvent& MouseEvent)
{
	// A click anywhere on the (full-screen) overlay keeps the keyboard in the input line instead of falling through to the game.
	if (InputBox.IsValid())
	{
		FSlateApplication::Get().SetKeyboardFocus(InputBox, EFocusCause::Mouse);
	}
	return FReply::Handled();
}

// ======================================================================================================================
// SRoamConsoleHint
// ======================================================================================================================

void SRoamConsoleHint::Construct(const FArguments& InArgs)
{
	using namespace RoamMenus;
	ChildSlot
	.HAlign(HAlign_Center)
	.VAlign(VAlign_Top)
	.Padding(0.0f, 26.0f, 0.0f, 0.0f)
	[
		SNew(SBorder)
		.BorderImage(Style::PillBrush())
		.BorderBackgroundColor(FLinearColor(0.03f, 0.04f, 0.06f, 0.78f))
		.Padding(FMargin(22.0f, 9.0f))
		[
			SNew(SHorizontalBox)
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(STextBlock).Text(INVTEXT("Press")).Font(Style::Font(20)).ColorAndOpacity(Style::Dim())
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center).Padding(8.0f, 0.0f)
			[
				SNew(SBorder)
				.BorderImage(Style::PillBrush())
				.BorderBackgroundColor(Style::Orange())
				.Padding(FMargin(12.0f, 1.0f))
				[
					SNew(STextBlock).Text(INVTEXT("~")).Font(Style::Font(22, true)).ColorAndOpacity(FLinearColor(0.03f, 0.03f, 0.04f, 1.0f))
				]
			]
			+ SHorizontalBox::Slot().AutoWidth().VAlign(VAlign_Center)
			[
				SNew(STextBlock).Text(INVTEXT("for console     F1 garage     F2 debug     Esc pause")).Font(Style::Font(20)).ColorAndOpacity(Style::Dim())
			]
		]
	];
	SetRenderOpacity(0.0f);
}

void SRoamConsoleHint::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SCompoundWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	if (StartTime < 0.0)
	{
		StartTime = InCurrentTime;
	}
	// 1.2 s delay, 0.7 s fade in, 7 s hold, 1.5 s fade out.
	const float T = static_cast<float>(InCurrentTime - StartTime);
	float Alpha = 0.0f;
	if (T > 1.2f && T < 10.4f)
	{
		Alpha = T < 1.9f ? (T - 1.2f) / 0.7f : (T < 8.9f ? 1.0f : 1.0f - (T - 8.9f) / 1.5f);
	}
	SetRenderOpacity(bSuppressed ? 0.0f : FMath::Clamp(Alpha, 0.0f, 1.0f));
}

#undef LOCTEXT_NAMESPACE
