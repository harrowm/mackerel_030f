// Behavioral simulation stub for the Lattice ECP5 ODDRX1F DDR output
// register primitive -- swapped in for simulation by compiling this file
// alongside sdram_adapter.v's own real ODDRX1F instantiation. oss-cad-
// suite ships ODDRX1F as a blackbox only (confirmed: no behavioral body
// in ~/oss-cad-suite/share/yosys/ecp5/cells_sim.v), matching the same
// clk_pll.v/clk_pll_sim.v pattern already established in this directory.
//
// Real semantics: D0 is launched on SCLK's rising edge, D1 on its
// falling edge (standard DDR output shape) -- sdram_adapter.v ties
// D0=1/D1=0 to forward SCLK itself at unchanged frequency/phase through
// a dedicated I/O resource instead of a bare wire tied straight to the
// internal clock net (project_nextpnr_sdram_clk_hold_violation.md).
`timescale 1ns/1ps

module ODDRX1F (
    input  wire SCLK,
    input  wire RST,
    input  wire D0,
    input  wire D1,
    output reg  Q
);

    always @(posedge SCLK or posedge RST)
        if (RST) Q <= 1'b0;
        else     Q <= D0;

    always @(negedge SCLK or posedge RST)
        if (RST) Q <= 1'b0;
        else     Q <= D1;

endmodule
