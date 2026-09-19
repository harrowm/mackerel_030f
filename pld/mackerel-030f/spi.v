// Mackerel-030F SPI wrapper -- adapted from Mackerel-F's own
// pld/mackerel-f/spi.v essentially unchanged, same shape as uart.v: the
// underlying OpenCores tiny_spi core doesn't care which CPU is on the
// other side of this simple register interface.
//
// Registers (reg_addr, byte stride): 0 RXDATA  1 TXDATA  2 STATUS
// {-,TXR,TXE}  3 CONTROL  4 BAUD. CS is NOT part of tiny_spi (it has no
// slave-select output) -- driven separately via mackerel_030f.v's own
// sd_cs GPIO register, matching Mackerel-F's own convention exactly.

module spi (
    input clk,
    input rst_n,

    input cs_n,
    input [2:0] reg_addr,
    input rwn,
    input ds_n,
    input [7:0] data_in,
    output [7:0] data_out,
    output dtack_n,
    output irq,

    output mosi,
    output sck,
    input miso
);

    localparam IDLE = 2'd0;
    localparam REQ  = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state = IDLE;
    reg [7:0] rd_data = 8'h00;

    wire wb_ack;
    wire [31:0] wb_dat_o;

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
                        rd_data <= wb_dat_o[7:0];
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

    tiny_spi #(
        .BAUD_WIDTH(8),
        .SPI_MODE(0)
    ) core (
        .clk_i(clk),
        .rst_i(~rst_n),

        .stb_i(stb),
        .cyc_i(stb),
        .we_i(~rwn),
        .adr_i(reg_addr),
        .dat_i({24'b0, data_in}),
        .dat_o(wb_dat_o),
        .ack_o(wb_ack),
        .int_o(irq),

        .MOSI(mosi),
        .SCLK(sck),
        .MISO(miso)
    );

endmodule
