# -*- coding: utf-8 -*-
"""
Roadside kit entry point.  Run inside the shared Blender (port 9889) with:

    _p = r"W:\\YouTube\\Claude Sonnet 5.5\\Forza Horizen\\Sonnet55Forza\\UnrealSonnet55Forza\\Tools\\blender\\roadside\\roadside_kit.py"
    _g = {'__name__': 'rs_kit'}
    exec(compile(open(_p, encoding='utf8').read(), _p, 'exec'), _g)
    _g['build'](['rs_guardrail_4m'])          # idempotent: removes + rebuilds only that asset
    _g['validate_all']();  _g['export']('rs_guardrail_4m')

All library/builder code is exec'd into the caller's PRIVATE dict, so no names leak into the shared interpreter.
"""
import os
_here = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else \
    r"W:\YouTube\Claude Sonnet 5.5\Forza Horizen\Sonnet55Forza\UnrealSonnet55Forza\Tools\blender\roadside"
_PARTS = ['rs_lib.py', 'rs_font.py', 'rs_ads.py', 'rs_barriers.py', 'rs_barriers2.py', 'rs_traffic.py', 'rs_signs.py', 'rs_poles.py', 'rs_misc.py', 'rs_order.py']
for _f in _PARTS:
    _fp = os.path.join(_here, _f)
    if os.path.exists(_fp):
        exec(compile(open(_fp, encoding='utf8').read(), _fp, 'exec'), globals())
