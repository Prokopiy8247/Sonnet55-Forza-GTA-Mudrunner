// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"

class URoamCarDefinition;

/**
 * The ten roster cars as code-built URoamCarDefinition objects (no assets needed). The numbers come from RoamTestCarData.inl, generated
 * by Tools/ue/drive_test_cars_gen.py out of the SAME spec table that builds the DA_Car_* data assets (Tools/ue/cars_spec.py), so the
 * automation drive tests (Tests/RoamVehiclePhysicsTests.cpp, Docs/Tech/DRIVE_TESTS.md) and the `testcar` console command exercise the
 * values the final assets carry. Index order = Docs/CAR_ROSTER.md (0 = Pulse ... 9 = Brisa).
 */
namespace RoamTestCars
{
	SONNET55FORZA_API int32 Num();
	SONNET55FORZA_API FName IdOf(int32 Index);
	/** Creates a transient definition (outer given) for roster index 0..9; nullptr for an invalid index. */
	SONNET55FORZA_API URoamCarDefinition* Make(UObject* Outer, int32 Index);
	/** Resolves a 1-based number, an id or a unique substring ("pulse", "car03"). INDEX_NONE if not found. */
	SONNET55FORZA_API int32 Find(const FString& Query);
}
