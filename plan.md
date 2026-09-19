# Mackerel-030F — ULX3S (ECP5-85F) port plan

> Moved here from MH030's own `tang_plan.md` (2026-09-18) once the board
> bring-up work got its own repo — see this repo's `README.md` for why.
> File paths below that used to read `rtl/...` now read `cores/mh030/rtl/...`
> since MH030 is a fetched dependency (`cores/get_cores.sh`), not vendored
> RTL living in this repo.

## Board decision: ULX3S-85F (2026-09-17)

**Target board is the [ULX3S-85F](https://www.crowdsupply.com/radiona/ulx3s)
(Lattice ECP5-85F, `LFE5UM5G-85F`), not a Tang Nano 20K.** This plan was
originally written against the Tang Nano 20K; see "Board selection
history" near the end of this file for the full resource-fit
investigation that led here (short version: `m68030_top` needs
~54K-103K LUT4-equivalent cells, the Tang Nano 20K's GW2AR-18C only has
20,736, no bigger Gowin board has working open-toolchain support yet,
and DE10-Nano/MiSTer's bigger Cyclone V only has an experimental open
backend plus no native Mac Quartus). ULX3S-85F is $155, in production,
has the right onboard peripherals (32MB SDRAM, USB, microSD, GPIO), and
carries the most mature fully-open FPGA toolchain that exists
(Project Trellis + nextpnr-ecp5) — chosen over ECPIX-5 (better
peripherals, real DDR3 + Gigabit Ethernet, but currently out of stock).

## Goal

Build "Mackerel-030F": a Mackerel-030 (the real, prototype-stage MC68030
board in [crmaykish/mackerel-68k](https://github.com/crmaykish/mackerel-68k),
`hardware/mackerel-30-proto/`) implemented as an FPGA SoC on the ULX3S-85F,
the same way [Mackerel-F](https://github.com/crmaykish/mackerel-68k/blob/master/docs/building-and-running-mackerel-f.md)
is an FPGA SoC implementation of the plain Mackerel-68k boards on a Tang
Nano 20K — except Mackerel-F drops in `fx68k` (a 68000 soft core) where
Mackerel-030F drops in `m68030_top` ([MH030](https://github.com/harrowm/MH030)'s
own cycle-accurate 68030, `cores/mh030/rtl/m68030_top.sv`), and
Mackerel-030F targets a different (bigger) board because `m68030_top`
doesn't fit on Mackerel-F's own Tang Nano 20K.

Toolchain constraint: **use Yosys + Project Trellis + nextpnr-ecp5 +
openFPGALoader — the open ECP5 flow — never Lattice's proprietary
Diamond**, even though Mackerel-F's own Gowin build uses Gowin's
proprietary `gw_sh`. This is an explicit, standing user requirement, not
just a Tang-Nano-specific one.

## Reference: what Mackerel-F actually is

`pld/mackerel-f/mackerel_f.v` on a Tang Nano 20K (GW2AR-18C):
`fx68k` (real 68000 pinout) + hand-written glue to on-chip ROM
(`$readmemh`), on-chip BSRAM, a nand2mario SDRAM controller (8 MB), OpenCores
`uart16550`/`tiny_spi`, a WS2812 driver, a timer, and an `irq_encoder`.
Address decode is off the 68000's 24-bit bus; peripherals sit in an 8-slot,
256-byte-each MMIO window at `0xFFF800`; everything terminates on `DTACKn`;
`VPAn` is tied low during CPU-space (autovectored interrupts); a
`boot_signal` shadow maps ROM to address 0 until the first fetch escapes it,
then SDRAM owns `0x000000`. Built with Gowin EDA (`gw_sh`) + `openFPGALoader`.

Mackerel-030F needs the same shape, but `m68030_top`'s bus is a materially
different animal: 32-bit data, single `/DS` (not LDS/UDS), `SIZ[1:0]` +
real dynamic bus sizing (not fixed 16-bit), `DSACK0/1` (not `DTACK`),
`/AVEC` (not `VPAn`), a full 32-bit address bus, plus pins Mackerel-F never
had to deal with (`ECS/OCS`, `RMC#`, `DBEN#`, `CBREQ/CBACK`, `CIIN/CIOUT`,
`STATUS`, `CDIS#/MMUDIS#`).

`m68030_top`'s full external pin list is in `cores/mh030/rtl/m68030_top.sv`
(module port list) — it is genuinely pin-accurate to real MC68030 silicon
per that project's own design constraints (see MH030's own `CLAUDE.md`).

## Staged plan (ULX3S-85F)

**0. Resource-fit check.** Done against the Gowin-family proxy first
(decisive — see "Board selection history"); re-run against the *actual*
target architecture via Yosys `synth_ecp5` once ULX3S was chosen, since
ECP5 packs LUTs somewhat differently than GW1N/GW2A even though both are
native 4-input-LUT architectures. **Resolved: fits, three independent
confirmations (LUT-count estimate, nextpnr's own utilization report,
and a complete successful place-and-route). See "Step 1 progress"
below.**

**1. Toolchain setup.** Yosys (`synth_ecp5`) + nextpnr-ecp5 + Project
Trellis (`ecppack` for bitstream generation) + `openFPGALoader
--board=ulx3s` (loading — supports both SRAM-load, volatile/fast-iterate,
and SPI-flash-persist, mirroring Mackerel-F's own `prog`/`flash` split).
Confirmed working reference invocation chain:
```
yosys -p 'synth_ecp5 -top top -json out.json' src.v
nextpnr-ecp5 --85k --json out.json --lpf ulx3s_v20.lpf --package CABGA381 --textcfg out.config
ecppack out.config out.bit
openFPGALoader --board=ulx3s out.bit
```
Need to pull the revision-matched `.lpf` pin-constraint file from the
official [emard/ulx3s](https://github.com/emard/ulx3s) hardware repo
(matching the exact board revision in hand — ULX3S has multiple
revisions with different `.lpf` files) rather than write one from
scratch. `m68030_top`'s SystemVerilog needs the same `sv2v` flattening
step used for the resource check (Yosys's built-in frontend doesn't
parse the unpacked-array ports `eu_agu.sv` and others use) — this is now
a permanent step in the synthesis flow, not just a one-off for the
feasibility check. **Status: installed, verified, exercised end-to-end
through a real place-and-route — see "Step 1 progress" below.**

**2. Clock plan.** MH030 requires `clk_4x` = 4x the external bus
frequency (fully synchronous, no `negedge` tricks — see MH030's
`CLAUDE.md` Design Constraints). ULX3S provides a **25 MHz onboard
oscillator** (vs. Tang Nano 20K's 27 MHz). Project Trellis ships its own
PLL-wizard equivalent, `ecppll`, which generates an `EHXPLLL` primitive
wrapper directly: `ecppll -i 25 -o <target_MHz> -n <module_name> -f
<output.v>`. Target e.g. 25 MHz external bus -> 100 MHz `clk_4x`, or
match the real Mackerel-30 board's 20 MHz -> 80 MHz `clk_4x` — one
community report flags limited output-frequency granularity from a
25 MHz input in `ecppll`'s simple mode, so confirm the actual achievable
frequency lands close enough to the target before committing to one. No
phase-enable trick needed (that's an `fx68k`/68000 two-phase-clock
artifact MH030 doesn't have).

**3. New top-level glue module** (`mackerel_030f.v`, structurally
`mackerel_f.v`'s twin, lives in `pld/mackerel-030f/` in this repo)
instantiating `m68030_top` in place of `fx68k`, driving its real pin
list: `ext_a[31:0]`, `ext_d_out/ext_d_in/ext_d_oe`, `ext_as_n`,
`ext_ds_n`, `ext_rw`, `ext_fc[2:0]`, `ext_siz[1:0]`, `dsack0_n/dsack1_n`,
`avec_n`, `ipl_n[2:0]`, `berr_n`, `halt_n`, `br_n/bgack_n`,
`ciin_n/ciout_n`, `cback_n`, plus pins Mackerel-F never wired (`ECS/OCS`,
`RMC#`, `DBEN#`, `STATUS`, `CDIS#/MMUDIS#` — mostly tie-off/no-op for a
monolithic FPGA SoC where nothing external actually needs them). **In
progress — first cut scoped to the first bring-up milestone only (ROM +
GPIO/LED + UART), not every peripheral at once. See `pld/mackerel-030f/`.**

**4. Memory map + boot strategy.** Decide: keep Mackerel-F's "ROM shadowed
at 0 until first fetch, then SDRAM owns it" trick (matches `m68030_top`'s
own documented boot sequence — it fetches SSP@0/PC@4 off the external bus
for real, so the shadow trick still applies verbatim), or hard-map ROM
permanently at `0x00000000` for a simpler first bring-up. Either way this
is a values-only change to the same decode-logic shape `mackerel_f.v`
already has, widened from a 24-bit to a 32-bit address compare.

**5. Peripheral adaptation.** `uart16550`, `tiny_spi`, `timer.v`,
`ws2812.v` are dumb 8-bit MMIO registers with a `cs_n/rwn/ds_n/dtack_n`
shim, and are plain synthesizable Verilog with no Gowin-specific
primitives — portable to ECP5 unchanged. What changes is the shim:
instead of hand-muxing `LDS/UDS` and padding onto a fixed 16-bit
`DTACKn`, each peripheral's existing `dtack_n` needs translating into the
right `DSACK0/1` 8-bit-port encoding — MH030's own `biu_sizing_fsm`
(already built, already Harte-verified) does the byte/word/longword
iteration automatically. `irq_encoder.v` is reusable completely
unchanged — `IPL[2:0]` priority encoding is pin-identical between 68000
and 68030. WS2812 doesn't exist on ULX3S (no onboard addressable RGB LED
the way Tang Nano 20K has) — drop it or repurpose for one of the 11
onboard LEDs.

**6. SDRAM adapter** — the one real new engineering item, and now a
different chip than originally scoped (Tang Nano 20K's SDRAM is an
in-package SiP with a ready-made nand2mario controller; ULX3S's is a
genuine discrete part). ULX3S carries an **MT48LC32M16 SDRAM, 16-bit
data bus**, 8/16/32/64 MB depending on board revision — no single
"official" ULX3S SDRAM controller was confirmed during research; this
needs a dedicated look (candidates: adapt nand2mario's controller to the
16-bit MT48LC32M16 timing instead of Tang Nano's part, or find/port an
existing MT48LC32M16 controller from the broader ECP5/Lattice hobbyist
ecosystem). Cheapest integration path either way: expose it to MH030 as
a 16-bit dynamically-sized port for first bring-up (free via the
existing sizing FSM); widen/add burst support only once the base system
is solid and caches get turned on (they reset disabled — `CACR`'s
`icache_en`/`dcache_en` bits default to 0 — so nothing forces this
early).

**7. Autovectoring.** Swap `VPAn` (68000/6800-bus relic, confirmed absent
from real 68030 silicon per MH030's own `CLAUDE.md`) for `/AVEC`
(`avec_n`). Same idea: tie asserted during CPU-space IACK cycles.

**8. Bring-up order:** synth/utilization check (done) -> toolchain +
`.lpf` pull -> minimal glue (on-chip ROM + LED blink, prove the core
boots on real fabric) -> UART console (onboard FTDI FT231XS,
`openFPGALoader`'s JTAG and the console UART are separate USB
interfaces, same two-port split as Mackerel-F) -> bootloader
(`m68k-mackerel-elf-`, new `BOARD=mack030f` target, `-m68030`) -> SDRAM
-> SPI/SD + timer/interrupts (no onboard Ethernet on ULX3S itself —
would need an external W5500 wired to the PMOD/GPIO headers, same as
Mackerel-F's own approach on Tang Nano) -> enable caches/MMU -> stretch
goal: port the existing full-MMU Mackerel-30 Linux board support.

**9. New verification surface.** Everything MH030 already proves (Harte,
Musashi cosim) covers instruction correctness, not this. The memory-map
decode, DSACK generation, and SDRAM adapter are new, untested glue — worth
a `tb/mackerel_030f_tb.sv` smoke test against a simulated ROM/SDRAM/
peripheral model before ever touching real hardware, matching MH030's
own established verification discipline.

**Stretch goal, noted for later, not scoped now:** MH882 ([MH030](https://github.com/harrowm/MH030)'s
own sibling MC68881/68882 FPU, `cores/mh882` once fetched) has a real
coprocessor interface. Dropping it into the same fabric later as a
second FPGA core would give a genuine live cross-repo MH030<->MH882
cosim — currently listed as a deliberately deferred aspiration in both
of those projects' own memory/plan files.

## Status

- [x] Board decision: **ULX3S-85F** (see top of file + board selection
  history below)
- [x] Step 0a: Yosys `synth_gowin` resource-utilization check against
  Tang Nano 20K — DOES NOT FIT (the finding that triggered the board
  search)
- [x] Step 0b: Yosys resource-utilization check against the actual
  target (ULX3S's ECP5-85F) — FITS, ~78% LUT utilization.
- [x] Step 1a: toolchain installed — oss-cad-suite at `~/oss-cad-suite`
  (nextpnr-ecp5, ecppack, ecppll, openFPGALoader all confirmed working;
  homebrew has no `nextpnr-ecp5` formula, only `nextpnr-ice40`)
- [x] **Step 1b: real `nextpnr-ecp5` place & route — COMPLETE, 0 errors,
  238,677 arcs routed. Third independent confirmation of "fits." Timing
  result (1.61 MHz) is not meaningful — came from a non-timing-driven
  synthesis shortcut, not a real speed ceiling. Getting a trustworthy
  Fmax number is separate future work.** Result below.
- [x] Combinational-loop investigation — RESOLVED. One real RTL-level
  loop found (not a synthesis artifact), precisely diagnosed, confirmed
  semantically dead (disjoint BKPT/Bcc opcode encodings), unblocked via
  `nextpnr-ecp5 --ignore-loops` rather than an RTL change. Result below.
- [ ] Step 1c: board `.lpf` — need the user's actual board revision
  (Crowd Supply's current batch ships v3.1.7/v3.1.8, not yet published
  upstream; using v3.1.6 as a stand-in has been fine for toolchain
  validation)
- [x] **Step 3: `mackerel_030f.v` top-level glue module — first cut
  (ROM + GPIO/LED only) written, synthesized, placed, routed, and
  packed into a real bitstream against the actual ULX3S `.lpf`. See
  "Step 3 first cut result" below. Not yet loaded onto real hardware —
  no board in hand yet, and the `.lpf` is still the v3.1.6 stand-in.**

### Step 3 first cut result (2026-09-19)

Wrote `pld/mackerel-030f/mackerel_030f.v`: PLL (real `ecppll`-generated
25→100MHz wrapper, not hand-derived), power-on reset, `m68030_top`
wired to its complete real pin list, on-chip ROM (4KB, `$readmemh`,
registered/synchronous read — deliberately the real BRAM-inferable
idiom), one GPIO/LED register, and a bus watchdog asserting `BERR` on
unmapped accesses. Plus `boot.s`/`rom.hex`: a real, hand-assembled
smoke-test program (LED counter with a software delay loop) — SSP/PC
vectors, `MOVEA.L`/`MOVE.L`/`ADDQ.L`/`SUBQ.L`/`Bcc.S` encodings all
verified by hand against the standard 68000 bit layouts.

Two details confirmed directly against MH030's own RTL rather than
assumed, worth recording since they'll matter for every future
peripheral: the 32-bit-port DSACK encoding (`dsack0_n`/`dsack1_n` both
asserted together decodes as port=2'b11 in `biu_sizing_fsm.sv`'s
`next_siz`/`needs_more` functions -> 32-bit, whole request in one
beat), and `ext_rw` polarity (1=read, 0=write, confirmed via its
reset-default values in `biu_cycle_gen.sv`).

**Full real toolchain chain exercised end to end, 0 errors at every
stage:**
1. Yosys synthesis (`synth_lattice -family ecp5` + the `abc -lut 4`
   recipe from Step 1) — 0 problems reported by `check`.
2. `nextpnr-ecp5 --85k --package CABGA381 --lpf ulx3s_v20.lpf
   --ignore-loops` — **every one of the module's own ports
   (`led[7:0]`, `ftdi_txd`/`ftdi_rxd`, `clk_25mhz`, `btn[6:0]`) matched
   a real physical pad in the `.lpf` and placed correctly**, the PLL
   placed onto a real `EHXPLL` hardware block, 235,213 routing arcs
   routed. **"Program finished normally." 0 errors.**
3. `ecppack` — produced a real 1.28 MB `.bit` bitstream file,
   `impl/mackerel_030f.bit`.

Resource utilization essentially unchanged from the bare-core numbers
(64,161/83,640 LUT4, 76%; 12,694 DFFs) — the glue logic itself
(PLL/reset/ROM/GPIO/watchdog) is a rounding error against the CPU core.

**This is a genuine, complete milestone**: the actual Mackerel-030F
top-level module — not just the bare `m68030_top` core — has been
synthesized, placed, routed against real board pin constraints, and
packed into a loadable bitstream, with zero errors at any stage. As
before, the reported Fmax (1.69 MHz) is not meaningful — same
non-timing-driven `abc -lut 4` synthesis shortcut as Step 1, not a real
speed ceiling.

**Not done, real remaining gaps before this can run on real hardware:**
the `.lpf` is the v3.1.6 stand-in, not the user's actual board revision
(Crowd Supply's current batch ships v3.1.7/v3.1.8); there is no
physical board in hand yet to load the bitstream onto; and getting a
trustworthy Fmax number is still separate future work (proper
timing-driven synthesis with a real clock constraint).

### UART increment (2026-09-19)

Added the UART console — the next item in the plan's own bring-up order
after ROM+LED. Reused Mackerel-F's own approach essentially unchanged:
the same OpenCores `uart16550` core (`cores/uart16550`, fetched by
`cores/get_cores.sh`, plain Verilog-2001, no sv2v flattening needed)
behind the same wrapper shape as Mackerel-F's own `pld/mackerel-f/
uart.v` (`pld/mackerel-030f/uart.v`, adapted essentially unchanged — the
underlying core doesn't care which CPU is on the other side of the
wrapper's own simple `cs_n/reg_addr/rwn/ds_n/data_in/data_out/dtack_n`
interface).

**New memory-map entry**: UART at `0xFFFFFF10-0xFFFFFF17` (8 registers,
byte-addressed 1:1, unlike Mackerel-F's own word-strided 16-bit-bus
layout). This is the first genuinely **8-bit-port** peripheral in the
design (vs. ROM/GPIO's 32-bit port) — confirms MH030's own dynamic bus
sizing handles a real narrow peripheral correctly, not just the trivial
full-width case: `dsack1_n` mirrors the wrapper's own `dtack_n` directly
(port=2'b10 decoding, confirmed the same way as the 32-bit case against
`biu_sizing_fsm.sv`), `dsack0_n` stays inactive throughout.

**Boot program extended** (`boot.s`/`rom.hex`): configures the UART for
9600 baud/8N1 (divisor 651=$0288 for the 100MHz `clk_4x` fed to
`wb_clk_i`), then polls LSR's THRE bit each loop iteration and
transmits a fixed test byte (`'U'`/$55, chosen for its recognizable
01010101 bit pattern) when ready — alongside the existing LED counter.
New instructions needed real care: `MOVE.B #imm,(d16,An)` (opcode
`$137C`, mode 101 = address-register-indirect-with-16-bit-displacement,
genuinely simpler than the indexed `(d8,An,Xn)` mode since it's a single
plain 16-bit displacement extension word, not a brief/full-format
index byte) and the static-bit-test form of `BTST #n,Dn` (`$08xx`
family). Every displacement (`BEQ.S`/`BNE.S`/`BRA.S`) computed twice,
independently, from scratch, and cross-checked — caught one bug in the
*checking script itself* (a mislabeled target in the first pass, not in
the actual assembled program) before trusting the result.

**Synthesis result — a genuine, unplanned bonus finding**: this build
used the full `synth_lattice` recipe (no `-nolutram`, unlike the
Step 0b feasibility check), and the boot ROM's `reg [31:0] rom[0:1023]`
array — written from the start using the real BRAM-inferable idiom
(registered/synchronous read) specifically discussed with the user
earlier as a *theoretical* lever for freeing up LUTs — **actually
inferred to 2 real `DP16KD` block-RAM cells this time**, plus 4 small
`TRELLIS_DPR16X4` distributed-RAM cells from the UART's own internal
FIFOs. Confirms that discussion's conclusion in practice, not just in
theory: writing arrays in the synchronous-read idiom is enough on its
own, on any target, with zero vendor-specific pragmas. `check`
reported 0 problems.

| | This build | Cut-1 (ROM+GPIO only) |
|---|---|---|
| LUT4 (pre-pack) | 64,397/83,640 (76%) | 64,161/83,640 (76%) |
| DFFs | 13,159/83,640 (16%) | 12,694/83,640 (15%) |
| Block RAM | 2 DP16KD + 4 DPR16X4 | 0 |

Essentially unchanged resource usage despite adding a real UART core —
the block-RAM ROM saved roughly what the new UART logic cost.

**Place-and-route**: launched against the real `.lpf`, same as cut 1 —
every port (including the now-live `ftdi_rxd`/`ftdi_txd`) matched a
real physical pad and the PLL placed onto real `EHXPLL` hardware.
Result pending at time of writing this entry — update once complete,
matching cut 1's own already-established pattern (structural
success/error count is what matters; Fmax is not meaningful with this
synthesis recipe).

**Not tested on real hardware** — same gap as cut 1: no board in hand,
`.lpf` still the v3.1.6 stand-in.

### Step 1 progress (2026-09-18)

**Toolchain:** homebrew only packages `nextpnr-ice40`, not
`nextpnr-ecp5` — installed [oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite-build)
(521MB, 2026-09-18 build) to `~/oss-cad-suite`, which happens to be the
*exact* path Mackerel-F's own `pld/mackerel-f/Makefile` already expects
(`$(HOME)/oss-cad-suite/bin/openFPGALoader`) — no divergence from the
reference project's own convention. All 4 needed tools confirmed
working: `nextpnr-ecp5` (0.11.1-30-g3e53a0bf), `ecppack`, `ecppll`,
`openFPGALoader` (v1.1.1).

**Real place-and-route test:** re-synthesized via oss-cad-suite's own
bundled `yosys` (a different build from the earlier homebrew one used
for the Step 0b LUT count) and fed the result to `nextpnr-ecp5 --85k
--package CABGA381 --freq 100 --timing-allow-fail` — no `--lpf` yet
(`m68030_top`'s raw pin names don't match any board's pin names until
the step-3 glue module exists; this run tests internal fabric placement
only, which is exactly what's needed to sanity-check the Step 0b
answer).

Getting a clean JSON netlist out of yosys took 5 attempts — worth
recording since it'll recur: `synth_lattice`'s own `map_luts` stage
defaults to `abc9 -W 300` (timing-driven retiming with no real clock
constraint given), which ran 39+ minutes of ABC CPU time with zero
progress before being killed; swapping in a plain area-only `abc -lut 4`
pass fixed that, but then broke JSON export on an unused `DPR16X4C`
library cell ("contains processes, not supported by JSON backend") for
4 attempts (`-nolutram` didn't help since the module isn't actually
instantiated, just present as an inert `whitebox` library entry) — the
real fix was running `synth_lattice`'s own `check:` stage (`autoname;
hierarchy -check; stat; check -noinit; blackbox =A:whitebox`) before
`write_json`, which converts library `whitebox` modules into true
blackboxes. Full working recipe:
```
synth_lattice -family ecp5 -top m68030_top -run begin:map_luts
abc -lut 4
techmap -map +/lattice/cells_map_trellis.v
opt_lut_ins -tech lattice
clean; autoname; hierarchy -check; stat; check -noinit; blackbox =A:whitebox
write_json
```

**Real ECP5-native numbers, from nextpnr itself (not estimated)** —
strong independent confirmation of the Step 0b answer:

| | nextpnr's number | Step 0b estimate |
|---|---|---|
| Total LUT4s (pre-pack) | 65,147/83,640 (77%) | 65,043 (77.8%) |
| logic LUTs | 51,959/83,640 (62%) | 51,855-51,959 |
| carry LUTs | 13,188/83,640 (15%) | 13,188 (6,594 CCU2C x2) |
| RAM LUTs | 0/10,455 (0%) | 0 |
| DFFs | 12,978/83,640 (15%) | 12,978 |
| TRELLIS_COMB after packing | 66,839/83,640 (**79%**) | — |
| MULT18X18D | 5/156 | 5 |

Packing (IOs, constants, carries, LUTs, LUT5-7s, FFs — 6,103 FFs paired
with LUTs) completed cleanly with no resource-overflow errors.

### Combinational-loop investigation (2026-09-18) — RESOLVED, root cause found

Ran Yosys's own `scc` pass directly on the coarse, pre-technology-mapped
RTL (`proc; opt_clean; scc -nofeedback`, before any LUT mapping) —
found exactly 1 SCC in the whole design, confined entirely to `eu_seq`/
`cores/mh030/rtl/eu_seq_execute.svh`. nextpnr's 65 reported loops (found
during the P&R attempt before `--ignore-loops` was added) are the same
one real cycle, fractured into many overlapping gate-level SCCs by LUT
mapping — consistent with one wide multi-term feedback loop, not 65
independent bugs, and **not** the synthesis-shortcut artifact first
suspected.

**The exact cycle** (all in `cores/mh030/rtl/eu_seq_execute.svh`):

```
ex_mem_stall (line 995, via the BKPT-substitution term at line 1030-1032)
  -> !ex_redirect_pending
ex_redirect_pending (line 964-966) = branch_taken || (ex_valid && jsr/bsr/rts/rtr/rte)
  -> branch_taken
branch_taken (line 5272) = dec_branch_taken | ex_dbcc_taken | ...
  -> dec_branch_taken
dec_branch_taken (line 5198) = dec_valid && !stall && dec_is_branch && eval_cc(...)
  -> !stall
stall = stall_base || int_defer; stall_base (line 1810) = ex_mem_stall || ...
  -> back to ex_mem_stall
```

**Why it's real but (almost certainly) semantically dead, not a bug:**
the one term that closes the loop is `ex_mem_stall`'s own BKPT-
substitution guard (`eu_seq_execute.svh:1030-1032`, itself already
carefully commented — a documented fix for a stale-fall-through-word
race with JSR/BSR/RTS/RTR/RTE redirects): `dec_valid && dec_is_bkpt &&
... && !ex_redirect_pending`. This only matters when `dec_is_bkpt` is
true. `dec_branch_taken` (the term that actually depends on `stall`,
closing the cycle) only matters when `dec_is_branch` is true. BKPT
(`0100100001001xxx`) and Bcc (`0110xxxxxxxxxxxx`) are disjoint opcode
encodings — a given decode slot can never be both simultaneously, so
for any real reachable state, one side of the cycle is always
structurally forced to a constant, and the "loop" never actually
propagates a live value around itself. This is fully consistent with
MH030's own verification history: hundreds of phases of Icarus/
Verilator simulation (which would very likely have hung, warned, or
shown X-propagation on a truly *live* oscillating loop) and the full
124-suite Tom Harte sweep have never shown any sign of trouble here.

**Why no RTL change was made:** the standard, lowest-risk industry fix
for a provably-dead structural loop is an SDC `set_false_path`
constraint (tool-level, zero RTL risk) — checked, and **nextpnr's SDC
reader currently parses `set_false_path` but explicitly no-ops it**
("does not do anything (yet)"), confirmed via nextpnr's own
[`sdc.cc`](https://github.com/YosysHQ/nextpnr/blob/main/common/kernel/sdc.cc)
and a still-open
[timing-analysis-improvements meta-issue](https://github.com/YosysHQ/nextpnr/issues/470)
— so that path isn't usable with this toolchain today. Restructuring the
RTL itself (e.g. registering one term in the cycle) would be a genuine
cycle-timing change to the 68030 model in MH030, and `ex_mem_stall` is
exactly the signal MH030's own project memory
(`feedback_shared_stall_signal_blast_radius.md`) already flags as
high-blast-radius to touch casually — not something to do as a side
effect of an FPGA bring-up task in a different repo, without explicit
sign-off from MH030's own maintainer.

**Practical unblock found instead:** `nextpnr-ecp5 --help` has a direct,
purpose-built flag for exactly this situation: **`--ignore-loops`**
("ignore combinational loops in timing"). Since the loop is confirmed
structurally-real-but-semantically-dead, this is the right tool-level
answer — skips the hard-stop without touching MH030's RTL or trying to
convince a tool feature that doesn't work yet.

### Full place-and-route result (2026-09-18) — THIRD independent confirmation of "fits"

Re-ran `nextpnr-ecp5 --85k --package CABGA381 --freq 100
--timing-allow-fail --ignore-loops` to completion. **"Program finished
normally." 0 errors, 11 warnings.** `top_ecp5.config` written (28 MB, a
complete real bitstream-level configuration — `ecppack` could turn this
into an actual `.bit` file for `openFPGALoader` if there were a real
board-pin-mapped top level to load, which is exactly what Step 3 in
this repo is building).

- **Placement:** completed (analytic placer converged over ~800K+
  iterations).
- **Routing:** 238,677 arcs routed, 0 failures.
- **This is the third independent confirmation the design fits and is
  physically realizable on ULX3S-85F** — Step 0b's LUT-counting estimate,
  then nextpnr's own post-pack utilization report, and now a complete,
  successful, real place-and-route with no resource or routing failures.

**Timing result needs a real caveat — do not treat this as the design's
actual achievable speed:**

```
Max frequency for clock 'clk_4x': 1.61 MHz (FAIL at 100.00 MHz)
```

This is **not representative** of what the design can actually run at.
It's the direct, expected consequence of the synthesis shortcut taken
earlier in Step 1 to get past the JSON-export and combinational-loop
blockers quickly: the LUT mapping came from a plain, non-timing-driven
`abc -lut 4` pass (not the timing-driven `abc9` stage `synth_lattice`
normally uses), so nothing in the flow — LUT packing, retiming, or the
placer's own cost function — ever had real critical-path information to
optimize against. The critical path nextpnr reported (e.g. `Info: 2.50
ns logic, 20.00 ns routing`) shows placement spreading a timing-critical
net across the whole die with no guidance to keep it compact, exactly
what an unguided/non-timing-driven flow produces. **The honest
takeaway: structurally sound (fits, places, routes) with a real,
independently-confirmed clock speed question still genuinely open.**

**Getting a real Fmax number is separate future work:** either (a)
retry `abc9`'s timing-driven pass with an explicit, realistic period
constraint (a proper `create_clock`/SDC rather than none, which is
likely why it ran unbounded for 39+ minutes last time — no target to
converge toward), or (b) do one proper, complete, timing-driven
synthesis + P&R run against the real Step 3 top-level module + `.lpf`
once both exist, instead of the bare core.

## Board selection history

The rest of this section is the investigation that led to the ULX3S-85F
decision above — kept in full since it explains *why*, and rules out
several boards that will otherwise keep coming up.

### Step 0 result (2026-09-17)

**Method:** Gowin EDA (`gw_sh`) is not installed and the proprietary
toolchain is explicitly out of scope per the user — used the open stack
instead. `sv2v` (installed via `brew install sv2v`) flattened the full
30-file `m68030_top` RTL hierarchy (the same file set MH030's own
`Makefile`'s `TOP_SRCS` uses for its top-level cosim testbench —
unpacked-array ports, `always_comb`/`always_ff`, etc.) into plain
Verilog-2005, since Yosys's built-in frontend can't parse SV
unpacked-array ports directly. Yosys `synth_gowin -top m68030_top`
(targets the real GW1N/GW2A LUT4 architecture, ABC9 tech-mapping) then
produced a real resource count — no vendor place & route needed to
answer the fit question. ~15 min run, dominated by ABC9 mapping a
280,291-AND-gate flattened netlist.

**Raw cell counts** (`m68030_top`, flat):

| Cell type | Count |
|---|---|
| LUT1 | 8,756 |
| LUT2 | 6,563 |
| LUT3 | 11,058 |
| LUT4 | 27,930 |
| MUX2_LUT5 (2x LUT4-equiv) | 11,406 |
| MUX2_LUT6 (4x LUT4-equiv) | 2,508 |
| MUX2_LUT7 (8x LUT4-equiv) | 1,115 |
| MUX2_LUT8 (16x LUT4-equiv) | 431 |
| DFF/DFFE/DFFC/DFFCE/DFFP/DFFPE/DFFRE/DFFSE (total) | 12,986 |
| MULT18X18 / MULT36X36 | 1 / 1 |

**Verdict against the GW2AR-18C budget (20,736 LUT4, 15,552 FF, 828 Kbit
BSRAM, 48 multipliers):**

- Direct LUT1-4 cells alone: 54,307 -> **2.6x the entire chip's LUT4
  budget**, before even counting the wide-input MUX2_LUTx constructs
  (which each cost 2/4/8/16 real LUT4s apiece to build 5/6/7/8-input
  functions) -> ~103,000 LUT4-equivalent total, roughly **5x over
  budget**.
- Flip-flops fit comfortably (12,986 vs 15,552, ~0.84x) — LUTs are the
  binding constraint, not registers.
- The 2 DSP multiplier primitives are nowhere near the 48 available —
  not a constraint.

**This is decisive regardless of exact wide-mux accounting** — the direct
LUT count alone already blows the budget by more than 2x. `m68030_top` as
currently built (full MMU + TLB, I+D caches, the complete EU functional
unit set, the 8-format exception controller, all memory-indirect EA
decode) will not fit on a single Tang Nano 20K, on any open or proprietary
Gowin toolchain — this isn't a place-and-route/timing problem, it's a
raw-cell-count problem this stage was specifically chosen to catch before
any glue-logic work was invested.

**Implication:** step 0 was explicitly scoped to catch this before any
Mackerel-030F glue-logic work. This triggered the board search below.

### Step 0b result (2026-09-18) — ULX3S-85F, the real target architecture

**Method:** the Gowin-family check above was always a proxy (Gowin and
ECP5 are both native 4-input-LUT architectures, but pack differently).
Once ULX3S-85F was chosen, re-ran against the real target via Yosys's
`synth_ecp5`/`synth_lattice -family ecp5`, reusing the same `sv2v`-
flattened netlist.

**First attempt got stuck, not decisive:** `synth_ecp5`'s default
`map_luts` stage runs `abc9 -W 300` — timing-driven retiming against an
assumed wire delay, with no real clock constraint (`.sdc`) supplied. On
this design's ~280K-gate flattened netlist it ran for 39+ minutes of ABC
CPU time with zero incremental progress in the log (still actively
computing, not hung, just doing far more expensive work than a resource
count needs) before being killed. Re-ran with the timing-driven stage
swapped for a plain, area-only `abc -lut 4` pass — finished in
**170 seconds**, a ~14x speedup, sufficient for a resource-fit answer
even though it skips real timing closure (irrelevant for this question).

**Raw cell counts** (`m68030_top`, ECP5-native primitives):

| Cell type | Count |
|---|---|
| LUT4 | 51,855 |
| CCU2C (carry-chain macro, 2 LUT4 slots each) | 6,594 |
| TRELLIS_FF (registers) | 12,978 |
| MULT18X18D | 5 |
| EBR/DP16KD (block RAM) | 0 |

**Verdict against the LFE5UM5G-85F's real budget** (83.6K LUT4, ~3744
Kbit EBR / ~216 x 18Kbit blocks, up to 156 MULT18X18 DSP slices —
confirmed via Lattice's own FPGA-DS-02012 family datasheet):

- Total LUT4-equivalent demand: 51,855 + 6,594x2 (each CCU2C occupies
  both LUT4s of a slice in carry mode) = **65,043** vs. **83,640**
  budget -> **77.8% utilization, ~22% headroom**. **Fits — and not just
  barely**, unlike the Tang Nano 20K's 5x overage.
- Registers (12,978) and DSP multipliers (5) are trivially within
  budget, exactly as in the Gowin-proxy check — consistent with that
  earlier pass's own ~12,986 register count, confirming the two
  independent methodologies agree.
- **EBR usage is 0** — every array structure in the design (register
  file, TLB, I/D cache tag/data arrays) is being built from distributed
  LUT/FF fabric rather than the chip's dedicated 3.7 Mbit block-RAM
  resource. This is already reflected correctly in the "fits" verdict
  above (the LUT/FF counts already include whatever those arrays cost
  as distributed logic), but it's a real, free optimization opportunity
  for later: explicit block-RAM inference for the cache/TLB arrays would
  free up LUT4s currently doing that job, widening the margin further.
  Not investigated further — noted for the memory-map/SDRAM work in
  step 6, or for after first bring-up if margin gets tight once real
  place-and-route (not just this LUT-counting proxy) is run.

**This resolves step 0 in full: `m68030_top`, entirely as currently
built (full MMU/TLB, both caches, the complete EU, all memory-indirect
EA decode, the 8-format exception controller — no trimming), fits on
ULX3S-85F with real margin.** No design trimming was needed.

### Larger-FPGA survey (2026-09-17, why not a bigger Gowin/Tang board)

Researched what's actually available with enough LUTs, and — critically —
whether the open toolchain (no Gowin EDA) actually supports it today.

| Part / board | LUT4-equiv | Open-toolchain status |
|---|---|---|
| Gowin GW5A-25 / Tang Primer 25K | ~25K | **Not supported by Apicula** (GW5A family; [issue #204](https://github.com/YosysHQ/apicula/issues/204), open since Oct 2023, stalled) |
| Gowin GW5AT-60 / Tang Mega 60K, Tang Console 60K (~$69) | 60K | Same GW5A gap. An [NLnet-funded Apicula project](https://nlnet.nl/project/Apicula-GW5A/) to add GW5A support started June 2026 — no completion date, not usable today |
| Gowin GW5AST-138 / Tang Mega/Console 138K | 138K | Same gap; also needs Gowin's **paid** EDA tier even on the proprietary path |
| **Lattice ECP5 (LFE5UM5G-85F) / ULX3S** | **~85K** (native 4-input LUT — directly comparable, no conversion) | **Ready today.** Project Trellis + nextpnr-ecp5 fully supports all ECP5 parts — the most mature large fully-open FPGA flow that exists |
| Xilinx Artix-7 200T-class (Nexys Video, Arty, ~$200-500) | ~200K+ (LUT6, ~1.6-2x a LUT4 each) | Usable via openXC7 (Project X-Ray + nextpnr-xilinx), functional and active, but newer/less proven than Trellis |

**Bottom line:** every bigger *Gowin* board (the natural "stay in the Tang
family" choice) is currently a dead end for the open toolchain — they're
all GW5A-class, and Apicula support for that family just started and has
no ETA. Staying open-toolchain and wanting real headroom over
`m68030_top`'s ~54K-103K LUT4-equivalent footprint means leaving the Tang
Nano board family entirely, most plausibly for a Lattice ECP5 board
(ULX3S) — a different vendor and a different physical board than
"Tang Nano 20K." Xilinx/openXC7 has much more headroom if needed but a
less mature toolchain.

### ECP5-85F-class dev board survey (2026-09-17)

Surveyed the ECP5-85F-class landscape (other boards with this same
chip, besides ULX3S):

| Board | ECP5 part | Peripherals | Price | Availability |
|---|---|---|---|---|
| **ULX3S-85F** | LFE5UM5G-85F | 32MB SDRAM, USB, microSD, ESP32 Wi-Fi/BT co-processor, GPIO | $155 | In production (Crowd Supply) |
| ECPIX-5 (LambdaConcept) | LFE5UM5G-85F | 512MB DDR3L, Gigabit Ethernet, microSD (UHS-II), HDMI, SATA, USB-C, 8 PMODs | ~$165 | **Currently out of stock**, notify-me only |
| Lattice's own ECP5-5G-85F Eval Board | LFE5UM5G-85F | Bare: DIP switches/LEDs, SPI flash, Arduino/RPi/Pmod headers — **no SDRAM/Ethernet/SD onboard** | $158.75 | In stock (DigiKey) |
| OrangeCrab-85 | ECP5-85F | Feather-format USB dongle, small PSRAM only, no SDRAM/Ethernet/SD | — | **Discontinued** (existing stock only) |
| Colorlight i9 module | LFE5U-45F (44K LUT, undersized) | 8MB SDRAM, dual Ethernet PHYs | $50-70 | Available, but too small for this design as-is |

**Verdict: ULX3S-85F remains the pick** — cheapest, actually in stock,
and has the right peripheral set (SDRAM + UART/USB + microSD) for a
Mackerel-F-shaped SoC. ECPIX-5 has the best peripherals of the bunch
(real DDR3, Gigabit Ethernet — closer to matching Mackerel-F's own
W5500 Ethernet ambition) but isn't buyable right now.

### DE10-Nano / MiSTer FPGA (Cyclone V) — checked on user request (2026-09-17)

Terasic DE10-Nano (the board MiSTer FPGA is built on): Intel/Altera
Cyclone V SE `5CSXFC6D6F31C6`, dual-core ARM Cortex-A9 HPS + FPGA fabric.

- **Capacity:** 41,509 ALMs -> Altera's own LE conversion gives
  **~110,000 LE**, i.e. **~110K LUT4-equivalent** — comfortably above
  the 54K-103K target, above ECP5's 85K.
- **Price (2026):** $225 direct from Terasic ($190 academic); ~$370-430
  on the secondary market.
- **Open toolchain status: not there yet.** `nextpnr-mistral` (the
  Cyclone V backend) is explicitly labeled **"experimental"** in
  upstream nextpnr's own README, unlike Gowin/ECP5's stable status.
  Actively developed but no stability guarantee yet.
- **MiSTer-specific confirmation:** the MiSTer community itself still
  builds cores with Quartus Lite 17.0.2 (proprietary), not
  `nextpnr-mistral`.
- **Quartus specifics:** free (Lite edition, no license file, Cyclone V
  still supported in current 24.1/25.1 releases), but **Windows/Linux
  only — no native macOS build, ever**. Only path on a Mac: a
  Windows/Linux VM.

**Verdict:** DE10-Nano has plenty of raw capacity, but going with it
means either Quartus (the proprietary toolchain explicitly ruled out)
or an explicitly experimental open backend — a step down in toolchain
maturity from ECP5/Trellis despite the bigger chip, plus a VM
requirement on macOS specifically.

**Pricing comparison + general-purpose usability:**

| Item | Price |
|---|---|
| Bare DE10-Nano (Terasic direct) | $225 ($190 academic) |
| Full MiSTer kit (board + SDRAM/IO boards + hub + RTC + PSU + case + SD) | commonly $350-550+ |
| **ULX3S-85F** | **$155** — in production |

ULX3S-85F is roughly half the price of a bare DE10-Nano. A MiSTer board
is a stock, general-purpose Terasic dev board with zero MiSTer-specific
hardware lock-in — fully usable for unrelated custom projects, and the
bare board (1GB HPS-side DDR3 + on-chip FPGA memory) doesn't need
MiSTer's own SDRAM/IO add-on boards for that.
