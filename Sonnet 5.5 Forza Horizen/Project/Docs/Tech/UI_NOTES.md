# UI notes (Slate HUD, minimap, notifications, screens)

Mission B1. All UI is C++ Slate, no Blueprint/UMG assets. Look: dark glass panels, festival orange (`RoamUI::Color::Orange`) and lagoon teal accents, engine Roboto. All sizes are **1080p units**: the viewport DPI scale makes them grow with the resolution (a 4K capture is simply 2x).

## What exists

| File | What |
|---|---|
| `UI/RoamUIStyle.*` | namespace `RoamUI`: `Layer::*` z-orders, `Layout::*` numbers, `Color::*`, `Font()`, `Brushes::*`, **pure logic** in `RoamUI::Logic` (safe area, unit conversion, tach segments, minimap transform and circle clipping, polyline simplification, popup/toast envelopes, `FNotificationChannel` queue, wrong-way test) and paint helpers (`DrawBox`, `DrawRotatedBox`, `PaintText`, `DrawPolygon`). Unit tested in `Tests/RoamUITests.cpp` (`Roam.UI.*`). |
| `UI/SRoamHud.*` | root widget (z 100): places the cluster bottom-right and the minimap bottom-left inside the 5 percent safe area, plus `SRoamHudInfo` (world strip above the minimap: clock + weather icon + temperature label, camera-mode chip that fades 3 s after a change, FPS counter, WRONG WAY hint) and `SRoamNotifications`. |
| `UI/SRoamSpeedCluster.*` | 480 x 200: 3-cell tabular speed (104 px, dim leading zeros, km/h or mph), 48-segment tach arc (teal / amber from 78 percent / red from 90 percent, limiter flash), gear box, `SHIFT` cue (manual gearbox) and `LIMIT` cue, rpm readout, surface name, ABS/TCS/STM lamps (flash while the assist intervenes), G chip, boost bar when the car has a turbo. Pulls `ARoamVehicle::GetTelemetry()` once per tick. |
| `UI/SRoamMinimap.*` | 264 px heading-up vector minimap. `FRoamMinimapCache` flattens + simplifies (Douglas-Peucker 2.5 m) every road of `URoamRoadNetwork` **once**, sorted by class draw order. Per frame: cull polylines by bounds, transform, clip to the circle on the CPU, one `MakeLines` per visible run. View radius 350 m -> 900 m with speed (smoothed), player arrow 18 percent behind the centre, north marker, scale bar, waypoint marker (clamped to the rim), GPS route polyline. |
| `UI/SRoamNotifications.*` | full-screen click-through painter: region popup (top-left 560 x 88, 350 ms in / 2.8 s hold / 400 ms out), activity event bar (top-centre 640 x 84, fed by `URoamActivitySubsystem::GetLiveInfo()`), toast stack (top-right, 3 slots of 440 x 72, extra toasts wait in a queue), banner (upper third), result card (centre: stars, value, NEW BEST). |
| `UI/RoamUISubsystem.*` | owner of widgets and UI state (see API below). `CreateWidgets()` builds `SRoamHud` and calls `RoamRegisterMenuScreens(this)` (console overlay, garage, debug menu, pause; idempotent, B2). |

Data flow: widgets **pull** (vehicle telemetry, `URoamTimeWeatherSubsystem`, `URoamActivitySubsystem`, `URoamSaveSubsystem` settings) or listen to subsystem delegates (`OnNotificationPushed`, `OnRegionPopup`). Nothing pushes into widgets. The region popup is triggered by `URoamRegionSubsystem` through `URoamUISubsystem::ShowRegionName` (80 m hysteresis and the cooldown are there). The canvas shell `ARoamHUD::DrawHUD` is debug text only and is off (`bShowHudShellDebugText=False` in `Config/DefaultGame.ini`).

## API of `URoamUISubsystem` (all previous members unchanged)

* Notifications: `PushNotification(Title, Body, Color, Seconds)` or the `FRoamNotification` overload (`Kind` Toast / Banner / ResultCard, `Stars`, `Value`, `bNewBest`). Activities already call it.
* Panels (enum, existing): `SetPanelOpen / IsPanelOpen / TogglePanel / CloseAllPanels / IsGameplayInputBlocked / OnPanelChanged`. Garage, map, photo and pause hide the HUD layer automatically (`UpdateHudVisibility`).
* **Generic screens (new):** `RegisterScreen(FRoamScreenDesc)`, `ShowScreen / HideScreen / ToggleScreen / IsScreenShown / GetScreenWidget / UnregisterScreen`, `OnScreenChanged`.
* Layers: `ERoamUILayer::{Hud, Overlay, Modal}` -> z 100 / 640 / 800 (`GetLayerZOrder`); the menus of B2 keep their own z values 640..1000, the console is topmost.
* Minimap hooks: `SetWaypoint(FVector cm) / ClearWaypoint()`, `SetRoute(TArray<FVector> cm) / ClearRoute()` (feed it `URoamRoadNetwork::BuildRoutePolyline`), `ResolveRoadNetwork()`.
* Test hooks: `SetTestNetworkEnabled`, `SetTestEventEnabled`, `SetHudHidden`.

### How a new screen registers (full map, photo overlay, settings ...)

```cpp
FRoamScreenDesc Desc;
Desc.Id = TEXT("FullMap");
Desc.Layer = ERoamUILayer::Modal;          // z 800
Desc.bBlocksGameplayInput = true;           // IsGameplayInputBlocked() while shown
Desc.bShowCursor = true;                    // game-and-UI input mode + cursor while shown
Desc.Factory = [UI]() -> TSharedRef<SWidget> { return SNew(SRoamMapScreen, UI); };
UI->RegisterScreen(Desc);                   // once (e.g. from a ticker like RoamMenus.cpp, or from CreateWidgets)
UI->ToggleScreen(TEXT("FullMap"));          // from a key binding / console command
```

The factory runs on the first `ShowScreen`; the widget is cached until the HUD ends (level change), registrations persist. Pausing the game is not part of the generic screens: use `SetPanelOpen(ERoamUIPanel::Map, true)` for that (it pauses and hides the HUD). Use the helpers of `RoamUIStyle.h` (`DrawBox`, `PaintText`, `Logic::ComputeSafeArea`, `Color::*`) to stay in the same look. Slate pitfalls found here:

* **Outline brushes are not tinted.** `FSlateRoundedBoxBrush` fills follow the element tint, its outline colour does not (and a transparent-fill ring brush renders as a filled disc). Draw a ring as a larger disc under a smaller opaque disc, or use the panel brush whose outline is a constant 9 percent white.
* **Elements in one layer are drawn in insertion order**, but give logical groups their own layer ids (`LayerId + n`) and return the highest one.
* `HighResShot` does **not** capture Slate; use `Screenshot showui` (via `roam ue Screenshot showui`).
* Text: font size is in pixels at DPI scale 1 (104 px digits = `Font(104, true)`).
* `FSlateDrawElement::MakeLines` takes its point array by value (one small allocation per visible polyline run per frame); everything else in the HUD (rotated boxes, boxes, custom-vertex polygons with reused arrays) allocates nothing per frame except the text strings Slate copies.

## Console commands

`ui <console|garage|debug|map|photo|pause> [on|off]`, `notify <text>`, `fps`, `speed`, `units [kmh|mph]` (existing) and new: `ui.hud [on|off]`, `ui.testnetwork [on|off]` (generated 3 x 3 junction grid, 1 km spacing, when no `DA_RoadNetwork` exists), `ui.testevent [on|off]` (fake drift live meter), `ui.testnotify` (4 toasts, banner, result card), `ui.region <name>`, `ui.waypoint <north_m> <east_m> | clear`.

## Verification recipe (screenshots with the Slate UI)

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue_cmd.ps1 -Game -Map /Game/Forza/Maps/L_Test -ResX 1920 -ResY 1080 -LogName hud ^
  -ExecCmds "roam ui.testnetwork on, roam delay 2 drive 0.8 0.12, roam delay 2.5 ui.region Sunset Coast, roam delay 2.5 ui.testevent on, roam delay 3 ui.testnotify, roam delay 5.5 ue Screenshot showui, roam delay 9 ue Quit"
```

Screenshots land in `Saved/Screenshots/WindowsEditor/ScreenShot*.png`. Automation: `Automation RunTests Roam.UI` (layout/units, minimap math, minimap cache, notification queue and animation phases).

## Known gaps

No full-screen map, photo overlay or settings screen yet (they plug into `RegisterScreen`); no discovered/undiscovered road colouring and no baked minimap underlay; the GPS route is only a hook (`SetRoute`), nothing computes routes yet; the temperature label is a stylised value from daylight and weather (the time/weather model has no temperature); off-road hint is not implemented (wrong-way is).
