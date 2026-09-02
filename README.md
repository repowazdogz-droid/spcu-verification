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

## Then the same argument was turned on that experiment

Those five mutations were written by the same person who wrote the properties.
Phase 2 ran **200 netlist mutations sampled by Yosys**, each checked against the
property set *and* against an equivalence miter so no-ops are separated out.

| | |
|---|---|
| detected by a property | 84 |
| equivalent (no observable difference) | 23 |
| **survived and observable** | **93** |

Detection rate **47.5%**. And the survivors are not where the hand-authored
experiment looked:

| RTL file | survivors |
|---|---|
| register file (`spcu_regs.sv`) | **42** |
| status latching (`spcu_top.sv`) | 19 |
| synchronisers (`spcu_sync2.sv`) | 17 |
| the DVFS FSM (`spcu_ctrl_fsm.sv`) | 15 |

**16% of survivors are in the FSM. 100% of the hand-authored mutations were.**
The largest single cluster is the `prdata` assignment, and no formal property
constrains `prdata` at all — read-back is verified in simulation only.

A self-authored adversarial check probes the part of the design its author was
already thinking about. The Phase 1 figure of 5/5 was true, and it was measuring
the wrong population.

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
| **Unbounded formal beat bounded formal** | Mutation M1. BMC at depth 30 found nothing; unbounded PDR caught it immediately. The defect needs a downward transition, first reachable at step 26. **A BMC pass is not a proof**, demonstrated rather than asserted. |
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
- **R18 was refuted when formalised.** It holds only under R22, a stated
  integration constraint on whoever instantiates the IP; the refutation is
  reproducible with `make formal-rdc`.
- **The bounded-response bound is tight**: 13 proves, 12 is refuted, so worst
  case is exactly 12 cycles and is attained.

Per-requirement detail: **[docs/TRACEABILITY.md](docs/TRACEABILITY.md)**.

## Evidence on disk

The formal flow was re-run from a clean checkout on 2026-09-02 and every task's
SymbiYosys status and summary is committed under
[`verif/formal/results/`](verif/formal/results/) with the engine versions in
[`docs/TOOLS.md`](docs/TOOLS.md). What each task establishes:

| task | mode | engine | result | what it means |
|---|---|---|---|---|
| `prove` | unbounded (k-induction + PDR/IC3) | abc pdr | PASS | the Tier-A assertions hold over all reachable states of the collapsed-clock model |
| `bmc` | bounded, depth 30 | smtbmc z3 | PASS | no counterexample within 30 cycles; not a proof |
| `cover` | reachability, depth 90 | smtbmc z3 | PASS | all 7 cover statements reached, traces recorded |
| `cdc_bmc` | bounded, depth 20, independent clocks | smtbmc z3 | PASS | the CDC claims, bounded only; induction does not close in this model |
| `rdc_freerst` | bounded, depth 20, free resets | smtbmc z3 | PASS | regression guard for the B1 reset-crossing fix |

The preserved counterexamples under `verif/formal/cex/` are the refutations that
drove S1 and R18 and are tracked deliberately. The 200-mutant `mcy` run is
recorded in [`mutations/mcy/RESULTS.txt`](mutations/mcy/RESULTS.txt); the
hand-authored catalogue with its pre-run predictions is
[`mutations/mutations.yaml`](mutations/mutations.yaml).

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

Tools: OSS CAD Suite (Yosys, SymbiYosys, Verilator, mcy, Z3), see `docs/TOOLS.md`.
Point the Makefile and the mutation runner at it with `OSS_CAD=/path/to/oss-cad-suite/bin`
(default `~/eda/oss-cad-suite/bin`).

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
