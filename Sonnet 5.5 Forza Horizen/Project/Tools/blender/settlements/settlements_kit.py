# -*- coding: utf-8 -*-
"""
Settlements kit entry point.  Run inside the shared Blender (port 9889) with:

    _p = r"W:\\YouTube\\Claude Sonnet 5.5\\Forza Horizen\\Sonnet55Forza\\UnrealSonnet55Forza\\Tools\\blender\\settlements\\settlements_kit.py"
    _g = {'__name__': 'bld_kit'}
    exec(compile(open(_p, encoding='utf8').read(), _p, 'exec'), _g)
    _g['build'](['bld_house_a']); _g['validate'](...); _g['export']('bld_house_a')

All code is exec'd into the caller's PRIVATE dict (no leakage into the shared interpreter).
"""
import os
_here = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else \
    r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza\Tools\blender\settlements"
_PARTS = ['bld_lib.py', 'bld_houses.py', 'bld_farm.py', 'bld_civic.py', 'bld_coast.py', 'bld_landmarks.py', 'bld_ruins.py']
for _f in _PARTS:
    _fp = os.path.join(_here, _f)
    if os.path.exists(_fp):
        exec(compile(open(_fp, encoding='utf8').read(), _fp, 'exec'), globals())
