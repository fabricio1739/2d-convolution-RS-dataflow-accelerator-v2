`timescale 1ns / 1ps

module filter_spad
#(
    parameter DWIDTH = 0,
    parameter DEPTH  = 0
)
(
    input wire clk, rst, wr_en, rd_en,
    input wire [$clog2(DEPTH+1)-1:0] window_size,
    input wire [DWIDTH-1:0] data_in,
    output reg [DWIDTH-1:0] data_out
);

    localparam AWIDTH = $clog2(DEPTH);

    reg [DWIDTH-1:0] mem [0:DEPTH-1];
    reg [AWIDTH-1:0] wptr;
    reg [AWIDTH-1:0] rptr;

    always @(posedge clk)
    begin
        if (rst)
        begin
            rptr <= 0;
            wptr <= 0;
            data_out <= 0;
        end
        else
        begin
            if (rd_en)
            begin
                data_out <= mem[rptr];
                rptr <= (rptr == window_size-1) ? 0 : rptr + 1;
            end
            if (wr_en)
            begin
                mem[wptr] <= data_in;
                wptr <= (wptr == window_size-1) ? 0 : wptr + 1;
            end
        end
    end

endmodule