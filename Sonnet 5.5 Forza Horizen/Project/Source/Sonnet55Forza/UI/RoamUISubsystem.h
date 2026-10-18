// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "Core/RoamTypes.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "RoamUISubsystem.generated.h"

class ARoamHUD;
class ARoamVehicle;
class SRoamHud;
class SWidget;
class URoamRoadNetwork;

/** Panels (screens) the UI subsystem tracks. Console and DebugMenu are overlays; Garage, Map, PauseMenu and PhotoMode are exclusive. */
UENUM(BlueprintType)
enum class ERoamUIPanel : uint8
{
	Console = 0,
	Garage,
	DebugMenu,
	Map,
	PhotoMode,
	PauseMenu,
	Count UMETA(Hidden)
};
ENUM_RANGE_BY_COUNT(ERoamUIPanel, ERoamUIPanel::Count);

DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnPanelChanged, ERoamUIPanel /*Panel*/, bool /*bOpen*/);
DECLARE_MULTICAST_DELEGATE_OneParam(FRoamOnNotificationPushed, const FRoamNotification& /*Notification*/);
DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnRegionPopup, const FText& /*Name*/, const FText& /*Subtitle*/);
DECLARE_MULTICAST_DELEGATE_TwoParams(FRoamOnScreenChanged, FName /*ScreenId*/, bool /*bShown*/);

/** Z-order layers of the viewport widgets (see RoamUI::Layer in RoamUIStyle.h). */
enum class ERoamUILayer : uint8
{
	Hud = 0,   // always-on HUD (z 100)
	Overlay,   // transient overlays above the HUD (z 640)
	Modal      // full screens: map, photo overlay, settings, ... (z 800)
};

/**
 * A generic screen for URoamUISubsystem::RegisterScreen (full map, photo overlay, settings, ...): the factory is called lazily on the
 * first ShowScreen and the widget is cached until the HUD ends. While shown, bBlocksGameplayInput blocks driving input and bShowCursor
 * switches the input mode to game-and-UI with a visible cursor.
 */
struct FRoamScreenDesc
{
	FName Id;
	TFunction<TSharedRef<SWidget>()> Factory;
	ERoamUILayer Layer = ERoamUILayer::Modal;
	bool bBlocksGameplayInput = true;
	bool bShowCursor = true;
};

/**
 * Owner of the game's UI state and of the Slate widgets (Docs/ARCHITECTURE.md sections 3 and 5): HUD, minimap, console, garage,
 * debug menu, map, photo overlay, notifications. Lives for the whole game session (UGameInstanceSubsystem); the HUD actor of a
 * level tells it when it is ready (OnHUDReady) and when the level ends (OnHUDEndPlay).
 *
 * What the SKELETON implements (so that every other system can already talk to the UI without the widgets existing):
 *   - the notification queue and region-name popup state (widgets read it, other systems push into it),
 *   - the panel open/closed state machine with exclusivity rules, game pause for Map/Pause and input-mode switching
 *     (game <-> game-and-UI, gameplay mapping context on/off through ARoamPlayerController::SetGameplayInputEnabled),
 *   - helpers to add/remove Slate widgets to the game viewport,
 *   - console commands: ui, notify, fps, speed.
 *
 * ---- OWNER: UI agent ------------------------------------------------------------------------------------------------------
 * Fills CreateWidgets()/DestroyWidgets() (SRoamHud, SRoamMinimap, SRoamConsole, SRoamGarageMenu, SRoamDebugMenu, SRoamMapScreen,
 * SRoamPhotoOverlay) in their own files under UI/ and reacts to OnPanelChanged / OnNotificationPushed. Widgets pull data through
 * the vehicle (GetPlayerVehicle()->GetTelemetry(), ->GetCameraMode()), URoamTimeWeatherSubsystem, URoamRegionSubsystem,
 * URoamActivitySubsystem and URoamSaveSubsystem - never the other way round.
 */
UCLASS()
class SONNET55FORZA_API URoamUISubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	static URoamUISubsystem* Get(const UObject* WorldContext);

	//~ Begin USubsystem
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;
	//~ End USubsystem

	// ---- HUD lifecycle ---------------------------------------------------------------------------------------------
	/** Called by ARoamHUD::BeginPlay. Creates the widgets (OWNER: UI). */
	void OnHUDReady(ARoamHUD* HUD);
	/** Called by ARoamHUD::EndPlay. Destroys the widgets and closes all panels. */
	void OnHUDEndPlay(ARoamHUD* HUD);
	ARoamHUD* GetHUD() const { return ActiveHUD.Get(); }

	/** The vehicle the UI shows (first local player's pawn). */
	ARoamVehicle* GetPlayerVehicle() const;

	// ---- notifications ---------------------------------------------------------------------------------------------
	/**
	 * Pushes a toast (Docs/ARCHITECTURE.md section 3). Seconds <= 0 uses the player's NotificationSeconds setting.
	 * Returns the notification id.
	 */
	int32 PushNotification(const FText& Title, const FText& Body, FLinearColor Color, float Seconds = 0.0f);
	/** Full variant (banner / result card with stars). */
	int32 PushNotification(const FRoamNotification& Notification);

	/** Notifications still visible (real time), oldest first. Expired ones are pruned. */
	TArray<FRoamNotification> GetActiveNotifications();
	void ClearNotifications();

	/** Region name popup (Docs/Tech/FH5_traffic_hud_photo.md 3.3: 350 ms in, 2.8 s hold, 400 ms out - timing by the widget). */
	void ShowRegionName(const FText& Name, const FText& Subtitle = FText::GetEmpty());
	/** Latest popup and when it was shown (FPlatformTime::Seconds), false if none yet. */
	bool GetRegionPopup(FText& OutName, FText& OutSubtitle, double& OutShownAt) const;

	// ---- panels ----------------------------------------------------------------------------------------------------
	UFUNCTION(BlueprintCallable, Category = "Roam|UI")
	void SetPanelOpen(ERoamUIPanel Panel, bool bOpen);
	UFUNCTION(BlueprintCallable, Category = "Roam|UI")
	bool IsPanelOpen(ERoamUIPanel Panel) const;
	UFUNCTION(BlueprintCallable, Category = "Roam|UI")
	void TogglePanel(ERoamUIPanel Panel) { SetPanelOpen(Panel, !IsPanelOpen(Panel)); }
	UFUNCTION(BlueprintCallable, Category = "Roam|UI")
	void CloseAllPanels();
	/** True while any panel is open. */
	UFUNCTION(BlueprintCallable, Category = "Roam|UI")
	bool IsAnyPanelOpen() const;
	/** True while a panel that must swallow driving input (console, garage, map, pause, photo) is open. */
	UFUNCTION(BlueprintCallable, Category = "Roam|UI")
	bool IsGameplayInputBlocked() const;

	// ---- generic screens (mission B1; the enum panels above stay as they are) ------------------------------------------
	/** Registers (or replaces) a screen. Registrations survive level changes; widgets are created lazily and dropped with the HUD. */
	void RegisterScreen(const FRoamScreenDesc& Desc);
	void UnregisterScreen(FName Id);
	/** Creates the widget on first use and adds it to the viewport. False when the id is unknown or no viewport exists. */
	bool ShowScreen(FName Id);
	void HideScreen(FName Id);
	void ToggleScreen(FName Id) { if (IsScreenShown(Id)) { HideScreen(Id); } else { ShowScreen(Id); } }
	bool IsScreenShown(FName Id) const;
	bool IsScreenRegistered(FName Id) const;
	TSharedPtr<SWidget> GetScreenWidget(FName Id) const;
	/** z-order used for a layer. */
	static int32 GetLayerZOrder(ERoamUILayer Layer);

	// ---- HUD (SRoamHud) ----------------------------------------------------------------------------------------------
	TSharedPtr<SRoamHud> GetHudWidget() const { return HudWidget; }
	/** Road network the minimap/GPS use: the synthetic test network while ui.testnetwork is on, else the configured DA_RoadNetwork (may be null). */
	URoamRoadNetwork* ResolveRoadNetwork() const;
	/** Console `ui.testnetwork`: feeds the minimap a generated network (BuildGeneratedForTests) even when no DA_RoadNetwork exists. */
	void SetTestNetworkEnabled(bool bEnabled);
	bool IsTestNetworkEnabled() const { return bTestNetwork; }
	/** Minimap hooks: waypoint marker and GPS route polyline (world cm). */
	void SetWaypoint(const FVector& WorldCm);
	void ClearWaypoint();
	void SetRoute(const TArray<FVector>& WorldPointsCm);
	void ClearRoute();
	/** Console `ui.testevent`: fake activity live info on the event bar. */
	void SetTestEventEnabled(bool bEnabled);
	/** Shows/hides the whole HUD layer (also hidden automatically while garage/map/photo/pause are open). */
	void SetHudHidden(bool bHidden);

	void ToggleConsole() { TogglePanel(ERoamUIPanel::Console); }
	void ToggleGarage() { TogglePanel(ERoamUIPanel::Garage); }
	void ToggleDebugMenu() { TogglePanel(ERoamUIPanel::DebugMenu); }
	void ToggleMap() { TogglePanel(ERoamUIPanel::Map); }
	void TogglePhotoMode() { TogglePanel(ERoamUIPanel::PhotoMode); }
	void TogglePauseMenu() { TogglePanel(ERoamUIPanel::PauseMenu); }

	/** Re-applies input mode / cursor / gameplay mapping context for the current panel state. */
	void RefreshInputMode();

	// ---- viewport widgets ------------------------------------------------------------------------------------------
	/** Adds a Slate widget to the game viewport (tracked so it is removed on HUD end play). Higher ZOrder draws on top. */
	void AddViewportWidget(TSharedRef<SWidget> Widget, int32 ZOrder = 0);
	void RemoveViewportWidget(TSharedRef<SWidget> Widget);

	// ---- events ----------------------------------------------------------------------------------------------------
	FRoamOnPanelChanged OnPanelChanged;
	FRoamOnNotificationPushed OnNotificationPushed;
	FRoamOnRegionPopup OnRegionPopup;
	FRoamOnScreenChanged OnScreenChanged;

protected:
	/** OWNER: UI agent. Build all Slate widgets and add them with AddViewportWidget. Called from OnHUDReady. */
	void CreateWidgets();
	/** OWNER: UI agent. Release widget references (the viewport widgets are removed automatically). */
	void DestroyWidgets();

private:
	void PruneNotifications();
	void UpdateHudVisibility();
	bool AnyScreenWants(bool bCursor) const;

	TWeakObjectPtr<ARoamHUD> ActiveHUD;
	TArray<FRoamNotification> Notifications;
	int32 NextNotificationId = 1;
	bool bPanelOpen[static_cast<int32>(ERoamUIPanel::Count)] = {};
	FText RegionPopupName;
	FText RegionPopupSubtitle;
	double RegionPopupShownAt = -1.0;
	TArray<TSharedRef<SWidget>> ViewportWidgets;

	// --- added by B1 (hud) ---
	struct FScreenEntry
	{
		FRoamScreenDesc Desc;
		TSharedPtr<SWidget> Widget;
		bool bShown = false;
	};
	TMap<FName, FScreenEntry> Screens;
	TSharedPtr<SRoamHud> HudWidget;
	bool bHudHidden = false;
	bool bTestNetwork = false;
	UPROPERTY(Transient)
	TObjectPtr<URoamRoadNetwork> TestNetwork;
};
