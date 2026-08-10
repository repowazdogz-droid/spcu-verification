"""UVM-architecture testbench for SPCU, written in pyuvm on cocotb.

WHAT THIS IS
    A real UVM architecture: sequence items, a sequencer, a driver, a monitor,
    an analysis port, a scoreboard, an agent, an environment, and phasing --
    built on pyuvm, which implements the most-used parts of IEEE 1800.2 in
    Python.

WHAT THIS IS NOT
    SystemVerilog UVM. There is no uvm_pkg, no SystemVerilog factory, no
    `uvm_component_utils, no vendor UVM debug flow, and no constrained-random
    solver of the kind a commercial simulator provides. No freely available
    simulator runs SystemVerilog UVM: Verilator does not support it, Questa
    Intel Starter Edition gates randomize() behind a licence feature, and
    Vivado XSim ships UVM 1.2 but has no macOS build.

    docs/TRACEABILITY.md classifies the UVM requirement as PARTIALLY COVERED on
    exactly this basis. This file is evidence of understanding the methodology,
    not of commercial SystemVerilog UVM experience.
"""

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from pyuvm import (ConfigDB, uvm_agent, uvm_analysis_port, uvm_component,
                   uvm_driver, uvm_env, uvm_monitor, uvm_sequence,
                   uvm_sequence_item, uvm_sequencer, uvm_test, uvm_root,
                   uvm_tlm_analysis_fifo)

# Register offsets come from the generated model, not from magic numbers here.
import sys
import pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from spcu_reg_model import REGISTERS, place, field   # noqa: E402

A_ID = REGISTERS["ID"]["offset"]
A_CTRL = REGISTERS["CTRL"]["offset"]
A_STATUS = REGISTERS["STATUS"]["offset"]
A_LOCK = REGISTERS["LOCK"]["offset"]
A_PRIV = REGISTERS["PRIV_CFG"]["offset"]


# --------------------------------------------------------------- sequence item
class DvfsItem(uvm_sequence_item):
    def __init__(self, name="DvfsItem", target=0, priv=1):
        super().__init__(name)
        self.target = target
        self.priv = priv
        self.expect_refuse = None      # filled in by the scoreboard's model

    def __str__(self):
        return f"DvfsItem(target=P{self.target}, priv={int(self.priv)})"


# ------------------------------------------------------------------- sequences
class WalkSequence(uvm_sequence):
    """Directed: climb P0->P3 one legal step at a time, then descend."""

    async def body(self):
        for t in [1, 2, 3, 2, 1, 0]:
            item = DvfsItem(target=t, priv=1)
            await self.start_item(item)
            await self.finish_item(item)


class IllegalJumpSequence(uvm_sequence):
    """Directed: request a two-step jump, which must be refused."""

    async def body(self):
        item = DvfsItem(target=2, priv=1)
        await self.start_item(item)
        await self.finish_item(item)


class UnprivilegedSequence(uvm_sequence):
    """Directed: an unprivileged request must be refused."""

    async def body(self):
        item = DvfsItem(target=1, priv=0)
        await self.start_item(item)
        await self.finish_item(item)


class RandomSequence(uvm_sequence):
    """Constrained random. Privilege is weighted towards privileged so that
    legal transitions dominate and the refusal paths still get exercised."""

    def __init__(self, name="RandomSequence", n=30, seed=1):
        super().__init__(name)
        self.n = n
        self.rng = random.Random(seed)

    async def body(self):
        for _ in range(self.n):
            item = DvfsItem(target=self.rng.randint(0, 3),
                            priv=self.rng.choices([1, 0], weights=[8, 2])[0])
            await self.start_item(item)
            await self.finish_item(item)


# ---------------------------------------------------------------------- BFM
class ApbBfm:
    """Pin-level APB3 access. Kept separate from the driver so the driver
    deals only in transactions."""

    def __init__(self, dut):
        self.dut = dut

    async def write(self, addr, data, priv):
        await RisingEdge(self.dut.pclk)
        self.dut.psel.value = 1
        self.dut.pwrite.value = 1
        self.dut.paddr.value = addr
        self.dut.pwdata.value = data
        self.dut.pprot0.value = int(priv)
        self.dut.penable.value = 0
        await RisingEdge(self.dut.pclk)
        self.dut.penable.value = 1
        await RisingEdge(self.dut.pclk)
        self.dut.psel.value = 0
        self.dut.penable.value = 0
        self.dut.pwrite.value = 0

    async def read(self, addr):
        await RisingEdge(self.dut.pclk)
        self.dut.psel.value = 1
        self.dut.pwrite.value = 0
        self.dut.paddr.value = addr
        self.dut.pprot0.value = 1
        self.dut.penable.value = 0
        await RisingEdge(self.dut.pclk)
        self.dut.penable.value = 1
        await RisingEdge(self.dut.pclk)
        val = int(self.dut.prdata.value)
        self.dut.psel.value = 0
        self.dut.penable.value = 0
        return val


# -------------------------------------------------------------------- driver
class SpcuDriver(uvm_driver):
    def build_phase(self):
        # cocotb.top, NOT ConfigDB: uvm_root().run_test() clears singletons
        # (including the ConfigDB) by default, so anything registered before
        # run_test is gone by build_phase. See docs/LIMITATIONS.md.
        self.dut = cocotb.top
        self.bfm = ApbBfm(self.dut)

    async def run_phase(self):
        while True:
            item = await self.seq_item_port.get_next_item()
            word = place("CTRL", "TARGET", item.target) | place("CTRL", "GO", 1)
            await self.bfm.write(A_CTRL, word, item.priv)
            # Wait for the transaction to retire.
            for _ in range(400):
                st = await self.bfm.read(A_STATUS)
                if not field("STATUS", "BUSY", st):
                    break
            self.seq_item_port.item_done()


# ------------------------------------------------------------------- monitor
class SpcuMonitor(uvm_monitor):
    """PASSIVE bus observer.

    It decodes APB reads of STATUS off the pins rather than issuing its own
    reads (which would contend with the driver for the bus) and rather than
    peeking at internal FSM state (which would let it observe things a real
    integrator cannot). What it publishes is exactly what software could see.
    """

    def build_phase(self):
        self.ap = uvm_analysis_port("ap", self)
        self.dut = cocotb.top

    async def run_phase(self):
        while True:
            await RisingEdge(self.dut.pclk)
            if (int(self.dut.psel.value) and int(self.dut.penable.value)
                    and not int(self.dut.pwrite.value)
                    and int(self.dut.paddr.value) == A_STATUS):
                word = int(self.dut.prdata.value)
                self.ap.write({
                    "busy": field("STATUS", "BUSY", word),
                    "pstate": field("STATUS", "CUR_PSTATE", word),
                    "volt": field("STATUS", "VOLT", word),
                    "freq": field("STATUS", "FREQ", word),
                    "error": field("STATUS", "ERROR", word),
                })


# ---------------------------------------------------------------- scoreboard
class SpcuScoreboard(uvm_component):
    """Independent reference model.

    Predicts from the REQUIREMENTS, not by mirroring the RTL. A scoreboard that
    re-implements the design agrees with it by construction and checks nothing.
    """

    def build_phase(self):
        self.fifo = uvm_tlm_analysis_fifo("fifo", self)
        self.expected = []
        self.errors = 0
        self.checks = 0
        self.ref_pstate = 0
        self.prev_busy = 0

    def predict(self, item, require_priv=True, lock=False, pd_on=True):
        """Called BEFORE the item is driven, so the prediction cannot be
        contaminated by the observed result."""
        refuse = ((not pd_on) or lock
                  or (require_priv and not item.priv)
                  or abs(item.target - self.ref_pstate) > 1)
        if not refuse:
            self.ref_pstate = item.target
        self.expected.append((refuse, self.ref_pstate))
        return refuse

    async def run_phase(self):
        while True:
            txn = await self.fifo.get()
            # A transaction retires when BUSY is observed falling.
            if self.prev_busy and not txn["busy"]:
                self.compare(txn)
            self.prev_busy = txn["busy"]

    def compare(self, txn):
        if not self.expected:
            return
        refuse, exp_pstate = self.expected.pop(0)
        self.checks += 1
        if refuse:
            if not txn["error"]:
                self.logger.error(f"expected refusal, observed success: {txn}")
                self.errors += 1
        else:
            if txn["pstate"] != exp_pstate:
                self.logger.error(
                    f"expected P{exp_pstate}, observed P{txn['pstate']}")
                self.errors += 1
            if txn["volt"] != txn["pstate"] or txn["freq"] != txn["pstate"]:
                self.logger.error(f"settled point inconsistent: {txn}")
                self.errors += 1

    def check_phase(self):
        if self.errors:
            self.logger.error(
                f"SCOREBOARD FAIL: {self.errors} mismatches in {self.checks} checks")
        else:
            self.logger.info(f"SCOREBOARD CLEAN: {self.checks} checks")


# --------------------------------------------------------------- agent / env
class SpcuAgent(uvm_agent):
    def build_phase(self):
        self.seqr = uvm_sequencer("seqr", self)
        ConfigDB().set(None, "*", "SEQR", self.seqr)
        self.driver = SpcuDriver("driver", self)
        self.monitor = SpcuMonitor("monitor", self)

    def connect_phase(self):
        self.driver.seq_item_port.connect(self.seqr.seq_item_export)


class SpcuEnv(uvm_env):
    def build_phase(self):
        self.agent = SpcuAgent("agent", self)
        self.scoreboard = SpcuScoreboard("scoreboard", self)

    def connect_phase(self):
        self.agent.monitor.ap.connect(self.scoreboard.fifo.analysis_export)
