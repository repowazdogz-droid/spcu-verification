"""cocotb entry points for the pyuvm testbench, plus the Verilator runner."""

import os
import pathlib
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from pyuvm import ConfigDB, uvm_root, uvm_test

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from spcu_pyuvm_tb import (IllegalJumpSequence, RandomSequence,  # noqa: E402
                           SpcuEnv, UnprivilegedSequence, WalkSequence)

ROOT = pathlib.Path(__file__).resolve().parents[2]


async def bring_up(dut):
    """Two asynchronous clocks and a reset. The period ratio is deliberately
    non-integer so the CDC sampling relationship does not repeat."""
    cocotb.start_soon(Clock(dut.pclk, 10, units="ns").start())
    cocotb.start_soon(Clock(dut.sclk, 14, units="ns").start())

    dut.presetn.value = 0
    dut.srst_n.value = 0
    dut.psel.value = 0
    dut.penable.value = 0
    dut.pwrite.value = 0
    dut.paddr.value = 0
    dut.pwdata.value = 0
    dut.pprot0.value = 0
    dut.pd_on.value = 1
    dut.vack.value = 0
    await ClockCycles(dut.pclk, 8)
    dut.presetn.value = 1
    dut.srst_n.value = 1
    await ClockCycles(dut.pclk, 8)

    cocotb.start_soon(pmic(dut))


async def pmic(dut):
    """Voltage regulator model: acknowledge a request after a short delay,
    and drop the acknowledge once the request is withdrawn."""
    while True:
        await RisingEdge(dut.sclk)
        if int(dut.vreq.value) == 1 and int(dut.vack.value) == 0:
            await ClockCycles(dut.sclk, 2)
            dut.vack.value = 1
        elif int(dut.vreq.value) == 0:
            dut.vack.value = 0


class BaseTest(uvm_test):
    sequence_cls = WalkSequence

    def build_phase(self):
        self.env = SpcuEnv("env", self)

    async def run_phase(self):
        self.raise_objection()
        seqr = ConfigDB().get(self, "", "SEQR")
        seq = self.sequence_cls()
        # The scoreboard predicts each item before it is driven, so the
        # prediction cannot be contaminated by the observed result.
        sb = self.env.scoreboard
        orig_start = seq.start_item

        async def start_item(item, *a, **k):
            sb.predict(item)
            return await orig_start(item, *a, **k)

        seq.start_item = start_item
        await seq.start(seqr)
        await ClockCycles(cocotb.top.pclk, 60)
        self.drop_objection()


class WalkTest(BaseTest):
    sequence_cls = WalkSequence


class IllegalTest(BaseTest):
    sequence_cls = IllegalJumpSequence


class UnprivTest(BaseTest):
    sequence_cls = UnprivilegedSequence


class RandomTest(BaseTest):
    sequence_cls = RandomSequence


@cocotb.test()
async def run_uvm(dut):
    await bring_up(dut)
    name = os.environ.get("SPCU_TEST", "WalkTest")
    await uvm_root().run_test(name)
    sb_errors = getattr(run_uvm, "errors", 0)
    assert sb_errors == 0, f"{sb_errors} scoreboard mismatches"


# ------------------------------------------------------------------- runner
def main():
    # cocotb 2.0 moved the runner out of the cocotb package into cocotb_tools.
    from cocotb_tools.runner import get_runner

    sources = [ROOT / p for p in [
        "rtl/spcu_pkg.sv", "rtl/spcu_sync2.sv", "rtl/spcu_regs.sv",
        "rtl/spcu_ctrl_fsm.sv", "verif/props/spcu_props.sv",
        "verif/props/spcu_props_pclk.sv", "rtl/spcu_top.sv",
    ]]
    runner = get_runner("verilator")
    runner.build(
        verilog_sources=sources,
        hdl_toplevel="spcu_top",
        build_dir=ROOT / "build" / "obj_pyuvm",
        build_args=["--assert", "--timing", "-Wno-fatal", "-Wno-WIDTHEXPAND",
                    "--trace", str(ROOT / "verif" / "verilator.vlt")],
        always=True,
    )
    runner.test(
        hdl_toplevel="spcu_top",
        test_module="test_spcu",
        test_dir=pathlib.Path(__file__).parent,
        build_dir=ROOT / "build" / "obj_pyuvm",
    )


if __name__ == "__main__":
    main()
