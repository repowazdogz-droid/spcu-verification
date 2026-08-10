// TIER-A PROPERTIES. One source, read by BOTH engines.
//
// WHY THIS FILE LOOKS LIKE 2005 VERILOG WHEN THE RTL DOES NOT
//   The 5.051 Verilator frontend supports rich concurrent SVA (|=>, ##[m:n],
//   s_eventually). Yosys supports none of it. Verified on this machine:
//     read_verilog -sv : "syntax error, unexpected '@'"
//     read_slang       : "encountered unsupported SVA feature"
//   Both frontends DO accept immediate assert/assume/cover in a clocked always
//   block, together with $past / $stable / $rose / $fell / $changed.
//   That intersection is the entire Tier-A vocabulary. Anything richer is
//   Tier B, lives in verif/sv/spcu_sva_tb.sv, and is simulation-only evidence.
//
// PROVENANCE OF EACH PROPERTY
//   [SPEC]  Written from docs/REQUIREMENTS.md before any mutation was run.
//   [ADDED] Written AFTER mutation analysis showed the [SPEC] set was
//           insufficient. These are the findings, not the plumbing. Their
//           existence is the argument that verification completeness is
//           bounded by specification adequacy.
//
// VACUITY
//   p1_* are marked VACUOUS deliberately and are kept as evidence, not as
//   assurance. See docs/LIMITATIONS.md.

module spcu_props
  import spcu_pkg::*;
(
    input logic       sclk,
    input logic       srst_n,
    input fsm_e       st,
    input logic [1:0] cur_pstate,
    input logic [1:0] volt_level,
    input logic [1:0] freq_level,
    input logic       req_pulse,
    input logic [1:0] req_target,
    input logic       req_priv,
    input logic       require_priv,
    input logic       lock,
    input logic       pd_on,
    input logic       vreq,
    input logic       vack,
    input logic       ack_tog,
    input logic       error,
    input logic       priv_latched
);

  // ------------------------------------------------------------- bookkeeping
  logic inflight;
  logic ack_tog_d;
  logic [7:0] latency;

  wire ack_edge = (ack_tog != ack_tog_d);

  always_ff @(posedge sclk or negedge srst_n) begin
    if (!srst_n) begin
      inflight  <= 1'b0;
      ack_tog_d <= 1'b0;
      latency   <= 8'd0;
    end else begin
      ack_tog_d <= ack_tog;
      if (req_pulse) begin
        inflight <= 1'b1;
        latency  <= 8'd0;
      end else if (ack_edge) begin
        inflight <= 1'b0;
      end else if (inflight) begin
        latency <= latency + 8'd1;
      end
    end
  end

  // ------------------------------------------------ auxiliary invariant [AUX]
  // NOT a requirement. A strengthening invariant, needed because P5 is true
  // but NOT INDUCTIVE: k-induction starts from an arbitrary state in which
  // this property's own bookkeeping can disagree with the design's, and
  // refutes P5 from a configuration no execution can reach.
  //
  // FIRST ATTEMPT WAS ITSELF FALSE, which is the useful part. It related
  // inflight to the bus-side busy flag -- across the clock boundary. Reset
  // propagation makes that relation genuinely untrue: presetn clears busy_p
  // immediately, while the sclk side only sees it two synchroniser stages
  // later, so inflight legitimately outlives busy. An auxiliary invariant that
  // is false does not merely fail to help, it would invalidate every proof
  // resting on it, which is why it is ASSERTED here and never assumed.
  //
  // Restated within a single clock domain and a single reset. The ack_edge
  // term admits the one cycle in which the FSM has returned to S_IDLE and the
  // bookkeeping has not yet retired the transaction.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      aux_inflight_tracks_fsm: assert (!inflight || (st != S_IDLE) || ack_edge);
    end
  end

  // ---------------------------------------------------------------- P1 [SPEC]
  // "Operating state always belongs to the legal state set."
  //
  // VACUOUS BY CONSTRUCTION and retained to prove the point. fsm_e uses all 8
  // encodings of a 3-bit type and cur_pstate uses all 4 of a 2-bit type, so no
  // reachable OR unreachable assignment can falsify either. These assertions
  // cannot fail on any input. A green result here carries zero bits.
  // The requirement was real; this encoding of it is not a check.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      p1_state_legal:  assert (st <= S_ACK);
      p1_pstate_legal: assert (cur_pstate <= 2'd3);
    end
  end

  // --------------------------------------------------------------- P1b [ADDED]
  // What P1 should have said. When the controller is idle the operating point
  // must be internally consistent: the voltage and frequency actually applied
  // must be the ones the current P-state calls for.
  //
  // Closes mutation M1, which every [SPEC] property passes.
  //
  // SCOPED TO COMPLETED TRANSACTIONS (`!error`), and here is why. The
  // mid-sequence abort added for B2 can stop a ramp after the voltage has been
  // raised but before the frequency and P-state follow. The part is then left
  // SAFE (freq <= volt still holds) but not MINIMAL: the supply is higher than
  // cur_pstate implies. Restoring it is not possible, because the managed
  // domain has powered down and there is nothing to drive the regulator into.
  //
  // This is a weakening, and it leaves a real residual recorded as B4 in
  // docs/BUGS_FOUND.md: after an aborted transition the operating point is
  // inconsistent until the next successful request. It does NOT blunt mutation
  // M1, which completes without error and is still caught here.
  always_ff @(posedge sclk) begin
    if (srst_n && st == S_IDLE && !error) begin
      p1b_settled_volt: assert (volt_level == req_volt(cur_pstate));
      p1b_settled_freq: assert (freq_level == req_freq(cur_pstate));
    end
  end

  // ---------------------------------------------------------------- P2 [SPEC]
  // "Frequency cannot increase until the required voltage state is reached."
  // Stated as the standing physical invariant it implies: the part is never
  // clocked faster than the supply sustains.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      p2_freq_le_volt: assert (freq_level <= volt_level);
    end
  end

  // -------------------------------------------------- decision-point capture
  // WHEN is authority evaluated? The requirements did not say, and formal
  // refused to let the question stay open: properties written over the COMMIT
  // instant (P3, P9 in their first form) were refuted by traces in which the
  // configuration changed legitimately AFTER the controller had already
  // decided. Those were not design bugs; they were the specification failing
  // to name an instant.
  //
  // A SECOND refutation sharpened this further. The property first read the
  // LIVE bus-side privilege payload. Formal produced a trace in which presetn
  // asserts while the sclk domain has not yet seen it: the bus payload resets
  // to 0 while the controller correctly continues on the credential it latched
  // when the request was accepted. The design was right and the property was
  // wrong, so it now reads obs_priv_latched -- the credential actually acted
  // upon. Preserved at verif/formal/cex/p3_live_vs_latched/.
  //
  // The answer adopted, and now recorded in docs/REQUIREMENTS.md: authority
  // and lock are evaluated ONCE, at acceptance (state S_CHECK). An in-flight
  // transition completes under the policy in force when it was accepted.
  //
  // RESIDUAL, stated rather than hidden: raising require_priv or setting lock
  // does NOT abort a transition already in flight. The exposure window is one
  // transaction, bounded by P7 at LATENCY_MAX sclk cycles. Aborting a voltage
  // ramp midway is the more dangerous option, since it can strand the part at
  // a frequency its supply does not sustain.
  logic auth_ok_q, lock_at_accept_q;

  always_ff @(posedge sclk or negedge srst_n) begin
    if (!srst_n) begin
      auth_ok_q        <= 1'b0;
      lock_at_accept_q <= 1'b0;
    end else if (st == S_CHECK) begin
      auth_ok_q        <= !(require_priv && !priv_latched);
      lock_at_accept_q <= lock;
    end
  end

  // ---------------------------------------------------------------- P3 [SPEC]
  // "Unprivileged requests cannot alter protected operating state."
  //
  // NOTE THE SHAPE. This reads `require_priv`, a CONFIGURATION BIT, to decide
  // whether privilege was needed. The check therefore trusts a label rather
  // than verifying authority. If anything can lower require_priv, this
  // assertion is satisfied by the very attack it was written to exclude.
  // Mutation M2 does exactly that, and this property still passes under it.
  // Kept verbatim as specified. P3b in spcu_props_pclk is the real check.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      p3_unpriv_no_change:
        assert (!(cur_pstate != $past(cur_pstate)) || auth_ok_q);
    end
  end

  // --------------------------------------------------------------- P3b [ADDED]
  // What P3 should have said. Authority is not a property of the action, it is
  // a property of the PROVENANCE of the permission. Checked in the pclk domain
  // in spcu_props_pclk, because that is where the authority bit is written.

  // ---------------------------------------------------------------- P4 [SPEC]
  // "Reset returns the controller to its defined safe state."
  // Combinational: the reset is asynchronous, so the safe values must hold the
  // whole time reset is low, not merely at the first clock edge after it.
  always_comb begin
    if (!srst_n) begin
      p4_reset_safe_state: assert (st == S_IDLE);
      p4_reset_safe_op:    assert (cur_pstate == 2'd0 && volt_level == 2'd0 &&
                                   freq_level == 2'd0);
      p4_reset_no_vreq:    assert (vreq == 1'b0);
    end
  end

  // ---------------------------------------------------------------- P5 [SPEC]
  // "A request crossing a clock boundary cannot cause two commits."
  // Two directions, both needed: no request may be taken while one is already
  // in flight, and no acknowledge may appear that no request asked for.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      p5_no_double_accept: assert (!(req_pulse && inflight));
      p5_no_orphan_ack:    assert (!(ack_edge && !inflight));
    end
  end

  // -------------------------------------------------------- P6 [SPEC/AMENDED]
  // "Disabled/powered-down domains cannot perform protected state changes."
  //
  // THE FIRST TRANSCRIPTION OF THIS REQUIREMENT WAS UNSATISFIABLE. It was
  // written over the CURRENT value of pd_on:
  //
  //     assert (pd_on || (volt_level == $past(volt_level)));
  //
  // Formal refuted it in 4 steps, and the counterexample is not a design bug.
  // A commit decided at the edge where pd_on was still high lands in the cycle
  // where pd_on has just gone low. No synchronous design can satisfy the
  // original property, because it demands a reaction in the same cycle as the
  // input that causes it. Preserved at verif/formal/cex/p6_unsatisfiable/.
  //
  // The requirement is therefore stated over the value the design was ENTITLED
  // TO ACT ON, which is the previous one. That is a genuine weakening and it is
  // recorded as such in docs/TRACEABILITY.md: this property permits exactly one
  // cycle of commit latency after pd_on falls. It does NOT permit the sequence
  // to continue, which is a separate obligation discharged by the mid-sequence
  // abort in spcu_ctrl_fsm.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      p6_pd_off_pstate: assert ($past(pd_on) || (cur_pstate == $past(cur_pstate)));
      p6_pd_off_volt:   assert ($past(pd_on) || (volt_level == $past(volt_level)));
      p6_pd_off_freq:   assert ($past(pd_on) || (freq_level == $past(freq_level)));
    end
  end

  // ---------------------------------------------------------------- P7 [SPEC]
  // "Accepted requests eventually resolve to DONE or ERROR."
  //
  // THIS IS NOT LIVENESS. True liveness needs s_eventually, which Yosys cannot
  // parse. What is proven here is BOUNDED RESPONSE: an accepted request
  // resolves within LATENCY_MAX sclk cycles. That is a strictly weaker claim
  // and it is only meaningful under the regulator fairness assumption in
  // verif/formal/spcu_fv_env.sv. Neither the bound nor the assumption may be
  // dropped when this result is described.
  localparam logic [7:0] LATENCY_MAX = 8'd24;

  always_ff @(posedge sclk) begin
    if (srst_n) begin
      p7_bounded_response: assert (latency < LATENCY_MAX);
    end
  end

  // ---------------------------------------------------------------- P9 [SPEC]
  // "Forbidden state transitions are refused." The lock is the coarse form of
  // that: while it is set, no request may move the operating point at all.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      // Evaluated at the decision point, for the reason recorded above.
      p9_lock_blocks: assert (!(cur_pstate != $past(cur_pstate)) || !lock_at_accept_q);
    end
  end

  // --------------------------------------------------------------- P10 [SPEC]
  // The regulator handshake is four-phase: the controller must not hold vreq
  // once the level has been applied, or the next transaction cannot tell a
  // fresh acknowledge from a stale one.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      p10_vreq_drops_after_ack: assert (!($past(vreq) && $past(vack)) || !vreq);
    end
  end

  // --------------------------------------------------------------- P11 [SPEC]
  // The applied voltage may only change as the result of a COMPLETED regulator
  // handshake. Without this, the controller can record a voltage it never
  // actually asked the regulator to supply -- the model and the silicon then
  // disagree, and nothing downstream can tell.
  //
  // Added after mutation triage: M3 (stale acknowledge) passed every other
  // property. A defect that makes the design lie about the physical world is
  // invisible to properties written only about the design's own variables.
  always_ff @(posedge sclk) begin
    if (srst_n && $past(srst_n)) begin
      p11_volt_needs_handshake:
        assert (!(volt_level != $past(volt_level)) || ($past(vreq) && $past(vack)));
    end
  end

  // --------------------------------------------------------------- P12 [SPEC]
  // "Forbidden state transitions are refused." One request moves at most one
  // P-state, so P0 -> P2 and P0 -> P3 are illegal, not merely slow.
  //
  // Added after mutation triage: M5 (off-by-one in the step check) passed every
  // other property, because a two-step jump is still internally consistent --
  // voltage leads frequency, the settled point matches, the state is legal. The
  // requirement that the jump is forbidden was simply never written down.
  always_ff @(posedge sclk) begin
    if (srst_n && $past(srst_n)) begin
      p12_single_step:
        assert (!(cur_pstate != $past(cur_pstate))
                || ((cur_pstate > $past(cur_pstate))
                    ? ((cur_pstate - $past(cur_pstate)) == 2'd1)
                    : (($past(cur_pstate) - cur_pstate) == 2'd1)));
    end
  end

  // -------------------------------------------------------------- cover
  // Coverage of the property's own reachability. If these never hit, the
  // assertions above were never exercised and their pass means nothing.
  always_ff @(posedge sclk) begin
    if (srst_n) begin
      c_req_accepted: cover (req_pulse);
      c_up_transition: cover (st == S_FREQ_UP);
      c_dn_transition: cover (st == S_VOLT_DN);
      c_refused:       cover (st == S_FINISH && cur_pstate != req_target);
      c_at_p3:         cover (cur_pstate == 2'd3);
    end
  end

endmodule
