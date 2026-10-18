// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamTireModel.h"

#include "Data/RoamCarDefinition.h"

namespace RoamTire
{
	float Curve(float S, float SlideRatio, float FalloffWidth)
	{
		if (S <= 0.0f)
		{
			return 0.0f;
		}
		if (S < 1.0f)
		{
			const float Q = 1.0f - S;
			return 1.0f - Q * Q;
		}
		const float T = (S - 1.0f) / FMath::Max(FalloffWidth, 0.05f);
		return SlideRatio + (1.0f - SlideRatio) * FMath::Exp(-T * T);
	}

	FResult Evaluate(const FShape& Shape, float PeakMu, float Fz, float VLong, float VLat, float OmegaR, float V0)
	{
		FResult Out;
		const float Denominator = FMath::Max(FMath::Abs(VLong), V0);
		const float Kappa = (OmegaR - VLong) / Denominator;
		const float TanAlpha = VLat / Denominator;
		Out.SlipRatio = Kappa;
		Out.SlipAngleRad = FMath::Atan(TanAlpha);
		const float Sx = Kappa / Shape.PeakSlipRatio;
		const float Sy = TanAlpha / Shape.PeakTanAlpha;
		const float S = FMath::Sqrt(Sx * Sx + Sy * Sy);
		Out.SlideNorm = S;
		if (S < 1.0e-5f || Fz <= 0.0f)
		{
			return Out;
		}
		const float Magnitude = PeakMu * Fz * Curve(S, Shape.SlideRatio, Shape.FalloffWidth);
		Out.Fx = Magnitude * Sx / S;
		Out.Fy = -Magnitude * Sy / S;
		return Out;
	}

	float Mu(const FRoamTireSpec& Spec, float Fz, ERoamSurface Surface, float Wetness01, float PressurePsi)
	{
		const float Nominal = FMath::Max(Spec.NominalLoadN, 500.0f);
		const float LoadRatio = FMath::Clamp(Fz / Nominal, 0.2f, 4.0f);
		float Mu = Spec.PeakFriction * FMath::Pow(LoadRatio, -Spec.LoadSensitivity);
		Mu *= Spec.GetSurfaceBias(Surface);
		// World grip: dry table value, reduced by the wet loss of the table (the compound's WetGripBias scales that loss).
		const float Dry = Roam::SurfaceGripMultiplier(Surface, 0.0f);
		const float Wet = Roam::SurfaceGripMultiplier(Surface, Wetness01);
		const float Loss = Dry > 1.0e-3f ? FMath::Max(0.0f, 1.0f - Wet / Dry) : 0.0f;
		Mu *= Dry * (1.0f - Loss / FMath::Max(Spec.WetGripBias, 0.3f));
		// Pressure: optimum near 32 psi, a wrong pressure costs about 0.5 % grip per psi.
		Mu *= 1.0f - 0.005f * FMath::Min(FMath::Abs(PressurePsi - 32.0f), 14.0f);
		return Mu;
	}

	float RollingResistanceFactor(ERoamSurface Surface)
	{
		switch (Surface)
		{
		case ERoamSurface::Asphalt: return 1.0f;
		case ERoamSurface::Concrete: return 0.95f;
		case ERoamSurface::Dirt: return 2.0f;
		case ERoamSurface::Gravel: return 2.4f;
		case ERoamSurface::Grass: return 3.0f;
		case ERoamSurface::Sand: return 4.5f;
		case ERoamSurface::Snow: return 2.8f;
		case ERoamSurface::Mud: return 4.0f;
		default: return 1.0f;
		}
	}

	FShape MakeShape(const FRoamTireSpec& Spec)
	{
		FShape Shape;
		Shape.PeakSlipRatio = FMath::Max(Spec.PeakSlipRatio, 0.02f);
		Shape.PeakTanAlpha = FMath::Tan(FMath::DegreesToRadians(FMath::Clamp(Spec.PeakSlipAngleDeg, 1.0f, 25.0f)));
		Shape.SlideRatio = FMath::Clamp(Spec.SlideFrictionRatio, 0.4f, 1.0f);
		return Shape;
	}
}
