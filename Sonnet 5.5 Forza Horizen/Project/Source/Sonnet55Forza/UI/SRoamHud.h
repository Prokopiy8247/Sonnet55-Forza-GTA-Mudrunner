// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "UI/RoamUIStyle.h"
#include "Widgets/SCompoundWidget.h"

class SRoamMinimap;
class SRoamNotifications;
class SRoamSpeedCluster;
class URoamUISubsystem;

/**
 * Root of the in-game HUD (one viewport widget at RoamUI::Layer::Hud): speed cluster bottom-right, minimap bottom-left, a click-through
 * info layer (world strip above the minimap, camera-mode chip, FPS counter, wrong-way hint) and the notification painter. All elements
 * sit inside the 5 percent safe area, which is recomputed from the widget's own size (so it follows window resizes).
 */
class SRoamHud : public SCompoundWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamHud) {}
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI);

	TSharedPtr<SRoamSpeedCluster> GetSpeedCluster() const { return SpeedCluster; }
	TSharedPtr<SRoamMinimap> GetMinimap() const { return Minimap; }
	TSharedPtr<SRoamNotifications> GetNotifications() const { return Notifications; }

	//~ Begin SWidget
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;
	//~ End SWidget

private:
	FMargin GetClusterPadding() const;
	FMargin GetMinimapPadding() const;

	TWeakObjectPtr<URoamUISubsystem> UI;
	TSharedPtr<SRoamSpeedCluster> SpeedCluster;
	TSharedPtr<SRoamMinimap> Minimap;
	TSharedPtr<SRoamNotifications> Notifications;
	RoamUI::Logic::FSafeArea Safe;
};
