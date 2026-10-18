// Copyright Epic Games, Inc. All Rights Reserved.

#include "UI/RoamUISubsystem.h"

#include "Console/RoamConsoleSubsystem.h"
#include "Core/RoamGameInstance.h"
#include "Core/RoamHUD.h"
#include "Core/RoamLog.h"
#include "Core/RoamPlayerController.h"
#include "Data/RoamRoadNetwork.h"
#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "Framework/Application/SlateApplication.h"
#include "Kismet/GameplayStatics.h"
#include "Save/RoamSaveSubsystem.h"
#include "UI/RoamMenus.h"
#include "UI/RoamUIStyle.h"
#include "UI/SRoamHud.h"
#include "UI/SRoamMinimap.h"
#include "UI/SRoamNotifications.h"
#include "Vehicle/RoamVehicle.h"
#include "Widgets/SWidget.h"

namespace
{
	constexpr int32 MaxStoredNotifications = 16;

	bool IsExclusivePanel(ERoamUIPanel Panel)
	{
		return Panel == ERoamUIPanel::Garage || Panel == ERoamUIPanel::Map || Panel == ERoamUIPanel::PhotoMode || Panel == ERoamUIPanel::PauseMenu;
	}
}

URoamUISubsystem* URoamUISubsystem::Get(const UObject* WorldContext)
{
	const UWorld* World = GEngine ? GEngine->GetWorldFromContextObject(WorldContext, EGetWorldErrorMode::ReturnNull) : nullptr;
	const UGameInstance* GameInstance = World ? World->GetGameInstance() : nullptr;
	return GameInstance ? GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
}

void URoamUISubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	// The console subsystem registers its own commands; make sure it exists before the UI asks for it.
	Collection.InitializeDependency<URoamConsoleSubsystem>();
	Collection.InitializeDependency<URoamSaveSubsystem>();
}

void URoamUISubsystem::Deinitialize()
{
	DestroyWidgets();
	ViewportWidgets.Reset();
	Super::Deinitialize();
}

ARoamVehicle* URoamUISubsystem::GetPlayerVehicle() const
{
	const UGameInstance* GameInstance = GetGameInstance();
	const APlayerController* PC = GameInstance ? GameInstance->GetFirstLocalPlayerController() : nullptr;
	return PC ? Cast<ARoamVehicle>(PC->GetPawn()) : nullptr;
}

void URoamUISubsystem::OnHUDReady(ARoamHUD* HUD)
{
	ActiveHUD = HUD;
	CreateWidgets();
	RefreshInputMode();
	UE_LOG(LogRoamUI, Display, TEXT("ROAM_UI_READY hud=%s"), HUD ? *HUD->GetName() : TEXT("<none>"));
}

void URoamUISubsystem::OnHUDEndPlay(ARoamHUD* HUD)
{
	if (ActiveHUD.Get() != HUD)
	{
		return;
	}
	DestroyWidgets();
	if (GEngine && GEngine->GameViewport)
	{
		for (const TSharedRef<SWidget>& Widget : ViewportWidgets)
		{
			GEngine->GameViewport->RemoveViewportWidgetContent(Widget);
		}
	}
	ViewportWidgets.Reset();
	for (bool& bOpen : bPanelOpen)
	{
		bOpen = false;
	}
	ActiveHUD.Reset();
}

void URoamUISubsystem::CreateWidgets()
{
	if (HudWidget.IsValid() || IsRunningCommandlet() || !GEngine || !GEngine->GameViewport || !FSlateApplication::IsInitialized())
	{
		return;
	}
	HudWidget = SNew(SRoamHud, TWeakObjectPtr<URoamUISubsystem>(this));
	AddViewportWidget(HudWidget.ToSharedRef(), GetLayerZOrder(ERoamUILayer::Hud));
	if (bTestNetwork)
	{
		HudWidget->GetMinimap()->SetNetwork(TestNetwork);
	}
	// Console overlay, garage, debug menu and pause menu (mission B2). Idempotent; a 0.5 s ticker in RoamMenus.cpp does the same as a fallback.
	RoamRegisterMenuScreens(this);
	UpdateHudVisibility();
}

void URoamUISubsystem::DestroyWidgets()
{
	RoamUnregisterMenuScreens(this);
	for (TPair<FName, FScreenEntry>& Pair : Screens)
	{
		Pair.Value.bShown = false;
		Pair.Value.Widget.Reset();
	}
	HudWidget.Reset();
}

int32 URoamUISubsystem::GetLayerZOrder(ERoamUILayer Layer)
{
	switch (Layer)
	{
	case ERoamUILayer::Hud: return RoamUI::Layer::Hud;
	case ERoamUILayer::Overlay: return RoamUI::Layer::Overlay;
	default: return RoamUI::Layer::Modal;
	}
}

void URoamUISubsystem::UpdateHudVisibility()
{
	if (!HudWidget.IsValid())
	{
		return;
	}
	const bool bCovered = IsPanelOpen(ERoamUIPanel::Garage) || IsPanelOpen(ERoamUIPanel::Map) || IsPanelOpen(ERoamUIPanel::PhotoMode) || IsPanelOpen(ERoamUIPanel::PauseMenu);
	HudWidget->SetVisibility((bHudHidden || bCovered) ? EVisibility::Collapsed : EVisibility::SelfHitTestInvisible);
}

void URoamUISubsystem::SetHudHidden(bool bHidden)
{
	bHudHidden = bHidden;
	UpdateHudVisibility();
}

// ------------------------------------------------------------------------------------------------------------------
// Generic screens
// ------------------------------------------------------------------------------------------------------------------

void URoamUISubsystem::RegisterScreen(const FRoamScreenDesc& Desc)
{
	if (Desc.Id.IsNone() || !Desc.Factory)
	{
		return;
	}
	if (FScreenEntry* Existing = Screens.Find(Desc.Id))
	{
		if (Existing->bShown && Existing->Widget.IsValid())
		{
			RemoveViewportWidget(Existing->Widget.ToSharedRef());
		}
		Screens.Remove(Desc.Id);
	}
	FScreenEntry& Entry = Screens.Add(Desc.Id);
	Entry.Desc = Desc;
}

void URoamUISubsystem::UnregisterScreen(FName Id)
{
	HideScreen(Id);
	Screens.Remove(Id);
}

bool URoamUISubsystem::IsScreenRegistered(FName Id) const
{
	return Screens.Contains(Id);
}

bool URoamUISubsystem::IsScreenShown(FName Id) const
{
	const FScreenEntry* Entry = Screens.Find(Id);
	return Entry && Entry->bShown;
}

TSharedPtr<SWidget> URoamUISubsystem::GetScreenWidget(FName Id) const
{
	const FScreenEntry* Entry = Screens.Find(Id);
	return Entry ? Entry->Widget : nullptr;
}

bool URoamUISubsystem::AnyScreenWants(bool bCursor) const
{
	for (const TPair<FName, FScreenEntry>& Pair : Screens)
	{
		if (Pair.Value.bShown && (bCursor ? Pair.Value.Desc.bShowCursor : Pair.Value.Desc.bBlocksGameplayInput))
		{
			return true;
		}
	}
	return false;
}

bool URoamUISubsystem::ShowScreen(FName Id)
{
	FScreenEntry* Entry = Screens.Find(Id);
	if (!Entry || !GEngine || !GEngine->GameViewport || !FSlateApplication::IsInitialized())
	{
		return false;
	}
	if (Entry->bShown)
	{
		return true;
	}
	if (!Entry->Widget.IsValid())
	{
		Entry->Widget = Entry->Desc.Factory();
	}
	if (!Entry->Widget.IsValid())
	{
		return false;
	}
	AddViewportWidget(Entry->Widget.ToSharedRef(), GetLayerZOrder(Entry->Desc.Layer));
	Entry->bShown = true;
	RefreshInputMode();
	UE_LOG(LogRoamUI, Log, TEXT("ROAM_SCREEN %s shown"), *Id.ToString());
	OnScreenChanged.Broadcast(Id, true);
	return true;
}

void URoamUISubsystem::HideScreen(FName Id)
{
	FScreenEntry* Entry = Screens.Find(Id);
	if (!Entry || !Entry->bShown)
	{
		return;
	}
	Entry->bShown = false;
	if (Entry->Widget.IsValid())
	{
		RemoveViewportWidget(Entry->Widget.ToSharedRef());
	}
	RefreshInputMode();
	UE_LOG(LogRoamUI, Log, TEXT("ROAM_SCREEN %s hidden"), *Id.ToString());
	OnScreenChanged.Broadcast(Id, false);
}

// ------------------------------------------------------------------------------------------------------------------
// HUD hooks (minimap, test data)
// ------------------------------------------------------------------------------------------------------------------

URoamRoadNetwork* URoamUISubsystem::ResolveRoadNetwork() const
{
	if (bTestNetwork && TestNetwork)
	{
		return TestNetwork;
	}
	URoamGameInstance* GameInstance = Cast<URoamGameInstance>(GetGameInstance());
	return GameInstance ? GameInstance->GetRoadNetwork() : nullptr;
}

void URoamUISubsystem::SetTestNetworkEnabled(bool bEnabled)
{
	bTestNetwork = bEnabled;
	if (bEnabled && !TestNetwork)
	{
		TestNetwork = URoamRoadNetwork::BuildGeneratedForTests(this, 3, 100000.0f, 500.0f);
	}
	if (HudWidget.IsValid() && HudWidget->GetMinimap().IsValid())
	{
		HudWidget->GetMinimap()->SetNetwork(nullptr);
		if (bEnabled)
		{
			HudWidget->GetMinimap()->SetNetwork(TestNetwork);
		}
	}
}

void URoamUISubsystem::SetWaypoint(const FVector& WorldCm)
{
	if (HudWidget.IsValid() && HudWidget->GetMinimap().IsValid())
	{
		HudWidget->GetMinimap()->SetWaypoint(WorldCm);
	}
}

void URoamUISubsystem::ClearWaypoint()
{
	if (HudWidget.IsValid() && HudWidget->GetMinimap().IsValid())
	{
		HudWidget->GetMinimap()->ClearWaypoint();
	}
}

void URoamUISubsystem::SetRoute(const TArray<FVector>& WorldPointsCm)
{
	if (HudWidget.IsValid() && HudWidget->GetMinimap().IsValid())
	{
		HudWidget->GetMinimap()->SetRoute(WorldPointsCm);
	}
}

void URoamUISubsystem::ClearRoute()
{
	if (HudWidget.IsValid() && HudWidget->GetMinimap().IsValid())
	{
		HudWidget->GetMinimap()->ClearRoute();
	}
}

void URoamUISubsystem::SetTestEventEnabled(bool bEnabled)
{
	if (!HudWidget.IsValid() || !HudWidget->GetNotifications().IsValid())
	{
		return;
	}
	if (!bEnabled)
	{
		HudWidget->GetNotifications()->SetEventOverride(nullptr, FText::GetEmpty());
		return;
	}
	FRoamActivityLiveInfo Info;
	Info.ActivityId = TEXT("test_drift");
	Info.Type = ERoamActivityType::DriftZone;
	Info.State = ERoamActivityState::Active;
	Info.ElapsedSec = 47.38f;
	Info.Value = 12840.0f;
	Info.StarsNow = 2;
	Info.ChainScore = 1260.0f;
	Info.Multiplier = 4;
	HudWidget->GetNotifications()->SetEventOverride(&Info, FText::FromString(TEXT("Ridgeback Drift Zone")));
}

// ------------------------------------------------------------------------------------------------------------------
// Notifications
// ------------------------------------------------------------------------------------------------------------------

int32 URoamUISubsystem::PushNotification(const FText& Title, const FText& Body, FLinearColor Color, float Seconds)
{
	FRoamNotification Notification;
	Notification.Kind = ERoamNotifyKind::Toast;
	Notification.Title = Title;
	Notification.Body = Body;
	Notification.Color = Color;
	Notification.Seconds = Seconds;
	return PushNotification(Notification);
}

int32 URoamUISubsystem::PushNotification(const FRoamNotification& Notification)
{
	FRoamNotification Stored = Notification;
	Stored.Id = NextNotificationId++;
	Stored.PushTime = FPlatformTime::Seconds();
	if (Stored.Seconds <= 0.0f)
	{
		const URoamSaveSubsystem* Save = GetGameInstance() ? GetGameInstance()->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		Stored.Seconds = Save ? Save->GetSettings().NotificationSeconds : 4.0f;
	}
	Notifications.Add(Stored);
	while (Notifications.Num() > MaxStoredNotifications)
	{
		Notifications.RemoveAt(0);
	}
	UE_LOG(LogRoamUI, Log, TEXT("ROAM_NOTIFY [%s] %s - %s (%.1fs)"), *Roam::EnumToString(Stored.Kind), *Stored.Title.ToString(), *Stored.Body.ToString(), Stored.Seconds);
	OnNotificationPushed.Broadcast(Stored);
	return Stored.Id;
}

void URoamUISubsystem::PruneNotifications()
{
	const double Now = FPlatformTime::Seconds();
	Notifications.RemoveAll([Now](const FRoamNotification& N) { return Now - N.PushTime > static_cast<double>(N.Seconds) + 0.5; });
}

TArray<FRoamNotification> URoamUISubsystem::GetActiveNotifications()
{
	PruneNotifications();
	return Notifications;
}

void URoamUISubsystem::ClearNotifications()
{
	Notifications.Reset();
}

void URoamUISubsystem::ShowRegionName(const FText& Name, const FText& Subtitle)
{
	RegionPopupName = Name;
	RegionPopupSubtitle = Subtitle;
	RegionPopupShownAt = FPlatformTime::Seconds();
	UE_LOG(LogRoamUI, Log, TEXT("ROAM_REGION_POPUP %s | %s"), *Name.ToString(), *Subtitle.ToString());
	OnRegionPopup.Broadcast(Name, Subtitle);
}

bool URoamUISubsystem::GetRegionPopup(FText& OutName, FText& OutSubtitle, double& OutShownAt) const
{
	if (RegionPopupShownAt < 0.0)
	{
		return false;
	}
	OutName = RegionPopupName;
	OutSubtitle = RegionPopupSubtitle;
	OutShownAt = RegionPopupShownAt;
	return true;
}

// ------------------------------------------------------------------------------------------------------------------
// Panels
// ------------------------------------------------------------------------------------------------------------------

bool URoamUISubsystem::IsPanelOpen(ERoamUIPanel Panel) const
{
	const int32 Index = static_cast<int32>(Panel);
	return Index >= 0 && Index < static_cast<int32>(ERoamUIPanel::Count) && bPanelOpen[Index];
}

bool URoamUISubsystem::IsAnyPanelOpen() const
{
	for (bool bOpen : bPanelOpen)
	{
		if (bOpen)
		{
			return true;
		}
	}
	return false;
}

bool URoamUISubsystem::IsGameplayInputBlocked() const
{
	return IsPanelOpen(ERoamUIPanel::Console) || IsPanelOpen(ERoamUIPanel::Garage) || IsPanelOpen(ERoamUIPanel::Map)
		|| IsPanelOpen(ERoamUIPanel::PauseMenu) || IsPanelOpen(ERoamUIPanel::PhotoMode) || AnyScreenWants(false);
}

void URoamUISubsystem::CloseAllPanels()
{
	for (ERoamUIPanel Panel : TEnumRange<ERoamUIPanel>())
	{
		SetPanelOpen(Panel, false);
	}
}

void URoamUISubsystem::SetPanelOpen(ERoamUIPanel Panel, bool bOpen)
{
	const int32 Index = static_cast<int32>(Panel);
	if (Index < 0 || Index >= static_cast<int32>(ERoamUIPanel::Count) || bPanelOpen[Index] == bOpen)
	{
		return;
	}

	// Exclusive panels replace each other.
	if (bOpen && IsExclusivePanel(Panel))
	{
		for (ERoamUIPanel Other : TEnumRange<ERoamUIPanel>())
		{
			if (Other != Panel && IsExclusivePanel(Other))
			{
				SetPanelOpen(Other, false);
			}
		}
	}

	bPanelOpen[Index] = bOpen;

	// The map and the pause menu stop the world; garage / debug / console keep it running (they are also benchmark tools).
	if (Panel == ERoamUIPanel::Map || Panel == ERoamUIPanel::PauseMenu)
	{
		if (UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr)
		{
			UGameplayStatics::SetGamePaused(World, IsPanelOpen(ERoamUIPanel::Map) || IsPanelOpen(ERoamUIPanel::PauseMenu));
		}
	}

	RefreshInputMode();
	UpdateHudVisibility();
	UE_LOG(LogRoamUI, Log, TEXT("ROAM_PANEL %s %s"), *Roam::EnumToString(Panel), bOpen ? TEXT("open") : TEXT("closed"));
	OnPanelChanged.Broadcast(Panel, bOpen);
}

void URoamUISubsystem::RefreshInputMode()
{
	APlayerController* PC = GetGameInstance() ? GetGameInstance()->GetFirstLocalPlayerController() : nullptr;
	if (!PC)
	{
		return;
	}
	if (ARoamPlayerController* RoamPC = Cast<ARoamPlayerController>(PC))
	{
		RoamPC->SetGameplayInputEnabled(!IsGameplayInputBlocked());
	}
	if (IsAnyPanelOpen() || AnyScreenWants(true))
	{
		FInputModeGameAndUI Mode;
		Mode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
		Mode.SetHideCursorDuringCapture(false);
		PC->SetInputMode(Mode);
		PC->SetShowMouseCursor(true);
	}
	else
	{
		PC->SetInputMode(FInputModeGameOnly());
		PC->SetShowMouseCursor(false);
	}
}

void URoamUISubsystem::AddViewportWidget(TSharedRef<SWidget> Widget, int32 ZOrder)
{
	if (GEngine && GEngine->GameViewport)
	{
		GEngine->GameViewport->AddViewportWidgetContent(Widget, ZOrder);
		ViewportWidgets.Add(Widget);
	}
}

void URoamUISubsystem::RemoveViewportWidget(TSharedRef<SWidget> Widget)
{
	if (GEngine && GEngine->GameViewport)
	{
		GEngine->GameViewport->RemoveViewportWidgetContent(Widget);
	}
	ViewportWidgets.Remove(Widget);
}

// ------------------------------------------------------------------------------------------------------------------
// Console commands
// ------------------------------------------------------------------------------------------------------------------

namespace
{
	bool ParsePanel(const FString& Text, ERoamUIPanel& OutPanel)
	{
		const FString T = Text.ToLower();
		if (T == TEXT("console")) { OutPanel = ERoamUIPanel::Console; return true; }
		if (T == TEXT("garage") || T == TEXT("cars")) { OutPanel = ERoamUIPanel::Garage; return true; }
		if (T == TEXT("debug") || T == TEXT("debugmenu") || T == TEXT("benchmark")) { OutPanel = ERoamUIPanel::DebugMenu; return true; }
		if (T == TEXT("map")) { OutPanel = ERoamUIPanel::Map; return true; }
		if (T == TEXT("photo") || T == TEXT("photomode")) { OutPanel = ERoamUIPanel::PhotoMode; return true; }
		if (T == TEXT("pause") || T == TEXT("pausemenu")) { OutPanel = ERoamUIPanel::PauseMenu; return true; }
		return false;
	}
}

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("ui", "ui <console|garage|debug|map|photo|pause> [on|off]", "Open, close or toggle a UI panel.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamUISubsystem* UI = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
		if (!UI)
		{
			return Ctx.Fail(TEXT("no UI subsystem"));
		}
		ERoamUIPanel Panel = ERoamUIPanel::Console;
		if (Ctx.NumArgs() == 0 || !ParsePanel(Ctx.Arg(0), Panel))
		{
			return Ctx.Fail(TEXT("usage: ui <console|garage|debug|map|photo|pause> [on|off]"));
		}
		bool bOpen = !UI->IsPanelOpen(Panel);
		if (Ctx.NumArgs() > 1 && !Ctx.GetBool(1, bOpen))
		{
			return Ctx.Fail(TEXT("usage: ui <panel> [on|off]"));
		}
		UI->SetPanelOpen(Panel, bOpen);
		return FString::Printf(TEXT("%s %s"), *Roam::EnumToString(Panel), UI->IsPanelOpen(Panel) ? TEXT("open") : TEXT("closed"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("notify", "notify <text...>", "Push a test notification to the HUD.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamUISubsystem* UI = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
		if (!UI)
		{
			return Ctx.Fail(TEXT("no UI subsystem"));
		}
		if (Ctx.NumArgs() == 0)
		{
			return Ctx.Fail(TEXT("usage: notify <text...>"));
		}
		UI->PushNotification(FText::FromString(TEXT("NOTIFICATION")), FText::FromString(Ctx.JoinFrom(0)), FLinearColor(0.133f, 0.827f, 0.933f, 1.0f));
		return FString();
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("fps", "fps [on|off]", "Show or hide the FPS counter.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		if (!Save)
		{
			return Ctx.Fail(TEXT("no save subsystem"));
		}
		bool bOn = !Save->GetSettings().bShowFps;
		if (Ctx.NumArgs() > 0 && !Ctx.GetBool(0, bOn))
		{
			return Ctx.Fail(TEXT("usage: fps [on|off]"));
		}
		Save->GetSettings().bShowFps = bOn;
		Save->MarkDirty();
		return FString::Printf(TEXT("fps counter %s"), bOn ? TEXT("on") : TEXT("off"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("speed", "speed [on|off]", "Show or hide the speedometer.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		if (!Save)
		{
			return Ctx.Fail(TEXT("no save subsystem"));
		}
		bool bOn = !Save->GetSettings().bShowSpeedometer;
		if (Ctx.NumArgs() > 0 && !Ctx.GetBool(0, bOn))
		{
			return Ctx.Fail(TEXT("usage: speed [on|off]"));
		}
		Save->GetSettings().bShowSpeedometer = bOn;
		Save->MarkDirty();
		return FString::Printf(TEXT("speedometer %s"), bOn ? TEXT("on") : TEXT("off"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("units", "units [kmh|mph]", "Switch the speed unit of the HUD.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		if (!Save)
		{
			return Ctx.Fail(TEXT("no save subsystem"));
		}
		if (Ctx.NumArgs() > 0)
		{
			const FString Unit = Ctx.Arg(0).ToLower();
			if (Unit != TEXT("kmh") && Unit != TEXT("mph"))
			{
				return Ctx.Fail(TEXT("usage: units [kmh|mph]"));
			}
			Save->GetSettings().bUseMph = (Unit == TEXT("mph"));
			Save->MarkDirty();
		}
		return FString::Printf(TEXT("units: %s"), Save->GetSettings().bUseMph ? TEXT("mph") : TEXT("km/h"));
	});

// ------------------------------------------------------------------------------------------------------------------
// HUD test / debug commands (mission B1)
// ------------------------------------------------------------------------------------------------------------------

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("ui.testnetwork", "ui.testnetwork [on|off]", "Feed the minimap a generated road network (3x3 junction grid, 1 km spacing) when no DA_RoadNetwork exists.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamUISubsystem* UI = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
		if (!UI)
		{
			return Ctx.Fail(TEXT("no UI subsystem"));
		}
		bool bOn = !UI->IsTestNetworkEnabled();
		if (Ctx.NumArgs() > 0 && !Ctx.GetBool(0, bOn))
		{
			return Ctx.Fail(TEXT("usage: ui.testnetwork [on|off]"));
		}
		UI->SetTestNetworkEnabled(bOn);
		return FString::Printf(TEXT("minimap test network %s"), bOn ? TEXT("on") : TEXT("off"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("ui.testevent", "ui.testevent [on|off]", "Show a fake drift-zone live meter in the event bar.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamUISubsystem* UI = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
		if (!UI)
		{
			return Ctx.Fail(TEXT("no UI subsystem"));
		}
		bool bOn = true;
		if (Ctx.NumArgs() > 0 && !Ctx.GetBool(0, bOn))
		{
			return Ctx.Fail(TEXT("usage: ui.testevent [on|off]"));
		}
		UI->SetTestEventEnabled(bOn);
		return FString::Printf(TEXT("test event %s"), bOn ? TEXT("on") : TEXT("off"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("ui.testnotify", "ui.testnotify", "Push four toasts (three visible, one queued), a banner and a result card.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamUISubsystem* UI = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
		if (!UI)
		{
			return Ctx.Fail(TEXT("no UI subsystem"));
		}
		UI->PushNotification(FText::FromString(TEXT("Speed trap")), FText::FromString(TEXT("Harbour Run - 187 km/h")), FLinearColor(0.133f, 0.827f, 0.933f, 1.0f));
		UI->PushNotification(FText::FromString(TEXT("XP +250")), FText::FromString(TEXT("Skill chain bonus")), FLinearColor(1.0f, 0.478f, 0.11f, 1.0f));
		UI->PushNotification(FText::FromString(TEXT("Discovery")), FText::FromString(TEXT("New road found: Cliffside Pass")), FLinearColor(1.0f, 0.698f, 0.141f, 1.0f));
		UI->PushNotification(FText::FromString(TEXT("Queued toast")), FText::FromString(TEXT("Waits for a free slot")), FLinearColor(0.7f, 0.5f, 1.0f, 1.0f));
		FRoamNotification Banner;
		Banner.Kind = ERoamNotifyKind::Banner;
		Banner.Title = FText::FromString(TEXT("Festival Opens"));
		Banner.Body = FText::FromString(TEXT("Roads are open - go explore"));
		Banner.Seconds = 5.0f;
		UI->PushNotification(Banner);
		FRoamNotification Card;
		Card.Kind = ERoamNotifyKind::ResultCard;
		Card.Title = FText::FromString(TEXT("Drift Zone Complete"));
		Card.Body = FText::FromString(TEXT("Ridgeback Drift Zone"));
		Card.Value = FText::FromString(TEXT("12,840"));
		Card.Stars = 2;
		Card.bNewBest = true;
		Card.Seconds = 6.0f;
		UI->PushNotification(Card);
		return FString();
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("ui.region", "ui.region <name...>", "Show the region-name popup.", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamUISubsystem* UI = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
		if (!UI || Ctx.NumArgs() == 0)
		{
			return Ctx.Fail(TEXT("usage: ui.region <name...>"));
		}
		UI->ShowRegionName(FText::FromString(Ctx.JoinFrom(0)), FText::FromString(TEXT("Region discovered")));
		return FString();
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("ui.hud", "ui.hud [on|off]", "Show or hide the whole HUD (saved in the profile).", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamSaveSubsystem* Save = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamSaveSubsystem>() : nullptr;
		if (!Save)
		{
			return Ctx.Fail(TEXT("no save subsystem"));
		}
		bool bOn = !Save->GetSettings().bHudVisible;
		if (Ctx.NumArgs() > 0 && !Ctx.GetBool(0, bOn))
		{
			return Ctx.Fail(TEXT("usage: ui.hud [on|off]"));
		}
		Save->GetSettings().bHudVisible = bOn;
		Save->MarkDirty();
		return FString::Printf(TEXT("hud %s"), bOn ? TEXT("on") : TEXT("off"));
	});

ROAM_REGISTER_CONSOLE_COMMAND_CATEGORY("ui.waypoint", "ui.waypoint <north_m> <east_m> | clear", "Set or clear the minimap waypoint (world metres, X north / Y east).", "ui",
	[](const FRoamConsoleContext& Ctx) -> FString
	{
		URoamUISubsystem* UI = Ctx.GameInstance ? Ctx.GameInstance->GetSubsystem<URoamUISubsystem>() : nullptr;
		if (!UI)
		{
			return Ctx.Fail(TEXT("no UI subsystem"));
		}
		float North = 0.0f;
		float East = 0.0f;
		if (Ctx.NumArgs() == 1 && Ctx.Arg(0).ToLower() == TEXT("clear"))
		{
			UI->ClearWaypoint();
			return TEXT("waypoint cleared");
		}
		if (Ctx.NumArgs() < 2 || !Ctx.GetFloat(0, North) || !Ctx.GetFloat(1, East))
		{
			return Ctx.Fail(TEXT("usage: ui.waypoint <north_m> <east_m> | clear"));
		}
		UI->SetWaypoint(FVector(North * 100.0f, East * 100.0f, 0.0f));
		return FString::Printf(TEXT("waypoint at %.0f N, %.0f E"), North, East);
	});
