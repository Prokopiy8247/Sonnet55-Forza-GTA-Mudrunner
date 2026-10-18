// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "UI/RoamMenus.h"
#include "Widgets/DeclarativeSyntaxSupport.h"
#include "Widgets/SCompoundWidget.h"

class ARoamVehicle;
class SVerticalBox;
class SWrapBox;
class UGameInstance;

/** Which debug read-outs the overlay draws (shared between the menu and the overlay). */
struct FRoamDebugOverlayState
{
	bool bFps = false;
	bool bCoordinates = false;
	bool bSpeed = false;
};

/** Top-right read-outs: FPS, world coordinates and speed. Hidden while all three are off. */
class SRoamDebugOverlay : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamDebugOverlay) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UGameInstance>, GameInstance)
		SLATE_ARGUMENT(TSharedPtr<FRoamDebugOverlayState>, State)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;

private:
	TWeakObjectPtr<UGameInstance> GameInstance;
	TSharedPtr<FRoamDebugOverlayState> State;
	float SmoothedFps = 60.0f;
};

/**
 * Debug / benchmark menu (F2): a left side panel that does NOT take keyboard focus, so the car stays drivable while it is open (it is
 * operated with the mouse). Sections: teleports (regions, long-road starts, points of interest), spawn any car, time slider + weather,
 * traffic density, assists, overlays (FPS, coordinates, speed), repair / flip / reset buttons and a live telemetry panel.
 */
class SRoamDebugMenu : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamDebugMenu) {}
		SLATE_ARGUMENT(TWeakObjectPtr<UGameInstance>, GameInstance)
		SLATE_ARGUMENT(TSharedPtr<FRoamDebugOverlayState>, OverlayState)
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs);
	/** The panel was opened: rebuild the data driven lists (teleports, cars). */
	void OnOpened();

private:
	ARoamVehicle* GetVehicle() const;
	void Exec(const FString& CommandLine) const;
	void RebuildTeleports();
	void RebuildCars();

	TSharedRef<SWidget> MakeToggle(const FText& Label, TFunction<bool()> IsOn, TFunction<void()> Toggle) const;
	TSharedRef<SWidget> MakeActionButton(const FText& Label, TFunction<void()> Action, const FSlateColor& Tint) const;
	TSharedRef<SWidget> MakeSection(const FText& Title, const TSharedRef<SWidget>& Content) const;
	TSharedRef<SWidget> MakeTelemetry() const;

	TWeakObjectPtr<UGameInstance> GameInstance;
	TSharedPtr<FRoamDebugOverlayState> OverlayState;
	TSharedPtr<SVerticalBox> TeleportBox;
	TSharedPtr<SVerticalBox> PoiBox;
	TSharedPtr<SWrapBox> CarBox;
};
