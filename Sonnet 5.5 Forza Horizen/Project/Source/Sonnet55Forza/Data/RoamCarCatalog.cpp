// Copyright Epic Games, Inc. All Rights Reserved.

#include "Data/RoamCarCatalog.h"

#include "Core/RoamLog.h"
#include "Data/RoamCarDefinition.h"

URoamCarDefinition* URoamCarCatalog::GetCarByIndex(int32 Index) const
{
	if (!Cars.IsValidIndex(Index))
	{
		return nullptr;
	}
	return Cars[Index].LoadSynchronous();
}

URoamCarDefinition* URoamCarCatalog::FindCarById(FName CarId) const
{
	const int32 Index = IndexOfCar(CarId);
	return Index != INDEX_NONE ? GetCarByIndex(Index) : nullptr;
}

int32 URoamCarCatalog::IndexOfCar(FName CarId) const
{
	if (CarId.IsNone())
	{
		return INDEX_NONE;
	}
	for (int32 i = 0; i < Cars.Num(); ++i)
	{
		// Compare on the cheap soft path first (asset name usually equals the id), then on the loaded definition.
		if (const URoamCarDefinition* Def = Cars[i].LoadSynchronous())
		{
			if (Def->CarId == CarId)
			{
				return i;
			}
		}
	}
	return INDEX_NONE;
}

URoamCarDefinition* URoamCarCatalog::ResolveCar(const FString& Text, FString* OutError, int32* OutIndex) const
{
	const auto Fail = [&](const FString& Message) -> URoamCarDefinition*
	{
		if (OutError)
		{
			*OutError = Message;
		}
		return nullptr;
	};

	const FString Query = Text.TrimStartAndEnd();
	if (Query.IsEmpty())
	{
		return Fail(TEXT("empty car name"));
	}
	if (Cars.Num() == 0)
	{
		return Fail(TEXT("the car catalog is empty"));
	}

	// 1-based index.
	if (Query.IsNumeric() && !Query.Contains(TEXT(".")))
	{
		const int32 OneBased = FCString::Atoi(*Query);
		if (OneBased < 1 || OneBased > Cars.Num())
		{
			return Fail(FString::Printf(TEXT("car index must be 1..%d"), Cars.Num()));
		}
		if (OutIndex)
		{
			*OutIndex = OneBased - 1;
		}
		return GetCarByIndex(OneBased - 1);
	}

	TArray<int32> Exact;
	TArray<int32> Partial;
	for (int32 i = 0; i < Cars.Num(); ++i)
	{
		const URoamCarDefinition* Def = Cars[i].LoadSynchronous();
		if (!Def)
		{
			continue;
		}
		const FString Id = Def->CarId.ToString();
		const FString Name = Def->DisplayName.ToString();
		if (Id.Equals(Query, ESearchCase::IgnoreCase) || Name.Equals(Query, ESearchCase::IgnoreCase))
		{
			Exact.Add(i);
		}
		else if (Id.Contains(Query, ESearchCase::IgnoreCase) || Name.Contains(Query, ESearchCase::IgnoreCase))
		{
			Partial.Add(i);
		}
	}

	const TArray<int32>& Candidates = Exact.Num() > 0 ? Exact : Partial;
	if (Candidates.Num() == 0)
	{
		return Fail(FString::Printf(TEXT("no car matches '%s'"), *Query));
	}
	if (Candidates.Num() > 1)
	{
		FString List;
		for (int32 Index : Candidates)
		{
			List += FString::Printf(TEXT("%s%s"), List.IsEmpty() ? TEXT("") : TEXT(", "), *Cars[Index].LoadSynchronous()->CarId.ToString());
		}
		return Fail(FString::Printf(TEXT("'%s' is ambiguous: %s"), *Query, *List));
	}
	if (OutIndex)
	{
		*OutIndex = Candidates[0];
	}
	return GetCarByIndex(Candidates[0]);
}

void URoamCarCatalog::LoadAll(TArray<URoamCarDefinition*>& OutCars) const
{
	OutCars.Reset();
	for (const TSoftObjectPtr<URoamCarDefinition>& Soft : Cars)
	{
		if (URoamCarDefinition* Def = Soft.LoadSynchronous())
		{
			OutCars.Add(Def);
		}
	}
}

bool URoamCarCatalog::Validate(TArray<FString>& OutProblems) const
{
	const int32 Before = OutProblems.Num();
	TSet<FName> Seen;
	for (int32 i = 0; i < Cars.Num(); ++i)
	{
		const URoamCarDefinition* Def = Cars[i].LoadSynchronous();
		if (!Def)
		{
			OutProblems.Add(FString::Printf(TEXT("catalog entry %d (%s) does not load"), i, *Cars[i].ToString()));
			continue;
		}
		if (Seen.Contains(Def->CarId))
		{
			OutProblems.Add(FString::Printf(TEXT("duplicate CarId %s"), *Def->CarId.ToString()));
		}
		Seen.Add(Def->CarId);
		Def->Validate(OutProblems);
	}
	return OutProblems.Num() == Before;
}
