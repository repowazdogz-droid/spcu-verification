# Coverage

Every number here states what it was measured over, at what unit, and what it
says nothing about. A coverage figure is a claim about **stimulus**, never about
correctness, and the two are routinely conflated.

---

## 1. Functional coverage (SystemVerilog covergroup)

**Instrument:** `cg_request` in `verif/sv/spcu_sv_tb.sv`.
**Unit of analysis:** one DVFS request.
**Denominator:** 10 bins — 4 target P-states, 2 privilege levels, 2 outcomes
(accepted/refused), plus the 8-bin `target × privilege` cross, scored by
Verilator as instance coverage.
**Sampling event:** explicit `cg.sample()` at each request.

| Stimulus | Requests | Coverage |
|---|---|---|
| `+TEST=unpriv` (1 directed) | 1 | 40.0% |
| `+TEST=illegal` (1 directed) | 1 | 40.0% |
| `+TEST=walk` (directed P0→P3→P0) | 6 | 70.0% |
| `+TEST=random` (constrained random) | 40 | 100.0% |
| `+TEST=all` | 53 | 100.0% |

### The defect this table exists to record

The first version of this covergroup reported **100.0% for every test,
including single-request directed ones**. It sampled `@(posedge pclk)` against
variables that only change once per request, so every bin filled from stale
values sitting in those variables between transactions. It was measuring "did
these variables ever hold these values", not "were these request types
exercised".

It was found by a **negative control**, not by inspection: a single directed
test that exercises one target and one privilege level *cannot* legitimately
reach 100%, so the number was refuted by a case whose answer was known in
advance.

**A coverage metric needs its own negative control.** If a metric cannot be made
to read low by stimulus that is obviously narrow, it is not measuring the thing
its name claims.

### What 100% here does not mean

- It does not mean the design is correct. Mutation M3 escapes this testbench
  entirely while coverage reads 100%.
- It does not mean the request space is covered. `target × privilege × outcome`
  is 16 combinations; several are unreachable (a privileged single-step request
  to an adjacent state cannot be refused), so the reachable denominator is
  smaller than the nominal one and the metric is scored against bins, not
  against behaviours.
- It says nothing about *sequences* of requests, timing, or the clock-domain
  relationship. Those are covered, where they are covered at all, by the formal
  cover points and the Tier-B cover property.

---

## 2. Formal cover reachability

**Instrument:** `sby -f verif/formal/spcu.sby cover`, depth 90.
**Meaning:** the solver constructed a concrete trace reaching each point. This
is *reachability*, which is stronger evidence than a simulation hit: it proves
the state is achievable at all, not merely that one testbench happened to reach
it.

| Cover point | Reached at step |
|---|---|
| `c_priv_write_ok` | 7 |
| `c_unpriv_write_refused` | 7 |
| `c_req_accepted` | 10 |
| `c_refused` | 12 |
| `c_up_transition` | 14 |
| `c_dn_transition` | 26 |
| `c_at_p3` | **41** |

All 7 reachable.

### The near-miss worth recording

At the original depth of 40, `c_at_p3` was reported **unreached**. It is
reachable at step 41.

A cover bound reports "not reached within N", and that is *not* the same claim
as "not reachable" — but it is displayed identically and it is easy to read as a
design or stimulus problem. The margin here was one step. Anyone treating an
unreached cover point at a fixed bound as evidence of unreachability would have
drawn exactly the wrong conclusion.

The same reasoning explains the M1 result in `docs/BUGS_FOUND.md`: BMC at depth
30 missed a defect that only manifests on a downward transition, and the first
downward transition is not reachable until step 26.

---

## 3. Property coverage

Counted from source, not estimated.

| Category | Count |
|---|---|
| Tier-A assertions, requirement-derived | 22 |
| Tier-A assertions, auxiliary (proof plumbing, not a requirement) | 1 |
| Tier-A cover points | 7 |
| Tier-B assertions (concurrent SVA, simulation only) | 4 |
| Tier-B cover points | 1 |
| Environment assumptions | 4 |

Of the 22 requirement-derived Tier-A assertions:

| | Count | Note |
|---|---|---|
| Informative and **PROVEN** unbounded | 19 | `prove` task returned PASS via PDR, collapsed-clock model |
| **PROVEN under a named assumption** | 1 | `p7_bounded_response` rests on `a_vack_fairness`; without it the property is false |
| **VACUOUS** | 2 | `p1_state_legal`, `p1_pstate_legal` — cannot fail on any input |

**2 of 22 carry no information.** That ratio is reported because a property
count is otherwise a misleading headline: "22 properties, all passing" would be
true and would overstate the assurance by exactly those two.

Every proof also rests on the four APB environment assumptions, so no property
here is unconditional. `p5_no_double_accept` and `p5_no_orphan_ack` are
additionally checked in the multiclock `clk2fflogic` model, where the result is
**bounded at depth 20 and not a proof** — that is the only model in which the
CDC claim means anything, and induction does not close in it.

Per-requirement detail is in `docs/TRACEABILITY.md` §1.

---

## 4. Mutation coverage

The most decision-relevant coverage measure here, and the least standard. Two
independent experiments, and they disagree in an instructive way.

### 4a. Hand-authored catalogue (5 mutations)

**Denominator:** 5. Detected by at least one technique after remediation: 5/5.
Detected by formal at BMC depth 30: 4/5. By simulation: 4/5.

The honest score is against the **original** specification, before the property
set was amended in response: **2/5**.

Five hand-authored mutations are not a sample of anything. They were chosen to
span the defect classes in the project brief, by the same person who wrote the
properties, which biases them toward defects that person was already considering.

**Section 4b measures exactly how large that bias was.**

### 4b. MCY netlist mutation coverage (200 mutations)

`make mcy`. Yosys samples 200 mutations evenly over the RTL netlist. Selection
is restricted to RTL-sourced objects (`select a:src=*rtl/spcu_*`, 131 objects),
so the property modules (157 objects) are never mutated and the property set is
byte-identical across all 200 runs.

Each mutant is run through **two** tests: the property set, and an equivalence
miter against the golden design. The second is what separates a real gap from a
no-op.

| outcome | count |
|---|---|
| detected by a property | 84 |
| equivalent (no observable difference within 30 cycles) | 23 |
| **survived and observable** | **93** |
| not evaluable in this flow | 0 |

**Detection rate: 47.5%**, denominator 177 = 84 detected + 93 observable
survivors, excluding 23 equivalents.

### Where the survivors are, and why that is the result

| RTL file | observable survivors |
|---|---|
| `rtl/spcu_regs.sv` — register file read mux and write decode | **42** |
| `rtl/spcu_top.sv` — status latching and wiring | 19 |
| `rtl/spcu_sync2.sv` — synchronisers | 17 |
| `rtl/spcu_ctrl_fsm.sv` — the DVFS FSM | 15 |

**16% of surviving mutants are in the FSM. 100% of the hand-authored mutations
were.** The hand-authored experiment reported 5/5 after remediation and never
touched the register read path; MCY put 45% of its survivors there. The largest
single cluster — 15 mutants — is `spcu_regs.sv:103`, the `prdata` assignment,
and **no formal property constrains `prdata` at all**.

Read-back *is* checked, by the C driver, the SV scoreboard and the pyuvm
scoreboard. It is checked in simulation only, and the mutation experiment is
what made that visible.

Classification of all 93 is in `docs/BUGS_FOUND.md` §S7.

### Denominator honesty

- One seed (1). A different seed samples different cells; nothing here
  establishes a confidence interval.
- "Equivalent" means **no observable difference within 30 cycles**, not proved
  equivalent. `sat -tempinduct` did not converge within 10 minutes. Some of the
  23 may be observable later, which would move them into the survivor column and
  **lower** the 47.5% figure. The bound can only bias the number favourably, and
  is stated for that reason.
- Equivalents are excluded from the denominator because a mutation that changes
  nothing observable cannot be detected by anything; including them would inflate
  the rate.
- The miter compares the observable outputs of `spcu_fv_top`. Behaviour not
  visible at those ports is out of scope for the equivalence decision.
- **The identity mutation is the control.** `-mode none` must be equivalent to
  itself, and three separate harness defects were caught because it was not. See
  `docs/BUGS_FOUND.md` §S7.

## 5. Code coverage

**Not measured.** Verilator supports line and toggle coverage via
`--coverage`; it was not enabled.

This is a deliberate omission rather than an oversight. Line coverage on a
450-line design driven by four independent flows would read very high and would
be the least informative number in this document — it measures whether stimulus
reached a line, not whether reaching it was checked. The mutation matrix answers
the question line coverage is usually used as a proxy for, and answers it
directly.

Stated so the absence is visible rather than quietly missing.

---

## 6. What no number here covers

- **Gate-level behaviour.** No synthesis, no netlist, no timing. All results are
  RTL-level.
- **Metastability.** `clk2fflogic` models arbitrary clock phase; it does not
  model a flop resolving to an intermediate voltage. No metastability injection
  was performed.
- **Payload stability across the CDC.** R18 is argued by construction and
  checked by no property. The weakest link in the CDC argument.
- **APB protocol compliance of the DUT.** The APB rules constrain the testbench;
  no independent protocol checker verifies the slave.
- **True liveness.** Only bounded response is verified, and only under a stated
  regulator fairness assumption.
