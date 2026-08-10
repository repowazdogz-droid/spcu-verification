// SPCU top level. Two clock domains, joined by one two-phase toggle handshake.
//
//   pclk  (APB register domain)          sclk  (always-on controller domain)
//   ------------------------------       ----------------------------------
//   spcu_regs                            spcu_ctrl_fsm
//   busy_p, target_p, priv_p             cur_pstate, volt_level, freq_level
//        |  req_tog_p  ------- sync2 ------->  req_pulse_s
//        |  done_pulse_p <----- sync2 -------  ack_tog_s
//
// CROSSING DISCIPLINE
//   Control crossings are TOGGLES through spcu_sync2, never pulses: a pulse
//   narrower than the destination clock period can be missed entirely, and a
//   pulse wider than one destination period can be seen twice. A toggle holds
//   its value until the next event, so exactly one edge is observed.
//
//   Payload (target_p, priv_p, and the returning status) is NOT synchronised.
//   It is data-with-handshake: the payload is written on the same pclk edge
//   that flips req_tog_p and then held until the transaction completes, so it
//   has been stable for at least two sclk edges by the time req_pulse_s fires.
//   Synchronising a multi-bit payload with per-bit 2FF would be WORSE, not
//   better: the bits would resolve independently and could be sampled as a
//   value that was never driven.

module spcu_top
  import spcu_pkg::*;
(
    // ---- APB register domain ----
    input  logic        pclk,
    input  logic        presetn,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [7:0]  paddr,
    input  logic [31:0] pwdata,
    input  logic        pprot0,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // ---- controller domain ----
    input  logic        sclk,
    input  logic        srst_n,
    input  logic        pd_on,          // managed power domain is on
    input  logic        vack,           // regulator acknowledge
    output logic        vreq,           // regulator request
    output logic [1:0]  vlevel,

    // ---- observable operating point (sclk domain) ----
    output logic [1:0]  cur_pstate,
    output logic [1:0]  volt_level,
    output logic [1:0]  freq_level
);

  // ------------------------------------------------------------------ regs
  logic [1:0] ctrl_target_q;
  logic       ctrl_go_wpulse, ctrl_go_wpulse_priv;
  logic       lock_locked_q, priv_cfg_require_priv_q;

  logic [1:0] status_cur_pstate_i, status_volt_i, status_freq_i;
  logic       status_busy_i, status_done_i, status_error_i, status_pd_on_i;

  spcu_regs u_regs (
      .pclk                   (pclk),
      .presetn                (presetn),
      .psel                   (psel),
      .penable                (penable),
      .pwrite                 (pwrite),
      .paddr                  (paddr),
      .pwdata                 (pwdata),
      .pprot0                 (pprot0),
      .prdata                 (prdata),
      .pready                 (pready),
      .pslverr                (pslverr),
      .ctrl_target_q          (ctrl_target_q),
      .ctrl_go_wpulse         (ctrl_go_wpulse),
      .ctrl_go_wpulse_priv    (ctrl_go_wpulse_priv),
      .status_cur_pstate_i    (status_cur_pstate_i),
      .status_busy_i          (status_busy_i),
      .status_done_i          (status_done_i),
      .status_error_i         (status_error_i),
      .status_pd_on_i         (status_pd_on_i),
      .status_volt_i          (status_volt_i),
      .status_freq_i          (status_freq_i),
      .lock_locked_q          (lock_locked_q),
      .priv_cfg_require_priv_q(priv_cfg_require_priv_q)
  );

  // ------------------------------------------- reset domain crossing (RDC)
  //
  // FOUND BY FORMAL, NOT SEEDED. See docs/BUGS_FOUND.md B1.
  //
  // presetn and srst_n are independent inputs, as they are in a real SoC where
  // each power/clock domain has its own reset controller. Before this fix, a
  // pclk reset asserted while a request was in flight cleared req_tog_p back
  // to 0 while the launched 1 was still inside the sclk synchroniser. The sclk
  // side then observed TWO toggle edges for one request and processed a
  // transaction the register domain had already abandoned.
  //
  // A CDC synchroniser protects against clock asynchrony. It does nothing
  // about reset asynchrony: both endpoints of a handshake must leave reset
  // consistently, or the handshake state itself is corrupt. So each domain's
  // reset is crossed into the other, and the handshake on both sides is held
  // in reset while EITHER domain is in reset.
  logic presetn_s, srst_n_p;

  // These two synchronisers are the only registers reset by a single domain's
  // reset alone. Anything else would be circular.
  spcu_sync2 u_sync_prst (.dclk(sclk), .drst_n(srst_n),  .d(presetn), .q(presetn_s));
  spcu_sync2 u_sync_srst (.dclk(pclk), .drst_n(presetn), .d(srst_n),  .q(srst_n_p));

  wire rst_n_s = srst_n  && presetn_s;   // sclk-domain combined reset
  wire rst_n_p = presetn && srst_n_p;    // pclk-domain combined reset

  // ------------------------------------------------- pclk-side transaction
  logic       busy_p, req_tog_p;
  logic [1:0] target_p;
  logic       priv_p;
  logic       ack_tog_p, ack_tog_p_d;

  // A request is accepted only when none is in flight. This is what keeps the
  // payload stable for the whole crossing.
  wire go_accept    = ctrl_go_wpulse && !busy_p;
  wire done_pulse_p = ack_tog_p ^ ack_tog_p_d;

  always_ff @(posedge pclk or negedge rst_n_p) begin
    if (!rst_n_p) begin
      busy_p      <= 1'b0;
      req_tog_p   <= 1'b0;
      target_p    <= 2'd0;
      priv_p      <= 1'b0;
      ack_tog_p_d <= 1'b0;
    end else begin
      ack_tog_p_d <= ack_tog_p;
      if (go_accept) begin
        req_tog_p <= ~req_tog_p;
        target_p  <= ctrl_target_q;
        priv_p    <= ctrl_go_wpulse_priv;
        busy_p    <= 1'b1;
      end else if (done_pulse_p) begin
        busy_p <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------- pclk -> sclk (req)
  logic req_tog_s, req_tog_s_d;
  spcu_sync2 u_sync_req (.dclk(sclk), .drst_n(rst_n_s), .d(req_tog_p), .q(req_tog_s));

  logic require_priv_s, lock_s, pd_on_s, vack_s;
  spcu_sync2 u_sync_rp   (.dclk(sclk), .drst_n(rst_n_s), .d(priv_cfg_require_priv_q), .q(require_priv_s));
  spcu_sync2 u_sync_lock (.dclk(sclk), .drst_n(rst_n_s), .d(lock_locked_q),           .q(lock_s));
  spcu_sync2 u_sync_pd   (.dclk(sclk), .drst_n(rst_n_s), .d(pd_on),                   .q(pd_on_s));
  spcu_sync2 u_sync_vack (.dclk(sclk), .drst_n(rst_n_s), .d(vack),                    .q(vack_s));

  always_ff @(posedge sclk or negedge rst_n_s) begin
    if (!rst_n_s) req_tog_s_d <= 1'b0;
    else         req_tog_s_d <= req_tog_s;
  end

  wire req_pulse_s = req_tog_s ^ req_tog_s_d;

  // ------------------------------------------------------------ controller
  logic done_s, error_s, ack_tog_s, priv_latched_s;
  fsm_e st_s;

  spcu_ctrl_fsm u_fsm (
      .sclk        (sclk),
      .srst_n      (rst_n_s),
      .req_pulse   (req_pulse_s),
      .req_target  (target_p),
      .req_priv    (priv_p),
      .require_priv(require_priv_s),
      .lock        (lock_s),
      .pd_on       (pd_on_s),
      .vack        (vack_s),
      .vreq        (vreq),
      .vlevel      (vlevel),
      .volt_level  (volt_level),
      .freq_level  (freq_level),
      .cur_pstate  (cur_pstate),
      .done        (done_s),
      .error       (error_s),
      .ack_tog     (ack_tog_s),
      .st          (st_s),
      .obs_priv_latched (priv_latched_s)
  );

  // ---------------------------------------------------- sclk -> pclk (ack)
  spcu_sync2 u_sync_ack (.dclk(pclk), .drst_n(rst_n_p), .d(ack_tog_s), .q(ack_tog_p));

  // Returning status is data-with-handshake in the other direction: sampled
  // only on done_pulse_p, by which time the FSM has held it stable since
  // S_FINISH, one sclk cycle before it toggled ack.
  logic [1:0] st_cur_q, st_volt_q, st_freq_q;
  logic       st_done_q, st_error_q;
  logic [1:0] cur_ps_p, volt_p, freq_p;
  logic       done_p, error_p, pd_on_p;

  spcu_sync2 #(.WIDTH(2)) u_s_cur  (.dclk(pclk), .drst_n(rst_n_p), .d(cur_pstate), .q(cur_ps_p));
  spcu_sync2 #(.WIDTH(2)) u_s_volt (.dclk(pclk), .drst_n(rst_n_p), .d(volt_level), .q(volt_p));
  spcu_sync2 #(.WIDTH(2)) u_s_freq (.dclk(pclk), .drst_n(rst_n_p), .d(freq_level), .q(freq_p));
  spcu_sync2              u_s_done (.dclk(pclk), .drst_n(rst_n_p), .d(done_s),     .q(done_p));
  spcu_sync2              u_s_err  (.dclk(pclk), .drst_n(rst_n_p), .d(error_s),    .q(error_p));
  spcu_sync2              u_s_pd   (.dclk(pclk), .drst_n(rst_n_p), .d(pd_on),      .q(pd_on_p));

  always_ff @(posedge pclk or negedge rst_n_p) begin
    if (!rst_n_p) begin
      st_cur_q   <= 2'd0;
      st_volt_q  <= 2'd0;
      st_freq_q  <= 2'd0;
      st_done_q  <= 1'b0;
      st_error_q <= 1'b0;
    end else if (done_pulse_p) begin
      st_cur_q   <= cur_ps_p;
      st_volt_q  <= volt_p;
      st_freq_q  <= freq_p;
      st_done_q  <= done_p;
      st_error_q <= error_p;
    end
  end

  assign status_cur_pstate_i = st_cur_q;
  assign status_volt_i       = st_volt_q;
  assign status_freq_i       = st_freq_q;
  assign status_done_i       = st_done_q;
  assign status_error_i      = st_error_q;
  assign status_busy_i       = busy_p;
  assign status_pd_on_i      = pd_on_p;

  // --------------------------------------------------------- Tier-A checks
  // Instantiated unconditionally, NOT inside an ifdef. One property source is
  // read by Verilator simulation and by Yosys/SBY formal. See
  // verif/props/spcu_props.sv for why the subset is restricted to immediate
  // assertions.
  spcu_props u_props (
      .sclk        (sclk),
      .srst_n      (rst_n_s),
      .st          (st_s),
      .cur_pstate  (cur_pstate),
      .volt_level  (volt_level),
      .freq_level  (freq_level),
      .req_pulse   (req_pulse_s),
      .req_target  (target_p),
      .req_priv    (priv_p),
      .require_priv(require_priv_s),
      .lock        (lock_s),
      .pd_on       (pd_on_s),
      .vreq        (vreq),
      .vack        (vack_s),
      .ack_tog     (ack_tog_s),
      .error       (error_s),
      .priv_latched(priv_latched_s)
  );

  spcu_props_pclk u_props_pclk (
      .pclk          (pclk),
      .presetn       (rst_n_p),
      .psel          (psel),
      .penable       (penable),
      .pwrite        (pwrite),
      .paddr         (paddr),
      .pprot0        (pprot0),
      .pslverr       (pslverr),
      .require_priv_q(priv_cfg_require_priv_q),
      .lock_q        (lock_locked_q),
      .busy          (busy_p),
      .target_p      (target_p),
      .priv_p        (priv_p)
  );

endmodule
