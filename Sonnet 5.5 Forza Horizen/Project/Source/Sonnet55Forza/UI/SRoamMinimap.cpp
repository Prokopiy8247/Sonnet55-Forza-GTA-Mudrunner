// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/SRoamMinimap.h"

#include "Data/RoamRoadNetwork.h"
#include "Engine/GameInstance.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUIStyle.h"
#include "UI/RoamUISubsystem.h"
#include "Vehicle/RoamVehicle.h"

using namespace RoamUI;

// ======================================================================================================================
// FRoamMinimapCache
// ======================================================================================================================

int32 FRoamMinimapCache::DrawOrder(ERoamRoadClass Class)
{
	switch (Class)
	{
	case ERoamRoadClass::Shortcut: return 0;
	case ERoamRoadClass::Dirt: return 1;
	case ERoamRoadClass::Village: return 2;
	case ERoamRoadClass::Mountain: return 3;
	case ERoamRoadClass::Regional: return 4;
	case ERoamRoadClass::Highway: return 5;
	default: return 4;
	}
}

float FRoamMinimapCache::Thickness(ERoamRoadClass Class)
{
	switch (Class)
	{
	case ERoamRoadClass::Highway: return 5.5f;
	case ERoamRoadClass::Regional: return 4.0f;
	case ERoamRoadClass::Mountain: return 3.5f;
	case ERoamRoadClass::Village: return 3.0f;
	case ERoamRoadClass::Dirt: return 2.5f;
	case ERoamRoadClass::Shortcut: return 2.0f;
	default: return 3.0f;
	}
}

void FRoamMinimapCache::Clear()
{
	Polylines.Reset();
	Points.Reset();
	Source.Reset();
	SourceRoads = -1;
	NumSourceSamples = 0;
}

bool FRoamMinimapCache::Build(const URoamRoadNetwork* Network, float SimplifyToleranceM)
{
	if (!Network)
	{
		const bool bHadData = IsBuilt();
		Clear();
		return bHadData;
	}
	if (Source.Get() == Network && SourceRoads == Network->Roads.Num() && IsBuilt())
	{
		return false;
	}
	Clear();
	Source = Network;
	SourceRoads = Network->Roads.Num();

	struct FTemp
	{
		FPolyline Line;
		TArray<FVector2f> Pts;
	};
	TArray<FTemp> Temps;
	Temps.Reserve(Network->Roads.Num());
	TArray<FVector2f> Raw;
	for (const FRoamRoad& Road : Network->Roads)
	{
		if (Road.Samples.Num() < 2)
		{
			continue;
		}
		Raw.Reset();
		Raw.Reserve(Road.Samples.Num());
		for (const FRoamRoadSample& Sample : Road.Samples)
		{
			Raw.Add(FVector2f(static_cast<float>(Sample.Position.X) * 0.01f, static_cast<float>(Sample.Position.Y) * 0.01f));
		}
		NumSourceSamples += Raw.Num();
		FTemp& Temp = Temps.AddDefaulted_GetRef();
		Temp.Line.Class = Road.RoadClass;
		Logic::SimplifyPolyline(Raw, SimplifyToleranceM, Temp.Pts);
		Temp.Line.BoundsMin = Temp.Pts[0];
		Temp.Line.BoundsMax = Temp.Pts[0];
		for (const FVector2f& P : Temp.Pts)
		{
			Temp.Line.BoundsMin.X = FMath::Min(Temp.Line.BoundsMin.X, P.X);
			Temp.Line.BoundsMin.Y = FMath::Min(Temp.Line.BoundsMin.Y, P.Y);
			Temp.Line.BoundsMax.X = FMath::Max(Temp.Line.BoundsMax.X, P.X);
			Temp.Line.BoundsMax.Y = FMath::Max(Temp.Line.BoundsMax.Y, P.Y);
		}
	}
	Temps.StableSort([](const FTemp& A, const FTemp& B) { return DrawOrder(A.Line.Class) < DrawOrder(B.Line.Class); });
	for (FTemp& Temp : Temps)
	{
		Temp.Line.FirstPoint = Points.Num();
		Temp.Line.NumPoints = Temp.Pts.Num();
		Points.Append(Temp.Pts);
		Polylines.Add(Temp.Line);
	}
	return true;
}

// ======================================================================================================================
// SRoamMinimap
// ======================================================================================================================

struct SRoamMinimap::FFrame
{
	const FGeometry* G = nullptr;
	FSlateWindowElementList* Out = nullptr;
	int32 Layer = 0;
	FVector2f Centre = FVector2f::ZeroVector; // local
	float ClipRadius = 0.0f;                  // px
	FVector2f PlayerM = FVector2f::ZeroVector;
	float YawDeg = 0.0f;
	float PxPerM = 1.0f;
	FVector2f PlayerRel = FVector2f::ZeroVector; // px relative to the circle centre
};

void SRoamMinimap::Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI)
{
	UI = InUI;
	SetCanTick(true);
	SetVisibility(EVisibility::HitTestInvisible);
}

FVector2D SRoamMinimap::ComputeDesiredSize(float) const
{
	return FVector2D(Layout::MinimapSize, Layout::MinimapSize);
}

void SRoamMinimap::SetNetwork(const URoamRoadNetwork* Network)
{
	ExplicitNetwork = Network;
	Cache.Build(Network);
}

void SRoamMinimap::SetRoute(const TArray<FVector>& WorldPointsCm)
{
	RouteM.Reset();
	RouteM.Reserve(WorldPointsCm.Num());
	for (const FVector& P : WorldPointsCm)
	{
		RouteM.Add(FVector2f(static_cast<float>(P.X) * 0.01f, static_cast<float>(P.Y) * 0.01f));
	}
}

void SRoamMinimap::ClearRoute()
{
	RouteM.Reset();
}

void SRoamMinimap::SetWaypoint(const FVector& WorldCm)
{
	bHasWaypoint = true;
	WaypointM = FVector2f(static_cast<float>(WorldCm.X) * 0.01f, static_cast<float>(WorldCm.Y) * 0.01f);
}

void SRoamMinimap::ClearWaypoint()
{
	bHasWaypoint = false;
}

void SRoamMinimap::SetViewOverride(const FVector& LocationCm, float InYawDeg, float InSpeedKmh)
{
	bOverride = true;
	OverrideLocationCm = LocationCm;
	OverrideYaw = InYawDeg;
	OverrideSpeed = InSpeedKmh;
}

void SRoamMinimap::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SLeafWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	const URoamUISubsystem* Subsystem = UI.Get();

	// Visibility toggle from the profile.
	bool bVisibleSetting = true;
	if (const URoamSaveSubsystem* Save = (Subsystem && Subsystem->GetGameInstance()) ? Subsystem->GetGameInstance()->GetSubsystem<URoamSaveSubsystem>() : nullptr)
	{
		bVisibleSetting = Save->GetSettings().bHudVisible && Save->GetSettings().bShowMinimap;
	}

	// Network (re-resolved once per second: the data asset may load late, ui.testnetwork may flip it).
	if (!ExplicitNetwork.IsValid() && InCurrentTime >= NextNetworkCheck)
	{
		NextNetworkCheck = InCurrentTime + 1.0;
		Cache.Build(Subsystem ? Subsystem->ResolveRoadNetwork() : nullptr);
	}

	// Pose.
	float TargetYaw = YawDeg;
	float Speed = SpeedKmh;
	bool bPose = false;
	if (bOverride)
	{
		PlayerM = FVector2f(static_cast<float>(OverrideLocationCm.X) * 0.01f, static_cast<float>(OverrideLocationCm.Y) * 0.01f);
		TargetYaw = OverrideYaw;
		Speed = OverrideSpeed;
		bPose = true;
	}
	else if (const ARoamVehicle* Vehicle = Subsystem ? Subsystem->GetPlayerVehicle() : nullptr)
	{
		const FVector Location = Vehicle->GetActorLocation();
		PlayerM = FVector2f(static_cast<float>(Location.X) * 0.01f, static_cast<float>(Location.Y) * 0.01f);
		const FVector Forward = Vehicle->GetTelemetry().ForwardAxis;
		if (FMath::Abs(Forward.X) + FMath::Abs(Forward.Y) > 0.01)
		{
			TargetYaw = FMath::RadiansToDegrees(FMath::Atan2(static_cast<float>(Forward.Y), static_cast<float>(Forward.X)));
		}
		Speed = Vehicle->GetTelemetry().SpeedKmh;
		bPose = true;
	}
	bHasPose = bPose;
	bShown = bPose && bVisibleSetting;
	SetVisibility(bShown ? EVisibility::HitTestInvisible : EVisibility::Collapsed);
	if (!bShown)
	{
		return;
	}

	const float Dt = FMath::Clamp(InDeltaTime, 0.0f, 0.1f);
	if (bOverride)
	{
		YawDeg = TargetYaw;
		SpeedKmh = Speed;
	}
	else
	{
		YawDeg += FMath::FindDeltaAngleDegrees(YawDeg, TargetYaw) * FMath::Clamp(Dt * 14.0f, 0.0f, 1.0f);
		SpeedKmh = FMath::FInterpTo(SpeedKmh, Speed, Dt, 4.0f);
	}
	ViewRadiusM = FMath::FInterpTo(ViewRadiusM, Logic::MinimapViewRadiusM(SpeedKmh), Dt, 1.6f);
}

void SRoamMinimap::EmitPolyline(const FFrame& F, const FVector2f* Pts, int32 Num, const FLinearColor& Color, float Thickness) const
{
	if (Num < 2)
	{
		return;
	}
	RunScratch.Reset();
	FVector2f PrevRel = FVector2f::ZeroVector;
	bool bHavePrev = false;
	const auto Flush = [&]()
	{
		if (RunScratch.Num() >= 2)
		{
			FSlateDrawElement::MakeLines(*F.Out, F.Layer, F.G->ToPaintGeometry(), RunScratch, ESlateDrawEffect::None, Color, true, Thickness);
		}
		RunScratch.Reset();
	};
	for (int32 i = 0; i < Num; ++i)
	{
		const FVector2f Rel = Logic::WorldDeltaToMapOffset(Pts[i] - F.PlayerM, F.YawDeg) * F.PxPerM + F.PlayerRel;
		if (bHavePrev)
		{
			float T0 = 0.0f;
			float T1 = 1.0f;
			if (Logic::ClipSegmentToCircle(PrevRel, Rel, F.ClipRadius, T0, T1))
			{
				if (RunScratch.Num() == 0 || T0 > 0.0f)
				{
					Flush();
					RunScratch.Add(F.Centre + PrevRel + (Rel - PrevRel) * T0);
				}
				RunScratch.Add(F.Centre + PrevRel + (Rel - PrevRel) * T1);
				if (T1 < 1.0f)
				{
					Flush();
				}
			}
			else
			{
				Flush();
			}
		}
		PrevRel = Rel;
		bHavePrev = true;
	}
	Flush();
}

int32 SRoamMinimap::OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
	int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const
{
	if (!bShown)
	{
		return LayerId;
	}
	const FGeometry& G = AllottedGeometry;
	const FVector2f Size = G.GetLocalSize();
	const float Diameter = FMath::Min(Size.X, Size.Y);
	const float Radius = Diameter * 0.5f - 2.0f;
	const FVector2f Centre = Size * 0.5f;

	const int32 LBack = LayerId;
	const int32 LRoads = LayerId + 4; // LayerId .. +3: shadow, rim, fill, range rings
	const int32 LRoute = LayerId + 5;
	const int32 LFront = LayerId + 6;
	const int32 LTop = LayerId + 7;

	// ---- disc + soft outer shadow
	// (Outline brushes are avoided on purpose: Slate does not tint their outline, so the ring is a slightly larger disc under the fill.)
	DrawBox(OutDrawElements, LBack + 0, G, Centre - FVector2f(Radius + 6.0f, Radius + 6.0f), FVector2f(Radius + 6.0f, Radius + 6.0f) * 2.0f, Brushes::Disc(), FLinearColor(0.0f, 0.0f, 0.0f, 0.22f));
	DrawBox(OutDrawElements, LBack + 1, G, Centre - FVector2f(Radius, Radius), FVector2f(Radius, Radius) * 2.0f, Brushes::Disc(), FLinearColor(0.95f, 0.97f, 1.0f, 0.55f));
	DrawBox(OutDrawElements, LBack + 2, G, Centre - FVector2f(Radius - 3.0f, Radius - 3.0f), FVector2f(Radius - 3.0f, Radius - 3.0f) * 2.0f, Brushes::Disc(), FLinearColor(0.006f, 0.010f, 0.018f, 0.96f));

	FFrame F;
	F.G = &G;
	F.Out = &OutDrawElements;
	F.Centre = Centre;
	F.ClipRadius = Radius - 1.5f;
	F.PlayerM = PlayerM;
	F.YawDeg = YawDeg;
	F.PxPerM = Radius / FMath::Max(50.0f, ViewRadiusM);
	F.PlayerRel = FVector2f(0.0f, Logic::MinimapPlayerBackFraction * Radius);

	// ---- faint range rings (every third of the radius) for scale feel
	for (int32 Ring = 1; Ring <= 2; ++Ring)
	{
		const float RR = Radius * static_cast<float>(Ring) / 3.0f;
		RunScratch.Reset();
		for (int32 i = 0; i <= 48; ++i)
		{
			const float A = static_cast<float>(i) * (UE_TWO_PI / 48.0f);
			RunScratch.Add(Centre + FVector2f(FMath::Cos(A), FMath::Sin(A)) * RR);
		}
		FSlateDrawElement::MakeLines(OutDrawElements, LBack + 3, G.ToPaintGeometry(), RunScratch, ESlateDrawEffect::None, FLinearColor(1.0f, 1.0f, 1.0f, 0.07f), true, 1.5f);
	}
	RunScratch.Reset();

	// ---- roads (back to front by class)
	F.Layer = LRoads;
	{
		const float CullDistM = ViewRadiusM * (1.0f + Logic::MinimapPlayerBackFraction) + 40.0f;
		const FVector2f* Pts = Cache.GetPoints().GetData();
		for (const FRoamMinimapCache::FPolyline& Line : Cache.GetPolylines())
		{
			const float Dx = FMath::Max3(Line.BoundsMin.X - PlayerM.X, 0.0f, PlayerM.X - Line.BoundsMax.X);
			const float Dy = FMath::Max3(Line.BoundsMin.Y - PlayerM.Y, 0.0f, PlayerM.Y - Line.BoundsMax.Y);
			if (Dx * Dx + Dy * Dy > CullDistM * CullDistM)
			{
				continue;
			}
			EmitPolyline(F, Pts + Line.FirstPoint, Line.NumPoints, Color::Road(Line.Class), FRoamMinimapCache::Thickness(Line.Class));
		}
	}

	// ---- GPS route
	if (RouteM.Num() >= 2)
	{
		F.Layer = LRoute;
		EmitPolyline(F, RouteM.GetData(), RouteM.Num(), Color::Teal(), 6.0f);
	}

	// ---- waypoint
	if (bHasWaypoint)
	{
		const FVector2f Rel = Logic::WorldDeltaToMapOffset(WaypointM - PlayerM, YawDeg) * F.PxPerM + F.PlayerRel;
		bool bClamped = false;
		const FVector2f Marker = Logic::ClampToCircle(Rel, Radius - 10.0f, &bClamped);
		const float S = bClamped ? 11.0f : 15.0f;
		DrawRotatedBox(OutDrawElements, LFront, G, Centre + Marker, FVector2f(S, S), FMath::DegreesToRadians(45.0f), Brushes::Flat(), FLinearColor(0.02f, 0.02f, 0.03f, 0.9f));
		DrawRotatedBox(OutDrawElements, LTop, G, Centre + Marker, FVector2f(S - 4.0f, S - 4.0f), FMath::DegreesToRadians(45.0f), Brushes::Flat(), Color::Orange());
	}

	// ---- north marker on the rim
	{
		const FVector2f North = Logic::NorthOnMap(YawDeg);
		const FVector2f P = Centre + North * (Radius - 13.0f);
		DrawBox(OutDrawElements, LFront, G, P - FVector2f(11.0f, 11.0f), FVector2f(22.0f, 22.0f), Brushes::Disc(), FLinearColor(0.02f, 0.03f, 0.04f, 0.92f));
		PaintText(OutDrawElements, LTop, G, P + FVector2f(0.0f, -9.0f), TEXT("N"), Font(14, true), Color::Orange(), ETextAnchor::Center);
	}

	// ---- scale bar
	{
		static const float Nice[] = { 25.0f, 50.0f, 100.0f, 200.0f, 250.0f, 500.0f, 1000.0f };
		float Metres = Nice[0];
		for (const float Candidate : Nice)
		{
			if (Candidate * F.PxPerM <= 72.0f)
			{
				Metres = Candidate;
			}
		}
		const float Px = Metres * F.PxPerM;
		const FVector2f Origin = Centre + FVector2f(-Px * 0.5f, Radius * 0.64f);
		DrawBox(OutDrawElements, LFront, G, Origin, FVector2f(Px, 2.0f), Brushes::Flat(), FLinearColor(1.0f, 1.0f, 1.0f, 0.75f));
		DrawBox(OutDrawElements, LFront, G, Origin + FVector2f(0.0f, -3.0f), FVector2f(2.0f, 8.0f), Brushes::Flat(), FLinearColor(1.0f, 1.0f, 1.0f, 0.75f));
		DrawBox(OutDrawElements, LFront, G, Origin + FVector2f(Px - 2.0f, -3.0f), FVector2f(2.0f, 8.0f), Brushes::Flat(), FLinearColor(1.0f, 1.0f, 1.0f, 0.75f));
		const FString Label = Metres >= 1000.0f ? FString::Printf(TEXT("%.0f km"), Metres / 1000.0f) : FString::Printf(TEXT("%.0f m"), Metres);
		PaintText(OutDrawElements, LTop, G, Centre + FVector2f(0.0f, Radius * 0.64f + 7.0f), Label, Font(13, true), Color::Dim(), ETextAnchor::Center);
	}

	// ---- player arrow (always pointing up in a heading-up map)
	{
		const FVector2f P = Centre + F.PlayerRel;
		static thread_local TArray<FVector2f> Arrow;
		Arrow.Reset();
		const auto MakeArrow = [&](float Scale)
		{
			Arrow.Reset();
			Arrow.Add(P + FVector2f(0.0f, -15.0f) * Scale);
			Arrow.Add(P + FVector2f(-10.5f, 11.0f) * Scale);
			Arrow.Add(P + FVector2f(0.0f, 5.0f) * Scale);
			Arrow.Add(P + FVector2f(10.5f, 11.0f) * Scale);
		};
		MakeArrow(1.35f);
		DrawPolygon(OutDrawElements, LFront, G, Arrow, FLinearColor(0.0f, 0.0f, 0.0f, 0.7f));
		MakeArrow(1.0f);
		DrawPolygon(OutDrawElements, LTop, G, Arrow, Color::Chalk());
	}

	return LTop + 2;
}
