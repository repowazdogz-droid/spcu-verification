# SPCU Requirements

Secure Power Control Unit. A small DVFS controller with a memory-mapped
register interface, an asynchronous internal clock boundary, and a
security-relevant authority model.

Each requirement has a stable identifier used by `docs/TRACEABILITY.md`, by the
assertion labels in `verif/props/`, and by `mutations/mutations.yaml`.

Requirements marked **[AMENDED]** were changed *after* formal refuted the
original wording. The original is kept in the text, because a requirement that
turned out to be unimplementable is a finding about the specification and
deleting it would hide the finding.

---

## 1. Function

**R1 — Operating states.** The controller supports four operating points,
P0..P3. P0 is the lowest voltage and frequency, P3 the highest. The voltage
level and frequency level required to sustain P-state N are both N.

**R2 — Requests.** Software submits a request by writing `CTRL.TARGET` and
`CTRL.GO` in a single APB write. Exactly one request may be in flight; a
request arriving while `STATUS.BUSY` is set is not accepted.

**R3 — Single-step rule.** One request moves the operating point by at most one
P-state. A request whose target is more than one step from the current state is
**refused**, not clamped and not performed slowly. P0→P2 and P0→P3 are
forbidden transitions.

**R4 — Completion.** Every accepted request resolves to exactly one of DONE or
ERROR, reported in `STATUS.DONE` / `STATUS.ERROR`, and clears `STATUS.BUSY`.

**R5 — Self-consistency at rest.** When the controller is idle after a request
that completed without error, the applied voltage level and frequency level
must both equal the level required by `STATUS.CUR_PSTATE`.

> **[ADDED]** R5 did not exist in the first draft. Mutation M1 leaves the part
> at a *higher* voltage than the P-state requires: safe, wasteful, and passing
> every other requirement. The specification said the voltage must be
> *sufficient*; it never said it must be *correct*. See `docs/BUGS_FOUND.md`.

## 2. Sequencing and safety

**R6 — Voltage leads frequency.** Raising the operating point raises voltage
first, then frequency. Lowering it lowers frequency first, then voltage.
Consequently `freq_level <= volt_level` holds at every instant. The part is
never clocked faster than its supply sustains.

**R7 — Regulator handshake.** The applied voltage level may change only as the
result of a completed four-phase handshake with the regulator: `vreq` asserted,
`vack` observed while `vreq` is asserted, then `vreq` withdrawn.

> **[ADDED]** R7 did not exist in the first draft. Mutation M3 samples a stale
> `vack` and records a voltage the regulator was never asked to supply. Every
> requirement written about the controller's *own variables* still held. A
> defect that makes the design lie about the physical world is invisible to
> them.

## 3. Authority

**R8 — Privileged requests.** A request is authorised if the agent that wrote
`CTRL.GO` presented `pprot[0] == 1`, or if `PRIV_CFG.REQUIRE_PRIV` is clear.
Authority is evaluated **in series** with the state change, inside the
controller, not at the bus. `CTRL` is deliberately writable by any agent: the
thing that must be gated is the state change, not the register.

**R9 — Authority provenance.** `PRIV_CFG.REQUIRE_PRIV` and `LOCK.LOCKED` may be
modified only by a privileged write. An unprivileged write to either is refused
and raises `pslverr`.

> **[ADDED]** R9 did not exist in the first draft, and its absence is the most
> serious finding in the project. R8 alone is satisfied by an attacker who
> clears `REQUIRE_PRIV` first: the authority check consults a label that the
> unprivileged side controls. R8 asks *"was this action permitted under current
> policy"*. R9 asks *"could the policy have been set by someone not entitled to
> set it"*. Only the second is a security property. See mutation M2.

**R10 — Instant of evaluation [AMENDED].** Authority and lock are evaluated
**once, at acceptance**. A transition already in flight completes under the
policy in force when it was accepted.

> Originally unstated. Formal refuted properties written over the *commit*
> instant with traces in which configuration changed legitimately after the
> controller had already decided. Those were not design bugs; the specification
> had simply never named an instant.
>
> **Accepted residual:** raising `REQUIRE_PRIV` or setting `LOCK` does not abort
> an in-flight transition. Exposure is bounded by one transaction (R13).
> Aborting a voltage ramp midway is the more dangerous option, because it can
> strand the part at a frequency its supply does not sustain.

**R11 — Lock.** While `LOCK.LOCKED` is set, no request is accepted.

## 4. Power and reset

**R12 — Powered-down domain [AMENDED].** While the managed power domain is off,
the controller must not change the applied voltage, applied frequency, or
`CUR_PSTATE`. A request arriving while the domain is off is refused. A domain
that powers down *during* a transition aborts that transition with ERROR.

> The original wording was **unimplementable**. Stated over the current value of
> `pd_on`, it demands that a synchronous design react to an input in the same
> cycle that input changes. Formal refuted it in four steps. The requirement is
> now stated over the value the design was entitled to act on, permitting
> exactly one cycle of commit latency after `pd_on` falls. Counterexample
> preserved at `verif/formal/cex/p6_unsatisfiable/`.

**R13 — Bounded response [TIGHTENED].** An accepted request resolves within 13
`sclk` cycles, **given** that the regulator acknowledges within 4 cycles of a
request.

> The bound is **tight, not merely sufficient**. Swept by re-elaborating with
> `-DSPCU_LATENCY_MAX=N`: N=13 proves, N=12 is refuted. Worst-case latency is
> therefore exactly 12 cycles and that value is attained. The original bound of
> 24 was a guess that happened to hold; this one is a measurement.

> This is **not** a liveness requirement, and the distinction is not pedantic.
> True liveness ("eventually resolves") requires `s_eventually`, which no open
> formal tool in this stack can parse. What is verified is a bounded response
> under a stated fairness assumption. Both the bound and the assumption are part
> of the claim; neither may be dropped when the result is described.

**R14 — Reset.** Asserting either reset returns the controller to its safe
state: `S_IDLE`, P0, voltage 0, frequency 0, `vreq` deasserted. The reset is
asynchronously asserted, so the safe values hold for the whole time reset is
low, not merely at the first clock edge after it.

**R15 — Reset domain crossing.** `presetn` and `srst_n` are independent. The
request/acknowledge handshake must be held in reset while *either* domain is in
reset.

> **[ADDED]** R15 did not exist in the first draft. Formal's very first
> counterexample showed a `pclk` reset, asserted mid-transaction, clearing the
> launched toggle while it was still inside the `sclk` synchroniser — so the
> controller saw two edges for one request. A CDC synchroniser protects against
> clock asynchrony and does nothing about reset asynchrony.

## 5. Clock domain crossing

**R16 — Crossing discipline.** Every control signal crossing between `pclk` and
`sclk` passes through a two-flop synchroniser and is encoded as a **toggle**,
never a pulse. A pulse narrower than the destination period can be missed; one
wider than the destination period can be seen twice.

**R17 — No double commit.** One request produces at most one commit. No
acknowledge may be produced that no request asked for.

**R18 — Payload stability [NOW CHECKED].** Multi-bit payload crossing the
boundary is *not* synchroniser-per-bit; it is data-with-handshake. Split into
two checkable obligations:

- **R18a (launch side).** Once a request is in flight, the payload does not
  change. Checked by `p18a_target_stable` / `p18a_priv_stable`.
- **R18b (sampling side).** At the instant the controller samples the payload,
  it has already been stable across the two preceding `sclk` edges — the
  synchroniser depth. Checked by `p18b_target_settled` / `p18b_priv_settled`.

> Previously recorded as ARGUED, NOT VERIFIED. It is now verified, and doing so
> **refuted the design under fully independent resets** — see R22.
>
> What remains outside any property: R18 covers payload **stability**, which is
> the precondition the synchroniser argument needs. It does **not** cover
> intra-word **bit skew**, because `clk2fflogic` models arbitrary clock phase
> but not a flop resolving to an intermediate value. Per-bit synchronisation
> would be worse regardless: the bits would resolve independently and could be
> sampled as a value that was never driven.

**R22 — Reset ordering [ADDED — an integration constraint on the IP].** The
controller domain must be held in reset whenever the register domain is:
`presetn` low implies `srst_n` low.

> **Discovered by formal, not assumed.** Without it, R18b is refuted: `presetn`
> can clear the launch-side payload while the request toggle is still inside the
> `sclk` synchroniser, so the controller consumes a request whose payload the
> source domain has already wiped. Counterexample preserved at
> `verif/formal/cex/r18_payload_settling/`.
>
> **No local RTL fix exists.** At the failing instant the synchronised pclk
> reset (`presetn_s`) is still high — the reset information has not yet crossed
> — so no signal observable in the `sclk` domain can distinguish the case.
> Closing it inside the IP would require a full reset handshake between domains.
> Stating the requirement on the integrator is the standard alternative and the
> one taken here.
>
> This is a **requirement on anyone instantiating this IP**, and it is the kind
> of constraint that belongs in a datasheet rather than in a comment. The
> residual is reproducible in one command:
> `sby -f verif/formal/spcu.sby rdc_freerst`.

## 6. Register interface

**R19 — APB3.** The register interface is an AMBA APB3 slave, zero wait states,
with `pprot[0]` carrying the privilege of the requesting agent.

**R20 — Error reporting.** A refused write raises `pslverr`. Silent refusal is
indistinguishable from success to firmware and is its own class of bug.

**R21 — Single source of truth.** The register map is defined once, in
`spec/spcu_regs.yaml`. The RTL register file, the C header, the pyuvm register
model and the register documentation are all generated from it. Hand-editing a
generated file is a defect, detected by `make check-gen`.
