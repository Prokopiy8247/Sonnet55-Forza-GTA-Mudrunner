"""world_lib - shared constants and helpers of the world-builder scripts (Tools/ue/world_*.py).  Docs/Tech/WORLD_BUILD.md

Everything here runs INSIDE the editor (import unreal).  Log markers: ROAM_WORLD_*  (grep them in Tools/Logs/<name>.log).
"""
import json
import os
import sys
import time

import unreal

ROOT = unreal.Paths.project_dir().replace("\\", "/")          # ends with '/'
SRC = ROOT + "Content/Forza/World/Source"                      # raw generator output (git-ignored)
TOOLS_UE = ROOT + "Tools/ue"

# ---- content paths -----------------------------------------------------------------------------------------------------
MAP_DIR = "/Game/Forza/Maps"
MAP_MAIN = MAP_DIR + "/L_Main"
PM_DIR = "/Game/Forza/Materials/Physical"
LANDSCAPE_MAT_DIR = "/Game/Forza/Materials/Landscape"
LANDSCAPE_MAT = LANDSCAPE_MAT_DIR + "/M_Roam_Landscape"
LAYER_INFO_DIR = "/Game/Forza/World/Landscape"
DATA_DIR = "/Game/Forza/Data"
DA_ROAD_NETWORK = DATA_DIR + "/DA_RoadNetwork"
DA_WORLD_DEFINITION = DATA_DIR + "/DA_WorldDefinition"
TEX_ROOT = "/Game/Forza/Textures"
MPC_PATH = "/Game/Forza/Materials/MPC_Roam_World"

# ---- terrain layout (Docs/WORLD_DATA_FORMATS.md) -------------------------------------------------------------------------
SRC_SIZE = 4033
LAYERS = ["Grass", "ForestFloor", "Farmland", "Rock", "Sand", "RedClay", "Snow", "RoadVerge"]   # world_meta.json -> layers.order
SCALE = unreal.Vector(100.0, 100.0, 300.0)        # cm per vertex XY, Z scale of the uint16 encoding
GRID_COMPONENTS = 4                               # World Partition landscape proxy edge (components): 4 x 4 proxies of 4 x 4 components

# (name, ERoamSurface index, friction, static friction, density) - indices equal ERoamSurface (Core/RoamTypes.h) = SurfaceType1..8
SURFACES = [
    ("Asphalt", 0, 1.00, 1.00, 2.4),
    ("Concrete", 1, 0.97, 0.97, 2.4),
    ("Dirt", 2, 0.78, 0.80, 1.6),
    ("Gravel", 3, 0.70, 0.72, 1.8),
    ("Grass", 4, 0.60, 0.62, 1.2),
    ("Sand", 5, 0.55, 0.58, 1.6),
    ("Snow", 6, 0.35, 0.40, 0.5),
    ("Mud", 7, 0.45, 0.50, 1.4),
    # Rock has no ERoamSurface of its own: it is mapped to the Gravel surface type (hard, loose-ish, nobody drives on it) with a higher friction
    ("Rock", 3, 0.85, 0.88, 2.6),
]

# landscape layer -> physical material (names of PM_Roam_*)
LAYER_PHYS = {
    "Grass": "Grass", "ForestFloor": "Dirt", "Farmland": "Dirt", "Rock": "Rock",
    "Sand": "Sand", "RedClay": "Dirt", "Snow": "Snow", "RoadVerge": "Gravel",
}


def log(msg):
    unreal.log("ROAM_WORLD " + str(msg))


def warn(msg):
    unreal.log_warning("ROAM_WORLD " + str(msg))


def err(msg):
    unreal.log_error("ROAM_WORLD " + str(msg))


ea = unreal.EditorAssetLibrary
tools = unreal.AssetToolsHelpers.get_asset_tools()
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


class Timer(object):
    def __init__(self, name):
        self.name = name
        self.t0 = time.time()

    def done(self, extra=""):
        log("STEP_DONE %s %.1fs %s" % (self.name, time.time() - self.t0, extra))


def ensure_dir(path):
    if not ea.does_directory_exist(path):
        ea.make_directory(path)


def load(path):
    asset = ea.load_asset(path)
    if asset is None:
        raise RuntimeError("asset not found: " + path)
    return asset


def save_asset(asset):
    """Saves one asset package via the C++ helper (works headless)."""
    return unreal.RoamWorldBuilder.save_asset_by_object(asset)


def get_world():
    return unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()


_JOB_ARGS = ""


def set_job_args(text):
    """Called by world_build.py with the JOB_ARGS string of the editor job server (whitespace separated tokens)."""
    global _JOB_ARGS
    _JOB_ARGS = text or ""


def _tokens():
    return _JOB_ARGS.split()


def steps_from_environment(default):
    """Steps to run: bare tokens of JOB_ARGS ("material,map crop=1,2,3") or env ROAM_WORLD_STEPS (comma separated); falls back to `default`."""
    steps = []
    for token in _tokens():
        if "=" not in token:
            steps += [s for s in token.replace(";", ",").split(",") if s]
    if not steps:
        raw = os.environ.get("ROAM_WORLD_STEPS", "").strip()
        steps = [s.strip() for s in raw.replace(";", ",").split(",") if s.strip()]
    return steps if steps else list(default)


def option(name, default=""):
    """Option `name=value` token of JOB_ARGS (e.g. crop=1762,1762,509 map=/Game/Forza/Maps/L_WorldTest nanite=0) or the environment variable
    ROAM_WORLD_<NAME>."""
    for token in _tokens():
        if "=" in token:
            key, value = token.split("=", 1)
            if key.lower() == name.lower():
                return value
    return os.environ.get("ROAM_WORLD_" + name.upper(), default)


def world_meta():
    with open(SRC + "/world_meta.json", "r", encoding="utf-8") as fh:
        return json.load(fh)


def roads_json():
    with open(SRC + "/roads.json", "r", encoding="utf-8") as fh:
        return json.load(fh)


def road_sample(road_id, s):
    """(x, y, z, heading_deg) in metres at arc length s on a roads.json road (nearest 2 m sample)."""
    data = roads_json()
    road = next(r for r in data["roads"] if r["id"] == road_id)
    samples = road["samples"]
    row = samples[min(len(samples) - 1, max(0, int(round(s / 2.0))))]
    return row[1], row[2], row[3], row[4]
