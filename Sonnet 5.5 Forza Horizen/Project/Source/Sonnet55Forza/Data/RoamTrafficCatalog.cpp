// Copyright Epic Games, Inc. All Rights Reserved.

#include "Data/RoamTrafficCatalog.h"

#include "Engine/StaticMesh.h"

const FRoamTrafficVehicleDef* URoamTrafficCatalog::FindByTypeId(FName TypeId) const
{
	return Vehicles.FindByPredicate([TypeId](const FRoamTrafficVehicleDef& Def) { return Def.TypeId == TypeId; });
}

void URoamTrafficCatalog::GetSpecs(TArray<FRoamTrafficVehicleSpec>& OutSpecs) const
{
	OutSpecs.Reset(Vehicles.Num());
	for (const FRoamTrafficVehicleDef& Def : Vehicles)
	{
		OutSpecs.Add(Def.Spec);
	}
}

bool URoamTrafficCatalog::Validate(TArray<FString>& OutProblems) const
{
	const int32 StartProblems = OutProblems.Num();
	TSet<FName> Seen;
	for (const FRoamTrafficVehicleDef& Def : Vehicles)
	{
		const FString Id = Def.TypeId.ToString();
		if (Def.TypeId.IsNone())
		{
			OutProblems.Add(TEXT("traffic vehicle without TypeId"));
			continue;
		}
		if (Seen.Contains(Def.TypeId))
		{
			OutProblems.Add(FString::Printf(TEXT("%s: duplicate TypeId"), *Id));
		}
		Seen.Add(Def.TypeId);
		if (Def.Spec.TypeId != Def.TypeId)
		{
			OutProblems.Add(FString::Printf(TEXT("%s: Spec.TypeId differs"), *Id));
		}
		if (Def.Spec.BodyMesh.IsNull())
		{
			OutProblems.Add(FString::Printf(TEXT("%s: no body mesh"), *Id));
		}
		if (Def.Wheels.Num() < 4)
		{
			OutProblems.Add(FString::Printf(TEXT("%s: fewer than 4 wheels"), *Id));
		}
		for (const FRoamTrafficWheelDef& Wheel : Def.Wheels)
		{
			if (Wheel.Mesh.IsNull() || Wheel.RadiusCm <= 1.0f)
			{
				OutProblems.Add(FString::Printf(TEXT("%s: wheel %s has no mesh or radius"), *Id, *Wheel.PartName.ToString()));
			}
		}
		if (Def.Spec.LengthCm <= 1.0f || Def.Spec.WidthCm <= 1.0f || Def.Spec.HeightCm <= 1.0f || Def.Spec.MassKg <= 1.0f)
		{
			OutProblems.Add(FString::Printf(TEXT("%s: non-positive size or mass"), *Id));
		}
	}
	return OutProblems.Num() == StartProblems;
}
