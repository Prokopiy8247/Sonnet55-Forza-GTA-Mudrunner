"""lane4_export.py - exports characters/human.glb (skins, no root). Run after gta_lib.py + lane4_lib.py."""
_root = c4_root()
for _o in descendants(_root):
    _o.hide_set(False)
    _o.hide_viewport = False
_path = export_glb(_root, "characters/human", skins=True, include_root=False)
print("export done", _path)
