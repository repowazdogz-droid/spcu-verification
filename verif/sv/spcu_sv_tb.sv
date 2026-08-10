// SystemVerilog class-based testbench for SPCU.
//
// WHAT THIS IS, AND WHAT IT IS NOT
//   This is a class-based, constrained-random, self-checking SystemVerilog
//   testbench. It is NOT UVM. There is no uvm_pkg here, no factory, no phasing,
//   no config_db, because no freely available simulator runs SystemVerilog UVM.
//   The UVM-architecture testbench for this DUT is verif/pyuvm/, written in
//   pyuvm against cocotb. Neither is commercial SystemVerilog UVM experience
//   and docs/TRACEABILITY.md says so.
//
//   What this file does demonstrate: SystemVerilog classes, constrained random
//   generation with `randomize()`, a transaction-level driver, a reference
//   model, a scoreboard, and functional coverage via covergroups.
//
// CLOCKING
//   pclk and sclk are deliberately asynchronous with a non-integer period
//   ratio (10 vs 14). An integer ratio hides CDC bugs by making the sampling
//   relationship repeat, which is exactly the class of defect the crossing is
//   there to survive.

`timescale 1ns/1ps

module spcu_sv_tb;

  import spcu_pkg::*;

  // ------------------------------------------------------------------ clocks
  logic pclk = 1'b0;
  logic sclk = 1'b0;
  always #5 pclk = ~pclk;   // 10 ns
  always #7 sclk = ~sclk;   // 14 ns, asynchronous to pclk

  logic presetn = 1'b0;
  logic srst_n  = 1'b0;

  // --------------------------------------------------------------- DUT wires
  logic        psel = 0, penable = 0, pwrite = 0, pprot0 = 0;
  logic [7:0]  paddr = '0;
  logic [31:0] pwdata = '0;
  logic [31:0] prdata;
  logic        pready, pslverr;
  logic        pd_on = 1'b1;
  logic        vack = 1'b0;
  logic        vreq;
  logic [1:0]  vlevel, cur_pstate, volt_level, freq_level;

  spcu_top u_dut (
      .pclk(pclk), .presetn(presetn), .psel(psel), .penable(penable),
      .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata), .pprot0(pprot0),
      .prdata(prdata), .pready(pready), .pslverr(pslverr),
      .sclk(sclk), .srst_n(srst_n), .pd_on(pd_on), .vack(vack),
      .vreq(vreq), .vlevel(vlevel),
      .cur_pstate(cur_pstate), .volt_level(volt_level), .freq_level(freq_level)
  );

  spcu_sva_tier_b u_tier_b (
      .sclk(sclk), .srst_n(u_dut.rst_n_s), .vreq(vreq), .vack(vack),
      .volt_level(volt_level), .freq_level(freq_level),
      .req_pulse(u_dut.req_pulse_s), .done(u_dut.done_s), .error(u_dut.error_s)
  );

  // ------------------------------------------------------------- PMIC model
  // Responds to vreq after a variable delay, then drops vack when vreq drops.
  // The delay is randomised so the controller is not verified against one
  // convenient regulator latency.
  int pmic_delay = 2;
  always @(posedge sclk) begin
    if (!srst_n) begin
      vack <= 1'b0;
    end else if (vreq && !vack) begin
      repeat (pmic_delay) @(posedge sclk);
      vack <= 1'b1;
    end else if (!vreq) begin
      vack <= 1'b0;
    end
  end

  // ----------------------------------------------------------- register map
  localparam logic [7:0] A_ID = 8'h00, A_CTRL = 8'h04, A_STATUS = 8'h08,
                         A_LOCK = 8'h0C, A_PRIV = 8'h10;

  // ------------------------------------------------------------- transaction
  class dvfs_req;
    rand bit [1:0] target;
    rand bit       priv;
    rand bit       use_lock;
    // Weighted so that legal single-step requests dominate but illegal
    // multi-step jumps and unprivileged attempts still occur often enough to
    // exercise the refusal paths.
    constraint c_priv     { priv     dist {1 := 8, 0 := 2}; }
    constraint c_use_lock { use_lock dist {0 := 9, 1 := 1}; }
  endclass

  // ---------------------------------------------------------------- coverage
  bit [1:0] cov_target;
  bit       cov_priv;
  bit       cov_err;

  // SAMPLED EXPLICITLY AT EACH REQUEST, not on a clock edge.
  //
  // The first version was `covergroup cg_request @(posedge pclk);`, which
  // reported 100.0% and meant nothing. It sampled every pclk edge against
  // variables that only change once per request, so every bin filled from the
  // stale values left lying around between transactions. The number measured
  // "did these variables ever hold these values", not "were these request
  // types exercised" -- which is the requirement it is supposed to stand for.
  //
  // A coverage figure is a claim about stimulus. If the sampling event is not
  // the event the requirement is about, the figure is not evidence for it.
  covergroup cg_request;
    option.per_instance = 1;
    cp_target : coverpoint cov_target { bins p[] = {0, 1, 2, 3}; }
    cp_priv   : coverpoint cov_priv   { bins unpriv = {0}; bins priv = {1}; }
    cp_err    : coverpoint cov_err    { bins ok = {0}; bins refused = {1}; }
    x_target_priv : cross cp_target, cp_priv;
  endgroup

  cg_request cg = new();

  // ------------------------------------------------------------------- BFM
  task automatic apb_write(input logic [7:0] a, input logic [31:0] d,
                           input logic priv);
    @(posedge pclk);
    psel <= 1; pwrite <= 1; paddr <= a; pwdata <= d; pprot0 <= priv; penable <= 0;
    @(posedge pclk);
    penable <= 1;
    @(posedge pclk);
    psel <= 0; penable <= 0; pwrite <= 0;
  endtask

  task automatic apb_read(input logic [7:0] a, output logic [31:0] d);
    @(posedge pclk);
    psel <= 1; pwrite <= 0; paddr <= a; pprot0 <= 1; penable <= 0;
    @(posedge pclk);
    penable <= 1;
    @(posedge pclk);
    d = prdata;
    psel <= 0; penable <= 0;
  endtask

  task automatic wait_idle(input int max_cycles = 200);
    logic [31:0] st;
    int n = 0;
    forever begin
      apb_read(A_STATUS, st);
      if (!st[4]) break;                 // BUSY clear
      n++;
      if (n > max_cycles) begin
        $display("[%0t] ERROR: timeout waiting for BUSY to clear", $time);
        errors++;
        break;
      end
    end
  endtask

  // ------------------------------------------------------- reference model
  // Deliberately independent of the RTL: it predicts from the REQUEST and the
  // rules in docs/REQUIREMENTS.md, not by mirroring the FSM. A model that
  // mirrors the implementation agrees with it by construction and checks
  // nothing.
  bit [1:0] ref_pstate = 2'd0;
  int       errors = 0;
  int       checks = 0;

  function automatic bit ref_would_refuse(input bit [1:0] tgt, input bit priv,
                                          input bit require_priv, input bit lock,
                                          input bit pd);
    int diff;
    diff = (tgt > ref_pstate) ? (tgt - ref_pstate) : (ref_pstate - tgt);
    return (!pd) || lock || (require_priv && !priv) || (diff > 1);
  endfunction

  task automatic check_after(input bit [1:0] tgt, input bit expect_refuse);
    logic [31:0] st;
    apb_read(A_STATUS, st);
    checks++;
    if (expect_refuse) begin
      if (st[6] !== 1'b1) begin
        $display("[%0t] MISMATCH: expected ERROR for target %0d, STATUS=%08x",
                 $time, tgt, st);
        errors++;
      end
    end else begin
      ref_pstate = tgt;
      if (st[1:0] !== ref_pstate) begin
        $display("[%0t] MISMATCH: expected P%0d, got P%0d (STATUS=%08x)",
                 $time, ref_pstate, st[1:0], st);
        errors++;
      end
      if (st[13:12] !== st[11:10]) begin
        $display("[%0t] MISMATCH: settled freq %0d != volt %0d",
                 $time, st[13:12], st[11:10]);
        errors++;
      end
    end
  endtask

  task automatic do_request(input bit [1:0] tgt, input bit priv,
                            input bit require_priv = 1'b1,
                            input bit lock = 1'b0);
    bit refuse;
    refuse = ref_would_refuse(tgt, priv, require_priv, lock, pd_on);
    cov_target = tgt; cov_priv = priv; cov_err = refuse;
    cg.sample();
    apb_write(A_CTRL, {23'd0, 1'b1, 6'd0, tgt}, priv);
    wait_idle();
    check_after(tgt, refuse);
  endtask

  // ------------------------------------------------------------------ tests
  task automatic t_reset_and_id;
    logic [31:0] d;
    apb_read(A_ID, d);
    checks++;
    if (d !== 32'h53504355) begin
      $display("[%0t] MISMATCH: ID=%08x expected 53504355", $time, d);
      errors++;
    end
    apb_read(A_STATUS, d);
    checks++;
    if (d[1:0] !== 2'd0) begin
      $display("[%0t] MISMATCH: post-reset P-state %0d, expected 0", $time, d[1:0]);
      errors++;
    end
  endtask

  task automatic t_walk_up_and_down;
    do_request(2'd1, 1'b1);
    do_request(2'd2, 1'b1);
    do_request(2'd3, 1'b1);
    do_request(2'd2, 1'b1);
    do_request(2'd1, 1'b1);
    do_request(2'd0, 1'b1);
  endtask

  task automatic t_illegal_jump;
    // P0 -> P2 is more than one step and must be refused.
    do_request(2'd2, 1'b1);
  endtask

  task automatic t_unprivileged_refused;
    do_request(2'd1, 1'b0);
  endtask

  task automatic t_unpriv_cannot_write_privcfg;
    logic [31:0] d;
    apb_write(A_PRIV, 32'h0, 1'b0);      // unprivileged attempt
    apb_read(A_PRIV, d);
    checks++;
    if (d[0] !== 1'b1) begin
      $display("[%0t] SECURITY: unprivileged write cleared REQUIRE_PRIV", $time);
      errors++;
    end
  endtask

  task automatic t_lock_blocks;
    apb_write(A_LOCK, 32'h1, 1'b1);
    do_request(2'd1, 1'b1, 1'b1, 1'b1);
    apb_write(A_LOCK, 32'h0, 1'b1);
  endtask

  task automatic t_power_down_refused;
    pd_on = 1'b0;
    repeat (8) @(posedge sclk);
    do_request(2'd1, 1'b1, 1'b1, 1'b0);
    pd_on = 1'b1;
    repeat (8) @(posedge sclk);
  endtask

  task automatic t_constrained_random(input int n);
    dvfs_req r = new();
    for (int i = 0; i < n; i++) begin
      if (!r.randomize()) begin
        $display("[%0t] ERROR: randomize() failed", $time);
        errors++;
        break;
      end
      pmic_delay = 1 + (i % 4);
      do_request(r.target, r.priv);
    end
  endtask

  // ------------------------------------------------------------------- main
  string testname;

  initial begin
    if (!$value$plusargs("TEST=%s", testname)) testname = "all";

    presetn = 0; srst_n = 0;
    repeat (6) @(posedge pclk);
    presetn = 1; srst_n = 1;
    repeat (6) @(posedge pclk);

    $display("=== SPCU SystemVerilog TB : test=%s ===", testname);

    if (testname == "all" || testname == "reset")   t_reset_and_id();
    if (testname == "all" || testname == "walk")    t_walk_up_and_down();
    if (testname == "all" || testname == "illegal") t_illegal_jump();
    if (testname == "all" || testname == "unpriv")  t_unprivileged_refused();
    if (testname == "all" || testname == "sec")     t_unpriv_cannot_write_privcfg();
    if (testname == "all" || testname == "lock")    t_lock_blocks();
    if (testname == "all" || testname == "pd")      t_power_down_refused();
    if (testname == "all" || testname == "random")  t_constrained_random(40);

    repeat (20) @(posedge pclk);

    $display("=== checks=%0d errors=%0d coverage=%0.1f%% ===",
             checks, errors, cg.get_inst_coverage());
    if (errors == 0) $display("TEST PASSED");
    else             $display("TEST FAILED (%0d mismatches)", errors);
    $finish;
  end

  // Global watchdog. A hung testbench that never prints PASSED is a failure,
  // not a silent success.
  initial begin
    #4000000;
    $display("TEST FAILED (global timeout)");
    $finish;
  end

endmodule
