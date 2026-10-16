`timescale 1ns / 1ps

module fifo
#(
    parameter DWIDTH = 0,
    parameter DEPTH = 0
)
(
    input wire clk, rst, wr_en, rd_en,
    input wire [DWIDTH-1:0] data_in,
    output wire full, empty,
    output reg wrote,
    output reg [DWIDTH-1:0] data_out
);

    localparam AWIDTH = $clog2(DEPTH);
    reg [DWIDTH-1:0] mem [0:DEPTH-1];
    reg [AWIDTH-1:0] wptr;
    reg [AWIDTH-1:0] rptr;

    always @(posedge clk) begin
        if (rst) begin
            rptr <= 0;
            wptr <= 0;
            wrote <= 0;
            data_out <= 0;
        end
        else begin
            if (rd_en && !empty) begin
                data_out <= mem[rptr];
                rptr <= (rptr == DEPTH-1) ? 0 : rptr + 1;
                wrote <= 0;
            end
            if (wr_en && !full) begin
                mem[wptr] <= data_in;
                wptr <= (wptr == DEPTH-1) ? 0 : wptr + 1;
                wrote <= 1;
            end
        end
    end

    assign empty = (rptr == wptr) && !wrote;
    assign full = (rptr == wptr) && wrote;

endmodule