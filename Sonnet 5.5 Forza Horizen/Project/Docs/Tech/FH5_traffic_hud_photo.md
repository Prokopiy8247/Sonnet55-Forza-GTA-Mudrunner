# FH5 reference research: traffic, ambient life, HUD, minimap, GPS, map, photo mode

Scope: Forza Horizon 5 is used only as a mechanics / structure / feature-scope reference. Everything under "Original design" is
this project's own layout and numbers, written for a 4 km x 4 km UE 5.8 world with 40-60 km of rural roads and
code-generated assets. No Forza artwork, icons, fonts or exact layouts are reproduced.

Confidence tags used below:
- [V] stated by a source that was actually read (source id in brackets, list at the end)
- [S] only seen in a search-result snippet, page not fully read (lower confidence)
- [E] verified in the local engine install (W:\Unreal Engine 5\UE_5.8, headers read directly)
- [I] my inference / engineering recommendation, NOT a claim about FH5
- [?] sources conflict or nothing found

IMPORTANT HONESTY NOTE: official material on FH5 traffic behaviour, minimap geometry, GPS line colour and region popups is
almost nonexistent. Playground has not published numbers for any of it. All traffic speeds, distances, densities and all
screen geometry below are [I] design values chosen to be sensible for this project, informed by real-road norms and by
the few FH5 facts that are verifiable. Do not present them as "how FH5 does it".

---

## 1. What FH5 verifiably does (facts only)

### 1.1 HUD options and conventions
- HUD & Gameplay menu has an analogue-or-digital speedometer choice, metric/US units, separate power and spring units. [V S3]
- Per-element HUD on/off switches: map, lap time and position, wrong-way warning, names over cars, ghosts, skills, notifications,
  online-event, convoy/achievement notifications, Drivatar/player designs, the assistant ("Anna"), Forza Link. [V S3]
- Skill-point popups appear in the centre of the screen; they can be hidden and points still accrue. [V S5]
- Notifications (XP gains, newly found roads) can be toggled per type; a notification-duration setting exists in Accessibility. [V S3, S5]
- Text size can scale up to 150 %; subtitles have size, background opacity and keyword-bold options; colour-blind and high-contrast
  modes exist, with separate deuteranopia / protanopia / tritanopia sliders. [V S3]
- GPS voice has on/off and a volume slider (Audio menu). Navigation is on by default and warns of turns. [V S3, S]
- Driving line has three modes: off / always / braking-only. Colours: sources disagree. One says green = keep speed, yellow = ease off,
  red = brake hard [V ludo.guide]; another says blue = fast, yellow = slow, red = stop [V S5]; a third says blue = can take the turn,
  orange/red = too fast [S]. Net: three-state traffic-light semantics, hue unreliable. [?]
- On-road braking arrows change colour when you brake at the right moment. [V S7]
- A review reported that the waypoint trail was hard to tell apart from the road colour (colour-blind issue). [S]
  Lesson for us: route line must differ from asphalt in luminance, not only hue.

### 1.2 Map, minimap, discovery, fast travel
- Roads you have not driven are shown orange on both map and minimap; driving a new road gives 50 XP and a notification.
  A brief pass through an intersection did not seem to count. [V S4] A guide counts 578 roads to discover in the base game. [S]
- XP signs appear on the minimap when you are near them. [V S7]
- Full map: a filter menu (right shoulder on Xbox) lists many icon types; the top checkbox clears everything so you can re-enable
  only what you want; completed event icons stay on the map and overlap, causing clutter. [V S4, criticalhits]
  A forum user complained filters reset on every boot. [S] -> we should persist them.
- Fast travel costs credits (about 9-10k at the start); each smashed Fast Travel board lowers the price by 200 credits, all 50 make it
  free; board icons are purple until smashed, then grey; "Go to Home" is free. [V S4, S8]
- Player houses unlock rewards including fast travel. [V S9]
- The map is about 50 % larger than FH4, with 11 biomes; weather is local per region, so storm and clear sky coexist; four seasons. [V S9, S10, S11]
- GPS can lead to a board that sits on a rooftop or under a bridge, so route targets in 3D matter. [V S4]

### 1.3 Activities (PR Stunts) and skills (relevant to toasts / HUD)
- Speed trap = single beam, measures instantaneous speed. Speed zone = two beams, average speed over the stretch (braking before a corner
  hurts). Danger sign = ramp, measures airborne distance. Drift zone = points score for a marked section (angle x speed x chain length).
  Up to 3 stars each, replayable. [V S12]
- 3-star targets observed: speed traps 100-270 mph (typical 135-225); speed zones 70-175 mph averages; danger signs 91-533 m (median
  about 308 m); drift zones 30k-500k points (median about 115k). 1- and 2-star thresholds are not published. [V S12]
- Skill chain: actions (drift, near miss, smashing) start a chain and raise a multiplier; a crash ends the chain; waiting too long
  resets the multiplier. [V pcinvasion/insider-gaming via search, S]

### 1.4 Ambient life
- Pre-release statements claimed the widest wildlife variety of any Forza; named animals include goats, donkeys, bighorn sheep, flamingos, wild dogs;
  players also report chickens, rams, a dog in a jungle village, seagulls on the coast. [V S10, S] Wildlife is tied to biomes
  (Living Desert wildlife and flowers, Farmland animals to spot, Tropical Coast seagulls). [V S11]
- Hot-air balloons hang over the festival; a cargo plane drops cars in the opening; Horizon Arcade has cargo-plane pinata drops. [S, V S9]
- Players describe fewer civilian cars than FH4, thinning at night and almost empty mountain/desert roads; few pedestrians. [S GTPlanet]
- No in-game switch to disable civilian traffic was found (low-quality source). [?]
- Playground built the world "from the driver's perspective" and used Street View for small lived-in details (porches, benches,
  bikes). [V S14] This supports our approach: ambient detail concentrated at roadside, not deep interiors.

### 1.5 Photo mode
- Enter: D-pad up (Xbox) / P (PC) or pause menu; hide HUD with the View button; A takes the photo (watermark in a corner) and a photo
  is only kept once you go through the naming step. [S Digital Trends/GameSpew/Steam, V S13]
- Sticks move the camera, triggers raise/lower it; focal distance adjustable. [V S13]
- Update 21 (2023) added: time of day, weather, wheel angle, composition guidelines, character position and emotes, presets, portrait
  mode, "Manage Presets" in Effects. [V S2, S1]
- Time-of-day options run Default, Dawn, Sunrise, Morning ... Night; weather from clear to fog. [S]
- Official Turn 10 guide values (their own 0-100-style sliders, not physical units): zoom 1.4-2.5x keeps the car sharp, about 1.7x looks
  realistic, 0.5-1x gives fisheye stretch; aperture 7-13 realistic (below 7 background stays sharp, above 13 toy-model blur);
  bokeh "Diamond"; shutter 15 baseline, up to 20 for a rolling shot; exposure 50 (check you can tell tyre from rear fender);
  brightness/contrast/saturation/temperature 50; sepia and vignette 0; focus 0; sampling Quality; let the image finish rendering
  before saving. [V S1]
- Focus modes Tracking (follow subject) and Panning (blur background at speed); focus point set with a button. [S Prima]

---

## 2. Original design: traffic

### 2.1 Architecture (C++, no per-actor tick)
- `UTrafficSubsystem` (UTickableWorldSubsystem) owns a `FTrafficLaneGraph` built once at BeginPlay from the road splines, a struct-of-arrays
  `TArray<FTrafficAgent>` (not UObjects), and a pool of `ATrafficVehicle` visual actors. [I]
- Lane graph: node = lane start/end/junction, edge = lane polyline sampled every 5 m, with per-sample precomputed curvature, corner-speed
  cap, road class, posted limit, tunnel/bridge flag. Direction of travel is baked (right-hand traffic default, `bRightHandTraffic`). [I]
- Do NOT use Mass/MassTraffic. [E] Engine ships MassGameplay, MassAI (MassZoneGraphNavigation), MassCrowd and ZoneGraph, but there is
  no MassTraffic plugin in the engine (it lives in the CitySample project). ZoneGraph provides lane tags, links and query functions
  (`FindNearestLane`, `FindLaneOverlaps`, `AdvanceLaneLocation`, `GetLinkedLanes`, `FZoneGraphTagFilter`), but it needs ZoneShape authoring
  actors and Mass entity setup; for a few dozen agents on code-generated splines a custom lane graph is simpler and fully deterministic.
  Steal the ideas (lane tags, lane links, advance-along-lane) not the dependency.
- Car-following: Intelligent Driver Model (IDM). a = A * (1 - (v/v0)^4 - (s*/s)^2), s* = s0 + v*T + v*dv / (2*sqrt(A*B)). Clamp dt to 0.05 s. [I]
- Lateral: lane-centre offset with low-pass noise (+/-0.2 m, 0.3 Hz) so lines are not perfectly rigid. [I]
- Corner speed: vc = sqrt(a_lat / |kappa|), a_lat 3.0 m/s2 cars, 2.0 trucks/buses, 1.2 tractors; look-ahead braking
  v_allowed(d) = sqrt(vc^2 + 2*b_c*d) with b_c = 2.5 m/s2. [I]

### 2.2 Simulation LOD and ring management (distances are for a player doing up to about 250 km/h = 70 m/s)
| Ring (distance from player) | Representation | Notes |
|---|---|---|
| 0-120 m | Actor + collision body, kinematic-driven (physics on contact) | Chaos kinematic body moved with ETeleportType::None so impacts get velocity; on first strong hit (relative speed > 15 km/h) switch to SimulatePhysics with last velocity |
| 120-450 m | Actor, mesh LOD1/2, no collision (query-off), transform driven at 30 Hz and interpolated | No wheel physics, wheels rotate by v/r |
| 450-900 m | Data only (agent struct), IDM at 10 Hz | No actor, no mesh |
| > 900 m | Removed | |
- Spawn ring: 500-750 m from the player along lanes in front of and beside the player's travel direction (closing speed with oncoming
  traffic at 250 km/h plus a 70 km/h car = 89 m/s -> 750 m gives 8.4 s warning). Never spawn inside the camera frustum within 400 m. [I]
- Despawn: > 900 m, or behind the player and > 450 m and not visible. Hysteresis band 150 m so agents do not flicker. Recycle agents that fall
  behind into new slots ahead instead of destroying actors (pooling). [I]
- Budgets: max 40 live agents, max 24 pooled actors, max 2 spawns per frame, spawn pass every 0.25 s. [I]
- Gap rule at spawn: free space to the next agent in the lane >= 1.5 x (s0 + v*T) of the new agent. [I]

### 2.3 Speeds per road class (km/h)
| Road class | Posted | Cruise target for cars | Notes |
|---|---|---|---|
| Highway (2 lanes each way or wide 2-lane) | 110 | 90-110 | trucks 70-80 |
| Valley / secondary | 80 | 60-80 | tractors allowed 20-25 |
| Coastal | 70 | 55-70 | |
| Mountain pass | 50 | 35-50 | curvature cap dominates |
| Dirt / gravel | 40 | 25-40 | pickups 35-45, tractors 20-25 |
| Village street | 30 | 20-30 | parked cars on kerb |
| Bridges / tunnels | parent class | parent class | no overtaking; headlights on in tunnels |
- Per-driver factor ~ N(1.0, 0.07) clamped 0.85-1.10 multiplies the cruise target. [I]
- Weather: rain x0.85 speed, fog x0.75, night x0.9; headlights on at sun elevation < 3 degrees or in rain/fog/tunnel. [I]

### 2.4 Following distance and vehicle parameters
| Type | Length | Time headway T | Min gap s0 | Accel A | Comfort decel B | Max speed |
|---|---|---|---|---|---|---|
| Compact / sedan / hatch | 4.0-4.6 m | 1.3-1.7 s | 2.5 m | 2.0 m/s2 | 3.0 | by class |
| Pickup | 5.3 m | 1.5 s | 3 m | 1.8 | 3.0 | by class |
| Van | 5.5 m | 1.6 s | 3 m | 1.5 | 2.8 | 100 |
| Bus | 11 m | 2.0 s | 5 m | 1.0 | 2.2 | 80 |
| Lorry | 9-12 m | 2.0 s | 5 m | 0.9 | 2.2 | 80 |
| Tractor | 5 m | 1.2 s | 3 m | 0.6 | 2.0 | 25 (farm, dirt, valley only) |
- Emergency braking 8 m/s2. At 100 km/h a 1.5 s headway gives about 45 m gap. [I]
- Type mix: highway 55 % cars, 15 % vans/pickups, 25 % lorries/buses, 5 % other; valley 60 % cars, 20 % pickups/vans, 10 % tractors,
  10 % lorries; mountain 70 % cars, 20 % pickups, 10 % vans; dirt 50 % pickups, 30 % tractors, 20 % cars. [I]
- Lane width: highway 3.65 m, secondary 3.4 m, mountain 3.0 m, dirt 5.5-6 m shared two-way, village 3.0 m. [I]

### 2.5 Density (vehicles per km per direction, daytime) and time multipliers
| Class | veh/km/dir |
|---|---|
| Highway | 3.5 |
| Valley / secondary | 2.5 |
| Coastal | 2.0 |
| Mountain | 1.2 |
| Dirt | 0.4 |
| Village (moving) + parked | 4 + 6 parked/km |
- Time-of-day multiplier: 22:00-05:00 x0.35; 05:00-06:30 x0.6; 06:30-09:00 x1.15; 09:00-16:30 x1.0; 16:30-19:00 x1.2; 19:00-22:00 x0.7. [I]
- Console `traffic <0..1>` multiplies all densities; 0 stops spawning and lets existing agents despawn only out of view. [I]
- Feel check at 200 km/h on highway: oncoming car every 1000/3.5 = 286 m / (55.6+28 m/s) = about 3.4 s; same-direction overtakes every
  about 10 s. About 4.8 km of road lies inside a 700 m radius, so about 25 live agents (cap 40). Mountain: oncoming every about 9 s. [I]
- FH5 anecdotes agree with "thin at night, rare in mountains/desert" [S]; the project prompt requires roads neither empty nor crowded, so
  tune with the 3.4 s / 10 s rule above and expose the numbers in a `TrafficSettings` DataAsset.

### 2.6 Behaviour toward the player and events
- The player is a leader candidate if within the agent's lane corridor (lateral < half lane + 0.9 m) ahead within 80 m and closing. [I]
- Oncoming-lane protection: if the player is in the wrong lane, closing, TTC < 3 s, the agent drifts up to 0.8 m toward the shoulder and
  brakes about 30 %. Horn + flash when the player tailgates < 8 m for 1.5 s. [I]
- Near miss event for the skill system: lateral gap < 1.2 m with combined speed > 80 km/h; emit `OnNearMiss(agent, gap, speed)`. [I]
- Collision: hazard lights on, stopped 3 s after rest, despawn after 15-25 s when out of view; cap of 6 wrecks alive. [I]
- Junctions: one reservation token per junction (one conflicting movement at a time), 6 s timeout, minor road yields, stop line decel 2.5 m/s2,
  yield if the player's predicted arrival < 2.5 s. [I]
- Overtaking (stretch): only when the leader is slower than 60 % of desired speed for > 8 s, sight distance > 250 m, no oncoming within a
  12 s horizon, not on bridge/tunnel/junction. [I]
- During activities (speed zones/races) either fade traffic out in a 200 m corridor ahead of the player on the event route or reduce
  density to 30 %. [I]

### 2.7 Ambient life (original)
| Element | Behaviour | Budget |
|---|---|---|
| Livestock (sheep, goats, cattle) | 6-12 per pasture, idle/graze, flee 8-15 m from the road when a car passes at > 30 km/h; non-colliding, never gory | instanced meshes + vertex-animation or simple skeletal, update only < 120 m |
| Birds (crows, gulls on coast) | flock of 5-20, scatter when car < 25 m and > 50 km/h, regroup after 20 s | Niagara or HISM, < 100 live |
| Roadside wildlife crossing (deer-like) | rare, only mountain/forest, signposted, crosses only when player > 80 m away and path clear | max 1 live |
| Hot-air balloons | 3-5 at 150-400 m altitude, drift 1-2 m/s, visible from far | 5 actors |
| Aircraft | high contrail + occasional light plane 150 m AGL with Doppler audio | 1 live |
| Settlement dressing | parked cars, washing lines, a few static figures at event gates, tents/flags | static |
| Spectators at event gates | SKIP in v1; use tents, banners, flags instead | none |
- All driven by an `UAmbientLifeSubsystem` ticking at 10 Hz over 250 m grid cells, not by actors ticking. [I]

---

## 3. Original design: HUD (reference frame 1920 x 1080, scale by min(w/1920, h/1080))

Safe area: 96 px (5 %) left/right, 54 px (5 %) top/bottom. Design for a 1080p YouTube recording: primary info >= 22 px, nothing under
16 px, 2 px dark shadow behind all text.

### 3.1 Style tokens (original)
| Token | Hex | Use |
|---|---|---|
| Asphalt Ink | #0D131A at 72 % | panels, 1 px Chalk at 16 % border, 12 px chamfer on top-left corner only |
| Chalk | #F1F4F6 | primary text |
| Mist | #9AA9B5 | secondary text |
| Beacon Cyan | #22D3EE | navigation, route line, waypoint |
| Amber Flag | #FFB224 | score, rewards, personal best |
| Brake Coral | #FF5A4D | danger, redline, wrong-way |
| Moss Go | #5BD98A | success, good speed |
| Event Violet | #A98BFF | activities / events |
| Road Sand | #D6B77A | dirt roads on map |
| Water Slate | #2B4A63 | water on map |
- Fonts (engine ships Roboto, [E] Engine/Content/Slate/Fonts has Black, Bold, BoldCondensed, Medium, Regular, Light): numerals Roboto Black (tabular
  digits so speed does not jitter), labels Roboto BoldCondensed uppercase with about +6 % tracking, body Roboto Medium. Sizes at 1080p:
  display 104, h1 40, h2 28, body 22, caption 18. Verify the `FCoreStyle::GetDefaultFontStyle` typeface names in the project before relying
  on "BoldCondensed" being addressable. [I]
- Never encode state by hue alone: add shape/pattern/position (chevron density, dash pattern, icon) and keep luminance contrast. Provide a
  colour-vision preset that swaps Coral/Moss for blue/orange pairs. [I]

### 3.2 Regions (px and % of 1080p)
| Region | Rect | Size | Contents |
|---|---|---|---|
| Speed cluster, bottom-right | x 1344-1824, y 826-1026 | 480 x 200 (25 % x 18.5 %) | speed 104 px right-aligned, unit caption, gear box 84 x 84 with 64 px glyph, tach bar 440 x 12 with 48 segments (amber from 80 %, coral from 92 %, flash 6 Hz at limiter), assist chips (ABS, TCS, STM) 40 x 22, surface icon; analogue option = 300 px dial with 270 deg sweep |
| Minimap, bottom-left | circle diameter 264, centre (228, 894) | 24.4 % of height | see section 4 |
| Event bar, top-centre | x 640-1280, y 54-138 | 640 x 84 (33 % x 7.8 %) | timer 56 px, checkpoint n/m, position, hidden outside events |
| Region popup, top-left | x 96-656, y 54-142 | 560 x 88 | region name 44 px caps, subtitle 20 px |
| Status, top-right | x 1464-1824, y 54-98 | 360 x 44 | clock/time-of-day, weather icon, credits or XP |
| Toast stack, left | x 96-536, from y 170 | 440 x 72 each, 10 px gap, max 3 | notifications |
| Skill ticker, centre-low | x 600-1320, y 700-820 | 720 x 120 (37.5 % x 11 %) | skill name 28 px, chain total 64 px, multiplier chip, chain timer bar 320 x 8 |
| Warnings, centre-top | x 700-1220, y 200-264 | 520 x 64 | wrong way (chevron + text, 2 Hz pulse), off-road, low-visibility |
| Prompt bar, bottom-centre | 520 x 40 above bottom safe edge | | context hints ("Hold M: map") |
| Result card, centre | 640 x 260 around y 300-560, 2.6 s | | speed trap / zone / drift / jump result with 3 stars |
| World-space | | | waypoint beacon, event gates, route line, driving line, danger-sign labels |

### 3.3 Timing and behaviour
- Toast: slide-in 180 ms ease-out, hold 4.0 s (user range 2-10 s, as FH5 exposes a duration option), fade 220 ms; priorities info < reward <
  warning; warning may bump the oldest toast; per-category on/off toggles (road discovered, skills, events, system). [I, FH5 parity V S3]
- Region popup: crossing a region boundary with 80 m hysteresis and a 20 s per-region cooldown; 350 ms in, 2.8 s hold, 400 ms out;
  suppressed during result cards. No FH5 source describes its own popup, so this is purely original. [I]
- Skill ticker: chain window 4.0 s after the last skill; multiplier +1 per distinct skill within the chain up to x8; chain banks on timeout;
  an impact with delta-v > 25 km/h cancels the chain (red "CHAIN LOST" flash 0.6 s). Skills: drift (angle x speed), near miss, speed burst
  (> 160 km/h for 1 s), air time (> 0.6 s), clean slipstream behind traffic. FH5 parity: chain, multiplier, crash-ends-chain. [V S, I numbers]
- Speed text updated at 30 Hz, not every frame; static panels wrapped in an Invalidation Box. [I]
- HUD master toggle plus per-element toggles stored in the save game (parity with FH5 per-element HUD toggles). [V S3]

### 3.4 Result-card targets (scaled to this world; 1/2/3 stars at 60/80/100 % of target, since FH5 does not publish those)
- Speed trap: 3-star 140-260 km/h (FH5: 100-270 mph, so we compress for slower cars). Speed zone: average 90-180 km/h over 0.8-2.5 km.
- Danger sign: 60-220 m airborne. Drift zone: 8,000-60,000 points over 150-400 m. [I]

---

## 4. Original design: minimap

- Shape: circle, 264 px, 4 px Chalk ring at 80 %, soft 12 px shadow, rim ticks every 90 degrees with an "N". Circular fits a heading-up map.
- Mode: heading-up (default) or north-up option; heading smoothed with tau 0.15 s; below 5 km/h freeze rotation to avoid spinning when parked.
- View radius at the rim: 350 m at 0 km/h rising to 900 m at 200 km/h (smoothed tau 0.6 s). Manual override levels 250 / 500 / 1000 m.
  Player marker sits 18 % of radius behind centre so more of the road ahead is visible. FH5 zoom behaviour is not documented. [I]
- Content stack, bottom to top: baked terrain underlay (hillshade + water + vegetation tint, 1024 x 1024 for the whole 4 km = 3.9 m/px), road
  casing, roads by class (highway 6 px light, secondary 4 px, mountain 4 px, dirt 3 px dashed Road Sand), discovered-state tint (undiscovered
  roads warm amber, driven roads neutral; mirrors the FH5 orange-undiscovered convention [V S4]), route line (Beacon Cyan 5 px with chevrons),
  POI icons 16-20 px inside 70 % radius, objective/waypoint diamond clamped to the rim, player arrow, ring.
- Nearby collectibles/XP-style items appear only within 150 m (FH5 shows XP signs when near [V S7]).
- Road discovery (stretch): split roads into segments of about 600 m; mark discovered at >= 60 % driven; toast "Road discovered +50 XP"
  (FH5 gives 50 XP per new road [V S4]); persist in save game; show total percentage on map.
- Implementation (preferred): a custom Slate/UMG widget `SRoadMapCanvas`. Roads are pre-baked world-space polylines stored in a subsystem with a
  128 m spatial hash; each frame cull to the view circle, clip segments against the circle, transform and call
  `FSlateDrawElement::MakeLines`. [E] In 5.8 `MakeLines` lives in DrawElementTypes.h and takes `TArray<FVector2f>` (by value) or
  `const TArray<FVector2d>&` plus a `FPaintGeometry`; reuse a scratch array. Typically < 400 segments per frame. Underlay = one brush with an MID
  (UV offset/rotation/scale) and a radial mask.
- Coordinate pitfall: UE is left-handed with X forward, Y right. For heading-up, map_x = dot(d, right), map_y = -dot(d, forward), d = world - player. [I]
- Rejected: SceneCapture2D top-down for the live minimap. It re-renders the scene (community guidance: disable CaptureEveryFrame / CaptureOnMovement,
  use 512 x 512, lighting off) and still costs more than vector drawing. [S] [E] Properties exist: `bCaptureEveryFrame`, `bCaptureOnMovement`,
  `CaptureSource` (`SCS_BaseColor` etc.), `OrthoWidth`, `ShowFlagSettings`. Use SceneCapture only once, in the editor, to bake the underlay if no
  procedural source exists.

---

## 5. Original design: full map and fast travel

- Screen: pauses the game (activatable widget on a Common UI stack). 4 km fits at 4.3 m/px on a 920 px tall panel; zoom steps 1x / 2x / 4x;
  left stick or mouse-drag pans, triggers/wheel zoom, cursor snaps to nearest POI within 24 px. [I]
- Layers: terrain underlay, roads (same canvas as minimap), region labels (visible when zoomed out), icons, route line, player arrow, waypoint pin.
- Filters (FH5 parity [V S4]): panel opened by a shoulder button / F; first checkbox "All" toggles everything; categories: Races, Time trials,
  Speed traps, Speed zones, Drift zones, Danger signs, Collectibles, Photo spots, Settlements and fuel, Garage, Fast-travel points. Persist the state
  in the save game (FH5 players complained it resets [S]). Completed icons dim to grey instead of disappearing (FH5 keeps them, causing clutter;
  grey + filter "hide completed" solves it). [I]
- Waypoint: place with A / left click, press again to clear; pin snaps to the nearest road within 40 m; shows distance and ETA at about 80 % of
  current speed; one waypoint at a time. [I]
- Fast travel: free to garage/home and to discovered settlement hubs for v1 (FH5 charges credits and makes "Go to Home" free [V S4, S8]). A credit
  cost scaled by distance can be added with the economy stretch. Sequence: fade out 0.4 s -> teleport, set `bIsFastTraveling` -> wait until World
  Partition streaming around the target completes -> place on road facing lane direction with speed 0 -> fade in. Share the code with the console
  command `tp <region|poi>`. [I]

---

## 6. Original design: waypoint / GPS navigation

- Routing: A* on the road graph (nodes at junctions and road ends). Edge cost = length / classFactor (highway 1.0, secondary 0.8, coastal 0.75,
  mountain 0.55, dirt 0.4) + 15 m penalty per turn. Recompute when off route > 35 m for 1.5 s, throttled to 2 Hz. [I]
- In-world route line: one dynamic mesh ribbon (UDynamicMeshComponent or procedural mesh) along the next 450 m of the route, 1.4 m wide,
  lifted 0.12 m (use a material depth bias / world-position offset so it does not z-fight the road), unlit emissive Beacon Cyan with white
  chevrons scrolling at 12 m/s, dark 0.15 m edge outline for contrast, fades out below 8 m and beyond 450 m. Rebuild when the player advances
  25 m. At junctions only the chosen branch is drawn; turn arrow decal 120 m before a turn. [I]
- Destination: thin vertical beam 80 m tall, diamond with distance label, drawn always-on-top when > 200 m away; clamps to a screen-edge arrow
  when off-screen. Auto-clear within 40 m with an "Arrived" toast. [I]
- Colour rules: route line must differ from asphalt by luminance (cyan about 0.55 vs asphalt 0.05-0.10) because FH5 reviewers flagged the trail hard to
  distinguish. [S]
- Racing / corner-assist line (three modes like FH5: off / always / braking-only [V ludo.guide, S3]): fixed to three states with distinct patterns
  as well as colour: sustain = solid Moss Go, ease off = dashed Amber Flag, brake = chevron-dense Brake Coral. FH5 sources disagree on hues, so ours is
  our own. Speed target per sample = min(corner cap, vehicle limit). [I]
- Voice: SKIP v1; text turn card top-left under the region popup plus a short ping. FH5 has a GPS voice with volume slider. [V S3]

---

## 7. Original design: photo mode

State machine: Idle -> Entering (fade 0.25 s, store state) -> Active -> Capturing -> Exiting (restore). [I]
- Enter: P (keyboard) / D-pad up (pad), same as FH5. Disallow during active events (pause the event timer instead). [V S, I]
- Pause: `UGameplayStatics::SetGamePaused(true)`. [E] APlayerController has `bShouldPerformFullTickWhenPaused`; actors need `bTickEvenWhenPaused`
  (FActorTickFunction); Enhanced Input actions need `UInputAction::bTriggerWhenPaused = true`. Verify delta time for paused-ticking actors in
  this project; if zero use `FApp::GetDeltaTime()`. Timers do not advance while paused, so use real-time deltas for UI. [I]
- Freeze: world pause freezes the day/night manager, weather transitions, traffic and ambient life, which also meets "time-of-day freeze". Photo
  time-of-day and weather changes call the same TimeOfDay/Weather managers with an explicit override and then wait 6-10 frames for Lumen/sky to settle.
- Camera: `ACineCameraActor`/`UCineCameraComponent` on a photo pawn, full-frame 36 mm filmback so focal length matches photographic intuition.
  Horizontal FOV = 2 atan(18 / f): 14 mm 104 deg, 24 mm 73.7, 35 mm 54.4, 50 mm 39.6, 85 mm 23.9, 135 mm 15.2, 200 mm 10.3. [I]
  [E] `CurrentFocalLength`, `CurrentAperture`, `CurrentFocusDistance`, `FocusSettings.FocusMethod` (`ECameraFocusMethod`: Manual, Tracking, Disable,
  DoNotOverride), `ManualFocusDistance` (cm), `LensSettings.MinFocalLength/MaxFocalLength/MinFStop/MaxFStop/DiaphragmBladeCount`.
  PITFALL [E]: the default `FCameraLensSettings` has Min=Max focal length 50 and Min=Max F-stop 2.0, so `CurrentFocalLength` and `CurrentAperture`
  are clamped; set Min/Max (for example 12-200 mm and f/1.2-f/22) on the camera before driving sliders. [V Epic docs: Current values are limited by the ranges]
- Modes: Free (stick/WASD, Q/E down/up, speed 3 m/s, shift 12 m/s, ctrl 0.5 m/s, sphere collision 0.3 m, stay >= 0.4 m above ground, leash 150 m from the car)
  and Orbit (target = player car, radius 2-12 m, yaw/pitch). Add `UWorldPartitionStreamingSourceComponent` [E] to the photo pawn so cells stream
  around the free camera, or keep the leash. [I]
- Focus: modes Auto-track car (Tracking), Manual distance with reticle and "pick centre" via a line trace, Off (Disable). Smooth focus changes on.
  Aperture slider 1.2-22 shown as real f-numbers (FH5's 7-13 scale is unitless [V S1]). Bokeh: blade count 4 (diamond-ish), 6, 8, 16 (round);
  `DepthOfFieldBladeCount` clamps 4-16. [E] Cinematic DoF CVars if quality needs tuning: `r.DOF.Gather.RingCount`, `r.DOF.Gather.AccumulatorQuality`,
  `r.DOF.Recombine.Quality`, `r.DOF.TemporalAAQuality`, `r.DepthOfFieldQuality`. [E]
- Effects (sliders 0-100, 50 = neutral, same convention as the FH5 guide [V S1]): exposure (-3..+3 EV via AutoExposureBias), brightness, contrast,
  saturation, temperature (WhiteTemp), vignette, grain, bloom, motion blur, chromatic aberration. Look presets as DataAssets (Neutral, Warm cinematic,
  Cool teal, Vivid, Mono, Sepia) plus 6 user slots with rename and save (FH5 "Manage Presets" [V S1, S2]). Stored in the save game. [I]
- Composition: guides Off / Thirds / Golden ratio / Centre cross / Diagonals; aspect crops 16:9, 21:9 (2.39), 4:3 (1.33), 4:5 portrait (FH5 added guides
  and portrait [V S2]; Epic crop presets 1.33/1.77/2.39/custom [V Epic]). [I]
- World: time-of-day slider 0-24 h with presets Dawn 05:30, Sunrise 06:30, Morning 09:00, Noon 12:00, Golden hour 18:00, Sunset 19:30, Dusk 20:30, Night 23:00
  (FH5 lists Default, Dawn, Sunrise, Morning ... Night [S]); weather presets Clear, Partly cloudy, Overcast, Rain, Storm, Fog. [I]
- Car: wheel steer angle -35..+35 degrees (FH5 added wheel angle [V S2]), headlights on/off, hazards, reset visual damage (FH5 has this [V S13]). [I]
- Hide HUD: toggle with H; UMG root collapsed. Panel on the left, 440 px (23 % width), tabs Camera / Effects / World / Car; bottom hint bar. [I]
- Capture: hide all UI, wait 8-16 frames for Lumen/TSR/Nanite streaming to converge (FH5 guide also says let the image finish rendering [V S1]), then
  `FScreenshotRequest::RequestScreenshot(Filename, /*bShowUI*/ false, /*bAddFilenameSuffix*/ false)`. [E] Optional supersample via console `HighResShot 2`.
  Save to `Saved/Photos/Photo_YYYYMMDD_HHMMSS.png`; keep an in-game gallery list; no watermark (FH5 adds one on A [V S13]). [I]
- Exit: restore time dilation, destroy photo pawn, restore HUD, input contexts and camera blend. [I]

---

## 8. Common UI / menu plumbing (for console, garage menu, map, photo UI)
- [E] CommonUI is in-engine (Engine/Plugins/Runtime/CommonUI): `UCommonActivatableWidget`, `UCommonActivatableWidgetStack` (and Queue), `UCommonButtonBase`,
  `UCommonUserWidget`, `UCommonTextBlock`, `UCommonTabListWidgetBase`. Epic describes input routing to the top painted tree so only the topmost layer receives input. [V Epic]
- The project prompt allows plain UMG/Slate; Common UI is optional. Use it only if gamepad menu navigation is required; otherwise a single
  `UUserWidget` per screen with manual focus is faster to build. Keep the in-game HUD as plain UMG regardless. [I]

---

## 9. Decisions (feature -> ADOPT / ADAPT / SKIP)
See the structured feature list in the agent result; summary table:
| Feature | Decision | One-line reason |
|---|---|---|
| Per-element HUD toggles | ADOPT | cheap, helps recording and accessibility |
| Analogue/digital speedometer + units | ADAPT | digital bar tach default, analogue as option |
| Circular minimap, heading-up | ADAPT | vector roads + baked underlay, no scene capture |
| Orange undiscovered roads | ADAPT | amber tint with discovery % |
| Map filter menu with All toggle | ADOPT | fixes icon clutter; persist state |
| Fast travel | ADAPT | free to hubs/home, shares code with console tp |
| GPS route ribbon + beacon | ADAPT | A* on road graph, dynamic mesh ribbon |
| GPS voice | SKIP | scope; text card + ping |
| Driving line three modes | ADAPT | own palette plus patterns |
| Skill chain ticker | ADAPT | five skills, simple chain rules |
| Region popups | ADAPT | original design, no FH5 reference |
| Notification toggles + duration | ADOPT | matches FH5 accessibility parity |
| PR stunts result cards | ADAPT | scaled targets, 60/80/100 % stars |
| Civilian traffic | ADAPT | lane graph + IDM + ring LOD |
| Ambient wildlife | ADAPT | few cheap biome animals |
| Balloons / planes | ADAPT | 3-5 balloons, 1 plane |
| Spectators / crowds | SKIP | cost; use tents/flags |
| Photo mode core | ADAPT | cine camera pawn, pause-based freeze |
| Photo presets / guides / portrait | ADOPT | small, high value for video |
| Local weather per region | SKIP (v1) | one global weather state |
| Mass/ZoneGraph traffic | SKIP | not needed for 40 agents |
| SceneCapture minimap | SKIP | cost and complexity |

---

## 10. Pitfalls and open questions
1. FH5's real minimap size, zoom behaviour, route colour and region-popup design are not documented by any reliable source. Treat section 3-6 numbers as design.
2. Driving-line colours conflict between sources; do not claim FH5 parity there.
3. Paused photo mode: ordinary actors, timers and input stop while paused; use tick-when-paused flags, check what delta time those actors receive in this project (fall back to `FApp::GetDeltaTime()`), and give photo input actions `bTriggerWhenPaused`.
4. CineCamera default lens clamps (focal 50, f/2) will silently ignore sliders until Min/Max are widened.
5. `FSlateDrawElement::MakeLines` is declared in DrawElementTypes.h in 5.8 and copies point arrays; per-frame allocation will hitch; reuse buffers.
6. World Partition streaming does not follow a free camera unless it has a streaming source or is leashed to the car.
7. Kinematic-to-physics handoff on traffic: move kinematic bodies with teleport type None so Chaos infers velocity; hard teleports give zero-velocity impacts.
8. Traffic spawn popping at 250 km/h: spawn at least 500 m ahead and outside the frustum; verify with a 70 m/s test drive.
9. Per-actor tick on traffic/animals will exceed budget; use the subsystem tick and SoA data.
10. Screenshot capture without waiting frames produces blurry Lumen/TSR output; use the 8-16 frame delay.
11. UMG text jitter: use tabular numerals (Roboto) and right-align speed.
12. Map filters: persist in save; completed icons dim not vanish.
13. Roads count: FH5 has 578 discoverable roads; ours should be 60-100 segments of about 600 m, not hundreds.
14. Open: whether to support left-hand traffic region flag; `bRightHandTraffic` is a single global flag in v1.
15. Open: color-vision presets need a real test pass with a simulator.

---

## 11. Sources actually used
Fetched and read:
- S1 https://forza.net/news/forza-photo-guide (official Turn 10 photo guide)
- S2 https://www.purexbox.com/news/2023/05/forza-horizon-5-update-21-is-huge-featuring-all-new-photo-mode-options-and-more
- S3 https://caniplaythat.com/2021/11/04/forza-horizon-5-accessibility-menu-deep-dive/
- S4 https://kotaku.com/11-things-i-wish-i-knew-before-starting-forza-horizon-5-1848007497
- S5 https://kotaku.com/before-you-start-five-settings-to-change-in-forza-hori-1848004522
- ludo.guide https://www.ludo.guide/guide/forza-horizon-5/racing-line
- S7 https://www.thegamer.com/forza-horizon-beginners-guide-tips/
- S8 https://www.shacknews.com/article/127554/fast-travel-and-xp-board-location-maps-forza-horizon-5
- S9 https://en.wikipedia.org/wiki/Forza_Horizon_5
- S10 https://www.gameshedge.com/forza-horizon-5-location-specific-barn-finds-localized-weather-diverse-animals/
- S11 https://gtplanet.net/here-are-the-11-biomes-featured-in-forza-horizon-5
- S12 https://mapmaster.io/games/forza-horizon-5-playstation/guides/Speed Zone (also /Speed Trap, /Drift Zone, /Danger Sign)
- S13 https://www.gamespew.com/2021/11/how-to-use-photo-mode-in-forza-horizon-5/
- S14 https://press-start.com.au/news/xbox/2021/10/11/google-maps-played-a-big-role-in-forza-horizon-5s-mexico/
- criticalhits https://criticalhits.com.br/games/forza-horizon-5-como-filtrar-icones-do-mapa/
- https://www.purexbox.com/news/2026/03/forza-horizon-6s-low-traffic-gameplay-was-done-on-purpose-says-ign (context: traffic density is an intentional tuning choice)
- Epic: https://dev.epicgames.com/documentation/unreal-engine/depth-of-field-in-unreal-engine
- Epic: https://dev.epicgames.com/documentation/unreal-engine/cinematic-cameras-in-unreal-engine
- Epic: https://dev.epicgames.com/documentation/unreal-engine/overview-of-advanced-multiplatform-user-interfaces-with-common-ui-for-unreal-engine
- Epic: https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/MassZoneGraphNavigation
- Local engine headers read (UE_5.8): ZoneGraphQuery.h, ZoneGraphTypes.h, CineCameraComponent.h, CineCameraSettings.h, Scene.h (DoF properties), SceneCaptureComponent(2D).h,
  DiaphragmDOF.cpp (CVars), UnrealClient.h (FScreenshotRequest), DrawElementTypes.h (MakeLines), PlayerController.h, InputAction.h,
  WorldPartitionStreamingSourceComponent.h, CommonUI Public headers, Engine/Content/Slate/Fonts.

Search-result snippets only (not read in full; marked [S]): primagames.com photo mode tips, digitaltrends.com photo mode, twinfinite.net photo mode,
gtplanet.net FH5 General Discussion traffic posts, videogamer.com review (balloons), progameguides.com road count, pcinvasion / insider-gaming skill chains,
stevivor / thegamer / nme / techradar developer interviews (biomes, driver-perspective design, sky capture), racinggames.gg FH5 articles.
Pages that returned 403/redirect and were not usable: support.forza.net (accessibility and release notes), primagames, twinfinite, forums.forza.net, Digital Trends (empty).
