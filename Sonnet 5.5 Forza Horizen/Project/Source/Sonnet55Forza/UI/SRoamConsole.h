// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Console/RoamConsoleSubsystem.h"
#include "UI/RoamMenus.h"
#include "Widgets/DeclarativeSyntaxSupport.h"
#include "Widgets/SCompoundWidget.h"

class SEditableText;
class SScrollBox;
class STextBlock;

/**
 * The in-game console overlay (toggled with ` / ~): scrolling output log, single-line input with history (Up/Down), autocomplete
 * (Tab / Shift+Tab, commands and their arguments) and live suggestions. Executes through URoamConsoleSubsystem::Execute and mirrors its
 * output buffer, so everything printed by any system (or by `roam <cmd>` from the engine console) appears here.
 * Keys: Enter run | Up/Down history | Tab complete | PgUp/PgDn scroll | Esc, ~ or gamepad B close.
 */
class SRoamConsole : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamConsole) {}
		SLATE_ARGUMENT(TWeakObjectPtr<URoamConsoleSubsystem>, Console)
		SLATE_EVENT(FSimpleDelegate, OnCloseRequested)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);
	virtual ~SRoamConsole() override;

	/** The panel was opened: clear the input, show the end of the log. */
	void OnOpened();
	TSharedPtr<SWidget> GetFocusWidget() const;

	virtual bool SupportsKeyboardFocus() const override { return false; }
	virtual FReply OnPreviewKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent) override;
	virtual FReply OnMouseButtonDown(const FGeometry& MyGeometry, const FPointerEvent& MouseEvent) override;
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;

private:
	void AddLine(const FRoamConsoleLine& Line);
	void HandleLineAdded(const FRoamConsoleLine& Line);
	void HandleTextChanged(const FText& NewText);
	void HandleTextCommitted(const FText& NewText, ETextCommit::Type CommitType);
	void SetInputText(const FString& Text);
	FString GetInputString() const;
	void DoComplete(bool bBackward);
	void RefreshSuggestions();
	void GatherCommandNames(TArray<FString>& OutNames) const;
	void ScrollLog(float DeltaPixels);

	TWeakObjectPtr<URoamConsoleSubsystem> Console;
	FSimpleDelegate OnCloseRequested;
	FDelegateHandle LineAddedHandle;

	TSharedPtr<SScrollBox> LogBox;
	TSharedPtr<SEditableText> InputBox;
	TSharedPtr<STextBlock> SuggestionText;
	TArray<TSharedRef<SWidget>> LineWidgets;

	RoamMenus::FAutocompleteSession Autocompleter;
	RoamMenus::FHistoryCursor HistoryCursor;
	FString SuggestionString;
	bool bSettingText = false;
	double OpenedTime = -10.0;
	int32 PendingScrollFrames = 0;
};

/** "Press ~ for console" hint: fades in at the start of the session, stays a few seconds and fades out. */
class SRoamConsoleHint : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamConsoleHint) {}
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);
	/** True while any panel is open: the hint disappears immediately. */
	void SetSuppressed(bool bInSuppressed) { bSuppressed = bInSuppressed; }
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;

private:
	double StartTime = -1.0;
	bool bSuppressed = false;
};
