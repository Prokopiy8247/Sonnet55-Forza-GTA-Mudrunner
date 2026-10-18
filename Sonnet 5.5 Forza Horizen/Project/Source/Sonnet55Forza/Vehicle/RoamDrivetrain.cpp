// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamDrivetrain.h"

namespace
{
	FORCEINLINE float SmoothStep01(float A, float B, float X)
	{
		const float T = FMath::Clamp((X - A) / FMath::Max(B - A, 1.0e-4f), 0.0f, 1.0f);
		return T * T * (3.0f - 2.0f * T);
	}
}

void FRoamDrivetrain::Configure(const URoamCarDefinition* Definition, const FRoamTuning& Tuning, float AverageWheelRadiusM)
{
	check(Definition);
	Engine = &Definition->Engine;
	const FRoamGearboxSpec& Gearbox = Definition->Gearbox;
	Ratios = Gearbox.ForwardRatios;
	if (Ratios.Num() == 0)
	{
		Ratios = { 3.6f, 2.2f, 1.5f, 1.12f, 0.9f, 0.76f };
	}
	// GearSpacing (-1..+1): re-spaces the intermediate ratios around the fixed first and last gear by bending the geometric progression.
	if (Ratios.Num() > 2 && !FMath::IsNearlyZero(Tuning.GearSpacing))
	{
		const float First = Ratios[0];
		const float Last = Ratios.Last();
		const int32 N = Ratios.Num();
		const float Exponent = FMath::Pow(2.0f, -Tuning.GearSpacing);   // < 1 packs the gears towards first, > 1 towards the top
		for (int32 i = 1; i < N - 1; ++i)
		{
			const float T = FMath::Pow(static_cast<float>(i) / static_cast<float>(N - 1), Exponent);
			Ratios[i] = First * FMath::Pow(Last / First, T);
		}
	}
	ReverseRatio = Gearbox.ReverseRatio;
	FinalDrive = Gearbox.FinalDrive * FMath::Clamp(Tuning.FinalDriveMultiplier, 0.5f, 1.6f);
	Efficiency = FMath::Clamp(Gearbox.Efficiency, 0.5f, 1.0f);
	ShiftTime = FMath::Max(Gearbox.ShiftTimeSec, 0.02f);
	UpFraction = Gearbox.UpshiftRpmFraction;
	DownFraction = Gearbox.DownshiftRpmFraction;
	Idle = Engine->IdleRPM;
	Redline = Engine->RedlineRPM;
	Limiter = FMath::Max(Engine->RevLimiterRPM, Redline + 50.0f);
	float PeakTorqueRpm = 0.0f;
	Engine->GetPeakTorqueNm(&PeakTorqueRpm);
	LaunchRpm = FMath::Clamp(0.65f * PeakTorqueRpm, Idle * 1.3f, Redline * 0.7f);
	WheelRadius = FMath::Max(AverageWheelRadiusM, 0.15f);
	Reset();
}

void FRoamDrivetrain::Reset()
{
	Gear = 1;
	EngineRPM = Idle;
	EngineTorqueNm = 0.0f;
	WheelTorqueNm = 0.0f;
	ReflectedInertia = 0.0f;
	bSlipping = false;
	bShifting = false;
	bLimiterCut = false;
	Boost01 = 0.0f;
	ThrottleFiltered = 0.0f;
	ShiftTimer = 0.0f;
	TimeInGear = 0.0f;
	ReverseTimer = 0.0f;
	PendingShift = 0;
}

float FRoamDrivetrain::GetTotalRatio(int32 InGear) const
{
	if (InGear > 0 && InGear <= Ratios.Num())
	{
		return Ratios[InGear - 1] * FinalDrive;
	}
	if (InGear < 0)
	{
		return ReverseRatio * FinalDrive;
	}
	return 0.0f;
}

float FRoamDrivetrain::SpeedToRpm(int32 GearToUse, float SpeedMs) const
{
	return FMath::Abs(SpeedMs) / WheelRadius * GetTotalRatio(GearToUse) * (30.0f / UE_PI);
}

void FRoamDrivetrain::SetGear(int32 NewGear, bool bTimedShift)
{
	if (NewGear == Gear)
	{
		return;
	}
	Gear = NewGear;
	TimeInGear = 0.0f;
	if (bTimedShift)
	{
		ShiftTimer = ShiftTime;
	}
}

void FRoamDrivetrain::Step(float Dt, const FInput& In)
{
	check(Engine);
	const int32 NumGears = Ratios.Num();
	const float SpeedAbs = FMath::Abs(In.ForwardSpeedMs);
	const bool bStopped = SpeedAbs < 1.0f;
	TimeInGear += Dt;
	ShiftTimer = FMath::Max(0.0f, ShiftTimer - Dt);

	// ---- driver direction: reverse is engaged by the brake pedal at a standstill, forward again by the throttle ------------
	if (Gear >= 0)
	{
		if (bStopped && In.BrakePedal > 0.15f && In.ThrottlePedal < 0.1f)
		{
			ReverseTimer += Dt;
			if (ReverseTimer > 0.15f)
			{
				SetGear(-1, false);
				ReverseTimer = 0.0f;
			}
		}
		else
		{
			ReverseTimer = 0.0f;
		}
		if (Gear == 0 && In.ThrottlePedal > 0.05f)
		{
			SetGear(1, false);
		}
	}
	else if (In.ThrottlePedal > 0.15f && In.BrakePedal < 0.1f && In.ForwardSpeedMs > -1.0f)
	{
		SetGear(1, false);
		PendingShift = 0;
	}

	// ---- forward gear selection ---------------------------------------------------------------------------------------------
	if (Gear >= 1)
	{
		if (PendingShift != 0)
		{
			if (!In.bAutomatic)
			{
				if (PendingShift > 0 && Gear < NumGears)
				{
					SetGear(Gear + 1, true);
				}
				else if (PendingShift < 0)
				{
					if (Gear > 1)
					{
						SetGear(Gear - 1, true);
					}
					else if (bStopped)
					{
						SetGear(-1, false);
					}
				}
			}
			PendingShift = 0;
		}
		else if (In.bAutomatic && ShiftTimer <= 0.0f && TimeInGear > 0.4f)
		{
			const float Thr = FMath::Clamp(In.ThrottlePedal, 0.0f, 1.0f);
			const float RpmNow = SpeedToRpm(Gear, SpeedAbs);
			const float UpThreshold = Redline * FMath::Lerp(0.60f, UpFraction, FMath::Pow(Thr, 0.6f));
			if (Gear < NumGears && RpmNow >= UpThreshold && SpeedToRpm(Gear + 1, SpeedAbs) > Idle * 1.4f)
			{
				SetGear(Gear + 1, true);
			}
			else if (Gear > 1)
			{
				const float DownThreshold = Redline * FMath::Lerp(0.28f, DownFraction, Thr);
				const bool bKickdown = Thr > 0.85f && RpmNow < Redline * 0.52f && SpeedToRpm(Gear - 1, SpeedAbs) < Redline * 0.9f;
				if (RpmNow < DownThreshold || bKickdown)
				{
					SetGear(Gear - 1, true);
				}
			}
		}
	}
	else
	{
		PendingShift = 0;
	}

	// ---- engine: throttle lag, turbo, rev limiter -------------------------------------------------------------------------
	const float ThrottleTarget = FMath::Clamp(In.DrivePedal, 0.0f, 1.0f);
	ThrottleFiltered += (ThrottleTarget - ThrottleFiltered) * (1.0f - FMath::Exp(-Dt / FMath::Max(Engine->ThrottleResponseSec, 0.01f)));

	const float Ratio = GetTotalRatio(Gear);
	const float RatioSigned = Gear < 0 ? -Ratio : Ratio;
	bShifting = ShiftTimer > 0.0f;
	const bool bOpen = (Gear == 0) || bShifting;
	const float DrivenRpm = FMath::Max(0.0f, RatioSigned * In.DrivenOmega) * (30.0f / UE_PI);
	const float Floor = Idle + (LaunchRpm - Idle) * SmoothStep01(0.05f, 0.7f, ThrottleFiltered);

	float RpmTarget;
	if (bOpen)
	{
		bSlipping = false;
		RpmTarget = (Gear == 0) ? Idle + (Redline * 0.92f - Idle) * ThrottleFiltered : FMath::Max(Idle, DrivenRpm);
	}
	else
	{
		bSlipping = DrivenRpm < Floor;
		RpmTarget = FMath::Max(DrivenRpm, Floor);
	}
	const float FollowRate = bOpen ? 14.0f : 45.0f;
	EngineRPM += (RpmTarget - EngineRPM) * (1.0f - FMath::Exp(-Dt * FollowRate));

	if (EngineRPM > Limiter)
	{
		bLimiterCut = true;
	}
	else if (EngineRPM < Limiter - 250.0f)
	{
		bLimiterCut = false;
	}

	if (Engine->bTurbo)
	{
		const float BoostTarget = ThrottleFiltered * SmoothStep01(Engine->TurboFullBoostRPM * 0.45f, Engine->TurboFullBoostRPM, EngineRPM);
		Boost01 += (BoostTarget - Boost01) * (1.0f - FMath::Exp(-Dt / FMath::Max(Engine->TurboSpoolTimeSec, 0.05f)));
	}
	else
	{
		Boost01 = 0.0f;
	}
	const float TurboFactor = Engine->bTurbo ? FMath::Lerp(Engine->TurboLagTorqueFraction, 1.0f, Boost01) : 1.0f;

	const float Full = Engine->GetTorqueNm(EngineRPM) * TurboFactor * TorqueScale;
	const float FrictionTorque = Engine->EngineBrakeNm * (0.15f + 0.85f * FMath::Clamp(EngineRPM / FMath::Max(Redline, 1.0f), 0.0f, 1.3f)) * SmoothStep01(Idle * 0.95f, Idle * 1.4f, EngineRPM);
	const float Thr = ThrottleFiltered;
	float Te = bLimiterCut ? -0.6f * FrictionTorque : Thr * Full - (1.0f - Thr) * FrictionTorque;
	EngineTorqueNm = Te;

	// ---- wheels ---------------------------------------------------------------------------------------------------------------
	if (bOpen || Ratio <= 0.0f)
	{
		WheelTorqueNm = 0.0f;
		ReflectedInertia = 0.0f;
		return;
	}
	if (Te > 0.0f)
	{
		Te *= FMath::Clamp(In.TcsFactor, 0.0f, 1.0f);
	}
	WheelTorqueNm = Te * RatioSigned * Efficiency;
	ReflectedInertia = bSlipping ? 0.0f : Engine->InertiaKgM2 * Ratio * Ratio;
}

namespace RoamDrive
{
	float DiffBias(ERoamDiffType Type, float LockAccel, float LockDecel, float PreloadNm, float AxleTorqueNm, float OmegaLeft, float OmegaRight)
	{
		if (Type == ERoamDiffType::Open)
		{
			return 0.0f;
		}
		const float Lock = Type == ERoamDiffType::Locked ? 1.0f : (AxleTorqueNm >= 0.0f ? LockAccel : LockDecel);
		const float Half = 0.5f * FMath::Abs(AxleTorqueNm);
		const float Cap = FMath::Min(Lock * Half + PreloadNm, Half + PreloadNm);
		return Cap * FMath::Tanh((OmegaLeft - OmegaRight) / 4.0f);
	}

	float CenterRearShare(ERoamDiffType Type, float BaseRearShare, float CenterLock, float OmegaFrontAvg, float OmegaRearAvg)
	{
		if (Type == ERoamDiffType::Open)
		{
			return BaseRearShare;
		}
		const float Lock = Type == ERoamDiffType::Locked ? 1.0f : CenterLock;
		return FMath::Clamp(BaseRearShare + Lock * 0.5f * FMath::Tanh((OmegaFrontAvg - OmegaRearAvg) / 4.0f), 0.05f, 0.95f);
	}
}
