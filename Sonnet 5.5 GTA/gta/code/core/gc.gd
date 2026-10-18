class_name GC
extends RefCounted
## Global constants shared by every module. Additive changes only (never rename/remove).

const GAME_NAME := "Halcyon Bay"
const WORLD_SIZE := 600.0           # playable ground footprint, metres
const WORLD_HALF := 300.0           # playable ground spans x,z in [-300, 300]
const GROUND_Y := 0.0               # urban plateau height
const WATER_LEVEL := -1.5           # sea surface Y (quays are 1.5 m above it)

# ---- Physics layers (bit values) -------------------------------------------------
const L_WORLD := 1 << 0        # terrain, roads, buildings, static props
const L_PLAYER := 1 << 1       # player character body
const L_NPC := 1 << 2          # pedestrians, police on foot
const L_VEHICLE := 1 << 3      # vehicle bodies (all classes)
const L_PROP := 1 << 4         # dynamic props (cones, bins, crates...)
const L_PROJECTILE := 1 << 5   # rockets, grenades
const L_TRIGGER := 1 << 6      # Area3D triggers / interaction zones
const L_WATER := 1 << 7        # water volumes (Area3D)
const L_RAGDOLL := 1 << 8      # ragdoll bones
const L_DEBRIS := 1 << 9       # cosmetic debris (collides with world only)
const L_ANIMAL := 1 << 10      # wildlife

# ---- Common masks ------------------------------------------------------------------
const M_BULLET := L_WORLD | L_PLAYER | L_NPC | L_VEHICLE | L_PROP | L_RAGDOLL | L_ANIMAL
const M_LOS := L_WORLD                                  # line-of-sight blocking (static world only)
const M_LOS_VEHICLES := L_WORLD | L_VEHICLE
const M_GROUND := L_WORLD | L_PROP                      # wheel / foot rays
const M_CAMERA := L_WORLD                               # camera collision
const M_CHARACTER_MOVE := L_WORLD | L_VEHICLE | L_PROP | L_NPC | L_PLAYER
const M_VEHICLE_MOVE := L_WORLD | L_VEHICLE | L_PROP | L_NPC | L_PLAYER
const M_EXPLOSION := L_PLAYER | L_NPC | L_VEHICLE | L_PROP | L_RAGDOLL | L_ANIMAL

# ---- Groups ---------------------------------------------------------------------------
const G_PLAYER := &"player"
const G_NPC := &"npc"                     # every non-player CharacterBase
const G_PED := &"pedestrian"              # civilians
const G_POLICE := &"police"               # police on foot AND police vehicles / helicopters
const G_HOSTILE := &"hostile"             # gang / hostile NPCs
const G_VEHICLE := &"vehicle"             # every VehicleBase
const G_TRAFFIC := &"traffic_vehicle"     # AI civilian traffic vehicles
const G_DAMAGEABLE := &"damageable"       # implements apply_damage(amount, info)
const G_INTERACT := &"interactable"       # implements get_interaction(player)->Dictionary and interact(player)
const G_ANIMAL := &"animal"
const G_PICKUP := &"pickup"
const G_SYSTEM := &"game_system"

# ---- Damage types (info["type"]) ---------------------------------------------------
const DMG_BULLET := &"bullet"
const DMG_MELEE := &"melee"
const DMG_EXPLOSION := &"explosion"
const DMG_FIRE := &"fire"
const DMG_COLLISION := &"collision"
const DMG_RUNOVER := &"runover"
const DMG_FALL := &"fall"
const DMG_DROWN := &"drown"
const DMG_ANIMAL := &"animal"

# ---- Damage zones (info["zone"]) --------------------------------------------------
const ZONE_HEAD := &"head"
const ZONE_TORSO := &"torso"
const ZONE_LIMB := &"limb"
const ZONE_TIRE := &"tire"
const ZONE_GLASS := &"glass"
const ZONE_BODY := &"body"
const ZONE_ENGINE := &"engine"

# ---- Factions (CharacterBase.faction / VehicleBase.faction) -------------------------
const F_PLAYER := &"player"
const F_CIVILIAN := &"civilian"
const F_POLICE := &"police"
const F_GANG := &"gang"
const F_MILITARY := &"military"
const F_ANIMAL := &"animal"

# ---- Crime types (Events.crime_committed) ----------------------------------------------
const CRIME_ASSAULT := &"assault"                    # hitting / shooting a civilian
const CRIME_MURDER := &"murder"                      # killing a civilian
const CRIME_SHOOTING := &"public_shooting"           # firing a weapon in public (non-suppressed is louder)
const CRIME_POLICE_ASSAULT := &"police_assault"
const CRIME_POLICE_KILL := &"police_kill"
const CRIME_CARJACK := &"carjack"                    # pulling a driver out
const CRIME_VEHICLE_THEFT := &"vehicle_theft"        # taking an empty / parked vehicle
const CRIME_POLICE_VEHICLE_THEFT := &"police_vehicle_theft"
const CRIME_POLICE_VEHICLE_DESTROYED := &"police_vehicle_destroyed"
const CRIME_HIT_AND_RUN := &"hit_and_run"
const CRIME_COLLISION := &"reckless_collision"
const CRIME_EXPLOSION := &"explosion"
const CRIME_VANDALISM := &"vandalism"
const CRIME_ROBBERY := &"robbery"
const CRIME_RESIST_ARREST := &"resist_arrest"
const CRIME_AIRCRAFT_THEFT := &"aircraft_theft"

# ---- Districts (WorldLayout.district_at) ---------------------------------------------
const D_DOWNTOWN := &"downtown"
const D_RESIDENTIAL := &"residential"
const D_INDUSTRIAL := &"industrial"
const D_WATERFRONT := &"waterfront"
const D_PARK := &"park_hills"
const D_AIRPORT := &"airport"
const D_BEACH := &"beach"
const D_SEA := &"sea"

# ---- Weather ----------------------------------------------------------------------------
const W_CLEAR := &"clear"
const W_CLOUDY := &"cloudy"
const W_RAIN := &"rain"
const W_FOG := &"fog"
const W_STORM := &"storm"
const WEATHERS: Array[StringName] = [&"clear", &"cloudy", &"rain", &"fog", &"storm"]

# ---- Vehicle classes (VehicleBase.vclass) ----------------------------------------------
const VC_CAR := &"car"
const VC_BIKE := &"bike"            # motorcycle
const VC_BICYCLE := &"bicycle"
const VC_BOAT := &"boat"
const VC_HELI := &"heli"
const VC_PLANE := &"plane"

# ---- Display colours used by UI + minimap (original palette "Halcyon") ----------------
const COL_ACCENT := Color("#34e0ff")      # cyan
const COL_ACCENT2 := Color("#ff3d9a")     # magenta
const COL_WARN := Color("#ffb347")        # amber
const COL_DANGER := Color("#ff4d4d")
const COL_OK := Color("#7be495")
const COL_PANEL := Color(0.05, 0.07, 0.10, 0.82)
const COL_TEXT := Color("#eaf2f7")
const COL_TEXT_DIM := Color("#8fa3b3")
