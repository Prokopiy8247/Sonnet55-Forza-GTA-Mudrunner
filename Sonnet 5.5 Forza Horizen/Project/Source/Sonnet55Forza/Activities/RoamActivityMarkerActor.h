// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Activities/RoamActivityActor.h"
#include "RoamActivityMarkerActor.generated.h"

class UInstancedStaticMeshComponent;
class UMaterialInterface;
class UMaterialInstanceDynamic;

/**
 * The visible gate marker of an activity, spawned by URoamActivitySubsystem from an FRoamActivityDef (runtime-generated
 * activities have no placed props). Pure presentation: gantries (two posts, a beam and a banner plate) built from engine shapes in
 * two instanced mesh components, tinted per activity type with the engine's BasicShapeMaterial "Color" parameter. Intermediate
 * checkpoints are smaller than start/finish gates; collectibles and photo spots are a tall beacon column with a diamond on top.
 * No collision, no tick: the subsystem evaluates the gates.
 */
UCLASS()
class SONNET55FORZA_API ARoamActivityMarkerActor : public ARoamActivityActor
{
	GENERATED_BODY()

public:
	ARoamActivityMarkerActor();

	/** Builds all instances for the definition's gates and tints them. Safe to call again (rebuilds). */
	void BuildFromDefinition(const FRoamActivityDef& Definition);

	virtual void OnActivityStateChanged(ERoamActivityState NewState) override;
	virtual void OnActivityResult(const FRoamActivityResult& Result) override;

	/** Number of mesh instances currently shown (tests / debugging). */
	int32 GetNumInstances() const;

private:
	void AddGantry(const FRoamGate& Gate, float Scale, bool bBigBanner);
	void AddBeacon(const FRoamGate& Gate);
	void SetTint(const FLinearColor& Color);

	UPROPERTY(Transient)
	TObjectPtr<UInstancedStaticMeshComponent> PostInstances;

	UPROPERTY(Transient)
	TObjectPtr<UInstancedStaticMeshComponent> PlateInstances;

	UPROPERTY(Transient)
	TObjectPtr<UMaterialInterface> BaseMaterial;

	UPROPERTY(Transient)
	TObjectPtr<UMaterialInstanceDynamic> TintMaterial;

	FLinearColor Tint = FLinearColor::White;
};
