// SPCU shared types.
//
// P-state encoding is deliberately monotonic: P0 is the lowest voltage and
// frequency operating point, P3 the highest. The required voltage level and
// frequency level for P-state N are both N. This makes the DVFS ordering
// requirement expressible as a plain arithmetic relation between two 2-bit
// levels, which is exactly what keeps the Tier-A properties inside the subset
// that both Verilator and Yosys accept.

package spcu_pkg;

  typedef enum logic [1:0] {
    P0 = 2'd0,
    P1 = 2'd1,
    P2 = 2'd2,
    P3 = 2'd3
  } pstate_e;

  typedef enum logic [2:0] {
    S_IDLE    = 3'd0,
    S_CHECK   = 3'd1,
    S_VOLT_UP = 3'd2,
    S_FREQ_UP = 3'd3,
    S_FREQ_DN = 3'd4,
    S_VOLT_DN = 3'd5,
    S_FINISH  = 3'd6,   // set done/error; payload settles here
    S_ACK     = 3'd7    // toggle ack one cycle LATER, so the payload is
                        // already stable when the toggle crosses to pclk
  } fsm_e;

  // Voltage and frequency level required to sustain a given P-state.
  function automatic logic [1:0] req_volt(input logic [1:0] p);
    return p;
  endfunction

  function automatic logic [1:0] req_freq(input logic [1:0] p);
    return p;
  endfunction

endpackage
