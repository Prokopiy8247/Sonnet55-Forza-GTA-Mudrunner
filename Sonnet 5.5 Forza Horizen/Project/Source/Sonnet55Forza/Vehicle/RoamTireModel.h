// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"

struct FRoamTireSpec;

/**
 * Pure tyre force model of the project-owned vehicle (Docs/Tech/DRIVE_TESTS.md "Tyre model"). No engine objects, no allocation:
 * every function is a free function of plain floats so it is unit-testable and cheap enough to be called 3x per wheel per solver step.
 *
 * MODEL (normalised-slip friction circle):
 *   kappa = (omega*R - vx) / max(|vx|, V0)            longitudinal slip ratio (V0 regularises the standstill)
 *   tanA  = vy / max(|vx|, V0)                        lateral slip (vy positive = contact patch moving to the right)
 *   sx = kappa / kappaPeak,  sy = tanA / tanAlphaPeak,  s = hypot(sx, sy)      (s = 1 is the grip peak, the same for every direction)
 *   F = mu * Fz * f(s),  direction = (sx, -sy) / s
 *   f(s) = 1 - (1 - s)^2 up to the peak, then Slide + (1 - Slide) * exp(-((s - 1) / w)^2)  (C1 at the peak, falls to the slide level)
 * so the friction is a circle in normalised slip space: a locked wheel gives the full slide force against the motion, wheelspin
 * takes lateral grip away, a slide of the whole car converges to Slide*mu*Fz opposing the velocity. mu itself comes from
 * Mu() = peak * load sensitivity * surface bias * world grip multiplier (weather).
 */
namespace RoamTire
{
	struct FShape
	{
		float PeakSlipRatio = 0.12f;
		float PeakTanAlpha = 0.14f;   // tan(peak slip angle)
		float SlideRatio = 0.88f;
		float FalloffWidth = 1.2f;    // in units of normalised slip
	};

	struct FResult
	{
		float Fx = 0.0f;              // N along the wheel's rolling direction (positive = pushes the car forward)
		float Fy = 0.0f;              // N sideways (positive = to the right)
		float SlipRatio = 0.0f;
		float SlipAngleRad = 0.0f;
		float SlideNorm = 0.0f;       // s, 1 = peak
	};

	/** f(s): normalised force curve, 0 at s = 0, 1 at s = 1. */
	SONNET55FORZA_API float Curve(float S, float SlideRatio, float FalloffWidth);

	/** Evaluates the forces of one wheel. VLong/VLat in m/s in the wheel frame, OmegaR = omega * radius in m/s, Fz and result in N. */
	SONNET55FORZA_API FResult Evaluate(const FShape& Shape, float PeakMu, float Fz, float VLong, float VLat, float OmegaR, float V0);

	/** Effective peak friction coefficient: spec peak x load sensitivity x surface bias x grip multiplier (weather) x pressure effect. */
	SONNET55FORZA_API float Mu(const FRoamTireSpec& Spec, float Fz, ERoamSurface Surface, float Wetness01, float PressurePsi);

	/** Dry base grip and wet-adjusted grip of a surface, rolling-resistance multiplier of a surface. */
	SONNET55FORZA_API float RollingResistanceFactor(ERoamSurface Surface);

	/** Shape parameters from the spec (slide ratio, peak slip). */
	SONNET55FORZA_API FShape MakeShape(const FRoamTireSpec& Spec);
}
