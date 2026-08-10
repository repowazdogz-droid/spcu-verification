#!/usr/bin/env python3
"""Generate RTL, C header, pyuvm register model and docs from spec/spcu_regs.yaml.

The register map is defined once. Every consumer is generated. Hand-editing a
generated file is a bug, and --check detects it by comparing the recorded source
hash and the regenerated content.

Usage:
    python3 tools/genregs.py            # regenerate everything
    python3 tools/genregs.py --check    # fail if anything is stale (used by CI)
"""

import argparse
import hashlib
import pathlib
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required:  pip install pyyaml")

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = ROOT / "spec" / "spcu_regs.yaml"

BANNER = (
    "GENERATED FILE - DO NOT EDIT.\n"
    "Source : spec/spcu_regs.yaml (sha256 {hash})\n"
    "Tool   : tools/genregs.py\n"
    "Edit the YAML and re-run the tool. Hand edits are lost and are a defect."
)


def load():
    raw = SPEC.read_bytes()
    return yaml.safe_load(raw), hashlib.sha256(raw).hexdigest()[:16]


def cmt(h, prefix="// "):
    """Comment every line of the banner, not just the first."""
    return "\n".join(prefix + ln for ln in BANNER.format(hash=h).splitlines())


def sig(name, field):
    return f"{name.lower()}_{field['name'].lower()}"


def width(f):
    return f["msb"] - f["lsb"] + 1


# --------------------------------------------------------------------------- RTL


def gen_rtl(spec, h):
    blk, regs = spec["block"], spec["registers"]
    dw, aw = blk["data_width"], blk["addr_width"]
    ports, decl, rst, wr, rd = [], [], [], [], []

    for r in regs:
        for f in r["fields"]:
            s, w = sig(r["name"], f), width(f)
            t = f"logic [{w-1}:0]" if w > 1 else "logic"
            if r.get("constant"):
                continue
            if f["access"] == "RW":
                ports.append(f"  output {t} {s}_q,")
                decl.append(f"  {t} {s}_q_r;")
                rv = (r["reset"] >> f["lsb"]) & ((1 << w) - 1)
                rst.append(f"      {s}_q_r <= {w}'d{rv};")
                wr.append(f"          if (addr_sel_{r['name'].lower()}) "
                          f"{s}_q_r <= pwdata[{f['msb']}:{f['lsb']}];")
            elif f["access"] == "W1P":
                ports.append(f"  output logic {s}_wpulse,")
                ports.append(f"  output logic {s}_wpulse_priv,")
                decl.append(f"  logic {s}_wpulse_r, {s}_wpulse_priv_r;")
                rst.append(f"      {s}_wpulse_r <= 1'b0;")
                rst.append(f"      {s}_wpulse_priv_r <= 1'b0;")
            elif f["access"] == "RO":
                ports.append(f"  input  {t} {s}_i,")

    # read mux
    for r in regs:
        bits = []
        for f in r["fields"]:
            s = sig(r["name"], f)
            src = ("{}'d{}".format(width(f), (r["reset"] >> f["lsb"]) & ((1 << width(f)) - 1))
                   if r.get("constant")
                   else (f"{s}_q_r" if f["access"] == "RW"
                         else f"{s}_i" if f["access"] == "RO" else f"{width(f)}'d0"))
            bits.append(f"      rd[{f['msb']}:{f['lsb']}] = {src};")
        rd.append(f"    {aw}'h{r['offset']:02X}: begin\n" + "\n".join(bits) + "\n    end")

    sel = "\n".join(
        f"  wire addr_sel_{r['name'].lower()} = (paddr == {aw}'h{r['offset']:02X});"
        for r in regs)
    priv = "\n".join(
        f"  wire priv_req_{r['name'].lower()} = 1'b{1 if r.get('priv_write') else 0};"
        for r in regs)
    any_priv = " || ".join(
        f"(addr_sel_{r['name'].lower()} && priv_req_{r['name'].lower()})" for r in regs)

    w1p = []
    for r in regs:
        for f in r["fields"]:
            if f["access"] == "W1P":
                s = sig(r["name"], f)
                fire = (f"wr_ok && addr_sel_{r['name'].lower()}"
                        f" && pwdata[{f['msb']}:{f['lsb']}] == 1'b1")
                # The privilege of the writing agent is captured AT the write,
                # not sampled continuously: it is the authority evidence the
                # controller consumes one clock later.
                w1p.append(
                    f"      {s}_wpulse_r <= {fire};\n"
                    f"      if ({fire}) {s}_wpulse_priv_r <= pprot0;")

    return f"""{cmt(h)}

module spcu_regs (
  input  logic pclk,
  input  logic presetn,
  // ---- APB3 ----
  input  logic psel,
  input  logic penable,
  input  logic pwrite,
  input  logic [{aw-1}:0] paddr,
  input  logic [{dw-1}:0] pwdata,
  input  logic pprot0,             // AMBA pprot[0]: 1 = privileged
  output logic [{dw-1}:0] prdata,
  output logic pready,
  output logic pslverr,
  // ---- register interface ----
{chr(10).join(ports).rstrip(',')}
);

{sel}
{priv}

  // An APB3 write commits in the ACCESS phase (psel & penable & pwrite).
  wire wr_phase = psel && penable && pwrite;
  wire priv_viol = wr_phase && ({any_priv}) && !pprot0;
  wire wr_ok = wr_phase && !priv_viol;

{chr(10).join(decl)}
  logic [{dw-1}:0] rd;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
{chr(10).join(rst)}
    end else begin
{chr(10).join(w1p)}
      if (wr_ok) begin
{chr(10).join(wr)}
      end
    end
  end

  always_comb begin
    rd = {dw}'d0;
    case (paddr)
{chr(10).join(rd)}
      default: rd = {dw}'d0;
    endcase
  end

  assign prdata  = (psel && !pwrite) ? rd : {dw}'d0;
  assign pready  = 1'b1;
  assign pslverr = priv_viol;

{chr(10).join(f'  assign {p.split()[-1].rstrip(",")} = {p.split()[-1].rstrip(",")}_r;' for p in ports if p.strip().startswith('output'))}

endmodule
"""


# ------------------------------------------------------------------------ C header


def gen_c(spec, h):
    blk, regs = spec["block"], spec["registers"]
    out = [f"/* {BANNER.format(hash=h)} */", "", "#ifndef SPCU_REGS_H",
           "#define SPCU_REGS_H", "", "#include <stdint.h>", "",
           "/* Linkage guard. This header is consumed by C firmware and by the",
           " * C++ Verilator harness, and the harness DEFINES the accessors the",
           " * firmware calls. Without extern \"C\" the two disagree about name",
           " * mangling and the link fails with an undefined symbol whose",
           " * signature looks correct. */",
           "#ifdef __cplusplus", 'extern "C" {', "#endif", ""]
    for r in regs:
        out.append(f"/* {r['name']}: {str(r.get('description','')).strip()} */")
        out.append(f"#define SPCU_{r['name']}_OFFSET 0x{r['offset']:02X}u")
        for f in r["fields"]:
            n, w = f"SPCU_{r['name']}_{f['name']}", width(f)
            mask = ((1 << w) - 1) << f["lsb"]
            out += [f"#define {n}_SHIFT {f['lsb']}u",
                    f"#define {n}_MASK  0x{mask:08X}u"]
        out.append("")
    out += [
        "/* MMIO accessors.",
        " *",
        " * On real hardware these are volatile loads and stores to the",
        " * peripheral aperture. Under simulation (-DSPCU_SIM) they become",
        " * external calls that the Verilator harness implements by driving APB",
        " * transactions into the model.",
        " *",
        " * The DRIVER SOURCE IS IDENTICAL in both cases. That is the point: the",
        " * firmware under test is the firmware, not a simulation-only rewrite of",
        " * it. Only the bus accessor is substituted.",
        " */",
        "#ifdef SPCU_SIM",
        "uint32_t spcu_rd(uintptr_t base, uint32_t off);",
        "void     spcu_wr(uintptr_t base, uint32_t off, uint32_t v);",
        "#else",
        "static inline uint32_t spcu_rd(uintptr_t base, uint32_t off) {",
        "    return *(volatile uint32_t *)(base + off);", "}", "",
        "static inline void spcu_wr(uintptr_t base, uint32_t off, uint32_t v) {",
        "    *(volatile uint32_t *)(base + off) = v;", "}",
        "#endif", "",
        "#ifdef __cplusplus", "}", "#endif", "",
        "#endif /* SPCU_REGS_H */"]
    return "\n".join(out) + "\n"


# ------------------------------------------------------------------- pyuvm model


def gen_py(spec, h):
    regs = spec["registers"]
    out = ['"""' + BANNER.format(hash=h) + '"""', "", "REGISTERS = {"]
    for r in regs:
        out.append(f"    {r['name']!r}: {{")
        out.append(f"        'offset': 0x{r['offset']:02X},")
        out.append(f"        'access': {r['access']!r},")
        out.append(f"        'priv_write': {bool(r.get('priv_write'))},")
        out.append(f"        'reset': 0x{r['reset']:08X},")
        out.append("        'fields': {")
        for f in r["fields"]:
            out.append(f"            {f['name']!r}: "
                       f"{{'msb': {f['msb']}, 'lsb': {f['lsb']}, "
                       f"'access': {f['access']!r}}},")
        out += ["        },", "    },"]
    out += ["}", "", "",
            "def field(regname, fieldname, value):",
            '    """Extract a field from a full register value."""',
            "    f = REGISTERS[regname]['fields'][fieldname]",
            "    return (value >> f['lsb']) & ((1 << (f['msb'] - f['lsb'] + 1)) - 1)",
            "", "",
            "def place(regname, fieldname, value):",
            '    """Position a field value within a register word."""',
            "    f = REGISTERS[regname]['fields'][fieldname]",
            "    return (value & ((1 << (f['msb'] - f['lsb'] + 1)) - 1)) << f['lsb']", ""]
    return "\n".join(out)


# -------------------------------------------------------------------------- docs


def gen_md(spec, h):
    blk, regs = spec["block"], spec["registers"]
    out = [f"# {blk['name'].upper()} register map", "",
           f"<!-- {BANNER.format(hash=h)} -->", "",
           f"{blk['description']}. {blk['data_width']}-bit registers, "
           f"{blk['addr_width']}-bit address space.", "",
           "`priv` means the write requires AMBA `pprot[0] == 1`. An unprivileged "
           "write to such a register is refused and raises `pslverr`.", "",
           "| Offset | Name | Access | Priv write | Reset |",
           "|---|---|---|---|---|"]
    for r in regs:
        out.append(f"| 0x{r['offset']:02X} | `{r['name']}` | {r['access']} | "
                   f"{'yes' if r.get('priv_write') else 'no'} | 0x{r['reset']:08X} |")
    for r in regs:
        out += ["", f"## `{r['name']}` (0x{r['offset']:02X})", "",
                str(r.get("description", "")).strip(), "",
                "| Bits | Field | Access | Description |", "|---|---|---|---|"]
        for f in sorted(r["fields"], key=lambda x: -x["msb"]):
            bits = f"{f['msb']}" if f["msb"] == f["lsb"] else f"{f['msb']}:{f['lsb']}"
            out.append(f"| {bits} | `{f['name']}` | {f['access']} | {f['description']} |")
    return "\n".join(out) + "\n"


TARGETS = {
    "rtl/spcu_regs.sv": gen_rtl,
    "verif/c/spcu_regs.h": gen_c,
    "verif/pyuvm/spcu_reg_model.py": gen_py,
    "docs/REGISTERS.md": gen_md,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if any generated file is stale")
    args = ap.parse_args()

    spec, h = load()
    stale = []
    for rel, fn in TARGETS.items():
        path, new = ROOT / rel, fn(spec, h)
        if args.check:
            if not path.exists() or path.read_text() != new:
                stale.append(rel)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(new)
            print(f"  wrote {rel}")

    if args.check:
        if stale:
            print("STALE (regenerate with tools/genregs.py):")
            for s in stale:
                print(f"  {s}")
            return 1
        print(f"all {len(TARGETS)} generated files up to date (spec sha256 {h})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
