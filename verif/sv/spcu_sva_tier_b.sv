// TIER-B PROPERTIES. Concurrent SVA. SIMULATION ONLY.
//
// Every property here uses syntax Yosys cannot parse, verified on this machine:
//   read_verilog -sv : "syntax error, unexpected '@'"
//   read_slang       : "encountered unsupported SVA feature"
//
// So these are evidence from SIMULATION, over the stimulus that was actually
// run. They are not proofs and carry none of the coverage of the Tier-A set.
// Their value is that they express things Tier-A cannot: multi-cycle sequences,
// bounded-window responses, and the ordering of a transition as a SEQUENCE
// rather than as a standing invariant.
//
// The honest split:
//   Tier A says "freq_level <= volt_level, always, proven".
//   Tier B says "on a rising transition, the voltage step is observed BEFORE
//     the frequency step, within this window, on the traces we ran".
// The first is stronger. The second is more specific. Neither subsumes the
// other, and only the first is a proof.

module spcu_sva_tier_b (
    input logic       sclk,
    input logic       srst_n,
    input logic       vreq,
    input logic       vack,
    input logic [1:0] volt_level,
    input logic [1:0] freq_level,
    input logic       req_pulse,
    input logic       done,
    input logic       error
);

  // A request that is accepted resolves within the bounded window. This is the
  // property P7 wants to be. In formal it degrades to a counter and a bound;
  // here it is the sequence itself.
  property p_bounded_resolve;
    @(posedge sclk) disable iff (!srst_n)
      req_pulse |-> ##[1:24] (done || error);
  endproperty
  a_bounded_resolve: assert property (p_bounded_resolve);

  // The regulator handshake completes rather than hanging. Expressed as an
  // ASSUMPTION about the environment in formal; here it is checked against the
  // PMIC model actually driven, so a broken testbench is caught rather than
  // silently satisfying itself.
  property p_vreq_gets_vack;
    @(posedge sclk) disable iff (!srst_n)
      $rose(vreq) |-> ##[1:6] vack;
  endproperty
  a_vreq_gets_vack: assert property (p_vreq_gets_vack);

  // Rising transition ORDER, as a sequence. Tier A proves the invariant
  // freq <= volt; this says the voltage actually moved first on this trace.
  property p_volt_leads_freq;
    @(posedge sclk) disable iff (!srst_n)
      $rose(freq_level[0] | freq_level[1]) |-> $past(volt_level) >= freq_level;
  endproperty
  a_volt_leads_freq: assert property (p_volt_leads_freq);

  // vreq must not remain asserted indefinitely after its acknowledge.
  //
  // THE WINDOW IS NOT COSMETIC. Written first as `(vreq && vack) |=> !vreq`,
  // this failed in simulation at 343 us -- correctly. `vack` here is the RAW
  // pad-level acknowledge, while the controller can only act on `vack_s`, two
  // synchroniser stages later. Demanding a next-cycle response asks the design
  // to react to a signal it has not yet received.
  //
  // This is the third time the same mistake appeared (see P6 and P3 in
  // verif/props/spcu_props.sv). Stating a property over the observable
  // interface means stating it over what that interface can actually promise,
  // and across a CDC boundary that always includes the synchroniser latency.
  // The window is 2 stages + decision cycle + margin.
  property p_vreq_deasserts;
    @(posedge sclk) disable iff (!srst_n)
      (vreq && vack) |-> ##[1:5] !vreq;
  endproperty
  a_vreq_deasserts: assert property (p_vreq_deasserts);

  // Cover: a full up-then-down excursion actually happened in this run.
  //
  // TOOL LIMIT, measured on this machine (Verilator 5.051). Two CHAINED wide
  // range-delays blow up the sequence NFA: ##[1:40] twice compiles in under a
  // second, ##[1:60] twice had not finished after 10 minutes, and ##[1:200]
  // twice aborts the front end with "Verilator internal fault". The bound here
  // is inside the working range.
  //
  // The bound is therefore a TOOL constraint, not a design one. A miss on this
  // cover point means "not observed within 40 sclk cycles per leg", which is
  // not the same as "did not happen". docs/COVERAGE.md records that.
  c_up_then_down: cover property (
      @(posedge sclk) disable iff (!srst_n)
      (freq_level == 2'd0) ##[1:40] (freq_level == 2'd2) ##[1:40] (freq_level == 2'd0));

endmodule
