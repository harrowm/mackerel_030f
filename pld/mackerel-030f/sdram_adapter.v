// Mackerel-030F SDRAM adapter -- wraps vendor/sdram_16bit.v (see that
// file's own header for its real origin/license: Next186 SoC PC project,
// Nicolae Dumitrache, EMARD's ULX3S cleanup) with a simple single-word
// (no burst) handshake matching MH030's own real 16-bit-port DSACK
// dynamic-sizing convention -- confirmed directly against MH030's own
// rtl/biu_sizing_fsm.sv (next_siz/needs_more): port=2'b01 (dsack0
// asserted, dsack1 inactive) decodes as a 16-bit port, so every access
// here (byte/word/longword from the CPU's own perspective) is always a
// single plain 16-bit transfer -- MH030's own dynamic bus sizing FSM
// handles iterating multi-beat longword/byte requests on its own; this
// adapter never needs to know or care.
//
// ULX3S-85F's real SDRAM, confirmed directly from ulx3s_v20.lpf's own
// pin list (13 address bits + 2 bank bits + 16-bit data, not assumed
// from a datasheet): standard 4-bank x 8192-row x 512-col x 16-bit SDR
// SDRAM, 32 MB total (matches sdram_16bit.v's own default C_RowBits=13/
// C_ColBits=9/C_BankBits=2 parameters exactly -- no override needed
// there). C_PitchBits set to 0 here (word-granular addressing, no
// burst-pair grouping) to match this adapter's own single-word-at-a-time
// usage -- the vendored core's default C_PitchBits=1 assumes a
// burst-of-2-words host access pattern from its own original SoC, which
// doesn't match a CPU doing individual dynamically-sized bus cycles.
//
// C_RFB (refresh-bit) DOES need overriding from its default: JEDEC
// tREF=64ms/8192 rows requires refreshing at least every ~7.8us; the
// vendored core's own default C_RFB=11 gives a 20.48us interval at our
// 100MHz clk_4x -- 2.6x too infrequent, a real data-loss risk on actual
// hardware, not just a performance tweak. C_RFB=9 (5.12us interval,
// comfortable margin under the 7.8us requirement) fixes this -- verified
// by direct calculation, not assumed from the vendored default.
`default_nettype none

module sdram_adapter (
    input  wire        clk,
    input  wire        rst_n,

    // CPU-facing side: single-word (16-bit) transactions only
    input  wire        req,        // pulse/level: cyc_active && in_sdram
    input  wire [23:0] word_addr,  // ext_a[24:1] -- word address
    input  wire        wr,         // 1 = write, 0 = read
    input  wire [15:0] wdata,
    output reg  [15:0] rdata,
    output reg         done,       // stays asserted until req drops (matches
                                    // the CPU releasing AS/DS at cycle end)

    // REAL BUG FOUND via simulation (confirmed by hierarchical signal
    // tracing): the vendored core's own post-power-on init sequence
    // doesn't just wait for its `counter[15]` threshold -- after that, it
    // still has to converge an internal refresh-loop (`rfsh !=
    // counter[C_RFB]` in vendor/sdram_16bit.v's STATE 4) before it's
    // genuinely ready for a real command. This is a FIXED, deterministic
    // number of cycles (both counters are free-running from the same
    // clk_4x reset-of-time-0, so the relationship never changes no matter
    // how long the SYSTEM reset is separately extended -- confirmed by
    // trying exactly that and observing the identical ~126-cycle stall
    // recur at a shifted absolute time) that, in practice, comes out
    // close to (and in one measured case, exceeding) MH030's own internal
    // BIU bus-cycle watchdog (rtl/biu_error_handler.sv, TIMEOUT_CLKS=128
    // clk_4x cycles) -- a genuine internal Bus Error can fire on the
    // CPU's very first SDRAM access before the controller has actually
    // converged, which (since boot.s has no real exception vector table)
    // corrupts the whole program. Real fix: expose the vendored core's
    // own genuine readiness indicator -- `sdr_DQM` is actively held at
    // 2'b11 throughout power-up/refresh-convergence and cleared to 2'b00
    // (STATE 4's own "else" branch) the instant it's actually ready,
    // matching real SDR SDRAM chip behavior -- so the top level can gate
    // CPU reset release on genuine SDRAM readiness instead of a fixed
    // guess.
    output wire        ready,

    // SDRAM pins (pass through to top level)
    output wire        sdram_clk,
    output wire        sdram_cke,
    output wire        sdram_csn,
    output wire        sdram_wen,
    output wire        sdram_rasn,
    output wire        sdram_casn,
    output wire [12:0] sdram_a,
    output wire [1:0]  sdram_ba,
    output wire [1:0]  sdram_dqm,
    inout  wire [15:0] sdram_d
);

    localparam ST_IDLE = 3'd0;
    localparam ST_ISSUE = 3'd1;
    localparam ST_BUSY = 3'd2;
    localparam ST_DONE = 3'd3;

    reg [2:0]  state;
    reg [1:0]  cmd_r;
    reg [23:0] addr_r;
    reg [15:0] wdata_r;

    wire [1:0]  sys_cmd_ack;
    wire        sys_rd_data_valid, sys_wr_data_valid;
    wire [15:0] sys_dout;
    wire [3:0]  sdr_n_CS_WE_RAS_CAS;
    wire [1:0]  sdr_BA;
    wire [12:0] sdr_ADDR;
    wire [1:0]  sdr_DQM;

    sdram_16bit #(
        .C_PitchBits (0),
        .C_ColBits   (9),
        .C_RowBits   (13),
        .C_BankBits  (2),
        .C_RFB       (9),  // see header comment: overridden for correctness at 100MHz
        // REAL BUG FOUND via simulation: the vendored core's own default
        // C_WR2=8'h80 (128) sizes STATE 7's post-WRITE-command DLY wait
        // for its ORIGINAL SoC's own multi-word BURST-write use case
        // ("01=write WR2 bytes" per the core's own sys_CMD comment) --
        // completely wrong for this adapter's single-16-bit-word,
        // no-burst transfers (confirmed via hierarchical signal tracing:
        // a plain single-word write was taking ~126 extra clk_4x DLY
        // cycles for no functional reason, coming within a hair of --
        // and, combined with other timing, actually exceeding -- MH030's
        // own internal 128-cycle bus-cycle watchdog, corrupting the CPU's
        // program via a spurious internal Bus Error). The READ path
        // already correctly uses the core's OWN short/single-beat
        // constant (C_RD1=8'h10=16, confirmed working via this same
        // adapter's already-passing SDRAM read-back test) -- overriding
        // C_WR2 to match it restores that same fast, single-beat shape
        // for writes instead of a full burst-length wait.
        .C_WR2       (8'h10)
    ) u_sdram (
        .sys_CLK             (clk),
        .sys_CMD              (cmd_r),
        .sys_ADDR             (addr_r),
        .sys_DIN               (wdata_r),
        .sys_DOUT              (sys_dout),
        .sys_rd_data_valid     (sys_rd_data_valid),
        .sys_wr_data_valid     (sys_wr_data_valid),
        .sys_cmd_ack           (sys_cmd_ack),

        .sdr_n_CS_WE_RAS_CAS (sdr_n_CS_WE_RAS_CAS),
        .sdr_BA              (sdr_BA),
        .sdr_ADDR            (sdr_ADDR),
        .sdr_DATA            (sdram_d),
        .sdr_DQM             (sdr_DQM)
    );

    assign sdram_clk  = clk;
    assign sdram_cke  = 1'b1;
    assign sdram_csn  = sdr_n_CS_WE_RAS_CAS[3];
    assign sdram_wen  = sdr_n_CS_WE_RAS_CAS[2];
    assign sdram_rasn = sdr_n_CS_WE_RAS_CAS[1];
    assign sdram_casn = sdr_n_CS_WE_RAS_CAS[0];
    assign sdram_a    = sdr_ADDR;
    assign sdram_ba   = sdr_BA;
    assign sdram_dqm  = sdr_DQM;
    assign ready      = (sdr_DQM == 2'b00);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_IDLE;
            cmd_r   <= 2'b00;
            done    <= 1'b0;
            rdata   <= 16'h0000;
        end else begin
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    if (req) begin
                        addr_r  <= word_addr;
                        wdata_r <= wdata;
                        // sys_CMD: 2'b10 = read (short/RD1 -- fast path,
                        // not the RD2 burst-read variant, which this
                        // single-word adapter never needs), 2'b01 = write.
                        cmd_r   <= wr ? 2'b01 : 2'b10;
                        state   <= ST_ISSUE;
                    end
                end

                ST_ISSUE: begin
                    // Hold the command until the core latches it (sys_cmd_ack
                    // becomes nonzero, matching the uart wrapper's own
                    // wb_ack-style handshake shape), then drop it -- state 0
                    // in sdram_16bit.v only ever samples |sys_CMD once per
                    // idle-to-busy transition, so holding longer is safe,
                    // but dropping promptly avoids any risk of it being
                    // re-sampled on a later idle-return.
                    if (sys_cmd_ack != 2'b00) begin
                        cmd_r <= 2'b00;
                        state <= ST_BUSY;
                    end
                end

                ST_BUSY: begin
                    if (sys_rd_data_valid)
                        rdata <= sys_dout;
                    // sys_cmd_ack returns to 2'b00 (state 6 in
                    // sdram_16bit.v) once the whole transaction -- read or
                    // write -- has fully completed; using it as the one
                    // uniform completion signal for both directions avoids
                    // needing separate read/write completion logic.
                    if (sys_cmd_ack == 2'b00) begin
                        done  <= 1'b1;
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    // Latch done until the CPU releases the bus (req drops
                    // at end of its own cycle) -- mirrors how the ROM/GPIO/
                    // UART paths all key off the CPU's own /DS, not an
                    // internal one-shot pulse.
                    if (!req) begin
                        done  <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
