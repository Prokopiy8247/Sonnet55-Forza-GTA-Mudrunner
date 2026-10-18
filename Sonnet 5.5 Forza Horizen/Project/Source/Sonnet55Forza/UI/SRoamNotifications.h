// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Activities/RoamActivitySubsystem.h"
#include "Core/RoamTypes.h"
#include "UI/RoamUIStyle.h"
#include "Widgets/SLeafWidget.h"

class URoamUISubsystem;

/**
 * Full-screen, click-through painter of every transient HUD message (RESEARCH_NOTES 5.1 item 5):
 *   - region name popup, top-left (560 x 88; 350 ms in, 2.8 s hold, 400 ms out),
 *   - activity event bar / live meter, top-centre (640 x 84): title, type, value, timer, stars (URoamActivitySubsystem::GetLiveInfo),
 *   - toast stack, top-right (max 3 at 440 x 72, 4 s hold, overflow waits in a queue),
 *   - banner (upper third) and result card (centre, stars + "NEW BEST") for activity results.
 * Notifications arrive through URoamUISubsystem::OnNotificationPushed, the region popup through OnRegionPopup.
 */
class SRoamNotifications : public SLeafWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamNotifications) {}
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI);
	virtual ~SRoamNotifications() override;

	/** Debug/preview hook (console `ui.testevent`): shows this live info in the event bar instead of the activity system's. */
	void SetEventOverride(const FRoamActivityLiveInfo* LiveInfo, const FText& Title);

	//~ Begin SWidget
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;
	virtual int32 OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
		int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;
	virtual FVector2D ComputeDesiredSize(float LayoutScaleMultiplier) const override { return FVector2D::ZeroVector; }
	//~ End SWidget

private:
	void HandleNotification(const FRoamNotification& Notification);
	void HandleRegionPopup(const FText& Name, const FText& Subtitle);
	void PaintToast(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const RoamUI::Logic::FNotificationChannel::FEntry& Entry, const FVector2f& Origin, float Alpha) const;

	TWeakObjectPtr<URoamUISubsystem> UI;
	FDelegateHandle NotificationHandle;
	FDelegateHandle RegionHandle;

	RoamUI::Logic::FNotificationChannel Toasts{ RoamUI::Layout::MaxToasts, 16 };
	RoamUI::Logic::FNotificationChannel Banners{ 1, 6 };
	RoamUI::Logic::FNotificationChannel Cards{ 1, 6 };
	double Now = 0.0;

	// region popup
	FString RegionName;
	FString RegionSubtitle;
	double RegionShownAt = -1000.0;

	// event bar
	bool bEventActive = false;
	FRoamActivityLiveInfo EventInfo;
	FString EventTitle;
	bool bEventOverride = false;
	FRoamActivityLiveInfo EventOverrideInfo;
	FText EventOverrideTitle;
	double EventOverrideSetAt = 0.0;
	FString EventTypeText;
	FString EventValueText;
	FString EventValueLabel;
	FString EventTimerText;
	bool bMph = false;
	bool bShowNotifications = true;
};
