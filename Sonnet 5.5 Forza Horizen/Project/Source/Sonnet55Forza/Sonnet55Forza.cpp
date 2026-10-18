// Copyright Epic Games, Inc. All Rights Reserved.

#include "Sonnet55Forza.h"
#include "Modules/ModuleManager.h"

// Log categories are defined in Core/RoamLog.cpp. The module itself needs no startup logic: every system bootstraps through
// subsystems (UGameInstanceSubsystem / UWorldSubsystem) so nothing here has to be edited when systems are added.
IMPLEMENT_PRIMARY_GAME_MODULE( FDefaultGameModuleImpl, Sonnet55Forza, "Sonnet55Forza" );
