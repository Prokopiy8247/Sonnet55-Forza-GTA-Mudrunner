// Copyright Epic Games, Inc. All Rights Reserved.

#include "Data/RoamWorldDefinition.h"

const FRoamRegionDef* URoamWorldDefinition::FindRegionAt(const FVector& WorldLocation) const
{
	const FRoamRegionDef* Best = nullptr;
	for (const FRoamRegionDef& Region : Regions)
	{
		if (Region.Contains(WorldLocation) && (!Best || Region.Priority > Best->Priority))
		{
			Best = &Region;
		}
	}
	return Best;
}

const FRoamRegionDef* URoamWorldDefinition::FindRegion(FName RegionId) const
{
	return Regions.FindByPredicate([RegionId](const FRoamRegionDef& R) { return R.RegionId == RegionId; });
}

const FRoamPoiDef* URoamWorldDefinition::FindPoi(FName PoiId) const
{
	return Pois.FindByPredicate([PoiId](const FRoamPoiDef& P) { return P.PoiId == PoiId; });
}

const FRoamActivityDef* URoamWorldDefinition::FindActivity(FName ActivityId) const
{
	return Activities.FindByPredicate([ActivityId](const FRoamActivityDef& A) { return A.ActivityId == ActivityId; });
}

bool URoamWorldDefinition::ResolveTeleportTarget(const FString& Text, FVector& OutLocation, float& OutYawDeg, FString* OutLabel, FString* OutError) const
{
	const FString Query = Text.TrimStartAndEnd();
	if (Query.IsEmpty())
	{
		if (OutError) { *OutError = TEXT("empty teleport target"); }
		return false;
	}

	struct FCandidate
	{
		FVector Location;
		float Yaw;
		FString Label;
		bool bExact;
		bool bPoi; // world-builder: a POI wins over a region of the same name ("tp crossroads" = the hub, not the basin)
	};
	TArray<FCandidate> Found;

	const auto Consider = [&](const FString& Id, const FString& Name, const FVector& Location, float Yaw, bool bPoi)
	{
		const bool bExact = Id.Equals(Query, ESearchCase::IgnoreCase) || Name.Equals(Query, ESearchCase::IgnoreCase);
		if (bExact || Id.Contains(Query, ESearchCase::IgnoreCase) || Name.Contains(Query, ESearchCase::IgnoreCase))
		{
			Found.Add({ Location, Yaw, Name.IsEmpty() ? Id : Name, bExact, bPoi });
		}
	};

	for (const FRoamPoiDef& Poi : Pois)
	{
		if (Poi.bTeleportTarget)
		{
			Consider(Poi.PoiId.ToString(), Poi.DisplayName.ToString(), Poi.Location, Poi.YawDeg, true);
		}
	}
	// --- changed by world-builder (F1): a region may consist of several rectangles that share one RegionId (generated worlds); only the FIRST
	// rectangle of a region (the largest one, see Tools/ue/world_regions_gen.py) is its teleport target, otherwise `tp <region>` is "ambiguous".
	TSet<FName> SeenRegions;
	for (const FRoamRegionDef& Region : Regions)
	{
		bool bAlreadySeen = false;
		SeenRegions.Add(Region.RegionId, &bAlreadySeen);
		if (bAlreadySeen)
		{
			continue;
		}
		const FVector Centre(0.5 * (Region.MinXY.X + Region.MaxXY.X), 0.5 * (Region.MinXY.Y + Region.MaxXY.Y), 0.0);
		Consider(Region.RegionId.ToString(), Region.DisplayName.ToString(), Centre, 0.0f, false);
	}

	TArray<FCandidate> Exact = Found.FilterByPredicate([](const FCandidate& C) { return C.bExact; });
	if (Exact.Num() > 1 && Exact.ContainsByPredicate([](const FCandidate& C) { return C.bPoi; }))
	{
		Exact = Exact.FilterByPredicate([](const FCandidate& C) { return C.bPoi; });
	}
	const TArray<FCandidate>& Use = Exact.Num() > 0 ? Exact : Found;
	if (Use.Num() == 0)
	{
		if (OutError) { *OutError = FString::Printf(TEXT("unknown teleport target '%s'"), *Query); }
		return false;
	}
	if (Use.Num() > 1)
	{
		if (OutError)
		{
			FString List;
			for (const FCandidate& C : Use)
			{
				List += (List.IsEmpty() ? FString() : FString(TEXT(", "))) + C.Label;
			}
			*OutError = FString::Printf(TEXT("'%s' is ambiguous: %s"), *Query, *List);
		}
		return false;
	}
	OutLocation = Use[0].Location;
	OutYawDeg = Use[0].Yaw;
	if (OutLabel) { *OutLabel = Use[0].Label; }
	return true;
}
