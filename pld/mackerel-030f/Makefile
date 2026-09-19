# Mackerel-030F build -- open toolchain only (Yosys + Trellis + nextpnr-ecp5
# + openFPGALoader via oss-cad-suite), never Lattice's proprietary Diamond.
# See ../../plan.md for the full toolchain investigation.

OSS_CAD  = $(HOME)/oss-cad-suite/bin
YOSYS    = $(OSS_CAD)/yosys
NEXTPNR  = $(OSS_CAD)/nextpnr-ecp5
ECPPACK  = $(OSS_CAD)/ecppack
LOADER   = $(OSS_CAD)/openFPGALoader
SV2V     = sv2v

MH030    = ../../cores/mh030/rtl
UART     = ../../cores/uart16550/rtl/verilog
SPI      = ../../cores/tiny_spi/rtl/verilog
TOP      = mackerel_030f
LPF      = ulx3s_v20.lpf

# MH030's own Makefile TOP_SRCS list (see MH030's own Makefile) -- kept in
# sync by hand for now; MH030's SV (unpacked-array ports, etc.) needs sv2v
# flattening before Yosys can read it at all.
MH030_SRCS = \
    $(MH030)/opcode_fields.sv \
    $(MH030)/eu_regfile.sv \
    $(MH030)/eu_alu.sv \
    $(MH030)/eu_shifter.sv \
    $(MH030)/eu_mul_div.sv \
    $(MH030)/eu_bcd.sv \
    $(MH030)/eu_bitops.sv \
    $(MH030)/eu_agu.sv \
    $(MH030)/eu_bitfield.sv \
    $(MH030)/eu_seq.sv \
    $(MH030)/m68030_eu.sv \
    $(MH030)/biu_cycle_gen.sv \
    $(MH030)/biu_arbiter.sv \
    $(MH030)/biu_sizing_fsm.sv \
    $(MH030)/biu_multiop_fsm.sv \
    $(MH030)/biu_cache_if.sv \
    $(MH030)/biu_icache_if.sv \
    $(MH030)/biu_mmu_if.sv \
    $(MH030)/biu_mmu_arb.sv \
    $(MH030)/biu_exc_capture.sv \
    $(MH030)/biu_byte_lane_ctrl.sv \
    $(MH030)/biu_config.sv \
    $(MH030)/biu_pin_driver.sv \
    $(MH030)/biu_error_handler.sv \
    $(MH030)/biu_burst_ctrl.sv \
    $(MH030)/m68030_biu.sv \
    $(MH030)/m68030_ifu.sv \
    $(MH030)/m68030_seq.sv \
    $(MH030)/m68030_exc.sv \
    $(MH030)/m68030_mmu.sv \
    $(MH030)/m68030_top.sv

GLUE_SRCS = mackerel_030f.v clk_pll.v uart.v spi.v sdram_adapter.v vendor/sdram_16bit.v

# OpenCores uart16550/tiny_spi -- the same cores Mackerel-F itself uses.
# Plain Verilog-2001, no sv2v flattening needed (unlike MH030's SV).
UART_SRCS = $(wildcard $(UART)/*.v)
SPI_SRCS  = $(SPI)/tiny_spi.v

BIT = impl/$(TOP).bit

flat.v: $(MH030_SRCS)
	$(SV2V) -I $(MH030) $(MH030_SRCS) > flat.v

$(BIT): flat.v $(GLUE_SRCS) $(UART_SRCS) $(SPI_SRCS) $(LPF) rom.hex
	mkdir -p impl
	$(YOSYS) -p "read_verilog flat.v; read_verilog $(GLUE_SRCS) $(UART_SRCS) $(SPI_SRCS); \
	    synth_lattice -family ecp5 -top $(TOP) -run begin:map_luts; \
	    abc -lut 4; \
	    techmap -map +/lattice/cells_map_trellis.v; \
	    opt_lut_ins -tech lattice; \
	    clean; autoname; hierarchy -check; check -noinit; \
	    blackbox =A:whitebox; \
	    write_json impl/$(TOP).json"
	$(NEXTPNR) --85k --package CABGA381 --json impl/$(TOP).json \
	    --lpf $(LPF) --textcfg impl/$(TOP).config \
	    --ignore-loops
	$(ECPPACK) impl/$(TOP).config $(BIT)

# Load into SRAM (volatile, fast to iterate; lost on power cycle)
prog: $(BIT)
	$(LOADER) --board=ulx3s $(BIT)

# Write to SPI flash (persists across a power cycle)
flash: $(BIT)
	$(LOADER) --board=ulx3s -f $(BIT)

clean:
	rm -f flat.v
	rm -rf impl

.PHONY: prog flash clean
