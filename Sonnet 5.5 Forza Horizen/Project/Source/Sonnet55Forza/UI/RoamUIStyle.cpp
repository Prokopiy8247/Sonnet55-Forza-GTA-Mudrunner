// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/RoamUIStyle.h"

#include "Fonts/FontMeasure.h"
#include "Framework/Application/SlateApplication.h"
#include "Rendering/SlateRenderer.h"
#include "Styling/CoreStyle.h"
#include "Styling/SlateBrush.h"
#include "Styling/SlateTypes.h"

// ======================================================================================================================
// Palette, font, brushes
// ======================================================================================================================

namespace RoamUI
{
	namespace Color
	{
		FLinearColor Glass() { return FLinearColor(0.006f, 0.010f, 0.018f, 0.88f); }
		FLinearColor Orange() { return FLinearColor(1.000f, 0.478f, 0.110f, 1.0f); }
		FLinearColor Teal() { return FLinearColor(0.133f, 0.827f, 0.933f, 1.0f); }
		FLinearColor Amber() { return FLinearColor(1.000f, 0.698f, 0.141f, 1.0f); }
		FLinearColor Red() { return FLinearColor(1.000f, 0.200f, 0.180f, 1.0f); }
		FLinearColor Chalk() { return FLinearColor(0.945f, 0.957f, 0.965f, 1.0f); }
		FLinearColor Dim() { return FLinearColor(0.700f, 0.745f, 0.790f, 0.85f); }
		FLinearColor Lerp(const FLinearColor& A, const FLinearColor& B, float T) { return A + (B - A) * FMath::Clamp(T, 0.0f, 1.0f); }
		FLinearColor WithAlpha(const FLinearColor& C, float Alpha) { return FLinearColor(C.R, C.G, C.B, C.A * Alpha); }

		FLinearColor Road(ERoamRoadClass Class)
		{
			switch (Class)
			{
			case ERoamRoadClass::Highway: return FLinearColor(1.00f, 0.56f, 0.16f, 1.0f);
			case ERoamRoadClass::Regional: return FLinearColor(0.93f, 0.94f, 0.92f, 1.0f);
			case ERoamRoadClass::Mountain: return FLinearColor(0.98f, 0.80f, 0.40f, 1.0f);
			case ERoamRoadClass::Village: return FLinearColor(0.60f, 0.67f, 0.74f, 1.0f);
			case ERoamRoadClass::Dirt: return FLinearColor(0.74f, 0.56f, 0.38f, 1.0f);
			case ERoamRoadClass::Shortcut: return FLinearColor(0.60f, 0.48f, 0.36f, 1.0f);
			default: return FLinearColor::White;
			}
		}
	}

	FSlateFontInfo Font(int32 Size, bool bBold)
	{
		return FCoreStyle::GetDefaultFontStyle(bBold ? "Bold" : "Regular", Size);
	}

	namespace
	{
		struct FBrushSet
		{
			FSlateColorBrush FlatBrush{ FLinearColor::White };
			FSlateRoundedBoxBrush PanelBrush{ FLinearColor::White, 18.0f, FLinearColor(1.0f, 1.0f, 1.0f, 0.09f), 1.5f };
			FSlateRoundedBoxBrush PillBrush{ FLinearColor::White, 8.0f, FLinearColor::Transparent, 0.0f };
			FSlateRoundedBoxBrush DiscBrush{ FLinearColor::White, 8.0f, FLinearColor::Transparent, 0.0f };

			FBrushSet()
			{
				DiscBrush.OutlineSettings.RoundingType = ESlateBrushRoundingType::HalfHeightRadius;
			}
		};
		const FBrushSet& BrushSet()
		{
			static const FBrushSet Set;
			return Set;
		}
	}

	namespace Brushes
	{
		const FSlateBrush* Flat() { return &BrushSet().FlatBrush; }
		const FSlateBrush* Panel() { return &BrushSet().PanelBrush; }
		const FSlateBrush* Pill() { return &BrushSet().PillBrush; }
		const FSlateBrush* Disc() { return &BrushSet().DiscBrush; }
	}
}

// ======================================================================================================================
// Pure logic
// ======================================================================================================================

namespace RoamUI::Logic
{
	FSafeArea ComputeSafeArea(const FVector2f& ViewSize, float Fraction)
	{
		const float F = FMath::Clamp(Fraction, 0.0f, 0.25f);
		FSafeArea Area;
		Area.Left = Area.Right = FMath::Max(0.0f, ViewSize.X) * F;
		Area.Top = Area.Bottom = FMath::Max(0.0f, ViewSize.Y) * F;
		return Area;
	}

	float ConvertSpeed(float Kmh, bool bMph) { return bMph ? Roam::KmhToMph(Kmh) : Kmh; }

	int32 SpeedValue(float Kmh, bool bMph)
	{
		return FMath::Clamp(FMath::RoundToInt(FMath::Max(0.0f, ConvertSpeed(Kmh, bMph))), 0, 999);
	}

	const TCHAR* UnitLabel(bool bMph) { return bMph ? TEXT("MPH") : TEXT("KM/H"); }

	FString GearText(int32 Gear)
	{
		if (Gear < 0)
		{
			return TEXT("R");
		}
		return Gear == 0 ? FString(TEXT("N")) : FString::FromInt(Gear);
	}

	FString FormatTimer(float Seconds)
	{
		const int32 Cs = FMath::Max(0, FMath::FloorToInt(Seconds * 100.0f));
		return FString::Printf(TEXT("%02d:%02d.%02d"), Cs / 6000, (Cs / 100) % 60, Cs % 100);
	}

	int32 LeadingZeroCells(int32 Value, int32 Cells)
	{
		const int32 Digits = Value >= 100 ? 3 : (Value >= 10 ? 2 : 1);
		return FMath::Clamp(Cells - Digits, 0, FMath::Max(0, Cells - 1));
	}

	int32 TachLitSegments(float NormRpm, int32 Segments)
	{
		if (!(NormRpm >= 0.005f))
		{
			return 0;
		}
		return FMath::Clamp(FMath::CeilToInt(FMath::Min(NormRpm, 1.0f) * static_cast<float>(Segments)), 1, Segments);
	}

	ETachZone TachZoneOf(int32 Index, int32 Segments)
	{
		if (Index >= FMath::CeilToInt(0.90f * static_cast<float>(Segments)))
		{
			return ETachZone::Redline;
		}
		if (Index >= FMath::CeilToInt(0.78f * static_cast<float>(Segments)))
		{
			return ETachZone::Warn;
		}
		return ETachZone::Normal;
	}

	float TachSegmentAngleDeg(int32 Index, int32 Segments, float StartDeg, float SweepDeg)
	{
		return StartDeg + SweepDeg * (static_cast<float>(Index) + 0.5f) / static_cast<float>(FMath::Max(1, Segments));
	}

	float MinimapViewRadiusM(float SpeedKmh)
	{
		const float T = FMath::Clamp(SpeedKmh / MinimapFullRadiusSpeedKmh, 0.0f, 1.0f);
		return FMath::Lerp(MinimapMinRadiusM, MinimapMaxRadiusM, T * T * (3.0f - 2.0f * T));
	}

	FVector2f WorldDeltaToMapOffset(const FVector2f& DeltaNorthEastM, float HeadingYawDeg)
	{
		float S = 0.0f;
		float C = 1.0f;
		FMath::SinCos(&S, &C, FMath::DegreesToRadians(HeadingYawDeg));
		const float North = DeltaNorthEastM.X;
		const float East = DeltaNorthEastM.Y;
		const float Right = East * C - North * S;
		const float Up = East * S + North * C;
		return FVector2f(Right, -Up);
	}

	FVector2f NorthOnMap(float HeadingYawDeg)
	{
		return WorldDeltaToMapOffset(FVector2f(1.0f, 0.0f), HeadingYawDeg);
	}

	bool ClipSegmentToCircle(const FVector2f& A, const FVector2f& B, float Radius, float& OutT0, float& OutT1)
	{
		const FVector2f D = B - A;
		const float QuadA = D.X * D.X + D.Y * D.Y;
		const float QuadC = A.X * A.X + A.Y * A.Y - Radius * Radius;
		if (QuadA < 1e-8f)
		{
			OutT0 = 0.0f;
			OutT1 = 1.0f;
			return QuadC <= 0.0f;
		}
		const float QuadB = 2.0f * (A.X * D.X + A.Y * D.Y);
		const float Disc = QuadB * QuadB - 4.0f * QuadA * QuadC;
		if (Disc < 0.0f)
		{
			return false;
		}
		const float Root = FMath::Sqrt(Disc);
		const float TA = (-QuadB - Root) / (2.0f * QuadA);
		const float TB = (-QuadB + Root) / (2.0f * QuadA);
		OutT0 = FMath::Max(0.0f, TA);
		OutT1 = FMath::Min(1.0f, TB);
		return OutT0 < OutT1;
	}

	void SimplifyPolyline(const TArray<FVector2f>& In, float ToleranceM, TArray<FVector2f>& Out)
	{
		Out.Reset();
		const int32 Num = In.Num();
		if (Num < 3 || ToleranceM <= 0.0f)
		{
			Out = In;
			return;
		}
		TBitArray<> Keep(false, Num);
		Keep[0] = true;
		Keep[Num - 1] = true;
		TArray<TPair<int32, int32>, TInlineAllocator<64>> Stack;
		Stack.Add(TPair<int32, int32>(0, Num - 1));
		const float TolSq = ToleranceM * ToleranceM;
		while (Stack.Num() > 0)
		{
			const TPair<int32, int32> Range = Stack.Pop(EAllowShrinking::No);
			const FVector2f A = In[Range.Key];
			const FVector2f B = In[Range.Value];
			const FVector2f AB = B - A;
			const float LenSq = AB.X * AB.X + AB.Y * AB.Y;
			float BestDistSq = -1.0f;
			int32 BestIndex = INDEX_NONE;
			for (int32 i = Range.Key + 1; i < Range.Value; ++i)
			{
				const FVector2f AP = In[i] - A;
				float T = LenSq > 1e-8f ? (AP.X * AB.X + AP.Y * AB.Y) / LenSq : 0.0f;
				T = FMath::Clamp(T, 0.0f, 1.0f);
				const FVector2f Closest = A + AB * T;
				const FVector2f Diff = In[i] - Closest;
				const float DistSq = Diff.X * Diff.X + Diff.Y * Diff.Y;
				if (DistSq > BestDistSq)
				{
					BestDistSq = DistSq;
					BestIndex = i;
				}
			}
			if (BestIndex != INDEX_NONE && BestDistSq > TolSq)
			{
				Keep[BestIndex] = true;
				Stack.Add(TPair<int32, int32>(Range.Key, BestIndex));
				Stack.Add(TPair<int32, int32>(BestIndex, Range.Value));
			}
		}
		for (int32 i = 0; i < Num; ++i)
		{
			if (Keep[i])
			{
				Out.Add(In[i]);
			}
		}
	}

	FVector2f ClampToCircle(const FVector2f& P, float Radius, bool* bOutClamped)
	{
		const float Len = P.Size();
		const bool bOutside = Len > Radius && Len > 1e-4f;
		if (bOutClamped)
		{
			*bOutClamped = bOutside;
		}
		return bOutside ? P * (Radius / Len) : P;
	}

	float EaseOutCubic(float T)
	{
		const float U = 1.0f - FMath::Clamp(T, 0.0f, 1.0f);
		return 1.0f - U * U * U;
	}

	FPhase RegionPopupPhase(float ElapsedSec)
	{
		FPhase Phase;
		if (ElapsedSec < 0.0f)
		{
			return Phase;
		}
		if (ElapsedSec < RegionPopupInSec)
		{
			const float P = ElapsedSec / RegionPopupInSec;
			Phase.Alpha = P;
			Phase.Slide = EaseOutCubic(P);
			Phase.bVisible = true;
		}
		else if (ElapsedSec < RegionPopupInSec + RegionPopupHoldSec)
		{
			Phase.Alpha = 1.0f;
			Phase.Slide = 1.0f;
			Phase.bVisible = true;
		}
		else if (ElapsedSec < RegionPopupInSec + RegionPopupHoldSec + RegionPopupOutSec)
		{
			const float Q = (ElapsedSec - RegionPopupInSec - RegionPopupHoldSec) / RegionPopupOutSec;
			Phase.Alpha = 1.0f - Q;
			Phase.Slide = 1.0f - Q * Q;
			Phase.bVisible = true;
		}
		return Phase;
	}

	FPhase NotificationPhase(float AgeSec, float HoldSec)
	{
		FPhase Phase;
		if (AgeSec < 0.0f)
		{
			return Phase;
		}
		if (AgeSec < NotificationInSec)
		{
			const float P = AgeSec / NotificationInSec;
			Phase.Alpha = P;
			Phase.Slide = EaseOutCubic(P);
			Phase.bVisible = true;
		}
		else if (AgeSec < NotificationInSec + HoldSec)
		{
			Phase.Alpha = 1.0f;
			Phase.Slide = 1.0f;
			Phase.bVisible = true;
		}
		else if (AgeSec < NotificationInSec + HoldSec + NotificationOutSec)
		{
			const float Q = (AgeSec - NotificationInSec - HoldSec) / NotificationOutSec;
			Phase.Alpha = 1.0f - Q;
			Phase.Slide = 1.0f - Q * Q;
			Phase.bVisible = true;
		}
		return Phase;
	}

	void FNotificationChannel::Push(const FRoamNotification& Notification, double Now)
	{
		if (Pending.Num() >= MaxPending)
		{
			Pending.RemoveAt(0);
		}
		Pending.Add(Notification);
		Update(Now);
	}

	void FNotificationChannel::Update(double Now)
	{
		Visible.RemoveAll([Now](const FEntry& Entry) { return AgeOf(Entry, Now) >= LifetimeOf(Entry); });
		while (Visible.Num() < Capacity && Pending.Num() > 0)
		{
			FEntry Entry;
			Entry.Data = Pending[0];
			Entry.StartTime = Now;
			Entry.HoldSec = Entry.Data.Seconds > 0.0f ? Entry.Data.Seconds : 4.0f;
			Visible.Add(Entry);
			Pending.RemoveAt(0);
		}
	}

	void FNotificationChannel::Clear()
	{
		Visible.Reset();
		Pending.Reset();
	}

	bool IsWrongWay(float Dot, float LateralCm, bool bOneWay, float SpeedKmh)
	{
		if (SpeedKmh < 25.0f)
		{
			return false;
		}
		if (bOneWay)
		{
			return Dot < -0.6f;
		}
		return (Dot > 0.6f && LateralCm < -120.0f) || (Dot < -0.6f && LateralCm > 120.0f);
	}
}

// ======================================================================================================================
// Painting helpers
// ======================================================================================================================

namespace RoamUI
{
	void DrawBox(FSlateWindowElementList& Out, int32 LayerId, const FGeometry& G, const FVector2f& Pos, const FVector2f& Size, const FSlateBrush* Brush, const FLinearColor& Tint)
	{
		if (Tint.A <= 0.004f || Size.X <= 0.0f || Size.Y <= 0.0f)
		{
			return;
		}
		FSlateDrawElement::MakeBox(Out, LayerId, G.ToPaintGeometry(Size, FSlateLayoutTransform(Pos)), Brush, ESlateDrawEffect::None, Tint);
	}

	void DrawRotatedBox(FSlateWindowElementList& Out, int32 LayerId, const FGeometry& G, const FVector2f& Center, const FVector2f& Size, float AngleRad, const FSlateBrush* Brush, const FLinearColor& Tint)
	{
		if (Tint.A <= 0.004f)
		{
			return;
		}
		FSlateDrawElement::MakeRotatedBox(Out, LayerId, G.ToPaintGeometry(Size, FSlateLayoutTransform(Center - Size * 0.5f)), Brush, ESlateDrawEffect::None,
			AngleRad, TOptional<FVector2f>(), FSlateDrawElement::RelativeToElement, Tint);
	}

	FVector2f MeasureText(const FString& Text, const FSlateFontInfo& FontInfo)
	{
		if (Text.IsEmpty() || !FSlateApplication::IsInitialized())
		{
			return FVector2f::ZeroVector;
		}
		const TSharedRef<FSlateFontMeasure> Measure = FSlateApplication::Get().GetRenderer()->GetFontMeasureService();
		return FVector2f(Measure->Measure(Text, FontInfo, 1.0f));
	}

	FVector2f PaintText(FSlateWindowElementList& Out, int32 LayerId, const FGeometry& G, const FVector2f& Pos, const FString& Text, const FSlateFontInfo& FontInfo,
		const FLinearColor& Tint, ETextAnchor Anchor, bool bShadow)
	{
		if (Text.IsEmpty() || Tint.A <= 0.004f)
		{
			return FVector2f::ZeroVector;
		}
		const FVector2f Size = MeasureText(Text, FontInfo);
		float X = Pos.X;
		if (Anchor == ETextAnchor::Center)
		{
			X -= Size.X * 0.5f;
		}
		else if (Anchor == ETextAnchor::Right)
		{
			X -= Size.X;
		}
		if (bShadow)
		{
			FSlateDrawElement::MakeText(Out, LayerId, G.ToPaintGeometry(Size, FSlateLayoutTransform(FVector2f(X + 1.5f, Pos.Y + 1.5f))), Text, FontInfo,
				ESlateDrawEffect::None, FLinearColor(0.0f, 0.0f, 0.0f, 0.55f * Tint.A));
		}
		FSlateDrawElement::MakeText(Out, LayerId + (bShadow ? 1 : 0), G.ToPaintGeometry(Size, FSlateLayoutTransform(FVector2f(X, Pos.Y))), Text, FontInfo, ESlateDrawEffect::None, Tint);
		return Size;
	}

	void DrawPolygon(FSlateWindowElementList& Out, int32 LayerId, const FGeometry& G, const TArray<FVector2f>& Points, const FLinearColor& Tint)
	{
		const int32 Num = Points.Num();
		if (Num < 3 || Tint.A <= 0.004f || !FSlateApplication::IsInitialized())
		{
			return;
		}
		// Game-thread only (OnPaint). The arrays are reused, so a frame costs no allocation here.
		static TArray<FSlateVertex> Verts;
		static TArray<SlateIndex> Indices;
		Verts.Reset();
		Indices.Reset();

		FVector2f Centroid = FVector2f::ZeroVector;
		for (const FVector2f& P : Points)
		{
			Centroid += P;
		}
		Centroid /= static_cast<float>(Num);

		const FSlateRenderTransform& RenderTransform = G.GetAccumulatedRenderTransform();
		const FColor Col = Tint.ToFColor(true);
		const FVector2f Uv(0.5f, 0.5f);
		Verts.Add(FSlateVertex::Make<ESlateVertexRounding::Disabled>(RenderTransform, Centroid, Uv, Col));
		for (const FVector2f& P : Points)
		{
			Verts.Add(FSlateVertex::Make<ESlateVertexRounding::Disabled>(RenderTransform, P, Uv, Col));
		}
		for (int32 i = 0; i < Num; ++i)
		{
			Indices.Add(0);
			Indices.Add(static_cast<SlateIndex>(i + 1));
			Indices.Add(static_cast<SlateIndex>((i + 1) % Num + 1));
		}
		const FSlateResourceHandle Handle = FSlateApplication::Get().GetRenderer()->GetResourceHandle(*Brushes::Flat());
		FSlateDrawElement::MakeCustomVerts(Out, LayerId, Handle, Verts, Indices, nullptr, 0, 0);
	}

	void MakeStarPoints(const FVector2f& Center, float Radius, TArray<FVector2f>& OutPoints)
	{
		OutPoints.Reset();
		for (int32 i = 0; i < 10; ++i)
		{
			const float Angle = FMath::DegreesToRadians(-90.0f + 36.0f * static_cast<float>(i));
			const float R = (i % 2 == 0) ? Radius : Radius * 0.45f;
			OutPoints.Add(Center + FVector2f(FMath::Cos(Angle), FMath::Sin(Angle)) * R);
		}
	}
}
