// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Widgets/SLeafWidget.h"

class URoamRoadNetwork;
class URoamUISubsystem;

/**
 * Flattened, simplified road lines for the minimap: built ONCE per road network (Douglas-Peucker at ~2.5 m), sorted by draw order so
 * the widget can paint the classes back to front without any per-frame sorting. Coordinates are metres, x = UE X (north), y = UE Y (east).
 */
class SONNET55FORZA_API FRoamMinimapCache
{
public:
	struct FPolyline
	{
		ERoamRoadClass Class = ERoamRoadClass::Regional;
		int32 FirstPoint = 0;
		int32 NumPoints = 0;
		FVector2f BoundsMin = FVector2f::ZeroVector;
		FVector2f BoundsMax = FVector2f::ZeroVector;
	};

	/** Rebuilds the cache (no-op when the same network with the same road count is already cached). Returns true when it rebuilt. */
	bool Build(const URoamRoadNetwork* Network, float SimplifyToleranceM = 2.5f);
	void Clear();

	bool IsBuilt() const { return Polylines.Num() > 0; }
	const TArray<FPolyline>& GetPolylines() const { return Polylines; }
	const TArray<FVector2f>& GetPoints() const { return Points; }
	int32 GetNumSourceSamples() const { return NumSourceSamples; }
	const URoamRoadNetwork* GetSource() const { return Source.Get(); }

	/** Back-to-front painting order of the classes (index 0 is painted first). */
	static int32 DrawOrder(ERoamRoadClass Class);
	/** Line thickness in 1080p units. */
	static float Thickness(ERoamRoadClass Class);

private:
	TArray<FPolyline> Polylines;
	TArray<FVector2f> Points;
	TWeakObjectPtr<const URoamRoadNetwork> Source;
	int32 SourceRoads = -1;
	int32 NumSourceSamples = 0;
};

/**
 * Heading-up vector minimap (bottom-left, 264 px): dark glass disc, roads per class, GPS route and waypoint hooks, player arrow 18 percent
 * behind the centre, north marker, scale bar. The view radius grows from 350 m to 900 m with speed. Lines are clipped to the circle on
 * the CPU; per frame only the visible runs are transformed and emitted (no allocation besides Slate's own line payload copy).
 */
class SRoamMinimap : public SLeafWidget
{
public:
	SLATE_BEGIN_ARGS(SRoamMinimap) {}
	SLATE_END_ARGS()

	void Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI);

	/** Explicit network (tests, ui.testnetwork). Without it the widget uses URoamUISubsystem::ResolveRoadNetwork(). */
	void SetNetwork(const URoamRoadNetwork* Network);
	/** GPS route polyline in UE world cm (e.g. from URoamRoadNetwork::BuildRoutePolyline). */
	void SetRoute(const TArray<FVector>& WorldPointsCm);
	void ClearRoute();
	void SetWaypoint(const FVector& WorldCm);
	void ClearWaypoint();
	bool HasWaypoint() const { return bHasWaypoint; }

	/** Preview hook: draws from this pose instead of the player's vehicle (position cm, yaw degrees, speed km/h). */
	void SetViewOverride(const FVector& LocationCm, float YawDeg, float SpeedKmh);
	void ClearViewOverride() { bOverride = false; }

	const FRoamMinimapCache& GetCache() const { return Cache; }

	//~ Begin SWidget
	virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override;
	virtual int32 OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
		int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;
	virtual FVector2D ComputeDesiredSize(float LayoutScaleMultiplier) const override;
	//~ End SWidget

private:
	struct FFrame;
	void EmitPolyline(const FFrame& Frame, const FVector2f* Points, int32 Num, const FLinearColor& Color, float Thickness) const;

	TWeakObjectPtr<URoamUISubsystem> UI;
	FRoamMinimapCache Cache;
	TWeakObjectPtr<const URoamRoadNetwork> ExplicitNetwork;
	double NextNetworkCheck = 0.0;

	// Pose (metres: x north, y east).
	FVector2f PlayerM = FVector2f::ZeroVector;
	float YawDeg = 0.0f;
	float SpeedKmh = 0.0f;
	float ViewRadiusM = 350.0f;
	bool bHasPose = false;
	bool bOverride = false;
	FVector OverrideLocationCm = FVector::ZeroVector;
	float OverrideYaw = 0.0f;
	float OverrideSpeed = 0.0f;
	bool bShown = true;

	TArray<FVector2f> RouteM;
	bool bHasWaypoint = false;
	FVector2f WaypointM = FVector2f::ZeroVector;

	mutable TArray<FVector2f> RunScratch;
};
