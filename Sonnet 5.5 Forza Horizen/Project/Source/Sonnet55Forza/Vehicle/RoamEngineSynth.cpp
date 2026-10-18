// Copyright Epic Games, Inc. All Rights Reserved.

#include "Vehicle/RoamEngineSynth.h"

#include "Core/RoamLog.h"
#include "Data/RoamCarDefinition.h"
#include "Engine/Engine.h"
#include "Engine/World.h"

URoamEngineSynth::URoamEngineSynth(const FObjectInitializer& ObjectInitializer)
	: Super(ObjectInitializer)
{
	bAutoActivate = false;
	NumChannels = 2;
	PreferredBufferLength = 1024;
	static const float DefaultHarmonics[6] = { 1.0f, 0.55f, 0.35f, 0.22f, 0.12f, 0.08f };
	for (int32 i = 0; i < 6; ++i)
	{
		Harmonics[i].store(DefaultHarmonics[i], std::memory_order_relaxed);
	}
}

void URoamEngineSynth::ApplySoundSpec(const FRoamSoundSpec& Spec, float IdleRPM, float RedlineRPM)
{
	(void)RedlineRPM;
	NumCylinders.store(FMath::Clamp(Spec.Cylinders, 1, 16), std::memory_order_relaxed);
	PitchScale.store(Spec.PitchScale, std::memory_order_relaxed);
	NoiseAmount.store(Spec.NoiseAmount, std::memory_order_relaxed);
	ProfileVolume.store(Spec.Volume, std::memory_order_relaxed);
	for (int32 i = 0; i < 6; ++i)
	{
		Harmonics[i].store(Spec.HarmonicMix.IsValidIndex(i) ? Spec.HarmonicMix[i] : 0.0f, std::memory_order_relaxed);
	}
	TargetRPM.store(IdleRPM, std::memory_order_relaxed);
}

void URoamEngineSynth::SetEngineState(float RPM, float Load01, float Boost01)
{
	TargetRPM.store(FMath::Max(RPM, 0.0f), std::memory_order_relaxed);
	TargetLoad.store(FMath::Clamp(Load01, 0.0f, 1.0f), std::memory_order_relaxed);
	TargetBoost.store(FMath::Clamp(Boost01, 0.0f, 1.0f), std::memory_order_relaxed);
}

void URoamEngineSynth::SetEngineVolume(float Volume01)
{
	VolumeScale.store(FMath::Clamp(Volume01, 0.0f, 1.0f), std::memory_order_relaxed);
}

void URoamEngineSynth::SetMuted(bool bInMuted)
{
	bMutedFlag.store(bInMuted, std::memory_order_relaxed);
}

void URoamEngineSynth::StartIfAudible()
{
	// No audio device in commandlets, -nosound runs and servers: Start() would only log noise there.
	if (IsRunningCommandlet() || !GEngine || !GEngine->UseSound())
	{
		return;
	}
	const UWorld* World = GetWorld();
	if (!World || !World->GetAudioDeviceRaw())
	{
		return;
	}
	Start();
}

bool URoamEngineSynth::Init(int32& SampleRate)
{
	SampleRateHz = static_cast<float>(SampleRate);
	NumChannels = 2;
	return true;
}

int32 URoamEngineSynth::OnGenerateAudio(float* OutAudio, int32 NumSamples)
{
	// AUDIO THREAD. No allocations, no UObject access.
	const int32 Channels = FMath::Max(NumChannels, 1);
	const int32 Frames = NumSamples / Channels;

	if (bMutedFlag.load(std::memory_order_relaxed))
	{
		FMemory::Memzero(OutAudio, sizeof(float) * NumSamples);
		return NumSamples;
	}

	const float RpmTarget = TargetRPM.load(std::memory_order_relaxed);
	const float LoadTarget = TargetLoad.load(std::memory_order_relaxed);
	const float Cylinders = static_cast<float>(NumCylinders.load(std::memory_order_relaxed));
	const float Pitch = PitchScale.load(std::memory_order_relaxed);
	const float Noise = NoiseAmount.load(std::memory_order_relaxed);
	const float Volume = 0.18f * VolumeScale.load(std::memory_order_relaxed) * ProfileVolume.load(std::memory_order_relaxed);
	float Mix[6];
	float MixSum = 0.0001f;
	for (int32 i = 0; i < 6; ++i)
	{
		Mix[i] = Harmonics[i].load(std::memory_order_relaxed);
		MixSum += FMath::Abs(Mix[i]);
	}

	// One-pole smoothing towards the targets (~20 ms for RPM, ~40 ms for load) so game-frame steps never click.
	const float RpmCoeff = 1.0f - FMath::Exp(-1.0f / (0.020f * SampleRateHz));
	const float LoadCoeff = 1.0f - FMath::Exp(-1.0f / (0.040f * SampleRateHz));

	for (int32 Frame = 0; Frame < Frames; ++Frame)
	{
		CurrentRPM += (RpmTarget - CurrentRPM) * RpmCoeff;
		CurrentLoad += (LoadTarget - CurrentLoad) * LoadCoeff;

		// Four-stroke: every cylinder fires once per two revolutions.
		const double FiringHz = static_cast<double>(CurrentRPM) / 60.0 * static_cast<double>(Cylinders) * 0.5 * static_cast<double>(Pitch);
		Phase += FiringHz / static_cast<double>(SampleRateHz);
		Phase -= FMath::FloorToDouble(Phase);

		float Sample = 0.0f;
		for (int32 k = 0; k < 6; ++k)
		{
			const float Brightness = (k == 0) ? 1.0f : (0.4f + 0.6f * CurrentLoad);
			Sample += Mix[k] * Brightness * FMath::Sin(static_cast<float>(UE_TWO_PI * static_cast<double>(k + 1) * Phase));
		}
		Sample /= MixSum;

		// xorshift noise
		NoiseState ^= NoiseState << 13;
		NoiseState ^= NoiseState >> 17;
		NoiseState ^= NoiseState << 5;
		const float White = (static_cast<float>(NoiseState) / 2147483648.0f) - 1.0f;
		Sample += White * Noise * (0.15f + 0.85f * CurrentLoad) * 0.5f;

		const float Out = Sample * Volume;
		for (int32 Channel = 0; Channel < Channels; ++Channel)
		{
			OutAudio[Frame * Channels + Channel] = Out;
		}
	}
	return NumSamples;
}
