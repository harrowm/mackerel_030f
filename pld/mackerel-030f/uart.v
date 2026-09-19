// Mackerel-030F UART wrapper -- adapted from Mackerel-F's own
// pld/mackerel-f/uart.v (mackerel-68k repo) essentially unchanged: the
// register interface (cs_n/reg_addr/rwn/ds_n/data_in/data_out/dtack_n/
// irq/rx/tx) it presents is already exactly the shape needed here, since
// the underlying OpenCores 16550 core (uart_top) doesn't care whether the
// CPU wrapped around it is a 68000 or a 68030 -- only mackerel_030f.v's
// own DSACK-vs-DTACK adaptation (see its own comments) differs.
`define DATA_BUS_WIDTH_8

module uart (
    input clk,
    input rst_n,

    input cs_n,
    input [2:0] reg_addr,   // register select (0-7)
    input rwn,
    input ds_n,
    input [7:0] data_in,
    output [7:0] data_out,
    output dtack_n,
    output irq,

    input rx,
    output tx
);

    localparam IDLE = 2'd0;
    localparam REQ  = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state = IDLE;
    reg [7:0] rd_data = 8'h00;

    wire wb_ack;
    wire [7:0] wb_dat_o;

    wire start = ~cs_n & ~ds_n;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            rd_data <= 8'h00;
        end else begin
            case (state)
                IDLE:
                    if (start) state <= REQ;
                REQ:
                    if (wb_ack) begin
                        rd_data <= wb_dat_o;
                        state <= DONE;
                    end
                DONE:
                    if (cs_n) state <= IDLE;
                default:
                    state <= IDLE;
            endcase
        end
    end

    wire stb = (state == REQ);
    assign dtack_n = ~(state == DONE);
    assign data_out = rd_data;

    uart_top core (
        .wb_clk_i(clk),
        .wb_rst_i(~rst_n),

        .wb_adr_i(reg_addr),
        .wb_dat_i(data_in),
        .wb_dat_o(wb_dat_o),
        .wb_we_i(~rwn),
        .wb_stb_i(stb),
        .wb_cyc_i(stb),
        .wb_sel_i(4'b0000),
        .wb_ack_o(wb_ack),

        .int_o(irq),

        .stx_pad_o(tx),
        .srx_pad_i(rx),

        .cts_pad_i(1'b1),
        .dsr_pad_i(1'b1),
        .ri_pad_i(1'b1),
        .dcd_pad_i(1'b1),
        .rts_pad_o(),
        .dtr_pad_o()
    );

endmodule
