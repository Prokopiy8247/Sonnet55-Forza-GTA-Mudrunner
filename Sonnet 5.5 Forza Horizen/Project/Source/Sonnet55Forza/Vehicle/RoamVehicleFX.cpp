// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamVehicleFX.h"

URoamVehicleFX::URoamVehicleFX()
{
	// No tick of its own: ARoamVehicle feeds UpdateFromTelemetry once per frame.
	PrimaryComponentTick.bCanEverTick = false;
}

void URoamVehicleFX::UpdateFromTelemetry(const FRoamVehicleTelemetry& Telemetry, float DeltaTime)
{
	// OWNER: effects agent. Tyre smoke/dust/spray from WheelSlip*, Surface, SurfaceWetness and speed; brake glow; exhaust flames.
	(void)Telemetry;
	(void)DeltaTime;
}

void URoamVehicleFX::NotifyImpact(const FVector& Location, const FVector& Normal, float StrengthMs)
{
	// OWNER: effects agent. Sparks / debris / impact sound scaled by StrengthMs.
	(void)Location;
	(void)Normal;
	(void)StrengthMs;
}

void URoamVehicleFX::NotifyTeleported()
{
	// OWNER: effects agent. Clear skid trails and kill pending bursts.
}
