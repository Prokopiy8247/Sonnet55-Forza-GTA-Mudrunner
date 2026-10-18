// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Components/StaticMeshComponent.h"
#include "RoamVehicleBody.generated.h"

class UBodySetup;

/**
 * The root body of ARoamVehicle. A normal static mesh component whose collision shape can be replaced by a box proxy: cars without an
 * imported body mesh (tests, the placeholder look, a car whose body mesh fails to load) still need a physics body, and the engine
 * only creates one for a static mesh component that has a mesh. The proxy keeps the engine cube as the (hidden) mesh and answers
 * GetBodySetup() with a runtime body setup that holds one box sized and placed like the car.
 * Real cars keep the UCX convex hulls of their Blender body mesh: the proxy is switched off as soon as ClearProxy() is called.
 */
UCLASS(ClassGroup = (Roam))
class SONNET55FORZA_API URoamVehicleBody : public UStaticMeshComponent
{
	GENERATED_BODY()

public:
	virtual UBodySetup* GetBodySetup() override;

	/** Full box size and centre in component space (cm). Recreates the physics state. */
	void SetProxyBox(const FVector& SizeCm, const FVector& CenterCm);
	void ClearProxy();
	bool IsUsingProxy() const { return bUseProxy && ProxySetup != nullptr; }

private:
	UPROPERTY(Transient)
	TObjectPtr<UBodySetup> ProxySetup;

	bool bUseProxy = false;
};
