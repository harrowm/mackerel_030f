// Behavioral SDR SDRAM model, for simulation only -- functional/protocol
// fidelity (real JEDEC command decode, real CAS-latency timing, real
// bank/row/col addressing, real DQM masking), not full datasheet
// timing-parameter checking (tRP/tRCD/tRC minimums etc. are not
// enforced -- that level of verification needs real hardware or a much
// more elaborate model). Written from scratch against the real JEDEC
// SDR SDRAM command table, matching the exact 13 row / 2 bank / 9
// column / 16-bit configuration confirmed against ulx3s_v20.lpf and
// already used by ../sdram_adapter.v and ../vendor/sdram_16bit.v.
//
// Storage: a dense 16M-entry x 16-bit array (32MB) -- trivial for a
// simulator, and simpler/more trustworthy than a sparse associative
// array (this Icarus build doesn't support associative array syntax
// anyway). Uninitialized entries read as 'x, matching real SDRAM's own
// undefined cold-boot content.
`timescale 1ns/1ps

module sdram_model (
    input  wire        clk,
    input  wire        cke,
    input  wire        csn,
    input  wire        rasn,
    input  wire        casn,
    input  wire        wen,
    input  wire [12:0] a,
    input  wire [1:0]  ba,
    input  wire [1:0]  dqm,
    inout  wire [15:0] dq
);

    // 4 banks x 8192 rows x 512 cols x 16 bits, addressed as a flat
    // {bank[1:0], row[12:0], col[8:0]} = 24-bit word address, matching
    // sdram_16bit.v's own {linAddr,bAddr,colAddr} <= sys_ADDR ordering.
    reg [15:0] mem [0:(1<<24)-1];

    // Command decode.
    //
    // BUG FOUND (simulation model only, confirmed via hierarchical signal
    // tracing against vendor/sdram_16bit.v -- not an RTL/hardware bug):
    // `cmd` here is packed in real JEDEC standard order (CS#,RAS#,CAS#,WE#).
    // The constants below were originally copy-pasted directly from the
    // vendored controller's own 4'b____ dispatch literals -- but that
    // core's own `sdr_n_CS_WE_RAS_CAS` register packs its bits in a
    // DIFFERENT internal order (CS#,WE#,RAS#,CAS#, per its own port name),
    // confirmed correct there by cross-checking every one of its dispatch
    // literals (STATE 2/3/4/5/6/7) bit-for-bit against the real JEDEC
    // truth table. Copying those literals verbatim into a (CS,RAS,CAS,WE)-
    // ordered `cmd` silently transposed the RAS/WE bit positions for every
    // command except MRS (0000, order-independent) -- e.g. a real
    // PRECHARGE ALL (CS,RAS,CAS,WE=0,0,1,0) was misdecoded as this file's
    // own (wrong) CMD_WRITE=4'b0010, producing a bogus periodic "WRITE to
    // inactive bank" error exactly once per refresh interval, since
    // PRECHARGE ALL is refresh's own first phase and correctly clears
    // bank_active. Values below are the real JEDEC (CS#,RAS#,CAS#,WE#)
    // encodings, matching `cmd`'s own bit order directly.
    wire [3:0] cmd = {csn, rasn, casn, wen};
    localparam CMD_MRS    = 4'b0000;
    localparam CMD_REF    = 4'b0001; // (auto) refresh
    localparam CMD_PRE    = 4'b0010; // precharge
    localparam CMD_ACT    = 4'b0011; // activate (bank active)
    localparam CMD_WRITE  = 4'b0100;
    localparam CMD_READ   = 4'b0101;
    localparam CMD_BST    = 4'b0110; // burst terminate
    localparam CMD_NOP    = 4'b0111;
    localparam CMD_DESEL  = 4'b1111; // csn=1, rest don't-care

    reg [3:0]  bank_active;
    reg [12:0] bank_row [0:3];
    reg [2:0]  cas_latency = 3'd3; // real reset default is undefined; a real
                                   // MRS always precedes any read/write in
                                   // normal operation, matching this
                                   // controller's own init sequence.

    // Burst engine (read or write in progress).
    reg        burst_active;
    reg        burst_is_write;
    reg [1:0]  burst_bank;
    reg [8:0]  burst_col;

    // Read data pipeline: CAS latency is modeled as a shift register of
    // {valid, data} entries, matching real SDR SDRAM's fixed-latency
    // (not variable) read timing.
    reg        rd_pipe_valid [0:7];
    reg [15:0] rd_pipe_data  [0:7];
    reg [1:0]  rd_pipe_dqm   [0:7];
    integer    p;

    reg [15:0] dq_out;
    reg        dq_oe;
    assign dq = dq_oe ? dq_out : 16'hzzzz;

    function [23:0] flat_addr(input [1:0] bnk, input [12:0] row, input [8:0] col);
        flat_addr = {bnk, row, col};
    endfunction

    always @(posedge clk) begin
        if (!cke) begin
            // CKE low: device holds state, ignores commands (matches real
            // SDRAM clock-enable/self-refresh gating at a basic level).
        end else begin
            // Advance the read pipeline every cycle.
            dq_oe <= rd_pipe_valid[0];
            dq_out[15:8] <= rd_pipe_dqm[0][1] ? 8'hxx : rd_pipe_data[0][15:8];
            dq_out[7:0]  <= rd_pipe_dqm[0][0] ? 8'hxx : rd_pipe_data[0][7:0];
            for (p = 0; p < 7; p = p + 1) begin
                rd_pipe_valid[p] <= rd_pipe_valid[p+1];
                rd_pipe_data[p]  <= rd_pipe_data[p+1];
                rd_pipe_dqm[p]   <= rd_pipe_dqm[p+1];
            end
            rd_pipe_valid[7] <= 1'b0;

            // csn=1 (deselect) always means NOP regardless of ras/cas/we --
            // real hardware ignores them in that case, and the vendored
            // controller (vendor/sdram_16bit.v:111) deliberately drives
            // them as literal don't-cares (`4'b1xxx`) during NOP for
            // exactly this reason, which appear as X in simulation and
            // would otherwise fail to match any 4-bit case pattern.
            if (csn) begin
                // NOP / deselect: no state change.
            end else case (cmd)
                CMD_MRS: begin
                    cas_latency  <= a[6:4];
                    burst_active <= 1'b0; // MRS implicitly ends any burst
                end

                CMD_ACT: begin
                    bank_active[ba] <= 1'b1;
                    bank_row[ba]    <= a;
                end

                CMD_PRE: begin
                    if (a[10]) bank_active <= 4'b0000; // precharge all
                    else       bank_active[ba] <= 1'b0;
                    if (burst_active && burst_bank == ba) burst_active <= 1'b0;
                end

                CMD_READ: begin
                    if (!bank_active[ba]) begin
                        $display("[sdram_model] ERROR: READ to inactive bank %0d at %0t", ba, $time);
                    end
                    burst_active   <= 1'b1;
                    burst_is_write <= 1'b0;
                    burst_bank     <= ba;
                    burst_col      <= a[8:0];
                    // Schedule the first word into the CAS-latency pipeline.
                    rd_pipe_valid[cas_latency - 1] <= 1'b1;
                    rd_pipe_data[cas_latency - 1]  <= mem[flat_addr(ba, bank_row[ba], a[8:0])];
                    rd_pipe_dqm[cas_latency - 1]   <= dqm;
                    if (a[10]) burst_active <= 1'b0; // auto-precharge: single-beat only here
                end

                CMD_WRITE: begin
                    if (!bank_active[ba]) begin
                        $display("[sdram_model] ERROR: WRITE to inactive bank %0d at %0t", ba, $time);
                    end
                    if (!dqm[1]) mem[flat_addr(ba, bank_row[ba], a[8:0])][15:8] <= dq[15:8];
                    if (!dqm[0]) mem[flat_addr(ba, bank_row[ba], a[8:0])][7:0]  <= dq[7:0];
                    burst_active   <= !a[10]; // auto-precharge: single-beat only
                    burst_is_write <= 1'b1;
                    burst_bank     <= ba;
                    burst_col      <= a[8:0] + 9'd1;
                    if (a[10]) bank_active[ba] <= 1'b0;
                end

                CMD_BST: begin
                    burst_active <= 1'b0;
                end

                CMD_REF, CMD_NOP: begin
                    // No state change needed for a functional (not
                    // retention-timing) model.
                end

                default: begin
                    $display("[sdram_model] WARNING: unrecognized command %b at %0t", cmd, $time);
                end
            endcase

            // Continuing burst (full-page mode: this controller's own MRS
            // always selects full-page burst -- see vendor/sdram_16bit.v's
            // own state 3 comment) advances the column each cycle while no
            // new command interrupts it. NOP here means either a real NOP
            // (csn=0, ras/cas/we=111) or deselect (csn=1, others don't-care)
            // -- both are functionally identical "leave the burst alone."
            if (burst_active && (csn || cmd == CMD_NOP)) begin
                if (burst_is_write) begin
                    if (!dqm[1]) mem[flat_addr(burst_bank, bank_row[burst_bank], burst_col)][15:8] <= dq[15:8];
                    if (!dqm[0]) mem[flat_addr(burst_bank, bank_row[burst_bank], burst_col)][7:0]  <= dq[7:0];
                    burst_col <= burst_col + 9'd1;
                end else begin
                    rd_pipe_valid[cas_latency - 1] <= 1'b1;
                    rd_pipe_data[cas_latency - 1]  <= mem[flat_addr(burst_bank, bank_row[burst_bank], burst_col)];
                    rd_pipe_dqm[cas_latency - 1]   <= dqm;
                    burst_col <= burst_col + 9'd1;
                end
            end
        end
    end

endmodule
