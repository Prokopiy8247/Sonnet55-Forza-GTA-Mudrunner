class_name ActivityBase
extends Node
## Base class of every activity (shooting range, stunt jumps, races, base jump). An activity is a Node child of ActivitySystem.
## The system owns the state machine (IDLE / COUNTDOWN / RUNNING / FINISHED / ABORTED), the HUD, the interaction point and the rewards;
## an activity only implements the hooks below and reports back with finish_activity(result) / abort_activity(reason).
##
## Result dictionary (finish_activity):
##   key: String            best-score slot ("range:pistol"), default = id
##   value: float           the number that is compared with the previous best
##   higher_better: bool    true for scores, false for times
##   medal: String          "gold" | "silver" | "bronze" | "none"
##   cash: int              small cash reward (the system pays it)
##   skill: Dictionary      skill id -> use units for Game.sys(&"skills").record
##   title / subtitle / main / rows / hint   results card text (see ActivityHud._draw_results); rows = [[label, value, Color?], ...]

enum Kind { RANGE, RACE, JUMP, CHUTE, OTHER }

var id: StringName = &"activity"
var title := "Activity"
var kind: Kind = Kind.OTHER
var accent: Color = GC.COL_ACCENT
var description := ""
var location_id: StringName = &""          ## WorldLayout location the interaction point / map icon sits at
var point_pos := Vector3.ZERO              ## interaction point position (default = the location)
var point_yaw := 0.0
var interact_range := 3.2
var passive := false                       ## stunt jumps: started by poll_passive(), not by pressing E
var from_vehicle := false                  ## may be started with E from inside a vehicle (races)
var countdown_seconds := 0                 ## 3 -> "3 2 1 GO" before on_go(); 0 = starts running at once
var show_marker := true
var marker_radius := 1.5
var options: Array = []                    ## menu choices [{"id": "pistol", "name": "Pistol", "desc": "..."}]; empty = start directly
var menu_hint := ""                        ## extra line in the menu
var blip_id: StringName = &""              ## extra WorldLayout location id for the map icon (needs a UIIcons.LOC entry), "" = use location_id

var sys: Node = null                       ## ActivitySystem (set by register)
var running := false                       ## true between start and finish/abort
var last_option := ""


# ---- hooks to override ----------------------------------------------------------------------------------------------------
## Called once after the world is built (static content: target stands, ramps data, route tables).
func setup_activity() -> void:
	pass


## "" = may start now, otherwise the toast shown to the player.
func can_start(_player: Node, _opts: Dictionary) -> String:
	return ""


## Text of the interaction prompt ("Shooting Range"); the key cap is added by the HUD.
func prompt_text(_player: Node) -> String:
	return title


## Prepare the run (teleport, loan weapons, spawn the checkpoint chain...). Return false (after toasting) to cancel.
func begin(_opts: Dictionary) -> bool:
	return true


## The countdown reached GO (or begin() finished when countdown_seconds == 0).
func on_go() -> void:
	pass


## Physics tick while COUNTDOWN / RUNNING (sys_state tells which).
func tick(_dt: float, _sys_state: int) -> void:
	pass


## Return a reason to abort the run ("You left the firing line"), "" to continue. Called every physics frame while active.
func check_abort() -> String:
	return ""


func on_abort(_reason: String) -> void:
	pass


## Always called when a run ends (finish or abort): restore weapons, free checkpoints, unlock the player.
func cleanup() -> void:
	pass


## Passive activities: return true when the activity wants to start itself (the system then calls begin({}) and goes RUNNING).
func poll_passive(_dt: float) -> bool:
	return false


## One line for the menu: "Best 3 120 pts (gold)".
func best_line(key: String = "") -> String:
	if sys == null:
		return ""
	return sys.best_text(key if key != "" else String(id))


## World positions of the neon start markers (default: the interaction point).
func marker_spots() -> Array:
	return [point_pos]


## Called when a saved game was loaded (best scores are restored); activities may refresh their world content.
func on_loaded() -> void:
	pass


# ---- helpers for subclasses -------------------------------------------------------------------------------------------------
func finish_activity(result: Dictionary) -> void:
	if sys != null:
		sys.complete(self, result)


func abort_activity(reason: String) -> void:
	if sys != null:
		sys.abort(reason, self)


func player() -> Node:
	return Game.player if is_instance_valid(Game.player) else null


func hud() -> Node:
	return sys.hud if sys != null else null


func say(text: String, seconds: float = 3.0) -> void:
	Events.subtitle.emit(text, seconds)


func toast(text: String, kind_name: StringName = &"info") -> void:
	Events.notification.emit(text, kind_name)


func play_sfx(sound_id: StringName) -> void:
	if sys != null:
		sys.play_sfx(sound_id)


## Medal from a value and three thresholds. higher_better: gold >= t[0]; else gold <= t[0].
static func medal_for(value: float, gold: float, silver: float, bronze: float, higher_better: bool = true) -> String:
	if higher_better:
		if value >= gold:
			return "gold"
		if value >= silver:
			return "silver"
		if value >= bronze:
			return "bronze"
		return "none"
	if value <= gold:
		return "gold"
	if value <= silver:
		return "silver"
	if value <= bronze:
		return "bronze"
	return "none"


## Gentle cash curve: repeat plays at the same medal pay half.
static func cash_for(medal: String, table: Array) -> int:
	match medal:
		"gold":
			return int(table[3])
		"silver":
			return int(table[2])
		"bronze":
			return int(table[1])
	return int(table[0])
