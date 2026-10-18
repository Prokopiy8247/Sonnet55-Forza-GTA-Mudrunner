// Copyright Epic Games, Inc. All Rights Reserved.

#include "Core/RoamSettings.h"

#include "PhysicalMaterials/PhysicalMaterial.h"
#include "Vehicle/RoamVehicle.h"

URoamSettings::URoamSettings()
{
	CategoryName = TEXT("Game");
	SectionName = TEXT("Roamline");
}

ERoamSurface URoamSettings::ResolveSurface(const UPhysicalMaterial* PhysicalMaterial) const
{
	if (!PhysicalMaterial)
	{
		return ERoamSurface::Asphalt;
	}
	if (PhysicalMaterialToSurface.Num() > 0)
	{
		for (const TPair<TSoftObjectPtr<UPhysicalMaterial>, ERoamSurface>& Pair : PhysicalMaterialToSurface)
		{
			// Compare by object identity without loading: the soft path of a loaded asset resolves to the same object.
			if (Pair.Key.Get() == PhysicalMaterial)
			{
				return Pair.Value;
			}
		}
	}
	return Roam::SurfaceFromPhysicalSurface(PhysicalMaterial->SurfaceType);
}

TSubclassOf<ARoamVehicle> URoamSettings::LoadVehicleClass() const
{
	if (!DefaultVehicleClass.IsNull())
	{
		if (UClass* Loaded = DefaultVehicleClass.LoadSynchronous())
		{
			return Loaded;
		}
	}
	return ARoamVehicle::StaticClass();
}
