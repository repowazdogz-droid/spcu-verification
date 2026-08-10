`ifndef VERILATOR
module testbench;
  reg [4095:0] vcdfile;
  reg clock;
`else
module testbench(input clock, output reg genclock);
  initial genclock = 1;
`endif
  reg genclock = 1;
  reg [31:0] cycle = 0;
  reg [0:0] PI_psel;
  reg [0:0] PI_penable;
  reg [0:0] PI_clk_b;
  reg [0:0] PI_clk_a;
  reg [0:0] PI_presetn;
  reg [0:0] PI_pwrite;
  reg [31:0] PI_pwdata;
  reg [0:0] PI_vack;
  reg [0:0] PI_pd_on;
  reg [0:0] PI_srst_n;
  reg [7:0] PI_paddr;
  reg [0:0] PI_pprot0;
  spcu_fv_top UUT (
    .psel(PI_psel),
    .penable(PI_penable),
    .clk_b(PI_clk_b),
    .clk_a(PI_clk_a),
    .presetn(PI_presetn),
    .pwrite(PI_pwrite),
    .pwdata(PI_pwdata),
    .vack(PI_vack),
    .pd_on(PI_pd_on),
    .srst_n(PI_srst_n),
    .paddr(PI_paddr),
    .pprot0(PI_pprot0)
  );
`ifndef VERILATOR
  initial begin
    if ($value$plusargs("vcd=%s", vcdfile)) begin
      $dumpfile(vcdfile);
      $dumpvars(0, testbench);
    end
    #5 clock = 0;
    while (genclock) begin
      #5 clock = 0;
      #5 clock = 1;
    end
  end
`endif
  initial begin
`ifndef VERILATOR
    #1;
`endif
    // UUT.$auto$async2sync.\cc:107:execute$832  = 1'b0;
    // UUT.$auto$async2sync.\cc:107:execute$838  = 1'b0;
    // UUT.$auto$async2sync.\cc:107:execute$922  = 1'b0;
    // UUT.$auto$async2sync.\cc:116:execute$824  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$830  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$836  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$842  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$848  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$854  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$860  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$866  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$872  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$878  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$884  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$890  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$896  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$902  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$920  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$926  = 1'b1;
    // UUT.$auto$async2sync.\cc:116:execute$932  = 1'b1;
    UUT._witness_.anyinit_driver_u_dut_ack_tog_p_d = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_busy_p = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_priv_p = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_req_tog_p = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_req_tog_s_d = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_target_p = 2'b00;
    UUT._witness_.anyinit_driver_u_dut_u_fsm_ack_tog = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_fsm_cur_pstate = 2'b00;
    UUT._witness_.anyinit_driver_u_dut_u_fsm_freq_level = 2'b00;
    UUT._witness_.anyinit_driver_u_dut_u_fsm_priv_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_fsm_st = 3'b000;
    UUT._witness_.anyinit_driver_u_dut_u_fsm_tgt_q = 2'b00;
    UUT._witness_.anyinit_driver_u_dut_u_fsm_volt_level = 2'b00;
    UUT._witness_.anyinit_driver_u_dut_u_fsm_vreq = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_props_ack_tog_d = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_props_inflight = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_props_latency = 8'b00000000;
    UUT._witness_.anyinit_driver_u_dut_u_regs_ctrl_go_wpulse_priv_r = 1'b1;
    UUT._witness_.anyinit_driver_u_dut_u_regs_ctrl_go_wpulse_r = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_regs_ctrl_target_q_r = 2'b01;
    UUT._witness_.anyinit_driver_u_dut_u_regs_lock_locked_q_r = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_regs_priv_cfg_require_priv_q_r = 1'b1;
    UUT._witness_.anyinit_driver_u_dut_u_sync_ack_meta_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_ack_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_lock_meta_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_lock_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_pd_meta_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_pd_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_prst_meta_q = 1'b1;
    UUT._witness_.anyinit_driver_u_dut_u_sync_prst_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_req_meta_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_req_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_rp_meta_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_rp_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_srst_meta_q = 1'b1;
    UUT._witness_.anyinit_driver_u_dut_u_sync_srst_q = 1'b1;
    UUT._witness_.anyinit_driver_u_dut_u_sync_vack_meta_q = 1'b0;
    UUT._witness_.anyinit_driver_u_dut_u_sync_vack_q = 1'b0;
    UUT._witness_.anyinit_driver_u_env_vreq_age = 4'b0001;
    UUT._witness_.anyinit_past_344 = 2'b00;
    UUT._witness_.anyinit_past_373 = 2'b01;
    UUT._witness_.anyinit_past_378 = 2'b10;
    UUT._witness_.anyinit_past_383 = 2'b10;
    UUT._witness_.anyinit_past_393 = 2'b00;
    UUT._witness_.anyinit_past_399 = 1'b0;
    UUT._witness_.anyinit_past_401 = 1'b0;
    UUT._witness_.anyinit_past_445 = 1'b0;
    UUT._witness_.anyinit_past_450 = 1'b0;
    UUT._witness_.anyinit_past_455 = 1'b1;
    UUT._witness_.anyinit_past_460 = 1'b0;
    UUT._witness_.anyinit_past_527 = 1'b0;
    UUT._witness_.anyinit_past_531 = 1'b0;
    UUT._witness_.anyinit_past_534 = 1'b0;
    UUT.rst_cnt = 3'b000;

    // state 0
    PI_psel = 1'b1;
    PI_penable = 1'b1;
    PI_clk_b = 1'b0;
    PI_clk_a = 1'b0;
    PI_presetn = 1'b0;
    PI_pwrite = 1'b1;
    PI_pwdata = 32'b00000000000000000000000000000000;
    PI_vack = 1'b0;
    PI_pd_on = 1'b0;
    PI_srst_n = 1'b0;
    PI_paddr = 8'b00001100;
    PI_pprot0 = 1'b0;
  end
  always @(posedge clock) begin
    // state 1
    if (cycle == 0) begin
      PI_psel <= 1'b0;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b0;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000000;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b0;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    // state 2
    if (cycle == 1) begin
      PI_psel <= 1'b0;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b0;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000000;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b0;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    // state 3
    if (cycle == 2) begin
      PI_psel <= 1'b1;
      PI_penable <= 1'b1;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b0;
      PI_pwrite <= 1'b1;
      PI_pwdata <= 32'b00000000000000000000000000000000;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b0;
      PI_paddr <= 8'b00001100;
      PI_pprot0 <= 1'b0;
    end

    // state 4
    if (cycle == 3) begin
      PI_psel <= 1'b1;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b1;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000010;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    // state 5
    if (cycle == 4) begin
      PI_psel <= 1'b1;
      PI_penable <= 1'b1;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b1;
      PI_pwrite <= 1'b1;
      PI_pwdata <= 32'b00000000000000000000000100000001;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00000100;
      PI_pprot0 <= 1'b1;
    end

    // state 6
    if (cycle == 5) begin
      PI_psel <= 1'b0;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b1;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000000;
      PI_vack <= 1'b1;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    // state 7
    if (cycle == 6) begin
      PI_psel <= 1'b1;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b1;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000011;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    // state 8
    if (cycle == 7) begin
      PI_psel <= 1'b1;
      PI_penable <= 1'b1;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b1;
      PI_pwrite <= 1'b1;
      PI_pwdata <= 32'b00000000000000000000000000000000;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b1;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00010000;
      PI_pprot0 <= 1'b1;
    end

    // state 9
    if (cycle == 8) begin
      PI_psel <= 1'b1;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b1;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000001;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b1;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    // state 10
    if (cycle == 9) begin
      PI_psel <= 1'b1;
      PI_penable <= 1'b1;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b1;
      PI_pwrite <= 1'b1;
      PI_pwdata <= 32'b00000000000000000000000000000011;
      PI_vack <= 1'b1;
      PI_pd_on <= 1'b1;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00001100;
      PI_pprot0 <= 1'b1;
    end

    // state 11
    if (cycle == 10) begin
      PI_psel <= 1'b0;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b1;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000000;
      PI_vack <= 1'b1;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    // state 12
    if (cycle == 11) begin
      PI_psel <= 1'b1;
      PI_penable <= 1'b1;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b0;
      PI_pwrite <= 1'b1;
      PI_pwdata <= 32'b00000000000000000000000000000010;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00001100;
      PI_pprot0 <= 1'b0;
    end

    // state 13
    if (cycle == 12) begin
      PI_psel <= 1'b0;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b0;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000001;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b1;
      PI_srst_n <= 1'b1;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    // state 14
    if (cycle == 13) begin
      PI_psel <= 1'b0;
      PI_penable <= 1'b0;
      PI_clk_b <= 1'b0;
      PI_clk_a <= 1'b0;
      PI_presetn <= 1'b0;
      PI_pwrite <= 1'b0;
      PI_pwdata <= 32'b00000000000000000000000000000000;
      PI_vack <= 1'b0;
      PI_pd_on <= 1'b0;
      PI_srst_n <= 1'b0;
      PI_paddr <= 8'b00000000;
      PI_pprot0 <= 1'b0;
    end

    genclock <= cycle < 14;
    cycle <= cycle + 1;
  end
endmodule
