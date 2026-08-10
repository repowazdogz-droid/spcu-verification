// Formal environment constraints.
//
// EVERY assumption in this file weakens every proof that depends on it. They
// are collected here, and nowhere else, so that the exact strength of a PASS
// can be read off one page.
//
// THE ASSUMPTION THAT IS DELIBERATELY ABSENT
//   The obvious constraint to write is `assume (!vack || vreq)` -- the
//   regulator only acknowledges what was asked for. It is NOT written, because
//   it would make mutation M3 (sampling bare vack instead of vreq && vack)
//   unfalsifiable: under that assumption a stale acknowledge cannot exist, so
//   the property that should catch M3 would pass vacuously and the proof would
//   be an artefact of the environment rather than a fact about the design.
//   vack is therefore left free apart from the fairness bound below.
//   Checked, not assumed: see docs/BUGS_FOUND.md, "assumption audit".

module spcu_fv_env #(
    parameter logic [3:0] VACK_MAX = 4'd4
) (
    input logic sclk,
    input logic srst_n,
    input logic vreq,
    input logic vack,
    // APB side
    input logic pclk,
    input logic presetn,
    input logic psel,
    input logic penable,
    input logic pready
);

  // ------------------------------------------------------- regulator fairness
  // The ONLY constraint on the regulator: once a request has been held for
  // VACK_MAX cycles, it must be acknowledged. Without this, vack may never
  // arrive and P7 (bounded response) is simply false -- correctly so, because
  // an unbounded regulator genuinely does hang the controller.
  //
  // This is a LIVENESS assumption discharged as a bounded safety constraint.
  // It is the reason P7 must be described as "bounded response under a stated
  // regulator fairness assumption" and never as liveness.
  logic [3:0] vreq_age;

  always_ff @(posedge sclk or negedge srst_n) begin
    if (!srst_n)               vreq_age <= 4'd0;
    else if (!vreq)            vreq_age <= 4'd0;
    else if (vreq_age != VACK_MAX) vreq_age <= vreq_age + 4'd1;
  end

  always_ff @(posedge sclk) begin
    if (srst_n) begin
      a_vack_fairness: assume (!(vreq && (vreq_age >= VACK_MAX)) || vack);
    end
  end

  // -------------------------------------------------- reset ordering (R22)
  //
  // AN INTEGRATION CONSTRAINT ON THE IP, not a modelling convenience, and it
  // was DISCOVERED by formal rather than assumed up front.
  //
  // With fully independent resets, R18b is REFUTED: presetn can clear the
  // launch-side payload while the request toggle is still inside the sclk
  // synchroniser, so the controller consumes a request whose payload the
  // source domain has already wiped. Counterexample preserved at
  // verif/formal/cex/r18_payload_settling/.
  //
  // No RTL fix is available locally. At the failing instant the synchronised
  // pclk reset (presetn_s) is STILL HIGH -- the reset information has not yet
  // crossed -- so no observable signal in the sclk domain can distinguish the
  // case. Closing it inside the IP would need a full reset handshake between
  // domains. The standard alternative, and the one taken here, is to state the
  // requirement on the integrator: the controller domain must be held in reset
  // whenever the register domain is.
  //
  // Kept behind a define so the residual stays reproducible in one command:
  //   sby -f verif/formal/spcu.sby rdc_freerst   (resets free, R18b disabled)
`ifndef SPCU_FREE_RESETS
  always_comb begin
    a_reset_order: assume (presetn || !srst_n);
  end
`endif

  // ------------------------------------------------------------ APB3 legality
  // A conforming master. These constrain the ENVIRONMENT, not the DUT: without
  // them the solver invents illegal bus behaviour and reports design bugs that
  // no real master could provoke.
  always_ff @(posedge pclk) begin
    if (presetn) begin
      // ACCESS phase implies the slave was selected.
      a_apb_enable_implies_sel: assume (!penable || psel);
      // ACCESS is preceded by SETUP.
      a_apb_setup_first:        assume (!penable || $past(psel));
      // With pready tied high, a transfer completes in one ACCESS cycle, so
      // penable is never high on two consecutive cycles.
      a_apb_single_cycle:       assume (!(penable && $past(penable) && $past(pready)));
    end
  end

endmodule
