# Counterexample: R18b refuted under independent resets

Properties (`verif/props/spcu_props.sv`):

    p18b_target_settled: assert (!req_pulse || ((req_target == tgt_d1) && (req_target == tgt_d2)));
    p18b_priv_settled:   assert (!req_pulse || ((req_priv   == prv_d1) && (req_priv   == prv_d2)));

Refuted in **both** clocking models, so this is a reset problem, not a clocking
problem. Signal trace at the failure:

| time | presetn | srst_n | rst_n_p | rst_n_s | busy_p | target_p | priv_p | req_pulse_s |
|------|---------|--------|---------|---------|--------|----------|--------|-------------|
| 160  | 1       | 1      | 1       | 1       | 1      | **10**   | **1**  | 0           |
| 165  | **0**   | 1      | 0       | **1**   | 0      | **00**   | **0**  | **1**       |

At t=165 `presetn` falls. `rst_n_p` clears the launch-side payload immediately
(P2 → P0, privileged → unprivileged) while `rst_n_s` is still high, because the
reset has not yet crossed into the controller domain. In that same instant
`req_pulse_s` fires and the controller consumes a request whose payload the
source domain has already wiped.

## Why there is no local RTL fix

At the failing instant the synchronised pclk reset (`presetn_s`) is **still
high** — the information has not arrived — so no signal observable in the `sclk`
domain distinguishes this from a legitimate request. The B1 reset-domain-crossing
fix stopped the double *commit*; it does not stop a single commit being taken
against a cleared payload. Closing this inside the IP requires a full reset
handshake between the two domains.

## Resolution

R22, an integration constraint: the controller domain must be held in reset
whenever the register domain is. Under it, R18a and R18b are proven unbounded by
PDR. Without it they are refuted, and that is reproducible in one command:

    make formal-rdc

That task keeps every other property live, so it also guards the B1 fix against
regression — the constraint is not allowed to mask the defect it was derived
from.

The reset direction here happens to be benign (the payload clears toward P0 and
unprivileged, which are the safe values), but the obligation is violated
regardless, and an IP that silently depends on an unstated integration
requirement is a liability rather than a verified component.
