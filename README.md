# SPCU Verification Lab

**Secure Power Control Unit** — a small DVFS/power-control IP, verified with
open-source tools across formal, SystemVerilog simulation, a UVM-architecture
Python testbench, and bare-metal C running against the RTL.

This is a verification study, not an RTL project. The design is ~450 lines and
deliberately small enough to read line by line. The work is in the properties,
the counterexamples, and the argument about what has and has not been
established.

> Independent personal project. Not affiliated with, endorsed by, or derived
> from any company. No proprietary tooling or IP was used.

---

## The finding

Five realistic defects were injected into a design whose verification argument
was complete and green.

**Two of them passed every property written from the original specification.**
Not because the checking was weak — because the specification never stated the
requirement they violate.

| Mutation | Why it escaped |
|---|---|
| Voltage not lowered on a downward transition | The spec said the voltage must be **sufficient**. It never said **minimal**. Every property held: voltage was *higher*, which is the safe direction. |
| Off-by-one in the transition step check | A two-step jump is internally consistent — voltage still leads frequency, the settled point still matches, the state is still legal. Nothing structural distinguishes it. |

A third defect — a stale regulator acknowledge — escaped every property written
about the *design's own variables*, because internally the design stays perfectly
consistent while recording something false about the physical world.

The properties that catch all three exist **only because the mutations were
run**. Verification completeness is bounded by specification adequacy, and no
amount of coverage inside an inadequate specification detects the difference.

Full analysis: **[docs/BUGS_FOUND.md](docs/BUGS_FOUND.md)**.

---

## Four unseeded design bugs, found by formal

None of these were planted. They were mistakes in RTL written to be correct.

| # | Bug | How it was found |
|---|---|---|
| B1 | **Reset domain crossing.** A `pclk` reset asserted mid-transaction cleared the request toggle while the launched value was still inside the `sclk` synchroniser, so the controller saw two edges for one request. | Formal, first run |
| B2 | **Power-down mid-sequence.** `pd_on` was checked once at acceptance; the domain can power down during a multi-cycle ramp, and the controller kept driving the regulator. | Formal |
| B3 | **Stale operating point survived.** An aborted ramp left voltage raised; a later no-op request laundered it clean. | Formal, after B2's fix |
| S1 | **A requirement no implementation could satisfy.** Stated over the current value of `pd_on`, it demanded a reaction in the same cycle as the input causing it. | Formal, in 4 steps |

B1's lesson generalises: **a CDC synchroniser protects against clock asynchrony
and does nothing about reset asynchrony.**

S1's lesson recurred three separate times: **a property must be stated over the
value the design was entitled to act on, at the instant it was entitled to act.**

---

## Where each technique won

| | Result |
|---|---|
| **Simulation beat formal** | Mutation M1. BMC at depth 30 found nothing; unbounded PDR caught it immediately. The defect needs a downward transition, first reachable at step 26. **A BMC pass is not a proof**, demonstrated rather than asserted. |
| **Formal beat simulation** | Mutation M3. The testbench's regulator model never presents a stale acknowledge, so the stimulus simply cannot be generated — no number of random seeds fixes a modelled assumption. Formal finds it because `vack` is left free. |
| **Both failed** | Mutations M1 and M5 against the original specification. Neither is a checking weakness. See above. |

---

## What is actually proven

Of 22 requirement-derived Tier-A assertions, **20 are informative and PROVEN** —
unbounded, via PDR/IC3, over all reachable states of the collapsed-clock model,
under the four environment assumptions in `verif/formal/spcu_fv_env.sv`. One of
the 20 (`p7_bounded_response`) additionally rests on the regulator fairness
assumption and is false without it.

Stated with equal prominence:

- **2 of the 22 are VACUOUS** and cannot fail on any input. Kept as evidence,
  excluded from every claim. Verilator independently agrees (`CMPCONST`).
- **CDC results are BOUNDED at depth 20, not proven.** Induction does not close
  in the multiclock model.
- **Liveness is NOT verified.** Only bounded response, under a stated regulator
  fairness assumption. `s_eventually` is unparseable by every formal tool here.
- **One assumption was deliberately refused** because writing it would have made
  mutation M3 unfalsifiable.

Per-requirement detail: **[docs/TRACEABILITY.md](docs/TRACEABILITY.md)**.
Everything not established: **[docs/LIMITATIONS.md](docs/LIMITATIONS.md)**.

---

## The design

```
      pclk domain (APB3)                    sclk domain (always-on)
   ┌──────────────────────┐              ┌──────────────────────────┐
   │ spcu_regs            │  req toggle  │ spcu_ctrl_fsm            │
   │  CTRL STATUS LOCK    │ ───2FF────►  │  P0..P3 DVFS sequencer   │
   │  PRIV_CFG  ID        │              │  voltage-before-frequency│
   │  busy / payload      │  ◄───2FF───  │  in-series authority gate│
   └──────────────────────┘  ack toggle  └──────────────────────────┘
        pprot[0]                               vreq/vack ──► regulator
                                               pd_on ──► managed domain
```

- **AMBA APB3** slave, with `pprot[0]` as the real privilege signal.
- **Authority is enforced in series** at the decision point, not at the bus:
  `CTRL` is writable by any agent, because the thing that must be gated is the
  state change, not the register.
- **Two-phase toggle handshake** across the boundary; payload is
  data-with-handshake, never per-bit synchronised.
- **Single-step rule**: P0→P2 is a forbidden transition, not a slow one.

Register map is generated from `spec/spcu_regs.yaml` — RTL, C header, pyuvm
model and docs all come from that one file, and `make check-gen` fails if any
drifts.

---

## Layout

```
spec/spcu_regs.yaml        single source of truth for the register map
rtl/                       SystemVerilog RTL (spcu_regs.sv is generated)
verif/props/               Tier-A properties: ONE source, read by BOTH engines
verif/formal/              SymbiYosys flow, environment assumptions
verif/formal/cex/          preserved counterexamples
verif/sv/                  SystemVerilog class-based TB + Tier-B SVA
verif/pyuvm/               pyuvm/cocotb UVM-architecture TB
verif/c/                   bare-metal C driver + Verilator MMIO harness
mutations/                 mutation catalogue with pre-registered predictions
tools/                     register generator, mutation runner
docs/                      requirements, plan, traceability, bugs, coverage, limits
```

### The two property tiers

Yosys parses **no** concurrent SVA — measured here, not assumed:

```
read_verilog -sv : syntax error, unexpected '@'
read_slang       : encountered unsupported SVA feature   (on |=> and ##[1:3])
```

Verilator 5.051 parses a great deal of it. Both accept immediate assertions with
`$past`/`$rose`/`$fell`.

- **Tier A** — that intersection. One file, both engines, no `ifdef`. Everything
  proven lives here.
- **Tier B** — rich concurrent SVA, **simulation only**. Formal is blind to it.

---

## Running it

```bash
make setup     # venv (cocotb requires Python <= 3.13; 3.14 is refused)
make all       # check-gen, lint, formal x4, sim, pyuvm, ctest, mutations
```

Individual flows: `make formal-prove`, `make sim`, `make pyuvm`, `make ctest`,
`make mutations`.

**Requires** the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)
(Yosys 0.68, SymbiYosys, Verilator 5.051, Z3, ABC). Point `OSS_CAD` at it:

```bash
make OSS_CAD=/path/to/oss-cad-suite/bin all
```

Verified on macOS 15.7.3, Apple Silicon.

---

## Honest scope

**Not used:** JasperGold, VC Formal, VCS, Xcelium, Questa, Verdi, Spyglass, or
any Arm proprietary tooling. No result here implies experience with them.

**Not SystemVerilog UVM.** The pyuvm testbench is a real UVM *architecture*, and
it is not `uvm_pkg`. No freely available simulator runs SystemVerilog UVM.

**No UPF.** No open tool consumes IEEE 1801. A UPF file that no tool reads would
demonstrate syntax while implying a capability this flow does not have, so none
was written. Power behaviour is modelled and verified behaviourally instead.

**No GLS, no DFT/DFD, no SoC integration.** RTL only, one IP block.

**AI assistance:** this project was built with AI assistance throughout. Every
headline result is reproducible from a clean clone by running `make all`, and
the counterexamples are preserved in the repository rather than described.

Full accounting: **[docs/TRACEABILITY.md §3](docs/TRACEABILITY.md)**.
