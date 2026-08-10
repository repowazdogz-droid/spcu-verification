#!/bin/bash
# Run the SPCU property set against one mutant.
#   sby PASS  => no property fired => the mutant SURVIVED
#   sby FAIL  => a property fired  => the mutant was DETECTED
#   sby ERROR => the mutant could not be evaluated in this model at all.
#
# The ERROR case is real and must not be silently dropped. `mutate -mode inv
# -port CLK` inverts a clock edge, and `prep` then refuses the design with
# "CLK ... also used with opposite polarity, run clk2fflogic instead". Those
# mutants are a TOOLING LIMITATION of the flow, not evidence about the
# property set, and they are reported separately in the denominator.
exec 2>&1
set -x
bash $SCRIPTS/create_mutated.sh -o mutated.il
ln -sf ../../test_fm.sby .
sby -f test_fm.sby || true
# NOTE: `awk`, not `gawk`. MCY's shipped examples use gawk, which macOS does
# not provide; the tests then run correctly and silently record nothing.
awk "{ print 1, \$1; }" test_fm/status >> output.txt
exit 0
