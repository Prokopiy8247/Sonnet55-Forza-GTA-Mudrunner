"""Quick C# compile check WITHOUT Unity (takes a few seconds, needs no editor lock).

Re-uses the response files Unity/Bee generated on the last real compile (Library/Bee/artifacts/*/<asm>.rsp) -
same references, defines, language version - but swaps in the CURRENT source list found under each .asmdef folder.
Run:  python -I Tools/qc.py            (all project assemblies)
      python -I Tools/qc.py Runtime    (substring of an assembly name: Runtime | Editor | Tests)
Exit code 0 = no errors. Prints only errors (and warnings with -w).

Limits: it cannot see shader/asset problems, [MenuItem]/serialization issues, or new packages/asmdef references that Unity
has not compiled yet (run Tools/ub.sh compile once after adding an asmdef or package).
"""
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
CSC = r"C:\Program Files\Unity\Hub\Editor\6000.6.0f1\Editor\Data\DotNetSdk\sdk\8.0.318\Roslyn\bincore\csc.dll"
DOTNET = r"C:\Program Files\Unity\Hub\Editor\6000.6.0f1\Editor\Data\DotNetSdk\dotnet.exe"
OUT = os.path.join(ROOT, "Temp", "qc")
os.makedirs(OUT, exist_ok=True)
want = [a for a in sys.argv[1:] if not a.startswith("-")]
show_warn = "-w" in sys.argv


def asmdefs():
    res = {}
    for p in glob.glob("Assets/**/*.asmdef", recursive=True):
        import json
        with open(p, encoding="utf-8-sig") as f:
            name = json.load(f)["name"]
        res[os.path.dirname(p).replace("\\", "/")] = name
    return res


def sources_by_asm(defs):
    groups = {}
    dirs = sorted(defs.keys(), key=len, reverse=True)
    for cs in glob.glob("Assets/**/*.cs", recursive=True):
        cs = cs.replace("\\", "/")
        owner = None
        for d in dirs:
            if cs.startswith(d + "/"):
                owner = defs[d]
                break
        groups.setdefault(owner or "Assembly-CSharp", []).append(cs)
    return groups


def find_rsp(name):
    c = sorted(glob.glob("Library/Bee/artifacts/*/%s.rsp" % name), key=os.path.getmtime)
    return c[-1] if c else None


def build(name, srcs, extra_refs):
    rsp = find_rsp(name)
    if not rsp:
        return None, "no rsp for %s yet (run Tools/ub.sh compile once)" % name
    keep = []
    for l in open(rsp, encoding="utf-8").read().splitlines():
        s = l.strip()
        if not s:
            continue
        if s.startswith(("-out:", "-refout:", "-analyzer", "/additionalfile", "-a:")):
            continue
        if s.startswith('"') and s.endswith('.cs"'):
            continue
        if s.startswith("-r:") and any(("%s." % n) in s or ("%s/" % n) in s for n in extra_refs):
            continue
        keep.append(s)
    out = os.path.join(OUT, name + ".dll")
    keep.append('-out:"%s"' % out)
    for r in extra_refs.values():
        keep.append('-r:"%s"' % r)
    for s in sorted(srcs):
        keep.append('"%s"' % s)
    os.makedirs(OUT, exist_ok=True)
    rsp_path = os.path.join(OUT, name + ".qc.rsp")
    with open(rsp_path, "w", encoding="utf-8") as f:
        f.write("\n".join(keep))
    p = subprocess.run([DOTNET, CSC, "@" + rsp_path, "-nologo"], capture_output=True, text=True, cwd=ROOT)
    return out, (p.stdout + p.stderr)


def main():
    defs = asmdefs()
    groups = sources_by_asm(defs)
    order = ["MudRunner.Runtime", "MudRunner.Editor", "MudRunner.Tests.PlayMode"]
    built = {}
    bad = False
    for name in order + [n for n in groups if n not in order]:
        if name not in groups:
            continue
        refs = {}
        if name != "MudRunner.Runtime" and "MudRunner.Runtime" in built:
            refs["MudRunner.Runtime"] = built["MudRunner.Runtime"]
        out, log = build(name, groups[name], refs)
        if out is None:
            print("[qc] %s: %s" % (name, log))
            continue
        errs = [l for l in log.splitlines() if ": error " in l]
        warns = [l for l in log.splitlines() if ": warning " in l]
        built[name] = out
        if want and not any(w.lower() in name.lower() for w in want):
            continue
        if errs:
            bad = True
            print("[qc] %s: %d error(s)" % (name, len(errs)))
            for e in sorted(set(errs))[:80]:
                print("  " + e)
        else:
            print("[qc] %s: OK (%d files, %d warnings)" % (name, len(groups[name]), len(warns)))
        if show_warn:
            for w in sorted(set(warns))[:40]:
                print("  " + w)
    sys.exit(1 if bad else 0)


main()
