# Limitations

What this project does not establish, and why. Written so that a reader can
tell, without running anything, exactly how far each claim reaches.

---

## 1. Two properties cannot fail

`p1_state_legal` and `p1_pstate_legal` transcribe requirement R1 faithfully and
carry **zero information**. `fsm_e` occupies all 8 encodings of a 3-bit type and
`cur_pstate` all 4 of a 2-bit type, so no assignment — reachable or not — can
falsify either.

Independently confirmed by Verilator:
`CMPCONST: Comparison is constant due to limited range`, on exactly those lines.

They are retained deliberately as evidence, waived with a written justification
in `verif/verilator.vlt`, and excluded from every assurance claim. A future
reader is instructed not to "fix" them by deleting them.

**Implication for the headline:** "20 properties, all passing" would be true and
would overstate the assurance by exactly two.

---

## 2. Not everything proved is proved in the same model

Two clocking models, because neither answers both questions.

- **Collapsed-clock model** (`pclk == sclk`): where the functional properties are
  **proven** unbounded. It proves the control logic. **It proves nothing about
  the clock domain crossing.**
- **Multiclock model** (`clk2fflogic`, independent clocks): the only model in
  which the CDC claims mean anything. Induction does not close here, so the CDC
  results are **bounded at depth 20 — not proofs**.

`docs/TRACEABILITY.md` records which model produced each result. Reading a
collapsed-clock PASS as a statement about the asynchronous design would be wrong,
and the split exists precisely so that mistake is visible.

---

## 3. Bounded results are not proofs, and the gap is not theoretical

Mutation M1 is the demonstration: BMC at depth 30 reported no counterexample;
unbounded PDR found one immediately. The defect requires a downward transition,
and the first downward transition is not reachable until step 26.

Every result in this repository labelled **BOUNDED** carries that risk. Nothing
labelled BOUNDED may be described as verified, proven, or formally verified.

---

## 4. Load-bearing assumptions

All in `verif/formal/spcu_fv_env.sv`. Two matter:

**Regulator fairness** — `vack` must arrive within 4 cycles of `vreq`. Without
it, `p7_bounded_response` is *false*, correctly: an unbounded regulator does hang
the controller. Every bounded-response claim inherits this.

**APB3 master legality** — the solver would otherwise invent illegal bus
behaviour and report design bugs no conforming master could provoke. This
constrains the environment; the DUT's own APB compliance is consequently **not
verified**.

An assumption that was deliberately **refused** is recorded in
`docs/BUGS_FOUND.md` §S4, because refusing it is what keeps mutation M3
detectable.

---

## 5. Liveness is not verified, and the stack cannot verify it

R13 is a **bounded response** property: an accepted request resolves within 13
`sclk` cycles under the regulator fairness assumption. This is strictly weaker
than liveness.

The bound is at least **tight** rather than merely sufficient. Swept by
re-elaborating with `-DSPCU_LATENCY_MAX=N`:

| N | result |
|---|---|
| 24, 16, 15, 14, 13 | PASS |
| 12, 10, 9, 8, 7 | FAIL |

Worst-case latency is therefore exactly 12 cycles, and 12 is attained. A bound
that merely passes is a guess; this one is a measurement of the design.

### Three independent blockers, each verified by running it

Phase 2 probed liveness experimentally rather than assuming it was unavailable.
It is unavailable for three separate reasons, any one of which is sufficient:

**1. It cannot be expressed.** No frontend in this stack parses `s_eventually`:

```
read_verilog -sv : error
read_slang       : error: encountered unsupported SVA feature
```

Yosys's IR *does* have a `$live (A, EN)` cell, so the limitation is in the
frontends, not the representation. Verific would bridge it and is licence-gated.

**2. The engine is refused.** `sby` supports `mode live`, but:

```
ERROR: Invalid engine 'smtbmc' for live mode.
```

Only `aiger suprove` is accepted for liveness.

**3. That engine is absent.** With `aiger suprove` configured:

```
engine_0: starting process "suprove +simple_liveness model/design_aiger.aig"
engine_0: finished (returncode=127)
engine_0: COMMAND NOT FOUND. ERROR.
```

`suprove` is not shipped in this OSS CAD Suite build. Nor does any other
installed engine cover liveness: `pono`, `rIC3`, `btormc`, `avy` and `aigbmc`
are all safety-only — checked, none advertises LTL, fairness or justice.

**The honest claim.** "Accepted requests eventually resolve to DONE or ERROR" is
**NOT PROVEN and cannot be proven with this toolchain**. What is proven is a
tight bounded response under a stated fairness assumption. Even installing
`suprove` would not be sufficient on its own, because blocker 1 would remain.

## 6. Tool limitations measured on this machine

Facts from commands run here, not from documentation.

**Yosys parses no concurrent SVA.** Both frontends refuse it:
`read_verilog -sv` gives `syntax error, unexpected '@'`; `read_slang` elaborates
the design and then reports `encountered unsupported SVA feature` on `|=>` and
`##[1:3]`. Full SVA in formal requires Verific, which is licence-gated
(Tabby CAD). This is the single constraint that shapes the whole property
architecture.

**Verilator's SVA sequence NFA blows up on chained wide range-delays.** Measured:
`##[1:40]` twice compiles in under a second; `##[1:60]` twice had not finished
after 10 minutes; `##[1:200]` twice aborts the front end with
`%Error: Verilator internal fault`. The Tier-B cover bound is set by this tool
limit, not by the design — so a miss on that cover point means "not observed
within 40 cycles per leg", not "did not happen".

**cocotb caps at Python 3.13.** `cocotb 2.0.1 only supports a maximum Python
version of 3.13`; the system Python here is 3.14.6, so the venv is built on an
explicitly installed 3.13.

**pyuvm clears the ConfigDB.** `uvm_root().run_test()` defaults to
`keep_singletons=False` and clears singletons including the ConfigDB, so
anything registered before `run_test` is gone by `build_phase`. Components take
the DUT handle from `cocotb.top` instead.

**GNU make 3.81 bypasses the shell.** The macOS system make exec's simple recipe
lines directly, which does not see a `PATH` exported from the makefile — so a
bare `verilator` fails while a recipe line containing shell metacharacters
succeeds. Tools are invoked by absolute path.

**Comment lines must not begin with the tool's own name.** `// Verilator ...` is
parsed as a pragma and rejected as `BADVLTPRAGMA`, in `.sv` and `.vlt` files
alike.

---

## 7. Industrial tools not used, and what that costs

JasperGold, VC Formal, Questa Formal, VCS, Xcelium, Questa/ModelSim, Verdi,
Spyglass CDC, Conformal, and all Arm proprietary tooling.

Nothing here is evidence of experience with any of them. Concretely, what is
missing is not just the brand:

- **No formal coverage or proof-core analysis.** Commercial formal tools report
  which parts of the design a proof actually depended on. Without it there is no
  way to detect an over-constrained environment that made a proof easy for the
  wrong reason. This is a real gap in the assurance argument, not just a missing
  feature.
- **No structural CDC/RDC report.** The crossing inventory here is maintained by
  review. A tool would enumerate crossings automatically and flag the one nobody
  remembered.
- **No sign-off methodology.** No coverage closure process, no review gates, no
  regression triage at scale.

---

## 8. What is verified by construction rather than by a tool

- **R16, crossing discipline.** That every crossing uses `spcu_sync2` and a
  toggle is enforced by code review. No tool checks it.
- **R18 is no longer in this list.** It was the weakest link; Phase 2 formalised
  it, and formalising it **refuted the design** under independent resets. It is
  now PROVEN under the R22 integration constraint, with the refutation preserved
  and reproducible via `make formal-rdc`. What R18 covers is payload
  **stability**; it does not cover intra-word **bit skew**, which `clk2fflogic`
  cannot model.
- **The register read path.** No formal property constrains `prdata`. Read-back
  correctness rests entirely on simulation. MCY put 42 of 93 surviving mutants in
  `spcu_regs.sv`, and this is why.

---

## 9. Scope

- **IP, not SoC.** One peripheral. No interconnect, no masters, no CPU, no
  system integration.
- **RTL only.** No synthesis, no gate-level netlist, no timing, no
  X-propagation, no DFT, no UPF.
- **No metastability modelling.** `clk2fflogic` explores arbitrary clock phase;
  it does not model a flop resolving to an intermediate voltage.
- **Mutations are hand-authored by the same person who wrote the properties**,
  which biases them towards defects that person was already considering. `mcy`
  would generate them impartially and was not run.

---

## 10. The limitation that cannot be removed from inside

The central finding of this project — that two of five mutations escaped every
property because the *specification* was incomplete — was only visible because
mutations were run from outside the property set.

Nothing inside a verification argument reveals what the argument does not
mention. Coverage was high, properties passed, and the design was wrong in ways
the whole apparatus was structurally unable to see. The mutation catalogue is
one external check; it is hand-authored, so it is a weak one.

**This report cannot rule out that further requirements are still missing.**
That is not modesty. It is the actual epistemic position, and the same argument
that found S2a and S2b applies to whatever has not been thought of yet.

### Phase 2 measured the size of that blind spot

The hand-authored catalogue was the external check, and it was **authored by the
same person who wrote the properties**, so it inherited the same blind spot. MCY
sampled the netlist without that bias and put **45% of its surviving mutants in
the register file, a region the hand-authored set never touched at all**, while
only 16% landed in the FSM where every hand-authored mutation lived.

The lesson generalises past this project: **a self-authored adversarial check
probes the part of the design its author was already thinking about.** It is
better than no check, and it is not a substitute for one that samples
independently. The 5/5 figure from Phase 1 was true and it was measuring the
wrong population.
