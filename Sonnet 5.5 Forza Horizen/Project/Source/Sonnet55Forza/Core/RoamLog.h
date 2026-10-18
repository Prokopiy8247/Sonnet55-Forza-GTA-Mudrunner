// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Logging/LogMacros.h"

/**
 * Log categories of "Roamline: Open Roads".
 *
 * All categories are declared AND defined centrally (Core/RoamLog.cpp) so that no agent has to touch a shared file to add
 * a log channel. Use the category of your area; use LogRoam for cross-cutting messages (bootstrap, data loading, tests).
 *
 * Test/automation convention: lines that a script must be able to grep for start with a stable upper-case token, e.g.
 *   UE_LOG(LogRoam, Display, TEXT("ROAM_SPAWN car=%s"), ...)
 */
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoam, Log, All);          // general / bootstrap / data
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoamVehicle, Log, All);   // vehicle physics, drivetrain, camera, FX
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoamAudio, Log, All);     // engine synth, ambience
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoamWorld, Log, All);     // time/weather, sky, regions, road network
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoamTraffic, Log, All);   // traffic subsystem and agents
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoamActivity, Log, All);  // activities / events / scoring
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoamUI, Log, All);        // HUD, menus, console widget
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoamConsole, Log, All);   // the Roam developer console
SONNET55FORZA_API DECLARE_LOG_CATEGORY_EXTERN(LogRoamSave, Log, All);      // save game / profile
