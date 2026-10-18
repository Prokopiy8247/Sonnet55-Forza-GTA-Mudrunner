// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Modules/ModuleInterface.h"

/** Editor-only module of Roamline. Startup only logs; tooling is exposed through URoamEditorLibrary (Python) and commandlets. */
class FSonnet55ForzaEditorModule : public IModuleInterface
{
public:
	virtual void StartupModule() override;
	virtual void ShutdownModule() override;
};
