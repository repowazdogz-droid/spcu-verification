# SPCU Verification Plan

## 1. What this plan optimises for

Not green tests. The objective is to find out whether the verification argument
is *sound* — which means deliberately looking for the places where it is not:
properties that cannot fail, assumptions that make properties true for free,
coverage numbers that do not correspond to the requirement they stand for, and
defects that every technique misses because nobody wrote the requirement down.

Three findings of that kind are recorded in `docs/BUGS_FOUND.md`. They are the
point of the project, not a by-product of it.

## 2. Tool stack, and what each result is worth

| Tool | Version | Used for | Strength of a PASS |
|---|---|---|---|
| Yosys + SymbiYosys | 0.68 | formal | see below |
| `abc pdr` (IC3/PDR) | in Yosys 0.68 | unbounded proof | **proof** over all reachable states |
| `smtbmc` + Z3 | Yosys 0.68 / Z3 | k-induction, BMC | k-induction PASS is a **proof**; BMC PASS is **bounded** |
| Verilator | 5.051-devel | simulation, SVA, lint | evidence over the stimulus actually run |
| cocotb + pyuvm | 2.0.1 / 4.0.1 | UVM-architecture testbench | as above |
| `read_slang` | in Yosys 0.68 | SystemVerilog frontend for formal | — |

**The distinction that governs every claim in this repository:** a BMC pass
means "no counterexample within the depth". It is not a proof, and mutation M1
demonstrates the difference concretely — BMC at depth 30 missed it, unbounded
PDR caught it.

### Industrial tools NOT used

JasperGold, VC Formal, Questa Formal, VCS, Xcelium, Questa/ModelSim, Verdi,
Spyglass CDC, Conformal, and any Arm proprietary tooling. No result here is
evidence of experience with any of them. See `docs/TRACEABILITY.md` §3.

## 3. Property architecture: two tiers, forced by the tools

Measured on this machine, not read from documentation:

```
$ yosys -p "read_verilog -sv conc.sv"
conc.sv:3: ERROR: syntax error, unexpected '@'

$ yosys -p "read_slang conc.sv"
conc.sv:3:65: error: encountered unsupported SVA feature
  ap_req_ack: assert property (@(posedge clk) disable iff (rst) req |=> ack);
```

Yosys parses no concurrent SVA at all. Verilator 5.051 parses a great deal of
it. Both accept immediate `assert`/`assume`/`cover` in a clocked block together
with `$past`/`$stable`/`$rose`/`$fell`/`$changed`.

- **Tier A** (`verif/props/spcu_props*.sv`) — that intersection. **One source
  file, read by both engines.** No `ifdef`, no duplication. Everything proved
  formally lives here.
- **Tier B** (`verif/sv/spcu_sva_tier_b.sv`) — rich concurrent SVA. **Simulation
  only.** Formal is blind to it.

Neither tier subsumes the other. Tier A proves `freq_level <= volt_level`
always. Tier B says the voltage step was *observed before* the frequency step,
within a window, on the traces actually run. The first is stronger; the second
is more specific.

## 4. Formal strategy

Two clocking models, because one model cannot answer both questions.

| Task | Model | Engine | What it establishes |
|---|---|---|---|
| `prove` | `pclk == sclk` | k-induction + PDR | **unbounded proof** of the control logic |
| `bmc` | `pclk == sclk` | smtbmc/Z3, depth 30 | bounded check, names failing assertions |
| `cover` | `pclk == sclk` | smtbmc/Z3, depth 90 | every cover point is reachable |
| `cdc_bmc` | independent clocks, `clk2fflogic`, `multiclock on` | smtbmc/Z3, depth 20 | CDC under **arbitrary clock phase**, bounded |

The split is deliberate and is recorded per-property in
`docs/TRACEABILITY.md`. Proving everything in the multiclock model would be
sounder but does not converge; proving everything in the collapsed model would
converge while answering an easier question than the one asked. Each property is
proved in the weakest model that can still state it.

### Assumption discipline

Every environment constraint lives in one file, `verif/formal/spcu_fv_env.sv`,
so the strength of a PASS can be read off one page.

**The assumption deliberately NOT written** is `assume (!vack || vreq)` — "the
regulator only acknowledges what was asked for". It would be natural, and it
would make mutation M3 unfalsifiable: under it a stale acknowledge cannot exist,
so the property that catches M3 would pass vacuously. `vack` is left free apart
from the fairness bound. This is the concrete answer to "do the assumptions make
the properties trivially true" — see `docs/BUGS_FOUND.md` §4.

## 5. Simulation strategy

**SystemVerilog class-based** (`verif/sv/spcu_sv_tb.sv`): APB BFM, classes,
`randomize()` with `dist` constraints, an independent reference model, a
scoreboard, covergroups, directed tests plus 40 constrained-random requests.

**pyuvm / cocotb** (`verif/pyuvm/`): full UVM architecture — sequence items,
sequencer, driver, *passive* monitor, analysis port, TLM fifo, scoreboard,
agent, environment, phasing. Four tests.

Both drive `pclk` and `sclk` at a **non-integer period ratio** (10 ns vs 14 ns).
An integer ratio makes the sampling relationship repeat and hides exactly the
class of defect the crossing exists to survive.

The reference model predicts from the requirements, never by mirroring the FSM.
A model that mirrors the implementation agrees with it by construction and
checks nothing.

## 6. C / MMIO strategy

`verif/c/spcu_driver.c` is ordinary embedded C: generated header, volatile
memory-mapped accessors, status polling, bounded retries. Under `-DSPCU_SIM` the
accessors become external calls that `verif/c/sim_main.cpp` implements by
driving APB transactions into the Verilated model.

**The driver source is identical in both builds.** The regression compiles it
natively as well, without `SPCU_SIM`, to prove the same source still builds
against real volatile MMIO. Only the bus accessor is substituted, so the
firmware under test is the firmware and not a simulation-only rewrite of it.

Privilege is exercised from the harness, not the driver: firmware cannot lower
its own `pprot[0]`, so crediting the C layer with proving the privilege
requirement would be false.

## 7. Mutation strategy

`mutations/mutations.yaml` defines five realistic defects by exact, auditable
text substitution. `tools/run_mutations.py` applies each to a copy of the tree
and runs **both** flows.

The prediction for each mutation is recorded in the catalogue *before* running,
so that a surprise is visible as a surprise rather than rationalised afterwards.

A mutation that nothing catches is the most valuable row in the table: it
locates a hole in the **specification** rather than in the checking, and those
have different fixes.

## 8. Negative controls

No pass in this repository is trusted until the corresponding failure has been
observed. A check that has only ever been seen to pass is a check that has not
been tested.

| Flow | Known-bad input | Observed |
|---|---|---|
| formal | mutation M4 | `Assert failed: p5_no_double_accept` |
| formal | mutation M5 | `Assert failed: p12_single_step` |
| SV testbench | mutation M1 | `Assertion failed: p1b_settled_volt` |
| pyuvm | mutation M5 | `Assertion failed: p12_single_step` |
| coverage metric | single directed test | 40% / 70%, not 100% |

The last row is a negative control on a *metric* rather than a checker, and it
caught a real defect — see `docs/COVERAGE.md`.

## 9. Reproducing

```
make setup     # venv; cocotb requires Python <= 3.13
make all       # check-gen, lint, formal x4, sim, pyuvm, ctest, mutations
```

Every headline number in `docs/` comes from one of those targets.
