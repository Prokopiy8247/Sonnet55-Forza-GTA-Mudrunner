// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/SRoamSpeedCluster.h"

#include "Engine/GameInstance.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamUIStyle.h"
#include "UI/RoamUISubsystem.h"
#include "Vehicle/RoamVehicle.h"

using namespace RoamUI;

namespace
{
	// Tacho arc geometry (local units inside the 480 x 200 cluster).
	const FVector2f ArcCenter(118.0f, 98.0f);
	constexpr float ArcRadiusMid = 85.0f;
	constexpr float ArcSegLength = 21.0f;
	constexpr float ArcSegThickness = 5.0f;
	constexpr float ArcStartDeg = 150.0f;
	constexpr float ArcSweepDeg = 240.0f;

	// Right block (speed digits, unit, lamps).
	constexpr float DigitRight = 462.0f;
	constexpr float DigitCell = 60.0f;
	constexpr float BlockLeft = 270.0f;
}

void SRoamSpeedCluster::Construct(const FArguments& InArgs, TWeakObjectPtr<URoamUISubsystem> InUI)
{
	UI = InUI;
	SetCanTick(true);
	SetVisibility(EVisibility::HitTestInvisible);
}

void SRoamSpeedCluster::SetTelemetryOverride(const FRoamVehicleTelemetry* InTelemetry, bool bInMph)
{
	bOverride = InTelemetry != nullptr;
	bOverrideMph = bInMph;
	if (InTelemetry)
	{
		Telemetry = *InTelemetry;
		bHasData = true;
	}
}

FVector2D SRoamSpeedCluster::ComputeDesiredSize(float) const
{
	return FVector2D(Layout::SpeedClusterW, Layout::SpeedClusterH);
}

void SRoamSpeedCluster::Tick(const FGeometry& AllottedGeometry, const double InCurrentTime, const float InDeltaTime)
{
	SLeafWidget::Tick(AllottedGeometry, InCurrentTime, InDeltaTime);
	Now = InCurrentTime;

	const URoamUISubsystem* Subsystem = UI.Get();
	const URoamSaveSubsystem* Save = (Subsystem && Subsystem->GetGameInstance()) ? Subsystem->GetGameInstance()->GetSubsystem<URoamSaveSubsystem>() : nullptr;
	bool bVisibleSetting = true;
	if (Save)
	{
		const FRoamPlayerSettings& Settings = Save->GetSettings();
		bVisibleSetting = Settings.bHudVisible && Settings.bShowSpeedometer;
		bMph = Settings.bUseMph;
		bManualGearbox = !Settings.Assists.bAutomaticGearbox;
	}
	if (bOverride)
	{
		bMph = bOverrideMph;
		bVisibleSetting = true;
	}
	else
	{
		const ARoamVehicle* Vehicle = Subsystem ? Subsystem->GetPlayerVehicle() : nullptr;
		bHasData = Vehicle != nullptr;
		if (Vehicle)
		{
			Telemetry = Vehicle->GetTelemetry();
		}
	}
	const bool bShow = bHasData && bVisibleSetting;
	SetVisibility(bShow ? EVisibility::HitTestInvisible : EVisibility::Collapsed);
	if (!bShow)
	{
		return;
	}

	const float Dt = FMath::Clamp(InDeltaTime, 0.0f, 0.1f);
	DisplayNormRpm = FMath::FInterpTo(DisplayNormRpm, Telemetry.NormRPM, Dt, 22.0f);
	DisplaySpeedKmh = FMath::FInterpTo(DisplaySpeedKmh, Telemetry.SpeedKmh, Dt, 16.0f);
	DisplayBoost = FMath::FInterpTo(DisplayBoost, Telemetry.Boost01, Dt, 10.0f);
	GForce = FMath::FInterpTo(GForce, FMath::Sqrt(Telemetry.LatG * Telemetry.LatG + Telemetry.LongG * Telemetry.LongG), Dt, 8.0f);

	const int32 NewSpeed = Logic::SpeedValue(DisplaySpeedKmh, bMph);
	if (NewSpeed != SpeedInt || SpeedText.IsEmpty())
	{
		SpeedInt = NewSpeed;
		SpeedText = FString::FromInt(NewSpeed);
	}
	GearTextCache = Logic::GearText(Telemetry.Gear);
	RpmText = FString::Printf(TEXT("%.1f"), Telemetry.RPM * 0.001f);
	GText = FString::Printf(TEXT("%.1fG"), GForce);
	SurfaceText = Roam::EnumToString(Telemetry.Surface).ToUpper();
}

int32 SRoamSpeedCluster::OnPaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
	int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const
{
	if (!bHasData)
	{
		return LayerId;
	}
	const FGeometry& G = AllottedGeometry;
	const int32 LBack = LayerId;
	const int32 LArc = LayerId + 1;
	const int32 LFront = LayerId + 2;

	// ---- glass panel
	DrawBox(OutDrawElements, LBack, G, FVector2f::ZeroVector, FVector2f(Layout::SpeedClusterW, Layout::SpeedClusterH), Brushes::Panel(), Color::Glass());

	// ---- tachometer arc (48 rotated boxes, no allocations)
	const bool bLimiter = Telemetry.bRedline || DisplayNormRpm >= 0.985f;
	const bool bFlashOn = FMath::Fmod(Now, 0.12) < 0.06; // ~8 Hz
	const int32 Lit = Logic::TachLitSegments(DisplayNormRpm);
	for (int32 i = 0; i < Layout::TachSegments; ++i)
	{
		const float Deg = Logic::TachSegmentAngleDeg(i, Layout::TachSegments, ArcStartDeg, ArcSweepDeg);
		const float Rad = FMath::DegreesToRadians(Deg);
		const FVector2f Center = ArcCenter + FVector2f(FMath::Cos(Rad), FMath::Sin(Rad)) * ArcRadiusMid;
		const Logic::ETachZone Zone = Logic::TachZoneOf(i);
		FLinearColor LitColor = Zone == Logic::ETachZone::Redline ? Color::Red() : (Zone == Logic::ETachZone::Warn ? Color::Amber() : Color::Teal());
		FLinearColor Tint;
		if (i < Lit)
		{
			Tint = (bLimiter && !bFlashOn) ? Color::WithAlpha(LitColor, 0.35f) : LitColor;
		}
		else
		{
			Tint = Zone == Logic::ETachZone::Redline ? FLinearColor(1.0f, 0.2f, 0.18f, 0.20f) : FLinearColor(1.0f, 1.0f, 1.0f, 0.10f);
		}
		// Segments grow slightly towards the redline.
		const float Grow = 1.0f + 0.35f * static_cast<float>(i) / static_cast<float>(Layout::TachSegments);
		DrawRotatedBox(OutDrawElements, LArc, G, Center, FVector2f(ArcSegLength * Grow, ArcSegThickness), Rad, Brushes::Flat(), Tint);
	}

	// ---- gear box
	const float GearBox = 72.0f;
	// frame = slightly larger rounded square under an opaque dark fill (outline brushes are not tinted by Slate)
	DrawBox(OutDrawElements, LArc, G, ArcCenter - FVector2f(GearBox, GearBox) * 0.5f, FVector2f(GearBox, GearBox), Brushes::Pill(),
		bLimiter ? Color::Red() : Color::WithAlpha(Color::Teal(), 0.75f));
	DrawBox(OutDrawElements, LArc + 0, G, ArcCenter - FVector2f(GearBox - 5.0f, GearBox - 5.0f) * 0.5f, FVector2f(GearBox - 5.0f, GearBox - 5.0f), Brushes::Pill(), FLinearColor(0.012f, 0.02f, 0.032f, 0.97f));
	const FLinearColor GearColor = Telemetry.Gear < 0 ? Color::Amber() : Color::Chalk();
	PaintText(OutDrawElements, LFront, G, ArcCenter + FVector2f(0.0f, -34.0f), GearTextCache, Font(58, true), GearColor, ETextAnchor::Center);

	// shift / limiter cue (manual gearbox: shift cue from 93 percent; limiter always)
	const bool bShiftCue = bManualGearbox && DisplayNormRpm >= 0.93f && !bLimiter && Telemetry.Gear > 0;
	if (bLimiter || bShiftCue)
	{
		const bool bOn = bLimiter ? bFlashOn : FMath::Fmod(Now, 0.30) < 0.18;
		const FLinearColor CueColor = bLimiter ? Color::Red() : Color::Amber();
		DrawBox(OutDrawElements, LArc, G, ArcCenter + FVector2f(-36.0f, -62.0f), FVector2f(72.0f, 22.0f), Brushes::Pill(), Color::WithAlpha(CueColor, bOn ? 0.95f : 0.25f));
		PaintText(OutDrawElements, LFront, G, ArcCenter + FVector2f(0.0f, -60.0f), bLimiter ? TEXT("LIMIT") : TEXT("SHIFT"), Font(16, true),
			FLinearColor(0.05f, 0.05f, 0.06f, bOn ? 1.0f : 0.5f), ETextAnchor::Center);
	}

	// rpm readout under the gear box
	PaintText(OutDrawElements, LFront, G, ArcCenter + FVector2f(0.0f, 41.0f), RpmText, Font(24, true), Color::Chalk(), ETextAnchor::Center);
	PaintText(OutDrawElements, LFront, G, ArcCenter + FVector2f(0.0f, 68.0f), TEXT("x1000 rpm"), Font(13), Color::Dim(), ETextAnchor::Center);

	// ---- speed digits (3 tabular cells, dim leading zeros)
	const int32 Zeros = Logic::LeadingZeroCells(SpeedInt);
	const FSlateFontInfo DigitFont = Font(104, true);
	for (int32 Cell = 0; Cell < 3; ++Cell) // 0 = hundreds
	{
		const float CenterX = DigitRight - DigitCell * (2.5f - static_cast<float>(Cell));
		const bool bLeadingZero = Cell < Zeros;
		const int32 DigitIndex = Cell - Zeros; // index into SpeedText for the real digits
		const FVector2f Pos(CenterX, -12.0f);
		if (bLeadingZero)
		{
			PaintText(OutDrawElements, LFront, G, Pos, TEXT("0"), DigitFont, FLinearColor(1.0f, 1.0f, 1.0f, 0.11f), ETextAnchor::Center);
		}
		else if (SpeedText.IsValidIndex(DigitIndex))
		{
			PaintText(OutDrawElements, LFront, G, Pos, SpeedText.Mid(DigitIndex, 1), DigitFont, Color::Chalk(), ETextAnchor::Center, true);
		}
	}
	PaintText(OutDrawElements, LFront, G, FVector2f(DigitRight, 112.0f), Logic::UnitLabel(bMph), Font(22, true), Color::Teal(), ETextAnchor::Right);

	// ---- surface indicator (left of the unit label)
	const FLinearColor SurfaceColor = Telemetry.Surface == ERoamSurface::Asphalt ? Color::Dim() : Color::Amber();
	DrawBox(OutDrawElements, LArc, G, FVector2f(BlockLeft, 123.0f), FVector2f(9.0f, 9.0f), Brushes::Disc(), SurfaceColor);
	PaintText(OutDrawElements, LFront, G, FVector2f(BlockLeft + 15.0f, 117.0f), SurfaceText, Font(14, true), SurfaceColor, ETextAnchor::Left);

	// ---- assist lamps + G-force chip (4 x 44 px, 4 px gaps)
	struct FLamp { const TCHAR* Label; bool bActive; };
	const FLamp Lamps[3] = { { TEXT("ABS"), Telemetry.bABSActive }, { TEXT("TCS"), Telemetry.bTCSActive }, { TEXT("STM"), Telemetry.bSTMActive } };
	const bool bBlink = FMath::Fmod(Now, 0.2) < 0.1;
	for (int32 i = 0; i < 3; ++i)
	{
		const FVector2f Pos(BlockLeft + 48.0f * static_cast<float>(i), 152.0f);
		const bool bOn = Lamps[i].bActive && bBlink;
		DrawBox(OutDrawElements, LArc, G, Pos, FVector2f(44.0f, 24.0f), Brushes::Pill(), bOn ? Color::WithAlpha(Color::Amber(), 0.95f) : FLinearColor(1.0f, 1.0f, 1.0f, 0.09f));
		PaintText(OutDrawElements, LFront, G, Pos + FVector2f(22.0f, 3.5f), Lamps[i].Label, Font(15, true),
			bOn ? FLinearColor(0.05f, 0.05f, 0.06f, 1.0f) : Color::WithAlpha(Color::Dim(), 0.7f), ETextAnchor::Center);
	}
	{
		const FVector2f Pos(BlockLeft + 48.0f * 3.0f, 152.0f);
		DrawBox(OutDrawElements, LArc, G, Pos, FVector2f(DigitRight - Pos.X, 24.0f), Brushes::Pill(), FLinearColor(0.133f, 0.827f, 0.933f, 0.16f));
		PaintText(OutDrawElements, LFront, G, Pos + FVector2f((DigitRight - Pos.X) * 0.5f, 3.5f), GText, Font(15, true), Color::Chalk(), ETextAnchor::Center);
	}

	// ---- boost gauge
	if (Telemetry.bTurbo)
	{
		const float Width = 192.0f;
		const FVector2f Pos(BlockLeft, 186.0f);
		DrawBox(OutDrawElements, LArc, G, Pos, FVector2f(Width, 5.0f), Brushes::Pill(), FLinearColor(1.0f, 1.0f, 1.0f, 0.10f));
		DrawBox(OutDrawElements, LArc, G, Pos, FVector2f(FMath::Max(5.0f, Width * FMath::Clamp(DisplayBoost, 0.0f, 1.0f)), 5.0f), Brushes::Pill(),
			Color::Lerp(Color::Teal(), Color::Orange(), DisplayBoost));
	}

	return LFront + 2;
}
