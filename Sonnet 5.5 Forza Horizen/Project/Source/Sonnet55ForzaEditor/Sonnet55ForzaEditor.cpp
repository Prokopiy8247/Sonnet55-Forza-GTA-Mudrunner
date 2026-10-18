// Copyright Epic Games, Inc. All Rights Reserved.

#include "Sonnet55ForzaEditor.h"
#include "Modules/ModuleManager.h"
#include "Core/RoamLog.h"

IMPLEMENT_MODULE(FSonnet55ForzaEditorModule, Sonnet55ForzaEditor)

void FSonnet55ForzaEditorModule::StartupModule()
{
	UE_LOG(LogRoam, Log, TEXT("Sonnet55ForzaEditor module started"));
}

void FSonnet55ForzaEditorModule::ShutdownModule()
{
	UE_LOG(LogRoam, Log, TEXT("Sonnet55ForzaEditor module shut down"));
}
