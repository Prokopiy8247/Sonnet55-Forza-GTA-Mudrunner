// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Fonts/SlateFontInfo.h"
#include "Layout/Geometry.h"
#include "Rendering/DrawElements.h"
#include "Styling/SlateBrush.h"

/**
 * HUD look + PURE layout/animation logic (mission B1). Everything under RoamUI::Logic needs no Slate and no UObject and is covered by
 * Tests/RoamUITests.cpp. The painting helpers at the bottom wrap FSlateDrawElement so the leaf widgets (SRoamSpeedCluster,
 * SRoamMinimap, SRoamNotifications) stay short. All HUD numbers are in "1080p units": the viewport DPI scale (UserInterfaceSettings)
 * makes them grow with the resolution, so a 4K capture is simply 2x.
 */
namespace RoamUI
{
	// ---- z-order layers (URoamUISubsystem::AddViewportWidget). Menus (RoamMenus.cpp) already use 640 (debug overlay) .. 1000 (console).
	namespace Layer
	{
		inline constexpr int32 Hud = 100;           // speed cluster, minimap, world strip
		inline constexpr int32 Notifications = 500; // toasts, banners, result cards, event bar, region popup
		inline constexpr int32 Overlay = 640;       // debug overlay, hints
		inline constexpr int32 Modal = 800;         // garage, pause, full map
		inline constexpr int32 Console = 1000;
	}

	// ---- layout numbers (RESEARCH_NOTES 5.1 items 5 and 13)
	namespace Layout
	{
		inline constexpr float SafeAreaFraction = 0.05f;
		inline constexpr float SpeedClusterW = 480.0f;
		inline constexpr float SpeedClusterH = 200.0f;
		inline constexpr float MinimapSize = 264.0f;
		inline constexpr float EventBarW = 640.0f;
		inline constexpr float EventBarH = 84.0f;
		inline constexpr float RegionPopupW = 560.0f;
		inline constexpr float RegionPopupH = 88.0f;
		inline constexpr float ToastW = 440.0f;
		inline constexpr float ToastH = 72.0f;
		inline constexpr float ToastGap = 10.0f;
		inline constexpr int32 MaxToasts = 3;
		inline constexpr int32 TachSegments = 48;
	}

	// ---- palette (same family as RoamMenus::Style: dark glass + festival orange + lagoon teal)
	namespace Color
	{
		SONNET55FORZA_API FLinearColor Glass();   // panel fill, translucent
		SONNET55FORZA_API FLinearColor Orange();
		SONNET55FORZA_API FLinearColor Teal();
		SONNET55FORZA_API FLinearColor Amber();
		SONNET55FORZA_API FLinearColor Red();
		SONNET55FORZA_API FLinearColor Chalk();
		SONNET55FORZA_API FLinearColor Dim();
		SONNET55FORZA_API FLinearColor Lerp(const FLinearColor& A, const FLinearColor& B, float T);
		SONNET55FORZA_API FLinearColor WithAlpha(const FLinearColor& C, float Alpha);
		/** Minimap road colours per class. */
		SONNET55FORZA_API FLinearColor Road(ERoamRoadClass Class);
	}

	SONNET55FORZA_API FSlateFontInfo Font(int32 Size, bool bBold = false);

	namespace Brushes
	{
		SONNET55FORZA_API const FSlateBrush* Flat();    // square white
		SONNET55FORZA_API const FSlateBrush* Panel();   // rounded dark glass, 18 px corners, white outline at 9% alpha
		SONNET55FORZA_API const FSlateBrush* Pill();    // rounded white, 8 px corners
		SONNET55FORZA_API const FSlateBrush* Disc();    // filled circle (HalfHeightRadius rounding): needs a square box
	}

	namespace Logic
	{
		// =========================================================== safe area / units
		struct FSafeArea
		{
			float Left = 0.0f;
			float Top = 0.0f;
			float Right = 0.0f;
			float Bottom = 0.0f;
		};
		/** Title-safe margins: Fraction of the width left/right, of the height top/bottom. */
		SONNET55FORZA_API FSafeArea ComputeSafeArea(const FVector2f& ViewSize, float Fraction = Layout::SafeAreaFraction);

		/** Speed in the unit the player chose. */
		SONNET55FORZA_API float ConvertSpeed(float Kmh, bool bMph);
		/** Rounded, clamped to 0..999 (three digit cells). */
		SONNET55FORZA_API int32 SpeedValue(float Kmh, bool bMph);
		SONNET55FORZA_API const TCHAR* UnitLabel(bool bMph);
		/** -1 -> "R", 0 -> "N", n -> "n". */
		SONNET55FORZA_API FString GearText(int32 Gear);
		/** "01:23.45" (minutes may exceed 59 -> "75:00.00"). Negative values clamp to zero. */
		SONNET55FORZA_API FString FormatTimer(float Seconds);
		/** Number of leading zero cells that should be drawn dim for a 3-cell readout (0..2). */
		SONNET55FORZA_API int32 LeadingZeroCells(int32 Value, int32 Cells = 3);

		// =========================================================== tachometer
		enum class ETachZone : uint8 { Normal, Warn, Redline };
		/** Lit segments for a normalised RPM (RPM / redline): ceil, 0 below 0.5 percent, 48 at/above 1. */
		SONNET55FORZA_API int32 TachLitSegments(float NormRpm, int32 Segments = Layout::TachSegments);
		/** Zone of segment Index (0-based): warn from 78 percent, red from 90 percent of the arc. */
		SONNET55FORZA_API ETachZone TachZoneOf(int32 Index, int32 Segments = Layout::TachSegments);
		/** Centre angle (degrees, clockwise from +X on screen) of segment Index of an arc starting at StartDeg and sweeping SweepDeg. */
		SONNET55FORZA_API float TachSegmentAngleDeg(int32 Index, int32 Segments, float StartDeg, float SweepDeg);

		// =========================================================== minimap
		inline constexpr float MinimapMinRadiusM = 350.0f;
		inline constexpr float MinimapMaxRadiusM = 900.0f;
		inline constexpr float MinimapFullRadiusSpeedKmh = 200.0f;
		/** The player arrow sits this fraction of the radius BELOW the circle centre (more road visible ahead). */
		inline constexpr float MinimapPlayerBackFraction = 0.18f;

		/** View radius in metres for a speed: 350 m standing, 900 m at 200 km/h and above, smoothstep in between. */
		SONNET55FORZA_API float MinimapViewRadiusM(float SpeedKmh);
		/**
		 * World delta (UE X = north, Y = east, metres) -> map offset (x right, y DOWN) in metres for a heading-up map. HeadingYawDeg is the
		 * actor yaw (0 = +X = north, 90 = +Y = east): a point straight ahead of the car maps to (0, -distance).
		 */
		SONNET55FORZA_API FVector2f WorldDeltaToMapOffset(const FVector2f& DeltaNorthEastM, float HeadingYawDeg);
		/** Direction of north on the heading-up map (unit vector, x right, y down). */
		SONNET55FORZA_API FVector2f NorthOnMap(float HeadingYawDeg);
		/**
		 * Clips the segment A-B (circle-centre relative) to the circle of radius R. Returns false when no part of it is inside; otherwise
		 * OutT0 <= OutT1 are the parameters of the inside piece.
		 */
		SONNET55FORZA_API bool ClipSegmentToCircle(const FVector2f& A, const FVector2f& B, float Radius, float& OutT0, float& OutT1);
		/** Douglas-Peucker; keeps the first and last point. */
		SONNET55FORZA_API void SimplifyPolyline(const TArray<FVector2f>& In, float ToleranceM, TArray<FVector2f>& Out);
		/** Point on the circle boundary in the direction of P (for off-screen markers); P unchanged when inside. */
		SONNET55FORZA_API FVector2f ClampToCircle(const FVector2f& P, float Radius, bool* bOutClamped = nullptr);

		// =========================================================== animation envelopes
		struct FPhase
		{
			/** Opacity 0..1. */
			float Alpha = 0.0f;
			/** 0 = fully hidden (off-screen side), 1 = fully in place. */
			float Slide = 0.0f;
			bool bVisible = false;
		};
		/** Region name popup: 350 ms in, 2.8 s hold, 400 ms out (RESEARCH_NOTES 5.1 item 5). */
		SONNET55FORZA_API FPhase RegionPopupPhase(float ElapsedSec);
		inline constexpr float RegionPopupInSec = 0.35f;
		inline constexpr float RegionPopupHoldSec = 2.8f;
		inline constexpr float RegionPopupOutSec = 0.4f;
		/** Toast/banner/card: 250 ms in, HoldSec, 300 ms out. */
		SONNET55FORZA_API FPhase NotificationPhase(float AgeSec, float HoldSec);
		inline constexpr float NotificationInSec = 0.25f;
		inline constexpr float NotificationOutSec = 0.3f;
		SONNET55FORZA_API float EaseOutCubic(float T);

		// =========================================================== notification channel (queue with N visible slots)
		/**
		 * One presentation channel (toasts: 3 slots, banner: 1, result card: 1). Pushed notifications wait in a FIFO until a slot is free;
		 * the hold time starts when the notification becomes visible. Time is a caller-supplied double (real seconds), so the class is
		 * deterministic and testable.
		 */
		class SONNET55FORZA_API FNotificationChannel
		{
		public:
			struct FEntry
			{
				FRoamNotification Data;
				double StartTime = 0.0;
				float HoldSec = 4.0f;
			};

			explicit FNotificationChannel(int32 InCapacity = 3, int32 InMaxPending = 12) : Capacity(InCapacity), MaxPending(InMaxPending) {}

			void Push(const FRoamNotification& Notification, double Now);
			/** Expires finished entries, then promotes waiting ones into free slots. */
			void Update(double Now);
			void Clear();

			const TArray<FEntry>& GetVisible() const { return Visible; }
			int32 GetNumPending() const { return Pending.Num(); }
			int32 GetCapacity() const { return Capacity; }
			/** Age of an entry in seconds. */
			static float AgeOf(const FEntry& Entry, double Now) { return static_cast<float>(Now - Entry.StartTime); }
			/** Total lifetime of an entry including the in/out animation. */
			static float LifetimeOf(const FEntry& Entry) { return NotificationInSec + Entry.HoldSec + NotificationOutSec; }

		private:
			TArray<FEntry> Visible;
			TArray<FRoamNotification> Pending;
			int32 Capacity = 3;
			int32 MaxPending = 12;
		};

		/** Wrong-way test used by the HUD hint (right-hand traffic): Dot = forward . road tangent, Lateral = signed offset from the centreline (cm, + = right). */
		SONNET55FORZA_API bool IsWrongWay(float Dot, float LateralCm, bool bOneWay, float SpeedKmh);
	}

	// ======================================================================================================================
	// Painting helpers (game thread, OnPaint)
	// ======================================================================================================================
	enum class ETextAnchor : uint8 { Left, Center, Right };

	/** Local-space filled rect (optionally with one of the Brushes). */
	SONNET55FORZA_API void DrawBox(FSlateWindowElementList& Out, int32 LayerId, const FGeometry& G, const FVector2f& Pos, const FVector2f& Size,
		const FSlateBrush* Brush, const FLinearColor& Tint);
	/** Box rotated by AngleRad around its own centre. */
	SONNET55FORZA_API void DrawRotatedBox(FSlateWindowElementList& Out, int32 LayerId, const FGeometry& G, const FVector2f& Center, const FVector2f& Size,
		float AngleRad, const FSlateBrush* Brush, const FLinearColor& Tint);
	/** Text with Pos as the anchor (x by Anchor, y = top of the line). Returns the measured size. Shadow draws a dark copy first. */
	SONNET55FORZA_API FVector2f PaintText(FSlateWindowElementList& Out, int32 LayerId, const FGeometry& G, const FVector2f& Pos, const FString& Text,
		const FSlateFontInfo& FontInfo, const FLinearColor& Tint, ETextAnchor Anchor = ETextAnchor::Left, bool bShadow = false);
	SONNET55FORZA_API FVector2f MeasureText(const FString& Text, const FSlateFontInfo& FontInfo);
	/** Convex-or-star-shaped polygon (fan from the centroid) in local space. */
	SONNET55FORZA_API void DrawPolygon(FSlateWindowElementList& Out, int32 LayerId, const FGeometry& G, const TArray<FVector2f>& Points, const FLinearColor& Tint);
	/** 5-point star polygon helper (outer radius R, inner 0.45 R). */
	SONNET55FORZA_API void MakeStarPoints(const FVector2f& Center, float Radius, TArray<FVector2f>& OutPoints);
}
