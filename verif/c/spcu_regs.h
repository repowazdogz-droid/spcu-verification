/* GENERATED FILE - DO NOT EDIT.
Source : spec/spcu_regs.yaml (sha256 74a2a23e23212dc9)
Tool   : tools/genregs.py
Edit the YAML and re-run the tool. Hand edits are lost and are a defect. */

#ifndef SPCU_REGS_H
#define SPCU_REGS_H

#include <stdint.h>

/* Linkage guard. This header is consumed by C firmware and by the
 * C++ Verilator harness, and the harness DEFINES the accessors the
 * firmware calls. Without extern "C" the two disagree about name
 * mangling and the link fails with an undefined symbol whose
 * signature looks correct. */
#ifdef __cplusplus
extern "C" {
#endif

/* ID: Identification register, constant. */
#define SPCU_ID_OFFSET 0x00u
#define SPCU_ID_IDCODE_SHIFT 0u
#define SPCU_ID_IDCODE_MASK  0xFFFFFFFFu

/* CTRL: Request control. Writing GO submits one DVFS request. Deliberately NOT bus-privileged: any agent may submit a request. Authority is enforced in series at the decision point in spcu_ctrl_fsm, which compares the pprot[0] captured at the GO write against PRIV_CFG.REQUIRE_PRIV and rejects the request. Enforcing at the bus instead would make the register writable-or-not; enforcing at the decision point makes the state change itself the thing that is gated. */
#define SPCU_CTRL_OFFSET 0x04u
#define SPCU_CTRL_TARGET_SHIFT 0u
#define SPCU_CTRL_TARGET_MASK  0x00000003u
#define SPCU_CTRL_GO_SHIFT 8u
#define SPCU_CTRL_GO_MASK  0x00000100u

/* STATUS: Controller status. Hardware-driven, read-only from the bus. */
#define SPCU_STATUS_OFFSET 0x08u
#define SPCU_STATUS_CUR_PSTATE_SHIFT 0u
#define SPCU_STATUS_CUR_PSTATE_MASK  0x00000003u
#define SPCU_STATUS_BUSY_SHIFT 4u
#define SPCU_STATUS_BUSY_MASK  0x00000010u
#define SPCU_STATUS_DONE_SHIFT 5u
#define SPCU_STATUS_DONE_MASK  0x00000020u
#define SPCU_STATUS_ERROR_SHIFT 6u
#define SPCU_STATUS_ERROR_MASK  0x00000040u
#define SPCU_STATUS_PD_ON_SHIFT 8u
#define SPCU_STATUS_PD_ON_MASK  0x00000100u
#define SPCU_STATUS_VOLT_SHIFT 10u
#define SPCU_STATUS_VOLT_MASK  0x00000C00u
#define SPCU_STATUS_FREQ_SHIFT 12u
#define SPCU_STATUS_FREQ_MASK  0x00003000u

/* LOCK: When set, all DVFS requests are refused regardless of privilege. */
#define SPCU_LOCK_OFFSET 0x0Cu
#define SPCU_LOCK_LOCKED_SHIFT 0u
#define SPCU_LOCK_LOCKED_MASK  0x00000001u

/* PRIV_CFG: Authority configuration. REQUIRE_PRIV selects whether DVFS requests must be privileged. This register gates the authority of every other protected register, so it must itself be privileged-write. */
#define SPCU_PRIV_CFG_OFFSET 0x10u
#define SPCU_PRIV_CFG_REQUIRE_PRIV_SHIFT 0u
#define SPCU_PRIV_CFG_REQUIRE_PRIV_MASK  0x00000001u

/* MMIO accessors.
 *
 * On real hardware these are volatile loads and stores to the
 * peripheral aperture. Under simulation (-DSPCU_SIM) they become
 * external calls that the Verilator harness implements by driving APB
 * transactions into the model.
 *
 * The DRIVER SOURCE IS IDENTICAL in both cases. That is the point: the
 * firmware under test is the firmware, not a simulation-only rewrite of
 * it. Only the bus accessor is substituted.
 */
#ifdef SPCU_SIM
uint32_t spcu_rd(uintptr_t base, uint32_t off);
void     spcu_wr(uintptr_t base, uint32_t off, uint32_t v);
#else
static inline uint32_t spcu_rd(uintptr_t base, uint32_t off) {
    return *(volatile uint32_t *)(base + off);
}

static inline void spcu_wr(uintptr_t base, uint32_t off, uint32_t v) {
    *(volatile uint32_t *)(base + off) = v;
}
#endif

#ifdef __cplusplus
}
#endif

#endif /* SPCU_REGS_H */
