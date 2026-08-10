# SPCU Verification Lab
#
# Every headline result in docs/ is reproducible from a clean clone with:
#     make setup && make all
#
# OSS_CAD points at the OSS CAD Suite. Override on the command line if yours
# lives elsewhere:  make OSS_CAD=/path/to/oss-cad-suite/bin all

OSS_CAD ?= $(HOME)/eda/oss-cad-suite/bin
PY      ?= ./.venv/bin/python

# Tools are invoked by ABSOLUTE path. GNU make 3.81 (the macOS system make)
# exec's simple recipe lines directly instead of going through a shell, and
# that direct exec does NOT see a PATH exported from the makefile -- so a bare
# `verilator` fails with "No such file or directory" while a recipe line that
# happens to contain shell metacharacters works. Absolute paths remove the
# inconsistency. PATH is still exported, because sby spawns yosys and the
# solvers by name.
export PATH := $(OSS_CAD):$(PATH)
VERILATOR := $(OSS_CAD)/verilator
SBY       := $(OSS_CAD)/sby

RTL   := rtl/spcu_pkg.sv rtl/spcu_sync2.sv rtl/spcu_regs.sv rtl/spcu_ctrl_fsm.sv \
         verif/props/spcu_props.sv verif/props/spcu_props_pclk.sv rtl/spcu_top.sv
SIM   := $(RTL) verif/sv/spcu_sva_tier_b.sv verif/sv/spcu_sv_tb.sv
VFLAGS := --assert -sv -Wno-fatal verif/verilator.vlt

.PHONY: all setup gen check-gen lint formal formal-prove formal-bmc formal-cover \
        formal-cdc formal-rdc sim pyuvm ctest mutations mcy clean help

help:
	@echo "make setup      create the Python venv and install cocotb/pyuvm/pyyaml"
	@echo "make all        the full regression (everything below)"
	@echo "make gen        regenerate RTL/C/pyuvm/docs from spec/spcu_regs.yaml"
	@echo "make check-gen  fail if any generated file is stale"
	@echo "make lint       Verilator lint with documented waivers"
	@echo "make formal     all four formal tasks"
	@echo "make sim        SystemVerilog class-based testbench"
	@echo "make pyuvm      pyuvm/cocotb UVM-architecture testbench"
	@echo "make ctest      bare-metal C driver against the RTL"
	@echo "make mutations  apply the hand-authored mutation catalogue"
	@echo "make mcy        netlist mutation coverage with equivalence classification (slow)"

all: check-gen lint formal sim pyuvm ctest mutations
	@echo
	@echo "=============================================="
	@echo " full regression complete"
	@echo "=============================================="

setup:
	/opt/homebrew/opt/python@3.13/bin/python3.13 -m venv .venv || python3.13 -m venv .venv
	$(PY) -m pip install -q --upgrade pip
	$(PY) -m pip install -q pyyaml cocotb pyuvm pytest
	@echo "venv ready. cocotb requires Python <= 3.13; 3.14 is rejected at install."

gen:
	$(PY) tools/genregs.py

# The generated files are committed, so CI must prove they still match the spec.
check-gen:
	@echo "=== generated-file freshness ==="
	$(PY) tools/genregs.py --check

lint:
	@echo "=== lint ==="
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME $(VFLAGS) $(RTL) --top spcu_top
	@echo "lint clean (waivers justified in verif/verilator.vlt)"

formal: formal-prove formal-bmc formal-cover formal-cdc formal-rdc

# UNBOUNDED. k-induction and PDR/IC3 race; either returning PASS is a proof.
formal-prove:
	@echo "=== formal: unbounded proof (k-induction + PDR) ==="
	$(SBY) -f verif/formal/spcu.sby prove

# BOUNDED. A pass means "no counterexample within the depth", NOT a proof.
formal-bmc:
	@echo "=== formal: bounded model checking (NOT a proof) ==="
	$(SBY) -f verif/formal/spcu.sby bmc

formal-cover:
	@echo "=== formal: cover reachability ==="
	$(SBY) -f verif/formal/spcu.sby cover

# clk2fflogic + multiclock: genuinely asynchronous clocks. BMC only.
formal-cdc:
	@echo "=== formal: CDC under arbitrary clock phase (bounded) ==="
	$(SBY) -f verif/formal/spcu.sby cdc_bmc

# Resets FREE (the R22 integration constraint removed), R18b disabled. This is
# the standing regression guard for the B1 reset-domain-crossing fix, which was
# found with free resets and would be masked if every task assumed R22.
formal-rdc:
	@echo "=== formal: free resets, R18b off (guards the B1 fix) ==="
	$(SBY) -f verif/formal/spcu.sby rdc_freerst

sim:
	@echo "=== simulation: SystemVerilog class-based testbench ==="
	@mkdir -p build/obj_sv
	$(VERILATOR) --binary --timing $(VFLAGS) $(SIM) --top spcu_sv_tb \
	    -o spcu_sv_tb --Mdir build/obj_sv
	./build/obj_sv/spcu_sv_tb

pyuvm:
	@echo "=== simulation: pyuvm / cocotb ==="
	@for t in WalkTest IllegalTest UnprivTest RandomTest; do \
	    echo "--- $$t ---"; \
	    SPCU_TEST=$$t $(PY) verif/pyuvm/test_spcu.py 2>&1 \
	      | grep -E 'SCOREBOARD|TESTS=' || exit 1; \
	done

ctest:
	@echo "=== bare-metal C driver against RTL ==="
	@mkdir -p build/obj_c
	$(VERILATOR) --cc $(VFLAGS) $(RTL) --top spcu_top --Mdir build/obj_c \
	    --exe --build -CFLAGS "-DSPCU_SIM -I../../verif/c" \
	    ../../verif/c/sim_main.cpp ../../verif/c/spcu_driver.c -o spcu_c_tb
	./build/obj_c/spcu_c_tb
	@echo "--- same driver source also builds for a real target (no SPCU_SIM) ---"
	cc -c -o /dev/null -Iverif/c verif/c/spcu_driver.c && echo "native build OK"

mutations:
	@echo "=== hand-authored mutation catalogue ==="
	$(PY) tools/run_mutations.py

# Netlist-level mutation coverage. 200 mutations sampled by Yosys, each run
# through BOTH the property set and an equivalence miter, so survivors are
# separated into "equivalent" and "real gap" rather than lumped together.
# Long-running; not part of `make all`.
mcy:
	@echo "=== MCY: automatic netlist mutation coverage ==="
	cd mutations/mcy && $(OSS_CAD)/mcy init && $(OSS_CAD)/mcy run -j $$(( $$(sysctl -n hw.ncpu) - 2 ))
	cd mutations/mcy && $(OSS_CAD)/mcy status

clean:
	rm -rf build verif/formal/spcu_prove verif/formal/spcu_bmc \
	       verif/formal/spcu_cover verif/formal/spcu_cdc_bmc \
	       verif/pyuvm/__pycache__ verif/pyuvm/sim_build
