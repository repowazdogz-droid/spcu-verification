# SPCU register map

<!-- GENERATED FILE - DO NOT EDIT.
Source : spec/spcu_regs.yaml (sha256 74a2a23e23212dc9)
Tool   : tools/genregs.py
Edit the YAML and re-run the tool. Hand edits are lost and are a defect. -->

Secure Power Control Unit. 32-bit registers, 8-bit address space.

`priv` means the write requires AMBA `pprot[0] == 1`. An unprivileged write to such a register is refused and raises `pslverr`.

| Offset | Name | Access | Priv write | Reset |
|---|---|---|---|---|
| 0x00 | `ID` | RO | no | 0x53504355 |
| 0x04 | `CTRL` | RW | no | 0x00000000 |
| 0x08 | `STATUS` | RO | no | 0x00000100 |
| 0x0C | `LOCK` | RW | yes | 0x00000000 |
| 0x10 | `PRIV_CFG` | RW | yes | 0x00000001 |

## `ID` (0x00)

Identification register, constant.

| Bits | Field | Access | Description |
|---|---|---|---|
| 31:0 | `IDCODE` | RO | Fixed identification code |

## `CTRL` (0x04)

Request control. Writing GO submits one DVFS request. Deliberately NOT bus-privileged: any agent may submit a request. Authority is enforced in series at the decision point in spcu_ctrl_fsm, which compares the pprot[0] captured at the GO write against PRIV_CFG.REQUIRE_PRIV and rejects the request. Enforcing at the bus instead would make the register writable-or-not; enforcing at the decision point makes the state change itself the thing that is gated.

| Bits | Field | Access | Description |
|---|---|---|---|
| 8 | `GO` | W1P | Write 1 to submit the request. Self-clearing. |
| 1:0 | `TARGET` | RW | Requested P-state P0..P3 |

## `STATUS` (0x08)

Controller status. Hardware-driven, read-only from the bus.

| Bits | Field | Access | Description |
|---|---|---|---|
| 13:12 | `FREQ` | RO | Current frequency level |
| 11:10 | `VOLT` | RO | Current voltage level |
| 8 | `PD_ON` | RO | Controller power domain is on |
| 6 | `ERROR` | RO | Last request was rejected |
| 5 | `DONE` | RO | Last request completed successfully |
| 4 | `BUSY` | RO | A request is in flight |
| 1:0 | `CUR_PSTATE` | RO | Current settled P-state |

## `LOCK` (0x0C)

When set, all DVFS requests are refused regardless of privilege.

| Bits | Field | Access | Description |
|---|---|---|---|
| 0 | `LOCKED` | RW | Configuration lock |

## `PRIV_CFG` (0x10)

Authority configuration. REQUIRE_PRIV selects whether DVFS requests must be privileged. This register gates the authority of every other protected register, so it must itself be privileged-write.

| Bits | Field | Access | Description |
|---|---|---|---|
| 0 | `REQUIRE_PRIV` | RW | Requests require pprot[0]==1 |
