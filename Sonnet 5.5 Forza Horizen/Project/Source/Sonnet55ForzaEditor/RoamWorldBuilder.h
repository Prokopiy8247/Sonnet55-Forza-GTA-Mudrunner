// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"
#include "RoamWorldBuilder.generated.h"

class ALandscape;
class ULandscapeLayerInfoObject;
class UMaterialInterface;
class UPhysicalMaterial;
class URoamRoadNetwork;
class URoamWorldDefinition;
class UWorld;

/**
 * Parameters of URoamWorldBuilder::CreateLandscapeFromHeightmap (Docs/Tech/WORLD_BUILD.md).
 *
 * The source data are the raw grids written by Tools/world/build_world.py: a uint16 little-endian heightmap and uint8 weight maps,
 * all SourceSize x SourceSize, row-major with the ROW = +Y direction and the COLUMN = +X direction (UE landscape layout, no flips).
 * The grid is padded (edge replication) to the next valid landscape size: (verts - 1) must be a multiple of
 * QuadsPerSection * SectionsPerComponent (127 x 2 = 254 quads per component -> 4065 vertices for the 4033 map, 16 x 16 components).
 */
USTRUCT(BlueprintType)
struct FRoamLandscapeBuildParams
{
	GENERATED_BODY()

	/** Absolute path of heightmap_4033.r16 (uint16 LE, Z_cm = (h - 32768) / 128 * Scale.Z). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	FString HeightmapFile;

	/** Vertices per side of the source grids (4033). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	int32 SourceSize = 4033;

	/** Weight layers, in landscape layer order. LayerNames[i] is read from LayerFiles[i] and uses LayerInfos[i]. All three arrays must have equal length (may be empty: no weights). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	TArray<FName> LayerNames;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	TArray<FString> LayerFiles;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	TArray<TObjectPtr<ULandscapeLayerInfoObject>> LayerInfos;

	/** Optional sub-window of the source (for fast tests): first vertex and number of vertices per side. CropSize 0 = the whole source. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	int32 CropX = 0;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	int32 CropY = 0;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	int32 CropSize = 0;

	/**
	 * Landscape holes: SOURCE-grid vertices (X index, Y index; vertex (i, j) is at X = i - 2016 m, Y = j - 2016 m, i.e. the layout of
	 * Exports/Roads/chunks.json -> landscape_hole_vertices) whose quads are hidden through the landscape visibility layer (weight 255 on
	 * ALandscapeProxy::VisibilityLayer; the renderer / Nanite mesh drop the quads, the heightfield collision opens the cell owned by the
	 * vertex). The padding and crop shift of the import is applied here. Empty = no holes.
	 */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Source")
	TArray<FIntPoint> HoleVertices;

	/** Landscape component layout. 127 quads x 2 x 2 sections = 254-quad components. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Landscape")
	int32 QuadsPerSection = 127;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Landscape")
	int32 SectionsPerComponent = 2;

	/** Actor scale: X/Y = cm per vertex (100 = 1 m), Z = height scale (300 for the Roamline heightmap encoding). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Landscape")
	FVector Scale = FVector(100.0, 100.0, 300.0);

	/** World position (cm) of the CENTRE vertex of the source grid ((SourceSize-1)/2) - the world origin for the Roamline map. Z is the actor Z. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Landscape")
	FVector SourceCentreCm = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Landscape")
	TObjectPtr<UMaterialInterface> Material;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Landscape")
	TObjectPtr<UPhysicalMaterial> DefaultPhysicalMaterial;

	/** Collision profile name applied to the landscape actor and every proxy (the vehicle ground rays need RoamWorldStatic). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Landscape")
	FName CollisionProfile = TEXT("RoamWorldStatic");

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Landscape")
	FString ActorLabel = TEXT("Landscape_Roamline");

	/** Edge length (in components) of the World Partition landscape proxies. 0 = keep one big actor (non partitioned maps). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "WorldPartition")
	int32 WorldPartitionGridComponents = 4;

	/** True: the landscape proxies are never streamed out (always loaded). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "WorldPartition")
	bool bProxiesAlwaysLoaded = true;

	/** Enable the Nanite landscape representation (it still has to be built: BuildLandscapeData). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Nanite")
	bool bEnableNanite = true;
};

/** Result of URoamWorldBuilder::CreateLandscapeFromHeightmap. */
USTRUCT(BlueprintType)
struct FRoamLandscapeBuildResult
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Result")
	bool bSuccess = false;

	UPROPERTY(BlueprintReadOnly, Category = "Result")
	TObjectPtr<ALandscape> Landscape;

	/** Vertices per side of the created landscape (4065 for the full map). */
	UPROPERTY(BlueprintReadOnly, Category = "Result")
	int32 LandscapeVerts = 0;

	UPROPERTY(BlueprintReadOnly, Category = "Result")
	int32 ComponentsPerSide = 0;

	/** Padding added at the low / high end of each axis (vertices). */
	UPROPERTY(BlueprintReadOnly, Category = "Result")
	int32 PadLow = 0;
	UPROPERTY(BlueprintReadOnly, Category = "Result")
	int32 PadHigh = 0;

	/** World location (cm) of landscape vertex (0,0). */
	UPROPERTY(BlueprintReadOnly, Category = "Result")
	FVector ActorLocationCm = FVector::ZeroVector;

	UPROPERTY(BlueprintReadOnly, Category = "Result")
	int32 NumProxies = 0;

	/** Number of visibility-layer (hole) vertices written. */
	UPROPERTY(BlueprintReadOnly, Category = "Result")
	int32 NumHoleVertices = 0;

	UPROPERTY(BlueprintReadOnly, Category = "Result")
	float ReadSeconds = 0.0f;
	UPROPERTY(BlueprintReadOnly, Category = "Result")
	float ImportSeconds = 0.0f;

	UPROPERTY(BlueprintReadOnly, Category = "Result")
	FString Report;
};

/** One surface sample of the landscape, for verification scripts (URoamWorldBuilder::SampleLandscape). */
USTRUCT(BlueprintType)
struct FRoamLandscapeSample
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Sample")
	bool bValid = false;

	/** Landscape height in cm (world Z). */
	UPROPERTY(BlueprintReadOnly, Category = "Sample")
	float HeightCm = 0.0f;
};

/**
 * Editor-only world construction utilities for Roamline (landscape from the generated heightmap, layer infos, Nanite, World Partition
 * tuning, road network / world definition data assets). Callable from Python as  unreal.RoamWorldBuilder.<snake_case_name>(...).
 * Orchestrated by Tools/ue/world_build.py; documented in Docs/Tech/WORLD_BUILD.md. Owner: world-builder agent (F1).
 */
UCLASS()
class URoamWorldBuilder : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/** One-line status; proves the class is reachable from Python. */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static FString GetWorldBuilderStatus();

	// ---- landscape --------------------------------------------------------------------------------------------------

	/**
	 * Reads the raw heightmap + weight maps, pads them to a valid landscape size and creates the landscape (ALandscape.Import), the
	 * target layers, the material, collision profile and, in a World Partition world, the streaming proxies (always loaded when
	 * Params.bProxiesAlwaysLoaded). The actor is positioned so that the source centre vertex lies at Params.SourceCentreCm.
	 * Does not save anything.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static FRoamLandscapeBuildResult CreateLandscapeFromHeightmap(UWorld* World, const FRoamLandscapeBuildParams& Params);

	/**
	 * Creates (or loads, when it already exists) a ULandscapeLayerInfoObject asset  PackageFolder/AssetName  for a layer and assigns the
	 * physical material (may be null). Saves nothing - the caller saves with EditorAssetLibrary.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static ULandscapeLayerInfoObject* CreateOrLoadLayerInfo(FName LayerName, const FString& PackageFolder, const FString& AssetName, UPhysicalMaterial* PhysicalMaterial, bool bWeightBlended);

	/** Assigns PhysicalMaterial to an existing layer info asset (SetPhysicalMaterial). */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static bool SetLayerInfoPhysicalMaterial(ULandscapeLayerInfoObject* LayerInfo, UPhysicalMaterial* PhysicalMaterial);

	/**
	 * Helper to assign physical materials to the layers of an existing landscape by layer name (parallel arrays; layers not listed are
	 * untouched). Returns the number of layers changed and then re-registers them with the landscape info.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static int32 AssignLayerPhysicalMaterials(ALandscape* Landscape, const TArray<FName>& LayerNames, const TArray<UPhysicalMaterial*>& PhysicalMaterials);

	/** Switch the Nanite landscape representation on every proxy (does not build it). */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static bool SetLandscapeNanite(ALandscape* Landscape, bool bEnable);

	/** Replaces the landscape material on the landscape and all proxies. */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static bool SetLandscapeMaterial(ALandscape* Landscape, UMaterialInterface* Material);

	/**
	 * Builds the derived landscape data of the editor world: grass maps, physical-material (dominant layer) data and Nanite meshes.
	 * Synchronous. Returns a one-line summary with the number of outdated proxies before/after.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static FString BuildLandscapeData(UWorld* World, bool bBuildGrassMaps, bool bBuildPhysicalMaterial, bool bBuildNanite);

	/** Number of landscape proxies of the world with stale Nanite / physical material / grass data (verification). */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static FString DescribeLandscape(UWorld* World);

	/** Landscape height (cm, world Z) at a world XY (cm). */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static FRoamLandscapeSample SampleLandscape(UWorld* World, double WorldXCm, double WorldYCm);

	// ---- world partition --------------------------------------------------------------------------------------------

	/**
	 * Configures the runtime partition of a World Partition world (runtime hash set): main grid cell size, loading range, streaming
	 * flag. 5.8's default (256 m range / 128 m cells) is far too small for driving. Returns a one-line summary (or an error).
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static FString ConfigureWorldPartition(UWorld* World, int32 CellSizeCm, int32 LoadingRangeCm, bool bEnableStreaming);

	// ---- data assets ------------------------------------------------------------------------------------------------

	/**
	 * Builds the runtime road graph (URoamRoadNetwork) from roads.json (Docs/WORLD_DATA_FORMATS.md) and stores it as asset AssetPath
	 * (e.g. /Game/Forza/Data/DA_RoadNetwork). One URoamRoad per EDGE of the junction graph (a road that touches several nodes is split
	 * at them; single-edge roads keep the road id, the others are "<road>#<k>"). The asset is created/overwritten and saved.
	 * OutReport receives a multi-line summary.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static URoamRoadNetwork* CreateRoadNetworkAsset(const FString& RoadsJsonPath, const FString& AssetPath, FString& OutReport);

	/**
	 * Builds URoamWorldDefinition (regions, POIs / teleport targets) from world_meta.json (sites), roads.json (road start POIs) and the
	 * hand-authored Tools/ue/world_regions.json (region rectangles, display names, POI naming); saved as AssetPath.
	 */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static URoamWorldDefinition* CreateWorldDefinitionAsset(const FString& WorldMetaJsonPath, const FString& RoadsJsonPath, const FString& RegionsJsonPath, const FString& AssetPath, FString& OutReport);

	/** Saves an asset (package) to disk. Returns false on failure. Works in commandlet runs where UEditorAssetLibrary dialogs would not. */
	UFUNCTION(BlueprintCallable, Category = "Roam|World")
	static bool SaveAssetByObject(UObject* Asset);
};
