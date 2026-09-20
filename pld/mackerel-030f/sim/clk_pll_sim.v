// Behavioral simulation stub for clk_pll.v -- same module name/port list
// (clkin/clkout0/locked), swapped in for simulation by simply compiling
// this file INSTEAD of the real clk_pll.v (which instantiates the real
// EHXPLLL hardware primitive). oss-cad-suite ships EHXPLLL as a blackbox
// only (confirmed: no behavioral body in
// ~/oss-cad-suite/share/yosys/ecp5/cells_sim.v, unlike DP16KD which does
// have one there) -- this is the standard, expected way every FPGA
// project handles a vendor PLL in simulation: don't model the analog
// lock behavior, just provide a stable clock at the target ratio to the
// digital logic that actually needs verifying.
`timescale 1ns/1ps

module clk_pll (
    input  wire clkin,
    output reg  clkout0 = 1'b0,
    output reg  locked  = 1'b0
);

    // Real ratio is 25MHz -> 100MHz (ecppll -i 25 -o 100, see clk_pll.v's
    // own header) -- 5ns half-period = 100MHz, generated directly rather
    // than derived from clkin's own edges (a real PLL's closed-loop lock
    // behavior isn't what's under test here).
    always #5 clkout0 = ~clkout0;

    initial begin
        locked = 1'b0;
        #200 locked = 1'b1; // arbitrary short settle delay, mirrors a real PLL lock time
    end

endmodule
