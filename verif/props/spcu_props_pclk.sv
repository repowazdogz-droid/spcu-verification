// TIER-A PROPERTIES, pclk (APB register) domain.
//
// Separate module because Yosys states that properties spanning multiple clock
// domains are unsupported. Keeping each property single-clocked is what allows
// the formal flow to run at all; the cross-domain reasoning is instead done by
// clk2fflogic over the design, not by a multi-clock property.

module spcu_props_pclk (
    input logic        pclk,
    input logic        presetn,
    input logic        psel,
    input logic        penable,
    input logic        pwrite,
    input logic [7:0]  paddr,
    input logic        pprot0,
    input logic        pslverr,
    input logic        require_priv_q,
    input logic        lock_q
);

  localparam logic [7:0] ADDR_LOCK     = 8'h0C;
  localparam logic [7:0] ADDR_PRIV_CFG = 8'h10;

  wire wr_phase   = psel && penable && pwrite;
  wire wr_privcfg = wr_phase && (paddr == ADDR_PRIV_CFG);
  wire wr_lock    = wr_phase && (paddr == ADDR_LOCK);

  // --------------------------------------------------------------- P3b [ADDED]
  // AUTHORITY PROVENANCE. The bit that decides whether privilege is required
  // may itself only be changed by a privileged agent.
  //
  // This is the property P3 should have been. P3 asks "was this action allowed
  // under the current policy" and reads the policy bit to answer. This asks
  // "could the policy bit have been set by someone not entitled to set it",
  // which is the question an attacker actually exploits. A check that reads a
  // label is only as strong as the weakest writer of that label.
  //
  // Fails under mutation M2. Passes on the golden design.
  always_ff @(posedge pclk) begin
    if (presetn) begin
      p3b_authority_provenance:
        assert (!(require_priv_q != $past(require_priv_q))
                || $past(wr_privcfg && pprot0));
    end
  end

  // --------------------------------------------------------------- P3c [ADDED]
  // The lock is protected state too, and by the same argument.
  always_ff @(posedge pclk) begin
    if (presetn) begin
      p3c_lock_provenance:
        assert (!(lock_q != $past(lock_q)) || $past(wr_lock && pprot0));
    end
  end

  // ---------------------------------------------------------------- P8 [SPEC]
  // An unprivileged write to a privileged register must be reported, not
  // silently dropped. Silent refusal is indistinguishable from success to
  // firmware, which is its own class of bug.
  always_ff @(posedge pclk) begin
    if (presetn) begin
      p8_slverr_on_unpriv:
        assert (!((wr_privcfg || wr_lock) && !pprot0) || pslverr);
    end
  end

  // ------------------------------------------------------------------- cover
  always_ff @(posedge pclk) begin
    if (presetn) begin
      c_unpriv_write_refused: cover (wr_privcfg && !pprot0 && pslverr);
      c_priv_write_ok:        cover (wr_privcfg && pprot0);
    end
  end

endmodule
