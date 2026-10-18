"""Remove orphaned material assets of earlier designs (job; only assets that nothing references are deleted).
    ue_job.ps1 Tools/ue/materials_cleanup.py            (or: job_drop.ps1 Tools/ue/materials_cleanup.py)
Log marker: MAT_CLEANUP.  Deleting a master that still has instances crashed the editor (python311 / MaterialEditor access violation), so every candidate is checked with
find_package_referencers_for_asset first; instances go before their parent master."""
import unreal

ea = unreal.EditorAssetLibrary
M = "/Game/Forza/Materials/"
# (path, why)  - instances first, then masters
CANDIDATES = [
    (M + "Instances/MI_Skid_Strip_Tire", "instance of the removed M_Roam_Skid_Strip"),
    (M + "M_Roam_Skid_Strip", "replaced by M_Roam_Skid (deferred decal)"),
    (M + "M_Roam_Glass_Simple", "replaced by M_Roam_Glass_Building"),
    (M + "M_Roam_Particle_Soft_Unlit", "replaced by M_Roam_Particle_Unlit"),
]
for path, why in CANDIDATES:
    if not ea.does_asset_exist(path):
        continue
    refs = [r for r in ea.find_package_referencers_for_asset(path, False) if r.split(".")[0] != path]
    if refs:
        unreal.log_warning("MAT_CLEANUP keep %s (%s): still referenced by %s" % (path, why, refs[:4]))
        continue
    ok = ea.delete_asset(path)
    unreal.log("MAT_CLEANUP deleted %s (%s): %s" % (path, why, ok))
unreal.log("MAT_CLEANUP done")
