// GENERATED FILE - DO NOT EDIT.
// Source : spec/spcu_regs.yaml (sha256 74a2a23e23212dc9)
// Tool   : tools/genregs.py
// Edit the YAML and re-run the tool. Hand edits are lost and are a defect.

module spcu_regs (
  input  logic pclk,
  input  logic presetn,
  // ---- APB3 ----
  input  logic psel,
  input  logic penable,
  input  logic pwrite,
  input  logic [7:0] paddr,
  input  logic [31:0] pwdata,
  input  logic pprot0,             // AMBA pprot[0]: 1 = privileged
  output logic [31:0] prdata,
  output logic pready,
  output logic pslverr,
  // ---- register interface ----
  output logic [1:0] ctrl_target_q,
  output logic ctrl_go_wpulse,
  output logic ctrl_go_wpulse_priv,
  input  logic [1:0] status_cur_pstate_i,
  input  logic status_busy_i,
  input  logic status_done_i,
  input  logic status_error_i,
  input  logic status_pd_on_i,
  input  logic [1:0] status_volt_i,
  input  logic [1:0] status_freq_i,
  output logic lock_locked_q,
  output logic priv_cfg_require_priv_q
);

  wire addr_sel_id = (paddr == 8'h00);
  wire addr_sel_ctrl = (paddr == 8'h04);
  wire addr_sel_status = (paddr == 8'h08);
  wire addr_sel_lock = (paddr == 8'h0C);
  wire addr_sel_priv_cfg = (paddr == 8'h10);
  wire priv_req_id = 1'b0;
  wire priv_req_ctrl = 1'b0;
  wire priv_req_status = 1'b0;
  wire priv_req_lock = 1'b1;
  wire priv_req_priv_cfg = 1'b1;

  // An APB3 write commits in the ACCESS phase (psel & penable & pwrite).
  wire wr_phase = psel && penable && pwrite;
  wire priv_viol = wr_phase && ((addr_sel_id && priv_req_id) || (addr_sel_ctrl && priv_req_ctrl) || (addr_sel_status && priv_req_status) || (addr_sel_lock && priv_req_lock) || (addr_sel_priv_cfg && priv_req_priv_cfg)) && !pprot0;
  wire wr_ok = wr_phase && !priv_viol;

  logic [1:0] ctrl_target_q_r;
  logic ctrl_go_wpulse_r, ctrl_go_wpulse_priv_r;
  logic lock_locked_q_r;
  logic priv_cfg_require_priv_q_r;
  logic [31:0] rd;

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_target_q_r <= 2'd0;
      ctrl_go_wpulse_r <= 1'b0;
      ctrl_go_wpulse_priv_r <= 1'b0;
      lock_locked_q_r <= 1'd0;
      priv_cfg_require_priv_q_r <= 1'd1;
    end else begin
      ctrl_go_wpulse_r <= wr_ok && addr_sel_ctrl && pwdata[8:8] == 1'b1;
      if (wr_ok && addr_sel_ctrl && pwdata[8:8] == 1'b1) ctrl_go_wpulse_priv_r <= pprot0;
      if (wr_ok) begin
          if (addr_sel_ctrl) ctrl_target_q_r <= pwdata[1:0];
          if (addr_sel_lock) lock_locked_q_r <= pwdata[0:0];
          if (addr_sel_priv_cfg) priv_cfg_require_priv_q_r <= pwdata[0:0];
      end
    end
  end

  always_comb begin
    rd = 32'd0;
    case (paddr)
    8'h00: begin
      rd[31:0] = 32'd1397769045;
    end
    8'h04: begin
      rd[1:0] = ctrl_target_q_r;
      rd[8:8] = 1'd0;
    end
    8'h08: begin
      rd[1:0] = status_cur_pstate_i;
      rd[4:4] = status_busy_i;
      rd[5:5] = status_done_i;
      rd[6:6] = status_error_i;
      rd[8:8] = status_pd_on_i;
      rd[11:10] = status_volt_i;
      rd[13:12] = status_freq_i;
    end
    8'h0C: begin
      rd[0:0] = lock_locked_q_r;
    end
    8'h10: begin
      rd[0:0] = priv_cfg_require_priv_q_r;
    end
      default: rd = 32'd0;
    endcase
  end

  assign prdata  = (psel && !pwrite) ? rd : 32'd0;
  assign pready  = 1'b1;
  assign pslverr = priv_viol;

  assign ctrl_target_q = ctrl_target_q_r;
  assign ctrl_go_wpulse = ctrl_go_wpulse_r;
  assign ctrl_go_wpulse_priv = ctrl_go_wpulse_priv_r;
  assign lock_locked_q = lock_locked_q_r;
  assign priv_cfg_require_priv_q = priv_cfg_require_priv_q_r;

endmodule
