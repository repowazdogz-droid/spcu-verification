#!/bin/bash
# EQUIVALENCE MITER: mutated design vs golden, comparing the observable
# outputs of spcu_fv_top over a bounded window.
#
#   PASS => no observable difference within EQ_DEPTH cycles  => EQUIVALENT
#   FAIL => the outputs provably differ                      => OBSERVABLE
#
# THREE THINGS THIS HARNESS GOT WRONG FIRST, all caught by controls:
#
#  1. `chformal -remove` stripped the ASSUMPTIONS as well as the assertions,
#     so the miter lost the reset anchor and the two copies started from
#     arbitrary independent states. The identity mutation then reported
#     "not equivalent", which is impossible. Assumptions are retained here;
#     only asserts and covers are removed.
#  2. Without `setundef -init -zero` the initial state is still free.
#  3. `sat` needs `async2sync` for this design's asynchronous-reset flops.
#
# The result is BOUNDED, not a proof: `sat -tempinduct` (unbounded) did not
# converge within 10 minutes on this miter. "Equivalent" here means "no
# observable difference within EQ_DEPTH cycles".
exec 2>&1
set -x
EQ_DEPTH=30
bash $SCRIPTS/create_mutated.sh -o mutated.il
cp $PRJDIR/database/design.il golden.il

yosys -ql eq.log -p "
  read_rtlil golden.il
  rename spcu_fv_top gold
  chformal -assert -cover -remove gold
  read_rtlil mutated.il
  rename spcu_fv_top gate
  chformal -assert -cover -remove gate
  miter -equiv -flatten -make_assert gold gate miter
  prep -top miter
  setundef -init -zero
  async2sync
  sat -seq $EQ_DEPTH -prove-asserts
"
if grep -q 'no model found' eq.log; then
    echo "1 PASS" >> output.txt      # equivalent within the bound
elif grep -q 'model found' eq.log; then
    echo "1 FAIL" >> output.txt      # observable difference
else
    echo "1 ERROR" >> output.txt
fi
exit 0
