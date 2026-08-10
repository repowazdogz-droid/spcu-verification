// SPCU DVFS sequencer. Runs in the sclk (always-on) domain.
//
// AUTHORITY MODEL
//   The controller is always-on. `pd_on` refers to the MANAGED power domain
//   whose voltage and frequency this block controls, not to the controller
//   itself. Changing the operating point of a powered-down domain is refused.
//
//   Authority is decided HERE, in series with the state change, not at the
//   APB bus. `req_priv` is the pprot[0] of the agent that wrote CTRL.GO,
//   captured at that write. `require_priv` is PRIV_CFG.REQUIRE_PRIV.
//
// DVFS ORDERING
//   Raising the operating point raises voltage FIRST, then frequency.
//   Lowering it lowers frequency FIRST, then voltage.
//   Consequently freq_level <= volt_level holds at every instant, which is the
//   physical safety requirement: the part must never be clocked faster than
//   its supply sustains.
//
// STEP RULE
//   One request moves at most one P-state. A request more than one step away
//   is refused. This makes P0 -> P3 an illegal transition rather than a slow
//   one, and gives the "forbidden transition" requirement a crisp form.

module spcu_ctrl_fsm
  import spcu_pkg::*;
(
    input  logic       sclk,
    input  logic       srst_n,
    // request in (sclk domain, already synchronised)
    input  logic       req_pulse,
    input  logic [1:0] req_target,
    input  logic       req_priv,
    // configuration (sclk domain, already synchronised)
    input  logic       require_priv,
    input  logic       lock,
    input  logic       pd_on,
    // voltage regulator handshake
    input  logic       vack,
    output logic       vreq,
    output logic [1:0] vlevel,
    // observable operating point
    output logic [1:0] volt_level,
    output logic [1:0] freq_level,
    output logic [1:0] cur_pstate,
    // completion
    output logic       done,
    output logic       error,
    output logic       ack_tog,
    output fsm_e       st,
    // Verification observation port. The credential the controller LATCHED and
    // actually acted on, which during an asymmetric reset window is not the
    // same as the live payload on the bus side. Properties must reason about
    // the value the design decided with, not a value that has since changed
    // underneath it.
    output logic       obs_priv_latched
);

  logic [1:0] tgt_q;
  logic       priv_q;
  logic       err_q;   // outcome of this request, settled before S_ACK

  // Distance between the request and where we are now.
  wire [1:0] step = (tgt_q > cur_pstate) ? (tgt_q - cur_pstate)
                                         : (cur_pstate - tgt_q);
  wire illegal_step = (step > 2'd1);

  // Levels the requested P-state calls for, and whether the applied levels
  // already match them.
  //
  // The comparison is against the APPLIED LEVELS, not against cur_pstate.
  // Comparing P-states alone made the controller treat "already there" as
  // "nothing to do", which let a stale operating point left behind by an
  // aborted ramp survive a subsequent successful request. Driving off the
  // levels makes the controller self-correcting: any request re-establishes
  // the invariant whether or not the P-state itself is changing.
  wire [1:0] want_v = req_volt(tgt_q);
  wire [1:0] want_f = req_freq(tgt_q);
  wire needs_up = (want_v > volt_level) || (want_f > freq_level);
  wire needs_dn = (want_f < freq_level) || (want_v < volt_level);

  // The in-series authority decision. Every term is a reason to refuse.
  wire refuse = !pd_on
             || lock
             || (require_priv && !priv_q)
             || illegal_step;

  always_ff @(posedge sclk or negedge srst_n) begin
    if (!srst_n) begin
      st         <= S_IDLE;
      tgt_q      <= 2'd0;
      priv_q     <= 1'b0;
      err_q      <= 1'b0;
      cur_pstate <= 2'd0;
      volt_level <= 2'd0;
      freq_level <= 2'd0;
      vreq       <= 1'b0;
      vlevel     <= 2'd0;
      done       <= 1'b0;
      error      <= 1'b0;
      ack_tog    <= 1'b0;
    end else if (!pd_on && st != S_IDLE && st != S_FINISH && st != S_ACK) begin
      // MID-SEQUENCE ABORT. FOUND BY FORMAL, NOT SEEDED. docs/BUGS_FOUND.md B2.
      //
      // Testing pd_on once in S_CHECK is a check of the request, not of the
      // sequence. The managed domain can power down at any point during a
      // multi-cycle voltage or frequency ramp, and before this fix the
      // controller carried on driving the regulator and updating volt_level
      // into a domain that was no longer there.
      //
      // Note the shape of the original defect: the guard existed, ran, and
      // returned the right answer -- for the instant it was evaluated. A
      // precondition checked once is not an invariant maintained throughout.
      err_q <= 1'b1;
      vreq  <= 1'b0;
      st    <= S_FINISH;
    end else begin
      case (st)

        S_IDLE: begin
          vreq <= 1'b0;
          if (req_pulse) begin
            tgt_q  <= req_target;
            priv_q <= req_priv;
            done   <= 1'b0;
            error  <= 1'b0;
            st     <= S_CHECK;
          end
        end

        S_CHECK: begin
          if (refuse) begin
            err_q <= 1'b1;
            st    <= S_FINISH;
          end else if (needs_up) begin
            st <= S_VOLT_UP;
          end else if (needs_dn) begin
            st <= S_FREQ_DN;
          end else begin
            // Already at the required levels. Adopt the P-state and finish.
            cur_pstate <= tgt_q;
            err_q      <= 1'b0;
            st         <= S_FINISH;
          end
        end

        // ---- raising: voltage first, then frequency ----
        // `vreq && vack`, not bare `vack`: the acknowledge is only meaningful
        // once our own request is on the wire. Sampling bare vack accepts an
        // acknowledge left over from the previous transaction. That is
        // mutation M3 (stale acknowledge).
        S_VOLT_UP: begin
          vreq   <= 1'b1;
          vlevel <= want_v;
          if (vreq && vack) begin
            volt_level <= want_v;
            vreq       <= 1'b0;
            st         <= S_FREQ_UP;
          end
        end

        S_FREQ_UP: begin
          freq_level <= want_f;
          cur_pstate <= tgt_q;
          err_q      <= 1'b0;
          st         <= S_FINISH;
        end

        // ---- lowering: frequency first, then voltage ----
        S_FREQ_DN: begin
          freq_level <= want_f;
          st         <= S_VOLT_DN;
        end

        S_VOLT_DN: begin
          vreq   <= 1'b1;
          vlevel <= want_v;
          if (vreq && vack) begin
            volt_level <= want_v;
            cur_pstate <= tgt_q;
            vreq       <= 1'b0;
            err_q      <= 1'b0;
            st         <= S_FINISH;
          end
        end

        // Payload settles here...
        S_FINISH: begin
          done  <= ~err_q;
          error <=  err_q;
          st    <= S_ACK;
        end

        // ...and only then does the toggle cross the boundary. One sclk cycle
        // of separation is what makes the pclk side's sampling of done/error
        // safe when its own ack edge arrives.
        S_ACK: begin
          ack_tog <= ~ack_tog;
          st      <= S_IDLE;
        end

        default: st <= S_IDLE;

      endcase
    end
  end

  assign obs_priv_latched = priv_q;

endmodule
