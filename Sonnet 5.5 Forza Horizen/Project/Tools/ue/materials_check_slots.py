"""Slot coverage report (plain python, no editor):  every Blender material slot name found in Exports/**/*.json (non-car assets) must have an entry in
Tools/ue/materials_slot_map.json (written by the `instances` step).   "W:/Blender/5.2/python/bin/python.exe" -I Tools/ue/materials_check_slots.py
Traffic wheel / body slots (Body, Glass, Interior, Wheel_*) belong to the cars agent (Content/Forza/Materials/Cars, Traffic) and are reported separately."""
import collections
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
slots = collections.defaultdict(set)


def walk(o, f):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "material_slots" and isinstance(v, list):
                for s in v:
                    if isinstance(s, str):
                        slots[s].add(os.path.basename(f))
            else:
                walk(v, f)
    elif isinstance(o, list):
        for x in o:
            walk(x, f)


for f in glob.glob(ROOT + "/Exports/**/*.json", recursive=True):
    if os.sep + "Cars" + os.sep in f:
        continue
    try:
        walk(json.load(open(f, encoding="utf-8")), f)
    except (OSError, ValueError):
        pass
smap = json.load(open(ROOT + "/Tools/ue/materials_slot_map.json", encoding="utf-8"))
other = [s for s in sorted(slots) if not s.startswith("M_")]
missing = [s for s in sorted(slots) if s.startswith("M_") and s not in smap]
print("unique non-car slot names: %d   mapped: %d   missing: %d" % (len(slots), len(slots) - len(missing) - len(other), len(missing)))
for s in missing:
    print("  MISSING", s, sorted(slots[s])[:3])
print("not M_* (traffic body/glass/wheel slots, cars agent):", other)
sys.exit(1 if missing else 0)
