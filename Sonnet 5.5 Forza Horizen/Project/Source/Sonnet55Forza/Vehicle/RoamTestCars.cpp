// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamTestCars.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Data/RoamCarDefinition.h"
#include "Vehicle/RoamVehicle.h"

#include "Vehicle/RoamTestCarData.inl"

namespace RoamTestCars
{
	int32 Num()
	{
		return UE_ARRAY_COUNT(GRoamTestCarIds);
	}

	FName IdOf(int32 Index)
	{
		return Index >= 0 && Index < Num() ? FName(GRoamTestCarIds[Index]) : NAME_None;
	}

	URoamCarDefinition* Make(UObject* Outer, int32 Index)
	{
		if (Index < 0 || Index >= Num())
		{
			return nullptr;
		}
		URoamCarDefinition* Definition = NewObject<URoamCarDefinition>(Outer ? Outer : GetTransientPackage(), NAME_None, RF_Transient);
		RoamFillTestCar(Index, Definition);
		return Definition;
	}

	int32 Find(const FString& Query)
	{
		if (Query.IsNumeric())
		{
			const int32 OneBased = FCString::Atoi(*Query);
			return OneBased >= 1 && OneBased <= Num() ? OneBased - 1 : INDEX_NONE;
		}
		int32 Found = INDEX_NONE;
		for (int32 i = 0; i < Num(); ++i)
		{
			const FString Id = FString(GRoamTestCarIds[i]);
			if (Id.Equals(Query, ESearchCase::IgnoreCase))
			{
				return i;
			}
			if (Id.Contains(Query, ESearchCase::IgnoreCase))
			{
				if (Found != INDEX_NONE)
				{
					return INDEX_NONE;   // ambiguous
				}
				Found = i;
			}
		}
		return Found;
	}
}

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("testcar", "testcar [n|id]", "Applies one of the ten roster cars built in code (drive-test numbers, no data assets needed) to the player car.", "debug",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		if (Ctx.NumArgs() == 0)
		{
			FString List;
			for (int32 i = 0; i < RoamTestCars::Num(); ++i)
			{
				List += FString::Printf(TEXT("%d %s\n"), i + 1, *RoamTestCars::IdOf(i).ToString());
			}
			return List;
		}
		ARoamVehicle* Vehicle = ARoamVehicle::GetPlayerVehicle(Ctx.World);
		if (!Vehicle)
		{
			return Ctx.Fail(TEXT("no player vehicle"));
		}
		const int32 Index = RoamTestCars::Find(Ctx.Arg(0));
		if (Index == INDEX_NONE)
		{
			return Ctx.Fail(TEXT("unknown test car (1..10, id or unique substring)"));
		}
		Vehicle->ApplyCarDefinition(RoamTestCars::Make(Vehicle, Index));
		return FString::Printf(TEXT("test car applied: %s"), *RoamTestCars::IdOf(Index).ToString());
	});
