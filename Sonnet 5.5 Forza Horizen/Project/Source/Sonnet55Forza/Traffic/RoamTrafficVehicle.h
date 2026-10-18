// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Core/RoamTypes.h"
#include "RoamTrafficVehicle.generated.h"

class UStaticMesh;
class UStaticMeshComponent;
class UMaterialInstanceDynamic;
class ARoamTrafficVehicle;

/**
 * Simulation level of detail of a traffic agent (Docs/Tech/FH5_traffic_hud_photo.md 2.2). The subsystem decides the level from the
 * distance to the player; the actor only applies it.
 */
UENUM(BlueprintType)
enum class ERoamTrafficLOD : uint8
{
	Physics = 0,   // 0-120 m: collision body, kinematic-driven, switches to physics after a hit
	Kinematic,     // 120-450 m: mesh LOD, no collision, transform driven at a low rate and interpolated
	DataOnly,      // 450-900 m: no actor, agent struct only
	Culled         // beyond: removed
};

/** One wheel of a traffic vehicle with any wheel count (lorry 10, coach 6): mesh pivot = axle centre, axle along local Y. Filled from DA_TrafficVehicles. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamTrafficWheelSlot
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	TSoftObjectPtr<UStaticMesh> Mesh;

	/** Axle centre in UE car space (cm, origin = ground under the middle of the wheelbase). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	FVector CentreCm = FVector::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	float RadiusCm = 31.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	bool bSteering = false;
};

/** Static description of a civilian vehicle type (small car, van, lorry, bus, tractor, pickup). Registered with URoamTrafficSubsystem. */
USTRUCT(BlueprintType)
struct SONNET55FORZA_API FRoamTrafficVehicleSpec
{
	GENERATED_BODY()

	/** "traffic01_compact", "traffic02_van", ... (Docs/CAR_ROSTER.md). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	FName TypeId;

	/** Body mesh, pivot on the ground under the middle of the wheelbase (Docs/BLENDER_CONTRACT.md). Missing = engine cube placeholder. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	TSoftObjectPtr<UStaticMesh> BodyMesh;

	/** Window mesh (same pivot as the body). Optional. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	TSoftObjectPtr<UStaticMesh> GlassMesh;

	/** One mesh for every wheel (used when PerWheelMeshes is empty). Missing = engine cylinder placeholder. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	TSoftObjectPtr<UStaticMesh> WheelMesh;

	/** FL, FR, RL, RR wheel meshes, each centred on its axle (SM_<id>_Wheel_FL ...). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	TArray<TSoftObjectPtr<UStaticMesh>> PerWheelMeshes;

	/** Wheels with their own positions (any count). When not empty it replaces the four FL/FR/RL/RR wheels computed from wheelbase and track. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	TArray<FRoamTrafficWheelSlot> Wheels;

	/** Paint variants the spawner picks from by agent id (M_Paint primary, M_Paint2 secondary). Empty = the mesh's own material colours. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	TArray<FRoamPaint> PaintVariants;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	float LengthCm = 430.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	float WidthCm = 180.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	float HeightCm = 150.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	float WheelbaseCm = 255.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	float WheelRadiusCm = 31.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	float TrackCm = 150.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic")
	float MassKg = 1300.0f;

	// IDM parameters (Docs/Tech/FH5_traffic_hud_photo.md 2.4)
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic|Behaviour")
	float MaxSpeedKmh = 130.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic|Behaviour")
	float AccelerationMs2 = 2.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic|Behaviour")
	float ComfortDecelMs2 = 3.0f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic|Behaviour")
	float TimeHeadwaySec = 1.5f;
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic|Behaviour")
	float MinGapM = 2.5f;

	/** Relative spawn probability. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic|Spawning")
	float SpawnWeight = 1.0f;

	/** Road classes this type may use (empty = all). */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Traffic|Spawning")
	TArray<ERoamRoadClass> AllowedRoadClasses;
};

/** Native hit notification of the collision body (the subsystem turns it into a physics reaction). */
DECLARE_MULTICAST_DELEGATE_ThreeParams(FRoamOnTrafficBodyHit, ARoamTrafficVehicle* /*Vehicle*/, AActor* /*Other*/, const FVector& /*NormalImpulse*/);

/**
 * Visual + collision actor of a traffic agent. POOLED: the traffic subsystem creates them up front, activates them at the agent's pose
 * and returns them to the pool on despawn - nobody calls SpawnActor/Destroy during play. It does not tick; the subsystem drives
 * transforms and calls TickVisuals in one batch (Docs/ARCHITECTURE.md section 8: "single tick for all").
 *
 * Without imported meshes the actor shows an engine cube scaled to the vehicle size on four engine cylinders (placeholder), so the
 * whole pipeline runs before the Blender meshes exist. The actor origin is the ground point under the middle of the wheelbase.
 */
UCLASS()
class SONNET55FORZA_API ARoamTrafficVehicle : public AActor
{
	GENERATED_BODY()

public:
	ARoamTrafficVehicle();

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Traffic")
	TObjectPtr<UStaticMeshComponent> Body;

	/** FL, FR, RL, RR. */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Traffic")
	TArray<TObjectPtr<UStaticMeshComponent>> WheelMeshes;

	/** Wheels 5.. of vehicles with more than four (created on demand, pooled with the actor). */
	UPROPERTY(Transient)
	TArray<TObjectPtr<UStaticMeshComponent>> ExtraWheelMeshes;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Traffic")
	TObjectPtr<UStaticMeshComponent> Glass;

	/** Rear lamps of the placeholder body (brake / hazard feedback); hidden with real meshes, whose emissive materials take over. */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Traffic")
	TArray<TObjectPtr<UStaticMeshComponent>> TailLamps;

	/** Takes a vehicle out of the pool and places it (Transform = ground pose). Sets meshes from the spec, enables collision. */
	void ActivateAt(const FTransform& Transform, const FRoamTrafficVehicleSpec& InSpec, int32 InAgentId);

	/** Returns the vehicle to the pool: hidden, no collision, no physics. */
	void Deactivate();

	bool IsActiveInTraffic() const { return bActiveInTraffic; }
	int32 GetAgentId() const { return AgentId; }
	const FRoamTrafficVehicleSpec& GetSpec() const { return Spec; }

	/** Applies a simulation LOD (collision on/off, mesh LOD bias). */
	void SetSimLOD(ERoamTrafficLOD NewLOD);
	ERoamTrafficLOD GetSimLOD() const { return SimLOD; }

	/**
	 * Moves the body kinematically (Target = ground pose). VelocityCmS is the agent's velocity, used for wheel spin and steering.
	 * Ignored once the vehicle is in its physics reaction.
	 */
	void SetKinematicTarget(const FTransform& Target, const FVector& VelocityCmS);

	/** Hands the body over to physics after a hit and keeps the last velocity (YawKickDegS = initial spin about Z). */
	void EnablePhysicsReaction(const FVector& InitialVelocityCmS, float YawKickDegS = 0.0f);
	bool IsInPhysicsReaction() const { return bPhysicsReaction; }

	/** After the reaction: freezes the wreck where it lies; it stays a collider (a stopped obstacle). */
	void SettleAsObstacle();
	bool IsSettledObstacle() const { return bSettled; }

	void SetBrakeLights(bool bOn) { bBrakeLights = bOn; }
	void SetHazardLights(bool bOn) { bHazardLights = bOn; }
	void SetHeadlights(bool bOn) { bHeadlights = bOn; }
	bool AreBrakeLightsOn() const { return bBrakeLights; }
	bool AreHazardLightsOn() const { return bHazardLights; }
	bool AreHeadlightsOn() const { return bHeadlights; }

	/** Short horn / lamp flash (blocked by the player). Fires OnHorn: the audio system binds it to play the sound at the vehicle. */
	void Horn();
	bool IsHornActive() const { return HornTimer > 0.0f; }
	FSimpleMulticastDelegate OnHorn;

	/** Collision body was hit by another actor (not fired during the physics reaction). */
	FRoamOnTrafficBodyHit OnBodyHit;

	/** Per-frame visuals: wheel spin and steering, lamps, horn timer. Called by the subsystem for every active actor. */
	void TickVisuals(float DeltaTime);

	//~ Begin AActor
	virtual void PostInitializeComponents() override;
	//~ End AActor

private:
	UFUNCTION()
	void HandleBodyHit(UPrimitiveComponent* HitComp, AActor* OtherActor, UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit);

	void ApplySpec();
	void UpdateWheelPose();
	void UpdateLamps();
	UStaticMeshComponent* GetWheelComponent(int32 Index);
	void BuildRealMeshMaterials(const FRoamPaint* Paint);
	void SetLampIntensities(float Head, float Tail, float Indicator);
	static UStaticMesh* LoadSoftMesh(const TSoftObjectPtr<UStaticMesh>& Soft);

	UPROPERTY(Transient)
	TObjectPtr<UStaticMesh> PlaceholderCube;
	UPROPERTY(Transient)
	TObjectPtr<UStaticMesh> PlaceholderCylinder;
	UPROPERTY(Transient)
	TObjectPtr<UMaterialInstanceDynamic> BodyMID;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> LampMIDs;
	/** Real-mesh materials by Blender slot name (M_Paint, M_Paint2, M_Headlight, M_Taillight, M_Indicator): emissive 'Intensity' and paint 'PrimaryColor'. */
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> PaintMIDs;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> Paint2MIDs;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> HeadMIDs;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> TailMIDs;
	UPROPERTY(Transient)
	TArray<TObjectPtr<UMaterialInstanceDynamic>> IndicatorMIDs;
	TWeakObjectPtr<UStaticMesh> RealMidsMesh;
	float LampHeadLevel = -1.0f;
	float LampTailLevel = -1.0f;
	float LampIndicatorLevel = -1.0f;

	FRoamTrafficVehicleSpec Spec;
	ERoamTrafficLOD SimLOD = ERoamTrafficLOD::Culled;
	int32 AgentId = INDEX_NONE;
	bool bActiveInTraffic = false;
	bool bPhysicsReaction = false;
	bool bSettled = false;
	bool bBrakeLights = false;
	bool bHazardLights = false;
	bool bHeadlights = false;

	bool bPlaceholderBody = true;
	TArray<bool> bWheelPlaceholder;
	TArray<bool> bWheelSteers;
	FVector BodyScale = FVector::OneVector;
	float GroundOffsetCm = 0.0f;
	TArray<FVector> WheelCentreGround;

	float WheelAngleDeg = 0.0f;
	float SteerDeg = 0.0f;
	float LastYawDeg = 0.0f;
	bool bHasLastYaw = false;
	float LastSpeedCms = 0.0f;
	float HornTimer = 0.0f;
	int32 LastLampState = -1;
};
