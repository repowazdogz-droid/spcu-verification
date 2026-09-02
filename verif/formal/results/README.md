# Formal run record

Re-run on 2026-09-02 from a clean checkout with `make formal` (all five SymbiYosys tasks
in `verif/formal/spcu.sby`). Each `*.status` file is SymbiYosys's own status line
(`PASS <rc> <seconds>`); each `*.summary` is its summary file, including the cover traces
reached. Engine versions are in `docs/TOOLS.md`. The per-task working directories
(`verif/formal/spcu_*/`) are regenerable and not tracked.

Read `prove` as unbounded and everything else as bounded. `docs/TRACEABILITY.md` maps each
requirement to the task and model that established it.
