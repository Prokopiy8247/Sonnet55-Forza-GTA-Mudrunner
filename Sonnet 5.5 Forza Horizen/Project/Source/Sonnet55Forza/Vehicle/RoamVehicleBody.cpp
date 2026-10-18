// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamVehicleBody.h"

#include "PhysicsEngine/BodySetup.h"
#include "PhysicsEngine/BoxElem.h"

UBodySetup* URoamVehicleBody::GetBodySetup()
{
	if (bUseProxy && ProxySetup)
	{
		return ProxySetup;
	}
	return Super::GetBodySetup();
}

void URoamVehicleBody::SetProxyBox(const FVector& SizeCm, const FVector& CenterCm)
{
	UBodySetup* Setup = NewObject<UBodySetup>(this, NAME_None, RF_Transient);
	Setup->BodySetupGuid = FGuid::NewGuid();
	Setup->CollisionTraceFlag = CTF_UseSimpleAsComplex;
	FKBoxElem Box(static_cast<float>(SizeCm.X), static_cast<float>(SizeCm.Y), static_cast<float>(SizeCm.Z));
	Box.Center = CenterCm;
	Setup->AggGeom.BoxElems.Add(Box);
	Setup->CreatePhysicsMeshes();
	ProxySetup = Setup;
	bUseProxy = true;
	RecreatePhysicsState();
}

void URoamVehicleBody::ClearProxy()
{
	if (!bUseProxy)
	{
		return;
	}
	bUseProxy = false;
	ProxySetup = nullptr;
	RecreatePhysicsState();
}
