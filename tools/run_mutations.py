#!/usr/bin/env python3
"""Apply each catalogued mutation and record which technique detects it.

For every mutation: copy the tree, apply the substitution, then run BOTH the
formal flow and the simulation flow, and record what each one says.

The output table is the deliverable. A mutation that NOTHING catches is the
most valuable row in it, because it locates a hole in the specification rather
than in the checking.

Usage:
    python3 tools/run_mutations.py [--only M1,M3] [--jobs N]
"""

import argparse
import concurrent.futures
import json
import pathlib
import re
import shutil
import subprocess
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required:  pip install pyyaml")

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORK = ROOT / "build" / "mut"
import os
# Location of the OSS CAD Suite binaries. Override with OSS_CAD=/path/to/oss-cad-suite/bin
# (the Makefile uses the same variable).
OSS = pathlib.Path(os.environ.get("OSS_CAD", str(pathlib.Path.home() / "eda" / "oss-cad-suite" / "bin")))

RTL = ["rtl/spcu_pkg.sv", "rtl/spcu_sync2.sv", "rtl/spcu_regs.sv",
       "rtl/spcu_ctrl_fsm.sv", "verif/props/spcu_props.sv",
       "verif/props/spcu_props_pclk.sv", "rtl/spcu_top.sv"]
SIM = RTL + ["verif/sv/spcu_sva_tier_b.sv", "verif/sv/spcu_sv_tb.sv"]


def env():
    import os
    e = dict(os.environ)
    e["PATH"] = f"{OSS}:{e['PATH']}"
    return e


def run(cmd, cwd, timeout=900):
    try:
        p = subprocess.run(cmd, cwd=cwd, env=env(), capture_output=True,
                           text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT"


def formal(d):
    """Run BMC. Returns (verdict, [failing assertion names]).

    BMC rather than PDR deliberately: smtbmc NAMES the assertion that failed,
    which is the whole point of the exercise. The cost is that a PASS here is
    bounded, not a proof -- and for mutation detection that is the right
    trade, because we are looking for failures, not banking proofs.
    """
    rc, out = run(["sby", "-f", "verif/formal/spcu.sby", "bmc"], d)
    hits = sorted(set(re.findall(r"Assert failed in \S+: (\S+)", out)))
    hits = [h.split(".")[-1] for h in hits]
    if "TIMEOUT" in out:
        return "TIMEOUT", []
    return ("CAUGHT" if hits else "missed"), hits


def sim(d):
    """Build and run the SystemVerilog testbench. Returns (verdict, detail)."""
    obj = d / "build" / "obj_mut"
    obj.mkdir(parents=True, exist_ok=True)
    rc, out = run(["verilator", "--binary", "--assert", "--timing", "-sv",
                   "-Wno-fatal", "verif/verilator.vlt", *SIM,
                   "--top", "spcu_sv_tb", "-o", "tb", "--Mdir", str(obj)], d)
    if rc != 0:
        return "BUILD-FAIL", (out.strip().splitlines() or ["?"])[-1][:120]
    rc, out = run([str(obj / "tb")], d)
    sva = sorted(set(re.findall(r"Assertion failed in \S+\.(\w+):", out)))
    if sva:
        return "CAUGHT", "SVA: " + ",".join(sva)
    if "TEST FAILED" in out:
        m = re.findall(r"(MISMATCH|SECURITY)[^\n]*", out)
        return "CAUGHT", "scoreboard: " + (m[0][:90] if m else "TEST FAILED")
    if "TEST PASSED" in out:
        return "missed", "TEST PASSED"
    return "ERROR", out.strip()[-120:]


def apply_mutation(d, m):
    """Apply the substitution, tolerating YAML's indentation normalisation.

    A YAML block scalar strips the block's COMMON leading indentation, so the
    RTL snippets in the catalogue arrive without their real indent and never
    match verbatim. Matching on stripped lines and re-applying the file's own
    indent to the replacement keeps the catalogue readable while still being an
    exact, auditable substitution.
    """
    f = d / m["file"]
    lines = f.read_text().split("\n")
    find = m["find"].rstrip("\n").split("\n")
    repl = m["replace"].rstrip("\n").split("\n")
    key = [l.strip() for l in find]
    n = len(key)

    for i in range(len(lines) - n + 1):
        if [l.strip() for l in lines[i:i + n]] != key:
            continue
        # Indent actually used in the file, minus the indent YAML left us with.
        file_ind = len(lines[i]) - len(lines[i].lstrip())
        yaml_ind = len(find[0]) - len(find[0].lstrip())
        pad = " " * max(0, file_ind - yaml_ind)
        lines[i:i + n] = [(pad + r) if r.strip() else r for r in repl]
        f.write_text("\n".join(lines))
        break
    else:
        return False

    if m.get("regen"):
        rc, _ = run([str(ROOT / ".venv/bin/python"), "tools/genregs.py"], d)
        if rc != 0:
            return False
    return True


def one(m):
    d = WORK / m["id"]
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    for sub in ["rtl", "verif", "spec", "tools"]:
        shutil.copytree(ROOT / sub, d / sub,
                        ignore=shutil.ignore_patterns("*_bmc", "*_prove",
                                                      "*_cover", "*_cdc_bmc",
                                                      "cex", "__pycache__"))
    if not apply_mutation(d, m):
        return {**m, "formal": "PATCH-FAIL", "formal_hits": [],
                "sim": "PATCH-FAIL", "sim_detail": "find string not present"}
    fv, fh = formal(d)
    sv, sd = sim(d)
    return {**m, "formal": fv, "formal_hits": fh, "sim": sv, "sim_detail": sd}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=3)
    a = ap.parse_args()

    cat = yaml.safe_load((ROOT / "mutations" / "mutations.yaml").read_text())
    muts = cat["mutations"]
    if a.only:
        keep = set(a.only.split(","))
        muts = [m for m in muts if m["id"] in keep]

    WORK.mkdir(parents=True, exist_ok=True)
    print(f"running {len(muts)} mutations, {a.jobs} at a time\n")

    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        results = list(ex.map(one, muts))
    results.sort(key=lambda r: r["id"])

    print(f"{'ID':<4} {'FORMAL':<9} {'SIM':<11} {'CLASS':<42} DETECTED BY")
    print("-" * 118)
    for r in results:
        by = ", ".join(r["formal_hits"]) if r["formal_hits"] else r["sim_detail"]
        print(f"{r['id']:<4} {r['formal']:<9} {r['sim']:<11} "
              f"{r['class'][:42]:<42} {by[:44]}")

    out = ROOT / "build" / "mutation_results.json"
    out.write_text(json.dumps(results, indent=2))
    print(f"\nwrote {out.relative_to(ROOT)}")

    escaped = [r for r in results if r["formal"] == "missed" and r["sim"] == "missed"]
    if escaped:
        print(f"\n{len(escaped)} mutation(s) escaped EVERY technique:")
        for r in escaped:
            print(f"  {r['id']}  {r['name']}")
        print("  -> a specification gap, not a checking gap. See docs/BUGS_FOUND.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
