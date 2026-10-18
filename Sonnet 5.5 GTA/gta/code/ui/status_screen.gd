class_name StatusScreen
extends MenuBase
## Status screen: use-based character skills (SkillsSystem) + play statistics (UIRoot.stats). Registered as menu
## &"status"; the same content (StatusScreen.Page) is embedded as a tab of the pause menu.

const SKILLS := [
	[&"stamina", "Stamina", "Sprint, swim and cycle for longer"],
	[&"shooting", "Shooting", "Steadier aim and faster reloads"],
	[&"strength", "Strength", "Harder melee, tougher body"],
	[&"stealth", "Stealth", "Quieter movement, lower detection"],
	[&"driving", "Driving", "Better control of cars and bikes"],
	[&"flying", "Flying", "Smoother aircraft handling"],
	[&"lung", "Lung Capacity", "Stay underwater longer"],
]

var page: Page


func _init() -> void:
	super._init()
	pauses_game = true
	var b := build_frame("Status", "Skills and statistics", 1240)
	page = Page.new()
	b.add_child(page)
	set_hints([["Esc", "Close"]])


func _on_open(_d: Dictionary) -> void:
	page.refresh()


func _process(_delta: float) -> void:
	if visible:
		page.tick()


## Reads a skill value 0..1 from the SkillsSystem (several API shapes tolerated) or from the Events.skill_changed cache.
static func read_skill(id: StringName) -> Dictionary:
	var out := {"value": 0.0, "known": false}
	var s = Game.sys(&"skills")
	if s != null:
		var v = null
		if s.has_method("get_skill"):
			v = s.get_skill(id)
		elif s.has_method("get_value"):
			v = s.get_value(id)
		else:
			var d = s.get("skills")
			if d is Dictionary and d.has(id):
				v = d[id]
				if v is Dictionary:
					v = v.get("value", 0.0)
		if v != null and (v is float or v is int):
			var f := float(v)
			out["value"] = clampf(f / 100.0 if f > 1.0001 else f, 0.0, 1.0)
			out["known"] = true
			return out
	if Game.ui != null:
		var cache: Dictionary = Game.ui.get("skill_cache") if Game.ui.get("skill_cache") != null else {}
		if cache.has(id):
			var f2 := float(cache[id])
			out["value"] = clampf(f2 / 100.0 if f2 > 1.0001 else f2, 0.0, 1.0)
			out["known"] = true
	return out


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


static func format_dist(m: float) -> String:
	return ("%.2f km" % (m / 1000.0)) if m >= 1000.0 else ("%d m" % int(m))


# =====================================================================================================================
class Page extends HBoxContainer:
	var _skill_bars: Dictionary = {}
	var _skill_vals: Dictionary = {}
	var _stat_rows: Dictionary = {}
	var _acc := 0.0

	func _init() -> void:
		add_theme_constant_override("separation", 22)
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		# ---- skills ----
		var left := UIKit.panel(&"PanelDeep")
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(left)
		var lv := UIKit.vbox(12)
		left.add_child(lv)
		lv.add_child(UIKit.caption("Skills - improve by doing"))
		for s in StatusScreen.SKILLS:
			var box := UIKit.vbox(2)
			var top := UIKit.hbox(8)
			var nm := UIKit.label(s[1], 21, UITheme.C_TEXT, true)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top.add_child(nm)
			var val := UIKit.label("0%", 19, UITheme.C_ACCENT, true, HORIZONTAL_ALIGNMENT_RIGHT)
			top.add_child(val)
			box.add_child(top)
			var bar := UIKit.bar(0.0, UITheme.C_ACCENT, 10.0)
			box.add_child(bar)
			box.add_child(UIKit.label(s[2], 15, UITheme.C_DIM))
			lv.add_child(box)
			_skill_bars[s[0]] = bar
			_skill_vals[s[0]] = val
		# ---- stats ----
		var right := UIKit.panel(&"PanelDeep")
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(right)
		var rv := UIKit.vbox(10)
		right.add_child(rv)
		rv.add_child(UIKit.caption("Play statistics"))
		for row in [["time", "Time played"], ["foot", "Distance on foot"], ["driven", "Distance driven"], ["kills", "Kills"],
				["earned", "Money earned"], ["spent", "Money spent"], ["wanted_peak", "Highest wanted level"],
				["deaths", "Times knocked out"], ["busted", "Times busted"], ["vehicles", "Vehicles entered"]]:
			var r := UIKit.stat_row(row[1], "-")
			rv.add_child(r)
			_stat_rows[row[0]] = r.get_meta(&"value")

	func tick() -> void:
		_acc += get_process_delta_time()
		if _acc >= 0.5:
			_acc = 0.0
			refresh()

	func refresh() -> void:
		for s in StatusScreen.SKILLS:
			var r := StatusScreen.read_skill(s[0])
			var bar: ProgressBar = _skill_bars[s[0]]
			bar.value = r["value"]
			var lab: Label = _skill_vals[s[0]]
			lab.text = ("%d%%" % int(round(float(r["value"]) * 100.0))) if r["known"] else "0%"
		var st: Dictionary = Game.ui.get("stats") if Game.ui != null and Game.ui.get("stats") != null else {}
		_put("time", StatusScreen.format_time(float(st.get("time_played", 0.0))))
		_put("foot", StatusScreen.format_dist(float(st.get("dist_foot", 0.0))))
		_put("driven", StatusScreen.format_dist(float(st.get("dist_driven", 0.0))))
		_put("kills", str(int(st.get("kills", 0))))
		_put("earned", Util.format_money(int(st.get("money_earned", 0))))
		_put("spent", Util.format_money(int(st.get("money_spent", 0))))
		_put("wanted_peak", ("%d star%s" % [int(st.get("wanted_peak", 0)), "" if int(st.get("wanted_peak", 0)) == 1 else "s"]))
		_put("deaths", str(int(st.get("deaths", 0))))
		_put("busted", str(int(st.get("busted", 0))))
		_put("vehicles", str(int(st.get("vehicles", 0))))

	func _put(key: String, text: String) -> void:
		var l: Label = _stat_rows.get(key)
		if l != null:
			l.text = text
