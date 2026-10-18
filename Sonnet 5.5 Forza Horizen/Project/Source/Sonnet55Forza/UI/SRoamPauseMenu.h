// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "UI/RoamMenus.h"
#include "Widgets/DeclarativeSyntaxSupport.h"
#include "Widgets/SCompoundWidget.h"

class UGameInstance;
class URoamSaveSubsystem;
struct FRoamPlayerSettings;

/**
 * Pause menu (Esc): RESUME, SETTINGS (speed unit km/h | mph, HUD toggles, master volume - all stored in the profile through
 * URoamSaveSubsystem::GetSettings), SAVE and QUIT (asks twice). The game is paused by URoamUISubsystem while this panel is open.
 * Esc / gamepad B go back one level, Up/Down/Enter or the mouse operate the buttons.
 */
class SRoamPauseMenu : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamPauseMenu) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UGameInstance>, GameInstance)
		SLATE_EVENT(FSimpleDelegate, OnCloseRequested)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);

	/** The panel was opened: back to the main page. */
	void OnOpened();
	TSharedPtr<SWidget> GetFocusWidget() const;

	virtual bool SupportsKeyboardFocus() const override { return true; }
	virtual FReply OnPreviewKeyDown(const FGeometry& MyGeometry, const FKeyEvent& InKeyEvent) override;

private:
	enum class EPage : uint8 { Main = 0, Settings };

	URoamSaveSubsystem* GetSave() const;
	FRoamPlayerSettings* GetSettings() const;
	void SetPage(EPage NewPage);
	void DoSave();
	void DoQuit();
	TSharedRef<SWidget> BuildMainPage();
	TSharedRef<SWidget> BuildSettingsPage();
	TSharedRef<SWidget> MakeSettingToggle(const FText& Label, TFunction<bool*(FRoamPlayerSettings&)> Field, TSharedPtr<SWidget>* OutButton = nullptr);

	TWeakObjectPtr<UGameInstance> GameInstance;
	FSimpleDelegate OnCloseRequested;
	EPage Page = EPage::Main;
	TSharedPtr<SWidget> ResumeButton;
	TSharedPtr<SWidget> SettingsFocus;
	bool bQuitArmed = false;
	FString StatusText;
};
