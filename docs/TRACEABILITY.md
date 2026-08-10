# Traceability

Three sections:

1. Requirement → failure mode → technique → property → result → residual uncertainty.
2. Verdict vocabulary and what each result strength means.
3. Coverage of the target job description, item by item, with nothing stretched.

---

## 1. Requirement traceability

`R*` are from `docs/REQUIREMENTS.md`. `P*` are assertion labels in
`verif/props/`. **Result strength** uses the vocabulary in §2.

| Req | Failure mode it guards | Technique | Property / test | Result | Residual uncertainty |
|---|---|---|---|---|---|
| R1 | Operating point outside the legal set | formal | `p1_state_legal`, `p1_pstate_legal` | **VACUOUS** | These cannot fail on any input; the encodings are dense. Retained as evidence, excluded from all assurance. See `docs/LIMITATIONS.md` §1. |
| R2 | Second request accepted while one is in flight | formal `prove` | `p5_no_double_accept` | **PROVEN** (PDR) | Proven in the collapsed-clock model. The asynchronous case is bounded only — see R17. |
| R3 | Forbidden multi-step transition accepted | formal `prove` + sim + pyuvm + C | `p12_single_step`; `t_illegal_jump`; `IllegalTest` | **PROVEN** | Property added only after mutation M5 escaped everything else. |
| R4 | Request never resolves | formal `prove` | `p7_bounded_response` | **PROVEN under assumption** | Bounded response, not liveness. Depends on the regulator fairness assumption. See R13. |
| R5 | Settled operating point inconsistent | formal `prove` + sim | `p1b_settled_volt`, `p1b_settled_freq` | **PROVEN** | Scoped to `!error`: an *aborted* transition may leave voltage above the level `CUR_PSTATE` implies. Documented residual B4. |
| R6 | Clocked faster than the supply sustains | formal `prove` | `p2_freq_le_volt` | **PROVEN** | Strongest result in the project. Holds at every instant in the collapsed-clock model. |
| R7 | Voltage recorded without a real handshake | formal `prove` | `p11_volt_needs_handshake` | **PROVEN** | Property added only after mutation M3 escaped everything else. Simulation still misses M3 — see §1 note below. |
| R8 | Unprivileged agent changes operating state | formal `prove` | `p3_unpriv_no_change` | **PROVEN, AND INSUFFICIENT** | Passes under mutation M2. The property consults the same configuration bit an attacker can clear. R9 is the real check. |
| R9 | Authority bit lowered by the unprivileged side | formal `prove` + C | `p3b_authority_provenance`, `p3c_lock_provenance`, `p8_slverr_on_unpriv` | **PROVEN** | Verified independently: with `p8` downgraded to a cover, `p3b` still refutes M2 on its own. |
| R10 | Policy change mid-flight ignored | formal `prove` | decision-point capture (`auth_ok_q`, `lock_at_accept_q`) | **PROVEN** | **Accepted residual:** an in-flight transition is not aborted by raising `REQUIRE_PRIV` or `LOCK`. Exposure bounded by R13. |
| R11 | Locked controller still moves | formal `prove` + sim + C | `p9_lock_blocks`; `t_lock_blocks`; `t_lock_refuses` | **PROVEN** | Evaluated at acceptance, per R10. |
| R12 | Powered-down domain driven | formal `prove` | `p6_pd_off_pstate/volt/freq` | **PROVEN, AMENDED** | Original wording unimplementable; permits one cycle of commit latency after `pd_on` falls. CEX preserved. |
| R13 | Request hangs | formal `prove` | `p7_bounded_response` | **PROVEN under assumption** | Depends on `a_vack_fairness`. True liveness is **NOT VERIFIED** and cannot be with this stack. |
| R14 | Reset does not reach the safe state | formal `prove` | `p4_reset_safe_state/op/no_vreq` | **PROVEN** | Combinational, so it holds throughout reset, not only at the first edge. |
| R15 | Asymmetric reset corrupts the handshake | formal `prove` | `p5_no_double_accept` | **PROVEN** | The defect that motivated this requirement was found by formal, unseeded. Fix at `rtl/spcu_top.sv`. |
| R16 | Pulse missed or double-sampled across the boundary | review + formal `cdc_bmc` | `spcu_sync2` instantiation; `p5_*` under `clk2fflogic` | **BOUNDED** | Structural discipline is enforced by review, **not by a CDC tool**. No open equivalent of Spyglass exists. |
| R17 | One request commits twice | formal `cdc_bmc` | `p5_no_double_accept`, `p5_no_orphan_ack` | **BOUNDED (depth 20)** | Under arbitrary clock phase via `clk2fflogic`. **This is not a proof.** Induction does not close in the multiclock model. |
| R18 | Multi-bit payload sampled as a value never driven | review | data-with-handshake construction | **ARGUED, NOT VERIFIED** | No property checks payload stability directly. The weakest link in the CDC argument. |
| R19 | APB protocol violation | formal env + sim + C | `a_apb_*` assumptions; BFM | **CONSTRAINED, NOT CHECKED** | The APB assumptions constrain the *environment*. The DUT's own APB compliance is not independently verified — no protocol checker VIP. |
| R20 | Silent refusal | formal `prove` + C | `p8_slverr_on_unpriv` | **PROVEN** | |
| R21 | RTL / firmware / docs drift | `make check-gen` | `tools/genregs.py --check` | **ENFORCED** | Checks the four generated files match the spec hash. |

**Note on R7.** Formal catches mutation M3; simulation does not. The testbench's
regulator model never presents a stale acknowledge, so the stimulus that would
expose the defect is never generated. Formal finds it because `vack` is left
free. This is the clearest case in the project of formal reaching something
simulation cannot.

---

## 2. Verdict vocabulary

Used consistently above and throughout `docs/`.

| Term | Meaning |
|---|---|
| **PROVEN** | An unbounded engine (k-induction or PDR/IC3) returned PASS. Holds over all reachable states of the model, within the stated clocking model and the assumptions in `spcu_fv_env.sv`. |
| **PROVEN under assumption** | As above, but a named environment assumption is load-bearing. Dropping it makes the property false. |
| **BOUNDED** | BMC found no counterexample within a stated depth. **Not a proof.** Mutation M1 shows the gap is real: BMC at depth 30 missed a defect that PDR caught. |
| **VACUOUS** | The property cannot fail on any input. Carries zero information. |
| **ARGUED, NOT VERIFIED** | Established by construction and review. No tool checks it. |
| **CONSTRAINED, NOT CHECKED** | Assumed of the environment rather than verified of the design. |
| **ENFORCED** | A build step fails if the condition is violated. |
| **NOT VERIFIED** | Stated plainly where a requirement is not covered. |

---

## 3. Job-description coverage

Scored against the literal requirement list for the target role. **COVERED**
means this project genuinely produced the skill. **PARTIALLY COVERED** means a
real but materially narrower version. **NOT COVERED** means it was not done,
regardless of how adjacent something else looks.

Adjacent experience is not stretched into coverage. The specific exclusions
requested are honoured explicitly and repeated here so they cannot be missed:
pyuvm is not SystemVerilog UVM; SBY/Yosys is not JasperGold or VC Formal;
behavioural power modelling is not UPF sign-off; hand-written CDC properties are
not industrial CDC tooling; an APB3 peripheral is not professional Arm SoC
experience.

### Essential

| JD item | Verdict | Basis, and what is missing |
|---|---|---|
| Verilog/SystemVerilog HDL | **COVERED** | ~450 lines of SystemVerilog RTL authored and debugged: packages, typed enums, `always_ff`, parameterised modules, a generated register file. Plus SV testbench classes and constrained randomisation. |
| Formal verification | **COVERED** | 22 requirement-derived properties, unbounded proofs via k-induction and PDR, a deliberate assumption audit, four counterexample-driven specification corrections, preserved counterexamples. Open-source engines only. |
| UVM | **PARTIALLY COVERED** | Full UVM *architecture* in pyuvm: sequences, sequencer, driver, passive monitor, analysis port, TLM fifo, scoreboard, agent, env, phasing. **No `uvm_pkg`, no SystemVerilog factory, no vendor UVM debug flow, no commercial constraint solver.** No free simulator runs SystemVerilog UVM: Verilator lacks it, Questa Intel Starter gates `randomize()` behind a licence feature, Vivado XSim has no macOS build. This is not commercial SystemVerilog UVM experience. |
| Power-aware verification | **PARTIALLY COVERED** | Power-domain behaviour (`pd_on`), refusal when off, mid-sequence abort, and the proof that a powered-down domain cannot be driven. Modelled **behaviourally in RTL**. No power intent file, no isolation/retention cell insertion, no power-aware simulation semantics. |
| UPF power-aware verification | **NOT COVERED** | No open tool consumes IEEE 1801. **Deliberately not written.** An unconsumed UPF file would demonstrate syntax while implying a capability the flow does not have, which is the definition of the CV theatre this project set out to avoid. |
| SoC verification | **NOT COVERED** | This is a single IP block. No interconnect, no multiple masters, no CPU, no boot flow, no system-level integration or scenario testing. |
| Embedded low-level C/C++ tests | **COVERED** | Bare-metal C driver over memory-mapped registers, status polling, bounded retries, self-checking; C++ Verilator harness converting MMIO to APB transactions. Identical driver source builds for a real target. |
| ARM assembly | **NOT COVERED** | No assembly was written. |
| Low-level memory-mapped HW interaction | **COVERED** | The C driver's only interface to the device is volatile MMIO through a generated header. |
| Requirements collection | **PARTIALLY COVERED** | 21 requirements authored, and — more substantively — **amended under evidence**: two proved unimplementable as written, three were entirely missing until mutation analysis exposed them. Missing: elicitation from real stakeholders, and any external source of truth to reconcile against. |
| Verification methodology plan | **COVERED** | `docs/VERIFICATION_PLAN.md`, including tool-strength policy and negative-control policy. |
| Test plans | **COVERED** | Per-technique test lists, mutation catalogue with pre-registered predictions. |
| Testbench implementation | **COVERED** | Two independent testbenches (SV classes; pyuvm/cocotb) plus a C/MMIO harness and a formal testbench. |
| Test-case development | **COVERED** | Directed, constrained-random, and mutation-driven cases across four flows. |
| Documentation | **COVERED** | Seven documents plus generated register documentation. |
| Debugging | **COVERED** | Genuine debugging with preserved evidence: an RDC defect diagnosed from a VCD signal table; a Verilator front-end crash bisected to a minimal trigger; a GNU make 3.81 direct-exec issue; a C/C++ linkage failure whose symbol looked correct. |
| IP verification flow and strategy | **COVERED** | Spec → generated collateral → RTL → properties → formal → simulation → firmware → mutation → regression. |
| SoC verification flow and strategy | **NOT COVERED** | See SoC verification above. |
| AMBA / Arm system architecture | **PARTIALLY COVERED** | The register interface is a genuine AMBA APB3 slave and `pprot[0]` is the real AMBA privilege signal, so the privilege model is authentic rather than invented. **That is protocol-level exposure to one of the simplest AMBA buses.** No AXI, no ACE, no CHI, no Arm core, no Arm system IP. Not professional Arm SoC experience. |
| ARM-based builds | **NOT COVERED** | No Arm toolchain, no Arm target, no Arm build environment. |
| Clock-domain-crossing verification | **PARTIALLY COVERED** | Two-flop synchronisers, two-phase toggle handshake, data-with-handshake payload, non-integer clock ratio in simulation, formal CDC under arbitrary clock phase via `clk2fflogic`, and a **real reset-domain-crossing defect found and fixed**. **No industrial CDC tool**: no structural CDC/RDC report, no automatic crossing inventory, no metastability injection, no sign-off methodology. Hand-written properties are not Spyglass. |
| GLS | **NOT COVERED** | No synthesis, no gate-level netlist, no SDF, no timing back-annotation, no X-propagation analysis. |
| DFT / DFD | **NOT COVERED** | No scan, no ATPG, no MBIST, no debug/trace infrastructure. |
| Python automation | **COVERED** | Register generator with staleness checking, parallel mutation runner, cocotb integration. |
| Shell / Make automation | **COVERED** | Full regression driver. |
| Tcl / Perl automation | **NOT COVERED** | Neither was used. SymbiYosys config files and Yosys scripts are neither language. |
| Applying AI methods to digital verification | **COVERED, with disclosure** | This project was built with AI assistance throughout, and the working method — pre-registered mutation predictions, negative controls before trusting a pass, counterexample-driven specification repair — is the substance of the claim. The disclosure is in `README.md`; every headline result is reproducible from a clean clone without it. |

### Preferred

| JD item | Verdict | Basis |
|---|---|---|
| JasperGold / VC Formal exposure | **NOT COVERED** | Neither tool was used. SymbiYosys, Yosys, Z3 and ABC are not substitutes and no result here implies familiarity with commercial formal flows, their proof-core analysis, or their coverage methodology. |
| Hardware security | **PARTIALLY COVERED** | A real security finding: a confused-deputy defect where the authority check consults a bit the unprivileged side can clear, plus the distinction between gating an action and gating the provenance of the permission, plus in-series-versus-at-the-bus enforcement placement. Not a security *sign-off* process, no threat model document, no side-channel or fault-injection analysis. |
| Cryptographic algorithms | **NOT COVERED** | No cryptography of any kind. |
| ML applications in verification | **NOT COVERED** | No ML was applied — no coverage-closure ML, no test generation via learning, no bug prediction. AI assistance in *authoring* is a different thing and is recorded above. |
| Arm proprietary tools / environments | **NOT COVERED** | None were used, and none are publicly available. |

### Summary

Fully covered: 14. Partially covered: 7. Not covered: 10.

The honest reading: this project is strong evidence of **IP-level verification
method** — formal reasoning, property discipline, specification repair under
evidence, mutation-driven assessment, multi-flow regression — and it is **not**
evidence of SoC-scale work, industrial tool experience, or the back-end
disciplines (GLS, DFT, UPF sign-off).
