# Tool versions

Everything is open source. The run recorded in `verif/formal/results/` used:

| tool | version | source |
|---|---|---|
| OSS CAD Suite | 2026-08-10 build, darwin-arm64 | github.com/YosysHQ/oss-cad-suite-build |
| Yosys | 0.68+40 | in the suite |
| SymbiYosys (sby) | 0.68 | in the suite |
| yosys-smtbmc + Z3 | Z3 4.15.5 | in the suite |
| ABC (pdr engine) | 1.01, 2026-08-08 build | in the suite |
| Verilator | 5.051 devel (v5.050-155) | in the suite |
| mcy | in the suite | mutation coverage |
| cocotb / pyuvm | 2.0.1 / 4.0.1 | `make setup` venv, Python 3.13 or older |

`make OSS_CAD=/path/to/oss-cad-suite/bin <target>` selects the suite. The mutation runner
reads the same `OSS_CAD` environment variable. Results on other suite builds should match
for `prove`, `bmc`, `cdc_bmc` and `rdc_freerst`; cover trace step counts can differ between
solver versions.
