// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "RoamCarCatalog.generated.h"

class URoamCarDefinition;

/**
 * Ordered list of the garage's cars (exactly 10 in the shipped game, see Docs/CAR_ROSTER.md). The order is the order shown in
 * the garage menu and the index used by the console command `car <index>` (1-based for users, 0-based in code).
 * Referenced from URoamSettings::CarCatalog; loaded once by URoamGameInstance.
 */
UCLASS(BlueprintType)
class SONNET55FORZA_API URoamCarCatalog : public UDataAsset
{
	GENERATED_BODY()

public:
	/** The cars in garage order. Soft references so that the catalog can be listed without loading every mesh. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Catalog")
	TArray<TSoftObjectPtr<URoamCarDefinition>> Cars;

	/** Number of entries (including entries that fail to load). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Catalog")
	int32 GetNumCars() const { return Cars.Num(); }

	/** Loads (synchronously) and returns the definition at an index, or nullptr. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Catalog")
	URoamCarDefinition* GetCarByIndex(int32 Index) const;

	/** Finds a car by CarId (exact, case-insensitive). Loads definitions on demand. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Catalog")
	URoamCarDefinition* FindCarById(FName CarId) const;

	/** Index of CarId or INDEX_NONE. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Catalog")
	int32 IndexOfCar(FName CarId) const;

	/**
	 * Resolves user text to a car: a 1-based index ("3"), an exact CarId, a unique prefix/substring of the CarId or of the
	 * display name ("pulse", "muscle", "car05"). Returns nullptr and fills OutError if nothing/ambiguous.
	 */
	URoamCarDefinition* ResolveCar(const FString& Text, FString* OutError = nullptr, int32* OutIndex = nullptr) const;

	/** Loads every definition and returns them (skipping failures). */
	void LoadAll(TArray<URoamCarDefinition*>& OutCars) const;

	/** Validates all entries (loadable, unique ids, each definition valid). */
	bool Validate(TArray<FString>& OutProblems) const;
};
