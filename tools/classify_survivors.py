#!/usr/bin/env python3
"""Group and classify the surviving mutants from an MCY run.

MCY answers two questions per mutant:
    test_fm  did any property fire?          (FAIL => detected)
    test_eq  is it observable at the ports?  (FAIL => observable)

That gives three machine-decided classes: COVERED, EQUIV, GAP. It does NOT
decide WHY a GAP survived, and that judgement is the actual output of mutation
analysis. This script groups the survivors by the RTL line and mutation mode
they came from, so the judgement is made per group with the evidence attached
rather than mutant by mutant from memory.

Categories, as required by the Phase 2 brief:
    specification gap   no requirement forbids the mutated behaviour
    property gap        a requirement covers it but no property expresses it
    unreachable         the mutated logic is not reachable in the real design
    equivalent          no observable difference (decided by test_eq)
    tooling limitation  could not be evaluated in this flow

Usage:
    python3 tools/classify_survivors.py [--db mutations/mcy/database/db.sqlite3]
"""

import argparse
import collections
import pathlib
import re
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "mutations" / "mcy" / "database" / "db.sqlite3"


def load(db_path):
    """Return {mutation_id: (tag, mutation_string)}."""
    con = sqlite3.connect(str(db_path))
    cur = con.cursor()
    muts = dict(cur.execute("SELECT mutation_id, mutation FROM mutations").fetchall())
    tags = collections.defaultdict(set)
    for mid, tag in cur.execute("SELECT mutation_id, tag FROM tags").fetchall():
        tags[mid].add(tag)
    con.close()
    return {mid: (sorted(tags.get(mid, {"<untagged>"})), m) for mid, m in muts.items()}


def parse(mut):
    """Pull the mutation mode and originating source line out of the descriptor."""
    mode = re.search(r"-mode (\w+)", mut)
    srcs = re.findall(r"-src ([^\s]+)", mut)
    src = srcs[-1] if srcs else "?"
    # keep file:line, drop the column range
    m = re.match(r"(.*?):(\d+)", src)
    src = f"{m.group(1)}:{m.group(2)}" if m else src
    src = src.replace("../../", "")
    return (mode.group(1) if mode else "?"), src


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(DEFAULT_DB))
    args = ap.parse_args()

    db = pathlib.Path(args.db)
    if not db.exists():
        sys.exit(f"no MCY database at {db}\nrun:  make mcy")

    data = load(db)
    counts = collections.Counter()
    groups = collections.defaultdict(collections.Counter)

    for mid, (tags, mut) in data.items():
        tag = tags[0] if tags else "<untagged>"
        counts[tag] += 1
        if tag in ("GAP", "EQUIV", "TOOLING"):
            mode, src = parse(mut)
            groups[tag][(src, mode)] += 1

    total = sum(counts.values())
    print(f"MCY mutants: {total}\n")
    for tag in ("COVERED", "EQUIV", "GAP", "TOOLING", "<untagged>"):
        if counts[tag]:
            print(f"  {tag:<12} {counts[tag]:>4}")

    den = counts["COVERED"] + counts["GAP"]
    if den:
        print(f"\ndetection over non-equivalent, evaluable mutants: "
              f"{100.0 * counts['COVERED'] / den:.1f}%  (denominator {den})")
        print(f"  excluded: {counts['EQUIV']} equivalent, {counts['TOOLING']} unevaluable")

    for tag in ("GAP", "TOOLING"):
        if not groups[tag]:
            continue
        print(f"\n--- {tag}: grouped by originating RTL line and mutation mode ---")
        print(f"{'count':>5}  {'mode':<10} source")
        for (src, mode), n in sorted(groups[tag].items(), key=lambda kv: -kv[1]):
            print(f"{n:>5}  {mode:<10} {src}")

    print("\nGrouping is the input to classification, not the classification.")
    print("The per-group verdicts are recorded in docs/BUGS_FOUND.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
