// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Engine/EngineTypes.h"

/**
 * Collision channel and profile names of Roamline (Docs/ARCHITECTURE.md section 7). The channels are DEFINED in
 * Config/DefaultEngine.ini ([/Script/Engine.CollisionProfile] DefaultChannelResponses); this header only gives them names so
 * code never uses magic ECC_GameTraceChannelN numbers. Keep the two in sync.
 *
 *   object channels:  Roam_Vehicle (GameTraceChannel1), Roam_Traffic (2), Roam_Pickup (3)
 *   trace channels:   Roam_Wheel (4)  - wheel/suspension rays, vehicle-vs-ground queries
 *                     Roam_Camera (5) - camera collision probes
 *   Both trace channels default to IGNORE: pawns, characters, spectators and props must never intercept the ground rays. Only
 *   objects with the RoamWorldStatic profile (or an explicit Block response) are ground / camera obstacles - the world builder must
 *   assign it to landscape, road meshes, terrain, buildings and rocks.
 *
 * PROFILES (also in DefaultEngine.ini):
 *   RoamVehicle      player/AI car body: ObjectType Roam_Vehicle, blocks world + Roam_Vehicle + Roam_Traffic, ignores Roam_Wheel/Roam_Camera
 *   RoamTraffic      civilian car body: ObjectType Roam_Traffic, blocks world + Roam_Vehicle, ignores other traffic and rays
 *   RoamWorldStatic  roads, terrain, buildings: blocks everything incl. Roam_Wheel and Roam_Camera
 *   RoamPickup       collectibles: ObjectType Roam_Pickup, overlaps Roam_Vehicle only
 */
namespace RoamCollision
{
	constexpr ECollisionChannel ObjectVehicle = ECC_GameTraceChannel1;
	constexpr ECollisionChannel ObjectTraffic = ECC_GameTraceChannel2;
	constexpr ECollisionChannel ObjectPickup = ECC_GameTraceChannel3;
	constexpr ECollisionChannel TraceWheel = ECC_GameTraceChannel4;
	constexpr ECollisionChannel TraceCamera = ECC_GameTraceChannel5;

	inline const FName ProfileVehicle(TEXT("RoamVehicle"));
	inline const FName ProfileTraffic(TEXT("RoamTraffic"));
	inline const FName ProfileWorldStatic(TEXT("RoamWorldStatic"));
	inline const FName ProfilePickup(TEXT("RoamPickup"));

	/** Actor tags used by the world builder and queries (Docs/ARCHITECTURE.md section 7). */
	inline const FName TagRoad(TEXT("RoamRoad"));
	inline const FName TagDrivable(TEXT("RoamDrivable"));
	/** Components with this tag fail a Danger Sign landing when hit (trees, rocks, buildings). */
	inline const FName TagStuntFail(TEXT("StuntFail"));
}
