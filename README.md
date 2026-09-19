# Mackerel-030F

An FPGA SoC implementation of a Mackerel-030 (the real, prototype-stage
MC68030 board in [crmaykish/mackerel-68k](https://github.com/crmaykish/mackerel-68k),
`hardware/mackerel-30-proto/`) — the same way
[Mackerel-F](https://github.com/crmaykish/mackerel-68k/blob/master/docs/building-and-running-mackerel-f.md)
is an FPGA SoC implementation of the plain Mackerel-68k boards on a Tang Nano 20K.

Mackerel-F drops a 68000 soft core (`fx68k`) into its own glue/memory-map/
peripheral logic. Mackerel-030F does the same thing with a real,
pin-accurate MC68030 core instead: [MH030](https://github.com/harrowm/MH030)
(cycle-accurate, full 68020+ ISA, MMU, caches — see that repo's own
`CLAUDE.md` for the complete design). The board target is a
[ULX3S-85F](https://www.crowdsupply.com/radiona/ulx3s) (Lattice ECP5-85F),
not a Tang Nano 20K — `plan.md` explains why.

## Repo layout

- `cores/` — external CPU/FPU cores, fetched by `cores/get_cores.sh`, never
  vendored (mirrors `mackerel-68k`'s own `pld/mackerel-f/get_cores.sh`
  convention exactly). `cores/mh030` is [MH030](https://github.com/harrowm/MH030)
  itself; `cores/mh882` is [MH882](https://github.com/harrowm/mh882) (the
  sibling MC68881/68882 FPU core), fetched but not yet wired in — see
  `plan.md`'s coprocessor stretch goal.
- `pld/mackerel-030f/` — the actual FPGA project: top-level glue
  (`mackerel_030f.v`), memory map, peripherals, board constraints
  (`.lpf`), Makefile.
- `docs/` — reference material.
- `plan.md` — the full staged bring-up plan, board-selection history
  (why ULX3S-85F over Tang Nano 20K/DE10-Nano/other ECP5 boards), and
  the resource-fit + place-and-route investigation that preceded any of
  this repo's own RTL.

## Why a separate repo from MH030/MH882

MH030 and MH882 are independent, reusable, board-agnostic CPU/FPU core
projects, each with its own complete verification discipline (Tom Harte
sweep, Musashi cosim, etc.) — the same role `fx68k` plays for Mackerel-F.
Mackerel-030F is the SoC/board integration layer, exactly the role
`mackerel-68k` itself plays relative to `fx68k`: it clones cores in as
external dependencies via `cores/get_cores.sh` rather than merging RTL
trees, so MH030's own commit history stays about CPU correctness, not
board bring-up, and this repo's own history stays about board bring-up,
not CPU correctness.

## Toolchain

Open only: Yosys + Project Trellis + nextpnr-ecp5 + openFPGALoader — via
[oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite-build), never
Lattice's proprietary Diamond. See `plan.md` for the full toolchain
investigation (including two real synthesis-flow issues found and fixed
along the way, and a real RTL-level combinational loop diagnosed and
found to be benign).
