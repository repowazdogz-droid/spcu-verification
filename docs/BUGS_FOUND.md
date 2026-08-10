# Bugs Found

Two categories, kept apart because they mean different things.

**B — defects in the design**, found by a verification technique. Four of these
were found by formal and **none of them were seeded**; they were real mistakes
in RTL written to be correct.

**S — defects in the specification or in the verification argument itself.**
These matter more. A design bug means the process worked. A specification bug
means the process would have said "verified" about something wrong.

---

## B1 — Reset domain crossing corrupts the handshake

**Found by:** formal, first run, unseeded. **Severity:** high. **Fixed.**

`presetn` and `srst_n` are independent inputs, as they are in a real SoC where
each domain has its own reset controller. A `pclk` reset asserted mid-transaction
cleared `req_tog_p` back to 0 while the launched `1` was still propagating
through the `sclk` synchroniser. The `sclk` side then observed **two** toggle
edges for one request.

Signal table extracted from the counterexample VCD:

| time | presetn | srst_n | req_tog_p | req_tog_s | req_tog_s_d | inflight | st |
|---|---|---|---|---|---|---|---|
| 65 | 1 | 1 | 1 | 0 | 0 | 0 | IDLE |
| 75 | **0** | 1 | 0 | 0 | 0 | 0 | IDLE |
| 85 | 0 | 1 | 0 | **1** | 0 | 0 | IDLE |
| 95 | 0 | 1 | 0 | 0 | **1** | **1** | CHECK |

At t=75 the register domain abandons the request; at t=95 the controller starts
processing it anyway.

**The lesson, which generalises:** a CDC synchroniser protects against clock
asynchrony and does nothing whatsoever about **reset** asynchrony. Both
endpoints of a handshake must leave reset consistently or the handshake state
itself is corrupt.

**Fix:** each domain's reset is crossed into the other, and the handshake on
both sides is held in reset while either domain is in reset
(`rtl/spcu_top.sv`). Requirement R15 was added.

---

## B2 — Power-down mid-sequence keeps driving the regulator

**Found by:** formal, unseeded. **Severity:** high. **Fixed.**

`pd_on` was tested once, in `S_CHECK`. The managed domain can power down at any
point during a multi-cycle ramp, and the controller carried on driving `vreq`
and updating `volt_level` into a domain that was no longer there.

**The shape of this defect is worth naming:** the guard existed, it ran, and it
returned the correct answer — *for the instant at which it was evaluated*. **A
precondition checked once is not an invariant maintained throughout.**

**Fix:** a mid-sequence abort in `spcu_ctrl_fsm.sv`.

---

## B3 — An aborted transition left a stale operating point

**Found by:** formal, after B2's fix. **Severity:** medium. **Fixed.**

B2's abort could stop a ramp after voltage had risen but before frequency and
`CUR_PSTATE` followed. The controller then treated a later request for the
*same* P-state as "already there, nothing to do", so the inconsistent point
survived a subsequent successful request — laundered clean.

**Fix:** the FSM now decides from the **applied levels**, not from the P-state
comparison, making it self-correcting: any request re-establishes the invariant
whether or not the P-state is changing.

---

## B4 — Residual: aborted transitions are still inconsistent until the next request

**Status: open, accepted, documented.** Not fixed, deliberately.

After an abort the part sits at a voltage above what `CUR_PSTATE` implies. It is
safe (`freq <= volt` still holds) but not minimal, and it cannot be corrected at
the time: the managed domain has powered down, so there is nothing to drive the
regulator into.

`p1b_*` is therefore scoped to `!error`. That is a genuine weakening of the
property and it is recorded here rather than hidden in the scope condition.

---

## S1 — A requirement that no implementation could satisfy

**Found by:** formal, in 4 steps. **The most instructive result in the project.**

R12 was first transcribed as:

```systemverilog
p6_pd_off_volt: assert (pd_on || (volt_level == $past(volt_level)));
```

Faithful to the requirement's English. Refuted immediately:

| time | pd_on_s | volt_level | st | vreq | vack_s |
|---|---|---|---|---|---|
| 130 | 1 | 00 | S_VOLT_UP | 1 | 1 |
| 135 | **0** | **01** | S_FREQ_UP | 0 | 1 |

At t=130 the controller is legitimately mid-handshake with `pd_on` high and
commits the voltage. The commit becomes visible at t=135, by which time `pd_on`
has fallen.

**No synchronous design can satisfy the original property.** It demands a
reaction in the same cycle as the input causing it. This is not a design bug and
no amount of RTL work would have fixed it.

Restated over `$past(pd_on)` — the value the design was entitled to act on.
Counterexample preserved at `verif/formal/cex/p6_unsatisfiable/`.

**The same mistake recurred twice more**, which is why it is worth a section
rather than a footnote:

- **P3 and P9** were written over the *commit* instant while the controller
  decides at *acceptance*. Formal produced traces where configuration changed
  legitimately after the decision. This forced a specification question nobody
  had answered: **at which instant is authority evaluated?** R10 now answers it.
- **P3 again**, more subtly: the property read the *live* bus-side privilege
  payload. Formal produced a trace where `presetn` asserts while the `sclk`
  domain has not yet seen it, so the payload resets while the controller
  correctly continues on the credential it latched. **The design was right and
  the property was wrong.** It now reads `obs_priv_latched`.
- **Tier-B SVA**, a third time: `(vreq && vack) |=> !vreq` failed in simulation
  because `vack` there is the *raw* acknowledge while the controller can only act
  on the synchronised one, two stages later.

**Generalised lesson:** a property must be stated over the value the design was
*entitled to act on*, at the instant it was *entitled to act*. Across a clock
boundary that always includes the synchroniser latency. Transcribing a
requirement's English directly into an assertion is not sufficient and produces
properties that are unsatisfiable rather than merely wrong.

---

## S2 — Two requirements that were simply missing

**Found by:** mutation analysis. Both mutations passed **every** property written
from the original specification.

### S2a — Mutation M1: the specification never said "minimal"

M1 stops the downward path from lowering voltage. The part is left at a higher
voltage than needed.

Every original property passes. `freq <= volt` still holds — voltage is *higher*,
which is the safe direction. The state is legal. The transition is single-step.
The handshake completed.

The specification said the voltage must be **sufficient**. It never said it must
be **correct**. R5 was added.

### S2b — Mutation M5: the step rule was never asserted

M5 changes `illegal_step` from `> 1` to `> 2`, permitting a two-step jump.

A two-step jump is *internally consistent*: voltage still leads frequency, the
settled point still matches, the state is still legal. Nothing structural
distinguishes it. Only a property stating the step rule itself catches it, and
that property did not exist. R3's property `p12_single_step` was added.

### S2c — Mutation M3: properties about the design cannot see the world

M3 samples a stale `vack`, so the controller records a voltage the regulator was
never asked to supply.

Every property written about the *controller's own variables* still held,
because internally the design is perfectly consistent — it has simply recorded
something false about the physical world. R7's property
`p11_volt_needs_handshake` was added to tie the recorded value to the handshake
that must have produced it.

---

## S3 — A property that could not fail

`p1_state_legal` and `p1_pstate_legal` transcribe R1 faithfully and **cannot
fail on any input**: `fsm_e` occupies all 8 encodings of a 3-bit type and
`cur_pstate` all 4 of a 2-bit type.

Independently confirmed by a second tool — Verilator reports
`CMPCONST: Comparison is constant due to limited range` on exactly those two
lines.

They are **kept**, deliberately, as evidence that a requirement can be
transcribed faithfully into an assertion that carries zero information. They are
excluded from every assurance claim. The waiver in `verif/verilator.vlt` says so
and instructs future readers not to "fix" them by deletion.

---

## S4 — The assumption that was deliberately not written

The natural environment constraint for the regulator is:

```systemverilog
assume (!vack || vreq);   // NOT WRITTEN
```

It is true of any sane regulator. It would also make mutation M3
**unfalsifiable**: under it a stale acknowledge cannot exist, so the property
that catches M3 would pass vacuously and the proof would be an artefact of the
environment rather than a fact about the design.

`vack` is left free apart from the fairness bound. This is the concrete answer
to "do the assumptions make the properties trivially true": one assumption was
identified as doing exactly that and was refused. The regulator's real
behaviour is instead *checked* in simulation by the Tier-B property
`a_vreq_gets_vack`, so a broken testbench model is caught rather than silently
satisfying itself.

---

## S5 — A coverage number that measured nothing

The covergroup originally sampled `@(posedge pclk)` against variables that only
change once per request. It reported **100.0%** and meant nothing: every bin
filled from stale values lying around between transactions.

Fixed to sample at the request. The number now discriminates:

| stimulus | coverage |
|---|---|
| single unprivileged request | 40% |
| single illegal-jump request | 40% |
| directed walk P0→P3→P0 | 70% |
| 40 constrained-random requests | 100% |

The negative control is what exposed it: a metric that reads 100% for a single
directed test is not measuring what it claims. See `docs/COVERAGE.md`.

---

## Mutation detection matrix

Produced by `make mutations`. Predictions were recorded in
`mutations/mutations.yaml` **before** the runs.

| ID | Defect class | Formal (BMC d30) | Simulation | Caught by |
|---|---|---|---|---|
| M1 | voltage/frequency sequencing | **missed** | CAUGHT | `p1b_settled_volt` |
| M2 | privilege check omitted | CAUGHT | CAUGHT | `p8_slverr_on_unpriv`; `p3b_authority_provenance` independently |
| M3 | stale acknowledgement | CAUGHT | **missed** | `p11_volt_needs_handshake` |
| M4 | double-processing across CDC | CAUGHT | CAUGHT | `p5_no_double_accept` |
| M5 | invalid transition accepted | CAUGHT | CAUGHT | `p12_single_step` |

### Where simulation beat formal — M1

BMC at depth 30 missed it. **Unbounded PDR caught it.** The defect only manifests
on a *downward* transition, which requires first climbing — and the `cover` run
shows a downward transition is first reachable at step 26 and P3 at step 41.
The bound was simply too shallow.

This is the cleanest demonstration in the project that **a BMC pass is not a
proof**. Simulation, which runs long sequences cheaply, walked past depth 30
without effort.

### Where formal beat simulation — M3

Simulation never presents a stale acknowledge, because the testbench regulator
model drops `vack` when `vreq` drops. The stimulus that would expose the defect
is never generated, and no amount of random seeds fixes that — it is a *modelled
assumption*, not a coverage hole.

Formal finds it because `vack` is left free (see S4). This is formal reaching
something simulation structurally cannot: not a corner case that is rare, but a
behaviour the testbench cannot produce at all.

### Where both would have failed — M1 and M5 as originally specified

Both escaped **every** property in the original specification, and neither is a
checking weakness. M1 escaped because no requirement said the settled voltage
must be minimal. M5 escaped because no requirement asserted the step rule.

The properties that catch them today exist **only because these mutations were
run**. Before that, the verification argument was complete, green, and wrong —
and nothing inside the argument could have revealed it.

**Verification completeness is bounded by specification adequacy, and no amount
of coverage inside an inadequate specification detects the difference.**
