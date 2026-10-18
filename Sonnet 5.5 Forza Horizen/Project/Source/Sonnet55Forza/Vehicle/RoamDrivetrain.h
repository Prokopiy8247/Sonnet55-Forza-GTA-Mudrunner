// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Data/RoamCarDefinition.h"

/**
 * Engine + clutch + automatic/manual gearbox of the project-owned vehicle model (Docs/Tech/DRIVE_TESTS.md "Drivetrain").
 * Pure C++ state machine without engine objects: one Step() per physics solver step, deterministic, unit-testable.
 *
 * COUPLING MODEL (no stiff clutch spring): the engine is rigidly tied to the wheels while the wheel-driven RPM is above the
 * clutch floor (idle, rising towards the launch RPM with the pedal). Below it the clutch slips: the engine sits at the floor RPM and
 * the torque of that RPM reaches the wheels (the same launch model the PI estimator in URoamCarDefinition::ComputePerformance uses).
 * While locked the engine inertia is reflected into the wheels (ReflectedInertia = Ie * ratio^2), so spin-up of the wheels and of
 * the engine is one consistent system; while slipping, shifting or in neutral nothing is reflected.
 */
class FRoamDrivetrain
{
public:
	struct FInput
	{
		/** Pedal that drives the engine (0..1): the throttle in forward gears, the brake pedal in reverse. */
		float DrivePedal = 0.0f;
		float ThrottlePedal = 0.0f;
		float BrakePedal = 0.0f;
		/** Signed speed along the car's heading in m/s. */
		float ForwardSpeedMs = 0.0f;
		/** Share-weighted angular speed of the driven wheels, rad/s, positive = rolling forward. */
		float DrivenOmega = 0.0f;
		bool bAutomatic = true;
		/** Traction-control factor 0..1 multiplying positive engine torque. */
		float TcsFactor = 1.0f;
	};

	/** Copies the spec (and applies tuning: final-drive multiplier, gear spacing). Resets the state. */
	void Configure(const URoamCarDefinition* Definition, const FRoamTuning& Tuning, float AverageWheelRadiusM);
	void Reset();
	void Step(float Dt, const FInput& Input);

	/** Manual shifting: +1 up, -1 down (consumed in the next Step, honours the speed rules for reverse). */
	void RequestShift(int32 Direction) { PendingShift += Direction; }

	/** Total ratio (gear x final drive) of a gear, positive; 0 for neutral. Gear -1 = reverse. */
	float GetTotalRatio(int32 Gear) const;
	int32 GetNumForwardGears() const { return Ratios.Num(); }
	/** RPM the engine would have at a speed in a gear (no slip). */
	float SpeedToRpm(int32 GearToUse, float SpeedMs) const;
	float GetIdleRpm() const { return Idle; }
	float GetRedlineRpm() const { return Redline; }

	// ---- state / outputs (read by the movement component) -----------------------------------------------------------
	int32 Gear = 1;
	float EngineRPM = 900.0f;
	/** Crankshaft torque in Nm (negative = engine braking). */
	float EngineTorqueNm = 0.0f;
	/** Torque at the driven wheels' axles in Nm, signed (positive = pushes the car forward). Zero while shifting / in neutral. */
	float WheelTorqueNm = 0.0f;
	/** Engine inertia seen from the wheels in kg*m^2 (0 when the clutch is open or slipping). */
	float ReflectedInertia = 0.0f;
	bool bSlipping = false;
	bool bShifting = false;
	bool bLimiterCut = false;
	float Boost01 = 0.0f;
	float ThrottleFiltered = 0.0f;
	float ShiftTimer = 0.0f;
	/** Upgrade / tuning multiplier on the engine torque curve. */
	float TorqueScale = 1.0f;

private:
	void SetGear(int32 NewGear, bool bTimedShift);

	// configuration
	const FRoamEngineSpec* Engine = nullptr;
	TArray<float> Ratios;
	float ReverseRatio = 3.4f;
	float FinalDrive = 4.0f;
	float Efficiency = 0.9f;
	float ShiftTime = 0.25f;
	float UpFraction = 0.96f;
	float DownFraction = 0.45f;
	float Idle = 900.0f;
	float Redline = 6800.0f;
	float Limiter = 7000.0f;
	float LaunchRpm = 3000.0f;
	float WheelRadius = 0.33f;
	// state
	float TimeInGear = 0.0f;
	float ReverseTimer = 0.0f;
	int32 PendingShift = 0;
};

namespace RoamDrive
{
	/**
	 * Torque bias of a limited-slip / locked differential. Returned value X is ADDED to the right wheel's torque and subtracted from
	 * the left one's: positive when the left wheel runs faster (torque moves to the slower wheel). Open differentials return 0.
	 */
	float DiffBias(ERoamDiffType Type, float LockAccel, float LockDecel, float PreloadNm, float AxleTorqueNm, float OmegaLeft, float OmegaRight);

	/** Share of the engine torque sent to the REAR axle of an AWD car after the centre differential bias. */
	float CenterRearShare(ERoamDiffType Type, float BaseRearShare, float CenterLock, float OmegaFrontAvg, float OmegaRearAvg);
}
