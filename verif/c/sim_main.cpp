// Verilator harness that lets bare-metal C run against the RTL.
//
// HOW THE TWO WORLDS MEET
//   The C driver calls spcu_rd/spcu_wr. Under -DSPCU_SIM those are external
//   symbols, and this file implements them by driving a full APB3 transaction
//   into the Verilated model, advancing both clocks until the transfer
//   completes, and returning the sampled read data.
//
//   The C driver is therefore BLOCKING on simulation time. That is exactly how
//   firmware behaves against a real peripheral: it issues a load and does not
//   proceed until the bus returns. Nothing in the driver is aware of this.
//
// CLOCKS
//   pclk and sclk are stepped independently with different half-periods so the
//   crossing is genuinely asynchronous, matching the SystemVerilog testbench.

#include <cstdio>
#include <cstdint>

#include "Vspcu_top.h"
#include "verilated.h"

#include "spcu_regs.h"
#include "spcu_driver.h"

static Vspcu_top *dut = nullptr;
static vluint64_t main_time = 0;

// Half-periods in arbitrary time units. 5 vs 7 gives a non-integer ratio.
static const int PCLK_HALF = 5;
static const int SCLK_HALF = 7;
static vluint64_t next_p = PCLK_HALF;
static vluint64_t next_s = SCLK_HALF;

// Advance simulation until the next pclk RISING edge, toggling both clocks
// independently on the way.
static void advance_to_pclk_edge() {
    while (true) {
        vluint64_t t = (next_p < next_s) ? next_p : next_s;
        main_time = t;
        bool rose_p = false;
        if (next_p == t) {
            dut->pclk = !dut->pclk;
            rose_p = dut->pclk;
            next_p += PCLK_HALF;
        }
        if (next_s == t) {
            dut->sclk = !dut->sclk;
            next_s += SCLK_HALF;
        }
        dut->eval();
        // Voltage regulator model: acknowledge a request, drop it when the
        // request is withdrawn. Kept trivial on purpose; the interesting
        // regulator behaviour is exercised by the formal environment, which
        // leaves vack free.
        if (dut->vreq) dut->vack = 1;
        else           dut->vack = 0;
        dut->eval();
        if (rose_p) return;
    }
}

static void apb_phase(int sel, int enable, int write, uint32_t addr,
                      uint32_t wdata, int priv) {
    dut->psel = sel;
    dut->penable = enable;
    dut->pwrite = write;
    dut->paddr = addr;
    dut->pwdata = wdata;
    dut->pprot0 = priv;
    advance_to_pclk_edge();
}

// Privilege of the simulated software agent. Firmware cannot change this; the
// harness sets it, standing in for the execution mode the core would present
// on pprot[0].
static int agent_priv = 1;

void spcu_set_priv(int p) { agent_priv = p; }

void spcu_wr(uintptr_t /*base*/, uint32_t off, uint32_t v) {
    apb_phase(1, 0, 1, off, v, agent_priv);   // SETUP
    apb_phase(1, 1, 1, off, v, agent_priv);   // ACCESS
    apb_phase(0, 0, 0, 0, 0, agent_priv);     // IDLE
}

uint32_t spcu_rd(uintptr_t /*base*/, uint32_t off) {
    apb_phase(1, 0, 0, off, 0, agent_priv);   // SETUP
    apb_phase(1, 1, 0, off, 0, agent_priv);   // ACCESS
    uint32_t d = dut->prdata;
    apb_phase(0, 0, 0, 0, 0, agent_priv);     // IDLE
    return d;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vspcu_top;

    dut->pclk = 0;
    dut->sclk = 0;
    dut->presetn = 0;
    dut->srst_n = 0;
    dut->psel = 0;
    dut->penable = 0;
    dut->pwrite = 0;
    dut->paddr = 0;
    dut->pwdata = 0;
    dut->pprot0 = 1;
    dut->pd_on = 1;
    dut->vack = 0;

    for (int i = 0; i < 10; i++) advance_to_pclk_edge();
    dut->presetn = 1;
    dut->srst_n = 1;
    for (int i = 0; i < 10; i++) advance_to_pclk_edge();

    printf("=== SPCU C/MMIO tests against RTL ===\n");
    int fails = spcu_run_tests();

    // The privilege dimension is exercised HERE, not in the driver: firmware
    // cannot lower its own pprot[0], so only the harness can present an
    // unprivileged agent.
    printf("[c] unprivileged agent cannot clear REQUIRE_PRIV\n");
    spcu_set_priv(0);
    spcu_wr(0, 0x10u, 0u);
    spcu_set_priv(1);
    uint32_t pc = spcu_rd(0, 0x10u);
    if ((pc & 1u) != 1u) {
        printf("  FAIL: unprivileged write cleared REQUIRE_PRIV\n");
        fails++;
    }

    dut->final();
    delete dut;

    printf(fails == 0 ? "C TESTS PASSED\n" : "C TESTS FAILED\n");
    return fails == 0 ? 0 : 1;
}
