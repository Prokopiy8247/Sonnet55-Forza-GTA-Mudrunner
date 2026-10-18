// Copyright Epic Games, Inc. All Rights Reserved.

#include "Core/RoamTypes.h"
#include "PhysicalMaterials/PhysicalMaterial.h"

namespace Roam
{
	ERoamSurface SurfaceFromPhysicalSurface(EPhysicalSurface PhysicalSurface)
	{
		// SurfaceType1..SurfaceType8 <-> Asphalt..Mud (see the ERoamSurface comment and DefaultEngine.ini).
		const int32 Index = static_cast<int32>(PhysicalSurface) - static_cast<int32>(SurfaceType1);
		if (Index >= 0 && Index < static_cast<int32>(ERoamSurface::Count))
		{
			return static_cast<ERoamSurface>(Index);
		}
		return ERoamSurface::Asphalt;
	}

	EPhysicalSurface PhysicalSurfaceFromSurface(ERoamSurface Surface)
	{
		const int32 Index = FMath::Clamp(static_cast<int32>(Surface), 0, static_cast<int32>(ERoamSurface::Count) - 1);
		return static_cast<EPhysicalSurface>(static_cast<int32>(SurfaceType1) + Index);
	}

	float SurfaceGripMultiplier(ERoamSurface Surface, float Wetness01)
	{
		struct FRow { float Dry; float Wet; float Soaked; };
		static const FRow Table[static_cast<int32>(ERoamSurface::Count)] =
		{
			{ 1.00f, 0.72f, 0.62f }, // Asphalt
			{ 0.97f, 0.70f, 0.60f }, // Concrete
			{ 0.78f, 0.55f, 0.45f }, // Dirt
			{ 0.70f, 0.56f, 0.50f }, // Gravel
			{ 0.60f, 0.44f, 0.38f }, // Grass
			{ 0.55f, 0.58f, 0.52f }, // Sand
			{ 0.35f, 0.34f, 0.32f }, // Snow
			{ 0.45f, 0.42f, 0.36f }, // Mud
		};
		const int32 Index = FMath::Clamp(static_cast<int32>(Surface), 0, static_cast<int32>(ERoamSurface::Count) - 1);
		const FRow& Row = Table[Index];
		const float W = FMath::Clamp(Wetness01, 0.0f, 1.0f);
		constexpr float WetKnot = 0.7f;
		if (W <= WetKnot)
		{
			return FMath::Lerp(Row.Dry, Row.Wet, W / WetKnot);
		}
		return FMath::Lerp(Row.Wet, Row.Soaked, (W - WetKnot) / (1.0f - WetKnot));
	}

	float SurfaceRollingResistanceFactor(ERoamSurface Surface)
	{
		switch (Surface)
		{
		case ERoamSurface::Asphalt:  return 1.0f;
		case ERoamSurface::Concrete: return 1.0f;
		case ERoamSurface::Gravel:   return 2.0f;
		case ERoamSurface::Dirt:     return 3.5f;
		case ERoamSurface::Snow:     return 4.0f;
		case ERoamSurface::Grass:    return 7.0f;
		case ERoamSurface::Mud:      return 8.0f;
		case ERoamSurface::Sand:     return 10.0f;
		default: break;
		}
		return 1.0f;
	}

	ERoamCarClass ClassFromPerformanceIndex(int32 PerformanceIndex)
	{
		if (PerformanceIndex <= 500) { return ERoamCarClass::D; }
		if (PerformanceIndex <= 600) { return ERoamCarClass::C; }
		if (PerformanceIndex <= 700) { return ERoamCarClass::B; }
		if (PerformanceIndex <= 800) { return ERoamCarClass::A; }
		if (PerformanceIndex <= 900) { return ERoamCarClass::S1; }
		if (PerformanceIndex <= 998) { return ERoamCarClass::S2; }
		return ERoamCarClass::X;
	}

	FString ClassToLabel(ERoamCarClass Class)
	{
		switch (Class)
		{
		case ERoamCarClass::D:  return TEXT("D");
		case ERoamCarClass::C:  return TEXT("C");
		case ERoamCarClass::B:  return TEXT("B");
		case ERoamCarClass::A:  return TEXT("A");
		case ERoamCarClass::S1: return TEXT("S1");
		case ERoamCarClass::S2: return TEXT("S2");
		case ERoamCarClass::X:  return TEXT("X");
		}
		return TEXT("?");
	}

	FLinearColor ClassColor(ERoamCarClass Class)
	{
		switch (Class)
		{
		case ERoamCarClass::D:  return FLinearColor::FromSRGBColor(FColor(0x4F, 0xC3, 0xF7));
		case ERoamCarClass::C:  return FLinearColor::FromSRGBColor(FColor(0xFF, 0xD5, 0x4F));
		case ERoamCarClass::B:  return FLinearColor::FromSRGBColor(FColor(0xFF, 0x9F, 0x43));
		case ERoamCarClass::A:  return FLinearColor::FromSRGBColor(FColor(0xFF, 0x5C, 0x5C));
		case ERoamCarClass::S1: return FLinearColor::FromSRGBColor(FColor(0xB3, 0x6B, 0xFF));
		case ERoamCarClass::S2: return FLinearColor::FromSRGBColor(FColor(0x3F, 0x7B, 0xFF));
		case ERoamCarClass::X:  return FLinearColor::FromSRGBColor(FColor(0x3D, 0xDC, 0x84));
		}
		return FLinearColor::White;
	}

	bool ParseAssistName(const FString& Text, ERoamAssist& OutAssist)
	{
		const FString T = Text.TrimStartAndEnd().ToLower();
		struct FAlias { const TCHAR* Name; ERoamAssist Assist; };
		static const FAlias Aliases[] =
		{
			{ TEXT("tcs"), ERoamAssist::TractionControl },
			{ TEXT("tc"), ERoamAssist::TractionControl },
			{ TEXT("traction"), ERoamAssist::TractionControl },
			{ TEXT("tractioncontrol"), ERoamAssist::TractionControl },
			{ TEXT("stm"), ERoamAssist::StabilityControl },
			{ TEXT("esc"), ERoamAssist::StabilityControl },
			{ TEXT("sc"), ERoamAssist::StabilityControl },
			{ TEXT("stability"), ERoamAssist::StabilityControl },
			{ TEXT("stabilitycontrol"), ERoamAssist::StabilityControl },
			{ TEXT("abs"), ERoamAssist::ABS },
			{ TEXT("brakes"), ERoamAssist::ABS },
			{ TEXT("steer"), ERoamAssist::SteeringAssist },
			{ TEXT("steering"), ERoamAssist::SteeringAssist },
			{ TEXT("steeringassist"), ERoamAssist::SteeringAssist },
			{ TEXT("auto"), ERoamAssist::AutomaticGearbox },
			{ TEXT("automatic"), ERoamAssist::AutomaticGearbox },
			{ TEXT("automaticgearbox"), ERoamAssist::AutomaticGearbox },
			{ TEXT("gearbox"), ERoamAssist::AutomaticGearbox },
			{ TEXT("line"), ERoamAssist::DrivingLine },
			{ TEXT("drivingline"), ERoamAssist::DrivingLine },
			{ TEXT("racingline"), ERoamAssist::DrivingLine },
		};
		for (const FAlias& Alias : Aliases)
		{
			if (T == Alias.Name)
			{
				OutAssist = Alias.Assist;
				return true;
			}
		}
		return false;
	}

	FString AssistToShortName(ERoamAssist Assist)
	{
		switch (Assist)
		{
		case ERoamAssist::TractionControl:  return TEXT("TCS");
		case ERoamAssist::StabilityControl: return TEXT("STM");
		case ERoamAssist::ABS:              return TEXT("ABS");
		case ERoamAssist::SteeringAssist:   return TEXT("STEER");
		case ERoamAssist::AutomaticGearbox: return TEXT("AUTO");
		case ERoamAssist::DrivingLine:      return TEXT("LINE");
		default: break;
		}
		return TEXT("?");
	}
}

bool FRoamAssistSettings::Get(ERoamAssist Assist) const
{
	switch (Assist)
	{
	case ERoamAssist::TractionControl:  return bTractionControl;
	case ERoamAssist::StabilityControl: return bStabilityControl;
	case ERoamAssist::ABS:              return bABS;
	case ERoamAssist::SteeringAssist:   return SteeringAssist > 0.0f;
	case ERoamAssist::AutomaticGearbox: return bAutomaticGearbox;
	case ERoamAssist::DrivingLine:      return bDrivingLine;
	default: break;
	}
	return false;
}

void FRoamAssistSettings::Set(ERoamAssist Assist, bool bEnabled)
{
	switch (Assist)
	{
	case ERoamAssist::TractionControl:  bTractionControl = bEnabled; break;
	case ERoamAssist::StabilityControl: bStabilityControl = bEnabled; break;
	case ERoamAssist::ABS:              bABS = bEnabled; break;
	case ERoamAssist::SteeringAssist:   SteeringAssist = bEnabled ? 0.5f : 0.0f; break;
	case ERoamAssist::AutomaticGearbox: bAutomaticGearbox = bEnabled; break;
	case ERoamAssist::DrivingLine:      bDrivingLine = bEnabled; break;
	default: break;
	}
}
