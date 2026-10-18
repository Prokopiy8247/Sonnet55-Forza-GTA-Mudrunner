// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Widgets/SLeafWidget.h"

class URoamUISubsystem;

/**
 * Speed cluster (bottom-right, 480 x 200 in 1080p units): 3-cell tabular speed readout (104 px) with dim leading zeros, km/h <-> mph,
 * 48-segment tachometer arc with warn/redline zones and limiter flash, gear box, shift/limiter cue, surface indicator, ABS/TCS/STM
 * lamps, G-force readout and a boost gauge when the car has a turbo. Pulls the player's telemetry in Tick (one struct copy) and draws
 * everything from cached values in OnPaint.
 */
class SRoamSpeedCluster : public SLeafWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamSpeedCluster) {}
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI);

	/** Test/preview hook: when set the cluster shows this telemetry instead of the player's vehicle. */
	void SetTelemetryOverride(const FRoamVehicleTelemetry* Telemetry, bool bMph);

	//~ Begin SWidget
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;
	virtual int32 OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
		int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;
	virtual FVector2D ComputeDesiredSize(float LayoutScaleMultiplier) const override;
	//~ End SWidget

private:
	TWeakObjectPtr<URoamUISubsystem> UI;

	FRoamVehicleTelemetry Telemetry;
	bool bHasData = false;
	bool bOverride = false;
	bool bOverrideMph = false;
	bool bMph = false;
	double Now = 0.0;

	// Smoothed / cached presentation state (updated in Tick).
	float DisplayNormRpm = 0.0f;
	float DisplaySpeedKmh = 0.0f;
	float DisplayBoost = 0.0f;
	float GForce = 0.0f;
	int32 SpeedInt = 0;
	FString SpeedText;
	FString GearTextCache;
	FString RpmText;
	FString GText;
	FString SurfaceText;
	bool bManualGearbox = false;
};
