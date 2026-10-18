// Copyright Epic Games, Inc. All Rights Reserved.

#include "Data/RoamCarDefinition.h"

#include "UObject/PrimaryAssetId.h"

// ------------------------------------------------------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------------------------------------------------------

namespace
{
	/** Piecewise-linear lookup of a sorted (X, Y) array; clamps outside the range. */
	template <typename TGetX, typename TGetY, typename TArr>
	float InterpSorted(const TArr& Points, float X, TGetX GetX, TGetY GetY)
	{
		const int32 Num = Points.Num();
		if (Num == 0)
		{
			return 0.0f;
		}
		if (X <= GetX(Points[0]))
		{
			return GetY(Points[0]);
		}
		for (int32 i = 1; i < Num; ++i)
		{
			const float X1 = GetX(Points[i]);
			if (X <= X1)
			{
				const float X0 = GetX(Points[i - 1]);
				const float Alpha = (X1 > X0) ? (X - X0) / (X1 - X0) : 1.0f;
				return FMath::Lerp(GetY(Points[i - 1]), GetY(Points[i]), Alpha);
			}
		}
		return GetY(Points[Num - 1]);
	}

	float Normalise(float Value, const FVector2D& Range)
	{
		const float A = static_cast<float>(Range.X);
		const float B = static_cast<float>(Range.Y);
		if (FMath::IsNearlyEqual(A, B))
		{
			return 0.0f;
		}
		return FMath::Clamp((Value - A) / (B - A), 0.0f, 1.0f);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Value-type helpers
// ------------------------------------------------------------------------------------------------------------------

const FRoamWheelGeometry& FRoamCarGeometry::GetWheel(int32 WheelIndex) const
{
	switch (WheelIndex)
	{
	case 0: return WheelFL;
	case 1: return WheelFR;
	case 2: return WheelRL;
	default: return WheelRR;
	}
}

FRoamWheelGeometry& FRoamCarGeometry::GetWheel(int32 WheelIndex)
{
	return const_cast<FRoamWheelGeometry&>(static_cast<const FRoamCarGeometry*>(this)->GetWheel(WheelIndex));
}

float FRoamEngineSpec::GetTorqueNm(float RPM) const
{
	if (TorqueCurve.Num() == 0 || RPM <= 0.0f || RPM >= RevLimiterRPM)
	{
		return 0.0f;
	}
	if (RPM <= TorqueCurve[0].RPM)
	{
		// Below the first sample the torque ramps up from zero (engine stall region).
		const float First = TorqueCurve[0].RPM;
		return First > 1.0f ? TorqueCurve[0].TorqueNm * (RPM / First) : TorqueCurve[0].TorqueNm;
	}
	return InterpSorted(TorqueCurve, RPM, [](const FRoamTorquePoint& P) { return P.RPM; }, [](const FRoamTorquePoint& P) { return P.TorqueNm; });
}

float FRoamEngineSpec::GetPowerKw(float RPM) const
{
	return GetTorqueNm(RPM) * (RPM * UE_TWO_PI / 60.0f) / 1000.0f;
}

float FRoamEngineSpec::GetPeakPowerKw(float* OutRPM) const
{
	float Best = 0.0f;
	float BestRPM = 0.0f;
	// Only the working range counts: between the redline and the limiter the curve is extrapolated, not measured.
	const float UpperRPM = FMath::Min(RedlineRPM, RevLimiterRPM);
	for (float RPM = 500.0f; RPM <= UpperRPM; RPM += 50.0f)
	{
		const float P = GetPowerKw(RPM);
		if (P > Best)
		{
			Best = P;
			BestRPM = RPM;
		}
	}
	if (OutRPM)
	{
		*OutRPM = BestRPM;
	}
	return Best;
}

float FRoamEngineSpec::GetPeakTorqueNm(float* OutRPM) const
{
	float Best = 0.0f;
	float BestRPM = 0.0f;
	for (const FRoamTorquePoint& P : TorqueCurve)
	{
		if (P.TorqueNm > Best)
		{
			Best = P.TorqueNm;
			BestRPM = P.RPM;
		}
	}
	if (OutRPM)
	{
		*OutRPM = BestRPM;
	}
	return Best;
}

TArray<FRoamTorquePoint> FRoamEngineSpec::BuildSyntheticTorqueCurve(float PeakPowerKw, float IdleRPM, float RedlineRPM, int32 NumSamples)
{
	TArray<FRoamTorquePoint> Out;
	if (PeakPowerKw <= 0.0f || RedlineRPM <= IdleRPM || NumSamples < 2)
	{
		return Out;
	}
	const auto Shape = [RedlineRPM](float RPM)
	{
		const float X = RPM / RedlineRPM;
		return FMath::Max(0.35f, 1.0f - 1.35f * FMath::Square(X - 0.62f));
	};

	// Scale so that the maximum of T*omega over the working range equals the requested peak power.
	float MaxShapeOmega = 0.0f;
	for (float RPM = IdleRPM; RPM <= RedlineRPM; RPM += 25.0f)
	{
		MaxShapeOmega = FMath::Max(MaxShapeOmega, Shape(RPM) * (RPM * UE_TWO_PI / 60.0f));
	}
	const float PeakTorque = (PeakPowerKw * 1000.0f) / FMath::Max(MaxShapeOmega, 1.0f);

	Out.Reserve(NumSamples);
	for (int32 i = 0; i < NumSamples; ++i)
	{
		const float Alpha = static_cast<float>(i) / static_cast<float>(NumSamples - 1);
		FRoamTorquePoint P;
		P.RPM = FMath::Lerp(IdleRPM, RedlineRPM, Alpha);
		P.TorqueNm = PeakTorque * Shape(P.RPM);
		Out.Add(P);
	}
	return Out;
}

float FRoamGearboxSpec::GetTotalRatio(int32 Gear) const
{
	if (Gear > 0 && Gear <= ForwardRatios.Num())
	{
		return ForwardRatios[Gear - 1] * FinalDrive;
	}
	if (Gear == -1)
	{
		return ReverseRatio * FinalDrive;
	}
	return 0.0f;
}

float FRoamTireSpec::GetSurfaceBias(ERoamSurface Surface) const
{
	const float* Found = SurfaceBias.Find(Surface);
	return Found ? *Found : 1.0f;
}

float FRoamSteeringSpec::GetLockFraction(float SpeedKmh) const
{
	if (SpeedReduction.Num() == 0)
	{
		return 1.0f;
	}
	return InterpSorted(SpeedReduction, SpeedKmh, [](const FVector2D& P) { return static_cast<float>(P.X); }, [](const FVector2D& P) { return static_cast<float>(P.Y); });
}

// ------------------------------------------------------------------------------------------------------------------
// URoamCarDefinition
// ------------------------------------------------------------------------------------------------------------------

const FPrimaryAssetType& URoamCarDefinition::GetPrimaryAssetTypeName()
{
	static const FPrimaryAssetType Type(TEXT("RoamCar"));
	return Type;
}

FPrimaryAssetId URoamCarDefinition::GetPrimaryAssetId() const
{
	return FPrimaryAssetId(GetPrimaryAssetTypeName(), CarId.IsNone() ? GetFName() : CarId);
}

void URoamCarDefinition::PostLoad()
{
	Super::PostLoad();
	CachedPerformanceIndex = 0;
}

#if WITH_EDITOR
void URoamCarDefinition::PostEditChangeProperty(FPropertyChangedEvent& PropertyChangedEvent)
{
	Super::PostEditChangeProperty(PropertyChangedEvent);
	CachedPerformanceIndex = 0;
}
#endif

FRoamCarPerformance URoamCarDefinition::ComputePerformance(const FRoamPerformanceRules& Rules) const
{
	FRoamCarPerformance Out;

	constexpr float Gravity = 9.81f;
	constexpr float AirDensity = 1.2f;
	constexpr float Dt = 0.005f;
	constexpr int32 NumSteps = 18000; // 90 s

	const float Mass = FMath::Max(MassKg, 100.0f);
	const float Mu = GetMeanPeakFriction();
	const float WheelRadiusM = FMath::Max(0.2f, 0.01f * 0.5f * (Geometry.WheelFL.RadiusCm + Geometry.WheelRL.RadiusCm));
	const float Crr = 0.5f * (TireFront.RollingResistance + TireRear.RollingResistance);
	const float CdA = Aero.CdA;
	const float ClA = Aero.ClAFront + Aero.ClARear;
	const float DriveFraction = (Drivetrain.Layout == ERoamDrivetrain::AWD) ? 0.95f : (Drivetrain.Layout == ERoamDrivetrain::FWD ? 0.55f : 0.58f);
	const int32 NumGears = Gearbox.GetNumForwardGears();

	// ---- longitudinal simulation -----------------------------------------------------------------------------------
	float PeakTorqueRPM = 0.0f;
	Engine.GetPeakTorqueNm(&PeakTorqueRPM);
	const float LaunchRPM = FMath::Max(Engine.IdleRPM, 0.65f * PeakTorqueRPM);

	float V = 0.0f;
	float Time = 0.0f;
	int32 Gear = 1;
	float ShiftTimer = 0.0f;
	float T60 = -1.0f;
	float T100 = -1.0f;
	const float V60 = 60.0f / 3.6f;
	const float V100 = 100.0f / 3.6f;

	if (NumGears > 0 && Engine.TorqueCurve.Num() > 1)
	{
		for (int32 Step = 0; Step < NumSteps; ++Step)
		{
			const float Ratio = Gearbox.GetTotalRatio(Gear);
			float RPM = (V / WheelRadiusM) * Ratio * 60.0f / UE_TWO_PI;
			if (Gear < NumGears && RPM > Gearbox.UpshiftRpmFraction * Engine.RedlineRPM && ShiftTimer <= 0.0f)
			{
				++Gear;
				ShiftTimer = Gearbox.ShiftTimeSec;
			}

			float Thrust = 0.0f;
			if (ShiftTimer > 0.0f)
			{
				ShiftTimer -= Dt;
			}
			else
			{
				const float RPMForTorque = (Gear == 1) ? FMath::Max(RPM, LaunchRPM) : RPM;
				const float WheelForce = Engine.GetTorqueNm(RPMForTorque) * Gearbox.GetTotalRatio(Gear) * Gearbox.Efficiency / WheelRadiusM;
				const float ActiveClA = ClA + ((Aero.bActiveWing && V * 3.6f > Aero.ActiveWingDeployKmh) ? Aero.ActiveWingExtraClA : 0.0f);
				const float TractionLimit = Mu * (Mass * Gravity * DriveFraction + 0.5f * AirDensity * ActiveClA * V * V);
				Thrust = FMath::Min(WheelForce, TractionLimit);
			}

			const float Resistance = 0.5f * AirDensity * CdA * V * V + ((V > 0.01f) ? Crr * Mass * Gravity : 0.0f);
			const float Accel = (Thrust - Resistance) / Mass;
			const float PrevV = V;
			V = FMath::Max(0.0f, V + Accel * Dt);
			Time += Dt;

			if (T60 < 0.0f && V >= V60)
			{
				T60 = Time - Dt + Dt * (V60 - PrevV) / FMath::Max(V - PrevV, 1e-6f);
			}
			if (T100 < 0.0f && V >= V100)
			{
				T100 = Time - Dt + Dt * (V100 - PrevV) / FMath::Max(V - PrevV, 1e-6f);
			}
		}
	}
	Out.Time0To60Kmh = (T60 >= 0.0f) ? T60 : 90.0f;
	Out.Time0To100Kmh = (T100 >= 0.0f) ? T100 : 90.0f;
	Out.TopSpeedKmh = V * 3.6f;

	// ---- lateral grip at 100 km/h, braking -------------------------------------------------------------------------
	const float V27 = 27.8f;
	const float Downforce27 = 0.5f * AirDensity * ClA * V27 * V27;
	Out.LateralG = Mu * HandlingFactor * (Mass * Gravity + Downforce27) / (Mass * Gravity);
	const float MuBrake = FMath::Min(Mu * 1.02f, Brakes.PeakDecelerationG) * (1.0f + 0.5f * Downforce27 / (Mass * Gravity));
	const float V100Ms = 100.0f / 3.6f;
	Out.BrakeDistance100M = (V100Ms * V100Ms) / (2.0f * Gravity * FMath::Max(MuBrake, 0.1f));

	// ---- off-road suitability -------------------------------------------------------------------------------------
	{
		const float TravelMeanCm = 0.25f * (SuspensionFront.TravelUpCm + SuspensionFront.TravelDownCm + SuspensionRear.TravelUpCm + SuspensionRear.TravelDownCm) + 0.0f;
		const float Travel = FMath::Clamp(TravelMeanCm * 2.0f / 25.0f, 0.0f, 1.0f); // mean total (up + down) travel / 25 cm
		float LooseGrip = 0.0f;
		const ERoamSurface Loose[3] = { ERoamSurface::Dirt, ERoamSurface::Gravel, ERoamSurface::Sand };
		for (ERoamSurface S : Loose)
		{
			const float Bias = 0.5f * (TireFront.GetSurfaceBias(S) + TireRear.GetSurfaceBias(S));
			LooseGrip += Roam::SurfaceGripMultiplier(S, 0.0f) * Bias;
		}
		LooseGrip /= 3.0f;
		// Street tyres (~0.68 average loose grip) land near 0.4, rally/all-terrain compounds (bias > 1.2) near 1.
		const float LooseRating = FMath::Clamp((LooseGrip - 0.5f) / 0.4f, 0.0f, 1.0f);
		Out.Offroad01 = FMath::Clamp(LooseRating * (0.6f + 0.4f * Travel) * ((Drivetrain.Layout == ERoamDrivetrain::AWD) ? 1.1f : 1.0f), 0.0f, 1.0f);
	}

	// ---- ratings, score, PI -----------------------------------------------------------------------------------------
	const float NSpeed = Normalise(Out.TopSpeedKmh, Rules.RangeSpeedKmh);
	const float NHandling = Normalise(Out.LateralG, Rules.RangeLateralG);
	const float NAccel = Normalise(Out.Time0To100Kmh, Rules.RangeTime0To100);
	const float NLaunch = Normalise(Out.Time0To60Kmh, Rules.RangeTime0To60);
	const float NBraking = Normalise(Out.BrakeDistance100M, Rules.RangeBrakeDistance);
	const float NOffroad = FMath::Clamp(Out.Offroad01, 0.0f, 1.0f);

	Out.RatingSpeed = 10.0f * NSpeed;
	Out.RatingHandling = 10.0f * NHandling;
	Out.RatingAcceleration = 10.0f * NAccel;
	Out.RatingLaunch = 10.0f * NLaunch;
	Out.RatingBraking = 10.0f * NBraking;
	Out.RatingOffroad = 10.0f * NOffroad;

	Out.Score = Rules.WeightSpeed * NSpeed + Rules.WeightHandling * NHandling + Rules.WeightAcceleration * NAccel
		+ Rules.WeightLaunch * NLaunch + Rules.WeightBraking * NBraking + Rules.WeightOffroad * NOffroad;
	Out.PerformanceIndex = FMath::Clamp(FMath::RoundToInt(100.0f + 899.0f * FMath::Pow(FMath::Clamp(Out.Score, 0.0f, 1.0f), Rules.Gamma)), 100, 999);
	Out.CarClass = Roam::ClassFromPerformanceIndex(Out.PerformanceIndex);
	return Out;
}

int32 URoamCarDefinition::GetPerformanceIndex() const
{
	if (CachedPerformanceIndex <= 0)
	{
		CachedPerformanceIndex = ComputePerformance(FRoamPerformanceRules()).PerformanceIndex;
	}
	return CachedPerformanceIndex;
}

ERoamCarClass URoamCarDefinition::GetCarClass() const
{
	return Roam::ClassFromPerformanceIndex(GetPerformanceIndex());
}

FString URoamCarDefinition::GetClassLabel() const
{
	return FString::Printf(TEXT("%s %d"), *Roam::ClassToLabel(GetCarClass()), GetPerformanceIndex());
}

FVector URoamCarDefinition::GetEstimatedInertia() const
{
	if (!InertiaKgM2.IsNearlyZero())
	{
		return InertiaKgM2;
	}
	// Box model with 80 % of the extent (mass is concentrated towards the centre): Ixx roll, Iyy pitch, Izz yaw.
	const float L = 0.01f * Geometry.LengthCm * 0.8f;
	const float W = 0.01f * Geometry.WidthCm * 0.8f;
	const float H = 0.01f * Geometry.HeightCm * 0.8f;
	const float K = MassKg / 12.0f;
	return FVector(K * (W * W + H * H), K * (L * L + H * H), K * (L * L + W * W));
}

float URoamCarDefinition::GetFrontWeightFraction() const
{
	const float Wheelbase = FMath::Max(Geometry.WheelbaseCm, 1.0f);
	return FMath::Clamp(0.5f + CenterOfMassCm.X / Wheelbase, 0.3f, 0.7f);
}

bool URoamCarDefinition::Validate(TArray<FString>& OutProblems) const
{
	const int32 Before = OutProblems.Num();
	const auto Problem = [&](const TCHAR* Text) { OutProblems.Add(FString::Printf(TEXT("%s: %s"), *CarId.ToString(), Text)); };

	if (CarId.IsNone()) { Problem(TEXT("CarId is empty")); }
	if (MassKg < 300.0f) { Problem(TEXT("MassKg < 300")); }
	if (Engine.TorqueCurve.Num() < 2) { Problem(TEXT("torque curve needs >= 2 points")); }
	if (Engine.RedlineRPM <= Engine.IdleRPM) { Problem(TEXT("RedlineRPM <= IdleRPM")); }
	if (Engine.RevLimiterRPM < Engine.RedlineRPM) { Problem(TEXT("RevLimiterRPM < RedlineRPM")); }
	if (Gearbox.ForwardRatios.Num() < 1) { Problem(TEXT("no forward gears")); }
	for (float R : Gearbox.ForwardRatios)
	{
		if (R <= 0.0f) { Problem(TEXT("gear ratio <= 0")); break; }
	}
	if (Gearbox.FinalDrive <= 0.0f) { Problem(TEXT("FinalDrive <= 0")); }
	if (Geometry.WheelbaseCm <= 100.0f) { Problem(TEXT("WheelbaseCm too small")); }
	for (int32 i = 0; i < Roam::NumWheels; ++i)
	{
		if (Geometry.GetWheel(i).RadiusCm < 10.0f) { Problem(TEXT("wheel radius < 10 cm")); break; }
	}
	if (Geometry.WheelFL.CenterCm.Y > 0.0f || Geometry.WheelFR.CenterCm.Y < 0.0f)
	{
		Problem(TEXT("left wheels must have negative Y and right wheels positive Y (UE car space)"));
	}
	if (Aero.CdA <= 0.0f) { Problem(TEXT("Aero.CdA <= 0")); }
	return OutProblems.Num() == Before;
}

FString URoamCarDefinition::ToDebugString() const
{
	return FString::Printf(TEXT("%s (%s) %s"), *CarId.ToString(), *DisplayName.ToString(), *GetClassLabel());
}
