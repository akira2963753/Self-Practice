# Train

Personal training repo for **digital IC design, verification, and the ASIC back-end flow**.
Each folder is a self-contained project taken from RTL through synthesis, STA, and gate-level sim.

## Projects

| Project | Topic | Implementation |
|---------|-------|-------------------|
| [`CDC/`](CDC/) | Clock Domain Crossing (async FIFO) | [`CDC.v`](CDC/ADFP/01_RTL/CDC.v) · [`PATTERN.sv`](CDC/ADFP/00_TESTBED/PATTERN.sv) · [`TESTBED.sv`](CDC/ADFP/00_TESTBED/TESTBED.sv) · [`syn.tcl`](CDC/ADFP/02_SYN/syn.tcl) · [`pt.tcl`](CDC/ADFP/03_PT/pt.tcl) |

*(more to come)*

## Flow

Each project follows the same back-end flow, one folder per stage:

| Stage | Folder | Tool |
|-------|--------|------|
| RTL Simulation | `01_RTL` | VCS / Verdi |
| Synthesis | `02_SYN` | Design Compiler |
| Static Timing Analysis | `03_PT` | PrimeTime |
| Gate-level Simulation | `04_GATE` | VCS (SDF back-annotated) |

Verification environment (`PATTERN.sv` / `TESTBED.sv`) lives in `00_TESTBED`.

Run scripts are `0X_run` inside each stage folder.

## Author

**Marco** · M11407439 · <harry2963753@gmail.com>
