// Formal testbench: DUT + environment constraints.
//
// TWO CLOCKING MODES, selected by the SPCU_FV_SYNC define.
//
//   SPCU_FV_SYNC defined  -- pclk and sclk are the SAME net. The CDC is
//     collapsed away. This is the mode in which the functional properties
//     (P1..P4, P6..P10) are proved by k-induction, because the state space is
//     small enough for induction to close. It proves the CONTROL LOGIC. It
//     proves nothing about the clock domain crossing, and the results must
//     never be described as if it did.
//
//   SPCU_FV_SYNC undefined -- pclk and sclk are independent free-running
//     inputs, and the .sby file runs `multiclock on` with clk2fflogic. Yosys
//     then models each flop against arbitrary clock phase, which is what lets
//     P5 (no double commit) be a statement about a genuine asynchronous
//     crossing rather than about one convenient clock ratio.
//
// The split is not a convenience. Proving everything in the multiclock model
// would be sounder but does not converge; proving everything in the collapsed
// model would converge but would be answering an easier question than the one
// asked. Each property is proved in the weakest model that can still state it,
// and docs/TRACEABILITY.md records which model each result came from.

module spcu_fv_top (
    input logic        clk_a,
    input logic        clk_b,
    input logic        presetn,
    input logic        srst_n,
    input logic        psel,
    input logic        penable,
    input logic        pwrite,
    input logic [7:0]  paddr,
    input logic [31:0] pwdata,
    input logic        pprot0,
    input logic        pd_on,
    input logic        vack,

    // OBSERVABLE OUTPUTS.
    //
    // Present so that mutation analysis can build an equivalence miter between
    // the golden and mutated designs. Without ports, a miter has nothing to
    // compare and every mutant looks equivalent -- which would have silently
    // classified all 98 survivors as harmless.
    //
    // They carry no assertions and do not affect any proof.
    output logic [31:0] o_prdata,
    output logic        o_pready,
    output logic        o_pslverr,
    output logic        o_vreq,
    output logic [1:0]  o_vlevel,
    output logic [1:0]  o_cur_pstate,
    output logic [1:0]  o_volt_level,
    output logic [1:0]  o_freq_level
);

`ifdef SPCU_FV_SYNC
  wire pclk = clk_a;
  wire sclk = clk_a;
`else
  wire pclk = clk_a;
  wire sclk = clk_b;
`endif

  logic [31:0] prdata;
  logic        pready, pslverr;
  logic        vreq;
  logic [1:0]  vlevel, cur_pstate, volt_level, freq_level;

  spcu_top u_dut (
      .pclk      (pclk),
      .presetn   (presetn),
      .psel      (psel),
      .penable   (penable),
      .pwrite    (pwrite),
      .paddr     (paddr),
      .pwdata    (pwdata),
      .pprot0    (pprot0),
      .prdata    (prdata),
      .pready    (pready),
      .pslverr   (pslverr),
      .sclk      (sclk),
      .srst_n    (srst_n),
      .pd_on     (pd_on),
      .vack      (vack),
      .vreq      (vreq),
      .vlevel    (vlevel),
      .cur_pstate(cur_pstate),
      .volt_level(volt_level),
      .freq_level(freq_level)
  );

  spcu_fv_env u_env (
      .sclk   (sclk),
      .srst_n (srst_n),
      .vreq   (vreq),
      .vack   (vack),
      .pclk   (pclk),
      .presetn(presetn),
      .psel   (psel),
      .penable(penable),
      .pready (pready)
  );

  assign o_prdata     = prdata;
  assign o_pready     = pready;
  assign o_pslverr    = pslverr;
  assign o_vreq       = vreq;
  assign o_vlevel     = vlevel;
  assign o_cur_pstate = cur_pstate;
  assign o_volt_level = volt_level;
  assign o_freq_level = freq_level;

  // ANCHOR THE INITIAL STATE.
  //
  // Without this the solver begins in an arbitrary flop assignment and every
  // property fails from a configuration no reset could produce -- a true
  // counterexample to a claim nobody made.
  //
  // `initial assume(...)` is the natural way to write it and is REJECTED by
  // slang ("reading net state during design initialization unsupported"), so
  // the reset window is driven by a counter that carries a declaration
  // initialiser instead. The counter must be wide enough that the window spans
  // an sclk edge even when the two clocks are independent under clk2fflogic.
  //
  // Reset is left FREE after the window closes, deliberately: P4 is a claim
  // about reset behaviour, and constraining reset to stay deasserted would
  // make P4 unfalsifiable.
  logic [2:0] rst_cnt = 3'd0;

  always_ff @(posedge clk_a) begin
    if (rst_cnt != 3'd7) rst_cnt <= rst_cnt + 3'd1;
  end

  always_comb begin
    if (rst_cnt < 3'd4) begin
      assume (!presetn);
      assume (!srst_n);
    end
  end

endmodule
