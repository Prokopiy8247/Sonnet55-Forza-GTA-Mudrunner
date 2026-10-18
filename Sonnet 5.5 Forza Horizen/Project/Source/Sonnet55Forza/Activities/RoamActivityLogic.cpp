// Copyright Epic Games, Inc. All Rights Reserved.

#include "Activities/RoamActivityLogic.h"

#include "Data/RoamRoadNetwork.h"
#include "Math/RandomStream.h"

namespace RoamActivity
{
	// ------------------------------------------------------------------------------------------------------------------
	// Gates
	// ------------------------------------------------------------------------------------------------------------------

	bool SegmentCrossesGate(const FRoamGate& Gate, const FVector& A, const FVector& B, FGateCrossing& Out, bool bAllowReverse)
	{
		const FVector Normal = Gate.Forward.GetSafeNormal();
		if (Normal.IsNearlyZero())
		{
			return false;
		}
		const double DistA = FVector::DotProduct(A - Gate.Center, Normal);
		const double DistB = FVector::DotProduct(B - Gate.Center, Normal);
		const bool bForward = DistA < 0.0 && DistB >= 0.0;
		const bool bReverse = DistA > 0.0 && DistB <= 0.0;
		if (!bForward && !(bAllowReverse && bReverse))
		{
			return false;
		}
		const double Alpha = DistA / (DistA - DistB);
		const FVector Point = A + (B - A) * Alpha;

		FVector Right = FVector::CrossProduct(FVector::UpVector, Normal);
		Right = Right.GetSafeNormal();
		if (Right.IsNearlyZero())
		{
			Right = FVector::RightVector;
		}
		const FVector Local = Point - Gate.Center;
		const double Lateral = FVector::DotProduct(Local, Right);
		if (FMath::Abs(Lateral) > Gate.HalfWidthCm || FMath::Abs(Local.Z) > Gate.HalfHeightCm)
		{
			return false;
		}
		Out.Alpha = static_cast<float>(Alpha);
		Out.Point = Point;
		Out.LateralCm = static_cast<float>(Lateral);
		Out.bForward = bForward;
		return true;
	}

	// ------------------------------------------------------------------------------------------------------------------
	// Stars / thresholds
	// ------------------------------------------------------------------------------------------------------------------

	float RoundTo(float Value, float Step)
	{
		return Step > 0.0f ? FMath::RoundToFloat(Value / Step) * Step : Value;
	}

	int32 StarsForValue(const FVector& T, float Value, bool bLowerIsBetter)
	{
		if (bLowerIsBetter)
		{
			return Value <= T.Z ? 3 : (Value <= T.Y ? 2 : (Value <= T.X ? 1 : 0));
		}
		return Value >= T.Z ? 3 : (Value >= T.Y ? 2 : (Value >= T.X ? 1 : 0));
	}

	FVector SpeedTrapThresholds(float V3Kmh)
	{
		const float V3 = RoundTo(V3Kmh, 5.0f);
		return FVector(RoundTo(0.28f * V3, 5.0f), RoundTo(0.69f * V3, 5.0f), V3);
	}

	FVector SpeedZoneThresholds(float V3Kmh)
	{
		const float V3 = RoundTo(V3Kmh, 5.0f);
		return FVector(RoundTo(0.38f * V3, 5.0f), RoundTo(0.74f * V3, 5.0f), V3);
	}

	FVector DriftThresholds(float S3)
	{
		const float Top = FMath::Max(2500.0f, RoundTo(S3, 2500.0f));
		return FVector(FMath::Max(500.0f, RoundTo(0.08f * Top, 500.0f)), RoundTo(0.53f * Top, 500.0f), Top);
	}

	FVector JumpThresholds(float D3Metres)
	{
		const float D3 = FMath::Max(RoundTo(D3Metres, 5.0f), 20.0f);
		return FVector(RoundTo(0.20f * D3, 5.0f), RoundTo(0.55f * D3, 5.0f), D3);
	}

	FVector TimeThresholds(float ProfileSeconds, float ClassFactor)
	{
		const float Base = ProfileSeconds * ClassFactor;
		return FVector(1.50f * Base, 1.30f * Base, 1.15f * Base);
	}

	FString FormatTime(float Seconds)
	{
		const float Clamped = FMath::Max(Seconds, 0.0f);
		const int32 Minutes = FMath::FloorToInt(Clamped / 60.0f);
		return FString::Printf(TEXT("%d:%05.2f"), Minutes, Clamped - 60.0f * static_cast<float>(Minutes));
	}

	FLinearColor TypeColor(ERoamActivityType Type)
	{
		switch (Type)
		{
		case ERoamActivityType::SpeedTrap:      return FLinearColor(1.00f, 0.28f, 0.10f, 1.0f);
		case ERoamActivityType::SpeedZone:      return FLinearColor(1.00f, 0.70f, 0.08f, 1.0f);
		case ERoamActivityType::DriftZone:      return FLinearColor(0.90f, 0.20f, 0.85f, 1.0f);
		case ERoamActivityType::DangerSign:     return FLinearColor(1.00f, 0.92f, 0.10f, 1.0f);
		case ERoamActivityType::CheckpointRace: return FLinearColor(0.15f, 0.90f, 0.30f, 1.0f);
		case ERoamActivityType::TimeTrial:      return FLinearColor(0.10f, 0.78f, 1.00f, 1.0f);
		case ERoamActivityType::Collectible:    return FLinearColor(1.00f, 0.80f, 0.20f, 1.0f);
		case ERoamActivityType::PhotoSpot:      return FLinearColor(0.75f, 0.85f, 1.00f, 1.0f);
		default:                                return FLinearColor::White;
		}
	}

	FString TypeTitle(ERoamActivityType Type)
	{
		switch (Type)
		{
		case ERoamActivityType::SpeedTrap:      return TEXT("SPEED TRAP");
		case ERoamActivityType::SpeedZone:      return TEXT("SPEED ZONE");
		case ERoamActivityType::DriftZone:      return TEXT("DRIFT ZONE");
		case ERoamActivityType::DangerSign:     return TEXT("DANGER SIGN");
		case ERoamActivityType::CheckpointRace: return TEXT("ROAD RACE");
		case ERoamActivityType::TimeTrial:      return TEXT("TIME TRIAL");
		case ERoamActivityType::Collectible:    return TEXT("COLLECTIBLE");
		case ERoamActivityType::PhotoSpot:      return TEXT("PHOTO SPOT");
		default:                                return TEXT("ACTIVITY");
		}
	}

	int32 XpForStarImprovement(int32 OldStars, int32 NewStars, int32 XpReward)
	{
		static const int32 Table[4] = { 0, 100, 250, 500 };
		OldStars = FMath::Clamp(OldStars, 0, 3);
		NewStars = FMath::Clamp(NewStars, 0, 3);
		int32 Xp = FMath::Max(0, Table[NewStars] - Table[OldStars]);
		if (OldStars == 0 && NewStars > 0)
		{
			Xp += 50;
		}
		return FMath::RoundToInt(static_cast<float>(Xp) * static_cast<float>(XpReward) / 100.0f);
	}

	// ------------------------------------------------------------------------------------------------------------------
	// Drift tracker
	// ------------------------------------------------------------------------------------------------------------------

	void FDriftTracker::Reset()
	{
		bDrifting = false;
		CandidateSec = 0.0f;
		GapSec = 0.0f;
		ChainSec = 0.0f;
		Multiplier = 1;
		ChainScore = 0.0f;
		ZoneScore = 0.0f;
	}

	void FDriftTracker::Step(float Dt, float SpeedKmh, float SlipDeg, bool bGrounded)
	{
		const float Angle = FMath::Abs(SlipDeg);
		const float LowAngle = bDrifting ? KeepAngleDeg : EnterAngleDeg;
		const bool bCandidate = bGrounded && SpeedKmh >= MinSpeedKmh && Angle >= LowAngle && Angle <= MaxAngleDeg;
		if (bCandidate)
		{
			GapSec = 0.0f;
			if (!bDrifting)
			{
				CandidateSec += Dt;
				if (CandidateSec >= EnterHoldSec)
				{
					bDrifting = true;
					ChainSec = 0.0f;
					ChainScore = 0.0f;
					Multiplier = 1;
				}
			}
			else
			{
				ChainSec += Dt;
				Multiplier = FMath::Min(5, 1 + FMath::FloorToInt(ChainSec / MultStepSec));
				const float Rate = 0.5f * FMath::Min(SpeedKmh, 140.0f) * FMath::Min(Angle, 60.0f) * RateScale;
				ChainScore += Rate * static_cast<float>(Multiplier) * Dt;
			}
		}
		else
		{
			CandidateSec = 0.0f;
			if (bDrifting)
			{
				GapSec += Dt;
				if (GapSec > TransitionSec)
				{
					BankChain();
				}
			}
		}
	}

	void FDriftTracker::LoseChain()
	{
		bDrifting = false;
		CandidateSec = 0.0f;
		GapSec = 0.0f;
		ChainSec = 0.0f;
		Multiplier = 1;
		ChainScore = 0.0f;
	}

	void FDriftTracker::BankChain()
	{
		ZoneScore += ChainScore;
		bDrifting = false;
		CandidateSec = 0.0f;
		GapSec = 0.0f;
		ChainSec = 0.0f;
		Multiplier = 1;
		ChainScore = 0.0f;
	}

	// ------------------------------------------------------------------------------------------------------------------
	// Placement
	// ------------------------------------------------------------------------------------------------------------------

	namespace
	{
		constexpr float LateralAccelMs2 = 7.5f; // reference (top) car cornering limit used for the speed profile

		FVector Flat(const FVector& V)
		{
			const FVector F(V.X, V.Y, 0.0);
			return F.IsNearlyZero() ? FVector::ForwardVector : F.GetSafeNormal();
		}

		float ClassSpeedCapKmh(ERoamRoadClass RoadClass)
		{
			switch (RoadClass)
			{
			case ERoamRoadClass::Highway:  return 230.0f;
			case ERoamRoadClass::Regional: return 170.0f;
			case ERoamRoadClass::Mountain: return 130.0f;
			case ERoamRoadClass::Dirt:     return 100.0f;
			case ERoamRoadClass::Shortcut: return 100.0f;
			case ERoamRoadClass::Village:  return 80.0f;
			default:                       return 120.0f;
			}
		}

		float RoadLength(const FRoamRoad& Road)
		{
			return Road.Samples.Num() >= 2 ? Road.Samples.Last().S : Road.LengthCm;
		}

		bool IsPaved(const FRoamRoad& Road)
		{
			return Road.RoadClass != ERoamRoadClass::Dirt && Road.RoadClass != ERoamRoadClass::Shortcut;
		}

		/** Cornering-limited speed profile of one road (curvature from tangents +-15 m around each sample). */
		struct FRoadProfile
		{
			const FRoamRoad* Road = nullptr;
			TArray<float> VKmh;
			TArray<float> CumTime;
			TArray<float> CumTurn;
			TArray<float> Kappa; // 1/cm

			void Build(const FRoamRoad& InRoad)
			{
				Road = &InRoad;
				const int32 N = InRoad.Samples.Num();
				VKmh.SetNumZeroed(N);
				CumTime.SetNumZeroed(N);
				CumTurn.SetNumZeroed(N);
				Kappa.SetNumZeroed(N);
				if (N < 2)
				{
					return;
				}
				const float Spacing = FMath::Max(RoadLength(InRoad) / static_cast<float>(N - 1), 50.0f);
				const int32 K = FMath::Max(1, FMath::RoundToInt(1500.0f / Spacing));
				const float Cap = ClassSpeedCapKmh(InRoad.RoadClass);
				for (int32 i = 0; i < N; ++i)
				{
					const int32 I0 = FMath::Max(0, i - K);
					const int32 I1 = FMath::Min(N - 1, i + K);
					const FVector T0 = Flat(InRoad.Samples[I0].Tangent);
					const FVector T1 = Flat(InRoad.Samples[I1].Tangent);
					const float Angle = FMath::Acos(FMath::Clamp(static_cast<float>(FVector::DotProduct(T0, T1)), -1.0f, 1.0f));
					const float Arc = InRoad.Samples[I1].S - InRoad.Samples[I0].S;
					Kappa[i] = Arc > 1.0f ? Angle / Arc : 0.0f;
					float V = Cap;
					if (Kappa[i] > 1.0e-7f)
					{
						const float RadiusM = 1.0f / (Kappa[i] * 100.0f);
						V = FMath::Min(Cap, FMath::Sqrt(LateralAccelMs2 * RadiusM) * 3.6f);
					}
					VKmh[i] = FMath::Max(V, 15.0f);
				}
				for (int32 i = 1; i < N; ++i)
				{
					const float DsM = (InRoad.Samples[i].S - InRoad.Samples[i - 1].S) * 0.01f;
					const float VMs = FMath::Max(0.5f * (VKmh[i] + VKmh[i - 1]) / 3.6f, 3.0f);
					CumTime[i] = CumTime[i - 1] + DsM / VMs;
					const float Step = FMath::Acos(FMath::Clamp(static_cast<float>(FVector::DotProduct(Flat(InRoad.Samples[i - 1].Tangent), Flat(InRoad.Samples[i].Tangent))), -1.0f, 1.0f));
					CumTurn[i] = CumTurn[i - 1] + FMath::RadiansToDegrees(Step);
				}
			}

			int32 IndexAt(float S) const
			{
				int32 Lo = 0;
				int32 Hi = Road->Samples.Num() - 1;
				while (Lo < Hi)
				{
					const int32 Mid = (Lo + Hi) / 2;
					if (Road->Samples[Mid].S < S) { Lo = Mid + 1; } else { Hi = Mid; }
				}
				return Lo;
			}

			float InterpAt(const TArray<float>& Values, float S) const
			{
				const int32 i = IndexAt(S);
				if (i <= 0)
				{
					return Values[0];
				}
				const float S0 = Road->Samples[i - 1].S;
				const float S1 = Road->Samples[i].S;
				const float A = S1 > S0 ? FMath::Clamp((S - S0) / (S1 - S0), 0.0f, 1.0f) : 1.0f;
				return FMath::Lerp(Values[i - 1], Values[i], A);
			}

			float TimeSec(float S0, float S1) const { return FMath::Max(InterpAt(CumTime, S1) - InterpAt(CumTime, S0), 0.1f); }
			float TurnDeg(float S0, float S1) const { return InterpAt(CumTurn, S1) - InterpAt(CumTurn, S0); }
			float AvgKmh(float S0, float S1) const { return (S1 - S0) * 0.01f / TimeSec(S0, S1) * 3.6f; }

			float MaxKappa(float S0, float S1) const
			{
				float Max = 0.0f;
				for (int32 i = IndexAt(S0); i <= IndexAt(S1) && i < Kappa.Num(); ++i)
				{
					Max = FMath::Max(Max, Kappa[i]);
				}
				return Max;
			}

			float MinKmh(float S0, float S1) const
			{
				float Min = 1.0e6f;
				for (int32 i = IndexAt(S0); i <= IndexAt(S1) && i < VKmh.Num(); ++i)
				{
					Min = FMath::Min(Min, VKmh[i]);
				}
				return Min < 1.0e5f ? Min : 100.0f;
			}
		};

		FRoamGate MakeGate(const FRoamRoad& Road, float S)
		{
			const FRoamRoadSample Sample = URoamRoadNetwork::SampleRoad(Road, S);
			FRoamGate Gate;
			Gate.Forward = Flat(Sample.Tangent);
			Gate.Center = Sample.Position + FVector(0.0, 0.0, 150.0);
			Gate.HalfWidthCm = FMath::Max(700.0f, Sample.WidthCm * 0.5f + 350.0f);
			Gate.HalfHeightCm = 450.0f;
			return Gate;
		}

		void SampleRoute(const FRoamRoad& Road, float S0, float S1, float Step, TArray<FVector>& Out)
		{
			for (float S = S0; S < S1; S += Step)
			{
				Out.Add(URoamRoadNetwork::SampleRoad(Road, S).Position);
			}
			Out.Add(URoamRoadNetwork::SampleRoad(Road, S1).Position);
		}

		struct FOccupancy
		{
			TMap<int32, TArray<TPair<float, float>>> Intervals;

			bool IsFree(int32 RoadIndex, float S0, float S1, float Pad) const
			{
				if (const TArray<TPair<float, float>>* List = Intervals.Find(RoadIndex))
				{
					for (const TPair<float, float>& I : *List)
					{
						if (S0 < I.Value + Pad && S1 > I.Key - Pad)
						{
							return false;
						}
					}
				}
				return true;
			}

			void Add(int32 RoadIndex, float S0, float S1) { Intervals.FindOrAdd(RoadIndex).Add(TPair<float, float>(S0, S1)); }
		};
	}

	void GenerateDefaultActivityDefs(const URoamRoadNetwork& Network, const URoamWorldDefinition* WorldDef, const FPlacementOptions& Options, TArray<FRoamActivityDef>& OutDefs)
	{
		OutDefs.Reset();
		const TArray<FRoamRoad>& Roads = Network.Roads;
		if (Roads.Num() == 0)
		{
			return;
		}
		FRandomStream Rand(Options.Seed);

		TArray<FRoadProfile> Profiles;
		Profiles.SetNum(Roads.Num());
		TArray<bool> Built;
		Built.Init(false, Roads.Num());
		const auto Profile = [&](int32 RoadIndex) -> const FRoadProfile&
		{
			if (!Built[RoadIndex])
			{
				Profiles[RoadIndex].Build(Roads[RoadIndex]);
				Built[RoadIndex] = true;
			}
			return Profiles[RoadIndex];
		};

		TArray<int32> ByLength;
		for (int32 i = 0; i < Roads.Num(); ++i)
		{
			if (Roads[i].Samples.Num() >= 2)
			{
				ByLength.Add(i);
			}
		}
		ByLength.Sort([&Roads](int32 A, int32 B) { return RoadLength(Roads[A]) > RoadLength(Roads[B]); });
		if (ByLength.Num() == 0)
		{
			return;
		}

		FOccupancy Occupied;
		const auto RegionFor = [&](const FVector& Position, const FRoamRoad& Road) -> FName
		{
			if (WorldDef)
			{
				if (const FRoamRegionDef* Region = WorldDef->FindRegionAt(Position))
				{
					return Region->RegionId;
				}
			}
			return Road.RegionId;
		};

		const auto Fill = [&](FRoamActivityDef& Def, ERoamActivityType Type, const TCHAR* Prefix, int32 Number, const FString& Label, int32 RoadIndex, float S)
		{
			Def.ActivityId = FName(*FString::Printf(TEXT("%s_%02d"), Prefix, Number));
			Def.Type = Type;
			Def.DisplayName = FText::FromString(FString::Printf(TEXT("%s %02d (%s)"), *Label, Number, *Roads[RoadIndex].RoadId.ToString()));
			Def.RoadId = Roads[RoadIndex].RoadId;
			Def.RoadS = S;
			Def.RegionId = RegionFor(URoamRoadNetwork::SampleRoad(Roads[RoadIndex], S).Position, Roads[RoadIndex]);
		};

		// Round-robin over roads (longest first), three passes with shrinking length so short synthetic networks still fill up.
		const auto PlaceRoundRobin = [&](int32 Want, const TArray<int32>& Order, const TFunctionRef<bool(int32)>& Eligible, const TFunctionRef<bool(int32, float)>& TryPlace) -> int32
		{
			int32 Placed = 0;
			const float Scales[3] = { 1.0f, 0.6f, 0.4f };
			for (const float Scale : Scales)
			{
				for (int32 Round = 0; Round < 4 && Placed < Want; ++Round)
				{
					bool bAny = false;
					for (const int32 RoadIndex : Order)
					{
						if (Placed >= Want)
						{
							break;
						}
						if (Eligible(RoadIndex) && TryPlace(RoadIndex, Scale))
						{
							++Placed;
							bAny = true;
						}
					}
					if (!bAny)
					{
						break;
					}
				}
			}
			return Placed;
		};

		const float ClassFactor = Options.ClassFactor;

		// ---- jumps: straight crests only ---------------------------------------------------------------------------------
		struct FCrest { int32 Road; float S; float Dz; float Grade; };
		TArray<FCrest> Crests;
		for (const int32 R : ByLength)
		{
			const FRoamRoad& Road = Roads[R];
			const float L = RoadLength(Road);
			if (!IsPaved(Road) || Road.RoadClass == ERoamRoadClass::Village || L < 60000.0f)
			{
				continue;
			}
			const int32 N = Road.Samples.Num();
			const float Spacing = FMath::Max(L / static_cast<float>(N - 1), 50.0f);
			const int32 K = FMath::Max(2, FMath::RoundToInt(4000.0f / Spacing));
			for (int32 i = K; i < N - K; i += FMath::Max(1, K / 4))
			{
				const double Dz = Road.Samples[i - K].Position.Z + Road.Samples[i + K].Position.Z - 2.0 * Road.Samples[i].Position.Z;
				const float S = Road.Samples[i].S;
				if (Dz < -50.0 && S > 30000.0f && S < L - 10000.0f && Profile(R).MaxKappa(S - 30000.0f, S + 10000.0f) < 1.0f / 50000.0f)
				{
					const float Grade = static_cast<float>((Road.Samples[i].Position.Z - Road.Samples[i - K].Position.Z) / (static_cast<double>(K) * Spacing));
					Crests.Add({ R, S, static_cast<float>(Dz), Grade });
				}
			}
		}
		Crests.Sort([](const FCrest& A, const FCrest& B) { return A.Dz < B.Dz; });
		int32 NumJumps = 0;
		for (const FCrest& Crest : Crests)
		{
			if (NumJumps >= Options.NumJumps)
			{
				break;
			}
			const FRoamRoad& Road = Roads[Crest.Road];
			const float GateS = Crest.S - 4500.0f;
			if (!Occupied.IsFree(Crest.Road, GateS - 2000.0f, Crest.S + 9000.0f, 3000.0f))
			{
				continue;
			}
			Occupied.Add(Crest.Road, GateS - 2000.0f, Crest.S + 9000.0f);
			const float VMs = FMath::Min(Profile(Crest.Road).MinKmh(Crest.S - 20000.0f, Crest.S), 200.0f) / 3.6f;
			const float Theta = FMath::DegreesToRadians(FMath::Max(6.0f, FMath::RadiansToDegrees(FMath::Atan(Crest.Grade))));
			const float RangeM = VMs * VMs * FMath::Sin(2.0f * Theta) / 9.81f;
			FRoamActivityDef Def;
			Fill(Def, ERoamActivityType::DangerSign, TEXT("jump"), ++NumJumps, TEXT("Danger Sign"), Crest.Road, GateS);
			Def.Gates.Add(MakeGate(Road, GateS));
			Def.StarThresholds = JumpThresholds(FMath::Clamp(0.85f * RangeM, 40.0f, 250.0f));
			Def.XpReward = 100;
			Def.Params.Add(TEXT("LaunchWindowCm"), 9000.0f);
			Def.Params.Add(TEXT("CrestS"), Crest.S);
			OutDefs.Add(Def);
		}

		// ---- checkpoint races ------------------------------------------------------------------------------------------
		int32 NumRaces = 0;
		PlaceRoundRobin(Options.NumRaces, ByLength,
			[&](int32 R) { return IsPaved(Roads[R]) && Roads[R].RoadClass != ERoamRoadClass::Village && RoadLength(Roads[R]) >= 80000.0f; },
			[&](int32 R, float Scale) -> bool
			{
				const FRoamRoad& Road = Roads[R];
				const float L = RoadLength(Road);
				const float RL = FMath::Min(L - 20000.0f, FMath::Min(400000.0f, FMath::Max(60000.0f, L * 0.6f)) * Scale);
				if (RL < 50000.0f)
				{
					return false;
				}
				for (int32 Try = 0; Try < 14; ++Try)
				{
					const float S0 = 5000.0f + Rand.FRand() * FMath::Max(L - RL - 10000.0f, 0.0f);
					if (!Occupied.IsFree(R, S0, S0 + RL, 4000.0f))
					{
						continue;
					}
					Occupied.Add(R, S0, S0 + RL);
					const int32 Legs = FMath::Clamp(FMath::RoundToInt(RL / 60000.0f), 2, 7);
					FRoamActivityDef Def;
					Fill(Def, ERoamActivityType::CheckpointRace, TEXT("race"), ++NumRaces, TEXT("Road Race"), R, S0);
					for (int32 g = 0; g <= Legs; ++g)
					{
						Def.Gates.Add(MakeGate(Road, S0 + RL * static_cast<float>(g) / static_cast<float>(Legs)));
					}
					SampleRoute(Road, S0, S0 + RL, 500.0f, Def.RoutePoints);
					const float Tp = Profile(R).TimeSec(S0, S0 + RL);
					Def.StarThresholds = TimeThresholds(Tp, ClassFactor);
					Def.bLowerIsBetter = true;
					Def.XpReward = 200;
					Def.Params.Add(TEXT("ProfileSeconds"), Tp);
					Def.Params.Add(TEXT("TimeLimitSec"), 1.8f * Tp * ClassFactor + 20.0f);
					Def.Params.Add(TEXT("LengthCm"), RL);
					OutDefs.Add(Def);
					return true;
				}
				return false;
			});

		// ---- speed zones -----------------------------------------------------------------------------------------------
		int32 NumZones = 0;
		PlaceRoundRobin(Options.NumSpeedZones, ByLength,
			[&](int32 R) { return IsPaved(Roads[R]) && Roads[R].RoadClass != ERoamRoadClass::Village && RoadLength(Roads[R]) >= 60000.0f; },
			[&](int32 R, float Scale) -> bool
			{
				const FRoamRoad& Road = Roads[R];
				const float L = RoadLength(Road);
				const float ZL = FMath::Min(L - 20000.0f, FMath::Min(250000.0f, FMath::Max(80000.0f, L * 0.45f)) * Scale);
				if (ZL < 30000.0f)
				{
					return false;
				}
				for (int32 Try = 0; Try < 14; ++Try)
				{
					const float S0 = 5000.0f + Rand.FRand() * FMath::Max(L - ZL - 10000.0f, 0.0f);
					if (!Occupied.IsFree(R, S0, S0 + ZL, 4000.0f))
					{
						continue;
					}
					Occupied.Add(R, S0, S0 + ZL);
					FRoamActivityDef Def;
					Fill(Def, ERoamActivityType::SpeedZone, TEXT("zone"), ++NumZones, TEXT("Speed Zone"), R, S0);
					Def.Gates.Add(MakeGate(Road, S0));
					Def.Gates.Add(MakeGate(Road, S0 + ZL));
					SampleRoute(Road, S0, S0 + ZL, 500.0f, Def.RoutePoints);
					const float V3 = RoundTo(0.92f * Profile(R).AvgKmh(S0, S0 + ZL), 5.0f);
					Def.StarThresholds = SpeedZoneThresholds(V3);
					Def.XpReward = 100;
					Def.Params.Add(TEXT("LengthCm"), ZL);
					OutDefs.Add(Def);
					return true;
				}
				return false;
			});

		// ---- drift zones: the most winding stretches first -------------------------------------------------------------
		TArray<int32> WindingOrder = ByLength;
		const auto Winding = [&](int32 R) { return Profile(R).TurnDeg(0.0f, RoadLength(Roads[R])) / FMath::Max(RoadLength(Roads[R]), 1.0f); };
		WindingOrder.Sort([&](int32 A, int32 B) { return Winding(A) > Winding(B); });
		int32 NumDrift = 0;
		PlaceRoundRobin(Options.NumDriftZones, WindingOrder,
			[&](int32 R) { return Roads[R].RoadClass != ERoamRoadClass::Highway && RoadLength(Roads[R]) >= 35000.0f; },
			[&](int32 R, float Scale) -> bool
			{
				const FRoamRoad& Road = Roads[R];
				const FRoadProfile& P = Profile(R);
				const float L = RoadLength(Road);
				const float DL = FMath::Min(L - 10000.0f, FMath::Min(70000.0f, FMath::Max(35000.0f, L * 0.25f)) * FMath::Max(Scale, 0.6f));
				if (DL < 25000.0f)
				{
					return false;
				}
				float BestS = -1.0f;
				float BestScore = -1.0f;
				for (float S0 = 5000.0f; S0 + DL <= L - 5000.0f; S0 += 5000.0f)
				{
					if (!Occupied.IsFree(R, S0, S0 + DL, 4000.0f))
					{
						continue;
					}
					const float Score = P.TurnDeg(S0, S0 + DL) + 0.01f * Rand.FRand();
					if (Score > BestScore)
					{
						BestScore = Score;
						BestS = S0;
					}
				}
				if (BestS < 0.0f)
				{
					return false;
				}
				Occupied.Add(R, BestS, BestS + DL);
				FRoamActivityDef Def;
				Fill(Def, ERoamActivityType::DriftZone, TEXT("drift"), ++NumDrift, TEXT("Drift Zone"), R, BestS);
				Def.Gates.Add(MakeGate(Road, BestS));
				Def.Gates.Add(MakeGate(Road, BestS + DL));
				SampleRoute(Road, BestS, BestS + DL, 500.0f, Def.RoutePoints);
				const float TDrift = 0.7f * (DL * 0.01f) / (65.0f / 3.6f);
				const float RateNominal = 0.5f * 65.0f * 30.0f;
				const float Ideal = RateNominal * (TDrift >= 8.0f ? 5.0f * TDrift - 20.0f : TDrift);
				Def.StarThresholds = DriftThresholds(0.6f * Ideal);
				Def.XpReward = 100;
				Def.Params.Add(TEXT("LengthCm"), DL);
				Def.Params.Add(TEXT("TurnDeg"), BestScore);
				OutDefs.Add(Def);
				return true;
			});

		// ---- speed traps: end of the straightest run-up ----------------------------------------------------------------
		TArray<TPair<int32, float>> TrapSites;
		int32 NumTraps = 0;
		PlaceRoundRobin(Options.NumSpeedTraps, ByLength,
			[&](int32 R) { return IsPaved(Roads[R]) && Roads[R].RoadClass != ERoamRoadClass::Village && RoadLength(Roads[R]) >= 30000.0f; },
			[&](int32 R, float Scale) -> bool
			{
				(void)Scale;
				const FRoamRoad& Road = Roads[R];
				const FRoadProfile& P = Profile(R);
				const float L = RoadLength(Road);
				const float RunUp = FMath::Min(100000.0f, L * 0.6f);
				float BestS = -1.0f;
				float BestScore = 1.0e9f;
				for (float S = FMath::Min(RunUp, L * 0.5f); S <= L - 5000.0f; S += 5000.0f)
				{
					bool bSpaced = true;
					for (const TPair<int32, float>& Site : TrapSites)
					{
						if (Site.Key == R && FMath::Abs(Site.Value - S) < 20000.0f)
						{
							bSpaced = false;
							break;
						}
					}
					if (!bSpaced)
					{
						continue;
					}
					const float Score = P.MaxKappa(FMath::Max(S - RunUp, 0.0f), S) * 1.0e5f + 0.05f * Rand.FRand();
					if (Score < BestScore)
					{
						BestScore = Score;
						BestS = S;
					}
				}
				if (BestS < 0.0f)
				{
					return false;
				}
				TrapSites.Add(TPair<int32, float>(R, BestS));
				const float V0 = 100.0f / 3.6f;
				const float ReachMs = FMath::Sqrt(V0 * V0 + 2.0f * 4.0f * RunUp * 0.01f);
				const float Reach = FMath::Min(ClassSpeedCapKmh(Road.RoadClass), ReachMs * 3.6f);
				const float Local = FMath::Max(P.MinKmh(FMath::Max(BestS - 25000.0f, 0.0f), BestS), 60.0f);
				const float V3 = RoundTo(0.96f * FMath::Min(Reach, Local * 1.15f), 5.0f);
				FRoamActivityDef Def;
				Fill(Def, ERoamActivityType::SpeedTrap, TEXT("trap"), ++NumTraps, TEXT("Speed Trap"), R, BestS);
				Def.Gates.Add(MakeGate(Road, BestS));
				Def.StarThresholds = SpeedTrapThresholds(V3);
				Def.XpReward = 100;
				Def.Params.Add(TEXT("RunUpCm"), RunUp);
				OutDefs.Add(Def);
				return true;
			});

		// ---- time trial on the loop chain -------------------------------------------------------------------------------
		if (Options.NumTimeTrials > 0)
		{
			TArray<int32> Candidates;
			for (const int32 R : ByLength)
			{
				if (Roads[R].RoadId.ToString().StartsWith(TEXT("LOOP"), ESearchCase::IgnoreCase))
				{
					Candidates.Add(R);
				}
			}
			if (Candidates.Num() == 0)
			{
				for (const int32 R : ByLength)
				{
					if (IsPaved(Roads[R]) && RoadLength(Roads[R]) >= 40000.0f)
					{
						Candidates.Add(R);
					}
				}
			}
			if (Candidates.Num() > 0)
			{
				// Chain start: a candidate that no other candidate leads into (else the longest one).
				int32 Start = Candidates[0];
				for (const int32 R : Candidates)
				{
					bool bHasPredecessor = false;
					for (const int32 Other : Candidates)
					{
						if (Other != R && !Roads[R].StartJunction.IsNone() && Roads[Other].EndJunction == Roads[R].StartJunction)
						{
							bHasPredecessor = true;
							break;
						}
					}
					if (!bHasPredecessor)
					{
						Start = R;
						break;
					}
				}
				TArray<int32> Chain;
				Chain.Add(Start);
				while (Chain.Num() < 12)
				{
					const FRoamRoad& Current = Roads[Chain.Last()];
					int32 Next = INDEX_NONE;
					for (const int32 R : Candidates)
					{
						if (!Chain.Contains(R) && !Current.EndJunction.IsNone() && Roads[R].StartJunction == Current.EndJunction)
						{
							Next = R;
							break;
						}
					}
					if (Next == INDEX_NONE)
					{
						break;
					}
					Chain.Add(Next);
				}

				const float Margin = 15000.0f;
				float Total = 0.0f;
				TArray<float> Starts;
				for (const int32 R : Chain)
				{
					Starts.Add(Total);
					Total += RoadLength(Roads[R]);
				}
				const float Usable = Total - 2.0f * Margin;
				if (Usable >= 60000.0f)
				{
					const auto ChainToRoad = [&](float D, int32& OutChainIndex, float& OutS)
					{
						D = FMath::Clamp(D, 0.0f, Total);
						OutChainIndex = 0;
						for (int32 c = Chain.Num() - 1; c >= 0; --c)
						{
							if (D >= Starts[c])
							{
								OutChainIndex = c;
								break;
							}
						}
						OutS = FMath::Clamp(D - Starts[OutChainIndex], 0.0f, RoadLength(Roads[Chain[OutChainIndex]]));
					};

					FRoamActivityDef Def;
					int32 C0 = 0;
					float S0 = 0.0f;
					ChainToRoad(Margin, C0, S0);
					Fill(Def, ERoamActivityType::TimeTrial, TEXT("tt"), 1, TEXT("Scenic Loop Time Trial"), Chain[C0], S0);
					Def.ActivityId = TEXT("tt_loop");
					const int32 Legs = FMath::Clamp(FMath::RoundToInt(Usable / 200000.0f), 2, 14);
					for (int32 g = 0; g <= Legs; ++g)
					{
						int32 C = 0;
						float S = 0.0f;
						ChainToRoad(Margin + Usable * static_cast<float>(g) / static_cast<float>(Legs), C, S);
						Def.Gates.Add(MakeGate(Roads[Chain[C]], S));
					}
					float Tp = 0.0f;
					for (int32 c = 0; c < Chain.Num(); ++c)
					{
						const FRoamRoad& Road = Roads[Chain[c]];
						const float L = RoadLength(Road);
						const float A = c == 0 ? Margin : 0.0f;
						const float B = c == Chain.Num() - 1 ? L - Margin : L;
						if (B > A)
						{
							Tp += Profile(Chain[c]).TimeSec(A, B);
							SampleRoute(Road, A, B, 2000.0f, Def.RoutePoints);
						}
					}
					Def.StarThresholds = TimeThresholds(Tp, ClassFactor);
					Def.bLowerIsBetter = true;
					Def.XpReward = 500;
					Def.Params.Add(TEXT("ProfileSeconds"), Tp);
					Def.Params.Add(TEXT("LengthCm"), Usable);
					Def.Params.Add(TEXT("TimeLimitSec"), 0.0f);
					OutDefs.Add(Def);
				}
			}
		}

		// ---- photo spots (viewpoints first) and collectibles -------------------------------------------------------------
		int32 NumPhoto = 0;
		if (WorldDef)
		{
			for (const FRoamPoiDef& Poi : WorldDef->Pois)
			{
				if (NumPhoto >= Options.NumPhotoSpots)
				{
					break;
				}
				if (Poi.Type == ERoamPoiType::Viewpoint)
				{
					FRoamActivityDef Def;
					Def.ActivityId = FName(*FString::Printf(TEXT("photo_%02d"), ++NumPhoto));
					Def.Type = ERoamActivityType::PhotoSpot;
					Def.DisplayName = Poi.DisplayName;
					Def.RegionId = Poi.RegionId;
					FRoamGate Gate;
					Gate.Center = Poi.Location;
					Gate.Forward = FVector(FMath::Cos(FMath::DegreesToRadians(Poi.YawDeg)), FMath::Sin(FMath::DegreesToRadians(Poi.YawDeg)), 0.0);
					Gate.HalfWidthCm = 2500.0f;
					Gate.HalfHeightCm = 1500.0f;
					Def.Gates.Add(Gate);
					Def.XpReward = 50;
					OutDefs.Add(Def);
				}
			}
		}
		const auto PlaceRoadside = [&](ERoamActivityType Type, const TCHAR* Prefix, const TCHAR* Label, int32& Counter, int32 Want, float Radius, float SideOffset, bool bPreferUnpaved)
		{
			for (int32 Try = 0; Try < Want * 6 && Counter < Want; ++Try)
			{
				const int32 R = ByLength[Rand.RandRange(0, ByLength.Num() - 1)];
				const FRoamRoad& Road = Roads[R];
				const float L = RoadLength(Road);
				if (L < 20000.0f || (bPreferUnpaved && Try < Want * 3 && IsPaved(Road)))
				{
					continue;
				}
				const float S = 5000.0f + Rand.FRand() * (L - 10000.0f);
				const FRoamRoadSample Sample = URoamRoadNetwork::SampleRoad(Road, S);
				const FVector T = Flat(Sample.Tangent);
				const FVector Right = FVector::CrossProduct(FVector::UpVector, T).GetSafeNormal();
				FRoamActivityDef Def;
				Fill(Def, Type, Prefix, ++Counter, Label, R, S);
				FRoamGate Gate;
				Gate.Center = Sample.Position + Right * SideOffset * (Sample.WidthCm * 0.5f + 800.0f) + FVector(0.0, 0.0, 100.0);
				Gate.Forward = T;
				Gate.HalfWidthCm = Radius;
				Gate.HalfHeightCm = 1200.0f;
				Def.Gates.Add(Gate);
				Def.XpReward = Type == ERoamActivityType::PhotoSpot ? 50 : 200;
				OutDefs.Add(Def);
			}
		};
		PlaceRoadside(ERoamActivityType::PhotoSpot, TEXT("photo"), TEXT("Photo Spot"), NumPhoto, Options.NumPhotoSpots, 2500.0f, 1.0f, false);
		int32 NumCollect = 0;
		PlaceRoadside(ERoamActivityType::Collectible, TEXT("collect"), TEXT("Collectible"), NumCollect, Options.NumCollectibles, 1500.0f, 0.0f, true);
	}
}
