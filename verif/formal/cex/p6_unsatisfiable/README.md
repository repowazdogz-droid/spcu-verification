# Counterexample: P6 as originally specified is unsatisfiable

Property (original transcription, spcu_props.sv):

    p6_pd_off_volt: assert (pd_on || (volt_level == $past(volt_level)));

Refuted by `sby prove` basecase in 4 steps. Signal trace at the failure:

| time | pd_on_s | volt_level | st        | vreq | vack_s |
|------|---------|-----------|-----------|------|--------|
| 125  | 1       | 00        | S_VOLT_UP | 1    | 1      |
| 130  | 1       | 00        | S_VOLT_UP | 1    | 1      |
| 135  | 0       | 01        | S_FREQ_UP | 0    | 1      |

At t=130 the controller is legitimately mid-handshake with `pd_on` HIGH and
`vreq && vack` true, so it commits `volt_level <= 1`. That commit becomes
visible at t=135, by which time `pd_on` has fallen.

THIS IS NOT A DESIGN BUG. The property demands that a synchronous design react
to an input in the same cycle that input changes. No implementation satisfies
it. The requirement was restated over `$past(pd_on)`, which is the value the
design was entitled to act upon.

Kept as evidence that a requirement can be transcribed faithfully into an
assertion and still be wrong, and that formal refutation is how that gets
discovered rather than argued about.
