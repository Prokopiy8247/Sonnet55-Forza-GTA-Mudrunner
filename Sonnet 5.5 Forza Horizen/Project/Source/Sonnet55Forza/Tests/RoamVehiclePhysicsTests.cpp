// Copyright Epic Games, Inc. All Rights Reserved.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "CoreGlobals.h"
#include "Core/RoamCollision.h"
#include "Core/RoamLog.h"
#include "Data/RoamCarDefinition.h"
#include "Engine/GameInstance.h"
#include "Engine/StaticMesh.h"
#include "Engine/StaticMeshActor.h"
#include "Engine/World.h"
#include "GameFramework/WorldSettings.h"
#include "Components/StaticMeshComponent.h"
#include "Misc/CommandLine.h"
#include "Subsystems/WorldSubsystem.h"
#include "Tickable.h"
#include "Misc/Parse.h"
#include "PhysicalMaterials/PhysicalMaterial.h"
#include "Vehicle/RoamDrivetrain.h"
#include "Vehicle/RoamTestCars.h"
#include "Vehicle/RoamTireModel.h"
#include "Vehicle/RoamVehicle.h"
#include "Vehicle/RoamVehicleMovement.h"
#include "World/RoamTimeWeatherSubsystem.h"

#define ROAM_VEH_TEST_FLAGS (EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter)

namespace
{
	constexpr float StepDt = 1.0f / 60.0f;

	void LogRow(const FString& Row);

	/** Cars selected for the heavy tests: -RoamTestCars=1,3,6 (1-based roster numbers), default = all ten. */
	TArray<int32> SelectedCars(const TArray<int32>& Default)
	{
		FString Value;
		if (FParse::Value(FCommandLine::Get(), TEXT("RoamTestCars="), Value, false))
		{
			TArray<FString> Parts;
			Value.ParseIntoArray(Parts, TEXT(","));
			TArray<int32> Out;
			for (const FString& Part : Parts)
			{
				const int32 N = FCString::Atoi(*Part);
				if (N >= 1 && N <= RoamTestCars::Num() && Default.Contains(N - 1))
				{
					Out.Add(N - 1);
				}
			}
			return Out;
		}
		return Default;
	}

	TArray<int32> AllCars()
	{
		TArray<int32> Out;
		for (int32 i = 0; i < RoamTestCars::Num(); ++i)
		{
			Out.Add(i);
		}
		return Out;
	}

	/** A bare game world with physics: a long asphalt runway, surface strips, a 5 degree ramp. Units of the helpers are metres. */
	struct FDriveWorld
	{
		UGameInstance* GameInstance = nullptr;
		UWorld* World = nullptr;
		UStaticMesh* Cube = nullptr;
		UPhysicalMaterial* Materials[static_cast<int32>(ERoamSurface::Count)] = {};

		bool IsReady() const { return World != nullptr; }

		bool Create()
		{
			if (!GEngine)
			{
				return false;
			}
			GameInstance = NewObject<UGameInstance>(GEngine);
			GameInstance->AddToRoot();
			GameInstance->InitializeStandalone();
			World = GameInstance->GetWorld();
			if (!World)
			{
				return false;
			}
			// The Water plugin's world subsystem crashes in its tick inside a bare automation world (null callback in UnrealEditor_Water
			// while no camera / water exists); it has nothing to do with the vehicle, so its tick is switched off for the tests.
			if (UClass* WaterClass = FindObject<UClass>(nullptr, TEXT("/Script/Water.WaterSubsystem")))
			{
				if (UTickableWorldSubsystem* Water = Cast<UTickableWorldSubsystem>(World->GetSubsystemBase(TSubclassOf<UWorldSubsystem>(WaterClass))))
				{
					Water->SetTickableTickType(ETickableTickType::Never);
				}
			}
			World->InitializeActorsForPlay(FURL());
			if (ULevel* Level = World->PersistentLevel)
			{
				Level->bIsVisible = true;
			}
			World->BeginPlay();
			if (AWorldSettings* Settings = World->GetWorldSettings())
			{
				Settings->NotifyBeginPlay();
				Settings->NotifyMatchStarted();
			}
			Cube = LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
			for (int32 i = 0; i < static_cast<int32>(ERoamSurface::Count); ++i)
			{
				Materials[i] = NewObject<UPhysicalMaterial>(GetTransientPackage());
				Materials[i]->SurfaceType = static_cast<EPhysicalSurface>(static_cast<int32>(SurfaceType1) + i);
				Materials[i]->Friction = 0.8f;
				Materials[i]->AddToRoot();
			}
			return Cube != nullptr;
		}

		~FDriveWorld()
		{
			for (UPhysicalMaterial*& Material : Materials)
			{
				if (Material)
				{
					Material->RemoveFromRoot();
					Material = nullptr;
				}
			}
			if (World)
			{
				World->DestroyWorld(false);
				if (GEngine)
				{
					GEngine->DestroyWorldContext(World);
				}
			}
			if (GameInstance)
			{
				GameInstance->Shutdown();
				GameInstance->RemoveFromRoot();
			}
		}

		/** Static box whose TOP face is at Z = TopZ metres. */
		AStaticMeshActor* AddSlab(ERoamSurface Surface, const FVector& CenterXYMeters, const FVector2D& SizeXYMeters, float TopZMeters = 0.0f, float ThicknessMeters = 2.0f, const FRotator& Rotation = FRotator::ZeroRotator)
		{
			const FVector Center(CenterXYMeters.X * 100.0, CenterXYMeters.Y * 100.0, (TopZMeters - 0.5f * ThicknessMeters) * 100.0);
			AStaticMeshActor* Actor = World->SpawnActor<AStaticMeshActor>(Center, Rotation);
			UStaticMeshComponent* Mesh = Actor->GetStaticMeshComponent();
			Mesh->SetMobility(EComponentMobility::Movable);
			Mesh->SetStaticMesh(Cube);
			Mesh->SetWorldScale3D(FVector(SizeXYMeters.X, SizeXYMeters.Y, ThicknessMeters));
			Mesh->SetCollisionProfileName(RoamCollision::ProfileWorldStatic);
			Mesh->SetPhysMaterialOverride(Materials[static_cast<int32>(Surface)]);
			return Actor;
		}

		/** Runway X -400..9000, Y -300..300 (asphalt), strips of loose surfaces at Y = 700.., ramp lane at Y = -200 (ramp X = 900..960). */
		void BuildStandardTrack()
		{
			AddSlab(ERoamSurface::Asphalt, FVector(4300.0, 0.0, 0.0), FVector2D(9400.0, 600.0));
			const ERoamSurface Strips[] = { ERoamSurface::Dirt, ERoamSurface::Gravel, ERoamSurface::Grass, ERoamSurface::Sand, ERoamSurface::Snow, ERoamSurface::Mud, ERoamSurface::Concrete };
			for (int32 i = 0; i < UE_ARRAY_COUNT(Strips); ++i)
			{
				AddSlab(Strips[i], FVector(700.0, 700.0 + 60.0 * i, 0.0), FVector2D(1600.0, 50.0));
			}
			// 5 degree ramp: top surface starts at (900, -200, 0), length 60 m, 14 m wide
			const FRotator Pitch(5.0, 0.0, 0.0);
			const FQuat Q = Pitch.Quaternion();
			const FVector Start(900.0, -200.0, 0.0);
			const FVector Center = Start - Q.RotateVector(FVector(-30.0, 0.0, 0.5));
			AStaticMeshActor* Ramp = World->SpawnActor<AStaticMeshActor>(Center * 100.0, Pitch);
			UStaticMeshComponent* Mesh = Ramp->GetStaticMeshComponent();
			Mesh->SetMobility(EComponentMobility::Movable);
			Mesh->SetStaticMesh(Cube);
			Mesh->SetWorldScale3D(FVector(60.0, 14.0, 1.0));
			Mesh->SetCollisionProfileName(RoamCollision::ProfileWorldStatic);
			Mesh->SetPhysMaterialOverride(Materials[static_cast<int32>(ERoamSurface::Asphalt)]);
		}

		ARoamVehicle* SpawnCar(int32 CarIndex, const FVector& LocationMeters, float YawDeg, bool bStockAssists = true)
		{
			URoamCarDefinition* Definition = RoamTestCars::Make(GameInstance, CarIndex);
			if (!Definition)
			{
				return nullptr;
			}
			Definition->AddToRoot();
			FActorSpawnParameters Params;
			Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
			ARoamVehicle* Car = World->SpawnActorDeferred<ARoamVehicle>(ARoamVehicle::StaticClass(), FTransform(FRotator(0.0, YawDeg, 0.0), LocationMeters * 100.0), nullptr, nullptr, ESpawnActorCollisionHandlingMethod::AlwaysSpawn);
			if (!Car)
			{
				return nullptr;
			}
			Car->InitialCarDefinition = Definition;
			Car->FinishSpawning(FTransform(FRotator(0.0, YawDeg, 0.0), LocationMeters * 100.0));
			Car->SetAIControlled(true);
			if (bStockAssists)
			{
				FRoamAssistSettings Assists;
				Assists.bTractionControl = Definition->AssistDefaults.bTractionControl;
				Assists.bStabilityControl = Definition->AssistDefaults.bStabilityControl;
				Assists.bABS = Definition->AssistDefaults.bABS;
				Assists.SteeringAssist = Definition->AssistDefaults.SteeringAssist;
				Assists.bAutomaticGearbox = true;
				Car->SetAssists(Assists);
			}
			return Car;
		}

		void Step(ARoamVehicle* Car, float Dt = StepDt)
		{
			(void)Car;
			// The tick task manager skips a tick function that already ran in the current engine frame: advance the frame counter
			// like a real frame loop does, otherwise only the first World->Tick of a test loop ticks actors and physics.
			++GFrameCounter;
			World->Tick(LEVELTICK_All, Dt);
		}

		void Run(ARoamVehicle* Car, float Seconds)
		{
			const int32 Steps = FMath::RoundToInt(Seconds / StepDt);
			for (int32 i = 0; i < Steps; ++i)
			{
				Step(Car);
			}
		}

		void SetWetness(float Wetness)
		{
			if (URoamTimeWeatherSubsystem* TimeWeather = World->GetSubsystem<URoamTimeWeatherSubsystem>())
			{
				TimeWeather->SetWetness(Wetness);
			}
		}
	};

	/**
	 * One world for all drive tests of the process, never destroyed: creating and destroying several game worlds in one process leaves the
	 * Water plugin's editor-only OnActorMoved binding pointing at freed subsystems and the next moving car crashes inside UnrealEditor_Water.
	 * (Cars are destroyed individually after each run.)
	 */
	FDriveWorld& SharedWorld()
	{
		static FDriveWorld* Shared = nullptr;
		if (!Shared)
		{
			Shared = new FDriveWorld();
			if (Shared->Create())
			{
				Shared->BuildStandardTrack();
			}
			else
			{
				Shared->World = nullptr;
			}
		}
		return *Shared;
	}

	/** Performance runs are done with traction control on (what a player has by default); stability control follows the car's default. */
	void EnableTcs(ARoamVehicle* Car)
	{
		FRoamAssistSettings Assists = Car->GetAssists();
		Assists.bTractionControl = true;
		Car->SetAssists(Assists);
	}

	float YawOf(const ARoamVehicle* Car)
	{
		const FVector Forward = Car->GetActorForwardVector();
		return FMath::Atan2(static_cast<float>(Forward.Y), static_cast<float>(Forward.X));
	}

	/** Keeps the car on the +X axis lane (small steering corrections); returns the steer command. */
	float LaneKeep(const ARoamVehicle* Car, float LaneY)
	{
		const float Yaw = YawOf(Car);
		const float OffsetM = static_cast<float>(Car->GetActorLocation().Y) * 0.01f - LaneY;
		return FMath::Clamp(-(1.6f * Yaw + 0.012f * OffsetM), -0.25f, 0.25f);
	}

	struct FAccelResult
	{
		float T0To60 = -1.0f;
		float T0To100 = -1.0f;
		float T0To200 = -1.0f;
		float TopKmh = 0.0f;
		float TimeToTop = 0.0f;
		float Distance = 0.0f;
		float TopGear = 0.0f;
		float MaxSlip = 0.0f;
	};

	/** Full throttle from standstill until the speed stops rising (or MaxSeconds). */
	FAccelResult AccelRun(FDriveWorld& W, ARoamVehicle* Car, float MaxSeconds, float LaneY = 0.0f)
	{
		FAccelResult Out;
		const bool bTrace = FParse::Param(FCommandLine::Get(), TEXT("RoamTestTrace"));
		const float StartX = static_cast<float>(Car->GetActorLocation().X) * 0.01f;
		float T = 0.0f;
		float PrevSpeed = 0.0f;
		float StallTime = 0.0f;
		float WindowStartSpeed = 0.0f;
		float WindowT = 0.0f;
		while (T < MaxSeconds)
		{
			Car->SetThrottle(1.0f);
			Car->SetBrake(0.0f);
			Car->SetSteer(LaneKeep(Car, LaneY));
			W.Step(Car);
			T += StepDt;
			const FRoamVehicleTelemetry& Telemetry = Car->GetTelemetry();
			const float V = Telemetry.SpeedKmh;
			const auto Cross = [&](float Threshold, float& Slot)
			{
				if (Slot < 0.0f && V >= Threshold && PrevSpeed < Threshold)
				{
					Slot = T - StepDt + StepDt * (Threshold - PrevSpeed) / FMath::Max(V - PrevSpeed, 1.0e-4f);
				}
			};
			Cross(60.0f, Out.T0To60);
			Cross(100.0f, Out.T0To100);
			Cross(200.0f, Out.T0To200);
			if (V > Out.TopKmh)
			{
				Out.TopKmh = V;
				Out.TimeToTop = T;
			}
			for (int32 i = 0; i < 4; ++i)
			{
				Out.MaxSlip = FMath::Max(Out.MaxSlip, FMath::Abs(Telemetry.WheelSlipRatio[i]));
			}
			if (bTrace && T < 2.0f && static_cast<int32>(T * 60.0f + 0.5f) % 6 == 0)
			{
				const URoamVehicleMovement* Mv = Car->VehicleMovement;
				LogRow(FString::Printf(TEXT("fine t=%.2f vx=%.2f m/s omegaRL=%.1f FxFL=%.0f FxRL=%.0f FxRR=%.0f FyRL=%.0f tcs=%.2f engT=%.0f clutch=%d"), T, Telemetry.VelocityCmS.X * 0.01 * 1.0, Mv->GetWheelState(2).Omega,
					Mv->GetWheelState(0).Fx, Mv->GetWheelState(2).Fx, Mv->GetWheelState(3).Fx, Mv->GetWheelState(2).Fy, Mv->GetTcsFactor(), Telemetry.EngineTorqueNm, Telemetry.bClutchSlipping ? 1 : 0));
			}
			if (bTrace && static_cast<int32>(T * 60.0f + 0.5f) % 30 == 0)
			{
				LogRow(FString::Printf(TEXT("trace t=%.1f v=%.1f gear=%d rpm=%.0f thr=%.2f tcs=%d stm=%d clutchSlip=%d engT=%.0f slipFL=%.2f slipRL=%.2f FzFL=%.0f FzRL=%.0f travel=%.1f/%.1f yaw=%.1f bslip=%.1f longG=%.2f steer=%.2f"), T, V, Telemetry.Gear, Telemetry.RPM, Telemetry.Throttle,
					Telemetry.bTCSActive ? 1 : 0, Telemetry.bSTMActive ? 1 : 0, Telemetry.bClutchSlipping ? 1 : 0, Telemetry.EngineTorqueNm, Telemetry.WheelSlipRatio[0], Telemetry.WheelSlipRatio[2],
					Telemetry.WheelLoadN[0], Telemetry.WheelLoadN[2], Telemetry.WheelTravelCm[0], Telemetry.WheelTravelCm[2], Telemetry.YawRateDeg, Telemetry.BodySlipAngleDeg, Telemetry.LongG, Telemetry.Steer));
			}
			PrevSpeed = V;
			WindowT += StepDt;
			if (WindowT >= 3.0f)
			{
				if (V - WindowStartSpeed < 0.6f && V > 20.0f)
				{
					break;   // top speed reached: less than 0.2 km/h per second over 3 s
				}
				WindowStartSpeed = V;
				WindowT = 0.0f;
			}
		}
		Out.Distance = static_cast<float>(Car->GetActorLocation().X) * 0.01f - StartX;
		Out.TopGear = static_cast<float>(Car->GetTelemetry().Gear);
		return Out;
	}

	/** Drives to a speed with a PI throttle on the lane, then brakes fully; returns the stopping distance from the moment the brake is applied. */
	float BrakeFrom(FDriveWorld& W, ARoamVehicle* Car, float FromKmh, float LaneY, float* OutDecelG = nullptr, bool* OutAbsSeen = nullptr, float* OutMaxSlideUsedAbs = nullptr)
	{
		float T = 0.0f;
		while (Car->GetTelemetry().SpeedKmh < FromKmh && T < 90.0f)
		{
			Car->SetThrottle(1.0f);
			Car->SetBrake(0.0f);
			Car->SetSteer(LaneKeep(Car, LaneY));
			W.Step(Car);
			T += StepDt;
		}
		const float StartX = static_cast<float>(Car->GetActorLocation().X) * 0.01f;
		const float StartSpeedMs = Car->GetTelemetry().SpeedMs;
		float BrakeT = 0.0f;
		bool bAbs = false;
		float MaxSlip = 0.0f;
		while (Car->GetTelemetry().SpeedKmh > 1.0f && BrakeT < 30.0f)
		{
			Car->SetThrottle(0.0f);
			Car->SetBrake(1.0f);
			Car->SetSteer(LaneKeep(Car, LaneY));
			W.Step(Car);
			BrakeT += StepDt;
			bAbs |= Car->GetTelemetry().bABSActive;
			for (int32 i = 0; i < 4; ++i)
			{
				MaxSlip = FMath::Max(MaxSlip, -Car->GetTelemetry().WheelSlipRatio[i]);
			}
		}
		const float Distance = static_cast<float>(Car->GetActorLocation().X) * 0.01f - StartX;
		if (OutDecelG)
		{
			*OutDecelG = BrakeT > 0.0f ? StartSpeedMs / BrakeT / 9.81f : 0.0f;
		}
		if (OutAbsSeen) { *OutAbsSeen = bAbs; }
		if (OutMaxSlideUsedAbs) { *OutMaxSlideUsedAbs = MaxSlip; }
		return Distance;
	}

	void LogRow(const FString& Row)
	{
		UE_LOG(LogRoamVehicle, Display, TEXT("ROAM_DRIVETEST %s"), *Row);
	}
}

// ------------------------------------------------------------------------------------------------------------------
// Pure model tests
// ------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamTireModelTest, "Roam.Vehicle.TireModel", ROAM_VEH_TEST_FLAGS)
bool FRoamTireModelTest::RunTest(const FString& Parameters)
{
	TestNearlyEqual(TEXT("curve(0)"), RoamTire::Curve(0.0f, 0.88f, 1.2f), 0.0f, 1.0e-5f);
	TestNearlyEqual(TEXT("curve(1) = peak"), RoamTire::Curve(1.0f, 0.88f, 1.2f), 1.0f, 1.0e-5f);
	TestTrue(TEXT("curve rises to the peak"), RoamTire::Curve(0.5f, 0.88f, 1.2f) > 0.7f && RoamTire::Curve(0.5f, 0.88f, 1.2f) < 1.0f);
	TestNearlyEqual(TEXT("curve(large) = slide level"), RoamTire::Curve(8.0f, 0.88f, 1.2f), 0.88f, 1.0e-3f);

	RoamTire::FShape Shape;
	// traction: wheel faster than the ground pushes the car forward
	RoamTire::FResult Drive = RoamTire::Evaluate(Shape, 1.0f, 4000.0f, 20.0f, 0.0f, 22.0f, 2.5f);
	TestTrue(TEXT("wheelspin gives a forward force"), Drive.Fx > 0.0f && FMath::Abs(Drive.Fy) < 1.0f);
	// braking: slower wheel decelerates
	RoamTire::FResult Brake = RoamTire::Evaluate(Shape, 1.0f, 4000.0f, 20.0f, 0.0f, 17.0f, 2.5f);
	TestTrue(TEXT("braking gives a rearward force"), Brake.Fx < 0.0f);
	// a locked wheel on a forward-moving car gives the slide force against the motion
	RoamTire::FResult Locked = RoamTire::Evaluate(Shape, 1.0f, 4000.0f, 20.0f, 0.0f, 0.0f, 2.5f);
	TestNearlyEqual(TEXT("locked wheel slide force"), Locked.Fx, -0.88f * 4000.0f, 40.0f);
	// sideways velocity to the right gives a force to the left
	RoamTire::FResult Side = RoamTire::Evaluate(Shape, 1.0f, 4000.0f, 20.0f, 2.0f, 20.0f, 2.5f);
	TestTrue(TEXT("lateral force opposes lateral velocity"), Side.Fy < 0.0f);
	// the force never exceeds mu * Fz
	for (float Kappa = -1.0f; Kappa <= 1.0f; Kappa += 0.1f)
	{
		for (float Vy = -10.0f; Vy <= 10.0f; Vy += 2.0f)
		{
			const RoamTire::FResult R = RoamTire::Evaluate(Shape, 1.2f, 3000.0f, 25.0f, Vy, 25.0f * (1.0f + Kappa), 2.5f);
			TestTrue(TEXT("force inside the friction circle"), FMath::Sqrt(R.Fx * R.Fx + R.Fy * R.Fy) <= 1.2f * 3000.0f * 1.0001f);
		}
	}
	// combined slip: wheelspin takes lateral grip away
	const RoamTire::FResult Pure = RoamTire::Evaluate(Shape, 1.0f, 4000.0f, 20.0f, 1.5f, 20.0f, 2.5f);
	const RoamTire::FResult Combined = RoamTire::Evaluate(Shape, 1.0f, 4000.0f, 20.0f, 1.5f, 28.0f, 2.5f);
	TestTrue(TEXT("lateral force falls with wheelspin"), FMath::Abs(Combined.Fy) < FMath::Abs(Pure.Fy));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDrivetrainModelTest, "Roam.Vehicle.Drivetrain", ROAM_VEH_TEST_FLAGS)
bool FRoamDrivetrainModelTest::RunTest(const FString& Parameters)
{
	URoamCarDefinition* Pulse = RoamTestCars::Make(GetTransientPackage(), 0);
	if (!TestNotNull(TEXT("test car"), Pulse))
	{
		return false;
	}
	FRoamDrivetrain Drivetrain;
	Drivetrain.Configure(Pulse, FRoamTuning(), 0.33f);
	TestEqual(TEXT("starts in first gear"), Drivetrain.Gear, 1);
	// accelerate through the gears with a crude speed model: wheel speed follows 4 m/s^2
	float Speed = 0.0f;
	int32 MaxGear = 1;
	for (int32 i = 0; i < 60 * 25; ++i)
	{
		FRoamDrivetrain::FInput In;
		In.DrivePedal = In.ThrottlePedal = 1.0f;
		In.ForwardSpeedMs = Speed;
		In.DrivenOmega = Speed / 0.33f;
		Drivetrain.Step(1.0f / 120.0f, In);
		Speed += 4.0f / 120.0f;
		MaxGear = FMath::Max(MaxGear, Drivetrain.Gear);
		TestTrue(TEXT("rpm stays below the limiter + margin"), Drivetrain.EngineRPM < Pulse->Engine.RevLimiterRPM + 400.0f);
	}
	TestTrue(TEXT("the automatic gearbox upshifted"), MaxGear >= 4);
	// reverse: stopped, brake held, no throttle
	FRoamDrivetrain Fresh;
	Fresh.Configure(Pulse, FRoamTuning(), 0.33f);
	for (int32 i = 0; i < 60; ++i)
	{
		FRoamDrivetrain::FInput In;
		In.BrakePedal = 0.8f;
		Fresh.Step(1.0f / 120.0f, In);
	}
	TestEqual(TEXT("brake at standstill engages reverse"), Fresh.Gear, -1);
	// differential bias moves torque to the slower wheel
	const float Bias = RoamDrive::DiffBias(ERoamDiffType::LimitedSlip, 0.5f, 0.1f, 40.0f, 400.0f, 30.0f, 10.0f);
	TestTrue(TEXT("LSD: left faster -> torque added to the right wheel"), Bias > 0.0f);
	TestEqual(TEXT("open diff has no bias"), RoamDrive::DiffBias(ERoamDiffType::Open, 0.5f, 0.1f, 40.0f, 400.0f, 30.0f, 10.0f), 0.0f);
	return true;
}

// ------------------------------------------------------------------------------------------------------------------
// Drive tests (Docs/Tech/DRIVE_TESTS.md)
// ------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveSettleTest, "Roam.Vehicle.Drive.Settle", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveSettleTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}
	for (const int32 CarIndex : SelectedCars({ 0, 7 }))
	{
		ARoamVehicle* Car = W.SpawnCar(CarIndex, FVector(0.0, 0.0, 0.06), 0.0f);
		if (!TestNotNull(TEXT("car"), Car))
		{
			return false;
		}
		TestTrue(TEXT("physics model is active"), Car->VehicleMovement->GetSimMode() == ERoamVehicleSimMode::Physics);
		W.Run(Car, 4.0f);
		const FRoamVehicleTelemetry& T = Car->GetTelemetry();
		const URoamVehicleMovement* M = Car->VehicleMovement;
		FString Travel;
		for (int32 i = 0; i < 4; ++i)
		{
			Travel += FString::Printf(TEXT("%.1f "), T.WheelTravelCm[i]);
		}
		LogRow(FString::Printf(TEXT("settle car=%s ready=%d steps=%lld speed=%.3f km/h wheels=%d travelCm=[%s] load=[%.0f %.0f %.0f %.0f] z=%.1fcm pitch=%.2f roll=%.2f gear=%d rpm=%.0f"),
			*RoamTestCars::IdOf(CarIndex).ToString(), M->IsPhysicsReady() ? 1 : 0, M->GetPhysicsStepStats().NumSteps, T.SpeedKmh, T.NumWheelsOnGround, *Travel,
			T.WheelLoadN[0], T.WheelLoadN[1], T.WheelLoadN[2], T.WheelLoadN[3], Car->GetActorLocation().Z, T.PitchDeg, T.RollDeg, T.Gear, T.RPM));
		TestTrue(TEXT("the async physics tick runs"), M->GetPhysicsStepStats().NumSteps > 100);
		TestEqual(TEXT("all wheels on the ground"), T.NumWheelsOnGround, 4);
		TestTrue(TEXT("car is at rest"), T.SpeedKmh < 1.0f);
		TestTrue(TEXT("car sits level"), FMath::Abs(T.PitchDeg) < 3.0f && FMath::Abs(T.RollDeg) < 3.0f);
		float Total = 0.0f;
		for (int32 i = 0; i < 4; ++i)
		{
			Total += T.WheelLoadN[i];
			TestTrue(TEXT("rest travel is small"), FMath::Abs(T.WheelTravelCm[i]) < 4.0f);
		}
		TestNearlyEqual(TEXT("wheel loads add up to the weight"), Total, M->GetEffectiveMassKg() * 9.81f, M->GetEffectiveMassKg() * 9.81f * 0.06f);
		Car->Destroy();
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveStraightTest, "Roam.Vehicle.Drive.Straight", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveStraightTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}
	for (const int32 CarIndex : SelectedCars(AllCars()))
	{
		ARoamVehicle* Car = W.SpawnCar(CarIndex, FVector(0.0, 0.0, 0.06), 0.0f);
		if (!TestNotNull(TEXT("car"), Car))
		{
			return false;
		}
		EnableTcs(Car);
		W.Run(Car, 2.0f);
		const FAccelResult A = AccelRun(W, Car, 80.0f);
		LogRow(FString::Printf(TEXT("accel car=%s t60=%.2f t100=%.2f t200=%.2f top=%.1f timeToTop=%.1f dist=%.0f maxSlip=%.2f"), *RoamTestCars::IdOf(CarIndex).ToString(), A.T0To60, A.T0To100, A.T0To200, A.TopKmh, A.TimeToTop, A.Distance, A.MaxSlip));
		TestTrue(TEXT("reaches 100 km/h"), A.T0To100 > 0.0f);
		TestTrue(TEXT("top speed is plausible"), A.TopKmh > 100.0f && A.TopKmh < 450.0f);
		Car->Destroy();

		// braking 100 -> 0, with and without ABS
		for (int32 AbsOn = 1; AbsOn >= 0; --AbsOn)
		{
			ARoamVehicle* BrakeCar = W.SpawnCar(CarIndex, FVector(0.0, 0.0, 0.06), 0.0f);
			FRoamAssistSettings Assists = BrakeCar->GetAssists();
			Assists.bABS = AbsOn == 1;
			BrakeCar->SetAssists(Assists);
			W.Run(BrakeCar, 1.5f);
			float DecelG = 0.0f;
			bool bAbsSeen = false;
			float MaxLock = 0.0f;
			const float Distance = BrakeFrom(W, BrakeCar, 100.0f, 0.0f, &DecelG, &bAbsSeen, &MaxLock);
			LogRow(FString::Printf(TEXT("brake car=%s abs=%d dist100=%.1f m avgDecel=%.2f g absSeen=%d maxLockSlip=%.2f"), *RoamTestCars::IdOf(CarIndex).ToString(), AbsOn, Distance, DecelG, bAbsSeen ? 1 : 0, MaxLock));
			TestTrue(TEXT("stops"), Distance > 10.0f && Distance < 200.0f);
			BrakeCar->Destroy();
		}
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveSkidpadTest, "Roam.Vehicle.Drive.Skidpad", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveSkidpadTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}
	for (const int32 CarIndex : SelectedCars({ 0, 2, 5, 7 }))
	{
		const float RadiusM = 50.0f;
		// circle centred 50 m to the right of the start (the car turns right: steer > 0)
		ARoamVehicle* Car = W.SpawnCar(CarIndex, FVector(0.0, -150.0, 0.06), 0.0f);
		EnableTcs(Car);
		W.Run(Car, 1.5f);
		const URoamCarDefinition* Def = Car->GetCarDefinition();
		const float Wheelbase = 0.01f * Def->Geometry.WheelbaseCm;
		const float SteerMax = Def->Steering.MaxSteerAngleDeg;
		const FVector Centre = Car->GetActorLocation() + FVector(0.0, RadiusM * 100.0, 0.0);
		float TargetKmh = 30.0f;
		float Peak = 0.0f;
		float Avg = 0.0f;
		float PeakSpeed = 0.0f;
		float T = 0.0f;
		float SpeedErrorI = 0.0f;
		bool bLost = false;
		for (; T < 70.0f && !bLost; T += StepDt)
		{
			const FRoamVehicleTelemetry& Tel = Car->GetTelemetry();
			TargetKmh += 1.6f * StepDt;
			const float SpeedError = (TargetKmh - Tel.SpeedKmh) / 10.0f;
			SpeedErrorI = FMath::Clamp(SpeedErrorI + SpeedError * StepDt, -1.0f, 1.0f);
			const float Drive = FMath::Clamp(0.3f + SpeedError + 0.5f * SpeedErrorI, 0.0f, 1.0f);
			Car->SetThrottle(Drive);
			Car->SetBrake(SpeedError < -0.5f ? 0.2f : 0.0f);
			// steer onto the circle: kinematic angle + radius error feedback
			const FVector ToCar = Car->GetActorLocation() - Centre;
			const float RadiusNow = static_cast<float>(FVector(ToCar.X, ToCar.Y, 0.0).Size()) * 0.01f;
			const float KinematicDeg = FMath::RadiansToDegrees(FMath::Atan(Wheelbase / RadiusM));
			const float Steer = FMath::Clamp((KinematicDeg + 0.5f * (RadiusNow - RadiusM)) / FMath::Max(SteerMax * Def->Steering.GetLockFraction(Tel.SpeedKmh), 1.0f), -1.0f, 1.0f);
			Car->SetSteer(Steer);
			W.Step(Car);
			Avg = FMath::Lerp(Avg, FMath::Abs(Tel.LatG), 1.0f - FMath::Exp(-StepDt / 0.5f));
			if (RadiusNow < RadiusM * 1.18f && RadiusNow > RadiusM * 0.82f && T > 4.0f)
			{
				if (Avg > Peak)
				{
					Peak = Avg;
					PeakSpeed = Tel.SpeedKmh;
				}
			}
			else if (T > 6.0f)
			{
				bLost = true;   // left the 50 m circle by more than 18 %: the limit has been passed
			}
		}
		LogRow(FString::Printf(TEXT("skidpad car=%s peakLatG=%.2f at %.0f km/h (r=50 m) t=%.0f s lostLine=%d"), *RoamTestCars::IdOf(CarIndex).ToString(), Peak, PeakSpeed, T, bLost ? 1 : 0));
		TestTrue(TEXT("lateral g is plausible"), Peak > 0.5f && Peak < 2.2f);
		Car->Destroy();
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveStabilityTest, "Roam.Vehicle.Drive.Stability250", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveStabilityTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}
	for (const int32 CarIndex : SelectedCars({ 3, 4, 5 }))
	{
		ARoamVehicle* Car = W.SpawnCar(CarIndex, FVector(0.0, 0.0, 0.06), 0.0f);
		W.Run(Car, 1.5f);
		// accelerate to ~250 km/h (or as fast as the car goes)
		float T = 0.0f;
		while (Car->GetTelemetry().SpeedKmh < 250.0f && T < 70.0f)
		{
			Car->SetThrottle(1.0f);
			Car->SetSteer(LaneKeep(Car, 0.0f));
			W.Step(Car);
			T += StepDt;
		}
		const float SpeedAtTest = Car->GetTelemetry().SpeedKmh;
		// steering perturbation: 10 % steer for 0.4 s, then hands off (steer 0, throttle held)
		float MaxYaw = 0.0f;
		float MaxRoll = 0.0f;
		float MaxSlip = 0.0f;
		float MaxOffset = 0.0f;
		const float StartY = static_cast<float>(Car->GetActorLocation().Y) * 0.01f;
		for (float P = 0.0f; P < 6.0f; P += StepDt)
		{
			Car->SetThrottle(P < 3.0f ? 1.0f : 0.5f);
			Car->SetSteer(P < 0.4f ? 0.1f : 0.0f);
			W.Step(Car);
			const FRoamVehicleTelemetry& Tel = Car->GetTelemetry();
			MaxYaw = FMath::Max(MaxYaw, FMath::Abs(Tel.YawRateDeg));
			MaxRoll = FMath::Max(MaxRoll, FMath::Abs(Tel.RollDeg));
			MaxSlip = FMath::Max(MaxSlip, FMath::Abs(Tel.BodySlipAngleDeg));
			MaxOffset = FMath::Max(MaxOffset, FMath::Abs(static_cast<float>(Car->GetActorLocation().Y) * 0.01f - StartY));
		}
		const FRoamVehicleTelemetry& End = Car->GetTelemetry();
		LogRow(FString::Printf(TEXT("stability car=%s at %.0f km/h: maxYawRate=%.1f deg/s maxRoll=%.1f maxSlipAngle=%.1f maxOffset=%.1f m endYawRate=%.1f endSlip=%.1f wheels=%d"), *RoamTestCars::IdOf(CarIndex).ToString(), SpeedAtTest, MaxYaw, MaxRoll, MaxSlip, MaxOffset, End.YawRateDeg, End.BodySlipAngleDeg, End.NumWheelsOnGround));
		TestTrue(TEXT("yaw rate decays (no divergence)"), FMath::Abs(End.YawRateDeg) < 6.0f);
		TestTrue(TEXT("body slip angle is small at the end"), FMath::Abs(End.BodySlipAngleDeg) < 6.0f);
		TestTrue(TEXT("the car does not roll"), MaxRoll < 12.0f);
		TestEqual(TEXT("all wheels on the ground"), End.NumWheelsOnGround, 4);
		Car->Destroy();
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveJumpTest, "Roam.Vehicle.Drive.Jump", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveJumpTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}
	for (const int32 CarIndex : SelectedCars({ 0, 5, 7 }))
	{
		const float LaneY = -200.0f;
		ARoamVehicle* Car = W.SpawnCar(CarIndex, FVector(300.0, LaneY, 0.06), 0.0f);
		W.Run(Car, 1.5f);
		const float TargetKmh = 120.0f;
		float T = 0.0f;
		float MaxAir = 0.0f;
		float MaxVertG = 0.0f;
		float MaxPitch = 0.0f;
		float MaxRoll = 0.0f;
		bool bLaunched = false;
		float SpeedAtRamp = 0.0f;
		while (T < 40.0f)
		{
			const FRoamVehicleTelemetry& Tel = Car->GetTelemetry();
			const float Err = (TargetKmh - Tel.SpeedKmh) / 10.0f;
			Car->SetThrottle(FMath::Clamp(0.5f + Err, 0.0f, 1.0f));
			Car->SetBrake(Err < -0.5f ? 0.3f : 0.0f);
			Car->SetSteer(LaneKeep(Car, LaneY));
			W.Step(Car);
			T += StepDt;
			const float X = static_cast<float>(Car->GetActorLocation().X) * 0.01f;
			if (!bLaunched && X > 898.0f)
			{
				bLaunched = true;
				SpeedAtRamp = Tel.SpeedKmh;
			}
			MaxAir = FMath::Max(MaxAir, Tel.AirTimeSec);
			MaxVertG = FMath::Max(MaxVertG, Tel.VertG);
			MaxPitch = FMath::Max(MaxPitch, FMath::Abs(Tel.PitchDeg));
			MaxRoll = FMath::Max(MaxRoll, FMath::Abs(Tel.RollDeg));
			if (X > 1080.0f)
			{
				break;
			}
		}
		W.Run(Car, 3.0f);   // let it settle after the landing (no pedals)
		const FRoamVehicleTelemetry& End = Car->GetTelemetry();
		LogRow(FString::Printf(TEXT("jump car=%s speedAtRamp=%.0f maxAir=%.2f s maxVertG=%.2f maxPitch=%.1f maxRoll=%.1f endPitch=%.1f endRoll=%.1f wheels=%d z=%.0f cm"), *RoamTestCars::IdOf(CarIndex).ToString(), SpeedAtRamp, MaxAir, MaxVertG, MaxPitch, MaxRoll, End.PitchDeg, End.RollDeg, End.NumWheelsOnGround, Car->GetActorLocation().Z));
		TestTrue(TEXT("the car left the ramp"), MaxAir > 0.2f);
		TestTrue(TEXT("lands upright"), FMath::Abs(End.PitchDeg) < 10.0f && FMath::Abs(End.RollDeg) < 10.0f);
		TestEqual(TEXT("all wheels on the ground after the landing"), End.NumWheelsOnGround, 4);
		TestTrue(TEXT("no explosion on landing"), MaxVertG < 30.0f && Car->GetActorLocation().Z < 200.0);
		Car->Destroy();
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveSurfacesTest, "Roam.Vehicle.Drive.Surfaces", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveSurfacesTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}
	struct FStrip { ERoamSurface Surface; float Y; };
	const FStrip Strips[] = { { ERoamSurface::Asphalt, 0.0f }, { ERoamSurface::Dirt, 700.0f }, { ERoamSurface::Gravel, 760.0f }, { ERoamSurface::Grass, 820.0f }, { ERoamSurface::Sand, 880.0f } };
	float AsphaltBrake[8] = {};
	float AsphaltAccel[8] = {};
	for (const int32 CarIndex : SelectedCars({ 0, 6, 7 }))
	{
		for (int32 s = 0; s < UE_ARRAY_COUNT(Strips); ++s)
		{
			ARoamVehicle* Car = W.SpawnCar(CarIndex, FVector(-50.0, Strips[s].Y, 0.06), 0.0f);
			W.Run(Car, 1.5f);
			float T = 0.0f;
			float T60 = -1.0f;
			float Prev = 0.0f;
			while (T < 25.0f && T60 < 0.0f)
			{
				Car->SetThrottle(1.0f);
				Car->SetSteer(LaneKeep(Car, Strips[s].Y));
				W.Step(Car);
				T += StepDt;
				const float V = Car->GetTelemetry().SpeedKmh;
				if (V >= 60.0f && Prev < 60.0f)
				{
					T60 = T;
				}
				Prev = V;
			}
			const FRoamVehicleTelemetry& Tel = Car->GetTelemetry();
			const ERoamSurface Seen = Tel.Surface;
			// braking 60 -> 0 on this surface (full ABS-assisted braking)
			float Dist = 0.0f;
			{
				float BT = 0.0f;
				const float StartX = static_cast<float>(Car->GetActorLocation().X) * 0.01f;
				while (Car->GetTelemetry().SpeedKmh > 1.0f && BT < 20.0f)
				{
					Car->SetThrottle(0.0f);
					Car->SetBrake(1.0f);
					Car->SetSteer(LaneKeep(Car, Strips[s].Y));
					W.Step(Car);
					BT += StepDt;
				}
				Dist = static_cast<float>(Car->GetActorLocation().X) * 0.01f - StartX;
			}
			if (s == 0)
			{
				AsphaltAccel[CarIndex] = T60;
				AsphaltBrake[CarIndex] = Dist;
			}
			LogRow(FString::Printf(TEXT("surface car=%s surface=%s seen=%s t0to60=%.2f brake60to0=%.1f m (vs asphalt: accel x%.2f, brake x%.2f)"), *RoamTestCars::IdOf(CarIndex).ToString(), *Roam::EnumToString(Strips[s].Surface), *Roam::EnumToString(Seen), T60, Dist,
				AsphaltAccel[CarIndex] > 0.0f ? T60 / AsphaltAccel[CarIndex] : 0.0f, AsphaltBrake[CarIndex] > 0.0f ? Dist / AsphaltBrake[CarIndex] : 0.0f));
			TestEqual(TEXT("the surface is detected"), Seen, Strips[s].Surface);
			if (s > 0 && AsphaltBrake[CarIndex] > 0.0f)
			{
				TestTrue(TEXT("loose surfaces brake longer than asphalt"), Dist > AsphaltBrake[CarIndex] * 0.9f);
			}
			Car->Destroy();
		}
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveWetTest, "Roam.Vehicle.Drive.Wet", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveWetTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}
	float Dry = 0.0f;
	for (int32 Wet = 0; Wet <= 1; ++Wet)
	{
		W.SetWetness(Wet ? 1.0f : 0.0f);
		ARoamVehicle* Car = W.SpawnCar(0, FVector(-50.0, 0.0, 0.06), 0.0f);
		W.Run(Car, 1.5f);
		const float Dist = BrakeFrom(W, Car, 100.0f, 0.0f);
		LogRow(FString::Printf(TEXT("wet car=pulse wetness=%.2f brake100to0=%.1f m"), Car->GetTelemetry().SurfaceWetness, Dist));
		if (!Wet)
		{
			Dry = Dist;
		}
		else
		{
			TestTrue(TEXT("wet braking is longer by roughly 1/0.72"), Dist > Dry * 1.2f && Dist < Dry * 1.9f);
		}
		Car->Destroy();
	}
	W.SetWetness(0.0f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveDriftTest, "Roam.Vehicle.Drive.Drift", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveDriftTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}
	for (const int32 CarIndex : SelectedCars({ 2, 9 }))
	{
		ARoamVehicle* Car = W.SpawnCar(CarIndex, FVector(0.0, 0.0, 0.06), 0.0f);
		FRoamAssistSettings Assists = Car->GetAssists();
		Assists.bStabilityControl = false;
		Assists.bTractionControl = false;
		Assists.SteeringAssist = 0.0f;
		Car->SetAssists(Assists);
		W.Run(Car, 1.5f);
		float T = 0.0f;
		while (Car->GetTelemetry().SpeedKmh < 90.0f && T < 40.0f)
		{
			Car->SetThrottle(1.0f);
			Car->SetSteer(LaneKeep(Car, 0.0f));
			W.Step(Car);
			T += StepDt;
		}
		// flick left, handbrake with the swing, steer into the slide, throttle on
		float MaxSlip = 0.0f;
		float MaxRoll = 0.0f;
		float EndSpeed = 0.0f;
		for (float P = 0.0f; P < 5.0f; P += StepDt)
		{
			float Steer = 0.0f;
			float Hand = 0.0f;
			float Throttle = 0.0f;
			if (P < 0.35f) { Steer = -0.7f; Throttle = 0.0f; }
			else if (P < 0.9f) { Steer = 0.2f; Hand = 1.0f; Throttle = 0.0f; }
			else
			{
				// hold the drift: steer into the slide proportional to the slip angle, modulate the throttle
				const float Slip = Car->GetTelemetry().BodySlipAngleDeg;
				Steer = FMath::Clamp(Slip / 25.0f, -1.0f, 1.0f);   // steer towards the direction of travel
				Throttle = 0.75f;
			}
			Car->SetSteer(Steer);
			Car->SetHandbrake(Hand);
			Car->SetThrottle(Throttle);
			W.Step(Car);
			const FRoamVehicleTelemetry& Tel = Car->GetTelemetry();
			MaxSlip = FMath::Max(MaxSlip, FMath::Abs(Tel.BodySlipAngleDeg));
			MaxRoll = FMath::Max(MaxRoll, FMath::Abs(Tel.RollDeg));
			EndSpeed = Tel.SpeedKmh;
		}
		LogRow(FString::Printf(TEXT("drift car=%s maxBodySlip=%.1f deg maxRoll=%.1f endSpeed=%.0f km/h"), *RoamTestCars::IdOf(CarIndex).ToString(), MaxSlip, MaxRoll, EndSpeed));
		TestTrue(TEXT("handbrake entry produces a real slide"), MaxSlip > 20.0f);
		TestTrue(TEXT("the car does not roll over"), MaxRoll < 30.0f);
		Car->Destroy();
	}
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FRoamDriveAssistsTest, "Roam.Vehicle.Drive.Assists", ROAM_VEH_TEST_FLAGS)
bool FRoamDriveAssistsTest::RunTest(const FString& Parameters)
{
	FDriveWorld& W = SharedWorld();
	if (!TestTrue(TEXT("world"), W.IsReady()))
	{
		return false;
	}

	// ABS flag + shorter-or-equal stopping distance with ABS on (Pulse, 100 km/h)
	float Distance[2] = {};
	bool bAbsFlag[2] = {};
	for (int32 AbsOn = 0; AbsOn <= 1; ++AbsOn)
	{
		ARoamVehicle* Car = W.SpawnCar(0, FVector(-50.0, 0.0, 0.06), 0.0f);
		FRoamAssistSettings Assists = Car->GetAssists();
		Assists.bABS = AbsOn == 1;
		Car->SetAssists(Assists);
		W.Run(Car, 1.5f);
		Distance[AbsOn] = BrakeFrom(W, Car, 100.0f, 0.0f, nullptr, &bAbsFlag[AbsOn]);
		Car->Destroy();
	}
	LogRow(FString::Printf(TEXT("assists abs: dist off=%.1f m (flag %d)  on=%.1f m (flag %d)"), Distance[0], bAbsFlag[0] ? 1 : 0, Distance[1], bAbsFlag[1] ? 1 : 0));
	TestFalse(TEXT("ABS flag stays off when the assist is off"), bAbsFlag[0]);
	TestTrue(TEXT("ABS flag lights up during hard braking"), bAbsFlag[1]);
	TestTrue(TEXT("ABS does not lengthen the stop"), Distance[1] <= Distance[0] * 1.05f);

	// TCS: launch on wet gravel (Thunderline, RWD V8): the flag lights up and the wheelspin is lower with the assist
	float MaxSlip[2] = {};
	bool bTcsFlag[2] = {};
	float Speed4s[2] = {};
	for (int32 TcsOn = 0; TcsOn <= 1; ++TcsOn)
	{
		ARoamVehicle* Car = W.SpawnCar(2, FVector(-50.0, 760.0, 0.06), 0.0f);   // gravel strip
		FRoamAssistSettings Assists = Car->GetAssists();
		Assists.bTractionControl = TcsOn == 1;
		Car->SetAssists(Assists);
		W.Run(Car, 1.5f);
		for (float T = 0.0f; T < 4.0f; T += StepDt)
		{
			Car->SetThrottle(1.0f);
			Car->SetSteer(LaneKeep(Car, 760.0f));
			W.Step(Car);
			bTcsFlag[TcsOn] |= Car->GetTelemetry().bTCSActive;
			for (int32 i = 2; i < 4; ++i)
			{
				MaxSlip[TcsOn] = FMath::Max(MaxSlip[TcsOn], Car->GetTelemetry().WheelSlipRatio[i]);
			}
		}
		Speed4s[TcsOn] = Car->GetTelemetry().SpeedKmh;
		Car->Destroy();
	}
	LogRow(FString::Printf(TEXT("assists tcs: gravel launch thunderline maxSlip off=%.2f on=%.2f flag off=%d on=%d speed@4s off=%.0f on=%.0f"), MaxSlip[0], MaxSlip[1], bTcsFlag[0] ? 1 : 0, bTcsFlag[1] ? 1 : 0, Speed4s[0], Speed4s[1]));
	TestFalse(TEXT("TCS flag stays off when the assist is off"), bTcsFlag[0]);
	TestTrue(TEXT("TCS flag lights up on a slippery launch"), bTcsFlag[1]);
	TestTrue(TEXT("TCS reduces wheelspin"), MaxSlip[1] < MaxSlip[0]);

	// assist toggles reach the movement component
	ARoamVehicle* Car = W.SpawnCar(0, FVector(-50.0, 0.0, 0.06), 0.0f);
	Car->SetAssistByName(TEXT("tcs"), false);
	Car->SetAssistByName(TEXT("stm"), false);
	Car->SetAssistByName(TEXT("abs"), false);
	TestFalse(TEXT("tcs off"), Car->GetAssists().bTractionControl);
	TestFalse(TEXT("stm off"), Car->GetAssists().bStabilityControl);
	TestFalse(TEXT("abs off"), Car->GetAssists().bABS);
	Car->SetAssistByName(TEXT("tcs"), true);
	TestTrue(TEXT("tcs on"), Car->GetAssists().bTractionControl);
	Car->Destroy();
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
