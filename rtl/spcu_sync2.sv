// Two-flop synchroniser.
//
// The only sanctioned way a signal crosses a clock boundary in this IP. Every
// crossing in spcu_top instantiates this module; the CDC lint script in
// tools/cdc_lint.py flags any crossing that does not.
//
// This synchronises a LEVEL. It is correct only for signals that are stable
// for at least two destination clock edges, which is why the request and
// acknowledge paths use toggles rather than pulses: a toggle holds until the
// next event, a pulse does not survive resampling.

module spcu_sync2 #(
    parameter int WIDTH = 1,
    parameter logic [WIDTH-1:0] RESET_VALUE = '0
) (
    input  logic             dclk,
    input  logic             drst_n,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

  logic [WIDTH-1:0] meta_q;

  always_ff @(posedge dclk or negedge drst_n) begin
    if (!drst_n) begin
      meta_q <= RESET_VALUE;
      q      <= RESET_VALUE;
    end else begin
      meta_q <= d;
      q      <= meta_q;
    end
  end

endmodule
