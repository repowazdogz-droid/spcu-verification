/* Bare-metal SPCU driver and its self-checking tests.
 *
 * This is ordinary embedded C. It uses only the generated header, talks to the
 * device exclusively through memory-mapped reads and writes, polls a status
 * register, and never assumes anything about timing beyond a bounded retry
 * count. Nothing in this file knows it is running against a simulator.
 *
 * Compiled twice by the regression:
 *   -DSPCU_SIM  linked against the Verilator harness, driving real APB
 *               transactions into the RTL.
 *   (native)    compiled without SPCU_SIM purely to prove the same source
 *               still builds against volatile MMIO for a real target.
 */

#include <stdint.h>
#include <stdio.h>

#include "spcu_regs.h"
#include "spcu_driver.h"

#define SPCU_BASE 0x40000000u
#define POLL_LIMIT 500

int spcu_failures;
static int spcu_checks;

static void check(int cond, const char *what) {
    spcu_checks++;
    if (!cond) {
        printf("  FAIL: %s\n", what);
        spcu_failures++;
    }
}

/* ------------------------------------------------------------------ driver */

static uint32_t status(void) {
    return spcu_rd(SPCU_BASE, SPCU_STATUS_OFFSET);
}

static uint32_t field(uint32_t word, uint32_t mask, uint32_t shift) {
    return (word & mask) >> shift;
}

int spcu_busy(void) {
    return (int)field(status(), SPCU_STATUS_BUSY_MASK, SPCU_STATUS_BUSY_SHIFT);
}

int spcu_current_pstate(void) {
    return (int)field(status(), SPCU_STATUS_CUR_PSTATE_MASK,
                      SPCU_STATUS_CUR_PSTATE_SHIFT);
}

/* Submit one request and poll to completion.
 * Returns 0 on success, 1 if the device reported ERROR, -1 on timeout. */
int spcu_request(int target) {
    uint32_t word = ((uint32_t)target << SPCU_CTRL_TARGET_SHIFT)
                  | (1u << SPCU_CTRL_GO_SHIFT);
    spcu_wr(SPCU_BASE, SPCU_CTRL_OFFSET, word);

    for (int i = 0; i < POLL_LIMIT; i++) {
        uint32_t s = status();
        if (!field(s, SPCU_STATUS_BUSY_MASK, SPCU_STATUS_BUSY_SHIFT)) {
            if (field(s, SPCU_STATUS_ERROR_MASK, SPCU_STATUS_ERROR_SHIFT))
                return 1;
            return 0;
        }
    }
    return -1;
}

/* ------------------------------------------------------------------- tests */

static void t_identity(void) {
    printf("[c] identity\n");
    check(spcu_rd(SPCU_BASE, SPCU_ID_OFFSET) == 0x53504355u, "ID reads SPCU");
    check(spcu_current_pstate() == 0, "reset P-state is P0");
}

static void t_legal_walk(void) {
    printf("[c] legal single-step walk P0->P3->P0\n");
    const int up[3] = {1, 2, 3};
    for (int i = 0; i < 3; i++) {
        check(spcu_request(up[i]) == 0, "single-step raise accepted");
        check(spcu_current_pstate() == up[i], "P-state advanced");
    }
    const int dn[3] = {2, 1, 0};
    for (int i = 0; i < 3; i++) {
        check(spcu_request(dn[i]) == 0, "single-step lower accepted");
        check(spcu_current_pstate() == dn[i], "P-state lowered");
    }
}

static void t_illegal_jump(void) {
    printf("[c] illegal two-step jump P0->P2\n");
    check(spcu_request(2) == 1, "two-step jump reported ERROR");
    check(spcu_current_pstate() == 0, "P-state unchanged after refusal");
}

static void t_settled_point_consistent(void) {
    printf("[c] settled operating point is self-consistent\n");
    check(spcu_request(1) == 0, "raise to P1");
    uint32_t s = status();
    uint32_t v = field(s, SPCU_STATUS_VOLT_MASK, SPCU_STATUS_VOLT_SHIFT);
    uint32_t f = field(s, SPCU_STATUS_FREQ_MASK, SPCU_STATUS_FREQ_SHIFT);
    uint32_t p = field(s, SPCU_STATUS_CUR_PSTATE_MASK,
                       SPCU_STATUS_CUR_PSTATE_SHIFT);
    check(v == p, "settled voltage matches P-state");
    check(f == p, "settled frequency matches P-state");
    check(spcu_request(0) == 0, "return to P0");
}

/* Firmware cannot raise its own privilege, so this test can only confirm the
 * device reports the refusal. Whether an unprivileged AGENT is refused is
 * checked from the testbench, which controls pprot[0]. Recorded in
 * docs/TRACEABILITY.md so the C layer is not credited with proving it. */
static void t_lock_refuses(void) {
    printf("[c] lock refuses requests\n");
    spcu_wr(SPCU_BASE, SPCU_LOCK_OFFSET, 1u);
    check(spcu_request(1) == 1, "request refused while locked");
    check(spcu_current_pstate() == 0, "P-state unchanged while locked");
    spcu_wr(SPCU_BASE, SPCU_LOCK_OFFSET, 0u);
    check(spcu_request(1) == 0, "request accepted after unlock");
    check(spcu_request(0) == 0, "return to P0");
}

int spcu_run_tests(void) {
    spcu_failures = 0;
    spcu_checks = 0;

    t_identity();
    t_legal_walk();
    t_illegal_jump();
    t_settled_point_consistent();
    t_lock_refuses();

    printf("[c] checks=%d failures=%d\n", spcu_checks, spcu_failures);
    return spcu_failures;
}
