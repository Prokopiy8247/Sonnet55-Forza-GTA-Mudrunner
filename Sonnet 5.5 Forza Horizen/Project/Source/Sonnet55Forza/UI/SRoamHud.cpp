// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/SRoamHud.h"

#include "Data/RoamRoadNetwork.h"
#include "Engine/GameInstance.h"
#include "Engine/World.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUISubsystem.h"
#include "UI/SRoamMinimap.h"
#include "UI/SRoamNotifications.h"
#include "UI/SRoamSpeedCluster.h"
#include "Vehicle/RoamVehicle.h"
#include "Widgets/SLeafWidget.h"
#include "Widgets/SOverlay.h"
#include "World/RoamTimeWeatherSubsystem.h"

using namespace RoamUI;

namespace
{
	// =====================================================================================================================
	// SRoamHudInfo: world strip, camera chip, fps counter, wrong-way hint
	// =====================================================================================================================
	class SRoamHudInfo : public SLeafWidget
	{
	public:
		SLATE_BEGIN_ARGS(SRoamHudInfo) {}
		SLATE_END_ARGS()

		void Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI)
		{
			UI = InUI;
			SetCanTick(true);
			SetVisibility(EVisibility::HitTestInvisible);
		}

		virtual FVector2D ComputeDesiredSize(float) const override { return FVector2D::ZeroVector; }

		virtual void Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime) override
		{
			SLeafWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
			Now = FPlatformTime::Seconds();
			const URoamUISubsystem* Subsystem = UI.Get();
			const UGameInstance* GameInstance = Subsystem ? Subsystem->GetGameInstance() : nullptr;
			const UWorld* World = GameInstance ? GameInstance->GetWorld() : nullptr;

			if (const URoamSaveSubsystem* Save = GameInstance ? GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr)
			{
				const FRoamPlayerSettings& Settings = Save->GetSettings();
				bHudVisible = Settings.bHudVisible;
				bShowFps = Settings.bShowFps;
				bMph = Settings.bUseMph;
			}
			SetVisibility(bHudVisible ? EVisibility::HitTestInvisible : EVisibility::Collapsed);

			// fps (smoothed, text refreshed 4x per second)
			SmoothedDt = FMath::Lerp(SmoothedDt, FMath::Clamp(InDeltaTime, 0.0001f, 0.5f), 0.08f);
			if (Now >= NextTextRefresh)
			{
				NextTextRefresh = Now + 0.25;
				FpsText = FString::Printf(TEXT("%.0f FPS   %.1f ms"), 1.0f / SmoothedDt, SmoothedDt * 1000.0f);
				if (const URoamTimeWeatherSubsystem* TimeWeather = World ? World->GetSubsystem<URoamTimeWeatherSubsystem>() : nullptr)
				{
					bHasWorld = true;
					TimeText = TimeWeather->GetTimeString();
					Weather = TimeWeather->GetWeather();
					bNight = TimeWeather->IsNight();
					const float Day = TimeWeather->GetDaylight01();
					float TempC = 8.0f + 14.0f * Day;
					switch (Weather)
					{
					case ERoamWeather::Cloudy: TempC -= 1.5f; break;
					case ERoamWeather::Rain: TempC -= 3.5f; break;
					case ERoamWeather::Fog: TempC -= 2.0f; break;
					case ERoamWeather::Storm: TempC -= 5.5f; break;
					default: break;
					}
					TempText = bMph ? FString::Printf(TEXT("%d°F"), FMath::RoundToInt(TempC * 1.8f + 32.0f)) : FString::Printf(TEXT("%d°C"), FMath::RoundToInt(TempC));
					WeatherText = Roam::EnumToString(Weather).ToUpper();
				}
			}

			// camera chip + wrong way
			const ARoamVehicle* Vehicle = Subsystem ? Subsystem->GetPlayerVehicle() : nullptr;
			if (Vehicle)
			{
				const ERoamCameraMode Mode = Vehicle->GetCameraMode();
				if (!bHaveCamera || Mode != CameraMode)
				{
					CameraMode = Mode;
					CameraText = Roam::EnumToString(Mode).ToUpper();
					CameraChangedAt = bHaveCamera ? Now : -100.0;
					bHaveCamera = true;
				}
				if (Now >= NextRoadCheck)
				{
					NextRoadCheck = Now + 0.2;
					bool bWrong = false;
					const URoamRoadNetwork* Network = Subsystem->ResolveRoadNetwork();
					const FRoamVehicleTelemetry& T = Vehicle->GetTelemetry();
					if (Network && T.SpeedKmh > 25.0f && T.NumWheelsOnGround > 0)
					{
						FRoamRoadHit Hit;
						if (Network->FindNearestRoad(Vehicle->GetActorLocation(), Hit, 0xFF, 1200.0f) && Hit.DistanceCm < Hit.WidthCm * 0.6f + 200.0f)
						{
							const float Dot = static_cast<float>(FVector::DotProduct(T.ForwardAxis, Hit.Tangent));
							const bool bOneWay = Network->Roads.IsValidIndex(Hit.RoadIndex) && Network->Roads[Hit.RoadIndex].bOneWay;
							bWrong = Logic::IsWrongWay(Dot, Hit.LateralCm, bOneWay, T.SpeedKmh);
						}
					}
					if (bWrong)
					{
						WrongWaySince = WrongWaySince < 0.0 ? Now : WrongWaySince;
					}
					else
					{
						WrongWaySince = -1.0;
					}
				}
			}
			else
			{
				WrongWaySince = -1.0;
			}
		}

		virtual int32 OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
			int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override
		{
			const FGeometry& G = AllottedGeometry;
			const FVector2f View = G.GetLocalSize();
			const Logic::FSafeArea Safe = Logic::ComputeSafeArea(View);
			int32 Layer = LayerId;

			// ---- world strip above the minimap
			if (bHasWorld)
			{
				const FVector2f Size(Layout::MinimapSize, 38.0f);
				const FVector2f Origin(Safe.Left, View.Y - Safe.Bottom - Layout::MinimapSize - 10.0f - Size.Y);
				DrawBox(OutDrawElements, Layer, G, Origin, Size, Brushes::Panel(), Color::Glass());
				PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(14.0f, 4.0f), TimeText, Font(23, true), Color::Chalk());
				PaintWeatherIcon(OutDrawElements, Layer + 1, G, Origin + FVector2f(112.0f, 19.0f));
				PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(130.0f, 12.0f), WeatherText, Font(13, true), Color::Dim());
				PaintText(OutDrawElements, Layer + 2, G, Origin + FVector2f(Size.X - 12.0f, 6.0f), TempText, Font(20, true), Color::Teal(), ETextAnchor::Right);
			}
			Layer += 4;

			// ---- camera chip (top-right, fades after 3 s)
			{
				const float Age = static_cast<float>(Now - CameraChangedAt);
				if (Age < 3.0f && !CameraText.IsEmpty())
				{
					const float A = Age < 2.4f ? 1.0f : 1.0f - (Age - 2.4f) / 0.6f;
					const FSlateFontInfo F = Font(20, true);
					const float W = 28.0f + 70.0f + MeasureText(CameraText, F).X;
					const FVector2f Origin(View.X - Safe.Right - W, Safe.Top);
					DrawBox(OutDrawElements, Layer, G, Origin, FVector2f(W, 38.0f), Brushes::Panel(), Color::WithAlpha(Color::Glass(), A));
					PaintText(OutDrawElements, Layer + 1, G, Origin + FVector2f(16.0f, 9.0f), TEXT("CAMERA"), Font(15, true), Color::WithAlpha(Color::Dim(), A));
					PaintText(OutDrawElements, Layer + 1, G, Origin + FVector2f(16.0f + 74.0f, 6.0f), CameraText, F, Color::WithAlpha(Color::Orange(), A));
				}
				Layer += 3;
			}

			// ---- fps (under the region popup area)
			if (bShowFps)
			{
				DrawBox(OutDrawElements, Layer, G, FVector2f(Safe.Left, Safe.Top + 100.0f), FVector2f(210.0f, 32.0f), Brushes::Pill(), FLinearColor(0.0f, 0.0f, 0.0f, 0.5f));
				PaintText(OutDrawElements, Layer + 1, G, FVector2f(Safe.Left + 12.0f, Safe.Top + 104.0f), FpsText, Font(17, true), Color::Chalk());
				Layer += 3;
			}

			// ---- wrong way
			if (WrongWaySince >= 0.0 && Now - WrongWaySince > 1.0)
			{
				const bool bOn = FMath::Fmod(Now, 0.8) < 0.5;
				const FVector2f Size(300.0f, 54.0f);
				const FVector2f Origin((View.X - Size.X) * 0.5f, View.Y * 0.30f);
				DrawBox(OutDrawElements, Layer, G, Origin, Size, Brushes::Panel(), FLinearColor(0.55f, 0.04f, 0.04f, bOn ? 0.9f : 0.45f));
				PaintText(OutDrawElements, Layer + 1, G, Origin + FVector2f(Size.X * 0.5f, 7.0f), TEXT("WRONG WAY"), Font(32, true), FLinearColor(1.0f, 1.0f, 1.0f, bOn ? 1.0f : 0.6f), ETextAnchor::Center);
				Layer += 3;
			}
			return Layer + 1;
		}

	private:
		void PaintWeatherIcon(FSlateWindowElementList& Out, int32 Layer, const FGeometry& G, const FVector2f& C) const
		{
			const FLinearColor CloudColor(0.86f, 0.89f, 0.93f, 1.0f);
			const auto Cloud = [&](const FLinearColor& Tint)
			{
				DrawBox(Out, Layer, G, C + FVector2f(-12.0f, -2.0f), FVector2f(24.0f, 10.0f), Brushes::Pill(), Tint);
				DrawBox(Out, Layer, G, C + FVector2f(-8.0f, -9.0f), FVector2f(12.0f, 12.0f), Brushes::Disc(), Tint);
				DrawBox(Out, Layer, G, C + FVector2f(-1.0f, -12.0f), FVector2f(14.0f, 14.0f), Brushes::Disc(), Tint);
			};
			switch (Weather)
			{
			case ERoamWeather::Clear:
				if (bNight)
				{
					DrawBox(Out, Layer, G, C + FVector2f(-8.0f, -8.0f), FVector2f(16.0f, 16.0f), Brushes::Disc(), Color::Chalk());
					DrawBox(Out, Layer + 1, G, C + FVector2f(-3.0f, -11.0f), FVector2f(14.0f, 14.0f), Brushes::Disc(), FLinearColor(0.075f, 0.09f, 0.115f, 1.0f));
				}
				else
				{
					DrawBox(Out, Layer, G, C + FVector2f(-6.5f, -6.5f), FVector2f(13.0f, 13.0f), Brushes::Disc(), Color::Amber());
					for (int32 i = 0; i < 8; ++i)
					{
						const float Rad = FMath::DegreesToRadians(45.0f * static_cast<float>(i));
						DrawRotatedBox(Out, Layer, G, C + FVector2f(FMath::Cos(Rad), FMath::Sin(Rad)) * 11.5f, FVector2f(5.0f, 2.2f), Rad, Brushes::Flat(), Color::Amber());
					}
				}
				break;
			case ERoamWeather::Cloudy:
				Cloud(CloudColor);
				break;
			case ERoamWeather::Rain:
			case ERoamWeather::Storm:
				Cloud(Weather == ERoamWeather::Storm ? FLinearColor(0.55f, 0.58f, 0.66f, 1.0f) : CloudColor);
				if (Weather == ERoamWeather::Storm)
				{
					static thread_local TArray<FVector2f> Bolt;
					Bolt.Reset();
					Bolt.Add(C + FVector2f(2.0f, 3.0f));
					Bolt.Add(C + FVector2f(-4.0f, 11.0f));
					Bolt.Add(C + FVector2f(0.0f, 10.0f));
					Bolt.Add(C + FVector2f(-2.0f, 17.0f));
					Bolt.Add(C + FVector2f(6.0f, 8.0f));
					Bolt.Add(C + FVector2f(2.0f, 8.5f));
					DrawPolygon(Out, Layer + 1, G, Bolt, Color::Amber());
				}
				else
				{
					for (int32 i = 0; i < 3; ++i)
					{
						DrawRotatedBox(Out, Layer + 1, G, C + FVector2f(-7.0f + 7.0f * static_cast<float>(i), 13.0f), FVector2f(2.0f, 6.0f), FMath::DegreesToRadians(20.0f), Brushes::Flat(), Color::Teal());
					}
				}
				break;
			case ERoamWeather::Fog:
				DrawBox(Out, Layer, G, C + FVector2f(-12.0f, -9.0f), FVector2f(24.0f, 3.5f), Brushes::Pill(), CloudColor);
				DrawBox(Out, Layer, G, C + FVector2f(-9.0f, -2.0f), FVector2f(24.0f, 3.5f), Brushes::Pill(), CloudColor);
				DrawBox(Out, Layer, G, C + FVector2f(-12.0f, 5.0f), FVector2f(18.0f, 3.5f), Brushes::Pill(), CloudColor);
				break;
			default:
				break;
			}
		}

		TWeakObjectPtr<URoamUISubsystem> UI;
		double Now = 0.0;
		double NextTextRefresh = 0.0;
		double NextRoadCheck = 0.0;
		float SmoothedDt = 0.016f;
		bool bHudVisible = true;
		bool bShowFps = false;
		bool bMph = false;
		bool bHasWorld = false;
		bool bNight = false;
		ERoamWeather Weather = ERoamWeather::Clear;
		FString FpsText;
		FString TimeText;
		FString TempText;
		FString WeatherText;
		FString CameraText;
		ERoamCameraMode CameraMode = ERoamCameraMode::Chase;
		bool bHaveCamera = false;
		double CameraChangedAt = -100.0;
		double WrongWaySince = -1.0;
	};
}

// =========================================================================================================================
// SRoamHud
// =========================================================================================================================

void SRoamHud::Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI)
{
	UI = InUI;
	SetCanTick(true);
	SetVisibility(EVisibility::SelfHitTestInvisible);

	ChildSlot
	[
		SNew(SOverlay)
		+ SOverlay::Slot().HAlign(HAlign_Right).VAlign(VAlign_Bottom).Padding(TAttribute<FMargin>::CreateSP(this, &SRoamHud::GetClusterPadding))
		[
			SAssignNew(SpeedCluster, SRoamSpeedCluster, InUI)
		]
		+ SOverlay::Slot().HAlign(HAlign_Left).VAlign(VAlign_Bottom).Padding(TAttribute<FMargin>::CreateSP(this, &SRoamHud::GetMinimapPadding))
		[
			SAssignNew(Minimap, SRoamMinimap, InUI)
		]
		+ SOverlay::Slot()
		[
			SNew(SRoamHudInfo, InUI)
		]
		+ SOverlay::Slot()
		[
			SAssignNew(Notifications, SRoamNotifications, InUI)
		]
	];
}

void SRoamHud::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SCompoundWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	Safe = Logic::ComputeSafeArea(AllottedGeometry.GetLocalSize());
}

FMargin SRoamHud::GetClusterPadding() const
{
	return FMargin(0.0f, 0.0f, Safe.Right, Safe.Bottom);
}

FMargin SRoamHud::GetMinimapPadding() const
{
	return FMargin(Safe.Left, 0.0f, 0.0f, Safe.Bottom);
}
