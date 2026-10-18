// Copyright Epic Games, Inc. All Rights Reserved.

#include "RoamWorldBuilder.h"

#include "Core/RoamLog.h"
#include "Core/RoamTypes.h"
#include "Data/RoamRoadNetwork.h"
#include "Data/RoamWorldDefinition.h"

#include "AssetRegistry/AssetRegistryModule.h"
#include "Async/ParallelFor.h"
#include "Dom/JsonObject.h"
#include "Editor.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "Landscape.h"
#include "LandscapeComponent.h"
#include "LandscapeEditTypes.h"
#include "LandscapeInfo.h"
#include "LandscapeLayerInfoObject.h"
#include "LandscapeProxy.h"
#include "LandscapeStreamingProxy.h"
#include "LandscapeSubsystem.h"
#include "LandscapeUtils.h"
#include "Materials/MaterialInterface.h"
#include "Misc/FileHelper.h"
#include "Misc/PackageName.h"
#include "Misc/Paths.h"
#include "PhysicalMaterials/PhysicalMaterial.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "UObject/Package.h"
#include "UObject/SavePackage.h"
#include "UObject/UnrealType.h"
#include "WorldPartition/RuntimeHashSet/RuntimePartition.h"
#include "WorldPartition/RuntimeHashSet/RuntimePartitionLHGrid.h"
#include "WorldPartition/RuntimeHashSet/WorldPartitionRuntimeHashSet.h"
#include "WorldPartition/WorldPartition.h"

namespace
{
	/** Wall clock seconds. */
	double NowSeconds()
	{
		return FPlatformTime::Seconds();
	}

	bool LoadJsonFile(const FString& Path, TSharedPtr<FJsonObject>& OutRoot, FString& OutError)
	{
		FString Text;
		if (!FFileHelper::LoadFileToString(Text, *Path))
		{
			OutError = FString::Printf(TEXT("cannot read '%s'"), *Path);
			return false;
		}
		const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(Text);
		if (!FJsonSerializer::Deserialize(Reader, OutRoot) || !OutRoot.IsValid())
		{
			OutError = FString::Printf(TEXT("invalid JSON in '%s'"), *Path);
			return false;
		}
		return true;
	}

	double NumField(const TSharedPtr<FJsonObject>& Object, const TCHAR* Name, double Default = 0.0)
	{
		double Value = Default;
		if (Object.IsValid())
		{
			Object->TryGetNumberField(Name, Value);
		}
		return Value;
	}

	FString StrField(const TSharedPtr<FJsonObject>& Object, const TCHAR* Name, const FString& Default = FString())
	{
		FString Value = Default;
		if (Object.IsValid())
		{
			Object->TryGetStringField(Name, Value);
		}
		return Value;
	}

	/** Saves the package of an asset to its .uasset file. */
	bool SavePackageOf(UObject* Asset)
	{
		if (!Asset)
		{
			return false;
		}
		UPackage* Package = Asset->GetPackage();
		const FString FileName = FPackageName::LongPackageNameToFilename(Package->GetName(), FPackageName::GetAssetPackageExtension());
		FSavePackageArgs Args;
		Args.TopLevelFlags = RF_Public | RF_Standalone;
		Args.SaveFlags = SAVE_NoError;
		return UPackage::SavePackage(Package, Asset, *FileName, Args);
	}

	/** Creates or loads (and returns) an asset object of class T at /Game/... path. bOutCreated reports whether it is new. */
	template <typename T>
	T* FindOrCreateAsset(const FString& AssetPath, bool& bOutCreated)
	{
		const FString ShortName = FPackageName::GetShortName(AssetPath);
		const FString ObjectPath = AssetPath + TEXT(".") + ShortName;
		bOutCreated = false;
		if (T* Existing = LoadObject<T>(nullptr, *ObjectPath, nullptr, LOAD_NoWarn | LOAD_Quiet))
		{
			return Existing;
		}
		UPackage* Package = CreatePackage(*AssetPath);
		T* Created = NewObject<T>(Package, *ShortName, RF_Public | RF_Standalone | RF_Transactional);
		if (Created)
		{
			bOutCreated = true;
			FAssetRegistryModule::AssetCreated(Created);
		}
		return Created;
	}

	// ------------------------------------------------------------------------------------------------------------------
	// roads.json model
	// ------------------------------------------------------------------------------------------------------------------

	struct FRawSample
	{
		double S = 0.0, X = 0.0, Y = 0.0, Z = 0.0, HeadingDeg = 0.0, Curvature = 0.0, BankDeg = 0.0, Width = 0.0;
		int32 Flags = 0;
	};

	struct FRawRoad
	{
		FString Id;
		FString Class;
		FString Surface;
		int32 LanesPerDirection = 1;
		double LaneWidth = 3.4, ShoulderWidth = 1.5, MedianWidth = 0.0, SpeedLimitKmh = 80.0, BedHalfWidth = 5.0;
		TArray<FRawSample> Samples; // 2 m spacing
	};

	struct FRawEdge
	{
		FString Id;
		int32 RoadIndex = INDEX_NONE;
		FString FromNode, ToNode;
		double S0 = 0.0, S1 = 0.0;
		FName AssetRoadId; // id used in URoamRoadNetwork
	};

	struct FRawConnection
	{
		FString Road;
		double S = 0.0;
		FString Role;
		FString Control;
	};

	struct FRawNode
	{
		FString Id;
		FVector PositionM = FVector::ZeroVector;
		TArray<FRawConnection> Connections;
	};

	struct FRoadsJson
	{
		TArray<FRawRoad> Roads;
		TArray<FRawEdge> Edges;
		TArray<FRawNode> Nodes;
		TMap<FString, int32> RoadIndexById;

		bool Load(const FString& Path, FString& OutError)
		{
			TSharedPtr<FJsonObject> Root;
			if (!LoadJsonFile(Path, Root, OutError))
			{
				return false;
			}
			const TArray<TSharedPtr<FJsonValue>>* RoadsArray = nullptr;
			const TArray<TSharedPtr<FJsonValue>>* EdgesArray = nullptr;
			const TArray<TSharedPtr<FJsonValue>>* NodesArray = nullptr;
			if (!Root->TryGetArrayField(TEXT("roads"), RoadsArray) || !Root->TryGetArrayField(TEXT("edges"), EdgesArray) || !Root->TryGetArrayField(TEXT("nodes"), NodesArray))
			{
				OutError = TEXT("roads.json: missing roads / edges / nodes");
				return false;
			}
			for (const TSharedPtr<FJsonValue>& Value : *RoadsArray)
			{
				const TSharedPtr<FJsonObject> Obj = Value->AsObject();
				FRawRoad Road;
				Road.Id = StrField(Obj, TEXT("id"));
				Road.Class = StrField(Obj, TEXT("class"));
				Road.Surface = StrField(Obj, TEXT("surface"), TEXT("asphalt"));
				Road.LanesPerDirection = FMath::Max(1, static_cast<int32>(NumField(Obj, TEXT("lanes_per_direction"), 1)));
				Road.LaneWidth = NumField(Obj, TEXT("lane_width"), 3.4);
				Road.ShoulderWidth = NumField(Obj, TEXT("shoulder_width"), 1.5);
				Road.MedianWidth = NumField(Obj, TEXT("median_width"), 0.0);
				Road.SpeedLimitKmh = NumField(Obj, TEXT("speed_limit_kmh"), 80.0);
				Road.BedHalfWidth = NumField(Obj, TEXT("bed_half_width"), 5.0);
				const TArray<TSharedPtr<FJsonValue>>* Samples = nullptr;
				if (Obj->TryGetArrayField(TEXT("samples"), Samples))
				{
					Road.Samples.Reserve(Samples->Num());
					for (const TSharedPtr<FJsonValue>& SampleValue : *Samples)
					{
						const TArray<TSharedPtr<FJsonValue>>& Row = SampleValue->AsArray();
						if (Row.Num() < 9)
						{
							continue;
						}
						FRawSample Sample;
						Sample.S = Row[0]->AsNumber();
						Sample.X = Row[1]->AsNumber();
						Sample.Y = Row[2]->AsNumber();
						Sample.Z = Row[3]->AsNumber();
						Sample.HeadingDeg = Row[4]->AsNumber();
						Sample.Curvature = Row[5]->AsNumber();
						Sample.BankDeg = Row[6]->AsNumber();
						Sample.Width = Row[7]->AsNumber();
						Sample.Flags = static_cast<int32>(Row[8]->AsNumber());
						Road.Samples.Add(Sample);
					}
				}
				RoadIndexById.Add(Road.Id, Roads.Num());
				Roads.Add(MoveTemp(Road));
			}

			TMap<FString, int32> EdgesPerRoad;
			for (const TSharedPtr<FJsonValue>& Value : *EdgesArray)
			{
				EdgesPerRoad.FindOrAdd(StrField(Value->AsObject(), TEXT("road")), 0) += 1;
			}
			for (const TSharedPtr<FJsonValue>& Value : *EdgesArray)
			{
				const TSharedPtr<FJsonObject> Obj = Value->AsObject();
				FRawEdge Edge;
				Edge.Id = StrField(Obj, TEXT("id"));
				const FString RoadId = StrField(Obj, TEXT("road"));
				Edge.RoadIndex = RoadIndexById.Contains(RoadId) ? RoadIndexById[RoadId] : INDEX_NONE;
				Edge.FromNode = StrField(Obj, TEXT("from_node"));
				Edge.ToNode = StrField(Obj, TEXT("to_node"));
				Edge.S0 = NumField(Obj, TEXT("s0"));
				Edge.S1 = NumField(Obj, TEXT("s1"));
				// single-edge roads keep the road id (DefaultSpawnRoadIds = HWY_EAST works), the others use "<road>#<k>"
				Edge.AssetRoadId = FName(*((EdgesPerRoad.FindRef(RoadId) == 1) ? RoadId : Edge.Id));
				if (Edge.RoadIndex != INDEX_NONE)
				{
					Edges.Add(MoveTemp(Edge));
				}
			}

			for (const TSharedPtr<FJsonValue>& Value : *NodesArray)
			{
				const TSharedPtr<FJsonObject> Obj = Value->AsObject();
				FRawNode Node;
				Node.Id = StrField(Obj, TEXT("id"));
				Node.PositionM = FVector(NumField(Obj, TEXT("x")), NumField(Obj, TEXT("y")), NumField(Obj, TEXT("z")));
				const TArray<TSharedPtr<FJsonValue>>* Connections = nullptr;
				if (Obj->TryGetArrayField(TEXT("connections"), Connections))
				{
					for (const TSharedPtr<FJsonValue>& ConnValue : *Connections)
					{
						const TSharedPtr<FJsonObject> ConnObj = ConnValue->AsObject();
						FRawConnection Connection;
						Connection.Road = StrField(ConnObj, TEXT("road"));
						Connection.S = NumField(ConnObj, TEXT("s"));
						Connection.Role = StrField(ConnObj, TEXT("role"));
						Connection.Control = StrField(ConnObj, TEXT("control"), TEXT("free"));
						Node.Connections.Add(Connection);
					}
				}
				Nodes.Add(MoveTemp(Node));
			}
			return true;
		}

		/** Interpolated sample at arc length S (clamped). */
		static FRawSample Eval(const FRawRoad& Road, double S)
		{
			FRawSample Out;
			if (Road.Samples.Num() == 0)
			{
				return Out;
			}
			if (Road.Samples.Num() == 1 || S <= Road.Samples[0].S)
			{
				return Road.Samples[0];
			}
			if (S >= Road.Samples.Last().S)
			{
				return Road.Samples.Last();
			}
			// samples are ~2 m apart: guess the index, then fix up
			int32 Index = FMath::Clamp(static_cast<int32>((S - Road.Samples[0].S) / 2.0), 0, Road.Samples.Num() - 2);
			while (Index > 0 && Road.Samples[Index].S > S)
			{
				--Index;
			}
			while (Index < Road.Samples.Num() - 2 && Road.Samples[Index + 1].S < S)
			{
				++Index;
			}
			const FRawSample& A = Road.Samples[Index];
			const FRawSample& B = Road.Samples[Index + 1];
			const double Span = FMath::Max(B.S - A.S, 1e-6);
			const double T = FMath::Clamp((S - A.S) / Span, 0.0, 1.0);
			Out.S = S;
			Out.X = FMath::Lerp(A.X, B.X, T);
			Out.Y = FMath::Lerp(A.Y, B.Y, T);
			Out.Z = FMath::Lerp(A.Z, B.Z, T);
			Out.Curvature = FMath::Lerp(A.Curvature, B.Curvature, T);
			Out.BankDeg = FMath::Lerp(A.BankDeg, B.BankDeg, T);
			Out.Width = FMath::Lerp(A.Width, B.Width, T);
			const double DeltaHeading = FMath::FindDeltaAngleDegrees(A.HeadingDeg, B.HeadingDeg);
			Out.HeadingDeg = FMath::Fmod(A.HeadingDeg + DeltaHeading * T + 720.0, 360.0);
			Out.Flags = (T < 0.5) ? A.Flags : B.Flags;
			return Out;
		}
	};

	ERoamRoadClass ParseRoadClass(const FString& Name)
	{
		if (Name == TEXT("HIGHWAY")) return ERoamRoadClass::Highway;
		if (Name == TEXT("MOUNTAIN")) return ERoamRoadClass::Mountain;
		if (Name == TEXT("DIRT")) return ERoamRoadClass::Dirt;
		if (Name == TEXT("SHORTCUT")) return ERoamRoadClass::Shortcut;
		if (Name == TEXT("VILLAGE")) return ERoamRoadClass::Village;
		return ERoamRoadClass::Regional;
	}

	ERoamSurface ParseSurface(const FString& Name)
	{
		if (Name == TEXT("gravel")) return ERoamSurface::Gravel;
		if (Name == TEXT("dirt")) return ERoamSurface::Dirt;
		if (Name == TEXT("concrete")) return ERoamSurface::Concrete;
		return ERoamSurface::Asphalt;
	}

	/** data flag bits -> ERoamRoadSection bits (BRIDGE 1, TUNNEL 2, CULVERT 4, JUNCTION 8, HAIRPIN 16, PORTAL 32). */
	uint8 MapFlags(int32 DataFlags, ERoamRoadClass Class)
	{
		uint8 Out = 0;
		if (DataFlags & 1) Out |= static_cast<uint8>(ERoamRoadSection::Bridge) | static_cast<uint8>(ERoamRoadSection::Guardrail);
		if (DataFlags & 2) Out |= static_cast<uint8>(ERoamRoadSection::Tunnel);
		if (DataFlags & 8) Out |= static_cast<uint8>(ERoamRoadSection::Junction);
		if ((DataFlags & 16) && Class == ERoamRoadClass::Mountain) Out |= static_cast<uint8>(ERoamRoadSection::Guardrail);
		return Out;
	}

	FString MakeSlug(const FString& Name)
	{
		FString Out;
		for (const TCHAR Char : Name)
		{
			if (FChar::IsAlnum(Char))
			{
				Out.AppendChar(FChar::ToLower(Char));
			}
			else if (!Out.IsEmpty() && !Out.EndsWith(TEXT("_")))
			{
				Out.AppendChar(TEXT('_'));
			}
		}
		Out.RemoveFromEnd(TEXT("_"));
		return Out;
	}
} // namespace

// ----------------------------------------------------------------------------------------------------------------------------
// status
// ----------------------------------------------------------------------------------------------------------------------------

FString URoamWorldBuilder::GetWorldBuilderStatus()
{
	return TEXT("RoamWorldBuilder OK");
}

// ----------------------------------------------------------------------------------------------------------------------------
// layer infos
// ----------------------------------------------------------------------------------------------------------------------------

ULandscapeLayerInfoObject* URoamWorldBuilder::CreateOrLoadLayerInfo(FName LayerName, const FString& PackageFolder, const FString& AssetName, UPhysicalMaterial* PhysicalMaterial, bool bWeightBlended)
{
	const FString PackagePath = PackageFolder.EndsWith(TEXT("/")) ? PackageFolder + AssetName : PackageFolder + TEXT("/") + AssetName;
	const FString ObjectPath = PackagePath + TEXT(".") + AssetName;
	ULandscapeLayerInfoObject* LayerInfo = LoadObject<ULandscapeLayerInfoObject>(nullptr, *ObjectPath, nullptr, LOAD_NoWarn | LOAD_Quiet);
	if (!LayerInfo)
	{
		LayerInfo = UE::Landscape::CreateTargetLayerInfo(LayerName, PackageFolder, AssetName);
	}
	if (!LayerInfo)
	{
		UE_LOG(LogRoam, Error, TEXT("ROAM_WORLD CreateOrLoadLayerInfo failed for %s"), *PackagePath);
		return nullptr;
	}
	LayerInfo->SetLayerName(LayerName, true);
	LayerInfo->SetBlendMethod(bWeightBlended ? ELandscapeTargetLayerBlendMethod::FinalWeightBlending : ELandscapeTargetLayerBlendMethod::None, true);
	if (PhysicalMaterial)
	{
		LayerInfo->SetPhysicalMaterial(PhysicalMaterial, true);
	}
	LayerInfo->MarkPackageDirty();
	return LayerInfo;
}

bool URoamWorldBuilder::SetLayerInfoPhysicalMaterial(ULandscapeLayerInfoObject* LayerInfo, UPhysicalMaterial* PhysicalMaterial)
{
	if (!LayerInfo)
	{
		return false;
	}
	LayerInfo->SetPhysicalMaterial(PhysicalMaterial, true);
	LayerInfo->MarkPackageDirty();
	return true;
}

int32 URoamWorldBuilder::AssignLayerPhysicalMaterials(ALandscape* Landscape, const TArray<FName>& LayerNames, const TArray<UPhysicalMaterial*>& PhysicalMaterials)
{
	if (!Landscape || LayerNames.Num() != PhysicalMaterials.Num())
	{
		return 0;
	}
	ULandscapeInfo* Info = Landscape->GetLandscapeInfo();
	if (!Info)
	{
		return 0;
	}
	int32 Changed = 0;
	for (int32 Index = 0; Index < LayerNames.Num(); ++Index)
	{
		const int32 LayerIndex = Info->GetLayerInfoIndex(LayerNames[Index]);
		if (LayerIndex != INDEX_NONE && Info->Layers[LayerIndex].LayerInfoObj)
		{
			Info->Layers[LayerIndex].LayerInfoObj->SetPhysicalMaterial(PhysicalMaterials[Index], true);
			Info->Layers[LayerIndex].LayerInfoObj->MarkPackageDirty();
			++Changed;
		}
	}
	return Changed;
}

// ----------------------------------------------------------------------------------------------------------------------------
// landscape
// ----------------------------------------------------------------------------------------------------------------------------

FRoamLandscapeBuildResult URoamWorldBuilder::CreateLandscapeFromHeightmap(UWorld* World, const FRoamLandscapeBuildParams& P)
{
	FRoamLandscapeBuildResult Result;
	const double T0 = NowSeconds();
	auto Fail = [&Result](const FString& Message) -> FRoamLandscapeBuildResult
	{
		Result.bSuccess = false;
		Result.Report = Message;
		UE_LOG(LogRoam, Error, TEXT("ROAM_LANDSCAPE_FAIL %s"), *Message);
		return Result;
	};

	if (!World)
	{
		return Fail(TEXT("World is null"));
	}
	const int32 QuadsPerComponent = P.QuadsPerSection * P.SectionsPerComponent;
	const int32 Src = P.SourceSize;
	const int32 CropN = P.CropSize > 0 ? P.CropSize : Src;
	if (P.QuadsPerSection <= 0 || P.SectionsPerComponent < 1 || P.SectionsPerComponent > 2)
	{
		return Fail(TEXT("invalid section layout (QuadsPerSection 7/15/31/63/127/255, SectionsPerComponent 1 or 2)"));
	}
	if (P.CropX < 0 || P.CropY < 0 || P.CropX + CropN > Src || P.CropY + CropN > Src || CropN < 3)
	{
		return Fail(FString::Printf(TEXT("crop window (%d,%d) size %d does not fit the %d source"), P.CropX, P.CropY, CropN, Src));
	}
	if (P.LayerNames.Num() != P.LayerFiles.Num() || P.LayerNames.Num() != P.LayerInfos.Num())
	{
		return Fail(TEXT("LayerNames / LayerFiles / LayerInfos must have the same length"));
	}
	for (int32 LayerIndex = 0; LayerIndex < P.LayerInfos.Num(); ++LayerIndex)
	{
		if (!P.LayerInfos[LayerIndex])
		{
			return Fail(FString::Printf(TEXT("LayerInfos[%d] (%s) is null"), LayerIndex, *P.LayerNames[LayerIndex].ToString()));
		}
	}

	const int32 Components = FMath::DivideAndRoundUp(CropN - 1, QuadsPerComponent);
	const int32 Verts = Components * QuadsPerComponent + 1;
	const int32 PadTotal = Verts - CropN;
	const int32 PadLow = PadTotal / 2;
	const int32 PadHigh = PadTotal - PadLow;
	const int64 Count = static_cast<int64>(Verts) * Verts;

	// ---- read the heightmap --------------------------------------------------------------------------------------------
	TArray<uint8> RawHeights;
	if (!FFileHelper::LoadFileToArray(RawHeights, *P.HeightmapFile))
	{
		return Fail(FString::Printf(TEXT("cannot read heightmap '%s'"), *P.HeightmapFile));
	}
	if (RawHeights.Num() != static_cast<int64>(Src) * Src * 2)
	{
		return Fail(FString::Printf(TEXT("heightmap size %d bytes, expected %lld"), RawHeights.Num(), static_cast<int64>(Src) * Src * 2));
	}
	const uint16* SrcHeights = reinterpret_cast<const uint16*>(RawHeights.GetData());

	auto SourceIndex = [&](int32 LandscapeIndex, int32 Crop) -> int32
	{
		return FMath::Clamp(Crop + LandscapeIndex - PadLow, Crop, Crop + CropN - 1);
	};

	TArray<uint16> Heights;
	Heights.SetNumUninitialized(Count);
	ParallelFor(Verts, [&](int32 Row)
	{
		const int32 SrcRow = SourceIndex(Row, P.CropY);
		const uint16* SrcLine = SrcHeights + static_cast<int64>(SrcRow) * Src;
		uint16* Dest = Heights.GetData() + static_cast<int64>(Row) * Verts;
		for (int32 Column = 0; Column < Verts; ++Column)
		{
			Dest[Column] = SrcLine[SourceIndex(Column, P.CropX)];
		}
	});
	RawHeights.Empty();

	// ---- read the weight maps ------------------------------------------------------------------------------------------
	TArray<FLandscapeImportLayerInfo> ImportLayers;
	for (int32 LayerIndex = 0; LayerIndex < P.LayerNames.Num(); ++LayerIndex)
	{
		TArray<uint8> RawLayer;
		if (!FFileHelper::LoadFileToArray(RawLayer, *P.LayerFiles[LayerIndex]))
		{
			return Fail(FString::Printf(TEXT("cannot read weight map '%s'"), *P.LayerFiles[LayerIndex]));
		}
		if (RawLayer.Num() != static_cast<int64>(Src) * Src)
		{
			return Fail(FString::Printf(TEXT("weight map '%s' has %d bytes, expected %lld"), *P.LayerFiles[LayerIndex], RawLayer.Num(), static_cast<int64>(Src) * Src));
		}
		FLandscapeImportLayerInfo Layer(P.LayerNames[LayerIndex]);
		Layer.LayerInfo = P.LayerInfos[LayerIndex];
		Layer.SourceFilePath = P.LayerFiles[LayerIndex];
		Layer.LayerData.SetNumUninitialized(Count);
		ParallelFor(Verts, [&](int32 Row)
		{
			const int32 SrcRow = SourceIndex(Row, P.CropY);
			const uint8* SrcLine = RawLayer.GetData() + static_cast<int64>(SrcRow) * Src;
			uint8* Dest = Layer.LayerData.GetData() + static_cast<int64>(Row) * Verts;
			for (int32 Column = 0; Column < Verts; ++Column)
			{
				Dest[Column] = SrcLine[SourceIndex(Column, P.CropX)];
			}
		});
		ImportLayers.Add(MoveTemp(Layer));
	}

	// ---- landscape holes: weight 255 on the visibility layer at the requested source vertices -----------------------------
	int32 NumHoleVertices = 0;
	if (P.HoleVertices.Num() > 0)
	{
		if (!ALandscapeProxy::VisibilityLayer)
		{
			return Fail(TEXT("ALandscapeProxy::VisibilityLayer is null (landscape holes cannot be written)"));
		}
		FLandscapeImportLayerInfo Hole(ALandscapeProxy::VisibilityLayer->GetLayerName());
		Hole.LayerInfo = ALandscapeProxy::VisibilityLayer;
		Hole.LayerData.SetNumZeroed(Count);
		for (const FIntPoint& V : P.HoleVertices)
		{
			const int32 Column = V.X - P.CropX + PadLow;
			const int32 Row = V.Y - P.CropY + PadLow;
			if (Column >= 0 && Column < Verts && Row >= 0 && Row < Verts && V.X >= P.CropX && V.X < P.CropX + CropN && V.Y >= P.CropY && V.Y < P.CropY + CropN)
			{
				uint8& Cell = Hole.LayerData[static_cast<int64>(Row) * Verts + Column];
				if (Cell == 0)
				{
					Cell = 255;
					++NumHoleVertices;
				}
			}
		}
		if (NumHoleVertices > 0)
		{
			ImportLayers.Add(MoveTemp(Hole));
		}
	}
	Result.NumHoleVertices = NumHoleVertices;
	Result.ReadSeconds = static_cast<float>(NowSeconds() - T0);

	// ---- placement -----------------------------------------------------------------------------------------------------
	// Landscape vertex (i, j) shows source vertex (Crop + i - PadLow); the source centre vertex ((Src-1)/2) must sit at SourceCentreCm.
	const double SourceCentre = 0.5 * (Src - 1);
	const FVector Location(
		P.SourceCentreCm.X + (P.CropX - PadLow - SourceCentre) * P.Scale.X,
		P.SourceCentreCm.Y + (P.CropY - PadLow - SourceCentre) * P.Scale.Y,
		P.SourceCentreCm.Z);

	ULandscapeSubsystem* LandscapeSubsystem = World->GetSubsystem<ULandscapeSubsystem>();
	const bool bPartitioned = LandscapeSubsystem && LandscapeSubsystem->IsGridBased();

	ALandscape* Landscape = World->SpawnActor<ALandscape>(Location, FRotator::ZeroRotator);
	if (!Landscape)
	{
		return Fail(TEXT("SpawnActor<ALandscape> failed"));
	}
	Landscape->SetActorRelativeScale3D(P.Scale); // before Import: normals use the scale
	Landscape->LandscapeMaterial = P.Material;
	Landscape->DefaultPhysMaterial = P.DefaultPhysicalMaterial;
	Landscape->bAreNewLandscapeActorsSpatiallyLoaded = !P.bProxiesAlwaysLoaded;
	Landscape->BodyInstance.SetCollisionProfileName(P.CollisionProfile);
	Landscape->StaticLightingLOD = FMath::DivideAndRoundUp(FMath::CeilLogTwo(static_cast<uint32>((static_cast<int64>(Verts) * Verts) / (2048 * 2048) + 1)), 2u);

	TMap<FGuid, TArray<uint16>> HeightPerLayer;
	HeightPerLayer.Add(FGuid(), MoveTemp(Heights));
	TMap<FGuid, TArray<FLandscapeImportLayerInfo>> LayerDataPerLayer;
	LayerDataPerLayer.Add(FGuid(), MoveTemp(ImportLayers));

	UE_LOG(LogRoam, Display, TEXT("ROAM_LANDSCAPE_IMPORT_BEGIN verts=%d components=%dx%d pad=%d/%d layers=%d partitioned=%d location=%s"),
		Verts, Components, Components, PadLow, PadHigh, P.LayerNames.Num(), bPartitioned ? 1 : 0, *Location.ToString());
	const double T1 = NowSeconds();
	Landscape->Import(FGuid::NewGuid(), 0, 0, Verts - 1, Verts - 1, P.SectionsPerComponent, P.QuadsPerSection, HeightPerLayer,
		TEXT(""), LayerDataPerLayer, ELandscapeImportAlphamapType::Additive, TArrayView<const FLandscapeLayer>());
	HeightPerLayer.Empty();
	LayerDataPerLayer.Empty();

	ULandscapeInfo* Info = Landscape->GetLandscapeInfo();
	if (!Info)
	{
		return Fail(TEXT("landscape info missing after Import"));
	}
	Landscape->SetActorLabel(P.ActorLabel);
	Info->UpdateLayerInfoMap(Landscape);
	for (int32 LayerIndex = 0; LayerIndex < P.LayerNames.Num(); ++LayerIndex)
	{
		ULandscapeLayerInfoObject* LayerInfo = P.LayerInfos[LayerIndex];
		Landscape->AddTargetLayer(LayerInfo->GetLayerName(), FLandscapeTargetLayerSettings(LayerInfo, P.LayerFiles[LayerIndex]));
		const int32 InfoIndex = Info->GetLayerInfoIndex(P.LayerNames[LayerIndex]);
		if (InfoIndex != INDEX_NONE)
		{
			Info->Layers[InfoIndex].LayerInfoObj = LayerInfo;
		}
	}
	if (NumHoleVertices > 0)
	{
		ULandscapeLayerInfoObject* VisibilityInfo = ALandscapeProxy::VisibilityLayer;
		const FName VisibilityName = VisibilityInfo->GetLayerName();
		if (!Landscape->HasTargetLayer(VisibilityName))
		{
			Landscape->AddTargetLayer(VisibilityName, FLandscapeTargetLayerSettings(VisibilityInfo));
		}
		const int32 InfoIndex = Info->GetLayerInfoIndex(VisibilityName);
		if (InfoIndex != INDEX_NONE)
		{
			Info->Layers[InfoIndex].LayerInfoObj = VisibilityInfo;
		}
		UE_LOG(LogRoam, Display, TEXT("ROAM_LANDSCAPE_HOLES %d visibility-layer vertices written (layer '%s')"), NumHoleVertices, *VisibilityName.ToString());
	}

	if (bPartitioned && P.WorldPartitionGridComponents > 0)
	{
		LandscapeSubsystem->ChangeGridSize(Info, static_cast<uint32>(P.WorldPartitionGridComponents));
	}
	Result.ImportSeconds = static_cast<float>(NowSeconds() - T1);

	// ---- per proxy settings ---------------------------------------------------------------------------------------------
	int32 NumProxies = 0;
	Info->ForEachLandscapeProxy([&](ALandscapeProxy* Proxy) -> bool
	{
		++NumProxies;
		Proxy->BodyInstance.SetCollisionProfileName(P.CollisionProfile);
		Proxy->DefaultPhysMaterial = P.DefaultPhysicalMaterial;
		if (P.Material)
		{
			Proxy->LandscapeMaterial = P.Material;
		}
		return true;
	});
	Result.NumProxies = NumProxies;

	if (P.bEnableNanite)
	{
		SetLandscapeNanite(Landscape, true);
	}

	Landscape->MarkPackageDirty();
	Result.bSuccess = true;
	Result.Landscape = Landscape;
	Result.LandscapeVerts = Verts;
	Result.ComponentsPerSide = Components;
	Result.PadLow = PadLow;
	Result.PadHigh = PadHigh;
	Result.ActorLocationCm = Location;
	Result.Report = FString::Printf(TEXT("landscape %dx%d verts (%d x %d components of %d quads), padding %d/%d, %d actor(s), location %s, read %.1fs import %.1fs"),
		Verts, Verts, Components, Components, QuadsPerComponent, PadLow, PadHigh, NumProxies, *Location.ToString(), Result.ReadSeconds, Result.ImportSeconds);
	UE_LOG(LogRoam, Display, TEXT("ROAM_LANDSCAPE_CREATED %s"), *Result.Report);
	return Result;
}

bool URoamWorldBuilder::SetLandscapeNanite(ALandscape* Landscape, bool bEnable)
{
	if (!Landscape)
	{
		return false;
	}
	ULandscapeInfo* Info = Landscape->GetLandscapeInfo();
	Landscape->Modify();
	// bEnableNanite is protected: go through reflection (the editor does the same through the details panel)
	FBoolProperty* Property = FindFProperty<FBoolProperty>(ALandscapeProxy::StaticClass(), TEXT("bEnableNanite"));
	if (!Property)
	{
		return false;
	}
	Property->SetPropertyValue_InContainer(Landscape, bEnable);
	{
		FPropertyChangedEvent Event(Property);
		Landscape->PostEditChangeProperty(Event); // propagates the shared property to the streaming proxies
	}
	if (Info)
	{
		Info->ForEachLandscapeProxy([Property, bEnable](ALandscapeProxy* Proxy) -> bool
		{
			if (Property->GetPropertyValue_InContainer(Proxy) != bEnable)
			{
				Property->SetPropertyValue_InContainer(Proxy, bEnable);
				FPropertyChangedEvent Event(Property);
				Proxy->PostEditChangeProperty(Event);
			}
			return true;
		});
	}
	if (bEnable)
	{
		// Neighbouring proxies are separate Nanite meshes: a skirt hides the cracks between them. Depth is in local Z units (x ZScale).
		Landscape->EnableNaniteSkirts(true, 0.5f, true);
	}
	return true;
}

bool URoamWorldBuilder::SetLandscapeMaterial(ALandscape* Landscape, UMaterialInterface* Material)
{
	if (!Landscape)
	{
		return false;
	}
	Landscape->Modify();
	Landscape->LandscapeMaterial = Material;
	if (ULandscapeInfo* Info = Landscape->GetLandscapeInfo())
	{
		Info->ForEachLandscapeProxy([Material](ALandscapeProxy* Proxy) -> bool
		{
			Proxy->LandscapeMaterial = Material;
			Proxy->UpdateAllComponentMaterialInstances();
			return true;
		});
	}
	return true;
}

FString URoamWorldBuilder::BuildLandscapeData(UWorld* World, bool bBuildGrassMaps, bool bBuildPhysicalMaterial, bool bBuildNanite)
{
	ULandscapeSubsystem* Subsystem = World ? World->GetSubsystem<ULandscapeSubsystem>() : nullptr;
	if (!Subsystem)
	{
		return TEXT("ERROR: no landscape subsystem");
	}
	const UE::Landscape::EBuildFlags Flags = UE::Landscape::EBuildFlags::ForceRebuild | UE::Landscape::EBuildFlags::WriteFinalLog;
	const double T0 = NowSeconds();
	double TGrass = 0.0, TPhys = 0.0, TNanite = 0.0;
	Subsystem->MarkModifiedLandscapesAsDirty(Flags);
	if (bBuildGrassMaps)
	{
		const double T = NowSeconds();
		Subsystem->BuildGrassMaps(Flags);
		TGrass = NowSeconds() - T;
	}
	if (bBuildPhysicalMaterial)
	{
		const double T = NowSeconds();
		Subsystem->BuildPhysicalMaterial(Flags);
		TPhys = NowSeconds() - T;
	}
	if (bBuildNanite)
	{
		const double T = NowSeconds();
		Subsystem->BuildNanite(Flags);
		TNanite = NowSeconds() - T;
	}
	const FString Summary = FString::Printf(TEXT("built landscape data in %.1fs (grass %.1fs, physical material %.1fs, nanite %.1fs)"), NowSeconds() - T0, TGrass, TPhys, TNanite);
	UE_LOG(LogRoam, Display, TEXT("ROAM_LANDSCAPE_BUILD %s"), *Summary);
	return Summary;
}

FString URoamWorldBuilder::DescribeLandscape(UWorld* World)
{
	if (!World)
	{
		return TEXT("no world");
	}
	int32 Proxies = 0, Components = 0, NaniteEnabled = 0, NaniteUpToDate = 0, SpatiallyLoaded = 0;
	FString Layers;
	for (TActorIterator<ALandscapeProxy> It(World); It; ++It)
	{
		ALandscapeProxy* Proxy = *It;
		++Proxies;
		Components += Proxy->LandscapeComponents.Num();
		NaniteEnabled += Proxy->IsNaniteEnabled() ? 1 : 0;
		NaniteUpToDate += (Proxy->IsNaniteEnabled() && Proxy->IsNaniteMeshUpToDate()) ? 1 : 0;
		SpatiallyLoaded += Proxy->GetIsSpatiallyLoaded() ? 1 : 0;
		if (Layers.IsEmpty())
		{
			if (ULandscapeInfo* Info = Proxy->GetLandscapeInfo())
			{
				for (const FLandscapeInfoLayerSettings& Layer : Info->Layers)
				{
					Layers += FString::Printf(TEXT("%s%s"), Layers.IsEmpty() ? TEXT("") : TEXT(","), *Layer.GetLayerName().ToString());
				}
			}
		}
	}
	return FString::Printf(TEXT("proxies=%d components=%d nanite_enabled=%d nanite_up_to_date=%d spatially_loaded=%d layers=[%s]"),
		Proxies, Components, NaniteEnabled, NaniteUpToDate, SpatiallyLoaded, *Layers);
}

FRoamLandscapeSample URoamWorldBuilder::SampleLandscape(UWorld* World, double WorldXCm, double WorldYCm)
{
	FRoamLandscapeSample Sample;
	if (!World)
	{
		return Sample;
	}
	for (TActorIterator<ALandscapeProxy> It(World); It; ++It)
	{
		const TOptional<float> Height = It->GetHeightAtLocation(FVector(WorldXCm, WorldYCm, 0.0));
		if (Height.IsSet())
		{
			Sample.bValid = true;
			Sample.HeightCm = Height.GetValue();
			return Sample;
		}
	}
	return Sample;
}

// ----------------------------------------------------------------------------------------------------------------------------
// world partition
// ----------------------------------------------------------------------------------------------------------------------------

FString URoamWorldBuilder::ConfigureWorldPartition(UWorld* World, int32 CellSizeCm, int32 LoadingRangeCm, bool bEnableStreaming)
{
	UWorldPartition* WorldPartition = World ? World->GetWorldPartition() : nullptr;
	if (!WorldPartition)
	{
		return TEXT("ERROR: the world is not a World Partition world");
	}
	WorldPartition->SetEnableStreaming(bEnableStreaming);

	UWorldPartitionRuntimeHashSet* Hash = Cast<UWorldPartitionRuntimeHashSet>(WorldPartition->RuntimeHash);
	if (!Hash)
	{
		return FString::Printf(TEXT("ERROR: runtime hash is %s, not a WorldPartitionRuntimeHashSet"), WorldPartition->RuntimeHash ? *WorldPartition->RuntimeHash->GetClass()->GetName() : TEXT("null"));
	}
	FArrayProperty* PartitionsProperty = CastField<FArrayProperty>(UWorldPartitionRuntimeHashSet::StaticClass()->FindPropertyByName(TEXT("RuntimePartitions")));
	if (!PartitionsProperty)
	{
		return TEXT("ERROR: RuntimePartitions property not found");
	}
	FStructProperty* DescProperty = CastField<FStructProperty>(PartitionsProperty->Inner);
	FObjectProperty* MainLayerProperty = DescProperty ? CastField<FObjectProperty>(DescProperty->Struct->FindPropertyByName(TEXT("MainLayer"))) : nullptr;
	if (!DescProperty || !MainLayerProperty)
	{
		return TEXT("ERROR: FRuntimePartitionDesc.MainLayer not found");
	}

	FString Summary;
	Hash->Modify();
	FScriptArrayHelper Helper(PartitionsProperty, PartitionsProperty->ContainerPtrToValuePtr<void>(Hash));
	for (int32 Index = 0; Index < Helper.Num(); ++Index)
	{
		const void* DescMemory = Helper.GetRawPtr(Index);
		URuntimePartition* Main = Cast<URuntimePartition>(MainLayerProperty->GetObjectPropertyValue_InContainer(DescMemory));
		if (!Main)
		{
			continue;
		}
		Main->Modify();
		Main->LoadingRange = LoadingRangeCm;
		if (URuntimePartitionLHGrid* Grid = Cast<URuntimePartitionLHGrid>(Main))
		{
			if (FNumericProperty* CellProperty = CastField<FNumericProperty>(URuntimePartitionLHGrid::StaticClass()->FindPropertyByName(TEXT("CellSize"))))
			{
				CellProperty->SetIntPropertyValue(CellProperty->ContainerPtrToValuePtr<void>(Grid), static_cast<int64>(CellSizeCm));
			}
			Summary += FString::Printf(TEXT("[%s: LH grid cell %d cm range %d cm] "), *Main->Name.ToString(), CellSizeCm, LoadingRangeCm);
		}
		else
		{
			Summary += FString::Printf(TEXT("[%s: %s range %d cm] "), *Main->Name.ToString(), *Main->GetClass()->GetName(), LoadingRangeCm);
		}
	}
	World->MarkPackageDirty();
	const FString Out = FString::Printf(TEXT("world partition: streaming=%d partitions=%d %s"), bEnableStreaming ? 1 : 0, Helper.Num(), *Summary);
	UE_LOG(LogRoam, Display, TEXT("ROAM_WP_CONFIG %s"), *Out);
	return Out;
}

// ----------------------------------------------------------------------------------------------------------------------------
// data assets
// ----------------------------------------------------------------------------------------------------------------------------

bool URoamWorldBuilder::SaveAssetByObject(UObject* Asset)
{
	return SavePackageOf(Asset);
}

URoamRoadNetwork* URoamWorldBuilder::CreateRoadNetworkAsset(const FString& RoadsJsonPath, const FString& AssetPath, FString& OutReport)
{
	FString Error;
	FRoadsJson Data;
	if (!Data.Load(RoadsJsonPath, Error))
	{
		OutReport = TEXT("ERROR: ") + Error;
		return nullptr;
	}

	bool bCreated = false;
	URoamRoadNetwork* Network = FindOrCreateAsset<URoamRoadNetwork>(AssetPath, bCreated);
	if (!Network)
	{
		OutReport = TEXT("ERROR: cannot create asset ") + AssetPath;
		return nullptr;
	}
	Network->Modify();
	Network->Roads.Reset();
	Network->Junctions.Reset();
	Network->bRightHandTraffic = true;
	Network->GridCellSizeCm = 20000.0f;

	constexpr double SampleSpacingM = 4.0; // data is 2 m; the contract says ~5 m, 4 m keeps curves and flag boundaries sharp
	int32 TotalSamples = 0;
	double TotalLengthM = 0.0;

	for (const FRawEdge& Edge : Data.Edges)
	{
		const FRawRoad& Road = Data.Roads[Edge.RoadIndex];
		FRoamRoad Out;
		Out.RoadId = Edge.AssetRoadId;
		Out.RoadClass = ParseRoadClass(Road.Class);
		Out.Surface = ParseSurface(Road.Surface);
		Out.SpeedLimitKmh = static_cast<float>(Road.SpeedLimitKmh);
		Out.LanesForward = Road.LanesPerDirection;
		Out.LanesBackward = Road.LanesPerDirection;
		Out.LaneWidthCm = static_cast<float>(Road.LaneWidth * 100.0);
		Out.bOneWay = false;
		Out.StartJunction = FName(*Edge.FromNode);
		Out.EndJunction = FName(*Edge.ToNode);

		// station list: exact start, every SampleSpacingM, exact end
		TArray<double> Stations;
		for (double S = Edge.S0; S < Edge.S1 - 0.75 * SampleSpacingM; S += SampleSpacingM)
		{
			Stations.Add(S);
		}
		Stations.Add(Edge.S1);
		Out.Samples.Reserve(Stations.Num());
		for (const double S : Stations)
		{
			const FRawSample Raw = FRoadsJson::Eval(Road, S);
			FRoamRoadSample Sample;
			Sample.Position = FVector(Raw.X, Raw.Y, Raw.Z) * 100.0;
			Sample.BankDeg = static_cast<float>(Raw.BankDeg);
			Sample.WidthCm = static_cast<float>(Raw.Width * 100.0);
			Sample.Flags = MapFlags(Raw.Flags, Out.RoadClass);
			Sample.S = static_cast<float>((S - Edge.S0) * 100.0);
			Out.Samples.Add(Sample);
		}
		// tangents from neighbouring samples (BuildSpatialIndex recomputes them, this keeps the asset sane before that)
		for (int32 Index = 0; Index < Out.Samples.Num(); ++Index)
		{
			const FVector& Prev = Out.Samples[FMath::Max(Index - 1, 0)].Position;
			const FVector& Next = Out.Samples[FMath::Min(Index + 1, Out.Samples.Num() - 1)].Position;
			Out.Samples[Index].Tangent = (Next - Prev).GetSafeNormal();
		}
		TotalSamples += Out.Samples.Num();
		TotalLengthM += Edge.S1 - Edge.S0;
		Network->Roads.Add(MoveTemp(Out));
	}

	// ---- junctions -------------------------------------------------------------------------------------------------------
	for (const FRawNode& Node : Data.Nodes)
	{
		FRoamJunction Junction;
		Junction.JunctionId = FName(*Node.Id);
		Junction.Position = Node.PositionM * 100.0;
		double MaxBedHalfWidth = 0.0;
		bool bAnyStop = false, bAnyYield = false;
		for (const FRawConnection& Connection : Node.Connections)
		{
			const int32* RoadIndex = Data.RoadIndexById.Find(Connection.Road);
			if (RoadIndex)
			{
				MaxBedHalfWidth = FMath::Max(MaxBedHalfWidth, Data.Roads[*RoadIndex].BedHalfWidth);
			}
			bAnyStop |= Connection.Control == TEXT("stop");
			bAnyYield |= Connection.Control == TEXT("yield");

			int32 ArmPriority = 1;
			if (Connection.Control == TEXT("priority")) ArmPriority = 2;
			else if (Connection.Control == TEXT("stop")) ArmPriority = 0;

			// edges of this road that touch the node at this connection's arc length
			for (const FRawEdge& Edge : Data.Edges)
			{
				if (Data.Roads[Edge.RoadIndex].Id != Connection.Road)
				{
					continue;
				}
				if (Edge.FromNode == Node.Id && FMath::Abs(Edge.S0 - Connection.S) < 1.0)
				{
					FRoamJunctionArm Arm;
					Arm.RoadId = Edge.AssetRoadId;
					Arm.bAtRoadStart = true;
					Arm.Priority = ArmPriority;
					Junction.Arms.Add(Arm);
				}
				if (Edge.ToNode == Node.Id && FMath::Abs(Edge.S1 - Connection.S) < 1.0)
				{
					FRoamJunctionArm Arm;
					Arm.RoadId = Edge.AssetRoadId;
					Arm.bAtRoadStart = false;
					Arm.Priority = ArmPriority;
					Junction.Arms.Add(Arm);
				}
			}
		}
		Junction.RadiusCm = static_cast<float>(FMath::Max(1500.0, MaxBedHalfWidth * 160.0));
		Junction.Control = bAnyStop ? ERoamJunctionControl::Stop : (bAnyYield ? ERoamJunctionControl::GiveWay : ERoamJunctionControl::None);
		Network->Junctions.Add(MoveTemp(Junction));
	}

	Network->BuildSpatialIndex();
	TArray<FString> Problems;
	const bool bValid = Network->Validate(Problems);
	Network->MarkPackageDirty();
	const bool bSaved = SavePackageOf(Network);

	OutReport = FString::Printf(TEXT("road network %s: %d roads (edges), %d junctions, %d samples, %.2f km, %.0f cm total (index), valid=%d saved=%d %s"),
		*AssetPath, Network->Roads.Num(), Network->Junctions.Num(), TotalSamples, TotalLengthM / 1000.0, Network->GetTotalLengthCm(), bValid ? 1 : 0, bSaved ? 1 : 0, bCreated ? TEXT("(new)") : TEXT("(overwritten)"));
	for (const FString& Problem : Problems)
	{
		OutReport += TEXT("\n  PROBLEM: ") + Problem;
	}
	UE_LOG(LogRoam, Display, TEXT("ROAM_ROADNET %s"), *OutReport);
	return Network;
}

URoamWorldDefinition* URoamWorldBuilder::CreateWorldDefinitionAsset(const FString& WorldMetaJsonPath, const FString& RoadsJsonPath, const FString& RegionsJsonPath, const FString& AssetPath, FString& OutReport)
{
	FString Error;
	TSharedPtr<FJsonObject> Meta, Regions;
	FRoadsJson Roads;
	if (!LoadJsonFile(WorldMetaJsonPath, Meta, Error) || !LoadJsonFile(RegionsJsonPath, Regions, Error) || !Roads.Load(RoadsJsonPath, Error))
	{
		OutReport = TEXT("ERROR: ") + Error;
		return nullptr;
	}

	bool bCreated = false;
	URoamWorldDefinition* Definition = FindOrCreateAsset<URoamWorldDefinition>(AssetPath, bCreated);
	if (!Definition)
	{
		OutReport = TEXT("ERROR: cannot create asset ") + AssetPath;
		return nullptr;
	}
	Definition->Modify();
	Definition->Regions.Reset();
	Definition->Pois.Reset();
	Definition->Activities.Reset();

	// ---- map extent ----------------------------------------------------------------------------------------------------
	if (const TSharedPtr<FJsonObject>* MapObject; Regions->TryGetObjectField(TEXT("map"), MapObject))
	{
		const TArray<TSharedPtr<FJsonValue>>* Min = nullptr;
		const TArray<TSharedPtr<FJsonValue>>* Max = nullptr;
		if ((*MapObject)->TryGetArrayField(TEXT("min_m"), Min) && (*MapObject)->TryGetArrayField(TEXT("max_m"), Max) && Min->Num() >= 2 && Max->Num() >= 2)
		{
			Definition->MapMinXY = FVector2D((*Min)[0]->AsNumber(), (*Min)[1]->AsNumber()) * 100.0;
			Definition->MapMaxXY = FVector2D((*Max)[0]->AsNumber(), (*Max)[1]->AsNumber()) * 100.0;
		}
		Definition->SeaLevelCm = static_cast<float>(NumField(*MapObject, TEXT("sea_level_m"), 0.0) * 100.0);
		Definition->LatitudeDeg = static_cast<float>(NumField(*MapObject, TEXT("latitude_deg"), 36.0));
	}
	Definition->DefaultSpawnPoi = FName(*StrField(Regions, TEXT("default_spawn_poi")));

	// ---- regions (a region may be several rectangles with the same id; higher priority wins) ------------------------------
	TMap<FString, FLinearColor> MetaColors;
	const TArray<TSharedPtr<FJsonValue>>* MetaRegions = nullptr;
	if (Meta->TryGetArrayField(TEXT("regions"), MetaRegions))
	{
		for (const TSharedPtr<FJsonValue>& Value : *MetaRegions)
		{
			const TSharedPtr<FJsonObject> Obj = Value->AsObject();
			const TArray<TSharedPtr<FJsonValue>>* Color = nullptr;
			if (Obj->TryGetArrayField(TEXT("color"), Color) && Color->Num() >= 3)
			{
				MetaColors.Add(StrField(Obj, TEXT("key")), FLinearColor((*Color)[0]->AsNumber() / 255.0, (*Color)[1]->AsNumber() / 255.0, (*Color)[2]->AsNumber() / 255.0, 1.0));
			}
		}
	}
	int32 NumRects = 0;
	const TArray<TSharedPtr<FJsonValue>>* RegionArray = nullptr;
	if (Regions->TryGetArrayField(TEXT("regions"), RegionArray))
	{
		for (const TSharedPtr<FJsonValue>& Value : *RegionArray)
		{
			const TSharedPtr<FJsonObject> Obj = Value->AsObject();
			const TArray<TSharedPtr<FJsonValue>>* Rects = nullptr;
			if (!Obj->TryGetArrayField(TEXT("rects"), Rects))
			{
				continue;
			}
			for (const TSharedPtr<FJsonValue>& RectValue : *Rects)
			{
				// [xmin, ymin, xmax, ymax, priority] in metres
				const TArray<TSharedPtr<FJsonValue>>& Rect = RectValue->AsArray();
				if (Rect.Num() < 5)
				{
					continue;
				}
				FRoamRegionDef Region;
				Region.RegionId = FName(*StrField(Obj, TEXT("id")));
				Region.DisplayName = FText::FromString(StrField(Obj, TEXT("name")));
				Region.Subtitle = FText::FromString(StrField(Obj, TEXT("subtitle")));
				Region.MinXY = FVector2D(Rect[0]->AsNumber(), Rect[1]->AsNumber()) * 100.0;
				Region.MaxXY = FVector2D(Rect[2]->AsNumber(), Rect[3]->AsNumber()) * 100.0;
				Region.Priority = static_cast<int32>(Rect[4]->AsNumber());
				Region.ClimateZone = FName(*StrField(Obj, TEXT("climate")));
				Region.TrafficDensityScale = static_cast<float>(NumField(Obj, TEXT("traffic"), 1.0));
				if (const FLinearColor* Color = MetaColors.Find(StrField(Obj, TEXT("key"))))
				{
					Region.MapColor = *Color;
				}
				Definition->Regions.Add(Region);
				++NumRects;
			}
		}
	}

	// ---- helper: nearest road point (metres) over all raw samples ----------------------------------------------------------
	struct FNearest
	{
		int32 RoadIndex = INDEX_NONE;
		int32 SampleIndex = INDEX_NONE;
		double DistanceM = 1e18;
	};
	auto FindNearest = [&Roads](double X, double Y) -> FNearest
	{
		FNearest Best;
		for (int32 RoadIndex = 0; RoadIndex < Roads.Roads.Num(); ++RoadIndex)
		{
			const TArray<FRawSample>& Samples = Roads.Roads[RoadIndex].Samples;
			for (int32 SampleIndex = 0; SampleIndex < Samples.Num(); ++SampleIndex)
			{
				const double Dx = Samples[SampleIndex].X - X;
				const double Dy = Samples[SampleIndex].Y - Y;
				const double D = FMath::Sqrt(Dx * Dx + Dy * Dy);
				if (D < Best.DistanceM)
				{
					Best.DistanceM = D;
					Best.RoadIndex = RoadIndex;
					Best.SampleIndex = SampleIndex;
				}
			}
		}
		return Best;
	};
	// edge of a data road that contains arc length S
	auto FindEdge = [&Roads](int32 RoadIndex, double S) -> const FRawEdge*
	{
		const FRawEdge* Found = nullptr;
		for (const FRawEdge& Edge : Roads.Edges)
		{
			if (Edge.RoadIndex == RoadIndex && S >= Edge.S0 - 1e-3 && S <= Edge.S1 + 1e-3)
			{
				Found = &Edge;
				if (S < Edge.S1 - 1e-3)
				{
					break; // prefer the edge that starts here
				}
			}
		}
		return Found;
	};
	auto RightLaneOffsetM = [](const FRawRoad& Road) { return Road.MedianWidth * 0.5 + Road.LaneWidth * 0.5; };

	auto FillRoadPlacement = [&](FRoamPoiDef& Poi, int32 RoadIndex, double S, bool bUseLane)
	{
		const FRawRoad& Road = Roads.Roads[RoadIndex];
		const FRawSample Raw = FRoadsJson::Eval(Road, S);
		const double HeadingRad = FMath::DegreesToRadians(Raw.HeadingDeg);
		// right of travel: the forward vector (cos, sin) rotated by +90 degrees (bearing increases clockwise seen from above, X north, Y east)
		const FVector2D RightVec(-FMath::Sin(HeadingRad), FMath::Cos(HeadingRad));
		const double Offset = bUseLane ? RightLaneOffsetM(Road) : 0.0;
		Poi.Location = FVector(Raw.X + RightVec.X * Offset, Raw.Y + RightVec.Y * Offset, Raw.Z) * 100.0;
		Poi.YawDeg = static_cast<float>(Raw.HeadingDeg);
		if (const FRawEdge* Edge = FindEdge(RoadIndex, S))
		{
			Poi.RoadId = Edge->AssetRoadId;
			Poi.RoadS = static_cast<float>((S - Edge->S0) * 100.0);
		}
	};

	// ---- POIs from the generator's sites -----------------------------------------------------------------------------------
	const double SnapDistanceM = NumField(Regions, TEXT("site_snap_distance_m"), 150.0);
	int32 NumSnapped = 0;
	const TArray<TSharedPtr<FJsonValue>>* Sites = nullptr;
	if (Meta->TryGetArrayField(TEXT("sites"), Sites))
	{
		const TSharedPtr<FJsonObject>* KindMap = nullptr;
		Regions->TryGetObjectField(TEXT("site_kind_to_poi_type"), KindMap);
		for (const TSharedPtr<FJsonValue>& Value : *Sites)
		{
			const TSharedPtr<FJsonObject> Obj = Value->AsObject();
			FRoamPoiDef Poi;
			const FString Name = StrField(Obj, TEXT("name"));
			const FString Kind = StrField(Obj, TEXT("kind"));
			Poi.PoiId = FName(*MakeSlug(Name));
			Poi.DisplayName = FText::FromString(Name);
			FString TypeName = TEXT("Other");
			if (KindMap)
			{
				(*KindMap)->TryGetStringField(Kind, TypeName);
			}
			const UEnum* TypeEnum = StaticEnum<ERoamPoiType>();
			const int64 TypeValue = TypeEnum ? TypeEnum->GetValueByNameString(TypeName) : INDEX_NONE;
			Poi.Type = TypeValue != INDEX_NONE ? static_cast<ERoamPoiType>(TypeValue) : ERoamPoiType::Other;
			const double X = NumField(Obj, TEXT("x"));
			const double Y = NumField(Obj, TEXT("y"));
			const double Z = NumField(Obj, TEXT("z"));
			Poi.Location = FVector(X, Y, Z) * 100.0;
			Poi.YawDeg = 0.0f;
			Poi.bTeleportTarget = true;

			const FNearest Near = FindNearest(X, Y);
			if (Near.RoadIndex != INDEX_NONE && Near.DistanceM <= SnapDistanceM)
			{
				const FRawRoad& Road = Roads.Roads[Near.RoadIndex];
				FillRoadPlacement(Poi, Near.RoadIndex, Road.Samples[Near.SampleIndex].S, true);
				++NumSnapped;
			}
			const FRoamRegionDef* Region = Definition->FindRegionAt(Poi.Location);
			Poi.RegionId = Region ? Region->RegionId : NAME_None;
			Definition->Pois.Add(Poi);
		}
	}

	// ---- road-start / road-position POIs -----------------------------------------------------------------------------------
	const TArray<TSharedPtr<FJsonValue>>* RoadPois = nullptr;
	int32 NumRoadPois = 0;
	if (Regions->TryGetArrayField(TEXT("road_pois"), RoadPois))
	{
		for (const TSharedPtr<FJsonValue>& Value : *RoadPois)
		{
			const TSharedPtr<FJsonObject> Obj = Value->AsObject();
			const FString RoadName = StrField(Obj, TEXT("road"));
			const int32* RoadIndex = Roads.RoadIndexById.Find(RoadName);
			if (!RoadIndex)
			{
				UE_LOG(LogRoam, Warning, TEXT("ROAM_WORLDDEF road_poi '%s': unknown road '%s'"), *StrField(Obj, TEXT("id")), *RoadName);
				continue;
			}
			FRoamPoiDef Poi;
			Poi.PoiId = FName(*StrField(Obj, TEXT("id")));
			Poi.DisplayName = FText::FromString(StrField(Obj, TEXT("name")));
			const FString TypeName = StrField(Obj, TEXT("type"), TEXT("RoadStart"));
			const UEnum* TypeEnum = StaticEnum<ERoamPoiType>();
			const int64 TypeValue = TypeEnum ? TypeEnum->GetValueByNameString(TypeName) : INDEX_NONE;
			Poi.Type = TypeValue != INDEX_NONE ? static_cast<ERoamPoiType>(TypeValue) : ERoamPoiType::RoadStart;
			Poi.bTeleportTarget = true;
			const double S = FMath::Clamp(NumField(Obj, TEXT("s"), 0.0), 0.0, Roads.Roads[*RoadIndex].Samples.Last().S);
			const bool bReverse = Obj->HasField(TEXT("reverse")) && Obj->GetBoolField(TEXT("reverse"));
			FillRoadPlacement(Poi, *RoadIndex, S, true);
			if (bReverse)
			{
				Poi.YawDeg = FMath::Fmod(Poi.YawDeg + 180.0f, 360.0f);
			}
			const FRoamRegionDef* Region = Definition->FindRegionAt(Poi.Location);
			Poi.RegionId = Region ? Region->RegionId : NAME_None;
			Definition->Pois.Add(Poi);
			++NumRoadPois;
		}
	}

	Definition->MarkPackageDirty();
	const bool bSaved = SavePackageOf(Definition);
	OutReport = FString::Printf(TEXT("world definition %s: %d region rectangles (%d regions), %d POIs (%d sites snapped to roads, %d road POIs), default spawn POI '%s' (%s), saved=%d"),
		*AssetPath, NumRects, Definition->Regions.Num(), Definition->Pois.Num(), NumSnapped, NumRoadPois, *Definition->DefaultSpawnPoi.ToString(),
		Definition->FindPoi(Definition->DefaultSpawnPoi) ? TEXT("found") : TEXT("MISSING"), bSaved ? 1 : 0);
	UE_LOG(LogRoam, Display, TEXT("ROAM_WORLDDEF %s"), *OutReport);
	return Definition;
}
