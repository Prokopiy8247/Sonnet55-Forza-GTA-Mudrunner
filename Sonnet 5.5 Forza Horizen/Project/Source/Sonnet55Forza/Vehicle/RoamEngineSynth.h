// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
// SynthComponent.h pulls in USoundWaveProcedural, whose engine header triggers a C4996 deprecation warning in 5.8.2 (an engine-side
// override of a deprecated virtual). It is not ours to fix, so it is silenced locally to keep our compile output warning-clean.
PRAGMA_DISABLE_DEPRECATION_WARNINGS
#include "Components/SynthComponent.h"
PRAGMA_ENABLE_DEPRECATION_WARNINGS
#include "Core/RoamTypes.h"
#include <atomic>
#include "RoamEngineSynth.generated.h"

struct FRoamSoundSpec;

/**
 * Procedural engine sound (prompt section 5 "Audio": RPM- and load-driven, project-owned, no recorded audio).
 *
 * THREADING: the game thread calls SetEngineState() every frame; OnGenerateAudio runs on the audio render thread. The shared
 * state is a handful of std::atomic<float> (relaxed): no locks, no allocations on the audio thread.
 *
 * ---- OWNER: camera/audio agent ----------------------------------------------------------------------------------------------
 * Skeleton behaviour: an additive synth (firing frequency = RPM/60 * Cylinders/2 * PitchScale, harmonic mix from
 * FRoamSoundSpec::HarmonicMix, noise, load-dependent brightness) so the plumbing is verified end to end. The owner replaces the
 * generator by the real design (formant filtering, per-cylinder pulses, turbo whine/blow-off, exhaust crackle, intake roar) and
 * adds the one-shot sounds (gear shifts, tyre squeal per surface, wind, suspension thumps) as further components or MetaSounds.
 * Do not change the public API.
 */
UCLASS(ClassGroup = (Roam), meta = (BlueprintSpawnableComponent))
class SONNET55FORZA_API URoamEngineSynth : public USynthComponent
{
	GENERATED_BODY()

public:
	URoamEngineSynth(const FObjectInitializer& ObjectInitializer);

	/** Applies the sound character of a car. Thread-safe, takes effect on the next audio buffer. */
	void ApplySoundSpec(const FRoamSoundSpec& Spec, float IdleRPM, float RedlineRPM);

	/** Per-frame engine state: rpm, throttle load 0..1, turbo boost 0..1. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Audio")
	void SetEngineState(float RPM, float Load01, float Boost01);

	/** Master volume of the engine sound (0..1), multiplied with the profile volume. */
	UFUNCTION(BlueprintCallable, Category = "Roam|Audio")
	void SetEngineVolume(float Volume01);

	/** Silences the synth without stopping it (AI-controlled / traffic cars). */
	UFUNCTION(BlueprintCallable, Category = "Roam|Audio")
	void SetMuted(bool bInMuted);

	/** Starts playback if the engine has audio output (not in -nosound / commandlets). */
	void StartIfAudible();

protected:
	//~ Begin USynthComponent
	virtual bool Init(int32& SampleRate) override;
	virtual int32 OnGenerateAudio(float* OutAudio, int32 NumSamples) override;
	//~ End USynthComponent

private:
	// game thread -> audio thread
	std::atomic<float> TargetRPM{ 900.0f };
	std::atomic<float> TargetLoad{ 0.0f };
	std::atomic<float> TargetBoost{ 0.0f };
	std::atomic<float> VolumeScale{ 1.0f };
	std::atomic<float> ProfileVolume{ 1.0f };
	std::atomic<float> PitchScale{ 1.0f };
	std::atomic<float> NoiseAmount{ 0.25f };
	std::atomic<int32> NumCylinders{ 4 };
	std::atomic<bool> bMutedFlag{ false };
	std::atomic<float> Harmonics[6];

	// audio thread only
	float SampleRateHz = 48000.0f;
	float CurrentRPM = 900.0f;
	float CurrentLoad = 0.0f;
	double Phase = 0.0;
	uint32 NoiseState = 0x12345678u;
};
